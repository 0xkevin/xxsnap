import AppKit
import XCTest
@testable import xxsnap

@MainActor
final class ScrollCaptureSessionTests: XCTestCase {
    func testSessionRecordsDiagnosticLifecycleAndStepEvidence() async throws {
        let logger = RecordingDiagnosticLogger()
        let controller = FakeStepController()
        let engine = FakeStitcher(
            results: [.acceptedInitial, .acceptedAppend],
            directions: [.unknown, .down]
        )
        let session = makeSession(
            engine: engine,
            stepController: controller,
            diagnosticLogger: logger
        )

        try await session.start()
        try await session.performStep(direction: .down)
        _ = try await session.finish()

        XCTAssertEqual(logger.beginSessionCount, 1)
        XCTAssertEqual(logger.endSessionCount, 1)
        XCTAssertEqual(
            logger.events.map(\.event),
            [
                "scroll_session_started",
                "scroll_step_requested",
                "scroll_stitch_result",
                "scroll_step_completed",
                "scroll_session_finished",
            ]
        )
        XCTAssertTrue(logger.events[2].metadata.keys.contains("appended_height"))
        XCTAssertFalse(logger.events[2].metadata.keys.contains("image"))
    }

    func testSessionEndsDiagnosticLifecycleWhenCancelled() async throws {
        let logger = RecordingDiagnosticLogger()
        let session = makeSession(
            engine: FakeStitcher(results: [.acceptedInitial]),
            diagnosticLogger: logger
        )
        try await session.start()

        _ = session.cancel()

        XCTAssertEqual(logger.beginSessionCount, 1)
        XCTAssertEqual(logger.endSessionCount, 1)
        XCTAssertEqual(logger.events.last?.event, "scroll_session_cancelled")
    }

    func testAutomaticStepDistanceUsesFortyPercentBelowSixHundredPoints() {
        XCTAssertEqual(
            ScrollCaptureSession.stepDistance(forViewportHeight: 599),
            239.6,
            accuracy: 0.001
        )
    }

    func testAutomaticStepDistanceUsesFiftyPercentAtSixHundredPoints() {
        XCTAssertEqual(
            ScrollCaptureSession.stepDistance(forViewportHeight: 600),
            300,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScrollCaptureSession.stepDistance(forViewportHeight: 900),
            450,
            accuracy: 0.001
        )
    }

    func testAutomaticStepDistanceReturnsAtLeastOnePointForInvalidOrTinyHeights() {
        XCTAssertEqual(ScrollCaptureSession.stepDistance(forViewportHeight: 0), 1)
        XCTAssertEqual(ScrollCaptureSession.stepDistance(forViewportHeight: -100), 1)
        XCTAssertEqual(ScrollCaptureSession.stepDistance(forViewportHeight: 0.01), 1)
        XCTAssertEqual(ScrollCaptureSession.stepDistance(forViewportHeight: .nan), 1)
        XCTAssertEqual(ScrollCaptureSession.stepDistance(forViewportHeight: .infinity), 1)
        XCTAssertEqual(ScrollCaptureSession.stepDistance(forViewportHeight: -.infinity), 1)
    }

