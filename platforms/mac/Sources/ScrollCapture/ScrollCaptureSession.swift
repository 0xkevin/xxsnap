import AppKit

@MainActor
protocol ScrollRegionCapturing {
    func captureImage(in selectionRect: NSRect) async throws -> NSImage
}

struct ScrollCaptureSeed {
    let screenRect: NSRect
    let snapshotRect: NSRect
    let frozenImage: NSImage
    let annotations: [CaptureAnnotation]
    let eraserMasks: [EraserMask]
}

@MainActor
protocol ScrollCaptureClock {
    func sleep(for duration: Duration) async throws
}

@MainActor
struct ContinuousScrollCaptureClock: ScrollCaptureClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

@MainActor
protocol ScrollStitching: AnyObject {
    func append(_ image: NSImage) throws -> ScrollCaptureAppendUpdate
    func preview(maximumHeight: Int) throws -> NSImage
    func finalImage() throws -> NSImage
}

extension ScrollCaptureBridge: ScrollStitching {}

enum ScrollCapturePauseReason: Equatable {
    case lowConfidence
    case resourceLimit
    case captureFailure
}

enum ScrollCaptureSessionState: Equatable {
    case idle
    case preparing
    case capturing
    case paused(ScrollCapturePauseReason)
    case finishing
    case finished
    case cancelled
}

enum ScrollCapturePresentationUpdate {
    case state(ScrollCaptureSessionState)
    case append(ScrollCaptureAppendUpdate)
    case preview(NSImage)
}

enum ScrollCaptureSessionError: Error, Equatable {
    case invalidState(ScrollCaptureSessionState)
    case initialFrameRejected(ScrollCaptureAppendKind)
    case operationCancelled
}

@MainActor
final class ScrollCaptureSession {
    let seed: ScrollCaptureSeed
    private(set) var state: ScrollCaptureSessionState = .idle
    private(set) var isSamplingArmed = false

    private let capturer: any ScrollRegionCapturing
    private var stitcher: (any ScrollStitching)?
    private let clock: any ScrollCaptureClock
    private let activityMonitor: any ScrollActivityMonitoring
    private let presentation: @MainActor (ScrollCapturePresentationUpdate) -> Void
    private let samplingInterval: Duration
    private let stabilityThreshold: Int
    private var stabilityCount = 0
    private var samplingTask: Task<Void, Never>?
    private var currentSamplingLoopID: UInt64?
    private var nextSamplingLoopID: UInt64 = 0
    private var tickInProgress = false
    private var generation = 0

    init(
        seed: ScrollCaptureSeed,
        capturer: any ScrollRegionCapturing,
        stitcher: any ScrollStitching,
        clock: any ScrollCaptureClock,
        activityMonitor: any ScrollActivityMonitoring,
        samplingInterval: Duration = .milliseconds(180),
        stabilityThreshold: Int = 3,
        presentation: @escaping @MainActor (ScrollCapturePresentationUpdate) -> Void
    ) {
        precondition(stabilityThreshold > 0)
        self.seed = seed
        self.capturer = capturer
        self.stitcher = stitcher
        self.clock = clock
        self.activityMonitor = activityMonitor
        self.samplingInterval = samplingInterval
        self.stabilityThreshold = stabilityThreshold
        self.presentation = presentation
    }

    func start() async throws {
        guard state == .idle else { throw ScrollCaptureSessionError.invalidState(state) }
        let operationGeneration = generation
        guard setState(.preparing, operationGeneration: operationGeneration) else { return }
        do {
            guard let stitcher else { throw ScrollCaptureSessionError.invalidState(state) }
            let update = try stitcher.append(seed.frozenImage)
            guard emit(
                .append(update),
                operationGeneration: operationGeneration,
                expectedState: .preparing
            ) else { return }
            guard update.kind == .acceptedInitial else {
                throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
            }
            guard setState(.capturing, operationGeneration: operationGeneration) else { return }
            activityMonitor.start { [weak self] in self?.recordScrollActivity() }
        } catch {
            guard generation == operationGeneration, state == .preparing else { return }
            disarmSampling()
            _ = setState(.paused(.captureFailure), operationGeneration: operationGeneration)
            throw error
        }
    }

    func recordScrollActivity() {
        switch state {
        case .capturing, .paused(.lowConfidence):
            stabilityCount = 0
            isSamplingArmed = true
            ensureSamplingLoop()
        default:
            break
        }
    }

