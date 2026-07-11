import AppKit
import XCTest
@testable import xxsnap

@MainActor
final class ScrollCapturePresentationTests: XCTestCase {
    func testPreviewFramePrefersLargestFittingOutsideSpace() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let selection = NSRect(x: 360, y: 250, width: 240, height: 180)
        let result = ScrollCapturePresentationController.previewFrame(
            selection: selection,
            previewSize: NSSize(width: 220, height: 260),
            visibleFrame: visible
        )
        XCTAssertEqual(result, NSRect(x: 612, y: 210, width: 220, height: 260))
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

    func testPreviewFrameUsesAboveAndBelowWhenTheyAreLargestAvailable() {
        let visible = NSRect(x: 0, y: 0, width: 800, height: 800)
        let size = NSSize(width: 500, height: 140)
        XCTAssertEqual(
            ScrollCapturePresentationController.previewFrame(
                selection: NSRect(x: 100, y: 100, width: 600, height: 200),
                previewSize: size,
                visibleFrame: visible
            ).minY,
            312
        )
        XCTAssertEqual(
            ScrollCapturePresentationController.previewFrame(
                selection: NSRect(x: 100, y: 500, width: 600, height: 200),
                previewSize: size,
                visibleFrame: visible
            ).maxY,
            488
        )
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

    func testFullScreenPreviewIsInsideSelection() {
        let screen = NSRect(x: 0, y: 0, width: 1280, height: 720)
        let result = ScrollCapturePresentationController.previewFrame(
            selection: screen,
            previewSize: NSSize(width: 360, height: 500),
            visibleFrame: screen
        )
        XCTAssertTrue(screen.contains(result))
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
        XCTAssertFalse(controller.test_controlCanBecomeKey)
        XCTAssertFalse(controller.test_controlIsOpaque)
        XCTAssertEqual(controller.test_controlBackgroundColor, .clear)
        XCTAssertEqual(controller.test_finishButtonFrame, finish.offsetBy(dx: -toolbar.minX, dy: -toolbar.minY))
        XCTAssertEqual(controller.test_cancelButtonFrame, cancel.offsetBy(dx: -toolbar.minX, dy: -toolbar.minY))
        XCTAssertEqual(controller.test_controlHitTargetCount, 2)
        XCTAssertTrue(controller.test_controlHitTargetsAreTransparent)
        XCTAssertEqual(controller.test_finishButtonToolTip, L10n(language: .english).text(.finishScrollCapture))
        XCTAssertEqual(controller.test_cancelButtonToolTip, L10n(language: .english).text(.cancel))
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
        XCTAssertNil(controller.test_previewImage)
        XCTAssertNil(controller.test_warningText)
        controller.start()
        XCTAssertFalse(controller.test_hasVisiblePanels)
    }

    func testPreviewTailFollowAndReviewPositionAreIndependentFromWarning() {
        let controller = makeController()
        controller.updatePreview(NSImage(size: NSSize(width: 240, height: 900)))
        XCTAssertTrue(controller.test_isFollowingTail)
        XCTAssertEqual(controller.test_visibleRect.minY, 0, accuracy: 0.5)
        controller.test_userScroll(to: 160)
        XCTAssertGreaterThan(controller.test_visibleRect.minY, 100)
        let reviewOffset = controller.test_visibleRect.minY
        let oldDocumentHeight = controller.test_documentHeight
        controller.updatePreview(NSImage(size: NSSize(width: 240, height: 1200)))
        XCTAssertFalse(controller.test_isFollowingTail)
        XCTAssertEqual(
            controller.test_visibleRect.minY,
            reviewOffset + controller.test_documentHeight - oldDocumentHeight,
            accuracy: 0.5
        )
        controller.setWarning("Low confidence")
        XCTAssertEqual(controller.test_warningText, "Low confidence")
        controller.clearWarning()
        XCTAssertNil(controller.test_warningText)
        XCTAssertNotNil(controller.test_previewImage)
        controller.test_userScroll(to: 0)
        XCTAssertTrue(controller.test_isFollowingTail)
        controller.updatePreview(NSImage(size: NSSize(width: 240, height: 1400)))
        XCTAssertEqual(controller.test_visibleRect.minY, 0, accuracy: 0.5)
    }

    func testReviewAnchorTracksGrowingTailAndClampsWhileTailFollowStaysAtZero() {
        let controller = makeController()
        let width = controller.test_contentWidth
        controller.updatePreview(NSImage(size: NSSize(width: width, height: 600)))
        XCTAssertEqual(controller.test_documentHeight, 600, accuracy: 0.5)
        controller.test_userScroll(to: 120)
        controller.updatePreview(NSImage(size: NSSize(width: width, height: 720)))
        XCTAssertEqual(controller.test_documentHeight, 720, accuracy: 0.5)
        XCTAssertEqual(controller.test_visibleRect.minY, 240, accuracy: 0.5)

        controller.test_userScroll(to: 400)
        controller.updatePreview(NSImage(size: NSSize(width: width, height: 500)))
        XCTAssertLessThanOrEqual(
            controller.test_visibleRect.maxY,
            controller.test_documentHeight + 0.5
        )

        controller.test_userScroll(to: 0)
        controller.updatePreview(NSImage(size: NSSize(width: width, height: 800)))
        XCTAssertEqual(controller.test_visibleRect.minY, 0, accuracy: 0.5)
    }

    func testTransparentControlTooltipsAreLocalizedInChinese() {
        let controller = makeController(language: .zhHans)
        XCTAssertEqual(controller.test_finishButtonToolTip, "完成滚动截图")
        XCTAssertEqual(controller.test_cancelButtonToolTip, "取消")
    }

    func testStopRemovesObserverAndReleasesPreviewImage() {
        var controller: ScrollCapturePresentationController? = makeController()
        weak var weakImage: NSImage?
        weak let weakController = controller
        var reviewOffset: CGFloat?
        autoreleasepool {
            let image = NSImage(size: NSSize(width: 400, height: 1600))
            weakImage = image
            controller?.updatePreview(image)
            controller?.test_userScroll(to: 120)
            reviewOffset = controller?.test_reviewOffset
            controller?.stop()
        }
        XCTAssertNil(weakImage)
        controller?.test_postBoundsChangeNotification()
        XCTAssertEqual(controller?.test_reviewOffset, reviewOffset)
        XCTAssertFalse(controller?.test_hasBoundsObserver ?? true)
        controller?.updatePreview(NSImage(size: NSSize(width: 200, height: 800)))
        controller?.setWarning("late")
        XCTAssertNil(controller?.test_previewImage)
        XCTAssertNil(controller?.test_warningText)
        controller = nil
        XCTAssertNil(weakController)
    }

    private func makeController(language: AppLanguage = .english) -> ScrollCapturePresentationController {
        ScrollCapturePresentationController(
            toolbarFrame: NSRect(x: 100, y: 100, width: 400, height: 28),
            finishButtonFrame: NSRect(x: 300, y: 104, width: 20, height: 20),
            cancelButtonFrame: NSRect(x: 356, y: 104, width: 20, height: 20),
            selectionFrame: NSRect(x: 200, y: 200, width: 300, height: 240),
            visibleFrame: NSRect(x: 0, y: 0, width: 1000, height: 700),
            language: language,
            onFinish: {},
            onCancel: {}
        )
    }
}