    func testStepModeProbesRightEdgeBeforeOtherTargetsForChatComposer() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(
            results: [.acceptedInitial, .acceptedAppend],
            directions: [.unknown, .down]
        )
        let session = makeSession(engine: engine, stepController: controller)
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.map(\.point), [NSPoint(x: 172, y: 230)])
    }

    func testStepScrollPointsPreferRightEdgeThenContentCenter() {
        let rect = NSRect(x: 100, y: 200, width: 80, height: 60)

        let points = ScrollCaptureSession.stepScrollPoints(in: rect)

        XCTAssertEqual(points, [
            NSPoint(x: 172, y: 230),
            NSPoint(x: 172, y: 245),
            NSPoint(x: 172, y: 215),
            NSPoint(x: 140, y: 230),
            NSPoint(x: 140, y: 245),
            NSPoint(x: 140, y: 215),
            NSPoint(x: 108, y: 230),
            NSPoint(x: 108, y: 245),
        ])
    }

    func testStepModeKeepsSixtyPercentViewportOverlapAndLocksDirectionAfterAppend() async throws {
        let controller = FakeStepController()
        let monitor = FakeActivityMonitor()
        let engine = FakeStitcher(
            results: [.acceptedInitial, .acceptedAppend],
            directions: [.unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            monitor: monitor,
            stepController: controller,
            presentation: presentation
        )

        try await session.start()
        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.startCount, 1)
        XCTAssertEqual(controller.steps.count, 1)
        XCTAssertEqual(controller.steps[0].direction, .down)
        XCTAssertEqual(controller.steps[0].distance, 24, accuracy: 0.001)
        XCTAssertEqual(engine.preferredDirections, [.down])
        XCTAssertEqual(engine.expectedAdvances, [24])
        XCTAssertEqual(engine.previewHeights, [1_200, 1_200])
        XCTAssertEqual(engine.previewWidths, [])
        XCTAssertEqual(presentation.scrollActivities, [
            ScrollCaptureScrollActivity(direction: .down, distance: 24),
        ])
        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertEqual(presentation.stepStates, [
            .ready(directionLocked: false),
            .executing,
            .ready(directionLocked: true),
        ])
    }

    func testStepModePreviewFollowsRequestedDownwardEdgeWhenCoreDirectionIsUp() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(
            results: [.acceptedInitial, .acceptedAppend],
            directions: [.unknown, .up]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(presentation.previewEdges, [.bottom, .bottom])
    }

    func testStepModeUsesFiftyPercentOfLargeSessionSeedHeight() async throws {
        let controller = FakeStepController()
        let monitor = FakeActivityMonitor()
        let engine = FakeStitcher(
            results: [.acceptedInitial, .acceptedAppend],
            directions: [.unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            monitor: monitor,
            stepController: controller,
            presentation: presentation,
            screenRect: NSRect(x: 100, y: 200, width: 80, height: 800)
        )

        try await session.start()
        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.count, 1)
        XCTAssertEqual(controller.steps[0].distance, 400, accuracy: 0.001)
        XCTAssertEqual(presentation.scrollActivities, [
            ScrollCaptureScrollActivity(direction: .down, distance: 400),
        ])
        XCTAssertEqual(monitor.startCount, 1)
    }

    func testStepModeRunsOneThousandOverlappingViewportStepsWithoutFallbackOrReverse() async throws {
        let stepCount = 1_000
        let controller = FakeStepController()
        let engine = FakeStitcher(
            results: [.acceptedInitial] + Array(repeating: .acceptedAppend, count: stepCount),
            directions: [.unknown] + Array(repeating: .down, count: stepCount)
        )
        let session = makeSession(engine: engine, stepController: controller)
        try await session.start()

        for _ in 0..<stepCount {
            try await session.performStep(direction: .down)
        }

        XCTAssertEqual(controller.steps.count, stepCount)
        XCTAssertTrue(controller.steps.allSatisfy {
            $0.direction == .down
                && abs($0.distance - 24) < 0.001
                && $0.point == NSPoint(x: 172, y: 230)
        })
        XCTAssertEqual(engine.preferredDirections, Array(repeating: .down, count: stepCount))
    }

    func testAutomaticStepControllerUsesPhysicalWheelDirectionForSelectedDocumentDirection() {
        XCTAssertEqual(
            AutomaticScrollCaptureStepController.wheelDelta(direction: .down, distance: 420),
            -420
        )
        XCTAssertEqual(
            AutomaticScrollCaptureStepController.wheelDelta(direction: .up, distance: 420),
            420
        )
    }

    func testAutomaticStepEventPolicyBlocksPointerButtonsOnlyDuringProgrammaticStep() {
        XCTAssertFalse(AutomaticScrollCaptureEventPolicy.shouldBlock(
            type: .leftMouseDown,
            sourceTag: 0,
            blocksPointerButtons: false
        ))
        XCTAssertTrue(AutomaticScrollCaptureEventPolicy.shouldBlock(
            type: .leftMouseDown,
            sourceTag: 0,
            blocksPointerButtons: true
        ))
        XCTAssertTrue(AutomaticScrollCaptureEventPolicy.shouldBlock(
            type: .leftMouseUp,
            sourceTag: 0,
            blocksPointerButtons: true
        ))
        XCTAssertFalse(AutomaticScrollCaptureEventPolicy.shouldBlock(
            type: .leftMouseDown,
            sourceTag: automaticScrollCaptureEventTag,
            blocksPointerButtons: true
        ))
        XCTAssertFalse(AutomaticScrollCaptureEventPolicy.shouldBlock(
            type: .mouseMoved,
            sourceTag: 0,
            blocksPointerButtons: true
        ))
        XCTAssertTrue(AutomaticScrollCaptureEventPolicy.shouldBlock(
            type: .scrollWheel,
            sourceTag: 0,
            blocksPointerButtons: false
        ))
        XCTAssertFalse(AutomaticScrollCaptureEventPolicy.shouldBlock(
            type: .scrollWheel,
            sourceTag: automaticScrollCaptureEventTag,
            blocksPointerButtons: false
        ))
    }

    func testAutomaticStepControllerDetectsTopAndBottomFromScrollBarRange() {
        XCTAssertEqual(
            AutomaticScrollCaptureStepController.boundaryState(
                direction: .up,
                value: 0,
                minimum: 0,
                maximum: 1
            ),
            .atBoundary
        )
        XCTAssertEqual(
            AutomaticScrollCaptureStepController.boundaryState(
                direction: .down,
                value: 1,
                minimum: 0,
                maximum: 1
            ),
            .atBoundary
        )
        XCTAssertEqual(
            AutomaticScrollCaptureStepController.boundaryState(
                direction: .up,
                value: 0.5,
                minimum: 0,
                maximum: 1
            ),
            .notAtBoundary
        )
        XCTAssertEqual(
            AutomaticScrollCaptureStepController.boundaryState(
                direction: .down,
                value: 0.5,
                minimum: 0,
                maximum: 1
            ),
            .notAtBoundary
        )
    }

    func testAutomaticStepMovesPointerToCapturePointBeforePostingAndRestoresIt() async throws {
        let originalPointer = CGPoint(x: 910, y: 640)
        var eventLocations: [CGPoint] = []
        var scrollPhases: [Int64] = []
        var momentumPhases: [Int64] = []
        var continuousScrollFlags: [Int64] = []
        var pointerMoves: [CGPoint] = []
        let controller = AutomaticScrollCaptureStepController(
            eventDispatcher: { event, _ in
                eventLocations.append(event.location)
                if event.type == .scrollWheel {
                    scrollPhases.append(event.getIntegerValueField(.scrollWheelEventScrollPhase))
                    momentumPhases.append(event.getIntegerValueField(.scrollWheelEventMomentumPhase))
                    continuousScrollFlags.append(event.getIntegerValueField(.scrollWheelEventIsContinuous))
                }
            },
            pointerLocationProvider: { originalPointer },
            pointerWarper: { pointerMoves.append($0) }
        )

        try await controller.performStep(
            direction: .down,
            distance: 70,
            at: NSPoint(x: 240, y: 320)
        )

        XCTAssertEqual(eventLocations.count, 3)
        XCTAssertTrue(eventLocations.allSatisfy { $0 != .zero })
        XCTAssertTrue(eventLocations.allSatisfy { $0 != originalPointer })
        XCTAssertEqual(scrollPhases, [0])
        XCTAssertEqual(momentumPhases, [0])
        XCTAssertEqual(continuousScrollFlags, [0])
        XCTAssertEqual(pointerMoves.count, 3)
        XCTAssertEqual(pointerMoves.first, eventLocations.first)
        XCTAssertEqual(pointerMoves[1], eventLocations[1])
        XCTAssertEqual(pointerMoves.last, originalPointer)
        controller.stop()
    }

    func testAutomaticStepUsesBoundedDiscreteWheelTicksForLargeViewport() async throws {
        var continuousScrollFlags: [Int64] = []
        var wheelDeltas: [Int64] = []
        let controller = AutomaticScrollCaptureStepController(
            eventDispatcher: { event, _ in
                guard event.type == .scrollWheel else { return }
                continuousScrollFlags.append(
                    event.getIntegerValueField(.scrollWheelEventIsContinuous)
                )
                wheelDeltas.append(
                    event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                )
            },
            pointerLocationProvider: { CGPoint(x: 910, y: 640) },
            pointerWarper: { _ in }
        )

        try await controller.performStep(
            direction: .down,
            distance: 1_019,
            at: NSPoint(x: 240, y: 320)
        )

        XCTAssertEqual(continuousScrollFlags, Array(repeating: 0, count: 9))
        XCTAssertEqual(wheelDeltas.reduce(0, +), -25)
        XCTAssertTrue(wheelDeltas.allSatisfy { abs($0) <= 3 })
        controller.stop()
    }

    func testAutomaticStepKeepsPointerRoutedWheelEventsGlobal() async throws {
        var deliveredProcessIdentifiers: [pid_t?] = []
        var activatedProcessIdentifiers: [pid_t] = []
        let controller = AutomaticScrollCaptureStepController(
            eventDispatcher: { _, processIdentifier in
                deliveredProcessIdentifiers.append(processIdentifier)
            },
            targetProcessIdentifierProvider: { 42 },
            targetApplicationActivator: { activatedProcessIdentifiers.append($0) }
        )

        try await controller.performStep(
            direction: .down,
            distance: 70,
            at: NSPoint(x: 240, y: 320)
        )

        XCTAssertEqual(deliveredProcessIdentifiers.count, 3)
        XCTAssertTrue(deliveredProcessIdentifiers.allSatisfy { $0 == nil })
        XCTAssertEqual(activatedProcessIdentifiers, [42])
    }

    func testAutomaticTargetedStepPostsWheelEventsDirectlyToCapturedApplication() async throws {
        var eventTypes: [CGEventType] = []
        var deliveredProcessIdentifiers: [pid_t?] = []
        let controller = AutomaticScrollCaptureStepController(
            eventDispatcher: { event, processIdentifier in
                eventTypes.append(event.type)
                deliveredProcessIdentifiers.append(processIdentifier)
            },
            pointerLocationProvider: { CGPoint(x: 910, y: 640) },
            pointerWarper: { _ in },
            targetProcessIdentifierProvider: { 42 }
        )

        let performed = try await controller.performTargetedStep(
            direction: .down,
            distance: 70,
            at: NSPoint(x: 240, y: 320)
        )

        XCTAssertTrue(performed)
        XCTAssertEqual(eventTypes, [.mouseMoved, .mouseMoved, .scrollWheel])
        XCTAssertEqual(deliveredProcessIdentifiers.compactMap { $0 }, [42, 42, 42])
    }

    func testOuterScrollbarDetectorFindsAContiguousDarkThumbAtTheRightEdge() throws {
        let image = TestImageFactory.browserScrollbar()

        let observation = try XCTUnwrap(OuterScrollbarThumbDetector.detect(in: image))

        XCTAssertGreaterThan(observation.pixelX, 220)
        XCTAssertEqual(observation.thumbLength, 40, accuracy: 2)
    }

    func testOuterScrollbarDetectorIgnoresSeparateDarkWindowBorderAtTop() throws {
        let image = TestImageFactory.browserScrollbar(
            thumbVisualRange: 70..<150,
            extraDarkVisualRange: 0..<6
        )

        let observation = try XCTUnwrap(OuterScrollbarThumbDetector.detect(in: image))

        XCTAssertEqual(observation.thumbLength, 80, accuracy: 2)
    }

    func testAutomaticScrollbarStepDragsDetectedThumbWithoutClickingPageContent() async throws {
        var eventTypes: [CGEventType] = []
        var eventLocations: [CGPoint] = []
        let image = TestImageFactory.browserScrollbar()
        let controller = AutomaticScrollCaptureStepController(
            eventDispatcher: { event, _ in
                eventTypes.append(event.type)
                eventLocations.append(event.location)
            },
            pointerLocationProvider: { CGPoint(x: 900, y: 700) },
            pointerWarper: { _ in },
            targetProcessIdentifierProvider: { 42 }
        )

        let performed = try await controller.performScrollbarStep(
            direction: .down,
            distance: 50,
            in: NSRect(x: 100, y: 200, width: 120, height: 100),
            capturedImage: image
        )

        XCTAssertTrue(performed)
        XCTAssertEqual(eventTypes.first, .mouseMoved)
        XCTAssertEqual(eventTypes.dropFirst().first, .leftMouseDown)
        XCTAssertTrue(eventTypes.contains(.leftMouseDragged))
        XCTAssertEqual(eventTypes.last, .leftMouseUp)
        XCTAssertTrue(eventLocations.allSatisfy { $0.x > 210 })
    }

    func testAutomaticKeyboardFallbackPostsArrowKeysForFocusedScrollArea() async throws {
        var eventTypes: [CGEventType] = []
        var keyCodes: [Int64] = []
        var deliveredProcessIdentifiers: [pid_t?] = []
        var activatedProcessIdentifiers: [pid_t] = []
        let controller = AutomaticScrollCaptureStepController(
            eventDispatcher: { event, processIdentifier in
                eventTypes.append(event.type)
                keyCodes.append(event.getIntegerValueField(.keyboardEventKeycode))
                deliveredProcessIdentifiers.append(processIdentifier)
            },
            targetProcessIdentifierProvider: { 42 },
            targetApplicationActivator: { activatedProcessIdentifiers.append($0) }
        )

        let performed = try await controller.performKeyboardStep(direction: .down, distance: 70)

        XCTAssertTrue(performed)
        XCTAssertEqual(eventTypes, [.keyDown, .keyUp, .keyDown, .keyUp])
        XCTAssertEqual(keyCodes, [125, 125, 125, 125])
        XCTAssertEqual(deliveredProcessIdentifiers.compactMap { $0 }, Array(repeating: 42, count: 4))
        XCTAssertEqual(activatedProcessIdentifiers, [42])
    }

    func testAutomaticKeyboardFallbackCoversLargeViewportStepWithoutTwelvePressCap() async throws {
        var eventCount = 0
        let controller = AutomaticScrollCaptureStepController(
            eventDispatcher: { _, _ in eventCount += 1 },
            targetProcessIdentifierProvider: { 42 }
        )

        let performed = try await controller.performKeyboardStep(direction: .up, distance: 1_019)

        XCTAssertTrue(performed)
        XCTAssertEqual(eventCount, 50)
    }

    func testStepModeDropsFramesCapturedDuringSyntheticScrollBeforeMatching() async throws {
        var operations: [String] = []
        let controller = FakeStepController {
            operations.append("step")
        }
        let capturer = BufferingFakeCapturer {
            operations.append("discard")
        } onCapture: {
            operations.append("capture")
        }
        let engine = FakeStitcher(results: [.acceptedInitial, .acceptedAppend])
        let session = makeSession(
            capturer: capturer,
            engine: engine,
            stepController: controller
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(operations, ["discard", "step", "discard", "capture"])
    }

    func testStepModeUsesQueuedCandidateToRecoverFromLowConfidence() async throws {
        let controller = FakeStepController()
        let capturer = FakeCapturer()
        capturer.images.append(TestImageFactory.solid(size: CGSize(width: 80, height: 60), color: .blue))
        let engine = FakeStitcher(
            results: [.acceptedInitial, .lowConfidenceDiscarded, .acceptedAppend],
            directions: [.unknown, .unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            capturer: capturer,
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.count, 1)
        XCTAssertEqual(capturer.captureCount, 2)
        XCTAssertEqual(presentation.kinds.suffix(2), [.lowConfidenceDiscarded, .acceptedAppend])
        XCTAssertTrue(presentation.warnings.isEmpty)
        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
    }

    func testStepModeRetriesAtHalfDistanceInsteadOfEndingWithAReverseScroll() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .lowConfidenceDiscarded, .lowConfidenceDiscarded,
                .acceptedAppend,
            ],
            directions: [.unknown, .unknown, .unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.map(\.direction), [.down, .up, .down])
        XCTAssertEqual(controller.steps.map(\.distance), [24, 24, 12])
        XCTAssertEqual(controller.steps.map(\.point), [
            NSPoint(x: 172, y: 230),
            NSPoint(x: 172, y: 230),
            NSPoint(x: 172, y: 230),
        ])
        XCTAssertEqual(presentation.scrollActivities, [
            ScrollCaptureScrollActivity(direction: .down, distance: 24),
            ScrollCaptureScrollActivity(direction: .up, distance: 24),
            ScrollCaptureScrollActivity(direction: .down, distance: 12),
        ])
        XCTAssertTrue(presentation.warnings.isEmpty)
        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
    }

    func testStepModeRetriesAtQuarterDistanceWhenLargeWhiteRegionDefeatsHalfStep() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .lowConfidenceDiscarded, .lowConfidenceDiscarded,
                .lowConfidenceDiscarded, .lowConfidenceDiscarded,
                .acceptedAppend,
            ],
            directions: [.unknown, .unknown, .unknown, .unknown, .unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.map(\.direction), [.down, .up, .down, .up, .down])
        XCTAssertEqual(controller.steps.map(\.distance), [24, 24, 12, 12, 6])
        XCTAssertTrue(presentation.warnings.isEmpty)
        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
    }

    func testStepModeWarnsOnlyAfterProgressiveRecoveryAlsoHasLowConfidence() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(results: [
            .acceptedInitial,
            .lowConfidenceDiscarded, .lowConfidenceDiscarded,
            .lowConfidenceDiscarded, .lowConfidenceDiscarded,
            .lowConfidenceDiscarded, .lowConfidenceDiscarded,
        ])
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(presentation.warnings, [.lowConfidence])
        XCTAssertEqual(presentation.warningEvents.count, 1)
    }

    func testStepModeTreatsRepeatedLowConfidenceWithoutGrowthAsVisualBoundaryAfterProgress() async throws {
        let controller = FakeStepController(boundaryState: .notAtBoundary)
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .acceptedAppend,
            ] + Array(repeating: .lowConfidenceDiscarded, count: 12),
            directions: [.unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()
        try await session.performStep(direction: .down)

        try await session.performStep(direction: .down)
        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
        XCTAssertEqual(presentation.warnings, [.lowConfidence])

        try await session.performStep(direction: .down)
        XCTAssertEqual(presentation.stepStates.last, .boundary)
        XCTAssertNil(presentation.warningEvents.last!)
    }

    func testStepModeUsesAcceptedContentDirectionForSubsequentMatching() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(
            results: [.acceptedInitial, .acceptedAppend, .acceptedAppend],
            directions: [.unknown, .down, .down]
        )
        let session = makeSession(engine: engine, stepController: controller)
        try await session.start()

        try await session.performStep(direction: .up)
        try await session.performStep(direction: .up)

        XCTAssertEqual(engine.preferredDirections, [.up, .down])
    }

    func testStepModeUsesAcceptedContentDirectionForBoundaryChecks() async throws {
        let controller = FakeStepController { direction, _ in
            direction == .down ? .atBoundary : .notAtBoundary
        }
        let engine = FakeStitcher(
            results: [.acceptedInitial, .acceptedAppend, .duplicateDiscarded],
            directions: [.unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .up)
        try await session.performStep(direction: .up)

        XCTAssertEqual(controller.steps.count, 1)
        XCTAssertEqual(controller.boundaryChecks.suffix(5).map(\.direction), Array(repeating: .down, count: 5))
        XCTAssertEqual(presentation.stepStates.last, .boundary)
    }

    func testStepModeTreatsRepeatedReviewAfterLockedMovementAsVisualBoundary() async throws {
        let controller = FakeStepController(boundaryState: .notAtBoundary)
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .acceptedAppend,
                .reviewDiscarded, .reviewDiscarded,
                .reviewDiscarded, .reviewDiscarded,
                .reviewDiscarded, .reviewDiscarded,
            ],
            directions: [.unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()
        try await session.performStep(direction: .up)

        try await session.performStep(direction: .up)

        XCTAssertEqual(presentation.stepStates.last, .boundary)
        XCTAssertTrue(presentation.warnings.isEmpty)
    }

    func testStepModeDoesNotTreatRepeatedReviewAsBoundaryWhenDirectionsAgree() async throws {
        let controller = FakeStepController(boundaryState: .notAtBoundary)
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .acceptedAppend,
                .reviewDiscarded, .reviewDiscarded,
                .reviewDiscarded, .reviewDiscarded,
                .reviewDiscarded, .reviewDiscarded,
            ],
            directions: [.unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()
        try await session.performStep(direction: .down)

        try await session.performStep(direction: .down)

        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
        XCTAssertEqual(presentation.warnings, [.lowConfidence])
    }

    func testStepModeStillAcceptsPartialStepAfterReviewRecovery() async throws {
        let controller = FakeStepController(boundaryState: .notAtBoundary)
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .acceptedAppend,
                .reviewDiscarded, .reviewDiscarded,
                .acceptedAppend,
            ],
            directions: [.unknown, .down, .unknown, .unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()
        try await session.performStep(direction: .down)

        try await session.performStep(direction: .down)

        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
        XCTAssertTrue(presentation.warnings.isEmpty)
        XCTAssertEqual(controller.steps.map(\.direction), [.down, .down, .up, .down])
    }

    func testStepModeConfirmsBottomBoundaryFromAccessibilityWithoutScrolling() async throws {
        let controller = FakeStepController(boundaryState: .atBoundary)
        let engine = FakeStitcher(results: [.acceptedInitial, .duplicateDiscarded])
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.boundaryChecks.count, 8)
        XCTAssertTrue(controller.boundaryChecks.allSatisfy { $0.direction == .down })
        XCTAssertTrue(controller.steps.isEmpty)
        XCTAssertTrue(controller.keyboardSteps.isEmpty)
        XCTAssertEqual(presentation.stepStates.last, .boundary)
    }

    func testStepModeConfirmsTopBoundaryFromAccessibilityWithoutScrolling() async throws {
        let controller = FakeStepController(boundaryState: .atBoundary)
        let engine = FakeStitcher(results: [.acceptedInitial, .duplicateDiscarded])
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .up)

        XCTAssertEqual(controller.boundaryChecks.count, 8)
        XCTAssertTrue(controller.boundaryChecks.allSatisfy { $0.direction == .up })
        XCTAssertTrue(controller.steps.isEmpty)
        XCTAssertTrue(controller.keyboardSteps.isEmpty)
        XCTAssertEqual(presentation.stepStates.last, .boundary)
    }

    func testStepModeUsesAccessibilityScrollableTargetBeforeUnknownTargets() async throws {
        let scrollablePoint = NSPoint(x: 172, y: 245)
        let controller = FakeStepController { _, point in
            point == scrollablePoint ? .notAtBoundary : .unavailable
        }
        let engine = FakeStitcher(
            results: [.acceptedInitial, .acceptedAppend],
            directions: [.unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.map(\.point), [scrollablePoint])
        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
    }

    func testStepModeAppendsCurrentFrameBeforeTrustingAccessibilityBoundary() async throws {
        let controller = FakeStepController(boundaryState: .atBoundary)
        let engine = FakeStitcher(
            results: [.acceptedInitial, .acceptedAppend],
            directions: [.unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertTrue(controller.steps.isEmpty)
        XCTAssertEqual(engine.appendedImages.count, 2)
        XCTAssertEqual(presentation.previewEdges, [.bottom, .bottom])
        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
    }

    func testStepModeConfirmsBottomBoundaryAfterOneClickWhenAccessibilityIsUnavailable() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(results: [
            .acceptedInitial,
            .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
            .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
            .duplicateDiscarded, .duplicateDiscarded,
        ])
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.map(\.distance), Array(repeating: 24, count: 8))
        XCTAssertEqual(controller.steps.map(\.point), [
            NSPoint(x: 172, y: 230),
            NSPoint(x: 172, y: 245),
            NSPoint(x: 172, y: 215),
            NSPoint(x: 140, y: 230),
            NSPoint(x: 140, y: 245),
            NSPoint(x: 140, y: 215),
            NSPoint(x: 108, y: 230),
            NSPoint(x: 108, y: 245),
        ])
        XCTAssertEqual(presentation.stepStates.last, .boundary)
        XCTAssertTrue(presentation.warnings.isEmpty)

        try await session.performStep(direction: .down)
        XCTAssertEqual(controller.steps.count, 8)
        XCTAssertEqual(presentation.stepStates.last, .boundary)
    }

    func testStepModeConfirmsTopBoundaryAfterOneClickWhenAccessibilityIsUnavailable() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(results: [
            .acceptedInitial,
            .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
            .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
            .duplicateDiscarded, .duplicateDiscarded,
        ])
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .up)

        XCTAssertEqual(controller.steps.count, 8)
        XCTAssertTrue(controller.steps.allSatisfy { $0.direction == .up })
        XCTAssertEqual(presentation.stepStates.last, .boundary)
        XCTAssertTrue(presentation.warnings.isEmpty)
    }

    func testStepModeDoesNotTreatReviewFramesAsBoundaryEvidence() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(results: [
            .acceptedInitial,
        ] + Array(repeating: .reviewDiscarded, count: 16))
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .up)

        XCTAssertNotEqual(presentation.stepStates.last, .boundary)
        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: false))
        XCTAssertEqual(presentation.warnings, [.lowConfidence])
    }

    func testStepModeDoesNotReportBoundaryWhenAccessibilitySaysMoreContentRemains() async throws {
        let controller = FakeStepController(boundaryState: .notAtBoundary)
        let engine = FakeStitcher(results: [
            .acceptedInitial,
            .lowConfidenceDiscarded, .lowConfidenceDiscarded,
            .duplicateDiscarded, .duplicateDiscarded,
        ])
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: false))
        XCTAssertEqual(presentation.warnings, [.lowConfidence])
    }

    func testStepModeRecoversAtAnotherPointInsideSelectionWithoutEndingCapture() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .duplicateDiscarded, .duplicateDiscarded,
                .acceptedAppend,
                .acceptedAppend,
            ],
            directions: [.unknown, .unknown, .unknown, .down, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)
        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.map(\.point), [
            NSPoint(x: 172, y: 230),
            NSPoint(x: 172, y: 245),
            NSPoint(x: 172, y: 215),
            NSPoint(x: 172, y: 215),
        ])
        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
        XCTAssertTrue(presentation.warnings.isEmpty)
    }

    func testStepModeUsesFocusedKeyboardFallbackWhenWheelTargetsStayStationary() async throws {
        let controller = FakeStepController(keyboardResult: true)
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
                .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
                .duplicateDiscarded, .duplicateDiscarded,
                .acceptedAppend,
            ],
            directions: [.unknown] + Array(repeating: .unknown, count: 8) + [.down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.count, 8)
        XCTAssertEqual(controller.keyboardSteps.count, 1)
        XCTAssertEqual(controller.keyboardSteps[0].direction, .down)
        XCTAssertEqual(controller.keyboardSteps[0].distance, 24, accuracy: 0.001)
        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
        XCTAssertTrue(presentation.warnings.isEmpty)
    }

    func testStepModeUsesTargetedWheelFallbackBeforeKeyboardWhenGlobalWheelStopsMoving() async throws {
        let controller = FakeStepController(targetedResult: true, keyboardResult: true)
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
                .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
                .duplicateDiscarded, .duplicateDiscarded,
                .acceptedAppend,
            ],
            directions: [.unknown] + Array(repeating: .unknown, count: 8) + [.down]
        )
        let session = makeSession(engine: engine, stepController: controller)
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.targetedSteps.count, 1)
        XCTAssertEqual(controller.targetedSteps[0].direction, .down)
        XCTAssertTrue(controller.keyboardSteps.isEmpty)
    }

    func testStepModeUsesVisibleScrollbarFallbackBeforeKeyboard() async throws {
        let controller = FakeStepController(
            targetedResult: true,
            scrollbarResult: true,
            keyboardResult: true
        )
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
                .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
                .duplicateDiscarded, .duplicateDiscarded,
                .acceptedAppend,
            ],
            directions: [.unknown] + Array(repeating: .unknown, count: 8) + [.down]
        )
        let session = makeSession(engine: engine, stepController: controller)
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.scrollbarSteps.count, 1)
        XCTAssertEqual(controller.scrollbarSteps[0].direction, .down)
        XCTAssertTrue(controller.targetedSteps.isEmpty)
        XCTAssertTrue(controller.keyboardSteps.isEmpty)
    }

    func testLockedStepUsesVisibleScrollbarAfterFirstStationaryWheelProbe() async throws {
        let controller = FakeStepController(scrollbarResult: true)
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .acceptedAppend,
                .duplicateDiscarded,
                .acceptedAppend,
            ],
            directions: [.unknown, .down, .unknown, .down]
        )
        let session = makeSession(engine: engine, stepController: controller)
        try await session.start()

        try await session.performStep(direction: .down)
        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.count, 2)
        XCTAssertEqual(controller.scrollbarSteps.count, 1)
        XCTAssertTrue(controller.targetedSteps.isEmpty)
        XCTAssertTrue(controller.keyboardSteps.isEmpty)
    }

    func testLockedStepContinuesProbingAfterScrollbarReviewAtEdge() async throws {
        let controller = FakeStepController(scrollbarResult: true)
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .acceptedAppend,
                .duplicateDiscarded,
                .reviewDiscarded,
                .acceptedAppend,
            ],
            directions: [.unknown, .down, .unknown, .unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)
        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.map(\.point), [
            NSPoint(x: 172, y: 230),
            NSPoint(x: 172, y: 230),
            NSPoint(x: 172, y: 245),
        ])
        XCTAssertEqual(controller.scrollbarSteps.count, 1)
        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
        XCTAssertTrue(presentation.warnings.isEmpty)
    }

    func testLowConfidenceAfterTargetSwitchIsReversedAtTheSamePoint() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .duplicateDiscarded, .duplicateDiscarded,
                .lowConfidenceDiscarded, .lowConfidenceDiscarded,
                .acceptedAppend,
            ],
            directions: [.unknown, .unknown, .unknown, .unknown, .unknown, .down]
        )
        let session = makeSession(engine: engine, stepController: controller)
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.map(\.direction), [.down, .down, .down, .up, .down])
        XCTAssertEqual(controller.steps.map(\.point), [
            NSPoint(x: 172, y: 230),
            NSPoint(x: 172, y: 245),
            NSPoint(x: 172, y: 215),
            NSPoint(x: 172, y: 215),
            NSPoint(x: 172, y: 215),
        ])
    }

    func testStepModeFindsMovementAtLastTargetWithinOneClick() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
                .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
                .duplicateDiscarded,
                .acceptedAppend,
            ],
            directions: [.unknown] + Array(repeating: .unknown, count: 7) + [.down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(presentation.kinds.last, .acceptedAppend)
        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
        XCTAssertEqual(controller.steps.count, 8)
    }

    func testStepModeFindsMovementAtContentCenterAfterRightEdgeFails() async throws {
        let controller = FakeStepController()
        let engine = FakeStitcher(
            results: [
                .acceptedInitial,
                .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded,
                .acceptedAppend,
            ],
            directions: [.unknown, .unknown, .unknown, .unknown, .down]
        )
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: engine,
            stepController: controller,
            presentation: presentation
        )
        try await session.start()

        try await session.performStep(direction: .down)

        XCTAssertEqual(controller.steps.map(\.point), [
            NSPoint(x: 172, y: 230),
            NSPoint(x: 172, y: 245),
            NSPoint(x: 172, y: 215),
            NSPoint(x: 140, y: 230),
        ])
        XCTAssertEqual(presentation.stepStates.last, .ready(directionLocked: true))
    }

    func testScrollDirectionIsForwardedToLiveStitchAppend() async throws {
        let engine = FakeStitcher(results: [.acceptedInitial, .acceptedAppend], directions: [.unknown, .up])
        let session = makeSession(engine: engine)
        try await session.start()

        session.recordScrollActivity(direction: .up)
        await session.test_runSamplingTick()

        XCTAssertEqual(engine.preferredDirections, [.up])
    }

    func testStartAppendsFrozenSeedExactlyOnceBeforeCapturing() async throws {
        let engine = FakeStitcher(results: [.acceptedInitial])
        let presentation = PresentationRecorder()
        let session = makeSession(engine: engine, presentation: presentation)

        try await session.start()

        XCTAssertEqual(session.state, .capturing)
        XCTAssertEqual(engine.appendedImages.count, 1)
        XCTAssertTrue(engine.appendedImages[0] === session.seed.frozenImage)
        XCTAssertEqual(presentation.states, [.preparing, .capturing])
        XCTAssertEqual(presentation.kinds, [.acceptedInitial])
    }

    func testStartPrimesLiveFrameSourceWithoutSamplingBeforeScrollActivity() async throws {
        let capturer = PrimingFakeCapturer()
        let clock = ControlledClock()
        let monitor = FakeActivityMonitor()
        let engine = FakeStitcher(results: [.acceptedInitial])
        let session = makeSession(
            capturer: capturer,
            engine: engine,
            clock: clock,
            monitor: monitor
        )

        try await session.start()
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(capturer.primeCount, 1)
        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertEqual(capturer.captureCount, 0)
        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertFalse(session.isSamplingArmed)
    }

    func testStartDoesNotDiscardPrimedBufferedFramesBeforeScrollActivity() async throws {
        let capturer = PrimingBufferingFakeCapturer()
        let engine = FakeStitcher(results: [.acceptedInitial])
        let session = makeSession(capturer: capturer, engine: engine)

        try await session.start()

        XCTAssertEqual(capturer.operations, ["prime"])
        XCTAssertEqual(capturer.discardCount, 0)
        XCTAssertEqual(capturer.captureCount, 0)
    }

    func testFirstScrollActivityDiscardsBufferedFramesBeforeSamplingCapture() async throws {
        let capturer = PrimingBufferingFakeCapturer()
        let monitor = FakeActivityMonitor()
        let engine = FakeStitcher(results: [.acceptedInitial, .duplicateDiscarded])
        let session = makeSession(capturer: capturer, engine: engine, monitor: monitor)
        try await session.start()

        monitor.send(ScrollCaptureScrollActivity(direction: .down, distance: 12))

        await waitUntil { capturer.captureCount == 1 }
        XCTAssertEqual(capturer.discardCount, 1)
        XCTAssertEqual(capturer.operations, ["prime", "discard", "capture"])
        _ = session.cancel()
    }

    func testRepeatedActivityWhileSamplingIsArmedDoesNotDiscardBufferedFramesAgain() async throws {
        let capturer = PrimingBufferingFakeCapturer()
        let engine = FakeStitcher(results: [.acceptedInitial, .duplicateDiscarded])
        let session = makeSession(capturer: capturer, engine: engine)
        try await session.start()

        session.recordScrollActivity()
        session.recordScrollActivity()

        XCTAssertEqual(capturer.discardCount, 1)
        await session.test_runSamplingTick()
        XCTAssertEqual(capturer.operations, ["prime", "discard", "capture"])
    }

    func testActivityAfterStableDisarmDiscardsBufferedFramesAgain() async throws {
        let capturer = PrimingBufferingFakeCapturer()
        let engine = FakeStitcher(results: [
            .acceptedInitial,
            .duplicateDiscarded,
            .duplicateDiscarded,
            .duplicateDiscarded,
        ])
        let session = makeSession(capturer: capturer, engine: engine)
        try await session.start()
        session.recordScrollActivity()
        await session.test_runSamplingTick()
        await session.test_runSamplingTick()
        await session.test_runSamplingTick()
        XCTAssertFalse(session.isSamplingArmed)

        session.recordScrollActivity()

        XCTAssertTrue(session.isSamplingArmed)
        XCTAssertEqual(capturer.discardCount, 2)
        _ = session.cancel()
    }

    func testMonitoredScrollActivityStartsSamplingAfterPriming() async throws {
        let capturer = PrimingFakeCapturer()
        let clock = ControlledClock()
        let monitor = FakeActivityMonitor()
        let engine = FakeStitcher(results: [.acceptedInitial, .duplicateDiscarded])
        let session = makeSession(
            capturer: capturer,
            engine: engine,
            clock: clock,
            monitor: monitor
        )
        try await session.start()

        monitor.send(ScrollCaptureScrollActivity(direction: .down, distance: 12))

        await waitUntil { capturer.captureCount == 1 && clock.pendingCount == 1 }
        XCTAssertTrue(session.isSamplingArmed)
        XCTAssertEqual(engine.preferredDirections, [.down])
        _ = session.cancel()
    }

    func testStartRejectsNonInitialResultAndPausesForCaptureFailure() async {
        let engine = FakeStitcher(results: [.acceptedAppend])
        let session = makeSession(engine: engine)

        await XCTAssertThrowsErrorAsync { try await session.start() }

        XCTAssertEqual(session.state, .paused(.captureFailure))
        XCTAssertEqual(engine.appendedImages.count, 1)
    }

    func testActivityArmsSamplingAndAcceptedAppendKeepsItArmed() async throws {
        let engine = FakeStitcher(results: [.acceptedInitial, .acceptedAppend])
        let session = makeSession(engine: engine)
        try await session.start()

        session.recordScrollActivity()
        XCTAssertTrue(session.isSamplingArmed)
        await session.test_runSamplingTick()

        XCTAssertEqual(session.state, .capturing)
        XCTAssertTrue(session.isSamplingArmed)
        XCTAssertEqual(engine.appendedImages.count, 2)
    }

    func testDirectionalActivitySamplesBeforeWaitingForThePeriodicInterval() async throws {
        let clock = ControlledClock()
        let capturer = FakeCapturer()
        let engine = FakeStitcher(results: [.acceptedInitial, .acceptedAppend])
        let session = makeSession(capturer: capturer, engine: engine, clock: clock)
        try await session.start()

        session.recordScrollActivity(direction: .down)

        await waitUntil { engine.appendedImages.count == 2 }
        XCTAssertEqual(capturer.captureCount, 1)
        XCTAssertEqual(engine.preferredDirections, [.down])
        XCTAssertEqual(clock.pendingCount, 1)
        _ = session.cancel()
    }

    func testAcceptedAppendPublishesPreviewAtLockedDirectionEdge() async throws {
        for (direction, expectedEdge) in [
            (ScrollCaptureDirection.down, ScrollCapturePreviewEdge.bottom),
            (.up, .top),
        ] {
            let engine = FakeStitcher(
                results: [.acceptedInitial, .acceptedAppend],
                directions: [.unknown, direction]
            )
            let presentation = PresentationRecorder()
            let session = makeSession(engine: engine, presentation: presentation)
            try await session.start()
            session.recordScrollActivity()

            await session.test_runSamplingTick()

            XCTAssertEqual(presentation.previewEdges, [.bottom, expectedEdge])
            XCTAssertEqual(presentation.previewViewports.count, 2)
            XCTAssertTrue(presentation.previewViewports.allSatisfy {
                $0.viewportHeight > 0 && $0.outputHeight >= $0.viewportHeight
            })
        }
    }

    func testAcceptedAppendWithUnknownDirectionFailsSafely() async throws {
        let engine = FakeStitcher(
            results: [.acceptedInitial, .acceptedAppend],
            directions: [.unknown, .unknown]
        )
        let session = makeSession(engine: engine)
        try await session.start()
        session.recordScrollActivity()

        await session.test_runSamplingTick()

        XCTAssertEqual(session.state, .paused(.captureFailure))
        XCTAssertFalse(session.isSamplingArmed)
        XCTAssertEqual(engine.previewCallCount, 1)
    }

    func testThreeStableDuplicateFramesDisarmSampling() async throws {
        let capturer = FakeCapturer()
        let engine = FakeStitcher(results: [
            .acceptedInitial,
            .duplicateDiscarded,
            .duplicateDiscarded,
            .duplicateDiscarded,
        ])
        let session = makeSession(capturer: capturer, engine: engine)
        try await session.start()
        session.recordScrollActivity()

        await session.test_runSamplingTick()
        await session.test_runSamplingTick()
        await session.test_runSamplingTick()

        XCTAssertFalse(session.isSamplingArmed)
        XCTAssertEqual(capturer.captureCount, 3)
        await session.test_runSamplingTick()
        XCTAssertEqual(capturer.captureCount, 3)
        XCTAssertEqual(session.state, .capturing)
    }

    func testThreeStableReviewFramesDisarmSamplingWithoutPublishingPreview() async throws {
        let capturer = FakeCapturer()
        let engine = FakeStitcher(results: [.acceptedInitial, .reviewDiscarded, .reviewDiscarded, .reviewDiscarded])
        let presentation = PresentationRecorder()
        let session = makeSession(capturer: capturer, engine: engine, presentation: presentation)
        try await session.start()
        session.recordScrollActivity()

        await session.test_runSamplingTick()
        await session.test_runSamplingTick()
        await session.test_runSamplingTick()

        XCTAssertFalse(session.isSamplingArmed)
        XCTAssertEqual(capturer.captureCount, 3)
        XCTAssertEqual(presentation.previews.count, 1)
        XCTAssertEqual(presentation.kinds, [.acceptedInitial, .reviewDiscarded, .reviewDiscarded, .reviewDiscarded])
    }

    func testResourceLimitPausesAndScrollActivityCannotRearmSampling() async throws {
        let limitEngine = FakeStitcher(results: [.acceptedInitial, .resourceLimit, .acceptedAppend])
        let limitSession = makeSession(engine: limitEngine)
        try await limitSession.start()
        limitSession.recordScrollActivity()
        await limitSession.test_runSamplingTick()
        XCTAssertEqual(limitSession.state, .paused(.resourceLimit))
        XCTAssertFalse(limitSession.isSamplingArmed)
        limitSession.recordScrollActivity()
        await limitSession.test_runSamplingTick()
        XCTAssertFalse(limitSession.isSamplingArmed)
        XCTAssertEqual(limitEngine.appendedImages.count, 2)
    }

    func testAwaitingEvidenceKeepsLoopArmedAndAcceptedAppendPublishesWithoutNewActivity() async throws {
        let clock = ControlledClock()
        let engine = FakeStitcher(results: [.acceptedInitial, .awaitingEvidence, .awaitingEvidence, .acceptedAppend])
        let presentation = PresentationRecorder()
        let session = makeSession(engine: engine, clock: clock, presentation: presentation)
        try await session.start()
        session.recordScrollActivity()
        await waitUntil { clock.pendingCount == 1 }

        clock.advance()
        await waitUntil { engine.appendedImages.count == 2 && clock.pendingCount == 1 }
        XCTAssertEqual(session.state, .capturing)
        XCTAssertTrue(session.isSamplingArmed)
        XCTAssertEqual(presentation.previews.count, 1)
        XCTAssertTrue(presentation.warningEvents.isEmpty)

        clock.advance()
        await waitUntil { engine.appendedImages.count == 3 && clock.pendingCount == 1 }
        clock.advance()
        await waitUntil { engine.appendedImages.count == 4 && presentation.previews.count == 2 }

        XCTAssertEqual(session.state, .capturing)
        XCTAssertTrue(session.isSamplingArmed)
        XCTAssertTrue(presentation.warningEvents.isEmpty)
        _ = session.cancel()
    }

    func testLowConfidenceWarnsWithoutStoppingAndAcceptedAppendClearsWarning() async throws {
        let engine = FakeStitcher(results: [
            .acceptedInitial,
            .lowConfidenceDiscarded,
            .lowConfidenceDiscarded,
            .lowConfidenceDiscarded,
            .acceptedAppend,
        ])
        let presentation = PresentationRecorder()
        let session = makeSession(engine: engine, presentation: presentation)
        try await session.start()
        session.recordScrollActivity()

        await session.test_runSamplingTick()
        XCTAssertEqual(session.state, .capturing)
        XCTAssertTrue(session.isSamplingArmed)
        XCTAssertEqual(presentation.warnings, [.lowConfidence])
        XCTAssertEqual(presentation.previews.count, 1)

        await session.test_runSamplingTick()
        await session.test_runSamplingTick()
        XCTAssertEqual(session.state, .capturing)
        XCTAssertTrue(session.isSamplingArmed)
        XCTAssertEqual(presentation.warnings, [.lowConfidence])

        await session.test_runSamplingTick()

        XCTAssertEqual(session.state, .capturing)
        XCTAssertTrue(session.isSamplingArmed)
        XCTAssertEqual(presentation.warningEvents.count, 2)
        XCTAssertNil(presentation.warningEvents.last!)
        XCTAssertEqual(presentation.previews.count, 2)
    }

    func testAwaitingEvidenceClearsLowConfidenceWarningOnceAndKeepsSamplingArmed() async throws {
        let engine = FakeStitcher(results: [
            .acceptedInitial,
            .lowConfidenceDiscarded,
            .awaitingEvidence,
            .awaitingEvidence,
        ])
        let presentation = PresentationRecorder()
        let session = makeSession(engine: engine, presentation: presentation)
        try await session.start()
        session.recordScrollActivity()

        await session.test_runSamplingTick()
        XCTAssertEqual(presentation.warnings, [.lowConfidence])

        await session.test_runSamplingTick()
        XCTAssertEqual(session.state, .capturing)
        XCTAssertTrue(session.isSamplingArmed)
        XCTAssertEqual(presentation.warningEvents.count, 2)
        XCTAssertNil(presentation.warningEvents.last!)
        XCTAssertEqual(presentation.previews.count, 1)

        await session.test_runSamplingTick()
        XCTAssertEqual(session.state, .capturing)
        XCTAssertTrue(session.isSamplingArmed)
        XCTAssertEqual(presentation.warningEvents.count, 2)
        XCTAssertEqual(presentation.previews.count, 1)
    }

    func testInitialAcceptedPreviewRemainsVisibleWhenFirstLiveAppendHitsResourceLimit() async throws {
        let accepted = TestImageFactory.solid(size: CGSize(width: 80, height: 60), color: .red)
        let engine = FakeStitcher(results: [.acceptedInitial, .resourceLimit], final: accepted)
        let presentation = PresentationRecorder()
        let session = makeSession(engine: engine, presentation: presentation)

        try await session.start()
        XCTAssertEqual(presentation.previews.count, 1)
        XCTAssertTrue(try XCTUnwrap(presentation.previews.first) === accepted)

        session.recordScrollActivity()
        await session.test_runSamplingTick()

        XCTAssertEqual(session.state, .paused(.resourceLimit))
        XCTAssertEqual(presentation.previews.count, 1)
        XCTAssertTrue(try XCTUnwrap(presentation.previews.first) === accepted)
        XCTAssertEqual(engine.previewCallCount, 1)
    }

    func testReentrantTicksNeverOverlapCaptureOrAppend() async throws {
        let capturer = BlockingCapturer()
        let engine = FakeStitcher(results: [.acceptedInitial, .acceptedAppend])
        let session = makeSession(capturer: capturer, engine: engine)
        try await session.start()
        session.recordScrollActivity()

        let first = Task { await session.test_runSamplingTick() }
        await capturer.waitUntilCaptureStarts()
        await session.test_runSamplingTick()
        capturer.resumeCapture()
        await first.value

        XCTAssertEqual(capturer.maximumConcurrent, 1)
        XCTAssertEqual(capturer.captureCount, 1)
        XCTAssertEqual(engine.maximumConcurrent, 1)
    }

    func testLiveStitchingDoesNotBlockMainActor() async throws {
        let engine = SlowLiveStitcher(delay: 0.25)
        let session = makeSession(engine: engine)
        try await session.start()
        session.recordScrollActivity()

        let tick = Task { await session.test_runSamplingTick() }
        let startedAt = ProcessInfo.processInfo.systemUptime
        await Task.yield()
        let heartbeatDelay = ProcessInfo.processInfo.systemUptime - startedAt
        await tick.value

        XCTAssertLessThan(heartbeatDelay, 0.10)
    }

    func testFinishFromPausedStopsMonitorAndReturnsFinalImage() async throws {
        let final = TestImageFactory.solid(size: CGSize(width: 10, height: 30), color: .blue)
        let engine = FakeStitcher(results: [.acceptedInitial, .resourceLimit], final: final)
        let monitor = FakeActivityMonitor()
        let presentation = PresentationRecorder()
        let session = makeSession(engine: engine, monitor: monitor, presentation: presentation)
        try await session.start()
        session.recordScrollActivity()
        await session.test_runSamplingTick()

        let result = try await session.finish()

        XCTAssertTrue(result === final)
        XCTAssertEqual(session.state, .finished)
        XCTAssertFalse(session.isSamplingArmed)
        XCTAssertEqual(monitor.stopCount, 1)
        XCTAssertEqual(presentation.states.suffix(2), [.finishing, .finished])
    }

    func testFinishFailureKeepsStitcherAndCanRetrySameSession() async throws {
        let final = TestImageFactory.solid(size: CGSize(width: 10, height: 30), color: .blue)
        let engine = FakeStitcher(results: [.acceptedInitial], final: final, finalErrors: [TestError.failed])
        let presentation = PresentationRecorder()
        let session = makeSession(engine: engine, presentation: presentation)
        try await session.start()

        await XCTAssertThrowsErrorAsync { _ = try await session.finish() }
        XCTAssertEqual(session.state, .paused(.captureFailure))

        let result = try await session.finish()
        XCTAssertTrue(result === final)
        XCTAssertEqual(engine.finalImageCallCount, 2)
        XCTAssertEqual(session.state, .finished)
    }

    func testFinishFailureRestartsTerminalMonitorAndReturnCanRetrySameSession() async throws {
        let final = TestImageFactory.solid(size: CGSize(width: 10, height: 30), color: .blue)
        let engine = FakeStitcher(results: [.acceptedInitial], final: final, finalErrors: [TestError.failed])
        let monitor = FakeActivityMonitor()
        let presentation = PresentationRecorder()
        let session = makeSession(engine: engine, monitor: monitor, presentation: presentation)
        try await session.start()

        await XCTAssertThrowsErrorAsync { _ = try await session.finish() }

        XCTAssertEqual(session.state, .paused(.captureFailure))
        XCTAssertFalse(session.isSamplingArmed)
        XCTAssertEqual(monitor.stopCount, 1)
        XCTAssertEqual(monitor.startCount, 2)

        monitor.send(.finish)
        XCTAssertEqual(presentation.commands, [.finish])
        let result = try await session.finish()

        XCTAssertTrue(result === final)
        XCTAssertEqual(engine.finalImageCallCount, 2)
        XCTAssertEqual(monitor.stopCount, 2)
        XCTAssertEqual(session.state, .finished)
    }

    func testFinishFailureRestartsTerminalMonitorAndEscapeCanCancelWithoutSamplingLeak() async throws {
        let engine = FakeStitcher(results: [.acceptedInitial], finalErrors: [TestError.failed])
        let monitor = FakeActivityMonitor()
        let presentation = PresentationRecorder()
        let session = makeSession(engine: engine, monitor: monitor, presentation: presentation)
        try await session.start()

        await XCTAssertThrowsErrorAsync { _ = try await session.finish() }
        monitor.send(.cancel)
        XCTAssertEqual(presentation.commands, [.cancel])

        _ = session.cancel()
        session.recordScrollActivity()
        await session.test_runSamplingTick()

        XCTAssertEqual(session.state, .cancelled)
        XCTAssertFalse(session.isSamplingArmed)
        XCTAssertEqual(engine.appendedImages.count, 1)
        XCTAssertEqual(monitor.startCount, 2)
        XCTAssertEqual(monitor.stopCount, 2)
    }

    func testCancelReturnsImmutableSeedAndPreventsLaterTick() async throws {
        let engine = FakeStitcher(results: [.acceptedInitial, .acceptedAppend])
        let monitor = FakeActivityMonitor()
        let session = makeSession(engine: engine, monitor: monitor)
        try await session.start()
        session.recordScrollActivity()

        let seed = session.cancel()
        await session.test_runSamplingTick()

        XCTAssertTrue(seed.frozenImage === session.seed.frozenImage)
        XCTAssertEqual(session.state, .cancelled)
        XCTAssertEqual(engine.appendedImages.count, 1)
        XCTAssertEqual(monitor.stopCount, 1)
    }

    func testCaptureErrorPausesWithoutConcurrentResidueAndFinishInvalidStateIsDeterministic() async throws {
        let capturer = FakeCapturer(error: TestError.failed)
        let engine = FakeStitcher(results: [.acceptedInitial])
        let session = makeSession(capturer: capturer, engine: engine)

        await XCTAssertThrowsErrorAsync { _ = try await session.finish() }
        try await session.start()
        session.recordScrollActivity()
        await session.test_runSamplingTick()

        XCTAssertEqual(session.state, .paused(.captureFailure))
        XCTAssertFalse(session.isSamplingArmed)
        XCTAssertEqual(capturer.maximumConcurrent, 1)
        XCTAssertEqual(engine.appendedImages.count, 1)
    }

    func testEngineAppendErrorPausesAndLeavesNoTickResidue() async throws {
        let engine = FakeStitcher(results: [.acceptedInitial])
        let session = makeSession(engine: engine)
        try await session.start()
        session.recordScrollActivity()

        await session.test_runSamplingTick()
        await session.test_runSamplingTick()

        XCTAssertEqual(session.state, .paused(.captureFailure))
        XCTAssertFalse(session.isSamplingArmed)
        XCTAssertEqual(engine.appendedImages.count, 2)
        XCTAssertEqual(engine.concurrent, 0)
    }

    func testRealSamplingLoopStopsAfterStableFramesAndRearmsOnNextActivity() async throws {
        let clock = ControlledClock()
        let capturer = FakeCapturer()
        let engine = FakeStitcher(results: [
            .acceptedInitial,
            .duplicateDiscarded,
            .duplicateDiscarded,
            .duplicateDiscarded,
            .acceptedAppend,
        ])
        let session = makeSession(capturer: capturer, engine: engine, clock: clock)
        try await session.start()

        session.recordScrollActivity()
        await waitUntil { clock.pendingCount == 1 }
        for expectedCount in 2...4 {
            clock.advance()
            await waitUntil {
                engine.appendedImages.count == expectedCount
                    && (expectedCount == 4 || clock.pendingCount == 1)
            }
        }

        await waitUntil { !session.isSamplingArmed && clock.pendingCount == 0 }
        XCTAssertEqual(capturer.captureCount, 3)

        session.recordScrollActivity()
        await waitUntil { session.isSamplingArmed && clock.pendingCount == 1 }
        clock.advance()
        await waitUntil { engine.appendedImages.count == 5 && clock.pendingCount == 1 }

        XCTAssertEqual(capturer.captureCount, 4)
        XCTAssertEqual(capturer.maximumConcurrent, 1)
        XCTAssertEqual(engine.maximumConcurrent, 1)
        _ = session.cancel()
        await waitUntil { clock.pendingCount == 0 }
    }

    func testRepeatedActivityDoesNotCreateSecondSamplingLoop() async throws {
        let clock = ControlledClock()
        let capturer = BlockingCapturer()
        let engine = FakeStitcher(results: [.acceptedInitial, .acceptedAppend])
        let session = makeSession(capturer: capturer, engine: engine, clock: clock)
        try await session.start()

        session.recordScrollActivity()
        await waitUntil { clock.pendingCount == 1 }
        session.recordScrollActivity()
        XCTAssertEqual(clock.pendingCount, 1)
        clock.advance()
        await capturer.waitUntilCaptureStarts()
        session.recordScrollActivity()
        XCTAssertEqual(clock.pendingCount, 0)
        capturer.resumeCapture()
        await waitUntil { engine.appendedImages.count == 2 && clock.pendingCount == 1 }

        XCTAssertEqual(capturer.maximumConcurrent, 1)
        _ = session.cancel()
    }

    func testCancelWhileSamplerSleepsCancelsClockAndNeverCaptures() async throws {
        let clock = ControlledClock()
        let capturer = FakeCapturer()
        let engine = FakeStitcher(results: [.acceptedInitial, .acceptedAppend])
        let session = makeSession(capturer: capturer, engine: engine, clock: clock)
        try await session.start()
        session.recordScrollActivity()
        await waitUntil { clock.pendingCount == 1 }

        _ = session.cancel()

        await waitUntil { clock.pendingCount == 0 }
        XCTAssertEqual(capturer.captureCount, 0)
        XCTAssertEqual(session.state, .cancelled)
    }

    func testLateCaptureReturnAfterCancelIsInertAndDoesNotPublish() async throws {
        let capturer = BlockingCapturer()
        let engine = FakeStitcher(results: [.acceptedInitial, .acceptedAppend])
        let presentation = PresentationRecorder()
        let session = makeSession(capturer: capturer, engine: engine, presentation: presentation)
        try await session.start()
        session.recordScrollActivity()
        let tick = Task { await session.test_runSamplingTick() }
        await capturer.waitUntilCaptureStarts()

        _ = session.cancel()
        let eventCountAtCancel = presentation.eventCount
        capturer.resumeCapture()
        await tick.value

        XCTAssertEqual(session.state, .cancelled)
        XCTAssertEqual(engine.appendedImages.count, 1)
        XCTAssertEqual(presentation.eventCount, eventCountAtCancel)
    }

    func testLateCaptureErrorAfterFinishCannotOverwriteFinishedState() async throws {
        let capturer = BlockingCapturer()
        let engine = FakeStitcher(results: [.acceptedInitial, .acceptedAppend])
        let presentation = PresentationRecorder()
        let session = makeSession(capturer: capturer, engine: engine, presentation: presentation)
        try await session.start()
        session.recordScrollActivity()
        let tick = Task { await session.test_runSamplingTick() }
        await capturer.waitUntilCaptureStarts()

        _ = try await session.finish()
        let eventCountAtFinish = presentation.eventCount
        capturer.failCapture()
        await tick.value

        XCTAssertEqual(session.state, .finished)
        XCTAssertEqual(engine.appendedImages.count, 1)
        XCTAssertEqual(presentation.eventCount, eventCountAtFinish)
    }

    func testCancelReleasesOwnedStitcherAndReturnsSeed() async throws {
        var didDeinitialize = false
        var engine: FakeStitcher? = FakeStitcher(
            results: [.acceptedInitial],
            onDeinit: { didDeinitialize = true }
        )
        let weakEngine = WeakBox(engine)
        let session = makeSession(engine: try XCTUnwrap(engine))
        try await session.start()
        engine = nil

        let seed = session.cancel()

        XCTAssertNil(weakEngine.value)
        XCTAssertTrue(didDeinitialize)
        XCTAssertTrue(seed.frozenImage === session.seed.frozenImage)
    }

    func testLowConfidenceFramesKeepTheSameSamplingLoopAlive() async throws {
        let clock = ControlledClock()
        let capturer = FakeCapturer()
        let engine = FakeStitcher(results: [
            .acceptedInitial,
            .lowConfidenceDiscarded,
            .lowConfidenceDiscarded,
            .lowConfidenceDiscarded,
            .acceptedAppend,
        ])
        let session = makeSession(capturer: capturer, engine: engine, clock: clock)
        try await session.start()
        session.recordScrollActivity()
        await waitUntil { clock.pendingCount == 1 }

        for expectedCount in 2...4 {
            clock.advance()
            await waitUntil {
                engine.appendedImages.count == expectedCount
                    && (expectedCount == 4 || clock.pendingCount == 1)
            }
        }
        await waitUntil { session.isSamplingArmed && clock.pendingCount == 1 }
        XCTAssertEqual(session.state, .capturing)

        clock.advance()
        await waitUntil { engine.appendedImages.count == 5 && clock.pendingCount == 1 }
        XCTAssertEqual(clock.pendingCount, 1)
        XCTAssertEqual(capturer.captureCount, 4)
        XCTAssertEqual(capturer.maximumConcurrent, 1)
        _ = session.cancel()
    }

    func testStartAppendPresentationCanCancelWithoutStartingMonitorOrRevivingState() async throws {
        let engine = FakeStitcher(results: [.acceptedInitial])
        let monitor = FakeActivityMonitor()
        weak var weakSession: ScrollCaptureSession?
        let session = makeSession(
            engine: engine,
            monitor: monitor,
            presentationHandler: { update in
                if update.isAppend(.acceptedInitial) { _ = weakSession?.cancel() }
            }
        )
        weakSession = session

        try await session.start()

        XCTAssertEqual(session.state, .cancelled)
        XCTAssertEqual(monitor.startCount, 0)
    }

    func testTickAppendPresentationCanCancelWithoutPreviewOrHandlingResult() async throws {
        let engine = FakeStitcher(results: [.acceptedInitial, .acceptedAppend])
        let recorder = PresentationRecorder()
        weak var weakSession: ScrollCaptureSession?
        let session = makeSession(
            engine: engine,
            presentation: recorder,
            presentationHandler: { update in
                if update.isAppend(.acceptedAppend) { _ = weakSession?.cancel() }
            }
        )
        weakSession = session
        try await session.start()
        session.recordScrollActivity()

        await session.test_runSamplingTick()

        XCTAssertEqual(session.state, .cancelled)
        XCTAssertEqual(recorder.previews.count, 1)
        XCTAssertEqual(engine.previewCallCount, 1)
    }

    func testFinishingPresentationCanCancelWithoutCallingFinalOrRevivingState() async throws {
        let engine = FakeStitcher(results: [.acceptedInitial])
        weak var weakSession: ScrollCaptureSession?
        let session = makeSession(
            engine: engine,
            presentationHandler: { update in
                if update.isState(.finishing) { _ = weakSession?.cancel() }
            }
        )
        weakSession = session
        try await session.start()

        await XCTAssertThrowsErrorAsync { _ = try await session.finish() }

        XCTAssertEqual(session.state, .cancelled)
        XCTAssertEqual(engine.finalImageCallCount, 0)
    }

    func testScreenCaptureServiceConformsToScrollRegionCapturing() {
        let service: any ScrollRegionCapturing = ScreenCaptureService()
        XCTAssertTrue(service is ScreenCaptureService)
    }

    func testActivityMonitorRegistrationIsIdempotentReturnsLocalEventAndStopsAllMonitors() async throws {
        let registrar = FakeMonitorRegistrar()
        let monitor = ScrollActivityMonitor(registrar: registrar)
        var activityCount = 0
        monitor.start { activityCount += 1 }
        monitor.start { activityCount += 100 }
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ))

        XCTAssertTrue(registrar.localHandler?(event) === event)
        registrar.globalHandler?(event)
        await Task.yield()
        XCTAssertEqual(activityCount, 2)
        XCTAssertEqual(registrar.addLocalCount, 1)
        XCTAssertEqual(registrar.addGlobalCount, 1)
        XCTAssertEqual(registrar.addGlobalKeyCount, 1)

        monitor.stop()
        monitor.stop()
        XCTAssertEqual(registrar.removed.count, 3)
    }

    func testActivityMonitorMapsWheelDeltaToDocumentDirection() {
        XCTAssertEqual(ScrollActivityMonitor.direction(forScrollingDeltaY: -1), .up)
        XCTAssertEqual(ScrollActivityMonitor.direction(forScrollingDeltaY: 1), .down)
        XCTAssertEqual(ScrollActivityMonitor.direction(forScrollingDeltaY: 0), .unknown)
        XCTAssertEqual(
            ScrollActivityMonitor.direction(
                forScrollingDeltaY: -1,
                isDirectionInvertedFromDevice: false
            ),
            .down
        )
    }

    func testActivityMonitorPreservesWheelDistanceWithDocumentDirection() {
        XCTAssertEqual(
            ScrollActivityMonitor.activity(forScrollingDeltaY: 12),
            ScrollCaptureScrollActivity(direction: .down, distance: 12, viewportDirection: .up)
        )
        XCTAssertEqual(
            ScrollActivityMonitor.activity(forScrollingDeltaY: -7),
            ScrollCaptureScrollActivity(direction: .up, distance: 7, viewportDirection: .down)
        )
        let naturalScroll = ScrollActivityMonitor.activity(forScrollingDeltaY: 12)
        XCTAssertEqual(naturalScroll.direction, .down)
        XCTAssertEqual(naturalScroll.viewportDirection, .up)
        XCTAssertEqual(
            ScrollActivityMonitor.activity(
                forScrollingDeltaY: 1,
                isPreciseScrollingDelta: false
            ),
            ScrollCaptureScrollActivity(direction: .down, distance: 24, viewportDirection: .up)
        )
    }

    func testDuplicateAndReviewFramesClearStaleLowConfidenceWarning() async throws {
        for recoveryKind in [ScrollCaptureAppendKind.duplicateDiscarded, .reviewDiscarded] {
            let engine = FakeStitcher(results: [.acceptedInitial, .lowConfidenceDiscarded, recoveryKind])
            let presentation = PresentationRecorder()
            let session = makeSession(engine: engine, presentation: presentation)
            try await session.start()
            session.recordScrollActivity()

            await session.test_runSamplingTick()
            await session.test_runSamplingTick()

            XCTAssertEqual(presentation.warningEvents.count, 2)
            XCTAssertNil(presentation.warningEvents.last!)
            _ = session.cancel()
        }
    }

    func testSessionPublishesViewportMovementImmediatelyOnScrollActivity() async throws {
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: FakeStitcher(results: [.acceptedInitial]),
            presentation: presentation
        )
        try await session.start()

        let activity = ScrollCaptureScrollActivity(direction: .down, distance: 18)
        session.recordScrollActivity(activity)

        XCTAssertEqual(presentation.scrollActivities, [activity])
    }

    func testActivityMonitorForwardsTerminalKeysFromOtherApplicationsAndStopsKeyMonitor() async throws {
        let registrar = FakeMonitorRegistrar()
        let monitor = ScrollActivityMonitor(registrar: registrar)
        var commands: [ScrollCaptureTerminalCommand] = []
        monitor.start(
            onScrollActivity: {},
            onTerminalCommand: { commands.append($0) }
        )

        registrar.globalKeyHandler?(try makeKeyEvent(keyCode: 36))
        registrar.globalKeyHandler?(try makeKeyEvent(keyCode: 76))
        registrar.globalKeyHandler?(try makeKeyEvent(keyCode: 53))
        registrar.globalKeyHandler?(try makeKeyEvent(keyCode: 0))
        await Task.yield()

        XCTAssertEqual(commands, [.finish, .finish, .cancel])
        XCTAssertEqual(registrar.addGlobalKeyCount, 1)

        monitor.stop()
        XCTAssertEqual(registrar.removed.count, 3)
    }

    func testActivityMonitorStillStopsScrollMonitorsWhenGlobalKeyRegistrationIsUnavailable() async {
        let registrar = FakeMonitorRegistrar()
        registrar.providesGlobalKeyToken = false
        let monitor = ScrollActivityMonitor(registrar: registrar)

        monitor.start(onScrollActivity: {}, onTerminalCommand: { _ in })
        monitor.stop()

        XCTAssertEqual(registrar.addGlobalKeyCount, 1)
        XCTAssertEqual(registrar.removed.count, 2)
        await Task.yield()
    }

    func testActivityMonitorUsesAccessibilityTrustForWarningButStillAttemptsGlobalKeyRegistration() async {
        let registrar = FakeMonitorRegistrar()
        var messages: [String] = []
        let monitor = ScrollActivityMonitor(
            registrar: registrar,
            isAccessibilityTrusted: { false },
            log: { messages.append($0) }
        )

        monitor.start(onScrollActivity: {}, onTerminalCommand: { _ in })

        XCTAssertEqual(registrar.addGlobalKeyCount, 1)
        XCTAssertEqual(messages, ["xxsnap global scroll-capture keys require Accessibility permission; toolbar controls remain available"])
        monitor.stop()
        await Task.yield()
    }

    func testSessionPublishesTerminalCommandsOnlyWhileCaptureCanTerminate() async throws {
        let monitor = FakeActivityMonitor()
        let presentation = PresentationRecorder()
        let session = makeSession(
            engine: FakeStitcher(results: [.acceptedInitial]),
            monitor: monitor,
            presentation: presentation
        )
        try await session.start()

        monitor.send(.finish)
        XCTAssertEqual(presentation.commands, [.finish])

        _ = session.cancel()
        monitor.send(.cancel)
        XCTAssertEqual(presentation.commands, [.finish])
    }

    private func makeKeyEvent(keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func makeSession(
        capturer: (any ScrollRegionCapturing)? = nil,
        engine: any ScrollStitching,
        clock: (any ScrollCaptureClock)? = nil,
        monitor: (any ScrollActivityMonitoring)? = nil,
        stepController: (any ScrollCaptureStepControlling)? = nil,
        presentation: PresentationRecorder? = nil,
        presentationHandler: (@MainActor (ScrollCapturePresentationUpdate) -> Void)? = nil,
        diagnosticLogger: any DiagnosticLogging = RecordingDiagnosticLogger(),
        screenRect: NSRect = NSRect(x: 100, y: 200, width: 80, height: 60)
    ) -> ScrollCaptureSession {
        let presentation = presentation ?? PresentationRecorder()
        return ScrollCaptureSession(
            seed: ScrollCaptureSeed(
                screenRect: screenRect,
                snapshotRect: NSRect(x: 0, y: 0, width: 80, height: 60),
                frozenImage: TestImageFactory.solid(size: CGSize(width: 80, height: 60), color: .red),
                annotations: [],
                eraserMasks: []
            ),
            capturer: capturer ?? FakeCapturer(),
            stitcher: engine,
            clock: clock ?? FakeClock(),
            activityMonitor: monitor ?? FakeActivityMonitor(),
            stepController: stepController,
            diagnosticLogger: diagnosticLogger,
            presentation: {
                presentation.record($0)
                presentationHandler?($0)
            }
        )
    }
}

