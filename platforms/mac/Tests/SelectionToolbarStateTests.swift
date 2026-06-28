import AppKit
import XCTest
@testable import xxsnap

final class SelectionToolbarStateTests: XCTestCase {
    func testEyedropperSamplesVisibleAnnotationAndCopiesOnlyColor() {
        let background = solidImage(size: NSSize(width: 240, height: 160), color: NSColor(srgbRed: 0.95, green: 0.8, blue: 0.1, alpha: 1))
        let expectedOverlayColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 20, y: 10, width: 80, height: 50),
            style: {
                var style = CaptureAnnotationStyle()
                style.strokeColor = expectedOverlayColor
                style.fillEnabled = true
                style.fillColor = expectedOverlayColor
                return style
            }()
        )
        let point = NSPoint(x: 90, y: 60)
        let selection = NSRect(x: 40, y: 30, width: 120, height: 80)
        let overlayColorHex = SelectionToolbarState.colorSamplerHexString(for: expectedOverlayColor)

        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])

        guard let eyedropperPoint = window.test_mainToolbarButtonPoint(for: .eyedropper) else {
            return XCTFail("Expected eyedropper toolbar button")
        }
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)

        window.test_mouseMoved(to: point)
        XCTAssertTrue(window.test_isColorSamplerVisible)
        XCTAssertEqual(window.test_sampledColorHex, overlayColorHex)
        XCTAssertEqual(window.test_magnifierSampleColorHex(at: point), overlayColorHex)

        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "c")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), overlayColorHex)

        var copyResult: CaptureSelectionResult?
        let copyExpectation = expectation(description: "copy action")
        let copiedWindow = SelectionOverlayWindow(backgroundImage: background) { result in
            copyResult = result
            copyExpectation.fulfill()
        }
        copiedWindow.test_setLockedSelectionRect(selection)
        copiedWindow.test_setAnnotations([annotation])
        copiedWindow.test_mouseDown(at: eyedropperPoint)
        copiedWindow.test_mouseUp(at: eyedropperPoint)
        copiedWindow.test_keyDown(keyCode: 8, charactersIgnoringModifiers: "c", modifierFlags: [.command])
        wait(for: [copyExpectation], timeout: 0.5)
        XCTAssertEqual(copyResult?.action, .copy)

        window.test_updateColorSampler(at: NSPoint(x: selection.maxX + 12, y: selection.midY))
        XCTAssertFalse(window.test_isColorSamplerVisible)
    }

    func testEyedropperSamplesFromTipPointAndMagnifierMatchesTipPixel() throws {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let green = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        let blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let cyan = NSColor(srgbRed: 0, green: 1, blue: 1, alpha: 1)
        let magenta = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        let yellow = NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)
        let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let image = pixelImage(
            width: 3,
            height: 3,
            pixels: [
                [red, green, blue],
                [cyan, magenta, yellow],
                [black, white, blue],
            ]
        )
        let selection = NSRect(x: 0, y: 0, width: 3, height: 3)
        let mousePoint = NSPoint(x: 1.5, y: 1.5)
        let samplePoint = NSPoint(
            x: mousePoint.x + SelectionToolbarState.eyedropperSampleOffset.width,
            y: mousePoint.y + SelectionToolbarState.eyedropperSampleOffset.height
        )
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)

        guard let eyedropperPoint = window.test_mainToolbarButtonPoint(for: .eyedropper) else {
            return XCTFail("Expected eyedropper toolbar button")
        }
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)

        window.test_mouseMoved(to: mousePoint)

        XCTAssertEqual(window.test_sampledPointerPoint, samplePoint)
        XCTAssertEqual(window.test_sampledColorHex, "#FF00FF")
        XCTAssertEqual(window.test_magnifierSampleColorHex(at: samplePoint), "#FF00FF")
        XCTAssertEqual(window.test_magnifierSampleColorHex(at: samplePoint, columnOffset: -1, rowOffset: -1), "#FF0000")
        XCTAssertEqual(window.test_magnifierSampleColorHex(at: samplePoint, columnOffset: 1, rowOffset: 1), "#0000FF")
    }

    func testEyedropperCursorHotSpotAlignsWithSvgTip() {
        XCTAssertEqual(SelectionToolbarState.eyedropperCursorHotSpot.x, 3.6, accuracy: 0.2)
        XCTAssertEqual(SelectionToolbarState.eyedropperCursorHotSpot.y, 20.4, accuracy: 0.2)
    }

    func testMainToolbarPlacesEyedropperImmediatelyBeforeMosaic() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))

        guard
            let markerRect = window.test_mainToolbarButtonRect(for: .marker),
            let eyedropperRect = window.test_mainToolbarButtonRect(for: .eyedropper),
            let mosaicRect = window.test_mainToolbarButtonRect(for: .mosaic)
        else {
            return XCTFail("Expected marker, eyedropper, and mosaic toolbar buttons")
        }

        XCTAssertLessThan(markerRect.midX, eyedropperRect.midX)
        XCTAssertLessThan(eyedropperRect.midX, mosaicRect.midX)
        XCTAssertEqual(eyedropperRect.minX - markerRect.minX, mosaicRect.minX - eyedropperRect.minX, accuracy: 0.5)
        XCTAssertEqual(window.test_symbolName(for: .eyedropper), "toolbar-eyedropper")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "eyedropper"), "取色")
    }

    func testEyedropperResourceIsBundledAndReadableByMacTarget() {
        let url = Bundle.main.url(forResource: "eyedropper", withExtension: "svg")

        XCTAssertNotNil(url)
        XCTAssertGreaterThan((try? Data(contentsOf: XCTUnwrap(url)).count) ?? 0, 0)
    }

    func testClickingEyedropperTogglesExplicitModeAndSelectedState() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))

        guard let point = window.test_mainToolbarButtonPoint(for: .eyedropper) else {
            return XCTFail("Expected eyedropper toolbar button")
        }

        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)
        XCTAssertTrue(window.test_isEyedropperToolActive)
        XCTAssertTrue(window.test_eyedropperToolbarButtonIsSelected)
        XCTAssertNil(window.test_optionsToolbarRect)
        XCTAssertNil(window.test_optionsToolbarMode)
        XCTAssertNil(window.test_currentShapeKind)

        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)
        XCTAssertFalse(window.test_isEyedropperToolActive)
        XCTAssertFalse(window.test_eyedropperToolbarButtonIsSelected)
    }

    func testClickingTextToolTogglesTextModeAndSelectedState() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))

        guard let point = window.test_mainToolbarButtonPoint(for: .text) else {
            return XCTFail("Expected text toolbar button")
        }

        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)
        XCTAssertTrue(window.test_isTextToolActive)
        XCTAssertTrue(window.test_textToolbarButtonIsSelected)
        XCTAssertEqual(window.test_optionsToolbarMode, .text)
        XCTAssertNil(window.test_currentShapeKind)

        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)
        XCTAssertFalse(window.test_isTextToolActive)
        XCTAssertFalse(window.test_textToolbarButtonIsSelected)
        XCTAssertNil(window.test_optionsToolbarMode)
    }

    func testTextToolCreatesEditableAnnotationAndCommitsTypedText() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .text)
        XCTAssertTrue(window.test_isEditingTextAnnotation)
        XCTAssertEqual(window.test_textAnnotation(at: 0)?.text, "")

        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "H")
        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "i")
        window.test_keyDown(keyCode: 36, charactersIgnoringModifiers: "\r")

        XCTAssertEqual(window.test_selectedAnnotationKind, .text)
        XCTAssertFalse(window.test_isEditingTextAnnotation)
        XCTAssertEqual(window.test_textAnnotation(at: 0)?.text, "Hi")
        XCTAssertGreaterThanOrEqual(window.test_annotationRect(at: 0)?.width ?? 0, 160)
    }

    func testTextToolReopensExistingAnnotationFromBodyClick() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "H")
        window.test_keyDown(keyCode: 36, charactersIgnoringModifiers: "\r")

        guard let textRect = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected text annotation")
        }

        window.test_mouseDown(at: NSPoint(x: 100 + textRect.midX, y: 100 + textRect.midY))
        window.test_mouseUp(at: NSPoint(x: 100 + textRect.midX, y: 100 + textRect.midY))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .text)
        XCTAssertTrue(window.test_isEditingTextAnnotation)
        XCTAssertEqual(window.test_textAnnotation(at: 0)?.text, "H")
    }

    func testEmptyTextDraftIsDiscardedOnEscape() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertTrue(window.test_isEditingTextAnnotation)

        window.test_keyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}")

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertFalse(window.test_isEditingTextAnnotation)
        XCTAssertNil(window.test_selectedAnnotationKind)
    }

    func testFinishingCaptureCommitsOrDiscardsActiveTextEdit() {
        var emptyResult: CaptureSelectionResult?
        let emptyExpectation = expectation(description: "empty text draft result")
        let emptyWindow = SelectionOverlayWindow(backgroundImage: nil) { result in
            emptyResult = result
            emptyExpectation.fulfill()
        }
        emptyWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        emptyWindow.test_activateTextTool()
        emptyWindow.test_mouseDown(at: NSPoint(x: 140, y: 150))
        emptyWindow.test_mouseUp(at: NSPoint(x: 140, y: 150))
        emptyWindow.test_keyDown(keyCode: 8, charactersIgnoringModifiers: "c", modifierFlags: [.command])
        wait(for: [emptyExpectation], timeout: 0.5)
        XCTAssertEqual(emptyResult?.annotations.count, 0)

        var textResult: CaptureSelectionResult?
        let textExpectation = expectation(description: "non-empty text result")
        let textWindow = SelectionOverlayWindow(backgroundImage: nil) { result in
            textResult = result
            textExpectation.fulfill()
        }
        textWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        textWindow.test_activateTextTool()
        textWindow.test_mouseDown(at: NSPoint(x: 140, y: 150))
        textWindow.test_mouseUp(at: NSPoint(x: 140, y: 150))
        textWindow.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "x")
        textWindow.test_keyDown(keyCode: 8, charactersIgnoringModifiers: "c", modifierFlags: [.command])
        wait(for: [textExpectation], timeout: 0.5)
        XCTAssertEqual(textResult?.annotations.count, 1)
        XCTAssertEqual(textResult?.annotations.first?.kind, .text)
        XCTAssertEqual(textResult?.annotations.first?.text, "x")
    }

    func testActivatingAnotherToolExitsEyedropperMode() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))

        guard let eyedropperPoint = window.test_mainToolbarButtonPoint(for: .eyedropper) else {
            return XCTFail("Expected eyedropper toolbar button")
        }

        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)
        XCTAssertTrue(window.test_isEyedropperToolActive)

        window.test_activateShapeTool(.marker)

        XCTAssertFalse(window.test_isEyedropperToolActive)
        XCTAssertFalse(window.test_eyedropperToolbarButtonIsSelected)
        XCTAssertEqual(window.test_currentShapeKind, .marker)
        XCTAssertEqual(window.test_optionsToolbarMode, .marker)
    }

    func testEyedropperCursorOverridesArrowAnnotationHoverInsideSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let arrowLine = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        guard let eyedropperPoint = window.test_mainToolbarButtonPoint(for: .eyedropper) else {
            return XCTFail("Expected eyedropper toolbar button")
        }

        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)

        let start = NSPoint(x: 100 + arrowLine.start.x, y: 100 + arrowLine.start.y)
        let end = NSPoint(x: 100 + arrowLine.end.x, y: 100 + arrowLine.end.y)
        let body = NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)

        XCTAssertTrue(window.test_isEyedropperToolActive)
        XCTAssertEqual(window.test_cursorStyle(at: start), .eyedropper)
        XCTAssertEqual(window.test_cursorStyle(at: body), .eyedropper)
        XCTAssertEqual(window.test_cursorStyle(at: end), .eyedropper)
    }

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

    func testOverlayWindowResizesSelectionFromBorderWhileMosaicToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicRectangle)

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

    func testOverlayWindowUsesArrowCursorOnMeasurementToolbarWhileShapeToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        guard let cornerPoint = window.test_measurementControlPoint(.cornerStyle),
              let refreshPoint = window.test_measurementControlPoint(.refresh) else {
            return XCTFail("Expected measurement toolbar points")
        }

        XCTAssertEqual(window.test_cursorStyle(at: cornerPoint), .arrow)
        XCTAssertEqual(window.test_cursorStyle(at: refreshPoint), .arrow)

        window.test_activateShapeTool(.rectangle)
        XCTAssertEqual(window.test_cursorStyle(at: cornerPoint), .arrow)
        XCTAssertEqual(window.test_cursorStyle(at: refreshPoint), .arrow)
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

    func testOverlayWindowUsesActiveDrawingCursorOutsideSelectionAwayFromBorder() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let outsidePoint = NSPoint(x: selection.maxX + 40, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        let cases: [(CaptureAnnotationKind, SelectionToolbarState.OverlayCursorStyle)] = [
            (.rectangle, .crosshair),
            (.arrowLine, .crosshair),
            (.brush, .brush),
            (.marker, .marker)
        ]

        for (shape, expectedCursor) in cases {
            window.test_activateShapeTool(shape)
            XCTAssertEqual(window.test_cursorStyle(at: outsidePoint), expectedCursor)
        }
    }

    func testOverlayWindowActivatesMosaicTool() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        XCTAssertEqual(window.test_optionsToolbarMode, .mosaic)
        XCTAssertEqual(window.test_currentShapeKind, .mosaicRectangle)
        XCTAssertEqual(window.test_mosaicRedactionType, .pixelMosaic)
        XCTAssertEqual(window.test_mosaicRedactionValue(for: .gaussianBlur), 8)
        XCTAssertEqual(window.test_mosaicRedactionValue(for: .pixelMosaic), 8)
    }

    func testOverlayWindowUsesMosaicRectangleDrawingCursorOutsideSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let outsidePoint = NSPoint(x: 80, y: selection.midY)
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicRectangle)

        XCTAssertEqual(window.test_cursorStyle(at: outsidePoint), .crosshair)

        guard let toolbarPoint = window.test_mainToolbarDragPoint() else {
            return XCTFail("Expected toolbar drag point")
        }

        XCTAssertEqual(window.test_cursorStyle(at: outsidePoint), .crosshair)
        XCTAssertEqual(window.test_cursorStyle(at: toolbarPoint), .arrow)
    }

    func testOverlayWindowUsesSelectionResizeCursorOnMosaicBorder() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let rightBorderPoint = NSPoint(x: selection.maxX + 10, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        window.test_toggleShapeTool(.mosaicRectangle)
        XCTAssertEqual(window.test_cursorStyle(at: rightBorderPoint), .resizeLeftRight)

        window.test_activateShapeTool(.mosaicStroke)
        XCTAssertEqual(window.test_cursorStyle(at: rightBorderPoint), .resizeLeftRight)
    }

    func testOverlayWindowMosaicToolReopensWithPixelMosaicRedaction() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        guard let redactionTypePoint = window.test_mosaicRedactionTypePoint(.pixelMosaic) else {
            return XCTFail("Expected mosaic redaction type point")
        }

        window.test_mouseDown(at: redactionTypePoint)
        window.test_mouseUp(at: redactionTypePoint)
        XCTAssertEqual(window.test_mosaicRedactionType, .gaussianBlur)

        window.test_toggleShapeTool(.brush)
        window.test_toggleShapeTool(.mosaicRectangle)

        XCTAssertEqual(window.test_mosaicRedactionType, .pixelMosaic)
        XCTAssertEqual(window.test_currentShapeKind, .mosaicRectangle)
    }

    func testOverlayWindowMosaicRedactionTypeTooltipRefreshesImmediatelyAfterToggle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        guard let redactionTypePoint = window.test_mosaicRedactionTypePoint(.pixelMosaic) else {
            return XCTFail("Expected mosaic redaction type point")
        }

        window.test_mouseMoved(to: redactionTypePoint)
        XCTAssertEqual(window.test_hoveredTooltipText, "马赛克")

        window.test_mouseDown(at: redactionTypePoint)
        XCTAssertEqual(window.test_mosaicRedactionType, .gaussianBlur)
        XCTAssertEqual(window.test_hoveredTooltipText, "高斯")

        window.test_mouseDown(at: redactionTypePoint)
        XCTAssertEqual(window.test_mosaicRedactionType, .pixelMosaic)
        XCTAssertEqual(window.test_hoveredTooltipText, "马赛克")
    }

    func testOverlayWindowMosaicOptionsKeepPerTypeValuesWithoutShapeModeButtons() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        guard
            let redactionTypePoint = window.test_mosaicRedactionTypePoint(.pixelMosaic),
            let valueMaximumPoint = window.test_mosaicValueIncrementPoint(),
            let valueMinimumPoint = window.test_mosaicValueDecrementPoint()
        else {
            return XCTFail("Expected mosaic option points")
        }

        XCTAssertNil(window.test_mosaicRectangleOptionPoint())
        XCTAssertNil(window.test_optionsStrokeWidthPoint(at: 0))
        XCTAssertEqual(window.test_currentShapeKind, .mosaicRectangle)

        window.test_mouseDown(at: redactionTypePoint)
        window.test_mouseUp(at: redactionTypePoint)
        XCTAssertEqual(window.test_mosaicRedactionType, .gaussianBlur)
        XCTAssertEqual(window.test_mosaicRedactionValue(for: .gaussianBlur), 8)

        window.test_mouseDown(at: valueMaximumPoint)
        window.test_mouseUp(at: valueMaximumPoint)
        XCTAssertEqual(window.test_mosaicRedactionValue(for: .gaussianBlur), 20)

        window.test_mouseDown(at: valueMinimumPoint)
        window.test_mouseUp(at: valueMinimumPoint)
        XCTAssertEqual(window.test_mosaicRedactionValue(for: .gaussianBlur), 5)

        window.test_mouseDown(at: redactionTypePoint)
        window.test_mouseUp(at: redactionTypePoint)
        XCTAssertEqual(window.test_mosaicRedactionType, .pixelMosaic)
        XCTAssertEqual(window.test_mosaicRedactionValue(for: .pixelMosaic), 8)
    }

    func testOverlayWindowMosaicValueSliderClampsToMaximum() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        guard
            let sliderPoint = window.test_mosaicValueIncrementPoint(),
            let minimumPoint = window.test_mosaicValueDecrementPoint()
        else {
            return XCTFail("Expected mosaic value slider points")
        }

        window.test_mouseDown(at: sliderPoint)
        window.test_mouseDragged(to: NSPoint(x: sliderPoint.x + 40, y: sliderPoint.y))
        window.test_mouseUp(at: NSPoint(x: sliderPoint.x + 40, y: sliderPoint.y))

        XCTAssertEqual(window.test_mosaicRedactionValue(for: .pixelMosaic), 20)

        window.test_mouseDown(at: minimumPoint)
        window.test_mouseDragged(to: NSPoint(x: minimumPoint.x - 40, y: minimumPoint.y))
        window.test_mouseUp(at: NSPoint(x: minimumPoint.x - 40, y: minimumPoint.y))

        XCTAssertEqual(window.test_mosaicRedactionValue(for: .pixelMosaic), 5)
    }

    func testOverlayWindowMosaicValueSliderSkipsSameValuePreviewInvalidation() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicRectangle)

        window.test_mouseDown(at: NSPoint(x: 60, y: 55))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        window.test_mouseUp(at: NSPoint(x: 140, y: 125))

        let sliderPoint = try XCTUnwrap(window.test_mosaicValueInputPoint())
        window.test_mouseDown(at: sliderPoint)

        let annotation = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 0)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 0)),
            mosaicRedaction: try XCTUnwrap(window.test_mosaicRedaction(at: 0))
        )
        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [annotation]))
        XCTAssertTrue(window.test_hasMosaicCompositeCache)

        window.test_mouseDragged(to: sliderPoint)

        XCTAssertTrue(window.test_hasMosaicCompositeCache)
        window.test_mouseUp(at: sliderPoint)
    }

    func testOverlayWindowMosaicRectangleRotationReusesPreviewCompositeCache() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 180))
        window.test_toggleShapeTool(.mosaicRectangle)

        window.test_mouseDown(at: NSPoint(x: 60, y: 55))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        window.test_mouseUp(at: NSPoint(x: 140, y: 125))
        XCTAssertNotNil(window.test_renderedOverlayImage())
        let renderCountBeforeRotation = window.test_mosaicCompositeRenderCount

        let rotationPoint = try XCTUnwrap(window.test_mosaicRectangleRotationHandlePoint())
        window.test_mouseDown(at: rotationPoint)
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 24, y: rotationPoint.y + 18))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicCompositeRenderCount, renderCountBeforeRotation)
        window.test_mouseUp(at: NSPoint(x: rotationPoint.x + 24, y: rotationPoint.y + 18))
    }

    func testOverlayWindowDraggingMosaicValueUsesLocalPreviewWithoutFullCompositeRender() throws {
        let image = gradientImage(size: NSSize(width: 260, height: 180))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.pixelMosaic))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: NSPoint(x: 52, y: 48))
        window.test_mouseDragged(to: NSPoint(x: 134, y: 104))
        window.test_mouseUp(at: NSPoint(x: 134, y: 104))

        XCTAssertNotNil(window.test_renderedOverlayImage())
        let renderCountBeforeDrag = window.test_mosaicCompositeRenderCount
        let sliderPoint = try XCTUnwrap(window.test_mosaicValueIncrementPoint())

        window.test_mouseDown(at: sliderPoint)
        window.test_mouseDragged(to: NSPoint(x: sliderPoint.x + 20, y: sliderPoint.y))
        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())

        let overlayPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: NSPoint(x: 92, y: 76)))
        let originalPixel = try XCTUnwrap(rgbaPixel(in: image, at: NSPoint(x: 92, y: 76)))
        XCTAssertTrue(pixelDiffers(overlayPixel, originalPixel))
        XCTAssertEqual(window.test_mosaicCompositeRenderCount, renderCountBeforeDrag)
        window.test_mouseUp(at: NSPoint(x: sliderPoint.x + 20, y: sliderPoint.y))
    }

    func testOverlayWindowMosaicRectangleRotationHandleWinsOutsideSelection() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicRectangle)

        window.test_mouseDown(at: NSPoint(x: 60, y: 55))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        window.test_mouseUp(at: NSPoint(x: 140, y: 125))

        let rotationPoint = try XCTUnwrap(window.test_mosaicRectangleRotationHandlePoint())
        XCTAssertGreaterThan(rotationPoint.y, selection.maxY)
        window.test_mouseDown(at: rotationPoint)
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 24, y: rotationPoint.y + 18))
        window.test_mouseUp(at: NSPoint(x: rotationPoint.x + 24, y: rotationPoint.y + 18))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertGreaterThan(abs(window.test_annotationRotationAngle(at: 0) ?? 0), 0.05)
    }

    func testOverlayWindowMosaicToolbarHidesShapeModeControls() {
        var refreshCallCount = 0
        let window = SelectionOverlayWindow(
            backgroundImage: nil,
            refreshHandler: {
                refreshCallCount += 1
                return nil
            }
        ) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        XCTAssertEqual(refreshCallCount, 0)
        XCTAssertNil(window.test_mosaicRectangleOptionPoint())
        XCTAssertNil(window.test_optionsStrokeWidthPoint(at: 0))
        XCTAssertEqual(window.test_currentShapeKind, .mosaicRectangle)
    }

    func testOverlayWindowMosaicLargeDotDoesNotTriggerRefreshAndCanDraw() {
        var refreshCallCount = 0
        let window = SelectionOverlayWindow(
            backgroundImage: nil,
            refreshHandler: {
                refreshCallCount += 1
                return nil
            }
        ) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)
        window.test_setCurrentStrokeWidth(40)

        XCTAssertEqual(refreshCallCount, 0)
        XCTAssertEqual(window.test_currentShapeKind, .mosaicStroke)
        XCTAssertEqual(window.test_currentStyle?.strokeWidth, 40)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 180))
        window.test_mouseUp(at: NSPoint(x: 210, y: 180))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_annotationStyle(at: 0)?.strokeWidth, 40)
    }

    func testOverlayWindowMosaicDotClickCreatesDotRedaction() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_annotationStyle(at: 0)?.strokeWidth, 30)
        XCTAssertEqual(window.test_mosaicStroke(at: 0)?.points.count, 1)
    }

    func testOverlayWindowMosaicLargeDotKeepsShortHorizontalStroke() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)
        window.test_setCurrentStrokeWidth(40)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 150))
        window.test_mouseUp(at: NSPoint(x: 210, y: 150))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_annotationStyle(at: 0)?.strokeWidth, 40)
        XCTAssertEqual(window.test_mosaicStroke(at: 0)?.points.count ?? 0, 2)
    }

    func testOverlayWindowMosaicStrokeCollectsDraggedPoints() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 170, y: 165))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 180))
        window.test_mouseUp(at: NSPoint(x: 240, y: 200))

        guard let stroke = window.test_mosaicStroke(at: 0) else {
            return XCTFail("Expected mosaic stroke")
        }
        XCTAssertGreaterThan(stroke.points.count, 2)
    }

    func testOverlayWindowMosaicStrokeCanStartOutsideSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 80, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 160))
        window.test_mouseUp(at: NSPoint(x: 180, y: 170))

        guard let stroke = window.test_mosaicStroke(at: 0) else {
            return XCTFail("Expected mosaic stroke")
        }

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertLessThan(stroke.points.first?.x ?? 0, 0)
        XCTAssertGreaterThan(stroke.points.last?.x ?? 0, 0)
    }

    func testOverlayWindowMosaicStrokeResizesSelectionFromBorder() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: selection.minX, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 150, y: 160))
        window.test_mouseUp(at: NSPoint(x: 150, y: 160))

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertEqual(window.test_lockedSelectionRect?.minX, 150)
        XCTAssertEqual(window.test_lockedSelectionRect?.width, 250)
    }

    func testOverlayWindowMosaicStrokeShiftDrawsAxisLockedLine() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 190, y: 162), modifierFlags: [.shift])
        window.test_mouseUp(at: NSPoint(x: 190, y: 162), modifierFlags: [.shift])

        guard let stroke = window.test_mosaicStroke(at: 0) else {
            return XCTFail("Expected mosaic stroke")
        }
        XCTAssertEqual(stroke.points.count, 2)
        XCTAssertEqual(stroke.points[0].y, stroke.points[1].y, accuracy: 0.001)
        XCTAssertGreaterThan(stroke.points[1].x, stroke.points[0].x)
    }

    func testOverlayWindowMosaicStrokeDoesNotMoveExistingStroke() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 150))
        window.test_mouseUp(at: NSPoint(x: 210, y: 150))

        let original = window.test_mosaicStroke(at: 0)?.points
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 200, y: 170))
        window.test_mouseUp(at: NSPoint(x: 200, y: 170))

        guard let before = original, let after = window.test_mosaicStroke(at: 0)?.points else {
            return XCTFail("Expected mosaic stroke")
        }
        XCTAssertEqual(window.test_annotationCount, 2)
        XCTAssertEqual(after.first?.x ?? 0, before.first?.x ?? 0, accuracy: 0.001)
        XCTAssertEqual(after.first?.y ?? 0, before.first?.y ?? 0, accuracy: 0.001)
    }

    func testOverlayWindowMosaicRectangleCanMoveResizeAndRotate() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicRectangle)
        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected mosaic rectangle")
        }
        XCTAssertEqual(window.test_selectedAnnotationKind, .mosaicRectangle)
        XCTAssertTrue(window.test_selectedAnnotationShowsOutline)

        window.test_mouseDown(at: NSPoint(x: 160, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 190, y: 170))
        window.test_mouseUp(at: NSPoint(x: 190, y: 170))

        guard let moved = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected moved mosaic rectangle")
        }
        XCTAssertEqual(moved.origin.x, original.origin.x + 30, accuracy: 0.1)
        XCTAssertEqual(moved.origin.y, original.origin.y + 20, accuracy: 0.1)

        guard let resizePoint = window.test_shapeResizeHandlePoint(.bottomRight) else {
            return XCTFail("Expected resize handle")
        }
        window.test_mouseDown(at: resizePoint)
        window.test_mouseDragged(to: NSPoint(x: resizePoint.x + 30, y: resizePoint.y - 20))
        window.test_mouseUp(at: NSPoint(x: resizePoint.x + 30, y: resizePoint.y - 20))

        guard let resized = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected resized mosaic rectangle")
        }
        XCTAssertGreaterThan(resized.width, moved.width)
        XCTAssertGreaterThan(resized.height, moved.height)

        guard let rotationPoint = window.test_mosaicRectangleRotationHandlePoint() else {
            return XCTFail("Expected rotation handle")
        }
        window.test_mouseDown(at: rotationPoint)
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 30, y: rotationPoint.y + 25))
        window.test_mouseUp(at: NSPoint(x: rotationPoint.x + 30, y: rotationPoint.y + 25))

        XCTAssertGreaterThan(abs(window.test_annotationRotationAngle(at: 0) ?? 0), 0.05)
        XCTAssertEqual(window.test_mosaicRectangleRotationHandleGlyph(), .refreshDot)
    }

    func testOverlayWindowMosaicRectangleCanStartOutsideSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicRectangle)
        window.test_mouseDown(at: NSPoint(x: 80, y: 130))
        window.test_mouseDragged(to: NSPoint(x: 160, y: 190))
        window.test_mouseUp(at: NSPoint(x: 160, y: 190))

        guard let rect = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected mosaic rectangle")
        }

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertLessThan(rect.minX, 0)
        XCTAssertGreaterThan(rect.maxX, 0)
    }

    func testOverlayWindowMosaicStrokeDraftUsesLiveCompositePreviewPath() {
        let image = NSImage(size: NSSize(width: 500, height: 400))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 500, height: 400).fill()
        image.unlockFocus()

        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))

        XCTAssertTrue(window.test_mosaicStrokeDraftUsesLiveCompositePreviewPath)

        window.test_mouseUp(at: NSPoint(x: 220, y: 180))
    }

    func testOverlayWindowMosaicRectangleDraftUsesLiveCompositePreviewPath() {
        let image = NSImage(size: NSSize(width: 500, height: 400))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 500, height: 400).fill()
        image.unlockFocus()

        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicRectangle)
        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))

        XCTAssertTrue(window.test_mosaicRectangleDraftUsesLivePreviewPath)

        window.test_mouseUp(at: NSPoint(x: 220, y: 180))
    }

    func testOverlayWindowMosaicStrokeDraftUsesLocalPreviewTile() {
        let image = NSImage(size: NSSize(width: 500, height: 400))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 500, height: 400).fill()
        image.unlockFocus()

        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let stroke = CaptureMosaicStroke(points: [
            NSPoint(x: 40, y: 40),
            NSPoint(x: 120, y: 80),
        ])
        let draft = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: stroke.boundingRect,
            style: style,
            mosaicStroke: stroke,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        guard let drawRect = window.test_mosaicDraftPreviewDrawRect(for: draft) else {
            return XCTFail("Expected mosaic stroke preview draw rect")
        }

        XCTAssertLessThan(drawRect.width, image.size.width)
        XCTAssertLessThan(drawRect.height, image.size.height)
        XCTAssertLessThan(drawRect.minX, 140)
        XCTAssertLessThan(drawRect.minY, 140)
        XCTAssertGreaterThan(drawRect.maxX, 220)
        XCTAssertGreaterThan(drawRect.maxY, 180)
    }

    func testOverlayWindowMosaicRectangleDraftUsesLocalPreviewTile() {
        let image = NSImage(size: NSSize(width: 500, height: 400))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 500, height: 400).fill()
        image.unlockFocus()

        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 40, y: 40, width: 80, height: 40),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        guard let drawRect = window.test_mosaicDraftPreviewDrawRect(for: draft) else {
            return XCTFail("Expected mosaic rectangle preview draw rect")
        }

        XCTAssertLessThan(drawRect.width, image.size.width)
        XCTAssertLessThan(drawRect.height, image.size.height)
        XCTAssertLessThan(drawRect.minX, 140)
        XCTAssertLessThan(drawRect.minY, 140)
        XCTAssertGreaterThan(drawRect.maxX, 220)
        XCTAssertGreaterThan(drawRect.maxY, 180)
    }

    func testOverlayWindowMosaicRectangleDraftPreservesExistingDotMosaic() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 88, y: 82))
        window.test_mouseUp(at: NSPoint(x: 88, y: 82))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 40, y: 35, width: 80, height: 70),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        guard let preview = window.test_mosaicDraftPreview(for: draft) else {
            return XCTFail("Expected mosaic rectangle preview")
        }
        let originalCrop = try XCTUnwrap(croppedImage(image, to: preview.drawRect))
        let originalOnlyPreview = CaptureAnnotationRenderer.redactedPreview(
            image: originalCrop,
            redaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        XCTAssertNotEqual(try rgbaBytes(in: preview.image), try rgbaBytes(in: originalOnlyPreview))
    }

    func testOverlayWindowMosaicRectangleDraftFullyRedactsOverExistingDotMosaic() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 88, y: 82))
        window.test_mouseUp(at: NSPoint(x: 88, y: 82))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 40, y: 35, width: 80, height: 70),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let originalCrop = try XCTUnwrap(croppedImage(image, to: preview.drawRect))

        for point in [
            NSPoint(x: 72, y: 60),
            NSPoint(x: 88, y: 82),
            NSPoint(x: 112, y: 92),
            NSPoint(x: 132, y: 122),
        ] {
            let localPoint = NSPoint(x: point.x - preview.drawRect.minX, y: point.y - preview.drawRect.minY)
            let previewPixel = try XCTUnwrap(rgbaPixel(in: preview.image, at: localPoint))
            let originalPixel = try XCTUnwrap(rgbaPixel(in: originalCrop, at: localPoint))
            XCTAssertTrue(pixelDiffers(previewPixel, originalPixel), "Expected draft mosaic to redact \(point)")
        }
    }

    func testOverlayWindowRenderedMosaicRectangleDoesNotRevealExistingDotMosaic() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let originalClearPixel = try XCTUnwrap(rgbaPixel(in: image, at: NSPoint(x: 112, y: 92)))

        let combinedWindow = SelectionOverlayWindow(backgroundImage: image) { _ in }
        combinedWindow.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        combinedWindow.test_toggleShapeTool(.mosaicStroke)
        combinedWindow.test_mouseDown(at: NSPoint(x: 88, y: 82))
        combinedWindow.test_mouseUp(at: NSPoint(x: 88, y: 82))
        let typePoint = try XCTUnwrap(combinedWindow.test_mosaicRedactionTypePoint(.gaussianBlur))
        combinedWindow.test_mouseDown(at: typePoint)
        combinedWindow.test_mouseUp(at: typePoint)
        combinedWindow.test_toggleShapeTool(.mosaicRectangle)
        combinedWindow.test_mouseDown(at: NSPoint(x: 60, y: 55))
        combinedWindow.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        combinedWindow.test_mouseUp(at: NSPoint(x: 140, y: 125))
        let combinedImage = try XCTUnwrap(combinedWindow.test_renderedOverlayImage())
        let combinedDotPixel = try XCTUnwrap(rgbaPixel(in: combinedImage, at: NSPoint(x: 88, y: 82)))
        let combinedRectanglePixel = try XCTUnwrap(rgbaPixel(in: combinedImage, at: NSPoint(x: 112, y: 92)))

        let originalDotPixel = try XCTUnwrap(rgbaPixel(in: image, at: NSPoint(x: 88, y: 82)))
        XCTAssertTrue(pixelDiffers(combinedDotPixel, originalDotPixel))
        XCTAssertTrue(pixelDiffers(combinedRectanglePixel, originalClearPixel))
    }

    func testOverlayWindowRenderedDotAndRectangleMosaicOverlapKeepsStackedRedaction() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160), squareSize: 4)
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let overlapPoint = NSPoint(x: 88, y: 82)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicStroke)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: overlapPoint)
        window.test_mouseUp(at: overlapPoint)

        window.test_toggleShapeTool(.mosaicRectangle)
        window.test_mouseDown(at: NSPoint(x: 60, y: 55))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        window.test_mouseUp(at: NSPoint(x: 140, y: 125))

        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let style = try XCTUnwrap(window.test_annotationStyle(at: 1))
        let rectangleRedaction = try XCTUnwrap(window.test_mosaicRedaction(at: 1))
        let rectangleOnly = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [
                overlayMosaicAnnotation(CaptureAnnotation(
                    kind: .mosaicRectangle,
                    rect: try XCTUnwrap(window.test_annotationRect(at: 1)),
                    style: style,
                    mosaicRedaction: rectangleRedaction
                ), selection: selection),
            ]
        )

        let overlayPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: overlapPoint))
        let originalPixel = try XCTUnwrap(rgbaPixel(in: image, at: overlapPoint))
        let rectangleOnlyPixel = try XCTUnwrap(rgbaPixel(in: rectangleOnly, at: overlapPoint))

        XCTAssertTrue(pixelDiffers(overlayPixel, originalPixel))
        XCTAssertTrue(pixelDiffers(overlayPixel, rectangleOnlyPixel))
    }

    func testOverlayWindowSwitchingFromSelectedMosaicRectangleToDotDoesNotMutateRectangleRedaction() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: NSPoint(x: 60, y: 55))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        window.test_mouseUp(at: NSPoint(x: 140, y: 125))

        XCTAssertEqual(window.test_selectedAnnotationKind, .mosaicRectangle)
        let originalRectangleRedaction = try XCTUnwrap(window.test_mosaicRedaction(at: 0))

        window.test_toggleShapeTool(.mosaicStroke)
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        XCTAssertEqual(window.test_mosaicRedaction(at: 0), originalRectangleRedaction)
        XCTAssertEqual(window.test_currentShapeKind, .mosaicStroke)
    }

    func testOverlayWindowRenderedOverlappingMosaicRectanglesDoNotRevealOriginalPixels() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicRectangle)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: NSPoint(x: 52, y: 48))
        window.test_mouseDragged(to: NSPoint(x: 134, y: 104))
        window.test_mouseUp(at: NSPoint(x: 134, y: 104))

        window.test_mouseDown(at: NSPoint(x: 164, y: 124))
        window.test_mouseDragged(to: NSPoint(x: 84, y: 68))
        window.test_mouseUp(at: NSPoint(x: 84, y: 68))

        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let firstRedaction = try XCTUnwrap(window.test_mosaicRedaction(at: 0))
        let secondStyle = try XCTUnwrap(window.test_annotationStyle(at: 1))
        let secondRedaction = try XCTUnwrap(window.test_mosaicRedaction(at: 1))
        XCTAssertEqual(firstRedaction.type, .gaussianBlur)
        XCTAssertEqual(secondRedaction.type, .gaussianBlur)
        let secondAnnotation = overlayMosaicAnnotation(CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 1)),
            style: secondStyle,
            mosaicRedaction: secondRedaction
        ), selection: selection)
        let secondOnly = CaptureAnnotationRenderer.render(image: image, annotations: [secondAnnotation])

        let overlapPoint = NSPoint(x: 100, y: 84)
        let overlayPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: overlapPoint))
        let originalPixel = try XCTUnwrap(rgbaPixel(in: image, at: overlapPoint))
        let secondOnlyPixel = try XCTUnwrap(rgbaPixel(in: secondOnly, at: overlapPoint))

        XCTAssertTrue(pixelDiffers(overlayPixel, originalPixel))
        XCTAssertTrue(pixelDiffers(overlayPixel, secondOnlyPixel))
    }

    func testOverlayWindowMosaicDraftOverMultipleExistingRectanglesKeepsPreviousRedaction() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicRectangle)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: NSPoint(x: 52, y: 48))
        window.test_mouseDragged(to: NSPoint(x: 134, y: 104))
        window.test_mouseUp(at: NSPoint(x: 134, y: 104))

        window.test_mouseDown(at: NSPoint(x: 92, y: 112))
        window.test_mouseDragged(to: NSPoint(x: 170, y: 136))
        window.test_mouseUp(at: NSPoint(x: 170, y: 136))

        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 64, y: 48, width: 80, height: 56),
            style: try XCTUnwrap(window.test_annotationStyle(at: 0)),
            mosaicRedaction: try XCTUnwrap(window.test_mosaicRedaction(at: 0))
        )
        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let draftOnly = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [overlayMosaicAnnotation(draft, selection: selection)]
        )

        let overlapPoint = NSPoint(x: 100, y: 84)
        let previewPoint = NSPoint(
            x: overlapPoint.x - preview.drawRect.minX,
            y: overlapPoint.y - preview.drawRect.minY
        )
        let previewPixel = try XCTUnwrap(rgbaPixel(in: preview.image, at: previewPoint))
        let originalPixel = try XCTUnwrap(rgbaPixel(in: image, at: overlapPoint))
        let draftOnlyPixel = try XCTUnwrap(rgbaPixel(in: draftOnly, at: overlapPoint))

        XCTAssertTrue(pixelDiffers(previewPixel, originalPixel))
        XCTAssertTrue(pixelDiffers(previewPixel, draftOnlyPixel))
    }

    func testOverlayWindowGaussianDotDraftStacksAboveExistingPixelDotMosaic() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160), squareSize: 4)
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let dotPoint = NSPoint(x: 88, y: 82)
        let localDotPoint = NSPoint(x: dotPoint.x - selection.minX, y: dotPoint.y - selection.minY)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: dotPoint)
        window.test_mouseUp(at: dotPoint)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        var style = try XCTUnwrap(window.test_currentStyle)
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: NSRect(origin: localDotPoint, size: .zero),
            style: style,
            mosaicStroke: CaptureMosaicStroke(points: [localDotPoint]),
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let first = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: NSRect(origin: dotPoint, size: .zero),
            style: style,
            mosaicStroke: CaptureMosaicStroke(points: [dotPoint]),
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )
        let firstComposite = CaptureAnnotationRenderer.render(image: image, annotations: [first])
        let originalCrop = try XCTUnwrap(croppedImage(image, to: preview.drawRect))
        let firstCrop = try XCTUnwrap(croppedImage(firstComposite, to: preview.drawRect))

        XCTAssertTrue(try imageBytesDiffer(preview.image, originalCrop))
        XCTAssertTrue(try imageBytesDiffer(preview.image, firstCrop))
    }

    func testOverlayWindowRectangleDraftStacksAboveExistingDotMosaic() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160), squareSize: 4)
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let dotPoint = NSPoint(x: 88, y: 82)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicStroke)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: dotPoint)
        window.test_mouseUp(at: dotPoint)

        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        var style = try XCTUnwrap(window.test_currentStyle)
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 40, y: 35, width: 80, height: 70),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )

        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let first = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: NSRect(origin: dotPoint, size: .zero),
            style: style,
            mosaicStroke: CaptureMosaicStroke(points: [dotPoint]),
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )
        let second = overlayMosaicAnnotation(draft, selection: selection)
        let firstComposite = CaptureAnnotationRenderer.render(image: image, annotations: [first])
        let expected = CaptureAnnotationRenderer.render(image: firstComposite, annotations: [second])
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: preview.drawRect))
        let firstCompositeCrop = try XCTUnwrap(croppedImage(firstComposite, to: preview.drawRect))

        XCTAssertLessThan(try averagePixelDistance(preview.image, expectedCrop), 8)
        XCTAssertGreaterThan(try averagePixelDistance(preview.image, firstCompositeCrop), 12)
    }

    func testOverlayWindowMosaicDraftOverlapDoesNotIncreaseSharpness() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)
        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.pixelMosaic))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        window.test_mouseDown(at: NSPoint(x: 50, y: 44))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 104))
        window.test_mouseUp(at: NSPoint(x: 140, y: 104))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 64, y: 34, width: 90, height: 60),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )
        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let firstCompositeImage = CaptureAnnotationRenderer.render(image: image, annotations: [
            CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 50, y: 44, width: 90, height: 60),
                style: style,
                mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
            )
        ])

        let overlap = NSRect(x: 76, y: 58, width: 44, height: 28)
        let firstCrop = try XCTUnwrap(croppedImage(firstCompositeImage, to: overlap))
        let previewCrop = try XCTUnwrap(croppedImage(preview.image, to: NSRect(
            x: overlap.minX - preview.drawRect.minX,
            y: overlap.minY - preview.drawRect.minY,
            width: overlap.width,
            height: overlap.height
        )))

        let firstSharpness = try averageLumaDelta(in: firstCrop, rect: NSRect(origin: .zero, size: firstCrop.size))
        let previewSharpness = try averageLumaDelta(in: previewCrop, rect: NSRect(origin: .zero, size: previewCrop.size))
        XCTAssertLessThanOrEqual(previewSharpness, firstSharpness * 1.08)
    }

    func testOverlayWindowMosaicDraftRedactsExistingMarkerAnnotation() throws {
        let image = checkerboardImage(size: desktopImageSize(), squareSize: 8)
        let selection = NSRect(x: 100, y: 100, width: 220, height: 160)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.marker)
        window.test_setCurrentStrokeWidth(30)
        window.test_mouseDown(at: NSPoint(x: 150, y: 170))
        window.test_mouseDragged(to: NSPoint(x: 260, y: 220))
        window.test_mouseUp(at: NSPoint(x: 260, y: 220))

        let marker = CaptureAnnotation(
            kind: .marker,
            rect: try XCTUnwrap(window.test_annotationRect(at: 0)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 0)),
            markerLine: try XCTUnwrap(window.test_markerLine(at: 0))
        )
        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 30, y: 50, width: 160, height: 90),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let expected = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [
                overlayAnnotation(marker, selection: selection),
                overlayAnnotation(draft, selection: selection),
            ]
        )
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: preview.drawRect))

        XCTAssertLessThan(try averagePixelDistance(preview.image, expectedCrop), 8)
    }

    func testOverlayWindowPixelMosaicDraftUsesCompositePixelsForExistingRectangleStroke() throws {
        let image = checkerboardImage(size: desktopImageSize(), squareSize: 8)
        let selection = NSRect(x: 100, y: 100, width: 260, height: 180)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.rectangle)
        window.test_setCurrentStrokeWidth(24)
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 250, y: 230))
        window.test_mouseUp(at: NSPoint(x: 250, y: 230))

        let rectangle = CaptureAnnotation(
            kind: .rectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 0)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 0))
        )
        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 44, y: 44, width: 116, height: 104),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )

        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let expected = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [
                overlayAnnotation(rectangle, selection: selection),
                overlayAnnotation(draft, selection: selection),
            ]
        )
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: preview.drawRect))
        let backgroundOnly = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [overlayAnnotation(draft, selection: selection)]
        )
        let backgroundOnlyCrop = try XCTUnwrap(croppedImage(backgroundOnly, to: preview.drawRect))

        XCTAssertLessThan(try averagePixelDistance(preview.image, expectedCrop), 8)
        XCTAssertGreaterThan(try averagePixelDistance(preview.image, backgroundOnlyCrop), 12)
    }

    func testOverlayWindowCommittedMosaicRedactsEarlierMarkerAnnotation() throws {
        let image = checkerboardImage(size: desktopImageSize(), squareSize: 8)
        let selection = NSRect(x: 100, y: 100, width: 220, height: 160)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.marker)
        window.test_setCurrentStrokeWidth(30)
        window.test_mouseDown(at: NSPoint(x: 150, y: 170))
        window.test_mouseDragged(to: NSPoint(x: 260, y: 220))
        window.test_mouseUp(at: NSPoint(x: 260, y: 220))

        let marker = CaptureAnnotation(
            kind: .marker,
            rect: try XCTUnwrap(window.test_annotationRect(at: 0)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 0)),
            markerLine: try XCTUnwrap(window.test_markerLine(at: 0))
        )
        window.test_toggleShapeTool(.mosaicRectangle)
        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.pixelMosaic))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: NSPoint(x: 130, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 290, y: 240))
        window.test_mouseUp(at: NSPoint(x: 290, y: 240))

        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let mosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 1)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 1)),
            mosaicRedaction: try XCTUnwrap(window.test_mosaicRedaction(at: 1))
        )
        let expected = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [
                overlayAnnotation(marker, selection: selection),
                overlayAnnotation(mosaic, selection: selection),
            ]
        )
        let checkRect = NSRect(x: 140, y: 160, width: 140, height: 70)
        let overlayCrop = try XCTUnwrap(croppedImage(overlayImage, to: checkRect))
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: checkRect))

        XCTAssertLessThan(try averagePixelDistance(overlayCrop, expectedCrop), 8)
    }

    func testOverlayWindowMosaicRectangleCanStartOnExistingRectangleVerticalBorder() throws {
        let image = checkerboardImage(size: desktopImageSize(), squareSize: 8)
        let selection = NSRect(x: 100, y: 100, width: 260, height: 180)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.rectangle)
        window.test_setCurrentStrokeWidth(24)
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 250, y: 230))
        window.test_mouseUp(at: NSPoint(x: 250, y: 230))

        let rectangle = CaptureAnnotation(
            kind: .rectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 0)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 0))
        )
        window.test_toggleShapeTool(.mosaicRectangle)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 150, y: 182)), .crosshair)
        window.test_mouseDown(at: NSPoint(x: 150, y: 182))
        window.test_mouseDragged(to: NSPoint(x: 178, y: 218))
        window.test_mouseUp(at: NSPoint(x: 178, y: 218))

        XCTAssertEqual(window.test_annotationCount, 2)
        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let mosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 1)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 1)),
            mosaicRedaction: try XCTUnwrap(window.test_mosaicRedaction(at: 1))
        )
        let expected = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [
                overlayAnnotation(rectangle, selection: selection),
                overlayAnnotation(mosaic, selection: selection),
            ]
        )
        let checkRect = NSRect(x: 156, y: 190, width: 20, height: 20)
        let overlayCrop = try XCTUnwrap(croppedImage(overlayImage, to: checkRect))
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: checkRect))

        XCTAssertLessThan(try averagePixelDistance(overlayCrop, expectedCrop), 18)
    }

    func testOverlayWindowSequentialMosaicCompositesReuseCacheAcrossPrefixes() throws {
        let image = checkerboardImage(size: NSSize(width: 260, height: 180), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))

        var markerStyle = CaptureAnnotationStyle()
        markerStyle.strokeColor = SelectionToolbarState.defaultMarkerColor
        markerStyle.strokeWidth = 24
        let marker = CaptureAnnotation(
            kind: .marker,
            rect: NSRect(x: 42, y: 44, width: 86, height: 40),
            style: markerStyle,
            markerLine: CaptureMarkerLine(start: NSPoint(x: 42, y: 44), end: NSPoint(x: 128, y: 84))
        )
        var mosaicStyle = CaptureAnnotationStyle()
        mosaicStyle.strokeWidth = 30
        let redaction = CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        let firstMosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 32, y: 26, width: 76, height: 50),
            style: mosaicStyle,
            mosaicRedaction: redaction
        )
        let secondMosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 66, y: 54, width: 82, height: 50),
            style: mosaicStyle,
            mosaicRedaction: redaction
        )

        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [marker, firstMosaic]))
        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [marker, firstMosaic, secondMosaic]))
        let renderCountAfterTwoPrefixes = window.test_mosaicCompositeRenderCount
        XCTAssertGreaterThan(renderCountAfterTwoPrefixes, 0)

        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [marker, firstMosaic]))

        XCTAssertEqual(window.test_mosaicCompositeRenderCount, renderCountAfterTwoPrefixes)
    }

    func testOverlayWindowMosaicOnlyAnnotationsUseSingleCompositeDraw() {
        let image = checkerboardImage(size: NSSize(width: 260, height: 180), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        window.test_mouseDown(at: NSPoint(x: 42, y: 46))
        window.test_mouseDragged(to: NSPoint(x: 92, y: 96))
        window.test_mouseUp(at: NSPoint(x: 92, y: 96))
        window.test_mouseDown(at: NSPoint(x: 142, y: 50))
        window.test_mouseDragged(to: NSPoint(x: 192, y: 100))
        window.test_mouseUp(at: NSPoint(x: 192, y: 100))

        XCTAssertEqual(window.test_annotationCount, 2)
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicCompositeRenderCount, 1)
    }

    func testOverlayWindowMosaicStrokeIsNotMutatedWhenPreparingNextRectangleMosaic() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 88, y: 82))
        window.test_mouseUp(at: NSPoint(x: 88, y: 82))

        XCTAssertNil(window.test_selectedAnnotationKind)
        let originalRedaction = try XCTUnwrap(window.test_mosaicRedaction(at: 0))

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        window.test_toggleShapeTool(.mosaicRectangle)

        XCTAssertEqual(window.test_mosaicRedaction(at: 0), originalRedaction)
        XCTAssertEqual(window.test_currentShapeKind, .mosaicRectangle)
    }

    func testOverlayWindowMosaicDraftPreviewKeepsExistingMosaicAnnotations() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 200, y: 160))
        window.test_mouseUp(at: NSPoint(x: 200, y: 160))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draftStroke = CaptureMosaicStroke(points: [
            NSPoint(x: 130, y: 90),
            NSPoint(x: 190, y: 92),
        ])
        let draft = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: draftStroke.boundingRect,
            style: style,
            mosaicStroke: draftStroke,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        XCTAssertEqual(window.test_mosaicDraftPreviewAnnotationCount(for: draft), 2)
    }

    func testMosaicStrokePreviewDotsStayVisuallySmall() {
        XCTAssertEqual(SelectionToolbarState.mosaicPreviewDotDiameter(for: 15), 5)
        XCTAssertEqual(SelectionToolbarState.mosaicPreviewDotDiameter(for: 30), 8)
        XCTAssertEqual(SelectionToolbarState.mosaicPreviewDotDiameter(for: 40), 11)
    }

    func testOverlayWindowMosaicPreviewUsesFullBackgroundImage() {
        let image = NSImage(size: NSSize(width: 240, height: 160))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 240, height: 160).fill()
        NSColor.black.setFill()
        NSRect(x: 120, y: 50, width: 50, height: 24).fill()
        image.unlockFocus()

        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 100, y: 40, width: 80, height: 60)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 16
        let annotation = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 20, y: 10, width: 50, height: 24),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        guard let preview = window.test_mosaicPreviewComposite(for: [annotation]) else {
            return XCTFail("Expected mosaic preview composite")
        }

        XCTAssertEqual(preview.size.width, image.size.width, accuracy: 0.1)
        XCTAssertEqual(preview.size.height, image.size.height, accuracy: 0.1)
        XCTAssertEqual(preview.drawRect.origin.x, 0, accuracy: 0.1)
        XCTAssertEqual(preview.drawRect.origin.y, 0, accuracy: 0.1)
        XCTAssertGreaterThan(preview.drawRect.width, selection.width)
        XCTAssertGreaterThan(preview.drawRect.height, selection.height)
    }

    func testOverlayWindowMosaicPreviewKeepsOutOfSelectionGeometryVisible() {
        let image = NSImage(size: NSSize(width: 240, height: 160))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 240, height: 160).fill()
        image.unlockFocus()

        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 100, y: 40, width: 80, height: 60)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let outsideStroke = CaptureMosaicStroke(points: [
            NSPoint(x: -40, y: 30),
            NSPoint(x: -25, y: 30),
        ])
        let annotation = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: outsideStroke.boundingRect,
            style: style,
            mosaicStroke: outsideStroke,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        guard let preview = window.test_mosaicPreviewComposite(for: [annotation]) else {
            return XCTFail("Expected mosaic preview composite")
        }

        XCTAssertEqual(preview.size.width, image.size.width, accuracy: 0.1)
        XCTAssertEqual(preview.size.height, image.size.height, accuracy: 0.1)
        XCTAssertGreaterThan(preview.drawRect.width, selection.width)
        XCTAssertGreaterThan(preview.drawRect.height, selection.height)

        guard let clipBounds = window.test_mosaicPreviewClipBounds(for: [annotation]) else {
            return XCTFail("Expected mosaic preview clip bounds")
        }
        XCTAssertLessThan(clipBounds.maxX, selection.minX)
        XCTAssertLessThan(clipBounds.width, preview.drawRect.width)
        XCTAssertLessThan(clipBounds.height, preview.drawRect.height)
        XCTAssertTrue(window.test_mosaicPreviewClipContains(NSPoint(x: 67.5, y: 70), for: [annotation]))
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

    func testOverlayWindowBrushDoesNotShowEndpointMarkersImmediatelyAfterDrawing() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 170, y: 180))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 190))
        window.test_mouseUp(at: NSPoint(x: 240, y: 170))

        XCTAssertNil(window.test_selectedAnnotationKind)
        XCTAssertTrue(window.test_selectedBrushEndpointMarkers.isEmpty)
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

        XCTAssertNotEqual(window.test_cursorStyle(at: startHandle), .rotationHandle)
        XCTAssertNotEqual(window.test_cursorStyle(at: endHandle), .rotationHandle)

        window.test_mouseDown(at: NSPoint(x: 160, y: 160))
        window.test_mouseUp(at: NSPoint(x: 160, y: 160))

        XCTAssertEqual(window.test_cursorStyle(at: startHandle), .resizeUpDown)
        XCTAssertEqual(window.test_cursorStyle(at: endHandle), .resizeUpDown)
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

        window.test_mouseDown(at: NSPoint(x: 160, y: 160))
        window.test_mouseUp(at: NSPoint(x: 160, y: 160))

        window.test_mouseDown(at: endHandle)
        window.test_mouseDragged(to: NSPoint(x: 210, y: 220))
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 210, y: 220)), .resizeUpDown)
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
            "xxsnap 截图 19700101-000000.png"
        )
    }

    func testOptionsToolbarOnlyShownForRectangleTool() {
        XCTAssertTrue(SelectionToolbarState.shouldShowOptionsToolbar(isPrimaryShapeToolActive: true))
        XCTAssertFalse(SelectionToolbarState.shouldShowOptionsToolbar(isPrimaryShapeToolActive: false))
    }

    func testToolbarIconInsetsRenderArrowLineLargerThanDefaultIcons() {
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "arrow-line"), 0)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "pencil-tool"), 2)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "eyedropper"), 2)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "text-tool"), 0)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "masaike2"), -3)
    }

    func testCurrentColorToolbarIconsUseTemplateTint() {
        XCTAssertFalse(SelectionToolbarState.usesFixedColorToolbarIconResource("pencil-tool"))
        XCTAssertFalse(SelectionToolbarState.usesFixedColorToolbarIconResource("arrow-line"))
        XCTAssertFalse(SelectionToolbarState.usesFixedColorToolbarIconResource("mosaic-tool"))
        XCTAssertTrue(SelectionToolbarState.usesFixedColorToolbarIconResource("undo-enabled"))
    }

    func testMosaicToolbarButtonUsesMasaike2Resource() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }

        XCTAssertEqual(window.test_symbolName(for: .mosaic), "toolbar-masaike2")
    }

    func testMosaicPreviewProgressMapsRangeEndpoints() {
        XCTAssertEqual(SelectionToolbarState.mosaicPreviewProgress(for: 5), 0, accuracy: 0.001)
        XCTAssertEqual(SelectionToolbarState.mosaicPreviewProgress(for: 12), 7.0 / 15.0, accuracy: 0.001)
        XCTAssertEqual(SelectionToolbarState.mosaicPreviewProgress(for: 20), 1, accuracy: 0.001)
    }

    func testMosaicPreviewBackgroundColorDarkensAsValueIncreases() {
        let low = SelectionToolbarState.mosaicPreviewBackgroundColor(for: 5).usingColorSpace(.sRGB)!
        let high = SelectionToolbarState.mosaicPreviewBackgroundColor(for: 20).usingColorSpace(.sRGB)!

        XCTAssertGreaterThan(low.redComponent, high.redComponent)
        XCTAssertGreaterThan(low.greenComponent, high.greenComponent)
        XCTAssertGreaterThan(low.blueComponent, high.blueComponent)
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

    func testMosaicOptionsToolbarOnlyShowsRedactionTypeAndValueControls() {
        let optionsRect = NSRect(x: 100, y: 100, width: 420, height: 40)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .mosaic
        )

        XCTAssertEqual(layout.strokeWidths.count, 0)
        XCTAssertNil(layout.ellipseMode)
        XCTAssertNil(layout.rectangleMode)
        XCTAssertEqual(SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsRect).minX, optionsRect.minX + 10)
        XCTAssertGreaterThan(
            SelectionToolbarState.mosaicRedactionValueRect(in: optionsRect).minX,
            SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsRect).maxX
        )
    }

    func testMosaicOptionsToolbarBalancesLeadingAndTrailingGapAroundControls() {
        let width = SelectionToolbarState.optionsToolbarWidth(paletteCount: 8, mode: .mosaic)
        let optionsRect = NSRect(x: 100, y: 100, width: width, height: 40)
        let typeRect = SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsRect)
        let valueRect = SelectionToolbarState.mosaicRedactionValueRect(in: optionsRect)

        let leadingGap = typeRect.minX - optionsRect.minX
        let trailingGap = optionsRect.maxX - valueRect.maxX

        XCTAssertLessThan(width, 300)
        XCTAssertEqual(leadingGap, 10, accuracy: 0.1)
        XCTAssertEqual(leadingGap, trailingGap, accuracy: 0.1)
    }

    func testOptionsToolbarLeadingAndTrailingGapsAreTenPixels() throws {
        let optionsRect = NSRect(x: 100, y: 100, width: 600, height: 40)
        let modes: [SelectionToolbarState.OptionsToolbarMode] = [.shape, .arrowLine, .brush, .marker, .mosaic]

        for mode in modes {
            let width = SelectionToolbarState.optionsToolbarWidth(paletteCount: 8, mode: mode)
            let modeRect = NSRect(x: optionsRect.minX, y: optionsRect.minY, width: width, height: optionsRect.height)
            let layout = SelectionToolbarState.optionsToolbarLayout(in: modeRect, paletteCount: 8, mode: mode)
            var controls = layout.strokeWidths
            controls.append(contentsOf: layout.colorSwatches)
            [
                layout.fillToggle,
                layout.rectangleMode,
                layout.ellipseMode,
                layout.strokeStyle.isEmpty ? nil : layout.strokeStyle,
                layout.startArrowType,
                layout.endArrowType,
            ].compactMap { $0 }.forEach { controls.append($0) }
            if mode == .mosaic {
                controls.append(SelectionToolbarState.mosaicRedactionTypeButtonRect(in: modeRect))
                controls.append(SelectionToolbarState.mosaicRedactionValueRect(in: modeRect))
            }

            let minX = try XCTUnwrap(controls.map(\.minX).min(), "Expected controls for \(mode)")
            let maxX = try XCTUnwrap(controls.map(\.maxX).max(), "Expected controls for \(mode)")
            XCTAssertEqual(minX - modeRect.minX, 10, accuracy: 0.1, "\(mode) leading gap")
            XCTAssertEqual(modeRect.maxX - maxX, 10, accuracy: 0.1, "\(mode) trailing gap")
        }
    }

    func testMosaicOptionsToolbarMatchesMainToolbarHeightAndOmitsSeparator() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 60, y: 60, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        let optionsRect = try XCTUnwrap(window.test_optionsToolbarRect)
        XCTAssertEqual(optionsRect.height, 28, accuracy: 0.1)

        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let typeRect = SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsRect)
        let typeBackground = typeRect.insetBy(dx: -3, dy: -5)
        let valueRect = SelectionToolbarState.mosaicRedactionValueRect(in: optionsRect)
        let oldSeparatorX = floor(typeBackground.maxX + (valueRect.minX - typeBackground.maxX) / 2) + 1
        let separatorPoint = NSPoint(x: oldSeparatorX, y: optionsRect.midY)
        let gapPoint = NSPoint(x: oldSeparatorX - 3, y: optionsRect.midY)
        let separatorPixel = try XCTUnwrap(rgbaPixel(in: image, at: separatorPoint))
        let gapPixel = try XCTUnwrap(rgbaPixel(in: image, at: gapPoint))

        XCTAssertLessThanOrEqual(pixelDistance(separatorPixel, gapPixel), 3)
    }

    func testSelectedToolbarBackgroundsAreHiddenExceptMeasurementControls() {
        XCTAssertEqual(SelectionToolbarState.toolbarSelectedBackgroundAlpha, 0, accuracy: 0.001)
        XCTAssertEqual(SelectionToolbarState.measurementControlSelectedBackgroundAlpha, 0.34, accuracy: 0.001)
        XCTAssertGreaterThan(SelectionToolbarState.measurementControlSelectedBackgroundAlpha, 0.22)
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

    func testOverlayWindowNonMarkerToolsResetToRedAfterCustomNonMarkerColor() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.rectangle)

        guard let rectangleBluePoint = window.test_optionsPaletteColorPoint(at: 8) else {
            return XCTFail("Expected rectangle palette control")
        }
        window.test_mouseDown(at: rectangleBluePoint)
        window.test_mouseUp(at: rectangleBluePoint)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: window.test_currentStyle?.strokeColor ?? .clear),
            "#3C53D7"
        )

        window.test_activateShapeTool(.arrowLine)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: window.test_currentStyle?.strokeColor ?? .clear),
            "#FF001A"
        )

        guard let arrowBluePoint = window.test_optionsPaletteColorPoint(at: 8) else {
            return XCTFail("Expected arrow palette control")
        }
        window.test_mouseDown(at: arrowBluePoint)
        window.test_mouseUp(at: arrowBluePoint)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: window.test_currentStyle?.strokeColor ?? .clear),
            "#3C53D7"
        )

        window.test_activateShapeTool(.brush)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: window.test_currentStyle?.strokeColor ?? .clear),
            "#FF001A"
        )

        guard let brushBluePoint = window.test_optionsPaletteColorPoint(at: 8) else {
            return XCTFail("Expected brush palette control")
        }
        window.test_mouseDown(at: brushBluePoint)
        window.test_mouseUp(at: brushBluePoint)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: window.test_currentStyle?.strokeColor ?? .clear),
            "#3C53D7"
        )

        window.test_activateShapeTool(.mosaicRectangle)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: window.test_currentStyle?.strokeColor ?? .clear),
            "#FF001A"
        )
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

        XCTAssertEqual(window.test_cursorStyle(at: startHandle), .resizeUpDown)
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

    func testOverlayWindowMovesSinglePointMarkerWithoutResizingIt() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        let point = NSPoint(x: 140, y: 150)
        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)

        guard let original = window.test_markerLine(at: 0) else {
            return XCTFail("Expected marker annotation")
        }
        XCTAssertEqual(original.start.x, original.end.x, accuracy: 0.1)
        XCTAssertEqual(original.start.y, original.end.y, accuracy: 0.1)
        XCTAssertEqual(window.test_cursorStyle(at: point), .move)

        window.test_mouseDown(at: point)
        window.test_mouseDragged(to: NSPoint(x: 170, y: 180))
        window.test_mouseUp(at: NSPoint(x: 170, y: 180))

        guard let moved = window.test_markerLine(at: 0) else {
            return XCTFail("Expected moved marker annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(moved.start.x, original.start.x + 30, accuracy: 0.1)
        XCTAssertEqual(moved.start.y, original.start.y + 30, accuracy: 0.1)
        XCTAssertEqual(moved.end.x, moved.start.x, accuracy: 0.1)
        XCTAssertEqual(moved.end.y, moved.start.y, accuracy: 0.1)
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

    func testMainToolbarHasLeadingAndTrailingDragHandles() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 360, height: 220))

        let leadingPoint = try XCTUnwrap(window.test_mainToolbarLeadingDragPoint())
        let trailingPoint = try XCTUnwrap(window.test_mainToolbarTrailingDragPoint())
        let firstButton = try XCTUnwrap(window.test_mainToolbarButtonRects().first)
        let settingsButton = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .settings))

        XCTAssertLessThan(leadingPoint.x, firstButton.minX)
        XCTAssertEqual(trailingPoint.x, settingsButton.midX, accuracy: 0.1)
        XCTAssertEqual(window.test_cursorStyle(at: leadingPoint), .move)
        XCTAssertEqual(window.test_cursorStyle(at: trailingPoint), .move)
    }

    func testMainToolbarLeadingDragHandleMovesToolbar() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 360, height: 220))
        let firstButtonBefore = try XCTUnwrap(window.test_mainToolbarButtonRects().first)
        let leadingPoint = try XCTUnwrap(window.test_mainToolbarLeadingDragPoint())

        window.test_mouseDown(at: leadingPoint)
        window.test_mouseDragged(to: NSPoint(x: leadingPoint.x + 36, y: leadingPoint.y + 10))
        window.test_mouseUp(at: NSPoint(x: leadingPoint.x + 36, y: leadingPoint.y + 10))

        let firstButtonAfter = try XCTUnwrap(window.test_mainToolbarButtonRects().first)
        XCTAssertGreaterThan(firstButtonAfter.minX, firstButtonBefore.minX + 20)
    }

    func testSelectedMainToolbarIconIsBlueWithoutSelectedBackground() throws {
        let image = solidImage(size: NSSize(width: 900, height: 520), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.rectangle)

        let button = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .rectangle))
        let unselectedButton = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .mosaic))
        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let iconPixel = try XCTUnwrap(firstBlueDominantPixel(in: overlayImage, rect: button))
        let selectedBackgroundPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: NSPoint(x: button.minX + 1, y: button.minY + 1)))
        let unselectedBackgroundPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: NSPoint(x: unselectedButton.minX + 1, y: unselectedButton.minY + 1)))

        XCTAssertGreaterThan(iconPixel.blue, iconPixel.red)
        XCTAssertGreaterThan(iconPixel.blue, iconPixel.green)
        XCTAssertLessThan(pixelDistance(selectedBackgroundPixel, unselectedBackgroundPixel), 8)
    }

    func testMainToolbarButtonsUseRoomierDefaultSpacing() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 360, height: 220))

        let rects = window.test_mainToolbarButtonRects()
        XCTAssertGreaterThan(rects.count, 8)

        let gaps = zip(rects, rects.dropFirst()).map { left, right in
            right.minX - left.maxX
        }
        XCTAssertGreaterThanOrEqual(gaps.min() ?? 0, 8)
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

    func testBrushCursorUsesBrushOutsideSelectionAndArrowOnToolbar() {
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
            .brush
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

    func testShapeToolCursorStaysActiveOutsideSelectionAwayFromBorder() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: false,
                isShapeToolActive: true,
                currentShapeKind: .rectangle
            ),
            .crosshair
        )
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: false,
                isShapeToolActive: true,
                currentShapeKind: .arrowLine
            ),
            .crosshair
        )
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: false,
                isShapeToolActive: true,
                currentShapeKind: .marker
            ),
            .marker
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

    func testPrimaryShapeToolActivationUsesFirstPaletteColorAfterUserChosenColor() {
        var currentStyle = CaptureAnnotationStyle()
        currentStyle.strokeColor = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        currentStyle.fillColor = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)

        let style = SelectionToolbarState.styleForPrimaryShapeToolActivation(
            currentStyle: currentStyle,
            paletteColors: SelectionOverlayWindow.defaultPaletteColors
        )

        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#FF001A")
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.fillColor), "#FF001A")
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
        XCTAssertEqual(SelectionToolbarState.optionsToolbarWidth(paletteCount: 4), 425)
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

        XCTAssertEqual(fullPaletteWidth, 533)
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

    func testMainToolbarDragHandleIconColorIsSofterThanToolIcons() throws {
        let color: NSColor = try XCTUnwrap(
            SelectionToolbarState.mainToolbarDragHandleIconColor(enabled: true)
                .usingColorSpace(NSColorSpace.deviceRGB)
        )
        let disabled = SelectionToolbarState.mainToolbarDragHandleIconColor(enabled: false)

        XCTAssertEqual(color.redComponent, 0.48, accuracy: 0.02)
        XCTAssertEqual(color.alphaComponent, 0.75, accuracy: 0.02)
        XCTAssertLessThan(color.alphaComponent, 1)
        XCTAssertEqual(disabled, NSColor.disabledControlTextColor)
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
        XCTAssertEqual(layout.labelSeparator.width, 1)
        XCTAssertEqual(layout.refreshSeparator.width, 1)
        XCTAssertEqual(layout.cornerStyle.minX - layout.labelSeparator.maxX, 8)
        XCTAssertEqual(layout.aspectRatio.minX - layout.cornerStyle.maxX, 8)
        XCTAssertEqual(layout.refreshSeparator.minX - layout.aspectRatio.maxX, 8)
        XCTAssertEqual(layout.refresh.minX - layout.refreshSeparator.maxX, 8)
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

    func testLockedAspectRatioSelectionResizeCanFlipPastAnchor() {
        let start = NSRect(x: 100, y: 100, width: 200, height: 100)
        let resized = SelectionToolbarState.resizedSelectionRect(
            from: start,
            handle: .bottomRight,
            point: NSPoint(x: 60, y: 240),
            lockAspectRatio: true
        )

        XCTAssertEqual(resized.width / resized.height, 2, accuracy: 0.01)
        XCTAssertEqual(resized.maxX, 100, accuracy: 0.1)
        XCTAssertEqual(resized.minY, 200, accuracy: 0.1)
        XCTAssertGreaterThan(resized.width, 8)
        XCTAssertGreaterThan(resized.height, 8)
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

    func testSelectionCornerRadiusDefaultsToRounded() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }

        XCTAssertEqual(window.test_selectionCornerRadius, 10)
    }

    func testClickingCornerStyleMeasurementControlTogglesSelectionCornerRadius() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 220, height: 140))

        guard let point = window.test_measurementControlPoint(.cornerStyle) else {
            return XCTFail("Expected corner style control")
        }
        window.test_mouseDown(at: point)

        XCTAssertEqual(window.test_selectionCornerRadius, 0)

        window.test_mouseDown(at: point)

        XCTAssertEqual(window.test_selectionCornerRadius, 10)
    }

    func testRoundedSelectionHidesCornerHandlesAndSquareSelectionShowsThem() {
        let rect = NSRect(x: 100, y: 120, width: 220, height: 140)

        XCTAssertEqual(
            SelectionToolbarState.selectionHandlePoints(in: rect, cornerRadius: 0),
            [
                NSPoint(x: rect.minX, y: rect.maxY),
                NSPoint(x: rect.midX, y: rect.maxY),
                NSPoint(x: rect.maxX, y: rect.maxY),
                NSPoint(x: rect.minX, y: rect.midY),
                NSPoint(x: rect.maxX, y: rect.midY),
                NSPoint(x: rect.minX, y: rect.minY),
                NSPoint(x: rect.midX, y: rect.minY),
                NSPoint(x: rect.maxX, y: rect.minY),
            ]
        )

        XCTAssertEqual(
            SelectionToolbarState.selectionHandlePoints(in: rect, cornerRadius: 8),
            [
                NSPoint(x: rect.midX, y: rect.maxY),
                NSPoint(x: rect.minX, y: rect.midY),
                NSPoint(x: rect.maxX, y: rect.midY),
                NSPoint(x: rect.midX, y: rect.minY),
            ]
        )
    }

    func testSelectionMeasurementControlSvgResourcesAreBundled() {
        let resourceNames: [String] = [
            "border-corner-rounded",
            "border-corner-square",
            "aspect-ratio",
            "aspect-ratio-fill",
            "refresh",
        ]
        resourceNames.forEach { name in
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "svg"), "\(name).svg should be bundled")
        }
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

    func testLockedAspectRatioSelectionDragCanContinueAfterCrossingMinimumSize() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 100))

        guard let aspectPoint = window.test_measurementControlPoint(.aspectRatioLock) else {
            return XCTFail("Expected aspect ratio control")
        }
        window.test_mouseDown(at: aspectPoint)

        window.test_mouseDown(at: NSPoint(x: 300, y: 100))
        window.test_mouseDragged(to: NSPoint(x: 60, y: 240))
        window.test_mouseUp(at: NSPoint(x: 60, y: 240))

        guard let resized = window.test_lockedSelectionRect else {
            return XCTFail("Expected locked selection")
        }
        XCTAssertEqual(resized.width / resized.height, 2, accuracy: 0.01)
        XCTAssertEqual(resized.maxX, 100, accuracy: 0.1)
        XCTAssertEqual(resized.minY, 200, accuracy: 0.1)
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

    func testCaptureRefreshIgnoresSniporyAsRefreshTarget() {
        XCTAssertFalse(
            CaptureCoordinator.shouldRefreshTargetApplication(
                targetBundleIdentifier: "com.snipory.v2.mac",
                mainBundleIdentifier: "com.snipory.v2.mac"
            )
        )
        XCTAssertFalse(
            CaptureCoordinator.shouldRefreshTargetApplication(
                targetBundleIdentifier: nil,
                mainBundleIdentifier: "com.snipory.v2.mac"
            )
        )
        XCTAssertTrue(
            CaptureCoordinator.shouldRefreshTargetApplication(
                targetBundleIdentifier: "com.apple.Safari",
                mainBundleIdentifier: "com.snipory.v2.mac"
            )
        )
    }

    func testCaptureRefreshIgnoresXxsnapAsRefreshTarget() {
        XCTAssertFalse(
            CaptureCoordinator.shouldRefreshTargetApplication(
                targetBundleIdentifier: "com.xxsnap.mac",
                mainBundleIdentifier: "com.xxsnap.mac"
            )
        )
        XCTAssertTrue(
            CaptureCoordinator.shouldRefreshTargetApplication(
                targetBundleIdentifier: "com.apple.finder",
                mainBundleIdentifier: "com.xxsnap.mac"
            )
        )
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
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "mosaicRectangle"), "矩形模糊")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "mosaicBlur"), "高斯")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "mosaicPixel"), "马赛克")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "save"), "保存")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "copy"), "复制到剪切板")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "scroll"), "滚动截图")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "cornerStyle"), "直角/圆角切换")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "aspectRatioLockedOn"), "锁定长宽比(开)")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "aspectRatioLockedOff"), "锁定长宽比(关)")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "refreshCapture"), "刷新截图")
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

    func testWheelZoomExpandsShrinksAndClampsLockedSelection() {
        let start = NSRect(x: 110, y: 90, width: 140, height: 90)
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        let anchor = NSPoint(x: start.midX, y: start.midY)

        let expanded = SelectionToolbarState.wheelZoomedSelectionRect(
            from: start,
            anchor: anchor,
            deltaY: 4,
            inside: bounds,
            minimumSize: 64
        )
        XCTAssertGreaterThan(expanded.width, start.width)
        XCTAssertGreaterThan(expanded.height, start.height)
        XCTAssertLessThan(expanded.width - start.width, 14)

        let shrunk = SelectionToolbarState.wheelZoomedSelectionRect(
            from: start,
            anchor: anchor,
            deltaY: -8,
            inside: bounds,
            minimumSize: 64
        )
        XCTAssertGreaterThanOrEqual(shrunk.width, 64)
        XCTAssertGreaterThanOrEqual(shrunk.height, 64)

        let hugeBounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        let nearlyFull = SelectionToolbarState.wheelZoomedSelectionRect(
            from: NSRect(x: 80, y: 70, width: 90, height: 80),
            anchor: NSPoint(x: 120, y: 110),
            deltaY: 80,
            inside: hugeBounds,
            minimumSize: 64
        )
        XCTAssertTrue(hugeBounds.contains(nearlyFull))
    }

    func testWheelZoomCanReachFullBoundsAfterRepeatedExpansion() {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        var rect = NSRect(x: 100, y: 110, width: 200, height: 80)

        for _ in 0..<80 {
            rect = SelectionToolbarState.wheelZoomedSelectionRect(
                from: rect,
                anchor: NSPoint(x: rect.midX, y: rect.midY),
                deltaY: 8,
                inside: bounds,
                minimumSize: 64
            )
        }

        XCTAssertEqual(rect.minX, bounds.minX, accuracy: 0.5)
        XCTAssertEqual(rect.minY, bounds.minY, accuracy: 0.5)
        XCTAssertEqual(rect.maxX, bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(rect.maxY, bounds.maxY, accuracy: 0.5)
    }

    func testWheelZoomAppliesWhileShapeToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 80, width: 160, height: 120)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.marker)

        XCTAssertTrue(window.test_handleScrollWheel(
            at: NSPoint(x: selection.midX, y: selection.midY),
            deltaY: 8
        ))
        XCTAssertNotEqual(window.test_lockedSelectionRect, selection)
    }

    func testWheelZoomAnimatesTowardTargetSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 80, width: 160, height: 120)
        let pointer = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.marker)

        let target = SelectionToolbarState.wheelZoomedSelectionRect(
            from: selection,
            anchor: pointer,
            deltaY: 8,
            inside: window.test_overlayBounds,
            minimumSize: 64
        )

        XCTAssertTrue(window.test_handleScrollWheel(at: pointer, deltaY: 8))

        guard let immediate = window.test_lockedSelectionRect else {
            return XCTFail("Expected animated selection")
        }
        XCTAssertNotEqual(immediate, target)
        XCTAssertGreaterThan(immediate.width, selection.width)
        XCTAssertLessThan(immediate.width, target.width)

        window.test_completeSelectionWheelAnimation()
        XCTAssertEqual(window.test_lockedSelectionRect?.minX ?? 0, target.minX, accuracy: 0.5)
        XCTAssertEqual(window.test_lockedSelectionRect?.minY ?? 0, target.minY, accuracy: 0.5)
        XCTAssertEqual(window.test_lockedSelectionRect?.width ?? 0, target.width, accuracy: 0.5)
        XCTAssertEqual(window.test_lockedSelectionRect?.height ?? 0, target.height, accuracy: 0.5)
    }

    func testWheelZoomPreservesMosaicStrokeOverlayPosition() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 80, width: 160, height: 120)
        let overlayPoint = NSPoint(x: 150, y: 130)
        let localPoint = NSPoint(x: overlayPoint.x - selection.minX, y: overlayPoint.y - selection.minY)
        let annotation = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: NSRect(x: localPoint.x, y: localPoint.y, width: 1, height: 1),
            style: CaptureAnnotationStyle(),
            mosaicStroke: CaptureMosaicStroke(points: [localPoint]),
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])

        XCTAssertTrue(window.test_handleScrollWheel(at: NSPoint(x: selection.midX, y: selection.midY), deltaY: 8))
        window.test_completeSelectionWheelAnimation()

        let resizedSelection = try XCTUnwrap(window.test_lockedSelectionRect)
        let resizedStroke = try XCTUnwrap(window.test_mosaicStroke(at: 0))
        let resizedPoint = try XCTUnwrap(resizedStroke.points.first)
        XCTAssertEqual(resizedSelection.minX + resizedPoint.x, overlayPoint.x, accuracy: 0.5)
        XCTAssertEqual(resizedSelection.minY + resizedPoint.y, overlayPoint.y, accuracy: 0.5)
    }

    func testWheelZoomUsesSelectionCenterWhenPointerIsOutsideSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 120, y: 120, width: 160, height: 120)
        window.test_setLockedSelectionRect(selection)

        XCTAssertTrue(window.test_handleScrollWheel(
            at: NSPoint(x: selection.maxX + 24, y: selection.midY),
            deltaY: 6
        ))

        guard let resized = window.test_lockedSelectionRect else {
            return XCTFail("Expected resized selection")
        }

        XCTAssertEqual(resized.midX, selection.midX, accuracy: 0.5)
        XCTAssertEqual(resized.midY, selection.midY, accuracy: 0.5)
    }

    func testWheelZoomDoesNotApplyOverToolbarButtons() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        window.test_setLockedSelectionRect(selection)

        guard let point = window.test_mainToolbarButtonPoint(for: .mosaic) else {
            return XCTFail("Expected toolbar button")
        }

        XCTAssertFalse(window.test_handleScrollWheel(at: point, deltaY: 8))
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
    }

    func testTrackpadMagnifyUsesSameSelectionZoomBehaviorAsWheel() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 80, width: 160, height: 120)
        let anchor = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        XCTAssertTrue(window.test_handleMagnify(at: anchor, magnification: 0.08))

        guard let immediate = window.test_lockedSelectionRect else {
            return XCTFail("Expected animated selection")
        }
        XCTAssertGreaterThan(immediate.width, selection.width)
        XCTAssertGreaterThan(immediate.height, selection.height)

        window.test_completeSelectionWheelAnimation()

        guard let magnified = window.test_lockedSelectionRect else {
            return XCTFail("Expected final magnified selection")
        }
        XCTAssertGreaterThan(magnified.width, immediate.width)
        XCTAssertGreaterThan(magnified.height, immediate.height)
    }

    func testTrackpadMagnifyDoesNotApplyOverToolbarButtons() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        window.test_setLockedSelectionRect(selection)

        guard let point = window.test_mainToolbarButtonPoint(for: .mosaic) else {
            return XCTFail("Expected toolbar button")
        }

        XCTAssertFalse(window.test_handleMagnify(at: point, magnification: 0.08))
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
    }

    func testInitialHoverImmediatelyTracksWindowRegion() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let candidate = WindowSelectionCandidate(
            id: 1,
            ownerPID: 10,
            layer: 0,
            alpha: 1,
            bounds: NSRect(x: 36, y: 28, width: 240, height: 140),
            name: "app"
        )
        window.test_setWindowSelectionCandidates([
            candidate
        ])

        window.test_mouseMoved(to: NSPoint(x: 90, y: 78))

        XCTAssertEqual(window.test_currentSelectionRect, candidate.bounds)
    }

    func testInitialHoverLocksCurrentWindowRegionOnMouseDownAndStopsTracking() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let first = WindowSelectionCandidate(
            id: 1,
            ownerPID: 10,
            layer: 0,
            alpha: 1,
            bounds: NSRect(x: 20, y: 20, width: 140, height: 120),
            name: "first"
        )
        let second = WindowSelectionCandidate(
            id: 2,
            ownerPID: 11,
            layer: 0,
            alpha: 1,
            bounds: NSRect(x: 190, y: 20, width: 140, height: 120),
            name: "second"
        )
        window.test_setWindowSelectionCandidates([
            first,
            second,
        ])

        window.test_mouseMoved(to: NSPoint(x: 88, y: 110))
        guard let lockedTarget = window.test_currentSelectionRect else {
            return XCTFail("Expected live window region before click")
        }
        XCTAssertEqual(lockedTarget, first.bounds)

        window.test_mouseDown(at: NSPoint(x: 88, y: 110))
        XCTAssertEqual(window.test_lockedSelectionRect, lockedTarget)

        window.test_mouseMoved(to: NSPoint(x: 240, y: 66))
        XCTAssertEqual(window.test_lockedSelectionRect, lockedTarget)
        XCTAssertEqual(window.test_currentSelectionRect, lockedTarget)
    }

    func testInitialHoverWindowTrackingStaysResponsiveAcrossMouseMoves() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setWindowSelectionCandidates([
            WindowSelectionCandidate(
                id: 1,
                ownerPID: 10,
                layer: 0,
                alpha: 1,
                bounds: NSRect(x: 80, y: 90, width: 1100, height: 670),
                name: "large app"
            )
        ])

        let start = CFAbsoluteTimeGetCurrent()
        for index in 0..<60 {
            window.test_mouseMoved(to: NSPoint(
                x: 180 + CGFloat(index % 20) * 18,
                y: 160 + CGFloat(index % 12) * 22
            ))
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 0.20)
    }

    func testInitialHoverTracksSystemBarRegions() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let menubar = WindowSelectionCandidate(
            id: 1,
            ownerPID: 0,
            layer: 24,
            alpha: 1,
            bounds: NSRect(x: 0, y: 563, width: 900, height: 37),
            name: "Menubar"
        )
        let dock = WindowSelectionCandidate(
            id: 2,
            ownerPID: 0,
            layer: 20,
            alpha: 1,
            bounds: NSRect(x: 0, y: 0, width: 900, height: 48),
            name: "Dock"
        )
        window.test_setWindowSelectionCandidates([
            menubar,
            dock,
        ])

        window.test_mouseMoved(to: NSPoint(x: 420, y: 580))
        XCTAssertEqual(window.test_currentSelectionRect, menubar.bounds)

        window.test_mouseMoved(to: NSPoint(x: 420, y: 24))
        XCTAssertEqual(window.test_currentSelectionRect, dock.bounds)
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

    private func checkerboardImage(size: NSSize) -> NSImage {
        checkerboardImage(size: size, squareSize: 8)
    }

    private func checkerboardImage(size: NSSize, squareSize: Int) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        for x in stride(from: 0, to: Int(size.width), by: squareSize) {
            for y in stride(from: 0, to: Int(size.height), by: squareSize) {
                let isDark = ((x / squareSize) + (y / squareSize)).isMultiple(of: 2)
                (isDark ? NSColor.black : NSColor.white).setFill()
                NSRect(x: x, y: y, width: squareSize, height: squareSize).fill()
            }
        }
        image.unlockFocus()
        return image
    }

    private func solidImage(size: NSSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    private func pixelImage(width: Int, height: Int, pixels: [[NSColor]]) -> NSImage {
        var bytes: [UInt8] = []
        for row in 0..<height {
            for column in 0..<width {
                let color = pixels[row][column].usingColorSpace(.sRGB) ?? pixels[row][column]
                bytes.append(UInt8(round(color.redComponent * 255)))
                bytes.append(UInt8(round(color.greenComponent * 255)))
                bytes.append(UInt8(round(color.blueComponent * 255)))
                bytes.append(UInt8(round(color.alphaComponent * 255)))
            }
        }
        let cgImage = makeTestImage(
            width: width,
            height: height,
            pixels: bytes,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func gradientImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        for x in 0..<Int(size.width) {
            let red = CGFloat(x) / max(size.width - 1, 1)
            for y in 0..<Int(size.height) {
                let green = CGFloat(y) / max(size.height - 1, 1)
                NSColor(srgbRed: red, green: green, blue: 1 - red * 0.4, alpha: 1).setFill()
                NSRect(x: x, y: y, width: 1, height: 1).fill()
            }
        }
        image.unlockFocus()
        return image
    }

    private func desktopImageSize() -> NSSize {
        let frame = NSScreen.screens.reduce(NSRect.null) { partial, screen in
            partial.union(screen.frame)
        }
        return frame.isNull ? NSSize(width: 640, height: 420) : frame.size
    }

    private func croppedImage(_ image: NSImage, to rect: NSRect) -> NSImage? {
        let normalizedRect = rect.standardized
        let clippedRect = normalizedRect.intersection(NSRect(origin: .zero, size: image.size))
        guard !clippedRect.isEmpty else {
            return nil
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let pixelRect = CGRect(
            x: clippedRect.minX * scaleX,
            y: (image.size.height - clippedRect.maxY) * scaleY,
            width: clippedRect.width * scaleX,
            height: clippedRect.height * scaleY
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard !pixelRect.isEmpty, let croppedImage = cgImage.cropping(to: pixelRect) else {
            return nil
        }
        return NSImage(cgImage: croppedImage, size: clippedRect.size)
    }

    private func rgbaBytes(in image: NSImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return bytes
    }

    private func rgbaPixel(in image: NSImage, at point: NSPoint) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let pixelX = Int((point.x * scaleX).rounded(.down))
        let pixelY = Int((point.y * scaleY).rounded(.down))
        guard pixelX >= 0, pixelX < cgImage.width, pixelY >= 0, pixelY < cgImage.height else {
            return nil
        }

        let bytes = try rgbaBytes(in: image)
        let index = (pixelY * cgImage.width + pixelX) * 4
        return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
    }

    private func pixelDiffers(
        _ lhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8),
        _ rhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)
    ) -> Bool {
        lhs.red != rhs.red || lhs.green != rhs.green || lhs.blue != rhs.blue || lhs.alpha != rhs.alpha
    }

    private func pixelDistance(
        _ lhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8),
        _ rhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)
    ) -> Int {
        abs(Int(lhs.red) - Int(rhs.red))
            + abs(Int(lhs.green) - Int(rhs.green))
            + abs(Int(lhs.blue) - Int(rhs.blue))
            + abs(Int(lhs.alpha) - Int(rhs.alpha))
    }

    private func firstBlueDominantPixel(
        in image: NSImage,
        rect: NSRect
    ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bytes = try rgbaBytes(in: image)
        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let minX = max(0, Int((rect.minX * scaleX).rounded(.down)))
        let maxX = min(cgImage.width - 1, Int((rect.maxX * scaleX).rounded(.up)))
        let directY = (
            min: max(0, Int((rect.minY * scaleY).rounded(.down))),
            max: min(cgImage.height - 1, Int((rect.maxY * scaleY).rounded(.up)))
        )
        let flippedY = (
            min: max(0, Int(((image.size.height - rect.maxY) * scaleY).rounded(.down))),
            max: min(cgImage.height - 1, Int(((image.size.height - rect.minY) * scaleY).rounded(.up)))
        )
        guard minX < maxX else {
            return nil
        }

        for yRange in [directY, flippedY] where yRange.min < yRange.max {
            for y in yRange.min...yRange.max {
                for x in minX...maxX {
                    let index = (y * cgImage.width + x) * 4
                    let pixel = (
                        red: bytes[index],
                        green: bytes[index + 1],
                        blue: bytes[index + 2],
                        alpha: bytes[index + 3]
                    )
                    if pixel.blue > pixel.red + 20,
                       pixel.blue > pixel.green + 20,
                       pixel.alpha > 200 {
                        return pixel
                    }
                }
            }
        }
        return nil
    }

    private func averageLumaDelta(in image: NSImage, rect: NSRect) throws -> Double {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bytes = try rgbaBytes(in: image)
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(cgImage.width - 1, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(cgImage.height - 1, Int(rect.maxY.rounded(.up)))
        guard minX < maxX, minY < maxY else {
            return 0
        }

        var total = 0.0
        var count = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let luma = lumaAt(x: x, y: y, width: cgImage.width, height: cgImage.height, bytes: bytes)
                let right = lumaAt(x: x + 1, y: y, width: cgImage.width, height: cgImage.height, bytes: bytes)
                let down = lumaAt(x: x, y: y + 1, width: cgImage.width, height: cgImage.height, bytes: bytes)
                total += abs(luma - right) + abs(luma - down)
                count += 2
            }
        }
        return total / Double(max(1, count))
    }

    private func lumaAt(x: Int, y: Int, width: Int, height: Int, bytes: [UInt8]) -> Double {
        let index = (y * width + x) * 4
        return 0.2126 * Double(bytes[index])
            + 0.7152 * Double(bytes[index + 1])
            + 0.0722 * Double(bytes[index + 2])
    }

    private func overlayMosaicAnnotation(_ annotation: CaptureAnnotation, selection: NSRect) -> CaptureAnnotation {
        overlayAnnotation(annotation, selection: selection)
    }

    private func overlayAnnotation(_ annotation: CaptureAnnotation, selection: NSRect) -> CaptureAnnotation {
        var overlay = annotation
        overlay.rect.origin.x += selection.minX
        overlay.rect.origin.y += selection.minY
        if let arrowLine = annotation.arrowLine {
            overlay.arrowLine = CaptureArrowLine(
                start: overlayPoint(arrowLine.start, selection: selection),
                end: overlayPoint(arrowLine.end, selection: selection),
                control: overlayPoint(arrowLine.control, selection: selection),
                startArrowType: arrowLine.startArrowType,
                endArrowType: arrowLine.endArrowType
            )
        }
        if let markerLine = annotation.markerLine {
            overlay.markerLine = CaptureMarkerLine(
                start: overlayPoint(markerLine.start, selection: selection),
                end: overlayPoint(markerLine.end, selection: selection)
            )
        }
        if let brushPath = annotation.brushPath {
            overlay.brushPath = CaptureBrushPath(
                points: brushPath.points.map { overlayPoint($0, selection: selection) }
            )
        }
        if let stroke = annotation.mosaicStroke {
            overlay.mosaicStroke = CaptureMosaicStroke(
                points: stroke.points.map { overlayPoint($0, selection: selection) }
            )
        }
        return overlay
    }

    private func overlayPoint(_ point: NSPoint, selection: NSRect) -> NSPoint {
        NSPoint(x: point.x + selection.minX, y: point.y + selection.minY)
    }

    private func assertPreview(
        _ preview: (image: NSImage, drawRect: NSRect),
        matchesCropFrom expected: NSImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: preview.drawRect))
        XCTAssertEqual(try rgbaBytes(in: preview.image), try rgbaBytes(in: expectedCrop), file: file, line: line)
    }

    private func imageBytesDiffer(_ lhs: NSImage, _ rhs: NSImage) throws -> Bool {
        try rgbaBytes(in: lhs) != rgbaBytes(in: rhs)
    }

    private func averagePixelDistance(_ lhs: NSImage, _ rhs: NSImage) throws -> Double {
        let lhsBytes = try rgbaBytes(in: lhs)
        let rhsBytes = try rgbaBytes(in: rhs)
        XCTAssertEqual(lhsBytes.count, rhsBytes.count)
        guard lhsBytes.count == rhsBytes.count, !lhsBytes.isEmpty else {
            return .infinity
        }

        var total = 0
        for index in stride(from: 0, to: lhsBytes.count, by: 4) {
            total += abs(Int(lhsBytes[index]) - Int(rhsBytes[index]))
            total += abs(Int(lhsBytes[index + 1]) - Int(rhsBytes[index + 1]))
            total += abs(Int(lhsBytes[index + 2]) - Int(rhsBytes[index + 2]))
            total += abs(Int(lhsBytes[index + 3]) - Int(rhsBytes[index + 3]))
        }
        return Double(total) / Double(lhsBytes.count / 4)
    }
}
