# Marker Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the mac screenshot overlay `标记` tool as a straight, editable, semi-transparent highlighter annotation.

**Architecture:** Add a dedicated marker annotation model instead of reusing brush or arrow line internals. Marker uses the existing overlay annotation pipeline, with its own toolbar mode, cursor style, hit testing, drawing, movement, and renderer path. Existing shape, arrow line, brush, copy, save, undo, and redo behavior must stay unchanged.

**Tech Stack:** Swift, AppKit, XCTest, existing `SelectionOverlayWindow`, `SelectionToolbarState`, and `CaptureAnnotationRenderer`.

---

### Task 1: Marker Model And Renderer

**Files:**
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
- Modify: `platforms/mac/Tests/SniporyMacTests.swift`

- [ ] **Step 1: Write failing renderer and model tests**

Add tests to `platforms/mac/Tests/SniporyMacTests.swift` near the existing brush renderer tests:

```swift
func testAnnotationRendererDrawsMarkerLineOntoImageWithFixedOpacity() throws {
    var style = CaptureAnnotationStyle()
    style.strokeColor = NSColor(srgbRed: 212 / 255, green: 238 / 255, blue: 167 / 255, alpha: 1)
    style.strokeWidth = 18

    let marker = CaptureMarkerLine(start: NSPoint(x: 20, y: 30), end: NSPoint(x: 90, y: 30))
    let image = try makeBitmapImage(pointSize: NSSize(width: 120, height: 80), fill: .white)
    let rendered = CaptureAnnotationRenderer.render(
        image: image,
        annotations: [CaptureAnnotation(kind: .marker, rect: marker.boundingRect, style: style, markerLine: marker)]
    )

    let pixel = try rgbaPixel(in: rendered, x: 55, y: 30)
    XCTAssertNotNil(pixel)
    XCTAssertLessThan(pixel!.red, 255)
    XCTAssertGreaterThan(pixel!.green, 240)
    XCTAssertLessThan(pixel!.alpha, 255)
}

func testAnnotationRendererPreservesImageDimensionsWhenDrawingMarker() throws {
    var style = CaptureAnnotationStyle()
    style.strokeColor = NSColor(srgbRed: 212 / 255, green: 238 / 255, blue: 167 / 255, alpha: 1)
    style.strokeWidth = 22

    let marker = CaptureMarkerLine(start: NSPoint(x: -20, y: 20), end: NSPoint(x: 140, y: 20))
    let image = try makeBitmapImage(pointSize: NSSize(width: 120, height: 80), fill: .white)
    let rendered = CaptureAnnotationRenderer.render(
        image: image,
        annotations: [CaptureAnnotation(kind: .marker, rect: marker.boundingRect, style: style, markerLine: marker)]
    )

    XCTAssertEqual(rendered.size, image.size)
    XCTAssertEqual(rendered.representations.first?.pixelsWide, image.representations.first?.pixelsWide)
    XCTAssertEqual(rendered.representations.first?.pixelsHigh, image.representations.first?.pixelsHigh)
}
```

- [ ] **Step 2: Run renderer tests to verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SniporyMacTests/testAnnotationRendererDrawsMarkerLineOntoImageWithFixedOpacity -only-testing:xxsnapTests/SniporyMacTests/testAnnotationRendererPreservesImageDimensionsWhenDrawingMarker
```

Expected: compile fails because `CaptureMarkerLine`, `.marker`, and `markerLine` do not exist.

- [ ] **Step 3: Add marker model and render path**

In `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`, extend the shared overlay model:

```swift
enum CaptureAnnotationKind {
    case rectangle
    case ellipse
    case arrowLine
    case brush
    case marker
}

struct CaptureMarkerLine: Equatable {
    var start: NSPoint
    var end: NSPoint

