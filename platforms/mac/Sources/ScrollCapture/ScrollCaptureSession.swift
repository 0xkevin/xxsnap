import AppKit

@MainActor
protocol ScrollRegionCapturing {
    func captureImage(in selectionRect: NSRect) async throws -> NSImage
}

@MainActor
protocol ScrollRegionCapturePriming: AnyObject {
    func primeCapture(in selectionRect: NSRect) async throws
}

@MainActor
protocol ScrollRegionCaptureBuffering: AnyObject {
    func discardBufferedFrames()
}

struct ScrollCaptureSeed {
    let screenRect: NSRect
    let snapshotRect: NSRect
    let frozenImage: NSImage
    let annotations: [CaptureAnnotation]
    let eraserMasks: [EraserMask]
    let targetApplicationProcessIdentifier: pid_t?

    init(
        screenRect: NSRect,
        snapshotRect: NSRect,
        frozenImage: NSImage,
        annotations: [CaptureAnnotation],
        eraserMasks: [EraserMask],
        targetApplicationProcessIdentifier: pid_t? = nil
    ) {
        self.screenRect = screenRect
        self.snapshotRect = snapshotRect
        self.frozenImage = frozenImage
        self.annotations = annotations
        self.eraserMasks = eraserMasks
        self.targetApplicationProcessIdentifier = targetApplicationProcessIdentifier
    }
}

@MainActor
protocol ScrollCaptureClock {
    func sleep(for duration: Duration) async throws
}

@MainActor
enum ScrollCaptureBoundaryState: Equatable {
    case atBoundary
    case notAtBoundary
    case unavailable
}

@MainActor
protocol ScrollCaptureStepControlling: AnyObject {
    func startBlockingPhysicalScroll() throws
    func boundaryState(
        direction: ScrollCaptureDirection,
        at point: NSPoint
    ) -> ScrollCaptureBoundaryState
    func performStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat,
        at point: NSPoint
    ) async throws
    func performKeyboardStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat
    ) async throws -> Bool
    func stop()
}

extension ScrollCaptureStepControlling {
    func boundaryState(
        direction: ScrollCaptureDirection,
        at point: NSPoint
    ) -> ScrollCaptureBoundaryState {
        .unavailable
    }

    func performKeyboardStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat
    ) async throws -> Bool {
        false
    }
}

@MainActor
struct ContinuousScrollCaptureClock: ScrollCaptureClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

protocol ScrollStitching: AnyObject {
    func append(_ image: NSImage) async throws -> ScrollCaptureAppendUpdate
    func append(
        _ image: NSImage,
        preferredDirection: ScrollCaptureDirection
    ) async throws -> ScrollCaptureAppendUpdate
    func preview(maximumHeight: Int) async throws -> NSImage
    func preview(maximumWidth: Int) async throws -> NSImage
    func finalImage() async throws -> NSImage
}

extension ScrollStitching {
    func append(
        _ image: NSImage,
        preferredDirection: ScrollCaptureDirection
    ) async throws -> ScrollCaptureAppendUpdate {
        try await append(image)
    }

    func preview(maximumWidth: Int) async throws -> NSImage {
        try await preview(maximumHeight: maximumWidth)
    }
}

final class ScrollCaptureBridgeWorker: ScrollStitching, @unchecked Sendable {
    private let bridge: ScrollCaptureBridge

    init?(maximumAcceptedBytes: UInt) {
        guard let bridge = ScrollCaptureBridge(maximumAcceptedBytes: maximumAcceptedBytes) else {
            return nil
        }
        self.bridge = bridge
    }

    func append(_ image: NSImage) async throws -> ScrollCaptureAppendUpdate {
        try await Task.detached(priority: .userInitiated) { [bridge] in
            try bridge.append(image)
        }.value
    }

    func append(
        _ image: NSImage,
        preferredDirection: ScrollCaptureDirection
    ) async throws -> ScrollCaptureAppendUpdate {
        try await Task.detached(priority: .userInitiated) { [bridge] in
            try bridge.append(image, preferredDirection: preferredDirection)
        }.value
    }

