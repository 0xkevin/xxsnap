# Scroll Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build manual vertical scrolling capture with adaptive sampling, duplicate-safe stitching, a tail-following preview, and a dedicated long-image editor that preserves existing annotations and output behavior.

**Architecture:** A Qt-free C++ scroll engine in `core/` owns deterministic frame classification, overlap estimation, fixed-region masking, scrollbar cropping, segment accumulation, and final composition. Objective-C++ bridges `NSImage` frames into that engine, while focused Swift controllers own macOS scroll activity, ScreenCaptureKit sampling, passive overlay controls, preview placement, session lifecycle, and the long-image editor.

**Tech Stack:** C++20, Qt Test for shared-core tests, Swift 5/AppKit, ScreenCaptureKit, Objective-C++, XCTest, CMake, Xcode.

---

## File Structure

### Shared core

- Create `core/include/snipory/core/scroll/ScrollFrame.h`: Qt-free BGRA frame and crop primitives shared by the engine and Objective-C++ bridge.
- Create `core/include/snipory/core/scroll/FrameFingerprint.h` and `core/src/scroll/FrameFingerprint.cpp`: downsampled fingerprints and fast frame-distance checks.
- Create `core/include/snipory/core/scroll/VerticalOverlapMatcher.h` and `core/src/scroll/VerticalOverlapMatcher.cpp`: vertical-only overlap candidates, confidence, fixed-band mask, and edge-scrollbar detection.
- Create `core/include/snipory/core/scroll/ScrollStitchSession.h` and `core/src/scroll/ScrollStitchSession.cpp`: immutable accepted-segment history, duplicate/review classification, resource accounting, preview composition, and final composition.
- Create `core/tests/TestFrameFingerprint.cpp`, `core/tests/TestVerticalOverlapMatcher.cpp`, and `core/tests/TestScrollStitchSession.cpp`: deterministic synthetic-frame and sequence tests.
- Modify `core/CMakeLists.txt`: compile the engine and register its tests.

### macOS bridge and session

- Create `platforms/mac/Sources/Bridge/ScrollCaptureBridge.h` and `platforms/mac/Sources/Bridge/ScrollCaptureBridge.mm`: convert `NSImage` to BGRA frames and expose append/finalize results to Swift.
- Modify `platforms/mac/Sources/Bridge/xxsnap-Bridging-Header.h`: import the scroll bridge.
- Create `platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift`: actor-isolated session state and adaptive sampler.
- Create `platforms/mac/Sources/ScrollCapture/ScrollActivityMonitor.swift`: event monitor that arms sampling without retaining global input state after capture.
- Create `platforms/mac/Sources/ScrollCapture/ScrollCapturePresentationController.swift`: passive capture chrome, toolbar control panel, live preview panel, placement, and warning state.
- Create `platforms/mac/Sources/ScrollCapture/LongImageEditorWindowController.swift`: scrollable image viewport, visible-slice annotation overlay, viewport/image coordinate conversion, and completion actions.
- Create `platforms/mac/Tests/ScrollCaptureTestSupport.swift`, `platforms/mac/Tests/ScrollCaptureSessionTests.swift`, `platforms/mac/Tests/ScrollCapturePresentationTests.swift`, and `platforms/mac/Tests/LongImageEditorTests.swift`.
- Modify `platforms/mac/xxsnap.xcodeproj/project.pbxproj`: add the new Swift, Objective-C++, C++, and test sources plus the core include path.

### Existing macOS integration

- Modify `platforms/mac/Sources/Capture/ScreenCaptureService.swift`: conform to a small region-capture protocol used by the session.
- Modify `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`: expose scroll-capture seed data and toolbar geometry, render a passive capture state, and retain/restore first-screen annotations.
- Modify `platforms/mac/Sources/App/CaptureCoordinator.swift`: own the scroll session, presentation controller, completed image, editor, and output fallbacks.
- Modify `platforms/mac/Sources/App/PinnedImageWindowController.swift`: accept a complete long image with a safe initial fit while preserving zoom and movement behavior.
- Modify `platforms/mac/Sources/App/AppSettings.swift`: add localized capture-state and recovery text.
- Modify `platforms/mac/Tests/SelectionToolbarStateTests.swift`, `platforms/mac/Tests/ScreenCaptureServiceTests.swift`, and `platforms/mac/Tests/manual-capture-checklist.md`.
- Modify `docs/requirements/xxsnap-mac-feature-requirements.md` and `docs/annotation-tools-user-guide.md` after the behavior is green.

---

### Task 1: Add Qt-free scroll frames and fast fingerprints

**Files:**
- Create: `core/include/snipory/core/scroll/ScrollFrame.h`
- Create: `core/include/snipory/core/scroll/FrameFingerprint.h`
- Create: `core/src/scroll/FrameFingerprint.cpp`
- Create: `core/tests/TestFrameFingerprint.cpp`
- Modify: `core/CMakeLists.txt`

- [ ] **Step 1: Write failing fingerprint tests**

Add tests covering identical frames, a one-pixel perturbation, and a visibly different frame. Use deterministic frame helpers in the test file:

```cpp
static snipory::core::scroll::ScrollFrame solidFrame(int width, int height, std::uint8_t value)
{
    snipory::core::scroll::ScrollFrame frame(width, height);
    std::fill(frame.pixels.begin(), frame.pixels.end(), value);
    return frame;
}

void identicalFramesHaveZeroDistance()
{
    const auto frame = solidFrame(64, 48, 40);
    const auto left = FrameFingerprint::make(frame, FingerprintSize{16, 12});
    const auto right = FrameFingerprint::make(frame, FingerprintSize{16, 12});
    const auto distance = FrameFingerprint::meanAbsoluteDistance(left, right);
    QVERIFY(distance.has_value());
    QCOMPARE(*distance, 0.0);
}

void differentFramesExceedDuplicateThreshold()
{
    const auto dark = FrameFingerprint::make(solidFrame(64, 48, 20), FingerprintSize{16, 12});
    const auto light = FrameFingerprint::make(solidFrame(64, 48, 220), FingerprintSize{16, 12});
    const auto distance = FrameFingerprint::meanAbsoluteDistance(dark, light);
    QVERIFY(distance.has_value());
    QVERIFY(*distance > 0.5);
}
```

- [ ] **Step 2: Register and run the failing test**

Add `snipory_core_add_test(test_frame_fingerprint tests/TestFrameFingerprint.cpp)` to `core/CMakeLists.txt`.

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake -S . -B build -DBUILD_TESTING=ON -DCMAKE_PREFIX_PATH="$(brew --prefix qtbase)"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake --build build --target test_frame_fingerprint
```

Expected: compilation fails because `ScrollFrame` and `FrameFingerprint` do not exist.

- [ ] **Step 3: Implement the Qt-free frame contract**

Define a moveable BGRA frame whose byte layout is explicit and bridge-safe:

```cpp
namespace snipory::core::scroll {

struct PixelCrop final {
    int left = 0;
    int right = 0;
    int top = 0;
    int bottom = 0;
};

struct ScrollFrame final {
    int width = 0;
    int height = 0;
    int bytesPerRow = 0;
    std::vector<std::uint8_t> pixels;

    ScrollFrame() = default;
    ScrollFrame(int frameWidth, int frameHeight)
        : width(frameWidth), height(frameHeight), bytesPerRow(frameWidth * 4),
          pixels(static_cast<std::size_t>(bytesPerRow * frameHeight), 0) {}

    bool isValid() const noexcept
    {
        return width > 0 && height > 0 && bytesPerRow >= width * 4
            && pixels.size() >= static_cast<std::size_t>(bytesPerRow * height);
    }
};

} // namespace snipory::core::scroll
```

- [ ] **Step 4: Implement downsampled luminance fingerprints**

`FrameFingerprint::make` must average BGRA pixels into a fixed luminance grid, and `meanAbsoluteDistance` must normalize each byte difference by `255.0`. Reject invalid or mismatched fingerprints with `std::nullopt` rather than silently comparing incompatible data.

```cpp
struct FingerprintSize final { int width; int height; };

struct Fingerprint final {
    FingerprintSize size;
    std::vector<std::uint8_t> luminance;
};

class FrameFingerprint final {
public:
    static Fingerprint make(const ScrollFrame &frame, FingerprintSize size);
    static std::optional<double> meanAbsoluteDistance(
        const Fingerprint &left,
        const Fingerprint &right
    );
};
```

- [ ] **Step 5: Run the focused core test**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake --build build --target test_frame_fingerprint
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ctest --test-dir build -R test_frame_fingerprint --output-on-failure
```

Expected: `test_frame_fingerprint` passes.

- [ ] **Step 6: Commit**

```bash
git add core/CMakeLists.txt core/include/snipory/core/scroll core/src/scroll/FrameFingerprint.cpp core/tests/TestFrameFingerprint.cpp
git commit -m "feat(core): add scroll frame fingerprints"
```

---

### Task 2: Implement vertical overlap matching and confidence

**Files:**
- Create: `core/include/snipory/core/scroll/VerticalOverlapMatcher.h`
- Create: `core/src/scroll/VerticalOverlapMatcher.cpp`
- Create: `core/tests/TestVerticalOverlapMatcher.cpp`
- Modify: `core/CMakeLists.txt`

- [ ] **Step 1: Write failing overlap tests**

Generate a tall deterministic striped document, crop consecutive viewports, and assert displacement, overlap, ambiguity, and insufficient-overlap behavior:

```cpp
void findsDownwardOffset()
{
    const ScrollFrame document = stripedDocument(120, 480);
    const ScrollFrame previous = crop(document, 0, 0, 120, 180);
    const ScrollFrame current = crop(document, 0, 72, 120, 180);

    const OverlapResult result = VerticalOverlapMatcher().match(previous, current, {});

    QCOMPARE(result.kind, OverlapKind::Reliable);
    QCOMPARE(result.verticalAdvance, 72);
    QCOMPARE(result.overlapHeight, 108);
    QVERIFY(result.confidence >= 0.8);
}

void rejectsRepeatedPatternWithAmbiguousPlacement()
{
    const ScrollFrame repeated = repeatedRows(120, 180, 12);
    const OverlapResult result = VerticalOverlapMatcher().match(repeated, repeated, {});
    QCOMPARE(result.kind, OverlapKind::Ambiguous);
}
```

- [ ] **Step 2: Run the failing test**

Register `test_vertical_overlap_matcher`, build it, and expect missing matcher symbols.

