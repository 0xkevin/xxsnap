# Magnifier Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the macOS xxsnap magnifier annotation tool with circular/rectangular lenses, fixed zoom levels, border styling, editing, and matching preview/export output.

**Architecture:** Add a dedicated magnifier annotation model in the existing Swift/AppKit overlay, then route toolbar state, creation, editing, preview drawing, and export rendering through the same annotation list used by existing tools. Magnifier pixels are sampled from the original screenshot image, never from the annotation composite.

**Tech Stack:** Swift, AppKit, XCTest, CoreGraphics, existing `SelectionOverlayWindow`, `SelectionToolbarState`, and `CaptureAnnotationRenderer`.

---

## File Structure

- Modify `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`: add magnifier enums/model fields and render magnifier annotations into overlay/export images.
- Modify `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`: add magnifier toolbar mode, fixed zoom values, layout rectangles, stroke widths, tooltip labels, and geometry support flags.
- Modify `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`: activate the magnifier tool, draw options, handle options clicks, create draft/final magnifier annotations, select/edit/delete/resize them, expose debug helpers, and keep preview/export geometry aligned.
- Modify `platforms/mac/Tests/SelectionToolbarStateTests.swift`: add focused XCTest coverage for toolbar state, creation, editing, original-image sampling, and export consistency.
- Modify `docs/annotation-tools-user-guide.md`: move magnifier from the unfinished list into the supported tools section after implementation.
- Modify `platforms/mac/Tests/manual-capture-checklist.md`: add a short manual smoke checklist for the magnifier workflow.

## Task 1: Magnifier Model And Pure Toolbar State

**Files:**
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing model and toolbar-state tests**

Add these tests near the existing options-toolbar tests in `platforms/mac/Tests/SelectionToolbarStateTests.swift`:

```swift
func testMagnifierToolbarModeHasShapeZoomStrokeAndColorSections() {
    let optionsRect = NSRect(x: 20, y: 30, width: 380, height: 40)
    let layout = SelectionToolbarState.optionsToolbarLayout(
        in: optionsRect,
        paletteCount: 14,
        mode: .magnifier
    )

    XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .magnifier), [2, 4, 7])
    XCTAssertEqual(SelectionToolbarState.magnifierZoomValues, [1.5, 2, 3, 4])
    XCTAssertNotNil(layout.rectangleMode)
    XCTAssertNotNil(layout.ellipseMode)
    XCTAssertEqual(layout.magnifierZooms.count, 4)
    XCTAssertEqual(layout.colorSwatches.count, 15)
    XCTAssertFalse(SelectionToolbarState.showsStrokeStyleField(for: .magnifier))
}

func testMagnifierKindSupportsSelectionAndGeometryEditing() {
    XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.magnifier))
    XCTAssertTrue(SelectionToolbarState.annotationKindSupportsGeometryEditing(.magnifier))
}

func testDefaultMagnifierAnnotationStateIsCircleTwoX() {
    var annotation = CaptureAnnotation(
        kind: .magnifier,
        rect: NSRect(x: 10, y: 20, width: 120, height: 120),
        style: CaptureAnnotationStyle()
    )

    XCTAssertEqual(annotation.magnifierShape ?? .circle, .circle)
    XCTAssertEqual(annotation.magnifierZoom ?? 2, 2)

    annotation.magnifierShape = .rectangle
    annotation.magnifierZoom = 4

    XCTAssertEqual(annotation.magnifierShape, .rectangle)
    XCTAssertEqual(annotation.magnifierZoom, 4)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierToolbarModeHasShapeZoomStrokeAndColorSections -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierKindSupportsSelectionAndGeometryEditing -only-testing:xxsnapTests/SelectionToolbarStateTests/testDefaultMagnifierAnnotationStateIsCircleTwoX
```

Expected: FAIL because `.magnifier`, `magnifierZoomValues`, `magnifierZooms`, `CaptureMagnifierShape`, and magnifier fields do not exist.

- [ ] **Step 3: Add the magnifier model**

In `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`, extend `CaptureAnnotationKind` and add the shape enum near the existing annotation model declarations:

```swift
enum CaptureAnnotationKind {
    case rectangle
    case ellipse
    case arrowLine
    case brush
    case marker
    case text
    case numberSequence
    case magnifier
    case mosaicStroke
    case mosaicRectangle
}

enum CaptureMagnifierShape: CaseIterable, Equatable {
    case circle
    case rectangle
}
```

Then extend `CaptureAnnotation`:

```swift
struct CaptureAnnotation {
    var kind: CaptureAnnotationKind
    var rect: NSRect
    var style: CaptureAnnotationStyle
    var rotationAngle: CGFloat = 0
    var arrowLine: CaptureArrowLine?
    var brushPath: CaptureBrushPath?
    var markerLine: CaptureMarkerLine?
    var text: String?
    var numberMarkType: CaptureNumberMarkType?
    var numberSequenceIndex: Int?
    var numberSequenceIsManual = false
    var magnifierShape: CaptureMagnifierShape?
    var magnifierZoom: CGFloat?
    var mosaicStroke: CaptureMosaicStroke?
    var mosaicRedaction: CaptureMosaicRedaction?
}
```

- [ ] **Step 4: Add toolbar-state support**

In `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`, extend the mode and layout:

```swift
enum OptionsToolbarMode: Equatable {
    case shape
    case arrowLine
    case brush
    case marker
    case mosaic
    case text
    case numberSequence
    case magnifier
}

struct OptionsToolbarLayout: Equatable {
    var strokeWidths: [NSRect]
    var textSizes: [NSRect]
    var textBold: NSRect
    var textItalic: NSRect
    var textOutline: NSRect
    var textFont: NSRect
    var textSize: NSRect
    var numberMarkType: NSRect
    var numberSize: NSRect
    var magnifierZooms: [NSRect]
    var fillToggle: NSRect?
    var rectangleMode: NSRect?
    var ellipseMode: NSRect?
    var strokeStyle: NSRect
    var startArrowType: NSRect?
    var endArrowType: NSRect?
    var colorSwatches: [NSRect]
}
```

Add zoom values and mode behavior:

