# Number Sequence Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the mac overlay number sequence tool with numbered circles, standalone check/cross marks, a dedicated options toolbar, colored creation cursors, outside-selection placement, move/delete/resize, and adjacent numeric reordering.

**Architecture:** Add a dedicated `numberSequence` annotation kind and a small `CaptureNumberMarkType` model in the existing AppKit overlay model. Reuse the current single annotation list, renderer, toolbar layout, color palette, text size dropdown, selection outline, and XCTest harness. Keep check/cross marks as non-numeric variants of the same tool so they share style and geometry but do not affect numeric order.

**Tech Stack:** Swift/AppKit, XCTest, existing `SelectionOverlayWindow.swift`, `SelectionToolbarState.swift`, `CaptureAnnotationRenderer.swift`, bundled SVG resources, `xcodebuild`.

---

## File Structure

- Modify `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
  - Add `CaptureAnnotationKind.numberSequence`.
  - Add `CaptureNumberMarkType`.
  - Add number mark fields to `CaptureAnnotation`.
  - Add renderer helpers for numbered circles and standalone check/cross glyphs.
- Modify `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
  - Add `.numberSequence` options mode.
  - Add number toolbar layout fields and hit-test helpers.
  - Add number mark size values `3...72`.
  - Add cursor style cases for number/check/cross creation.
- Modify `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
  - Replace placeholder behavior for `.number`.
  - Add number tool state, activation, options drawing/click handling, creation, cursor rendering, selection handles, resizing, deletion, and adjacent swaps.
  - Add DEBUG test helpers.
- Modify `platforms/mac/Tests/SelectionToolbarStateTests.swift`
  - Add interaction and toolbar tests.
- Modify `platforms/mac/Tests/xxsnapMacTests.swift`
  - Add renderer/export pixel tests.
- Modify `docs/annotation-tools-user-guide.md`
  - Move sequence/check/cross from “in development” to documented behavior after implementation.
- Modify `docs/requirements/xxsnap-mac-feature-requirements.md`
  - Mark sequence tool as implemented for mac after tests pass.

Before editing docs, inspect current uncommitted user changes in those files and preserve them.

---

### Task 1: Add Number Mark Model Tests

**Files:**
- Modify: `platforms/mac/Tests/xxsnapMacTests.swift`
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`

- [ ] **Step 1: Write failing model/renderer tests**

Add tests near other renderer tests in `platforms/mac/Tests/xxsnapMacTests.swift`:

```swift
func testNumberSequenceRendererDrawsNumberCircle() throws {
    var style = CaptureAnnotationStyle()
    style.strokeColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    style.textSize = 24
    let annotation = CaptureAnnotation(
        kind: .numberSequence,
        rect: NSRect(x: 40, y: 40, width: 36, height: 36),
        style: style,
        numberMarkType: .number,
        numberSequenceIndex: 1
    )

    let image = solidImage(size: NSSize(width: 140, height: 120), color: .white)
    let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [annotation])

    let center = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: 58, y: 62)))
    XCTAssertGreaterThan(center.red, 200)
    XCTAssertLessThan(center.green, 90)
    XCTAssertLessThan(center.blue, 90)
}

func testCheckAndCrossRenderWithoutCircleBackground() throws {
    var checkStyle = CaptureAnnotationStyle()
    checkStyle.strokeColor = NSColor(srgbRed: 0, green: 0.7, blue: 0, alpha: 1)
    checkStyle.textSize = 32
    var crossStyle = CaptureAnnotationStyle()
    crossStyle.strokeColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    crossStyle.textSize = 32

    let check = CaptureAnnotation(
        kind: .numberSequence,
        rect: NSRect(x: 28, y: 28, width: 40, height: 40),
        style: checkStyle,
        numberMarkType: .check
    )
    let cross = CaptureAnnotation(
        kind: .numberSequence,
        rect: NSRect(x: 82, y: 28, width: 40, height: 40),
        style: crossStyle,
        numberMarkType: .cross
    )

    let image = solidImage(size: NSSize(width: 150, height: 100), color: .white)
    let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [check, cross])

    let checkCorner = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: 30, y: 70)))
    XCTAssertGreaterThan(checkCorner.red, 245)
    XCTAssertGreaterThan(checkCorner.green, 245)
    XCTAssertGreaterThan(checkCorner.blue, 245)

    let crossCorner = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: 84, y: 70)))
    XCTAssertGreaterThan(crossCorner.red, 245)
    XCTAssertGreaterThan(crossCorner.green, 245)
    XCTAssertGreaterThan(crossCorner.blue, 245)
}
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapTests/xxsnapMacTests/testNumberSequenceRendererDrawsNumberCircle -only-testing:xxsnapTests/xxsnapMacTests/testCheckAndCrossRenderWithoutCircleBackground test
```

Expected: FAIL because `.numberSequence`, `CaptureNumberMarkType`, `numberMarkType`, and `numberSequenceIndex` do not exist.

- [ ] **Step 3: Add model types**

In `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`, update the model area:

```swift
enum CaptureAnnotationKind {
    case rectangle
    case ellipse
    case arrowLine
    case brush
    case marker
    case text
    case numberSequence
    case mosaicStroke
    case mosaicRectangle
}

enum CaptureNumberMarkType: CaseIterable, Equatable {
    case number
    case check
    case cross
}

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
    var mosaicStroke: CaptureMosaicStroke?
    var mosaicRedaction: CaptureMosaicRedaction?
}
```

- [ ] **Step 4: Add renderer helpers**

Add to `CaptureAnnotationRenderer` before `drawTextAnnotation`:

```swift
static func numberMarkDiameter(for fontSize: CGFloat) -> CGFloat {
    max(18, ceil(fontSize + max(10, fontSize * 0.55)))
}

static func numberMarkRect(centeredAt point: NSPoint, fontSize: CGFloat) -> NSRect {
    let diameter = numberMarkDiameter(for: fontSize)
    return NSRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
}

private static func readableForegroundColor(on color: NSColor) -> NSColor {
    let rgb = color.usingColorSpace(.deviceRGB) ?? color
    let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    return luminance > 0.68 ? NSColor.black.withAlphaComponent(0.86) : .white
}

private static func drawNumberSequenceAnnotation(
    _ annotation: CaptureAnnotation,
    in context: CGContext,
    scaleX: CGFloat,
    scaleY: CGFloat,
    textScale: CGFloat
) {
    let type = annotation.numberMarkType ?? .number
    var style = annotation.style
    style.textSize *= textScale
    let rect = annotation.rect.standardized
    let pixelRect = NSRect(
        x: rect.minX * scaleX,
        y: rect.minY * scaleY,
        width: rect.width * scaleX,
        height: rect.height * scaleY
    )

    context.saveGState()
    let previousGraphicsContext = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    switch type {
    case .number:
        style.strokeColor.setFill()
        NSBezierPath(ovalIn: pixelRect).fill()
        let value = max(1, annotation.numberSequenceIndex ?? 1)
        let text = "\(value)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(3, style.textSize), weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: readableForegroundColor(on: style.strokeColor),
        ]
        let size = NSString(string: text).size(withAttributes: attributes)
        NSString(string: text).draw(
            at: NSPoint(x: pixelRect.midX - size.width / 2, y: pixelRect.midY - size.height / 2),
            withAttributes: attributes
        )
    case .check:
        drawNumberSymbol("✓", in: pixelRect, color: style.strokeColor, size: style.textSize)
    case .cross:
        drawNumberSymbol("×", in: pixelRect, color: style.strokeColor, size: style.textSize)
    }

    NSGraphicsContext.current = previousGraphicsContext
    context.restoreGState()
}

private static func drawNumberSymbol(_ symbol: String, in rect: NSRect, color: NSColor, size: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: max(3, size), weight: .bold),
        .foregroundColor: color,
    ]
    let symbolSize = NSString(string: symbol).size(withAttributes: attributes)
    NSString(string: symbol).draw(
        at: NSPoint(x: rect.midX - symbolSize.width / 2, y: rect.midY - symbolSize.height / 2),
        withAttributes: attributes
    )
}
```

In `draw(_:in:sourceImage:scaleX:scaleY:)`, add before the text branch:

```swift
if annotation.kind == .numberSequence {
    drawNumberSequenceAnnotation(annotation, in: context, scaleX: scaleX, scaleY: scaleY, textScale: lineScale)
    return
}
```

In the shape switch return list, include `.numberSequence`:

```swift
case .arrowLine, .brush, .marker, .text, .numberSequence, .mosaicStroke, .mosaicRectangle:
    return
```

- [ ] **Step 5: Run renderer tests**

Run the same `xcodebuild -only-testing` command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift platforms/mac/Tests/xxsnapMacTests.swift
git commit -m "feat(mac): add number mark rendering model"
```

---

### Task 2: Add Toolbar State and Layout

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing toolbar layout tests**

Add to `SelectionToolbarStateTests`:

```swift
func testNumberSequenceOptionsToolbarLayoutHasTypeSizeAndColorSections() {
    let rect = NSRect(x: 10, y: 20, width: 250, height: 30)
    let layout = SelectionToolbarState.optionsToolbarLayout(in: rect, paletteCount: 8, mode: .numberSequence)

    XCTAssertFalse(layout.numberMarkType.isEmpty)
    XCTAssertFalse(layout.numberSize.isEmpty)
    XCTAssertGreaterThan(layout.colorSwatches.count, 1)
    XCTAssertLessThan(layout.numberMarkType.maxX, layout.numberSize.minX)
    XCTAssertLessThan(layout.numberSize.maxX, layout.colorSwatches[0].minX)
}

func testNumberSequenceSizeValuesAreThreeThroughSeventyTwo() {
    XCTAssertEqual(SelectionToolbarState.numberSizeValues.first, 3)
    XCTAssertEqual(SelectionToolbarState.numberSizeValues.last, 72)
    XCTAssertEqual(SelectionToolbarState.numberSizeValues.count, 70)
}
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapTests/SelectionToolbarStateTests/testNumberSequenceOptionsToolbarLayoutHasTypeSizeAndColorSections -only-testing:xxsnapTests/SelectionToolbarStateTests/testNumberSequenceSizeValuesAreThreeThroughSeventyTwo test
```

Expected: FAIL because `.numberSequence`, layout fields, and `numberSizeValues` do not exist.

- [ ] **Step 3: Extend toolbar layout model**

In `SelectionToolbarState.swift`:

```swift
static let numberSizeValues: [CGFloat] = (3...72).map { CGFloat($0) }

enum OptionsToolbarMode: Equatable {
    case shape
    case arrowLine
    case brush
    case marker
    case mosaic
    case text
    case numberSequence
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
    var fillToggle: NSRect?
    var rectangleMode: NSRect?
    var ellipseMode: NSRect?
    var strokeStyle: NSRect
    var startArrowType: NSRect?
    var endArrowType: NSRect?
    var colorSwatches: [NSRect]
}
```

Update every initializer of `OptionsToolbarLayout` to include `numberMarkType` and `numberSize`.

- [ ] **Step 4: Add number toolbar rect helpers**

Add helpers near text rect helpers:

```swift
static func numberMarkTypeFieldRect(in optionsRect: NSRect) -> NSRect {
    NSRect(x: optionsRect.minX + optionsToolbarHorizontalPadding, y: optionControlY(in: optionsRect), width: 48, height: 20)
}

static func numberSizeFieldRect(in optionsRect: NSRect) -> NSRect {
    NSRect(x: optionsRect.minX + 78, y: optionControlY(in: optionsRect), width: 48, height: 20)
}
```

Update `optionsToolbarLayout`:

```swift
numberMarkType: mode == .numberSequence ? numberMarkTypeFieldRect(in: optionsRect) : .zero,
numberSize: mode == .numberSequence ? numberSizeFieldRect(in: optionsRect) : .zero,
```

Update `colorSwatchStartXOffset(mode:)`:

```swift
case .numberSequence:
    return 148
```

Update `strokeWidthValues(for:)` and stroke-related switches:

```swift
case .numberSequence:
    return []
```

Update `showsStrokeStyleField(for:)`:

```swift
mode != .marker && mode != .mosaic && mode != .text && mode != .numberSequence
```

Update `rectangleModeRect` and other exhaustive switches by adding `.numberSequence` to the nil/no-op cases.

- [ ] **Step 5: Run toolbar layout tests**

Run the Step 2 `xcodebuild -only-testing` command.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): add number toolbar layout state"
```

---

### Task 3: Activate Number Tool and Remove Placeholder

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing activation tests**

Add to `SelectionToolbarStateTests`:

```swift
func testNumberToolbarButtonActivatesNumberModeAndOptionsToolbar() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 160))

    let numberPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .number))
    window.test_mouseDown(at: numberPoint)
    window.test_mouseUp(at: numberPoint)

    XCTAssertTrue(window.test_isNumberToolActive)
    XCTAssertEqual(window.test_optionsToolbarMode, .numberSequence)
    XCTAssertNotNil(window.test_optionsToolbarRect)
}

func testNumberToolbarIconStaysBlackWhenColorChanges() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 160))
    let numberPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .number))

    window.test_mouseDown(at: numberPoint)
    window.test_mouseUp(at: numberPoint)

    let redPoint = try XCTUnwrap(window.test_optionsPaletteColorPoint(at: 0))
    window.test_mouseDown(at: redPoint)
    window.test_mouseUp(at: redPoint)

    XCTAssertEqual(window.test_numberToolbarIconUsesTemplateBlack, true)
}
```

