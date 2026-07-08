# Eraser Tool Safe V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Ship the first macOS eraser tool as fast object deletion without changing renderer, export, or mosaic compositing architecture.

**Architecture:** Keep eraser state inside `SelectionOverlayWindow`. Add one active-tool boolean, one eraser interaction mode, object hit-testing from topmost annotation to bottommost, and a narrow annotation history that supports normal appended annotations plus arbitrary-index eraser deletes. Existing render/export paths continue to consume only `annotations`.

**Tech Stack:** Swift/AppKit, XCTest, existing xxsnap mac overlay test helpers.

---

## File Map

- Modify `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
  - Add `TestToolbarButton.eraser` debug access.
  - Add `InteractionMode.erasingAnnotation`.
  - Add `isEraserToolActive` and a small `AnnotationHistoryEntry`.
  - Replace `redoAnnotations` with redo history and record append/delete history.
  - Route toolbar eraser button to `toggleEraserTool()`.
  - Add eraser mouse-down handling before selection move/resize.
  - Add `eraserAnnotationIndex(at:)` using existing hit-test helpers.
  - Keep renderer/export/mosaic cache key code unchanged.
- Modify `platforms/mac/Tests/SelectionToolbarStateTests.swift`
  - Add focused tests for activation, deletion, empty-drag safety, undo/redo, topmost hit behavior, and mosaic cache behavior.

## Task 1: Add Failing Eraser Activation Test

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [x] **Step 1: Write the failing test**

Add `eraser` to `TestToolbarButton` and its debug mapping enough for tests to ask for the toolbar point. Then add this test near the existing toolbar activation tests:

```swift
func testOverlayWindowActivatesEraserToolWithoutOptionsToolbar() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 160))

    let point = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .eraser))
    window.test_mouseDown(at: point)
    window.test_mouseUp(at: point)

    XCTAssertTrue(window.test_isEraserToolActive)
    XCTAssertTrue(window.test_eraserToolbarButtonIsSelected)
    XCTAssertNil(window.test_optionsToolbarMode)
    XCTAssertFalse(window.test_isEyedropperToolActive)
    XCTAssertFalse(window.test_isTextToolActive)
    XCTAssertFalse(window.test_isNumberToolActive)
    XCTAssertFalse(window.test_isMagnifierToolActive)
    XCTAssertNil(window.test_currentShapeKind)
}
```

Expose these debug accessors:

```swift
func test_activateEraserTool() {
    activateEraserTool()
}

var test_isEraserToolActive: Bool {
    isEraserToolActive
}

var test_eraserToolbarButtonIsSelected: Bool {
    buttonMatchesCurrentTool(.eraser)
}
```

- [x] **Step 2: Run the focused test to verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testOverlayWindowActivatesEraserToolWithoutOptionsToolbar
```

Expected: FAIL because eraser activation/debug state does not exist yet or the eraser still opens the placeholder path.

- [x] **Step 3: Implement minimal activation**

In `SelectionOverlayWindow.swift`:

```swift
case eraser
```

Add to `TestToolbarButton`, add `.eraser` mapping in `test_mainToolbarButtonRect(for:)` and `test_symbolName(for:)`, add:

```swift
private var isEraserToolActive = false
```

Route toolbar selection:

```swift
case .eraser:
    return isEraserToolActive
```

Route toolbar action:

```swift
case .eraser:
    toggleEraserTool()
```

Add:

