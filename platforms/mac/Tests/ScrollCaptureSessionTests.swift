import AppKit
import XCTest
@testable import xxsnap

@MainActor
final class ScrollCaptureSessionTests: XCTestCase {
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

    func testThreeConsecutiveDuplicatesDisarmAndNewActivityResetsStability() async throws {
        let engine = FakeStitcher(results: [.acceptedInitial, .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded, .duplicateDiscarded])
        let session = makeSession(engine: engine)
        try await session.start()
        session.recordScrollActivity()

        await session.test_runSamplingTick()
        session.recordScrollActivity() // direct activity resets stability; subsequent frames model inertial continuation
        await session.test_runSamplingTick()
        XCTAssertTrue(session.isSamplingArmed)
        await session.test_runSamplingTick()
        XCTAssertTrue(session.isSamplingArmed)
        await session.test_runSamplingTick()

        XCTAssertFalse(session.isSamplingArmed)
    }

    func testReviewDiscardedCountsTowardStableTailWithoutPublishingPreview() async throws {
        let engine = FakeStitcher(results: [.acceptedInitial, .reviewDiscarded, .reviewDiscarded, .reviewDiscarded])
        let presentation = PresentationRecorder()
        let session = makeSession(engine: engine, presentation: presentation)
        try await session.start()
        session.recordScrollActivity()

        await session.test_runSamplingTick()
        await session.test_runSamplingTick()
        await session.test_runSamplingTick()

        XCTAssertFalse(session.isSamplingArmed)
        XCTAssertEqual(presentation.previews.count, 1)
        XCTAssertEqual(presentation.kinds, [.acceptedInitial, .reviewDiscarded, .reviewDiscarded, .reviewDiscarded])
    }

    func testPauseKindsDisarmAndOnlyLowConfidenceCanRecoverAfterActivity() async throws {
        let lowEngine = FakeStitcher(results: [.acceptedInitial, .lowConfidenceDiscarded, .acceptedAppend])
        let lowSession = makeSession(engine: lowEngine)
        try await lowSession.start()
        lowSession.recordScrollActivity()
        await lowSession.test_runSamplingTick()
        XCTAssertEqual(lowSession.state, .paused(.lowConfidence))
        XCTAssertFalse(lowSession.isSamplingArmed)

        lowSession.recordScrollActivity()
        await lowSession.test_runSamplingTick()
        XCTAssertEqual(lowSession.state, .capturing)
        XCTAssertTrue(lowSession.isSamplingArmed)

        let limitEngine = FakeStitcher(results: [.acceptedInitial, .resourceLimit, .acceptedAppend])
        let limitSession = makeSession(engine: limitEngine)
        try await limitSession.start()
        limitSession.recordScrollActivity()
        await limitSession.test_runSamplingTick()
        XCTAssertEqual(limitSession.state, .paused(.resourceLimit))
        limitSession.recordScrollActivity()
        await limitSession.test_runSamplingTick()
        XCTAssertEqual(limitEngine.appendedImages.count, 2)
    }

