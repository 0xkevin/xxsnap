# Direction-Locked Scroll Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make normal fixed-region pages continue sampling without false low-confidence pauses and let each scroll-capture session lock to either upward prepend or downward append based on its first reliable movement.

**Architecture:** The Qt-free C++ stitcher remains the source of truth for direction, matching, pending fixed-band evidence, resource accounting, and composition. It gains explicit pending-evidence and discarded-low-confidence results plus a permanent per-session direction; upward capture reuses the existing segment model by inserting small segment descriptors at the logical front while keeping pixel buffers immutable. The Objective-C++ bridge maps the new result contract, and the Swift session separates non-blocking match warnings from true paused states so activity can continue until the user finishes or cancels.

**Tech Stack:** C++20, Qt Test, Objective-C++, Swift/AppKit, XCTest, CMake, Xcode 26.

---

## File Map

- `core/include/snipory/core/scroll/ScrollStitchSession.h`: public append result meanings; no platform types.
- `core/src/scroll/ScrollStitchSession.cpp`: direction lock, symmetric strip extraction, pending evidence, segment ordering, resource accounting, preview/final composition.
- `core/tests/TestScrollStitchSession.cpp`: deterministic document fixtures and pixel-exact direction/pending/review/resource tests.
- `platforms/mac/Sources/Bridge/ScrollCaptureBridge.h`: Swift-visible append-kind enum.
- `platforms/mac/Sources/Bridge/ScrollCaptureBridge.mm`: exhaustive C++ to Objective-C mapping.
- `platforms/mac/Tests/ScrollCaptureBridgeTests.swift`: real `NSImage` upward/downward mapping and fixed-evidence tests.
- `platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift`: continuous sampling and warning events; only capture/resource failures pause.
- `platforms/mac/Sources/App/CaptureCoordinator.swift`: non-blocking warning presentation while the overlay remains capturing.
- `platforms/mac/Tests/ScrollCaptureSessionTests.swift`: sampling, warning, recovery, and real-session lifecycle tests.
- `platforms/mac/Tests/SelectionToolbarStateTests.swift`: Coordinator warning/overlay integration.
- `platforms/mac/Tests/manual-capture-checklist.md`: upward-first/downward-first acceptance rows.
- `docs/requirements/xxsnap-mac-feature-requirements.md`: implemented direction lock and low-confidence behavior.
- `docs/annotation-tools-user-guide.md`: user workflow and direction-lock explanation.

---

### Task 1: Separate pending evidence from discarded low confidence

**Files:**
- Modify: `core/include/snipory/core/scroll/ScrollStitchSession.h`
- Modify: `core/src/scroll/ScrollStitchSession.cpp`
- Modify: `core/tests/TestScrollStitchSession.cpp`

- [ ] **Step 1: Write failing result-contract tests**

Replace the fixed-band expectations that currently call ordinary confirmation frames low confidence, and add a genuinely unrelated-frame assertion:

```cpp
void TestScrollStitchSession::fixedBandConfirmationIsAwaitingEvidence()
{
    auto config = defaultConfig();
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    config.fixedBandConfirmationMovements = 3;
    ScrollStitchSession session(config);

    QCOMPARE(session.append(documentViewport(0, true)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(documentViewport(40, true)).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(documentViewport(80, true)).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(documentViewport(120, true)).kind, AppendKind::AcceptedAppend);
}

void TestScrollStitchSession::unrelatedFrameIsDiscardedAsLowConfidence()
{
    ScrollStitchSession session(defaultConfig());
    QCOMPARE(session.append(documentViewport(0)).kind, AppendKind::AcceptedInitial);
    ScrollFrame unrelated(120, 140);
    std::fill(unrelated.pixels.begin(), unrelated.pixels.end(), 127);

    QCOMPARE(session.append(unrelated).kind, AppendKind::LowConfidenceDiscarded);
    QCOMPARE(session.outputHeight(), 140);
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake --build build --target test_scroll_stitch_session
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build/core/test_scroll_stitch_session fixedBandConfirmationIsAwaitingEvidence unrelatedFrameIsDiscardedAsLowConfidence
```

