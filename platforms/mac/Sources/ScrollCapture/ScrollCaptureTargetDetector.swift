import AppKit
import ApplicationServices

protocol ScrollCaptureTargetDetecting: AnyObject {
    func scrollableRegion(in selection: NSRect, processIdentifier: pid_t) async -> NSRect?
}

struct ScrollCaptureTargetCandidate: Equatable {
    let identity: CFHashCode
    let screenRect: NSRect
    let minimum: Double
    let maximum: Double
    let firstProbeIndex: Int
}

protocol ScrollCaptureTargetCandidateQuerying: Sendable {
    func candidates(
        processIdentifier: pid_t,
        probePoints: [NSPoint],
        context: ScrollCaptureTargetQueryContext
    ) -> [ScrollCaptureTargetCandidate]
}

protocol ScrollCaptureDeadlineCancellation: Sendable {
    func cancel()
}

protocol ScrollCaptureDeadlineScheduling: Sendable {
    func schedule(
        after interval: TimeInterval,
        action: @escaping @Sendable () -> Void
    ) -> ScrollCaptureDeadlineCancellation
}

private struct DispatchScrollCaptureDeadlineScheduler: ScrollCaptureDeadlineScheduling {
    private static let queue = DispatchQueue(
        label: "com.xxsnap.scroll-capture-target-deadline",
        qos: .userInitiated
    )

    func schedule(
        after interval: TimeInterval,
        action: @escaping @Sendable () -> Void
    ) -> ScrollCaptureDeadlineCancellation {
        let workItem = DispatchWorkItem(block: action)
        Self.queue.asyncAfter(deadline: .now() + max(0, interval), execute: workItem)
        return DispatchScrollCaptureDeadlineCancellation(workItem: workItem)
    }
}

private final class DispatchScrollCaptureDeadlineCancellation: ScrollCaptureDeadlineCancellation, @unchecked Sendable {
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        workItem.cancel()
    }
}

final class ScrollCaptureTargetQueryContext: @unchecked Sendable {
    typealias NowProvider = @Sendable () -> TimeInterval

    static let totalDetectionBudget: TimeInterval = 0.7

    private let lock = NSLock()
    private let deadline: TimeInterval
    private let nowProvider: NowProvider
    private var state = State.active

    private enum State {
        case active
        case cancelled
        case expired
    }

    init(
        totalBudget: TimeInterval = totalDetectionBudget,
        nowProvider: @escaping NowProvider = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.nowProvider = nowProvider
        deadline = nowProvider() + max(0, totalBudget)
    }

    var isCancelled: Bool {
        lock.withLock { state == .cancelled }
    }

    func shouldContinue() -> Bool {
        lock.withLock {
            guard state == .active else { return false }
            guard nowProvider() < deadline else {
                state = .expired
                return false
            }
            return true
        }
    }

    func cancel() {
        lock.withLock {
            guard state == .active else { return }
            state = .cancelled
        }
    }

    func expire() {
        lock.withLock {
            guard state == .active else { return }
            state = .expired
        }
    }
}

enum ScrollCaptureScreenCoordinates {
    static func appKitRect(
        quartzPosition: CGPoint,
        size: CGSize,
        quartzOriginY: CGFloat
    ) -> NSRect {
        NSRect(
            x: quartzPosition.x,
            y: quartzOriginY - quartzPosition.y - size.height,
            width: size.width,
            height: size.height
        )
    }
}

enum ScrollCaptureScrollbarStateValidator {
    static func isScrollable(
        enabled: Bool?,
        value: Double?,
        minimum: Double?,
        maximum: Double?
    ) -> Bool {
        guard enabled == true,
              let value,
              let minimum,
              let maximum,
              value.isFinite,
              minimum.isFinite,
              maximum.isFinite,
              maximum > minimum
        else {
            return false
        }
        return value >= minimum && value <= maximum
    }
}

final class ScrollCaptureTargetDetector: ScrollCaptureTargetDetecting {
    static let minimumRegionSize = NSSize(width: 120, height: 120)

