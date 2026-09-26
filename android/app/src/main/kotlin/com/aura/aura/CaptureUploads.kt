package com.aura.aura

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AtomicFile
import androidx.work.*
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Durable original copies. No image decoding, and no Flutter engine needed to upload. */
class CaptureUploadStore(val context: Context, val scope: String = "capture_uploads") {
    val root = File(context.noBackupFilesDir, scope).apply { mkdirs() }
    private val preferences = context.getSharedPreferences(scope, Context.MODE_PRIVATE)

    fun configure(url: String, key: String, bucket: String) {
        val parsed = java.net.URI(url)
        require(parsed.scheme == "https" ||
            (BuildConfig.DEBUG && parsed.scheme == "http" && parsed.host in listOf("127.0.0.1", "localhost", "10.0.2.2")))
        require(parsed.userInfo == null && parsed.query == null && parsed.fragment == null)
        require(bucket.matches(Regex("[A-Za-z0-9_-]+")) && key.isNotBlank())
        // A configuration change must never send already queued photos to another host.
        val previous = preferences.getString("url", null)
        require(previous == null || previous == url.trimEnd('/')) { "Upload host changed; existing queue retained" }
        check(preferences.edit().putString("url", url.trimEnd('/')).putString("key", key)
            .putString("bucket", bucket).commit())
    }

    fun config(): Triple<String, String, String> = Triple(
        preferences.getString("url", null) ?: error("Upload server is not configured"),
        preferences.getString("key", null) ?: error("Upload server is not configured"),
        preferences.getString("bucket", "captures")!!)

