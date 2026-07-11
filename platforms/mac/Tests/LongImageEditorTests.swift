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

    func testVisibleRendererMatchesCompleteLongImageCropForAnnotationMatrixAtRetinaScale() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 160, height: 1_200, scale: 2)
        let sliceRect = NSRect(x: 0, y: 160, width: 160, height: 240)
        var red = CaptureAnnotationStyle()
        red.strokeColor = .red
        red.strokeWidth = 4
        var mosaicStyle = CaptureAnnotationStyle()
        mosaicStyle.strokeWidth = 18
        var magnifierStyle = CaptureAnnotationStyle()
        magnifierStyle.strokeColor = .blue
        magnifierStyle.strokeWidth = 3

        let rectangle = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 12, y: 145, width: 70, height: 65), style: red)
        let text = CaptureAnnotation(kind: .text, rect: NSRect(x: 18, y: 220, width: 110, height: 45), style: red, text: "Long")
        let mosaicRectangle = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 30, y: 275, width: 80, height: 55),
            style: mosaicStyle,
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )
        let mosaicStroke = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: NSRect(x: 20, y: 330, width: 100, height: 45),
            style: mosaicStyle,
            mosaicStroke: CaptureMosaicStroke(points: [NSPoint(x: 20, y: 335), NSPoint(x: 120, y: 370)]),
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 6)
        )
        let magnifier = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 88, y: 175, width: 58, height: 58),
            style: magnifierStyle,
            magnifierShape: .circle,
            magnifierZoom: 2
        )
        let erasedRectangle = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 55, y: 245, width: 80, height: 65), style: red)
        let eraser = EraserMask(rect: NSRect(x: 75, y: 260, width: 25, height: 30), affectedAnnotationIDs: [erasedRectangle.id])

        let cases: [(String, [CaptureAnnotation], [EraserMask])] = [
            ("rectangle-boundary", [rectangle], []),
            ("text", [text], []),
            ("mosaic-rectangle", [mosaicRectangle], []),
            ("mosaic-stroke-boundary", [mosaicStroke], []),
            ("magnifier-source-context", [magnifier], []),
            ("eraser-affected-id", [erasedRectangle], [eraser]),
            ("combined-z-order", [rectangle, text, mosaicRectangle, magnifier, erasedRectangle], [eraser]),
        ]

        for (name, annotations, masks) in cases {
            let full = CaptureAnnotationRenderer.renderCompleteLongImage(image: image, annotations: annotations, eraserMasks: masks)
            let expected = try cropTopOrigin(full, rect: sliceRect)
            let actual = CaptureAnnotationRenderer.renderVisibleLongImageSlice(
                image: image,
                annotations: annotations,
                eraserMasks: masks,
                imageRect: sliceRect
            )
            XCTAssertEqual(pixelSize(actual), pixelSize(expected), name)
            XCTAssertEqual(try pixelBytes(actual), try pixelBytes(expected), name)
        }
    }

    func testVisibleRendererProcessingRegionIsBoundedForLongDocuments() {
        let processing = CaptureAnnotationRenderer.visibleLongImageProcessingRect(
            imageSize: NSSize(width: 1_000, height: 8_000),
            imageRect: NSRect(x: 0, y: 3_000, width: 1_000, height: 700)
        )
        XCTAssertEqual(processing, NSRect(x: 0, y: 2_744, width: 1_000, height: 1_212))
        XCTAssertLessThan(processing.height, 8_000)
    }

    func testEditorInteractionCallbacksLockAndUnlockDocumentScrolling() throws {
        let controller = LongImageEditorWindowController(
            image: TestImageFactory.solid(size: NSSize(width: 200, height: 1_000), color: .white),
            visibleFrame: NSRect(x: 0, y: 0, width: 600, height: 500),
            initialWindowSize: NSSize(width: 400, height: 420)
        )
        controller.show()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        overlay.test_activateShapeTool(.rectangle)
        overlay.test_mouseDown(at: NSPoint(x: 40, y: 80))
        XCTAssertFalse(controller.test_isDocumentScrollingEnabled)
        overlay.test_mouseDragged(to: NSPoint(x: 120, y: 150))
        overlay.test_mouseUp(at: NSPoint(x: 120, y: 150))
        XCTAssertTrue(controller.test_isDocumentScrollingEnabled)
        controller.stop()
    }

    func testStopIsIdempotentRemovesObserverAndIgnoresLaterBoundsNotifications() throws {
        let controller = LongImageEditorWindowController(
            image: TestImageFactory.solid(size: NSSize(width: 120, height: 800), color: .white),
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 400)
        )
        controller.show()
        XCTAssertTrue(controller.test_hasBoundsObserver)
        controller.stop()
        controller.stop()
        XCTAssertFalse(controller.test_hasBoundsObserver)
        let refreshCount = controller.test_viewportRefreshCount
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: controller.scrollView.contentView)
        XCTAssertEqual(controller.test_viewportRefreshCount, refreshCount)
        XCTAssertNil(controller.test_editingOverlay)
    }

    func testCloseReleasesEditorOverlayAndSeedImage() {
        weak var weakController: LongImageEditorWindowController?
        weak var weakOverlay: SelectionOverlayWindow?
        weak var weakImage: NSImage?
        var retainedController: LongImageEditorWindowController?
        autoreleasepool {
            var image: NSImage? = TestImageFactory.solid(size: NSSize(width: 120, height: 800), color: .white)
            retainedController = LongImageEditorWindowController(
                image: image!, visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 400)
            )
            retainedController?.show()
            weakController = retainedController
            weakOverlay = retainedController?.test_editingOverlay
            weakImage = image
            retainedController?.stop()
            image = nil
        }
        XCTAssertNil(weakOverlay)
        XCTAssertNil(weakImage)
        XCTAssertNotNil(weakController)
        retainedController = nil
        XCTAssertNil(weakController)
    }

    private func cropTopOrigin(_ image: NSImage, rect: NSRect) throws -> NSImage {
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let sx = CGFloat(cg.width) / image.size.width
        let sy = CGFloat(cg.height) / image.size.height
        let pixels = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy).integral
        return NSImage(cgImage: try XCTUnwrap(cg.cropping(to: pixels)), size: rect.size)
    }

    private func pixelSize(_ image: NSImage) -> NSSize {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .zero }
        return NSSize(width: cg.width, height: cg.height)
    }

    private func pixelBytes(_ image: NSImage) throws -> Data {
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return try XCTUnwrap(cg.dataProvider?.data) as Data
    }
}
