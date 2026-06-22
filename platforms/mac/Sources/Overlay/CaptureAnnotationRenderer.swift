import AppKit

enum CaptureCompletionAction {
    case copy
    case save
}

enum CaptureAnnotationKind {
    case rectangle
    case ellipse
    case arrowLine
    case brush
}

enum CaptureArrowType: Int, CaseIterable {
    case none
    case bar
    case dot
    case diamond
    case normal
    case solidArrow
    case hollowArrow

    static let allCases: [CaptureArrowType] = [
        .none,
        .normal,
        .solidArrow,
        .hollowArrow,
        .diamond,
        .bar,
        .dot,
    ]

    var title: String {
        switch self {
        case .none:
            return "没有箭头的实线"
        case .bar:
            return "端帽箭头线"
        case .dot:
            return "圆点箭头线"
        case .diamond:
            return "菱形箭头线"
        case .normal:
            return "普通箭头线"
        case .solidArrow:
            return "实心箭头线"
        case .hollowArrow:
            return "空心箭头线"
        }
    }
}

struct CaptureArrowLine: Equatable {
    var start: NSPoint
    var end: NSPoint
    var control: NSPoint
    var startArrowType: CaptureArrowType
    var endArrowType: CaptureArrowType

    var boundingRect: NSRect {
        let minX = min(start.x, end.x, control.x)
        let maxX = max(start.x, end.x, control.x)
        let minY = min(start.y, end.y, control.y)
        let maxY = max(start.y, end.y, control.y)
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

struct CaptureBrushPath: Equatable {
    var points: [NSPoint]

    var boundingRect: NSRect {
        guard let first = points.first else {
            return .zero
        }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

struct CaptureArrowVectorTemplate {
    let subpaths: [[CGPoint]]
    let evenOddFill: Bool
}

enum CaptureArrowVectorGeometry {
    // Points copied from arrow-filled2.svg and arrow-hollow2.svg.
    private static let arrowFilled2TipX: CGFloat = 20
    private static let arrowFilled2TailX: CGFloat = 4
    private static let arrowFilled2AxisY: CGFloat = 12.0457356
    private static let arrowFilled2Polygon = [
        CGPoint(x: 12.979733, y: 14.0133576),
        CGPoint(x: 11.9712417, y: 16.0147138),
        CGPoint(x: 20, y: 12.0457356),
        CGPoint(x: 11.9712417, y: 8.01471379),
        CGPoint(x: 12.979733, y: 10.0250492),
        CGPoint(x: 4, y: 12.0457356),
    ]
    private static let hollowArrowMiterLimit: CGFloat = 4
    private static let hollowArrowTailMiterLimit: CGFloat = 24
    private static let hollowArrowTailCapX: CGFloat = 5.2

    static func bodyInset(for type: CaptureArrowType, strokeWidth: CGFloat) -> CGFloat {
        guard isVectorArrow(type) else {
            return 0
        }
        return 16 * max(0.8, strokeWidth / 2)
    }

    static func isVectorArrow(_ type: CaptureArrowType) -> Bool {
        switch type {
        case .solidArrow, .hollowArrow:
            return true
        case .none, .bar, .dot, .diamond, .normal:
            return false
        }
    }

    static func normalArrowHeadInset(for strokeWidth: CGFloat) -> CGFloat {
        min(
            max(18, strokeWidth * 4.6) * 0.62,
            (arrowFilled2TipX - 11.45) * max(0.8, strokeWidth / 2)
        )
    }

    static func cgPath(
        for type: CaptureArrowType,
        tip: CGPoint,
        direction: CGVector,
        scale: CGFloat,
        minimumTemplateX: CGFloat? = nil
    ) -> (path: CGPath, evenOddFill: Bool)? {
        if type == .hollowArrow, minimumTemplateX == nil {
            guard let path = hollowArrowFilled2Path(tip: tip, direction: direction, scale: scale) else {
                return nil
            }
            return (path, false)
        }

        guard let template = template(for: type, minimumTemplateX: minimumTemplateX) else {
            return nil
        }

        let path = CGMutablePath()
        guard let transform = transform(tip: tip, direction: direction, scale: scale) else {
            return nil
        }

        for subpath in template.subpaths {
            guard let first = subpath.first else {
                continue
            }
            path.move(to: transform(first))
            subpath.dropFirst().forEach { path.addLine(to: transform($0)) }
            path.closeSubpath()
        }

        return (path, template.evenOddFill)
    }

    static func bezierPath(
        for type: CaptureArrowType,
        tip: NSPoint,
        direction: CGVector,
        scale: CGFloat,
        minimumTemplateX: CGFloat? = nil
    ) -> (path: NSBezierPath, evenOddFill: Bool)? {
        if type == .hollowArrow, minimumTemplateX == nil {
            guard let cgResult = cgPath(
                for: type,
                tip: tip,
                direction: direction,
                scale: scale,
                minimumTemplateX: minimumTemplateX
            ) else {
                return nil
            }
            let path = NSBezierPath(cgPath: cgResult.path)
            path.windingRule = cgResult.evenOddFill ? .evenOdd : .nonZero
            return (path, cgResult.evenOddFill)
        }

        guard let template = template(for: type, minimumTemplateX: minimumTemplateX) else {
            return nil
        }

        let path = NSBezierPath()
        guard let transform = transform(tip: tip, direction: direction, scale: scale) else {
            return nil
        }

        for subpath in template.subpaths {
            guard let first = subpath.first else {
                continue
            }
            path.move(to: transform(first))
            subpath.dropFirst().forEach { path.line(to: transform($0)) }
            path.close()
        }

        path.windingRule = template.evenOddFill ? .evenOdd : .nonZero
        return (path, template.evenOddFill)
    }

    static func cgPathAlongCurve(
        for type: CaptureArrowType,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        strokeWidth: CGFloat
    ) -> (path: CGPath, evenOddFill: Bool)? {
        switch type {
        case .solidArrow:
            guard let path = stretchedArrowFilled2Path(start: start, control: control, end: end, strokeWidth: strokeWidth) else {
                return nil
            }
            return (path, false)
        case .hollowArrow:
            guard let path = stretchedHollowArrowFilled2Path(start: start, control: control, end: end, strokeWidth: strokeWidth) else {
                return nil
            }
            return (path, false)
        case .none, .bar, .dot, .diamond, .normal:
            return nil
        }
    }

    static func bezierPathAlongCurve(
        for type: CaptureArrowType,
        start: NSPoint,
        control: NSPoint,
        end: NSPoint,
        strokeWidth: CGFloat
    ) -> (path: NSBezierPath, evenOddFill: Bool)? {
        guard let cgResult = cgPathAlongCurve(
            for: type,
            start: start,
            control: control,
            end: end,
            strokeWidth: strokeWidth
        ) else {
            return nil
        }

        let path = NSBezierPath(cgPath: cgResult.path)
        path.windingRule = cgResult.evenOddFill ? .evenOdd : .nonZero
        return (path, cgResult.evenOddFill)
    }

    private static func template(for type: CaptureArrowType, minimumTemplateX: CGFloat?) -> CaptureArrowVectorTemplate? {
        let template: CaptureArrowVectorTemplate?
        switch type {
        case .normal:
            template = CaptureArrowVectorTemplate(
                subpaths: [[
                    CGPoint(x: 12, y: 8),
                    CGPoint(x: 20, y: 12),
                    CGPoint(x: 12, y: 16),
                    CGPoint(x: 13.4784, y: 13),
                    CGPoint(x: 4, y: 13),
                    CGPoint(x: 4, y: 11),
                    CGPoint(x: 13.4784, y: 11),
                ]],
                evenOddFill: true
            )
        case .solidArrow:
            template = CaptureArrowVectorTemplate(
                subpaths: [arrowFilled2Polygon],
                evenOddFill: false
            )
        case .hollowArrow:
            template = CaptureArrowVectorTemplate(
                subpaths: [arrowFilled2Polygon],
                evenOddFill: false
            )
        case .none, .bar, .dot, .diamond:
            template = nil
        }

        guard let template else {
            return nil
        }
        guard let minimumTemplateX else {
            return template
        }

        let clippedSubpaths = template.subpaths.compactMap { clippedSubpath($0, minimumX: minimumTemplateX) }
        guard !clippedSubpaths.isEmpty else {
            return nil
        }
        return CaptureArrowVectorTemplate(subpaths: clippedSubpaths, evenOddFill: template.evenOddFill)
    }

    private struct CurveFrame {
        let point: CGPoint
        let tangent: CGVector
        let distance: CGFloat
    }

    private struct SpecialArrowMetrics {
        let tailHalfWidth: CGFloat
        let neckHalfWidth: CGFloat
        let shoulderHalfWidth: CGFloat
        let headLength: CGFloat
        let notchInsetFromTip: CGFloat
        let outlineWidth: CGFloat
    }

    private static func specialArrowMetrics(strokeWidth: CGFloat) -> SpecialArrowMetrics {
        let tailHalfWidth = max(0.35, strokeWidth * 0.10)
        let neckHalfWidth = max(5.2, strokeWidth * 1.20)
        let shoulderHalfWidth = max(11.4, strokeWidth * 2.75)
        let headLength = max(24, strokeWidth * 5.6)
        return SpecialArrowMetrics(
            tailHalfWidth: tailHalfWidth,
            neckHalfWidth: neckHalfWidth,
            shoulderHalfWidth: shoulderHalfWidth,
            headLength: headLength,
            notchInsetFromTip: headLength * 0.55,
            outlineWidth: min(neckHalfWidth - 0.7, max(2.2, strokeWidth * 0.85))
        )
    }

    private static func transform(
        tip: CGPoint,
        direction: CGVector,
        scale: CGFloat
    ) -> ((CGPoint) -> CGPoint)? {
        let length = hypot(direction.dx, direction.dy)
        guard length > 0.0001 else {
            return nil
        }

        let unit = CGVector(dx: direction.dx / length, dy: direction.dy / length)
        let perpendicular = CGVector(dx: -unit.dy, dy: unit.dx)

        return { point in
            let back = (20 - point.x) * scale
            let offset = (point.y - 12) * scale
            return CGPoint(
                x: tip.x - unit.dx * back + perpendicular.dx * offset,
                y: tip.y - unit.dy * back + perpendicular.dy * offset
            )
        }
    }

    private static func transformedArrowFilled2Polygon(
        tip: CGPoint,
        direction: CGVector,
        scale: CGFloat
    ) -> CGPath? {
        guard let transform = transform(tip: tip, direction: direction, scale: scale) else {
            return nil
        }
        return polygonPath(points: arrowFilled2Polygon.map(transform))
    }

    private static func hollowArrowFilled2Path(
        tip: CGPoint,
        direction: CGVector,
        scale: CGFloat
    ) -> CGPath? {
        guard let transform = transform(tip: tip, direction: direction, scale: scale) else {
            return nil
        }
        guard let outline = polygonPath(points: arrowFilled2Polygon.map(transform)) else {
            return nil
        }
        return outline.copy(
            strokingWithWidth: max(0.5, 0.5 * scale),
            lineCap: .butt,
            lineJoin: .miter,
            miterLimit: hollowArrowMiterLimit
        )
    }

    private static func stretchedArrowFilled2Path(
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        strokeWidth: CGFloat
    ) -> CGPath? {
        let frames = sampledCurveFrames(start: start, control: control, end: end)
        guard let last = frames.last, last.distance > 0.001 else {
            return nil
        }

        let totalDistance = last.distance
        let scale = min(max(0.8, strokeWidth / 2), max(0.2, totalDistance / (arrowFilled2TipX - arrowFilled2TailX)))
        let upperBodyEdge = sampledArrowFilled2BodyEdge(
            to: arrowFilled2Polygon[0],
            frames: frames,
            totalDistance: totalDistance,
            scale: scale,
            insetScale: 1
        )
        let lowerBodyEdge = sampledArrowFilled2BodyEdge(
            to: arrowFilled2Polygon[4],
            frames: frames,
            totalDistance: totalDistance,
            scale: scale,
            insetScale: 1
        )
        guard let first = upperBodyEdge.first else {
            return nil
        }

        let path = CGMutablePath()
        path.move(to: first)
        upperBodyEdge.dropFirst().forEach { path.addLine(to: $0) }
        [arrowFilled2Polygon[1], arrowFilled2Polygon[2], arrowFilled2Polygon[3]].forEach { point in
            path.addLine(to: stretchedArrowFilled2Point(point, frames: frames, totalDistance: totalDistance, scale: scale, insetScale: 1))
        }
        lowerBodyEdge.reversed().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private static func stretchedHollowArrowFilled2Path(
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        strokeWidth: CGFloat
    ) -> CGPath? {
        let frames = sampledCurveFrames(start: start, control: control, end: end)
        guard let last = frames.last, last.distance > 0.001 else {
            return nil
        }

        guard let outline = stretchedArrowFilled2Path(start: start, control: control, end: end, strokeWidth: strokeWidth)?.copy(
            strokingWithWidth: max(1, strokeWidth * 0.5),
            lineCap: .butt,
            lineJoin: .miter,
            miterLimit: hollowArrowTailMiterLimit
        ) else {
            return nil
        }

        let path = CGMutablePath()
        path.addPath(outline)
        if let tailCap = clippedSubpath(arrowFilled2Polygon, maximumX: hollowArrowTailCapX) {
            let totalDistance = last.distance
            let scale = min(max(0.8, strokeWidth / 2), max(0.2, totalDistance / (arrowFilled2TipX - arrowFilled2TailX)))
            appendStretchedArrowFilled2Subpath(
                to: path,
                points: tailCap,
                frames: frames,
                totalDistance: totalDistance,
                scale: scale,
                insetScale: 1
            )
        }
        return path
    }

    private static func appendStretchedArrowFilled2Subpath(
        to path: CGMutablePath,
        frames: [CurveFrame],
        totalDistance: CGFloat,
        scale: CGFloat,
        insetScale: CGFloat
    ) {
        let upperBodyEdge = sampledArrowFilled2BodyEdge(
            to: arrowFilled2Polygon[0],
            frames: frames,
            totalDistance: totalDistance,
            scale: scale,
            insetScale: insetScale
        )
        let lowerBodyEdge = sampledArrowFilled2BodyEdge(
            to: arrowFilled2Polygon[4],
            frames: frames,
            totalDistance: totalDistance,
            scale: scale,
            insetScale: insetScale
        )
        guard let first = upperBodyEdge.first else {
            return
        }

        path.move(to: first)
        upperBodyEdge.dropFirst().forEach { path.addLine(to: $0) }
        [arrowFilled2Polygon[1], arrowFilled2Polygon[2], arrowFilled2Polygon[3]].forEach { point in
            path.addLine(to: stretchedArrowFilled2Point(point, frames: frames, totalDistance: totalDistance, scale: scale, insetScale: insetScale))
        }
        lowerBodyEdge.reversed().forEach { path.addLine(to: $0) }
        path.closeSubpath()
    }

    private static func appendStretchedArrowFilled2Subpath(
        to path: CGMutablePath,
        points: [CGPoint],
        frames: [CurveFrame],
        totalDistance: CGFloat,
        scale: CGFloat,
        insetScale: CGFloat
    ) {
        guard let first = points.first else {
            return
        }

        path.move(to: stretchedArrowFilled2Point(first, frames: frames, totalDistance: totalDistance, scale: scale, insetScale: insetScale))
        points.dropFirst().forEach { point in
            path.addLine(to: stretchedArrowFilled2Point(point, frames: frames, totalDistance: totalDistance, scale: scale, insetScale: insetScale))
        }
        path.closeSubpath()
    }

    private static func sampledArrowFilled2BodyEdge(
        to bodyPoint: CGPoint,
        frames: [CurveFrame],
        totalDistance: CGFloat,
        scale: CGFloat,
        insetScale: CGFloat
    ) -> [CGPoint] {
        let bodyDistanceFromEnd = min(totalDistance, (arrowFilled2TipX - bodyPoint.x) * scale)
        let bodyDistance = max(0, totalDistance - bodyDistanceFromEnd)
        let sampleCount = max(12, Int(ceil(bodyDistance / 6)))

        return (0...sampleCount).map { index in
            let progress = CGFloat(index) / CGFloat(sampleCount)
            let frame = interpolatedFrame(at: bodyDistance * progress, frames: frames)
            let normal = CGVector(dx: -frame.tangent.dy, dy: frame.tangent.dx)
            let templateY = arrowFilled2AxisY + (bodyPoint.y - arrowFilled2AxisY) * progress
            let offset = (templateY - arrowFilled2AxisY) * scale * insetScale
            return CGPoint(
                x: frame.point.x + normal.dx * offset,
                y: frame.point.y + normal.dy * offset
            )
        }
    }

    private static func stretchedArrowFilled2Point(
        _ point: CGPoint,
        frames: [CurveFrame],
        totalDistance: CGFloat,
        scale: CGFloat,
        insetScale: CGFloat
    ) -> CGPoint {
        let distanceFromEnd = min(totalDistance, (arrowFilled2TipX - point.x) * scale)
        let frame = interpolatedFrame(at: max(0, totalDistance - distanceFromEnd), frames: frames)
        let normal = CGVector(dx: -frame.tangent.dy, dy: frame.tangent.dx)
        let offset = (point.y - arrowFilled2AxisY) * scale * insetScale
        return CGPoint(
            x: frame.point.x + normal.dx * offset,
            y: frame.point.y + normal.dy * offset
        )
    }

    private static func appendArrowFilled2Subpath(
        to path: CGMutablePath,
        transform: (CGPoint) -> CGPoint,
        insetScale: CGFloat
    ) {
        guard let first = arrowFilled2Polygon.first else {
            return
        }
        func inset(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: point.x,
                y: arrowFilled2AxisY + (point.y - arrowFilled2AxisY) * insetScale
            )
        }

        path.move(to: transform(inset(first)))
        arrowFilled2Polygon.dropFirst().forEach { path.addLine(to: transform(inset($0))) }
        path.closeSubpath()
    }

    private static func polygonPath(points: [CGPoint]) -> CGPath? {
        guard let first = points.first else {
            return nil
        }

        let path = CGMutablePath()
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private static func curveMapper(
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        transverseScale: CGFloat
    ) -> ((CGPoint) -> CGPoint)? {
        let templatePoints = [
            CGPoint(x: 3.99292919, y: 12),
            CGPoint(x: 19.9929292, y: 12),
        ]
        let minTemplateX = templatePoints.map(\.x).min() ?? 4
        let maxTemplateX = templatePoints.map(\.x).max() ?? 20
        let frames = sampledCurveFrames(start: start, control: control, end: end)
        guard let totalDistance = frames.last?.distance, totalDistance > 0.001 else {
            return nil
        }

        return { point in
            let progress = min(1, max(0, (point.x - minTemplateX) / max(0.001, maxTemplateX - minTemplateX)))
            let targetDistance = totalDistance * progress
            let frame = interpolatedFrame(at: targetDistance, frames: frames)
            let normal = CGVector(dx: -frame.tangent.dy, dy: frame.tangent.dx)
            let offset = (point.y - 12) * transverseScale
            return CGPoint(
                x: frame.point.x + normal.dx * offset,
                y: frame.point.y + normal.dy * offset
            )
        }
    }

    private static func sampledCurveFrames(
        start: CGPoint,
        control: CGPoint,
        end: CGPoint
    ) -> [CurveFrame] {
        let chord = hypot(end.x - start.x, end.y - start.y)
        let controlSpan = hypot(control.x - start.x, control.y - start.y) + hypot(end.x - control.x, end.y - control.y)
        let estimate = max(chord, controlSpan)
        let steps = max(32, Int(ceil(estimate / 3)))
        var frames: [CurveFrame] = []
        frames.reserveCapacity(steps + 1)

        var previous = start
        var distance: CGFloat = 0
        for index in 0...steps {
            let t = CGFloat(index) / CGFloat(steps)
            let point = quadraticPoint(start: start, control: control, end: end, t: t)
            if index > 0 {
                distance += hypot(point.x - previous.x, point.y - previous.y)
            }
            let tangent = normalizedVector(quadraticDerivative(start: start, control: control, end: end, t: t))
                ?? normalizedVector(CGVector(dx: end.x - start.x, dy: end.y - start.y))
                ?? CGVector(dx: 1, dy: 0)
            frames.append(CurveFrame(point: point, tangent: tangent, distance: distance))
            previous = point
        }
        return frames
    }

    private static func interpolatedFrame(at targetDistance: CGFloat, frames: [CurveFrame]) -> CurveFrame {
        guard let first = frames.first, let last = frames.last else {
            return CurveFrame(point: .zero, tangent: CGVector(dx: 1, dy: 0), distance: 0)
        }
        if targetDistance <= 0 {
            return first
        }
        if targetDistance >= last.distance {
            return last
        }

        for index in 1..<frames.count {
            let current = frames[index]
            let previous = frames[index - 1]
            if current.distance >= targetDistance {
                let span = max(0.001, current.distance - previous.distance)
                let t = (targetDistance - previous.distance) / span
                let point = CGPoint(
                    x: previous.point.x + (current.point.x - previous.point.x) * t,
                    y: previous.point.y + (current.point.y - previous.point.y) * t
                )
                let tangent = normalizedVector(CGVector(
                    dx: previous.tangent.dx + (current.tangent.dx - previous.tangent.dx) * t,
                    dy: previous.tangent.dy + (current.tangent.dy - previous.tangent.dy) * t
                )) ?? current.tangent
                return CurveFrame(point: point, tangent: tangent, distance: targetDistance)
            }
        }

        return last
    }

    private static func quadraticPoint(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let oneMinusT = 1 - t
        return CGPoint(
            x: oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * control.x + t * t * end.x,
            y: oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * control.y + t * t * end.y
        )
    }

    private static func quadraticDerivative(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGVector {
        CGVector(
            dx: 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x),
            dy: 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y)
        )
    }

    private static func normalizedVector(_ vector: CGVector) -> CGVector? {
        let length = hypot(vector.dx, vector.dy)
        guard length > 0.0001 else {
            return nil
        }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }

    static func pointAlongCurve(
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        distanceFromEnd: CGFloat
    ) -> CGPoint {
        let frames = sampledCurveFrames(start: start, control: control, end: end)
        let totalDistance = frames.last?.distance ?? 0
        return interpolatedFrame(at: max(0, totalDistance - distanceFromEnd), frames: frames).point
    }

    private static func notchedArrowPath(
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        tailHalfWidth: CGFloat,
        neckHalfWidth: CGFloat,
        shoulderHalfWidth: CGFloat,
        headLength: CGFloat,
        notchInsetFromTip: CGFloat,
        startInset: CGFloat = 0,
        tipInset: CGFloat = 0
    ) -> CGPath? {
        let frames = sampledCurveFrames(start: start, control: control, end: end)
        guard let last = frames.last, last.distance > 0.001 else {
            return nil
        }

        let totalDistance = last.distance
        let tipDistance = max(startInset, totalDistance - tipInset)
        let availableDistance = max(0, tipDistance - startInset)
        let effectiveHeadLength = min(headLength, availableDistance * 0.65)
        let shoulderDistance = max(startInset, tipDistance - effectiveHeadLength)
        let notchDistance = min(
            tipDistance,
            max(
                shoulderDistance,
                tipDistance - min(notchInsetFromTip, effectiveHeadLength * 0.75)
            )
        )
        let sampleSpan = max(0, notchDistance - startInset)
        let sampleCount = max(2, Int(ceil(sampleSpan / 8)))
        var left: [CGPoint] = []
        var right: [CGPoint] = []

        for index in 0...sampleCount {
            let progress = CGFloat(index) / CGFloat(sampleCount)
            let distance = startInset + sampleSpan * progress
            let frame = interpolatedFrame(at: distance, frames: frames)
            let halfWidth = tailHalfWidth + (neckHalfWidth - tailHalfWidth) * progress
            let normal = CGVector(dx: -frame.tangent.dy, dy: frame.tangent.dx)
            left.append(CGPoint(x: frame.point.x + normal.dx * halfWidth, y: frame.point.y + normal.dy * halfWidth))
            right.append(CGPoint(x: frame.point.x - normal.dx * halfWidth, y: frame.point.y - normal.dy * halfWidth))
        }

        guard let first = left.first else {
            return nil
        }

        let shoulderFrame = interpolatedFrame(at: shoulderDistance, frames: frames)
        let shoulderNormal = CGVector(dx: -shoulderFrame.tangent.dy, dy: shoulderFrame.tangent.dx)
        let tip = interpolatedFrame(at: tipDistance, frames: frames).point
        let headLeft = CGPoint(
            x: shoulderFrame.point.x + shoulderNormal.dx * shoulderHalfWidth,
            y: shoulderFrame.point.y + shoulderNormal.dy * shoulderHalfWidth
        )
        let headRight = CGPoint(
            x: shoulderFrame.point.x - shoulderNormal.dx * shoulderHalfWidth,
            y: shoulderFrame.point.y - shoulderNormal.dy * shoulderHalfWidth
        )

        let path = CGMutablePath()
        path.move(to: first)
        left.dropFirst().forEach { path.addLine(to: $0) }
        path.addLine(to: headLeft)
        path.addLine(to: tip)
        path.addLine(to: headRight)
        right.reversed().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private static func taperedArrowPath(
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        tailHalfWidth: CGFloat,
        neckHalfWidth: CGFloat,
        shoulderHalfWidth: CGFloat,
        headLength: CGFloat,
        startInset: CGFloat = 0,
        tipInset: CGFloat = 0
    ) -> CGPath? {
        let frames = sampledCurveFrames(start: start, control: control, end: end)
        guard let last = frames.last, last.distance > 0.001 else {
            return nil
        }

        let totalDistance = last.distance
        let tipDistance = max(startInset, totalDistance - tipInset)
        let headBaseDistance = max(startInset, tipDistance - min(headLength, max(0, tipDistance - startInset) * 0.65))
        let sampleSpan = max(0, headBaseDistance - startInset)
        let sampleCount = max(10, Int(sampleSpan / 8))
        var left: [CGPoint] = []
        var right: [CGPoint] = []

        for index in 0...sampleCount {
            let progress = CGFloat(index) / CGFloat(sampleCount)
            let distance = startInset + sampleSpan * progress
            let frame = interpolatedFrame(at: distance, frames: frames)
            let eased = 1 - pow(1 - progress, 2)
            let halfWidth = tailHalfWidth + (neckHalfWidth - tailHalfWidth) * eased
            let normal = CGVector(dx: -frame.tangent.dy, dy: frame.tangent.dx)
            left.append(CGPoint(x: frame.point.x + normal.dx * halfWidth, y: frame.point.y + normal.dy * halfWidth))
            right.append(CGPoint(x: frame.point.x - normal.dx * halfWidth, y: frame.point.y - normal.dy * halfWidth))
        }

        guard let first = left.first else {
            return nil
        }
        let headBaseFrame = interpolatedFrame(at: headBaseDistance, frames: frames)
        let headNormal = CGVector(dx: -headBaseFrame.tangent.dy, dy: headBaseFrame.tangent.dx)
        let tip = interpolatedFrame(at: tipDistance, frames: frames).point
        let headLeft = CGPoint(
            x: headBaseFrame.point.x + headNormal.dx * shoulderHalfWidth,
            y: headBaseFrame.point.y + headNormal.dy * shoulderHalfWidth
        )
        let headRight = CGPoint(
            x: headBaseFrame.point.x - headNormal.dx * shoulderHalfWidth,
            y: headBaseFrame.point.y - headNormal.dy * shoulderHalfWidth
        )

        let path = CGMutablePath()
        path.move(to: first)
        left.dropFirst().forEach { path.addLine(to: $0) }
        path.addLine(to: headLeft)
        path.addLine(to: tip)
        path.addLine(to: headRight)
        right.reversed().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private static func clippedSubpath(_ subpath: [CGPoint], minimumX: CGFloat) -> [CGPoint]? {
        guard subpath.count >= 3 else {
            return nil
        }

        var output: [CGPoint] = []
        var previous = subpath[subpath.count - 1]
        var previousInside = previous.x >= minimumX

        for current in subpath {
            let currentInside = current.x >= minimumX
            if currentInside {
                if !previousInside, let intersection = verticalIntersection(from: previous, to: current, atX: minimumX) {
                    output.append(intersection)
                }
                output.append(current)
            } else if previousInside, let intersection = verticalIntersection(from: previous, to: current, atX: minimumX) {
                output.append(intersection)
            }

            previous = current
            previousInside = currentInside
        }

        guard output.count >= 3 else {
            return nil
        }
        return output
    }

    private static func clippedSubpath(_ subpath: [CGPoint], maximumX: CGFloat) -> [CGPoint]? {
        guard subpath.count >= 3 else {
            return nil
        }

        var output: [CGPoint] = []
        var previous = subpath[subpath.count - 1]
        var previousInside = previous.x <= maximumX

        for current in subpath {
            let currentInside = current.x <= maximumX
            if currentInside {
                if !previousInside, let intersection = verticalIntersection(from: previous, to: current, atX: maximumX) {
                    output.append(intersection)
                }
                output.append(current)
            } else if previousInside, let intersection = verticalIntersection(from: previous, to: current, atX: maximumX) {
                output.append(intersection)
            }

            previous = current
            previousInside = currentInside
        }

        guard output.count >= 3 else {
            return nil
        }
        return output
    }

    private static func verticalIntersection(from start: CGPoint, to end: CGPoint, atX x: CGFloat) -> CGPoint? {
        let dx = end.x - start.x
        guard abs(dx) > 0.0001 else {
            return CGPoint(x: x, y: end.y)
        }
        let t = (x - start.x) / dx
        guard t >= 0, t <= 1 else {
            return nil
        }
        return CGPoint(x: x, y: start.y + (end.y - start.y) * t)
    }
}

enum CaptureStrokePattern: Int, CaseIterable {
    case solid
    case dashLong
    case dashNarrow
    case dashLongShort
    case sketchSolid
    case sketchDashed

    var title: String {
        switch self {
        case .solid:
            return "实心线条"
        case .dashLong:
            return "长虚线线条"
        case .dashNarrow:
            return "点状线条"
        case .dashLongShort:
            return "一长一点的虚线线条"
        case .sketchSolid:
            return "手绘实线"
        case .sketchDashed:
            return "手绘虚线"
        }
    }

    var requiresPremiumAccess: Bool {
        switch self {
        case .sketchSolid, .sketchDashed:
            return true
        case .solid, .dashLong, .dashNarrow, .dashLongShort:
            return false
        }
    }

    var isSketch: Bool {
        switch self {
        case .sketchSolid, .sketchDashed:
            return true
        case .solid, .dashLong, .dashNarrow, .dashLongShort:
            return false
        }
    }

    var dashPattern: [CGFloat] {
        dashPattern(strokeWidth: 2)
    }

    func dashPattern(strokeWidth: CGFloat) -> [CGFloat] {
        let width = max(strokeWidth, 1)
        let longDash = max(8, width * 3)
        let gap = max(4, width * 1.6)
        let dotGap = max(5, width * 2.2)

        switch self {
        case .solid, .sketchSolid:
            return []
        case .dashLong:
            return [longDash, gap]
        case .dashNarrow:
            return [0.1, dotGap]
        case .dashLongShort:
            return [longDash, gap, 0.1, gap]
        case .sketchDashed:
            return [longDash, gap]
        }
    }
}

struct CaptureAnnotationStyle {
    var strokeColor: NSColor = NSColor(calibratedRed: 245 / 255, green: 34 / 255, blue: 45 / 255, alpha: 1)
    var strokeWidth: CGFloat = 3
    var strokePattern: CaptureStrokePattern = .solid
    var fillEnabled = false
    var fillColor: NSColor = NSColor(calibratedRed: 245 / 255, green: 34 / 255, blue: 45 / 255, alpha: 1)
    var cornerRadius: CGFloat = 0
}

struct CaptureAnnotation {
    var kind: CaptureAnnotationKind
    var rect: NSRect
    var style: CaptureAnnotationStyle
    var arrowLine: CaptureArrowLine?
    var brushPath: CaptureBrushPath?
}

struct CaptureSelectionResult {
    var screenRect: NSRect
    var snapshotRect: NSRect
    var annotations: [CaptureAnnotation]
    var action: CaptureCompletionAction
}

enum CaptureAnnotationRenderer {
    static func render(image: NSImage, annotations: [CaptureAnnotation]) -> NSImage {
        guard !annotations.isEmpty else {
            return image
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        for annotation in annotations {
            draw(annotation, in: context, scaleX: scaleX, scaleY: scaleY)
        }

        guard let renderedImage = context.makeImage() else {
            return image
        }

        return NSImage(cgImage: renderedImage, size: image.size)
    }

    private static func draw(_ annotation: CaptureAnnotation, in context: CGContext, scaleX: CGFloat, scaleY: CGFloat) {
        let lineScale = (scaleX + scaleY) / 2
        if annotation.kind == .arrowLine {
            drawArrowLine(annotation, in: context, scaleX: scaleX, scaleY: scaleY, lineScale: lineScale)
            return
        }
        if annotation.kind == .brush {
            drawBrushPath(annotation, in: context, scaleX: scaleX, scaleY: scaleY, lineScale: lineScale)
            return
        }

        let rect = annotation.rect.standardized.insetBy(dx: annotation.style.strokeWidth / 2, dy: annotation.style.strokeWidth / 2)
        let pixelRect = CGRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        let path = CGMutablePath()

        switch annotation.kind {
        case .rectangle where annotation.style.cornerRadius > 0:
            path.addRoundedRect(
                in: pixelRect,
                cornerWidth: annotation.style.cornerRadius * scaleX,
                cornerHeight: annotation.style.cornerRadius * scaleY
            )
        case .rectangle:
            path.addRect(pixelRect)
        case .ellipse:
            path.addEllipse(in: pixelRect)
        case .arrowLine, .brush:
            return
        }

        context.saveGState()
        context.addPath(path)
        if annotation.style.fillEnabled {
            context.setFillColor(cgColor(annotation.style.fillColor))
            context.fillPath()
        }

        let strokeWidth = annotation.style.strokeWidth * lineScale
        if annotation.style.strokePattern.isSketch {
            context.addPath(
                CaptureSketchStrokePath.cgPath(
                    kind: annotation.kind,
                    rect: pixelRect,
                    cornerRadius: annotation.style.cornerRadius * lineScale,
                    lineWidth: strokeWidth
                )
            )
        } else {
            context.addPath(path)
        }
        context.setStrokeColor(cgColor(annotation.style.strokeColor))
        context.setLineWidth(strokeWidth)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setLineDash(
            phase: 0,
            lengths: annotation.style.strokePattern
                .dashPattern(strokeWidth: annotation.style.strokeWidth)
                .map { $0 * lineScale }
        )
        context.strokePath()
        context.restoreGState()
    }

    private static func drawBrushPath(
        _ annotation: CaptureAnnotation,
        in context: CGContext,
        scaleX: CGFloat,
        scaleY: CGFloat,
        lineScale: CGFloat
    ) {
        guard let brushPath = annotation.brushPath, !brushPath.points.isEmpty else {
            return
        }

        context.saveGState()
        context.setStrokeColor(cgColor(annotation.style.strokeColor))
        context.setLineWidth(annotation.style.strokeWidth * lineScale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setLineDash(
            phase: 0,
            lengths: annotation.style.strokePattern
                .dashPattern(strokeWidth: annotation.style.strokeWidth)
                .map { $0 * lineScale }
        )

        let path = CGMutablePath()
        let first = pixelPoint(brushPath.points[0], scaleX: scaleX, scaleY: scaleY)
        path.move(to: first)
        if brushPath.points.count == 1 {
            path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y + 0.01))
        } else {
            for point in brushPath.points.dropFirst() {
                path.addLine(to: pixelPoint(point, scaleX: scaleX, scaleY: scaleY))
            }
        }
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawArrowLine(
        _ annotation: CaptureAnnotation,
        in context: CGContext,
        scaleX: CGFloat,
        scaleY: CGFloat,
        lineScale: CGFloat
    ) {
        guard let arrowLine = annotation.arrowLine else {
            return
        }

        let start = pixelPoint(arrowLine.start, scaleX: scaleX, scaleY: scaleY)
        let end = pixelPoint(arrowLine.end, scaleX: scaleX, scaleY: scaleY)
        let control = pixelPoint(arrowLine.control, scaleX: scaleX, scaleY: scaleY)
        let strokeWidth = annotation.style.strokeWidth * lineScale
        let startDirection = direction(from: control, to: start, fallbackFrom: end, fallbackTo: start)
        let endDirection = direction(from: control, to: end, fallbackFrom: start, fallbackTo: end)

        context.saveGState()
        context.setStrokeColor(cgColor(annotation.style.strokeColor))
        context.setFillColor(cgColor(annotation.style.strokeColor))
        context.setLineWidth(strokeWidth)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setLineDash(
            phase: 0,
            lengths: annotation.style.strokePattern
                .dashPattern(strokeWidth: annotation.style.strokeWidth)
                .map { $0 * lineScale }
        )

        let usesVectorBody = CaptureArrowVectorGeometry.isVectorArrow(arrowLine.startArrowType)
            || CaptureArrowVectorGeometry.isVectorArrow(arrowLine.endArrowType)

        if CaptureArrowVectorGeometry.isVectorArrow(arrowLine.endArrowType) {
            if let vectorPath = CaptureArrowVectorGeometry.cgPathAlongCurve(
                for: arrowLine.endArrowType,
                start: start,
                control: control,
                end: end,
                strokeWidth: strokeWidth
            ) {
                context.addPath(vectorPath.path)
                context.drawPath(using: vectorPath.evenOddFill ? .eoFill : .fill)
            }
        }

        if !usesVectorBody {
            let bodyStart = arrowLine.startArrowType == .normal
                ? CaptureArrowVectorGeometry.pointAlongCurve(
                    start: end,
                    control: control,
                    end: start,
                    distanceFromEnd: CaptureArrowVectorGeometry.normalArrowHeadInset(for: strokeWidth)
                )
                : start
            let bodyEnd = arrowLine.endArrowType == .normal
                ? CaptureArrowVectorGeometry.pointAlongCurve(
                    start: start,
                    control: control,
                    end: end,
                    distanceFromEnd: CaptureArrowVectorGeometry.normalArrowHeadInset(for: strokeWidth)
                )
                : end
            if annotation.style.strokePattern.isSketch {
                context.addPath(
                    CaptureSketchStrokePath.cgQuadraticPath(
                        from: bodyStart,
                        control: control,
                        to: bodyEnd,
                        lineWidth: strokeWidth
                    )
                )
            } else {
                let path = CGMutablePath()
                path.move(to: bodyStart)
                path.addQuadCurve(to: bodyEnd, control: control)
                context.addPath(path)
            }
            context.strokePath()
        }

        context.setLineDash(phase: 0, lengths: [])
        if CaptureArrowVectorGeometry.isVectorArrow(arrowLine.startArrowType) {
            if let vectorPath = CaptureArrowVectorGeometry.cgPathAlongCurve(
                for: arrowLine.startArrowType,
                start: end,
                control: control,
                end: start,
                strokeWidth: strokeWidth
            ) {
                context.addPath(vectorPath.path)
                context.drawPath(using: vectorPath.evenOddFill ? .eoFill : .fill)
            }
        }
        if !CaptureArrowVectorGeometry.isVectorArrow(arrowLine.startArrowType) {
            drawArrowHead(
                type: arrowLine.startArrowType,
                tip: start,
                direction: startDirection,
                strokeWidth: strokeWidth,
                in: context
            )
        }
        if !CaptureArrowVectorGeometry.isVectorArrow(arrowLine.endArrowType) {
            drawArrowHead(
                type: arrowLine.endArrowType,
                tip: end,
                direction: endDirection,
                strokeWidth: strokeWidth,
                in: context
            )
        }
        context.restoreGState()
    }

    private static func drawArrowHead(
        type: CaptureArrowType,
        tip: CGPoint,
        direction: CGVector,
        strokeWidth: CGFloat,
        in context: CGContext
    ) {
        guard type != .none else {
            return
        }

        let perp = CGVector(dx: -direction.dy, dy: direction.dx)
        switch type {
        case .none:
            return
        case .bar:
            context.saveGState()
            context.setLineWidth(max(1.5, strokeWidth))
            context.setLineCap(.butt)
            let capHalfWidth = max(5, strokeWidth * 2.1)
            let capStart = CGPoint(x: tip.x + perp.dx * capHalfWidth, y: tip.y + perp.dy * capHalfWidth)
            let capEnd = CGPoint(x: tip.x - perp.dx * capHalfWidth, y: tip.y - perp.dy * capHalfWidth)
            let path = CGMutablePath()
            path.move(to: capStart)
            path.addLine(to: capEnd)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        case .dot:
            let radius = max(3.5, strokeWidth * 1.45)
            context.fillEllipse(in: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
        case .diamond:
            let diamondLength = max(10, strokeWidth * 3.3)
            let diamondHalfWidth = max(4, strokeWidth * 1.5)
            let center = CGPoint(x: tip.x - direction.dx * diamondLength * 0.5, y: tip.y - direction.dy * diamondLength * 0.5)
            let back = CGPoint(x: tip.x - direction.dx * diamondLength, y: tip.y - direction.dy * diamondLength)
            let path = CGMutablePath()
            path.move(to: tip)
            path.addLine(to: CGPoint(x: center.x + perp.dx * diamondHalfWidth, y: center.y + perp.dy * diamondHalfWidth))
            path.addLine(to: back)
            path.addLine(to: CGPoint(x: center.x - perp.dx * diamondHalfWidth, y: center.y - perp.dy * diamondHalfWidth))
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        case .normal, .solidArrow, .hollowArrow:
            guard
                let vectorPath = CaptureArrowVectorGeometry.cgPath(
                    for: type,
                    tip: tip,
                    direction: direction,
                    scale: max(0.8, strokeWidth / 2),
                    minimumTemplateX: 11.45
                )
            else {
                return
            }
            context.addPath(vectorPath.path)
            context.drawPath(using: vectorPath.evenOddFill ? .eoFill : .fill)
        }
    }

    private static func pixelPoint(_ point: NSPoint, scaleX: CGFloat, scaleY: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scaleX, y: point.y * scaleY)
    }

    private static func direction(
        from point: CGPoint,
        to tip: CGPoint,
        fallbackFrom: CGPoint,
        fallbackTo: CGPoint
    ) -> CGVector {
        let dx = tip.x - point.x
        let dy = tip.y - point.y
        let length = hypot(dx, dy)
        if length > 0.001 {
            return CGVector(dx: dx / length, dy: dy / length)
        }

        let fallbackDx = fallbackTo.x - fallbackFrom.x
        let fallbackDy = fallbackTo.y - fallbackFrom.y
        let fallbackLength = hypot(fallbackDx, fallbackDy)
        guard fallbackLength > 0.001 else {
            return CGVector(dx: 1, dy: 0)
        }
        return CGVector(dx: fallbackDx / fallbackLength, dy: fallbackDy / fallbackLength)
    }

    private static func cgColor(_ color: NSColor) -> CGColor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return CGColor(
            srgbRed: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            alpha: rgb.alphaComponent
        )
    }
}

enum CaptureSketchStrokePath {
    static func bezierPath(
        kind: CaptureAnnotationKind,
        rect: NSRect,
        cornerRadius: CGFloat,
        lineWidth: CGFloat
    ) -> NSBezierPath {
        let points = jittered(points: outlinePoints(kind: kind, rect: rect, cornerRadius: cornerRadius), lineWidth: lineWidth)
        let path = NSBezierPath()
        guard let first = points.first else {
            return path
        }

        path.move(to: first)
        points.dropFirst().forEach { path.line(to: $0) }
        path.close()
        return path
    }

    static func cgPath(
        kind: CaptureAnnotationKind,
        rect: CGRect,
        cornerRadius: CGFloat,
        lineWidth: CGFloat
    ) -> CGPath {
        let points = jittered(points: outlinePoints(kind: kind, rect: rect, cornerRadius: cornerRadius), lineWidth: lineWidth)
        let path = CGMutablePath()
        guard let first = points.first else {
            return path
        }

        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    static func sampleLine(from start: NSPoint, to end: NSPoint, lineWidth: CGFloat) -> NSBezierPath {
        let points = jittered(points: segmentPoints(from: start, to: end, step: 7, includeEnd: true), lineWidth: lineWidth)
        let path = NSBezierPath()
        guard let first = points.first else {
            return path
        }

        path.move(to: first)
        points.dropFirst().forEach { path.line(to: $0) }
        return path
    }

    static func sampleQuadraticCurve(from start: NSPoint, control: NSPoint, to end: NSPoint, lineWidth: CGFloat) -> NSBezierPath {
        let points = jittered(points: quadraticPoints(from: start, control: control, to: end, step: 7), lineWidth: lineWidth)
        let path = NSBezierPath()
        guard let first = points.first else {
            return path
        }

        path.move(to: first)
        points.dropFirst().forEach { path.line(to: $0) }
        return path
    }

    static func cgQuadraticPath(from start: CGPoint, control: CGPoint, to end: CGPoint, lineWidth: CGFloat) -> CGPath {
        let points = jittered(points: quadraticPoints(from: start, control: control, to: end, step: 7), lineWidth: lineWidth)
        let path = CGMutablePath()
        guard let first = points.first else {
            return path
        }

        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }

    private static func outlinePoints(kind: CaptureAnnotationKind, rect: CGRect, cornerRadius: CGFloat) -> [CGPoint] {
        guard rect.width > 0, rect.height > 0 else {
            return []
        }

        switch kind {
        case .arrowLine, .brush:
            return []
        case .ellipse:
            return ellipsePoints(in: rect)
        case .rectangle where cornerRadius > 0:
            return roundedRectPoints(in: rect, cornerRadius: cornerRadius)
        case .rectangle:
            return rectanglePoints(in: rect)
        }
    }

    private static func rectanglePoints(in rect: CGRect) -> [CGPoint] {
        let topLeft = CGPoint(x: rect.minX, y: rect.maxY)
        let topRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.minY)

        return segmentPoints(from: topLeft, to: topRight, step: 7, includeEnd: false)
            + segmentPoints(from: topRight, to: bottomRight, step: 7, includeEnd: false)
            + segmentPoints(from: bottomRight, to: bottomLeft, step: 7, includeEnd: false)
            + segmentPoints(from: bottomLeft, to: topLeft, step: 7, includeEnd: false)
    }

    private static func roundedRectPoints(in rect: CGRect, cornerRadius: CGFloat) -> [CGPoint] {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        guard radius > 0 else {
            return rectanglePoints(in: rect)
        }

        let topLeft = CGPoint(x: rect.minX + radius, y: rect.maxY)
        let topRight = CGPoint(x: rect.maxX - radius, y: rect.maxY)
        let rightTop = CGPoint(x: rect.maxX, y: rect.maxY - radius)
        let rightBottom = CGPoint(x: rect.maxX, y: rect.minY + radius)
        let bottomRight = CGPoint(x: rect.maxX - radius, y: rect.minY)
        let bottomLeft = CGPoint(x: rect.minX + radius, y: rect.minY)
        let leftBottom = CGPoint(x: rect.minX, y: rect.minY + radius)
        let leftTop = CGPoint(x: rect.minX, y: rect.maxY - radius)

        return segmentPoints(from: topLeft, to: topRight, step: 7, includeEnd: false)
            + arcPoints(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, start: .pi / 2, end: 0)
            + segmentPoints(from: rightTop, to: rightBottom, step: 7, includeEnd: false)
            + arcPoints(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius, start: 0, end: -.pi / 2)
            + segmentPoints(from: bottomRight, to: bottomLeft, step: 7, includeEnd: false)
            + arcPoints(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius, start: -.pi / 2, end: -.pi)
            + segmentPoints(from: leftBottom, to: leftTop, step: 7, includeEnd: false)
            + arcPoints(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius, start: .pi, end: .pi / 2)
    }

    private static func ellipsePoints(in rect: CGRect) -> [CGPoint] {
        let count = max(40, Int(ceil((rect.width + rect.height) / 3)))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return (0..<count).map { index in
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2
            return CGPoint(
                x: center.x + cos(angle) * rect.width / 2,
                y: center.y + sin(angle) * rect.height / 2
            )
        }
    }

    private static func segmentPoints(from start: CGPoint, to end: CGPoint, step: CGFloat, includeEnd: Bool) -> [CGPoint] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let count = max(1, Int(ceil(distance / step)))
        let upperBound = includeEnd ? count : max(0, count - 1)
        return (0...upperBound).map { index in
            let t = CGFloat(index) / CGFloat(count)
            return CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
        }
    }

    private static func quadraticPoints(from start: CGPoint, control: CGPoint, to end: CGPoint, step: CGFloat) -> [CGPoint] {
        let approximateLength = hypot(control.x - start.x, control.y - start.y) + hypot(end.x - control.x, end.y - control.y)
        let count = max(2, Int(ceil(approximateLength / step)))
        return (0...count).map { index in
            let t = CGFloat(index) / CGFloat(count)
            let u = 1 - t
            let startWeight = u * u
            let controlWeight = 2 * u * t
            let endWeight = t * t
            let x = startWeight * start.x + controlWeight * control.x + endWeight * end.x
            let y = startWeight * start.y + controlWeight * control.y + endWeight * end.y
            return CGPoint(x: x, y: y)
        }
    }

    private static func arcPoints(center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat) -> [CGPoint] {
        let arcLength = abs(end - start) * radius
        let count = max(2, Int(ceil(arcLength / 5)))
        return (0..<count).map { index in
            let t = CGFloat(index) / CGFloat(count)
            let angle = start + (end - start) * t
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private static func jittered(points: [CGPoint], lineWidth: CGFloat) -> [CGPoint] {
        let amplitude = min(2.2, max(0.7, lineWidth * 0.35))
        return points.enumerated().map { index, point in
            CGPoint(
                x: point.x + noise(index: index, salt: 0.19) * amplitude * 0.55,
                y: point.y + noise(index: index, salt: 0.73) * amplitude
            )
        }
    }

    private static func noise(index: Int, salt: CGFloat) -> CGFloat {
        let raw = sin((CGFloat(index) + 1) * 12.9898 + salt * 78.233) * 43758.5453
        return (raw - floor(raw)) * 2 - 1
    }
}
