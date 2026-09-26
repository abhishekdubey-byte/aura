package com.aura.aura

import android.content.Context
import androidx.work.workDataOf
import androidx.work.testing.TestWorkerBuilder
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class CaptureUploadsTest {
    private lateinit var context: Context
    private lateinit var store: CaptureUploadStore
    private lateinit var server: MockWebServer
    private val executor = Executors.newSingleThreadExecutor()
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        server = MockWebServer().apply { start() }
        store = CaptureUploadStore(context, "test_" + UUID.randomUUID().toString().replace("-", ""))
        store.configure(server.url("/").toString().trimEnd('/'), "test-public-key", "captures")
    }
    @After fun cleanup() { server.shutdown(); store.root.deleteRecursively(); executor.shutdownNow() }

    private fun source(large: Boolean = false): File {
        val file = File(context.cacheDir, "${UUID.randomUUID()}.${if (large) "mp4" else "jpg"}")
        file.outputStream().use { out ->
            val bytes = ByteArray(65536) { (it % 251).toByte() }
            repeat(if (large) 112 else 1) { out.write(bytes) }
        }
        return file
    }
    private fun queued(large: Boolean = false): org.json.JSONObject {
        val source = source(large)
        return store.enqueue(source.path, "test_user").also { source.delete() }
    }
    private fun worker(row: org.json.JSONObject) = TestWorkerBuilder.from(context,
        CaptureUploadWorker::class.java, executor).setInputData(workDataOf("scope" to store.scope,
            "id" to row.getString("id"))).build()

    @Test fun originalSurvivesSourceDeletionAndStoreRestart() {
        val row = queued()
        val reopened = CaptureUploadStore(context, store.scope)
        assertEquals(1, reopened.rows().size)
        assertEquals(row.getLong("bytes"), File(reopened.root, row.getString("id")).length())
        assertEquals("image/jpeg", reopened.rows().single().getString("mime"))
    }
    @Test fun duplicateCaptureIsOneQueuedObject() {
        val source = source()
        val a = store.enqueue(source.path, "test_user")
        val b = store.enqueue(source.path, "test_user")
        source.delete()
        assertEquals(a.getString("id"), b.getString("id"))
        assertEquals(1, store.rows().size)
    }
    @Test fun recoversCompletedCopyBeforeJournalCommit() {
        val row = queued()
        File(store.root, row.getString("id") + ".json").writeText("broken json")
        store.recover()
        assertEquals(1, store.rows().size)
        assertEquals("pending", store.rows().single().getString("status"))
    }
    @Test fun serverFailureRetainsBytesAndRetryCompletes() {
        val row = queued()
        row.put("attempts", 8); store.write(row)
        server.enqueue(MockResponse().setResponseCode(503))
        worker(row).doWork()
        assertEquals("retrying", store.read(row.getString("id"))!!.getString("status"))
        assertTrue(File(store.root, row.getString("id")).exists())
        server.enqueue(MockResponse().setResponseCode(200).setBody("{}"))
        worker(row).doWork()
        assertEquals("uploaded", store.read(row.getString("id"))!!.getString("status"))
        assertFalse(File(store.root, row.getString("id")).exists())
        val first = server.takeRequest(); val second = server.takeRequest()
        assertEquals(first.body.readByteString(), second.body.readByteString())
        assertEquals("image/jpeg", second.getHeader("Content-Type"))
    }
    @Test fun accessDeniedIsVisibleAndRetained() {
        val row = queued()
        server.enqueue(MockResponse().setResponseCode(403))
        worker(row).doWork()
        assertEquals("blocked", store.read(row.getString("id"))!!.getString("status"))
        assertEquals(1, store.snapshot()["blocked"])
        assertTrue(File(store.root, row.getString("id")).exists())
    }
    @Test fun duplicateObjectReceiptIsSuccessButGenericConflictIsNot() {
        val row = queued()
        server.enqueue(MockResponse().setResponseCode(400).setBody("{\"code\":\"ResourceAlreadyExists\"}"))
        CaptureUploadTransport(store).upload(row)
        server.enqueue(MockResponse().setResponseCode(409).setBody("offset conflict"))
        assertThrows(UploadResponseException::class.java) { CaptureUploadTransport(store).upload(row) }
    }
    @Test fun largeFileResumesAtServerConfirmedOffsetAfterFailure() {
        val row = queued(true)
        val length = row.getLong("bytes")
        server.enqueue(MockResponse().setResponseCode(201).setHeader("Location", server.url("/tus/one")))
        server.enqueue(MockResponse().setResponseCode(204).setHeader("Upload-Offset", CaptureUploadTransport.chunkSize))
        server.enqueue(MockResponse().setResponseCode(503))
        assertThrows(UploadResponseException::class.java) { CaptureUploadTransport(store).upload(row) }
        val restarted = CaptureUploadStore(context, store.scope)
        val checkpoint = restarted.read(row.getString("id"))!!
        assertEquals(CaptureUploadTransport.chunkSize, checkpoint.getLong("offset"))
        server.enqueue(MockResponse().setResponseCode(200).setHeader("Upload-Offset", CaptureUploadTransport.chunkSize))
        server.enqueue(MockResponse().setResponseCode(204).setHeader("Upload-Offset", length))
        CaptureUploadTransport(restarted).upload(checkpoint)
        val requests = (1..5).map { server.takeRequest() }
        assertEquals(listOf("POST", "PATCH", "PATCH", "HEAD", "PATCH"), requests.map { it.method })
        assertEquals(CaptureUploadTransport.chunkSize, requests[1].bodySize)
        assertEquals(length - CaptureUploadTransport.chunkSize, requests[4].bodySize)
        assertEquals(CaptureUploadTransport.chunkSize.toString(), requests[4].getHeader("Upload-Offset"))
        assertEquals(requests[2].body.readByteString(), requests[4].body.readByteString())
    }
    @Test fun lostFinalResponseDoesNotResendCompletedFile() {
        val row = queued(true).put("uploadUrl", server.url("/tus/done").toString())
        store.write(row)
        server.enqueue(MockResponse().setResponseCode(200).setHeader("Upload-Offset", row.getLong("bytes")))
        CaptureUploadTransport(store).upload(row)
        assertEquals(1, server.requestCount)
        assertEquals("HEAD", server.takeRequest().method)
    }
    @Test fun untrustedLocationCannotReceiveCredentials() {
        val row = queued(true)
        server.enqueue(MockResponse().setResponseCode(201).setHeader("Location", "https://untrusted.invalid/tus"))
        assertThrows(IllegalArgumentException::class.java) { CaptureUploadTransport(store).upload(row) }
        assertFalse(row.has("uploadUrl"))
    }
    @Test fun cannotRedirectQueuedMediaByReconfiguringHost() {
        queued()
        assertThrows(IllegalArgumentException::class.java) {
            store.configure("https://another.invalid", "not-a-real-key", "captures")
        }
        assertEquals(server.url("/").toString().trimEnd('/'), store.config().first)
    }
}