private enum TestError: Error { case failed }

private final class RecordingDiagnosticLogger: DiagnosticLogging {
    struct Event {
        let event: String
        let metadata: [String: String]
        let detail: DiagnosticLogDetail
    }

    private(set) var beginSessionCount = 0
    private(set) var endSessionCount = 0
    private(set) var events: [Event] = []

    func record(
        category: DiagnosticLogCategory,
        level: DiagnosticLogLevel,
        event: String,
        metadata: [String: String],
        detail: DiagnosticLogDetail
    ) {
        events.append(Event(event: event, metadata: metadata, detail: detail))
    }

    func beginScrollCaptureSession() -> DiagnosticCaptureSession {
        beginSessionCount += 1
        return DiagnosticCaptureSession(id: UUID(), startedAt: Date(), isDetailed: true)
    }

    func endScrollCaptureSession(_ session: DiagnosticCaptureSession) {
        endSessionCount += 1
    }
}

@MainActor
private final class FakeStepController: ScrollCaptureStepControlling {
    struct Step {
        let direction: ScrollCaptureDirection
        let distance: CGFloat
        let point: NSPoint
    }
    struct KeyboardStep {
        let direction: ScrollCaptureDirection
        let distance: CGFloat
    }
    struct BoundaryCheck {
        let direction: ScrollCaptureDirection
        let point: NSPoint
    }
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var steps: [Step] = []
    private(set) var targetedSteps: [Step] = []
    private(set) var scrollbarSteps: [Step] = []
    private(set) var keyboardSteps: [KeyboardStep] = []
    private(set) var boundaryChecks: [BoundaryCheck] = []

