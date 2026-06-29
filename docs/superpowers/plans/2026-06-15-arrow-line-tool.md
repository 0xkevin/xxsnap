# Arrow Line Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the second xxsnap mac annotation tool as an editable, exportable arrow line tool with arrow-specific toolbar controls.

**Architecture:** Keep this iteration mac-first. Extend the existing Swift annotation model and renderer, add pure toolbar/hit-test helpers in `SelectionToolbarState`, then wire the existing `SelectionOverlayWindow` mouse flow to arrow line creation and editing. Reuse the current options toolbar container and switch visible controls by active annotation kind.

**Tech Stack:** Swift/AppKit, XCTest, existing xxsnap mac target.

---

## File Structure

- Modify `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
  - Add `CaptureArrowType`, `CaptureArrowLine`, and `.arrowLine` support in `CaptureAnnotationKind`.
  - Render arrow line bodies and arrowheads in final exported images.
- Modify `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
  - Add toolbar mode helpers, arrow menu hit testing, arrow default activation style, and arrow line hit testing.
- Modify `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
  - Activate `.polyline` as the arrow line tool.
  - Switch options toolbar controls by active/selected annotation kind.
  - Draw, select, move, and edit arrow lines in the overlay.
- Modify `platforms/mac/Tests/SelectionToolbarStateTests.swift`
  - Add pure tests for tooltip, layout switching, arrow menu hit testing, default style, and arrow line hit targets.
- Modify `platforms/mac/Tests/SniporyMacTests.swift`
  - Add renderer tests proving arrow lines change exported pixels.

---

### Task 1: Toolbar State And Arrow Hit-Testing Tests

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`

- [ ] **Step 1: Write failing toolbar and hit-test tests**

Add tests like this to `SelectionToolbarStateTests`:

```swift
func testPolylineTooltipUsesArrowLineLabel() {
    XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "polyline"), "箭头线")
}

func testOptionsToolbarLayoutSwitchesShapeAndArrowControls() {
    let optionsRect = NSRect(x: 100, y: 100, width: 640, height: 40)
    let shapeLayout = SelectionToolbarState.optionsToolbarLayout(
        in: optionsRect,
        paletteCount: 8,
        mode: .shape
    )
    let arrowLayout = SelectionToolbarState.optionsToolbarLayout(
        in: optionsRect,
        paletteCount: 8,
        mode: .arrowLine
    )

    XCTAssertNotNil(shapeLayout.fillToggle)
    XCTAssertNotNil(shapeLayout.rectangleMode)
    XCTAssertNotNil(shapeLayout.ellipseMode)
    XCTAssertNil(shapeLayout.startArrowType)
    XCTAssertNil(shapeLayout.endArrowType)

    XCTAssertNil(arrowLayout.fillToggle)
    XCTAssertNil(arrowLayout.rectangleMode)
    XCTAssertNil(arrowLayout.ellipseMode)
    XCTAssertNotNil(arrowLayout.startArrowType)
    XCTAssertNotNil(arrowLayout.endArrowType)
    XCTAssertGreaterThan(arrowLayout.colorSwatches.first!.minX, arrowLayout.endArrowType!.maxX)
}

func testArrowTypeMenuHitTargetSelectsEveryMenuItem() {
    let menu = NSRect(x: 120, y: 80, width: 180, height: CGFloat(CaptureArrowType.allCases.count) * 24 + 8)

    for (index, rect) in SelectionToolbarState.arrowTypeMenuItemRects(in: menu, itemCount: CaptureArrowType.allCases.count).enumerated() {
        XCTAssertEqual(
            SelectionToolbarState.arrowTypeMenuHitTarget(
                at: NSPoint(x: rect.midX, y: rect.midY),
                in: menu,
                itemCount: CaptureArrowType.allCases.count
            ),
            .item(index)
        )
    }
}

func testDefaultArrowLineActivationUsesFirstPaletteColorAndExpectedArrowTypes() {
    let state = SelectionToolbarState.arrowLineActivationState(
        currentStyle: CaptureAnnotationStyle(),
        paletteColors: SelectionOverlayWindow.defaultPaletteColors
    )

    XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: state.style.strokeColor), "#FF001A")
    XCTAssertEqual(state.style.strokeWidth, 2)
    XCTAssertEqual(state.startArrowType, .none)
    XCTAssertEqual(state.endArrowType, .normal)
}

func testArrowLineHitTargetDistinguishesHandlesAndBody() {
    let line = CaptureArrowLine(
        start: NSPoint(x: 10, y: 10),
        end: NSPoint(x: 110, y: 10),
        control: NSPoint(x: 60, y: 60),
        startArrowType: .none,
        endArrowType: .normal
    )

    XCTAssertEqual(SelectionToolbarState.arrowLineHitTarget(at: NSPoint(x: 10, y: 10), line: line), .start)
    XCTAssertEqual(SelectionToolbarState.arrowLineHitTarget(at: NSPoint(x: 110, y: 10), line: line), .end)
    XCTAssertEqual(SelectionToolbarState.arrowLineHitTarget(at: NSPoint(x: 60, y: 60), line: line), .control)
    XCTAssertEqual(SelectionToolbarState.arrowLineHitTarget(at: NSPoint(x: 60, y: 34), line: line), .body)
    XCTAssertEqual(SelectionToolbarState.arrowLineHitTarget(at: NSPoint(x: 60, y: 90), line: line), .none)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug test
```

