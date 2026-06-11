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

    func testStrokeMenuHitTargetSelectsEveryMenuItem() {
        let menu = NSRect(x: 120, y: 80, width: 102, height: 104)

        for (index, rect) in SelectionToolbarState.strokeStyleMenuItemRects(in: menu, itemCount: 4).enumerated() {
            XCTAssertEqual(
                SelectionToolbarState.strokeMenuHitTarget(at: NSPoint(x: rect.midX, y: rect.midY), in: menu, itemCount: 4),
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

    func testAnnotationBorderMouseDownWinsOverSelectionResize() {
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

    func testColorSamplerCopyHintUsesLowercaseCAndHexText() {
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopyHintText, "按c复制HEX颜色值")
    }

    func testColorSamplerCopyHintFollowsCopyMode() {
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopyHintText(for: .hex), "按c复制HEX颜色值")
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopyHintText(for: .rgb), "按c复制RGB颜色值")
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

    private func makeTestImage(width: Int, height: Int, pixels: [UInt8], bitmapInfo: UInt32) -> CGImage {
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