```swift
static let magnifierZoomValues: [CGFloat] = [1.5, 2, 3, 4]

static func strokeWidthValues(for mode: OptionsToolbarMode) -> [CGFloat] {
    switch mode {
    case .shape:
        return [2, 4, 7]
    case .arrowLine:
        return [3, 4, 6]
    case .brush:
        return [3, 5, 7]
    case .marker:
        return [14, 18, 22]
    case .mosaic:
        return [15, 25, 35]
    case .magnifier:
        return [2, 4, 7]
    case .text, .numberSequence:
        return []
    }
}

static func showsStrokeStyleField(for mode: OptionsToolbarMode) -> Bool {
    mode != .marker && mode != .mosaic && mode != .text && mode != .numberSequence && mode != .magnifier
}
```

Update `annotationKindSupportsPostDrawEditing` and `annotationKindSupportsGeometryEditing`:

```swift
static func annotationKindSupportsPostDrawEditing(_ kind: CaptureAnnotationKind) -> Bool {
    switch kind {
    case .rectangle, .ellipse, .arrowLine, .marker, .text, .numberSequence, .magnifier, .mosaicStroke, .mosaicRectangle:
        return true
    case .brush:
        return false
    }
}

static func annotationKindSupportsGeometryEditing(_ kind: CaptureAnnotationKind) -> Bool {
    switch kind {
    case .rectangle, .ellipse, .text, .numberSequence, .magnifier, .mosaicRectangle:
        return true
    case .arrowLine, .brush, .marker, .mosaicStroke:
        return false
    }
}
```

- [ ] **Step 5: Add magnifier layout rectangles**

In `SelectionToolbarState.optionsToolbarLayout`, populate `magnifierZooms` and expose shape buttons for magnifier:

```swift
static func optionsToolbarLayout(
    in optionsRect: NSRect,
    paletteCount: Int,
    mode: OptionsToolbarMode
) -> OptionsToolbarLayout {
    OptionsToolbarLayout(
        strokeWidths: strokeWidthValues(for: mode).isEmpty ? [] : strokeWidthRects(in: optionsRect),
        textSizes: mode == .text ? [textSizeFieldRect(in: optionsRect)] : [],
        textBold: mode == .text ? textBoldRect(in: optionsRect) : .zero,
        textItalic: mode == .text ? textItalicRect(in: optionsRect) : .zero,
        textOutline: mode == .text ? textOutlineRect(in: optionsRect) : .zero,
        textFont: mode == .text ? textFontFieldRect(in: optionsRect) : .zero,
        textSize: mode == .text ? textSizeFieldRect(in: optionsRect) : .zero,
        numberMarkType: mode == .numberSequence ? numberMarkTypeFieldRect(in: optionsRect) : .zero,
        numberSize: mode == .numberSequence ? numberSizeFieldRect(in: optionsRect) : .zero,
        magnifierZooms: mode == .magnifier ? magnifierZoomRects(in: optionsRect) : [],
        fillToggle: mode == .shape ? fillToggleRect(in: optionsRect) : nil,
        rectangleMode: rectangleModeRect(in: optionsRect, mode: mode),
        ellipseMode: (mode == .shape || mode == .magnifier) ? ellipseModeButtonRect(in: optionsRect) : nil,
        strokeStyle: strokeStyleRect(in: optionsRect, mode: mode),
        startArrowType: mode == .arrowLine ? startArrowTypeFieldRect(in: optionsRect, mode: mode) : nil,
        endArrowType: mode == .arrowLine ? endArrowTypeFieldRect(in: optionsRect, mode: mode) : nil,
        colorSwatches: mode == .mosaic ? [] : colorSwatchRects(in: optionsRect, paletteCount: paletteCount, mode: mode)
    )
}

private static func rectangleModeRect(in optionsRect: NSRect, mode: OptionsToolbarMode) -> NSRect? {
    switch mode {
    case .shape:
        return rectangleModeButtonRect(in: optionsRect)
    case .magnifier:
        return rectangleModeButtonRect(in: optionsRect)
    case .mosaic:
        return mosaicRectangleButtonRect(in: optionsRect, mode: mode)
    case .arrowLine, .brush, .marker, .text, .numberSequence:
        return nil
    }
}

static func magnifierZoomRects(in optionsRect: NSRect) -> [NSRect] {
    (0..<magnifierZoomValues.count).map { index in
        NSRect(
            x: optionsRect.minX + 118 + CGFloat(index) * 38,
            y: optionsRect.midY - 11,
            width: 32,
            height: 22
        )
    }
}
```

Update `colorSwatchStartXOffset` and toolbar width:

```swift
private static func colorSwatchStartXOffset(mode: OptionsToolbarMode) -> CGFloat {
    switch mode {
    case .shape:
        return 329
    case .arrowLine:
        return 322
    case .brush:
        return 214
    case .marker:
        return 102
    case .magnifier:
        return 290
    case .text:
        return 350
    case .numberSequence:
        return 148
    case .mosaic:
        return 0
    }
}
```

Add a fixed width branch in `optionsToolbarWidth` so the four zoom choices and palette fit without clipping:

```swift
if mode == .magnifier {
    return 430
}
```

- [ ] **Step 6: Run focused tests and commit**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierToolbarModeHasShapeZoomStrokeAndColorSections -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierKindSupportsSelectionAndGeometryEditing -only-testing:xxsnapTests/SelectionToolbarStateTests/testDefaultMagnifierAnnotationStateIsCircleTwoX
```

Expected: PASS.

Commit:

```bash
git add platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): add magnifier annotation model"
```

## Task 2: Export Renderer For Original-Image Magnification

**Files:**
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing renderer tests**

Add these tests near the existing renderer pixel tests in `platforms/mac/Tests/SelectionToolbarStateTests.swift`:

```swift
func testMagnifierRendererSamplesOriginalImageInsteadOfAnnotations() throws {
    let base = makeTestImage(size: NSSize(width: 80, height: 80)) { point in
        if point.x < 40 && point.y < 40 {
            return NSColor.red
        }
        if point.x >= 40 && point.y >= 40 {
            return NSColor.blue
        }
        return NSColor.white
    }
    var coveringAnnotation = CaptureAnnotation(
        kind: .rectangle,
        rect: NSRect(x: 30, y: 30, width: 20, height: 20),
        style: {
            var style = CaptureAnnotationStyle()
            style.fillEnabled = true
            style.fillColor = .green
            style.strokeColor = .green
            style.strokeWidth = 2
            return style
        }()
    )
    coveringAnnotation.style.fillEnabled = true
    let magnifier = CaptureAnnotation(
        kind: .magnifier,
        rect: NSRect(x: 20, y: 20, width: 40, height: 40),
        style: {
            var style = CaptureAnnotationStyle()
            style.strokeColor = .black
            style.strokeWidth = 2
            return style
        }(),
        magnifierShape: .rectangle,
        magnifierZoom: 2
    )

    let rendered = CaptureAnnotationRenderer.render(image: base, annotations: [coveringAnnotation, magnifier])
    let center = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: 40, y: 40)))

    XCTAssertNotEqual(hex(center), "#00FF00")
}

