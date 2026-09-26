# F00 — Repository audit and gap analysis

Audited 26 September 2026 on `chore/reels-00-audit-baseline`, based at
`claude/tender-cannon-klfav3` @ `03323f59835485f3841288e4fd04532a9c6a05bd`.

This records what the repository actually contains today, measured by reading
the source and running the checks in [BASELINE.md](BASELINE.md). It replaces
assumption with fact for the planning statements in
`AURA_REELS_MOTION_EDITOR_CODEX_PLAN_V2.md`, which was written without repository
access. Nothing here is an implementation.

## Toolchain as measured

| Item | Actual value |
| --- | --- |
| Flutter / Dart | 3.47.5 stable / Dart 3.13.4 (satisfies `pubspec.yaml` `sdk: ^3.13.3`) |
| Android Gradle Plugin | 9.1.0 (`android/settings.gradle.kts`) |
| Kotlin | 2.4.0 |
| Gradle | 9.3.1 (`gradle-wrapper.properties`) |
| `compileSdk` / `minSdk` | 37 / 24; `targetSdk` from the Flutter plugin |
| Java / Kotlin JVM target | 17, with core library desugaring enabled |
| Namespace / applicationId | `com.aura.aura` |

Two build inputs are intentionally absent from version control and must exist
locally before any Android build: `android/local.properties` (supplies
`flutter.sdk`, which `settings.gradle.kts` requires) and `android/key.properties`
(supplies the release signing config). The Gradle wrapper script and JAR are
also not in the repository; only `gradle-wrapper.properties` is tracked, so
builds go through the Flutter tool or a locally provided Gradle.

## Reel-related file map

| Path | Lines | Responsibility |
| --- | --- | --- |
| `lib/reel/reel_camera_screen.dart` | 796 | Reel capture screen: camera open/close, Hold and hands-free capture, aspect/flash/zoom, lifecycle suspend and resume, Android post-background clip recovery, preview handoff |
| `lib/reel/reel_session.dart` | 135 | Recording deadline, start/stop race serialization, in-memory clip list, capture-scoped `undo()` |
| `lib/reel/reel_review_screen.dart` | 150 | Plays the already-rendered output file and saves it |
| `lib/reel/reel_duration_picker.dart` | 85 | Hands-free duration sheet |
| `lib/services/video_processor.dart` | 509 | FFmpeg filter graphs for reel/stitch/mirror/crop/boomerang, encoder fallback, hand-rolled MP4 header probe |
| `lib/camera/camera_session.dart` | 96 | Shared camera open, zoom range, flash |
| `lib/camera/capture_aspect.dart` | 134 | 12 aspect presets and viewfinder geometry |
| `lib/services/media_library.dart` | 119 | `Pictures/AURA/{Snaps,Videos,Boomerang,Wallpapers,Aura Results}` via `gal` |
| `lib/services/upload_manager.dart` | 350 | Dart side of the background upload queue |
| `lib/services/media_encoder_policy.dart` | 19 | Hardware-encoder eligibility (physical device, SDK ≥ 26) |
| `lib/hands_free/*` | 821 | Palm/voice/gesture commands shared with the main camera and Layout |
| `lib/theme/aura_theme.dart` | 256 | `AuraColors` / `AuraTheme` tokens |
| `lib/main.dart` | 2830 | App shell; `_openReels()` disposes the main camera then pushes `ReelCameraScreen` |

Android native sources are `MainActivity.kt`, `HandsFreeBridge.kt`,
`ImageProcessor.kt`, `CaptureUploads.kt`, and `CaptureUploadWorker.kt`, all under
`android/app/src/main/kotlin/com/aura/aura/`. The existing platform channels are
`com.aura.aura/volume` (EventChannel), `/shutter`, `/image`, `/uploads`, plus the
hands-free bridge. There is no reels channel.

## How the reel currently renders

This is the audit's most consequential finding for F02.

`Preview reel` in `reel_camera_screen.dart` closes the camera and calls
`VideoProcessor.reel(...)`, which builds one FFmpeg `filter_complex` over every
clip and **encodes the entire reel to a new MP4**. That file is then handed to
`ReelReviewScreen`, which plays it with `video_player`.