    func preview(maximumHeight: Int) async throws -> NSImage {
        try await Task.detached(priority: .userInitiated) { [bridge] in
            try bridge.preview(maximumHeight: maximumHeight)
        }.value
    }

    func preview(maximumWidth: Int) async throws -> NSImage {
        try await Task.detached(priority: .userInitiated) { [bridge] in
            try bridge.preview(maximumWidth: maximumWidth)
        }.value
    }

    func finalImage() async throws -> NSImage {
        try await Task.detached(priority: .userInitiated) { [bridge] in
            try bridge.finalImage()
        }.value
    }
}

enum ScrollCapturePauseReason: Equatable {
    case resourceLimit
    case captureFailure
}

enum ScrollCaptureMatchWarning: Equatable {
    case lowConfidence
    case noMovement
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

enum ScrollCapturePreviewEdge: Equatable {
    case bottom
    case top
}

struct ScrollCaptureScrollActivity: Equatable {
    let direction: ScrollCaptureDirection
    let distance: CGFloat
    let viewportDirection: ScrollCaptureDirection

    init(
        direction: ScrollCaptureDirection,
        distance: CGFloat,
        viewportDirection: ScrollCaptureDirection? = nil
    ) {
        self.direction = direction
        self.distance = distance
        self.viewportDirection = viewportDirection ?? direction
    }
}

struct ScrollCapturePreviewViewport: Equatable {
    let viewportHeight: Int
    let outputHeight: Int
}

enum ScrollCapturePresentationUpdate {
    case state(ScrollCaptureSessionState)
    case append(ScrollCaptureAppendUpdate)
    case preview(NSImage, edge: ScrollCapturePreviewEdge, viewport: ScrollCapturePreviewViewport)
    case viewportScroll(ScrollCaptureScrollActivity)
    case warning(ScrollCaptureMatchWarning?)
    case terminalCommand(ScrollCaptureTerminalCommand)
    case stepState(ScrollCaptureStepControlState)
}

enum ScrollCaptureTerminalCommand: Equatable {
    case finish
    case cancel
}

enum ScrollCaptureSessionError: Error, Equatable {
    case invalidState(ScrollCaptureSessionState)
    case initialFrameRejected(ScrollCaptureAppendKind)
    case operationCancelled
    case acceptedAppendWithoutDirection
}

@MainActor
final class ScrollCaptureSession {
    // A whole-window selection can contain a large fixed composer, title bar,
    // and sidebars. Keeping 70% of the selected height between samples also
    // leaves enough overlap inside the smaller message viewport.
    private static let stepViewportRatio: CGFloat = 0.3

    let seed: ScrollCaptureSeed
    private(set) var state: ScrollCaptureSessionState = .idle
    private(set) var isSamplingArmed = false

    private let capturer: any ScrollRegionCapturing
    private var stitcher: (any ScrollStitching)?
    private let clock: any ScrollCaptureClock
    private let activityMonitor: any ScrollActivityMonitoring
    private let stepController: (any ScrollCaptureStepControlling)?
    private let presentation: @MainActor (ScrollCapturePresentationUpdate) -> Void
    private let samplingInterval: Duration
    private var samplingTask: Task<Void, Never>?
    private var currentSamplingLoopID: UInt64?
    private var nextSamplingLoopID: UInt64 = 0
    private var tickInProgress = false
    private var generation = 0
    private var currentWarning: ScrollCaptureMatchWarning?
    private var preferredDirection: ScrollCaptureDirection = .unknown
    private var captureViewportPixelHeight = 1
    private var lockedStepDirection: ScrollCaptureDirection?
    private var stepInProgress = false
    private var consecutiveNoMovementSteps = 0
    private var stepTargetIndex = 0
    private var performedStepCount = 0
    private var reachedStepBoundary = false