    private let onStep: () -> Void
    private let targetedResult: Bool
    private let scrollbarResult: Bool
    private let keyboardResult: Bool
    private let boundaryStateResolver: (ScrollCaptureDirection, NSPoint) -> ScrollCaptureBoundaryState

    init(
        targetedResult: Bool = false,
        scrollbarResult: Bool = false,
        keyboardResult: Bool = false,
        boundaryState: ScrollCaptureBoundaryState = .unavailable,
        onStep: @escaping () -> Void = {}
    ) {
        self.targetedResult = targetedResult
        self.scrollbarResult = scrollbarResult
        self.keyboardResult = keyboardResult
        self.boundaryStateResolver = { _, _ in boundaryState }
        self.onStep = onStep
    }

    init(
        boundaryStateResolver: @escaping (
            ScrollCaptureDirection,
            NSPoint
        ) -> ScrollCaptureBoundaryState
    ) {
        self.targetedResult = false
        self.scrollbarResult = false
        self.keyboardResult = false
        self.boundaryStateResolver = boundaryStateResolver
        self.onStep = {}
    }

    func startBlockingPhysicalScroll() throws { startCount += 1 }
    func boundaryState(
        direction: ScrollCaptureDirection,
        at point: NSPoint
    ) -> ScrollCaptureBoundaryState {
        boundaryChecks.append(BoundaryCheck(direction: direction, point: point))
        return boundaryStateResolver(direction, point)
    }
    func performStep(direction: ScrollCaptureDirection, distance: CGFloat, at point: NSPoint) async throws {
        steps.append(Step(direction: direction, distance: distance, point: point))
        onStep()
    }
    func performTargetedStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat,
        at point: NSPoint
    ) async throws -> Bool {
        targetedSteps.append(Step(direction: direction, distance: distance, point: point))
        return targetedResult
    }
    func performScrollbarStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat,
        in viewport: NSRect,
        capturedImage: NSImage
    ) async throws -> Bool {
        scrollbarSteps.append(Step(
            direction: direction,
            distance: distance,
            point: NSPoint(x: viewport.maxX, y: viewport.midY)
        ))
        return scrollbarResult
    }
    func performKeyboardStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat
    ) async throws -> Bool {
        keyboardSteps.append(KeyboardStep(direction: direction, distance: distance))
        return keyboardResult
    }
    func stop() { stopCount += 1 }
}