Consequences:

- Preview and export are already "consistent" only because **preview is the
  export**. There is no shared plan; there are no two paths to reconcile yet.
- Every preview costs a full re-encode of the whole reel. The plan's performance
  contract ("no full-reel re-encode on every edit", `§8`) is not merely unmet —
  the current design is its opposite. An editor that previews after each edit
  cannot be built on this path.
- There is **no native preview surface**. `grep` over `lib/` and
  `android/app/src/` finds no `media3`, `Media3`, `CompositionPlayer`,
  `TextureRegistry`, or `SurfaceProducer` reference. The only `MediaCodec`
  mention is the comment in `media_encoder_policy.dart`.
- The rendering engine is FFmpegKit (`ffmpeg_kit_flutter_new_min_gpl ^2.6.2`),
  not Media3/Transformer. The plan's architecture, its `[S1]`–`[S6]` Media3
  references, and its `SpeedProvider`/`EditedMediaItem` reasoning therefore
  describe a pipeline that **does not exist in this repository yet**. Adopting
  Media3 is a new dependency and a new native module, not an extension of
  existing code.

Export profile facts worth preserving, all from `VideoProcessor.reel` and
`reelFilter`:

- Canvas long side is clamped to 1920 and both dimensions forced even.
- Per clip: `trim=duration=…`, `setpts=PTS-STARTPTS`, optional `hflip` for
  front-camera clips, centre `crop` to the clip's own ratio, then
  `scale=…:force_original_aspect_ratio=decrease` + `pad` (letterbox, never a
  second crop), `setsar=1`, `fps=30`, `format=yuv420p`.
- Audio is included when **any** clip has an audio track; clips without one
  contribute `anullsrc` silence. Audio is resampled to 48 kHz stereo,
  `apad`/`atrim`-ed to the clip's duration, then AAC at 192 kbps.
- `-movflags +faststart`.
- Encoding tries `h264_mediacodec` at the source bitrate, falling back to
  `libx264 -preset veryfast -crf 18`.

## Project model and editing state

There is no project document. `ReelClip` is an immutable
`{path, seconds, ratio, mirror}` value in an in-memory `List` on
`ReelSession`; a clip's identity is its list index.

Absent entirely: `ReelProject`, `MediaAsset`, `VideoClip`, `ImageClip`,
`MotionSpec`, `TimeMap`, `VisualLayer`, `MaskSpec`, `TextSpec`,
`LinkedMotionPair`, `CoverSelection`, `RenderPlan`, `ExportJob`; stable IDs;
project revisions; schema versioning; and asset reference ownership.

`ReelSession.undo()` removes the last clip and nothing else. That is the
capture-scoped "Remove last" the plan distinguishes from editor undo/redo;
there is no command history, so editor undo/redo is entirely new work (F01).

Reel drafts do not persist. `docs/reels.md` states plainly that "Drafts are not
restored after process termination." A reusable precedent does exist for
Layout — `lib/layout/layout_draft.dart` and `lib/layout/layout_store.dart` —
and should be read before F15 rather than inventing a second persistence
approach.

### Canvas ownership is a real defect against the plan

`_review()` passes `ratio: _session.clips.first.ratio`, so the output canvas is
**derived from whichever clip is currently first, at render time**. The plan
requires the first accepted visual item to initialize the canvas, after which the
canvas becomes project state that does not change when that item is removed,
reordered, or replaced (`§0`, `§2`).

Today there is no reorder or remove-from-middle, so the divergence is not yet
observable. It becomes a live bug the moment F06 or F07 lands. The canvas must
become stored project state in F01, and F13 owns deliberate project-wide
changes. Recorded here so it is not discovered late.

## Capture behavior to preserve

Verified by reading `reel_session.dart` and `reel_camera_screen.dart`:

- `ReelPhase` is `idle → starting → recording → stopping`. The deadline timer
  starts only after `startCapture()` returns, i.e. at actual camera recording
  start, not at button press.
- `stop()` is memoized through `_stopping`, so duplicate stops finalize once.
  `_stop()` awaits `_starting` first, so a release during startup is safe.
- A failed finalize sets a user-facing error, keeps earlier clips, closes the
  camera, and reopens it so the next clip is still possible.