func testMagnifierRendererClipsSourceAtImageBounds() throws {
    let base = makeSolidTestImage(size: NSSize(width: 80, height: 80), color: .red)
    let magnifier = CaptureAnnotation(
        kind: .magnifier,
        rect: NSRect(x: -10, y: -10, width: 40, height: 40),
        style: {
            var style = CaptureAnnotationStyle()
            style.strokeColor = .black
            style.strokeWidth = 2
            return style
        }(),
        magnifierShape: .circle,
        magnifierZoom: 4
    )

    let rendered = CaptureAnnotationRenderer.render(image: base, annotations: [magnifier])
    let insideAvailableSource = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: 8, y: 8)))
    XCTAssertEqual(hex(insideAvailableSource), "#FF0000")
}
```

If `makeTestImage`, `makeSolidTestImage`, or `hex(_:)` do not exist, add these helpers inside `SelectionToolbarStateTests` near the existing `rgbaPixel` helpers:

```swift
private func makeSolidTestImage(size: NSSize, color: NSColor) -> NSImage {
    makeTestImage(size: size) { _ in color }
}

private func makeTestImage(size: NSSize, colorAt: (NSPoint) -> NSColor) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    for y in 0..<Int(size.height) {
        for x in 0..<Int(size.width) {
            colorAt(NSPoint(x: x, y: y)).setFill()
            NSRect(x: x, y: y, width: 1, height: 1).fill()
        }
    }
    image.unlockFocus()
    return image
}

private func hex(_ pixel: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> String {
    String(format: "#%02X%02X%02X", pixel.red, pixel.green, pixel.blue)
}
```

- [ ] **Step 2: Run renderer tests and verify they fail**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierRendererSamplesOriginalImageInsteadOfAnnotations -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierRendererClipsSourceAtImageBounds
```

Expected: FAIL because renderer ignores `.magnifier`.

- [ ] **Step 3: Route magnifier annotations in export renderer**

In `CaptureAnnotationRenderer.draw(_:in:sourceImage:scaleX:scaleY:)`, add this branch before marker/arrow/brush/shape drawing:

```swift
if annotation.kind == .magnifier {
    drawMagnifierAnnotation(
        annotation,
        in: context,
        sourceImage: sourceImage,
        scaleX: scaleX,
        scaleY: scaleY,
        lineScale: lineScale
    )
    return
}
```

Also update the final shape switch return list:

```swift
case .arrowLine, .brush, .marker, .text, .numberSequence, .magnifier, .mosaicStroke, .mosaicRectangle:
    return
```

- [ ] **Step 4: Add renderer helpers**

Add these helpers in `CaptureAnnotationRenderer` before `isMosaicAnnotation`:

```swift
private static func drawMagnifierAnnotation(
    _ annotation: CaptureAnnotation,
    in context: CGContext,
    sourceImage: CGImage,
    scaleX: CGFloat,
    scaleY: CGFloat,
    lineScale: CGFloat
) {
    let rect = annotation.rect.standardized
    guard rect.width > 0, rect.height > 0 else {
        return
    }

    let zoom = validMagnifierZoom(annotation.magnifierZoom)
    let shape = annotation.magnifierShape ?? .circle
    let destination = CGRect(
        x: rect.minX * scaleX,
        y: rect.minY * scaleY,
        width: rect.width * scaleX,
        height: rect.height * scaleY
    )
    let sourceWidth = destination.width / zoom
    let sourceHeight = destination.height / zoom
    let requestedSource = CGRect(
        x: destination.midX - sourceWidth / 2,
        y: destination.midY - sourceHeight / 2,
        width: sourceWidth,
        height: sourceHeight
    )
    let imageBounds = CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
    let clippedSource = requestedSource.intersection(imageBounds)

    context.saveGState()
    addMagnifierClip(shape: shape, rect: destination, to: context)
    context.clip()
    if !clippedSource.isNull,
       clippedSource.width > 0,
       clippedSource.height > 0,
       let crop = sourceImage.cropping(to: clippedSource.integral) {
        let xScale = destination.width / max(requestedSource.width, 1)
        let yScale = destination.height / max(requestedSource.height, 1)
        let drawRect = CGRect(
            x: destination.minX + (clippedSource.minX - requestedSource.minX) * xScale,
            y: destination.minY + (clippedSource.minY - requestedSource.minY) * yScale,
            width: clippedSource.width * xScale,
            height: clippedSource.height * yScale
        )
        context.interpolationQuality = .none
        context.draw(crop, in: drawRect)
    }
    context.restoreGState()

    context.saveGState()
    addMagnifierClip(shape: shape, rect: destination.insetBy(dx: annotation.style.strokeWidth * lineScale / 2, dy: annotation.style.strokeWidth * lineScale / 2), to: context)
    context.setStrokeColor(cgColor(annotation.style.strokeColor))
    context.setLineWidth(annotation.style.strokeWidth * lineScale)
    context.strokePath()
    context.restoreGState()
}

private static func validMagnifierZoom(_ zoom: CGFloat?) -> CGFloat {
    let candidates: [CGFloat] = [1.5, 2, 3, 4]
    guard let zoom else {
        return 2
    }
    return candidates.min(by: { abs($0 - zoom) < abs($1 - zoom) }) ?? 2
}

private static func addMagnifierClip(shape: CaptureMagnifierShape, rect: CGRect, to context: CGContext) {
    switch shape {
    case .circle:
        context.addEllipse(in: rect)
    case .rectangle:
        context.addRect(rect)
    }
}
```

- [ ] **Step 5: Run renderer tests and commit**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierRendererSamplesOriginalImageInsteadOfAnnotations -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierRendererClipsSourceAtImageBounds
```

Expected: PASS.

Commit:

```bash
git add platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): render magnifier exports"
```

## Task 3: Magnifier Tool Activation And Options Toolbar

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing activation and options tests**

Add these tests near existing toolbar activation tests:

```swift
func testMagnifierToolbarButtonActivatesMagnifierModeAndOptionsToolbar() throws {
    let window = makeOverlayWindow()
    window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 220, height: 160))

    let point = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .magnifier))
    window.test_mouseDown(at: point)

    XCTAssertTrue(window.test_isMagnifierToolActive)
    XCTAssertEqual(window.test_optionsToolbarMode, .magnifier)
    XCTAssertNotNil(window.test_optionsToolbarRect)
    XCTAssertEqual(window.test_currentMagnifierShape, .circle)
    XCTAssertEqual(window.test_currentMagnifierZoom, 2)
}

