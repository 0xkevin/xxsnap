import AppKit
import XCTest
@testable import xxsnap

@MainActor
final class ScrollCapturePresentationTests: XCTestCase {
    func testOpenScrollCaptureControlsUpdateWhenLanguageChanges() {
        let controller = makeController(language: .zhHans)

        XCTAssertEqual(controller.test_finishButtonToolTip, L10n(language: .zhHans).text(.finishScrollCapture))
        XCTAssertEqual(controller.test_finishAccessibilityLabel, L10n(language: .zhHans).text(.finishScrollCapture))

        controller.updateLanguage(.english)

        XCTAssertEqual(controller.test_finishButtonToolTip, "Finish Scroll Capture")
        XCTAssertEqual(controller.test_finishAccessibilityLabel, "Finish Scroll Capture")
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

    func testBoundaryToastRetainsIndependentTopBoundaryPresentation() throws {
        let selection = NSRect(x: 200, y: 200, width: 300, height: 240)
        let controller = makeController(
            language: .zhHans,
            selectionFrame: selection
        )

        controller.test_showBoundaryAlert(isTopBoundary: true)
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
        XCTAssertEqual(alertFrame.height, 44)
        XCTAssertTrue(controller.test_boundaryAlertTextFits)
        XCTAssertEqual(alertFrame.midX, selection.midX, accuracy: 0.5)
        XCTAssertEqual(alertFrame.midY, selection.midY, accuracy: 0.5)
        controller.test_triggerBoundaryAlertClose()
        XCTAssertNil(controller.test_boundaryAlertMessage)
        XCTAssertFalse(controller.test_boundaryAutoDismissScheduled)
    }

    func testBoundaryToastCentersOnSelectionIndependentlyOfPreviewSize() throws {
        let selection = NSRect(x: 200, y: 200, width: 300, height: 240)
        let controller = makeController(selectionFrame: selection)
        controller.updatePreview(
            NSImage(size: NSSize(width: 16, height: 600)),
            following: .bottom,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 1_445, outputHeight: 61_869)
        )

        controller.test_showBoundaryAlert(isTopBoundary: true)

        XCTAssertNil(controller.test_warningText)
        XCTAssertEqual(controller.test_boundaryAlertMessage, "Already at the top")
        XCTAssertNil(controller.test_boundaryAlertInformation)
        XCTAssertNil(controller.test_boundaryAlertButtonTitle)
        XCTAssertEqual(controller.test_boundaryAlertActionButtonCount, 0)
        XCTAssertEqual(controller.test_boundaryAlertCloseAccessibilityLabel, "Dismiss")
        XCTAssertEqual(controller.test_boundaryAlertIconDescription, "Already at the top")
        XCTAssertTrue(controller.test_boundaryAlertTextFits)
        let alertFrame = try XCTUnwrap(controller.test_boundaryAlertFrame)
        XCTAssertEqual(alertFrame.midX, selection.midX, accuracy: 0.5)
        XCTAssertEqual(alertFrame.midY, selection.midY, accuracy: 0.5)

        controller.test_triggerBoundaryAlertClose()
        XCTAssertNil(controller.test_boundaryAlertMessage)
    }

