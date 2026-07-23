import AppKit
import XCTest
@testable import xxsnap

@MainActor
final class ScrollCapturePresentationTests: XCTestCase {
    func testStepButtonsUseMatchingCompactIconSize() {
        let controller = makeController()

        XCTAssertEqual(controller.test_startButtonImageSize, NSSize(width: 20, height: 20))
        XCTAssertEqual(controller.test_stopButtonImageSize, NSSize(width: 20, height: 20))
    }

    func testSingleStepGuideUsesBlueWhiteStyleAndHidesAfterFirstAcceptedStep() {
        var directions: [ScrollCaptureDirection] = []
        let controller = makeController(language: .zhHans, onStep: { directions.append($0) })
        controller.start()

        XCTAssertTrue(controller.test_stepGuideIsVisible)
        XCTAssertEqual(controller.test_stepGuideText, "引导提示：请点击进行单步滚动")
        XCTAssertEqual(controller.test_stepGuideBackgroundColor, .systemBlue)
        XCTAssertEqual(controller.test_stepGuideTextColor, .white)
        XCTAssertLessThan(controller.test_stepGuideFrame.width, 220)
        assertStepGuideTextFits(controller)
        XCTAssertLessThanOrEqual(controller.test_stepGuideFrame.maxY, controller.test_stepToolbarFrame.minY)
        XCTAssertEqual(controller.test_stepGuidePointerDirection, .up)
        XCTAssertEqual(controller.test_stepGuidePointerHeight, 8)

        controller.setStepControlState(.ready(directionLocked: false))
        controller.test_triggerStart()

        XCTAssertEqual(directions, [.down])
        XCTAssertFalse(controller.test_stepGuideIsVisible)
    }

    func testSingleStepGuideUsesEnglishCopy() {
        let controller = makeController(language: .english)
        controller.start()

        XCTAssertEqual(controller.test_stepGuideText, "Guide: Click for single-step scrolling")
        assertStepGuideTextFits(controller)
        XCTAssertLessThan(controller.test_stepGuideFrame.width, 245)
    }

    private func assertStepGuideTextFits(
        _ controller: ScrollCapturePresentationController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let measuringLabel = NSTextField(labelWithString: controller.test_stepGuideText)
        measuringLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        XCTAssertGreaterThanOrEqual(
            controller.test_stepGuideTextFrame.width,
            measuringLabel.fittingSize.width + 4,
            file: file,
            line: line
        )
        XCTAssertEqual(
            controller.test_stepGuideLineBreakMode,
            .byClipping,
            file: file,
            line: line
        )
    }

    func testNonFullscreenStepGuideUsesSpaceBelowToolbarAndPointsUp() {
        let placement = ScrollCapturePresentationController.stepGuidePlacement(
            stepToolbarFrame: NSRect(x: 300, y: 100, width: 168, height: 32),
            selectionFrame: NSRect(x: 100, y: 180, width: 600, height: 400),
            size: NSSize(width: 240, height: 42),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 700)
        )

