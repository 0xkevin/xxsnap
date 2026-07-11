import AppKit
import CoreImage
import CoreText

enum CaptureCompletionAction {
    case copy
    case save
    case pin
    case finishEditing
}

enum CaptureAnnotationKind {
    case rectangle
    case ellipse
    case arrowLine
    case brush
    case marker
    case text
    case numberSequence
    case magnifier
    case mosaicStroke
    case mosaicRectangle
}

enum CaptureMagnifierShape: CaseIterable, Equatable {
    case circle
    case rectangle
}

enum CaptureMosaicRedactionType: Equatable {
    case gaussianBlur
    case pixelMosaic
}

struct CaptureMosaicRedaction: Equatable {
    var type: CaptureMosaicRedactionType
    var value: Int
}

struct CaptureMosaicStroke: Equatable {
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

struct CaptureMarkerLine: Equatable {
    var start: NSPoint
    var end: NSPoint

    var boundingRect: NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
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
        let localStart = CGPoint.zero
        let localControl = CGPoint(x: control.x - start.x, y: control.y - start.y)
        let localEnd = CGPoint(x: end.x - start.x, y: end.y - start.y)
        var translation = CGAffineTransform(translationX: start.x, y: start.y)
        switch type {
        case .solidArrow:
            guard let localPath = stretchedArrowFilled2Path(start: localStart, control: localControl, end: localEnd, strokeWidth: strokeWidth),
                  let path = localPath.copy(using: &translation) else {
                return nil
            }
            return (path, false)
        case .hollowArrow:
            guard let localPath = stretchedHollowArrowFilled2Path(start: localStart, control: localControl, end: localEnd, strokeWidth: strokeWidth),
                  let path = localPath.copy(using: &translation) else {
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
    var textSize: CGFloat = 24
    var textFontFamily: String?
    var textBold = false
    var textItalic = false
    var textOutlineEnabled = false
    var textOutlineColor: NSColor = .white
}

typealias AnnotationID = UUID

struct EraserMask: Equatable {
    var id: UUID = UUID()
    var rect: NSRect
    var affectedAnnotationIDs: Set<AnnotationID>
}

struct CaptureAnnotation {
    var id: AnnotationID = UUID()
    var kind: CaptureAnnotationKind
    var rect: NSRect
    var style: CaptureAnnotationStyle
    var rotationAngle: CGFloat = 0
    var arrowLine: CaptureArrowLine?
    var brushPath: CaptureBrushPath?
    var markerLine: CaptureMarkerLine?
    var text: String?
    var numberMarkType: CaptureNumberMarkType?
    var numberSequenceIndex: Int?
    var numberSequenceIsManual = false
    var numberSequenceGroupID: UUID?
    var magnifierShape: CaptureMagnifierShape?
    var magnifierZoom: CGFloat?
    var mosaicStroke: CaptureMosaicStroke?
    var mosaicRedaction: CaptureMosaicRedaction?

    var effectiveMagnifierShape: CaptureMagnifierShape {
        magnifierShape ?? .rectangle
    }

    var effectiveMagnifierZoom: CGFloat {
        magnifierZoom ?? 2
    }
}

enum CaptureNumberMarkType: CaseIterable, Equatable {
    case number
    case check
    case cross
}

struct CaptureSelectionResult {
    var screenRect: NSRect
    var snapshotRect: NSRect
    var annotations: [CaptureAnnotation]
    var eraserMasks: [EraserMask] = []
    var action: CaptureCompletionAction
}

enum CaptureAnnotationRenderer {
    private enum ArrowHeadMetrics {
        static func barHalfWidth(_ strokeWidth: CGFloat) -> CGFloat { max(5, strokeWidth * 2.1) }
        static func dotRadius(_ strokeWidth: CGFloat) -> CGFloat { max(3.5, strokeWidth * 1.45) }
        static func diamondLength(_ strokeWidth: CGFloat) -> CGFloat { max(10, strokeWidth * 3.3) }
        static func diamondHalfWidth(_ strokeWidth: CGFloat) -> CGFloat { max(4, strokeWidth * 1.5) }

        static func conservativeRadius(for type: CaptureArrowType, strokeWidth: CGFloat) -> CGFloat {
            let lineHalf = max(0.75, strokeWidth / 2)
            switch type {
            case .none:
                return lineHalf
            case .bar:
                return barHalfWidth(strokeWidth) + lineHalf
            case .dot:
                return dotRadius(strokeWidth)
            case .diamond:
                return hypot(diamondLength(strokeWidth), diamondHalfWidth(strokeWidth)) + lineHalf
            case .normal:
                return 12 * max(0.8, strokeWidth / 2) + lineHalf
            case .solidArrow, .hollowArrow:
                return 24 * max(0.8, strokeWidth / 2) + strokeWidth * 2
            }
        }
    }
    struct VisibleLongImageRenderPlan {
        var processingRect: NSRect
        var annotationIDs: Set<AnnotationID>
        var maskIDs: Set<UUID>
        var annotationCount: Int { annotationIDs.count }
    }
    static let markerOpacity: CGFloat = 0.85
    static let textDisplayScale: CGFloat = 3
    private static let redactionContext = CIContext(options: nil)

    static func textFont(size: CGFloat) -> NSFont {
        textFont(style: {
            var style = CaptureAnnotationStyle()
            style.textSize = size
            return style
        }())
    }

    static func textFont(style: CaptureAnnotationStyle) -> NSFont {
        let size = max(3, min(300, style.textSize * textDisplayScale))
        let manager = NSFontManager.shared
        let base = style.textFontFamily.flatMap {
            manager.font(withFamily: $0, traits: [], weight: 5, size: size)
        } ?? NSFont.systemFont(ofSize: size, weight: style.textBold ? .bold : .medium)

        var font = base
        if style.textBold {
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        }
        if style.textItalic {
            font = manager.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    static func textLineHeight(style: CaptureAnnotationStyle) -> CGFloat {
        let font = textFont(style: style)
        return ceil(font.ascender - font.descender + font.leading)
    }

    static let textHorizontalPadding: CGFloat = 8

    static func textContentRect(in rect: NSRect) -> NSRect {
        let horizontalPadding = min(textHorizontalPadding, max(0, rect.width / 2))
        return rect.insetBy(dx: horizontalPadding, dy: 0)
    }

    static func textAttributes(style: CaptureAnnotationStyle) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: textFont(style: style),
            .foregroundColor: style.strokeColor,
            .paragraphStyle: paragraphStyle,
        ]
        if style.textItalic {
            attributes[.obliqueness] = CGFloat(0.22)
        }
        if style.textOutlineEnabled {
            attributes[.strokeColor] = style.textOutlineColor
            attributes[.strokeWidth] = CGFloat(-6)
        }
        return attributes
    }

    static func drawText(_ text: String, in rect: NSRect, style: CaptureAnnotationStyle) {
        let contentRect = textContentRect(in: rect)
        guard style.textOutlineEnabled else {
            NSAttributedString(string: text, attributes: textAttributes(style: style)).draw(in: contentRect)
            return
        }

        var outlineAttributes = textAttributes(style: style)
        outlineAttributes[.foregroundColor] = NSColor.clear
        outlineAttributes[.strokeColor] = style.textOutlineColor
        outlineAttributes[.strokeWidth] = CGFloat(8)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowOffset = NSSize(width: 1.4, height: -1.4)
        shadow.shadowBlurRadius = 2
        outlineAttributes[.shadow] = shadow

        var fillAttributes = textAttributes(style: style)
        fillAttributes.removeValue(forKey: .strokeColor)
        fillAttributes.removeValue(forKey: .strokeWidth)
        fillAttributes.removeValue(forKey: .shadow)

        NSAttributedString(string: text, attributes: outlineAttributes).draw(in: contentRect)
        NSAttributedString(string: text, attributes: fillAttributes).draw(in: contentRect)
    }

    static func render(image: NSImage, annotations: [CaptureAnnotation]) -> NSImage {
        guard !annotations.isEmpty else {
            return image
        }

        return renderImage(image: image, annotations: annotations) ?? image
    }

    static func render(image: NSImage, annotations: [CaptureAnnotation], eraserMasks: [EraserMask]) -> NSImage {
        guard !eraserMasks.isEmpty else {
            return render(image: image, annotations: annotations)
        }
        guard !annotations.isEmpty else {
            return image
        }

        return renderImage(image: image, annotations: annotations, eraserMasks: eraserMasks) ?? image
    }

    /// Stable export entry point for canonical full-document coordinates. It
    /// deliberately delegates to the single-image renderer so mosaic,
    /// magnifier, text, z-order and eraser behavior cannot diverge.
    static func renderLongImage(
        image: NSImage,
        annotations: [CaptureAnnotation],
        eraserMasks: [EraserMask]
    ) -> NSImage {
        let rendererAnnotations = annotations.map {
            LongImageAnnotationTranslation.annotationFromTopOriginToRenderer($0, imageHeight: image.size.height)
        }
        let rendererMasks = eraserMasks.map {
            LongImageAnnotationTranslation.maskFromTopOriginToRenderer($0, imageHeight: image.size.height)
        }
        return render(image: image, annotations: rendererAnnotations, eraserMasks: rendererMasks)
    }

    static func renderCompleteLongImage(
        image: NSImage,
        annotations: [CaptureAnnotation],
        eraserMasks: [EraserMask]
    ) -> NSImage {
        renderLongImage(image: image, annotations: annotations, eraserMasks: eraserMasks)
    }

    /// Renders only the bounded region needed for composite-dependent effects
    /// and raw magnifier samples, avoiding a second complete long image while scrolling.
    static func renderVisibleLongImageSlice(
        image: NSImage,
        annotations: [CaptureAnnotation],
        eraserMasks: [EraserMask],
        imageRect: NSRect
    ) -> NSImage {
        let imageBounds = NSRect(origin: .zero, size: image.size)
        let requested = imageRect.standardized.intersection(imageBounds)
        guard !requested.isEmpty else { return NSImage(size: .zero) }
        let plan = visibleLongImageRenderPlan(
            imageSize: image.size,
            imageRect: requested,
            annotations: annotations,
            eraserMasks: eraserMasks
        )
        let processing = plan.processingRect
        guard let source = cropLongImage(image, rect: processing) else { return image }
        let selectedAnnotations = annotations.filter { plan.annotationIDs.contains($0.id) }
        let selectedMasks = eraserMasks.filter { plan.maskIDs.contains($0.id) }
        let offset = NSPoint(x: -processing.minX, y: -processing.minY)
        let localAnnotations = selectedAnnotations.map {
            let topLocal = LongImageAnnotationTranslation.annotation($0, by: offset)
            return LongImageAnnotationTranslation.annotationFromTopOriginToRenderer(topLocal, imageHeight: processing.height)
        }
        let localMasks = selectedMasks.map {
            let topLocal = LongImageAnnotationTranslation.mask($0, by: offset)
            return LongImageAnnotationTranslation.maskFromTopOriginToRenderer(topLocal, imageHeight: processing.height)
        }
        guard let fullCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let scaleX = CGFloat(fullCG.width) / max(image.size.width, 1)
        let scaleY = CGFloat(fullCG.height) / max(image.size.height, 1)
        let contentOrigin = CGPoint(
            x: processing.minX * scaleX,
            y: (image.size.height - processing.maxY) * scaleY
        )
        let rendered = renderRegion(
            image: source,
            annotations: localAnnotations,
            eraserMasks: localMasks,
            contentOriginPixels: contentOrigin,
            fullCanvasPixelHeight: CGFloat(fullCG.height)
        )
        let localRequest = requested.offsetBy(dx: -processing.minX, dy: -processing.minY)
        return cropLongImage(rendered, rect: localRequest) ?? rendered
    }

    static func visibleLongImageProcessingRect(imageSize: NSSize, imageRect: NSRect) -> NSRect {
        visibleLongImageProcessingRect(imageSize: imageSize, imageRect: imageRect, annotations: [])
    }

    static func visibleLongImageProcessingRect(
        imageSize: NSSize,
        imageRect: NSRect,
        annotations: [CaptureAnnotation]
    ) -> NSRect {
        dependencyAnalysis(imageSize: imageSize, imageRect: imageRect, annotations: annotations).processingRect
    }

    private static func dependencyAnalysis(
        imageSize: NSSize,
        imageRect: NSRect,
        annotations: [CaptureAnnotation]
    ) -> (processingRect: NSRect, annotationIDs: Set<AnnotationID>) {
        let imageBounds = NSRect(origin: .zero, size: imageSize)
        let requested = imageRect.standardized.intersection(imageBounds)
        let visualBounds = annotations.map { longImageVisualBounds(for: $0).intersection(imageBounds) }
        let directIndexes = Set(visualBounds.indices.filter { visualBounds[$0].intersects(requested) })
        var processingRegion = requested
        var requiredPriorCompositeRegion = requested
        var includedIDs = Set<AnnotationID>()
        for index in visualBounds.indices.reversed() {
            let visual = visualBounds[index]
            guard directIndexes.contains(index) || visual.intersects(requiredPriorCompositeRegion) else { continue }
            let annotation = annotations[index]
            includedIDs.insert(annotation.id)
            if isCompositeSourceDependentLongImageAnnotation(annotation) {
                requiredPriorCompositeRegion = requiredPriorCompositeRegion.union(visual).intersection(imageBounds)
                processingRegion = processingRegion.union(visual).intersection(imageBounds)
            } else if let source = magnifierSourceBounds(for: annotation, imageBounds: imageBounds) {
                processingRegion = processingRegion.union(source).intersection(imageBounds)
            }
        }
        return (processingRegion.intersection(imageBounds).integral, includedIDs)
    }

    private static func isCompositeSourceDependentLongImageAnnotation(_ annotation: CaptureAnnotation) -> Bool {
        annotation.kind == .mosaicStroke || annotation.kind == .mosaicRectangle
    }

    private static func magnifierSourceBounds(for annotation: CaptureAnnotation, imageBounds: NSRect) -> NSRect? {
        guard annotation.kind == .magnifier else { return nil }
        return magnifierDrawGeometry(
            destination: annotation.rect.standardized,
            sourceBounds: imageBounds,
            zoom: annotation.effectiveMagnifierZoom
        )?.integralSource
    }

    static func visibleLongImageRenderPlan(
        imageSize: NSSize,
        imageRect: NSRect,
        annotations: [CaptureAnnotation],
        eraserMasks: [EraserMask]
    ) -> VisibleLongImageRenderPlan {
        let analysis = dependencyAnalysis(imageSize: imageSize, imageRect: imageRect, annotations: annotations)
        let processing = analysis.processingRect
        let annotationIDs = analysis.annotationIDs
        let maskIDs = Set(eraserMasks.lazy.filter {
            $0.rect.intersects(processing) && !$0.affectedAnnotationIDs.isDisjoint(with: annotationIDs)
        }.map(\.id))
        return VisibleLongImageRenderPlan(processingRect: processing, annotationIDs: annotationIDs, maskIDs: maskIDs)
    }

    static func longImageVisualBounds(for annotation: CaptureAnnotation) -> NSRect {
        var bounds = annotation.rect.standardized
        if let arrow = annotation.arrowLine { bounds = bounds.union(arrow.boundingRect) }
        if let brush = annotation.brushPath { bounds = bounds.union(brush.boundingRect) }
        if let marker = annotation.markerLine { bounds = bounds.union(marker.boundingRect) }
        if let mosaic = annotation.mosaicStroke { bounds = bounds.union(mosaic.boundingRect) }
        if annotation.kind == .arrowLine, let arrow = annotation.arrowLine {
            let startRadius = ArrowHeadMetrics.conservativeRadius(for: arrow.startArrowType, strokeWidth: annotation.style.strokeWidth)
            let endRadius = ArrowHeadMetrics.conservativeRadius(for: arrow.endArrowType, strokeWidth: annotation.style.strokeWidth)
            bounds = bounds
                .union(NSRect(x: arrow.start.x - startRadius, y: arrow.start.y - startRadius, width: startRadius * 2, height: startRadius * 2))
                .union(NSRect(x: arrow.end.x - endRadius, y: arrow.end.y - endRadius, width: endRadius * 2, height: endRadius * 2))
        }
        if annotation.rotationAngle != 0 {
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let cosine = cos(annotation.rotationAngle), sine = sin(annotation.rotationAngle)
            let corners = [
                NSPoint(x: bounds.minX, y: bounds.minY), NSPoint(x: bounds.maxX, y: bounds.minY),
                NSPoint(x: bounds.maxX, y: bounds.maxY), NSPoint(x: bounds.minX, y: bounds.maxY),
            ].map { point -> NSPoint in
                let dx = point.x - center.x, dy = point.y - center.y
                return NSPoint(x: center.x + dx * cosine - dy * sine, y: center.y + dx * sine + dy * cosine)
            }
            bounds = corners.dropFirst().reduce(NSRect(origin: corners[0], size: .zero)) { $0.union(NSRect(origin: $1, size: .zero)) }
        }
        var padding = max(4, annotation.style.strokeWidth * 2)
        if annotation.kind == .text { padding = max(padding, annotation.style.textSize * textDisplayScale) }
        if let redaction = annotation.mosaicRedaction { padding = max(padding, CGFloat(redaction.value) * 4 + annotation.style.strokeWidth) }
        return bounds.insetBy(dx: -padding, dy: -padding)
    }


    private static func cropLongImage(_ image: NSImage, rect: NSRect) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scaleX = CGFloat(cg.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cg.height) / max(image.size.height, 1)
        let pixels = CGRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let cropped = cg.cropping(to: pixels) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    private static func renderImage(
        image: NSImage,
        annotations: [CaptureAnnotation],
        eraserMasks: [EraserMask] = [],
        contentOriginPixels: CGPoint = .zero,
        fullCanvasPixelHeight: CGFloat? = nil
    ) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = makeRenderContext(width: cgImage.width, height: cgImage.height, colorSpace: colorSpace) else {
            return nil
        }

        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        if eraserMasks.isEmpty {
            drawAnnotations(annotations, in: context, sourceImage: cgImage, scaleX: scaleX, scaleY: scaleY, contentOriginPixels: contentOriginPixels, fullCanvasPixelHeight: fullCanvasPixelHeight ?? CGFloat(cgImage.height))
        } else {
            drawAnnotations(
                annotations: annotations,
                in: context,
                colorSpace: colorSpace,
                sourceImage: cgImage,
                eraserMasks: eraserMasks,
                scaleX: scaleX,
                scaleY: scaleY,
                contentOriginPixels: contentOriginPixels,
                fullCanvasPixelHeight: fullCanvasPixelHeight ?? CGFloat(cgImage.height)
            )
        }

        guard let renderedImage = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: renderedImage, size: image.size)
    }