Expected: compilation fails because `AwaitingEvidence` and `LowConfidenceDiscarded` do not exist.

- [ ] **Step 3: Introduce the explicit core results**

Change the enum/default in `ScrollStitchSession.h`:

```cpp
enum class AppendKind
{
    AcceptedInitial,
    AcceptedAppend,
    DuplicateDiscarded,
    ReviewDiscarded,
    AwaitingEvidence,
    LowConfidenceDiscarded,
    ResourceLimit,
};

struct AppendResult final
{
    AppendKind kind = AppendKind::LowConfidenceDiscarded;
    int appendedHeight = 0;
    int outputHeight = 0;
    double confidence = 0;
};
```

In the `safePrefix == 0U` branch, set the result before returning:

```cpp
result.kind = AppendKind::AwaitingEvidence;
result.outputHeight = implementation_->height;
return result;
```

Leave genuinely unreliable/no-advance paths on the default `LowConfidenceDiscarded` result. Resource overflow must remain `ResourceLimit`; the bridge continues rejecting malformed images before they enter the core.

- [ ] **Step 4: Update all core test expectations and run the full core target**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake --build build --target test_scroll_stitch_session
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build/core/test_scroll_stitch_session
```

Expected: all scroll-stitch tests pass, and every old `PausedLowConfidence` assertion has been intentionally assigned to one of the two new meanings.

- [ ] **Step 5: Commit**

```bash
git add core/include/snipory/core/scroll/ScrollStitchSession.h core/src/scroll/ScrollStitchSession.cpp core/tests/TestScrollStitchSession.cpp
git commit -m "fix(core): distinguish pending scroll evidence from low confidence"
```

---

### Task 2: Lock the first reliable direction and prepend upward strips

**Files:**
- Modify: `core/src/scroll/ScrollStitchSession.cpp`
- Modify: `core/tests/TestScrollStitchSession.cpp`

- [ ] **Step 1: Add failing downward/upward direction tests without fixed bands**

Add fixtures that encode unique document rows and tests with fixed-band detection disabled:

```cpp
void TestScrollStitchSession::firstReliableDownwardMovementLocksAppendDirection()
{
    auto config = defaultConfig();
    config.enableFixedBandDetection = false;
    ScrollStitchSession session(config);
    const auto frames = makeDocumentViewports({120, 180, 120, 240});

    QCOMPARE(session.append(frames[0]).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(frames[1]).kind, AppendKind::AcceptedAppend);
    QCOMPARE(session.append(frames[2]).kind, AppendKind::ReviewDiscarded);
    QCOMPARE(session.append(frames[3]).kind, AppendKind::AcceptedAppend);
    QCOMPARE(session.finalize().height, 260);
}

void TestScrollStitchSession::firstReliableUpwardMovementLocksPrependDirection()
{
    auto config = defaultConfig();
    config.enableFixedBandDetection = false;
    ScrollStitchSession session(config);
    const auto frames = makeDocumentViewports({120, 60, 0, 60, 180});

    QCOMPARE(session.append(frames[0]).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(frames[1]).kind, AppendKind::AcceptedAppend);
    QCOMPARE(session.append(frames[2]).kind, AppendKind::AcceptedAppend);
    QCOMPARE(session.append(frames[3]).kind, AppendKind::ReviewDiscarded);
    QCOMPARE(session.append(frames[4]).kind, AppendKind::ReviewDiscarded);

    const auto final = session.finalize();
    QCOMPARE(final.height, 260);
    QCOMPARE(blueAt(final, 37, 0), documentPixel(37, 0));
    QCOMPARE(blueAt(final, 37, 119), documentPixel(37, 119));
    QCOMPARE(blueAt(final, 37, 120), documentPixel(37, 120));
}
```

- [ ] **Step 2: Run the two tests and verify RED**

Run the two named Qt tests. Expected: the upward frame is `ReviewDiscarded` and output never grows above the seed.

- [ ] **Step 3: Add an internal direction and direction-aware overlap selection**

Inside `Implementation`, add:

```cpp
enum class Direction { Undetermined, Down, Up };
Direction direction = Direction::Undetermined;
```

Replace the one-way overlap selection with a helper returning one candidate only when the orientation is reliable and consistent with the lock:

```cpp
struct DirectionalMatch final {
    Direction direction = Direction::Undetermined;
    OverlapResult overlap;
};