```swift
private func toggleEraserTool() {
    commitCurrentTextEdit()
    clearPendingTextEdit()
    closeTextDropdown()
    closeMagnifierZoomDropdown()
    if isEraserToolActive {
        isEraserToolActive = false
        selectedAnnotationIndex = nil
        invalidateCursorRectsAndRefresh()
        needsDisplay = true
        return
    }

    activateEraserTool()
}

private func activateEraserTool() {
    commitCurrentTextEdit()
    clearPendingTextEdit()
    closeTextDropdown()
    closeMagnifierZoomDropdown()
    rememberCurrentStyleForActiveTool()
    isEraserToolActive = true
    isShapeToolActive = false
    activeShapeKind = nil
    isTextToolActive = false
    isNumberToolActive = false
    isMagnifierToolActive = false
    isEyedropperToolActive = false
    activeNumberDropdown = false
    clearEyedropperMeasurement()
    selectedAnnotationIndex = nil
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

When activating any other tool, set `isEraserToolActive = false`.

- [x] **Step 4: Run the focused test to verify GREEN**

Run the same `xcodebuild ... -only-testing` command. Expected: PASS.

## Task 2: Add Failing Click-To-Delete Tests

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [x] **Step 1: Write failing tests**

Add tests near annotation selection/delete tests:

```swift
func testEraserClickDeletesRectangleAnnotation() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
    window.test_setLockedSelectionRect(selection)
    window.test_setAnnotations([
        CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 40, y: 50, width: 80, height: 60))
    ])
    window.test_activateEraserTool()

    window.test_mouseDown(at: NSPoint(x: selection.minX + 80, y: selection.minY + 80))
    window.test_mouseUp(at: NSPoint(x: selection.minX + 80, y: selection.minY + 80))

    XCTAssertEqual(window.test_annotationCount, 0)
    XCTAssertEqual(window.test_lockedSelectionRect, selection)
}

func testEraserClickDeletesTopmostAnnotationOnly() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
    window.test_setLockedSelectionRect(selection)
    window.test_setAnnotations([
        CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 40, y: 50, width: 90, height: 70)),
        CaptureAnnotation(kind: .ellipse, rect: NSRect(x: 50, y: 60, width: 90, height: 70))
    ])
    window.test_activateEraserTool()

    window.test_mouseDown(at: NSPoint(x: selection.minX + 80, y: selection.minY + 90))
    window.test_mouseUp(at: NSPoint(x: selection.minX + 80, y: selection.minY + 90))

    XCTAssertEqual(window.test_annotationCount, 1)
    XCTAssertEqual(window.test_annotation(at: 0)?.kind, .rectangle)
}
```

- [x] **Step 2: Run tests to verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testEraserClickDeletesRectangleAnnotation -only-testing:xxsnapTests/SelectionToolbarStateTests/testEraserClickDeletesTopmostAnnotationOnly
```

Expected: FAIL because eraser mode consumes no annotation clicks yet.

- [x] **Step 3: Implement eraser hit-test and delete**

Add:

```swift
case erasingAnnotation
```

Route it in `mouseDown`, `mouseDragged`, and `mouseUp` with the same inert drag behavior as `.placingNumberMark`.

Add:

```swift
private func handleEraserMouseDown(at point: NSPoint) -> Bool {
    guard isEraserToolActive, !isToolbarOrPanelPoint(point) else {
        return false
    }
    commitCurrentTextEdit()
    commitNumberEditingIfNeeded()
    if let index = eraserAnnotationIndex(at: point) {
        deleteAnnotation(at: index, source: .eraser)
    }
    interactionMode = .erasingAnnotation
    needsDisplay = true
    return true
}
```

Call this in `handleAnnotatingMouseDown(at:clickCount:)` immediately after toolbar/options handling and before selection resize/move or drawing logic.

Add `eraserAnnotationIndex(at:)`:

```swift
private func eraserAnnotationIndex(at point: NSPoint) -> Int? {
    for index in annotations.indices.reversed() {
        let annotation = annotations[index]
        switch annotation.kind {
        case .arrowLine:
            if arrowLineHitTarget(at: point)?.index == index {
                return index
            }
        case .brush:
            if let path = overlayBrushPath(fromLocalBrushPath: annotation.brushPath),
               brushPathContains(point, path: path, hitOutset: max(8, annotation.style.strokeWidth / 2 + 4)) {
                return index
            }
        case .marker:
            if let line = overlayMarkerLine(fromLocalMarkerLine: annotation.markerLine),
               SelectionToolbarState.markerLineContains(point: point, line: line, hitOutset: max(8, annotation.style.strokeWidth / 2 + 4)) {
                return index
            }
        case .mosaicStroke:
            if let stroke = overlayMosaicStroke(fromLocalMosaicStroke: annotation.mosaicStroke),
               mosaicStrokeContains(point, stroke: stroke, hitOutset: max(8, annotation.style.strokeWidth / 2 + 4)) {
                return index
            }
        case .mosaicRectangle, .magnifier, .text:
            if rotatedAnnotationRectContains(point, annotation: annotation, hitOutset: 6) {
                return index
            }
        case .numberSequence:
            if numberAnnotationIndex(at: point) == index {
                return index
            }
        case .rectangle, .ellipse:
            let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
            if SelectionToolbarState.shapeBorderContains(
                point: point,
                rect: rect,
                kind: annotation.kind,
                cornerRadius: annotation.style.cornerRadius
            ) || rect.insetBy(dx: -4, dy: -4).contains(point) {
                return index
            }
        }
    }
    return nil
}
```