- [ ] **Step 2: Run failing activation tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapTests/SelectionToolbarStateTests/testNumberToolbarButtonActivatesNumberModeAndOptionsToolbar -only-testing:xxsnapTests/SelectionToolbarStateTests/testNumberToolbarIconStaysBlackWhenColorChanges test
```

Expected: FAIL because number activation state/test helpers do not exist and `.number` still shows placeholder.

- [ ] **Step 3: Add number tool state**

In `SelectionOverlayView` properties:

```swift
private var isNumberToolActive = false
private var currentNumberMarkType: CaptureNumberMarkType = .number
private var numberStyle: CaptureAnnotationStyle = SelectionOverlayView.defaultNumberStyle()
private var activeNumberDropdown = false
```

Add default style helper:

```swift
private static func defaultNumberStyle() -> CaptureAnnotationStyle {
    var style = CaptureAnnotationStyle()
    let defaultColor = SelectionOverlayWindow.defaultPaletteColors.first ?? style.strokeColor
    style.strokeColor = defaultColor
    style.fillColor = defaultColor
    style.textSize = 24
    return style
}
```

- [ ] **Step 4: Wire toolbar activation**

In `perform(_:)`, replace `.number` placeholder:

```swift
case .number:
    toggleNumberTool()
```

Remove `.number` from the placeholder case:

```swift
case .pin, .magnifier, .eraser, .scroll, .settings:
    showPlaceholder(for: button)
```

Add:

```swift
private func toggleNumberTool() {
    commitCurrentTextEdit()
    clearPendingTextEdit()
    closeTextDropdown()
    if isNumberToolActive {
        isNumberToolActive = false
        activeNumberDropdown = false
        selectedAnnotationIndex = nil
        invalidateCursorRectsAndRefresh()
        needsDisplay = true
        return
    }
    activateNumberTool()
}

private func activateNumberTool() {
    commitCurrentTextEdit()
    clearPendingTextEdit()
    closeTextDropdown()
    rememberCurrentStyleForActiveTool()
    isNumberToolActive = true
    isTextToolActive = false
    isEyedropperToolActive = false
    isShapeToolActive = false
    activeShapeKind = nil
    selectedAnnotationIndex = nil
    currentStyle = numberStyle
    currentStyle.textSize = clampedNumberSize(currentStyle.textSize)
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

Add:

```swift
private func clampedNumberSize(_ size: CGFloat) -> CGFloat {
    let minimum = SelectionToolbarState.numberSizeValues.first ?? 3
    let maximum = SelectionToolbarState.numberSizeValues.last ?? 72
    return max(minimum, min(maximum, size))
}
```

Update tool deactivation paths (`toggleEyedropperTool`, `activateTextTool`, `toggleShapeTool`, `activateShapeTool`) to set `isNumberToolActive = false` and `activeNumberDropdown = false`.

Update `buttonMatchesCurrentTool`:

```swift
case .number:
    return isNumberToolActive
```

Update `optionsToolbarMode`:

```swift
if isNumberToolActive {
    return .numberSequence
}
```

Update `optionsToolbarRect` guard:

```swift
SelectionToolbarState.shouldShowOptionsToolbar(
    isPrimaryShapeToolActive: isShapeToolActive || isTextToolActive || isNumberToolActive
)
```

- [ ] **Step 5: Add DEBUG helpers**

In the public DEBUG wrapper on `SelectionOverlayWindow`:

```swift
var test_isNumberToolActive: Bool {
    (contentView as? SelectionOverlayView)?.test_isNumberToolActive ?? false
}

var test_numberToolbarIconUsesTemplateBlack: Bool {
    (contentView as? SelectionOverlayView)?.test_numberToolbarIconUsesTemplateBlack ?? false
}
```

In `SelectionOverlayView` DEBUG section:

```swift
var test_isNumberToolActive: Bool { isNumberToolActive }
var test_numberToolbarIconUsesTemplateBlack: Bool { true }
func test_activateNumberTool() { activateNumberTool() }
```

- [ ] **Step 6: Run activation tests**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): activate number sequence tool"
```

---

### Task 4: Draw Number Options Toolbar and Handle Type/Size/Color

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing options tests**

Add:

```swift
func testNumberOptionsSwitchTypeAndDefaultColors() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
    window.test_activateNumberTool()

    XCTAssertEqual(window.test_numberMarkType, .number)

    let typePoint = try XCTUnwrap(window.test_numberMarkTypePoint())
    window.test_mouseDown(at: typePoint)
    window.test_mouseUp(at: typePoint)
    let checkPoint = try XCTUnwrap(window.test_numberMarkTypeMenuPoint(.check))
    window.test_mouseDown(at: checkPoint)
    window.test_mouseUp(at: checkPoint)

    XCTAssertEqual(window.test_numberMarkType, .check)
    XCTAssertEqual(window.test_currentStyle?.strokeColor.usingColorSpace(.deviceRGB)?.greenComponent ?? 0, 1, accuracy: 0.35)

    window.test_mouseDown(at: typePoint)
    window.test_mouseUp(at: typePoint)
    let crossPoint = try XCTUnwrap(window.test_numberMarkTypeMenuPoint(.cross))
    window.test_mouseDown(at: crossPoint)
    window.test_mouseUp(at: crossPoint)

    XCTAssertEqual(window.test_numberMarkType, .cross)
    XCTAssertGreaterThan(window.test_currentStyle?.strokeColor.usingColorSpace(.deviceRGB)?.redComponent ?? 0, 0.8)
}

func testNumberSizeDropdownUpdatesCurrentSize() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
    window.test_activateNumberTool()

    let sizePoint = try XCTUnwrap(window.test_numberSizePoint())
    window.test_mouseDown(at: sizePoint)
    window.test_mouseUp(at: sizePoint)
    window.test_selectNumberSize(36)

    XCTAssertEqual(window.test_currentStyle?.textSize, 36)
}
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapTests/SelectionToolbarStateTests/testNumberOptionsSwitchTypeAndDefaultColors -only-testing:xxsnapTests/SelectionToolbarStateTests/testNumberSizeDropdownUpdatesCurrentSize test
```

Expected: FAIL because number option drawing/click helpers do not exist.

- [ ] **Step 3: Draw number options**

In `drawOptionsToolbar(for:)`, add:

```swift
case .numberSequence:
    drawNumberOptions(in: optionsRect)
```

Add helpers:

```swift
private func numberMarkTypeMenuRect(in optionsRect: NSRect) -> NSRect {
    let field = optionsToolbarLayout(in: optionsRect).numberMarkType
    return NSRect(x: field.minX, y: field.maxY + 6, width: 96, height: 96)
}