- [ ] **Step 3: Implement a coarse-to-fine vertical matcher**

Use a quarter-scale luminance pyramid for the coarse scan, then rescore the best offsets at full resolution. Score only the overlap intersection, require a configurable minimum overlap ratio, and compare the best score to the runner-up:

```cpp
struct OverlapConfig final {
    double minimumOverlapRatio = 0.20;
    double maximumAdvanceRatio = 0.85;
    double maximumNormalizedError = 0.08;
    double minimumWinnerMargin = 0.015;
};

struct OverlapResult final {
    OverlapKind kind = OverlapKind::Insufficient;
    int verticalAdvance = 0;
    int overlapHeight = 0;
    double confidence = 0;
    double normalizedError = 1;
};
```

Keep the matcher vertical-only; do not add homography, feature descriptors, or OpenCV.

- [ ] **Step 4: Add mask support**

Allow callers to exclude top, bottom, left, and right pixel bands from scoring. Assert that a changing fixed header no longer changes the measured document displacement when its top band is masked.

- [ ] **Step 5: Run matcher and full core tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake --build build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ctest --test-dir build -R 'test_(vertical_overlap_matcher|frame_fingerprint)' --output-on-failure
```

Expected: both focused tests pass.

- [ ] **Step 6: Commit**

```bash
git add core/CMakeLists.txt core/include/snipory/core/scroll/VerticalOverlapMatcher.h core/src/scroll/VerticalOverlapMatcher.cpp core/tests/TestVerticalOverlapMatcher.cpp
git commit -m "feat(core): match vertical scroll overlap"
```

---

### Task 3: Build the duplicate-safe stitch session

**Files:**
- Create: `core/include/snipory/core/scroll/ScrollStitchSession.h`
- Create: `core/src/scroll/ScrollStitchSession.cpp`
- Create: `core/tests/TestScrollStitchSession.cpp`
- Modify: `core/CMakeLists.txt`

- [ ] **Step 1: Write failing sequence tests**

Cover initial acceptance, append, exact duplicate, upward review, downward resume, low confidence, fixed header retention, scrollbar crop, and resource guard:

```cpp
void reverseReviewDoesNotMutateAcceptedContent()
{
    ScrollStitchSession session(defaultConfig());
    const auto frames = makeDocumentViewports({0, 60, 120, 60, 120, 180});

    QCOMPARE(session.append(frames[0]).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(frames[1]).kind, AppendKind::AcceptedAppend);
    QCOMPARE(session.append(frames[2]).kind, AppendKind::AcceptedAppend);
    const int heightBeforeReview = session.outputHeight();
    QCOMPARE(session.append(frames[3]).kind, AppendKind::ReviewDiscarded);
    QCOMPARE(session.append(frames[4]).kind, AppendKind::DuplicateDiscarded);
    QCOMPARE(session.outputHeight(), heightBeforeReview);
    QCOMPARE(session.append(frames[5]).kind, AppendKind::AcceptedAppend);
}

void resourceLimitPreservesSaveableResult()
{
    ScrollStitchConfig config = defaultConfig();
    config.maximumAcceptedBytes = 120 * 260 * 4;
    ScrollStitchSession session(config);
    session.append(makeViewport(0));
    const AppendResult result = session.append(makeViewport(120));
    QCOMPARE(result.kind, AppendKind::ResourceLimit);
    QVERIFY(session.finalize().isValid());
}
```

- [ ] **Step 2: Run the failing test**

Register `test_scroll_stitch_session`, build it, and expect missing session symbols.

- [ ] **Step 3: Implement immutable accepted segments**

Expose these stable classifications to the bridge:

```cpp
enum class AppendKind {
    AcceptedInitial,
    AcceptedAppend,
    DuplicateDiscarded,
    ReviewDiscarded,
    PausedLowConfidence,
    ResourceLimit
};

struct AppendResult final {
    AppendKind kind = AppendKind::PausedLowConfidence;
    int appendedHeight = 0;
    int outputHeight = 0;
    double confidence = 0;
};
```

Store the first frame and each accepted non-overlapping bottom strip. Never crop or rewrite accepted segments after a review frame.

- [ ] **Step 4: Add seen-region indexing**

Keep fingerprints for accepted viewport anchors, search recent anchors before full history, and classify a frame that maps inside accepted content as `ReviewDiscarded`. Require a reliable match against the current tail before accepting new pixels after review.

- [ ] **Step 5: Add conservative fixed-band and scrollbar decisions**

Infer fixed top and bottom bands only after at least three accepted movements agree that those rows remain screen-stationary while the central document moves. Keep the first-frame copy and exclude later copies from append calculations.

Detect a scrollbar only within a narrow edge budget, require vertical persistence plus a moving thumb-shaped contrast region, and crop only when confidence exceeds the dedicated threshold. Preserve ambiguous edge pixels.

- [ ] **Step 6: Implement preview and final composition**

`preview(maxHeight:)` may downsample accepted segments; `finalize()` must compose original BGRA segments once in order and apply the confirmed edge crop. Add assertions for exact output height and representative seam pixels.

- [ ] **Step 7: Run all core tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake --build build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ctest --test-dir build --output-on-failure
```

Expected: all core tests pass, including the three new scroll targets.

- [ ] **Step 8: Commit**

