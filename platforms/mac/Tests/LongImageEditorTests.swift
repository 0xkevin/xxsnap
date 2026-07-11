import AppKit
import XCTest
@testable import xxsnap

@MainActor
final class LongImageEditorTests: XCTestCase {
    func testGeometryStartsAtDocumentTopAndMapsViewportPoints() {
        let geometry = LongImageEditorGeometry(
            imageSize: NSSize(width: 1_000, height: 8_000),
            viewportSize: NSSize(width: 1_000, height: 760),
            scrollOffset: 0
        )

        XCTAssertEqual(geometry.fitWidthScale, 1, accuracy: 0.0001)
        XCTAssertEqual(geometry.visibleImageRect, NSRect(x: 0, y: 0, width: 1_000, height: 760))
        XCTAssertEqual(geometry.imagePoint(forViewportPoint: NSPoint(x: 50, y: 80)), NSPoint(x: 50, y: 80))
    }

    func testGeometryIncludesTopOriginScrollOffset() {
        let geometry = LongImageEditorGeometry(
            imageSize: NSSize(width: 1_000, height: 8_000),
            viewportSize: NSSize(width: 500, height: 400),
            scrollOffset: 600
        )

        XCTAssertEqual(geometry.fitWidthScale, 0.5, accuracy: 0.0001)
        XCTAssertEqual(geometry.visibleImageRect, NSRect(x: 0, y: 600, width: 1_000, height: 800))
        XCTAssertEqual(geometry.imagePoint(forViewportPoint: NSPoint(x: 100, y: 80)), NSPoint(x: 200, y: 760))
    }

    func testRetinaBackingScaleDoesNotChangePointGeometry() throws {
        let image = TestImageFactory.solid(size: NSSize(width: 1_000, height: 8_000), color: .white, scale: 2)
        let controller = LongImageEditorWindowController(
            image: image,
            visibleFrame: NSRect(x: 0, y: 0, width: 1_200, height: 900),
            initialWindowSize: NSSize(width: 1_000, height: 840)
        )

        XCTAssertEqual(controller.imagePixelSize, NSSize(width: 2_000, height: 16_000))
        XCTAssertEqual(controller.fitWidthScale, 1, accuracy: 0.0001)
        XCTAssertEqual(controller.visibleImageRect.minY, 0, accuracy: 0.0001)
    }