    var boundingRect: NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

struct CaptureAnnotation {
    var kind: CaptureAnnotationKind
    var rect: NSRect
    var style: CaptureAnnotationStyle
    var arrowLine: CaptureArrowLine?
    var brushPath: CaptureBrushPath?
    var markerLine: CaptureMarkerLine?
}
```

Add marker constants and draw dispatch in `CaptureAnnotationRenderer`:

```swift
static let markerOpacity: CGFloat = 0.65

private static func draw(_ annotation: CaptureAnnotation, in context: CGContext, scaleX: CGFloat, scaleY: CGFloat) {
    let lineScale = (scaleX + scaleY) / 2
    if annotation.kind == .marker {
        drawMarkerLine(annotation, in: context, scaleX: scaleX, scaleY: scaleY, lineScale: lineScale)
        return
    }
    if annotation.kind == .arrowLine {
        drawArrowLine(annotation, in: context, scaleX: scaleX, scaleY: scaleY, lineScale: lineScale)
        return
    }
    if annotation.kind == .brush {
        drawBrushPath(annotation, in: context, scaleX: scaleX, scaleY: scaleY, lineScale: lineScale)
        return
    }
}

private static func drawMarkerLine(
    _ annotation: CaptureAnnotation,
    in context: CGContext,
    scaleX: CGFloat,
    scaleY: CGFloat,
    lineScale: CGFloat
) {
    guard let markerLine = annotation.markerLine else {
        return
    }

    context.saveGState()
    context.setStrokeColor(cgColor(annotation.style.strokeColor.withAlphaComponent(markerOpacity)))
    context.setLineWidth(annotation.style.strokeWidth * lineScale)
    context.setLineJoin(.round)
    context.setLineCap(.round)
    context.setLineDash(phase: 0, lengths: [])

    let path = CGMutablePath()
    path.move(to: pixelPoint(markerLine.start, scaleX: scaleX, scaleY: scaleY))
    path.addLine(to: pixelPoint(markerLine.end, scaleX: scaleX, scaleY: scaleY))
    context.addPath(path)
    context.strokePath()
    context.restoreGState()
}
```

Update any exhaustive `switch annotation.kind` in this file so `.marker` returns early together with `.arrowLine` and `.brush` where shape-only rendering is handled.

- [ ] **Step 4: Run renderer tests to verify pass**

Run the same focused command from Step 2.

Expected: both marker renderer tests pass.

- [ ] **Step 5: Commit model and renderer**

```bash
git add platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift platforms/mac/Tests/SniporyMacTests.swift
git commit -m "feat(mac): add marker annotation rendering"
```

### Task 2: Marker Toolbar State

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing toolbar state tests**

Add tests to `platforms/mac/Tests/SelectionToolbarStateTests.swift` near brush toolbar tests:

```swift
func testMarkerStrokeWidthValuesUseHighlighterSizes() {
    XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .marker), [14, 18, 22])
}

func testMarkerActivationUsesDefaultHighlighterStyle() {
    var current = CaptureAnnotationStyle()
    current.strokeColor = .systemRed
    current.fillColor = .systemRed
    current.strokeWidth = 4
    current.strokePattern = .dashLong
    current.fillEnabled = true

    let style = SelectionToolbarState.markerActivationStyle(currentStyle: current)

    XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#D4EEA7")
    XCTAssertEqual(style.strokeWidth, 18)
    XCTAssertEqual(style.strokePattern, .solid)
    XCTAssertFalse(style.fillEnabled)
}

func testMarkerOptionsToolbarShowsWidthAndColorsOnly() {
    let optionsRect = NSRect(x: 100, y: 100, width: 360, height: 40)
    let layout = SelectionToolbarState.optionsToolbarLayout(
        in: optionsRect,
        paletteCount: 8,
        mode: .marker
    )

    XCTAssertEqual(layout.strokeWidths.count, 3)
    XCTAssertNil(layout.fillToggle)
    XCTAssertNil(layout.rectangleMode)
    XCTAssertNil(layout.ellipseMode)
    XCTAssertNil(layout.startArrowType)
    XCTAssertNil(layout.endArrowType)
    XCTAssertGreaterThan(layout.colorSwatches.first!.minX, layout.strokeWidths.last!.maxX)
}
```

- [ ] **Step 2: Run focused toolbar tests to verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testMarkerStrokeWidthValuesUseHighlighterSizes -only-testing:xxsnapTests/SelectionToolbarStateTests/testMarkerActivationUsesDefaultHighlighterStyle -only-testing:xxsnapTests/SelectionToolbarStateTests/testMarkerOptionsToolbarShowsWidthAndColorsOnly
```

Expected: compile fails because `.marker` options mode and `markerActivationStyle` do not exist.

- [ ] **Step 3: Implement marker toolbar state**

In `SelectionToolbarState.swift`, extend toolbar mode and activation style:

```swift
enum OptionsToolbarMode: Equatable {
    case shape
    case arrowLine
    case brush
    case marker
}

static let defaultMarkerColor = NSColor(srgbRed: 212 / 255, green: 238 / 255, blue: 167 / 255, alpha: 1)

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
    }
}

static func markerActivationStyle(currentStyle: CaptureAnnotationStyle) -> CaptureAnnotationStyle {
    var style = currentStyle
    style.strokeColor = defaultMarkerColor
    style.fillColor = defaultMarkerColor
    style.strokeWidth = strokeWidthValues(for: .marker)[1]
    style.strokePattern = .solid
    style.fillEnabled = false
    return style
}
```

Update layout helpers:

```swift
static func strokePatternOptions(
    canUsePremiumStrokePatterns: Bool,
    mode: OptionsToolbarMode = .shape
) -> [StrokePatternOption] {
    let patterns: [CaptureStrokePattern]
    switch mode {
    case .brush:
        patterns = [.solid, .dashLong, .dashNarrow, .dashLongShort]
    case .marker:
        patterns = [.solid]
    case .shape, .arrowLine:
        patterns = CaptureStrokePattern.allCases
    }

    return patterns.map { pattern in
        StrokePatternOption(
            pattern: pattern,
            requiresPremiumAccess: pattern.requiresPremiumAccess,
            isEnabled: true
        )
    }
}

private static func colorSwatchStartXOffset(mode: OptionsToolbarMode) -> CGFloat {
    switch mode {
    case .shape:
        return 325
    case .arrowLine:
        return 318
    case .brush:
        return 210
    case .marker:
        return 98
    }
}
```

Keep `strokeStyle` non-nil in `OptionsToolbarLayout` for compatibility, but hide/don't draw it in overlay for marker mode in Task 3.

- [ ] **Step 4: Run focused toolbar tests to verify pass**

Run the command from Step 2.

Expected: all three marker toolbar tests pass.

- [ ] **Step 5: Commit toolbar state**

```bash
git add platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): add marker toolbar state"
```

### Task 3: Marker Overlay Activation, Cursor, And Drawing

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing overlay interaction tests**

Add tests to `SelectionToolbarStateTests.swift` near brush interaction tests:

```swift
func testOverlayWindowDrawsMarkerAnnotationFromDrag() {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
    window.test_activateShapeTool(.marker)

    window.test_mouseDown(at: NSPoint(x: 130, y: 150))
    window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
    window.test_mouseUp(at: NSPoint(x: 220, y: 180))

    XCTAssertEqual(window.test_annotationCount, 1)
    XCTAssertEqual(window.test_selectedAnnotationKind, .marker)
    guard let line = window.test_markerLine(at: 0) else {
        return XCTFail("Expected marker annotation")
    }
    XCTAssertEqual(line.start.x, 30, accuracy: 0.1)
    XCTAssertEqual(line.start.y, 50, accuracy: 0.1)
    XCTAssertEqual(line.end.x, 120, accuracy: 0.1)
    XCTAssertEqual(line.end.y, 80, accuracy: 0.1)
}

func testMarkerShiftDragSnapsToNearestHorizontalVerticalOrDiagonal() {
    let start = NSPoint(x: 100, y: 100)
    XCTAssertEqual(
        SelectionToolbarState.snappedMarkerEndPoint(start: start, rawEnd: NSPoint(x: 180, y: 112), isShiftPressed: true),
        NSPoint(x: 180, y: 100)
    )
    XCTAssertEqual(
        SelectionToolbarState.snappedMarkerEndPoint(start: start, rawEnd: NSPoint(x: 112, y: 180), isShiftPressed: true),
        NSPoint(x: 100, y: 180)
    )
    XCTAssertEqual(
        SelectionToolbarState.snappedMarkerEndPoint(start: start, rawEnd: NSPoint(x: 170, y: 155), isShiftPressed: true),
        NSPoint(x: 170, y: 170)
    )
}

func testOverlayWindowIgnoresVeryShortMarkerDrag() {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
    window.test_activateShapeTool(.marker)

    window.test_mouseDown(at: NSPoint(x: 130, y: 150))
    window.test_mouseDragged(to: NSPoint(x: 134, y: 153))
    window.test_mouseUp(at: NSPoint(x: 134, y: 153))

    XCTAssertEqual(window.test_annotationCount, 0)
}
```

