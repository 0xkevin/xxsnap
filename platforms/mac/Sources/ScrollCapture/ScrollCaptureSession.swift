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
        setState(.preparing)
        do {
            guard let stitcher else { throw ScrollCaptureSessionError.invalidState(state) }
            let update = try stitcher.append(seed.frozenImage)
            presentation(.append(update))
            guard update.kind == .acceptedInitial else {
                throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
            }
            setState(.capturing)
            activityMonitor.start { [weak self] in self?.recordScrollActivity() }
        } catch {
            disarmSampling()
            setState(.paused(.captureFailure))
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
        disarmSampling()
        activityMonitor.stop()
        setState(.finishing)
        do {
            let image = try stitcher.finalImage()
            self.stitcher = nil
            setState(.finished)
            return image
        } catch {
            self.stitcher = nil
            setState(.paused(.captureFailure))
            throw error
        }
    }

    @discardableResult
    func cancel() -> ScrollCaptureSeed {
        guard state != .finished, state != .cancelled else { return seed }
        generation += 1
        disarmSampling()
        activityMonitor.stop()
        stitcher = nil
        setState(.cancelled)
        return seed
    }

    private func ensureSamplingLoop() {
        guard samplingTask == nil else { return }
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
            self?.samplingTask = nil
        }
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
            presentation(.append(update))
            try handle(update, stitcher: stitcher)
        } catch {
            guard generation == tickGeneration else { return }
            guard state == .capturing || state == .paused(.lowConfidence) else { return }
            disarmSampling()
            setState(.paused(.captureFailure))
        }
    }

    private func handle(
        _ update: ScrollCaptureAppendUpdate,
        stitcher: any ScrollStitching
    ) throws {
        switch update.kind {
        case .acceptedAppend:
            stabilityCount = 0
            if state == .paused(.lowConfidence) { setState(.capturing) }
            presentation(.preview(try stitcher.preview(maximumHeight: 1_200)))
        case .duplicateDiscarded, .reviewDiscarded:
            stabilityCount += 1
            if stabilityCount >= stabilityThreshold { disarmSampling() }
        case .pausedLowConfidence:
            disarmSampling()
            setState(.paused(.lowConfidence))
        case .resourceLimit:
            disarmSampling()
            setState(.paused(.resourceLimit))
        case .acceptedInitial:
            throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
        @unknown default:
            throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
        }
    }

    private func disarmSampling() {
        isSamplingArmed = false
        samplingTask?.cancel()
        samplingTask = nil
    }

    private func setState(_ newState: ScrollCaptureSessionState) {
        state = newState
        presentation(.state(newState))
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