- Per-take duration is bounded by `_limit ?? maxSeconds` and clip seconds are
  `min(actual, limit)`. `maxSeconds = 300` is a **per-take** bound. Nothing in
  the code caps total project length.
- `presets = [3, 5, 7, 30, 60]` plus custom 1–300 s, matching `docs/reels.md`.
- On Android, if the app left the screen, the code does not call
  `stopVideoRecording()` (which can crash CameraX after surface destruction);
  it disposes the camera and recovers the newest `REC*.mp4` from the temporary
  directory, polling `VideoProcessor.isPlayable` up to 20 × 200 ms.
- Every finalized clip is enqueued with `UploadManager.instance.enqueue(path)`
  before its duration is probed.
- Capture orientation is locked to `portraitUp`; landscape output comes from the
  aspect picker.
- Reels default to `CaptureAspect.full`; the main camera's default is `standard`
  (3:4). 9:16 already exists twice — `tall` (`9:16`) and `stories` — so the plan's
  "add 9:16 if not already present" is already satisfied.

## Pre-existing sharp edges

Recorded as facts, not as F00 work. None of these is fixed on this branch.

1. `VideoProcessor._probe` falls back to `_VideoInfo(1080, 1920, 20000000, 0)`
   when the MP4 header cannot be parsed. `reel()` and `stitch()` reject
   `seconds <= 0` so they abort safely, but `mirror()`, `crop()`, and
   `boomerang()` use that fabricated bitrate. Any new code must not treat a
   probe result as authoritative source metadata.
2. `_Mp4Header` reads `mdhd` timescale and duration only. There is no per-frame
   timestamp handling, so variable-frame-rate sources have no accurate model.
   F04 (trim) and F20/F21 (retiming) need real timestamps; the plan's
   prohibition on approximating VFR as `frameIndex / nominalFps` cannot be
   honoured with this probe alone.
3. `reelFilter` forces `fps=30` on every clip. Source cadence above 30 fps is
   already discarded at export.
4. `ffmpeg_kit_flutter_new_min_gpl` is a GPL-licensed build. Relevant to any
   decision about keeping FFmpeg alongside or instead of Media3; flagged for the
   owner, not decided here.
5. `_review()` holds no cancellation path: a long FFmpeg encode cannot be
   aborted from the UI.

## Gap summary against the plan

| Plan capability | Repository today | First owning feature |
| --- | --- | --- |
| Editable project, stable IDs, asset ownership, undo/redo | Absent; index-identified in-memory clip list | F01 |
| Shared immutable `RenderPlan`; native preview surface | Absent; preview is a full FFmpeg re-encode played by `video_player` | F02 |
| Lazy filmstrip, clip selection, playhead, scrubbing | Absent | F03 |
| Trim / split / reorder / remove | Absent (only capture-scoped remove-last) | F04–F07 |
| Video and image import, image cards | Absent | F08, F09 |
| Replace and transactional middle-clip re-record | Absent | F10, F11 |
| Crop/reframe, project canvas as state, covers | Crop exists at capture; canvas derived at render time; no covers | F12–F14 |
| Durable drafts and relaunch recovery | Absent for reels; Layout precedent exists | F15 |
| Tap-to-Direct, paths, easing, linked motion | Absent | F16–F19 |
| Constant speed and speed ramps | Absent; `fps=30`, no time map | F20, F21 |
| Layers, overlay video, masks, motion blur | Absent | F22–F27 |
| Text layers and text animation | Absent | F28–F31 |
| 4 GB device validation, export/publication hardening | Absent | F33, F34 |
| Music subsystem | Absent, and stays absent | — out of scope |

No music, audio-import, waveform, picker, soundtrack, mixing, ducking,
voiceover, or beat-detection code exists in the repository. The plan's hard
exclusion is currently satisfied by construction, and must stay that way.

## Validation

See [BASELINE.md](BASELINE.md) for the commands, versions, and results behind
this audit. `flutter analyze` reported no issues and all 727 `flutter test`
cases passed on the audited commit, including the six reel cases and the
320×640 / 1.6× text-size case. The `integration_test/` suite needs an attached
Android device or emulator and was not run.
