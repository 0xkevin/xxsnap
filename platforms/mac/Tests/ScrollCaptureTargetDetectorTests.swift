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

    func testLargestScrollableIntersectionWinsOverNarrowChatSidebar() async {
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

        let region = await detector.scrollableRegion(in: selection, processIdentifier: 42)

        XCTAssertEqual(region, mainChat.screenRect)
    }

    func testCandidateIsClippedToOriginalSelectionAndNeverExpandsIt() async {
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

        let region = await detector.scrollableRegion(in: selection, processIdentifier: 42)

        XCTAssertEqual(region, selection)
    }

    func testInvalidRangeAndSubminimumRegionFallBack() async {
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

        let region = await detector.scrollableRegion(in: selection, processIdentifier: 42)

        XCTAssertNil(region)
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

    func testScrollbarStateRequiresEnabledFiniteInRangeValue() {
        XCTAssertTrue(ScrollCaptureScrollbarStateValidator.isScrollable(
            enabled: true,
            value: 0.5,
            minimum: 0,
            maximum: 1
        ))

        let invalidStates: [(Bool?, Double?, Double?, Double?)] = [
            (false, 0.5, 0, 1),
            (nil, 0.5, 0, 1),
            (true, nil, 0, 1),
            (true, .nan, 0, 1),
            (true, .infinity, 0, 1),
            (true, 0.5, .nan, 1),
            (true, 0.5, 0, .infinity),
            (true, -0.1, 0, 1),
            (true, 1.1, 0, 1),
            (true, 0.5, 1, 1),
        ]
        for (enabled, value, minimum, maximum) in invalidStates {
            XCTAssertFalse(ScrollCaptureScrollbarStateValidator.isScrollable(
                enabled: enabled,
                value: value,
                minimum: minimum,
                maximum: maximum
            ))
        }
    }

    func testEqualAreaPrefersTallerIntersection() async {
        let selection = NSRect(x: 0, y: 0, width: 1_000, height: 1_000)
        let wider = candidate(
            identity: 50,
            rect: NSRect(x: 300, y: 400, width: 400, height: 200),
            firstProbeIndex: 0
        )
        let taller = candidate(
            identity: 51,
            rect: NSRect(x: 400, y: 300, width: 200, height: 400),
            firstProbeIndex: 1
        )
        let detector = ScrollCaptureTargetDetector(
            candidateQuery: StubCandidateQuery(candidates: [wider, taller])
        )

        let region = await detector.scrollableRegion(in: selection, processIdentifier: 42)

        XCTAssertEqual(region, taller.screenRect)
    }

    func testEqualAreaAndHeightPrefersCenterNearestSelectionCenter() async {
        let selection = NSRect(x: 0, y: 0, width: 1_000, height: 1_000)
        let offset = candidate(
            identity: 60,
            rect: NSRect(x: 50, y: 50, width: 200, height: 200),
            firstProbeIndex: 0
        )
        let centered = candidate(
            identity: 61,
            rect: NSRect(x: 400, y: 400, width: 200, height: 200),
            firstProbeIndex: 1
        )
        let detector = ScrollCaptureTargetDetector(
            candidateQuery: StubCandidateQuery(candidates: [offset, centered])
        )

        let region = await detector.scrollableRegion(in: selection, processIdentifier: 42)

        XCTAssertEqual(region, centered.screenRect)
    }

    func testEqualGeometryRankPrefersEarlierProbe() async {
        let selection = NSRect(x: 0, y: 0, width: 1_000, height: 600)
        let laterProbe = candidate(
            identity: 70,
            rect: NSRect(x: 700, y: 200, width: 200, height: 200),
            firstProbeIndex: 7
        )
        let earlierProbe = candidate(
            identity: 71,
            rect: NSRect(x: 100, y: 200, width: 200, height: 200),
            firstProbeIndex: 1
        )
        let detector = ScrollCaptureTargetDetector(
            candidateQuery: StubCandidateQuery(candidates: [laterProbe, earlierProbe])
        )

        let region = await detector.scrollableRegion(in: selection, processIdentifier: 42)

        XCTAssertEqual(region, earlierProbe.screenRect)
    }

    func testDuplicateIdentityRetainsEarliestProbe() async {
        let selection = NSRect(x: 0, y: 0, width: 1_000, height: 600)
        let laterProbe = candidate(
            identity: 80,
            rect: NSRect(x: 700, y: 200, width: 200, height: 200),
            firstProbeIndex: 7
        )
        let earlierProbe = candidate(
            identity: 80,
            rect: NSRect(x: 100, y: 200, width: 200, height: 200),
            firstProbeIndex: 1
        )
        let detector = ScrollCaptureTargetDetector(
            candidateQuery: StubCandidateQuery(candidates: [laterProbe, earlierProbe])
        )

        let region = await detector.scrollableRegion(in: selection, processIdentifier: 42)

        XCTAssertEqual(region, earlierProbe.screenRect)
    }

    @MainActor
    func testAsyncDetectionRunsCandidateQueryOffMainThread() async {
        let query = ThreadRecordingCandidateQuery()
        let detector = ScrollCaptureTargetDetector(candidateQuery: query)

        _ = await detector.scrollableRegion(
            in: NSRect(x: 0, y: 0, width: 500, height: 500),
            processIdentifier: 42
        )

        XCTAssertEqual(query.wasCalledOnMainThread, false)
    }

    func testCancelledDetectionReturnsNilWithoutWaitingForBackgroundQuery() async {
        let selection = NSRect(x: 0, y: 0, width: 500, height: 500)
        let query = BlockingCandidateQuery(candidates: [candidate(
            identity: 85,
            rect: selection,
            firstProbeIndex: 0
        )])
        let detector = ScrollCaptureTargetDetector(candidateQuery: query)
        let detection = Task {
            await detector.scrollableRegion(in: selection, processIdentifier: 42)
        }

        await query.waitUntilStarted()
        detection.cancel()

        let returned = expectation(description: "cancelled detection returned")
        let observedResult = Task {
            let region = await detection.value
            returned.fulfill()
            return region
        }
        await fulfillment(of: [returned], timeout: 0.2)

        query.finish()
        let region = await observedResult.value
        XCTAssertNil(region)
    }

    func testNewDetectionDoesNotWaitForCancelledBackgroundQuery() async {
        let selection = NSRect(x: 0, y: 0, width: 500, height: 500)
        let candidate = candidate(identity: 86, rect: selection, firstProbeIndex: 0)
        let query = FirstCallBlockingCandidateQuery(laterCandidates: [candidate])
        let detector = ScrollCaptureTargetDetector(candidateQuery: query)
        let firstDetection = Task {
            await detector.scrollableRegion(in: selection, processIdentifier: 42)
        }

        await query.waitUntilFirstCallStarts()
        firstDetection.cancel()
        let cancelledRegion = await firstDetection.value
        XCTAssertNil(cancelledRegion)

        let secondDetection = Task {
            await detector.scrollableRegion(in: selection, processIdentifier: 42)
        }
        let returned = expectation(description: "new detection returned")
        let observedResult = Task {
            let region = await secondDetection.value
            returned.fulfill()
            return region
        }
        await fulfillment(of: [returned], timeout: 0.2)

        query.finishFirstCall()
        let region = await observedResult.value
        XCTAssertEqual(region, selection)
    }

    func testMessagingTimeoutIsShortAndFailureStopsBeforeHitTesting() {
        let reader = FakeAccessibilityReader()
        reader.messagingTimeoutSucceeds = false
        let query = AccessibilityScrollCaptureCandidateQuery(
            quartzOriginYProvider: { 1_000 },
            accessibilityReader: reader
        )

        let candidates = query.candidates(
            processIdentifier: 42,
            probePoints: [NSPoint(x: 100, y: 100)]
        )

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(reader.messagingTimeouts, [AccessibilityScrollCaptureCandidateQuery.messagingTimeout])
        XCTAssertGreaterThan(AccessibilityScrollCaptureCandidateQuery.messagingTimeout, 0)
        XCTAssertLessThan(AccessibilityScrollCaptureCandidateQuery.messagingTimeout, 1)
        XCTAssertEqual(reader.hitTestCount, 0)
    }

    func testMessagingTimeoutIsAppliedToEveryUniqueVisitedElement() {
        let parent = FakeAccessibilityNode()
        let child = FakeAccessibilityNode(parent: parent)
        let reader = FakeAccessibilityReader(hitElements: [child, child])
        let query = makeAccessibilityQuery(reader: reader)

        _ = query.candidates(
            processIdentifier: 42,
            probePoints: [NSPoint(x: 100, y: 100), NSPoint(x: 200, y: 200)]
        )

        XCTAssertEqual(reader.messagingTimeouts.count, 3)
        XCTAssertTrue(reader.messagingTimeouts.allSatisfy {
            $0 == AccessibilityScrollCaptureCandidateQuery.messagingTimeout
        })
    }

    func testHitTestFailureSafelyReturnsNoCandidates() {
        let reader = FakeAccessibilityReader(hitElements: [nil])
        let query = makeAccessibilityQuery(reader: reader)

        let candidates = query.candidates(
            processIdentifier: 42,
            probePoints: [NSPoint(x: 100, y: 100)]
        )

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(reader.hitTestCount, 1)
        XCTAssertEqual(reader.candidateReadCount, 0)
    }

    func testParentTraversalFindsScrollableOwner() {
        let scrollOwner = FakeAccessibilityNode(
            candidate: candidate(
                identity: 90,
                rect: NSRect(x: 20, y: 30, width: 400, height: 500),
                firstProbeIndex: -1
            )
        )
        let child = FakeAccessibilityNode(parent: scrollOwner)
        let reader = FakeAccessibilityReader(hitElements: [child])
        let query = makeAccessibilityQuery(reader: reader)

        let candidates = query.candidates(
            processIdentifier: 42,
            probePoints: [NSPoint(x: 100, y: 100)]
        )

        XCTAssertEqual(candidates, [candidate(
            identity: 90,
            rect: NSRect(x: 20, y: 30, width: 400, height: 500),
            firstProbeIndex: 0
        )])
        XCTAssertEqual(reader.candidateReadCount, 2)
    }

    func testDisabledFakeScrollbarProducesNoCandidate() {
        let disabledOwner = FakeAccessibilityNode(
            candidate: candidate(
                identity: 95,
                rect: NSRect(x: 0, y: 0, width: 500, height: 500),
                firstProbeIndex: -1
            ),
            scrollbarEnabled: false
        )
        let reader = FakeAccessibilityReader(hitElements: [disabledOwner])
        let query = makeAccessibilityQuery(reader: reader)

        let candidates = query.candidates(
            processIdentifier: 42,
            probePoints: [NSPoint(x: 100, y: 100)]
        )

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(reader.candidateReadCount, 1)
    }

    func testTraversalStopsAfterSixteenElements() {
        let nodes = (0..<17).map { _ in FakeAccessibilityNode() }
        for index in 0..<16 {
            nodes[index].parent = nodes[index + 1]
        }
        nodes[16].candidate = candidate(
            identity: 100,
            rect: NSRect(x: 0, y: 0, width: 500, height: 500),
            firstProbeIndex: -1
        )
        let reader = FakeAccessibilityReader(hitElements: [nodes[0]])
        let query = makeAccessibilityQuery(reader: reader)

        let candidates = query.candidates(
            processIdentifier: 42,
            probePoints: [NSPoint(x: 100, y: 100)]
        )

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(reader.candidateReadCount, 16)
        XCTAssertEqual(reader.parentReadCount, 15)
    }

    func testTraversalStopsWhenDetectionDeadlineExpires() {
        let nodes = (0..<5).map { _ in FakeAccessibilityNode() }
        for index in 0..<4 {
            nodes[index].parent = nodes[index + 1]
        }
        let clock = FakeMonotonicClock()
        let reader = FakeAccessibilityReader(hitElements: [nodes[0]])
        reader.onCandidateRead = { clock.advance(by: 1) }
        reader.onParentRead = { clock.advance(by: 1) }
        let query = makeAccessibilityQuery(reader: reader)
        let context = ScrollCaptureTargetQueryContext(
            totalBudget: 2.5,
            nowProvider: { clock.now }
        )

        let candidates = query.candidates(
            processIdentifier: 42,
            probePoints: [NSPoint(x: 100, y: 100)],
            context: context
        )

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(reader.candidateReadCount, 2)
        XCTAssertEqual(reader.parentReadCount, 1)
    }

    func testMissingCandidateAttributesSafelyContinueTraversal() {
        let missingParentOwner = FakeAccessibilityNode()
        let missingAttributesOwner = FakeAccessibilityNode(parent: missingParentOwner)
        let reader = FakeAccessibilityReader(hitElements: [missingAttributesOwner])
        let query = makeAccessibilityQuery(reader: reader)

        let candidates = query.candidates(
            processIdentifier: 42,
            probePoints: [NSPoint(x: 100, y: 100)]
        )

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(reader.candidateReadCount, 2)
    }

    func testSharedParentIsReadOnceAndKeepsEarliestProbeIndex() {
        let sharedOwner = FakeAccessibilityNode(
            candidate: candidate(
                identity: 110,
                rect: NSRect(x: 0, y: 0, width: 500, height: 500),
                firstProbeIndex: -1
            )
        )
        let firstChild = FakeAccessibilityNode(parent: sharedOwner)
        let secondChild = FakeAccessibilityNode(parent: sharedOwner)
        let reader = FakeAccessibilityReader(hitElements: [firstChild, secondChild])
        let query = makeAccessibilityQuery(reader: reader)

        let candidates = query.candidates(
            processIdentifier: 42,
            probePoints: [NSPoint(x: 100, y: 100), NSPoint(x: 200, y: 200)]
        )

        XCTAssertEqual(candidates.first?.firstProbeIndex, 0)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(reader.candidateReads(for: sharedOwner), 1)
        XCTAssertEqual(reader.parentReads(for: sharedOwner), 1)
    }

    func testCachedBoundaryNodeContinuesWithFreshDepthBudgetWithoutRepeatingReads() {
        let nodes = (0..<17).map { _ in FakeAccessibilityNode() }
        for index in 0..<16 {
            nodes[index].parent = nodes[index + 1]
        }
        nodes[16].candidate = candidate(
            identity: 120,
            rect: NSRect(x: 0, y: 0, width: 500, height: 500),
            firstProbeIndex: -1
        )
        let reader = FakeAccessibilityReader(
            hitElements: [nodes[0], nodes[15], nodes[15]]
        )
        let query = makeAccessibilityQuery(reader: reader)

        let candidates = query.candidates(
            processIdentifier: 42,
            probePoints: [
                NSPoint(x: 100, y: 100),
                NSPoint(x: 200, y: 200),
                NSPoint(x: 300, y: 300),
            ]
        )

        XCTAssertEqual(candidates, [candidate(
            identity: 120,
            rect: NSRect(x: 0, y: 0, width: 500, height: 500),
            firstProbeIndex: 1
        )])
        for node in nodes {
            XCTAssertEqual(reader.candidateReads(for: node), 1)
            XCTAssertEqual(reader.parentReads(for: node), 1)
        }
    }

    private func makeAccessibilityQuery(
        reader: FakeAccessibilityReader
    ) -> AccessibilityScrollCaptureCandidateQuery {
        AccessibilityScrollCaptureCandidateQuery(
            quartzOriginYProvider: { 1_000 },
            accessibilityReader: reader
        )
    }

    private func candidate(
        identity: CFHashCode,
        rect: NSRect,
        firstProbeIndex: Int
    ) -> ScrollCaptureTargetCandidate {
        ScrollCaptureTargetCandidate(
            identity: identity,
            screenRect: rect,
            minimum: 0,
            maximum: 1,
            firstProbeIndex: firstProbeIndex
        )
    }
}

