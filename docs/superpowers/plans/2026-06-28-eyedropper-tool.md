# Eyedropper Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit mac overlay eyedropper toolbar tool that samples visible screenshot content, plus global mouse-wheel resizing for locked selections.

**Architecture:** Keep the work inside the existing custom AppKit overlay. `SelectionOverlayWindow.swift` owns tool activation, hit testing, cursor behavior, sampler state, and selection resizing; `SelectionToolbarState.swift` owns pure helper decisions such as sampler visibility and wheel-zoom geometry. Existing renderer output is reused to build the visible composite sample source.

**Tech Stack:** Swift 5, AppKit, XCTest, Xcode project resources, existing xxsnap mac overlay/test helpers.

---

## Source Spec

- `docs/superpowers/specs/2026-06-28-eyedropper-tool-design.md`

## Scope Check

The spec contains two related overlay interaction changes:

- explicit eyedropper tool entry and sampling behavior;
- global wheel resizing for locked screenshot selections.

They share the same overlay state and tests, so one implementation plan is appropriate. The plan keeps them in separate tasks so each task is independently testable.

## File Structure

- Modify `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
  - Add tooltip and pure helper functions for explicit sampler visibility and wheel-zoom geometry.
- Modify `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
  - Add eyedropper toolbar button/state/cursor.
  - Add explicit sampler sampling from a visible composite image.
  - Add `scrollWheel(with:)` handling for locked selection zoom.
  - Add DEBUG test helpers for eyedropper, sampler, pasteboard, and wheel events.
- Modify `platforms/mac/Tests/SelectionToolbarStateTests.swift`
  - Add focused toolbar, sampler, clipboard, and wheel zoom tests.
- Modify `platforms/mac/project.yml`
  - Add root `eyedropper.svg` as a bundled resource.
- Modify `platforms/mac/xxsnap.xcodeproj/project.pbxproj`
  - Add `eyedropper.svg` to the app target resource phase, following existing root SVG resource entries.
- Modify `docs/annotation-tools-user-guide.md`
  - Document explicit eyedropper and global wheel selection resizing.
- Modify `platforms/mac/Tests/manual-capture-checklist.md`
  - Add a manual smoke checklist for eyedropper and wheel zoom.

---

### Task 1: Toolbar Entry, Resource, And Explicit Tool State

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`
- Modify: `platforms/mac/project.yml`
- Modify: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing toolbar and resource tests**

Add these tests near the existing main-toolbar and color-sampler tests in `platforms/mac/Tests/SelectionToolbarStateTests.swift`:

```swift
func testEyedropperToolbarButtonSitsImmediatelyBeforeMosaic() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 360, height: 220))

    let eyedropper = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .eyedropper))
    let mosaic = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .mosaic))
    XCTAssertEqual(mosaic.minX - eyedropper.minX, 28, accuracy: 0.1)
    XCTAssertEqual(window.test_symbolName(for: .eyedropper), "toolbar-eyedropper")
    XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "eyedropper"), "取色")
}

func testEyedropperSvgIsBundledAndReadable() throws {
    let url = try XCTUnwrap(Bundle.main.url(forResource: "eyedropper", withExtension: "svg"))
    let contents = try String(contentsOf: url)
    XCTAssertTrue(contents.contains("bi-eyedropper"))
}

func testEyedropperToolbarButtonTogglesExplicitSamplerMode() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
    let point = try XCTUnwrap(window.test_eyedropperToolbarButtonPoint())

    XCTAssertFalse(window.test_isEyedropperToolActive)
    window.test_mouseDown(at: point)
    window.test_mouseUp(at: point)
    XCTAssertTrue(window.test_isEyedropperToolActive)
    XCTAssertTrue(window.test_eyedropperToolbarButtonIsSelected)
    XCTAssertNil(window.test_optionsToolbarRect)

    window.test_mouseDown(at: point)
    window.test_mouseUp(at: point)
    XCTAssertFalse(window.test_isEyedropperToolActive)
}

func testActivatingAnnotationToolExitsEyedropperMode() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
    let eyedropper = try XCTUnwrap(window.test_eyedropperToolbarButtonPoint())
    window.test_mouseDown(at: eyedropper)
    window.test_mouseUp(at: eyedropper)

    window.test_activateShapeTool(.marker)

    XCTAssertFalse(window.test_isEyedropperToolActive)
    XCTAssertEqual(window.test_optionsToolbarMode, .marker)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperToolbarButtonSitsImmediatelyBeforeMosaic -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperSvgIsBundledAndReadable -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperToolbarButtonTogglesExplicitSamplerMode -only-testing:xxsnapTests/SelectionToolbarStateTests/testActivatingAnnotationToolExitsEyedropperMode
