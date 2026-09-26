# Capture uploads and Android validation

## Upload behavior

Normal and AURA photos, camera video segments, completed Boomerang recordings,
layout captures/imports, reel clips, and saved video/layout/reel exports enter the
upload queue.
The original is copied to app-private storage before processing or gallery work.
Copying and hashing share a streaming pass with a 64 KiB buffer. The capture UI
waits for this local handoff, not the network transfer.

Android WorkManager owns the uploads. Each original has an atomic journal and a
unique job constrained to a connected network. Reconnection, process recreation,
and device restart can resume queued work without a Flutter screen being open.
Jobs use exponential backoff without an arbitrary retry-count cutoff. Android
controls the exact start time; Doze, battery restrictions, or a user force-stop
can delay work. A force-stopped application must be opened again.

Files up to 6 MiB use a streamed standard upload. Larger files use TUS uploads
with 6 MiB chunks and an authoritative server offset on retry. No more than two
transfers run at once. The immutable identity/content-hash object key avoids
duplicate objects when a completed request is retried. Successful receipts are
committed before deleting the queued original; receipts are retained for seven
days. Failed or rejected uploads keep their originals. Uploads run in the
background without an in-app status panel. Launch, reconnection, and native
background scheduling continue to resume queued work.

Existing Dart queue entries migrate into the native queue, including entries
previously abandoned after repeated failures. Unavailable legacy originals are
reported rather than silently called uploaded. Clearing app data or uninstalling
the app removes its local queue, as with other app-private data.
An invalid legacy item does not block migration of other items or new captures.
Empty recording files are never retained as retryable uploads.

Server configuration is centralized in `lib/config/server_config.dart`, with
compile-time overrides. Production uploads require HTTPS. The client must have
permission to insert into the configured bucket, and bucket size/type limits and
storage quota must accommodate the media. A rejected upload stays in the queue and is
retained locally. The debug build permits localhost HTTP solely for isolated
synthetic upload tests; release builds do not.

## Compatibility and performance

The supported minimum is Android 7.0 (API 24). Release packages target ARM32,
ARM64, and x86-64. This is not a
promise of compatibility with every Android version or manufacturer's camera.
The packaged auxiliary TensorFlow runtime cannot load on Android 7; that failure
is contained and those optional models return unavailable. ML Kit face/pose and
image-quality analysis continue. Subject segmentation also has a fallback when
Google Play services or its downloaded module are unavailable.

Camera initialization falls back through supported resolutions, starts lower on
low-RAM devices, and tolerates missing zoom/flash capabilities. Denying microphone
access still allows photography and silent video. Camera lifecycle generations
prevent stale asynchronous opens from replacing a newer camera. Multi-clip video
export handles silent and mixed-audio segments; if combining fails, each original
clip is saved separately. Interrupted playable video is queued before trimming.
Android 7 and virtual devices use the bundled software video encoder because
their MediaCodec encoder may accept work without producing output. Android 8+
physical devices try hardware encoding first and fall back on reported failure.

## Repeatable checks

Run `flutter analyze --no-pub` and `flutter test --no-pub` for Dart checks.
Run `./gradlew :app:testDebugUnitTest --tests com.aura.aura.CaptureUploadsTest`
from `android/` for durable storage and upload transport checks. The native tests
cover source deletion, queue reopening, deduplication, journal recovery, repeated
server failures, permission rejection, duplicate replies, interrupted TUS chunks,
lost final acknowledgments, and validation of returned upload destinations.

Run `flutter test integration_test/runtime_smoke_test.dart -d DEVICE` for camera,
AURA composition/detectors, layout capture/recovery, and synthetic video exports.
Run `flutter test integration_test/layout_export_test.dart -d DEVICE` for the
native layout export matrix. Camera integration tests suspend production uploads.

`integration_test/support/upload_probe_app.dart` is a separate debug-only entry
point for a manual process-death check. It requires an offline emulator and a
synthetic HTTP receiver at `10.0.2.2:8754`; it uses an isolated test queue. After
the ready log, terminate the app process without force-stopping the package,
restore networking, and check the receiver's byte count/hash and uploaded journal.
Always rebuild with `--target=lib/main.dart` for a deliverable application.

Build release packages with `flutter build apk --release --split-per-abi
--target=lib/main.dart`. Keep the normal dependency/metadata regeneration enabled
when switching from integration/debug builds to release: using `--no-pub` with
this Flutter setup retained a stale generated integration-test registration and
caused release compilation to fail. Do not edit the generated registrant by hand.

## Validation on 2026-09-25

- Flutter: 716 tests passed; static analysis clean.
- Native uploader: 10 tests passed, including resumed large uploads.
- Android 7 emulator: an offline synthetic PNG survived source deletion and app
  process termination. Restoring connectivity restarted the native worker and
  uploaded all 293 bytes with the original SHA-256, without opening the UI.
- Android 7 emulator: all eight runtime integration tests passed, including
  capture/review recovery, camera switching, landscape layouts, timed clips,
  original-resolution composition, ML Kit, motion masks, mixed/silent audio,
  and all four Boomerang effects.
- Android 15 emulator: all 792 native layout exports passed, including
  production-resolution renders, masks, aspect ratios, orientations and media
  modes. The other runtime checks passed. A short custom recording returned
  `ERROR_NO_VALID_DATA` in the first full run. After keeping the camera preview
  fixed beneath the duration dialog's keyboard, the focused timed-recording
  recheck passed all five clips (3, 5, 7, 2 and 2 seconds).
- The configured live server accepted a tiny synthetic PNG. Its public client
  cannot list/delete that diagnostic object, so the object remains on the server.
  No camera test uploads real scene photos.
- Live resumable upload: session creation returned 201, a synthetic 6 MiB chunk
  returned 204, and HEAD confirmed offset 6,291,456. The unfinished session was
  terminated with 204, without creating an image object.
- Android 7 and Android 15 system HTTPS clients both reached the actual server's
  storage status endpoint successfully (HTTP 200 with verified TLS).

The FFmpeg plugin currently emits a future Kotlin Gradle Plugin migration warning.
Its current build works; a future Flutter upgrade needs a compatible plugin
release or a reviewed plugin migration.