DirectionalMatch directionalMatch(
    const ScrollFrame& frontier,
    const ScrollFrame& frame,
    const OverlapConfig& config) const;
```

Required behavior:

```cpp
// Undetermined: forward-only reliable => Down; reverse-only reliable => Up.
// Both/neither reliable => Undetermined and LowConfidenceDiscarded.
// Locked: only the locked orientation may mutate; the reliable opposite is review.
```

Keep `anchors.push_back()` in capture chronology so the newest accepted viewport remains the last anchor regardless of document direction.

- [ ] **Step 4: Make strip extraction and segment insertion direction-aware**

Use one immutable segment descriptor for both paths:

```cpp
const int firstRow = direction == Direction::Down
    ? frame.height - excludedBottom - appendedHeight
    : excludedTop;

Implementation::Segment segment{storedSegment, 0, appendedHeight};
if (direction == Direction::Down) {
    implementation_->segments.push_back(std::move(segment));
} else {
    implementation_->segments.insert(implementation_->segments.begin(), std::move(segment));
}
```

Set `direction` only immediately before the first successful output mutation. Never change it for duplicate, review, awaiting-evidence, low-confidence, or resource-limit results.

- [ ] **Step 5: Run direction, duplicate, preview, final, and resource tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build/core/test_scroll_stitch_session firstReliableDownwardMovementLocksAppendDirection firstReliableUpwardMovementLocksPrependDirection exactDuplicateDoesNotMutateOutput reverseReviewDoesNotMutateAcceptedContent previewDownsamplesWithoutMutatingFinalImage
```

Expected: all pass with natural top-to-bottom pixels.

- [ ] **Step 6: Commit**

```bash
git add core/src/scroll/ScrollStitchSession.cpp core/tests/TestScrollStitchSession.cpp
git commit -m "feat(core): lock and compose scroll capture direction"
```

---

### Task 3: Make fixed bands, pending runs, scrollbar state, and resources symmetric

**Files:**
- Modify: `core/src/scroll/ScrollStitchSession.cpp`
- Modify: `core/tests/TestScrollStitchSession.cpp`

- [ ] **Step 1: Add failing upward fixed-band and atomic-resource tests**

Add an upward counterpart to the existing fixed-header/footer fixture and a configuration with a byte limit that rejects the next prepend:

```cpp
void TestScrollStitchSession::upwardFixedBandsAreRetainedOnceAfterPendingEvidence();
void TestScrollStitchSession::rejectedUpwardPrependLeavesPixelsAndHeightUnchanged();
void TestScrollStitchSession::upwardPreviewUsesNaturalDocumentOrder();
```

Assertions must cover:

```cpp
QCOMPARE(first.kind, AppendKind::AwaitingEvidence);
QCOMPARE(second.kind, AppendKind::AwaitingEvidence);
QCOMPARE(third.kind, AppendKind::AcceptedAppend);
QCOMPARE(session.finalize().pixels, expectedNaturalOrder.pixels);
QCOMPARE(afterRejected.height, before.height);
QCOMPARE(afterRejected.pixels, before.pixels);
```

- [ ] **Step 2: Run the new tests and verify RED**

Expected: pending extraction still assumes the bottom edge, and/or resource accounting mutates downward-only state.

- [ ] **Step 3: Carry direction through pending movement evidence**

Extend pending entries:

```cpp
struct PendingMovement final
{
    std::shared_ptr<const ScrollFrame> frame;
    Fingerprint fingerprint;
    Direction direction = Direction::Undetermined;
    int advance = 0;
    double confidence = 0.0;
    std::size_t persistentBytes = 0U;
    BandDecision topDecision = BandDecision::Ordinary;
    BandDecision bottomDecision = BandDecision::Ordinary;
};
```

Reject a pending run whose candidate direction changes before confirmation; clear only that pending run, not accepted output. For an upward candidate, evaluate overlap in `frame -> frontier` orientation while stationary-band evidence continues comparing the same two viewport images.

- [ ] **Step 4: Extract and flush pending strips symmetrically**

