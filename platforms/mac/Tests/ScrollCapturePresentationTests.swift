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
        let controller = ScrollCapturePresentationController(
            toolbarFrame: toolbar,
            selectionFrame: NSRect(x: 200, y: 240, width: 400, height: 300),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            language: .english,
            onFinish: { finishes += 1 },
            onCancel: { cancels += 1 }
        )
        XCTAssertTrue(controller.test_controlStyleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(controller.test_controlFrame, toolbar)
        XCTAssertFalse(controller.test_controlCanBecomeKey)
        controller.start()
        XCTAssertTrue(controller.test_hasVisiblePanels)
        controller.test_triggerFinish()
        controller.test_triggerCancel()
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(cancels, 1)
        controller.stop()
        controller.stop()
        XCTAssertFalse(controller.test_hasVisiblePanels)
    }

    func testPreviewTailFollowAndReviewPositionAreIndependentFromWarning() {
        let controller = makeController()
        controller.updatePreview(NSImage(size: NSSize(width: 240, height: 900)))
        XCTAssertTrue(controller.test_isFollowingTail)
        controller.test_userReviewedAwayFromBottom(position: 0.35)
        controller.updatePreview(NSImage(size: NSSize(width: 240, height: 1200)))
        XCTAssertFalse(controller.test_isFollowingTail)
        XCTAssertEqual(controller.test_reviewPosition, 0.35, accuracy: 0.01)
        controller.setWarning("Low confidence")
        XCTAssertEqual(controller.test_warningText, "Low confidence")
        controller.clearWarning()
        XCTAssertNil(controller.test_warningText)
        XCTAssertNotNil(controller.test_previewImage)
        controller.test_userReturnedToBottom()
        XCTAssertTrue(controller.test_isFollowingTail)
    }

    private func makeController() -> ScrollCapturePresentationController {
        ScrollCapturePresentationController(
            toolbarFrame: NSRect(x: 100, y: 100, width: 400, height: 28),
            selectionFrame: NSRect(x: 200, y: 200, width: 300, height: 240),
            visibleFrame: NSRect(x: 0, y: 0, width: 1000, height: 700),
            language: .english,
            onFinish: {},
            onCancel: {}
        )
    }
}