    private static func renderRegion(
        image: NSImage,
        annotations: [CaptureAnnotation],
        eraserMasks: [EraserMask],
        contentOriginPixels: CGPoint,
        fullCanvasPixelHeight: CGFloat
    ) -> NSImage {
        renderImage(
            image: image,
            annotations: annotations,
            eraserMasks: eraserMasks,
            contentOriginPixels: contentOriginPixels,
            fullCanvasPixelHeight: fullCanvasPixelHeight
        ) ?? image
    }

    private static func drawAnnotations(
        _ annotations: [CaptureAnnotation],
        in context: CGContext,
        sourceImage: CGImage,
        scaleX: CGFloat,
        scaleY: CGFloat,
        contentOriginPixels: CGPoint = .zero,
        fullCanvasPixelHeight: CGFloat? = nil
    ) {
        for annotation in annotations {
            if isMosaicAnnotation(annotation) {
                drawMosaicAnnotation(
                    annotation,
                    in: context,
                    scaleX: scaleX,
                    scaleY: scaleY,
                    contentOriginPixels: contentOriginPixels,
                    fullCanvasPixelHeight: fullCanvasPixelHeight ?? CGFloat(context.height)
                )
            } else {
                draw(annotation, in: context, sourceImage: sourceImage, scaleX: scaleX, scaleY: scaleY)
            }
        }
    }