        XCTAssertEqual(placement.frame.maxY, 96, accuracy: 0.5)
        XCTAssertEqual(placement.pointerDirection, .up)
    }

    func testNonFullscreenStepGuideFallsBackAboveWhenSpaceBelowIsInsufficient() {
        let placement = ScrollCapturePresentationController.stepGuidePlacement(
            stepToolbarFrame: NSRect(x: 300, y: 5, width: 168, height: 32),
            selectionFrame: NSRect(x: 100, y: 80, width: 600, height: 400),
            size: NSSize(width: 240, height: 42),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 700)
        )

        XCTAssertEqual(placement.frame.minY, 41, accuracy: 0.5)
        XCTAssertEqual(placement.pointerDirection, .down)
    }

    func testFullscreenStepGuideStaysAboveToolbarAndPointsDown() {
        let visible = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let placement = ScrollCapturePresentationController.stepGuidePlacement(
            stepToolbarFrame: NSRect(x: 300, y: 100, width: 168, height: 32),
            selectionFrame: visible,
            size: NSSize(width: 240, height: 42),
            visibleFrame: visible
        )

        XCTAssertEqual(placement.frame.minY, 136, accuracy: 0.5)
        XCTAssertEqual(placement.pointerDirection, .down)
    }

    func testWarningUsesSameBlackAndYellowToastStyleAsBoundaryNotice() {
        let controller = makeController()

        controller.setWarning("No page movement detected")

        XCTAssertEqual(controller.test_warningBackgroundColor, .clear)
        XCTAssertEqual(controller.test_warningCornerRadius, 11)
        XCTAssertEqual(controller.test_warningTextBackgroundColor, .black)
        XCTAssertFalse(controller.test_warningUsesVisualEffectBackdrop)
        XCTAssertEqual(controller.test_warningTextAlignment, .left)
        XCTAssertEqual(controller.test_warningFontSize, 13)
        XCTAssertEqual(
            controller.test_warningTextFrame.midY,
            controller.test_warningIconFrame.midY - 3
        )
        XCTAssertEqual(controller.test_warningFrame.height, 44)
        XCTAssertGreaterThanOrEqual(controller.test_warningFrame.width, 252)
        XCTAssertFalse(controller.test_warningWraps)
        let warningYellow = NSColor(srgbRed: 1, green: 176 / 255, blue: 32 / 255, alpha: 1)
        XCTAssertEqual(controller.test_warningIconTintColor, warningYellow)
        XCTAssertEqual(controller.test_warningAccentColor, warningYellow)
        XCTAssertFalse(controller.test_warningIgnoresMouseEvents)

        controller.test_triggerWarningClose()
        XCTAssertNil(controller.test_warningText)
    }

    func testStepToolbarAnchorsBelowScrollButtonAndFallsBackAbove() {
        let visible = NSRect(x: 0, y: 0, width: 800, height: 600)
        let size = NSSize(width: 168, height: 32)
        let selection = NSRect(x: 180, y: 150, width: 440, height: 300)
        let toolbarAbove = NSRect(x: 260, y: 466, width: 360, height: 28)
        let middleButton = NSRect(x: 400, y: 466, width: 28, height: 28)
        let below = ScrollCapturePresentationController.stepToolbarFrame(
            anchoredTo: middleButton,
            toolbarFrame: toolbarAbove,
            selectionFrame: selection,
            size: size,
            visibleFrame: visible
        )
        XCTAssertEqual(below.midX, middleButton.midX, accuracy: 0.5)
        XCTAssertEqual(below.minY, toolbarAbove.maxY + 6, accuracy: 0.5)
        XCTAssertFalse(below.intersects(toolbarAbove))
        XCTAssertFalse(below.intersects(selection))

        let toolbarBelow = NSRect(x: 260, y: 110, width: 360, height: 28)
        let bottomButton = NSRect(x: 400, y: 110, width: 28, height: 28)
        let above = ScrollCapturePresentationController.stepToolbarFrame(
            anchoredTo: bottomButton,
            toolbarFrame: toolbarBelow,
            selectionFrame: selection,
            size: size,
            visibleFrame: visible
        )
        XCTAssertEqual(above.midX, bottomButton.midX, accuracy: 0.5)
        XCTAssertEqual(above.maxY, toolbarBelow.minY - 6, accuracy: 0.5)
        XCTAssertFalse(above.intersects(toolbarBelow))
        XCTAssertFalse(above.intersects(selection))
    }

    func testFullscreenStepToolbarStaysInsideScreenWithoutCoveringMainToolbar() {
        let visible = NSRect(x: 0, y: 0, width: 1280, height: 720)
        let toolbar = NSRect(x: 420, y: 20, width: 440, height: 28)
        let button = NSRect(x: 640, y: 20, width: 28, height: 28)

        let result = ScrollCapturePresentationController.stepToolbarFrame(
            anchoredTo: button,
            toolbarFrame: toolbar,
            selectionFrame: visible,
            size: NSSize(width: 168, height: 32),
            visibleFrame: visible
        )

        XCTAssertTrue(visible.contains(result))
        XCTAssertFalse(result.intersects(toolbar))
    }

    func testStepToolbarNeverMovesToTheSideWhenVerticalSpaceIsTight() {
        let visible = NSRect(x: 0, y: 0, width: 800, height: 100)
        let toolbar = NSRect(x: 260, y: 34, width: 360, height: 28)
        let button = NSRect(x: 400, y: 34, width: 28, height: 28)

        let result = ScrollCapturePresentationController.stepToolbarFrame(
            anchoredTo: button,
            toolbarFrame: toolbar,
            selectionFrame: visible,
            size: NSSize(width: 168, height: 80),
            visibleFrame: visible
        )

        XCTAssertEqual(result.midX, button.midX, accuracy: 0.5)
    }

    func testVisibleUpSelectionReportsTopBoundary() throws {
        var directions: [ScrollCaptureDirection] = []
        let selection = NSRect(x: 200, y: 200, width: 300, height: 240)
        let controller = makeController(
            language: .zhHans,
            selectionFrame: selection,
            onStep: { directions.append($0) }
        )

        controller.setStepControlState(.ready(directionLocked: false))
        XCTAssertTrue(controller.test_directionControlIsEnabled)
        XCTAssertTrue(controller.test_startButtonIsEnabled)
        XCTAssertEqual(controller.test_startButtonTint, .systemBlue)

        controller.test_selectDirection(.up)
        controller.test_triggerStart()
        XCTAssertEqual(directions, [.up])

        controller.setStepControlState(.executing)
        XCTAssertFalse(controller.test_directionControlIsEnabled)
        XCTAssertFalse(controller.test_startButtonIsEnabled)
        XCTAssertEqual(controller.test_startButtonTint, .black)
        XCTAssertNil(controller.test_startButtonImageSize)
        XCTAssertTrue(controller.test_stepProgressIsVisible)

        controller.setStepControlState(.boundary)
        XCTAssertNil(controller.test_warningText)
        XCTAssertEqual(controller.test_boundaryAlertMessage, "已经到顶")
        XCTAssertNil(controller.test_boundaryAlertInformation)
        XCTAssertNil(controller.test_boundaryAlertButtonTitle)
        XCTAssertEqual(controller.test_boundaryAlertActionButtonCount, 0)
        XCTAssertEqual(controller.test_boundaryAlertCloseAccessibilityLabel, "关闭提示")
        XCTAssertEqual(controller.test_boundaryAlertCornerRadius, 11)
        XCTAssertEqual(controller.test_boundaryAlertPanelBackgroundColor, .clear)
        XCTAssertEqual(controller.test_boundaryAlertTextBackgroundColor, .black)
        XCTAssertEqual(controller.test_boundaryAlertTextColor, .white)
        let warningYellow = NSColor(srgbRed: 1, green: 176 / 255, blue: 32 / 255, alpha: 1)
        XCTAssertEqual(controller.test_boundaryAlertIconTintColor, warningYellow)
        XCTAssertEqual(controller.test_boundaryAlertAccentColor, warningYellow)
        XCTAssertEqual(
            controller.test_boundaryAlertTextFrame.midY,
            controller.test_boundaryAlertIconFrame.midY - 1
        )
        XCTAssertEqual(controller.test_boundaryAlertIconDescription, "已经到顶")
        XCTAssertTrue(controller.test_boundaryAutoDismissScheduled)
        let alertFrame = try XCTUnwrap(controller.test_boundaryAlertFrame)
        XCTAssertEqual(alertFrame.size, NSSize(width: 252, height: 44))
        XCTAssertEqual(alertFrame.midX, selection.midX, accuracy: 0.5)
        XCTAssertEqual(alertFrame.midY, selection.midY, accuracy: 0.5)
        XCTAssertFalse(controller.test_startButtonIsEnabled)
        XCTAssertEqual(controller.test_startButtonTint, .disabledControlTextColor)
        controller.test_triggerStart()
        XCTAssertEqual(directions, [.up])
        controller.test_triggerBoundaryAlertClose()
        XCTAssertNil(controller.test_boundaryAlertMessage)
        XCTAssertFalse(controller.test_boundaryAutoDismissScheduled)
        XCTAssertFalse(controller.test_startButtonIsEnabled)

        controller.setStepControlState(.ready(directionLocked: true))
        XCTAssertNil(controller.test_warningText)
        XCTAssertNil(controller.test_boundaryAlertMessage)
        XCTAssertFalse(controller.test_directionControlIsEnabled)
        XCTAssertTrue(controller.test_startButtonIsEnabled)
        XCTAssertEqual(controller.test_startButtonTint, .systemBlue)
        XCTAssertEqual(controller.test_startButtonImageSize, NSSize(width: 20, height: 20))
        XCTAssertFalse(controller.test_stepProgressIsVisible)
    }

    func testVisibleDownSelectionReportsBottomBoundary() {
        var directions: [ScrollCaptureDirection] = []
        let controller = makeController(language: .zhHans, onStep: { directions.append($0) })

        controller.setStepControlState(.ready(directionLocked: false))
        controller.test_selectDirection(.down)
        controller.test_triggerStart()
        XCTAssertEqual(directions, [.down])

        controller.setStepControlState(.boundary)
        XCTAssertNil(controller.test_warningText)
        XCTAssertEqual(controller.test_boundaryAlertMessage, "已经到底")
        XCTAssertNil(controller.test_boundaryAlertInformation)
        XCTAssertNil(controller.test_boundaryAlertButtonTitle)
        XCTAssertEqual(controller.test_boundaryAlertActionButtonCount, 0)
        XCTAssertEqual(controller.test_boundaryAlertCloseAccessibilityLabel, "关闭提示")
        XCTAssertEqual(controller.test_boundaryAlertIconDescription, "已经到底")
        XCTAssertFalse(controller.test_startButtonIsEnabled)
        XCTAssertEqual(controller.test_startButtonTint, .disabledControlTextColor)
    }

    func testBoundaryToastCentersOnSelectionIndependentlyOfPreviewSize() throws {
        let selection = NSRect(x: 200, y: 200, width: 300, height: 240)
        let controller = makeController(selectionFrame: selection)
        controller.updatePreview(
            NSImage(size: NSSize(width: 16, height: 600)),
            following: .bottom,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 1_445, outputHeight: 61_869)
        )

        controller.test_selectDirection(.up)
        controller.setStepControlState(.boundary)

        XCTAssertNil(controller.test_warningText)
        XCTAssertEqual(controller.test_boundaryAlertMessage, "Already at the top")
        XCTAssertNil(controller.test_boundaryAlertInformation)
        XCTAssertNil(controller.test_boundaryAlertButtonTitle)
        XCTAssertEqual(controller.test_boundaryAlertActionButtonCount, 0)
        XCTAssertEqual(controller.test_boundaryAlertCloseAccessibilityLabel, "Dismiss")
        XCTAssertEqual(controller.test_boundaryAlertIconDescription, "Already at the top")
        let alertFrame = try XCTUnwrap(controller.test_boundaryAlertFrame)
        XCTAssertEqual(alertFrame.midX, selection.midX, accuracy: 0.5)
        XCTAssertEqual(alertFrame.midY, selection.midY, accuracy: 0.5)

        controller.test_triggerBoundaryAlertClose()
        XCTAssertNil(controller.test_boundaryAlertMessage)
    }

    func testPreviewFrameBottomAlignsWithNonFullscreenSelection() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let selection = NSRect(x: 360, y: 250, width: 240, height: 180)
        let result = ScrollCapturePresentationController.previewFrame(
            selection: selection,
            previewSize: NSSize(width: 220, height: 260),
            visibleFrame: visible
        )
        XCTAssertEqual(result.minY, selection.minY, accuracy: 0.5)
        XCTAssertFalse(result.intersects(selection))
    }

    func testPreviewFrameUsesLeftWhenRightDoesNotFit() {
        let result = ScrollCapturePresentationController.previewFrame(
            selection: NSRect(x: 650, y: 180, width: 300, height: 260),
            previewSize: NSSize(width: 220, height: 280),
            visibleFrame: NSRect(x: 0, y: 0, width: 1000, height: 700)
        )
        XCTAssertEqual(result.maxX, 638)
    }

    func testPreviewFrameStaysOnSideInsteadOfUsingAboveOrBelowSpace() {
        let visible = NSRect(x: 0, y: 0, width: 800, height: 800)
        let size = NSSize(width: 500, height: 140)
        for selection in [
            NSRect(x: 100, y: 100, width: 600, height: 200),
            NSRect(x: 100, y: 500, width: 600, height: 200),
        ] {
            let result = ScrollCapturePresentationController.previewFrame(
                selection: selection,
                previewSize: size,
                visibleFrame: visible
            )
            XCTAssertGreaterThanOrEqual(result.minX, selection.maxX)
            XCTAssertFalse(result.intersects(selection))
        }
    }

    func testPreviewFrameFallsBackInsideAndClampsNegativeOriginDisplay() {
        let visible = NSRect(x: -1440, y: -60, width: 1440, height: 900)
        let selection = NSRect(x: -1430, y: -50, width: 1420, height: 880)
        let result = ScrollCapturePresentationController.previewFrame(
            selection: selection,
            previewSize: NSSize(width: 500, height: 700),
            visibleFrame: visible
        )
        XCTAssertTrue(visible.contains(result))
        XCTAssertTrue(selection.intersects(result))
    }

    func testFullScreenPreviewBottomAlignsWithVisibleFrame() {
        let screen = NSRect(x: 0, y: 0, width: 1280, height: 720)
        let result = ScrollCapturePresentationController.previewFrame(
            selection: screen,
            previewSize: NSSize(width: 360, height: 500),
            visibleFrame: screen
        )
        XCTAssertTrue(screen.contains(result))
        XCTAssertEqual(result.minY, screen.minY, accuracy: 0.5)
    }

    func testPreviewPanelNeverInterceptsFullScreenScrollEvents() {
        let fullscreen = NSRect(x: 0, y: 0, width: 1280, height: 720)
        let controller = makeController(selectionFrame: fullscreen, visibleFrame: fullscreen)

        XCTAssertTrue(controller.test_previewIgnoresMouseEvents)
    }

    func testNonFullscreenPreviewShrinksToRemainOutsideSelection() {
        let visible = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let selection = NSRect(x: 80, y: 120, width: 850, height: 600)
        let result = ScrollCapturePresentationController.previewFrame(
            selection: selection,
            previewSize: NSSize(width: 300, height: 480),
            visibleFrame: visible
        )

        XCTAssertTrue(visible.contains(result))
        XCTAssertFalse(result.intersects(selection))
        XCTAssertLessThan(result.width, 300)
        XCTAssertGreaterThanOrEqual(result.width, 120)
    }

    func testControlPanelIsNonactivatingAndLifecycleIsIdempotent() {
        var finishes = 0
        var cancels = 0
        let toolbar = NSRect(x: 100, y: 200, width: 480, height: 28)
        let finish = NSRect(x: 388, y: 204, width: 20, height: 20)
        let cancel = NSRect(x: 444, y: 204, width: 20, height: 20)
        let controller = ScrollCapturePresentationController(
            toolbarFrame: toolbar,
            finishButtonFrame: finish,
            cancelButtonFrame: cancel,
            selectionFrame: NSRect(x: 200, y: 240, width: 400, height: 300),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            language: .english,
            onFinish: { finishes += 1 },
            onCancel: { cancels += 1 }
        )
        XCTAssertTrue(controller.test_controlStyleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(controller.test_controlFrame, toolbar)
        XCTAssertTrue(controller.test_controlCanBecomeKey)
        XCTAssertFalse(controller.test_controlIsOpaque)
        XCTAssertEqual(controller.test_controlBackgroundColor, .clear)
        XCTAssertFalse(controller.test_controlIgnoresMouseEvents)
        XCTAssertTrue(controller.test_terminalHitPanelsCanBecomeKey)
        XCTAssertEqual(controller.test_stepToolbarFrame.maxY, toolbar.minY - 6, accuracy: 0.5)
        XCTAssertFalse(controller.test_stepToolbarFrame.intersects(toolbar))
        XCTAssertFalse(controller.test_stepToolbarFrame.intersects(NSRect(x: 200, y: 240, width: 400, height: 300)))
        XCTAssertEqual(controller.test_cancelButtonFrame, cancel)
        XCTAssertEqual(controller.test_controlHitTargetCount, 3)
        XCTAssertTrue(controller.test_controlHitTargetsAreTransparent)
        XCTAssertEqual(controller.test_interactiveWindowFrames, [toolbar, controller.test_stepToolbarFrame])
        XCTAssertFalse(controller.test_toolbarPointIsInteractive(NSPoint(x: finish.midX, y: finish.midY)))
        XCTAssertTrue(controller.test_toolbarPointIsInteractive(NSPoint(x: cancel.midX, y: cancel.midY)))
        XCTAssertFalse(controller.test_toolbarPointIsInteractive(NSPoint(x: toolbar.minX + 20, y: toolbar.midY)))
        XCTAssertEqual(controller.test_finishButtonToolTip, L10n(language: .english).text(.finishScrollCapture))
        XCTAssertEqual(controller.test_cancelButtonToolTip, L10n(language: .english).text(.cancel))
        XCTAssertEqual(controller.test_finishAccessibilityLabel, L10n(language: .english).text(.finishScrollCapture))
        XCTAssertEqual(controller.test_cancelAccessibilityLabel, L10n(language: .english).text(.cancel))
        XCTAssertEqual(controller.test_accessibilityRoles, [.button, .button, .button])
        controller.start()
        XCTAssertTrue(controller.test_hasVisiblePanels)
        controller.test_triggerFinish()
        controller.test_triggerFinish()
        controller.test_triggerCancel()
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(cancels, 0)
        controller.stop()
        controller.stop()
        XCTAssertFalse(controller.test_hasVisiblePanels)
        XCTAssertTrue(controller.test_panelsAreClosedAndDetached)
        XCTAssertNil(controller.test_previewImage)
        XCTAssertNil(controller.test_warningText)
        controller.start()
        XCTAssertFalse(controller.test_hasVisiblePanels)
    }

    func testTerminalActionsCanBeRearmedAfterRecoverableFailure() {
        var finishes = 0
        var cancels = 0
        let controller = ScrollCapturePresentationController(
            toolbarFrame: NSRect(x: 100, y: 100, width: 400, height: 28),
            finishButtonFrame: NSRect(x: 300, y: 104, width: 20, height: 20),
            cancelButtonFrame: NSRect(x: 350, y: 104, width: 20, height: 20),
            selectionFrame: NSRect(x: 100, y: 150, width: 400, height: 300),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 700),
            language: .english,
            onFinish: { finishes += 1 },
            onCancel: { cancels += 1 }
        )
        controller.start()
        controller.test_triggerFinish()
        controller.resetTerminalActionsForRetry()
        controller.test_triggerFinish()
        controller.resetTerminalActionsForRetry()
        controller.test_triggerCancel()

        XCTAssertEqual(finishes, 2)
        XCTAssertEqual(cancels, 1)
    }

    func testBottomPreviewKeepsLatestLongThumbnailVisible() {
        let controller = makeController()
        controller.setStepControlState(.executing)
        controller.updatePreview(NSImage(size: NSSize(width: 240, height: 900)), following: .bottom)
        XCTAssertTrue(controller.test_isFollowingTail)
        XCTAssertTrue(controller.test_visibleRect.contains(controller.test_viewportIndicatorFrame))
        controller.updatePreview(NSImage(size: NSSize(width: 240, height: 1200)), following: .bottom)
        XCTAssertTrue(controller.test_isFollowingTail)
        XCTAssertTrue(controller.test_visibleRect.contains(controller.test_viewportIndicatorFrame))
        controller.setWarning("Low confidence")
        XCTAssertEqual(controller.test_warningText, "Low confidence")
        controller.clearWarning()
        XCTAssertNil(controller.test_warningText)
        XCTAssertNotNil(controller.test_previewImage)
        controller.updatePreview(NSImage(size: NSSize(width: 240, height: 1400)), following: .bottom)
        XCTAssertEqual(controller.test_previewImageFrame.maxY, controller.test_visibleRect.maxY, accuracy: 0.5)
    }

    func testInitialPreviewPreservesAspectRatioInsteadOfExpandingToPanelHeight() {
        let controller = makeController()
        let image = NSImage(size: NSSize(width: 880, height: 546))

        controller.updatePreview(
            image,
            following: .bottom,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 1_092, outputHeight: 1_092)
        )

        let expectedHeight = 546 * controller.test_contentWidth / 880
        XCTAssertEqual(controller.test_documentHeight, expectedHeight, accuracy: 0.5)
        XCTAssertEqual(controller.test_documentHeight, controller.test_visibleRect.height, accuracy: 0.5)
        XCTAssertEqual(
            controller.test_viewportIndicatorFrame.height,
            controller.test_previewImageFrame.height,
            accuracy: 0.5
        )
    }

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
        XCTAssertEqual(
            controller.test_previewImageFrame.midX,
            controller.test_visibleRect.midX,
            accuracy: 0.5
        )
        XCTAssertEqual(
            controller.test_viewportIndicatorFrame.minX,
            controller.test_previewImageFrame.minX,
            accuracy: 0.5
        )
        XCTAssertEqual(
            controller.test_previewFrame.width,
            controller.test_previewImageFrame.width,
            accuracy: 0.5
        )
    }

    func testUpPreviewKeepsLatestLongThumbnailVisible() {
        let controller = makeController()
        controller.setStepControlState(.executing)
        let width = controller.test_contentWidth
        controller.updatePreview(NSImage(size: NSSize(width: width, height: 700)), following: .bottom)
        controller.updatePreview(NSImage(size: NSSize(width: width, height: 900)), following: .top)
        XCTAssertTrue(controller.test_isFollowingTail)
        XCTAssertEqual(controller.test_visibleRect.minY, 0, accuracy: 0.5)

        controller.updatePreview(NSImage(size: NSSize(width: width, height: 1100)), following: .top)
        XCTAssertTrue(controller.test_isFollowingTail)
        XCTAssertEqual(controller.test_visibleRect.minY, 0, accuracy: 0.5)
        controller.updatePreview(NSImage(size: NSSize(width: width, height: 1300)), following: .top)
        XCTAssertEqual(controller.test_visibleRect.minY, 0, accuracy: 0.5)
        XCTAssertTrue(controller.test_visibleRect.contains(controller.test_viewportIndicatorFrame))
    }

    func testViewportIndicatorTracksCurrentAppendedPosition() {
        let controller = makeController()
        controller.setStepControlState(.executing)
        let width = controller.test_contentWidth
        let image = NSImage(size: NSSize(width: width, height: 800))
        let viewport = ScrollCapturePreviewViewport(viewportHeight: 200, outputHeight: 800)
        controller.updatePreview(image, following: .bottom, viewport: viewport)
        let expectedHeight = controller.test_documentHeight * 200 / 800
        XCTAssertEqual(controller.test_viewportIndicatorFrame.height, expectedHeight, accuracy: 0.5)
        XCTAssertEqual(
            controller.test_viewportIndicatorFrame.maxY,
            controller.test_previewImageFrame.maxY,
            accuracy: 0.5
        )

        controller.updatePreview(image, following: .top, viewport: viewport)
        XCTAssertEqual(
            controller.test_viewportIndicatorFrame.minY,
            controller.test_previewImageFrame.minY,
            accuracy: 0.5
        )
        XCTAssertEqual(controller.test_viewportIndicatorFrame.height, expectedHeight, accuracy: 0.5)
    }

    func testGrowingPreviewKeepsCompleteImageAndIndicatorVisible() {
        let controller = makeController()
        let width = controller.test_contentWidth
        controller.updatePreview(
            NSImage(size: NSSize(width: width, height: 240)),
            following: .bottom,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 800, outputHeight: 800)
        )
        let initialIndicatorY = controller.test_viewportIndicatorFrame.minY
        controller.setStepControlState(.executing)

        controller.updatePreview(
            NSImage(size: NSSize(width: width, height: 720)),
            following: .bottom,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 800, outputHeight: 2_400)
        )

        XCTAssertGreaterThan(controller.test_viewportIndicatorFrame.minY, initialIndicatorY)
        XCTAssertEqual(controller.test_visibleRect.minY, 0, accuracy: 0.5)
        XCTAssertEqual(controller.test_reviewOffset, 0, accuracy: 0.5)
        XCTAssertTrue(controller.test_visibleRect.contains(controller.test_previewImageFrame))
        XCTAssertTrue(controller.test_previewImageFrame.contains(controller.test_viewportIndicatorFrame))
    }

    func testPreviewResizeKeepsSelectionBottomAligned() {
        let selection = NSRect(x: 200, y: 180, width: 300, height: 300)
        let controller = makeController(selectionFrame: selection)

        controller.updatePreview(NSImage(size: NSSize(width: 300, height: 240)), following: .bottom)
        XCTAssertEqual(controller.test_previewFrame.minY, selection.minY, accuracy: 0.5)

        controller.updatePreview(NSImage(size: NSSize(width: 300, height: 3_000)), following: .bottom)
        XCTAssertEqual(controller.test_previewFrame.minY, selection.minY, accuracy: 0.5)
    }

    func testUpwardPreviewGrowthKeepsSelectionBottomAligned() {
        let selection = NSRect(x: 200, y: 180, width: 300, height: 300)
        let controller = makeController(selectionFrame: selection)
        controller.test_selectDirection(.up)

        controller.updatePreview(NSImage(size: NSSize(width: 300, height: 240)), following: .bottom)
        XCTAssertEqual(controller.test_previewFrame.minY, selection.minY, accuracy: 0.5)

        controller.updatePreview(NSImage(size: NSSize(width: 300, height: 3_000)), following: .top)
        XCTAssertEqual(controller.test_previewFrame.minY, selection.minY, accuracy: 0.5)
    }

    func testFirstUpwardWheelAnchorsInitialPreviewAtBottom() {
        let controller = makeController()
        let availablePreviewFrame = controller.test_previewFrame
        controller.test_selectDirection(.up)
        controller.updatePreview(
            NSImage(size: NSSize(width: 240, height: 120)),
            following: .bottom
        )
        XCTAssertEqual(controller.test_previewFrame.size, controller.test_previewImageFrame.size)

        XCTAssertEqual(
            controller.test_previewImageFrame.maxY,
            controller.test_visibleRect.maxY,
            accuracy: 0.5
        )
        XCTAssertEqual(controller.test_previewFrame.minY, availablePreviewFrame.minY, accuracy: 0.5)
        let initialBottom = controller.test_previewFrame.minY
        controller.setStepControlState(.executing)
        controller.updatePreview(
            NSImage(size: NSSize(width: 240, height: 240)),
            following: .top,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 120, outputHeight: 240)
        )
        XCTAssertEqual(
            controller.test_viewportIndicatorFrame.minY,
            controller.test_previewImageFrame.minY,
            accuracy: 0.5
        )
        XCTAssertEqual(controller.test_previewFrame.minY, initialBottom, accuracy: 0.5)
    }

    func testFirstDownwardWheelKeepsPreviewBottomAligned() {
        let controller = makeController()
        let availablePreviewFrame = controller.test_previewFrame
        controller.updatePreview(
            NSImage(size: NSSize(width: 240, height: 120)),
            following: .bottom
        )
        XCTAssertEqual(controller.test_previewFrame.size, controller.test_previewImageFrame.size)

        XCTAssertEqual(
            controller.test_previewImageFrame.minY,
            controller.test_visibleRect.minY,
            accuracy: 0.5
        )
        XCTAssertEqual(controller.test_previewFrame.minY, availablePreviewFrame.minY, accuracy: 0.5)
        let initialBottom = controller.test_previewFrame.minY
        controller.setStepControlState(.executing)
        controller.updatePreview(
            NSImage(size: NSSize(width: 240, height: 240)),
            following: .bottom,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 120, outputHeight: 240)
        )
        XCTAssertEqual(
            controller.test_viewportIndicatorFrame.maxY,
            controller.test_previewImageFrame.maxY,
            accuracy: 0.5
        )
        XCTAssertEqual(controller.test_previewFrame.minY, initialBottom, accuracy: 0.5)
    }

    func testInitialViewportIndicatorMovesBeforeFirstFrameIsAppended() {
        let controller = makeController()
        let width = controller.test_contentWidth
        controller.updatePreview(
            NSImage(size: NSSize(width: width, height: 546)),
            following: .bottom,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 546, outputHeight: 1_092)
        )

        controller.moveViewportIndicator(ScrollCaptureScrollActivity(
            direction: .down,
            distance: 24,
            viewportDirection: .down
        ))

        XCTAssertLessThan(
            controller.test_viewportIndicatorFrame.height,
            controller.test_previewImageFrame.height
        )
        XCTAssertGreaterThan(
            controller.test_viewportIndicatorFrame.minY,
            controller.test_previewImageFrame.minY
        )
    }

    func testNonFullscreenPreviewRemainsOnItsOriginalSideWhenThumbnailResizes() {
        let selection = NSRect(x: 200, y: 200, width: 300, height: 240)
        let controller = makeController(selectionFrame: selection)
        let initialSideFrame = controller.test_previewFrame
        XCTAssertGreaterThanOrEqual(initialSideFrame.minX, selection.maxX)

        controller.updatePreview(
            NSImage(size: NSSize(width: 240, height: 2_400)),
            following: .bottom,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 400, outputHeight: 4_800)
        )

        XCTAssertGreaterThanOrEqual(controller.test_previewFrame.minX, selection.maxX)
        XCTAssertEqual(controller.test_previewFrame.minX, initialSideFrame.minX, accuracy: 0.5)
        XCTAssertFalse(controller.test_previewFrame.intersects(selection))
    }

    func testDynamicPreviewRespectsInitialAvoidanceRegionWidth() {
        let visible = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let selection = NSRect(x: 80, y: 120, width: 850, height: 600)
        let controller = makeController(selectionFrame: selection, visibleFrame: visible)
        let initialPreviewWidth = controller.test_previewFrame.width
        let image = NSImage(size: NSSize(width: 880, height: 546))

        XCTAssertFalse(controller.test_previewFrame.intersects(selection))

        controller.updatePreview(
            image,
            following: .bottom,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 1_092, outputHeight: 1_092)
        )

        XCTAssertTrue(visible.contains(controller.test_previewFrame))
        XCTAssertFalse(controller.test_previewFrame.intersects(selection))
        XCTAssertLessThanOrEqual(controller.test_previewFrame.width, initialPreviewWidth)
        XCTAssertEqual(
            controller.test_previewImageFrame.width / controller.test_previewImageFrame.height,
            image.size.width / image.size.height,
            accuracy: 0.001
        )
    }

    func testViewportIndicatorUsesOutputRatioWhenPreviewIsDownsampled() {
        let controller = makeController()
        controller.setStepControlState(.executing)
        let width = controller.test_contentWidth
        controller.updatePreview(
            NSImage(size: NSSize(width: width, height: 1_200)),
            following: .bottom,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 400, outputHeight: 2_400)
        )
        XCTAssertEqual(
            controller.test_viewportIndicatorFrame.height,
            controller.test_documentHeight * 400 / 2_400,
            accuracy: 0.5
        )
        XCTAssertEqual(
            controller.test_viewportIndicatorFrame.maxY,
            controller.test_previewImageFrame.maxY,
            accuracy: 0.5
        )
    }

    func testViewportIndicatorMovesContinuouslyWithWheelDirectionAndDistance() {
        let controller = makeController()
        let width = controller.test_contentWidth
        controller.updatePreview(
            NSImage(size: NSSize(width: width, height: 800)),
            following: .top,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 200, outputHeight: 800)
        )

        let scale = controller.test_documentHeight / 800
        let imageTop = controller.test_previewImageFrame.minY
        controller.moveViewportIndicator(
            ScrollCaptureScrollActivity(direction: .down, distance: 24)
        )
        XCTAssertEqual(controller.test_viewportIndicatorFrame.minY, imageTop + 20 * scale, accuracy: 0.5)

        controller.moveViewportIndicator(
            ScrollCaptureScrollActivity(direction: .down, distance: 12)
        )
        XCTAssertEqual(controller.test_viewportIndicatorFrame.minY, imageTop + 30 * scale, accuracy: 0.5)

        controller.moveViewportIndicator(
            ScrollCaptureScrollActivity(direction: .up, distance: 6)
        )
        XCTAssertEqual(controller.test_viewportIndicatorFrame.minY, imageTop + 25 * scale, accuracy: 0.5)
    }

    func testPreviewRefreshPreservesWheelDrivenViewportPosition() {
        let controller = makeController()
        controller.setStepControlState(.executing)
        let width = controller.test_contentWidth
        let image = NSImage(size: NSSize(width: width, height: 800))
        let viewport = ScrollCapturePreviewViewport(viewportHeight: 200, outputHeight: 800)
        controller.updatePreview(image, following: .bottom, viewport: viewport)

        controller.moveViewportIndicator(ScrollCaptureScrollActivity(
            direction: .up,
            distance: 120,
            viewportDirection: .up
        ))
        let wheelDrivenY = controller.test_viewportIndicatorFrame.minY
        XCTAssertLessThan(
            controller.test_viewportIndicatorFrame.maxY,
            controller.test_previewImageFrame.maxY
        )

        controller.updatePreview(image, following: .bottom, viewport: viewport)

        XCTAssertEqual(controller.test_viewportIndicatorFrame.minY, wheelDrivenY, accuracy: 0.5)
    }

    func testViewportIndicatorUsesPhysicalGestureDirectionNotDocumentDirection() {
        let controller = makeController()
        controller.test_selectDirection(.up)
        let width = controller.test_contentWidth
        controller.updatePreview(
            NSImage(size: NSSize(width: width, height: 800)),
            following: .bottom,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 200, outputHeight: 800)
        )

        controller.moveViewportIndicator(ScrollCaptureScrollActivity(
            direction: .down,
            distance: 120,
            viewportDirection: .up
        ))

        XCTAssertEqual(
            controller.test_viewportIndicatorFrame.minY,
            controller.test_previewImageFrame.minY + controller.test_documentHeight * 500 / 800,
            accuracy: 0.5
        )
    }

    func testViewportIndicatorWheelMovementClampsInsidePreviewDocument() {
        let controller = makeController()
        let width = controller.test_contentWidth
        controller.updatePreview(
            NSImage(size: NSSize(width: width, height: 800)),
            following: .top,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 200, outputHeight: 800)
        )

        controller.moveViewportIndicator(
            ScrollCaptureScrollActivity(direction: .up, distance: 10_000)
        )
        XCTAssertEqual(
            controller.test_viewportIndicatorFrame.minY,
            controller.test_previewImageFrame.minY,
            accuracy: 0.5
        )
        controller.moveViewportIndicator(
            ScrollCaptureScrollActivity(direction: .down, distance: 10_000)
        )
        XCTAssertEqual(
            controller.test_viewportIndicatorFrame.maxY,
            controller.test_previewImageFrame.maxY,
            accuracy: 0.5
        )
    }

    func testSuccessfulStepPreviewFollowsAcceptedEdge() {
        let controller = makeController()
        controller.setStepControlState(.executing)
        let width = controller.test_contentWidth
        controller.updatePreview(
            NSImage(size: NSSize(width: width, height: 800)),
            following: .top,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 200, outputHeight: 800)
        )
        controller.moveViewportIndicator(
            ScrollCaptureScrollActivity(direction: .down, distance: 120)
        )
        XCTAssertEqual(
            controller.test_viewportIndicatorFrame.minY,
            controller.test_previewImageFrame.minY + controller.test_documentHeight * 100 / 800,
            accuracy: 0.5
        )

        controller.updatePreview(
            NSImage(size: NSSize(width: width, height: 1_000)),
            following: .bottom,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 200, outputHeight: 1_000)
        )

        XCTAssertEqual(controller.test_viewportIndicatorFrame.maxY, controller.test_previewImageFrame.maxY, accuracy: 0.5)
        XCTAssertTrue(controller.test_visibleRect.intersects(controller.test_viewportIndicatorFrame))
    }

    func testTransparentControlTooltipsAreLocalizedInChinese() {
        let controller = makeController(language: .zhHans)
        XCTAssertEqual(controller.test_finishButtonToolTip, "结束滚动截图")
        XCTAssertEqual(controller.test_cancelButtonToolTip, "取消")
        XCTAssertEqual(controller.test_finishAccessibilityLabel, "结束滚动截图")
        XCTAssertEqual(controller.test_cancelAccessibilityLabel, "取消")
    }

    func testPreviewPanelNeverObscuresControlInFullscreenAndConstrainedLayouts() {
        let fullscreen = NSRect(x: 0, y: 0, width: 800, height: 600)
        let toolbar = NSRect(x: 200, y: 12, width: 400, height: 28)
        let controller = makeController(
            toolbarFrame: toolbar,
            selectionFrame: fullscreen,
            visibleFrame: fullscreen
        )
        XCTAssertFalse(controller.test_previewFrame.intersects(toolbar))
        XCTAssertFalse(controller.test_previewFrame.intersects(controller.test_stepToolbarFrame))
        XCTAssertTrue(fullscreen.contains(controller.test_previewFrame))
        XCTAssertEqual(controller.test_previewFrame.minY, fullscreen.minY, accuracy: 0.5)
        controller.updatePlacement(selectionFrame: fullscreen, visibleFrame: fullscreen)
        XCTAssertFalse(controller.test_previewFrame.intersects(toolbar))
        XCTAssertFalse(controller.test_previewFrame.intersects(controller.test_stepToolbarFrame))
        XCTAssertEqual(controller.test_previewFrame.minY, fullscreen.minY, accuracy: 0.5)

        let constrained = NSRect(x: 0, y: 0, width: 320, height: 240)
        let blockingToolbar = NSRect(x: 0, y: 100, width: 320, height: 40)
        let constrainedController = makeController(
            toolbarFrame: blockingToolbar,
            selectionFrame: constrained,
            visibleFrame: constrained
        )
        XCTAssertFalse(constrainedController.test_previewFrame.intersects(blockingToolbar))
        XCTAssertTrue(constrained.contains(constrainedController.test_previewFrame))
    }

    func testFullscreenPreviewAvoidsStepToolbarWhileBottomAligned() {
        let fullscreen = NSRect(x: 0, y: 0, width: 800, height: 600)
        let toolbar = NSRect(x: 100, y: 380, width: 560, height: 28)
        let scrollButton = NSRect(x: 420, y: 384, width: 20, height: 20)
        let controller = ScrollCapturePresentationController(
            toolbarFrame: toolbar,
            finishButtonFrame: scrollButton,
            cancelButtonFrame: NSRect(x: 620, y: 384, width: 20, height: 20),
            selectionFrame: fullscreen,
            visibleFrame: fullscreen,
            language: .english,
            onFinish: {},
            onCancel: {}
        )

        XCTAssertEqual(controller.test_stepToolbarFrame, NSRect(x: 346, y: 342, width: 168, height: 32))
        XCTAssertFalse(controller.test_previewFrame.intersects(controller.test_stepToolbarFrame))
        XCTAssertTrue(fullscreen.contains(controller.test_previewFrame))
        XCTAssertEqual(controller.test_previewFrame.minY, fullscreen.minY, accuracy: 0.5)

        controller.updatePlacement(selectionFrame: fullscreen, visibleFrame: fullscreen)
        XCTAssertFalse(controller.test_previewFrame.intersects(controller.test_stepToolbarFrame))
        XCTAssertTrue(fullscreen.contains(controller.test_previewFrame))
        XCTAssertEqual(controller.test_previewFrame.minY, fullscreen.minY, accuracy: 0.5)
    }

    func testNonFullscreenPreviewPrefersBottomAlignmentWhenToolbarSplitsSideRegion() {
        let visible = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let selection = NSRect(x: 200, y: 200, width: 300, height: 240)
        let toolbar = NSRect(x: 600, y: 190, width: 160, height: 28)
        let controller = ScrollCapturePresentationController(
            toolbarFrame: toolbar,
            finishButtonFrame: NSRect(x: 680, y: 194, width: 20, height: 20),
            cancelButtonFrame: NSRect(x: 728, y: 194, width: 20, height: 20),
            selectionFrame: selection,
            visibleFrame: visible,
            language: .english,
            onFinish: {},
            onCancel: {}
        )

        XCTAssertEqual(controller.test_previewFrame.minY, selection.minY, accuracy: 0.5)
        XCTAssertTrue(visible.contains(controller.test_previewFrame))
        XCTAssertFalse(controller.test_previewFrame.intersects(toolbar))
        XCTAssertFalse(controller.test_previewFrame.intersects(controller.test_stepToolbarFrame))
    }

    func testPreviewMaintainsSpacingFromAdjacentControlFrames() {
        let spacing: CGFloat = 12
        let visible = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let selection = NSRect(x: 100, y: 150, width: 300, height: 240)
        let toolbar = NSRect(x: 240, y: 160, width: 120, height: 28)
        let controller = ScrollCapturePresentationController(
            toolbarFrame: toolbar,
            finishButtonFrame: NSRect(x: 312, y: 164, width: 20, height: 20),
            cancelButtonFrame: NSRect(x: 332, y: 164, width: 20, height: 20),
            selectionFrame: selection,
            visibleFrame: visible,
            language: .english,
            onFinish: {},
            onCancel: {}
        )

        XCTAssertEqual(toolbar.minY - controller.test_stepToolbarFrame.maxY, 6, accuracy: 0.5)
        XCTAssertFalse(controller.test_previewFrame.intersects(toolbar.insetBy(dx: -spacing, dy: -spacing)))
        XCTAssertFalse(
            controller.test_previewFrame.intersects(
                controller.test_stepToolbarFrame.insetBy(dx: -spacing, dy: -spacing)
            )
        )
    }

    func testFullscreenPreviewEnforcesSpacingWhenControlFramesDoNotIntersectIt() {
        let spacing: CGFloat = 12
        let fullscreen = NSRect(x: 0, y: 0, width: 800, height: 600)
        let toolbar = NSRect(x: 100, y: 200, width: 380, height: 28)
        let controller = ScrollCapturePresentationController(
            toolbarFrame: toolbar,
            finishButtonFrame: NSRect(x: 200, y: 204, width: 20, height: 20),
            cancelButtonFrame: NSRect(x: 448, y: 204, width: 20, height: 20),
            selectionFrame: fullscreen,
            visibleFrame: fullscreen,
            language: .english,
            onFinish: {},
            onCancel: {}
        )

        XCTAssertFalse(controller.test_previewFrame.intersects(toolbar))
        XCTAssertFalse(controller.test_previewFrame.intersects(controller.test_stepToolbarFrame))
        XCTAssertFalse(controller.test_previewFrame.intersects(toolbar.insetBy(dx: -spacing, dy: -spacing)))
        XCTAssertFalse(
            controller.test_previewFrame.intersects(
                controller.test_stepToolbarFrame.insetBy(dx: -spacing, dy: -spacing)
            )
        )
        XCTAssertTrue(fullscreen.contains(controller.test_previewFrame))
        XCTAssertEqual(controller.test_previewFrame.minY, fullscreen.minY, accuracy: 0.5)
    }

    func testEveryLocalizedScrollCaptureWarningUsesOneLineAndFullTooltip() {
        let keys: [L10n.Key] = [
            .scrollCaptureLowConfidence,
            .scrollCaptureNoMovement,
            .scrollCaptureResourceLimit,
            .scrollCaptureFailure,
        ]
        for language in [AppLanguage.zhHans, .english] {
            let controller = makeController(language: language)
            let l10n = L10n(language: language)
            for key in keys {
                let warning = l10n.text(key)
                controller.setWarning(warning)
                XCTAssertEqual(controller.test_warningFrame.height, 44)
                XCTAssertFalse(controller.test_warningWraps)
                XCTAssertEqual(controller.test_warningFontSize, 13)
                XCTAssertEqual(controller.test_warningToolTip, warning)
            }
        }
    }

    func testStopRemovesObserverAndReleasesPreviewImage() {
        var controller: ScrollCapturePresentationController? = makeController()
        weak var weakImage: NSImage?
        weak let weakController = controller
        autoreleasepool {
            let image = NSImage(size: NSSize(width: 400, height: 1600))
            weakImage = image
            controller?.updatePreview(image, following: .bottom)
            controller?.test_userScroll(to: 120)
            XCTAssertEqual(controller?.test_reviewOffset ?? -1, 0, accuracy: 0.5)
            controller?.setWarning("cleanup warning")
            controller?.stop()
        }
        XCTAssertNil(weakImage)
        controller?.test_postBoundsChangeNotification()
        XCTAssertEqual(controller?.test_reviewOffset ?? -1, 0, accuracy: 0.5)
        XCTAssertFalse(controller?.test_hasBoundsObserver ?? true)
        XCTAssertNil(controller?.test_warningToolTip)
        controller?.updatePreview(NSImage(size: NSSize(width: 200, height: 800)), following: .bottom)
        controller?.setWarning("late")
        XCTAssertNil(controller?.test_previewImage)
        XCTAssertNil(controller?.test_warningText)
        controller = nil
        XCTAssertNil(weakController)
    }

    private func makeController(
        language: AppLanguage = .english,
        toolbarFrame: NSRect = NSRect(x: 100, y: 100, width: 400, height: 28),
        selectionFrame: NSRect = NSRect(x: 200, y: 200, width: 300, height: 240),
        visibleFrame: NSRect = NSRect(x: 0, y: 0, width: 1000, height: 700),
        onStep: @escaping (ScrollCaptureDirection) -> Void = { _ in }
    ) -> ScrollCapturePresentationController {
        ScrollCapturePresentationController(
            toolbarFrame: toolbarFrame,
            finishButtonFrame: NSRect(x: toolbarFrame.midX, y: toolbarFrame.minY + 4, width: 20, height: min(20, toolbarFrame.height)),
            cancelButtonFrame: NSRect(x: toolbarFrame.maxX - 28, y: toolbarFrame.minY + 4, width: 20, height: min(20, toolbarFrame.height)),
            selectionFrame: selectionFrame,
            visibleFrame: visibleFrame,
            language: language,
            onStep: onStep,
            onFinish: {},
            onCancel: {}
        )
    }
}