Extract deletion:

```swift
private enum AnnotationDeletionSource {
    case selected
    case eraser
}

@discardableResult
private func deleteAnnotation(at deletionIndex: Int, source: AnnotationDeletionSource) -> Bool {
    guard annotations.indices.contains(deletionIndex) else {
        return false
    }
    let removed = annotations[deletionIndex]
    let shouldRenumberNumberSequence = removed.kind == .numberSequence && !isNumberSequenceManualModeActive()
    annotations.remove(at: deletionIndex)
    recordAnnotationDelete(removed, at: deletionIndex, renumberedNumbers: shouldRenumberNumberSequence)
    selectedAnnotationIndex = nil
    editingTextAnnotationIndex = nil
    clearNumberEditing()
    clearPendingTextEdit()
    removeTextEditor()
    showsStrokeStyleMenu = false
    showsCornerRadiusPanel = false
    showsStartArrowTypeMenu = false
    showsEndArrowTypeMenu = false
    if removed.kind == .numberSequence {
        if shouldRenumberNumberSequence {
            renumberNumberSequenceAnnotations()
        }
        revealedNumberControlsIndex = nil
        invalidateCursorRectsAndRefresh()
    }
    if removed.kind == .mosaicStroke || removed.kind == .mosaicRectangle {
        resetMosaicPreviewCaches()
    }
    needsDisplay = true
    return true
}
```

Update `deleteSelectedAnnotation()` to resolve the selected/revealed index and call `deleteAnnotation(at:source:)`.

- [x] **Step 4: Run tests to verify GREEN**

Run the same focused command. Expected: PASS.

## Task 3: Add Failing Empty Drag And Cache Safety Tests

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [x] **Step 1: Write failing tests**

Add:

```swift
func testEraserMissedDragDoesNotMoveSelectionOrCreateAnnotation() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
    window.test_setLockedSelectionRect(selection)
    window.test_activateEraserTool()

    let start = NSPoint(x: selection.midX, y: selection.midY)
    let end = NSPoint(x: start.x + 80, y: start.y + 40)
    window.test_mouseDown(at: start)
    window.test_mouseDragged(to: end)
    window.test_mouseUp(at: end)

    XCTAssertEqual(window.test_lockedSelectionRect, selection)
    XCTAssertEqual(window.test_annotationCount, 0)
    XCTAssertTrue(window.test_isEraserToolActive)
}

func testMissedEraserClickDoesNotResetMosaicPreviewCache() throws {
    let background = solidImage(size: NSSize(width: 420, height: 300), color: .white)
    let window = fixedCanvasOverlayWindow(backgroundImage: background, canvasSize: background.size)
    let selection = NSRect(x: 100, y: 100, width: 240, height: 160)
    let mosaic = CaptureAnnotation(
        kind: .mosaicRectangle,
        rect: NSRect(x: 30, y: 30, width: 80, height: 50),
        mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
    )
    window.test_setLockedSelectionRect(selection)
    window.test_setAnnotations([mosaic])
    _ = window.test_mosaicPreviewComposite(for: [mosaic])
    let rendersBefore = window.test_mosaicCompositeRenderCount
    window.test_activateEraserTool()

    let miss = NSPoint(x: selection.maxX - 10, y: selection.maxY - 10)
    window.test_mouseDown(at: miss)
    window.test_mouseDragged(to: NSPoint(x: miss.x - 30, y: miss.y - 20))
    window.test_mouseUp(at: NSPoint(x: miss.x - 30, y: miss.y - 20))

    _ = window.test_mosaicPreviewComposite(for: [mosaic])
    XCTAssertEqual(window.test_annotationCount, 1)
    XCTAssertEqual(window.test_lockedSelectionRect, selection)
    XCTAssertEqual(window.test_mosaicCompositeRenderCount, rendersBefore)
}
```

