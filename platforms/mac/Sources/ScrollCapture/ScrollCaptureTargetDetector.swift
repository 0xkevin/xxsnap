import AppKit
import ApplicationServices

protocol ScrollCaptureTargetDetecting: AnyObject {
    func scrollableRegion(in selection: NSRect, processIdentifier: pid_t) -> NSRect?
}

struct ScrollCaptureTargetCandidate: Equatable {
    let identity: CFHashCode
    let screenRect: NSRect
    let minimum: Double
    let maximum: Double
    let firstProbeIndex: Int
}

protocol ScrollCaptureTargetCandidateQuerying {
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

    func scrollableRegion(in selection: NSRect, processIdentifier: pid_t) -> NSRect? {
        let selection = selection.standardized
        let queriedCandidates = candidateQuery.candidates(
            processIdentifier: processIdentifier,
            probePoints: probePoints(in: selection)
        )
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

struct AccessibilityScrollCaptureCandidateQuery: ScrollCaptureTargetCandidateQuerying {
    typealias QuartzOriginYProvider = () -> CGFloat?

    private let quartzOriginYProvider: QuartzOriginYProvider

    init(
        quartzOriginYProvider: @escaping QuartzOriginYProvider = {
            NSScreen.screens.first?.frame.maxY
        }
    ) {
        self.quartzOriginYProvider = quartzOriginYProvider
    }

    func candidates(
        processIdentifier: pid_t,
        probePoints: [NSPoint]
    ) -> [ScrollCaptureTargetCandidate] {
        guard let quartzOriginY = quartzOriginYProvider(), quartzOriginY.isFinite else {
            return []
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        var candidates: [ScrollCaptureTargetCandidate] = []
        var seenIdentities: Set<CFHashCode> = []

        for (probeIndex, point) in probePoints.enumerated() {
            let quartzPoint = CGPoint(x: point.x, y: quartzOriginY - point.y)
            guard quartzPoint.x.isFinite, quartzPoint.y.isFinite else { continue }

            var hitElement: AXUIElement?
            guard AXUIElementCopyElementAtPosition(
                application,
                Float(quartzPoint.x),
                Float(quartzPoint.y),
                &hitElement
            ) == .success, var element = hitElement else {
                continue
            }

            for depth in 0..<16 {
                if let candidate = candidate(
                    from: element,
                    firstProbeIndex: probeIndex,
                    quartzOriginY: quartzOriginY
                ), seenIdentities.insert(candidate.identity).inserted {
                    candidates.append(candidate)
                }

                guard depth < 15,
                      let parent = Self.elementAttribute(
                          kAXParentAttribute as CFString,
                          from: element
                      )
                else {
                    break
                }
                element = parent
            }
        }
        return candidates
    }

    private func candidate(
        from owner: AXUIElement,
        firstProbeIndex: Int,
        quartzOriginY: CGFloat
    ) -> ScrollCaptureTargetCandidate? {
        guard let scrollBar = Self.elementAttribute(
            kAXVerticalScrollBarAttribute as CFString,
            from: owner
        ),
        let minimum = Self.numberAttribute(kAXMinValueAttribute as CFString, from: scrollBar),
        let maximum = Self.numberAttribute(kAXMaxValueAttribute as CFString, from: scrollBar),
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