```

Expected: FAIL because `.eyedropper`, test helpers, tooltip, and bundled resource do not exist yet.

- [ ] **Step 3: Add the toolbar enum cases and DEBUG test surface**

In `SelectionOverlayWindow.swift`, update the public DEBUG test enum at the top:

```swift
enum TestToolbarButton {
    case rectangle
    case eyedropper
    case mosaic
    case settings
}
```

Add forwarding helpers to `SelectionOverlayWindow` in the `#if DEBUG` block near other test accessors:

```swift
func test_eyedropperToolbarButtonPoint() -> NSPoint? {
    (contentView as? SelectionOverlayView)?.test_eyedropperToolbarButtonPoint()
}

var test_isEyedropperToolActive: Bool {
    (contentView as? SelectionOverlayView)?.test_isEyedropperToolActive ?? false
}

var test_eyedropperToolbarButtonIsSelected: Bool {
    (contentView as? SelectionOverlayView)?.test_eyedropperToolbarButtonIsSelected ?? false
}
```

Inside the private `SelectionOverlayView.ToolbarButton` enum, add:

```swift
case eyedropper
```

Update `test_mainToolbarButtonRect(for:)` and `test_symbolName(for:)` switches to map `.eyedropper` to `.eyedropper`.

Add `SelectionOverlayView` DEBUG helpers:

```swift
func test_eyedropperToolbarButtonPoint() -> NSPoint? {
    guard let selectionRect, let toolbar = mainToolbarRect(for: selectionRect) else {
        return nil
    }
    guard let rect = toolbarButtonRects(in: toolbar).first(where: { $0.0 == .eyedropper })?.1 else {
        return nil
    }
    return NSPoint(x: rect.midX, y: rect.midY)
}

var test_isEyedropperToolActive: Bool {
    isEyedropperToolActive
}

var test_eyedropperToolbarButtonIsSelected: Bool {
    buttonMatchesCurrentTool(.eyedropper)
}
```

- [ ] **Step 4: Implement eyedropper activation state and toolbar placement**

Add state beside `isShapeToolActive`:

```swift
private var isEyedropperToolActive = false
```

Insert `.eyedropper` between `.marker` and `.mosaic` in `mainToolbarButtons()`:

```swift
.marker,
.eyedropper,
.mosaic,
```

Update `symbolName(for:)`:

```swift
case .eyedropper:
    return "toolbar-eyedropper"
```

Update `tooltipIdentifier(for:)`:

```swift
case .eyedropper:
    return "eyedropper"
```

Update `buttonMatchesCurrentTool(_:)`:

```swift
case .eyedropper:
    return isEyedropperToolActive
```

Add this activation helper near `toggleShapeTool(_:)`:

```swift
private func toggleEyedropperTool() {
    let shouldActivate = !isEyedropperToolActive
    rememberCurrentStyleForActiveTool()
    isEyedropperToolActive = shouldActivate
    if shouldActivate {
        activeShapeKind = nil
        isShapeToolActive = false
        selectedAnnotationIndex = nil
        shapeStartPoint = nil
        shapeCurrentPoint = nil
        brushDraftPoints.removeAll()
        mosaicDraftPoints.removeAll()
        showsCornerRadiusPanel = false
        showsStrokeStyleMenu = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        closeCustomColorPanel()
    } else {
        sampledPointerPoint = nil
        sampledColor = nil
    }
    invalidateCursorRectsAndRefresh()
}
```

At the start of the active branch in `toggleShapeTool(_:)` and `activateShapeTool(_:)`, clear the eyedropper:

```swift
isEyedropperToolActive = false
```

In `perform(_:)`, add:

```swift
case .eyedropper:
    toggleEyedropperTool()
    showsStrokeStyleMenu = false
    showsCornerRadiusPanel = false
    showsStartArrowTypeMenu = false
    showsEndArrowTypeMenu = false
```

- [ ] **Step 5: Add tooltip and icon sizing helpers**

In `SelectionToolbarState.tooltipTitle(for:)`, add:

```swift
"eyedropper": "取色",
```

In `SelectionToolbarState.toolbarIconInset(for:)`, add:

```swift
case "eyedropper":
    return 2
```

- [ ] **Step 6: Bundle the existing root SVG**

Add this entry under the `snipory` target `sources` list in `platforms/mac/project.yml`:

```yaml
      - ../../../eyedropper.svg
```

Update `platforms/mac/xxsnap.xcodeproj/project.pbxproj` following the existing root SVG entries such as `border-corner-rounded.svg`:

```pbxproj
A10000000000000000000033 /* eyedropper.svg in Resources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000033 /* eyedropper.svg */; };
A20000000000000000000033 /* eyedropper.svg */ = {isa = PBXFileReference; path = "../../../eyedropper.svg"; sourceTree = SOURCE_ROOT; };
```

