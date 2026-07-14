# Scroll Capture Full Overview Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the scrolling-capture preview always show the complete stitched result at its natural aspect ratio, scale very long images into the preview bounds, and keep the preview bottom-aligned with the capture region or screen.

**Architecture:** Keep full-resolution stitching and export unchanged. Generate a height-bounded lightweight preview in `ScrollCaptureSession`, then let `ScrollCapturePresentationController` contain that image within both the preview width and height, map the blue viewport indicator against the full output height, and remove any preview-document overflow. Reuse the existing side-selection and toolbar-avoidance logic, but replace vertical centering and direction-dependent anchoring with a stable bottom anchor.

**Tech Stack:** Swift 5, AppKit (`NSPanel`, `NSScrollView`, `NSImageView`), XCTest, existing Objective-C++ scrolling-capture bridge and C++ stitching core.

---

### Task 1: Produce a height-bounded complete preview image

**Files:**
- Modify: `platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift:246,583`
- Test: `platforms/mac/Tests/ScrollCaptureSessionTests.swift:7-32,1150-1210`

- [ ] **Step 1: Record height-based preview requests in the session fake**

Add `previewHeights` next to `previewWidths` and record the argument in `preview(maximumHeight:)`:

```swift
private(set) var previewHeights: [Int] = []
private(set) var previewWidths: [Int] = []

func preview(maximumHeight: Int) async throws -> NSImage {
    previewCallCount += 1
    previewHeights.append(maximumHeight)
    return final
}
```

Change `testStepModeScrollsSeventyPercentOnceAndLocksDirectionAfterAppend` to require height-bounded previews for the initial and accepted frames:

```swift
XCTAssertEqual(engine.previewHeights, [1_200, 1_200])
XCTAssertEqual(engine.previewWidths, [])
```

- [ ] **Step 2: Run the session regression test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap \
  -configuration Debug -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/ScrollCaptureSessionTests/testStepModeScrollsSeventyPercentOnceAndLocksDirectionAfterAppend
```

Expected: FAIL because `ScrollCaptureSession` still records `[600, 600]` in `previewWidths` and nothing in `previewHeights`.

- [ ] **Step 3: Request a full preview capped to 1,200 pixels high**

Replace both initial and accepted-append preview calls in `ScrollCaptureSession`:

```swift
let preview = try await stitcher.preview(maximumHeight: 1_200)
```

Do not change `ScrollCaptureBridgeWorker`, the bridge API, the shared core, or final-image generation; the existing height-limited preview already composes the entire accepted result before downsampling it.

- [ ] **Step 4: Run all session tests and verify GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap \
  -configuration Debug -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/ScrollCaptureSessionTests
```

Expected: all `ScrollCaptureSessionTests` pass and the preview height assertions equal `[1_200, 1_200]`.

- [ ] **Step 5: Commit the height-bounded preview path**

```bash
git add platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift \
  platforms/mac/Tests/ScrollCaptureSessionTests.swift
git commit -m "fix(mac): bound full scroll preview height"
```

### Task 2: Contain the complete long image without preview scrolling

**Files:**
- Modify: `platforms/mac/Sources/ScrollCapture/ScrollCapturePresentationController.swift:245-470`
- Test: `platforms/mac/Tests/ScrollCapturePresentationTests.swift:257-650`

- [ ] **Step 1: Replace scrolling expectations with complete-overview expectations**

Rename `testLongPreviewFitsWidthAndScrollsToCurrentPosition` to `testLongPreviewFitsCompletelyInsideVisibleOverview` and use these assertions:

```swift
func testLongPreviewFitsCompletelyInsideVisibleOverview() {
    let controller = makeController()
    let image = NSImage(size: NSSize(width: 240, height: 2_400))
    controller.setStepControlState(.executing)

    controller.updatePreview(
        image,
        following: .bottom,
        viewport: ScrollCapturePreviewViewport(viewportHeight: 400, outputHeight: 4_800)
    )

    XCTAssertTrue(controller.test_visibleRect.contains(controller.test_previewImageFrame))
    XCTAssertLessThanOrEqual(controller.test_previewImageFrame.width, 300)
    XCTAssertLessThanOrEqual(controller.test_previewImageFrame.height, 480)
    XCTAssertEqual(
        controller.test_previewImageFrame.width / controller.test_previewImageFrame.height,
        image.size.width / image.size.height,
        accuracy: 0.001
    )
    XCTAssertEqual(controller.test_visibleRect.minY, 0, accuracy: 0.5)
    XCTAssertEqual(controller.test_reviewOffset, 0, accuracy: 0.5)
    XCTAssertTrue(controller.test_previewImageFrame.contains(controller.test_viewportIndicatorFrame))
}
```

Update `testGrowingWidthFitPreviewMovesIndicatorWithDocumentAndPansToKeepItVisible` into `testGrowingPreviewKeepsCompleteImageAndIndicatorVisible`. Its final assertions must be:

```swift
XCTAssertEqual(controller.test_visibleRect.minY, 0, accuracy: 0.5)
XCTAssertEqual(controller.test_reviewOffset, 0, accuracy: 0.5)
XCTAssertTrue(controller.test_visibleRect.contains(controller.test_previewImageFrame))
XCTAssertTrue(controller.test_previewImageFrame.contains(controller.test_viewportIndicatorFrame))
```

- [ ] **Step 2: Run the two presentation tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap \
  -configuration Debug -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/ScrollCapturePresentationTests/testLongPreviewFitsCompletelyInsideVisibleOverview \
  -only-testing:xxsnapTests/ScrollCapturePresentationTests/testGrowingPreviewKeepsCompleteImageAndIndicatorVisible
```

Expected: FAIL because the current document height exceeds the visible height and the scroll view follows the blue indicator.

- [ ] **Step 3: Fit the preview image against both width and height**

In `configurePreviewPanel`, explicitly disable elastic overflow:

```swift
scrollView.hasVerticalScroller = false
scrollView.hasHorizontalScroller = false
scrollView.verticalScrollElasticity = .none
scrollView.horizontalScrollElasticity = .none
```

Replace the image sizing and preview-document setup at the start of `updatePreview` with:

```swift
let imageWidth = max(image.size.width, 1)
let imageHeight = max(image.size.height, 1)
let requestedScale = min(
    1,
    maximumPreviewContentSize.width / imageWidth,
    maximumPreviewContentSize.height / imageHeight
)
let requestedSize = NSSize(
    width: max(1, imageWidth * requestedScale),
    height: max(1, imageHeight * requestedScale)
)
resizePreviewPanel(contentSize: requestedSize)

let visibleSize = scrollView.contentSize
let displayScale = min(
    1,
    visibleSize.width / imageWidth,
    visibleSize.height / imageHeight
)
let displayWidth = max(1, imageWidth * displayScale)
let displayHeight = max(1, imageHeight * displayScale)
let documentSize = NSSize(
    width: max(1, visibleSize.width),
    height: max(1, visibleSize.height)
)
previewDocumentView.frame = NSRect(origin: .zero, size: documentSize)
let imageOrigin = NSPoint(
    x: max(0, (documentSize.width - displayWidth) / 2),
    y: max(0, (documentSize.height - displayHeight) / 2)
)
imageView.frame = NSRect(
    origin: imageOrigin,
    size: NSSize(width: displayWidth, height: displayHeight)
)
reviewOffset = 0
isProgrammaticScroll = true
scrollView.contentView.scroll(to: .zero)
scrollView.reflectScrolledClipView(scrollView.contentView)
isProgrammaticScroll = false
```

Keep the existing output-pixel mapping for `viewportTopPixel`, indicator height, and indicator Y. `keepViewportIndicatorVisible()` becomes a harmless no-op because the preview document no longer exceeds the visible bounds; do not remove it in this focused change.

- [ ] **Step 4: Update old scroll-follow assertions to full-overview assertions**

In the existing bottom, upward, first-direction, output-ratio, wheel-position, and successful-step tests:

- retain aspect-ratio and blue-indicator position assertions;
- replace every expectation that `documentHeight > visibleRect.height` or `visibleRect.minY > 0` with `visibleRect.contains(previewImageFrame)` and `reviewOffset == 0`;
- keep assertions that the indicator remains inside `previewImageFrame`;
- retain the cleanup test, but expect attempted user scrolling to keep `reviewOffset == 0`.

- [ ] **Step 5: Run all presentation tests and verify GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap \
  -configuration Debug -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/ScrollCapturePresentationTests
```