- [ ] **Step 2: Run focused overlay tests to verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testOverlayWindowDrawsMarkerAnnotationFromDrag -only-testing:xxsnapTests/SelectionToolbarStateTests/testMarkerShiftDragSnapsToNearestHorizontalVerticalOrDiagonal -only-testing:xxsnapTests/SelectionToolbarStateTests/testOverlayWindowIgnoresVeryShortMarkerDrag
```

Expected: compile fails because marker helpers and test accessors do not exist.

- [ ] **Step 3: Add marker snap helper and cursor style**

In `SelectionToolbarState.swift`, add cursor style and snapping:

```swift
enum OverlayCursorStyle: Equatable {
    case arrow
    case crosshair
    case move
    case resizeLeftRight
    case resizeUpDown
    case resizeTopLeft
    case resizeTopRight
    case resizeBottomLeft
    case resizeBottomRight
    case rotationHandle
    case brush
    case marker
}

static func snappedMarkerEndPoint(start: NSPoint, rawEnd: NSPoint, isShiftPressed: Bool) -> NSPoint {
    guard isShiftPressed else {
        return rawEnd
    }
    let dx = rawEnd.x - start.x
    let dy = rawEnd.y - start.y
    guard hypot(dx, dy) >= 0.001 else {
        return rawEnd
    }
    let angle = atan2(dy, dx)
    let step = CGFloat.pi / 4
    let snappedAngle = (angle / step).rounded() * step
    let projectedLength = hypot(dx, dy)
    return NSPoint(
        x: start.x + cos(snappedAngle) * projectedLength,
        y: start.y + sin(snappedAngle) * projectedLength
    )
}
```

Update `overlayCursorStyle(isSelecting:isToolbarOrPanelPoint:resizeHandle:selectionResizeHandle:isAnnotationBorder:isInsideSelection:isShapeToolActive:currentShapeKind:)` so marker acts like brush but returns `.marker` inside the selection:

```swift
if isShapeToolActive, currentShapeKind == .marker {
    return isInsideSelection ? .marker : .arrow
}
```

- [ ] **Step 4: Add marker activation and draft creation in overlay**

In `SelectionOverlayWindow.swift`:

```swift
case .marker:
    toggleShapeTool(.marker)
    showsStrokeStyleMenu = false
    showsCornerRadiusPanel = false
    showsStartArrowTypeMenu = false
    showsEndArrowTypeMenu = false
```

Update `toggleShapeTool(_:)`:

```swift
} else if activeShapeKind == .marker {
    currentStyle = SelectionToolbarState.markerActivationStyle(currentStyle: currentStyle)
    showsCornerRadiusPanel = false
}
```

Update `draftAnnotation` before arrow line handling:

```swift
if currentShapeKind == .marker {
    let rawEnd = shapeCurrentPoint
    let overlayLine = CaptureMarkerLine(start: shapeStartPoint, end: rawEnd)
    let localLine = localMarkerLine(fromOverlayMarkerLine: overlayLine)
    return CaptureAnnotation(
        kind: .marker,
        rect: localLine.boundingRect,
        style: currentStyle,
        markerLine: localLine
    )
}
```

Update dragging and mouse-up to apply Shift snapping:

```swift
private func markerEndPoint(from point: NSPoint, modifierFlags: NSEvent.ModifierFlags) -> NSPoint {
    guard currentShapeKind == .marker, let shapeStartPoint else {
        return point
    }
    return SelectionToolbarState.snappedMarkerEndPoint(
        start: shapeStartPoint,
        rawEnd: point,
        isShiftPressed: modifierFlags.contains(.shift)
    )
}
```

Use `markerEndPoint(from:modifierFlags:)` when setting `shapeCurrentPoint` in `.drawingShape` and recovered `.annotating` drag paths.

Add local/overlay conversion helpers:

```swift
private func localMarkerLine(fromOverlayMarkerLine line: CaptureMarkerLine, selectionRect: NSRect? = nil) -> CaptureMarkerLine {
    let selectionRect = selectionRect ?? lockedSelectionRect ?? .zero
    return CaptureMarkerLine(
        start: NSPoint(x: line.start.x - selectionRect.minX, y: line.start.y - selectionRect.minY),
        end: NSPoint(x: line.end.x - selectionRect.minX, y: line.end.y - selectionRect.minY)
    )
}