@MainActor
private final class BufferingFakeCapturer: ScrollRegionCapturing, ScrollRegionCaptureBuffering {
    private let onDiscard: () -> Void
    private let onCapture: () -> Void

    init(onDiscard: @escaping () -> Void, onCapture: @escaping () -> Void) {
        self.onDiscard = onDiscard
        self.onCapture = onCapture
    }

    func captureImage(in selectionRect: NSRect) async throws -> NSImage {
        onCapture()
        return TestImageFactory.solid(size: selectionRect.size, color: .green)
    }

    func discardBufferedFrames() {
        onDiscard()
    }
}

@MainActor
private final class PrimingFakeCapturer: ScrollRegionCapturing, ScrollRegionCapturePriming {
    private(set) var primeCount = 0
    private(set) var captureCount = 0

    func primeCapture(in selectionRect: NSRect) async throws {
        primeCount += 1
    }

    func captureImage(in selectionRect: NSRect) async throws -> NSImage {
        captureCount += 1
        return TestImageFactory.solid(size: selectionRect.size, color: .green)
    }
}

@MainActor
private final class PrimingBufferingFakeCapturer:
    ScrollRegionCapturing,
    ScrollRegionCapturePriming,
    ScrollRegionCaptureBuffering
{
    private(set) var operations: [String] = []
    private(set) var discardCount = 0
    private(set) var captureCount = 0

    func primeCapture(in selectionRect: NSRect) async throws {
        operations.append("prime")
    }

    func captureImage(in selectionRect: NSRect) async throws -> NSImage {
        captureCount += 1
        operations.append("capture")
        return TestImageFactory.solid(size: selectionRect.size, color: .green)
    }

    func discardBufferedFrames() {
        discardCount += 1
        operations.append("discard")
    }
}

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?
    init(_ value: Value?) { self.value = value }
}

