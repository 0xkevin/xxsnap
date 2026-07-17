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
        probePoints: [NSPoint]
    ) -> [ScrollCaptureTargetCandidate]
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

final class ScrollCaptureTargetDetector: ScrollCaptureTargetDetecting {
    static let minimumRegionSize = NSSize(width: 120, height: 120)

    private let candidateQuery: ScrollCaptureTargetCandidateQuerying
    private let candidateQueryQueue = DispatchQueue(
        label: "com.xxsnap.scroll-capture-target-detection",
        qos: .userInitiated
    )

    init(
        candidateQuery: ScrollCaptureTargetCandidateQuerying = AccessibilityScrollCaptureCandidateQuery()
    ) {
        self.candidateQuery = candidateQuery
    }

    func probePoints(in selection: NSRect) -> [NSPoint] {
        let selection = selection.standardized
        let fractions: [CGFloat] = [0.2, 0.5, 0.8]
        return fractions.flatMap { yFraction in
            fractions.map { xFraction in
                NSPoint(
                    x: selection.minX + selection.width * xFraction,
                    y: selection.minY + selection.height * yFraction
                )
            }
        }
    }

    func scrollableRegion(in selection: NSRect, processIdentifier: pid_t) async -> NSRect? {
        let selection = selection.standardized
        let probePoints = probePoints(in: selection)
        let queriedCandidates = await withCheckedContinuation { continuation in
            candidateQueryQueue.async { [candidateQuery] in
                continuation.resume(returning: candidateQuery.candidates(
                    processIdentifier: processIdentifier,
                    probePoints: probePoints
                ))
            }
        }
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
        quartzOriginY: CGFloat
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
        guard let quartzOriginY = quartzOriginYProvider(),
              quartzOriginY.isFinite,
              let application = accessibilityReader.application(
                  processIdentifier: processIdentifier
              ),
              accessibilityReader.setMessagingTimeout(
                  Self.messagingTimeout,
                  for: application
              )
        else {
            return []
        }

        var candidates: [ScrollCaptureTargetCandidate] = []
        var visitedElements: [ScrollCaptureAccessibilityElement] = []

        for (probeIndex, point) in probePoints.enumerated() {
            let quartzPoint = CGPoint(x: point.x, y: quartzOriginY - point.y)
            guard quartzPoint.x.isFinite,
                  quartzPoint.y.isFinite,
                  var element = accessibilityReader.element(
                      at: quartzPoint,
                      in: application
                  )
            else {
                continue
            }

            for depth in 0..<16 {
                if visitedElements.contains(where: {
                    accessibilityReader.elementsEqual($0, element)
                }) {
                    break
                }
                visitedElements.append(element)
                guard accessibilityReader.setMessagingTimeout(
                    Self.messagingTimeout,
                    for: element
                ) else {
                    return []
                }

                if let candidate = accessibilityReader.candidate(
                    from: element,
                    firstProbeIndex: probeIndex,
                    quartzOriginY: quartzOriginY
                ) {
                    candidates.append(candidate)
                }

                guard depth < 15,
                      let parent = accessibilityReader.parent(of: element)
                else {
                    break
                }
                element = parent
            }
        }
        return candidates
    }
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
        quartzOriginY: CGFloat
    ) -> ScrollCaptureTargetCandidate? {
        guard let owner = axElement(from: element),
              let scrollBar = Self.elementAttribute(
                  kAXVerticalScrollBarAttribute as CFString,
                  from: owner
              ),
              Self.setMessagingTimeout(
                  AccessibilityScrollCaptureCandidateQuery.messagingTimeout,
                  on: scrollBar
              ),
              let minimum = Self.numberAttribute(
                  kAXMinValueAttribute as CFString,
                  from: scrollBar
              ),
              let maximum = Self.numberAttribute(
                  kAXMaxValueAttribute as CFString,
                  from: scrollBar
              ),
              minimum.isFinite,
              maximum.isFinite,
              maximum > minimum,
              let position = Self.pointAttribute(kAXPositionAttribute as CFString, from: owner),
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