Replace the bottom-only `prepareMovement` inputs with both band decisions:

```cpp
const bool excludeTop = topDecision == BandDecision::Fixed;
const bool excludeBottom = bottomDecision == BandDecision::Fixed;
const int firstRow = movement.direction == Direction::Down
    ? movement.frame->height - movement.advance - (excludeBottom ? bottomHeight : 0)
    : (excludeTop ? topHeight : 0);
```

Prepare pending movements in capture chronology. Push downward descriptors at the back; insert each upward descriptor at the front. Because progressively earlier upward strips arrive later, repeated front insertion creates natural document order without reversing pixel rows.

Update the frontier, anchors, scrollbar observation, persistent byte counts, and fixed-band confirmation only after all segments for `safePrefix` have been prepared successfully.

- [ ] **Step 5: Run the complete scroll core tests**

Run the full `test_scroll_stitch_session` and `test_vertical_overlap_matcher` executables. Expected: all pass, including all prior downward fixed-band, scrollbar, memory-budget, preview, and review tests.

- [ ] **Step 6: Commit**

```bash
git add core/src/scroll/ScrollStitchSession.cpp core/tests/TestScrollStitchSession.cpp
git commit -m "fix(core): preserve fixed regions in either scroll direction"
```

---

### Task 4: Map the new result contract through the macOS bridge

**Files:**
- Modify: `platforms/mac/Sources/Bridge/ScrollCaptureBridge.h`
- Modify: `platforms/mac/Sources/Bridge/ScrollCaptureBridge.mm`
- Modify: `platforms/mac/Tests/ScrollCaptureBridgeTests.swift`
- Modify: `platforms/mac/Tests/ScrollCaptureTestSupport.swift`

- [ ] **Step 1: Write failing bridge mapping and real-image direction tests**

Change the test enum matrix to expect:

```swift
[
    .acceptedInitial,
    .acceptedAppend,
    .duplicateDiscarded,
    .reviewDiscarded,
    .awaitingEvidence,
    .lowConfidenceDiscarded,
    .resourceLimit,
]
```

Add real `NSImage` sequences generated from one uniquely textured document:

```swift
func testFirstReliableUpwardMovementPrependsInNaturalOrder() throws
func testFixedRegionEvidenceMapsAsAwaitingWithoutLosingFinalPixels() throws
```

The upward test must compare final pixel rows, not only image height or enum kinds.

- [ ] **Step 2: Run bridge tests and verify RED**

Expected: Swift enum cases are missing and upward final pixels equal only the seed.

- [ ] **Step 3: Update the Objective-C enum and exhaustive switch**

Use:

```objc
typedef NS_ENUM(NSInteger, ScrollCaptureAppendKind) {
    ScrollCaptureAppendKindAcceptedInitial,
    ScrollCaptureAppendKindAcceptedAppend,
    ScrollCaptureAppendKindDuplicateDiscarded,
    ScrollCaptureAppendKindReviewDiscarded,
    ScrollCaptureAppendKindAwaitingEvidence,
    ScrollCaptureAppendKindLowConfidenceDiscarded,
    ScrollCaptureAppendKindResourceLimit,
};
```

Map every C++ case explicitly in `bridgeKind`; do not use a default that could hide a future result kind.