```bash
git add core/CMakeLists.txt core/include/snipory/core/scroll/ScrollStitchSession.h core/src/scroll/ScrollStitchSession.cpp core/tests/TestScrollStitchSession.cpp
git commit -m "feat(core): accumulate scroll capture segments"
```

---

### Task 4: Bridge the scroll engine into the macOS target

**Files:**
- Create: `platforms/mac/Sources/Bridge/ScrollCaptureBridge.h`
- Create: `platforms/mac/Sources/Bridge/ScrollCaptureBridge.mm`
- Modify: `platforms/mac/Sources/Bridge/xxsnap-Bridging-Header.h`
- Modify: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`
- Create: `platforms/mac/Tests/ScrollCaptureBridgeTests.swift`
- Create: `platforms/mac/Tests/ScrollCaptureTestSupport.swift`

- [ ] **Step 1: Write failing bridge tests**

```swift
func testBridgeClassifiesDuplicateAndProducesFinalImage() throws {
    let bridge = ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024)
    let first = TestImageFactory.verticalDocumentViewport(offset: 0)
    let duplicate = TestImageFactory.verticalDocumentViewport(offset: 0)

    XCTAssertEqual(try bridge.append(first).kind, .acceptedInitial)
    XCTAssertEqual(try bridge.append(duplicate).kind, .duplicateDiscarded)
    XCTAssertNotNil(try bridge.finalImage())
}
```

Create shared deterministic image helpers in `ScrollCaptureTestSupport.swift` so later tasks do not redefine fixture behavior:

```swift
enum TestImageFactory {
    static func solid(size: NSSize, color: NSColor = .white) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    static func verticalDocumentViewport(offset: Int, width: Int = 120, height: Int = 180) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        for row in 0..<height {
            let documentY = row + offset
            NSColor(calibratedWhite: CGFloat((documentY / 12) % 10) / 10, alpha: 1).setFill()
            NSRect(x: 0, y: row, width: width, height: 1).fill()
        }
        image.unlockFocus()
        return image
    }
}
```

- [ ] **Step 2: Add project references and confirm the test fails**

Add the bridge, the three core `.cpp` files, and the test to the correct build phases. Set `HEADER_SEARCH_PATHS = "$(PROJECT_DIR)/../../core/include"` for app and test configurations.

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/ScrollCaptureBridgeTests test
```

Expected: the test fails because the Objective-C API is not implemented.

- [ ] **Step 3: Implement the Objective-C API**

Expose Objective-C enums and value objects rather than leaking C++ types into Swift:

```objc
typedef NS_ENUM(NSInteger, ScrollCaptureAppendKind) {
    ScrollCaptureAppendKindAcceptedInitial,
    ScrollCaptureAppendKindAcceptedAppend,
    ScrollCaptureAppendKindDuplicateDiscarded,
    ScrollCaptureAppendKindReviewDiscarded,
    ScrollCaptureAppendKindPausedLowConfidence,
    ScrollCaptureAppendKindResourceLimit,
};

@interface ScrollCaptureAppendUpdate : NSObject
@property(nonatomic, readonly) ScrollCaptureAppendKind kind;
@property(nonatomic, readonly) NSInteger appendedHeight;
@property(nonatomic, readonly) NSInteger outputHeight;
@property(nonatomic, readonly) double confidence;
@end

@interface ScrollCaptureBridge : NSObject
- (instancetype)initWithMaximumAcceptedBytes:(NSUInteger)maximumAcceptedBytes
    NS_SWIFT_NAME(init(maximumAcceptedBytes:));
- (nullable ScrollCaptureAppendUpdate *)appendImage:(NSImage *)image error:(NSError **)error
    NS_SWIFT_NAME(append(_:));
- (nullable NSImage *)previewImageWithMaximumHeight:(NSInteger)maximumHeight error:(NSError **)error
    NS_SWIFT_NAME(preview(maximumHeight:));
- (nullable NSImage *)finalImageAndReturnError:(NSError **)error
    NS_SWIFT_NAME(finalImage());
@end
```

Convert through `CGContext` into premultiplied BGRA bytes, preserve pixel dimensions separately from AppKit point size, and construct returned `NSImage` values with the source display scale.