- [x] **Step 2: Run tests to verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testEraserMissedDragDoesNotMoveSelectionOrCreateAnnotation -only-testing:xxsnapTests/SelectionToolbarStateTests/testMissedEraserClickDoesNotResetMosaicPreviewCache
```

Expected: FAIL before eraser missed clicks are consumed.

- [x] **Step 3: Finish inert eraser gesture**

Ensure `mouseDragged` case `.erasingAnnotation` is `break`, and `mouseUp` case `.erasingAnnotation` resets `interactionMode = .annotating`. Do not call any mosaic reset method on misses.

- [x] **Step 4: Run tests to verify GREEN**

Run the same focused command. Expected: PASS.

## Task 4: Add Failing Undo/Redo Tests

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [x] **Step 1: Write failing tests**

Add:

```swift
func testEraserDeletionIsUndoableAndRedoableAtOriginalIndex() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
    let first = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 20, y: 20, width: 40, height: 40))
    let second = CaptureAnnotation(kind: .ellipse, rect: NSRect(x: 90, y: 30, width: 60, height: 50))
    window.test_setLockedSelectionRect(selection)
    window.test_setAnnotations([first, second])
    window.test_activateEraserTool()

    window.test_mouseDown(at: NSPoint(x: selection.minX + 120, y: selection.minY + 55))
    window.test_mouseUp(at: NSPoint(x: selection.minX + 120, y: selection.minY + 55))
    XCTAssertEqual(window.test_annotationCount, 1)

    window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
    XCTAssertEqual(window.test_annotationCount, 2)
    XCTAssertEqual(window.test_annotation(at: 0)?.kind, .rectangle)
    XCTAssertEqual(window.test_annotation(at: 1)?.kind, .ellipse)

    window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command, .shift])
    XCTAssertEqual(window.test_annotationCount, 1)
    XCTAssertEqual(window.test_annotation(at: 0)?.kind, .rectangle)
}

func testEraserDeleteThenNewAnnotationUndoUsesNewestActionFirst() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
    window.test_setLockedSelectionRect(selection)
    window.test_setAnnotations([
        CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 20, y: 20, width: 40, height: 40))
    ])
    window.test_activateEraserTool()
    window.test_mouseDown(at: NSPoint(x: selection.minX + 40, y: selection.minY + 40))
    window.test_mouseUp(at: NSPoint(x: selection.minX + 40, y: selection.minY + 40))

    window.test_activateShapeTool(.ellipse)
    window.test_drag(from: NSPoint(x: 180, y: 150), to: NSPoint(x: 230, y: 190))
    XCTAssertEqual(window.test_annotationCount, 1)
    XCTAssertEqual(window.test_annotation(at: 0)?.kind, .ellipse)

    window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
    XCTAssertEqual(window.test_annotationCount, 0)

    window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
    XCTAssertEqual(window.test_annotationCount, 1)
    XCTAssertEqual(window.test_annotation(at: 0)?.kind, .rectangle)
}
```

- [x] **Step 2: Run tests to verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testEraserDeletionIsUndoableAndRedoableAtOriginalIndex -only-testing:xxsnapTests/SelectionToolbarStateTests/testEraserDeleteThenNewAnnotationUndoUsesNewestActionFirst
```

Expected: FAIL until history records arbitrary-index deletes and appended annotations together.

- [x] **Step 3: Implement narrow annotation history**

Replace `redoAnnotations` with:

```swift
private enum AnnotationHistoryEntry {
    case append(CaptureAnnotation)
    case delete(annotation: CaptureAnnotation, index: Int, renumberedNumbers: Bool)
}

private var annotationUndoHistory: [AnnotationHistoryEntry] = []
private var annotationRedoHistory: [AnnotationHistoryEntry] = []
```

Add:

```swift
private func recordAnnotationAppend(_ annotation: CaptureAnnotation) {
    annotationUndoHistory.append(.append(annotation))
    annotationRedoHistory.removeAll()
}

private func recordAnnotationDelete(_ annotation: CaptureAnnotation, at index: Int, renumberedNumbers: Bool) {
    annotationUndoHistory.append(.delete(annotation: annotation, index: index, renumberedNumbers: renumberedNumbers))
    annotationRedoHistory.removeAll()
}

private func clearAnnotationRedoHistory() {
    annotationRedoHistory.removeAll()
}
```

Update new annotation creation sites to call `recordAnnotationAppend(annotation)` or `recordAnnotationAppend(draft)` after appending:

- shape/magnifier/mosaic draft in `mouseUp`
- number mark in `createNumberMark(at:)`
- text draft in `handleTextToolMouseDown(at:selectionRect:)`

