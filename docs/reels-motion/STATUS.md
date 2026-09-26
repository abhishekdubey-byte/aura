# Reels Motion Editor — active feature status

One row is active at a time. Read this and
[FEATURE_WORKFLOW.md](FEATURE_WORKFLOW.md) before editing, including at the start
of a new session or after context restoration.

## Active feature

| Field | Value |
| --- | --- |
| Feature | **F01 — Minimal editable project, stable IDs, asset ownership, undo/redo** |
| Branch | `feature/reels-01-project-history` |
| Base branch | `chore/reels-00-audit-baseline` |
| Base commit | `d4554b21a77ae932252accb40ff270b196abeb88` |
| Gate state | **READY_FOR_DEVICE_TEST** — automated checks pass, device verification NOT RUN |
| Handoff | [features/F01.md](features/F01.md) |
| Checks | `flutter analyze` clean; `flutter test` 767/767 pass |
| Device / APK | **NOT RUN** — no Android SDK or reachable device in the build container |

Under the revised operating mode, work continues to the next feature rather than
halting here. What cannot continue is device verification and merging to `main`:
see the standing blockers below.

## Feature ledger

Gate states: `NOT_STARTED`, `IN_PROGRESS`, `READY_FOR_DEVICE_TEST`,
`FIXING_CURRENT_FEATURE`, `DEVICE_ACCEPTED`, `WAITING_FOR_MANUAL_GIT`,
`BLOCKED_SCOPE`.

| ID | Branch | Gate state | Accepted commit |
| --- | --- | --- | --- |
| F00 | `chore/reels-00-audit-baseline` | Pushed, awaiting review/merge | — |
| F01 | `feature/reels-01-project-history` | READY_FOR_DEVICE_TEST | — |
| F02 | `feature/reels-02-native-render-baseline` | NOT_STARTED | — |
| F03 | `feature/reels-03-clip-timeline` | NOT_STARTED | — |
| F04 | `feature/reels-04-clip-trim` | NOT_STARTED | — |
| F05 | `feature/reels-05-clip-split` | NOT_STARTED | — |
| F06 | `feature/reels-06-clip-reorder` | NOT_STARTED | — |
| F07 | `feature/reels-07-clip-remove` | NOT_STARTED | — |
| F08 | `feature/reels-08-video-import` | NOT_STARTED | — |
| F09 | `feature/reels-09-image-clips` | NOT_STARTED | — |
| F10 | `feature/reels-10-clip-replace` | NOT_STARTED | — |
| F11 | `feature/reels-11-clip-rerecord` | NOT_STARTED | — |
| F12 | `feature/reels-12-crop-reframe` | NOT_STARTED | — |
| F13 | `feature/reels-13-project-canvas` | NOT_STARTED | — |
| F14 | `feature/reels-14-reel-cover` | NOT_STARTED | — |
| F15 | `feature/reels-15-durable-drafts` | NOT_STARTED | — |
| F16 | `feature/reels-16-tap-to-direct` | NOT_STARTED | — |
| F17 | `feature/reels-17-custom-motion-paths` | NOT_STARTED | — |
| F18 | `feature/reels-18-custom-easing` | NOT_STARTED | — |
| F19 | `feature/reels-19-linked-motion` | NOT_STARTED | — |
| F20 | `feature/reels-20-constant-speed` | NOT_STARTED | — |
| F21 | `feature/reels-21-speed-ramps` | NOT_STARTED | — |
| F22 | `feature/reels-22-graphic-layers` | NOT_STARTED | — |
| F23 | `feature/reels-23-video-overlay` | NOT_STARTED | — |
| F24 | `feature/reels-24-layer-animation` | NOT_STARTED | — |
| F25 | `feature/reels-25-basic-masks` | NOT_STARTED | — |
| F26 | `feature/reels-26-custom-masks` | NOT_STARTED | — |
| F27 | `feature/reels-27-motion-blur` | NOT_STARTED | — |
| F28 | `feature/reels-28-text-layers` | NOT_STARTED | — |
| F29 | `feature/reels-29-text-animators` | NOT_STARTED | — |
| F30 | `feature/reels-30-text-travel-path` | NOT_STARTED | — |
| F31 | `feature/reels-31-text-on-path` | NOT_STARTED | — |
| F32 | `feature/reels-32-capture-editor-polish` | NOT_STARTED | — |
| F33 | `perf/reels-33-4gb-validation` | NOT_STARTED | — |
| F34 | `fix/reels-34-export-publication` | NOT_STARTED | — |

## Standing blockers for later features

These come from the F00 audit and affect authorization decisions. They are
recorded, not resolved.

1. **No Android SDK or device in the audit environment.** APK builds, the
   `integration_test/` suite, the Kotlin unit tests, and every performance or
   export-pixel measurement are unavailable here. `dl.google.com` is denied by
   the environment's network policy. Any feature whose acceptance depends on
   rendered output or measured performance needs a build environment with the
   Android SDK and a physical device.
2. **No native render pipeline exists.** Reel preview is a full FFmpeg re-encode
   of the whole reel, played back with `video_player`; there is no Media3, no
   `CompositionPlayer`, and no native preview surface. F02 is therefore a new
   native module and a dependency decision, not an extension of existing code.
   See [AUDIT.md](AUDIT.md).
3. ~~**The project canvas is derived at render time**, from
   `clips.first.ratio`.~~ **Fixed in F01**: the canvas is now project state,
   initialized by the first accepted clip and unchanged by removal, reorder, or
   an emptied sequence. F13 owns deliberate changes to it.
4. **No usable VFR timestamp model.** The MP4 probe reads only `mdhd`
   timescale/duration, and export forces `fps=30`. F04, F20, and F21 need real
   per-frame timestamps before their correctness claims can hold.
