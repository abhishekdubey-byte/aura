# Normal-mode layouts

Open **Normal → Layout**, directly below Flash. The layout camera has its own
draft; opening it releases the regular camera, and returning reopens that camera.
Boomerang and Aura Calc do not expose the entry point.

## Capture

- Choose Four, Two rows, Two columns, Three rows, Six, One + two, Diamond eight,
  Nine strips, or Seven strips. Diamond eight follows a staggered 3–2–3
  arrangement; the strip layouts contain full-height vertical panels.
- Photos accepts photographs, Videos records individual clips, and Hybrid lets
  each selected cell switch between Photo and Video.
- Layouts with more than six cells include a scrollable numbered cell selector,
  so narrow strips remain easy to select in portrait social formats.
- Tap an empty cell and use the shutter. In Video, tap once to start and again
  to stop. Volume-down also operates the shutter. Pinch the live cell to zoom.
- Video cells show **Auto-stop**, with 3s (default), 5s and 7s presets plus a
  custom 1–300 second duration. The saved duration applies to each subsequent
  video recording, including Hybrid cells, and recording stops automatically.
  The elapsed/target display shows progress. Manual stop can finish a clip early;
  existing and imported clips are unchanged and retain last-frame holding.
  Automatically stopped clips are normalized to the selected duration at 30 fps,
  holding the last frame and padding audio with silence to compensate for camera
  startup latency. This finalization runs before the cell becomes ready.
- Import uses the gallery for the selected cell's media type. Retake preserves
  the old capture until its replacement succeeds. Clear empties one cell.
- The selected ratio applies to the whole composition. All 12 existing presets
  are available, including Full, resolved when opening the layout session.
  Rotate composition swaps its width and height. Rotating the phone changes
  the controls and camera orientation without changing that chosen output ratio.
- A recording locks its capture orientation. Lens changes are available between
  cell recordings; they are disabled during a recording.
- Back offers Keep draft or Discard when cells are filled. Completed cell
  originals and draft metadata live in application-support storage and survive
  app restarts. Backgrounding finalizes and recovers a recording using CameraX's
  existing dispose-and-recover approach on Android.

## Review and output

Review renders the actual composition. Photo-only output is JPEG with a
2160-pixel long edge. Output containing video is H.264 MP4 at 30 fps with a
1920-pixel long edge. Dimensions and cell boundaries are even pixels; minor
rounding is necessary for arbitrary ratios. Photos honor the existing watermark
setting, applied once to the completed composition.

Video cells start together. Output lasts for the longest clip; shorter clips
hold their last frame and photographs remain static. Audio defaults to Mute;
select any cell with audio to use its track, padded with silence if necessary.
Changing audio rerenders the preview. Camera-front mirroring and input rotation
are applied before center-cover cropping. Diamond cells cut away their corners
against a black canvas, with media kept upright inside each cell. Source media
is never stretched. Desktop ratios and social presets (including 9:16 Stories,
4:5 posts and square) use the same composition geometry.

Save writes photos to AURA/Snaps (AURA/Wallpapers for desktop presets) and video
to AURA/Videos. Save or render failures keep the draft available for retry.
This feature does not require a new gallery folder or extra storage permissions.

## Implementation

- `lib/layout/layout_template.dart`: nine normalized arrangements, shared shape
  masks, output sizing, pixel boundaries, and center crops.
- `layout_draft.dart`, `layout_store.dart`: per-cell media, mode and aspect state,
  atomic serialized persistence, original retention, and orphan cleanup.
- `layout_camera_screen.dart`, `layout_widgets.dart`: capture state, lifecycle,
  gallery import, responsive controls, icons, and cell preview.
- `layout_exporter.dart`: background photo composition and FFmpeg video stacking,
  with hardware encoding on Android and software fallback.
- `layout_review_screen.dart`: rendered photo/video playback, audio selection,
  export progress, and gallery save.

`video_player` supplies local MP4 playback. Export reuses the existing FFmpeg,
image, MediaSaveQueue, and MediaLibrary infrastructure.

## Reproducible verification

```sh
flutter test test/layout_test.dart
flutter test integration_test/layout_export_test.dart -d <android-device-id>
flutter test integration_test/layout_camera_test.dart -d <android-device-id>
flutter analyze lib/layout lib/widgets/aspect_ratio_picker.dart lib/services/media_library.dart test integration_test
flutter build apk --debug
```

The local matrix exercises 9 layouts × 12 presets × 2 composition orientations ×
3 media modes (648 combinations). It checks tiling, crop bounds, persistence,
real JPEG composition and color placement, mirroring, video arguments, and
portrait/landscape widget constraints, with additional interaction and failure
tests.

The native export suite renders all 648 combinations at a 192-pixel long edge
for exhaustive coverage, then 144 compositions at production resolution (every
layout and media mode, both orientations, plus desktop and social ratios for
the three new presets). It probes video dimensions, duration and audio, and
decodes output frames to verify cell placement and held end frames. The workflow
suite also verifies real camera captures in all three new layouts and uses a changing-color video to check motion and
end-frame holding in both video-only and hybrid exports.
The camera suite uses a separate temporary draft and does not upload captures.

Native Android checks use the connected RMX3031. iOS requires separate device or
simulator validation. The repository-wide analyzer baseline already contains
missing imports in `test_math.dart` from files deleted before this feature.

Verified on 2026-09-25: all 661 local tests, 792 native matrix exports, and all
four camera/motion/timer integration tests passed on RMX3031. The motion test covers
six additional video-only/hybrid exports. Real-camera checks covered capture,
last-cell selection, landscape controls and full-resolution review for every new
preset. The feature's source and tests analyze without issues. Repository-wide
analysis retains the 44 pre-existing baseline issues.

Timed recording verification: all 661 local tests and the camera workflow suite
passed. After camera-latency normalization, the dedicated device test measured
3.0s, 5.0s, 7.0s, 2.0s and 2.0s saved clips, and verified custom-duration
persistence and consecutive automatic stops. Feature analysis reports no issues.