    private static func drawAnnotations(
        annotations: [CaptureAnnotation],
        in context: CGContext,
        colorSpace: CGColorSpace,
        sourceImage: CGImage,
        eraserMasks: [EraserMask],
        scaleX: CGFloat,
        scaleY: CGFloat,
        contentOriginPixels: CGPoint = .zero,
        fullCanvasPixelHeight: CGFloat? = nil
    ) {
        for annotation in annotations {
            let masksForAnnotation = eraserMasks.filter { $0.affectedAnnotationIDs.contains(annotation.id) }
            guard !masksForAnnotation.isEmpty else {
                drawAnnotations([annotation], in: context, sourceImage: sourceImage, scaleX: scaleX, scaleY: scaleY, contentOriginPixels: contentOriginPixels, fullCanvasPixelHeight: fullCanvasPixelHeight)
                continue
            }
            guard let annotationImage = makeMaskedAnnotationImage(
                width: context.width,
                height: context.height,
                colorSpace: colorSpace,
                currentImage: snapshotContext(context),
                sourceImage: sourceImage,
                annotation: annotation,
                eraserMasks: masksForAnnotation,
                scaleX: scaleX,
                scaleY: scaleY,
                contentOriginPixels: contentOriginPixels,
                fullCanvasPixelHeight: fullCanvasPixelHeight ?? CGFloat(context.height)
            ) else {
                continue
            }
            context.draw(annotationImage, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        }
    }

    private static func makeMaskedAnnotationImage(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace,
        currentImage: CGImage?,
        sourceImage: CGImage,
        annotation: CaptureAnnotation,
        eraserMasks: [EraserMask],
        scaleX: CGFloat,
        scaleY: CGFloat,
        contentOriginPixels: CGPoint,
        fullCanvasPixelHeight: CGFloat
    ) -> CGImage? {
        guard let context = makeRenderContext(width: width, height: height, colorSpace: colorSpace) else {
            return nil
        }
        context.interpolationQuality = .none
        if let currentImage {
            context.draw(currentImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        drawAnnotations([annotation], in: context, sourceImage: sourceImage, scaleX: scaleX, scaleY: scaleY, contentOriginPixels: contentOriginPixels, fullCanvasPixelHeight: fullCanvasPixelHeight)

        context.saveGState()
        context.setBlendMode(.clear)
        for mask in eraserMasks {
            let pixelRect = CGRect(
                x: mask.rect.minX * scaleX,
                y: mask.rect.minY * scaleY,
                width: mask.rect.width * scaleX,
                height: mask.rect.height * scaleY
            ).standardized.insetBy(dx: -scaleX, dy: -scaleY)
            context.fill(pixelRect)
        }
        context.restoreGState()

        return context.makeImage()
    }

    private static func makeRenderContext(width: Int, height: Int, colorSpace: CGColorSpace) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    static func redactedPreview(image: NSImage, redaction: CaptureMosaicRedaction) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        return NSImage(cgImage: redactedImage(from: cgImage, redaction: redaction), size: image.size)
    }

    private static func draw(
        _ annotation: CaptureAnnotation,
        in context: CGContext,
        sourceImage: CGImage,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) {
        let lineScale = (scaleX + scaleY) / 2
        if isMosaicAnnotation(annotation) {
            return
        }
        if annotation.kind == .magnifier {
            drawMagnifierAnnotation(
                annotation,
                in: context,
                sourceImage: sourceImage,
                scaleX: scaleX,
                scaleY: scaleY,
                lineScale: lineScale
            )
            return
        }
        if annotation.numberMarkType != nil {
            drawNumberSequenceAnnotation(annotation, in: context, scaleX: scaleX, scaleY: scaleY, textScale: lineScale)
            return
        }
        if annotation.kind == .text {
            drawTextAnnotation(annotation, in: context, scaleX: scaleX, scaleY: scaleY)
            return
        }
        if annotation.kind == .numberSequence {
            drawNumberSequenceAnnotation(annotation, in: context, scaleX: scaleX, scaleY: scaleY, textScale: lineScale)
            return
        }
        if annotation.kind == .marker {
            drawMarkerLine(annotation, in: context, sourceImage: sourceImage, scaleX: scaleX, scaleY: scaleY, lineScale: lineScale)
            return
        }
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
        case .arrowLine, .brush, .marker, .text, .numberSequence, .magnifier, .mosaicStroke, .mosaicRectangle:
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

    private static func drawTextAnnotation(
        _ annotation: CaptureAnnotation,
        in context: CGContext,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) {
        guard
            let text = annotation.text,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        let textRect = annotation.rect.standardized

        context.saveGState()
        context.scaleBy(x: scaleX, y: scaleY)
        if abs(annotation.rotationAngle) >= 0.001 {
            context.translateBy(x: textRect.midX, y: textRect.midY)
            context.rotate(by: annotation.rotationAngle)
            context.translateBy(x: -textRect.midX, y: -textRect.midY)
        }
        let previousGraphicsContext = NSGraphicsContext.current
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = graphicsContext
        drawText(text, in: textRect, style: annotation.style)
        NSGraphicsContext.current = previousGraphicsContext
        context.restoreGState()
    }

    static func numberMarkDiameter(for fontSize: CGFloat) -> CGFloat {
        interpolatedNumberMarkDiameter(for: fontSize)
    }

    static func numberMarkTextFontSize(for fontSize: CGFloat) -> CGFloat {
        max(7, numberMarkDiameter(for: fontSize) * 0.72)
    }

    static func numberMarkTextFontSize(for fontSize: CGFloat, text: String) -> CGFloat {
        let diameter = numberMarkDiameter(for: fontSize)
        let maxTextSize = NSSize(width: diameter * 0.78, height: diameter * 0.78)
        var candidate = numberMarkTextFontSize(for: fontSize)
        let string = NSString(string: text)
        while candidate > 6 {
            let font = NSFont.monospacedDigitSystemFont(ofSize: candidate, weight: .bold)
            let measured = string.size(withAttributes: [.font: font])
            if measured.width <= maxTextSize.width, measured.height <= maxTextSize.height {
                return candidate
            }
            candidate -= 1
        }
        return max(6, candidate)
    }

    static func numberMarkRect(centeredAt point: NSPoint, fontSize: CGFloat) -> NSRect {
        let diameter = numberMarkDiameter(for: fontSize)
        return NSRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
    }

    private static let snipasteNumberMarkDiameters: [(size: CGFloat, diameter: CGFloat)] = [
        (1, 15), (2, 18), (3, 21), (4, 24), (5, 27),
        (6, 30), (7, 33), (8, 36), (9, 38), (10, 41),
        (12, 47), (14, 47), (16, 54), (20, 70), (24, 82),
        (32, 105), (40, 128), (48, 152), (60, 186), (72, 221),
    ]

    private static func interpolatedNumberMarkDiameter(for fontSize: CGFloat) -> CGFloat {
        let points = snipasteNumberMarkDiameters
        guard let first = points.first, let last = points.last else {
            return max(18, fontSize)
        }
        if fontSize <= first.size {
            return first.diameter
        }
        if fontSize >= last.size {
            return last.diameter
        }
        if let exact = points.first(where: { abs($0.size - fontSize) < 0.001 }) {
            return exact.diameter
        }
        for index in 0..<(points.count - 1) {
            let lower = points[index]
            let upper = points[index + 1]
            if fontSize >= lower.size, fontSize <= upper.size {
                let progress = (fontSize - lower.size) / max(upper.size - lower.size, 1)
                return lower.diameter + (upper.diameter - lower.diameter) * progress
            }
        }
        return last.diameter
    }

    private static func readableForegroundColor(on color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.68 ? NSColor.black.withAlphaComponent(0.86) : .white
    }

    private static func drawNumberSequenceAnnotation(
        _ annotation: CaptureAnnotation,
        in context: CGContext,
        scaleX: CGFloat,
        scaleY: CGFloat,
        textScale: CGFloat
    ) {
        let type = annotation.numberMarkType ?? .number
        var style = annotation.style
        style.textSize *= textScale
        let rect = annotation.rect.standardized
        let pixelRect = NSRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )

        context.saveGState()
        let previousGraphicsContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        switch type {
        case .number:
            context.setFillColor(cgColor(style.strokeColor))
            context.fillEllipse(in: pixelRect)
            let value = min(999, max(1, annotation.numberSequenceIndex ?? 1))
            let text = "\(value)"
            let font = NSFont.monospacedDigitSystemFont(ofSize: numberMarkTextFontSize(for: style.textSize, text: text), weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: readableForegroundColor(on: style.strokeColor),
            ]
            let size = NSString(string: text).size(withAttributes: attributes)
            NSString(string: text).draw(
                at: NSPoint(
                    x: pixelRect.midX - size.width / 2,
                    y: pixelRect.midY - size.height / 2
                ),
                withAttributes: attributes
            )
        case .check:
            drawNumberSymbol("✓", in: pixelRect, color: style.strokeColor, size: style.textSize)
        case .cross:
            drawNumberSymbol("×", in: pixelRect, color: style.strokeColor, size: style.textSize)
        }

        NSGraphicsContext.current = previousGraphicsContext
        context.restoreGState()
    }

    private static func drawNumberSymbol(_ symbol: String, in rect: NSRect, color: NSColor, size: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(3, size), weight: .bold),
            .foregroundColor: color,
        ]
        let symbolSize = NSString(string: symbol).size(withAttributes: attributes)
        NSString(string: symbol).draw(
            at: NSPoint(x: rect.midX - symbolSize.width / 2, y: rect.midY - symbolSize.height / 2),
            withAttributes: attributes
        )
    }