private func overlayMarkerLine(fromLocalMarkerLine line: CaptureMarkerLine?, selectionRect: NSRect? = nil) -> CaptureMarkerLine? {
    guard let line else {
        return nil
    }
    let selectionRect = selectionRect ?? lockedSelectionRect ?? .zero
    return CaptureMarkerLine(
        start: NSPoint(x: selectionRect.minX + line.start.x, y: selectionRect.minY + line.start.y),
        end: NSPoint(x: selectionRect.minX + line.end.x, y: selectionRect.minY + line.end.y)
    )
}
```

Update usability:

```swift
if annotation.kind == .marker, let markerLine = annotation.markerLine {
    return hypot(markerLine.end.x - markerLine.start.x, markerLine.end.y - markerLine.start.y) >= 8
}
```

Add DEBUG accessor:

```swift
func test_markerLine(at index: Int) -> CaptureMarkerLine? {
    guard annotations.indices.contains(index) else {
        return nil
    }
    return annotations[index].markerLine
}
```

- [ ] **Step 5: Add marker cursor drawing**

Add an `NSCursor.xxsnapMarker(color:)` helper near the existing custom cursor helpers in `SelectionOverlayWindow.swift`:

```swift
static func xxsnapMarker(color: NSColor) -> NSCursor {
    let size = NSSize(width: 24, height: 24)
    let image = NSImage(size: size)
    image.lockFocus()
    let rect = NSRect(x: 3, y: 3, width: 18, height: 18)
    NSColor.white.withAlphaComponent(0.94).setFill()
    NSBezierPath(ovalIn: rect.insetBy(dx: -2, dy: -2)).fill()
    color.withAlphaComponent(1).setFill()
    NSBezierPath(ovalIn: rect).fill()
    image.unlockFocus()
    return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
}
```

Update `setCursor(_:)`:

```swift
case .marker:
    NSCursor.xxsnapMarker(color: currentStyle.strokeColor).set()
```

- [ ] **Step 6: Draw marker annotations in overlay**

In `drawAnnotation(_:, inOverlay:)`, add marker dispatch before arrow line:

```swift
if annotation.kind == .marker {
    drawMarkerAnnotation(annotation)
    return
}
```

Add:

```swift
private func drawMarkerAnnotation(_ annotation: CaptureAnnotation) {
    guard let markerLine = overlayMarkerLine(fromLocalMarkerLine: annotation.markerLine) else {
        return
    }
    let path = NSBezierPath()
    path.move(to: markerLine.start)
    path.line(to: markerLine.end)
    path.lineWidth = annotation.style.strokeWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    annotation.style.strokeColor.withAlphaComponent(CaptureAnnotationRenderer.markerOpacity).setStroke()
    path.stroke()
}
```

- [ ] **Step 7: Run overlay tests to verify pass**

Run the focused command from Step 2.

Expected: all three marker overlay tests pass.

- [ ] **Step 8: Commit overlay activation and drawing**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): activate marker annotation tool"
```

### Task 4: Marker Selection, Movement, And Style Editing

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing editing tests**

Add tests to `SelectionToolbarStateTests.swift`:

```swift
func testOverlayWindowMovesSelectedMarkerAnnotation() {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
    window.test_activateShapeTool(.marker)
    window.test_mouseDown(at: NSPoint(x: 130, y: 150))
    window.test_mouseDragged(to: NSPoint(x: 220, y: 150))
    window.test_mouseUp(at: NSPoint(x: 220, y: 150))

    guard let original = window.test_markerLine(at: 0) else {
        return XCTFail("Expected marker annotation")
    }
    window.test_mouseDown(at: NSPoint(x: 170, y: 150))
    window.test_mouseDragged(to: NSPoint(x: 195, y: 168))
    window.test_mouseUp(at: NSPoint(x: 195, y: 168))

    guard let moved = window.test_markerLine(at: 0) else {
        return XCTFail("Expected moved marker annotation")
    }
    XCTAssertEqual(moved.start.x, original.start.x + 25, accuracy: 0.1)
    XCTAssertEqual(moved.start.y, original.start.y + 18, accuracy: 0.1)
    XCTAssertEqual(moved.end.x, original.end.x + 25, accuracy: 0.1)
    XCTAssertEqual(moved.end.y, original.end.y + 18, accuracy: 0.1)
}

func testMarkerAnnotationStyleIsEditableAfterDrawing() {
    XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.marker))
    XCTAssertFalse(SelectionToolbarState.annotationKindSupportsGeometryEditing(.marker))
}

func testDeleteKeyRemovesSelectedMarkerAnnotation() {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
    window.test_activateShapeTool(.marker)
    window.test_mouseDown(at: NSPoint(x: 130, y: 150))
    window.test_mouseDragged(to: NSPoint(x: 220, y: 150))
    window.test_mouseUp(at: NSPoint(x: 220, y: 150))
    window.test_mouseDown(at: NSPoint(x: 170, y: 150))
    window.test_mouseUp(at: NSPoint(x: 170, y: 150))

    XCTAssertEqual(window.test_selectedAnnotationKind, .marker)
    window.test_keyDown(keyCode: 51)
    XCTAssertEqual(window.test_annotationCount, 0)
}
```