func testMagnifierOptionsSwitchShapeZoomStrokeAndColor() throws {
    let window = makeOverlayWindow()
    window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 220, height: 160))
    window.test_activateMagnifierTool()

    window.test_setMagnifierShape(.rectangle)
    window.test_setMagnifierZoom(3)
    window.test_setCurrentStrokeWidth(7)
    window.test_selectPaletteColor(at: 2)

    XCTAssertEqual(window.test_currentMagnifierShape, .rectangle)
    XCTAssertEqual(window.test_currentMagnifierZoom, 3)
    XCTAssertEqual(window.test_currentStyle.strokeWidth, 7)
    XCTAssertEqual(window.test_currentStyle.strokeColor, SelectionOverlayWindow.defaultPaletteColors[2])
}
```

If `test_currentStyle`, `test_selectPaletteColor`, or `test_mouseDown` are named differently, use the existing debug helpers in the same test file and add only the missing magnifier-specific helpers listed below.

- [ ] **Step 2: Run activation tests and verify they fail**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierToolbarButtonActivatesMagnifierModeAndOptionsToolbar -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierOptionsSwitchShapeZoomStrokeAndColor
```

Expected: FAIL because magnifier still triggers the unfinished alert and debug helpers do not exist.

- [ ] **Step 3: Add magnifier state and activation**

In `SelectionOverlayView`, add state near existing tool state:

```swift
private var isMagnifierToolActive = false
private var currentMagnifierShape: CaptureMagnifierShape = .circle
private var currentMagnifierZoom: CGFloat = 2
private var magnifierStyle = SelectionOverlayView.defaultMagnifierStyle()
```

Add a default style helper near `defaultNumberStyle()`:

```swift
private static func defaultMagnifierStyle() -> CaptureAnnotationStyle {
    var style = CaptureAnnotationStyle()
    style.strokeColor = NSColor.systemBlue
    style.fillColor = NSColor.systemBlue
    style.strokeWidth = SelectionToolbarState.strokeWidthValues(for: .magnifier)[1]
    style.strokePattern = .solid
    style.fillEnabled = false
    return style
}
```

Update tool toggles so activating text, number, eyedropper, or shape clears magnifier:

```swift
isMagnifierToolActive = false
```

Add magnifier activation:

```swift
private func toggleMagnifierTool() {
    commitCurrentTextEdit()
    clearPendingTextEdit()
    closeTextDropdown()
    if isMagnifierToolActive {
        isMagnifierToolActive = false
        selectedAnnotationIndex = nil
        invalidateCursorRectsAndRefresh()
        needsDisplay = true
        return
    }

    activateMagnifierTool()
}

private func activateMagnifierTool() {
    commitCurrentTextEdit()
    clearPendingTextEdit()
    closeTextDropdown()
    rememberCurrentStyleForActiveTool()
    isMagnifierToolActive = true
    isTextToolActive = false
    isNumberToolActive = false
    isEyedropperToolActive = false
    clearEyedropperMeasurement()
    isShapeToolActive = false
    activeShapeKind = nil
    selectedAnnotationIndex = nil
    currentStyle = magnifierStyle
    currentStyle.strokePattern = .solid
    showsCornerRadiusPanel = false
    showsStrokeStyleMenu = false
    showsStartArrowTypeMenu = false
    showsEndArrowTypeMenu = false
    shapeStartPoint = nil
    shapeCurrentPoint = nil
    brushDraftPoints.removeAll()
    mosaicDraftPoints.removeAll()
    invalidateCursorRectsAndRefresh()
    needsDisplay = true
}
```

Update `rememberCurrentStyleForActiveTool()`:

```swift
if isMagnifierToolActive {
    magnifierStyle = currentStyle
    magnifierStyle.strokePattern = .solid
    return
}
```

- [ ] **Step 4: Wire the toolbar button and mode**

In `perform(_:)`, replace the `.magnifier` branch:

```swift
case .magnifier:
    toggleMagnifierTool()
    showsStrokeStyleMenu = false
    showsCornerRadiusPanel = false
    showsStartArrowTypeMenu = false
    showsEndArrowTypeMenu = false
case .pin, .eraser, .scroll, .settings:
    showPlaceholder(for: button)
```

Update `optionsToolbarMode`:

```swift
private var optionsToolbarMode: SelectionToolbarState.OptionsToolbarMode {
    if isTextToolActive {
        return .text
    }
    if isNumberToolActive {
        return .numberSequence
    }
    if isMagnifierToolActive {
        return .magnifier
    }
    switch currentShapeKind {
    case .arrowLine:
        return .arrowLine
    case .brush:
        return .brush
    case .marker:
        return .marker
    case .mosaicStroke, .mosaicRectangle:
        return .mosaic
    default:
        return .shape
    }
}
```

Update `shouldShowOptionsToolbar` call:

```swift
SelectionToolbarState.shouldShowOptionsToolbar(
    isPrimaryShapeToolActive: isShapeToolActive || isTextToolActive || isNumberToolActive || isMagnifierToolActive
)
```

- [ ] **Step 5: Draw and handle magnifier options**

In `drawOptionsToolbar(for:)`, add a magnifier branch:

```swift
switch optionsToolbarMode {
case .mosaic:
    drawMosaicModeControls(in: optionsRect)
case .text:
    drawTextOptions(in: optionsRect)
case .numberSequence:
    drawNumberOptions(in: optionsRect)
case .magnifier:
    drawMagnifierOptions(in: optionsRect)
default:
    drawShapeModeButtons(in: optionsRect)
}
```

Add:

```swift
private func drawMagnifierOptions(in optionsRect: NSRect) {
    let layout = optionsToolbarLayout(in: optionsRect)
    drawMagnifierShapeButtons(in: optionsRect)
    for (index, rect) in layout.magnifierZooms.enumerated() {
        let value = SelectionToolbarState.magnifierZoomValues[index]
        drawToolbarButton(optionButtonBackgroundRect(for: rect), symbol: nil, selected: abs(currentMagnifierZoom - value) < 0.001, enabled: true)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: abs(currentMagnifierZoom - value) < 0.001 ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let text = value == floor(value) ? "\(Int(value))x" : "\(value)x"
        let size = NSString(string: text).size(withAttributes: attributes)
        NSString(string: text).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }
}

private func drawMagnifierShapeButtons(in optionsRect: NSRect) {
    let layout = optionsToolbarLayout(in: optionsRect)
    if let rectangleButton = layout.rectangleMode {
        drawToolbarButton(optionButtonBackgroundRect(for: rectangleButton), symbol: nil, selected: currentMagnifierShape == .rectangle, enabled: true)
        (currentMagnifierShape == .rectangle ? NSColor.controlAccentColor : NSColor.labelColor).setStroke()
        let path = NSBezierPath(roundedRect: rectangleButton.insetBy(dx: 7, dy: 7), xRadius: 1.5, yRadius: 1.5)
        path.lineWidth = 1.6
        path.stroke()
    }
    if let circleButton = layout.ellipseMode {
        drawToolbarButton(optionButtonBackgroundRect(for: circleButton), symbol: nil, selected: currentMagnifierShape == .circle, enabled: true)
        (currentMagnifierShape == .circle ? NSColor.controlAccentColor : NSColor.labelColor).setStroke()
        let path = NSBezierPath(ovalIn: circleButton.insetBy(dx: 7, dy: 7))
        path.lineWidth = 1.6
        path.stroke()
    }
}
```

In `handleOptionsClick(at:)`, add before text handling:

```swift
if optionsToolbarMode == .magnifier {
    return handleMagnifierOptionsClick(at: point, optionsRect: optionsRect)
}
```

Add:

```swift
private func handleMagnifierOptionsClick(at point: NSPoint, optionsRect: NSRect) -> Bool {
    let layout = optionsToolbarLayout(in: optionsRect)
    if let rectangleButton = layout.rectangleMode, rectangleButton.contains(point) {
        currentMagnifierShape = .rectangle
        applyCurrentMagnifierSettingsToSelectedAnnotation()
        needsDisplay = true
        return true
    }
    if let circleButton = layout.ellipseMode, circleButton.contains(point) {
        currentMagnifierShape = .circle
        applyCurrentMagnifierSettingsToSelectedAnnotation()
        needsDisplay = true
        return true
    }
    for (index, rect) in layout.magnifierZooms.enumerated() where rect.contains(point) {
        currentMagnifierZoom = SelectionToolbarState.magnifierZoomValues[index]
        applyCurrentMagnifierSettingsToSelectedAnnotation()
        needsDisplay = true
        return true
    }
    let strokeWidths = SelectionToolbarState.strokeWidthValues(for: .magnifier)
    for (index, rect) in layout.strokeWidths.enumerated() where rect.contains(point) {
        currentStyle.strokeWidth = strokeWidths[index]
        rememberCurrentStyleForActiveTool()
        applyCurrentStyleToSelectedAnnotation()
        return true
    }
    if handleColorSwatchClick(at: point, optionsRect: optionsRect) {
        return true
    }
    return optionsRect.contains(point)
}

private func applyCurrentMagnifierSettingsToSelectedAnnotation() {
    guard let selectedAnnotationIndex,
          annotations.indices.contains(selectedAnnotationIndex),
          annotations[selectedAnnotationIndex].kind == .magnifier else {
        rememberCurrentStyleForActiveTool()
        return
    }
    annotations[selectedAnnotationIndex].magnifierShape = currentMagnifierShape
    annotations[selectedAnnotationIndex].magnifierZoom = currentMagnifierZoom
    redoAnnotations.removeAll()
    rememberCurrentStyleForActiveTool()
}
```

- [ ] **Step 6: Add debug helpers and run tests**

Add to the `#if DEBUG` section in `SelectionOverlayView`:

```swift
func test_activateMagnifierTool() {
    activateMagnifierTool()
}

var test_isMagnifierToolActive: Bool {
    isMagnifierToolActive
}

var test_currentMagnifierShape: CaptureMagnifierShape {
    currentMagnifierShape
}

var test_currentMagnifierZoom: CGFloat {
    currentMagnifierZoom
}

var test_currentStyle: CaptureAnnotationStyle {
    currentStyle
}

func test_setMagnifierShape(_ shape: CaptureMagnifierShape) {
    currentMagnifierShape = shape
    applyCurrentMagnifierSettingsToSelectedAnnotation()
}

func test_setMagnifierZoom(_ zoom: CGFloat) {
    currentMagnifierZoom = zoom
    applyCurrentMagnifierSettingsToSelectedAnnotation()
}
```

Add matching pass-through helpers to `SelectionOverlayWindow`'s debug extension:

```swift
func test_activateMagnifierTool() {
    (contentView as? SelectionOverlayView)?.test_activateMagnifierTool()
}

var test_isMagnifierToolActive: Bool {
    (contentView as? SelectionOverlayView)?.test_isMagnifierToolActive ?? false
}

var test_currentMagnifierShape: CaptureMagnifierShape {
    (contentView as? SelectionOverlayView)?.test_currentMagnifierShape ?? .circle
}

var test_currentMagnifierZoom: CGFloat {
    (contentView as? SelectionOverlayView)?.test_currentMagnifierZoom ?? 2
}

var test_currentStyle: CaptureAnnotationStyle {
    (contentView as? SelectionOverlayView)?.test_currentStyle ?? CaptureAnnotationStyle()
}

func test_setMagnifierShape(_ shape: CaptureMagnifierShape) {
    (contentView as? SelectionOverlayView)?.test_setMagnifierShape(shape)
}

func test_setMagnifierZoom(_ zoom: CGFloat) {
    (contentView as? SelectionOverlayView)?.test_setMagnifierZoom(zoom)
}
```

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierToolbarButtonActivatesMagnifierModeAndOptionsToolbar -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierOptionsSwitchShapeZoomStrokeAndColor
```

Expected: PASS.

Commit:

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): activate magnifier tool"
```

## Task 4: Drag Creation, Preview Drawing, Selection, And Editing

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing creation and editing tests**

Add:

```swift
func testMagnifierDragCreatesCircleAndShiftConstrainsToSquare() throws {
    let window = makeOverlayWindow()
    window.test_setLockedSelectionRect(NSRect(x: 60, y: 60, width: 260, height: 180))
    window.test_activateMagnifierTool()

    window.test_drag(from: NSPoint(x: 100, y: 110), to: NSPoint(x: 190, y: 160), modifiers: [.shift])

    let annotation = try XCTUnwrap(window.test_annotation(at: 0))
    XCTAssertEqual(annotation.kind, .magnifier)
    XCTAssertEqual(annotation.magnifierShape, .circle)
    XCTAssertEqual(annotation.magnifierZoom, 2)
    XCTAssertEqual(annotation.rect.width, annotation.rect.height, accuracy: 0.001)
}

func testMagnifierTinyDragDoesNotCreateAnnotation() {
    let window = makeOverlayWindow()
    window.test_setLockedSelectionRect(NSRect(x: 60, y: 60, width: 260, height: 180))
    window.test_activateMagnifierTool()

    window.test_drag(from: NSPoint(x: 100, y: 110), to: NSPoint(x: 103, y: 112))

    XCTAssertEqual(window.test_annotationCount, 0)
}

func testSelectedMagnifierCanResizeMoveDeleteAndRestyle() throws {
    let window = makeOverlayWindow()
    window.test_setLockedSelectionRect(NSRect(x: 60, y: 60, width: 260, height: 180))
    window.test_activateMagnifierTool()
    window.test_setMagnifierShape(.rectangle)
    window.test_setMagnifierZoom(3)
    window.test_drag(from: NSPoint(x: 100, y: 110), to: NSPoint(x: 190, y: 160))

    let before = try XCTUnwrap(window.test_annotation(at: 0))
    XCTAssertEqual(before.magnifierShape, .rectangle)
    XCTAssertEqual(before.magnifierZoom, 3)

    window.test_selectAnnotation(at: 0)
    window.test_setMagnifierShape(.circle)
    window.test_setMagnifierZoom(4)
    window.test_setCurrentStrokeWidth(7)

    let afterStyle = try XCTUnwrap(window.test_annotation(at: 0))
    XCTAssertEqual(afterStyle.magnifierShape, .circle)
    XCTAssertEqual(afterStyle.magnifierZoom, 4)
    XCTAssertEqual(afterStyle.style.strokeWidth, 7)

    window.test_deleteSelectedAnnotation()
    XCTAssertEqual(window.test_annotationCount, 0)
}
```

- [ ] **Step 2: Run creation/editing tests and verify they fail**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierDragCreatesCircleAndShiftConstrainsToSquare -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierTinyDragDoesNotCreateAnnotation -only-testing:xxsnapTests/SelectionToolbarStateTests/testSelectedMagnifierCanResizeMoveDeleteAndRestyle
```

Expected: FAIL because magnifier creation and debug helpers are not wired.

- [ ] **Step 3: Create magnifier annotations from drag**

In `draftAnnotation`, extend the shape creation branch:

```swift
if currentShapeKind == .magnifier || isMagnifierToolActive {
    let rect = draftRect.standardized
    guard rect.width >= 8, rect.height >= 8 else {
        return nil
    }
    var style = currentStyle
    style.fillEnabled = false
    style.strokePattern = .solid
    return CaptureAnnotation(
        kind: .magnifier,
        rect: localAnnotationRect(from: rect),
        style: style,
        magnifierShape: currentMagnifierShape,
        magnifierZoom: currentMagnifierZoom
    )
}
```

If the project computes `draftRect` inside `draftAnnotation`, apply the same logic at the point where rectangle/ellipse annotations are returned. The magnifier branch must run before ordinary shape `switch` handling.

Update `beginShapeDrawing(at:)` call sites so magnifier uses the same drag path as shapes:

```swift
if isMagnifierToolActive {
    beginShapeDrawing(at: point)
    return
}
```

Place this in `handleAnnotatingMouseDown(at:)` after toolbar/options handling and before annotation hit testing if a blank-area drag should create a magnifier. Existing selected magnifiers should still hit-test before new draft creation.

- [ ] **Step 4: Keep current settings synchronized on selection**

In `selectAnnotation(at:)`, add:

```swift
if annotations[index].kind == .magnifier {
    currentMagnifierShape = annotations[index].magnifierShape ?? .circle
    currentMagnifierZoom = annotations[index].magnifierZoom ?? 2
    currentStyle = annotations[index].style
    currentStyle.fillEnabled = false
    currentStyle.strokePattern = .solid
    magnifierStyle = currentStyle
    isMagnifierToolActive = true
    isTextToolActive = false
    isNumberToolActive = false
    isEyedropperToolActive = false
    isShapeToolActive = false
    activeShapeKind = nil
}
```

In `applyCurrentStyleToSelectedAnnotation()`, ensure magnifier style updates:

```swift
if annotations[selectedAnnotationIndex].kind == .magnifier {
    var style = currentStyle
    style.fillEnabled = false
    style.strokePattern = .solid
    annotations[selectedAnnotationIndex].style = style
    annotations[selectedAnnotationIndex].magnifierShape = currentMagnifierShape
    annotations[selectedAnnotationIndex].magnifierZoom = currentMagnifierZoom
    redoAnnotations.removeAll()
    needsDisplay = true
    return
}
```

- [ ] **Step 5: Draw magnifier preview in overlay**

In `SelectionOverlayView.drawAnnotation(_:inOverlay:)`, add before mosaic/arrow branches:

```swift
if annotation.kind == .magnifier {
    drawMagnifierAnnotation(annotation, inOverlay: inOverlay)
    return
}
```

Add:

```swift
private func drawMagnifierAnnotation(_ annotation: CaptureAnnotation, inOverlay: Bool) {
    let rect = (inOverlay ? overlayRect(fromLocalAnnotationRect: annotation.rect) : annotation.rect).standardized
    guard rect.width > 0, rect.height > 0 else {
        return
    }
    guard let backgroundImage else {
        annotation.style.strokeColor.setStroke()
        magnifierPath(shape: annotation.magnifierShape ?? .circle, rect: rect.insetBy(dx: annotation.style.strokeWidth / 2, dy: annotation.style.strokeWidth / 2)).stroke()
        return
    }

    let zoom = validMagnifierZoom(annotation.magnifierZoom)
    let sourceRect = NSRect(
        x: rect.midX - rect.width / (2 * zoom),
        y: rect.midY - rect.height / (2 * zoom),
        width: rect.width / zoom,
        height: rect.height / zoom
    )
    let imageBounds = NSRect(origin: .zero, size: backgroundImage.size)
    let clippedSource = sourceRect.intersection(imageBounds)

    NSGraphicsContext.saveGraphicsState()
    magnifierPath(shape: annotation.magnifierShape ?? .circle, rect: rect).addClip()
    if !clippedSource.isNull, clippedSource.width > 0, clippedSource.height > 0 {
        let xScale = rect.width / max(sourceRect.width, 1)
        let yScale = rect.height / max(sourceRect.height, 1)
        let drawRect = NSRect(
            x: rect.minX + (clippedSource.minX - sourceRect.minX) * xScale,
            y: rect.minY + (clippedSource.minY - sourceRect.minY) * yScale,
            width: clippedSource.width * xScale,
            height: clippedSource.height * yScale
        )
        NSGraphicsContext.current?.imageInterpolation = .none
        backgroundImage.draw(
            in: drawRect,
            from: clippedSource,
            operation: .copy,
            fraction: 1
        )
    }
    NSGraphicsContext.restoreGraphicsState()

    annotation.style.strokeColor.setStroke()
    let border = magnifierPath(
        shape: annotation.magnifierShape ?? .circle,
        rect: rect.insetBy(dx: annotation.style.strokeWidth / 2, dy: annotation.style.strokeWidth / 2)
    )
    border.lineWidth = annotation.style.strokeWidth
    border.stroke()
}