    private static func drawMagnifierAnnotation(
        _ annotation: CaptureAnnotation,
        in context: CGContext,
        sourceImage: CGImage,
        scaleX: CGFloat,
        scaleY: CGFloat,
        lineScale: CGFloat
    ) {
        let rect = annotation.rect.standardized
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        let zoom = normalizedMagnifierZoom(annotation.effectiveMagnifierZoom)
        let shape = annotation.effectiveMagnifierShape
        let destination = CGRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        let imageBounds = CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
        let geometry = magnifierDrawGeometry(
            destination: destination,
            sourceBounds: imageBounds,
            zoom: zoom,
            contentXOffset: magnifierContentXOffset * scaleX,
            contentYOffset: magnifierContentYOffset * scaleY
        )

        context.saveGState()
        addMagnifierClip(shape: shape, rect: destination, to: context)
        context.clip()
        if let geometry {
            let cropRect = CGRect(
                x: geometry.integralSource.minX,
                y: CGFloat(sourceImage.height) - geometry.integralSource.maxY,
                width: geometry.integralSource.width,
                height: geometry.integralSource.height
            )
            if let crop = sourceImage.cropping(to: cropRect) {
                context.interpolationQuality = .none
                context.draw(crop, in: geometry.drawRect)
            }
        }
        context.restoreGState()

        strokeMagnifierBorder(annotation, in: context, rect: destination, shape: shape, lineScale: lineScale)
    }