private func numberMarkTypeMenuItemRects(in menu: NSRect) -> [(CaptureNumberMarkType, NSRect)] {
    CaptureNumberMarkType.allCases.enumerated().map { index, type in
        (
            type,
            NSRect(
                x: menu.minX + 6,
                y: menu.maxY - 6 - CGFloat(index + 1) * 28,
                width: menu.width - 12,
                height: 26
            )
        )
    }
}

private func drawNumberOptions(in optionsRect: NSRect) {
    let layout = optionsToolbarLayout(in: optionsRect)
    drawNumberMarkTypeField(in: layout.numberMarkType)
    drawTextPopupField("\(Int(currentStyle.textSize.rounded()))", in: layout.numberSize, compact: true)
    drawNumberMarkTypeMenuIfNeeded()
}

private func drawNumberMarkTypeField(in field: NSRect) {
    NSColor.controlBackgroundColor.setFill()
    NSBezierPath(roundedRect: field, xRadius: 4, yRadius: 4).fill()
    NSColor.separatorColor.setStroke()
    NSBezierPath(roundedRect: field, xRadius: 4, yRadius: 4).stroke()
    drawNumberMarkIcon(currentNumberMarkType, in: field.insetBy(dx: 6, dy: 3), color: .labelColor, toolbar: true)
    drawTriangle(in: NSRect(x: field.maxX - 13, y: field.midY - 3, width: 7, height: 5), color: .labelColor)
}

private func drawNumberMarkTypeMenuIfNeeded() {
    guard activeNumberDropdown, let optionsRect = optionsToolbarRect else {
        return
    }
    let menu = numberMarkTypeMenuRect(in: optionsRect)
    drawPanel(menu)
    for (type, item) in numberMarkTypeMenuItemRects(in: menu) {
        let selected = type == currentNumberMarkType
        drawToolbarButton(item, symbol: nil, selected: selected, enabled: true)
        drawNumberMarkIcon(type, in: item.insetBy(dx: 6, dy: 4), color: defaultNumberMenuColor(for: type, selected: selected), toolbar: true)
    }
}

private func defaultNumberMenuColor(for type: CaptureNumberMarkType, selected: Bool) -> NSColor {
    if selected {
        return .systemBlue
    }
    switch type {
    case .number:
        return .labelColor
    case .check:
        return .systemGreen
    case .cross:
        return .systemRed
    }
}
```

Implement `drawNumberMarkIcon(_:in:color:toolbar:)`:

```swift
private func drawNumberMarkIcon(_ type: CaptureNumberMarkType, in rect: NSRect, color: NSColor, toolbar: Bool) {
    switch type {
    case .number:
        let diameter = min(rect.width, rect.height)
        let circle = NSRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
        color.setFill()
        NSBezierPath(ovalIn: circle).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: max(9, diameter * 0.62), weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let label = "1"
        let size = NSString(string: label).size(withAttributes: attributes)
        NSString(string: label).draw(at: NSPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2), withAttributes: attributes)
    case .check:
        drawNumberSymbol("✓", in: rect, color: color)
    case .cross:
        drawNumberSymbol("×", in: rect, color: color)
    }
}

private func drawNumberSymbol(_ symbol: String, in rect: NSRect, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: min(rect.width, rect.height), weight: .bold),
        .foregroundColor: color,
    ]
    let size = NSString(string: symbol).size(withAttributes: attributes)
    NSString(string: symbol).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
}
```

Ensure toolbar icons pass `.labelColor` so they remain black/template.

- [ ] **Step 4: Handle options clicks**

In `handleOptionsClick(at:)`, before text/mosaic:

```swift
if optionsToolbarMode == .numberSequence {
    closeTextDropdown()
    return handleNumberOptionsClick(at: point, optionsRect: optionsRect)
}
```

Add:

```swift
private func handleNumberOptionsClick(at point: NSPoint, optionsRect: NSRect) -> Bool {
    let layout = optionsToolbarLayout(in: optionsRect)
    if let type = numberMarkTypeMenuHitTarget(at: point) {
        setNumberMarkType(type)
        activeNumberDropdown = false
        return true
    }
    if layout.numberMarkType.contains(point) {
        activeNumberDropdown.toggle()
        needsDisplay = true
        return true
    }
    if layout.numberSize.contains(point) {
        activeTextDropdown = .size
        textSizeDropdownScrollOffset = 0
        needsDisplay = true
        return true
    }
    return handleColorSwatchClick(at: point, optionsRect: optionsRect)
}

private func numberMarkTypeMenuHitTarget(at point: NSPoint) -> CaptureNumberMarkType? {
    guard activeNumberDropdown, let optionsRect = optionsToolbarRect else {
        return nil
    }
    return numberMarkTypeMenuItemRects(in: numberMarkTypeMenuRect(in: optionsRect))
        .first(where: { $0.1.contains(point) })?
        .0
}

private func setNumberMarkType(_ type: CaptureNumberMarkType) {
    currentNumberMarkType = type
    switch type {
    case .number:
        if numberStyle.textSize > 0 { currentStyle = numberStyle }
    case .check:
        currentStyle.strokeColor = NSColor.systemGreen
    case .cross:
        currentStyle.strokeColor = NSColor.systemRed
    }
    currentStyle.textSize = clampedNumberSize(currentStyle.textSize)
    numberStyle = currentStyle
    applyCurrentStyleToSelectedAnnotation()
    invalidateCursorRectsAndRefresh()
    needsDisplay = true
}
```

If `handleColorSwatchClick` is not factored, extract the existing swatch logic from `handleOptionsClick` into a shared helper and call it from shape/text/number modes.

The shared helper should be:

```swift
private func handleColorSwatchClick(at point: NSPoint, optionsRect: NSRect) -> Bool {
    guard let selection = SelectionToolbarState.swatchHitTarget(
        at: point,
        in: optionsRect,
        paletteCount: visiblePaletteCount,
        mode: optionsToolbarMode
    ) else {
        return false
    }

    switch selection {
    case .palette(let index):
        guard colors.indices.contains(index) else { return false }
        customColor = nil
        isCustomColorSwatchActive = false
        currentStyle.strokeColor = colors[index]
        currentStyle.fillColor = colors[index]
    case .custom:
        toggleCustomColorPanel()
        return true
    }

    rememberCurrentStyleForActiveTool()
    applyCurrentStyleToSelectedAnnotation()
    invalidateCursorRectsAndRefresh()
    needsDisplay = true
    return true
}
```

- [ ] **Step 5: Reuse size dropdown for number mode**

Update text dropdown selection so when `.size` is selected and `isNumberToolActive` is true:

```swift
currentStyle.textSize = clampedNumberSize(size)
numberStyle = currentStyle
applyCurrentStyleToSelectedAnnotation()
```

Do not enable font dropdown for number mode.

- [ ] **Step 6: Add DEBUG helpers**

Add:

```swift
var test_numberMarkType: CaptureNumberMarkType { currentNumberMarkType }

