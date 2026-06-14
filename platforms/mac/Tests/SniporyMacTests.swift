import AppKit
import XCTest
@testable import Snipory

final class SniporyMacTests: XCTestCase {
    func testAnnotationRendererDrawsRectangleOntoImage() throws {
        let image = NSImage(size: NSSize(width: 40, height: 40))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 40).fill()
        image.unlockFocus()

        var style = CaptureAnnotationStyle()
        style.fillEnabled = true
        style.strokeColor = .systemRed
        style.fillColor = .systemRed

        let rendered = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 20, height: 20), style: style)]
        )

        XCTAssertEqual(pixelColor(in: rendered, x: 40, y: 40)?.alphaComponent, 1)
    }

    @MainActor
    func testCropPreservesRetinaPixelDimensions() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 100, height: 50),
            pixelWidth: 200,
            pixelHeight: 100
        )

        let cropped = try XCTUnwrap(
            CaptureCoordinator.crop(image: image, rect: NSRect(x: 10, y: 5, width: 40, height: 20))
        )
        let cgImage = try XCTUnwrap(cropped.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(cropped.size, NSSize(width: 40, height: 20))
        XCTAssertEqual(cgImage.width, 80)
        XCTAssertEqual(cgImage.height, 40)
    }

    func testAnnotationRendererPreservesRetinaPixelDimensions() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 40, height: 40),
            pixelWidth: 80,
            pixelHeight: 80
        )
        var style = CaptureAnnotationStyle()
        style.fillEnabled = true
        style.strokeColor = .systemRed
        style.fillColor = .systemRed

        let rendered = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 20, height: 20), style: style)]
        )
        let cgImage = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(rendered.size, NSSize(width: 40, height: 40))
        XCTAssertEqual(cgImage.width, 80)
        XCTAssertEqual(cgImage.height, 80)
    }

    private func pixelColor(in image: NSImage, x: Int, y: Int) -> NSColor? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.colorAt(x: x, y: y)
    }

    private func makeBitmapImage(pointSize: NSSize, pixelWidth: Int, pixelHeight: Int) throws -> NSImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        let cgImage = try XCTUnwrap(context.makeImage())
        return NSImage(cgImage: cgImage, size: pointSize)
    }
}