- [ ] **Step 4: Run the complete bridge suite**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/ScrollCaptureBridgeTests
```

Expected: all bridge tests pass at 1x and 2x.

- [ ] **Step 5: Commit**

```bash
git add platforms/mac/Sources/Bridge/ScrollCaptureBridge.h platforms/mac/Sources/Bridge/ScrollCaptureBridge.mm platforms/mac/Tests/ScrollCaptureBridgeTests.swift platforms/mac/Tests/ScrollCaptureTestSupport.swift
git commit -m "feat(mac): bridge direction-aware scroll results"
```

---

### Task 5: Keep Swift sampling active and present low confidence as a warning

**Files:**
- Modify: `platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift`
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift`
- Modify: `platforms/mac/Tests/ScrollCaptureSessionTests.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Replace paused-low-confidence tests with continuous-warning tests**

Add these focused behaviors:

```swift
func testAwaitingEvidenceKeepsCapturingAndSamplingArmed() async throws
func testLowConfidenceWarnsWithoutPausingAndAcceptedAppendClearsWarning() async throws
func testRepeatedLowConfidenceMayIdleTimerAndNewActivityRearms() async throws
func testResourceLimitAndCaptureFailureRemainPaused() async throws
func testCoordinatorShowsLowConfidenceWarningWithoutPausingOverlay() async throws
```

Key assertions:

```swift
XCTAssertEqual(session.state, .capturing)
XCTAssertTrue(session.isSamplingArmed)
XCTAssertEqual(presentation.warnings, [.lowConfidence, nil])
XCTAssertEqual(overlay.test_scrollCaptureState, .capturing)
XCTAssertEqual(presentation.test_warningText, localizedWarning)
```

- [ ] **Step 2: Run the named tests and verify RED**

Expected: the enum cases/warning update do not exist and the old session pauses/disarms on low confidence.

- [ ] **Step 3: Separate warning events from session state**

Remove `.lowConfidence` from `ScrollCapturePauseReason` and add:

```swift
enum ScrollCaptureMatchWarning: Equatable {
    case lowConfidence
}

enum ScrollCapturePresentationUpdate {
    case state(ScrollCaptureSessionState)
    case append(ScrollCaptureAppendUpdate)
    case preview(NSImage)
    case warning(ScrollCaptureMatchWarning?)
    case terminalCommand(ScrollCaptureTerminalCommand)
}
```

Update `recordScrollActivity()` to arm only from `.capturing`. Capture/resource/final-composition failures remain explicit paused states.

- [ ] **Step 4: Implement non-blocking result handling**

Use the following behavior in `handle`:

```swift
case .acceptedAppend:
    stabilityCount = 0
    _ = emit(.warning(nil), operationGeneration: operationGeneration, expectedState: .capturing)
    let preview = try stitcher.preview(maximumHeight: 1_200)
    _ = emit(.preview(preview), operationGeneration: operationGeneration, expectedState: .capturing)

case .awaitingEvidence:
    stabilityCount = 0
    // Keep the current sampling loop armed; no warning is required.

case .lowConfidenceDiscarded:
    stabilityCount += 1
    _ = emit(.warning(.lowConfidence), operationGeneration: operationGeneration, expectedState: .capturing)
    if stabilityCount >= stabilityThreshold { disarmSampling() }

case .duplicateDiscarded, .reviewDiscarded:
    stabilityCount += 1
    if stabilityCount >= stabilityThreshold { disarmSampling() }

case .resourceLimit:
    disarmSampling()
    _ = setState(.paused(.resourceLimit), operationGeneration: operationGeneration)
```

The next scroll event resets stability and re-arms the timer because state never left `.capturing`.

- [ ] **Step 5: Route warning updates without pausing the overlay**

In `CaptureCoordinator.receiveScrollCaptureUpdate`:

```swift
case .warning(.lowConfidence):
    overlay.setScrollCaptureCapturing()
    presentation.setWarning(l10n.text(.scrollCaptureLowConfidence))
case .warning(nil):
    presentation.clearWarning()
```

Keep `.state(.paused(.resourceLimit))` and `.state(.paused(.captureFailure))` on the existing paused overlay path. Update every exhaustive test switch for the new warning case.

- [ ] **Step 6: Run session and Coordinator suites**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/ScrollCaptureSessionTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testCoordinatorShowsLowConfidenceWarningWithoutPausingOverlay
```

Expected: all named tests pass; known number-control baselines are not part of the focused command.

- [ ] **Step 7: Commit**

```bash
git add platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift platforms/mac/Sources/App/CaptureCoordinator.swift platforms/mac/Tests/ScrollCaptureSessionTests.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "fix(mac): keep scroll matching active through low confidence"
```

---

### Task 6: Update durable product behavior and manual acceptance

**Files:**
- Modify: `docs/requirements/xxsnap-mac-feature-requirements.md`
- Modify: `docs/annotation-tools-user-guide.md`
- Modify: `platforms/mac/Tests/manual-capture-checklist.md`
- Modify: `docs/superpowers/specs/2026-07-11-scroll-capture-design.md`