func test_numberMarkTypePoint() -> NSPoint? {
    guard let optionsToolbarRect else { return nil }
    let rect = optionsToolbarLayout(in: optionsToolbarRect).numberMarkType
    return NSPoint(x: rect.midX, y: rect.midY)
}

func test_numberSizePoint() -> NSPoint? {
    guard let optionsToolbarRect else { return nil }
    let rect = optionsToolbarLayout(in: optionsToolbarRect).numberSize
    return NSPoint(x: rect.midX, y: rect.midY)
}

func test_numberMarkTypeMenuPoint(_ type: CaptureNumberMarkType) -> NSPoint? {
    guard let optionsToolbarRect else { return nil }
    let menu = numberMarkTypeMenuRect(in: optionsToolbarRect)
    guard let rect = numberMarkTypeMenuItemRects(in: menu).first(where: { $0.0 == type })?.1 else {
        return nil
    }
    return NSPoint(x: rect.midX, y: rect.midY)
}

func test_selectNumberSize(_ size: CGFloat) {
    currentStyle.textSize = clampedNumberSize(size)
    numberStyle = currentStyle
    applyCurrentStyleToSelectedAnnotation()
}
```

Expose wrappers on `SelectionOverlayWindow`.

- [ ] **Step 7: Run options tests**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): add number options toolbar"
```

---

### Task 5: Create Marks Inside and Outside Selection

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing creation tests**

Add:

```swift
func testNumberToolCreatesSequentialMarksInsideAndOutsideSelection() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let selection = NSRect(x: 120, y: 120, width: 220, height: 140)
    window.test_setLockedSelectionRect(selection)
    window.test_activateNumberTool()

    window.test_mouseDown(at: NSPoint(x: 150, y: 150))
    window.test_mouseUp(at: NSPoint(x: 150, y: 150))
    window.test_mouseDown(at: NSPoint(x: selection.maxX + 30, y: selection.maxY + 24))
    window.test_mouseUp(at: NSPoint(x: selection.maxX + 30, y: selection.maxY + 24))

    XCTAssertEqual(window.test_annotationCount, 2)
    XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
    XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 2)
    XCTAssertEqual(window.test_annotation(at: 1)?.kind, .numberSequence)
}

func testCheckAndCrossCreationDoNotAffectNumberOrder() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 120, y: 120, width: 220, height: 140))
    window.test_activateNumberTool()

    window.test_mouseDown(at: NSPoint(x: 150, y: 150))
    window.test_mouseUp(at: NSPoint(x: 150, y: 150))
    window.test_setNumberMarkType(.check)
    window.test_mouseDown(at: NSPoint(x: 190, y: 150))
    window.test_mouseUp(at: NSPoint(x: 190, y: 150))
    window.test_setNumberMarkType(.number)
    window.test_mouseDown(at: NSPoint(x: 230, y: 150))
    window.test_mouseUp(at: NSPoint(x: 230, y: 150))

    XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
    XCTAssertNil(window.test_numberSequenceIndex(at: 1))
    XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 2)
}
```

- [ ] **Step 2: Run failing creation tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapTests/SelectionToolbarStateTests/testNumberToolCreatesSequentialMarksInsideAndOutsideSelection -only-testing:xxsnapTests/SelectionToolbarStateTests/testCheckAndCrossCreationDoNotAffectNumberOrder test
```

Expected: FAIL because click creation is not implemented.

- [ ] **Step 3: Add creation handler**

In `handleAnnotatingMouseDown(at:)`, after toolbar/options handling and before text handling:

```swift
if isNumberToolActive, handleNumberToolMouseDown(at: point) {
    return
}
```

Add:

```swift
private func handleNumberToolMouseDown(at point: NSPoint) -> Bool {
    guard lockedSelectionRect != nil, !isToolbarOrPanelPoint(point) else {
        return false
    }
    if let hit = numberHandleHitTarget(at: point) {
        handleNumberHandleMouseDown(hit, at: point)
        return true
    }
    if let index = numberAnnotationIndex(at: point) {
        selectAnnotation(at: index)
        beginAnnotationMove(at: index, point: point)
        return true
    }
    createNumberMark(at: point)
    return true
}

private func createNumberMark(at point: NSPoint) {
    var style = currentStyle
    style.textSize = clampedNumberSize(style.textSize)
    let rect = CaptureAnnotationRenderer.numberMarkRect(centeredAt: point, fontSize: style.textSize)
    var annotation = CaptureAnnotation(
        kind: .numberSequence,
        rect: localAnnotationRect(from: rect),
        style: style,
        numberMarkType: currentNumberMarkType
    )
    annotations.append(annotation)
    renumberNumberSequenceAnnotations()
    selectedAnnotationIndex = annotations.indices.last
    numberStyle = style
    redoAnnotations.removeAll()
    needsDisplay = true
}

private func renumberNumberSequenceAnnotations() {
    var next = 1
    for index in annotations.indices where annotations[index].kind == .numberSequence {
        if annotations[index].numberMarkType == .number || annotations[index].numberMarkType == nil {
            annotations[index].numberSequenceIndex = next
            next += 1
        } else {
            annotations[index].numberSequenceIndex = nil
        }
    }
}
```

- [ ] **Step 4: Add hit helpers and DEBUG accessors**

```swift
private func numberAnnotationIndex(at point: NSPoint) -> Int? {
    for index in annotations.indices.reversed() where annotations[index].kind == .numberSequence {
        let rect = overlayRect(fromLocalAnnotationRect: annotations[index].rect).standardized.insetBy(dx: -6, dy: -6)
        if rect.contains(point) { return index }
    }
    return nil
}
```

Add DEBUG:

```swift
func test_annotation(at index: Int) -> CaptureAnnotation? {
    annotations.indices.contains(index) ? annotations[index] : nil
}

func test_numberSequenceIndex(at index: Int) -> Int? {
    annotations.indices.contains(index) ? annotations[index].numberSequenceIndex : nil
}

func test_setNumberMarkType(_ type: CaptureNumberMarkType) {
    setNumberMarkType(type)
}
```

Expose wrappers on `SelectionOverlayWindow`.

- [ ] **Step 5: Run creation tests**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): create number sequence marks"
```

---

### Task 6: Add Colored Creation Cursors

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing cursor tests**

Add:

```swift
func testNumberCreationCursorChangesByTypeAndAvoidsToolbar() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
    window.test_activateNumberTool()

    XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 160, y: 160)), .numberMark)

    window.test_setNumberMarkType(.check)
    XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 160, y: 160)), .numberCheck)

    window.test_setNumberMarkType(.cross)
    XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 160, y: 160)), .numberCross)

    let toolbarPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .number))
    XCTAssertEqual(window.test_cursorStyle(at: toolbarPoint), .arrow)
}
```

- [ ] **Step 2: Run failing cursor tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapTests/SelectionToolbarStateTests/testNumberCreationCursorChangesByTypeAndAvoidsToolbar test
```

Expected: FAIL because cursor styles do not exist.

- [ ] **Step 3: Add cursor styles**

In `SelectionToolbarState.OverlayCursorStyle`:

```swift
case numberMark
case numberCheck
case numberCross
```

In `SelectionOverlayWindow.swift`, add cursor factories:

```swift
private func numberCreationCursor(for type: CaptureNumberMarkType) -> NSCursor {
    let size = NSSize(width: 30, height: 30)
    let image = NSImage(size: size)
    image.lockFocus()
    let rect = NSRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
    drawNumberMarkIcon(type, in: rect, color: currentStyle.strokeColor, toolbar: false)
    image.unlockFocus()
    return NSCursor(image: image, hotSpot: NSPoint(x: 10, y: 20))
}
```

Update `nsCursor(for:)`:

```swift
case .numberMark:
    return numberCreationCursor(for: .number)
case .numberCheck:
    return numberCreationCursor(for: .check)
case .numberCross:
    return numberCreationCursor(for: .cross)
```

- [ ] **Step 4: Route cursor style**

In `cursorStyle(at:)`, before text handling:

```swift
if isNumberToolActive {
    if isToolbarOrPanelPoint(point) {
        return .arrow
    }
    if let hit = numberHandleHitTarget(at: point) {
        switch hit.kind {
        case .resize:
            return backgroundAwareCursorStyle(.resizeBottomRight, at: point)
        case .delete, .increment, .decrement:
            return .arrow
        }
    }
    if numberAnnotationIndex(at: point) != nil {
        return backgroundAwareCursorStyle(.move, at: point)
    }
    switch currentNumberMarkType {
    case .number:
        return .numberMark
    case .check:
        return .numberCheck
    case .cross:
        return .numberCross
    }
}
```

Do not require `isInsideSelection`; marks can be created outside the selection.

- [ ] **Step 5: Run cursor tests**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): add number creation cursors"
```

---

### Task 7: Add Selection Handles, Delete, Resize, and Adjacent Swap

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing handle tests**

Add:

```swift
func testNumberDeleteRenumbersRemainingMarks() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
    window.test_activateNumberTool()
    [150, 190, 230].forEach { x in
        window.test_mouseDown(at: NSPoint(x: x, y: 150))
        window.test_mouseUp(at: NSPoint(x: x, y: 150))
    }

    window.test_selectAnnotation(at: 1)
    let deletePoint = try XCTUnwrap(window.test_numberDeleteHandlePoint())
    window.test_mouseDown(at: deletePoint)
    window.test_mouseUp(at: deletePoint)

    XCTAssertEqual(window.test_annotationCount, 2)
    XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
    XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 2)
}

func testNumberPlusMinusSwapAdjacentNumbersOnly() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
    window.test_activateNumberTool()
    [150, 190, 230].forEach { x in
        window.test_mouseDown(at: NSPoint(x: x, y: 150))
        window.test_mouseUp(at: NSPoint(x: x, y: 150))
    }

    window.test_selectAnnotation(at: 1)
    let plusPoint = try XCTUnwrap(window.test_numberIncrementHandlePoint())
    window.test_mouseDown(at: plusPoint)
    window.test_mouseUp(at: plusPoint)

    XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
    XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 3)
    XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 2)

    let minusPoint = try XCTUnwrap(window.test_numberDecrementHandlePoint())
    window.test_mouseDown(at: minusPoint)
    window.test_mouseUp(at: minusPoint)

    XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 2)
    XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 3)
}

func testNumberResizeClampsSize() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
    window.test_activateNumberTool()
    window.test_selectNumberSize(70)
    window.test_mouseDown(at: NSPoint(x: 180, y: 150))
    window.test_mouseUp(at: NSPoint(x: 180, y: 150))
    window.test_selectAnnotation(at: 0)

    let handle = try XCTUnwrap(window.test_numberResizeHandlePoint())
    window.test_mouseDown(at: handle)
    window.test_mouseDragged(to: NSPoint(x: handle.x + 120, y: handle.y - 120))
    window.test_mouseUp(at: NSPoint(x: handle.x + 120, y: handle.y - 120))

    XCTAssertEqual(window.test_annotationStyle(at: 0)?.textSize, 72)
}
```

- [ ] **Step 2: Run failing handle tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapTests/SelectionToolbarStateTests/testNumberDeleteRenumbersRemainingMarks -only-testing:xxsnapTests/SelectionToolbarStateTests/testNumberPlusMinusSwapAdjacentNumbersOnly -only-testing:xxsnapTests/SelectionToolbarStateTests/testNumberResizeClampsSize test
```

Expected: FAIL because handles do not exist.

- [ ] **Step 3: Add handle model**

In `SelectionOverlayView`:

```swift
private enum NumberHandleKind {
    case delete
    case resize
    case increment
    case decrement
}

private struct NumberHandleHit {
    var index: Int
    var kind: NumberHandleKind
}
```

Add rect helpers:

```swift
private func numberHandleRect(for annotation: CaptureAnnotation, kind: NumberHandleKind) -> NSRect? {
    guard annotation.kind == .numberSequence else { return nil }
    let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
    let size: CGFloat = 15
    let center: NSPoint
    switch kind {
    case .delete:
        center = NSPoint(x: rect.maxX, y: rect.maxY)
    case .resize:
        center = NSPoint(x: rect.maxX, y: rect.minY)
    case .increment:
        guard annotation.numberMarkType == .number || annotation.numberMarkType == nil else { return nil }
        center = NSPoint(x: rect.minX, y: rect.maxY)
    case .decrement:
        guard annotation.numberMarkType == .number || annotation.numberMarkType == nil else { return nil }
        center = NSPoint(x: rect.minX, y: rect.minY)
    }
    return NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
}