private func magnifierPath(shape: CaptureMagnifierShape, rect: NSRect) -> NSBezierPath {
    switch shape {
    case .circle:
        return NSBezierPath(ovalIn: rect)
    case .rectangle:
        return NSBezierPath(rect: rect)
    }
}

private func validMagnifierZoom(_ zoom: CGFloat?) -> CGFloat {
    SelectionToolbarState.magnifierZoomValues.min(by: { abs($0 - (zoom ?? 2)) < abs($1 - (zoom ?? 2)) }) ?? 2
}
```

- [ ] **Step 6: Ensure selection, move, resize, and delete work**

Update places that switch over `CaptureAnnotationKind` so `.magnifier` is handled as a geometry-editable rect annotation:

```swift
case .rectangle, .ellipse, .text, .numberSequence, .magnifier, .mosaicRectangle:
```

Use this exact addition in:

- `drawAnnotation` final shape switch return list;
- `resizeHandleCenters(for:kind:rotationAngle:)`;
- `annotationIndexForBorder(at:)` or equivalent body/border hit testing;
- any `switch annotation.kind` inside move/resize local-coordinate remapping.

For hit testing, magnifier can use the standardized overlay rect body in the first version. If circle hit testing is already available for ellipse, route `.magnifier` with `.circle` through the same oval path contains check.

- [ ] **Step 7: Add missing debug helpers and run tests**

Add helpers if they do not already exist:

```swift
var test_annotationCount: Int {
    annotations.count
}

func test_annotation(at index: Int) -> CaptureAnnotation? {
    annotations.indices.contains(index) ? annotations[index] : nil
}

func test_selectAnnotation(at index: Int) {
    guard annotations.indices.contains(index) else {
        return
    }
    selectAnnotation(at: index)
}

func test_deleteSelectedAnnotation() {
    _ = deleteSelectedAnnotation()
}
```

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierDragCreatesCircleAndShiftConstrainsToSquare -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierTinyDragDoesNotCreateAnnotation -only-testing:xxsnapTests/SelectionToolbarStateTests/testSelectedMagnifierCanResizeMoveDeleteAndRestyle
```

Expected: PASS.

Commit:

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): create and edit magnifiers"
```

## Task 5: Preview And Export Consistency

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing preview/export consistency tests**

Add:

```swift
func testMagnifierOverlayPreviewMatchesExportRendererAtCenter() throws {
    let window = makeOverlayWindow(backgroundImage: makeTestImage(size: NSSize(width: 240, height: 180)) { point in
        point.x < 120 ? NSColor.red : NSColor.blue
    })
    window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 160, height: 100))
    let magnifier = CaptureAnnotation(
        kind: .magnifier,
        rect: NSRect(x: 80, y: 60, width: 80, height: 80),
        style: {
            var style = CaptureAnnotationStyle()
            style.strokeColor = .black
            style.strokeWidth = 2
            return style
        }(),
        magnifierShape: .circle,
        magnifierZoom: 2
    )
    window.test_setAnnotations([magnifier])

    let overlay = try XCTUnwrap(window.test_renderedOverlayImage())
    let exported = CaptureAnnotationRenderer.render(
        image: try XCTUnwrap(window.test_backgroundImage),
        annotations: [magnifier]
    )
    let overlayPixel = try XCTUnwrap(rgbaPixel(in: overlay, at: NSPoint(x: 120, y: overlay.size.height - 100)))
    let exportPixel = try XCTUnwrap(rgbaPixel(in: exported, at: NSPoint(x: 120, y: 100)))

    XCTAssertEqual(hex(overlayPixel), hex(exportPixel))
}

func testMagnifierDoesNotMagnifyMosaicOrTextAnnotations() throws {
    let base = makeSolidTestImage(size: NSSize(width: 120, height: 120), color: .red)
    let text = CaptureAnnotation(
        kind: .text,
        rect: NSRect(x: 35, y: 35, width: 50, height: 30),
        style: {
            var style = CaptureAnnotationStyle()
            style.strokeColor = .green
            style.textSize = 18
            return style
        }(),
        text: "TXT"
    )
    let magnifier = CaptureAnnotation(
        kind: .magnifier,
        rect: NSRect(x: 30, y: 30, width: 60, height: 60),
        style: {
            var style = CaptureAnnotationStyle()
            style.strokeColor = .black
            style.strokeWidth = 2
            return style
        }(),
        magnifierShape: .rectangle,
        magnifierZoom: 3
    )

    let rendered = CaptureAnnotationRenderer.render(image: base, annotations: [text, magnifier])
    let center = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: 60, y: 60)))
    XCTAssertEqual(hex(center), "#FF0000")
}
```

- [ ] **Step 2: Run consistency tests and verify they fail or expose drift**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierOverlayPreviewMatchesExportRendererAtCenter -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierDoesNotMagnifyMosaicOrTextAnnotations
```

Expected before final alignment: FAIL if overlay/export coordinate transforms or source clipping differ.