private struct StubCandidateQuery: ScrollCaptureTargetCandidateQuerying, Sendable {
    var candidates: [ScrollCaptureTargetCandidate] = []

    func candidates(
        processIdentifier: pid_t,
        probePoints: [NSPoint],
        context: ScrollCaptureTargetQueryContext
    ) -> [ScrollCaptureTargetCandidate] {
        candidates
    }
}

private final class ThreadRecordingCandidateQuery: ScrollCaptureTargetCandidateQuerying, @unchecked Sendable {
    private let lock = NSLock()
    private var callThreadWasMain: Bool?

    var wasCalledOnMainThread: Bool? {
        lock.withLock { callThreadWasMain }
    }

    func candidates(
        processIdentifier: pid_t,
        probePoints: [NSPoint],
        context: ScrollCaptureTargetQueryContext
    ) -> [ScrollCaptureTargetCandidate] {
        lock.withLock {
            callThreadWasMain = Thread.isMainThread
        }
        return []
    }
}

private final class BlockingCandidateQuery: ScrollCaptureTargetCandidateQuerying, @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private let result: [ScrollCaptureTargetCandidate]

    init(candidates: [ScrollCaptureTargetCandidate]) {
        result = candidates
    }

    func candidates(
        processIdentifier: pid_t,
        probePoints: [NSPoint],
        context: ScrollCaptureTargetQueryContext
    ) -> [ScrollCaptureTargetCandidate] {
        started.signal()
        release.wait()
        return result
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [started] in
                started.wait()
                continuation.resume()
            }
        }
    }

    func finish() {
        release.signal()
    }
}