@MainActor
private final class FakeCapturer: ScrollRegionCapturing {
    var images = [TestImageFactory.solid(size: CGSize(width: 80, height: 60), color: .green)]
    let error: Error?
    private(set) var captureCount = 0
    private(set) var concurrent = 0
    private(set) var maximumConcurrent = 0

    init(error: Error? = nil) { self.error = error }

    func captureImage(in selectionRect: NSRect) async throws -> NSImage {
        captureCount += 1
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        defer { concurrent -= 1 }
        if let error { throw error }
        return images[min(captureCount - 1, images.count - 1)]
    }
}

@MainActor
private final class BlockingCapturer: ScrollRegionCapturing {
    private var started: CheckedContinuation<Void, Never>?
    private var resume: CheckedContinuation<NSImage, Error>?
    private(set) var captureCount = 0
    private(set) var concurrent = 0
    private(set) var maximumConcurrent = 0

    func captureImage(in selectionRect: NSRect) async throws -> NSImage {
        captureCount += 1
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        started?.resume()
        started = nil
        defer { concurrent -= 1 }
        return try await withCheckedThrowingContinuation { resume = $0 }
    }

    func waitUntilCaptureStarts() async {
        if captureCount > 0 { return }
        await withCheckedContinuation { started = $0 }
    }

