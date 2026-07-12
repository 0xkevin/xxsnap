# Scroll Capture Direction Lock and Continuous Matching Design

**Date:** 2026-07-12

**Status:** Approved for planning

## Problem

The first scroll-capture implementation has two related failures in normal use.

First, fixed-header and fixed-footer detection requires several consistent movement frames before it commits a band decision. The core currently reports those valid-but-pending frames as `PausedLowConfidence`. The macOS session interprets that result as an error, disarms sampling, changes the session to a paused state, and presents the user-facing low-confidence warning. A page with ordinary fixed chrome can therefore stop before the evidence needed to confirm that chrome is ever collected.

Second, the current stitcher only grows below the seed frame. Upward scrolling is classified exclusively as review, so a session that begins in the middle of a document cannot choose upward capture as its collection direction.

## Product Decisions

- The first reliable movement locks the session to one capture direction: upward or downward.
- A downward session appends below the seed. An upward session prepends above the seed.
- Once locked, scrolling in the opposite direction is review only, even if the user moves beyond the seed frame on that side.
- Exact repeats and frames mapping anywhere inside accepted content are discarded without changing output.
- Low-confidence matching never changes the session to an automatically paused state.
- The session may show a non-blocking low-confidence warning while it keeps accepting scroll activity and sampling.
- Fixed-band confirmation frames are normal pending evidence, not low-confidence failures.
- Capture failure and resource exhaustion retain their existing pause behavior. Finish and Cancel remain available.

## Direction Model

The shared core owns a direction state:

```text
Undetermined -> CapturingDown
Undetermined -> CapturingUp
```

The transition is permanent for the lifetime of the session.

For each frame while direction is undetermined, the matcher evaluates both orientations against the active frontier:

- `frontier -> frame` is a downward candidate.
- `frame -> frontier` is an upward candidate.

A direction may lock only when exactly one orientation has reliable positive vertical advance. If both orientations remain plausible or neither is reliable, the frame is ignored as low confidence and direction remains undetermined. Fixed-region evidence may hold reliable movement in a pending run; that run carries its candidate direction but does not lock or mutate visible output until the configured evidence requirement is met.

After direction lock:

- The locked orientation is the only orientation allowed to add pixels.
- A reliable match in the opposite orientation is review and is discarded.
- A fingerprint matching any accepted or pending viewport is a duplicate or review frame and is discarded.
- An ambiguous frame is ignored without clearing accepted content or changing the direction.

## Segment Storage and Composition

The initial frame remains the immutable seed segment.

The stitcher stores new segments relative to the seed:

- Downward segments are stored in output order after the seed.
- Upward segments are stored in discovery order as leading segments. Preview and final composition traverse them in reverse discovery order before the seed.

This avoids repeatedly moving an expanding image buffer. The natural final order is always:

```text
oldest accepted leading content
...
newest accepted leading content
seed frame
trailing content
...
```

Only one side grows in a direction-locked session, but composition supports both collections so the model remains explicit and testable.

For upward capture, the newly exposed strip is copied from the top content edge of the current frame. For downward capture, it continues to come from the bottom content edge. Confirmed fixed top/bottom bands and confirmed scrollbar crops are excluded symmetrically from matching and strip extraction. Viewport-fixed chrome is retained once using the existing seed-preservation rule; it is never copied into every new segment.

Resource accounting includes leading segments, trailing segments, pending frames, fingerprints, frontier storage, and preview/final composition exactly as it includes the current downward path. Reaching the accepted-byte limit does not partially mutate either side.

## Core Result Semantics

The append result must distinguish three cases that are currently conflated:

1. `AwaitingEvidence`: movement is reliable, but fixed-band or scrollbar evidence is not yet safe to commit. The core may retain bounded pending frames. The shell must continue sampling.
2. `LowConfidenceDiscarded`: no direction or seam is reliable enough to mutate output. The frame is discarded. The shell remains in capturing state and may show a warning.
3. `ResourceLimit`: no more persistent data may be accepted. The shell pauses with the existing resource-limit recovery path.

`AcceptedInitial`, `AcceptedAppend`, `DuplicateDiscarded`, and `ReviewDiscarded` retain their existing meanings.

## macOS Sampling and Presentation

`ScrollCaptureSession` remains in `.capturing` for `AwaitingEvidence` and `LowConfidenceDiscarded`.

- `AwaitingEvidence` resets neither direction evidence nor the sampling loop.
- `LowConfidenceDiscarded` publishes a non-blocking warning and keeps listening for activity.
- Repeated low-confidence frames may disarm the timer after the existing stability threshold to avoid sampling an idle or animated page forever, but they do not pause the session. The next wheel or trackpad event re-arms sampling immediately.
- `AcceptedAppend` clears the low-confidence warning, refreshes the preview, and continues sampling.
- Duplicate/review stability continues to stop the timer after the existing threshold without ending the session.
- Capture failures and resource limits still enter their explicit paused states.

The presentation controller separates warning visibility from capture phase. A low-confidence warning cannot disable Finish, Cancel, the passive toolbar, or later scroll-activity recovery.

## Error and Recovery Behavior

- Ambiguous or unrelated frames never mutate accepted pixels.
- Pending direction/fixed-band evidence is bounded by the existing resource guard.
- A failed pending run may be discarded without discarding already accepted leading or trailing segments.
- A capture error pauses and preserves the current preview.
- A resource-limit result pauses and allows Finish with all accepted content.
- Final composition failure retains the stitcher for the existing Retry Finish or Cancel behavior.

## Test Contract

### Shared core

- A fixed-header/footer page reports `AwaitingEvidence` for confirmation frames instead of low confidence, then accepts the run.
- A downward first movement locks downward, appends in order, and treats later upward movement as review.
- An upward first movement locks upward, prepends in natural document order, and treats later downward movement as review.
- Starting in the middle and capturing upward produces exact representative seam pixels above the unchanged seed.
- Exact duplicates and accepted-anchor review frames do not change height or pixels in either direction.
- Low-confidence frames do not mutate output or erase direction evidence; a later reliable frame recovers.
- Fixed bands and scrollbar cropping remain single-copy and symmetric in upward and downward modes.
- Resource failure before a prepend or append leaves output byte-for-byte unchanged.

### macOS bridge and session

- The bridge maps `AwaitingEvidence` and `LowConfidenceDiscarded` distinctly.
- Awaiting evidence never changes session state or disarms the sampler.
- Low confidence publishes a warning while state remains capturing.
- Consecutive low-confidence idle samples may stop the timer, and new scroll activity re-arms it.
- A subsequent accepted append clears the warning and refreshes the preview.
- Capture failure and resource-limit states retain their existing blocking recovery behavior.

### Product acceptance

- From the middle of the same long document, one session can lock upward and produce a correctly ordered topward long image.
- A separate session can lock downward and produce a correctly ordered bottomward long image.
- Reversing after lock only reviews accepted content and never changes the locked direction.
- Ordinary fixed headers or footers no longer trigger an automatic low-confidence pause during their confirmation frames.
- Repetitive or low-detail content may show a warning but scrolling can continue without restarting the capture.

## Explicit Non-Goals

- A single session does not grow both above and below the seed.
- The user does not manually choose direction before capture.
- Horizontal, diagonal, zoom-changing, rotated, or perspective-changing capture remains unsupported.
- Automatic target scrolling and automatic end-of-document detection remain deferred.