private final class FirstCallBlockingCandidateQuery: ScrollCaptureTargetCandidateQuerying, @unchecked Sendable {
    private let lock = NSLock()
    private let firstCallStarted = DispatchSemaphore(value: 0)
    private let firstCallRelease = DispatchSemaphore(value: 0)
    private let laterCandidates: [ScrollCaptureTargetCandidate]
    private var callCount = 0

    init(laterCandidates: [ScrollCaptureTargetCandidate]) {
        self.laterCandidates = laterCandidates
    }

    func candidates(
        processIdentifier: pid_t,
        probePoints: [NSPoint],
        context: ScrollCaptureTargetQueryContext
    ) -> [ScrollCaptureTargetCandidate] {
        let callIndex = lock.withLock {
            defer { callCount += 1 }
            return callCount
        }
        guard callIndex == 0 else { return laterCandidates }
        firstCallStarted.signal()
        firstCallRelease.wait()
        return []
    }

    func waitUntilFirstCallStarts() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [firstCallStarted] in
                firstCallStarted.wait()
                continuation.resume()
            }
        }
    }

    func finishFirstCall() {
        firstCallRelease.signal()
    }
}

private final class FakeAccessibilityNode {
    var parent: FakeAccessibilityNode?
    var candidate: ScrollCaptureTargetCandidate?
    var scrollbarEnabled: Bool?
    var scrollbarValue: Double?