    init(
        seed: ScrollCaptureSeed,
        capturer: any ScrollRegionCapturing,
        stitcher: any ScrollStitching,
        clock: any ScrollCaptureClock,
        activityMonitor: any ScrollActivityMonitoring,
        stepController: (any ScrollCaptureStepControlling)? = nil,
        samplingInterval: Duration = .milliseconds(180),
        presentation: @escaping @MainActor (ScrollCapturePresentationUpdate) -> Void
    ) {
        self.seed = seed
        self.capturer = capturer
        self.stitcher = stitcher
        self.clock = clock
        self.activityMonitor = activityMonitor
        self.stepController = stepController
        self.samplingInterval = samplingInterval
        self.presentation = presentation
    }

    func start() async throws {
        guard state == .idle else { throw ScrollCaptureSessionError.invalidState(state) }
        let operationGeneration = generation
        guard setState(.preparing, operationGeneration: operationGeneration) else { return }
        do {
            guard let stitcher else { throw ScrollCaptureSessionError.invalidState(state) }
            let update = try await stitcher.append(seed.frozenImage)
            guard emit(
                .append(update),
                operationGeneration: operationGeneration,
                expectedState: .preparing
            ) else { return }
            guard update.kind == .acceptedInitial else {
                throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
            }
            captureViewportPixelHeight = update.outputHeight > 0
                ? update.outputHeight
                : Self.pixelHeight(of: seed.frozenImage)
            let preview = try await stitcher.preview(maximumHeight: 1_200)
            guard emit(
                .preview(
                    preview,
                    edge: .bottom,
                    viewport: previewViewport(outputHeight: update.outputHeight)
                ),
                operationGeneration: operationGeneration,
                expectedState: .preparing
            ) else { return }
            if let primingCapturer = capturer as? any ScrollRegionCapturePriming {
                try await primingCapturer.primeCapture(in: seed.screenRect)
            }
            guard setState(.capturing, operationGeneration: operationGeneration) else { return }
            if let stepController {
                try stepController.startBlockingPhysicalScroll()
                activityMonitor.start(
                    onScrollActivity: { (_: ScrollCaptureScrollActivity) in },
                    onTerminalCommand: { [weak self] command in self?.receiveTerminalCommand(command) }
                )
                presentation(.stepState(.ready(directionLocked: false)))
            } else {
                startActivityMonitor()
            }
            if stepController == nil, capturer is any ScrollRegionCapturePriming {
                isSamplingArmed = true
                ensureSamplingLoop()
            }
        } catch {
            guard generation == operationGeneration, state == .preparing else { return }
            disarmSampling()
            _ = setState(.paused(.captureFailure), operationGeneration: operationGeneration)
            throw error
        }
    }