Update existing `redoAnnotations.removeAll()` callers to `clearAnnotationRedoHistory()`.

Implement:

```swift
private func undoLastAnnotation() {
    guard let action = annotationUndoHistory.popLast() else {
        return
    }
    switch action {
    case .append(let annotation):
        if let index = annotations.indices.reversed().first(where: { annotations[$0] == annotation }) {
            let removed = annotations.remove(at: index)
            selectedAnnotationIndex = annotations.indices.last
            annotationRedoHistory.append(.append(removed))
            if removed.kind == .mosaicStroke || removed.kind == .mosaicRectangle {
                resetMosaicPreviewCaches()
            }
        }
    case let .delete(annotation, index, renumberedNumbers):
        let restoreIndex = min(max(0, index), annotations.count)
        annotations.insert(annotation, at: restoreIndex)
        selectedAnnotationIndex = restoreIndex
        annotationRedoHistory.append(action)
        if annotation.kind == .numberSequence, renumberedNumbers {
            renumberNumberSequenceAnnotations()
        }
        if annotation.kind == .mosaicStroke || annotation.kind == .mosaicRectangle {
            resetMosaicPreviewCaches()
        }
    }
    needsDisplay = true
}

private func redoLastAnnotation() {
    guard let action = annotationRedoHistory.popLast() else {
        return
    }
    switch action {
    case .append(let annotation):
        annotations.append(annotation)
        selectedAnnotationIndex = annotations.indices.last
        annotationUndoHistory.append(action)
        if annotation.kind == .mosaicStroke || annotation.kind == .mosaicRectangle {
            resetMosaicPreviewCaches()
        }
    case let .delete(annotation, index, renumberedNumbers):
        let deletionIndex = annotations.indices.first(where: { annotations[$0] == annotation }) ?? (annotations.indices.contains(index) ? index : nil)
        guard let deletionIndex else {
            annotationRedoHistory.append(action)
            return
        }
        let removed = annotations.remove(at: deletionIndex)
        selectedAnnotationIndex = nil
        annotationUndoHistory.append(.delete(annotation: removed, index: deletionIndex, renumberedNumbers: renumberedNumbers))
        if removed.kind == .numberSequence, renumberedNumbers {
            renumberNumberSequenceAnnotations()
        }
        if removed.kind == .mosaicStroke || removed.kind == .mosaicRectangle {
            resetMosaicPreviewCaches()
        }
    }
    needsDisplay = true
}
```

Update toolbar enablement:

```swift
case .undo:
    return !annotationUndoHistory.isEmpty
case .redo:
    return !annotationRedoHistory.isEmpty
```

Update `test_setAnnotations(_:)` to clear both histories. Tests that seed annotations then expect undo must exercise deletion-generated history, not seeded initial data.

- [x] **Step 4: Run tests to verify GREEN**

Run the same focused command. Expected: PASS.

## Task 5: Add Representative Annotation Type Tests

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [x] **Step 1: Write tests for non-rectangle annotation kinds**

Add table-style tests:

```swift
func testEraserDeletesRepresentativeAnnotationKinds() throws {
    let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
    let cases: [(name: String, annotation: CaptureAnnotation, hit: NSPoint)] = [
        (
            "text",
            CaptureAnnotation(kind: .text, rect: NSRect(x: 30, y: 30, width: 80, height: 28), text: "hello"),
            NSPoint(x: selection.minX + 55, y: selection.minY + 44)
        ),
        (
            "number",
            CaptureAnnotation(kind: .numberSequence, rect: NSRect(x: 60, y: 50, width: 24, height: 24), numberMarkType: .number, numberSequenceIndex: 1),
            NSPoint(x: selection.minX + 72, y: selection.minY + 62)
        ),
        (
            "magnifier",
            CaptureAnnotation(kind: .magnifier, rect: NSRect(x: 90, y: 50, width: 70, height: 60)),
            NSPoint(x: selection.minX + 125, y: selection.minY + 80)
        ),
        (
            "mosaic rectangle",
            CaptureAnnotation(kind: .mosaicRectangle, rect: NSRect(x: 120, y: 70, width: 80, height: 60), mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)),
            NSPoint(x: selection.minX + 160, y: selection.minY + 100)
        ),
        (
            "mosaic stroke",
            CaptureAnnotation(
                kind: .mosaicStroke,
                rect: NSRect(x: 20, y: 90, width: 100, height: 30),
                style: {
                    var style = CaptureAnnotationStyle()
                    style.strokeWidth = 20
                    return style
                }(),
                mosaicStroke: CaptureMosaicStroke(points: [NSPoint(x: 20, y: 90), NSPoint(x: 120, y: 120)]),
                mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
            ),
            NSPoint(x: selection.minX + 70, y: selection.minY + 105)
        )
    ]

    for item in cases {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([item.annotation])
        window.test_activateEraserTool()

        window.test_mouseDown(at: item.hit)
        window.test_mouseUp(at: item.hit)

        XCTAssertEqual(window.test_annotationCount, 0, item.name)
    }
}
```

