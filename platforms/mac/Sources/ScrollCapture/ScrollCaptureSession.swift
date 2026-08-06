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
    func performTargetedStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat,
        at point: NSPoint
    ) async throws -> Bool
    func performScrollbarStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat,
        in viewport: NSRect,
        capturedImage: NSImage
    ) async throws -> Bool
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

    func performTargetedStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat,
        at point: NSPoint
    ) async throws -> Bool {
        false
    }

    func performScrollbarStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat,
        in viewport: NSRect,
        capturedImage: NSImage
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
    func append(
        _ image: NSImage,
        preferredDirection: ScrollCaptureDirection,
        expectedAdvance: CGFloat
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

    func append(
        _ image: NSImage,
        preferredDirection: ScrollCaptureDirection,
        expectedAdvance: CGFloat
    ) async throws -> ScrollCaptureAppendUpdate {
        try await append(image, preferredDirection: preferredDirection)
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

    func append(
        _ image: NSImage,
        preferredDirection: ScrollCaptureDirection,
        expectedAdvance: CGFloat
    ) async throws -> ScrollCaptureAppendUpdate {
        try await Task.detached(priority: .userInitiated) { [bridge] in
            try bridge.append(
                image,
                preferredDirection: preferredDirection,
                expectedAdvance: expectedAdvance
            )
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
    private static let largeViewportThreshold: CGFloat = 600
    private static let compactViewportRatio: CGFloat = 0.40
    private static let largeViewportRatio: CGFloat = 0.50
    private static let lowConfidenceVisualBoundaryThreshold = 2
    private static let stableSamplingFrameThreshold = 3

    static func stepDistance(forViewportHeight height: CGFloat) -> CGFloat {
        guard height.isFinite else { return 1 }
        let ratio = height >= largeViewportThreshold ? largeViewportRatio : compactViewportRatio
        return max(1, height * ratio)
    }

    let seed: ScrollCaptureSeed
    private(set) var state: ScrollCaptureSessionState = .idle
    private(set) var isSamplingArmed = false

    private let capturer: any ScrollRegionCapturing
    private var stitcher: (any ScrollStitching)?
    private let clock: any ScrollCaptureClock
    private let activityMonitor: any ScrollActivityMonitoring
    private let stepController: (any ScrollCaptureStepControlling)?
    private let diagnosticLogger: any DiagnosticLogging
    private let presentation: @MainActor (ScrollCapturePresentationUpdate) -> Void
    private let samplingInterval: Duration
    private var samplingTask: Task<Void, Never>?
    private var currentSamplingLoopID: UInt64?
    private var nextSamplingLoopID: UInt64 = 0
    private var tickInProgress = false
    private var generation = 0
    private var currentWarning: ScrollCaptureMatchWarning?
    private var preferredDirection: ScrollCaptureDirection = .unknown
    private var consecutiveStableSamplingFrames = 0
    private var captureViewportPixelHeight = 1
    private var lockedStepDirection: ScrollCaptureDirection?
    private var lockedContentDirection: ScrollCaptureDirection?
    private var lastAcceptedStepContentDirection: ScrollCaptureDirection?
    private var stepInProgress = false
    private var consecutiveNoMovementSteps = 0
    private var consecutiveLowConfidenceSteps = 0
    private var stepTargetIndex = 0
    private var performedStepCount = 0
    private var reachedStepBoundary = false
    private var lastStepCandidateImage: NSImage?
    private var diagnosticSession: DiagnosticCaptureSession?

    init(
        seed: ScrollCaptureSeed,
        capturer: any ScrollRegionCapturing,
        stitcher: any ScrollStitching,
        clock: any ScrollCaptureClock,
        activityMonitor: any ScrollActivityMonitoring,
        stepController: (any ScrollCaptureStepControlling)? = nil,
        samplingInterval: Duration = .milliseconds(180),
        diagnosticLogger: any DiagnosticLogging = NoopDiagnosticLogger.shared,
        presentation: @escaping @MainActor (ScrollCapturePresentationUpdate) -> Void
    ) {
        self.seed = seed
        self.capturer = capturer
        self.stitcher = stitcher
        self.clock = clock
        self.activityMonitor = activityMonitor
        self.stepController = stepController
        self.samplingInterval = samplingInterval
        self.diagnosticLogger = diagnosticLogger
        self.presentation = presentation
    }

    func start() async throws {
        guard state == .idle else { throw ScrollCaptureSessionError.invalidState(state) }
        let operationGeneration = generation
        guard setState(.preparing, operationGeneration: operationGeneration) else { return }
        let diagnosticSession = diagnosticLogger.beginScrollCaptureSession()
        self.diagnosticSession = diagnosticSession
        diagnosticLogger.record(
            category: .scrollCapture,
            level: .info,
            event: "scroll_session_started",
            metadata: [
                "capture_mode": stepController == nil ? "activity_sampling" : "automatic_step",
                "detailed": diagnosticSession.isDetailed ? "true" : "false",
                "viewport_height": String(format: "%.1f", seed.screenRect.height),
                "viewport_width": String(format: "%.1f", seed.screenRect.width),
            ]
        )
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
        } catch {
            guard generation == operationGeneration, state == .preparing else { return }
            disarmSampling()
            _ = setState(.paused(.captureFailure), operationGeneration: operationGeneration)
            endDiagnosticSession(
                event: "scroll_session_start_failed",
                level: .error,
                metadata: ["error_type": String(describing: type(of: error))]
            )
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
        lastStepCandidateImage = nil
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
            lastStepCandidateImage = nil
            if generation == operationGeneration, state == .capturing {
                presentation(.stepState(
                    reachedStepBoundary
                        ? .boundary
                        : .ready(directionLocked: lockedStepDirection != nil)
                ))
            }
        }

        do {
            let distance = Self.stepDistance(forViewportHeight: seed.screenRect.height)
            diagnosticLogger.record(
                category: .scrollCapture,
                level: .debug,
                event: "scroll_step_requested",
                metadata: [
                    "direction": String(describing: effectiveDirection),
                    "distance": String(format: "%.1f", distance),
                    "step_number": String(performedStepCount),
                ],
                detail: .detailed
            )
            let scrollPoints = Self.stepScrollPoints(in: seed.screenRect)
            let boundaryDirection = lockedContentDirection ?? effectiveDirection
            let boundaryStates = scrollPoints.map {
                stepController.boundaryState(direction: boundaryDirection, at: $0)
            }
            let accessibilityConfirmsMoreContent = boundaryStates.contains(.notAtBoundary)
            if boundaryStates.allSatisfy({ $0 == .atBoundary }) {
                (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                let boundaryOutcome = try await collectStepCandidates(
                    direction: effectiveDirection,
                    operationGeneration: operationGeneration,
                    maximumCandidates: 1
                )
                if boundaryOutcome == .accepted {
                    consecutiveNoMovementSteps = 0
                    consecutiveLowConfidenceSteps = 0
                    reachedStepBoundary = false
                    lockedStepDirection = effectiveDirection
                    if let acceptedDirection = lastAcceptedStepContentDirection {
                        lockedContentDirection = acceptedDirection
                    }
                    recordStepCompleted(outcome: boundaryOutcome)
                    return
                }
                if boundaryOutcome != .terminal {
                    consecutiveNoMovementSteps = 1
                    consecutiveLowConfidenceSteps = 0
                    reachedStepBoundary = true
                    _ = clearCurrentWarning(operationGeneration: operationGeneration)
                }
                NSLog(
                    "xxsnap scroll-capture %@ boundary confirmed by accessibility",
                    effectiveDirection == .up ? "top" : "bottom"
                )
                recordStepCompleted(outcome: boundaryOutcome)
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
            var attemptedScrollbarFallback = false
            presentation(.viewportScroll(ScrollCaptureScrollActivity(
                direction: effectiveDirection,
                distance: distance
            )))
            var outcome: StepCandidateOutcome = .noMovement
            var deferredProbeOutcome: StepCandidateOutcome = .noMovement
            func rememberDeferredProbeOutcome(_ candidate: StepCandidateOutcome) {
                switch candidate {
                case .lowConfidence:
                    deferredProbeOutcome = .lowConfidence
                case .review where deferredProbeOutcome != .lowConfidence:
                    deferredProbeOutcome = .review
                default:
                    break
                }
            }
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
                    expectedAdvance: distance,
                    maximumCandidates: 1
                )
                if outcome == .noMovement,
                   lockedStepDirection != nil,
                   !attemptedScrollbarFallback,
                   let lastStepCandidateImage {
                    attemptedScrollbarFallback = true
                    if try await stepController.performScrollbarStep(
                        direction: effectiveDirection,
                        distance: distance,
                        in: seed.screenRect,
                        capturedImage: lastStepCandidateImage
                    ) {
                        NSLog("xxsnap scroll-capture first wheel stationary; dragging detected outer scrollbar")
                        (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                        outcome = try await collectStepCandidates(
                            direction: effectiveDirection,
                            operationGeneration: operationGeneration,
                            expectedAdvance: distance,
                            maximumCandidates: 1
                        )
                    }
                }
                if outcome == .accepted || outcome == .terminal {
                    stepTargetIndex = targetIndex
                    break
                }
                if outcome == .lowConfidence {
                    stepTargetIndex = targetIndex
                    break
                }
                if outcome == .review,
                   boundaryStates[targetIndex] == .notAtBoundary {
                    stepTargetIndex = targetIndex
                    break
                }
                rememberDeferredProbeOutcome(outcome)
                stepTargetIndex = (targetIndex + 1) % scrollPoints.count
                outcome = .noMovement
            }
            if outcome == .noMovement, deferredProbeOutcome != .noMovement {
                outcome = deferredProbeOutcome
            }
            if outcome == .noMovement, !attemptedScrollbarFallback {
                if let lastStepCandidateImage,
                   try await stepController.performScrollbarStep(
                       direction: effectiveDirection,
                       distance: distance,
                       in: seed.screenRect,
                       capturedImage: lastStepCandidateImage
                   ) {
                    NSLog("xxsnap scroll-capture wheel stationary; dragging detected outer scrollbar")
                    (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                    outcome = try await collectStepCandidates(
                        direction: effectiveDirection,
                        operationGeneration: operationGeneration,
                        expectedAdvance: distance,
                        maximumCandidates: 1
                    )
                }
            }
            if outcome == .noMovement {
                (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                if try await stepController.performTargetedStep(
                    direction: effectiveDirection,
                    distance: distance,
                    at: activeScrollPoint
                ) {
                    NSLog("xxsnap scroll-capture global wheel stationary; trying targeted wheel delivery")
                    (capturer as? any ScrollRegionCaptureBuffering)?.discardBufferedFrames()
                    outcome = try await collectStepCandidates(
                        direction: effectiveDirection,
                        operationGeneration: operationGeneration,
                        expectedAdvance: distance,
                        maximumCandidates: 1
                    )
                }
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
                        operationGeneration: operationGeneration,
                        expectedAdvance: distance
                    )
                }
            }
            if outcome == .lowConfidence || outcome == .review {
                let delayedOutcome = try await collectStepCandidates(
                    direction: effectiveDirection,
                    operationGeneration: operationGeneration,
                    expectedAdvance: distance,
                    maximumCandidates: 1
                )
                if delayedOutcome == .accepted || delayedOutcome == .terminal {
                    outcome = delayedOutcome
                } else if delayedOutcome == .lowConfidence || delayedOutcome == .review {
                    outcome = delayedOutcome
                }
            }
            if outcome == .lowConfidence || outcome == .review {
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
                for recoveryDistance in [distance / 2, distance / 4] {
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
                        operationGeneration: operationGeneration,
                        expectedAdvance: recoveryDistance
                    )
                    guard outcome == .lowConfidence || outcome == .review else { break }

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
                consecutiveLowConfidenceSteps = 0
                reachedStepBoundary = false
                lockedStepDirection = effectiveDirection
                if let acceptedDirection = lastAcceptedStepContentDirection {
                    lockedContentDirection = acceptedDirection
                }
            case .noMovement:
                consecutiveLowConfidenceSteps = 0
                consecutiveNoMovementSteps += 1
                if accessibilityConfirmsMoreContent {
                    reachedStepBoundary = false
                    setCurrentWarning(.lowConfidence, operationGeneration: operationGeneration)
                } else {
                    // One user action has already checked every viable wheel target and
                    // the focused-keyboard fallback, so requiring more clicks only
                    // repeats the same evidence.
                    reachedStepBoundary = true
                    _ = clearCurrentWarning(operationGeneration: operationGeneration)
                }
            case .lowConfidence:
                consecutiveNoMovementSteps = 0
                if lockedStepDirection != nil {
                    consecutiveLowConfidenceSteps += 1
                } else {
                    consecutiveLowConfidenceSteps = 0
                }
                if consecutiveLowConfidenceSteps >= Self.lowConfidenceVisualBoundaryThreshold {
                    reachedStepBoundary = true
                    _ = clearCurrentWarning(operationGeneration: operationGeneration)
                } else {
                    setCurrentWarning(.lowConfidence, operationGeneration: operationGeneration)
                }
            case .review:
                consecutiveNoMovementSteps = 0
                consecutiveLowConfidenceSteps = 0
                if let lockedStepDirection,
                   let lockedContentDirection,
                   lockedStepDirection != lockedContentDirection {
                    reachedStepBoundary = true
                    _ = clearCurrentWarning(operationGeneration: operationGeneration)
                } else {
                    setCurrentWarning(.lowConfidence, operationGeneration: operationGeneration)
                }
            case .terminal:
                break
            }
            NSLog(
                "xxsnap scroll-capture step complete outcome=%@ noMovementCount=%ld boundary=%@",
                String(describing: outcome),
                consecutiveNoMovementSteps,
                reachedStepBoundary ? "true" : "false"
            )
            recordStepCompleted(outcome: outcome)
        } catch {
            guard generation == operationGeneration, state == .capturing else { throw error }
            _ = setState(.paused(.captureFailure), operationGeneration: operationGeneration)
            diagnosticLogger.record(
                category: .scrollCapture,
                level: .error,
                event: "scroll_step_failed",
                metadata: ["error_type": String(describing: type(of: error))]
            )
            throw error
        }
    }

    private enum StepCandidateOutcome: Equatable {
        case accepted
        case noMovement
        case lowConfidence
        case review
        case terminal
    }

    private func collectStepCandidates(
        direction: ScrollCaptureDirection,
        operationGeneration: Int,
        expectedAdvance: CGFloat = 0,
        maximumCandidates: Int = 2
    ) async throws -> StepCandidateOutcome {
        var sawLowConfidence = false
        var sawReview = false
        for candidateIndex in 0..<maximumCandidates {
            guard generation == operationGeneration, state == .capturing else { return .terminal }
            let image = try await capturer.captureImage(in: seed.screenRect)
            lastStepCandidateImage = image
            guard generation == operationGeneration, state == .capturing else { return .terminal }
            guard let stitcher else { return .terminal }
            let update = try await stitcher.append(
                image,
                preferredDirection: lockedContentDirection ?? direction,
                expectedAdvance: expectedAdvance
            )
            NSLog(
                "xxsnap scroll-capture step candidate=%ld expectedAdvance=%.1f kind=%@ direction=%@ confidence=%.3f appendedHeight=%ld outputHeight=%ld",
                candidateIndex + 1,
                expectedAdvance,
                String(describing: update.kind),
                String(describing: update.direction),
                update.confidence,
                update.appendedHeight,
                update.outputHeight
            )
            recordStitchResult(update, source: "step")
            guard emit(
                .append(update),
                operationGeneration: operationGeneration,
                expectedState: .capturing
            ) else { return .terminal }
            // A step may recover from a transient mismatch by sampling again or
            // retrying at half distance. Only expose low confidence after those
            // recovery attempts have also failed.
            if update.kind != .lowConfidenceDiscarded {
                try await handle(
                    update,
                    previewDirection: direction,
                    stitcher: stitcher,
                    operationGeneration: operationGeneration
                )
            }
            switch update.kind {
            case .acceptedAppend:
                if update.direction == .up || update.direction == .down {
                    lastAcceptedStepContentDirection = update.direction
                }
                return .accepted
            case .awaitingEvidence:
                if update.appendedHeight > 0,
                   update.direction == .up || update.direction == .down {
                    lastAcceptedStepContentDirection = update.direction
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
                sawReview = true
            case .duplicateDiscarded:
                break
            case .acceptedInitial:
                throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
            @unknown default:
                throw ScrollCaptureSessionError.initialFrameRejected(update.kind)
            }
        }
        if sawLowConfidence { return .lowConfidence }
        if sawReview { return .review }
        return .noMovement
    }

    private static func opposite(of direction: ScrollCaptureDirection) -> ScrollCaptureDirection {
        switch direction {
        case .down: return .up
        case .up: return .down
        case .unknown: return .unknown
        @unknown default: return .unknown
        }
    }

    static func stepScrollPoints(in rect: NSRect) -> [NSPoint] {
        let horizontalInset = min(rect.width / 2, min(16, max(8, rect.width * 0.04)))
        let verticalOffset = max(4, rect.height * 0.25)
        let rightX = rect.maxX - horizontalInset
        let centerX = rect.midX
        let leftX = rect.minX + horizontalInset
        return [
            NSPoint(x: rightX, y: rect.midY),
            NSPoint(x: rightX, y: rect.midY + verticalOffset),
            NSPoint(x: rightX, y: rect.midY - verticalOffset),
            NSPoint(x: centerX, y: rect.midY),
            NSPoint(x: centerX, y: rect.midY + verticalOffset),
            NSPoint(x: centerX, y: rect.midY - verticalOffset),
            NSPoint(x: leftX, y: rect.midY),
            NSPoint(x: leftX, y: rect.midY + verticalOffset),
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
        consecutiveStableSamplingFrames = 0
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
            endDiagnosticSession(
                event: "scroll_session_finished",
                level: .info,
                metadata: [
                    "final_height": String(format: "%.1f", image.size.height),
                    "final_width": String(format: "%.1f", image.size.width),
                ]
            )
            return image
        } catch {
            guard generation == operationGeneration, state == .finishing else { throw error }
            if setState(.paused(.captureFailure), operationGeneration: operationGeneration) {
                if stepController == nil { startActivityMonitor() }
            }
            diagnosticLogger.record(
                category: .scrollCapture,
                level: .error,
                event: "scroll_session_finish_failed",
                metadata: ["error_type": String(describing: type(of: error))]
            )
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
        endDiagnosticSession(
            event: "scroll_session_cancelled",
            level: .info
        )
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
            recordStitchResult(update, source: "sampling")
            let appendState = state
            guard emit(
                .append(update),
                operationGeneration: tickGeneration,
                expectedState: appendState
            ) else { return }
            updateSamplingStability(for: update.kind)
            try await handle(update, stitcher: stitcher, operationGeneration: tickGeneration)
        } catch {
            NSLog("xxsnap scroll-capture sampling failed: %@", String(describing: error))
            guard generation == tickGeneration else { return }
            guard state == .capturing else { return }
            disarmSampling()
            _ = setState(.paused(.captureFailure), operationGeneration: tickGeneration)
            diagnosticLogger.record(
                category: .scrollCapture,
                level: .error,
                event: "scroll_sampling_failed",
                metadata: ["error_type": String(describing: type(of: error))]
            )
        }
    }

    private func recordStitchResult(
        _ update: ScrollCaptureAppendUpdate,
        source: String
    ) {
        diagnosticLogger.record(
            category: .scrollCapture,
            level: .debug,
            event: "scroll_stitch_result",
            metadata: [
                "appended_height": String(update.appendedHeight),
                "confidence": String(format: "%.3f", update.confidence),
                "direction": String(describing: update.direction),
                "kind": String(describing: update.kind),
                "output_height": String(update.outputHeight),
                "source": source,
            ],
            detail: .detailed
        )
    }

    private func recordStepCompleted(outcome: StepCandidateOutcome) {
        diagnosticLogger.record(
            category: .scrollCapture,
            level: reachedStepBoundary ? .warning : .info,
            event: "scroll_step_completed",
            metadata: [
                "boundary": reachedStepBoundary ? "true" : "false",
                "no_movement_count": String(consecutiveNoMovementSteps),
                "outcome": String(describing: outcome),
                "step_number": String(performedStepCount),
            ]
        )
    }

    private func endDiagnosticSession(
        event: String,
        level: DiagnosticLogLevel,
        metadata: [String: String] = [:]
    ) {
        guard let diagnosticSession else { return }
        diagnosticLogger.record(
            category: .scrollCapture,
            level: level,
            event: event,
            metadata: metadata
        )
        diagnosticLogger.endScrollCaptureSession(diagnosticSession)
        self.diagnosticSession = nil
    }

    private func handle(
        _ update: ScrollCaptureAppendUpdate,
        previewDirection: ScrollCaptureDirection? = nil,
        stitcher: any ScrollStitching,
        operationGeneration: Int
    ) async throws {
        switch update.kind {
        case .acceptedAppend:
            guard update.direction == .down || update.direction == .up else {
                throw ScrollCaptureSessionError.acceptedAppendWithoutDirection
            }
            let edge: ScrollCapturePreviewEdge
            switch previewDirection ?? update.direction {
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
            guard update.direction == .down || update.direction == .up else { return }
            let edge: ScrollCapturePreviewEdge
            switch previewDirection ?? update.direction {
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

    private func updateSamplingStability(for kind: ScrollCaptureAppendKind) {
        switch kind {
        case .duplicateDiscarded, .reviewDiscarded:
            consecutiveStableSamplingFrames += 1
            if consecutiveStableSamplingFrames >= Self.stableSamplingFrameThreshold {
                disarmSampling()
            }
        case .acceptedAppend, .awaitingEvidence, .lowConfidenceDiscarded:
            consecutiveStableSamplingFrames = 0
        case .acceptedInitial, .resourceLimit:
            break
        @unknown default:
            consecutiveStableSamplingFrames = 0
        }
    }

    private static func pixelHeight(of image: NSImage) -> Int {
        if let height = image.representations.map(\.pixelsHigh).filter({ $0 > 0 }).max() {
            return height
        }
        return max(1, Int(image.size.height.rounded()))
    }

    private func disarmSampling() {
        isSamplingArmed = false
        consecutiveStableSamplingFrames = 0
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
    var test_hasAutomaticStepController: Bool { stepController != nil }

    func test_runSamplingTick() async {
        await runSamplingTick()
    }
#endif

    deinit {
        samplingTask?.cancel()
    }
}