private func numberHandleHitTarget(at point: NSPoint) -> NumberHandleHit? {
    guard interactionMode == .annotating,
          let selectedAnnotationIndex,
          annotations.indices.contains(selectedAnnotationIndex),
          annotations[selectedAnnotationIndex].kind == .numberSequence,
          activeToolCanEdit(annotationKind: .numberSequence)
    else { return nil }
    for kind in [NumberHandleKind.delete, .resize, .increment, .decrement] {
        if let rect = numberHandleRect(for: annotations[selectedAnnotationIndex], kind: kind),
           rect.insetBy(dx: -3, dy: -3).contains(point) {
            return NumberHandleHit(index: selectedAnnotationIndex, kind: kind)
        }
    }
    return nil
}
```

- [ ] **Step 4: Draw handles**

In `drawSelectedAnnotationOutline(_:)`, add first:

```swift
if annotation.kind == .numberSequence {
    drawSelectedNumberMarkOutline(annotation)
    return
}
```

Add:

```swift
private func drawSelectedNumberMarkOutline(_ annotation: CaptureAnnotation) {
    let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
    NSColor.systemBlue.setStroke()
    let outline = NSBezierPath(rect: rect)
    outline.lineWidth = 1.5
    outline.setLineDash([4, 3], count: 2, phase: 0)
    outline.stroke()
    drawNumberHandle(.delete, for: annotation, enabled: true)
    drawNumberHandle(.resize, for: annotation, enabled: true)
    if annotation.numberMarkType == .number || annotation.numberMarkType == nil {
        drawNumberHandle(.increment, for: annotation, enabled: canMoveNumberAnnotation(annotation, direction: 1))
        drawNumberHandle(.decrement, for: annotation, enabled: canMoveNumberAnnotation(annotation, direction: -1))
    }
}

private func drawNumberHandle(_ kind: NumberHandleKind, for annotation: CaptureAnnotation, enabled: Bool) {
    guard let rect = numberHandleRect(for: annotation, kind: kind) else { return }
    switch kind {
    case .delete:
        NSColor.systemBlue.setFill()
        NSBezierPath(ovalIn: rect).fill()
        drawNumberSymbol("×", in: rect.insetBy(dx: 2, dy: 2), color: .white)
    case .resize:
        (enabled ? NSColor.systemBlue : NSColor.disabledControlTextColor).setFill()
        NSBezierPath(ovalIn: rect).fill()
    case .increment, .decrement:
        NSColor.white.setFill()
        NSBezierPath(rect: rect).fill()
        (enabled ? NSColor.systemBlue : NSColor.disabledControlTextColor).setStroke()
        NSBezierPath(rect: rect).stroke()
        drawNumberSymbol(kind == .increment ? "+" : "−", in: rect.insetBy(dx: 1, dy: 1), color: enabled ? .systemBlue : .disabledControlTextColor)
    }
}
```

- [ ] **Step 5: Handle clicks and resize**

Update `handleNumberHandleMouseDown`:

```swift
private func handleNumberHandleMouseDown(_ hit: NumberHandleHit, at point: NSPoint) {
    selectAnnotation(at: hit.index)
    switch hit.kind {
    case .delete:
        _ = deleteSelectedAnnotation()
    case .resize:
        beginAnnotationResize(with: .bottomRight)
    case .increment:
        swapNumberAnnotation(at: hit.index, direction: 1)
    case .decrement:
        swapNumberAnnotation(at: hit.index, direction: -1)
    }
}
```

Update `deleteSelectedAnnotation()` after remove:

```swift
renumberNumberSequenceAnnotations()
```

Update `updateResizingShape(to:)` before text branch:

```swift
if annotations[selectedAnnotationIndex].kind == .numberSequence {
    updateNumberAnnotationResize(at: selectedAnnotationIndex, to: point, startRect: resizingAnnotationStartRect, startStyle: resizingAnnotationStartStyle ?? annotations[selectedAnnotationIndex].style)
    return
}
```

Add:

```swift
private func updateNumberAnnotationResize(at index: Int, to point: NSPoint, startRect: NSRect, startStyle: CaptureAnnotationStyle) {
    let center = NSPoint(x: startRect.midX, y: startRect.midY)
    let startDistance = max(1, hypot(startRect.maxX - center.x, startRect.minY - center.y))
    let currentDistance = max(1, hypot(point.x - center.x, point.y - center.y))
    var style = startStyle
    style.textSize = clampedNumberSize(startStyle.textSize * currentDistance / startDistance)
    let nextRect = CaptureAnnotationRenderer.numberMarkRect(centeredAt: center, fontSize: style.textSize)
    annotations[index].style = style
    annotations[index].rect = localAnnotationRect(from: nextRect)
    currentStyle = style
    numberStyle = style
}
```

- [ ] **Step 6: Implement adjacent swaps**

```swift
private func numericNumberAnnotationIndices() -> [Int] {
    annotations.indices.filter {
        annotations[$0].kind == .numberSequence &&
        (annotations[$0].numberMarkType == .number || annotations[$0].numberMarkType == nil)
    }
}

private func canMoveNumberAnnotation(_ annotation: CaptureAnnotation, direction: Int) -> Bool {
    guard let selectedAnnotationIndex else { return false }
    let indices = numericNumberAnnotationIndices()
    guard let position = indices.firstIndex(of: selectedAnnotationIndex) else { return false }
    return indices.indices.contains(position + direction)
}

private func swapNumberAnnotation(at index: Int, direction: Int) {
    let indices = numericNumberAnnotationIndices()
    guard let position = indices.firstIndex(of: index),
          indices.indices.contains(position + direction) else {
        return
    }
    let otherIndex = indices[position + direction]
    annotations.swapAt(index, otherIndex)
    selectedAnnotationIndex = otherIndex
    renumberNumberSequenceAnnotations()
    redoAnnotations.removeAll()
    needsDisplay = true
}
```

- [ ] **Step 7: Run handle tests**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): edit and reorder number marks"
```

---

### Task 8: Overlay Preview and Export Consistency

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`
- Modify: `platforms/mac/Tests/xxsnapMacTests.swift`

- [ ] **Step 1: Write failing preview/export tests**

Add to `SelectionToolbarStateTests`:

```swift
func testOverlayRendersStandaloneCheckWithoutBackgroundCircle() throws {
    let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 300, height: 220), color: .white)) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 180, height: 120))
    window.test_activateNumberTool()
    window.test_setNumberMarkType(.check)
    window.test_mouseDown(at: NSPoint(x: 160, y: 140))
    window.test_mouseUp(at: NSPoint(x: 160, y: 140))

    let image = try XCTUnwrap(window.test_renderedOverlayImage())
    let corner = try XCTUnwrap(rgbaPixel(in: image, at: NSPoint(x: 145, y: image.size.height - 125)))
    XCTAssertGreaterThan(corner.red, 245)
    XCTAssertGreaterThan(corner.green, 245)
    XCTAssertGreaterThan(corner.blue, 245)
}
```

Add to `xxsnapMacTests`:

```swift
func testNumberExportUsesSequenceIndexAndSelectedColor() throws {
    var style = CaptureAnnotationStyle()
    style.strokeColor = NSColor(srgbRed: 0.1, green: 0.25, blue: 1, alpha: 1)
    style.textSize = 28
    let mark = CaptureAnnotation(
        kind: .numberSequence,
        rect: NSRect(x: 30, y: 30, width: 42, height: 42),
        style: style,
        numberMarkType: .number,
        numberSequenceIndex: 7
    )
    let rendered = CaptureAnnotationRenderer.render(
        image: solidImage(size: NSSize(width: 120, height: 100), color: .white),
        annotations: [mark]
    )
    let fill = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: 51, y: 49)))
    XCTAssertGreaterThan(fill.blue, 180)
}
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapTests/SelectionToolbarStateTests/testOverlayRendersStandaloneCheckWithoutBackgroundCircle -only-testing:xxsnapTests/xxsnapMacTests/testNumberExportUsesSequenceIndexAndSelectedColor test
```

Expected: FAIL until overlay draw path calls the number renderer.

- [ ] **Step 3: Draw number annotations in overlay**

In overlay annotation drawing switch, add `.numberSequence`:

```swift
case .numberSequence:
    drawNumberSequenceAnnotation(annotation, inOverlay: true)