    private static func strokeMagnifierBorder(
        _ annotation: CaptureAnnotation,
        in context: CGContext,
        rect: CGRect,
        shape: CaptureMagnifierShape,
        lineScale: CGFloat
    ) {
        context.saveGState()
        addMagnifierClip(
            shape: shape,
            rect: rect.insetBy(
                dx: annotation.style.strokeWidth * lineScale / 2,
                dy: annotation.style.strokeWidth * lineScale / 2
            ),
            to: context
        )
        context.setStrokeColor(cgColor(annotation.style.strokeColor))
        context.setLineWidth(annotation.style.strokeWidth * lineScale)
        context.strokePath()
        context.restoreGState()
    }

    struct MagnifierDrawGeometry {
        var integralSource: CGRect
        var drawRect: CGRect
    }

    static let magnifierContentXOffset: CGFloat = 12
    static let magnifierContentYOffset: CGFloat = 3

    static func magnifierDrawGeometry(
        destination: CGRect,
        sourceBounds: CGRect,
        zoom: CGFloat,
        contentXOffset: CGFloat = magnifierContentXOffset,
        contentYOffset: CGFloat = magnifierContentYOffset
    ) -> MagnifierDrawGeometry? {
        guard destination.width > 0, destination.height > 0 else {
            return nil
        }
        let normalizedZoom = normalizedMagnifierZoom(zoom)
        let sourceWidth = destination.width / normalizedZoom
        let sourceHeight = destination.height / normalizedZoom
        let centeredSourceX = destination.midX - sourceWidth / 2
        let horizontalInset = contentXOffset / normalizedZoom
        let shiftedSourceX = centeredSourceX - horizontalInset
        let shouldOffsetContentHorizontally = shiftedSourceX >= sourceBounds.minX
            && shiftedSourceX + sourceWidth <= sourceBounds.maxX
            && destination.minX > sourceBounds.minX
            && destination.maxX < sourceBounds.maxX
        let requestedSource = CGRect(
            x: shouldOffsetContentHorizontally ? shiftedSourceX : centeredSourceX,
            y: destination.midY - sourceHeight / 2,
            width: sourceWidth,
            height: sourceHeight
        )
        let clippedSource = requestedSource.intersection(sourceBounds)
        let integralSource = clippedSource.integral.intersection(sourceBounds)
        guard !integralSource.isNull, integralSource.width > 0, integralSource.height > 0 else {
            return nil
        }

        let xScale = destination.width / max(requestedSource.width, 1)
        let yScale = destination.height / max(requestedSource.height, 1)
        let drawWidth = integralSource.width * xScale
        let drawHeight = integralSource.height * yScale
        let visibleDestination = destination.intersection(sourceBounds)
        let visibleMinX = visibleDestination.isNull ? destination.minX : visibleDestination.minX
        let visibleMaxX = visibleDestination.isNull ? destination.maxX : visibleDestination.maxX
        let visibleMinY = visibleDestination.isNull ? destination.minY : visibleDestination.minY
        let visibleMaxY = visibleDestination.isNull ? destination.maxY : visibleDestination.maxY
        let drawX: CGFloat
        if integralSource.minX <= sourceBounds.minX, requestedSource.minX < sourceBounds.minX {
            drawX = visibleMinX
        } else if integralSource.maxX >= sourceBounds.maxX, requestedSource.maxX > sourceBounds.maxX {
            drawX = visibleMaxX - drawWidth
        } else {
            drawX = destination.minX + (integralSource.minX - requestedSource.minX) * xScale
        }
        let drawY: CGFloat
        if integralSource.minY <= sourceBounds.minY, requestedSource.minY < sourceBounds.minY {
            drawY = visibleMinY
        } else if integralSource.maxY >= sourceBounds.maxY, requestedSource.maxY > sourceBounds.maxY {
            drawY = visibleMaxY - drawHeight
        } else {
            drawY = destination.minY + (integralSource.minY - requestedSource.minY) * yScale
        }
        return MagnifierDrawGeometry(
            integralSource: integralSource,
            drawRect: CGRect(
                x: drawX,
                y: drawY + contentYOffset,
                width: drawWidth,
                height: drawHeight
            )
        )
    }