Add `A20000000000000000000033 /* eyedropper.svg */,` to the `Icons` group and `A10000000000000000000033 /* eyedropper.svg in Resources */,` to the app target `Resources` build phase.

- [ ] **Step 7: Run toolbar tests**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperToolbarButtonSitsImmediatelyBeforeMosaic -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperSvgIsBundledAndReadable -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperToolbarButtonTogglesExplicitSamplerMode -only-testing:xxsnapTests/SelectionToolbarStateTests/testActivatingAnnotationToolExitsEyedropperMode
```

Expected: PASS.

- [ ] **Step 8: Commit toolbar entry**

```bash
git add platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift platforms/mac/project.yml platforms/mac/xxsnap.xcodeproj/project.pbxproj
git commit -m "feat(mac): add eyedropper toolbar entry"
```

---

### Task 2: Explicit Eyedropper Sampling, Cursor, And Clipboard

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing explicit sampler tests**

Add these tests near existing color sampler tests in `SelectionToolbarStateTests.swift`:

```swift
func testExplicitEyedropperCanSampleWhenAnnotationsExist() throws {
    let image = solidImage(size: NSSize(width: 260, height: 180), color: .white)
    let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 160, height: 100))
    window.test_appendAnnotation(CaptureAnnotation(
        kind: .rectangle,
        rect: NSRect(x: 20, y: 20, width: 60, height: 40),
        style: redFilledAnnotationStyle()
    ))
    window.test_activateEyedropperTool()

    window.test_mouseMoved(to: NSPoint(x: 70, y: 70))

    XCTAssertEqual(window.test_sampledColorHex, "#FF001A")
    XCTAssertTrue(window.test_isColorSamplerVisible)
}

func testExplicitEyedropperHidesOutsideLockedSelection() throws {
    let image = solidImage(size: NSSize(width: 260, height: 180), color: .white)
    let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 160, height: 100))
    window.test_activateEyedropperTool()

    window.test_mouseMoved(to: NSPoint(x: 60, y: 60))
    XCTAssertTrue(window.test_isColorSamplerVisible)

    window.test_mouseMoved(to: NSPoint(x: 10, y: 10))
    XCTAssertFalse(window.test_isColorSamplerVisible)
    XCTAssertNil(window.test_sampledColorHex)
}

func testEyedropperDoesNotMoveSelectionOrAnnotationsOnDrag() throws {
    let image = solidImage(size: NSSize(width: 260, height: 180), color: .white)
    let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
    let selection = NSRect(x: 40, y: 40, width: 160, height: 100)
    window.test_setLockedSelectionRect(selection)
    window.test_appendAnnotation(CaptureAnnotation(
        kind: .rectangle,
        rect: NSRect(x: 20, y: 20, width: 60, height: 40),
        style: redFilledAnnotationStyle()
    ))
    window.test_activateEyedropperTool()

    window.test_mouseDown(at: NSPoint(x: 80, y: 80))
    window.test_mouseDragged(to: NSPoint(x: 120, y: 110))
    window.test_mouseUp(at: NSPoint(x: 120, y: 110))

    XCTAssertEqual(window.test_lockedSelectionRect, selection)
    XCTAssertEqual(window.test_annotationRect(at: 0), NSRect(x: 20, y: 20, width: 60, height: 40))
    XCTAssertEqual(window.test_annotationCount, 1)
}

func testEyedropperPlainCCopiesOnlyColorText() throws {
    let image = solidImage(size: NSSize(width: 260, height: 180), color: .white)
    let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 160, height: 100))
    window.test_appendAnnotation(CaptureAnnotation(
        kind: .rectangle,
        rect: NSRect(x: 20, y: 20, width: 60, height: 40),
        style: redFilledAnnotationStyle()
    ))
    window.test_activateEyedropperTool()
    window.test_mouseMoved(to: NSPoint(x: 70, y: 70))

    NSPasteboard.general.clearContents()
    window.test_keyDown(keyCode: 8, charactersIgnoringModifiers: "c")

    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "#FF001A")
    XCTAssertNil(NSPasteboard.general.data(forType: .png))
    XCTAssertNil(NSPasteboard.general.data(forType: .tiff))
}