- [ ] **Step 4: Run bridge and project build**

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/ScrollCaptureBridgeTests test
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived build
```

Expected: bridge tests and the app build pass without linking Qt or OpenCV.

- [ ] **Step 5: Commit**

```bash
git add platforms/mac/Sources/Bridge platforms/mac/Tests/ScrollCaptureBridgeTests.swift platforms/mac/Tests/ScrollCaptureTestSupport.swift platforms/mac/xxsnap.xcodeproj/project.pbxproj
git commit -m "feat(mac): bridge scroll stitch engine"
```

---

### Task 5: Implement the Swift session state machine and adaptive sampler

**Files:**
- Create: `platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift`
- Create: `platforms/mac/Sources/ScrollCapture/ScrollActivityMonitor.swift`
- Create: `platforms/mac/Tests/ScrollCaptureSessionTests.swift`
- Modify: `platforms/mac/Sources/Capture/ScreenCaptureService.swift`
- Modify: `platforms/mac/Tests/ScreenCaptureServiceTests.swift`
- Modify: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing state and sampling tests**

Use a fake clock, fake region capturer, and fake bridge. Cover preparing, capturing, paused, finishing, cancelled, no concurrent requests, inertial continuation, and idle stop:

```swift
func testScrollActivityArmsSamplingUntilPixelsStabilize() async throws {
    let first = TestImageFactory.verticalDocumentViewport(offset: 0)
    let second = TestImageFactory.verticalDocumentViewport(offset: 60)
    let capturer = FakeRegionCapturer(frames: [first, second, second])
    let engine = FakeScrollEngine(results: [.acceptedInitial, .acceptedAppend, .duplicateDiscarded])
    let session = ScrollCaptureSession(capturer: capturer, engine: engine, clock: TestClock())

    try await session.start(seed: ScrollCaptureSeed.testFixture(image: first))
    await session.recordScrollActivity()
    await session.test_runSamplingTick()
    await session.test_runSamplingTick()
    await session.test_runSamplingTick()

    XCTAssertEqual(await session.state, .capturing)
    XCTAssertEqual(capturer.maximumConcurrentCaptures, 1)
    XCTAssertFalse(await session.test_isSamplingArmed)
}
```

Define the fakes in `ScrollCaptureSessionTests.swift` with no timers or global event monitors:

```swift
@MainActor
final class FakeRegionCapturer: ScrollRegionCapturing {
    private var frames: [NSImage]
    private(set) var activeCaptures = 0
    private(set) var maximumConcurrentCaptures = 0

    init(frames: [NSImage]) { self.frames = frames }

    func captureImage(in selectionRect: NSRect) async throws -> NSImage {
        activeCaptures += 1
        maximumConcurrentCaptures = max(maximumConcurrentCaptures, activeCaptures)
        defer { activeCaptures -= 1 }
        return frames.removeFirst()
    }
}

final class FakeScrollEngine: ScrollStitching {
    private var results: [ScrollCaptureAppendKind]
    init(results: [ScrollCaptureAppendKind]) { self.results = results }

    func append(_ image: NSImage) throws -> ScrollCaptureAppendUpdate {
        ScrollCaptureAppendUpdate.testValue(kind: results.removeFirst())
    }

    func preview(maximumHeight: Int) throws -> NSImage { imageFixture }
    func finalImage() throws -> NSImage { imageFixture }
    private let imageFixture = TestImageFactory.solid(size: NSSize(width: 120, height: 180))
}

struct TestClock: ScrollCaptureClock {
    func sleep(for duration: Duration) async throws {}
}
```

Add DEBUG-only `testValue(kind:)` and `ScrollCaptureSeed.testFixture(image:)` helpers in their owning production files so their initializers can remain read-only to normal callers.

- [ ] **Step 2: Define focused protocols**

```swift
@MainActor
protocol ScrollRegionCapturing {
    func captureImage(in selectionRect: NSRect) async throws -> NSImage
}

struct ScrollCaptureSeed {
    let screenRect: NSRect
    let snapshotRect: NSRect
    let frozenImage: NSImage
    let annotations: [CaptureAnnotation]
    let eraserMasks: [EraserMask]
}

protocol ScrollCaptureClock {
    func sleep(for duration: Duration) async throws
}

protocol ScrollStitching {
    func append(_ image: NSImage) throws -> ScrollCaptureAppendUpdate
    func preview(maximumHeight: Int) throws -> NSImage
    func finalImage() throws -> NSImage
}
```

Make `ScreenCaptureService` conform without changing existing capture behavior.

- [ ] **Step 3: Implement explicit session state**

```swift
enum ScrollCaptureSessionState: Equatable {
    case idle
    case preparing
    case capturing
    case paused(ScrollCapturePauseReason)
    case finishing
    case finished
    case cancelled
}
```

The session emits presentation updates through an injected `@MainActor` closure. It must never mutate the overlay directly.

- [ ] **Step 4: Implement adaptive sampling**

Scroll activity arms a short cadence. Each tick waits for the previous capture and engine append to complete. Accepted append keeps sampling armed, duplicate results count toward visual stability, and direct activity resets the stability counter so inertial movement remains covered.

- [ ] **Step 5: Implement pause, recovery, finish, and cancel**

Low confidence and resource limit enter distinct pause reasons. A reliable append after the user returns to a captured tail clears low-confidence pause. Finish returns the current final image from capturing or paused state; cancel drops the engine and returns the immutable seed.

- [ ] **Step 6: Run focused tests**

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/ScrollCaptureSessionTests -only-testing:xxsnapMacTests/ScreenCaptureServiceTests test
```

Expected: session and capture-service tests pass.

- [ ] **Step 7: Commit**

```bash
git add platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift platforms/mac/Sources/ScrollCapture/ScrollActivityMonitor.swift platforms/mac/Sources/Capture/ScreenCaptureService.swift platforms/mac/Tests/ScrollCaptureSessionTests.swift platforms/mac/Tests/ScreenCaptureServiceTests.swift platforms/mac/xxsnap.xcodeproj/project.pbxproj
git commit -m "feat(mac): orchestrate adaptive scroll sampling"
```

---

### Task 6: Add passive capture controls and the tail preview

**Files:**
- Create: `platforms/mac/Sources/ScrollCapture/ScrollCapturePresentationController.swift`
- Create: `platforms/mac/Tests/ScrollCapturePresentationTests.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/App/AppSettings.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`
- Modify: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing overlay-mode tests**

