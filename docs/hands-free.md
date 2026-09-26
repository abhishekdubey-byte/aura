# Hands-free camera (Android)

Open **Hands-free** from the right-side feature column in the normal camera,
or from the right-side tools in Reel. Layout capture also uses these settings.
Gestures and voice are separate global switches saved with SharedPreferences.
They default to off on first use and stay selected across camera routes, ratios,
front/back switches and app restarts. Temporary service failures never change
the saved switches. Both front and back previews use the same recognition path.

## Commands

- Photo/AURA: show an open palm, or say **click** / **capture**.
- Normal video: show thumbs-up or say **start**, **record**, **start recording**,
  or **resume**. These also start/resume a Reel clip or start a Boomerang.
- Reel: **capture** starts its next clip, respecting the selected clip timer.
- Pause video/Reel: form a **T** with two open hands. One hand points upward;
  the other hand is horizontal over its fingertips. Earlier clips are retained.
- Finish video/Reel: hold a **closed fist**. Normal video joins/saves its parts;
  a Reel joins its clips and opens preview. Saving the Reel is still explicit.
- Cancel a countdown with the on-screen **Cancel** button or the word **cancel**.
  A recognized T/fist can also cancel once the previous gesture is released.

Photos and recording starts have a 3-second countdown. Pause and finish have no
countdown, but all gestures must be stable: 0.9 seconds normally, 1.4 seconds for
a fist. A held hand never repeats; lower it for at least 0.6 seconds and allow the
2-second cooldown before giving another command. Keep both hands in frame for T,
with good light and enough visible hand detail. T is a geometric rule over two
tracked hands, not a trained custom gesture; occluded hands may not register.

Voice accepts complete English command phrases (optionally prefixed with
“Aura”), not words embedded inside conversation. A speech provider may still
mishear speech, so the countdown remains cancellable. Voice recognition is
stopped before recording starts, leaving the microphone to the video recorder.
Use gestures or the shutter to pause/finish while recording. Voice resumes when
recording is paused. The current listening state is visible.

## Implementation and privacy

`HandsFreeBridge.kt` uses MediaPipe Tasks Vision 0.10.35 on a single worker.
The version-1 float16 gesture recognizer model is bundled in the Android assets:

- Source: https://storage.googleapis.com/mediapipe-models/gesture_recognizer/gesture_recognizer/float16/1/gesture_recognizer.task
- SHA-256: `97952348cf6a6a4915c2ea1496b4b37ebabc50cbbf80571435643c455f2b0482`
- Upstream guide: https://developers.google.com/edge/mediapipe/solutions/vision/gesture_recognizer/android

The app samples only the camera preview boundary at up to 640 pixels on its long
edge, no faster than once per 300 ms, with at most one in-flight sample per
screen. Each snapshot is recognized independently so camera switches and
sparse samples cannot inherit a stale hand track. It does not open an extra image-analysis stream or change the video
resolution. Samples exist only in memory, are not saved, and never enter the
upload queue. Coordinates arrive already upright/mirrored as displayed; the
T rule is invariant to left/right mirroring. Confidence filtering rejects
uncertain or conflicting gesture categories. A lower-confidence open-palm label
also requires four extended fingers, a separated thumb and spread fingertips;
it never converts an unknown gesture into a capture.

Voice uses Android SpeechRecognizer, preferring on-device recognition when
available. If that service fails, it uses the installed Android speech provider; that provider may process audio online, as disclosed in the controls.
Microphone permission is requested only when enabling voice. Recognized text is
not stored. Speech timeouts restart listening; transient service errors retry with capped
backoff. Missing/unusable on-device models fall back to the installed Android
speech service, which may use the network. Permission failures show a specific
message and retry without erasing the preference. Devices
without a speech service can still use gestures. Unsupported platforms show the
availability message rather than pretend to listen.

Recognition/countdowns suspend when the camera route is covered, the app is
inactive, the camera is switching, or a capture is busy. State and owner tokens
prevent delayed frames or speech callbacks from controlling another camera
screen. Standard video now supports a paused multi-segment session with Resume
and Finish buttons; manual capture controls still work with hands-free off.

## Verification

- `test/hands_free_commands_test.dart`: exact voice parsing, context mapping,
  T geometry/mirroring, confidence, conflicting hands, stable hold, cooldown,
  neutral rearming and stale-frame rejection.
- `test/hands_free_controls_test.dart`: opt-in, cancellable countdown, repeated
  gestures and lifecycle suspension on a small screen with large text.
- `test/hands_free_preferences_test.dart`: persistence across new instances and
  ordered writes during rapid changes.
- `test/hands_free_voice_test.dart`: preference retention during service errors,
  automatic retry, restoration on a new screen, exact utterances, immediate
  countdown cancellation, and releasing speech before recording starts.
- `test/reel_camera_ui_test.dart`: normal video pause/resume and vertical right-side controls within the 3:4 frame
  at 320×640 with 1.6× text scaling, alongside timed and hold-to-record reels.
- `integration_test/hands_free_test.dart`: bundled model inference on upstream
  reference images passed through the preview sampler, plus actual front/back
  texture sampling before and during recording. Test recordings are deleted and
  uploads are suspended.

Reference test images originate from Google's MediaPipe test asset bucket
(`https://storage.googleapis.com/mediapipe-assets/`); their base64 copies are
compiled into the integration test only, never the production app.

Layout commands act on the selected cell. For video cells, pause/finish finalizes
that cell; for photo cells, palm/click captures a photo. Voice releases the
microphone before layout video recording as well.