    func testBoundaryToastDynamicallyFitsChineseAndEnglishCopy() throws {
        let selection = NSRect(x: 200, y: 200, width: 500, height: 300)
        let visible = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let chinese = makeController(
            language: .zhHans,
            selectionFrame: selection,
            visibleFrame: visible
        )
        chinese.test_showBoundaryAlert(isTopBoundary: false)
        let chineseFrame = try XCTUnwrap(chinese.test_boundaryAlertFrame)
        XCTAssertEqual(chinese.test_boundaryAlertMessage, "已经到底")
        XCTAssertTrue(chinese.test_boundaryAlertTextFits)

        let english = makeController(
            language: .english,
            selectionFrame: selection,
            visibleFrame: visible
        )
        english.test_showBoundaryAlert(isTopBoundary: false)
        let englishFrame = try XCTUnwrap(english.test_boundaryAlertFrame)
        XCTAssertEqual(english.test_boundaryAlertMessage, "Already at the bottom")
        XCTAssertTrue(english.test_boundaryAlertTextFits)
        XCTAssertGreaterThan(englishFrame.width, chineseFrame.width)
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
        let toolbar = NSRect(x: 100, y: 200, width: 480, height: 28)
        let finish = NSRect(x: 388, y: 204, width: 20, height: 20)
        let formerCancel = NSRect(x: 444, y: 204, width: 20, height: 20)
        let controller = ScrollCapturePresentationController(
            toolbarFrame: toolbar,
            finishButtonFrame: finish,
            selectionFrame: NSRect(x: 200, y: 240, width: 400, height: 300),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            language: .english,
            onFinish: { finishes += 1 }
        )
        XCTAssertTrue(controller.test_controlStyleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(controller.test_controlFrame, toolbar)
        XCTAssertTrue(controller.test_controlCanBecomeKey)
        XCTAssertFalse(controller.test_controlIsOpaque)
        XCTAssertEqual(controller.test_controlBackgroundColor, .clear)
        XCTAssertFalse(controller.test_controlIgnoresMouseEvents)
        XCTAssertTrue(controller.test_terminalHitPanelsCanBecomeKey)
        XCTAssertEqual(controller.test_finishButtonFrame, finish)
        XCTAssertEqual(controller.test_controlHitTargetCount, 1)
        XCTAssertTrue(controller.test_controlHitTargetsAreTransparent)
        XCTAssertEqual(controller.test_interactiveWindowFrames, [toolbar])
        XCTAssertTrue(controller.test_toolbarPointIsInteractive(NSPoint(x: finish.midX, y: finish.midY)))
        XCTAssertFalse(controller.test_toolbarPointIsInteractive(NSPoint(x: formerCancel.midX, y: formerCancel.midY)))
        XCTAssertFalse(controller.test_toolbarPointIsInteractive(NSPoint(x: toolbar.minX + 20, y: toolbar.midY)))
        XCTAssertEqual(controller.test_finishButtonToolTip, L10n(language: .english).text(.finishScrollCapture))
        XCTAssertEqual(controller.test_finishAccessibilityLabel, L10n(language: .english).text(.finishScrollCapture))
        XCTAssertEqual(controller.test_accessibilityRoles, [.button])
        controller.updatePreview(NSImage(size: NSSize(width: 80, height: 320)), following: .bottom)
        XCTAssertNotNil(controller.test_previewImage)
        XCTAssertTrue(controller.test_hasBoundsObserver)
        controller.start()
        XCTAssertTrue(controller.test_hasVisiblePanels)
        XCTAssertEqual(controller.test_visiblePanelKinds, ["control", "preview"])
        controller.test_triggerFinish()
        controller.test_triggerFinish()
        XCTAssertEqual(finishes, 1)
        controller.stop()
        controller.stop()
        XCTAssertFalse(controller.test_hasVisiblePanels)
        XCTAssertTrue(controller.test_panelsAreClosedAndDetached)
        XCTAssertNil(controller.test_previewImage)
        XCTAssertFalse(controller.test_hasBoundsObserver)
        XCTAssertNil(controller.test_warningText)
        controller.start()
        XCTAssertFalse(controller.test_hasVisiblePanels)
    }

    func testTerminalActionsCanBeRearmedAfterRecoverableFailure() {
        var finishes = 0
        let controller = ScrollCapturePresentationController(
            toolbarFrame: NSRect(x: 100, y: 100, width: 400, height: 28),
            finishButtonFrame: NSRect(x: 300, y: 104, width: 20, height: 20),
            selectionFrame: NSRect(x: 100, y: 150, width: 400, height: 300),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 700),
            language: .english,
            onFinish: { finishes += 1 }
        )
        controller.start()
        controller.test_triggerFinish()
        controller.resetTerminalActionsForRetry()
        controller.test_triggerFinish()
        controller.resetTerminalActionsForRetry()
        controller.test_triggerFinish()

        XCTAssertEqual(finishes, 3)
    }