    static func normalizedMagnifierZoom(_ zoom: CGFloat) -> CGFloat {
        let candidates: [CGFloat] = [1.5, 2, 3, 4]
        return candidates.min(by: { abs($0 - zoom) < abs($1 - zoom) }) ?? 2
    }

    private static func addMagnifierClip(shape: CaptureMagnifierShape, rect: CGRect, to context: CGContext) {
        switch shape {
        case .circle:
            context.addEllipse(in: rect)
        case .rectangle:
            context.addRect(rect)
        }
    }

    private static func isMosaicAnnotation(_ annotation: CaptureAnnotation) -> Bool {
        annotation.kind == .mosaicStroke || annotation.kind == .mosaicRectangle
    }

    private static func drawMosaicAnnotation(
        _ annotation: CaptureAnnotation,
        in context: CGContext,
        scaleX: CGFloat,
        scaleY: CGFloat,
        contentOriginPixels: CGPoint,
        fullCanvasPixelHeight: CGFloat
    ) {
        let lineScale = (scaleX + scaleY) / 2
        if annotation.kind == .mosaicStroke {
            drawMosaicStroke(
                annotation,
                in: context,
                scaleX: scaleX,
                scaleY: scaleY,
                lineScale: lineScale,
                contentOriginPixels: contentOriginPixels,
                fullCanvasPixelHeight: fullCanvasPixelHeight
            )
            return
        }
        if annotation.kind == .mosaicRectangle {
            drawMosaicRectangle(
                annotation,
                in: context,
                scaleX: scaleX,
                scaleY: scaleY,
                contentOriginPixels: contentOriginPixels,
                fullCanvasPixelHeight: fullCanvasPixelHeight
            )
        }
    }

    private static func drawMosaicStroke(
        _ annotation: CaptureAnnotation,
        in context: CGContext,
        scaleX: CGFloat,
        scaleY: CGFloat,
        lineScale: CGFloat,
        contentOriginPixels: CGPoint,
        fullCanvasPixelHeight: CGFloat
    ) {
        guard
            let mosaicStroke = annotation.mosaicStroke,
            let redaction = annotation.mosaicRedaction,
            !mosaicStroke.points.isEmpty
        else {
            return
        }

        guard let strokePath = mosaicStrokeMaskPath(
            stroke: mosaicStroke,
            strokeWidth: annotation.style.strokeWidth * lineScale,
            scaleX: scaleX,
            scaleY: scaleY
        ) else {
            return
        }

        renderMosaicEffect(
            redaction: redaction,
            maskPath: strokePath,
            in: context,
            clipRect: mosaicStroke.boundingRect,
            scaleX: scaleX,
            scaleY: scaleY,
            contentOriginPixels: contentOriginPixels,
            fullCanvasPixelHeight: fullCanvasPixelHeight
        )
    }

    private static func drawMosaicRectangle(
        _ annotation: CaptureAnnotation,
        in context: CGContext,
        scaleX: CGFloat,
        scaleY: CGFloat,
        contentOriginPixels: CGPoint,
        fullCanvasPixelHeight: CGFloat
    ) {
        guard let redaction = annotation.mosaicRedaction else {
            return
        }

        let rect = annotation.rect.standardized
        let maskPath = mosaicRectangleMaskPath(for: annotation, scaleX: scaleX, scaleY: scaleY)
        renderMosaicEffect(
            redaction: redaction,
            maskPath: maskPath,
            in: context,
            clipRect: rect,
            scaleX: scaleX,
            scaleY: scaleY,
            contentOriginPixels: contentOriginPixels,
            fullCanvasPixelHeight: fullCanvasPixelHeight
        )
    }

