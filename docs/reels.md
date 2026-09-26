# Reel capture

Open **Reel** from the right-side camera controls. Camera tools now sit
in a vertical column on the right, bounded by the 3:4 frame, including aspect ratio, flash, Layout, Boomerang,
and AURA.

- **Hold:** press the shutter to start, release to pause, then press again to
  append another clip. The next clip is added after the previous one finalizes.
- **Hands-free:** select 3, 5, 7, or 30 seconds, 1 minute, or **Custom** (1–300
  seconds), then tap the shutter. Recording stops automatically. Tap again to
  stop early. Timers start when the camera actually starts recording.
- Switch front/back cameras and change framing between clips. Each new reel
  defaults to Full, matching the phone screen. The first clip sets the output
  canvas; other aspect ratios retain their crop and fit inside it with padding.
- Undo removes the last clip from the current reel. Preview reel combines the
  clips in order with matching audio, then offers playback and Save reel.
- Saving writes to the existing AURA/Videos gallery album. Original captures
  and saved reels use the existing background upload queue, with no upload UI.

The session stays editable while this screen is open, including after app
backgrounding and preview/export errors. Leaving asks before discarding clips.
Drafts are not restored after process termination. Android background interruption
uses the existing CameraX disposal/recovery approach; other platforms stop the
recording before releasing the camera. All capture is locked to portrait device
orientation; landscape output is available through the aspect ratio picker.

Reel shares saved hands-free settings with the main camera and Layout.
Aspect, flash and hands-free live in the right-side tool column; the bottom
area contains clip durations, recording, undo and a full-width preview action.
A tap on an active hold-mode shutter pauses a hands-free recording.

Hands-free palm/voice/gesture controls are described in [hands-free.md](hands-free.md).

## Validation

`test/reel_session_test.dart` covers deadline timing, early release during camera
startup, duplicate stop requests, failure recovery, and custom duration bounds.
`test/reel_camera_ui_test.dart` uses a fake camera to exercise hold/timed capture,
front/back switching, and right-side controls within the 3:4 frame on a 320×640 screen at 1.6× text size.
`integration_test/reel_export_test.dart` uses synthetic media on Android to verify
single/multiple clips, mixed framing, silent/mixed audio, dimensions, and duration.