    func testBottomPreviewKeepsLatestLongThumbnailVisible() {
        let controller = makeController()
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

        controller.updatePreview(NSImage(size: NSSize(width: 300, height: 240)), following: .bottom)
        XCTAssertEqual(controller.test_previewFrame.minY, selection.minY, accuracy: 0.5)

        controller.updatePreview(NSImage(size: NSSize(width: 300, height: 3_000)), following: .top)
        XCTAssertEqual(controller.test_previewFrame.minY, selection.minY, accuracy: 0.5)
    }

    func testFirstUpwardWheelAnchorsInitialPreviewAtBottom() {
        let controller = makeController()
        let availablePreviewFrame = controller.test_previewFrame
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
        XCTAssertEqual(controller.test_finishButtonToolTip, L10n(language: .zhHans).text(.finishScrollCapture))
        XCTAssertEqual(controller.test_finishAccessibilityLabel, L10n(language: .zhHans).text(.finishScrollCapture))
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
        XCTAssertTrue(fullscreen.contains(controller.test_previewFrame))
        XCTAssertEqual(controller.test_previewFrame.minY, fullscreen.minY, accuracy: 0.5)
        controller.updatePlacement(selectionFrame: fullscreen, visibleFrame: fullscreen)
        XCTAssertFalse(controller.test_previewFrame.intersects(toolbar))
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

    func testNonFullscreenPreviewPrefersBottomAlignmentWhenToolbarSplitsSideRegion() {
        let visible = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let selection = NSRect(x: 200, y: 200, width: 300, height: 240)
        let toolbar = NSRect(x: 600, y: 190, width: 160, height: 28)
        let controller = ScrollCapturePresentationController(
            toolbarFrame: toolbar,
            finishButtonFrame: NSRect(x: 680, y: 194, width: 20, height: 20),
            selectionFrame: selection,
            visibleFrame: visible,
            language: .english,
            onFinish: {}
        )

        XCTAssertEqual(controller.test_previewFrame.minY, selection.minY, accuracy: 0.5)
        XCTAssertTrue(visible.contains(controller.test_previewFrame))
        XCTAssertFalse(controller.test_previewFrame.intersects(toolbar))
    }

    func testPreviewMaintainsSpacingFromAdjacentControlFrames() {
        let spacing: CGFloat = 12
        let visible = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let selection = NSRect(x: 100, y: 150, width: 300, height: 240)
        let toolbar = NSRect(x: 240, y: 160, width: 120, height: 28)
        let controller = ScrollCapturePresentationController(
            toolbarFrame: toolbar,
            finishButtonFrame: NSRect(x: 312, y: 164, width: 20, height: 20),
            selectionFrame: selection,
            visibleFrame: visible,
            language: .english,
            onFinish: {}
        )

        XCTAssertFalse(controller.test_previewFrame.intersects(toolbar.insetBy(dx: -spacing, dy: -spacing)))
    }

    func testFullscreenPreviewEnforcesSpacingWhenControlFramesDoNotIntersectIt() {
        let spacing: CGFloat = 12
        let fullscreen = NSRect(x: 0, y: 0, width: 800, height: 600)
        let toolbar = NSRect(x: 100, y: 200, width: 380, height: 28)
        let controller = ScrollCapturePresentationController(
            toolbarFrame: toolbar,
            finishButtonFrame: NSRect(x: 200, y: 204, width: 20, height: 20),
            selectionFrame: fullscreen,
            visibleFrame: fullscreen,
            language: .english,
            onFinish: {}
        )

        XCTAssertFalse(controller.test_previewFrame.intersects(toolbar))
        XCTAssertFalse(controller.test_previewFrame.intersects(toolbar.insetBy(dx: -spacing, dy: -spacing)))
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
                XCTAssertTrue(
                    controller.test_warningTextFits,
                    "\(language) \(key) must fit without truncation"
                )
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
        visibleFrame: NSRect = NSRect(x: 0, y: 0, width: 1000, height: 700)
    ) -> ScrollCapturePresentationController {
        ScrollCapturePresentationController(
            toolbarFrame: toolbarFrame,
            finishButtonFrame: NSRect(x: toolbarFrame.midX, y: toolbarFrame.minY + 4, width: 20, height: min(20, toolbarFrame.height)),
            selectionFrame: selectionFrame,
            visibleFrame: visibleFrame,
            language: language,
            onFinish: {}
        )
    }
}
