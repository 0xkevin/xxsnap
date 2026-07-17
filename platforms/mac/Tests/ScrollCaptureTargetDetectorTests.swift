import AppKit
import XCTest
@testable import xxsnap

final class ScrollCaptureTargetDetectorTests: XCTestCase {
    func testProbePointsCoverCenterAndThreeByThreeInteriorGrid() {
        let selection = NSRect(x: 100, y: 200, width: 500, height: 400)
        let detector = ScrollCaptureTargetDetector(candidateQuery: StubCandidateQuery())

        let points = detector.probePoints(in: selection)

        XCTAssertEqual(points, [
            NSPoint(x: 200, y: 280),
            NSPoint(x: 350, y: 280),
            NSPoint(x: 500, y: 280),
            NSPoint(x: 200, y: 400),
            NSPoint(x: 350, y: 400),
            NSPoint(x: 500, y: 400),
            NSPoint(x: 200, y: 520),
            NSPoint(x: 350, y: 520),
            NSPoint(x: 500, y: 520),
        ])
        XCTAssertTrue(points.allSatisfy(selection.contains))
        XCTAssertTrue(points.contains(NSPoint(x: selection.midX, y: selection.midY)))
    }

    func testLargestScrollableIntersectionWinsOverNarrowChatSidebar() {
        let selection = NSRect(x: 0, y: 0, width: 900, height: 700)
        let sidebar = ScrollCaptureTargetCandidate(
            identity: 10,
            screenRect: NSRect(x: 0, y: 0, width: 160, height: 700),
            minimum: 0,
            maximum: 1,
            firstProbeIndex: 0
        )
        let mainChat = ScrollCaptureTargetCandidate(
            identity: 20,
            screenRect: NSRect(x: 200, y: 80, width: 650, height: 540),
            minimum: 0,
            maximum: 3_000,
            firstProbeIndex: 4
        )
        let detector = ScrollCaptureTargetDetector(
            candidateQuery: StubCandidateQuery(candidates: [sidebar, mainChat])
        )

        let region = detector.scrollableRegion(in: selection, processIdentifier: 42)

        XCTAssertEqual(region, mainChat.screenRect)
    }

    func testCandidateIsClippedToOriginalSelectionAndNeverExpandsIt() {
        let selection = NSRect(x: 100, y: 100, width: 500, height: 400)
        let oversizedCandidate = ScrollCaptureTargetCandidate(
            identity: 30,
            screenRect: NSRect(x: -200, y: -300, width: 1_400, height: 1_300),
            minimum: 0,
            maximum: 1,
            firstProbeIndex: 0
        )
        let detector = ScrollCaptureTargetDetector(
            candidateQuery: StubCandidateQuery(candidates: [oversizedCandidate])
        )

        let region = detector.scrollableRegion(in: selection, processIdentifier: 42)

        XCTAssertEqual(region, selection)
    }

    func testInvalidRangeAndSubminimumRegionFallBack() {
        let selection = NSRect(x: 0, y: 0, width: 800, height: 600)
        let zeroRange = ScrollCaptureTargetCandidate(
            identity: 40,
            screenRect: selection,
            minimum: 12,
            maximum: 12,
            firstProbeIndex: 0
        )
        let reversedRange = ScrollCaptureTargetCandidate(
            identity: 41,
            screenRect: selection,
            minimum: 20,
            maximum: 10,
            firstProbeIndex: 1
        )
        let narrowRegion = ScrollCaptureTargetCandidate(
            identity: 42,
            screenRect: NSRect(x: 0, y: 0, width: 119, height: 500),
            minimum: 0,
            maximum: 1,
            firstProbeIndex: 2
        )
        let shortRegion = ScrollCaptureTargetCandidate(
            identity: 43,
            screenRect: NSRect(x: 0, y: 0, width: 500, height: 119),
            minimum: 0,
            maximum: 1,
            firstProbeIndex: 3
        )
        let detector = ScrollCaptureTargetDetector(
            candidateQuery: StubCandidateQuery(
                candidates: [zeroRange, reversedRange, narrowRegion, shortRegion]
            )
        )

        XCTAssertNil(detector.scrollableRegion(in: selection, processIdentifier: 42))
    }

    func testQuartzRectConvertsToAppKitBottomOrigin() {
        XCTAssertEqual(
            ScrollCaptureScreenCoordinates.appKitRect(
                quartzPosition: CGPoint(x: 100, y: 200),
                size: CGSize(width: 300, height: 400),
                quartzOriginY: 1_080
            ),
            NSRect(x: 100, y: 480, width: 300, height: 400)
        )

        XCTAssertEqual(
            ScrollCaptureScreenCoordinates.appKitRect(
                quartzPosition: CGPoint(x: -1_280, y: 1_600),
                size: CGSize(width: 1_280, height: 200),
                quartzOriginY: 900
            ),
            NSRect(x: -1_280, y: -900, width: 1_280, height: 200)
        )
    }
}

private struct StubCandidateQuery: ScrollCaptureTargetCandidateQuerying {
    var candidates: [ScrollCaptureTargetCandidate] = []

    func candidates(processIdentifier: pid_t, probePoints: [NSPoint]) -> [ScrollCaptureTargetCandidate] {
        candidates
    }
}