    func finish() async throws -> NSImage {
        switch state {
        case .capturing, .paused:
            break
        default:
            throw ScrollCaptureSessionError.invalidState(state)
        }
        guard let stitcher else { throw ScrollCaptureSessionError.invalidState(state) }
        generation += 1
        let operationGeneration = generation
        disarmSampling()
        activityMonitor.stop()
        guard setState(.finishing, operationGeneration: operationGeneration) else {
            throw ScrollCaptureSessionError.operationCancelled
        }
        do {
            let image = try stitcher.finalImage()
            self.stitcher = nil
            guard setState(.finished, operationGeneration: operationGeneration) else {
                throw ScrollCaptureSessionError.operationCancelled
            }
            return image
        } catch {
            guard generation == operationGeneration, state == .finishing else { throw error }
            _ = setState(.paused(.captureFailure), operationGeneration: operationGeneration)
            throw error
        }
    }

    @discardableResult
    func cancel() -> ScrollCaptureSeed {
        guard state != .finished, state != .cancelled else { return seed }
        generation += 1
        let operationGeneration = generation
        disarmSampling()
        activityMonitor.stop()
        stitcher = nil
        _ = setState(.cancelled, operationGeneration: operationGeneration)
        return seed
    }

    private func ensureSamplingLoop() {
        guard currentSamplingLoopID == nil else { return }
        nextSamplingLoopID &+= 1
        let loopID = nextSamplingLoopID
        currentSamplingLoopID = loopID
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let clock = self?.clock, let interval = self?.samplingInterval else { break }
                do {
                    try await clock.sleep(for: interval)
                } catch {
                    break
                }
                guard !Task.isCancelled, self?.isSamplingArmed == true else { break }
                await self?.runSamplingTick()
            }
            self?.samplingLoopDidFinish(loopID)
        }
    }

    private func samplingLoopDidFinish(_ loopID: UInt64) {
        guard currentSamplingLoopID == loopID else { return }
        samplingTask = nil
        currentSamplingLoopID = nil
    }

    private func runSamplingTick() async {
        guard isSamplingArmed, !tickInProgress else { return }
        guard state == .capturing || state == .paused(.lowConfidence) else { return }
        let tickGeneration = generation
        tickInProgress = true
        defer { tickInProgress = false }

        do {
            // ScreenCaptureService accepts AppKit global screen coordinates. snapshotRect is
            // image-local geometry and is therefore intentionally not used for live sampling.
            let image = try await capturer.captureImage(in: seed.screenRect)
            guard generation == tickGeneration, isSamplingArmed else { return }
            guard state == .capturing || state == .paused(.lowConfidence) else { return }
            guard let stitcher else { return }
            let update = try stitcher.append(image)
            let appendState = state
            guard emit(
                .append(update),
                operationGeneration: tickGeneration,
                expectedState: appendState
            ) else { return }
            try handle(update, stitcher: stitcher, operationGeneration: tickGeneration)
        } catch {
            guard generation == tickGeneration else { return }
            guard state == .capturing || state == .paused(.lowConfidence) else { return }
            disarmSampling()
            _ = setState(.paused(.captureFailure), operationGeneration: tickGeneration)
        }
    }

    private func handle(
        _ update: ScrollCaptureAppendUpdate,
        stitcher: any ScrollStitching,
        operationGeneration: Int
    ) throws {
        switch update.kind {
        case .acceptedAppend:
            stabilityCount = 0
            if state == .paused(.lowConfidence) {
                guard setState(.capturing, operationGeneration: operationGeneration) else { return }
            }
            let preview = try stitcher.preview(maximumHeight: 1_200)
            _ = emit(
                .preview(preview),
                operationGeneration: operationGeneration,
                expectedState: .capturing
            )
        case .duplicateDiscarded, .reviewDiscarded:
            stabilityCount += 1
            if stabilityCount >= stabilityThreshold { disarmSampling() }
        case .pausedLowConfidence:
            disarmSampling()
            _ = setState(.paused(.lowConfidence), operationGeneration: operationGeneration)
        case .resourceLimit:
            disarmSampling()
            _ = setState(.paused(.resourceLimit), operationGeneration: operationGeneration)
        case .acceptedInitial:
            throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
        @unknown default:
            throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
        }
    }

    private func disarmSampling() {
        isSamplingArmed = false
        currentSamplingLoopID = nil
        samplingTask?.cancel()
        samplingTask = nil
    }

    @discardableResult
    private func setState(
        _ newState: ScrollCaptureSessionState,
        operationGeneration: Int
    ) -> Bool {
        state = newState
        return emit(
            .state(newState),
            operationGeneration: operationGeneration,
            expectedState: newState
        )
    }

    private func emit(
        _ update: ScrollCapturePresentationUpdate,
        operationGeneration: Int,
        expectedState: ScrollCaptureSessionState
    ) -> Bool {
        presentation(update)
        return generation == operationGeneration && state == expectedState
    }

#if DEBUG
    func test_runSamplingTick() async {
        await runSamplingTick()
    }
#endif

    deinit {
        samplingTask?.cancel()
    }
}