    private let candidateQuery: ScrollCaptureTargetCandidateQuerying
    private let deadlineScheduler: ScrollCaptureDeadlineScheduling
    private let detectionTimeout: TimeInterval
    private let candidateQueryQueue = DispatchQueue(
        label: "com.xxsnap.scroll-capture-target-detection",
        qos: .userInitiated,
        attributes: .concurrent
    )

    init(
        candidateQuery: ScrollCaptureTargetCandidateQuerying = AccessibilityScrollCaptureCandidateQuery(),
        deadlineScheduler: ScrollCaptureDeadlineScheduling? = nil,
        detectionTimeout: TimeInterval = ScrollCaptureTargetQueryContext.totalDetectionBudget
    ) {
        self.candidateQuery = candidateQuery
        self.deadlineScheduler = deadlineScheduler ?? DispatchScrollCaptureDeadlineScheduler()
        self.detectionTimeout = detectionTimeout
    }

    func probePoints(in selection: NSRect) -> [NSPoint] {
        let selection = selection.standardized
        let fractions: [CGFloat] = [0.2, 0.5, 0.8]
        let grid = fractions.flatMap { yFraction in
            fractions.map { xFraction in
                NSPoint(
                    x: selection.minX + selection.width * xFraction,
                    y: selection.minY + selection.height * yFraction
                )
            }
        }
        let center = NSPoint(x: selection.midX, y: selection.midY)
        return [center] + grid.filter { $0 != center }
    }

    func scrollableRegion(in selection: NSRect, processIdentifier: pid_t) async -> NSRect? {
        guard !Task.isCancelled else { return nil }
        let context = ScrollCaptureTargetQueryContext(totalBudget: detectionTimeout)
        let selection = selection.standardized
        let probePoints = probePoints(in: selection)
        let request = ScrollCaptureTargetDetectionRequest(context: context)
        let deadlineCancellation = deadlineScheduler.schedule(after: detectionTimeout) {
            request.expire()
        }
        let queriedCandidates = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard request.install(continuation) else { return }
                candidateQueryQueue.async { [candidateQuery] in
                    request.complete(candidateQuery.candidates(
                        processIdentifier: processIdentifier,
                        probePoints: probePoints,
                        context: context
                    ))
                }
            }
        } onCancel: {
            request.cancel()
        }
        deadlineCancellation.cancel()
        guard let queriedCandidates, !Task.isCancelled else { return nil }
        let candidates = candidatesKeepingEarliestProbe(queriedCandidates)

        var best: RankedCandidate?
        for candidate in candidates where candidate.maximum > candidate.minimum {
            let intersection = selection.intersection(candidate.screenRect.standardized)
            guard !intersection.isNull,
                  intersection.width >= Self.minimumRegionSize.width,
                  intersection.height >= Self.minimumRegionSize.height
            else {
                continue
            }

            let ranked = RankedCandidate(
                intersection: intersection,
                firstProbeIndex: candidate.firstProbeIndex,
                selectionCenter: NSPoint(x: selection.midX, y: selection.midY)
            )
            if let bestCandidate = best {
                if ranked.isBetter(than: bestCandidate) {
                    best = ranked
                }
            } else {
                best = ranked
            }
        }
        return best?.intersection
    }

    private func candidatesKeepingEarliestProbe(
        _ candidates: [ScrollCaptureTargetCandidate]
    ) -> [ScrollCaptureTargetCandidate] {
        var positionsByIdentity: [CFHashCode: Int] = [:]
        var uniqueCandidates: [ScrollCaptureTargetCandidate] = []
        for candidate in candidates {
            if let position = positionsByIdentity[candidate.identity] {
                if candidate.firstProbeIndex < uniqueCandidates[position].firstProbeIndex {
                    uniqueCandidates[position] = candidate
                }
            } else {
                positionsByIdentity[candidate.identity] = uniqueCandidates.count
                uniqueCandidates.append(candidate)
            }
        }
        return uniqueCandidates
    }
}

private final class ScrollCaptureTargetDetectionRequest: @unchecked Sendable {
    private let lock = NSLock()
    private let context: ScrollCaptureTargetQueryContext
    private var isResolved = false
    private var result: [ScrollCaptureTargetCandidate]?
    private var continuation: CheckedContinuation<[ScrollCaptureTargetCandidate]?, Never>?