    fun enqueue(path: String, identity: String): JSONObject = synchronized(lock) {
        val source = File(path)
        require(source.isFile && source.length() > 0) { "Capture file is unavailable" }
        val extension = source.extension.lowercase().takeIf { mimeTypes.containsKey(it) }
            ?: throw IllegalArgumentException("Unsupported capture format")
        val safeIdentity = identity.replace(Regex("[^A-Za-z0-9_-]"), "_").take(120).ifEmpty { "capture" }
        val stage = File(root, "${UUID.randomUUID()}.part")
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            source.inputStream().buffered().use { input ->
                FileOutputStream(stage).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        digest.update(buffer, 0, count)
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                }
            }
            val hash = digest.digest().joinToString("") { "%02x".format(it) }
            val id = "capture_${safeIdentity}_$hash.$extension"
            val existing = read(id)
            if (existing != null && (existing.optString("status") == "uploaded" || File(root, id).exists())) {
                return@synchronized existing
            }
            check(stage.renameTo(File(root, id))) { "Could not retain original capture" }
            val record = newRecord(id)
            write(record)
            record
        } finally { stage.delete() }
    }

    private fun newRecord(id: String) = JSONObject().put("id", id)
        .put("status", "pending").put("createdAt", System.currentTimeMillis())
        .put("attempts", 0).put("bytes", File(root, id).length())
        .put("mime", mimeTypes[id.substringAfterLast('.')] ?: "application/octet-stream")

    fun read(id: String): JSONObject? = synchronized(lock) {
        require(validId(id))
        try { AtomicFile(File(root, "$id.json")).openRead().use {
            JSONObject(it.bufferedReader().readText()).also { row -> require(row.getString("id") == id) }
        } } catch (_: Exception) { null }
    }

    fun write(record: JSONObject) = synchronized(lock) {
        val id = record.getString("id")
        require(validId(id))
        val file = AtomicFile(File(root, "$id.json"))
        val out = file.startWrite()
        try {
            out.write(record.toString().toByteArray())
            file.finishWrite(out)
        } catch (e: Exception) { file.failWrite(out); throw e }
    }

    fun rows(): List<JSONObject> = synchronized(lock) {
        root.listFiles().orEmpty().mapNotNull {
            when {
                it.name.endsWith(".json") -> it.name.removeSuffix(".json")
                it.name.endsWith(".json.bak") -> it.name.removeSuffix(".json.bak")
                else -> null
            }
        }.distinct().mapNotNull { if (validId(it)) read(it) else null }
    }

    fun recover() = synchronized(lock) {
        // Recover a fully copied file if Android stopped us just before metadata was written.
        for (file in root.listFiles().orEmpty()) {
            if (validId(file.name) && read(file.name) == null) write(newRecord(file.name))
            if (file.extension == "part" && System.currentTimeMillis() - file.lastModified() > TimeUnit.DAYS.toMillis(1)) file.delete()
        }
        for (row in rows()) {
            if (row.optString("status") == "uploaded") {
                File(root, row.getString("id")).delete()
                if (System.currentTimeMillis() - row.optLong("completedAt") > TimeUnit.DAYS.toMillis(7)) {
                    AtomicFile(File(root, "${row.getString("id")}.json")).delete()
                }
            }
        }
    }

    fun schedule(id: String, retryNow: Boolean = false) {
        val request = OneTimeWorkRequestBuilder<CaptureUploadWorker>()
            .setInputData(workDataOf("scope" to scope, "id" to id))
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .addTag(scope).build()
        WorkManager.getInstance(context).enqueueUniqueWork("$scope:$id",
            if (retryNow) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, request).result.get()
    }

    fun resume(retryNow: Boolean = false) {
        recover()
        for (row in rows()) {
            val status = row.optString("status")
            if (status != "uploaded" && status != "missing") {
                schedule(row.getString("id"), retryNow && status in listOf("retrying", "blocked"))
            }
        }
    }

    fun snapshot(): Map<String, Any?> {
        val rows = rows()
        val pending = rows.filter { it.optString("status") != "uploaded" }
        return mapOf("pending" to pending.size,
            "uploading" to pending.count { it.optString("status") == "uploading" },
            "uploaded" to rows.count { it.optString("status") == "uploaded" },
            "blocked" to pending.count { it.optString("status") in listOf("blocked", "missing") },
            "bytes" to pending.sumOf { it.optLong("bytes") },
            "message" to pending.firstOrNull { it.has("error") }?.optString("error"))
    }

    companion object {
        private val lock = Any()
        val mimeTypes = mapOf("jpg" to "image/jpeg", "jpeg" to "image/jpeg", "png" to "image/png",
            "webp" to "image/webp", "heic" to "image/heic", "heif" to "image/heif",
            "mp4" to "video/mp4", "mov" to "video/quicktime", "m4v" to "video/mp4")
        fun validId(id: String) = id.startsWith("capture_") && id.matches(Regex("[A-Za-z0-9_.-]+")) &&
            mimeTypes.containsKey(id.substringAfterLast('.'))
        fun validScope(scope: String) = scope == "capture_uploads" ||
            (BuildConfig.DEBUG && scope.startsWith("test_") && scope.matches(Regex("[A-Za-z0-9_]+")))
    }
}

class CaptureUploads(private val context: Context) : MethodChannel.MethodCallHandler {
    // Application lifetime executor: rotating/destroying the Activity must not interrupt a durable copy.
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            try {
                val scope = call.argument<String>("scope") ?: "capture_uploads"
                require(CaptureUploadStore.validScope(scope))
                val store = CaptureUploadStore(context, scope)
                val value: Any? = when (call.method) {
                    "configure" -> { store.configure(call.argument<String>("url")!!,
                        call.argument<String>("key")!!, call.argument<String>("bucket")!!); null }
                    "enqueue" -> {
                        val row = store.enqueue(call.argument<String>("path")!!, call.argument<String>("identity")!!)
                        // Copies remain recoverable if scheduling fails.
                        if (row.optString("status") != "uploaded") store.schedule(row.getString("id"))
                        store.snapshot()
                    }
                    "resume" -> { store.resume(call.argument<Boolean>("retryNow") == true); store.snapshot() }
                    "status" -> store.snapshot()
                    else -> { main.post { result.notImplemented() }; return@execute }
                }
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("upload_queue", e.message, null) }
            }
        }
    }
    companion object {
        private val executor = Executors.newSingleThreadExecutor()
        private val main = Handler(Looper.getMainLooper())
    }
}