- [ ] **Step 2: Run focused editing tests to verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testOverlayWindowMovesSelectedMarkerAnnotation -only-testing:xxsnapTests/SelectionToolbarStateTests/testMarkerAnnotationStyleIsEditableAfterDrawing -only-testing:xxsnapTests/SelectionToolbarStateTests/testDeleteKeyRemovesSelectedMarkerAnnotation
```

Expected: at least movement and support-helper tests fail.

- [ ] **Step 3: Add marker hit testing helper**

In `SelectionToolbarState.swift`, expose segment distance for marker:

```swift
static func markerLineContains(point: NSPoint, line: CaptureMarkerLine, hitOutset: CGFloat) -> Bool {
    distanceFromSegment(point: point, start: line.start, end: line.end) <= hitOutset
}
```

Make `distanceFromSegment` internal to `SelectionToolbarState` by removing `private`.

Update support helpers:

```swift
static func annotationKindSupportsPostDrawEditing(_ kind: CaptureAnnotationKind) -> Bool {
    kind != .brush
}

static func annotationKindSupportsGeometryEditing(_ kind: CaptureAnnotationKind) -> Bool {
    switch kind {
    case .rectangle, .ellipse:
        return true
    case .arrowLine, .brush, .marker:
        return false
    }
}
```

- [ ] **Step 4: Wire marker hit testing and movement**

In `SelectionOverlayWindow.swift`, update `annotationBorderContains(_:for:)`:

```swift
if annotation.kind == .marker {
    guard let markerLine = overlayMarkerLine(fromLocalMarkerLine: annotation.markerLine) else {
        return false
    }
    return SelectionToolbarState.markerLineContains(
        point: point,
        line: markerLine,
        hitOutset: max(8, annotation.style.strokeWidth / 2 + 4)
    )
}
```

Update move state to capture marker:

```swift
private var movingAnnotationStartMarkerLine: CaptureMarkerLine?
```

In `beginAnnotationMove(at:point:)`:

```swift
movingAnnotationStartMarkerLine = overlayMarkerLine(fromLocalMarkerLine: annotations[index].markerLine)
```

In `updateMovingShape(to:)`, handle marker before brush/rect fallback:

```swift
if let movingAnnotationStartMarkerLine {
    let dx = requested.minX - movingAnnotationStartRect.minX
    let dy = requested.minY - movingAnnotationStartRect.minY
    let movedOverlayLine = CaptureMarkerLine(
        start: NSPoint(x: movingAnnotationStartMarkerLine.start.x + dx, y: movingAnnotationStartMarkerLine.start.y + dy),
        end: NSPoint(x: movingAnnotationStartMarkerLine.end.x + dx, y: movingAnnotationStartMarkerLine.end.y + dy)
    )
    let localLine = localMarkerLine(fromOverlayMarkerLine: movedOverlayLine)
    annotations[selectedAnnotationIndex].markerLine = localLine
    annotations[selectedAnnotationIndex].rect = localLine.boundingRect
    return
}
```

Clear `movingAnnotationStartMarkerLine` in `commitSelectedShapePreview()`.

- [ ] **Step 5: Ensure marker style editing uses marker toolbar**

Update `optionsToolbarMode`:

```swift
private var optionsToolbarMode: SelectionToolbarState.OptionsToolbarMode {
    switch currentShapeKind {
    case .arrowLine:
        return .arrowLine
    case .brush:
        return .brush
    case .marker:
        return .marker
    case .rectangle, .ellipse:
        return .shape
    }
}
```

Update `activeToolCanEdit(annotationKind:)`:

```swift
case .marker:
    return kind == .marker