func testEyedropperCommandCStillFinishesWithCopyAction() throws {
    let expectation = XCTestExpectation(description: "selection finished")
    let image = solidImage(size: NSSize(width: 260, height: 180), color: .white)
    let window = SelectionOverlayWindow(backgroundImage: image) { result in
        XCTAssertEqual(result?.action, .copy)
        expectation.fulfill()
    }
    window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 160, height: 100))
    window.test_activateEyedropperTool()
    window.test_keyDown(keyCode: 8, charactersIgnoringModifiers: "c", modifierFlags: [.command])

    wait(for: [expectation], timeout: 1)
}
```

Add this test helper near other helpers in `SelectionToolbarStateTests.swift`:

```swift
private func redFilledAnnotationStyle() -> CaptureAnnotationStyle {
    var style = CaptureAnnotationStyle()
    style.strokeColor = NSColor(srgbRed: 1, green: 0, blue: 26 / 255, alpha: 1)
    style.fillColor = style.strokeColor
    style.fillEnabled = true
    style.strokeWidth = 0
    return style
}
```

- [ ] **Step 2: Run explicit sampler tests and verify they fail**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testExplicitEyedropperCanSampleWhenAnnotationsExist -only-testing:xxsnapTests/SelectionToolbarStateTests/testExplicitEyedropperHidesOutsideLockedSelection -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperDoesNotMoveSelectionOrAnnotationsOnDrag -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperPlainCCopiesOnlyColorText -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperCommandCStillFinishesWithCopyAction
```

Expected: FAIL because explicit sampler helpers and visible-composite sampling do not exist.

- [ ] **Step 3: Add pure sampler visibility helper**

In `SelectionToolbarState.swift`, add:

```swift
static func shouldShowExplicitColorSampler(
    pointer: NSPoint,
    selectionRect: NSRect?
) -> Bool {
    guard let selectionRect else {
        return false
    }
    let rect = selectionRect.standardized
    return pointer.x >= rect.minX
        && pointer.x <= rect.maxX
        && pointer.y >= rect.minY
        && pointer.y <= rect.maxY
}
```

- [ ] **Step 4: Add eyedropper cursor**

In the `NSCursor` extension in `SelectionOverlayWindow.swift`, add:

```swift
static let xxsnapEyedropper: NSCursor = {
    let size = NSSize(width: 24, height: 24)
    let hotSpot = NSPoint(x: 6, y: 18)
    guard let image = svgImage(named: "eyedropper") else {
        return NSCursor.arrow
    }
    let cursorImage = NSImage(size: size)
    cursorImage.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 3, y: 3, width: 18, height: 18))
    cursorImage.unlockFocus()
    return NSCursor(image: cursorImage, hotSpot: hotSpot)
}()
```

Extend `SelectionToolbarState.OverlayCursorStyle`:

```swift
case eyedropper
```

Update `setCursor(_:)`:

```swift
case .eyedropper:
    NSCursor.xxsnapEyedropper.set()
```

Update `cursorStyle(at:)` before shape-tool cursor fallback:

```swift
if isEyedropperToolActive {
    if isToolbarOrPanelPoint(point) || !isInsideSelection {
        return .arrow
    }
    return .eyedropper
}
```

- [ ] **Step 5: Make sampler update respect explicit mode**

Add helpers in `SelectionOverlayView`:

```swift
private var isColorSamplerVisible: Bool {
    sampledPointerPoint != nil && sampledColor != nil
}

private func shouldShowColorSampler(at point: NSPoint) -> Bool {
    if isEyedropperToolActive {
        return SelectionToolbarState.shouldShowExplicitColorSampler(
            pointer: point,
            selectionRect: lockedSelectionRect
        ) && !isToolbarOrPanelPoint(point)
    }
    return SelectionToolbarState.shouldShowColorSampler(
        isShapeToolActive: isShapeToolActive,
        hasAnnotations: !annotations.isEmpty,
        pointer: point,
        selectionRect: colorSamplerSelectionRect
    )
}
```

Replace the guard in `updateColorSampler(at:)` with:

```swift
guard shouldShowColorSampler(at: point) else {
    if sampledPointerPoint != nil || sampledColor != nil {
        sampledPointerPoint = nil
        sampledColor = nil
        needsDisplay = true
    }
    return
}

sampledPointerPoint = point
sampledColor = sampleColor(at: point)
needsDisplay = true
```

Replace the guard in `drawColorSamplerIfNeeded()` with:

```swift
guard
    let point = sampledPointerPoint,
    let color = sampledColor,
    shouldShowColorSampler(at: point)
else {
    return
}
```

- [ ] **Step 6: Sample explicit eyedropper from visible composite**

Change `sampleColor(at:)`:

```swift
private func sampleColor(at point: NSPoint) -> NSColor? {
    if isEyedropperToolActive {
        return sampleVisibleCompositeColor(at: point)
    }
    guard let backgroundBitmap else {
        return nil
    }
    let pixel = bitmapPixelPoint(for: point, in: backgroundBitmap)
    return sampleColor(atPixelX: pixel.x, y: pixel.y, in: backgroundBitmap)
}
```

Add:

