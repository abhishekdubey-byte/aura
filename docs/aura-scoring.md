# Aura scoring, version 2

Aura is a deterministic photo game. Its thresholds are product rules, not a
validated measure of beauty, identity, gender, or personal worth.

## Caption wording

The engine produces neutral phrases. Settings offers Neutral, Masculine, and
Feminine wording; Neutral is the default even when a profile has a gender.
The result screen can override the style for the current photo and recompose
the original image without changing the score or running the detectors again.
This avoids treating the account owner's profile as the identity of somebody
in an uploaded photo. The previous face/hair gender heuristic was removed.

## Progression and quality gates

The weighted quality of measured components is raised to the sixteenth power
before mapping it to 101–99,999,999 points. Component points are apportioned
after calibration and sum exactly to the displayed total.

Before a photo can reach one million, it must pass eight checks: lighting,
focus, shadow/highlight detail, tonal detail, a clear person, framing, style,
and at least four strong categories with twelve measured components.

Ten million additionally requires exceptional exposure and detail, strong
styling/framing, and five exceptional categories with sixteen components.
Both selfies and full-body photos can qualify. Passing every gate opens the
range; it does not automatically award the maximum.

Very poor exposure or severe blur limits the score below 10,000; dim or weak
detail limits it below 100,000. Failing another million-tier check limits it
below one million. A scaled ceiling avoids assigning every failed photo the
same capped score. Exact numeric thresholds live in `score_calibration.dart`.

NSFW model output is informational and awards no points. Caption style also
has no effect on points. Outfits, pose and photographic quality use the same
rules for every person.

## Repeat-photo matching and migration

Only version 2 scores can be restored from local memory. Near-identical photos
must also have matching quality-gate results and similar brightness, clipping,
and focus measurements. A blurred thumbnail cannot borrow an earlier clear
photo's score. Original images are always used for pixel measurements; the
brightened detector input does not earn exposure points.

## Validation

`test/aura_scoring_test.dart` covers neutral and selected wording, dark and
overexposed photos, blur and clipping, multi-check thresholds, attainable high
scores for selfies/full-body images, deterministic arithmetic, duplicate labels,
cache migration, quality changes during reuse, and persisted style settings.
Fixtures prove the rules and reachability, not a real-world percentile. Further
calibration should use consented, non-explicit photos across varied lighting,
camera devices, outfits and poses.
