import AppKit
import XCTest
@testable import xxsnap

final class WindowSelectionStateTests: XCTestCase {
    func testBestWindowAtPointIgnoresTinyAndOffscreenWindows() {
        let candidates = [
            WindowSelectionCandidate(id: 1, ownerPID: 10, layer: 0, alpha: 1, bounds: NSRect(x: 0, y: 0, width: 20, height: 20), name: "tiny"),
            WindowSelectionCandidate(id: 2, ownerPID: 11, layer: 0, alpha: 1, bounds: NSRect(x: 100, y: 100, width: 240, height: 180), name: "chat"),
            WindowSelectionCandidate(id: 3, ownerPID: 12, layer: 0, alpha: 1, bounds: NSRect(x: 500, y: 500, width: 240, height: 180), name: "other"),
        ]

        let selected = WindowSelectionState.bestWindow(
            at: NSPoint(x: 150, y: 150),
            candidates: candidates,
            desktopFrame: NSRect(x: 0, y: 0, width: 800, height: 600),
            currentProcessID: 99
        )

        XCTAssertEqual(selected?.id, 2)
    }

    func testBestWindowFallsThroughToLowerWindowWhenPointIsOutsideFrontWindow() {
        let candidates = [
            WindowSelectionCandidate(id: 1, ownerPID: 10, layer: 0, alpha: 1, bounds: NSRect(x: 100, y: 100, width: 260, height: 180), name: "front"),
            WindowSelectionCandidate(id: 2, ownerPID: 11, layer: 0, alpha: 1, bounds: NSRect(x: 0, y: 0, width: 800, height: 600), name: "behind"),
        ]

        let selected = WindowSelectionState.bestWindow(
            at: NSPoint(x: 20, y: 20),
            candidates: candidates,
            desktopFrame: NSRect(x: 0, y: 0, width: 800, height: 600),
            currentProcessID: 99
        )

        XCTAssertEqual(selected?.id, 2)
    }

    func testBestWindowPrefersTopmostCandidateOrderOverWindowArea() {
        let candidates = [
            WindowSelectionCandidate(id: 1, ownerPID: 10, layer: 0, alpha: 1, bounds: NSRect(x: 120, y: 120, width: 500, height: 400), name: "front"),
            WindowSelectionCandidate(id: 2, ownerPID: 11, layer: 0, alpha: 1, bounds: NSRect(x: 200, y: 200, width: 120, height: 90), name: "behind"),
        ]

        let selected = WindowSelectionState.bestWindow(
            at: NSPoint(x: 240, y: 230),
            candidates: candidates,
            desktopFrame: NSRect(x: 0, y: 0, width: 800, height: 600),
            currentProcessID: 99
        )

        XCTAssertEqual(selected?.id, 1)
    }

    func testBestWindowIgnoresCurrentAppOverlayWindow() {
        let candidates = [
            WindowSelectionCandidate(id: 1, ownerPID: 99, layer: 0, alpha: 1, bounds: NSRect(x: 0, y: 0, width: 800, height: 600), name: "Snipory"),
            WindowSelectionCandidate(id: 2, ownerPID: 10, layer: 0, alpha: 1, bounds: NSRect(x: 80, y: 90, width: 320, height: 240), name: "target"),
        ]

        let selected = WindowSelectionState.bestWindow(
            at: NSPoint(x: 120, y: 120),
            candidates: candidates,
            desktopFrame: NSRect(x: 0, y: 0, width: 800, height: 600),
            currentProcessID: 99
        )

        XCTAssertEqual(selected?.id, 2)
    }

    func testBestWindowSelectsMacOSMenuBarSystemLayer() {
        let candidates = [
            WindowSelectionCandidate(id: 1, ownerPID: 170, layer: 24, alpha: 1, bounds: NSRect(x: 0, y: 563, width: 900, height: 37), name: "Menubar"),
            WindowSelectionCandidate(id: 2, ownerPID: 10, layer: 0, alpha: 1, bounds: NSRect(x: 0, y: 48, width: 900, height: 515), name: "app"),
        ]

        let selected = WindowSelectionState.bestWindow(
            at: NSPoint(x: 420, y: 580),
            candidates: candidates,
            desktopFrame: NSRect(x: 0, y: 0, width: 900, height: 600),
            currentProcessID: 99
        )

        XCTAssertEqual(selected?.id, 1)
    }