Expected: all `ScrollCapturePresentationTests` pass; no test requires preview-document scrolling.

- [ ] **Step 6: Commit the complete overview layout**

```bash
git add platforms/mac/Sources/ScrollCapture/ScrollCapturePresentationController.swift \
  platforms/mac/Tests/ScrollCapturePresentationTests.swift
git commit -m "fix(mac): show complete scroll capture overview"
```

### Task 3: Keep the preview bottom-aligned through placement and resizing

**Files:**
- Modify: `platforms/mac/Sources/ScrollCapture/ScrollCapturePresentationController.swift:729-910`
- Test: `platforms/mac/Tests/ScrollCapturePresentationTests.swift:93-180,400-505`

- [ ] **Step 1: Add bottom-placement regression tests**

Change the exact placement checks to require the selection or visible bottom:

```swift
func testPreviewFrameBottomAlignsWithNonFullscreenSelection() {
    let visible = NSRect(x: 0, y: 0, width: 1_000, height: 700)
    let selection = NSRect(x: 360, y: 250, width: 240, height: 180)
    let result = ScrollCapturePresentationController.previewFrame(
        selection: selection,
        previewSize: NSSize(width: 220, height: 260),
        visibleFrame: visible
    )

    XCTAssertEqual(result.minY, selection.minY, accuracy: 0.5)
    XCTAssertFalse(result.intersects(selection))
}

func testFullScreenPreviewBottomAlignsWithVisibleFrame() {
    let screen = NSRect(x: 0, y: 0, width: 1_280, height: 720)
    let result = ScrollCapturePresentationController.previewFrame(
        selection: screen,
        previewSize: NSSize(width: 360, height: 500),
        visibleFrame: screen
    )

    XCTAssertTrue(screen.contains(result))
    XCTAssertEqual(result.minY, screen.minY, accuracy: 0.5)
}
```

Add a resize regression test:

```swift
func testPreviewResizePreservesSelectionBottomAnchor() {
    let selection = NSRect(x: 200, y: 180, width: 300, height: 300)
    let controller = makeController(selectionFrame: selection)

    controller.updatePreview(NSImage(size: NSSize(width: 300, height: 240)), following: .bottom)
    XCTAssertEqual(controller.test_previewFrame.minY, selection.minY, accuracy: 0.5)

    controller.updatePreview(NSImage(size: NSSize(width: 300, height: 3_000)), following: .bottom)
    XCTAssertEqual(controller.test_previewFrame.minY, selection.minY, accuracy: 0.5)
}
```

- [ ] **Step 2: Run the three placement tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap \
  -configuration Debug -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/ScrollCapturePresentationTests/testPreviewFrameBottomAlignsWithNonFullscreenSelection \
  -only-testing:xxsnapTests/ScrollCapturePresentationTests/testFullScreenPreviewBottomAlignsWithVisibleFrame \
  -only-testing:xxsnapTests/ScrollCapturePresentationTests/testPreviewResizePreservesSelectionBottomAnchor
