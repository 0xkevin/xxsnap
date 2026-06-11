import AppKit

enum CaptureCompletionAction {
    case copy
    case save
}

enum CaptureAnnotationKind {
    case rectangle
    case ellipse
}

enum CaptureStrokePattern: Int, CaseIterable {
    case solid
    case dashLong
    case dashNarrow
    case dashLongShort

    var title: String {
        switch self {
        case .solid:
            return "实心线条"
        case .dashLong:
            return "长虚线线条"
        case .dashNarrow:
            return "窄虚线线条"
        case .dashLongShort:
            return "一长一短的虚线线条"
        }
    }

    var dashPattern: [CGFloat] {
        switch self {
        case .solid:
            return []
        case .dashLong:
            return [8, 4]
        case .dashNarrow:
            return [4, 2]
        case .dashLongShort:
            return [8, 3, 2, 3]
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

        let renderedImage = NSImage(size: image.size)
        renderedImage.lockFocus()
        NSGraphicsContext.current?.shouldAntialias = true
        image.draw(in: NSRect(origin: .zero, size: image.size))

        for annotation in annotations {
            draw(annotation)
        }

        renderedImage.unlockFocus()
        return renderedImage
    }

    private static func draw(_ annotation: CaptureAnnotation) {
        let rect = annotation.rect.standardized.insetBy(dx: annotation.style.strokeWidth / 2, dy: annotation.style.strokeWidth / 2)
        let path: NSBezierPath

        switch annotation.kind {
        case .rectangle where annotation.style.cornerRadius > 0:
            path = NSBezierPath(
                roundedRect: rect,
                xRadius: annotation.style.cornerRadius,
                yRadius: annotation.style.cornerRadius
            )
        case .rectangle:
            path = NSBezierPath(rect: rect)
        case .ellipse:
            path = NSBezierPath(ovalIn: rect)
        }

        if annotation.style.fillEnabled {
            annotation.style.fillColor.setFill()
            path.fill()
        }

        annotation.style.strokeColor.setStroke()
        path.lineWidth = annotation.style.strokeWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.setLineDash(annotation.style.strokePattern.dashPattern, count: annotation.style.strokePattern.dashPattern.count, phase: 0)
        path.stroke()
    }
}