```swift
private func sampleVisibleCompositeColor(at point: NSPoint) -> NSColor? {
    guard let lockedSelectionRect else {
        return nil
    }
    let localPoint = localPoint(fromOverlayPoint: point, selectionRect: lockedSelectionRect)
    let source = visibleCompositeImageForSampling()
    guard let bitmap = source.cgImage(forProposedRect: nil, context: nil, hints: nil).map(NSBitmapImageRep.init(cgImage:)) else {
        return nil
    }
    let scaleX = CGFloat(bitmap.pixelsWide) / max(source.size.width, 1)
    let scaleY = CGFloat(bitmap.pixelsHigh) / max(source.size.height, 1)
    let x = Int(localPoint.x * scaleX)
    let y = Int((source.size.height - localPoint.y) * scaleY)
    return sampleColor(atPixelX: x, y: y, in: bitmap)
}

private func visibleCompositeImageForSampling() -> NSImage {
    guard let backgroundImage, let lockedSelectionRect else {
        return NSImage(size: lockedSelectionRect?.size ?? bounds.size)
    }
    let base = crop(image: backgroundImage, to: lockedSelectionRect) ?? NSImage(size: lockedSelectionRect.size)
    return CaptureAnnotationRenderer.render(image: base, annotations: annotations)
}
```

This intentionally samples committed annotations only.

- [ ] **Step 7: Prevent eyedropper drags from moving or drawing**

At the top of `handleAnnotatingMouseDown(at:)`, after toolbar/panel handling and before annotation hit testing, add:

```swift
if isEyedropperToolActive {
    updateColorSampler(at: point)
    needsDisplay = true
    return
}
```

In `mouseDragged(with:)`, in the `.annotating` case before `if isShapeToolActive`, add:

```swift
if isEyedropperToolActive {
    updateColorSampler(at: point)
    return
}
```

- [ ] **Step 8: Add DEBUG helpers needed by tests**

Add forwarding helpers to `SelectionOverlayWindow`:

```swift
func test_activateEyedropperTool() {
    (contentView as? SelectionOverlayView)?.test_activateEyedropperTool()
}

func test_appendAnnotation(_ annotation: CaptureAnnotation) {
    (contentView as? SelectionOverlayView)?.test_appendAnnotation(annotation)
}

var test_sampledColorHex: String? {
    (contentView as? SelectionOverlayView)?.test_sampledColorHex
}

var test_isColorSamplerVisible: Bool {
    (contentView as? SelectionOverlayView)?.test_isColorSamplerVisible ?? false
}

func test_keyDown(keyCode: UInt16, charactersIgnoringModifiers: String = "", modifierFlags: NSEvent.ModifierFlags = []) {
    keyDown(with: test_keyEvent(keyCode: keyCode, charactersIgnoringModifiers: charactersIgnoringModifiers, modifierFlags: modifierFlags))
}
```

Update the existing `test_keyEvent` helper to accept modifier flags:

```swift
private func test_keyEvent(
    keyCode: UInt16,
    charactersIgnoringModifiers: String,
    modifierFlags: NSEvent.ModifierFlags = []
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: 0,
        windowNumber: windowNumber,
        context: nil,
        characters: charactersIgnoringModifiers,
        charactersIgnoringModifiers: charactersIgnoringModifiers,
        isARepeat: false,
        keyCode: keyCode
    )!
}
```

Add `SelectionOverlayView` DEBUG helpers:

```swift
func test_activateEyedropperTool() {
    if !isEyedropperToolActive {
        toggleEyedropperTool()
    }
}

func test_appendAnnotation(_ annotation: CaptureAnnotation) {
    annotations.append(annotation)
    resetMosaicPreviewCaches()
    needsDisplay = true
}

var test_sampledColorHex: String? {
    sampledColor.map(SelectionToolbarState.colorSamplerHexString(for:))
}

var test_isColorSamplerVisible: Bool {
    isColorSamplerVisible
}
```

- [ ] **Step 9: Run explicit sampler tests**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testExplicitEyedropperCanSampleWhenAnnotationsExist -only-testing:xxsnapTests/SelectionToolbarStateTests/testExplicitEyedropperHidesOutsideLockedSelection -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperDoesNotMoveSelectionOrAnnotationsOnDrag -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperPlainCCopiesOnlyColorText -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperCommandCStillFinishesWithCopyAction
```

Expected: PASS.

- [ ] **Step 10: Commit explicit sampling**

```bash
git add platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): sample visible colors with eyedropper"
```

---

### Task 3: Global Mouse-Wheel Selection Zoom

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing wheel zoom tests**

Add these tests near existing selection resize tests:

```swift
func testWheelZoomExpandsLockedSelectionAroundPointer() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
    let pointer = NSPoint(x: 150, y: 130)
    window.test_setLockedSelectionRect(selection)

    window.test_scrollWheel(at: pointer, deltaY: 8)

    let resized = try XCTUnwrap(window.test_lockedSelectionRect)
    XCTAssertGreaterThan(resized.width, selection.width)
    XCTAssertGreaterThan(resized.height, selection.height)
    XCTAssertEqual((pointer.x - resized.minX) / resized.width, (pointer.x - selection.minX) / selection.width, accuracy: 0.02)
    XCTAssertEqual((pointer.y - resized.minY) / resized.height, (pointer.y - selection.minY) / selection.height, accuracy: 0.02)
}

