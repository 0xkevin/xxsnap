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
        }

        context.saveGState()
        context.addPath(path)
        if annotation.style.fillEnabled {
            context.setFillColor(cgColor(annotation.style.fillColor))
            context.fillPath()
        }

        context.addPath(path)
        context.setStrokeColor(cgColor(annotation.style.strokeColor))
        context.setLineWidth(annotation.style.strokeWidth * lineScale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setLineDash(
            phase: 0,
            lengths: annotation.style.strokePattern.dashPattern.map { $0 * lineScale }
        )
        context.strokePath()
        context.restoreGState()
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