Assert that scroll mode keeps toolbar geometry stable, disables annotation commands, highlights scroll as Finish, preserves Cancel, exposes seed data, and restores state on cancel:

```swift
func testScrollCaptureModeKeepsToolbarLayoutAndDisablesAnnotationTools() throws {
    let window = SelectionOverlayWindow(
        backgroundImage: TestImageFactory.solid(size: NSSize(width: 640, height: 480)),
        featureGate: FeatureGate(license: LicenseState(plan: .trial))
    ) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 420, height: 280))
    let before = try XCTUnwrap(window.test_mainToolbarRect())

    window.test_beginScrollCapture()

    XCTAssertEqual(window.test_mainToolbarRect(), before)
    XCTAssertFalse(window.test_toolbarButtonIsEnabled(.rectangle))
    XCTAssertTrue(window.test_toolbarButtonIsEnabled(.scroll))
    XCTAssertTrue(window.test_toolbarButtonIsEnabled(.cancel))
    XCTAssertEqual(window.test_tooltipTitle(for: .scroll), "完成滚动截图")
}
```

- [ ] **Step 2: Add the scroll seed and passive mode API**

```swift
enum ScrollCaptureOverlayState: Equatable {
    case inactive
    case capturing
    case paused(message: String)
}
```

Reuse `ScrollCaptureSeed` from `ScrollCaptureSession.swift`; do not define a second overlay-specific seed type.

`SelectionOverlayWindow` exposes a request callback and screen-coordinate toolbar frame. The view commits text before producing the seed and does not call the ordinary completion handler.

- [ ] **Step 3: Preserve target scrolling with separate control windows**

When capture starts, make the full-screen overlay mouse-transparent so wheel and trackpad input reaches the target application. Cover the existing toolbar with a small borderless control panel at the same frame; that panel only handles Finish and Cancel. This preserves the visual toolbar location without reposting input events or giving the screenshot overlay focus.

- [ ] **Step 4: Implement preview placement as a pure function**

```swift
static func previewFrame(
    selection: NSRect,
    previewSize: NSSize,
    visibleFrame: NSRect,
    spacing: CGFloat = 12
) -> NSRect
```

Test right, left, above, below, largest-space selection, inside fallback, full-screen inside placement, and clamping on secondary displays.

- [ ] **Step 5: Implement the tail-following preview panel**

Use a borderless nonactivating panel with an `NSScrollView`. Replace its downsampled document image after accepted appends, scroll to the bottom unless the user is actively reviewing, and keep warning text separate from image content.

- [ ] **Step 6: Run presentation and overlay tests**

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/ScrollCapturePresentationTests -only-testing:xxsnapMacTests/SelectionToolbarStateTests test
```

Expected: layout, control-state, and restore tests pass.

- [ ] **Step 7: Commit**

```bash
git add platforms/mac/Sources/ScrollCapture/ScrollCapturePresentationController.swift platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Sources/App/AppSettings.swift platforms/mac/Tests/ScrollCapturePresentationTests.swift platforms/mac/Tests/SelectionToolbarStateTests.swift platforms/mac/xxsnap.xcodeproj/project.pbxproj
git commit -m "feat(mac): present scroll capture controls and preview"
```

---

### Task 7: Integrate scroll capture with CaptureCoordinator

**Files:**
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing coordinator lifecycle tests**

Inject session and presentation factories. Assert request-start, accepted-preview update, finish handoff, cancel restoration, resource-limit completion offer, and cleanup:

```swift
func testCoordinatorCancelsScrollAndRestoresOriginalOverlay() async throws {
    let session = FakeScrollCaptureSession()
    let coordinator = CaptureCoordinator(
        permissionCoordinator: PermissionCoordinator(),
        screenCaptureService: ScreenCaptureService(),
        scrollSessionFactory: { _ in session }
    )
    let seed = ScrollCaptureSeed.testFixture(
        image: TestImageFactory.verticalDocumentViewport(offset: 0)
    )
    coordinator.startCapture()
    coordinator.test_requestScrollCapture(seed: seed)

    await session.emit(.preview(TestImageFactory.verticalDocumentViewport(offset: 60)))
    await session.emit(.cancelled(seed))

    XCTAssertTrue(coordinator.test_overlayIsPresented)
    XCTAssertEqual(coordinator.test_overlayScrollState, .inactive)
    XCTAssertNil(coordinator.test_scrollSession)
}
```

Define the injected contract and fake in `SelectionToolbarStateTests.swift`:

```swift
@MainActor
protocol ScrollCaptureSessionRunning: AnyObject {
    var onEvent: ((ScrollCaptureSession.Event) -> Void)? { get set }
    func start(seed: ScrollCaptureSeed) async throws
    func finish() async throws
    func cancel() async
}