func testWheelZoomShrinksNoSmallerThanSixtyFourPoints() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 80, height: 80))

    window.test_scrollWheel(at: NSPoint(x: 140, y: 140), deltaY: -100)

    let resized = try XCTUnwrap(window.test_lockedSelectionRect)
    XCTAssertEqual(resized.width, 64, accuracy: 0.1)
    XCTAssertEqual(resized.height, 64, accuracy: 0.1)
}

func testWheelZoomIsIgnoredOverToolbar() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
    window.test_setLockedSelectionRect(selection)
    let toolbarPoint = try XCTUnwrap(window.test_mainToolbarDragPoint())

    window.test_scrollWheel(at: toolbarPoint, deltaY: 8)

    XCTAssertEqual(window.test_lockedSelectionRect, selection)
}

func testWheelZoomIsIgnoredWhileDrawingAnnotation() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
    window.test_setLockedSelectionRect(selection)
    window.test_activateShapeTool(.rectangle)
    window.test_mouseDown(at: NSPoint(x: 130, y: 130))

    window.test_scrollWheel(at: NSPoint(x: 150, y: 150), deltaY: 8)

    XCTAssertEqual(window.test_lockedSelectionRect, selection)
}

func testWheelZoomRemapsExistingAnnotations() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
    window.test_appendAnnotation(CaptureAnnotation(
        kind: .rectangle,
        rect: NSRect(x: 40, y: 30, width: 50, height: 30),
        style: CaptureAnnotationStyle()
    ))

    window.test_scrollWheel(at: NSPoint(x: 200, y: 160), deltaY: 8)

    let resizedSelection = try XCTUnwrap(window.test_lockedSelectionRect)
    let annotation = try XCTUnwrap(window.test_annotationRect(at: 0))
    XCTAssertGreaterThan(resizedSelection.width, 200)
    XCTAssertGreaterThan(annotation.width, 50)
    XCTAssertGreaterThan(annotation.height, 30)
}
```

- [ ] **Step 2: Run wheel tests and verify they fail**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomExpandsLockedSelectionAroundPointer -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomShrinksNoSmallerThanSixtyFourPoints -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomIsIgnoredOverToolbar -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomIsIgnoredWhileDrawingAnnotation -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomRemapsExistingAnnotations
```

Expected: FAIL because wheel zoom and test helpers do not exist.

- [ ] **Step 3: Add pure wheel-zoom geometry helper**

In `SelectionToolbarState.swift`, add:

```swift
static let minimumWheelZoomSelectionSize = NSSize(width: 64, height: 64)

static func wheelZoomedSelectionRect(
    from selection: NSRect,
    deltaY: CGFloat,
    pointer: NSPoint,
    pointerIsInsideSelection: Bool,
    inside bounds: NSRect
) -> NSRect {
    let selection = selection.standardized
    guard selection.width > 0, selection.height > 0, deltaY != 0 else {
        return selection
    }
    let zoomStep: CGFloat = 0.08
    let unclampedScale = 1 + min(6, max(-6, deltaY)) * zoomStep
    let scale = max(0.2, min(2.0, unclampedScale))
    let anchor = pointerIsInsideSelection ? pointer : NSPoint(x: selection.midX, y: selection.midY)
    let anchorRatioX = selection.width == 0 ? 0.5 : (anchor.x - selection.minX) / selection.width
    let anchorRatioY = selection.height == 0 ? 0.5 : (anchor.y - selection.minY) / selection.height
    let bounded = bounds.standardized
    let targetWidth = min(bounded.width, max(minimumWheelZoomSelectionSize.width, selection.width * scale))
    let targetHeight = min(bounded.height, max(minimumWheelZoomSelectionSize.height, selection.height * scale))
    let requested = NSRect(
        x: anchor.x - targetWidth * anchorRatioX,
        y: anchor.y - targetHeight * anchorRatioY,
        width: targetWidth,
        height: targetHeight
    )
    return clamp(rect: requested, inside: bounded)
}
```

- [ ] **Step 4: Factor selection resize remapping into a reusable helper**

In `SelectionOverlayWindow.swift`, extract the body of `updateResizingSelection(to:)` after `let resized = ...` into:

```swift
private func applySelectionResize(from startRect: NSRect, to resized: NSRect, startAnnotations: [CaptureAnnotation], startAnnotationRects: [NSRect]) {
    guard resized.width >= 8, resized.height >= 8 else {
        return
    }

    lockedSelectionRect = resized
    for index in annotations.indices where startAnnotationRects.indices.contains(index) {
        if startAnnotations.indices.contains(index),
           let arrowLine = startAnnotations[index].arrowLine {
            let overlayLine = overlayArrowLine(fromLocalArrowLine: arrowLine, selectionRect: startRect)
            let localLine = localArrowLine(fromOverlayArrowLine: overlayLine, selectionRect: resized)
            annotations[index].arrowLine = localLine
            annotations[index].rect = localLine.boundingRect
        } else if startAnnotations.indices.contains(index),
                  let markerLine = startAnnotations[index].markerLine {
            let overlayLine = overlayMarkerLine(fromLocalMarkerLine: markerLine, selectionRect: startRect)
            let localLine = localMarkerLine(fromOverlayMarkerLine: overlayLine, selectionRect: resized)
            annotations[index].markerLine = localLine
            annotations[index].rect = localLine.boundingRect
        } else if startAnnotations.indices.contains(index),
                  let brushPath = startAnnotations[index].brushPath {
            let overlayPath = overlayBrushPath(fromLocalBrushPath: brushPath, selectionRect: startRect)
            let localPath = localBrushPath(fromOverlayBrushPath: overlayPath, selectionRect: resized)
            annotations[index].brushPath = localPath
            annotations[index].rect = localPath.boundingRect
        } else if startAnnotations.indices.contains(index),
                  let mosaicStroke = startAnnotations[index].mosaicStroke {
            let overlayStroke = overlayMosaicStroke(fromLocalMosaicStroke: mosaicStroke, selectionRect: startRect)
            let localStroke = localMosaicStroke(fromOverlayStroke: overlayStroke, selectionRect: resized)
            annotations[index].mosaicStroke = localStroke
            annotations[index].rect = localStroke.boundingRect
        } else {
            annotations[index].rect = SelectionToolbarState.localAnnotationRect(
                fromOverlayRect: startAnnotationRects[index],
                selectionRect: resized
            )
        }
    }
}
```

Then make `updateResizingSelection(to:)` call:

```swift
applySelectionResize(
    from: resizingSelectionStartRect,
    to: resized,
    startAnnotations: resizingSelectionStartAnnotations,
    startAnnotationRects: resizingSelectionStartAnnotationRects
)
```

- [ ] **Step 5: Add wheel event handling**

Add:

```swift
override func scrollWheel(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard handleSelectionWheelZoom(at: point, deltaY: event.scrollingDeltaY) else {
        super.scrollWheel(with: event)
        return
    }
}

private func handleSelectionWheelZoom(at point: NSPoint, deltaY: CGFloat) -> Bool {
    guard
        interactionMode == .annotating,
        let lockedSelectionRect,
        !isToolbarOrPanelPoint(point),
        abs(deltaY) > 0.01
    else {
        return false
    }

    let selection = lockedSelectionRect.standardized
    let screenBounds = screenBounds(containing: selection)
    let resized = SelectionToolbarState.wheelZoomedSelectionRect(
        from: selection,
        deltaY: deltaY,
        pointer: point,
        pointerIsInsideSelection: selection.contains(point),
        inside: screenBounds
    )
    guard resized != selection else {
        return true
    }

    let startAnnotations = annotations
    let startRects = annotations.map { overlayRect(fromLocalAnnotationRect: $0.rect) }
    applySelectionResize(
        from: selection,
        to: resized,
        startAnnotations: startAnnotations,
        startAnnotationRects: startRects
    )
    updateColorSampler(at: point)
    invalidateCursorRectsAndRefresh(at: point)
    needsDisplay = true
    return true
}
```

This `interactionMode == .annotating` guard covers active drawing, moving, resizing, rotating, toolbar drag, selection drag, and Mosaic value editing.

- [ ] **Step 6: Add wheel DEBUG helper**

Add forwarding helper to `SelectionOverlayWindow`:

```swift
func test_scrollWheel(at point: NSPoint, deltaY: CGFloat) {
    guard let overlayView = contentView as? SelectionOverlayView else {
        return
    }
    overlayView.scrollWheel(with: test_scrollEvent(at: point, deltaY: deltaY))
}
```

Add event builder:

```swift
private func test_scrollEvent(at point: NSPoint, deltaY: CGFloat) -> NSEvent {
    NSEvent.scrollWheelEvent(
        with: .scrollWheel,
        location: point,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: windowNumber,
        context: nil,
        deltaX: 0,
        deltaY: deltaY,
        deltaZ: 0
    )!
}
```