    init(
        parent: FakeAccessibilityNode? = nil,
        candidate: ScrollCaptureTargetCandidate? = nil,
        scrollbarEnabled: Bool? = true,
        scrollbarValue: Double? = 0.5
    ) {
        self.parent = parent
        self.candidate = candidate
        self.scrollbarEnabled = scrollbarEnabled
        self.scrollbarValue = scrollbarValue
    }
}

private final class FakeAccessibilityReader: ScrollCaptureAccessibilityReading, @unchecked Sendable {
    var messagingTimeoutSucceeds = true
    var onCandidateRead: (() -> Void)?
    var onParentRead: (() -> Void)?
    private var remainingHitElements: [FakeAccessibilityNode?]
    private(set) var messagingTimeouts: [Float] = []
    private(set) var hitTestCount = 0
    private var candidateReadsByNode: [ObjectIdentifier: Int] = [:]
    private var parentReadsByNode: [ObjectIdentifier: Int] = [:]

    var candidateReadCount: Int {
        candidateReadsByNode.values.reduce(0, +)
    }

    var parentReadCount: Int {
        parentReadsByNode.values.reduce(0, +)
    }

    init(hitElements: [FakeAccessibilityNode?] = []) {
        remainingHitElements = hitElements
    }

    func application(processIdentifier: pid_t) -> ScrollCaptureAccessibilityElement? {
        ScrollCaptureAccessibilityElement(rawValue: FakeAccessibilityNode())
    }