@MainActor
final class FakeScrollCaptureSession: ScrollCaptureSessionRunning {
    var onEvent: ((ScrollCaptureSession.Event) -> Void)?
    func start(seed: ScrollCaptureSeed) async throws {}
    func finish() async throws {}
    func cancel() async {}
    func emit(_ event: ScrollCaptureSession.Event) { onEvent?(event) }
}
```

Make the production `ScrollCaptureSession` conform and add the factory parameter with a default that constructs the real session, preserving existing `CaptureCoordinator` call sites.

- [ ] **Step 2: Add coordinator ownership**

The coordinator owns one scroll session and presentation controller while keeping the original selection overlay retained. Do not end the global capture session when scroll mode starts.

- [ ] **Step 3: Wire request, finish, and cancel**

Start from the live selected `screenRect`, not the frozen desktop crop. Finish closes passive capture chrome and hands the raw long image plus seed annotations to the long-image editor factory. Cancel removes auxiliary windows, re-enables overlay input, restores its seed snapshot, and presents it again.

- [ ] **Step 4: Wire `Enter` and first-stage `Esc`**

The separate controls panel and overlay key handling must both route `Enter` to finish and the first `Esc` to scroll cancel. A second `Esc` after restoration continues through existing ordinary screenshot cancellation.

- [ ] **Step 5: Run coordinator and overlay tests**

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests test
```

Expected: existing selection and new scroll lifecycle tests pass.

- [ ] **Step 6: Commit**

```bash
git add platforms/mac/Sources/App/CaptureCoordinator.swift platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): connect scrolling capture lifecycle"
```

---

### Task 8: Build the dedicated long-image editor

**Files:**
- Create: `platforms/mac/Sources/ScrollCapture/LongImageEditorWindowController.swift`
- Create: `platforms/mac/Tests/LongImageEditorTests.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
- Modify: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing viewport and coordinate tests**

```swift
func testEditorOpensAtTopFitWidthAndMapsViewportToImageCoordinates() throws {
    let image = TestImageFactory.solid(size: NSSize(width: 1000, height: 8000))
    let annotation = CaptureAnnotation(
        kind: .rectangle,
        rect: NSRect(x: 20, y: 40, width: 100, height: 80),
        style: CaptureAnnotationStyle()
    )
    let editor = LongImageEditorWindowController(image: image, annotations: [annotation], eraserMasks: [])

    editor.test_layout(in: NSRect(x: 0, y: 0, width: 1200, height: 900))

    XCTAssertEqual(editor.test_visibleImageRect.minY, 0, accuracy: 0.5)
    XCTAssertEqual(editor.test_zoomScale, editor.test_viewportWidth / 1000, accuracy: 0.001)
    XCTAssertEqual(editor.test_imagePoint(fromViewport: NSPoint(x: 50, y: 80)).y, 80 / editor.test_zoomScale, accuracy: 0.5)
}
```

Also test annotation translation across scroll offsets, toolbar-fixed layout, Retina scale, and a resize that preserves the image-coordinate anchor.

- [ ] **Step 2: Implement the editor shell**

Create a titled, resizable `NSWindow` bounded to `visibleFrame`, an `NSScrollView` for the image, and a fixed control strip. Open at document top with fit-width zoom.

- [ ] **Step 3: Reuse the existing annotation overlay by visible slice**

Add `SelectionOverlayConfiguration.longImageEditor(...)`, modeled after `.pinnedImageEditor`, with scroll/cancel hidden and Finish Editing shown. The editor aligns a `SelectionOverlayWindow` to the image viewport, supplies a rendered visible slice, and translates annotations and eraser masks between full-image and viewport coordinates whenever the scroll position changes.

Do not duplicate annotation drawing logic in the editor. Disable document scrolling while a pointer drag is actively editing an annotation, then refresh the visible slice after the edit commits.

- [ ] **Step 4: Preserve first-screen annotations**

Initialize the editor's full-image annotation collection with the seed annotations at unchanged image-local coordinates. Verify annotations remain at the top after scrolling away and back.

- [ ] **Step 5: Render complete output**

Add a renderer entry point that accepts the full image, full-image annotations, and full-image eraser masks. Assert the visible editor slice and full exported pixels agree for rectangles, text, mosaic, magnifier, and eraser masks.

- [ ] **Step 6: Run editor and renderer tests**

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/LongImageEditorTests -only-testing:xxsnapMacTests/SelectionToolbarStateTests test
```

Expected: editor geometry and existing annotation tests pass.

- [ ] **Step 7: Commit**

```bash
git add platforms/mac/Sources/ScrollCapture/LongImageEditorWindowController.swift platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift platforms/mac/Tests/LongImageEditorTests.swift platforms/mac/xxsnap.xcodeproj/project.pbxproj
git commit -m "feat(mac): add long image editor"
```

---

### Task 9: Complete copy, save, pin, and failure recovery

**Files:**
- Modify: `platforms/mac/Sources/ScrollCapture/LongImageEditorWindowController.swift`
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift`
- Modify: `platforms/mac/Sources/App/PinnedImageWindowController.swift`
- Modify: `platforms/mac/Tests/LongImageEditorTests.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing output tests**

Verify that copy, save, and pin receive the same complete rendered long image. Verify a long pin fits the visible frame initially without replacing its source image:

```swift
func testPinUsesCompleteLongImageAndFitsVisibleFrame() throws {
    let image = TestImageFactory.solid(size: NSSize(width: 1200, height: 12000))
    let controller = PinnedImageWindowController(
        image: image,
        screenRect: NSRect(origin: .zero, size: image.size),
        visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
    )

    XCTAssertEqual(controller.test_sourceImageSize, image.size)
    XCTAssertLessThanOrEqual(controller.test_imageFrame.height, 900)
}
```