```

Update `drawOptionsToolbar(for:)` so marker does not draw the stroke style field. Keep the existing draw calls in their current functions; only route them by mode:

```swift
switch optionsToolbarMode {
case .shape:
    drawFillToggle(layout.fillToggle)
    drawShapeModeControls(rectangleButton: layout.rectangleMode, ellipseButton: layout.ellipseMode)
    drawStrokeStyleField(layout.strokeStyle)
case .arrowLine:
    drawStrokeStyleField(layout.strokeStyle)
    drawArrowTypeFields(startField: layout.startArrowType, endField: layout.endArrowType)
case .brush:
    drawStrokeStyleField(layout.strokeStyle)
case .marker:
    break
}
```

Ensure `handleOptionsClick(at:)` ignores `layout.strokeStyle` for marker:

```swift
if optionsToolbarMode != .marker, layout.strokeStyle.contains(point) {
    showsStrokeStyleMenu.toggle()
    showsCornerRadiusPanel = false
    showsStartArrowTypeMenu = false
    showsEndArrowTypeMenu = false
    return true
}
```

- [ ] **Step 6: Run editing tests to verify pass**

Run the focused command from Step 2.

Expected: all marker editing tests pass.

- [ ] **Step 7: Commit marker editing**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): support marker editing"
```

### Task 5: Regression Coverage And Full Verification

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`
- Modify: `platforms/mac/Tests/SniporyMacTests.swift`

- [ ] **Step 1: Add regression tests for existing tools**

Add or update tests to keep existing tools stable:

```swift
func testMarkerToolSelectionDoesNotChangeBrushDefaults() {
    XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .brush), [3, 5, 7])
    XCTAssertEqual(
        SelectionToolbarState.strokePatternOptions(canUsePremiumStrokePatterns: true, mode: .brush).map(\.pattern),
        [.solid, .dashLong, .dashNarrow, .dashLongShort]
    )
}

func testShapeArrowBrushAndMarkerToolbarsAreDistinct() {
    XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .shape), [2, 4, 7])
    XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .arrowLine), [3, 4, 6])
    XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .brush), [3, 5, 7])
    XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .marker), [14, 18, 22])
}
```

- [ ] **Step 2: Run focused marker and toolbar tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests -only-testing:xxsnapTests/SniporyMacTests
```

Expected: `SelectionToolbarStateTests` and `SniporyMacTests` pass.

- [ ] **Step 3: Run full mac XCTest target**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Expected: all tests pass, except the known environment-sensitive `ScreenCaptureServiceTests.testNativeScreenshotTaggedWithDisplayColorSpacePreservesSolidWindowByteValues` may fail on this machine. If it fails, record the exact failure and continue to Step 4.

- [ ] **Step 4: Run mac app build**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit final test adjustments**

If Step 1 added tests after prior commits:

```bash
git add platforms/mac/Tests/SelectionToolbarStateTests.swift platforms/mac/Tests/SniporyMacTests.swift
git commit -m "test(mac): cover marker tool regressions"
```

If no files changed after verification:

```bash
git status --short
```

Expected: no output.

### Task 6: Manual Smoke Check

**Files:**
- No source changes.

- [ ] **Step 1: Restart local debug app**

Run:

```bash
pkill -f "/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/xxsnap.app/Contents/MacOS/xxsnap" || true
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/xxsnap.app
pgrep -af "xxsnap.app/Contents/MacOS/xxsnap"
```

Expected: one running xxsnap debug app process from `build/xcode-derived`.

- [ ] **Step 2: Smoke marker workflow**

Manually verify:

- trigger screenshot capture;
- select a region;
- click `标记`;
- cursor inside the selection is a colored dot with a white soft ring;
- drag without Shift creates a free-angle rounded highlighter line;
- drag with Shift snaps to horizontal, vertical, or 45 degrees;
- select a committed marker and move it;
- change width and color from marker options toolbar;
- delete the selected marker;
- copy or save output includes the marker.

- [ ] **Step 3: Report verification status**

In the final implementation report, include:

- focused test command and result;
- full test command and result, including known `ScreenCaptureServiceTests` blocker if present;
- build command and result;
- manual smoke result or reason it could not be completed.
