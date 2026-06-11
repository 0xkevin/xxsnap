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

        XCTAssertEqual(pixelColor(in: rendered, x: 20, y: 20)?.alphaComponent, 1)
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
}