- [ ] **Step 1: Correct the implemented direction boundary**

Replace “manual downward only / arbitrary direction deferred” with the exact locked-direction behavior:

```markdown
- The first reliably matched movement locks one capture direction for the session.
- Downward capture appends below the seed; upward capture prepends above it.
- Reversing after lock is review only and never changes direction or duplicates content.
- A new session is required to capture the opposite side of the seed.
```

- [ ] **Step 2: Correct low-confidence guidance**

Document that low-confidence content shows a warning but does not automatically pause the capture. Sampling may become idle after repeated unmatched/stable frames, and the next wheel/trackpad event resumes it. Only capture failure and the resource guard are blocking pauses.

- [ ] **Step 3: Extend the manual matrix**

Add distinct acceptance rows:

```markdown
| D3 | Same document, start in middle | Mouse/trackpad upward first | Direction locks upward; output prepends in natural order. | 待人工 |
| D4 | Same document, start in middle | Mouse/trackpad downward first | Direction locks downward; output appends in natural order. | 待人工 |
| D5 | Reverse after direction lock | Both | Reverse frames are review-only; lock and output remain unchanged. | 待人工 |
| D6 | Fixed header/footer confirmation | Both | No automatic low-confidence pause during evidence collection. | 待人工 |
```

- [ ] **Step 4: Check documentation consistency and commit**

Run:

```bash
rg -n "only.*down|向下滚动|任意方向.*延期|低置信.*暂停|PausedLowConfidence" docs platforms/mac/Tests/manual-capture-checklist.md
git diff --check
```

Resolve every stale statement in the four scoped documents, then commit:

```bash
git add -f docs/requirements/xxsnap-mac-feature-requirements.md docs/annotation-tools-user-guide.md docs/superpowers/specs/2026-07-11-scroll-capture-design.md platforms/mac/Tests/manual-capture-checklist.md
git commit -m "docs(mac): document direction-locked scroll capture"
```

---

### Task 7: Run final verification and restart the exact app

**Files:**
- Modify tests/implementation only if verification exposes a defect covered by this specification.
- Modify `docs/requirements/xxsnap-mac-feature-requirements.md` only if the recorded automated counts need refreshing.

- [ ] **Step 1: Run all shared-core tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake -S . -B build -DBUILD_TESTING=ON -DCMAKE_PREFIX_PATH="$(brew --prefix qtbase)"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake --build build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ctest --test-dir build --output-on-failure
```

Expected: 8/8 core tests pass.

- [ ] **Step 2: Run all direction-specific macOS tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/ScrollCaptureBridgeTests \
  -only-testing:xxsnapTests/ScrollCaptureSessionTests \
  -only-testing:xxsnapTests/ScrollCapturePresentationTests
```

Expected: all selected tests pass.

- [ ] **Step 3: Run the full macOS test target**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Expected: every new direction/warning test passes. Record the five existing number-control/status-icon failures separately if unchanged; do not weaken them or include them in this fix.

- [ ] **Step 4: Build and restart the current worktree app**

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
APP_PATH="$REPO_ROOT/build/xcode-derived/Build/Products/Debug/XxSnap.app"
APP_EXEC="$APP_PATH/Contents/MacOS/XxSnap"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived build
pkill -f "$APP_EXEC" || true
open -n "$APP_PATH"
pgrep -af "$APP_EXEC"
```

Expected: build succeeds and exactly one process runs from the current worktree path.

- [ ] **Step 5: Run final repository checks**

```bash
git diff --check
git status --short --branch
```

Expected: no whitespace errors and no uncommitted files.

---

## Requirement Coverage

| Requirement | Tasks |
| --- | --- |
| Fixed-band evidence does not cause false pause | 1, 5 |
| First reliable movement locks direction | 2, 3 |
| Upward prepend in natural document order | 2, 3, 4 |
| Reverse after lock is review only | 2, 3 |
| Low confidence warns and continues | 1, 4, 5 |
| Fixed bands, scrollbar crop, resources work both ways | 3 |
| Durable user behavior and acceptance matrix | 6 |
| Full build/test/runtime evidence | 7 |
