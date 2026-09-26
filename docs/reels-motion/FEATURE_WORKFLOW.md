# Reels Motion Editor — feature workflow

The AURA Reels Motion Editor is built one registry feature at a time, with a
human device test between every feature. `AURA_REELS_MOTION_EDITOR_CODEX_PLAN_V2.md`
is the technical reference for *what* each feature must eventually do. This
document is the process contract for *how* features are started, handed over,
and stopped. The plan describes the finished product; it does not authorize
implementing more than the one currently named feature.

## One active feature

Exactly one registry row from [the registry](#feature-branch-registry) is active
at a time. A milestone (R0–R6 in the plan) is not a feature; a single registry
row is.

Before editing, the implementer states:

- Active feature ID and name.
- Exact feature branch.
- Starting branch and commit SHA.
- Included work.
- Explicit exclusions.
- Current-feature test and acceptance criteria.

Work then stops at the handoff. None of the following authorizes starting the
next feature: the implementation looking finished, automated tests passing,
remaining time or context, the next task looking easy, the plan saying to
complete all phases, or an earlier "finish end to end" instruction.

## Revised operating mode (26 September 2026)

The owner has since authorized continuous, autonomous execution: implement a
feature, run the available checks, then commit, push, and open a pull request
without waiting for a manual git step. The one-feature-per-branch registry, the
scope discipline, and the preserved-behavior rules all still apply — what changed
is who performs the git operations, and that work no longer halts between
features.

Two gates survive this change, because they are physical rather than procedural:

- **Device verification.** The owner's instruction conditions push and merge on
  successful real-device results. A cloud container has no `adb`, no Android SDK,
  and no USB passthrough, so device tests and APK builds cannot run there. Where
  they cannot run they are reported `NOT RUN` — never assumed, and never
  described as passed. Running them requires a session on the machine the phone
  is attached to.
- **Merge to `main`.** A branch whose device verification never ran is pushed and
  raised as a pull request, but not merged: merging is hard to reverse and the
  owner's own gate for it is unmet. The owner merges, or explicitly authorizes
  merging without device evidence.

## Git ownership

Under the revised operating mode above, the implementer stages, commits, pushes,
and opens pull requests for the active feature branch. Merging to `main` stays
with the owner unless device verification actually ran and passed.

The implementer still never rewrites shared history or destroys work: no
`commit --amend` on a pushed commit, no force-push, no `reset --hard`, no
`stash`, no `clean`, no forced switch, no branch deletion, and no change to
remotes. Unrelated work in the tree is preserved, never discarded to make a
commit tidy.

Before creating or switching a branch, verify: current branch and HEAD, staged /
unstaged / untracked files, a clean worktree apart from ignored build output, and
that HEAD is not detached, conflicted, or on an unexpected commit. A dirty or
unexpected state stops the work; it is reported, never repaired.

Each feature's changes are committed on its own registry branch and pushed.

## Branching from an accepted checkpoint

Only the active feature branch is created. Later branches are not pre-created.

F00 branches from the current clean, named branch's HEAD, recording its actual
name and SHA rather than assuming `main` or `develop`. Every later feature
branches from the previous feature's explicitly accepted, manually committed
checkpoint, unless the owner authorizes a different integration base.

The sequence is cumulative: a later branch carries the accepted earlier
capabilities, and its new changes belong only to the current feature. There are
no per-feature copies of the application in separate folders.

Starting the next branch requires all of:

1. The owner's explicit real-device acceptance of the previous feature.
2. The owner's confirmation that it was manually committed and pushed.
3. The accepted commit / base SHA.
4. A clean worktree.
5. Explicit authorization naming the next feature.

Remote push status is taken as owner-confirmed; it is not verified by pushing or
fetching. An existing expected feature branch is reused only when its base and
history match the recorded feature — never reset, and never renamed to dodge a
conflict.

## Scope discipline

A feature covers its required logic, the relevant UI, validation,
preview/export behavior, tests, and documentation — and nothing else. Not
allowed: a second feature smuggled in as "foundation work", future-feature
models, empty controls, unused dependencies or folders, speculative
architecture rewrites, opportunistic unrelated fixes, or preparing later
features through background workers or sub-agents.

Reading broader code for compatibility is expected. Implementing broader scope
is not.

Correctness is not deferred to the hardening features: every feature must
already work through its relevant preview/export path and preserve existing
behavior before handoff.

If a feature needs an unaccepted prerequisite or a substantial out-of-scope
redesign, the implementer reports `BLOCKED_SCOPE` with the missing dependency
and the smallest proposed change, then stops. The prerequisite is not
implemented automatically.

### Preserved behavior

These must keep working across every feature: the existing theme; the capture
lifecycle; Hold and hands-free behavior (see [hands-free.md](../hands-free.md));
Full as the reel default; portrait device orientation; original recorded audio;
the `Pictures/AURA/Videos` album; and the background upload queue with no upload
UI (see [uploads-and-android.md](../uploads-and-android.md)).

### Permanently out of scope for this sequence

Music import, audio extraction, waveforms, song pickers, soundtrack lanes, new
mixing or ducking systems, voiceovers, and beat detection. No placeholder
models, pickers, controls, or dependencies for them either. Reaching the last
visual feature does not authorize music work; that belongs to a separate later
branch and design.

Beat Punch (F16) is a manually placed visual marker and introduces no audio
analysis.

## Gate lifecycle

```text
NOT_STARTED → IN_PROGRESS → READY_FOR_DEVICE_TEST
                                   │
         owner reports failure ────┤
                                   ▼
                     FIXING_CURRENT_FEATURE → READY_FOR_DEVICE_TEST
                                   │
         owner approves ───────────┤
                                   ▼
                     DEVICE_ACCEPTED → WAITING_FOR_MANUAL_GIT
```

A reported failure is fixed on the **same** branch; checks are rerun, the
candidate is rebuilt, and work stops again. The next feature does not start
while the owner is testing or reporting fixes.

Device acceptance alone does not authorize the next feature. Any implementation
change after acceptance invalidates that candidate's acceptance: rebuild and
hand it back.

`READY_FOR_DEVICE_TEST` and `WAITING_FOR_MANUAL_GIT` both mean *remain stopped*
unless the owner's current message explicitly authorizes a fix, a device action,
or a named next feature. "Okay", "looks good", "continue", silence, and a
checked plan item are not authorizations. Ambiguous messages get a request for
the missing gate information and nothing else. Approval examples quoted in any
document are examples, never live authorizations.

### Authorization formats

Repair:

```text
FIX F11 ONLY.
Device test failed: <issue>.
```

Next feature:

```text
APPROVE F11.
DEVICE_TEST: PASS — <device and build tested>.
MANUAL_GIT: COMMITTED_AND_PUSHED.
ACCEPTED_COMMIT: <actual SHA>.
START F12 ONLY.
BASE: <accepted SHA or explicitly approved integration commit>.
```

## Testing and handoff

Run the available regression suite plus the new current-feature tests. For
export-affecting features, validate rendered output where the environment
permits — widget state alone is not proof of correct export. Failures caused by
the current feature are fixed within its scope; pre-existing failures are
identified separately. Tests are never weakened, and unavailable checks are
never reported as passed.

Build a testable APK when supported, reporting the actual build command, build
mode, artifact path, APK SHA-256, base HEAD, and a summary of the uncommitted
source changes included in the build. An uncommitted build is never labelled by
HEAD alone. Signing secrets and release configuration are not changed to force a
build.

Every started feature carries a focused real-device checklist: actions,
expected behavior, failure and cancellation cases, preview/export comparison
where applicable, capture/save regression checks, and the applicable 4 GB device
performance checks. The owner performs manual acceptance. Installing,
uninstalling, clearing app data, and intrusive device tests require the owner's
explicit authorization. A successful build, analyzer run, or automated device
test does not replace acceptance.

The handoff reports: feature ID/name, branch, starting commit; implemented
changes and exact changed/new files; commands with PASS / FAIL / NOT RUN;
build details or the precise blocker; the device checklist; remaining
limitations and exclusions; a suggested commit message as plain text; the
current gate state; and the next feature as reference only.

It ends with one of:

```text
STOPPED — Fxx — AWAITING YOUR DEVICE TEST.
NO GIT ADD/COMMIT/PUSH PERFORMED.
```

```text
STOPPED — Fxx — BLOCKED: <specific reason>.
NO NEXT FEATURE STARTED.
```

Nothing claims accepted, production-ready, fully verified, or complete without
the corresponding evidence.

## Records

| Path | Contents |
| --- | --- |
| `docs/reels-motion/FEATURE_WORKFLOW.md` | This process contract |
| `docs/reels-motion/STATUS.md` | The active-feature status record |
| `docs/reels-motion/AUDIT.md` | F00 repository audit and gap analysis |
| `docs/reels-motion/BASELINE.md` | F00 baseline check commands and results |
| `docs/reels-motion/features/<feature-id>.md` | One handoff per started feature |

Each feature handoff records the feature, branch and base; allowed scope;
changed files; test results; build identity; the device checklist; blockers; and
the current gate state. No scaffolding is generated for features that have not
been authorized.

At the start of a new session, or after context restoration, read
`FEATURE_WORKFLOW.md` and `STATUS.md` before editing anything.

## Feature branch registry

Each row is a separate authorization, implementation, and device-review cycle.

| ID | Branch | Feature boundary |
| --- | --- | --- |
| F00 | `chore/reels-00-audit-baseline` | Repository audit, existing tests, baseline, workflow documents; no application changes |
| F01 | `feature/reels-01-project-history` | Minimal editable project, stable IDs, asset ownership, undo/redo |
| F02 | `feature/reels-02-native-render-baseline` | Shared preview/export plan, native surface lifecycle, existing 1× clips |
| F03 | `feature/reels-03-clip-timeline` | Lazy filmstrip, arbitrary clip selection, playhead and scrubbing |
| F04 | `feature/reels-04-clip-trim` | Trimming, fine timing, original-audio and export correctness |
| F05 | `feature/reels-05-clip-split` | Non-destructive splitting and correct instance ownership |
| F06 | `feature/reels-06-clip-reorder` | Clip reordering and timeline updates |
| F07 | `feature/reels-07-clip-remove` | Remove any clip, undo removal, safe asset retention |
| F08 | `feature/reels-08-video-import` | Local video import, validation and cancellation |
| F09 | `feature/reels-09-image-clips` | Imported images as timed image cards; no motion yet |
| F10 | `feature/reels-10-clip-replace` | Transactional replacement from the gallery |
| F11 | `feature/reels-11-clip-rerecord` | Re-record any selected clip, review, accept/cancel and undo |
| F12 | `feature/reels-12-crop-reframe` | Static crop, positioning, fit/fill and orientation |
| F13 | `feature/reels-13-project-canvas` | Project-wide canvas/aspect changes |
| F14 | `feature/reels-14-reel-cover` | Composed-frame and imported covers, separate from playback |
| F15 | `feature/reels-15-durable-drafts` | Atomic drafts, relaunch recovery and safe cleanup |
| F16 | `feature/reels-16-tap-to-direct` | Five presets, focal point, duration/strength and edge protection |
| F17 | `feature/reels-17-custom-motion-paths` | Start/middle/end compositions, travel geometry and reverse |
| F18 | `feature/reels-18-custom-easing` | Timing curves and precise animation controls |
| F19 | `feature/reels-19-linked-motion` | Pairwise continuity between adjacent clips |
| F20 | `feature/reels-20-constant-speed` | Constant-speed retiming and original-sound policy |
| F21 | `feature/reels-21-speed-ramps` | Speed ramps and consistent source/output mapping |
| F22 | `feature/reels-22-graphic-layers` | Timed image/shape overlays and static layer controls |
| F23 | `feature/reels-23-video-overlay` | Bounded additional video input; overlay audio disabled |
| F24 | `feature/reels-24-layer-animation` | Layer-property animation using shared clocks/easing |
| F25 | `feature/reels-25-basic-masks` | Rectangle/ellipse masks, feather and invert |
| F26 | `feature/reels-26-custom-masks` | Editable mask paths and mask-transform animation |
| F27 | `feature/reels-27-motion-blur` | Transform-velocity blur and resource limits |
| F28 | `feature/reels-28-text-layers` | Editable static text and shared native typography |
| F29 | `feature/reels-29-text-animators` | Whole-text, word and shaped-character animation |
| F30 | `feature/reels-30-text-travel-path` | Move a text object along an editable path |
| F31 | `feature/reels-31-text-on-path` | Arrange shaped text along a curve |
| F32 | `feature/reels-32-capture-editor-polish` | Focused capture/editor UX, theme and accessibility polish |
| F33 | `perf/reels-33-4gb-validation` | Measured 4 GB device optimization and lifecycle stress validation |
| F34 | `fix/reels-34-export-publication` | Cross-feature export, cancellation/retry and gallery/upload validation |

Advanced native capability checks belong inside the corresponding authorized
feature branch, before that feature's production UI. F00 is audit,
documentation, and baseline validation only. F02 proves the existing 1×
preview/export path; it does not implement masks, text, layered video, or
retiming.