Expected: fails to compile because `CaptureArrowType`, `CaptureArrowLine`, `OptionsToolbarMode`, and arrow helpers do not exist yet.

- [ ] **Step 3: Add minimal model and state helpers**

Implement these types and helpers:

```swift
enum CaptureAnnotationKind {
    case rectangle
    case ellipse
    case arrowLine
}

enum CaptureArrowType: Int, CaseIterable {
    case none
    case swallowTail
    case normal
    case solidTapered
    case hollowTapered
    case sketch
}

struct CaptureArrowLine: Equatable {
    var start: NSPoint
    var end: NSPoint
    var control: NSPoint
    var startArrowType: CaptureArrowType
    var endArrowType: CaptureArrowType
}
```

Add `SelectionToolbarState.OptionsToolbarMode`, `OptionsToolbarLayout`, `ArrowTypeMenuSelection`, `ArrowLineHitTarget`, `optionsToolbarLayout`, `arrowTypeMenuItemRects`, `arrowTypeMenuHitTarget`, `arrowLineActivationState`, and `arrowLineHitTarget`.

- [ ] **Step 4: Run tests to verify Task 1 passes**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug test
```

Expected: Task 1 tests pass or the command reports an environment-specific signing/Xcode blocker.

---

### Task 2: Arrow Line Renderer Tests And Implementation

**Files:**
- Modify: `platforms/mac/Tests/SniporyMacTests.swift`
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`

- [ ] **Step 1: Write failing renderer test**

Add this test to `SniporyMacTests`:

```swift
func testAnnotationRendererDrawsArrowLineOntoImage() throws {
    let image = try makeBitmapImage(
        pointSize: NSSize(width: 80, height: 50),
        pixelWidth: 80,
        pixelHeight: 50
    )
    var style = CaptureAnnotationStyle()
    style.strokeColor = .systemRed
    style.strokeWidth = 4

    let annotation = CaptureAnnotation(
        kind: .arrowLine,
        rect: NSRect(x: 10, y: 10, width: 60, height: 30),
        style: style,
        arrowLine: CaptureArrowLine(
            start: NSPoint(x: 10, y: 12),
            end: NSPoint(x: 70, y: 36),
            control: NSPoint(x: 42, y: 42),
            startArrowType: .none,
            endArrowType: .normal
        )
    )

    let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [annotation])

    XCTAssertNotEqual(try rgbaBytes(in: rendered), try rgbaBytes(in: image))
}
```