    func setMessagingTimeout(_ timeout: Float, for application: ScrollCaptureAccessibilityElement) -> Bool {
        messagingTimeouts.append(timeout)
        return messagingTimeoutSucceeds
    }

    func element(
        at quartzPoint: CGPoint,
        in application: ScrollCaptureAccessibilityElement
    ) -> ScrollCaptureAccessibilityElement? {
        hitTestCount += 1
        guard !remainingHitElements.isEmpty,
              let node = remainingHitElements.removeFirst()
        else {
            return nil
        }
        return ScrollCaptureAccessibilityElement(rawValue: node)
    }

    func parent(
        of element: ScrollCaptureAccessibilityElement
    ) -> ScrollCaptureAccessibilityElement? {
        let node = node(from: element)
        increment(&parentReadsByNode, for: node)
        onParentRead?()
        return node.parent.map { ScrollCaptureAccessibilityElement(rawValue: $0) }
    }

    func candidate(
        from element: ScrollCaptureAccessibilityElement,
        firstProbeIndex: Int,
        quartzOriginY: CGFloat,
        context: ScrollCaptureTargetQueryContext
    ) -> ScrollCaptureTargetCandidate? {
        let node = node(from: element)
        increment(&candidateReadsByNode, for: node)
        onCandidateRead?()
        guard let candidate = node.candidate,
              ScrollCaptureScrollbarStateValidator.isScrollable(
                  enabled: node.scrollbarEnabled,
                  value: node.scrollbarValue,
                  minimum: candidate.minimum,
                  maximum: candidate.maximum
              )
        else {
            return nil
        }
        return ScrollCaptureTargetCandidate(
            identity: candidate.identity,
            screenRect: candidate.screenRect,
            minimum: candidate.minimum,
            maximum: candidate.maximum,
            firstProbeIndex: firstProbeIndex
        )
    }

    func elementsEqual(
        _ lhs: ScrollCaptureAccessibilityElement,
        _ rhs: ScrollCaptureAccessibilityElement
    ) -> Bool {
        lhs.rawValue === rhs.rawValue
    }

    func candidateReads(for node: FakeAccessibilityNode) -> Int {
        candidateReadsByNode[ObjectIdentifier(node), default: 0]
    }

    func parentReads(for node: FakeAccessibilityNode) -> Int {
        parentReadsByNode[ObjectIdentifier(node), default: 0]
    }

    private func node(from element: ScrollCaptureAccessibilityElement) -> FakeAccessibilityNode {
        element.rawValue as! FakeAccessibilityNode
    }

    private func increment(
        _ counts: inout [ObjectIdentifier: Int],
        for node: FakeAccessibilityNode
    ) {
        counts[ObjectIdentifier(node), default: 0] += 1
    }
}

private final class FakeMonotonicClock: @unchecked Sendable {
    private let lock = NSLock()
    private var currentTime: TimeInterval = 0

    var now: TimeInterval {
        lock.withLock { currentTime }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            currentTime += interval
        }
    }
}