- [ ] **Step 2: Route editor actions through coordinator services**

Use injected closures for pasteboard, save panel, and pin factory so the editor owns no global side effects. Keep `CaptureAnnotationRenderer` as the single export path.

- [ ] **Step 3: Add resource-limit completion behavior**

When the session reports resource limit, keep the accepted preview visible and present Finish Scroll Capture and Cancel. Finishing must use `finalImage()` from the preserved engine state.

- [ ] **Step 4: Add post-capture save fallback**

If final composition succeeds but editor creation fails, retain the image as `lastCapture`, display an alert with Save and Cancel, and call the existing PNG save path on Save. If composition fails, keep the bridge/session alive until the user retries save or cancels.

- [ ] **Step 5: Run focused output tests**

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/LongImageEditorTests -only-testing:xxsnapMacTests/SelectionToolbarStateTests test
```

Expected: output parity, pin fitting, and fallback tests pass.

- [ ] **Step 6: Commit**

```bash
git add platforms/mac/Sources/ScrollCapture/LongImageEditorWindowController.swift platforms/mac/Sources/App/CaptureCoordinator.swift platforms/mac/Sources/App/PinnedImageWindowController.swift platforms/mac/Tests/LongImageEditorTests.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): export and pin complete long images"
```

---

### Task 10: Verify the product contract and update durable documentation

**Files:**
- Modify: `platforms/mac/Tests/manual-capture-checklist.md`
- Modify: `docs/requirements/xxsnap-mac-feature-requirements.md`
- Modify: `docs/annotation-tools-user-guide.md`
- Modify: scroll tests and implementation files only when verification exposes a defect

- [ ] **Step 1: Add the manual acceptance matrix**

Document exact checks for:

- Safari and Chrome long pages with and without fixed headers.
- Preview or a text editor with a long document.
- Mouse wheel and trackpad inertia.
- Pause, upward review, downward resume, and exact-repeat behavior.
- High-confidence scrollbar crop and ambiguous edge preservation.
- Full-screen, outside preview, inside fallback, edge-constrained, multi-display, Retina, and non-Retina cases.
- Existing first-screen annotations, new long-image annotations, copy, save, and full-image pin.
- Low-confidence pause, resource guard, editor failure, and save fallback.

- [ ] **Step 2: Run all shared-core tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake -S . -B build -DBUILD_TESTING=ON -DCMAKE_PREFIX_PATH="$(brew --prefix qtbase)"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake --build build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ctest --test-dir build --output-on-failure
```

Expected: all core tests pass.

- [ ] **Step 3: Run the full macOS test target**

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Expected: all new scroll tests pass. Record the six known historical failures separately if they remain unchanged; do not weaken new assertions to obtain a green summary.

- [ ] **Step 4: Build and restart the exact debug app**

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived build
REPO_ROOT="$(git rev-parse --show-toplevel)"
APP_PATH="$REPO_ROOT/build/xcode-derived/Build/Products/Debug/XxSnap.app"
APP_EXEC="$APP_PATH/Contents/MacOS/XxSnap"
pkill -f "XxSnap.app/Contents/MacOS/XxSnap" || true
open -n "$APP_PATH"
pgrep -af "$APP_EXEC"
```

Expected: one fresh debug process runs from the current repository or worktree's `build/xcode-derived`; no XxSnap process from another checkout remains.

- [ ] **Step 5: Execute the manual acceptance matrix**

Capture one browser long page and one ordinary document with both mouse and trackpad where available. Save representative outputs outside the repository, compare seam order, fixed regions, scrollbar removal, annotations, clipboard, PNG, and pin content, and record any environment limitation in the final handoff.

- [ ] **Step 6: Update product documentation**

Mark Scroll Capture implemented in `docs/requirements/xxsnap-mac-feature-requirements.md`, add the user workflow and shortcuts to `docs/annotation-tools-user-guide.md`, and keep deferred compatibility targets explicit.

- [ ] **Step 7: Run final diff checks**

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only intentional feature, tests, and documentation changes remain.

- [ ] **Step 8: Commit**

```bash
git add platforms/mac/Tests/manual-capture-checklist.md docs/requirements/xxsnap-mac-feature-requirements.md docs/annotation-tools-user-guide.md
git commit -m "docs(mac): document scroll capture workflow"
```

---

## Requirement Coverage

| Product requirement group | Implementation tasks |
| --- | --- |
| Entry, toolbar, finish, cancel, and annotation preservation | Tasks 5-7 |
| Adaptive sampling and one-frame-once behavior | Tasks 1-5 |
| Reverse review and downward resume | Tasks 2-3, 5 |
| Fixed regions and scrollbar crop | Tasks 2-3 |
| Tail preview and placement | Task 6 |
| Resource protection and recovery | Tasks 3, 5, 7, 9 |
| Dedicated editor and image-coordinate annotations | Task 8 |
| Copy, save, and complete-image pin | Task 9 |
| Cross-platform core boundary | Tasks 1-4 |
| Blocking acceptance corpus and manual verification | Task 10 |

No product decision remains unresolved before execution. Matcher thresholds, sampling cadence, preview dimensions, and memory budgets are implementation constants selected through the named tests and acceptance fixtures rather than new product choices.