    func testTranslationCoversEveryCoordinateBearingAnnotationFieldAndMask() {
        let offset = NSPoint(x: 12, y: 300)
        let annotation = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 20, y: 320, width: 80, height: 60),
            style: CaptureAnnotationStyle(),
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 20, y: 320),
                end: NSPoint(x: 100, y: 380),
                control: NSPoint(x: 60, y: 340),
                startArrowType: .dot,
                endArrowType: .normal
            ),
            brushPath: CaptureBrushPath(points: [NSPoint(x: 30, y: 330)]),
            markerLine: CaptureMarkerLine(start: NSPoint(x: 40, y: 340), end: NSPoint(x: 50, y: 350)),
            mosaicStroke: CaptureMosaicStroke(points: [NSPoint(x: 70, y: 360)])
        )

        let translated = LongImageAnnotationTranslation.annotation(annotation, by: offset)
        XCTAssertEqual(translated.rect.origin, NSPoint(x: 32, y: 620))
        XCTAssertEqual(translated.arrowLine?.start, NSPoint(x: 32, y: 620))
        XCTAssertEqual(translated.arrowLine?.end, NSPoint(x: 112, y: 680))
        XCTAssertEqual(translated.arrowLine?.control, NSPoint(x: 72, y: 640))
        XCTAssertEqual(translated.brushPath?.points, [NSPoint(x: 42, y: 630)])
        XCTAssertEqual(translated.markerLine?.start, NSPoint(x: 52, y: 640))
        XCTAssertEqual(translated.markerLine?.end, NSPoint(x: 62, y: 650))
        XCTAssertEqual(translated.mosaicStroke?.points, [NSPoint(x: 82, y: 660)])

        let mask = EraserMask(rect: NSRect(x: 10, y: 310, width: 20, height: 30), affectedAnnotationIDs: [annotation.id])
        XCTAssertEqual(LongImageAnnotationTranslation.mask(mask, by: offset).rect.origin, NSPoint(x: 22, y: 610))
    }

    func testTranslationScalesBetweenImageAndViewportCoordinatesWithoutDrift() {
        let original = CaptureAnnotation(
            kind: .brush,
            rect: NSRect(x: 20, y: 620, width: 80, height: 40),
            style: CaptureAnnotationStyle(),
            brushPath: CaptureBrushPath(points: [NSPoint(x: 20, y: 620), NSPoint(x: 100, y: 660)])
        )
        let viewport = LongImageAnnotationTranslation.annotation(
            original,
            fromImageSliceOrigin: NSPoint(x: 0, y: 600),
            displayScale: 0.5
        )
        XCTAssertEqual(viewport.rect, NSRect(x: 10, y: 10, width: 40, height: 20))
        XCTAssertEqual(viewport.brushPath?.points, [NSPoint(x: 10, y: 10), NSPoint(x: 50, y: 30)])

        let restored = LongImageAnnotationTranslation.annotation(
            viewport,
            toImageSliceOrigin: NSPoint(x: 0, y: 600),
            displayScale: 0.5
        )
        XCTAssertEqual(restored.rect, original.rect)
        XCTAssertEqual(restored.brushPath?.points, original.brushPath?.points)
    }

    func testVisibleSliceFiltersAndTranslatesWithoutChangingOrderOrIDs() {
        let style = CaptureAnnotationStyle()
        let first = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 20, width: 30, height: 30), style: style)
        let second = CaptureAnnotation(kind: .text, rect: NSRect(x: 10, y: 620, width: 80, height: 30), style: style, text: "second")
        let third = CaptureAnnotation(kind: .numberSequence, rect: NSRect(x: 10, y: 680, width: 30, height: 30), style: style, numberSequenceIndex: 1)
        let slice = LongImageEditorDocument.visibleSlice(
            image: TestImageFactory.solid(size: NSSize(width: 200, height: 1_000), color: .white),
            annotations: [first, second, third],
            eraserMasks: [],
            imageRect: NSRect(x: 0, y: 600, width: 200, height: 100)
        )

        XCTAssertEqual(slice.annotations.map(\.id), [second.id, third.id])
        XCTAssertEqual(slice.annotations[0].rect.minY, 20, accuracy: 0.0001)
        XCTAssertEqual(slice.annotations[1].rect.minY, 80, accuracy: 0.0001)
        XCTAssertEqual(slice.image.size, NSSize(width: 200, height: 100))
    }

    func testResizePreservesTopVisibleCenterAnchor() {
        let before = LongImageEditorGeometry(
            imageSize: NSSize(width: 1_000, height: 8_000),
            viewportSize: NSSize(width: 800, height: 600),
            scrollOffset: 2_000
        )
        let anchor = before.topVisibleCenter
        let after = before.resized(viewportSize: NSSize(width: 1_000, height: 700), preserving: anchor)

        XCTAssertEqual(after.topVisibleCenter.x, anchor.x, accuracy: 0.0001)
        XCTAssertEqual(after.topVisibleCenter.y, anchor.y, accuracy: 0.0001)
        XCTAssertEqual(after.fitWidthScale, 1, accuracy: 0.0001)
    }

    func testWindowIsTitledResizableBoundedAndToolbarIsOutsideScrollView() {
        let visible = NSRect(x: 20, y: 40, width: 1_200, height: 900)
        let controller = LongImageEditorWindowController(
            image: TestImageFactory.solid(size: NSSize(width: 1_000, height: 8_000), color: .white),
            visibleFrame: visible,
            initialWindowSize: NSSize(width: 1_400, height: 1_100)
        )

        let window = try! XCTUnwrap(controller.window)
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(visible.contains(window.frame))
        XCTAssertFalse(controller.scrollView.isDescendant(of: controller.controlStripView))
        XCTAssertFalse(controller.controlStripView.isDescendant(of: controller.scrollView))
    }

    func testLongImageConfigurationUsesEditorContract() {
        let configuration = SelectionOverlayConfiguration.longImageEditor(
            windowFrame: NSRect(x: 0, y: 0, width: 500, height: 400),
            selectionRect: NSRect(x: 0, y: 0, width: 500, height: 400)
        )

        XCTAssertEqual(configuration.hiddenMainToolbarButtons, [.scroll, .cancel, .pin])
        XCTAssertTrue(configuration.showsFinishEditingButton)
        XCTAssertFalse(configuration.allowsSelectionGeometryEditing)
        XCTAssertFalse(configuration.showsSelectionBorder)
        XCTAssertFalse(configuration.showsSelectionMeasurementControl)
        XCTAssertFalse(configuration.allowsPassiveColorSampler)
        XCTAssertEqual(configuration.outsideSelectionDimAlpha, 0)
    }

    func testFullLongImageRendererPreservesPixelDimensions() throws {
        let image = TestImageFactory.solid(size: NSSize(width: 120, height: 600), color: .white, scale: 2)
        var style = CaptureAnnotationStyle()
        style.strokeColor = .red
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 400, width: 40, height: 40), style: style)

        let output = CaptureAnnotationRenderer.renderLongImage(image: image, annotations: [annotation], eraserMasks: [])
        let cgImage = try XCTUnwrap(output.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cgImage.width, 240)
        XCTAssertEqual(cgImage.height, 1_200)
    }
}