```

Expected: FAIL because static placement uses `selection.midY` and resizing preserves either the panel center or the upward-capture top edge.

- [ ] **Step 3: Bottom-align static preview candidates**

In `insidePreviewFrame`, replace the centered Y calculation with:

```swift
let insideY = min(
    max(selection.minY, visibleFrame.minY),
    visibleFrame.maxY - size.height
)
```

In both right-side and left-side branches of `outsidePreviewFrame`, set candidate Y relative to the selection bottom and clamp it inside the usable region:

```swift
y: min(
    max(selection.minY, region.frame.minY),
    region.frame.maxY - size.height
)
```

This keeps toolbar-split regions valid while making selection-bottom alignment the normal case.

- [ ] **Step 4: Preserve the chosen bottom anchor during dynamic resizing**

In `resizePreviewPanel`, replace the `initialVerticalAnchor` switch with:

```swift
origin.y = previewGrowthFrame.minY
```

Replace `anchorPreviewPanelForInitialDirection` with direction-independent bottom anchoring:

```swift
private func anchorPreviewPanelForInitialDirection() {
    var frame = previewPanel.frame
    frame.origin.y = previewGrowthFrame.minY
    frame.origin.y = min(
        max(frame.origin.y, placementVisibleFrame.minY),
        placementVisibleFrame.maxY - frame.height
    )
    previewPanel.setFrame(frame, display: false)
}
```

Keep horizontal side anchoring and screen clamping unchanged.

- [ ] **Step 5: Run all presentation tests and verify GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap \
  -configuration Debug -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/ScrollCapturePresentationTests
```

Expected: all presentation tests pass; both initial placement and every preview resize retain the bottom anchor.

- [ ] **Step 6: Commit bottom-aligned placement**

```bash
git add platforms/mac/Sources/ScrollCapture/ScrollCapturePresentationController.swift \
  platforms/mac/Tests/ScrollCapturePresentationTests.swift
git commit -m "fix(mac): bottom-align scroll capture preview"
```

### Task 4: Integrated verification and local app smoke test

**Files:**
- Verify only; no planned source changes.

- [ ] **Step 1: Run the complete scroll-capture macOS test set**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap \
  -configuration Debug -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/ScrollCaptureSessionTests \
  -only-testing:xxsnapTests/ScrollCapturePresentationTests \
  -only-testing:xxsnapTests/ScrollCaptureBridgeTests \
  -only-testing:xxsnapTests/ScreenCaptureServiceTests
```

Expected: all selected scrolling-capture tests pass with zero failures.

- [ ] **Step 2: Check patch hygiene**

Run:

```bash
git diff --check
```

Expected: exit code 0 with no output.

- [ ] **Step 3: Build and restart the exact local Debug app**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap \
  -configuration Debug -derivedDataPath build/xcode-derived build
pkill -f "/Users/kevin/Projects/open-source/Snipory/xxsnap/.worktrees/scroll-capture-impl/build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/MacOS/XxSnap" || true
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/.worktrees/scroll-capture-impl/build/xcode-derived/Build/Products/Debug/XxSnap.app
```

Expected: build succeeds and the process starts from this worktree's `build/xcode-derived` path.

- [ ] **Step 4: Perform the manual acceptance check**

Capture a scrollable Chrome or Safari region and perform at least ten downward steps. Verify:

1. the preview always shows both the top and bottom of the accepted stitched result;
2. the thumbnail remains proportional and becomes smaller as the result becomes longer;
3. the blue viewport indicator remains inside the thumbnail and follows the current position;
4. no preview scrollbar or internal panning appears;
5. a windowed selection preview stays level with the selection bottom;
6. a full-screen selection preview stays at the visible screen bottom;
7. finishing still opens the full-resolution long-image editor.

- [ ] **Step 5: Record final verification without committing unrelated dirty files**

Use `git status --short` and report the exact tests and manual checks run. Do not stage or revert pre-existing worktree changes outside the files named in this plan.