    func performStep(direction: ScrollCaptureDirection) async throws {
        guard state == .capturing else { throw ScrollCaptureSessionError.invalidState(state) }
        guard let stepController, !stepInProgress, !reachedStepBoundary else { return }
        let effectiveDirection = lockedStepDirection ?? direction
        guard effectiveDirection == .up || effectiveDirection == .down else { return }
        let operationGeneration = generation
        stepInProgress = true
        performedStepCount += 1
        NSLog(
            "xxsnap scroll-capture step begin number=%ld direction=%@ locked=%@ noMovementCount=%ld targetIndex=%ld",
            performedStepCount,
            String(describing: effectiveDirection),
            String(describing: lockedStepDirection),
            consecutiveNoMovementSteps,
            stepTargetIndex
        )
        presentation(.stepState(.executing))
        defer {
            stepInProgress = false
            if generation == operationGeneration, state == .capturing {
                presentation(.stepState(
                    reachedStepBoundary
                        ? .boundary
                        : .ready(directionLocked: lockedStepDirection != nil)
                ))
            }
        }

        do {
            let distance = max(1, seed.screenRect.height * Self.stepViewportRatio)
            let scrollPoints = Self.stepScrollPoints(in: seed.screenRect)
            let boundaryStates = scrollPoints.map {
                stepController.boundaryState(direction: effectiveDirection, at: $0)
            }
            if boundaryStates.allSatisfy({ $0 == .atBoundary }) {
                consecutiveNoMovementSteps = 1
                reachedStepBoundary = true
                _ = clearCurrentWarning(operationGeneration: operationGeneration)
                NSLog(
                    "xxsnap scroll-capture %@ boundary confirmed by accessibility",
                    effectiveDirection == .up ? "top" : "bottom"
                )
                return
            }

            let startIndex = stepTargetIndex % scrollPoints.count
            let rotatedIndices = (0..<scrollPoints.count).map {
                (startIndex + $0) % scrollPoints.count
            }
            let probeIndices = [
                ScrollCaptureBoundaryState.notAtBoundary,
                .unavailable,
                .atBoundary,
            ].flatMap { state in
                rotatedIndices.filter { boundaryStates[$0] == state }
            }
            var activeScrollPoint = scrollPoints[probeIndices[0]]
            var outcomeUsesKeyboard = false
            presentation(.viewportScroll(ScrollCaptureScrollActivity(
                direction: effectiveDirection,
                distance: distance
            )))
            var outcome: StepCandidateOutcome = .noMovement
            for targetIndex in probeIndices where boundaryStates[targetIndex] != .atBoundary {
                let scrollPoint = scrollPoints[targetIndex]
                activeScrollPoint = scrollPoint
                NSLog(
                    "xxsnap scroll-capture probing targetIndex=%ld point=(%.1f, %.1f) axBoundary=%@",
                    targetIndex,
                    scrollPoint.x,
                    scrollPoint.y,
                    String(describing: boundaryStates[targetIndex])
                )
                (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                try await stepController.performStep(
                    direction: effectiveDirection,
                    distance: distance,
                    at: scrollPoint
                )
                (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                outcome = try await collectStepCandidates(
                    direction: effectiveDirection,
                    operationGeneration: operationGeneration,
                    maximumCandidates: 1
                )
                if outcome != .noMovement {
                    stepTargetIndex = targetIndex
                    break
                }
                stepTargetIndex = (targetIndex + 1) % scrollPoints.count
            }
            if outcome == .noMovement {
                (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                if try await stepController.performKeyboardStep(
                    direction: effectiveDirection,
                    distance: distance
                ) {
                    NSLog("xxsnap scroll-capture wheel targets stationary; trying focused keyboard scroll")
                    outcomeUsesKeyboard = true
                    (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                    outcome = try await collectStepCandidates(
                        direction: effectiveDirection,
                        operationGeneration: operationGeneration
                    )
                }
            }
            if outcome == .lowConfidence {
                let delayedOutcome = try await collectStepCandidates(
                    direction: effectiveDirection,
                    operationGeneration: operationGeneration,
                    maximumCandidates: 1
                )
                if delayedOutcome == .accepted || delayedOutcome == .terminal {
                    outcome = delayedOutcome
                }
            }
            if outcome == .lowConfidence {
                let recoveryDistance = distance / 2
                let reverseDirection = Self.opposite(of: effectiveDirection)
                presentation(.viewportScroll(ScrollCaptureScrollActivity(
                    direction: reverseDirection,
                    distance: distance
                )))
                (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                if outcomeUsesKeyboard {
                    _ = try await stepController.performKeyboardStep(
                        direction: reverseDirection,
                        distance: distance
                    )
                } else {
                    try await stepController.performStep(
                        direction: reverseDirection,
                        distance: distance,
                        at: activeScrollPoint
                    )
                }
                presentation(.viewportScroll(ScrollCaptureScrollActivity(
                    direction: effectiveDirection,
                    distance: recoveryDistance
                )))
                (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                if outcomeUsesKeyboard {
                    _ = try await stepController.performKeyboardStep(
                        direction: effectiveDirection,
                        distance: recoveryDistance
                    )
                } else {
                    try await stepController.performStep(
                        direction: effectiveDirection,
                        distance: recoveryDistance,
                        at: activeScrollPoint
                    )
                }
                (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                outcome = try await collectStepCandidates(
                    direction: effectiveDirection,
                    operationGeneration: operationGeneration
                )
                if outcome == .lowConfidence {
                    presentation(.viewportScroll(ScrollCaptureScrollActivity(
                        direction: reverseDirection,
                        distance: recoveryDistance
                    )))
                    (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                    if outcomeUsesKeyboard {
                        _ = try await stepController.performKeyboardStep(
                            direction: reverseDirection,
                            distance: recoveryDistance
                        )
                    } else {
                        try await stepController.performStep(
                            direction: reverseDirection,
                            distance: recoveryDistance,
                            at: activeScrollPoint
                        )
                    }
                    (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                }
            }
            switch outcome {
            case .accepted:
                consecutiveNoMovementSteps = 0
                reachedStepBoundary = false
                lockedStepDirection = effectiveDirection
            case .noMovement:
                consecutiveNoMovementSteps += 1
                // One user action has already checked every viable wheel target and
                // the focused-keyboard fallback, so requiring more clicks only
                // repeats the same evidence.
                reachedStepBoundary = true
                _ = clearCurrentWarning(operationGeneration: operationGeneration)
            case .lowConfidence:
                consecutiveNoMovementSteps = 0
                setCurrentWarning(.lowConfidence, operationGeneration: operationGeneration)
            case .terminal:
                break
            }
            NSLog(
                "xxsnap scroll-capture step complete outcome=%@ noMovementCount=%ld boundary=%@",
                String(describing: outcome),
                consecutiveNoMovementSteps,
                reachedStepBoundary ? "true" : "false"
            )
        } catch {
            guard generation == operationGeneration, state == .capturing else { throw error }
            _ = setState(.paused(.captureFailure), operationGeneration: operationGeneration)
            throw error
        }
    }

    private enum StepCandidateOutcome: Equatable {
        case accepted
        case noMovement
        case lowConfidence
        case terminal
    }

    private func collectStepCandidates(
        direction: ScrollCaptureDirection,
        operationGeneration: Int,
        maximumCandidates: Int = 2
    ) async throws -> StepCandidateOutcome {
        var sawLowConfidence = false
        for candidateIndex in 0..<maximumCandidates {
            guard generation == operationGeneration, state == .capturing else { return .terminal }
            let image = try await capturer.captureImage(in: seed.screenRect)
            guard generation == operationGeneration, state == .capturing else { return .terminal }
            guard let stitcher else { return .terminal }
            let update = try await stitcher.append(image, preferredDirection: direction)
            NSLog(
                "xxsnap scroll-capture step candidate=%ld kind=%@ direction=%@ confidence=%.3f appendedHeight=%ld outputHeight=%ld",
                candidateIndex + 1,
                String(describing: update.kind),
                String(describing: update.direction),
                update.confidence,
                update.appendedHeight,
                update.outputHeight
            )
            guard emit(
                .append(update),
                operationGeneration: operationGeneration,
                expectedState: .capturing
            ) else { return .terminal }
            // A step may recover from a transient mismatch by sampling again or
            // retrying at half distance. Only expose low confidence after those
            // recovery attempts have also failed.
            if update.kind != .lowConfidenceDiscarded {
                try await handle(update, stitcher: stitcher, operationGeneration: operationGeneration)
            }
            switch update.kind {
            case .acceptedAppend:
                return .accepted
            case .awaitingEvidence:
                if update.appendedHeight > 0,
                   update.direction == .up || update.direction == .down {
                    return .accepted
                }
                sawLowConfidence = true
            case .lowConfidenceDiscarded:
                sawLowConfidence = true
            case .resourceLimit:
                return .terminal
            case .reviewDiscarded:
                // A review frame matched already-seen content rather than the
                // current viewport. That is inconclusive, not proof that the
                // scrollable control is at its boundary.
                sawLowConfidence = true
            case .duplicateDiscarded:
                break
            case .acceptedInitial:
                throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
            @unknown default:
                throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
            }
        }
        return sawLowConfidence ? .lowConfidence : .noMovement
    }

    private static func opposite(of direction: ScrollCaptureDirection) -> ScrollCaptureDirection {
        switch direction {
        case .down: return .up
        case .up: return .down
        case .unknown: return .unknown
        @unknown default: return .unknown
        }
    }

    private static func stepScrollPoints(in rect: NSRect) -> [NSPoint] {
        let horizontalOffset = max(4, min(48, rect.width * 0.10))
        let verticalOffset = max(4, rect.height * 0.25)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return [
            NSPoint(x: center.x, y: center.y + verticalOffset),
            center,
            NSPoint(x: center.x - horizontalOffset, y: center.y),
            NSPoint(x: center.x + horizontalOffset, y: center.y),
            NSPoint(x: center.x, y: center.y - verticalOffset),
        ]
    }

    func recordScrollActivity(direction: ScrollCaptureDirection = .unknown) {
        armSampling(direction: direction)
    }

    func recordScrollActivity(_ activity: ScrollCaptureScrollActivity) {
        guard state == .capturing else { return }
        if activity.direction != .unknown, activity.distance > 0 {
            presentation(.viewportScroll(activity))
        }
        armSampling(direction: activity.direction)
    }

    private func armSampling(direction: ScrollCaptureDirection) {
        guard state == .capturing else { return }
        if direction != .unknown { preferredDirection = direction }
        isSamplingArmed = true
        ensureSamplingLoop()
        if direction != .unknown, !tickInProgress {
            Task { [weak self] in
                await self?.runSamplingTick()
            }
        }
    }

    private func receiveTerminalCommand(_ command: ScrollCaptureTerminalCommand) {
        switch state {
        case .capturing, .paused:
            presentation(.terminalCommand(command))
        default:
            break
        }
    }

    private func startActivityMonitor() {
        activityMonitor.start(
            onScrollActivity: { [weak self] activity in
                self?.recordScrollActivity(activity)
            },
            onTerminalCommand: { [weak self] command in self?.receiveTerminalCommand(command) }
        )
    }

    func finish() async throws -> NSImage {
        NSLog("xxsnap scroll-capture session finish requested state=%@", String(describing: state))
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
        stepController?.stop()
        guard setState(.finishing, operationGeneration: operationGeneration) else {
            throw ScrollCaptureSessionError.operationCancelled
        }
        do {
            let image = try await stitcher.finalImage()
            NSLog("xxsnap scroll-capture stitcher produced final image size=%@", NSStringFromSize(image.size))
            self.stitcher = nil
            guard setState(.finished, operationGeneration: operationGeneration) else {
                throw ScrollCaptureSessionError.operationCancelled
            }
            return image
        } catch {
            guard generation == operationGeneration, state == .finishing else { throw error }
            if setState(.paused(.captureFailure), operationGeneration: operationGeneration) {
                if stepController == nil { startActivityMonitor() }
            }
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
        stepController?.stop()
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
        guard state == .capturing else { return }
        let tickGeneration = generation
        tickInProgress = true
        defer { tickInProgress = false }

        do {
            NSLog("xxsnap scroll-capture sampling request direction=%@", String(describing: preferredDirection))
            // ScreenCaptureService accepts AppKit global screen coordinates. snapshotRect is
            // image-local geometry and is therefore intentionally not used for live sampling.
            let image = try await capturer.captureImage(in: seed.screenRect)
            guard generation == tickGeneration, isSamplingArmed else { return }
            guard state == .capturing else { return }
            guard let stitcher else { return }
            let update = try await stitcher.append(
                image,
                preferredDirection: preferredDirection
            )
            NSLog(
                "xxsnap scroll-capture append kind=%@ direction=%@ confidence=%.3f appendedHeight=%ld",
                String(describing: update.kind),
                String(describing: update.direction),
                update.confidence,
                update.appendedHeight
            )
            let appendState = state
            guard emit(
                .append(update),
                operationGeneration: tickGeneration,
                expectedState: appendState
            ) else { return }
            try await handle(update, stitcher: stitcher, operationGeneration: tickGeneration)
        } catch {
            NSLog("xxsnap scroll-capture sampling failed: %@", String(describing: error))
            guard generation == tickGeneration else { return }
            guard state == .capturing else { return }
            disarmSampling()
            _ = setState(.paused(.captureFailure), operationGeneration: tickGeneration)
        }
    }

    private func handle(
        _ update: ScrollCaptureAppendUpdate,
        stitcher: any ScrollStitching,
        operationGeneration: Int
    ) async throws {
        switch update.kind {
        case .acceptedAppend:
            let edge: ScrollCapturePreviewEdge
            switch update.direction {
            case .down: edge = .bottom
            case .up: edge = .top
            case .unknown:
                throw ScrollCaptureSessionError.acceptedAppendWithoutDirection
            @unknown default:
                throw ScrollCaptureSessionError.acceptedAppendWithoutDirection
            }
            guard clearCurrentWarning(operationGeneration: operationGeneration) else { return }
            let preview = try await stitcher.preview(maximumHeight: 1_200)
            _ = emit(
                .preview(
                    preview,
                    edge: edge,
                    viewport: previewViewport(outputHeight: update.outputHeight)
                ),
                operationGeneration: operationGeneration,
                expectedState: .capturing
            )
        case .duplicateDiscarded, .reviewDiscarded:
            if currentWarning == .lowConfidence {
                _ = clearCurrentWarning(operationGeneration: operationGeneration)
            }
        case .awaitingEvidence:
            guard clearCurrentWarning(operationGeneration: operationGeneration) else { return }
            guard update.appendedHeight > 0 else { return }
            let edge: ScrollCapturePreviewEdge
            switch update.direction {
            case .down: edge = .bottom
            case .up: edge = .top
            case .unknown: return
            @unknown default: return
            }
            let preview = try await stitcher.preview(maximumHeight: 1_200)
            _ = emit(
                .preview(
                    preview,
                    edge: edge,
                    viewport: previewViewport(outputHeight: update.outputHeight)
                ),
                operationGeneration: operationGeneration,
                expectedState: .capturing
            )
        case .lowConfidenceDiscarded:
            if currentWarning != .lowConfidence {
                currentWarning = .lowConfidence
                guard emit(
                    .warning(.lowConfidence),
                    operationGeneration: operationGeneration,
                    expectedState: .capturing
                ) else { return }
            }
        case .resourceLimit:
            disarmSampling()
            _ = setState(.paused(.resourceLimit), operationGeneration: operationGeneration)
        case .acceptedInitial:
            throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
        @unknown default:
            throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
        }
    }

    private func clearCurrentWarning(operationGeneration: Int) -> Bool {
        guard currentWarning != nil else { return true }
        currentWarning = nil
        return emit(
            .warning(nil),
            operationGeneration: operationGeneration,
            expectedState: .capturing
        )
    }

    private func setCurrentWarning(
        _ warning: ScrollCaptureMatchWarning,
        operationGeneration: Int
    ) {
        guard currentWarning != warning else { return }
        currentWarning = warning
        _ = emit(
            .warning(warning),
            operationGeneration: operationGeneration,
            expectedState: .capturing
        )
    }

    private func previewViewport(outputHeight: Int) -> ScrollCapturePreviewViewport {
        ScrollCapturePreviewViewport(
            viewportHeight: captureViewportPixelHeight,
            outputHeight: max(captureViewportPixelHeight, outputHeight)
        )
    }

    private static func pixelHeight(of image: NSImage) -> Int {
        if let height = image.representations.map(\.pixelsHigh).filter({ $0 > 0 }).max() {
            return height
        }
        return max(1, Int(image.size.height.rounded()))
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
