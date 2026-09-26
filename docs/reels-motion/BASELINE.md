# F00 — Baseline validation

Recorded 26 September 2026, before any application change, so later features
have a real reference rather than an assumed one.

## Identity of the measured tree

| Item | Value |
| --- | --- |
| Base branch | `claude/tender-cannon-klfav3` |
| Base commit | `03323f59835485f3841288e4fd04532a9c6a05bd` |
| Commit subject | `Merge pull request #1 from abhishekdubey-byte/feature/reels-handsfree-camera-ux` |
| Audit branch | `chore/reels-00-audit-baseline` (same commit; docs only, uncommitted) |
| Worktree at measurement time | Clean, no untracked files |

`pubspec.lock` was SHA-256 checked before and after `flutter pub get` and is
byte-identical (`f6218a50c4fdbafcfdfe6501b84dc362568e80352be3f42814caab587087c087`).
Dependency resolution did not change any tracked file.

## Environment

The audit ran in a Linux container that ships **no** Flutter, Dart, or Android
SDK. Flutter 3.47.5 stable (Dart 3.13.4) was fetched to a scratch directory
outside the repository to make the checks below real rather than skipped. It was
chosen because it is the newest stable release whose Dart version satisfies
`pubspec.yaml`'s `sdk: ^3.13.3`; every earlier stable line ships Dart 3.12 or
lower and cannot resolve this project.

| Component | State |
| --- | --- |
| Flutter / Dart | 3.47.5 stable / 3.13.4 — fetched to scratch, outside the repo |
| Java | OpenJDK 21.0.10 (present) |
| Gradle | 8.14.3 at `/opt/gradle` (present, but the project pins 9.3.1) |
| Android SDK / platform-tools / `adb` | **Absent, and not obtainable** |
| `android/local.properties` | Absent (gitignored; required by `settings.gradle.kts`) |
| `android/key.properties` | Absent (gitignored; required by the release signing config) |
| Gradle wrapper script and JAR | Not tracked in the repository |
| Physical Android device | None attached |

The Android SDK cannot be installed here: the environment's network policy
denies `dl.google.com`, which serves both `commandlinetools-linux-*.zip` and the
Google Maven artifacts for AGP 9.1.0. `storage.googleapis.com` is permitted,
which is why the Flutter SDK could be fetched but the Android SDK could not.

## Commands and results

| Command | Result | Notes |
| --- | --- | --- |
| `flutter --version` | PASS | Flutter 3.47.5, Dart 3.13.4, DevTools 2.60.0 |
| `flutter pub get` | PASS | Resolved; `pubspec.lock` unchanged. 15 packages have newer versions held back by constraints |
| `flutter analyze` | **PASS** | `No issues found!` in 20.5 s |
| `flutter test` | **PASS** | `All tests passed!` — 727 cases, 0 failures, 0 skips, ~25 s |
| `flutter test integration_test/…` | **NOT RUN** | Needs an attached Android device or emulator; none available |
| `flutter build apk` | **NOT RUN** | No Android SDK; see the blocker above |
| `gradle :app:testDebugUnitTest` (Kotlin unit tests) | **NOT RUN** | Needs the Android SDK and `local.properties` |

Nothing was weakened, skipped, or marked passed to produce these results.

### Reel cases inside the passing suite

All six reel cases named by `docs/reels.md` and the plan ran and passed:

- `test/reel_session_test.dart` — release during startup finalizes exactly once
  and preserves earlier clips
- `test/reel_session_test.dart` — deadline starts after camera readiness and
  limits each clip independently
- `test/reel_session_test.dart` — failed capture leaves previous clips available
  and permits retry
- `test/reel_session_test.dart` — invalid duration is rejected before starting
  camera
- `test/reel_session_test.dart` — custom timer validates bounds and fits a
  narrow screen with large text
- `test/reel_camera_ui_test.dart` — reel capture and camera switching work;
  right-side tools stay within 3:4

The protected **320×640 at 1.6× text scale** case is present and passing:
`test/reel_camera_ui_test.dart` sets
`textScaler: TextScaler.linear(1.6)` and `tester.view.physicalSize = Size(320, 640)`.

### Test inventory on the baseline commit

`test/` — 12 files, 71 declared cases, expanding to 727 executed cases (the
Layout suite generates permutations):

| File | Declared cases |
| --- | --- |
| `aura_scoring_test.dart` | 15 |
| `aura_test.dart` | 11 |
| `layout_test.dart` | 14 |
| `project_regression_test.dart` | 8 |
| `upload_manager_test.dart` | 7 |
| `hands_free_commands_test.dart` | 6 |
| `reel_session_test.dart` | 5 |
| `hands_free_controls_test.dart` | 1 |
| `hands_free_preferences_test.dart` | 1 |
| `hands_free_voice_test.dart` | 1 |
| `model_runner_test.dart` | 1 |
| `reel_camera_ui_test.dart` | 1 |

`integration_test/` — 9 files, all NOT RUN for want of a device:
`reel_export_test.dart`, `layout_camera_test.dart`, `layout_export_test.dart`,
`aura_workflow_test.dart`, `hands_free_test.dart`, `video_workflow_test.dart`,
`upload_background_test.dart`, `android_validation_test.dart`,
`runtime_smoke_test.dart`.

`integration_test/reel_export_test.dart` is the one that actually inspects
rendered output — it synthesizes clips with FFmpeg, runs `VideoProcessor.reel`,
and asserts duration, aspect, and audio-track presence via `FFprobeKit`. It is
the natural place to extend export-pixel and timestamp verification from F02
onward, and it must be run on a device before any export-affecting feature is
accepted.

`android/app/src/test/kotlin/com/aura/aura/CaptureUploadsTest.kt` is a
Robolectric/JUnit suite for the native upload queue. It was NOT RUN for the same
Android SDK reason.

## No performance baseline was captured

No frame timings, memory figures, decoder counts, scrub latencies, or thermal
measurements exist for this commit. They require a physical Android device, which
this environment does not have. The plan's `§8` budgets remain **proposed
targets, not measured results**, and F33 owns measuring them.

`collect_android_memory_1.py` (supplied with the handoff) is a host-side,
read-only main-process PSS sampler needing `adb` and an authorized device. It is
not in this repository, `adb` is not installed here, and it was not run. Its own
documentation is explicit that it verifies no application performance threshold.

## What a later session should re-establish

The Flutter SDK lives outside the repository in a session scratch directory and
does not survive container replacement. Any later feature that needs to run
checks must re-fetch a Flutter release whose Dart version satisfies
`sdk: ^3.13.3` (3.47.x or newer stable), and must obtain an Android SDK plus a
physical device for anything involving a build, the integration suite, or
performance evidence.