- [ ] **Step 7: Run wheel zoom tests**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomExpandsLockedSelectionAroundPointer -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomShrinksNoSmallerThanSixtyFourPoints -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomIsIgnoredOverToolbar -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomIsIgnoredWhileDrawingAnnotation -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomRemapsExistingAnnotations
```

Expected: PASS.

- [ ] **Step 8: Commit wheel zoom**

```bash
git add platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): resize selection with mouse wheel"
```

---

### Task 4: Documentation And Final Verification

**Files:**
- Modify: `docs/annotation-tools-user-guide.md`
- Modify: `platforms/mac/Tests/manual-capture-checklist.md`

- [ ] **Step 1: Update user guide**

In `docs/annotation-tools-user-guide.md`, update the `颜色与取色` section to include:

```markdown
- 点击主工具栏中位于“标记”和“马赛克”之间的取色按钮，可以在已有标注后继续取色。
- 取色按钮启用后，只在截图选区内取样；选区外不会显示取色面板。
- 取到的是当前可见结果。如果已经画了矩形、画笔、标记、箭头或马赛克，会取这些标注后的颜色。
- 按 `C` 只复制当前颜色值；工具栏“复制”和 `Command+C` 仍然只复制截图结果。
- 截图选区锁定后，可以用鼠标滚轮放大或缩小选区。最小 `64 x 64 pt`，最大为当前屏幕完整区域。
```

- [ ] **Step 2: Update manual checklist**

Append this section to `platforms/mac/Tests/manual-capture-checklist.md`:

```markdown
## Eyedropper and wheel zoom

- [ ] After locking a selection, the eyedropper button appears immediately before Mosaic.
- [ ] Clicking eyedropper changes the cursor to the eyedropper inside the selected region.
- [ ] Draw a visible annotation, activate eyedropper, hover over the annotation, and confirm the sampler shows the annotation color.
- [ ] Press `C` in eyedropper mode and confirm the clipboard contains the color text.
- [ ] Press `Command+C` and confirm the capture finishes with screenshot copy behavior.
- [ ] Scroll the mouse wheel inside a locked selection and confirm the selection expands/shrinks.
- [ ] Scroll over the toolbar and confirm the selection does not resize.
```

- [ ] **Step 3: Run all affected focused tests**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperToolbarButtonSitsImmediatelyBeforeMosaic -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperSvgIsBundledAndReadable -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperToolbarButtonTogglesExplicitSamplerMode -only-testing:xxsnapTests/SelectionToolbarStateTests/testActivatingAnnotationToolExitsEyedropperMode -only-testing:xxsnapTests/SelectionToolbarStateTests/testExplicitEyedropperCanSampleWhenAnnotationsExist -only-testing:xxsnapTests/SelectionToolbarStateTests/testExplicitEyedropperHidesOutsideLockedSelection -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperDoesNotMoveSelectionOrAnnotationsOnDrag -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperPlainCCopiesOnlyColorText -only-testing:xxsnapTests/SelectionToolbarStateTests/testEyedropperCommandCStillFinishesWithCopyAction -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomExpandsLockedSelectionAroundPointer -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomShrinksNoSmallerThanSixtyFourPoints -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomIsIgnoredOverToolbar -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomIsIgnoredWhileDrawingAnnotation -only-testing:xxsnapTests/SelectionToolbarStateTests/testWheelZoomRemapsExistingAnnotations
```

Expected: PASS.

- [ ] **Step 4: Build the mac app**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run full mac test target if local environment allows**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Expected: PASS. If this fails because of signing, screen-recording permissions, or environment-sensitive capture tests, record the exact failing test and the focused-test/build results.

- [ ] **Step 6: Commit docs and verification checklist**

```bash
git add docs/annotation-tools-user-guide.md platforms/mac/Tests/manual-capture-checklist.md
git commit -m "docs: describe eyedropper and wheel zoom"
```

---

## Self-Review Checklist

- Spec coverage:
  - Toolbar entry: Task 1.
  - Explicit activation, selected state, and tool exclusivity: Task 1 and Task 2.
  - Sampling region and visible sampling source: Task 2.
  - Eyedropper cursor: Task 2.
  - Clipboard separation: Task 2.
  - Global wheel zoom, max/min bounds, ignored states, and annotation remapping: Task 3.
  - User docs and manual smoke coverage: Task 4.
- Placeholder scan: no task uses TBD/TODO/fill-in-later wording.
- Type consistency: plan uses existing `CaptureAnnotation`, `CaptureAnnotationStyle`, `SelectionToolbarState`, `SelectionOverlayWindow`, and known test helper patterns.