    func resumeCapture() {
        resume?.resume(returning: TestImageFactory.solid(size: CGSize(width: 80, height: 60), color: .green))
        resume = nil
    }

    func failCapture() {
        resume?.resume(throwing: TestError.failed)
        resume = nil
    }
}

@MainActor
private final class FakeStitcher: ScrollStitching {
    private var results: [ScrollCaptureAppendKind]
    private var directions: [ScrollCaptureDirection]
    let final: NSImage
    private let onDeinit: (() -> Void)?
    private(set) var appendedImages: [NSImage] = []
    private(set) var preferredDirections: [ScrollCaptureDirection] = []
    private(set) var expectedAdvances: [CGFloat] = []
    private(set) var concurrent = 0
    private(set) var maximumConcurrent = 0
    private(set) var previewCallCount = 0
    private(set) var previewHeights: [Int] = []
    private(set) var previewWidths: [Int] = []
    private(set) var finalImageCallCount = 0
    private var finalErrors: [Error]

    init(
        results: [ScrollCaptureAppendKind],
        directions: [ScrollCaptureDirection] = [],
        final: NSImage? = nil,
        finalErrors: [Error] = [],
        onDeinit: (() -> Void)? = nil
    ) {
        self.results = results
        self.directions = directions
        self.final = final ?? TestImageFactory.solid(size: CGSize(width: 80, height: 120), color: .purple)
        self.finalErrors = finalErrors
        self.onDeinit = onDeinit
    }

