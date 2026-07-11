import AppKit
import CoreGraphics

enum TestImageFactory {
    static func fourCornerMarkers(width: Int = 24, height: Int = 20) -> NSImage {
        precondition(width > 1 && height > 1)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colors: [[UInt8]] = [
            [0, 0, 255, 255],
            [0, 255, 0, 255],
            [255, 0, 0, 255],
            [0, 255, 255, 255],
        ]
        for y in 0..<height {
            for x in 0..<width {
                let quadrant = (y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)
                let index = (y * width + x) * 4
                bytes.replaceSubrange(index..<(index + 4), with: colors[quadrant])
            }
        }
        return image(
            pixelWidth: width,
            pixelHeight: height,
            pointSize: CGSize(width: width, height: height),
            bytes: bytes
        )
    }

    static func solid(size: CGSize, color: NSColor, scale: CGFloat = 1) -> NSImage {
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)
        return solid(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            pointSize: size,
            color: color
        )
    }

    static func solid(
        pixelWidth: Int,
        pixelHeight: Int,
        pointSize: CGSize,
        color: NSColor
    ) -> NSImage {
        precondition(pixelWidth > 0 && pixelHeight > 0)

        let converted = color.usingColorSpace(.deviceRGB)!
        let red = UInt8((converted.redComponent * 255).rounded())
        let green = UInt8((converted.greenComponent * 255).rounded())
        let blue = UInt8((converted.blueComponent * 255).rounded())
        let alpha = UInt8((converted.alphaComponent * 255).rounded())
        let bytes = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        return image(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            pointSize: pointSize,
            bytes: bytes.enumerated().map { index, _ in
                switch index % 4 {
                case 0: blue
                case 1: green
                case 2: red
                default: alpha
                }
            }
        )
    }

    static func verticalDocumentViewport(
        offset: Int,
        width: Int = 64,
        height: Int = 96,
        scale: CGFloat = 1
    ) -> NSImage {
        precondition(offset >= 0 && width > 0 && height > 0 && scale > 0)
        let pixelWidth = Int(CGFloat(width) * scale)
        let pixelHeight = Int(CGFloat(height) * scale)
        var bytes = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        for y in 0..<pixelHeight {
            // CGImage providers are consumed in AppKit's bottom-up image space.
            // Reverse the fixture rows so the visual top maps to document offset
            // and increasing core row indices move down the document.
            let documentY = offset * Int(scale) + (pixelHeight - 1 - y)
            for x in 0..<pixelWidth {
                let index = (y * pixelWidth + x) * 4
                var bits = UInt32(truncatingIfNeeded: documentY) &* 0x9e37_79b9
                    ^ UInt32(truncatingIfNeeded: x) &* 0x85eb_ca6b
                bits ^= bits >> 16
                bits &*= 0x7feb_352d
                bits ^= bits >> 15
                let blue = UInt8(truncatingIfNeeded: bits)
                bytes[index] = blue
                bytes[index + 1] = blue ^ 0x35
                bytes[index + 2] = blue ^ 0xa7
                bytes[index + 3] = 255
            }
        }
        return image(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            pointSize: CGSize(width: width, height: height),
            bytes: bytes
        )
    }

    private static func image(
        pixelWidth: Int,
        pixelHeight: Int,
        pointSize: CGSize,
        bytes: [UInt8]
    ) -> NSImage {
        let data = Data(bytes) as CFData
        let provider = CGDataProvider(data: data)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            .union(.byteOrder32Little)
        let cgImage = CGImage(
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: pixelWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(representation)
        return image
    }
}