    func testBestWindowSelectsMacOSDockStripSystemLayer() {
        let candidates = [
            WindowSelectionCandidate(id: 1, ownerPID: 449, layer: 20, alpha: 1, bounds: NSRect(x: 0, y: 0, width: 900, height: 48), name: "Dock"),
            WindowSelectionCandidate(id: 2, ownerPID: 10, layer: 0, alpha: 1, bounds: NSRect(x: 0, y: 48, width: 900, height: 515), name: "app"),
        ]

        let selected = WindowSelectionState.bestWindow(
            at: NSPoint(x: 420, y: 24),
            candidates: candidates,
            desktopFrame: NSRect(x: 0, y: 0, width: 900, height: 600),
            currentProcessID: 99
        )

        XCTAssertEqual(selected?.id, 1)
    }

    func testSystemUICandidatesUseVisibleFrameInsetsForMenuBarAndDock() {
        let candidates = WindowSelectionState.systemUICandidates(
            screenFrames: [NSRect(x: 0, y: 0, width: 900, height: 600)],
            visibleFrames: [NSRect(x: 0, y: 48, width: 900, height: 515)],
            desktopFrame: NSRect(x: 0, y: 0, width: 900, height: 600)
        )

        XCTAssertEqual(candidates.map(\.name), ["Menubar", "Dock"])
        XCTAssertEqual(candidates.map(\.bounds), [
            NSRect(x: 0, y: 563, width: 900, height: 37),
            NSRect(x: 0, y: 0, width: 900, height: 48),
        ])
    }

    func testBestHoverRectUsesOrdinaryWindowCandidate() {
        let window = WindowSelectionCandidate(
            id: 1,
            ownerPID: 10,
            layer: 0,
            alpha: 1,
            bounds: NSRect(x: 20, y: 20, width: 500, height: 360),
            name: "app"
        )

        let rect = WindowSelectionState.bestHoverRect(
            at: NSPoint(x: 140, y: 150),
            candidates: [window],
            desktopFrame: NSRect(x: 0, y: 0, width: 600, height: 420),
            currentProcessID: 99
        )

        XCTAssertEqual(rect, window.bounds)
    }

    func testBestHoverRectKeepsSystemUIAboveOrdinaryWindow() {
        let menubar = WindowSelectionCandidate(
            id: 1,
            ownerPID: 0,
            layer: 24,
            alpha: 1,
            bounds: NSRect(x: 0, y: 563, width: 900, height: 37),
            name: "Menubar"
        )
        let app = WindowSelectionCandidate(
            id: 2,
            ownerPID: 10,
            layer: 0,
            alpha: 1,
            bounds: NSRect(x: 0, y: 0, width: 900, height: 600),
            name: "app"
        )

        let rect = WindowSelectionState.bestHoverRect(
            at: NSPoint(x: 50, y: 580),
            candidates: [menubar, app],
            desktopFrame: NSRect(x: 0, y: 0, width: 900, height: 600),
            currentProcessID: 99
        )

        XCTAssertEqual(rect, menubar.bounds)
    }

    func testBestHoverRectReturnsNilOutsideWindowCandidates() {
        let window = WindowSelectionCandidate(
            id: 1,
            ownerPID: 10,
            layer: 0,
            alpha: 1,
            bounds: NSRect(x: 20, y: 20, width: 220, height: 160),
            name: "app"
        )

        let rect = WindowSelectionState.bestHoverRect(
            at: NSPoint(x: 280, y: 220),
            candidates: [window],
            desktopFrame: NSRect(x: 0, y: 0, width: 600, height: 420),
            currentProcessID: 99
        )

        XCTAssertNil(rect)
    }
}