    func append(_ image: NSImage) async throws -> ScrollCaptureAppendUpdate {
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        defer { concurrent -= 1 }
        appendedImages.append(image)
        guard !results.isEmpty else { throw TestError.failed }
        let kind = results.removeFirst()
        let direction = directions.isEmpty
            ? (kind == .acceptedAppend ? .down : .unknown)
            : directions.removeFirst()
        return .testValue(kind: kind, direction: direction)
    }

    func append(
        _ image: NSImage,
        preferredDirection: ScrollCaptureDirection
    ) async throws -> ScrollCaptureAppendUpdate {
        preferredDirections.append(preferredDirection)
        return try await append(image)
    }

    func append(
        _ image: NSImage,
        preferredDirection: ScrollCaptureDirection,
        expectedAdvance: CGFloat
    ) async throws -> ScrollCaptureAppendUpdate {
        expectedAdvances.append(expectedAdvance)
        return try await append(image, preferredDirection: preferredDirection)
    }

    func preview(maximumHeight: Int) async throws -> NSImage {
        previewCallCount += 1
        previewHeights.append(maximumHeight)
        return final
    }

    func preview(maximumWidth: Int) async throws -> NSImage {
        previewCallCount += 1
        previewWidths.append(maximumWidth)
        return final
    }

    func finalImage() async throws -> NSImage {
        finalImageCallCount += 1
        if !finalErrors.isEmpty { throw finalErrors.removeFirst() }
        return final
    }

    deinit { onDeinit?() }
}

@MainActor
private final class SlowLiveStitcher: ScrollStitching {
    private let delay: TimeInterval
    private var appendCount = 0

    init(delay: TimeInterval) { self.delay = delay }

    func append(_ image: NSImage) async throws -> ScrollCaptureAppendUpdate {
        appendCount += 1
        if appendCount > 1 { try await Task.sleep(for: .seconds(delay)) }
        return .testValue(
            kind: appendCount == 1 ? .acceptedInitial : .duplicateDiscarded,
            direction: .unknown
        )
    }

    func preview(maximumHeight: Int) async throws -> NSImage { image }
    func finalImage() async throws -> NSImage { image }

    private let image = TestImageFactory.solid(
        size: CGSize(width: 80, height: 60),
        color: .white
    )
}

@MainActor
private final class FakeClock: ScrollCaptureClock {
    func sleep(for duration: Duration) async throws { throw CancellationError() }
}

@MainActor
private final class ControlledClock: ScrollCaptureClock {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var waiters: [Waiter] = []
    var pendingCount: Int { waiters.count }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id: id) }
        }
    }

    func advance() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().continuation.resume()
    }

    private func cancel(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

private final class FakeMonitorRegistrar: ScrollEventMonitorRegistering {
    let localToken = NSObject()
    let globalToken = NSObject()
    private(set) var addLocalCount = 0
    private(set) var addGlobalCount = 0
    private(set) var addGlobalKeyCount = 0
    private(set) var removed: [AnyObject] = []
    var localHandler: ((NSEvent) -> NSEvent?)?
    var globalHandler: ((NSEvent) -> Void)?
    var globalKeyHandler: ((NSEvent) -> Void)?
    var providesGlobalKeyToken = true

    func addLocal(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        addLocalCount += 1
        localHandler = handler
        return localToken
    }

    func addGlobal(_ handler: @escaping (NSEvent) -> Void) -> Any? {
        addGlobalCount += 1
        globalHandler = handler
        return globalToken
    }

    func addGlobalKeyDown(_ handler: @escaping (NSEvent) -> Void) -> Any? {
        addGlobalKeyCount += 1
        globalKeyHandler = handler
        return providesGlobalKeyToken ? NSObject() : nil
    }

    func remove(_ monitor: Any) { removed.append(monitor as AnyObject) }
}

@MainActor
private final class FakeActivityMonitor: ScrollActivityMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var scrollActivity: (@MainActor (ScrollCaptureScrollActivity) -> Void)?
    private var terminalCommand: (@MainActor (ScrollCaptureTerminalCommand) -> Void)?
    func start(_ callback: @escaping @MainActor () -> Void) { startCount += 1 }
    func start(
        onScrollActivity: @escaping @MainActor () -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    ) {
        startCount += 1
        terminalCommand = onTerminalCommand
    }
    func start(
        onScrollActivity: @escaping @MainActor (ScrollCaptureScrollActivity) -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    ) {
        startCount += 1
        scrollActivity = onScrollActivity
        terminalCommand = onTerminalCommand
    }
    func stop() { stopCount += 1 }
    func send(_ activity: ScrollCaptureScrollActivity) { scrollActivity?(activity) }
    func send(_ command: ScrollCaptureTerminalCommand) { terminalCommand?(command) }
}

@MainActor
private final class PresentationRecorder {
    private(set) var states: [ScrollCaptureSessionState] = []
    private(set) var kinds: [ScrollCaptureAppendKind] = []
    private(set) var previews: [NSImage] = []
    private(set) var previewEdges: [ScrollCapturePreviewEdge] = []
    private(set) var previewViewports: [ScrollCapturePreviewViewport] = []
    private(set) var scrollActivities: [ScrollCaptureScrollActivity] = []
    private(set) var commands: [ScrollCaptureTerminalCommand] = []
    private(set) var warningEvents: [ScrollCaptureMatchWarning?] = []
    private(set) var stepStates: [ScrollCaptureStepControlState] = []
    var warnings: [ScrollCaptureMatchWarning] { warningEvents.compactMap { $0 } }
    var eventCount: Int { states.count + kinds.count + previews.count + commands.count + warningEvents.count }
    func record(_ event: ScrollCapturePresentationUpdate) {
        switch event {
        case let .terminalCommand(command): commands.append(command)
        case let .state(state): states.append(state)
        case let .append(update): kinds.append(update.kind)
        case let .preview(image, edge, viewport):
            previews.append(image)
            previewEdges.append(edge)
            previewViewports.append(viewport)
        case let .viewportScroll(activity): scrollActivities.append(activity)
        case let .warning(warning): warningEvents.append(warning)
        case let .stepState(state): stepStates.append(state)
        }
    }
}

private extension ScrollCapturePresentationUpdate {
    func isState(_ expected: ScrollCaptureSessionState) -> Bool {
        if case let .state(state) = self { return state == expected }
        return false
    }

    func isAppend(_ expected: ScrollCaptureAppendKind) -> Bool {
        if case let .append(update) = self { return update.kind == expected }
        return false
    }
}

@MainActor
private func waitUntil(
    _ condition: () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<100 where !condition() { await Task.yield() }
    XCTAssertTrue(condition(), file: file, line: line)
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