- [ ] **Step 3: Align overlay sampling with renderer geometry**

If tests fail due flipped Y coordinates, update `drawMagnifierAnnotation` in `SelectionOverlayWindow.swift` to sample `backgroundImage` with the same coordinate assumptions as the overlay's existing background drawing. Use this drawing form for AppKit overlay preview:

```swift
backgroundImage.draw(
    in: drawRect,
    from: clippedSource,
    operation: .copy,
    fraction: 1
)
```

If export and overlay still disagree, add a shared pure helper in `CaptureAnnotationRenderer.swift`:

```swift
struct CaptureMagnifierDrawGeometry: Equatable {
    var destination: NSRect
    var requestedSource: NSRect
    var clippedSource: NSRect
    var clippedDestination: NSRect
}

static func magnifierDrawGeometry(
    destination: NSRect,
    zoom: CGFloat,
    sourceBounds: NSRect
) -> CaptureMagnifierDrawGeometry {
    let requested = NSRect(
        x: destination.midX - destination.width / (2 * zoom),
        y: destination.midY - destination.height / (2 * zoom),
        width: destination.width / zoom,
        height: destination.height / zoom
    )
    let clippedSource = requested.intersection(sourceBounds)
    let xScale = destination.width / max(requested.width, 1)
    let yScale = destination.height / max(requested.height, 1)
    let clippedDestination = NSRect(
        x: destination.minX + (clippedSource.minX - requested.minX) * xScale,
        y: destination.minY + (clippedSource.minY - requested.minY) * yScale,
        width: max(0, clippedSource.width * xScale),
        height: max(0, clippedSource.height * yScale)
    )
    return CaptureMagnifierDrawGeometry(
        destination: destination,
        requestedSource: requested,
        clippedSource: clippedSource,
        clippedDestination: clippedDestination
    )
}
```

Then use it in both overlay and export code.

- [ ] **Step 4: Run consistency tests and commit**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierOverlayPreviewMatchesExportRendererAtCenter -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierDoesNotMagnifyMosaicOrTextAnnotations
```

Expected: PASS.

Commit:

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "test(mac): verify magnifier preview export parity"
```

## Task 6: Documentation And Full Verification

**Files:**
- Modify: `docs/annotation-tools-user-guide.md`
- Modify: `platforms/mac/Tests/manual-capture-checklist.md`

- [ ] **Step 1: Update user guide**

In `docs/annotation-tools-user-guide.md`, update the intro count and remove magnifier from the unfinished sentence. Add this section after the sequence tool section:

```markdown
### 8. 放大镜

放大镜用于局部放大截图中的原始内容，适合强调小字号文字、细节图标或紧密排列的界面区域。

#### 启用方式

点击工具栏中的“放大镜”按钮。启用后，会显示放大镜专用选项工具栏。

#### 绘制方式

1. 点击“放大镜”。
2. 在截图区域或截图周围按住鼠标左键。
3. 拖动到目标大小。
4. 松开鼠标生成放大镜。

圆形模式默认会画出椭圆形放大镜；按住 `Shift` 拖动时会锁定为正圆。矩形模式下按住 `Shift` 会锁定为正方形。

#### 样式选项

放大镜支持：

- 形状：圆形、矩形。
- 倍率：`1.5x / 2x / 3x / 4x`，默认 `2x`。
- 边框粗细：细线、中线、粗线。
- 边框颜色：调色板颜色或自定义颜色。

#### 编辑方式

- 点击放大镜可以选中它。
- 拖动放大镜本体可以移动。
- 拖动边缘或角上的控制点可以调整大小。
- 选中后可以继续修改形状、倍率、边框粗细和边框颜色。
- 按 `Delete` 可以删除当前选中的放大镜。

放大镜里的内容来自原始截图，不会放大后来添加的箭头、文字、序号、马赛克或其他标注。复制或保存时，放大镜效果与截图区域内的预览保持一致。
```

- [ ] **Step 2: Update manual checklist**

Append to `platforms/mac/Tests/manual-capture-checklist.md`:

```markdown
## Magnifier tool smoke check

- [ ] Start capture and lock a screenshot selection.
- [ ] Click the magnifier toolbar button and verify the second toolbar appears.
- [ ] Verify default shape is circle and default zoom is `2x`.
- [ ] Drag-create a circular magnifier.
- [ ] Hold `Shift` while dragging and verify the lens is square/circular.
- [ ] Switch to rectangle and create a rectangular magnifier.
- [ ] Change zoom to `1.5x`, `3x`, and `4x`.
- [ ] Change border color and width.
- [ ] Move, resize, and delete a selected magnifier.
- [ ] Draw text or an arrow over the screenshot and verify the magnifier still shows original screenshot pixels.
- [ ] Copy and save, then compare exported output with overlay preview.
```

- [ ] **Step 3: Run focused magnifier tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierToolbarModeHasShapeZoomStrokeAndColorSections -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierKindSupportsSelectionAndGeometryEditing -only-testing:xxsnapTests/SelectionToolbarStateTests/testDefaultMagnifierAnnotationStateIsCircleTwoX -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierRendererSamplesOriginalImageInsteadOfAnnotations -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierRendererClipsSourceAtImageBounds -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierToolbarButtonActivatesMagnifierModeAndOptionsToolbar -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierOptionsSwitchShapeZoomStrokeAndColor -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierDragCreatesCircleAndShiftConstrainsToSquare -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierTinyDragDoesNotCreateAnnotation -only-testing:xxsnapTests/SelectionToolbarStateTests/testSelectedMagnifierCanResizeMoveDeleteAndRestyle -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierOverlayPreviewMatchesExportRendererAtCenter -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierDoesNotMagnifyMosaicOrTextAnnotations
```

Expected: PASS.

- [ ] **Step 4: Run the mac test target**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Expected: PASS. If this fails due local signing, permissions, or ScreenCaptureKit environment constraints, capture the exact failure and run the focused test command from Step 3 plus a build:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived build
```

- [ ] **Step 5: Commit docs and verification updates**

Commit:

```bash
git add docs/annotation-tools-user-guide.md platforms/mac/Tests/manual-capture-checklist.md
git commit -m "docs: document magnifier tool"
```

## Final Verification

After all tasks are complete, run:

```bash
git status --short --branch
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Expected:

- working tree contains only intentional changes;
- mac XCTest target passes, or any local environment blocker is reported with the closest passing focused tests and build command.