    func testAwaitingEvidenceUsesTemporaryLowConfidencePause() async throws {
        let engine = FakeStitcher(results: [.acceptedInitial, .awaitingEvidence])
        let session = makeSession(engine: engine)
        try await session.start()
        session.recordScrollActivity()

        await session.test_runSamplingTick()

        XCTAssertEqual(session.state, .paused(.lowConfidence))
        XCTAssertFalse(session.isSamplingArmed)
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

    func testRealSamplingLoopContinuesInertiallyAndStopsAfterStableTail() async throws {
        let clock = ControlledClock()
        let capturer = FakeCapturer()
        let engine = FakeStitcher(results: [
            .acceptedInitial,
            .acceptedAppend,
            .duplicateDiscarded,
            .duplicateDiscarded,
            .duplicateDiscarded,
        ])
        let session = makeSession(capturer: capturer, engine: engine, clock: clock)
        try await session.start()

        session.recordScrollActivity()
        await waitUntil { clock.pendingCount == 1 }
        clock.advance()
        await waitUntil { engine.appendedImages.count == 2 && clock.pendingCount == 1 }

        // Direct activity resets stability while the same inertial loop remains active.
        session.recordScrollActivity()
        XCTAssertEqual(clock.pendingCount, 1)
        for expectedCount in 3...5 {
            clock.advance()
            await waitUntil {
                engine.appendedImages.count == expectedCount
                    && (expectedCount == 5 || clock.pendingCount == 1)
            }
        }

        await waitUntil { !session.isSamplingArmed && clock.pendingCount == 0 }
        XCTAssertEqual(capturer.captureCount, 4)
        XCTAssertEqual(capturer.maximumConcurrent, 1)
        XCTAssertEqual(engine.maximumConcurrent, 1)
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

    func testRearmedLowConfidenceLoopCannotBeClearedByRetiringLoop() async throws {
        let clock = ControlledClock()
        let capturer = FakeCapturer()
        let engine = FakeStitcher(results: [.acceptedInitial, .lowConfidenceDiscarded, .acceptedAppend])
        weak var weakSession: ScrollCaptureSession?
        let session = makeSession(
            capturer: capturer,
            engine: engine,
            clock: clock,
            presentationHandler: { update in
                if update.isState(.paused(.lowConfidence)) {
                    weakSession?.recordScrollActivity()
                }
            }
        )
        weakSession = session
        try await session.start()
        session.recordScrollActivity()
        await waitUntil { clock.pendingCount == 1 }

        clock.advance()
        await waitUntil { session.state == .paused(.lowConfidence) && clock.pendingCount == 1 }
        for _ in 0..<10 { await Task.yield() }
        session.recordScrollActivity()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(clock.pendingCount, 1)

        clock.advance()
        await waitUntil { engine.appendedImages.count == 3 }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(clock.pendingCount, 1)
        XCTAssertEqual(capturer.captureCount, 2)
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
        engine: FakeStitcher,
        clock: (any ScrollCaptureClock)? = nil,
        monitor: (any ScrollActivityMonitoring)? = nil,
        presentation: PresentationRecorder? = nil,
        presentationHandler: (@MainActor (ScrollCapturePresentationUpdate) -> Void)? = nil
    ) -> ScrollCaptureSession {
        let presentation = presentation ?? PresentationRecorder()
        return ScrollCaptureSession(
            seed: ScrollCaptureSeed(
                screenRect: NSRect(x: 100, y: 200, width: 80, height: 60),
                snapshotRect: NSRect(x: 0, y: 0, width: 80, height: 60),
                frozenImage: TestImageFactory.solid(size: CGSize(width: 80, height: 60), color: .red),
                annotations: [],
                eraserMasks: []
            ),
            capturer: capturer ?? FakeCapturer(),
            stitcher: engine,
            clock: clock ?? FakeClock(),
            activityMonitor: monitor ?? FakeActivityMonitor(),
            presentation: {
                presentation.record($0)
                presentationHandler?($0)
            }
        )
    }
}

private enum TestError: Error { case failed }

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
    let final: NSImage
    private let onDeinit: (() -> Void)?
    private(set) var appendedImages: [NSImage] = []
    private(set) var concurrent = 0
    private(set) var maximumConcurrent = 0
    private(set) var previewCallCount = 0
    private(set) var finalImageCallCount = 0
    private var finalErrors: [Error]

    init(
        results: [ScrollCaptureAppendKind],
        final: NSImage? = nil,
        finalErrors: [Error] = [],
        onDeinit: (() -> Void)? = nil
    ) {
        self.results = results
        self.final = final ?? TestImageFactory.solid(size: CGSize(width: 80, height: 120), color: .purple)
        self.finalErrors = finalErrors
        self.onDeinit = onDeinit
    }

    func append(_ image: NSImage) throws -> ScrollCaptureAppendUpdate {
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        defer { concurrent -= 1 }
        appendedImages.append(image)
        guard !results.isEmpty else { throw TestError.failed }
        return .testValue(kind: results.removeFirst())
    }

    func preview(maximumHeight: Int) throws -> NSImage {
        previewCallCount += 1
        return final
    }

    func finalImage() throws -> NSImage {
        finalImageCallCount += 1
        if !finalErrors.isEmpty { throw finalErrors.removeFirst() }
        return final
    }

    deinit { onDeinit?() }
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
    private var terminalCommand: (@MainActor (ScrollCaptureTerminalCommand) -> Void)?
    func start(_ callback: @escaping @MainActor () -> Void) { startCount += 1 }
    func start(
        onScrollActivity: @escaping @MainActor () -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    ) {
        startCount += 1
        terminalCommand = onTerminalCommand
    }
    func stop() { stopCount += 1 }
    func send(_ command: ScrollCaptureTerminalCommand) { terminalCommand?(command) }
}

@MainActor
private final class PresentationRecorder {
    private(set) var states: [ScrollCaptureSessionState] = []
    private(set) var kinds: [ScrollCaptureAppendKind] = []
    private(set) var previews: [NSImage] = []
    private(set) var commands: [ScrollCaptureTerminalCommand] = []
    var eventCount: Int { states.count + kinds.count + previews.count + commands.count }
    func record(_ event: ScrollCapturePresentationUpdate) {
        switch event {
        case let .terminalCommand(command): commands.append(command)
        case let .state(state): states.append(state)
        case let .append(update): kinds.append(update.kind)
        case let .preview(image): previews.append(image)
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
