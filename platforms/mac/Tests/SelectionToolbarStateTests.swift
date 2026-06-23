import AppKit
import XCTest
@testable import Snipory

final class SelectionToolbarStateTests: XCTestCase {
    func testOverlayWindowEscCancelsBeforeSelectionIsLocked() {
        let didCancel = expectation(description: "selection cancelled")
        let window = SelectionOverlayWindow(backgroundImage: nil) { result in
            XCTAssertNil(result)
            didCancel.fulfill()
        }
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        )!

        window.keyDown(with: event)

        wait(for: [didCancel], timeout: 0.5)
    }

    func testOverlayWindowResizesSelectionFromBorderWhileBrushToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: selection.maxX + 10, y: selection.midY))
        window.test_mouseDragged(to: NSPoint(x: selection.maxX + 40, y: selection.midY))
        window.test_mouseUp(at: NSPoint(x: selection.maxX + 40, y: selection.midY))

        XCTAssertEqual(window.test_lockedSelectionRect?.origin.x, selection.origin.x)
        XCTAssertEqual(window.test_lockedSelectionRect?.width, selection.width + 40)
    }

    func testOverlayWindowUsesArrowOutsideSelectionWhileShapeToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.rectangle)

        guard let toolbarPoint = window.test_mainToolbarDragPoint() else {
            return XCTFail("Expected toolbar drag point")
        }
        XCTAssertFalse(selection.contains(toolbarPoint))
        XCTAssertEqual(window.test_cursorStyle(at: toolbarPoint), .arrow)

        window.test_activateShapeTool(.arrowLine)
        XCTAssertEqual(window.test_cursorStyle(at: toolbarPoint), .arrow)
    }

    func testOverlayWindowUsesDrawingCursorInsideSelectionImmediatelyAfterToolSwitch() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let point = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        window.test_activateShapeTool(.rectangle)
        XCTAssertEqual(window.test_cursorStyle(at: point), .crosshair)

        window.test_activateShapeTool(.arrowLine)
        XCTAssertEqual(window.test_cursorStyle(at: point), .crosshair)
    }

    func testToolSwitchingResetsStrokePatternToFirstOption() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 160))

        window.test_setCurrentStrokePattern(.dashLong)
        window.test_toggleShapeTool(.rectangle)
        XCTAssertEqual(window.test_currentStrokePattern, .solid)

        window.test_setCurrentStrokePattern(.dashNarrow)
        window.test_toggleShapeTool(.arrowLine)
        XCTAssertEqual(window.test_currentStrokePattern, .solid)

        window.test_setCurrentStrokePattern(.dashLongShort)
        window.test_toggleShapeTool(.brush)
        XCTAssertEqual(window.test_currentStrokePattern, .solid)

        window.test_setCurrentStrokePattern(.dashLong)
        window.test_toggleShapeTool(.rectangle)
        XCTAssertEqual(window.test_currentStrokePattern, .solid)
    }

    func testOverlayWindowMovesSelectedBrushGeometryWithoutChangingStyle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 180, y: 180))
        window.test_mouseUp(at: NSPoint(x: 180, y: 180))

        guard let original = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected brush annotation")
        }

        window.test_mouseDown(at: NSPoint(x: 160, y: 160))
        window.test_mouseDragged(to: NSPoint(x: 190, y: 190))
        window.test_mouseUp(at: NSPoint(x: 190, y: 190))

        guard let moved = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected moved brush annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(moved.origin.x, original.origin.x + 30, accuracy: 0.1)
        XCTAssertEqual(moved.origin.y, original.origin.y + 30, accuracy: 0.1)
        XCTAssertEqual(moved.width, original.width, accuracy: 0.1)
        XCTAssertEqual(moved.height, original.height, accuracy: 0.1)
    }

    func testOverlayWindowKeepsMoveCursorWhileDraggingRectangleArrowAndBrush() {
        let rectangleWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        rectangleWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        rectangleWindow.test_activateShapeTool(.rectangle)
        rectangleWindow.test_mouseDown(at: NSPoint(x: 140, y: 140))
        rectangleWindow.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        rectangleWindow.test_mouseUp(at: NSPoint(x: 220, y: 180))
        rectangleWindow.test_mouseDown(at: NSPoint(x: 160, y: 140))
        rectangleWindow.test_mouseDragged(to: NSPoint(x: 170, y: 150))
        XCTAssertEqual(rectangleWindow.test_cursorStyle(at: NSPoint(x: 170, y: 150)), .move)
        rectangleWindow.test_mouseUp(at: NSPoint(x: 170, y: 150))

        let arrowWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        arrowWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        arrowWindow.test_activateShapeTool(.arrowLine)
        arrowWindow.test_mouseDown(at: NSPoint(x: 160, y: 160))
        arrowWindow.test_mouseDragged(to: NSPoint(x: 240, y: 200))
        arrowWindow.test_mouseUp(at: NSPoint(x: 240, y: 200))
        arrowWindow.test_mouseDown(at: NSPoint(x: 190, y: 175))
        arrowWindow.test_mouseDragged(to: NSPoint(x: 200, y: 185))
        XCTAssertEqual(arrowWindow.test_cursorStyle(at: NSPoint(x: 200, y: 185)), .move)
        arrowWindow.test_mouseUp(at: NSPoint(x: 200, y: 185))

        let brushWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        brushWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        brushWindow.test_activateShapeTool(.brush)
        brushWindow.test_mouseDown(at: NSPoint(x: 170, y: 170))
        brushWindow.test_mouseDragged(to: NSPoint(x: 210, y: 210))
        brushWindow.test_mouseUp(at: NSPoint(x: 210, y: 210))
        brushWindow.test_mouseDown(at: NSPoint(x: 190, y: 190))
        brushWindow.test_mouseDragged(to: NSPoint(x: 200, y: 200))
        XCTAssertEqual(brushWindow.test_cursorStyle(at: NSPoint(x: 200, y: 200)), .move)
        brushWindow.test_mouseUp(at: NSPoint(x: 200, y: 200))
    }

    func testOverlayWindowMovesBrushAnnotationWhileRectangleToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 190, y: 190))
        window.test_mouseUp(at: NSPoint(x: 190, y: 190))

        guard let original = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected brush annotation")
        }

        window.test_activateShapeTool(.rectangle)
        window.test_mouseDown(at: NSPoint(x: 170, y: 170))
        window.test_mouseDragged(to: NSPoint(x: 200, y: 200))
        window.test_mouseUp(at: NSPoint(x: 200, y: 200))

        guard let moved = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected moved brush annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .brush)
        XCTAssertEqual(moved.origin.x, original.origin.x + 30, accuracy: 0.1)
        XCTAssertEqual(moved.origin.y, original.origin.y + 30, accuracy: 0.1)
    }

    func testOverlayWindowDragsSelectedArrowControlPoint() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        let control = NSPoint(x: 100 + original.control.x, y: 100 + original.control.y)

        window.test_mouseDown(at: control)
        window.test_mouseDragged(to: NSPoint(x: control.x, y: control.y + 50))
        window.test_mouseUp(at: NSPoint(x: control.x, y: control.y + 50))

        guard let updated = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected updated arrow annotation")
        }
        XCTAssertEqual(updated.control.x, original.control.x, accuracy: 0.1)
        XCTAssertEqual(updated.control.y, original.control.y + 50, accuracy: 0.1)
    }

    func testOverlayWindowSelectedArrowShowsControlHandles() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        XCTAssertEqual(window.test_selectedAnnotationKind, .arrowLine)
        XCTAssertTrue(window.test_selectedAnnotationShowsOutline)
    }

    func testOverlayWindowDeleteKeyRemovesSelectedAnnotations() {
        let rectangleWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        rectangleWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        rectangleWindow.test_activateShapeTool(.rectangle)
        rectangleWindow.test_mouseDown(at: NSPoint(x: 140, y: 140))
        rectangleWindow.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        rectangleWindow.test_mouseUp(at: NSPoint(x: 220, y: 180))
        rectangleWindow.test_mouseDown(at: NSPoint(x: 160, y: 140))
        rectangleWindow.test_mouseUp(at: NSPoint(x: 160, y: 140))
        XCTAssertEqual(rectangleWindow.test_selectedAnnotationKind, .rectangle)
        rectangleWindow.test_keyDown(keyCode: 51)
        XCTAssertEqual(rectangleWindow.test_annotationCount, 0)
        XCTAssertNil(rectangleWindow.test_selectedAnnotationKind)

        let ellipseWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        ellipseWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        ellipseWindow.test_activateShapeTool(.ellipse)
        ellipseWindow.test_mouseDown(at: NSPoint(x: 140, y: 140))
        ellipseWindow.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        ellipseWindow.test_mouseUp(at: NSPoint(x: 220, y: 180))
        ellipseWindow.test_mouseDown(at: NSPoint(x: 160, y: 140))
        ellipseWindow.test_mouseUp(at: NSPoint(x: 160, y: 140))
        XCTAssertEqual(ellipseWindow.test_selectedAnnotationKind, .ellipse)
        ellipseWindow.test_keyDown(keyCode: 51)
        XCTAssertEqual(ellipseWindow.test_annotationCount, 0)
        XCTAssertNil(ellipseWindow.test_selectedAnnotationKind)

        let arrowWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        arrowWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        arrowWindow.test_activateShapeTool(.arrowLine)
        arrowWindow.test_mouseDown(at: NSPoint(x: 140, y: 140))
        arrowWindow.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        arrowWindow.test_mouseUp(at: NSPoint(x: 220, y: 180))
        arrowWindow.test_mouseDown(at: NSPoint(x: 180, y: 160))
        arrowWindow.test_mouseUp(at: NSPoint(x: 180, y: 160))
        XCTAssertEqual(arrowWindow.test_selectedAnnotationKind, .arrowLine)
        arrowWindow.test_keyDown(keyCode: 51)
        XCTAssertEqual(arrowWindow.test_annotationCount, 0)
        XCTAssertNil(arrowWindow.test_selectedAnnotationKind)

        let brushWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        brushWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        brushWindow.test_activateShapeTool(.brush)
        brushWindow.test_mouseDown(at: NSPoint(x: 150, y: 150))
        brushWindow.test_mouseDragged(to: NSPoint(x: 190, y: 190))
        brushWindow.test_mouseUp(at: NSPoint(x: 190, y: 190))
        brushWindow.test_mouseDown(at: NSPoint(x: 170, y: 170))
        brushWindow.test_mouseUp(at: NSPoint(x: 170, y: 170))
        XCTAssertEqual(brushWindow.test_selectedAnnotationKind, .brush)
        brushWindow.test_keyDown(keyCode: 51)
        XCTAssertEqual(brushWindow.test_annotationCount, 0)
        XCTAssertNil(brushWindow.test_selectedAnnotationKind)
    }

    func testOverlayWindowSelectedBrushShowsOnlyInsetEndpointMarkers() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 170, y: 180))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 190))
        window.test_mouseUp(at: NSPoint(x: 240, y: 170))
        window.test_mouseDown(at: NSPoint(x: 170, y: 180))
        window.test_mouseUp(at: NSPoint(x: 170, y: 180))

        let markers = window.test_selectedBrushEndpointMarkers
        XCTAssertEqual(markers.count, 2)
        XCTAssertEqual(markers[0].x, 157.8, accuracy: 0.1)
        XCTAssertEqual(markers[0].y, 161.6, accuracy: 0.1)
        XCTAssertEqual(markers[1].x, 228.4, accuracy: 0.1)
        XCTAssertEqual(markers[1].y, 177.8, accuracy: 0.1)
    }

    func testOverlayWindowShiftDoesNotChangeStraightArrowEndpointDrag() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        let end = NSPoint(x: 100 + original.end.x, y: 100 + original.end.y)
        window.test_mouseDown(at: end)
        window.test_mouseDragged(to: NSPoint(x: end.x + 30, y: end.y + 40), modifierFlags: [.shift])
        window.test_mouseUp(at: NSPoint(x: end.x + 30, y: end.y + 40), modifierFlags: [.shift])

        guard let updated = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected updated arrow annotation")
        }
        XCTAssertEqual(updated.end.x, original.end.x + 30, accuracy: 0.1)
        XCTAssertEqual(updated.end.y, original.end.y + 40, accuracy: 0.1)
        XCTAssertEqual(updated.control.x, (updated.start.x + updated.end.x) / 2, accuracy: 0.1)
        XCTAssertEqual(updated.control.y, (updated.start.y + updated.end.y) / 2, accuracy: 0.1)
    }

    func testOverlayWindowShiftDoesNotChangeCurvedArrowEndpointDrag() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        let control = NSPoint(x: 100 + original.control.x, y: 100 + original.control.y)
        window.test_mouseDown(at: control)
        window.test_mouseDragged(to: NSPoint(x: control.x, y: control.y + 50))
        window.test_mouseUp(at: NSPoint(x: control.x, y: control.y + 50))

        guard let curved = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected curved arrow annotation")
        }
        let end = NSPoint(x: 100 + curved.end.x, y: 100 + curved.end.y)
        window.test_mouseDown(at: end)
        window.test_mouseDragged(to: NSPoint(x: end.x + 30, y: end.y + 40), modifierFlags: [.shift])
        window.test_mouseUp(at: NSPoint(x: end.x + 30, y: end.y + 40), modifierFlags: [.shift])

        guard let updated = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected updated arrow annotation")
        }
        XCTAssertEqual(updated.end.x, curved.end.x + 30, accuracy: 0.1)
        XCTAssertEqual(updated.end.y, curved.end.y + 40, accuracy: 0.1)
        let curvedMidpoint = NSPoint(x: (curved.start.x + curved.end.x) / 2, y: (curved.start.y + curved.end.y) / 2)
        let updatedMidpoint = NSPoint(x: (updated.start.x + updated.end.x) / 2, y: (updated.start.y + updated.end.y) / 2)
        XCTAssertEqual(updated.control.x - updatedMidpoint.x, curved.control.x - curvedMidpoint.x, accuracy: 0.1)
        XCTAssertEqual(updated.control.y - updatedMidpoint.y, curved.control.y - curvedMidpoint.y, accuracy: 0.1)
    }

    func testOverlayWindowArrowEndpointUsesVerticalResizeCursor() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let arrowLine = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }

        let start = NSPoint(x: 100 + arrowLine.start.x, y: 100 + arrowLine.start.y)
        let end = NSPoint(x: 100 + arrowLine.end.x, y: 100 + arrowLine.end.y)
        XCTAssertEqual(window.test_cursorStyle(at: start), .resizeUpDown)
        XCTAssertEqual(window.test_cursorStyle(at: end), .resizeUpDown)
    }

    func testOverlayWindowBrushEndpointUsesVerticalArrowsCursor() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 180, y: 180))
        window.test_mouseUp(at: NSPoint(x: 180, y: 180))

        let path = CaptureBrushPath(points: [NSPoint(x: 140, y: 140), NSPoint(x: 180, y: 180)])
        let startHandle = SelectionToolbarState.brushRotationHandlePoint(for: .start, path: path)!
        let endHandle = SelectionToolbarState.brushRotationHandlePoint(for: .end, path: path)!

        XCTAssertEqual(window.test_cursorStyle(at: startHandle), .rotationHandle)
        XCTAssertEqual(window.test_cursorStyle(at: endHandle), .rotationHandle)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 140, y: 140)), .brush)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 180, y: 180)), .brush)
    }

    func testOverlayWindowDraggingBrushEndpointAnchorsOppositeEndAndKeepsVerticalArrowsCursor() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 180, y: 180))
        window.test_mouseUp(at: NSPoint(x: 180, y: 180))

        guard let original = window.test_brushPath(at: 0) else {
            return XCTFail("Expected brush annotation")
        }
        XCTAssertGreaterThanOrEqual(original.points.count, 2)

        let overlayPath = CaptureBrushPath(points: original.points.map { NSPoint(x: $0.x + 100, y: $0.y + 100) })
        let endHandle = SelectionToolbarState.brushRotationHandlePoint(for: .end, path: overlayPath)!

        window.test_mouseDown(at: endHandle)
        window.test_mouseDragged(to: NSPoint(x: 210, y: 220))
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 210, y: 220)), .rotationHandle)
        window.test_mouseUp(at: NSPoint(x: 210, y: 220))

        guard let updated = window.test_brushPath(at: 0) else {
            return XCTFail("Expected updated brush annotation")
        }
        XCTAssertEqual(updated.points.count, original.points.count)
        XCTAssertEqual(updated.points.first!.x, original.points.first!.x, accuracy: 0.1)
        XCTAssertEqual(updated.points.first!.y, original.points.first!.y, accuracy: 0.1)
        XCTAssertEqual(updated.points.last!.x, 110, accuracy: 0.1)
        XCTAssertEqual(updated.points.last!.y, 120, accuracy: 0.1)
    }

    func testOverlayWindowBrushShiftDragDrawsStraightLineAtAnyAngle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 170, y: 146), modifierFlags: [.shift])
        window.test_mouseDragged(to: NSPoint(x: 210, y: 132), modifierFlags: [.shift])
        window.test_mouseUp(at: NSPoint(x: 240, y: 151), modifierFlags: [.shift])

        guard let path = window.test_brushPath(at: 0) else {
            return XCTFail("Expected brush annotation")
        }

        XCTAssertEqual(path.points.count, 2)
        XCTAssertEqual(path.points[0].x, 40, accuracy: 0.1)
        XCTAssertEqual(path.points[0].y, 40, accuracy: 0.1)
        XCTAssertEqual(path.points[1].x, 140, accuracy: 0.1)
        XCTAssertEqual(path.points[1].y, 51, accuracy: 0.1)
    }

    func testOverlayWindowBrushToolMovesWholeArrowFromControlPointWithoutReshaping() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        let control = NSPoint(x: 100 + original.control.x, y: 100 + original.control.y)

        window.test_activateShapeTool(.brush)
        XCTAssertNil(window.test_selectedAnnotationKind)
        XCTAssertEqual(window.test_cursorStyle(at: control), .move)

        window.test_mouseDown(at: control)
        window.test_mouseDragged(to: NSPoint(x: control.x, y: control.y + 50))
        window.test_mouseUp(at: NSPoint(x: control.x, y: control.y + 50))

        guard let updated = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .arrowLine)
        XCTAssertEqual(updated.start.x, original.start.x, accuracy: 0.1)
        XCTAssertEqual(updated.start.y, original.start.y + 50, accuracy: 0.1)
        XCTAssertEqual(updated.end.x, original.end.x, accuracy: 0.1)
        XCTAssertEqual(updated.end.y, original.end.y + 50, accuracy: 0.1)
        XCTAssertEqual(updated.control.x, original.control.x, accuracy: 0.1)
        XCTAssertEqual(updated.control.y, original.control.y + 50, accuracy: 0.1)
    }

    func testOverlayWindowMovesArrowLineBodyWhileBrushToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        let body = NSPoint(x: 100 + original.boundingRect.midX, y: 100 + original.boundingRect.midY)

        window.test_activateShapeTool(.brush)
        window.test_mouseDown(at: body)
        window.test_mouseDragged(to: NSPoint(x: body.x + 24, y: body.y + 18))
        window.test_mouseUp(at: NSPoint(x: body.x + 24, y: body.y + 18))

        guard let moved = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected moved arrow annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .arrowLine)
        XCTAssertEqual(moved.start.x, original.start.x + 24, accuracy: 0.1)
        XCTAssertEqual(moved.start.y, original.start.y + 18, accuracy: 0.1)
        XCTAssertEqual(moved.end.x, original.end.x + 24, accuracy: 0.1)
        XCTAssertEqual(moved.end.y, original.end.y + 18, accuracy: 0.1)
        XCTAssertEqual(moved.control.x, original.control.x + 24, accuracy: 0.1)
        XCTAssertEqual(moved.control.y, original.control.y + 18, accuracy: 0.1)
    }

    func testOverlayWindowArrowControlPointWinsOverSelectionResizeHandle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        let initialControl = NSPoint(x: selection.minX + original.control.x, y: selection.minY + original.control.y)
        let edgeControl = NSPoint(x: selection.maxX - 4, y: initialControl.y)
        window.test_mouseDown(at: initialControl)
        window.test_mouseDragged(to: edgeControl)
        window.test_mouseUp(at: edgeControl)

        window.test_mouseDown(at: edgeControl)
        window.test_mouseDragged(to: NSPoint(x: edgeControl.x - 40, y: edgeControl.y + 40))
        window.test_mouseUp(at: NSPoint(x: edgeControl.x - 40, y: edgeControl.y + 40))

        guard let updated = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected updated arrow annotation")
        }
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
        XCTAssertEqual(updated.control.x, edgeControl.x - selection.minX - 40, accuracy: 0.1)
        XCTAssertEqual(updated.control.y, edgeControl.y - selection.minY + 40, accuracy: 0.1)
    }

    func testOverlayWindowUsesBrushCursorAtSelectedBrushBoundsInsteadOfResizeHandle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 180, y: 180))
        window.test_mouseUp(at: NSPoint(x: 180, y: 180))

        guard let original = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected brush annotation")
        }

        let formerBottomRightHandle = NSPoint(x: 100 + original.maxX - 1, y: 100 + original.minY)
        XCTAssertEqual(window.test_cursorStyle(at: formerBottomRightHandle), .brush)
    }

    func testDefaultCaptureFilenameIncludesTimestampToSecond() {
        let date = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(
            CaptureCoordinator.defaultCaptureFilename(date: date, timeZone: TimeZone(secondsFromGMT: 0)!),
            "Snipory 截图 19700101-000000.png"
        )
    }

    func testOptionsToolbarOnlyShownForRectangleTool() {
        XCTAssertTrue(SelectionToolbarState.shouldShowOptionsToolbar(isPrimaryShapeToolActive: true))
        XCTAssertFalse(SelectionToolbarState.shouldShowOptionsToolbar(isPrimaryShapeToolActive: false))
    }

    func testToolbarIconInsetsRenderArrowLineLargerThanDefaultIcons() {
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "arrow-line"), 0)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "pencil-tool"), 2)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "text-tool"), 0)
    }

    func testCurrentColorToolbarIconsUseTemplateTint() {
        XCTAssertFalse(SelectionToolbarState.usesFixedColorToolbarIconResource("pencil-tool"))
        XCTAssertFalse(SelectionToolbarState.usesFixedColorToolbarIconResource("arrow-line"))
        XCTAssertTrue(SelectionToolbarState.usesFixedColorToolbarIconResource("mosaic-tool"))
        XCTAssertTrue(SelectionToolbarState.usesFixedColorToolbarIconResource("undo-enabled"))
    }

    func testPolylineTooltipUsesArrowLineLabel() {
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "polyline"), "箭头线")
    }

    func testArrowTypeTooltipTitlesOmitTypeSuffix() {
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "startArrowType"), "开始箭头")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "endArrowType"), "结束箭头")
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

    func testArrowOptionsToolbarWidthShrinksWhenShapeOnlyControlsAreHidden() {
        XCTAssertLessThan(
            SelectionToolbarState.optionsToolbarWidth(paletteCount: 8, mode: .arrowLine),
            SelectionToolbarState.optionsToolbarWidth(paletteCount: 8, mode: .shape)
        )
    }

    func testArrowOptionsToolbarCompactsFieldsAfterStrokeWidths() {
        let optionsRect = NSRect(x: 100, y: 100, width: 480, height: 40)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .arrowLine
        )

        XCTAssertLessThanOrEqual(layout.strokeStyle.minX - layout.strokeWidths.last!.maxX, 22)
        XCTAssertEqual(layout.startArrowType?.width, 42)
        XCTAssertEqual(layout.endArrowType?.width, 42)
        XCTAssertLessThan(layout.endArrowType!.maxX, layout.colorSwatches.first!.minX)
    }

    func testArrowOptionsToolbarLeavesSeparatorSpacingAroundArrowTypeFields() {
        let optionsRect = NSRect(x: 100, y: 100, width: 480, height: 40)
        let arrowLayout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .arrowLine
        )
        let shapeLayout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .shape
        )

        let strokeWidthToStyleGap = arrowLayout.strokeStyle.minX - arrowLayout.strokeWidths.last!.maxX
        XCTAssertGreaterThanOrEqual(arrowLayout.startArrowType!.minX - arrowLayout.strokeStyle.maxX, strokeWidthToStyleGap)

        let shapeSeparatorX = shapeLayout.strokeStyle.maxX + (shapeLayout.colorSwatches.first!.minX - shapeLayout.strokeStyle.maxX) / 2
        let arrowSeparatorX = arrowLayout.endArrowType!.maxX + (arrowLayout.colorSwatches.first!.minX - arrowLayout.endArrowType!.maxX) / 2
        let separatorWidth: CGFloat = 1.5
        let selectedSwatchExpansion: CGFloat = 3
        let shapeSeparatorToSelectedSwatchGap = shapeLayout.colorSwatches.first!.minX - selectedSwatchExpansion - (floor(shapeSeparatorX) + 0.25 + separatorWidth)
        let arrowSeparatorToSelectedSwatchGap = arrowLayout.colorSwatches.first!.minX - selectedSwatchExpansion - (floor(arrowSeparatorX) + 0.25 + separatorWidth)

        XCTAssertEqual(arrowSeparatorToSelectedSwatchGap, shapeSeparatorToSelectedSwatchGap, accuracy: 0.5)
    }

    func testArrowTypeFieldsAndMenuUseConsistentSampleWidth() {
        let optionsRect = NSRect(x: 100, y: 100, width: 480, height: 40)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .arrowLine
        )
        let menu = NSRect(x: 120, y: 80, width: 58, height: CGFloat(CaptureArrowType.allCases.count) * 24 + 8)
        let item = SelectionToolbarState.arrowTypeMenuItemRects(in: menu, itemCount: CaptureArrowType.allCases.count)[4]

        let fieldSample = SelectionToolbarState.arrowTypeSampleRect(in: layout.endArrowType!, pointsRight: true)
        let fieldDisclosure = SelectionToolbarState.arrowTypeDisclosureRect(in: layout.endArrowType!)
        let menuSample = SelectionToolbarState.arrowTypeSampleRect(in: item.insetBy(dx: 8, dy: 4), pointsRight: true)

        XCTAssertEqual(fieldSample.width, 22)
        XCTAssertEqual(menuSample.width, fieldSample.width)
        XCTAssertGreaterThanOrEqual(fieldDisclosure.minX - fieldSample.maxX, 3)
        XCTAssertLessThanOrEqual(fieldDisclosure.maxX, layout.endArrowType!.maxX - 3)
    }

    func testArrowTypeMenuHitTargetSelectsEveryMenuItem() {
        let itemCount = CaptureArrowType.allCases.count
        let menu = NSRect(x: 120, y: 80, width: 180, height: CGFloat(itemCount) * 24 + 8)

        for (index, rect) in SelectionToolbarState.arrowTypeMenuItemRects(in: menu, itemCount: itemCount).enumerated() {
            XCTAssertEqual(
                SelectionToolbarState.arrowTypeMenuHitTarget(
                    at: NSPoint(x: rect.midX, y: rect.midY),
                    in: menu,
                    itemCount: itemCount
                ),
                .item(index)
            )
        }
    }

    func testArrowTypeOptionsMatchCompactIconMenu() {
        XCTAssertEqual(
            CaptureArrowType.allCases.map(\.title),
            [
                "没有箭头的实线",
                "普通箭头线",
                "实心箭头线",
                "空心箭头线",
                "菱形箭头线",
                "端帽箭头线",
                "圆点箭头线",
            ]
        )
        XCTAssertFalse(CaptureArrowType.allCases.map(\.title).contains("手绘箭头线"))
    }

    func testDefaultArrowLineActivationUsesFirstPaletteColorAndExpectedArrowTypes() {
        let state = SelectionToolbarState.arrowLineActivationState(
            currentStyle: CaptureAnnotationStyle(),
            paletteColors: SelectionOverlayWindow.defaultPaletteColors
        )

        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: state.style.strokeColor), "#FF001A")
        XCTAssertEqual(state.style.strokeWidth, 4)
        XCTAssertEqual(state.startArrowType, .none)
        XCTAssertEqual(state.endArrowType, .normal)
    }

    func testShapeAndArrowToolbarsUseSeparateStrokeWidthOptions() {
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .shape), [2, 4, 7])
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .arrowLine), [3, 4, 6])
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .brush), [3, 5, 7])
    }

    func testShapeArrowBrushAndMarkerToolbarsUseDistinctStrokeWidthOptions() {
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .shape), [2, 4, 7])
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .arrowLine), [3, 4, 6])
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .brush), [3, 5, 7])
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .marker), [14, 18, 22])
    }

    func testMarkerToolSelectionDoesNotChangeBrushDefaults() {
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .brush), [3, 5, 7])
        XCTAssertEqual(
            SelectionToolbarState.strokePatternOptions(canUsePremiumStrokePatterns: true, mode: .brush).map(\.pattern),
            [.solid, .dashLong, .dashNarrow, .dashLongShort]
        )
    }

    func testBrushActivationUsesFirstPaletteColorAndMediumWidth() {
        let style = SelectionToolbarState.brushActivationStyle(
            currentStyle: CaptureAnnotationStyle(),
            paletteColors: SelectionOverlayWindow.defaultPaletteColors
        )

        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#FF001A")
        XCTAssertEqual(style.strokeWidth, 3)
        XCTAssertFalse(style.fillEnabled)
    }

    func testBrushActivationFallsBackToSolidWhenCurrentStrokePatternIsSketchOnly() {
        var current = CaptureAnnotationStyle()
        current.strokePattern = .sketchDashed

        let style = SelectionToolbarState.brushActivationStyle(
            currentStyle: current,
            paletteColors: SelectionOverlayWindow.defaultPaletteColors
        )

        XCTAssertEqual(style.strokePattern, .solid)
    }

    func testBrushOptionsToolbarShowsStrokeStyleAndColorsOnly() {
        let optionsRect = NSRect(x: 100, y: 100, width: 420, height: 40)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .brush
        )

        XCTAssertEqual(layout.strokeWidths.count, 3)
        XCTAssertNil(layout.fillToggle)
        XCTAssertNil(layout.rectangleMode)
        XCTAssertNil(layout.ellipseMode)
        XCTAssertNil(layout.startArrowType)
        XCTAssertNil(layout.endArrowType)
        XCTAssertGreaterThan(layout.strokeStyle.minX, layout.strokeWidths.last!.maxX)
        XCTAssertGreaterThan(layout.colorSwatches.first!.minX, layout.strokeStyle.maxX)
    }

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

        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#B3EB00")
        XCTAssertEqual(style.strokeWidth, 18)
        XCTAssertEqual(style.strokePattern, .solid)
        XCTAssertFalse(style.fillEnabled)
    }

    func testMarkerToolbarStrokeWidthPreviewUsesScaledBrushLikeWidths() {
        XCTAssertEqual(SelectionToolbarState.strokeWidthPreviewLineWidth(for: 14, mode: .marker), 3)
        XCTAssertEqual(SelectionToolbarState.strokeWidthPreviewLineWidth(for: 18, mode: .marker), 5)
        XCTAssertEqual(SelectionToolbarState.strokeWidthPreviewLineWidth(for: 22, mode: .marker), 7)
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .marker), [14, 18, 22])
    }

    func testMarkerCursorDotDiameterTracksStrokeWidthWithoutUsingFullHighlighterSize() {
        XCTAssertEqual(SelectionToolbarState.markerCursorDotDiameter(for: 14), 10)
        XCTAssertEqual(SelectionToolbarState.markerCursorDotDiameter(for: 18), 13)
        XCTAssertEqual(SelectionToolbarState.markerCursorDotDiameter(for: 22), 16)
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
        XCTAssertEqual(layout.strokeStyle, .zero)
        XCTAssertGreaterThan(layout.colorSwatches.first!.minX, layout.strokeWidths.last!.maxX)
        for strokeWidth in layout.strokeWidths {
            XCTAssertFalse(layout.colorSwatches.contains { $0.intersects(strokeWidth) })
        }
    }

    func testMarkerOptionsToolbarDoesNotExposeStrokeStyleField() {
        XCTAssertFalse(SelectionToolbarState.showsStrokeStyleField(for: .marker))
        XCTAssertTrue(SelectionToolbarState.showsStrokeStyleField(for: .shape))
        XCTAssertTrue(SelectionToolbarState.showsStrokeStyleField(for: .arrowLine))
        XCTAssertTrue(SelectionToolbarState.showsStrokeStyleField(for: .brush))
    }

    func testOverlayWindowUsesMarkerOptionsToolbarModeForMarkerShape() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_activateShapeTool(.marker)

        XCTAssertEqual(window.test_optionsToolbarMode, .marker)
    }

    func testOverlayWindowMarkerActivationUsesDefaultHighlighterStyle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_activateShapeTool(.rectangle)
        window.test_setCurrentStrokePattern(.dashLong)

        window.test_activateShapeTool(.marker)

        guard let style = window.test_currentStyle else {
            return XCTFail("Expected current marker style")
        }
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#B3EB00")
        XCTAssertEqual(style.strokeWidth, 18)
        XCTAssertEqual(style.strokePattern, .solid)
        XCTAssertFalse(style.fillEnabled)
    }

    func testOverlayWindowMarkerColorDoesNotLeakIntoOtherShapeTools() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        guard let markerBluePoint = window.test_optionsPaletteColorPoint(at: 8) else {
            return XCTFail("Expected marker palette control")
        }
        window.test_mouseDown(at: markerBluePoint)
        window.test_mouseUp(at: markerBluePoint)

        guard let markerStyle = window.test_currentStyle else {
            return XCTFail("Expected marker style")
        }
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: markerStyle.strokeColor), "#3C53D7")

        window.test_activateShapeTool(.rectangle)
        guard let rectangleStyle = window.test_currentStyle else {
            return XCTFail("Expected rectangle style")
        }
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: rectangleStyle.strokeColor), "#FF001A")

        window.test_activateShapeTool(.arrowLine)
        guard let arrowStyle = window.test_currentStyle else {
            return XCTFail("Expected arrow line style")
        }
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: arrowStyle.strokeColor), "#FF001A")

        window.test_activateShapeTool(.brush)
        guard let brushStyle = window.test_currentStyle else {
            return XCTFail("Expected brush style")
        }
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: brushStyle.strokeColor), "#FF001A")

        window.test_activateShapeTool(.marker)
        guard let restoredMarkerStyle = window.test_currentStyle else {
            return XCTFail("Expected restored marker style")
        }
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: restoredMarkerStyle.strokeColor), "#3C53D7")
    }

    func testMarkerActivationClearsStaleStrokeStyleMenu() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_activateShapeTool(.rectangle)
        window.test_setStrokeStyleMenuVisible(true)

        window.test_activateShapeTool(.marker)

        XCTAssertFalse(window.test_showsStrokeStyleMenu)
    }

    func testMarkerActivationClearsStaleArrowTypeMenus() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_activateShapeTool(.arrowLine)
        window.test_setArrowTypeMenusVisible(start: true, end: true)

        window.test_activateShapeTool(.marker)

        XCTAssertFalse(window.test_showsStartArrowTypeMenu)
        XCTAssertFalse(window.test_showsEndArrowTypeMenu)
    }

    func testOverlayWindowDraggingMarkerCreatesLocalMarkerAnnotation() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let markerLine = window.test_markerLine(at: 0) else {
            return XCTFail("Expected marker annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .marker)
        XCTAssertEqual(markerLine.start.x, 40, accuracy: 0.1)
        XCTAssertEqual(markerLine.start.y, 50, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.x, 120, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.y, 80, accuracy: 0.1)
    }

    func testOverlayWindowClickingMarkerCreatesDotAnnotation() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        guard let markerLine = window.test_markerLine(at: 0) else {
            return XCTFail("Expected marker dot annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .marker)
        XCTAssertEqual(markerLine.start.x, 40, accuracy: 0.1)
        XCTAssertEqual(markerLine.start.y, 50, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.x, 40, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.y, 50, accuracy: 0.1)
    }

    func testOverlayWindowIgnoresShortMarkerDragsUnderEightPoints() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 146, y: 150))
        window.test_mouseUp(at: NSPoint(x: 146, y: 150))

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertNil(window.test_markerLine(at: 0))
    }

    func testOverlayWindowShiftDraggingMarkerSnapsToNearestAxisOrDiagonal() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 204, y: 170), modifierFlags: [.shift])
        window.test_mouseUp(at: NSPoint(x: 204, y: 170), modifierFlags: [.shift])

        guard let markerLine = window.test_markerLine(at: 0) else {
            return XCTFail("Expected marker annotation")
        }
        XCTAssertEqual(markerLine.start.x, 40, accuracy: 0.1)
        XCTAssertEqual(markerLine.start.y, 50, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.x, 104, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.y, 50, accuracy: 0.1)
    }

    func testOverlayWindowMovesSelectedMarkerLineWithoutAddingAnnotation() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_markerLine(at: 0) else {
            return XCTFail("Expected marker annotation")
        }

        window.test_mouseDown(at: NSPoint(x: 180, y: 165))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 185))
        window.test_mouseUp(at: NSPoint(x: 210, y: 185))

        guard let moved = window.test_markerLine(at: 0) else {
            return XCTFail("Expected moved marker annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .marker)
        XCTAssertEqual(moved.start.x, original.start.x + 30, accuracy: 0.1)
        XCTAssertEqual(moved.start.y, original.start.y + 20, accuracy: 0.1)
        XCTAssertEqual(moved.end.x, original.end.x + 30, accuracy: 0.1)
        XCTAssertEqual(moved.end.y, original.end.y + 20, accuracy: 0.1)
    }

    func testOverlayWindowMarkerEndpointHandlesResizeLineWithoutCoveringExactEndpoints() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        let overlayLine = CaptureMarkerLine(start: NSPoint(x: 140, y: 150), end: NSPoint(x: 220, y: 180))
        let startHandle = SelectionToolbarState.markerRotationHandlePoint(for: .start, line: overlayLine)!

        XCTAssertEqual(window.test_cursorStyle(at: startHandle), .rotationHandle)
        XCTAssertEqual(window.test_cursorStyle(at: overlayLine.start), .marker)

        window.test_mouseDown(at: startHandle)
        window.test_mouseDragged(to: NSPoint(x: 155, y: 130))
        window.test_mouseUp(at: NSPoint(x: 155, y: 130))

        guard let markerLine = window.test_markerLine(at: 0) else {
            return XCTFail("Expected marker annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(markerLine.start.x, 55, accuracy: 0.1)
        XCTAssertEqual(markerLine.start.y, 30, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.x, 120, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.y, 80, accuracy: 0.1)
    }

    func testOverlayWindowCanContinueDrawingMarkerFromExistingEndpoint() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        window.test_mouseDown(at: NSPoint(x: 220, y: 180))
        window.test_mouseDragged(to: NSPoint(x: 250, y: 180))
        window.test_mouseUp(at: NSPoint(x: 250, y: 180))

        XCTAssertEqual(window.test_annotationCount, 2)
        guard let continued = window.test_markerLine(at: 1) else {
            return XCTFail("Expected continued marker annotation")
        }
        XCTAssertEqual(continued.start.x, 120, accuracy: 0.1)
        XCTAssertEqual(continued.start.y, 80, accuracy: 0.1)
        XCTAssertEqual(continued.end.x, 150, accuracy: 0.1)
        XCTAssertEqual(continued.end.y, 80, accuracy: 0.1)
    }

    func testMarkerAnnotationStyleCanEditButGeometryCannotResizeAfterDrawing() {
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.marker))
        XCTAssertFalse(SelectionToolbarState.annotationKindSupportsGeometryEditing(.marker))
    }

    func testOverlayWindowDeleteKeyRemovesSelectedMarker() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))
        window.test_mouseDown(at: NSPoint(x: 180, y: 165))
        window.test_mouseUp(at: NSPoint(x: 180, y: 165))

        XCTAssertEqual(window.test_selectedAnnotationKind, .marker)
        window.test_keyDown(keyCode: 51)

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertNil(window.test_selectedAnnotationKind)
    }

    func testOverlayWindowMarkerOptionsToolbarEditsSelectedMarkerStyle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))
        window.test_mouseDown(at: NSPoint(x: 180, y: 165))
        window.test_mouseUp(at: NSPoint(x: 180, y: 165))

        guard let strokeWidthPoint = window.test_optionsStrokeWidthPoint(at: 2),
              let colorPoint = window.test_optionsPaletteColorPoint(at: 0) else {
            return XCTFail("Expected marker options toolbar controls")
        }

        window.test_mouseDown(at: strokeWidthPoint)
        window.test_mouseUp(at: strokeWidthPoint)
        window.test_mouseDown(at: colorPoint)
        window.test_mouseUp(at: colorPoint)

        guard let style = window.test_annotationStyle(at: 0) else {
            return XCTFail("Expected marker annotation style")
        }
        XCTAssertEqual(window.test_optionsToolbarMode, .marker)
        XCTAssertEqual(style.strokeWidth, 22)
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#FF001A")
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.fillColor), "#FF001A")
    }

    func testSnappedMarkerEndPointKeepsRawPointWithoutShift() {
        let rawEnd = NSPoint(x: 64, y: 34)

        let snapped = SelectionToolbarState.snappedMarkerEndPoint(
            start: .zero,
            rawEnd: rawEnd,
            isShiftPressed: false
        )

        XCTAssertEqual(snapped.x, rawEnd.x, accuracy: 0.1)
        XCTAssertEqual(snapped.y, rawEnd.y, accuracy: 0.1)
    }

    func testSnappedMarkerEndPointUsesNearestHorizontalVerticalOrDiagonalWithShift() {
        let horizontal = SelectionToolbarState.snappedMarkerEndPoint(
            start: .zero,
            rawEnd: NSPoint(x: 64, y: 20),
            isShiftPressed: true
        )
        XCTAssertEqual(horizontal.x, 64, accuracy: 0.1)
        XCTAssertEqual(horizontal.y, 0, accuracy: 0.1)

        let vertical = SelectionToolbarState.snappedMarkerEndPoint(
            start: .zero,
            rawEnd: NSPoint(x: 12, y: 64),
            isShiftPressed: true
        )
        XCTAssertEqual(vertical.x, 0, accuracy: 0.1)
        XCTAssertEqual(vertical.y, 64, accuracy: 0.1)

        let diagonal = SelectionToolbarState.snappedMarkerEndPoint(
            start: .zero,
            rawEnd: NSPoint(x: 42, y: 38),
            isShiftPressed: true
        )
        XCTAssertEqual(diagonal.x, diagonal.y, accuracy: 0.1)
    }

    func testMarkerToolbarButtonClickActivatesMarkerMode() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.rectangle)
        window.test_setStrokeStyleMenuVisible(true)
        window.test_setArrowTypeMenusVisible(start: true, end: true)

        guard let point = window.test_markerToolbarButtonPoint() else {
            return XCTFail("Expected visible marker toolbar button")
        }
        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)

        XCTAssertEqual(window.test_optionsToolbarMode, .marker)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 150, y: 150)), .marker)
        XCTAssertFalse(window.test_showsStrokeStyleMenu)
        XCTAssertFalse(window.test_showsStartArrowTypeMenu)
        XCTAssertFalse(window.test_showsEndArrowTypeMenu)
    }

    func testMarkerToolbarButtonSelectedStateWorksWhenMarkerIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        XCTAssertFalse(window.test_markerToolbarButtonIsSelected)

        window.test_activateShapeTool(.marker)

        XCTAssertTrue(window.test_markerToolbarButtonIsSelected)
    }

    func testBrushAnnotationStyleIsNotEditableAfterDrawing() {
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.rectangle))
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.ellipse))
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.arrowLine))
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.marker))
        XCTAssertFalse(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.brush))
    }

    func testBrushAnnotationGeometryCanMoveButNotResizeAfterDrawing() {
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsGeometryEditing(.rectangle))
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsGeometryEditing(.ellipse))
        XCTAssertFalse(SelectionToolbarState.annotationKindSupportsGeometryEditing(.arrowLine))
        XCTAssertFalse(SelectionToolbarState.annotationKindSupportsGeometryEditing(.brush))
    }

    func testBrushAnnotationStyleIsFrozenAfterDrawing() {
        var original = CaptureAnnotationStyle()
        original.strokeWidth = 5
        original.strokePattern = .solid
        original.strokeColor = .systemRed

        var current = CaptureAnnotationStyle()
        current.strokeWidth = 7
        current.strokePattern = .dashLong
        current.strokeColor = .systemBlue

        let applied = SelectionToolbarState.updatedSelectedAnnotationStyle(
            kind: .brush,
            existingStyle: original,
            currentStyle: current
        )

        XCTAssertEqual(applied.strokeWidth, 5)
        XCTAssertEqual(applied.strokePattern, .solid)
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: applied.strokeColor), "#FF3B30")
    }

    func testEditableAnnotationStyleUsesCurrentToolbarStyle() {
        var original = CaptureAnnotationStyle()
        original.strokeWidth = 4
        original.strokePattern = .solid

        var current = CaptureAnnotationStyle()
        current.strokeWidth = 7
        current.strokePattern = .dashLong

        let applied = SelectionToolbarState.updatedSelectedAnnotationStyle(
            kind: .rectangle,
            existingStyle: original,
            currentStyle: current
        )

        XCTAssertEqual(applied.strokeWidth, 7)
        XCTAssertEqual(applied.strokePattern, .dashLong)
    }

    func testSelectionResizeCursorWinsOverBrushOnSelectionBorder() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: .topLeft,
                isAnnotationBorder: false,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .brush
            ),
            .resizeTopLeft
        )
    }

    func testBrushCursorStillShowsInsideSelectionAwayFromBorder() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .brush
            ),
            .brush
        )
    }

    func testBrushCursorUsesArrowOutsideSelectionAndToolbar() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: false,
                isShapeToolActive: true,
                currentShapeKind: .brush
            ),
            .arrow
        )

        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: true,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .brush
            ),
            .arrow
        )
    }

    func testBrushCursorUsesArrowOnToolbarDragArea() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: true,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: false,
                isShapeToolActive: true,
                currentShapeKind: .brush
            ),
            .arrow
        )
    }

    func testShapeToolCursorUsesMoveOnAnnotationBorderWhileToolIsActive() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .rectangle
            ),
            .move
        )
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .arrowLine
            ),
            .move
        )
    }

    func testShapeToolCursorUsesResizeOnAnnotationHandleWhileToolIsActive() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: .topLeft,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .rectangle
            ),
            .resizeTopLeft
        )
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: .right,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .arrowLine
            ),
            .resizeLeftRight
        )
    }

    func testAnnotationResizeCursorWinsOverSelectionResizeWhileDrawingToolIsActive() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: .topLeft,
                selectionResizeHandle: .right,
                isAnnotationBorder: true,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .rectangle
            ),
            .resizeTopLeft
        )
    }

    func testAnnotatingCursorUsesArrowOutsideSelection() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: false,
                currentShapeKind: .rectangle
            ),
            .arrow
        )
    }

    func testSpecialArrowTypesCanOnlyBeSelectedOnOneEnd() {
        XCTAssertEqual(
            SelectionToolbarState.arrowTypesAfterSelection(
                currentStart: .normal,
                currentEnd: .normal,
                selectedType: .solidArrow,
                endpoint: .start
            ),
            SelectionToolbarState.ArrowTypePair(start: .solidArrow, end: .none)
        )
        XCTAssertEqual(
            SelectionToolbarState.arrowTypesAfterSelection(
                currentStart: .normal,
                currentEnd: .normal,
                selectedType: .hollowArrow,
                endpoint: .end
            ),
            SelectionToolbarState.ArrowTypePair(start: .none, end: .hollowArrow)
        )
    }

    func testChangingOtherEndClearsExistingSpecialArrowType() {
        XCTAssertEqual(
            SelectionToolbarState.arrowTypesAfterSelection(
                currentStart: .solidArrow,
                currentEnd: .none,
                selectedType: .bar,
                endpoint: .end
            ),
            SelectionToolbarState.ArrowTypePair(start: .none, end: .bar)
        )
        XCTAssertEqual(
            SelectionToolbarState.arrowTypesAfterSelection(
                currentStart: .none,
                currentEnd: .hollowArrow,
                selectedType: .dot,
                endpoint: .start
            ),
            SelectionToolbarState.ArrowTypePair(start: .dot, end: .none)
        )
    }

    func testRegularArrowTypesStillSupportBothEnds() {
        XCTAssertEqual(
            SelectionToolbarState.arrowTypesAfterSelection(
                currentStart: .diamond,
                currentEnd: .bar,
                selectedType: .normal,
                endpoint: .start
            ),
            SelectionToolbarState.ArrowTypePair(start: .normal, end: .bar)
        )
        XCTAssertEqual(
            SelectionToolbarState.arrowTypesAfterSelection(
                currentStart: .normal,
                currentEnd: .dot,
                selectedType: .diamond,
                endpoint: .end
            ),
            SelectionToolbarState.ArrowTypePair(start: .normal, end: .diamond)
        )
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

    func testBrushRotationHitTargetUsesInsetHandlesInsteadOfPathEndpoints() {
        let path = CaptureBrushPath(points: [
            NSPoint(x: 10, y: 10),
            NSPoint(x: 35, y: 45),
            NSPoint(x: 60, y: 70),
            NSPoint(x: 110, y: 10),
        ])

        let startHandle = SelectionToolbarState.brushRotationHandlePoint(for: .start, path: path)!
        let endHandle = SelectionToolbarState.brushRotationHandlePoint(for: .end, path: path)!

        XCTAssertNotEqual(startHandle, path.points.first)
        XCTAssertNotEqual(endHandle, path.points.last)
        XCTAssertEqual(SelectionToolbarState.brushRotationHitTarget(at: NSPoint(x: 10, y: 10), path: path), .none)
        XCTAssertEqual(SelectionToolbarState.brushRotationHitTarget(at: NSPoint(x: 110, y: 10), path: path), .none)
        XCTAssertEqual(SelectionToolbarState.brushRotationHitTarget(at: startHandle, path: path), .start)
        XCTAssertEqual(SelectionToolbarState.brushRotationHitTarget(at: endHandle, path: path), .end)
        XCTAssertEqual(SelectionToolbarState.brushRotationHitTarget(at: NSPoint(x: 60, y: 70), path: path), .none)
    }

    func testMarkerRotationHitTargetUsesInsetHandlesInsteadOfLineEndpoints() {
        let line = CaptureMarkerLine(start: NSPoint(x: 10, y: 10), end: NSPoint(x: 110, y: 10))

        XCTAssertEqual(SelectionToolbarState.markerRotationHandlePoint(for: .start, line: line), NSPoint(x: 24, y: 10))
        XCTAssertEqual(SelectionToolbarState.markerRotationHandlePoint(for: .end, line: line), NSPoint(x: 96, y: 10))
        XCTAssertEqual(SelectionToolbarState.markerRotationHitTarget(at: line.start, line: line), .none)
        XCTAssertEqual(SelectionToolbarState.markerRotationHitTarget(at: line.end, line: line), .none)
        XCTAssertEqual(SelectionToolbarState.markerRotationHitTarget(at: NSPoint(x: 24, y: 10), line: line), .start)
        XCTAssertEqual(SelectionToolbarState.markerRotationHitTarget(at: NSPoint(x: 96, y: 10), line: line), .end)
    }

    func testDraggingMarkerEndpointChangesOnlyThatEndpoint() {
        let line = CaptureMarkerLine(start: NSPoint(x: 10, y: 10), end: NSPoint(x: 110, y: 10))

        let movedStart = SelectionToolbarState.resizedMarkerLine(line, dragging: .start, to: NSPoint(x: 20, y: 35))
        XCTAssertEqual(movedStart.start.x, 20, accuracy: 0.1)
        XCTAssertEqual(movedStart.start.y, 35, accuracy: 0.1)
        XCTAssertEqual(movedStart.end.x, 110, accuracy: 0.1)
        XCTAssertEqual(movedStart.end.y, 10, accuracy: 0.1)

        let movedEnd = SelectionToolbarState.resizedMarkerLine(line, dragging: .end, to: NSPoint(x: 80, y: 45))
        XCTAssertEqual(movedEnd.start.x, 10, accuracy: 0.1)
        XCTAssertEqual(movedEnd.start.y, 10, accuracy: 0.1)
        XCTAssertEqual(movedEnd.end.x, 80, accuracy: 0.1)
        XCTAssertEqual(movedEnd.end.y, 45, accuracy: 0.1)
    }

    func testBrushRotationHandleAngleFollowsEndpointTangent() {
        let horizontal = CaptureBrushPath(points: [
            NSPoint(x: 10, y: 10),
            NSPoint(x: 40, y: 10),
            NSPoint(x: 70, y: 10),
        ])
        XCTAssertEqual(
            SelectionToolbarState.brushRotationHandleAngle(for: .start, path: horizontal)!,
            .pi,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SelectionToolbarState.brushRotationHandleAngle(for: .end, path: horizontal)!,
            0,
            accuracy: 0.001
        )

        let vertical = CaptureBrushPath(points: [
            NSPoint(x: 10, y: 10),
            NSPoint(x: 10, y: 40),
            NSPoint(x: 10, y: 70),
        ])
        XCTAssertEqual(
            SelectionToolbarState.brushRotationHandleAngle(for: .end, path: vertical)!,
            .pi / 2,
            accuracy: 0.001
        )
    }

    func testDraggingBrushEndpointTransformsWholePathAroundOppositeEndpoint() {
        let path = CaptureBrushPath(points: [
            NSPoint(x: 10, y: 10),
            NSPoint(x: 40, y: 30),
            NSPoint(x: 70, y: 10),
        ])

        let moved = SelectionToolbarState.rotatedBrushPath(
            path,
            dragging: .end,
            to: NSPoint(x: 40, y: 40)
        )

        XCTAssertEqual(moved.points.count, path.points.count)
        XCTAssertEqual(moved.points[0].x, 10, accuracy: 0.1)
        XCTAssertEqual(moved.points[0].y, 10, accuracy: 0.1)
        XCTAssertEqual(moved.points[1].x, 15, accuracy: 0.1)
        XCTAssertEqual(moved.points[1].y, 35, accuracy: 0.1)
        XCTAssertEqual(moved.points[2].x, 40, accuracy: 0.1)
        XCTAssertEqual(moved.points[2].y, 40, accuracy: 0.1)
    }

    func testPrimaryShapeToolSelectionTogglesOffWhenAnyShapeToolIsActive() {
        XCTAssertEqual(
            SelectionToolbarState.toggledPrimaryShapeTool(current: nil, defaultShape: .rectangle),
            .rectangle
        )
        XCTAssertNil(
            SelectionToolbarState.toggledPrimaryShapeTool(current: .rectangle, defaultShape: .rectangle)
        )
        XCTAssertNil(
            SelectionToolbarState.toggledPrimaryShapeTool(current: .ellipse, defaultShape: .rectangle)
        )
    }

    func testPrimaryShapeToolActivationUsesFirstPaletteColorWhenStyleIsStillDefault() {
        let style = SelectionToolbarState.styleForPrimaryShapeToolActivation(
            currentStyle: CaptureAnnotationStyle(),
            paletteColors: SelectionOverlayWindow.defaultPaletteColors
        )

        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#FF001A")
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.fillColor), "#FF001A")
        XCTAssertEqual(style.strokeWidth, 4)
        XCTAssertEqual(style.cornerRadius, 5)
    }

    func testPrimaryShapeToolActivationPreservesUserChosenColor() {
        var currentStyle = CaptureAnnotationStyle()
        currentStyle.strokeColor = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        currentStyle.fillColor = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)

        let style = SelectionToolbarState.styleForPrimaryShapeToolActivation(
            currentStyle: currentStyle,
            paletteColors: SelectionOverlayWindow.defaultPaletteColors
        )

        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#00FF00")
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.fillColor), "#00FF00")
        XCTAssertEqual(style.strokeWidth, 4)
        XCTAssertEqual(style.cornerRadius, 5)
    }

    func testFillPreviewUsesNeutralGrayWithoutFill() {
        let style = CaptureAnnotationStyle()

        let preview = SelectionToolbarState.fillPreviewStyle(
            currentShapeKind: .rectangle,
            currentStyle: style
        )

        XCTAssertEqual(preview.shape, .rectangle)
        XCTAssertFalse(preview.showsStrokeOutline)
        XCTAssertTrue(preview.color.isEqual(NSColor.systemGray))
    }

    func testFillPreviewUsesSelectedColorAndShapeWhenFillEnabled() {
        var style = CaptureAnnotationStyle()
        style.fillEnabled = true
        style.fillColor = .systemGreen

        let preview = SelectionToolbarState.fillPreviewStyle(
            currentShapeKind: .ellipse,
            currentStyle: style
        )

        XCTAssertEqual(preview.shape, .ellipse)
        XCTAssertFalse(preview.showsStrokeOutline)
        XCTAssertTrue(preview.color.isEqual(NSColor.systemGreen))
    }

    func testColorSwatchesUseTwoRowsAndSquarePaletteButton() {
        let optionsRect = NSRect(x: 100, y: 100, width: 510, height: 40)
        let swatches = SelectionToolbarState.colorSwatchRects(in: optionsRect, paletteCount: 20)
        let firstRow = swatches[0]
        let secondRow = swatches[10]
        let customSlot = SelectionToolbarState.colorSwatchRects(in: optionsRect, paletteCount: 20).last!

        XCTAssertEqual(firstRow.minY, optionsRect.minY + 23)
        XCTAssertEqual(secondRow.minY, optionsRect.minY + 7)
        XCTAssertEqual(customSlot.width, 32)
        XCTAssertEqual(customSlot.height, 32)
        XCTAssertEqual(customSlot.minY, optionsRect.minY + 4)
    }

    func testCompactColorSwatchesUseSingleRowAndShortToolbar() {
        let optionsRect = NSRect(x: 100, y: 100, width: 422, height: 30)
        let swatches = SelectionToolbarState.colorSwatchRects(in: optionsRect, paletteCount: 4)
        let customSlot = swatches.last!

        XCTAssertEqual(SelectionToolbarState.optionsToolbarHeight(paletteCount: 4), 30)
        XCTAssertEqual(SelectionToolbarState.optionsToolbarWidth(paletteCount: 4), 422)
        XCTAssertEqual(swatches.count, 5)
        XCTAssertTrue(swatches[0..<4].allSatisfy { $0.minY == optionsRect.minY + 9 })
        XCTAssertEqual(customSlot.width, 20)
        XCTAssertEqual(customSlot.height, 20)
        XCTAssertEqual(customSlot.minY, optionsRect.minY + 5)
    }

    func testDefaultPalettePutsFrequentRedFirstInRequestedTwoRowColors() {
        let hexColors = SelectionOverlayWindow.defaultPaletteColors.map {
            SelectionToolbarState.colorSamplerHexString(for: $0)
        }

        XCTAssertEqual(
            hexColors,
            [
                "#FF001A",
                "#8A8A8A",
                "#000000",
                "#A3000D",
                "#FF7E06",
                "#FFF300",
                "#00BE4E",
                "#00B0EF",
                "#3C53D7",
                "#BB4AB0",
                "#FFFFFF",
                "#CACACA",
                "#CE815D",
                "#FFB2D0",
                "#FFCC00",
                "#F5E7B5",
                "#B3EB00",
                "#8EE1EE",
                "#6F9EC8",
                "#D0C6EC",
            ]
        )
    }

    func testPaletteLastGraySwatchDoesNotTriggerCustomPalette() {
        let optionsRect = NSRect(x: 100, y: 100, width: 510, height: 40)
        let swatches = SelectionToolbarState.colorSwatchRects(in: optionsRect, paletteCount: 20)
        let lastGraySwatch = swatches[19]

        XCTAssertEqual(
            SelectionToolbarState.swatchHitTarget(at: NSPoint(x: lastGraySwatch.midX, y: lastGraySwatch.midY), in: optionsRect, paletteCount: 20),
            .palette(19)
        )
    }

    func testCustomPaletteButtonUsesItsOwnHitTargetOnly() {
        let optionsRect = NSRect(x: 100, y: 100, width: 510, height: 40)
        let customSlot = SelectionToolbarState.colorSwatchRects(in: optionsRect, paletteCount: 20).last!

        XCTAssertEqual(
            SelectionToolbarState.swatchHitTarget(at: NSPoint(x: customSlot.midX, y: customSlot.midY), in: optionsRect, paletteCount: 20),
            .custom
        )
        XCTAssertNil(
            SelectionToolbarState.swatchHitTarget(at: NSPoint(x: customSlot.maxX + 4, y: customSlot.midY), in: optionsRect, paletteCount: 20)
        )
    }

    func testOptionsToolbarWidthShrinksWhenPaletteCountIsReduced() {
        let fullPaletteWidth = SelectionToolbarState.optionsToolbarWidth(paletteCount: 20)
        let compactPaletteWidth = SelectionToolbarState.optionsToolbarWidth(paletteCount: 8)

        XCTAssertEqual(fullPaletteWidth, 530)
        XCTAssertLessThan(compactPaletteWidth, fullPaletteWidth)
    }

    func testStrokePatternOptionsReserveSketchLinesForPremiumAccess() {
        let freeOptions = SelectionToolbarState.strokePatternOptions(canUsePremiumStrokePatterns: false)

        XCTAssertEqual(
            freeOptions.map(\.pattern),
            [.solid, .dashLong, .dashNarrow, .dashLongShort, .sketchSolid, .sketchDashed]
        )
        XCTAssertTrue(freeOptions.allSatisfy(\.isEnabled))

        let premiumOptions = SelectionToolbarState.strokePatternOptions(canUsePremiumStrokePatterns: true)
        XCTAssertTrue(premiumOptions.allSatisfy(\.isEnabled))
    }

    func testBrushStrokePatternOptionsHideSketchLines() {
        let options = SelectionToolbarState.strokePatternOptions(
            canUsePremiumStrokePatterns: true,
            mode: .brush
        )

        XCTAssertEqual(options.map(\.pattern), [.solid, .dashLong, .dashNarrow, .dashLongShort])
    }

    func testMarkerStrokePatternOptionsOnlyUseSolidLine() {
        let options = SelectionToolbarState.strokePatternOptions(
            canUsePremiumStrokePatterns: true,
            mode: .marker
        )

        XCTAssertEqual(options.map(\.pattern), [.solid])
    }

    func testShapeAndArrowStrokePatternOptionsKeepSketchLines() {
        let shapeOptions = SelectionToolbarState.strokePatternOptions(
            canUsePremiumStrokePatterns: true,
            mode: .shape
        )
        let arrowOptions = SelectionToolbarState.strokePatternOptions(
            canUsePremiumStrokePatterns: true,
            mode: .arrowLine
        )

        XCTAssertEqual(shapeOptions.map(\.pattern), CaptureStrokePattern.allCases)
        XCTAssertEqual(arrowOptions.map(\.pattern), CaptureStrokePattern.allCases)
    }

    func testStrokeMenuHitTargetSelectsEveryMenuItem() {
        let itemCount = SelectionToolbarState.strokePatternOptions(canUsePremiumStrokePatterns: true).count
        let menu = NSRect(x: 120, y: 80, width: 102, height: CGFloat(itemCount) * 24 + 8)

        for (index, rect) in SelectionToolbarState.strokeStyleMenuItemRects(in: menu, itemCount: itemCount).enumerated() {
            XCTAssertEqual(
                SelectionToolbarState.strokeMenuHitTarget(at: NSPoint(x: rect.midX, y: rect.midY), in: menu, itemCount: itemCount),
                .item(index)
            )
        }
    }

    func testToolbarRectRightAlignsToAnchor() {
        let anchor = NSRect(x: 200, y: 300, width: 120, height: 80)
        let toolbar = SelectionToolbarState.toolbarRect(
            size: NSSize(width: 260, height: 30),
            anchoredTo: anchor,
            inside: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(toolbar.maxX, anchor.maxX)
    }

    func testToolbarRectStaysInsideBoundsForFullScreenSelection() {
        let bounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let toolbar = SelectionToolbarState.toolbarRect(
            size: NSSize(width: 520, height: 30),
            anchoredTo: bounds,
            inside: bounds
        )

        XCTAssertTrue(bounds.insetBy(dx: 8, dy: 8).contains(toolbar))
    }

    func testToolbarRectAvoidsMenuBarVisibleBoundsForFullScreenSelection() {
        let selection = NSRect(x: 0, y: 0, width: 800, height: 600)
        let visibleBounds = NSRect(x: 0, y: 0, width: 800, height: 560)
        let toolbar = SelectionToolbarState.toolbarRect(
            size: NSSize(width: 520, height: 30),
            anchoredTo: selection,
            inside: visibleBounds
        )

        XCTAssertLessThanOrEqual(toolbar.maxY, visibleBounds.maxY - 8)
    }

    func testToolbarRectUsesBottomRightInsideForFullScreenSelection() {
        let selection = NSRect(x: 0, y: 0, width: 800, height: 600)
        let visibleBounds = NSRect(x: 0, y: 0, width: 800, height: 560)
        let toolbar = SelectionToolbarState.toolbarRect(
            size: NSSize(width: 520, height: 30),
            anchoredTo: selection,
            inside: visibleBounds
        )

        XCTAssertEqual(toolbar.maxX, visibleBounds.maxX - 8)
        XCTAssertEqual(toolbar.minY, visibleBounds.minY + 8)
    }

    func testToolbarRectStaysOutsideMaximizedButNotFullScreenSelection() {
        let screenBounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let maximizedSelection = NSRect(x: 0, y: 40, width: 800, height: 520)
        let toolbar = SelectionToolbarState.toolbarRect(
            size: NSSize(width: 520, height: 30),
            anchoredTo: maximizedSelection,
            inside: screenBounds,
            allowsInsidePlacement: false
        )

        XCTAssertFalse(toolbar.intersects(maximizedSelection))
        XCTAssertTrue(screenBounds.insetBy(dx: 8, dy: 8).contains(toolbar))
    }

    func testToolbarRectUsesSideSpaceForTallNonFullScreenSelection() {
        let screenBounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let tallSelection = NSRect(x: 0, y: 0, width: 560, height: 600)
        let toolbar = SelectionToolbarState.toolbarRect(
            size: NSSize(width: 180, height: 30),
            anchoredTo: tallSelection,
            inside: screenBounds,
            allowsInsidePlacement: false
        )

        XCTAssertGreaterThanOrEqual(toolbar.minX, tallSelection.maxX)
        XCTAssertFalse(toolbar.intersects(tallSelection))
        XCTAssertTrue(screenBounds.insetBy(dx: 8, dy: 8).contains(toolbar))
    }

    func testFullScreenSelectionUsesScreenFrameNotVisibleFrame() {
        let screenBounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let maximizedSelection = NSRect(x: 0, y: 40, width: 800, height: 520)

        XCTAssertFalse(SelectionToolbarState.isFullScreenSelection(maximizedSelection, in: screenBounds))
        XCTAssertTrue(SelectionToolbarState.isFullScreenSelection(screenBounds, in: screenBounds))
    }

    func testDraggedToolbarRectAppliesOffsetAndClampsInsideBounds() {
        let dragged = SelectionToolbarState.draggedToolbarRect(
            baseRect: NSRect(x: 100, y: 120, width: 220, height: 28),
            offset: NSSize(width: 500, height: -200),
            inside: NSRect(x: 0, y: 0, width: 480, height: 320)
        )

        XCTAssertEqual(dragged.maxX, 472, accuracy: 0.1)
        XCTAssertEqual(dragged.minY, 8, accuracy: 0.1)
    }

    func testSelectionMeasurementControlLayoutAddsThreeButtonsAfterSizeText() {
        let selection = NSRect(x: 120, y: 140, width: 300, height: 180)
        let layout = SelectionToolbarState.measurementControlLayout(
            anchoredTo: selection,
            textSize: NSSize(width: 82, height: 15),
            inside: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertGreaterThan(layout.panel.width, 82 + 18)
        XCTAssertEqual(layout.cornerStyle.width, 20)
        XCTAssertEqual(layout.aspectRatio.width, 20)
        XCTAssertEqual(layout.refresh.width, 20)
        XCTAssertLessThan(layout.label.maxX, layout.cornerStyle.minX)
        XCTAssertLessThan(layout.cornerStyle.maxX, layout.aspectRatio.minX)
        XCTAssertLessThan(layout.aspectRatio.maxX, layout.refresh.minX)
    }

    func testSelectionMeasurementControlHitTestingFindsEachButton() {
        let selection = NSRect(x: 120, y: 140, width: 300, height: 180)
        let layout = SelectionToolbarState.measurementControlLayout(
            anchoredTo: selection,
            textSize: NSSize(width: 82, height: 15),
            inside: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(
            SelectionToolbarState.measurementControl(
                at: NSPoint(x: layout.cornerStyle.midX, y: layout.cornerStyle.midY),
                in: layout
            ),
            .cornerStyle
        )
        XCTAssertEqual(
            SelectionToolbarState.measurementControl(
                at: NSPoint(x: layout.aspectRatio.midX, y: layout.aspectRatio.midY),
                in: layout
            ),
            .aspectRatioLock
        )
        XCTAssertEqual(
            SelectionToolbarState.measurementControl(
                at: NSPoint(x: layout.refresh.midX, y: layout.refresh.midY),
                in: layout
            ),
            .refresh
        )
    }

    func testLockedAspectRatioSelectionResizeKeepsStartRatioFromCorner() {
        let start = NSRect(x: 100, y: 100, width: 200, height: 100)
        let resized = SelectionToolbarState.resizedSelectionRect(
            from: start,
            handle: .bottomRight,
            point: NSPoint(x: 360, y: 40),
            lockAspectRatio: true
        )

        XCTAssertEqual(resized.width / resized.height, 2, accuracy: 0.01)
        XCTAssertEqual(resized.minX, 100, accuracy: 0.1)
        XCTAssertEqual(resized.maxY, 200, accuracy: 0.1)
    }

    func testPopoverRectPrefersBelowAnchorWithoutCoveringIt() {
        let anchor = NSRect(x: 600, y: 420, width: 12, height: 12)
        let popover = SelectionToolbarState.popoverRect(
            size: NSSize(width: 240, height: 180),
            anchoredTo: anchor,
            inside: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertLessThanOrEqual(popover.maxY, anchor.minY - 8)
        XCTAssertFalse(popover.intersects(anchor))
    }

    func testPopoverRectFlipsAboveAnchorNearBottomAndStaysInsideBounds() {
        let bounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let anchor = NSRect(x: 600, y: 12, width: 12, height: 12)
        let popover = SelectionToolbarState.popoverRect(
            size: NSSize(width: 240, height: 180),
            anchoredTo: anchor,
            inside: bounds
        )

        XCTAssertGreaterThanOrEqual(popover.minY, anchor.maxY + 8)
        XCTAssertTrue(bounds.insetBy(dx: 8, dy: 8).contains(popover))
    }

    func testLocalAnnotationRectAllowsDrawingOutsideSelection() {
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let overlayRect = NSRect(x: 50, y: 80, width: 300, height: 180)

        XCTAssertEqual(
            SelectionToolbarState.localAnnotationRect(fromOverlayRect: overlayRect, selectionRect: selection),
            NSRect(x: -50, y: -20, width: 300, height: 180)
        )
    }

    func testLocalAnnotationRectKeepsOverlayPositionWhenSelectionMoves() {
        let movedSelection = NSRect(x: 160, y: 130, width: 200, height: 120)
        let existingOverlayRect = NSRect(x: 130, y: 140, width: 80, height: 50)

        XCTAssertEqual(
            SelectionToolbarState.localAnnotationRect(fromOverlayRect: existingOverlayRect, selectionRect: movedSelection),
            NSRect(x: -30, y: 10, width: 80, height: 50)
        )
    }

    func testLocalAnnotationRectsPreserveOverlayPositionsWhenSelectionMoves() {
        let movedSelection = NSRect(x: 160, y: 130, width: 200, height: 120)
        let existingOverlayRects = [
            NSRect(x: 130, y: 140, width: 80, height: 50),
            NSRect(x: 220, y: 180, width: 40, height: 30),
        ]

        XCTAssertEqual(
            SelectionToolbarState.localAnnotationRectsPreservingOverlayPositions(
                existingOverlayRects,
                selectionRect: movedSelection
            ),
            [
                NSRect(x: -30, y: 10, width: 80, height: 50),
                NSRect(x: 60, y: 50, width: 40, height: 30),
            ]
        )
    }

    func testShapeBorderHitIgnoresInteriorSoNestedDrawingCanStart() {
        let rect = NSRect(x: 100, y: 100, width: 120, height: 80)

        XCTAssertFalse(
            SelectionToolbarState.shapeBorderContains(
                point: NSPoint(x: rect.midX, y: rect.midY),
                rect: rect,
                kind: .rectangle,
                cornerRadius: 0
            )
        )
    }

    func testShapeBorderHitAcceptsPointNearBorderForMoving() {
        let rect = NSRect(x: 100, y: 100, width: 120, height: 80)

        XCTAssertTrue(
            SelectionToolbarState.shapeBorderContains(
                point: NSPoint(x: rect.minX + 2, y: rect.midY),
                rect: rect,
                kind: .rectangle,
                cornerRadius: 0
            )
        )
    }

    func testAnnotationBorderCursorUsesMoveCursorOverSelectionCrosshair() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: true
            ),
            .move
        )
    }

    func testResizeHandleCursorWinsOverAnnotationBorder() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: .left,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: true
            ),
            .resizeLeftRight
        )
    }

    func testResizeHandleCursorDirections() {
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .left), .resizeLeftRight)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .right), .resizeLeftRight)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .top), .resizeUpDown)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .bottom), .resizeUpDown)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .topLeft), .resizeTopLeft)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .topRight), .resizeTopRight)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .bottomLeft), .resizeBottomLeft)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .bottomRight), .resizeBottomRight)
    }

    func testSelectionResizeHandleCursorWinsOverSelectionCrosshair() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: .right,
                isAnnotationBorder: false,
                isInsideSelection: true
            ),
            .resizeLeftRight
        )
    }

    func testShapeResizeHandleCursorWinsOverSelectionResizeHandle() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: .topLeft,
                selectionResizeHandle: .right,
                isAnnotationBorder: true,
                isInsideSelection: true
            ),
            .resizeTopLeft
        )
    }

    func testSelectionResizeHandleHitsEntireEdges() {
        let rect = NSRect(x: 100, y: 100, width: 220, height: 140)

        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.minX + 2, y: rect.midY), in: rect),
            .left
        )
        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.maxX - 2, y: rect.midY), in: rect),
            .right
        )
        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.midX, y: rect.maxY - 2), in: rect),
            .top
        )
        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.midX, y: rect.minY + 2), in: rect),
            .bottom
        )
    }

    func testSelectionResizeHandleAcceptsVisibleHandleOutset() {
        let rect = NSRect(x: 100, y: 100, width: 220, height: 140)

        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.maxX + 10, y: rect.midY), in: rect),
            .right
        )
        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.midX, y: rect.maxY + 10), in: rect),
            .top
        )
    }

    func testSelectionResizeHandleHitsCornersAndIgnoresInterior() {
        let rect = NSRect(x: 100, y: 100, width: 220, height: 140)

        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.minX + 2, y: rect.maxY - 2), in: rect),
            .topLeft
        )
        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.maxX - 2, y: rect.minY + 2), in: rect),
            .bottomRight
        )
        XCTAssertNil(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.midX, y: rect.midY), in: rect)
        )
    }

    func testClickingCornerStyleMeasurementControlTogglesSelectionCornerRadius() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 220, height: 140))

        guard let point = window.test_measurementControlPoint(.cornerStyle) else {
            return XCTFail("Expected corner style control")
        }
        window.test_mouseDown(at: point)

        XCTAssertEqual(window.test_selectionCornerRadius, 8)

        window.test_mouseDown(at: point)

        XCTAssertEqual(window.test_selectionCornerRadius, 0)
    }

    func testClickingAspectRatioMeasurementControlLocksSelectionResizeRatio() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 100))

        guard let aspectPoint = window.test_measurementControlPoint(.aspectRatioLock) else {
            return XCTFail("Expected aspect ratio control")
        }
        window.test_mouseDown(at: aspectPoint)

        XCTAssertTrue(window.test_isSelectionAspectRatioLocked)

        window.test_mouseDown(at: NSPoint(x: 300, y: 100))
        window.test_mouseDragged(to: NSPoint(x: 360, y: 40))
        window.test_mouseUp(at: NSPoint(x: 360, y: 40))

        guard let resized = window.test_lockedSelectionRect else {
            return XCTFail("Expected locked selection")
        }
        XCTAssertEqual(resized.width / resized.height, 2, accuracy: 0.01)
    }

    func testClickingRefreshMeasurementControlKeepsSelectionAndRequestsRefresh() {
        let expectation = expectation(description: "refresh requested")
        let window = SelectionOverlayWindow(
            backgroundImage: nil,
            refreshHandler: {
                expectation.fulfill()
                return nil
            },
            selectionHandler: { _ in }
        )
        let selection = NSRect(x: 100, y: 100, width: 220, height: 140)
        window.test_setLockedSelectionRect(selection)

        guard let point = window.test_measurementControlPoint(.refresh) else {
            return XCTFail("Expected refresh control")
        }
        window.test_mouseDown(at: point)

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
    }

    func testAnnotationMoveMouseDownWinsOverSelectionResize() {
        XCTAssertEqual(
            SelectionToolbarState.annotatingMouseDownTarget(
                shapeResizeHandle: nil,
                isAnnotationBorder: true,
                selectionResizeHandle: .left,
                selectionMoveEligible: true
            ),
            .annotationMove
        )
    }

    func testShapeResizeMouseDownWinsOverAnnotationMove() {
        XCTAssertEqual(
            SelectionToolbarState.annotatingMouseDownTarget(
                shapeResizeHandle: .topLeft,
                isAnnotationBorder: true,
                selectionResizeHandle: .left,
                selectionMoveEligible: true
            ),
            .shapeResize(.topLeft)
        )
    }

    func testSelectionResizeMouseDownWinsOverSelectionMove() {
        XCTAssertEqual(
            SelectionToolbarState.annotatingMouseDownTarget(
                shapeResizeHandle: nil,
                isAnnotationBorder: false,
                selectionResizeHandle: .left,
                selectionMoveEligible: true
            ),
            .selectionResize(.left)
        )
    }

    func testSelectionMoveMouseDownStartsFromColorSamplerInterior() {
        XCTAssertEqual(
            SelectionToolbarState.annotatingMouseDownTarget(
                shapeResizeHandle: nil,
                isAnnotationBorder: false,
                selectionResizeHandle: nil,
                selectionMoveEligible: true
            ),
            .selectionMove
        )
    }

    func testSelectionMoveEligibilityRequiresPlainInteriorNonFullscreenSelection() {
        let selection = NSRect(x: 80, y: 90, width: 240, height: 160)
        let screenBounds = NSRect(x: 0, y: 0, width: 640, height: 480)

        XCTAssertTrue(
            SelectionToolbarState.shouldStartSelectionMove(
                isShapeToolActive: false,
                pointer: NSPoint(x: 160, y: 140),
                selectionRect: selection,
                screenBounds: screenBounds,
                selectionResizeHandle: nil
            )
        )
        XCTAssertFalse(
            SelectionToolbarState.shouldStartSelectionMove(
                isShapeToolActive: true,
                pointer: NSPoint(x: 160, y: 140),
                selectionRect: selection,
                screenBounds: screenBounds,
                selectionResizeHandle: nil
            )
        )
        XCTAssertFalse(
            SelectionToolbarState.shouldStartSelectionMove(
                isShapeToolActive: false,
                pointer: NSPoint(x: 82, y: 140),
                selectionRect: selection,
                screenBounds: screenBounds,
                selectionResizeHandle: .left
            )
        )
        XCTAssertFalse(
            SelectionToolbarState.shouldStartSelectionMove(
                isShapeToolActive: false,
                pointer: NSPoint(x: 320, y: 240),
                selectionRect: screenBounds,
                screenBounds: screenBounds,
                selectionResizeHandle: nil
            )
        )
    }

    func testMovedSelectionRectIsClampedInsideScreenBounds() {
        let moved = SelectionToolbarState.movedSelectionRect(
            startRect: NSRect(x: 80, y: 90, width: 200, height: 120),
            pointer: NSPoint(x: 720, y: 520),
            pointerOffset: NSPoint(x: 10, y: 10),
            inside: NSRect(x: 0, y: 0, width: 640, height: 480)
        )

        XCTAssertEqual(moved.origin.x, 440, accuracy: 0.1)
        XCTAssertEqual(moved.origin.y, 360, accuracy: 0.1)
        XCTAssertEqual(moved.width, 200, accuracy: 0.1)
        XCTAssertEqual(moved.height, 120, accuracy: 0.1)
    }

    func testToolbarTooltipTitlesAreAvailableForPrimaryButtons() {
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "rectangle"), "形状标注")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "save"), "保存")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "copy"), "复制到剪切板")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "scroll"), "滚动截图")
        XCTAssertNil(SelectionToolbarState.tooltipTitle(for: "ocr"))
        XCTAssertNil(SelectionToolbarState.tooltipTitle(for: "settings"))
    }

    func testTooltipRectStaysInsideVisibleBounds() {
        let anchor = NSRect(x: 760, y: 560, width: 22, height: 22)
        let tooltip = SelectionToolbarState.tooltipRect(
            textSize: NSSize(width: 100, height: 18),
            anchoredTo: anchor,
            inside: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertTrue(NSRect(x: 0, y: 0, width: 800, height: 600).insetBy(dx: 8, dy: 8).contains(tooltip))
        XCTAssertFalse(tooltip.intersects(anchor))
    }

    func testColorSamplerOnlyShowsInsideSelectionWhenNoToolIsActive() {
        let selection = NSRect(x: 100, y: 100, width: 300, height: 200)

        XCTAssertTrue(
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: false,
                hasAnnotations: false,
                pointer: NSPoint(x: 180, y: 180),
                selectionRect: selection
            )
        )

        XCTAssertFalse(
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: true,
                hasAnnotations: false,
                pointer: NSPoint(x: 180, y: 180),
                selectionRect: selection
            )
        )

        XCTAssertFalse(
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: false,
                hasAnnotations: false,
                pointer: NSPoint(x: 90, y: 180),
                selectionRect: selection
            )
        )
    }

    func testColorSamplerAcceptsPointerOnSelectionBorder() {
        let selection = NSRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertTrue(
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: false,
                hasAnnotations: false,
                pointer: NSPoint(x: selection.maxX, y: selection.midY),
                selectionRect: selection
            )
        )
    }

    func testColorSamplerHidesAfterUserHasAnnotations() {
        let selection = NSRect(x: 0, y: 0, width: 400, height: 300)

        XCTAssertFalse(
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: false,
                hasAnnotations: true,
                pointer: NSPoint(x: 120, y: 140),
                selectionRect: selection
            )
        )
    }

    func testColorSamplerRectFollowsPointerAndStaysInVisibleBounds() {
        let visibleBounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let sampler = SelectionToolbarState.colorSamplerRect(
            size: NSSize(width: 168, height: 122),
            pointer: NSPoint(x: 790, y: 30),
            inside: visibleBounds
        )

        XCTAssertTrue(visibleBounds.insetBy(dx: 8, dy: 8).contains(sampler))
        XCTAssertLessThan(sampler.minX, 790)
        XCTAssertGreaterThan(sampler.minY, 30)
    }

    func testColorSamplerRectPrefersPointerLowerRightWhenSpaceAllows() {
        let sampler = SelectionToolbarState.colorSamplerRect(
            size: NSSize(width: 168, height: 122),
            pointer: NSPoint(x: 120, y: 360),
            inside: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(sampler.origin.x, 134)
        XCTAssertEqual(sampler.origin.y, 224)
    }

    func testColorSamplerCanUseInProgressSelectionRect() {
        let currentSelection = NSRect(x: 100, y: 100, width: 120, height: 80)

        XCTAssertTrue(
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: false,
                hasAnnotations: false,
                pointer: NSPoint(x: currentSelection.maxX, y: currentSelection.maxY),
                selectionRect: currentSelection
            )
        )
    }

    func testColorSamplerToggleModeSwitchesBetweenHexAndRgb() {
        XCTAssertEqual(
            SelectionToolbarState.toggledColorSamplerCopyMode(from: .hex),
            .rgb
        )

        XCTAssertEqual(
            SelectionToolbarState.toggledColorSamplerCopyMode(from: .rgb),
            .hex
        )
    }

    func testColorSamplerCopyHintUsesUppercaseCWithSpacingAndHexText() {
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopyHintText, "按 C 复制HEX颜色值")
    }

    func testColorSamplerCopyHintFollowsCopyMode() {
        let l10n = L10n(language: .zhHans)

        XCTAssertEqual(SelectionToolbarState.colorSamplerCopyHintText(for: .hex, l10n: l10n), "按 C 复制HEX颜色值")
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopyHintText(for: .rgb, l10n: l10n), "按 C 复制RGB颜色值")
    }

    func testColorSamplerCopySuccessFeedbackText() {
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopySuccessText, "复制成功")
    }

    func testColorSamplerCopySuccessFeedbackTextColorIsGreen() {
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopySuccessTextColor, NSColor.systemGreen)
    }

    func testColorSamplerCopySuccessFeedbackDurationIsBrief() {
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopySuccessDuration, 1.2, accuracy: 0.01)
    }

    func testColorSamplerCopyShortcutUsesPlainCOnly() {
        XCTAssertTrue(
            SelectionToolbarState.isColorSamplerCopyShortcut(
                charactersIgnoringModifiers: "c",
                modifierFlags: []
            )
        )
        XCTAssertTrue(
            SelectionToolbarState.isColorSamplerCopyShortcut(
                charactersIgnoringModifiers: "C",
                modifierFlags: [.shift]
            )
        )
        XCTAssertFalse(
            SelectionToolbarState.isColorSamplerCopyShortcut(
                charactersIgnoringModifiers: "c",
                modifierFlags: [.command]
            )
        )
    }

    func testColorSamplerInfoTextColorsAreWhite() {
        XCTAssertEqual(SelectionToolbarState.colorSamplerCoordinateTextColor, NSColor.white)
        XCTAssertEqual(SelectionToolbarState.colorSamplerValueTextColor, NSColor.white)
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopyHintTextColor, NSColor.white)
        XCTAssertEqual(SelectionToolbarState.colorSamplerSwitchHintTextColor, NSColor.white)
    }

    func testColorSamplerCopyHintIsPlacedBelowColorSwatch() {
        let infoRect = NSRect(x: 0, y: 0, width: 170, height: 76)
        let swatchRect = NSRect(x: 44, y: 36, width: 18, height: 18)
        let hintRect = SelectionToolbarState.colorSamplerCopyHintRect(
            textSize: NSSize(width: 92, height: 12),
            infoRect: infoRect,
            swatchRect: swatchRect
        )

        XCTAssertLessThanOrEqual(hintRect.maxY, swatchRect.minY - 4)
        XCTAssertEqual(hintRect.midX, infoRect.midX, accuracy: 0.5)
    }

    func testColorSamplerSwitchHintIsBelowCopyHintWithSpacing() {
        let infoRect = NSRect(x: 0, y: 0, width: 170, height: 76)
        let copyRect = NSRect(x: 38, y: 22, width: 94, height: 12)
        let switchRect = SelectionToolbarState.colorSamplerSwitchHintRect(
            textSize: NSSize(width: 106, height: 12),
            infoRect: infoRect,
            copyHintRect: copyRect
        )

        XCTAssertLessThanOrEqual(switchRect.maxY, copyRect.minY - 5)
        XCTAssertEqual(switchRect.midX, infoRect.midX, accuracy: 0.5)
    }

    func testColorSamplerReadsWhitePixelNextToGreenPixel() {
        let pixels: [UInt8] = [
            40, 180, 70, 255,
            255, 255, 255, 255,
        ]
        let cgImage = makeTestImage(
            width: 2,
            height: 1,
            pixels: pixels,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )

        let green = SelectionToolbarState.sampleColor(atPixelX: 0, y: 0, in: cgImage)
        let color = SelectionToolbarState.sampleColor(atPixelX: 1, y: 0, in: cgImage)

        XCTAssertEqual(green?.redComponent ?? -1, CGFloat(40) / 255, accuracy: 0.01)
        XCTAssertEqual(green?.greenComponent ?? -1, CGFloat(180) / 255, accuracy: 0.01)
        XCTAssertEqual(green?.blueComponent ?? -1, CGFloat(70) / 255, accuracy: 0.01)
        XCTAssertEqual(color?.redComponent ?? -1, 1, accuracy: 0.01)
        XCTAssertEqual(color?.greenComponent ?? -1, 1, accuracy: 0.01)
        XCTAssertEqual(color?.blueComponent ?? -1, 1, accuracy: 0.01)
    }

    func testColorSamplerReadsRawRgbWithoutColorSpaceShifting() {
        let pixels: [UInt8] = [
            255, 0, 26, 255,
        ]
        let cgImage = makeTestImage(
            width: 1,
            height: 1,
            pixels: pixels,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )

        let color = SelectionToolbarState.sampleColor(atPixelX: 0, y: 0, in: cgImage)

        XCTAssertEqual(color?.redComponent ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(color?.greenComponent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(color?.blueComponent ?? -1, CGFloat(26) / 255, accuracy: 0.001)
    }

    func testColorSamplerReadsAlphaFirstBitmapWithoutTurningRedYellow() {
        let pixels: [UInt8] = [
            26, 0, 255, 255,
        ]
        let cgImage = makeTestImage(
            width: 1,
            height: 1,
            pixels: pixels,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )

        let color = SelectionToolbarState.sampleColor(atPixelX: 0, y: 0, in: cgImage)

        XCTAssertEqual(color?.redComponent ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(color?.greenComponent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(color?.blueComponent ?? -1, CGFloat(26) / 255, accuracy: 0.001)
    }

    func testColorSamplerDoesNotColorMatchGenericRgbByteSamples() {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 4,
            bitsPerPixel: 32
        )!
        var pixel = [255, 0, 26, 255]
        bitmap.setPixel(&pixel, atX: 0, y: 0)

        let color = SelectionToolbarState.sampleColor(atPixelX: 0, y: 0, in: bitmap)

        XCTAssertEqual(color.map(SelectionToolbarState.colorSamplerHexString(for:)), "#FF001A")
    }

    func testColorSamplerConvertsDisplayP3PixelsToSrgb() {
        let pixels: [UInt8] = [
            45, 51, 234, 255,
        ]
        let cgImage = makeTestImage(
            width: 1,
            height: 1,
            pixels: pixels,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue,
            colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!
        )

        let color = SelectionToolbarState.sampleColor(atPixelX: 0, y: 0, in: cgImage)

        XCTAssertEqual(color?.redComponent ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(color?.greenComponent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(color?.blueComponent ?? -1, CGFloat(26) / 255, accuracy: 0.002)
        XCTAssertEqual(color.map(SelectionToolbarState.colorSamplerHexString(for:)), "#FF001A")
    }

    private func makeTestImage(
        width: Int,
        height: Int,
        pixels: [UInt8],
        bitmapInfo: UInt32,
        colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    ) -> CGImage {
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