    init(context: ScrollCaptureTargetQueryContext) {
        self.context = context
    }

    func install(
        _ continuation: CheckedContinuation<[ScrollCaptureTargetCandidate]?, Never>
    ) -> Bool {
        lock.lock()
        guard !isResolved else {
            let result = result
            lock.unlock()
            continuation.resume(returning: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func complete(_ candidates: [ScrollCaptureTargetCandidate]) {
        resolve {
            guard context.shouldContinue() else {
                context.expire()
                return nil
            }
            return candidates
        }
    }

    func cancel() {
        resolve {
            context.cancel()
            return nil
        }
    }

    func expire() {
        resolve {
            context.expire()
            return nil
        }
    }

    private func resolve(
        with resultProvider: () -> [ScrollCaptureTargetCandidate]?
    ) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        let result = resultProvider()
        isResolved = true
        self.result = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

private struct RankedCandidate {
    let intersection: NSRect
    let firstProbeIndex: Int
    let centerDistanceSquared: CGFloat

    init(intersection: NSRect, firstProbeIndex: Int, selectionCenter: NSPoint) {
        self.intersection = intersection
        self.firstProbeIndex = firstProbeIndex
        let deltaX = intersection.midX - selectionCenter.x
        let deltaY = intersection.midY - selectionCenter.y
        centerDistanceSquared = deltaX * deltaX + deltaY * deltaY
    }

    func isBetter(than other: RankedCandidate) -> Bool {
        let area = intersection.width * intersection.height
        let otherArea = other.intersection.width * other.intersection.height
        if area != otherArea {
            return area > otherArea
        }
        if intersection.height != other.intersection.height {
            return intersection.height > other.intersection.height
        }
        if centerDistanceSquared != other.centerDistanceSquared {
            return centerDistanceSquared < other.centerDistanceSquared
        }
        return firstProbeIndex < other.firstProbeIndex
    }
}

struct ScrollCaptureAccessibilityElement: @unchecked Sendable {
    let rawValue: AnyObject
}

protocol ScrollCaptureAccessibilityReading: Sendable {
    func application(processIdentifier: pid_t) -> ScrollCaptureAccessibilityElement?
    func setMessagingTimeout(
        _ timeout: Float,
        for element: ScrollCaptureAccessibilityElement
    ) -> Bool
    func element(
        at quartzPoint: CGPoint,
        in application: ScrollCaptureAccessibilityElement
    ) -> ScrollCaptureAccessibilityElement?
    func parent(of element: ScrollCaptureAccessibilityElement) -> ScrollCaptureAccessibilityElement?
    func candidate(
        from element: ScrollCaptureAccessibilityElement,
        firstProbeIndex: Int,
        quartzOriginY: CGFloat,
        context: ScrollCaptureTargetQueryContext
    ) -> ScrollCaptureTargetCandidate?
    func elementsEqual(
        _ lhs: ScrollCaptureAccessibilityElement,
        _ rhs: ScrollCaptureAccessibilityElement
    ) -> Bool
}

struct AccessibilityScrollCaptureCandidateQuery: ScrollCaptureTargetCandidateQuerying {
    typealias QuartzOriginYProvider = @Sendable () -> CGFloat?

    static let messagingTimeout: Float = 0.15

    private let quartzOriginYProvider: QuartzOriginYProvider
    private let accessibilityReader: ScrollCaptureAccessibilityReading

    init(
        quartzOriginYProvider: @escaping QuartzOriginYProvider = {
            NSScreen.screens.first?.frame.maxY
        },
        accessibilityReader: ScrollCaptureAccessibilityReading = SystemScrollCaptureAccessibilityReader()
    ) {
        self.quartzOriginYProvider = quartzOriginYProvider
        self.accessibilityReader = accessibilityReader
    }

    func candidates(
        processIdentifier: pid_t,
        probePoints: [NSPoint]
    ) -> [ScrollCaptureTargetCandidate] {
        candidates(
            processIdentifier: processIdentifier,
            probePoints: probePoints,
            context: ScrollCaptureTargetQueryContext()
        )
    }

    func candidates(
        processIdentifier: pid_t,
        probePoints: [NSPoint],
        context: ScrollCaptureTargetQueryContext
    ) -> [ScrollCaptureTargetCandidate] {
        guard context.shouldContinue(),
              let quartzOriginY = quartzOriginYProvider(),
              quartzOriginY.isFinite,
              let application = accessibilityReader.application(
                  processIdentifier: processIdentifier
              ),
              context.shouldContinue(),
              accessibilityReader.setMessagingTimeout(
                  Self.messagingTimeout,
                  for: application
              )
        else {
            return []
        }

        var candidates: [ScrollCaptureTargetCandidate] = []
        var elementCache: [ScrollCaptureAccessibilityCacheEntry] = []

        for (probeIndex, point) in probePoints.enumerated() {
            guard context.shouldContinue() else { return candidates }
            let quartzPoint = CGPoint(x: point.x, y: quartzOriginY - point.y)
            guard quartzPoint.x.isFinite,
                  quartzPoint.y.isFinite,
                  context.shouldContinue(),
                  var element = accessibilityReader.element(
                      at: quartzPoint,
                      in: application
                  )
            else {
                continue
            }

            var currentProbeElements: [ScrollCaptureAccessibilityElement] = []
            for depth in 0..<16 {
                guard context.shouldContinue() else { return candidates }
                if currentProbeElements.contains(where: {
                    accessibilityReader.elementsEqual($0, element)
                }) {
                    break
                }
                currentProbeElements.append(element)

                let cacheIndex: Int
                if let existingIndex = elementCache.firstIndex(where: {
                    accessibilityReader.elementsEqual($0.element, element)
                }) {
                    cacheIndex = existingIndex
                } else {
                    guard context.shouldContinue() else { return candidates }
                    guard accessibilityReader.setMessagingTimeout(
                        Self.messagingTimeout,
                        for: element
                    ) else {
                        return []
                    }
                    cacheIndex = elementCache.count
                    elementCache.append(ScrollCaptureAccessibilityCacheEntry(element: element))
                }

                if !elementCache[cacheIndex].candidateWasRead {
                    guard context.shouldContinue() else { return candidates }
                    let candidate = accessibilityReader.candidate(
                        from: element,
                        firstProbeIndex: probeIndex,
                        quartzOriginY: quartzOriginY,
                        context: context
                    )
                    elementCache[cacheIndex].candidate = candidate
                    elementCache[cacheIndex].candidateWasRead = true
                    if let candidate {
                        candidates.append(candidate)
                    }
                }

                guard depth < 15 else {
                    break
                }
                let parent: ScrollCaptureAccessibilityElement?
                if elementCache[cacheIndex].parentWasRead {
                    parent = elementCache[cacheIndex].parent
                } else {
                    guard context.shouldContinue() else { return candidates }
                    let readParent = accessibilityReader.parent(of: element)
                    elementCache[cacheIndex].parent = readParent
                    elementCache[cacheIndex].parentWasRead = true
                    parent = readParent
                }
                guard let parent else { break }
                element = parent
            }
            if !candidates.isEmpty {
                return candidates
            }
        }
        return candidates
    }
}

private struct ScrollCaptureAccessibilityCacheEntry {
    let element: ScrollCaptureAccessibilityElement
    var candidateWasRead = false
    var candidate: ScrollCaptureTargetCandidate?
    var parentWasRead = false
    var parent: ScrollCaptureAccessibilityElement?
}

private struct SystemScrollCaptureAccessibilityReader: ScrollCaptureAccessibilityReading {
    func application(processIdentifier: pid_t) -> ScrollCaptureAccessibilityElement? {
        ScrollCaptureAccessibilityElement(
            rawValue: AXUIElementCreateApplication(processIdentifier)
        )
    }

    func setMessagingTimeout(
        _ timeout: Float,
        for element: ScrollCaptureAccessibilityElement
    ) -> Bool {
        guard let element = axElement(from: element) else { return false }
        return Self.setMessagingTimeout(timeout, on: element)
    }

    func element(
        at quartzPoint: CGPoint,
        in application: ScrollCaptureAccessibilityElement
    ) -> ScrollCaptureAccessibilityElement? {
        guard let application = axElement(from: application) else { return nil }
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            application,
            Float(quartzPoint.x),
            Float(quartzPoint.y),
            &hitElement
        ) == .success, let hitElement else {
            return nil
        }
        return ScrollCaptureAccessibilityElement(rawValue: hitElement)
    }

    func parent(
        of element: ScrollCaptureAccessibilityElement
    ) -> ScrollCaptureAccessibilityElement? {
        guard let element = axElement(from: element),
              let parent = Self.elementAttribute(kAXParentAttribute as CFString, from: element)
        else {
            return nil
        }
        return ScrollCaptureAccessibilityElement(rawValue: parent)
    }

    func candidate(
        from element: ScrollCaptureAccessibilityElement,
        firstProbeIndex: Int,
        quartzOriginY: CGFloat,
        context: ScrollCaptureTargetQueryContext
    ) -> ScrollCaptureTargetCandidate? {
        guard context.shouldContinue(),
              let owner = axElement(from: element),
              context.shouldContinue(),
              let scrollBar = Self.elementAttribute(
                  kAXVerticalScrollBarAttribute as CFString,
                  from: owner
              ),
              context.shouldContinue(),
              Self.setMessagingTimeout(
                  AccessibilityScrollCaptureCandidateQuery.messagingTimeout,
                  on: scrollBar
              ),
              context.shouldContinue(),
              let minimum = Self.numberAttribute(
                  kAXMinValueAttribute as CFString,
                  from: scrollBar
              ),
              context.shouldContinue(),
              let maximum = Self.numberAttribute(
                  kAXMaxValueAttribute as CFString,
                  from: scrollBar
              ),
              context.shouldContinue(),
              let enabled = Self.booleanAttribute(
                  kAXEnabledAttribute as CFString,
                  from: scrollBar
              ),
              context.shouldContinue(),
              let value = Self.numberAttribute(
                  kAXValueAttribute as CFString,
                  from: scrollBar
              ),
              ScrollCaptureScrollbarStateValidator.isScrollable(
                  enabled: enabled,
                  value: value,
                  minimum: minimum,
                  maximum: maximum
              ),
              context.shouldContinue(),
              let position = Self.pointAttribute(kAXPositionAttribute as CFString, from: owner),
              context.shouldContinue(),
              let size = Self.sizeAttribute(kAXSizeAttribute as CFString, from: owner),
              position.x.isFinite,
              position.y.isFinite,
              size.width.isFinite,
              size.height.isFinite
        else {
            return nil
        }

        return ScrollCaptureTargetCandidate(
            identity: CFHash(owner),
            screenRect: ScrollCaptureScreenCoordinates.appKitRect(
                quartzPosition: position,
                size: size,
                quartzOriginY: quartzOriginY
            ),
            minimum: minimum,
            maximum: maximum,
            firstProbeIndex: firstProbeIndex
        )
    }

    func elementsEqual(
        _ lhs: ScrollCaptureAccessibilityElement,
        _ rhs: ScrollCaptureAccessibilityElement
    ) -> Bool {
        CFEqual(lhs.rawValue, rhs.rawValue)
    }

    private func axElement(
        from element: ScrollCaptureAccessibilityElement
    ) -> AXUIElement? {
        guard CFGetTypeID(element.rawValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(element.rawValue, to: AXUIElement.self)
    }

    private static func setMessagingTimeout(
        _ timeout: Float,
        on element: AXUIElement
    ) -> Bool {
        AXUIElementSetMessagingTimeout(element, timeout) == .success
    }

    private static func copiedAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private static func elementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard let value = copiedAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func numberAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> Double? {
        (copiedAttribute(attribute, from: element) as? NSNumber)?.doubleValue
    }

    private static func booleanAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> Bool? {
        (copiedAttribute(attribute, from: element) as? NSNumber)?.boolValue
    }

    private static func pointAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> CGPoint? {
        guard let value = copiedAttribute(attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint,
              AXValueGetValue(axValue, .cgPoint, &point)
        else {
            return nil
        }
        return point
    }

    private static func sizeAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> CGSize? {
        guard let value = copiedAttribute(attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize,
              AXValueGetValue(axValue, .cgSize, &size)
        else {
            return nil
        }
        return size
    }
}