- [x] **Step 2: Run tests to verify RED or GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testEraserDeletesRepresentativeAnnotationKinds
```

Expected: PASS if Task 2 hit-testing covered every representative kind; otherwise FAIL and fix the missing hit case.

## Task 6: Regression Verification And Commit

**Files:**
- Modify: `docs/superpowers/plans/2026-07-08-eraser-tool-safe.md` checkbox statuses as tasks complete.

- [x] **Step 1: Verify no forbidden architecture changes**

Run:

```bash
git diff -- platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift core platforms/mac/Sources/Bridge
rg -n "renderOrder|eraserMasks|render\\(image:annotations:eraserMasks" platforms/mac/Sources core
```

Expected: no diffs in renderer/core/bridge and no forbidden symbols except in docs.

- [x] **Step 2: Run focused eraser regression set**

Run all eraser tests added in this plan:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testOverlayWindowActivatesEraserToolWithoutOptionsToolbar -only-testing:xxsnapTests/SelectionToolbarStateTests/testEraserClickDeletesRectangleAnnotation -only-testing:xxsnapTests/SelectionToolbarStateTests/testEraserClickDeletesTopmostAnnotationOnly -only-testing:xxsnapTests/SelectionToolbarStateTests/testEraserMissedDragDoesNotMoveSelectionOrCreateAnnotation -only-testing:xxsnapTests/SelectionToolbarStateTests/testMissedEraserClickDoesNotResetMosaicPreviewCache -only-testing:xxsnapTests/SelectionToolbarStateTests/testEraserDeletionIsUndoableAndRedoableAtOriginalIndex -only-testing:xxsnapTests/SelectionToolbarStateTests/testEraserDeleteThenNewAnnotationUndoUsesNewestActionFirst -only-testing:xxsnapTests/SelectionToolbarStateTests/testEraserDeletesRepresentativeAnnotationKinds
```

Expected: PASS.

- [x] **Step 3: Run nearby regression subset**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testOverlayWindowActivatesMosaicTool -only-testing:xxsnapTests/SelectionToolbarStateTests/testDraggingInsideSelectionWithTextToolDoesNotMoveSelectionRegion -only-testing:xxsnapTests/SelectionToolbarStateTests/testNumberCreationDragDoesNotMoveSelectionOrNewMark -only-testing:xxsnapTests/SelectionToolbarStateTests/testMainToolbarIconInsetsMatchRequestedPreviewSizes
```

Expected: PASS.

- [x] **Step 4: Build or run full mac tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Expected: PASS or the previously observed unrelated magnifier renderer pixel failures only. If the same known magnifier failures persist, report them separately with exact test names.

- [x] **Step 5: Commit only this feature work**

Run:

```bash
git status --short
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift docs/superpowers/plans/2026-07-08-eraser-tool-safe.md
git commit -m "feat(mac): add safe eraser object deletion"
```

Expected: commit includes only the implementation, tests, and this plan. Do not stage `.codex/` or `docs/superpowers/plans/2026-07-06-eraser-tool.md`.

## Self-Review

- Spec coverage: activation, object deletion, missed-click drag safety, undo/redo, representative annotation deletion, mosaic cache miss safety, and renderer/export non-changes are each covered by tasks.
- Placeholder scan: no `TBD`, `TODO`, or implementation-later steps are present.
- Type consistency: `isEraserToolActive`, `AnnotationHistoryEntry`, `annotationUndoHistory`, `annotationRedoHistory`, `erasingAnnotation`, and `eraserAnnotationIndex(at:)` are consistently named across tasks.