    private static func rotatedRectanglePath(for rect: NSRect, angle: CGFloat, scaleX: CGFloat, scaleY: CGFloat) -> CGPath? {
        guard abs(angle) >= 0.001 else {
            return nil
        }

        let center = NSPoint(x: rect.midX, y: rect.midY)
        let points = [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.maxY),
        ].map { rotatedPoint($0, around: center, angle: angle) }

        let path = CGMutablePath()
        guard let first = points.first else {
            return nil
        }
        path.move(to: CGPoint(x: first.x * scaleX, y: first.y * scaleY))
        points.dropFirst().forEach { point in
            path.addLine(to: CGPoint(x: point.x * scaleX, y: point.y * scaleY))
        }
        path.closeSubpath()
        return path
    }

    private static func rotatedPoint(_ point: NSPoint, around center: NSPoint, angle: CGFloat) -> NSPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosine = cos(angle)
        let sine = sin(angle)
        return NSPoint(
            x: center.x + dx * cosine - dy * sine,
            y: center.y + dx * sine + dy * cosine
        )
    }

    private static func renderMosaicEffect(
        redaction: CaptureMosaicRedaction,
        maskPath: CGPath?,
        in context: CGContext,
        clipRect: NSRect,
        scaleX: CGFloat,
        scaleY: CGFloat,
        contentOriginPixels: CGPoint,
        fullCanvasPixelHeight: CGFloat
    ) {
        guard let displaySnapshot = snapshotContext(context) else {
            return
        }

        let imageSize = CGSize(width: displaySnapshot.width, height: displaySnapshot.height)
        guard
            let effectRect = mosaicEffectPixelRect(
                maskPath: maskPath,
                clipRect: clipRect,
                redaction: redaction,
                imageSize: imageSize,
                scaleX: scaleX,
                scaleY: scaleY,
                contentOriginPixels: contentOriginPixels,
                fullCanvasPixelHeight: fullCanvasPixelHeight
            ),
            let displayCrop = cropMosaicSnapshot(displaySnapshot, to: effectRect)
        else {
            return
        }

        let displayEffectImage = redactedImage(from: displayCrop, redaction: redaction)

        drawMosaicEffectImage(
            displayEffectImage,
            maskPath: maskPath,
            in: context,
            pixelDrawRect: effectRect
        )
    }

    private static func drawMosaicEffectImage(
        _ image: CGImage,
        maskPath: CGPath?,
        in context: CGContext,
        pixelDrawRect: CGRect
    ) {
        context.saveGState()
        if let maskPath {
            context.addPath(maskPath)
            context.clip()
        } else {
            context.clip(to: pixelDrawRect)
        }
        context.setBlendMode(.copy)
        context.draw(image, in: pixelDrawRect)
        context.restoreGState()
    }

    private static func mosaicEffectPixelRect(
        maskPath: CGPath?,
        clipRect: NSRect,
        redaction: CaptureMosaicRedaction,
        imageSize: CGSize,
        scaleX: CGFloat,
        scaleY: CGFloat,
        contentOriginPixels: CGPoint,
        fullCanvasPixelHeight: CGFloat
    ) -> CGRect? {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        var effectRect = CGRect(
            x: clipRect.minX * scaleX,
            y: clipRect.minY * scaleY,
            width: clipRect.width * scaleX,
            height: clipRect.height * scaleY
        ).standardized

        if let maskPath {
            let maskBounds = maskPath.boundingBoxOfPath.standardized
            if !maskBounds.isEmpty {
                effectRect = effectRect.union(maskBounds)
            }
        }

        let value = CGFloat(max(1, redaction.value))
        let padding: CGFloat
        switch redaction.type {
        case .gaussianBlur:
            padding = value * 3
        case .pixelMosaic:
            padding = value
        }

        effectRect = effectRect.insetBy(dx: -padding, dy: -padding)
        if redaction.type == .pixelMosaic {
            effectRect = alignedPixelMosaicEffectRect(
                effectRect,
                blockSize: value,
                contentOriginPixels: contentOriginPixels,
                fullCanvasPixelHeight: fullCanvasPixelHeight
            )
        }

        let clipped = effectRect.integral.intersection(imageBounds)
        return clipped.isEmpty ? nil : clipped
    }

    private static func alignedPixelMosaicEffectRect(
        _ rect: CGRect,
        blockSize: CGFloat,
        contentOriginPixels: CGPoint,
        fullCanvasPixelHeight: CGFloat
    ) -> CGRect {
        guard blockSize > 1 else {
            return rect
        }

        let minX = floor((rect.minX + contentOriginPixels.x) / blockSize) * blockSize - contentOriginPixels.x
        let maxX = ceil((rect.maxX + contentOriginPixels.x) / blockSize) * blockSize - contentOriginPixels.x
        let top = fullCanvasPixelHeight - (rect.maxY + contentOriginPixels.y)
        let bottom = fullCanvasPixelHeight - (rect.minY + contentOriginPixels.y)
        let alignedTop = floor(top / blockSize) * blockSize
        let alignedBottom = ceil(bottom / blockSize) * blockSize
        let minY = fullCanvasPixelHeight - contentOriginPixels.y - alignedBottom
        let maxY = fullCanvasPixelHeight - contentOriginPixels.y - alignedTop
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func cropMosaicSnapshot(
        _ image: CGImage,
        to pixelRect: CGRect
    ) -> CGImage? {
        let sourceRect = CGRect(
            x: pixelRect.minX,
            y: CGFloat(image.height) - pixelRect.maxY,
            width: pixelRect.width,
            height: pixelRect.height
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return sourceRect.isEmpty ? nil : image.cropping(to: sourceRect)
    }

    private static func snapshotContext(_ context: CGContext) -> CGImage? {
        guard
            let data = context.data,
            let colorSpace = context.colorSpace,
            let copy = CGContext(
                data: nil,
                width: context.width,
                height: context.height,
                bitsPerComponent: context.bitsPerComponent,
                bytesPerRow: context.bytesPerRow,
                space: colorSpace,
                bitmapInfo: context.bitmapInfo.rawValue
            ),
            let copyData = copy.data
        else {
            return context.makeImage()
        }
        memcpy(copyData, data, context.bytesPerRow * context.height)
        return copy.makeImage()
    }

    private static func mosaicStrokeMaskPath(
        stroke: CaptureMosaicStroke,
        strokeWidth: CGFloat,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) -> CGPath? {
        guard let firstPoint = stroke.points.first else {
            return nil
        }

        let first = pixelPoint(firstPoint, scaleX: scaleX, scaleY: scaleY)
        if stroke.points.count == 1 {
            let radius = max(1, strokeWidth / 2)
            let dotPath = CGMutablePath()
            dotPath.addEllipse(in: CGRect(x: first.x - radius, y: first.y - radius, width: radius * 2, height: radius * 2))
            return dotPath
        }

        let path = CGMutablePath()
        path.move(to: first)
        for point in stroke.points.dropFirst() {
            path.addLine(to: pixelPoint(point, scaleX: scaleX, scaleY: scaleY))
        }
        return strokeMaskPath(for: path, strokeWidth: strokeWidth)
    }

    private static func mosaicRectangleMaskPath(for annotation: CaptureAnnotation, scaleX: CGFloat, scaleY: CGFloat) -> CGPath? {
        let rect = annotation.rect.standardized
        if let rotatedPath = rotatedRectanglePath(for: rect, angle: annotation.rotationAngle, scaleX: scaleX, scaleY: scaleY) {
            return rotatedPath
        }

        let path = CGMutablePath()
        path.addRect(CGRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).standardized)
        return path
    }

    private static func strokeMaskPath(for path: CGPath, strokeWidth: CGFloat) -> CGPath {
        let mutable = CGMutablePath()
        mutable.addPath(path.copy(strokingWithWidth: max(1, strokeWidth), lineCap: .round, lineJoin: .round, miterLimit: 4))
        return mutable
    }

    private static func redactedImage(from cgImage: CGImage, redaction: CaptureMosaicRedaction) -> CGImage {
        switch redaction.type {
        case .pixelMosaic:
            return pixelMosaicImage(from: cgImage, blockSize: max(1, redaction.value))
        case .gaussianBlur:
            break
        }
        let input = CIImage(cgImage: cgImage).clampedToExtent()
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(input, forKey: kCIInputImageKey)
        filter?.setValue(Float(max(1, redaction.value)), forKey: kCIInputRadiusKey)

        let output = (filter?.outputImage ?? input).cropped(to: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return redactionContext.createCGImage(output, from: output.extent) ?? cgImage
    }

    private static func pixelMosaicImage(from cgImage: CGImage, blockSize: Int) -> CGImage {
        let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let block = max(1, blockSize)
        guard block > 1 else {
            return cgImage
        }

        let smallWidth = max(1, Int(ceil(CGFloat(cgImage.width) / CGFloat(block))))
        let smallHeight = max(1, Int(ceil(CGFloat(cgImage.height) / CGFloat(block))))
        guard
            let smallContext = makeRenderContext(width: smallWidth, height: smallHeight, colorSpace: colorSpace),
            let outputContext = makeRenderContext(width: cgImage.width, height: cgImage.height, colorSpace: colorSpace)
        else {
            return cgImage
        }

        smallContext.interpolationQuality = .high
        smallContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let smallImage = smallContext.makeImage() else {
            return cgImage
        }

        outputContext.interpolationQuality = .none
        outputContext.draw(smallImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return outputContext.makeImage() ?? cgImage
    }

    private static func drawMarkerLine(
        _ annotation: CaptureAnnotation,
        in context: CGContext,
        sourceImage: CGImage,
        scaleX: CGFloat,
        scaleY: CGFloat,
        lineScale: CGFloat
    ) {
        guard let markerLine = annotation.markerLine else {
            return
        }

        context.saveGState()
        let prefersNormalBlend = markerLinePrefersNormalBlend(markerLine, sourceImage: sourceImage, scaleX: scaleX, scaleY: scaleY)
        let strokeColor = visibleMarkerColor(annotation.style.strokeColor, onDarkBackground: prefersNormalBlend)
        context.setBlendMode(prefersNormalBlend ? .normal : .multiply)
        context.setStrokeColor(cgColor(strokeColor.withAlphaComponent(markerOpacity)))
        context.setLineWidth(annotation.style.strokeWidth * lineScale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setLineDash(phase: 0, lengths: [])

        let start = pixelPoint(markerLine.start, scaleX: scaleX, scaleY: scaleY)
        let end = pixelPoint(markerLine.end, scaleX: scaleX, scaleY: scaleY)
        if hypot(end.x - start.x, end.y - start.y) < 0.5 {
            let radius = annotation.style.strokeWidth * lineScale / 2
            context.setFillColor(cgColor(strokeColor.withAlphaComponent(markerOpacity)))
            context.fillEllipse(in: CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2))
            context.restoreGState()
            return
        }

        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func markerLinePrefersNormalBlend(
        _ markerLine: CaptureMarkerLine,
        sourceImage: CGImage,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) -> Bool {
        let sampleCount = 17
        var darkSamples = 0
        for index in 0..<sampleCount {
            let t = CGFloat(index) / CGFloat(sampleCount - 1)
            let point = CGPoint(
                x: (markerLine.start.x + (markerLine.end.x - markerLine.start.x) * t) * scaleX,
                y: (markerLine.start.y + (markerLine.end.y - markerLine.start.y) * t) * scaleY
            )
            guard let color = SelectionToolbarState.sampleColor(
                atPixelX: Int(point.x.rounded()),
                y: Int(point.y.rounded()),
                in: sourceImage
            ) else {
                continue
            }
            if colorPerceivedLuminance(color) < 0.12 {
                darkSamples += 1
            }
        }
        return darkSamples >= sampleCount * 3 / 4
    }

    private static func visibleMarkerColor(_ color: NSColor, onDarkBackground: Bool) -> NSColor {
        guard onDarkBackground, colorPerceivedLuminance(color) < 0.18 else {
            return color
        }
        return .white
    }

    private static func colorPerceivedLuminance(_ color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
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
            let capHalfWidth = ArrowHeadMetrics.barHalfWidth(strokeWidth)
            let capStart = CGPoint(x: tip.x + perp.dx * capHalfWidth, y: tip.y + perp.dy * capHalfWidth)
            let capEnd = CGPoint(x: tip.x - perp.dx * capHalfWidth, y: tip.y - perp.dy * capHalfWidth)
            let path = CGMutablePath()
            path.move(to: capStart)
            path.addLine(to: capEnd)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        case .dot:
            let radius = ArrowHeadMetrics.dotRadius(strokeWidth)
            context.fillEllipse(in: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
        case .diamond:
            let diamondLength = ArrowHeadMetrics.diamondLength(strokeWidth)
            let diamondHalfWidth = ArrowHeadMetrics.diamondHalfWidth(strokeWidth)
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
        case .arrowLine, .brush, .marker, .text, .numberSequence, .magnifier, .mosaicStroke, .mosaicRectangle:
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