- [ ] **Step 2: Run renderer test to verify it fails**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug test
```

Expected: fails because renderer does not handle `.arrowLine`.

- [ ] **Step 3: Implement arrow line rendering**

In `CaptureAnnotationRenderer.draw`, branch `.arrowLine` before shape path creation. Draw a quadratic curve using `start`, `control`, and `end`; apply line width, color, dash pattern, and sketch sampling. Draw arrowheads with tip-at-end geometry using `startArrowType` and `endArrowType`.

- [ ] **Step 4: Run renderer test to verify it passes**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug test
```

Expected: renderer test passes or the command reports an environment-specific signing/Xcode blocker.

---

### Task 3: Overlay Toolbar Switching And Arrow Drawing

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Add failing state tests for toolbar widths and arrow field order**

Add tests checking:

```swift
func testArrowOptionsToolbarWidthIncludesTwoArrowFields() {
    XCTAssertGreaterThan(
        SelectionToolbarState.optionsToolbarWidth(paletteCount: 8, mode: .arrowLine),
        SelectionToolbarState.optionsToolbarWidth(paletteCount: 8, mode: .shape)
    )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the mac test command. Expected: fails because width overload or arrow mode support is incomplete.

- [ ] **Step 3: Wire toolbar mode and activation**

Implement in `SelectionOverlayWindow`:

- `.polyline` calls `toggleShapeTool(.arrowLine)` instead of `showPlaceholder`.
- `buttonMatchesCurrentTool(.rectangle)` is true only for rectangle/ellipse active tools.
- `buttonMatchesCurrentTool(.polyline)` is true for `.arrowLine`.
- `optionsToolbarMode` returns `.arrowLine` when the active or selected annotation kind is `.arrowLine`, otherwise `.shape`.
- Shape-only rect helpers return nil or are skipped in arrow mode.
- Arrow field rects and menus are drawn only in arrow mode.
- `handleOptionsClick` changes `currentStartArrowType` and `currentEndArrowType`, then applies them to a selected arrow line.

- [ ] **Step 4: Run tests to verify toolbar state passes**

Run the mac test command.

---

### Task 4: Arrow Line Editing Flow

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`

- [ ] **Step 1: Implement draft creation**

When the active tool is `.arrowLine`, `draftAnnotation` should create a `CaptureAnnotation` with:

```swift
let start = localPoint(fromOverlayPoint: shapeStartPoint)
let end = localPoint(fromOverlayPoint: shapeCurrentPoint)
let control = NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
let arrowLine = CaptureArrowLine(
    start: start,
    end: end,
    control: control,
    startArrowType: currentStartArrowType,
    endArrowType: currentEndArrowType
)
```

Commit the draft when `hypot(end.x - start.x, end.y - start.y) >= 8`.

- [ ] **Step 2: Implement overlay drawing and selection handles**

Draw selected arrow lines with a dashed blue curve outline plus three handles: start, end, and control. Keep rectangle/ellipse resize handles unchanged.

- [ ] **Step 3: Implement moving and handle dragging**

Add an active arrow handle state with `.start`, `.end`, and `.control`. On drag:

- start handle updates `arrowLine.start`;
- end handle updates `arrowLine.end`;
- control handle updates `arrowLine.control`;
- body move offsets start, end, and control together.

Recompute `annotation.rect` from the arrow points after each update.

- [ ] **Step 4: Preserve arrow positions when moving/resizing the selected screenshot region**

Update selection move/resize preservation so arrow line points are converted relative to the new selection origin, not just their bounding rect.

- [ ] **Step 5: Manual smoke path**

Launch the mac app if the build succeeds, select a screenshot region, activate arrow line, draw an arrow, drag the control point, drag the body, drag each endpoint, change color, change stroke width, change stroke pattern, change start/end arrow type, then copy/save.

---

### Task 5: Final Verification

**Files:**
- Verify modified Swift files and tests.

- [ ] **Step 1: Run focused tests**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug test
```

- [ ] **Step 2: Run build if tests are blocked**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug build
```

- [ ] **Step 3: Report exact result**

Report changed files, verification command output status, and any blocker such as signing, local Xcode configuration, or screen recording permission.