```

Add overlay helper:

```swift
private func drawNumberSequenceAnnotation(_ annotation: CaptureAnnotation, inOverlay: Bool) {
    let rect = inOverlay ? overlayRect(fromLocalAnnotationRect: annotation.rect).standardized : annotation.rect.standardized
    switch annotation.numberMarkType ?? .number {
    case .number:
        annotation.style.strokeColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
        let label = "\(max(1, annotation.numberSequenceIndex ?? 1))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: max(3, annotation.style.textSize), weight: .bold),
            .foregroundColor: readableNumberForegroundColor(on: annotation.style.strokeColor),
        ]
        let size = NSString(string: label).size(withAttributes: attributes)
        NSString(string: label).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    case .check:
        drawNumberSymbol("✓", in: rect, color: annotation.style.strokeColor)
    case .cross:
        drawNumberSymbol("×", in: rect, color: annotation.style.strokeColor)
    }
}

private func readableNumberForegroundColor(on color: NSColor) -> NSColor {
    let rgb = color.usingColorSpace(.deviceRGB) ?? color
    let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    return luminance > 0.68 ? NSColor.black.withAlphaComponent(0.86) : .white
}
```

- [ ] **Step 4: Ensure export clipping remains existing behavior**

Do not change `finish(action:)` or `CaptureSelectionResult.snapshotRect`. Confirm annotations outside the selection remain in `annotations` but are clipped by current export flow.

- [ ] **Step 5: Run preview/export tests**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift platforms/mac/Tests/SelectionToolbarStateTests.swift platforms/mac/Tests/xxsnapMacTests.swift
git commit -m "feat(mac): render number marks in overlay"
```

---

### Task 9: Final Integration Tests and Documentation

**Files:**
- Modify: `docs/annotation-tools-user-guide.md`
- Modify: `docs/requirements/xxsnap-mac-feature-requirements.md`
- Test only: `platforms/mac/Tests/SelectionToolbarStateTests.swift`
- Test only: `platforms/mac/Tests/xxsnapMacTests.swift`

- [ ] **Step 1: Inspect existing doc changes before editing**

Run:

```bash
git diff -- docs/annotation-tools-user-guide.md docs/requirements/xxsnap-mac-feature-requirements.md
```

Expected: output may include existing user changes. Preserve them.

- [ ] **Step 2: Update user guide**

In `docs/annotation-tools-user-guide.md`, update the supported tool count and add a short sequence-tool section:

```markdown
### 7. 序号

序号工具用于给操作步骤添加编号，也可以添加对勾或叉号标记。

- 点击主工具栏“序号”进入标注模式。
- 第二工具栏可切换“序号 / 对勾 / 叉号”，设置字号 `3...72`，并选择颜色。
- 序号标注显示为彩色圆圈；对勾和叉号没有背景圆圈。
- 点击截图区域内外都可以创建标注。
- 拖动标注本体可以移动；右上角蓝色叉可删除；右下角圆点可缩放。
- 数字标注左上角 `+` 和左下角 `-` 用于和相邻数字交换顺序。
- 删除数字标注后，剩余数字会自动连续重排。
```

Remove sequence from the “still in development” sentence while preserving other unfinished tools.

- [ ] **Step 3: Update requirements status**

In `docs/requirements/xxsnap-mac-feature-requirements.md`, update the status rows and the `8.1 序号` section to match implemented behavior. Include:

```markdown
- 支持序号、对勾、叉号三种标注类型。
- 序号支持自动递增、删除后连续重排，以及通过 `+` / `-` 与相邻数字交换。
- 对勾和叉号不参与数字排序。
- 字号范围为 `3...72`，并驱动标注整体大小。
- 支持在截图选区内外创建标注；复制/保存仍按截图选区裁剪。
```

- [ ] **Step 4: Run targeted tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapTests/SelectionToolbarStateTests -only-testing:xxsnapTests/xxsnapMacTests test
```

Expected: PASS.

- [ ] **Step 5: Run full mac tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Expected: PASS. If it fails for signing or local permissions, capture the exact error and run the largest available subset.

- [ ] **Step 6: Commit docs and final test adjustments**

```bash
git add docs/annotation-tools-user-guide.md docs/requirements/xxsnap-mac-feature-requirements.md platforms/mac/Tests/SelectionToolbarStateTests.swift platforms/mac/Tests/xxsnapMacTests.swift
git commit -m "docs: document number sequence tool"
```

---

### Task 10: Manual Smoke Check

**Files:**
- No source files expected.

- [ ] **Step 1: Build debug app**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Restart debug app**

Run:

```bash
pkill -f "/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/xxsnap.app/Contents/MacOS/xxsnap" || true
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/xxsnap.app
pgrep -af "xxsnap.app/Contents/MacOS/xxsnap"
```

Expected: a running `xxsnap.app/Contents/MacOS/xxsnap` process is listed.

- [ ] **Step 3: Manual workflow**

Verify:

- create a selection;
- click number tool;
- main-toolbar number icon has no bottom-right triangle and remains black;
- second toolbar shows type dropdown, size dropdown `3...72`, and colors;
- cursor becomes colored number/check/cross over drawable overlay;
- cursor returns to normal pointer over main toolbar, second toolbar, pixel display, and size/aspect-ratio controls;
- create numeric marks inside and outside selection;
- create standalone check and cross marks with no background circle;
- change colors;
- resize to minimum and maximum limits;
- delete a middle number and confirm continuous renumbering;
- use `+` and `-` to swap adjacent numeric marks;
- copy or save and verify exported image follows existing selection crop.

- [ ] **Step 4: Final status**

Run:

```bash
git status --short --branch
```

Expected: only pre-existing unrelated changes remain, or a clean working tree if all user doc changes were intentionally included.
