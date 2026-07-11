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

    func testVisibleSliceUsesRendererVisualBoundsForVisualOnlyIntersection() {
        var style = CaptureAnnotationStyle(); style.strokeWidth = 160
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 40, y: 300, width: 60, height: 50),
            style: style,
            rotationAngle: .pi / 4
        )
        let slice = LongImageEditorDocument.visibleSlice(
            image: TestImageFactory.solid(size: NSSize(width: 200, height: 1_000), color: .white),
            annotations: [annotation], eraserMasks: [],
            imageRect: NSRect(x: 0, y: 430, width: 200, height: 150)
        )
        XCTAssertEqual(slice.annotations.map(\.id), [annotation.id])
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
        XCTAssertEqual(processing, NSRect(x: 0, y: 3_000, width: 1_000, height: 700))
        XCTAssertLessThan(processing.height, 8_000)
    }

    func testOverlayWheelScrollsDocumentInsteadOfZoomingSelectionAndIsIgnoredWhileLocked() throws {
        let controller = makeTallController()
        controller.show()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let before = controller.visibleImageRect.minY
        overlay.test_scrollWheel(at: NSPoint(x: 100, y: 100), deltaY: -120)
        XCTAssertGreaterThan(controller.visibleImageRect.minY, before)

        overlay.test_activateShapeTool(.rectangle)
        overlay.test_mouseDown(at: NSPoint(x: 30, y: 40))
        let locked = controller.visibleImageRect.minY
        overlay.test_scrollWheel(at: NSPoint(x: 100, y: 100), deltaY: -120)
        XCTAssertEqual(controller.visibleImageRect.minY, locked, accuracy: 0.001)
        overlay.test_mouseUp(at: NSPoint(x: 60, y: 80))
        controller.stop()
    }

    func testMovingWindowRealignsOverlayToViewportScreenFrame() throws {
        let controller = makeTallController()
        controller.show()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let before = overlay.frame
        let windowOrigin = try XCTUnwrap(controller.window).frame.origin
        controller.window?.setFrameOrigin(NSPoint(x: 90, y: 70))
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        let after = overlay.frame
        XCTAssertEqual(after.origin.x - before.origin.x, 90 - windowOrigin.x, accuracy: 0.001)
        XCTAssertEqual(after.origin.y - before.origin.y, 70 - windowOrigin.y, accuracy: 0.001)
        controller.stop()
    }

    func testMovingWindowCommitsActiveTextSnapshotBeforeRefreshingOverlay() throws {
        let text = CaptureAnnotation(kind: .text, rect: NSRect(x: 20, y: 40, width: 120, height: 50), style: CaptureAnnotationStyle(), text: "draft")
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(size: NSSize(width: 200, height: 1_200), color: .white),
            annotations: [text], visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450)
        )
        controller.show()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        var edited = try XCTUnwrap(overlay.test_annotation(at: 0)); edited.text = "committed on move"
        overlay.test_setAnnotations([edited])
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        XCTAssertEqual(controller.test_fullAnnotations[0].text, "committed on move")
        XCTAssertEqual(controller.test_editingOverlay?.test_annotation(at: 0)?.text, "committed on move")
        controller.stop()
    }

    func testControlStripContainsAccessibleFinishButtonAndCommitsCurrentEdits() throws {
        let controller = makeTallController()
        var completionCount = 0
        var completedAnnotations: [CaptureAnnotation] = []
        controller.onFinishEditing = { _, annotations, _ in
            completionCount += 1
            completedAnnotations = annotations
        }
        controller.show()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        overlay.test_activateShapeTool(.rectangle)
        overlay.test_drag(from: NSPoint(x: 40, y: 80), to: NSPoint(x: 120, y: 150))
        let button = controller.test_finishButton
        XCTAssertTrue(button.isDescendant(of: controller.controlStripView))
        XCTAssertEqual(button.title, "完成编辑")
        XCTAssertEqual(button.accessibilityLabel(), "完成编辑")
        button.performClick(nil)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(completedAnnotations.count, 1)
    }

    func testSeedInitializerConvertsBottomOriginSeedCoordinatesToTopCanonical() throws {
        let frozen = TestImageFactory.solid(size: NSSize(width: 200, height: 300), color: .white)
        let style = CaptureAnnotationStyle()
        let annotation = CaptureAnnotation(
            kind: .brush,
            rect: NSRect(x: 20, y: 40, width: 60, height: 30),
            style: style,
            brushPath: CaptureBrushPath(points: [NSPoint(x: 20, y: 40), NSPoint(x: 80, y: 70)])
        )
        let mask = EraserMask(rect: NSRect(x: 30, y: 45, width: 20, height: 10), affectedAnnotationIDs: [annotation.id])
        let seed = ScrollCaptureSeed(screenRect: .zero, snapshotRect: .zero, frozenImage: frozen, annotations: [annotation], eraserMasks: [mask])
        let controller = LongImageEditorWindowController(
            image: TestImageFactory.solid(size: NSSize(width: 200, height: 1_200), color: .white),
            seed: seed,
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450)
        )
        XCTAssertEqual(controller.test_fullAnnotations[0].rect.minY, 230, accuracy: 0.001)
        XCTAssertEqual(controller.test_fullAnnotations[0].brushPath?.points.map(\.y), [260, 230])
        XCTAssertEqual(controller.test_fullEraserMasks[0].rect.minY, 245, accuracy: 0.001)
        controller.stop()
    }

    func testSeedAnnotationStaysAtTopAfterScrollingAwayAndBack() throws {
        let frozen = TestImageFactory.solid(size: NSSize(width: 200, height: 300), color: .white)
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 20, y: 220, width: 50, height: 40), style: CaptureAnnotationStyle())
        let seed = ScrollCaptureSeed(screenRect: .zero, snapshotRect: .zero, frozenImage: frozen, annotations: [annotation], eraserMasks: [])
        let controller = LongImageEditorWindowController(
            image: TestImageFactory.solid(size: NSSize(width: 200, height: 1_400), color: .white),
            seed: seed,
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450)
        )
        controller.show()
        var overlay = try XCTUnwrap(controller.test_editingOverlay)
        let canonicalID = try XCTUnwrap(overlay.test_annotation(at: 0)).id
        overlay.test_scrollWheel(at: NSPoint(x: 100, y: 100), deltaY: -600)
        XCTAssertNil(overlay.test_annotation(at: 0))
        overlay.test_scrollWheel(at: NSPoint(x: 100, y: 100), deltaY: 600)
        overlay = try XCTUnwrap(controller.test_editingOverlay)
        XCTAssertEqual(overlay.test_annotation(at: 0)?.id, canonicalID)
        XCTAssertEqual(controller.test_fullAnnotations[0].rect.minY, 40, accuracy: 0.001)
        controller.stop()
    }

    func testLongImageRendererAPIsShareTopOriginContract() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 100, height: 500, scale: 2)
        var style = CaptureAnnotationStyle(); style.strokeColor = .red
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 20, width: 40, height: 30), style: style)
        let first = CaptureAnnotationRenderer.renderLongImage(image: image, annotations: [annotation], eraserMasks: [])
        let second = CaptureAnnotationRenderer.renderCompleteLongImage(image: image, annotations: [annotation], eraserMasks: [])
        XCTAssertEqual(try pixelBytes(first), try pixelBytes(second))
    }

    func testVisibleRendererMatchesForNonAlignedOriginAndMultiplePixelBlockSizes() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 220, height: 1_600, scale: 2)
        let rect = NSRect(x: 20, y: 503, width: 180, height: 260)
        var style = CaptureAnnotationStyle(); style.strokeWidth = 22
        let first = CaptureAnnotation(kind: .mosaicRectangle, rect: NSRect(x: 60, y: 520, width: 70, height: 90), style: style, mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 7))
        let second = CaptureAnnotation(kind: .mosaicRectangle, rect: NSRect(x: 100, y: 640, width: 80, height: 80), style: style, mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 13))
        let third = CaptureAnnotation(kind: .mosaicRectangle, rect: NSRect(x: 120, y: 725, width: 70, height: 34), style: style, mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 17))
        let annotations = [first, second, third]
        let full = CaptureAnnotationRenderer.renderCompleteLongImage(image: image, annotations: annotations, eraserMasks: [])
        let expected = try cropTopOrigin(full, rect: rect)
        let actual = CaptureAnnotationRenderer.renderVisibleLongImageSlice(image: image, annotations: annotations, eraserMasks: [], imageRect: rect)
        XCTAssertEqual(pixelSize(actual), pixelSize(expected))
        XCTAssertEqual(try pixelBytes(actual), try pixelBytes(expected))
        let processing = CaptureAnnotationRenderer.visibleLongImageProcessingRect(imageSize: image.size, imageRect: rect, annotations: annotations)
        XCTAssertNotEqual(processing.minY.truncatingRemainder(dividingBy: 7), 0)
        XCTAssertGreaterThan(processing.minX, 0)
        XCTAssertLessThan(processing.height, rect.height + 300)
        XCTAssertLessThan(processing.height, image.size.height)
    }

    func testVisibleRenderPlanSelectsOnlyVisualIntersectionsFromLargeAnnotationCollection() {
        let style = CaptureAnnotationStyle()
        var annotations = (0..<10_000).map { index in
            CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: CGFloat(index * 20), width: 20, height: 10), style: style)
        }
        var crossingStyle = style; crossingStyle.strokeWidth = 120
        let crossing = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 80, y: 4_850, width: 30, height: 30), style: crossingStyle, rotationAngle: .pi / 4)
        annotations.append(crossing)
        let plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: NSSize(width: 200, height: 220_000),
            imageRect: NSRect(x: 0, y: 5_000, width: 200, height: 400),
            annotations: annotations,
            eraserMasks: []
        )
        XCTAssertLessThan(plan.annotationCount, 60)
        XCTAssertTrue(plan.annotationIDs.contains(crossing.id))
        XCTAssertLessThan(plan.processingRect.height, 1_000)
    }

    func testDynamicVisualBoundsPreserveRotatedHugeStrokeAndTextAcrossSliceBoundary() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 240, height: 1_800, scale: 2)
        let rect = NSRect(x: 0, y: 700, width: 240, height: 260)
        var huge = CaptureAnnotationStyle(); huge.strokeColor = .red; huge.strokeWidth = 180
        var textStyle = CaptureAnnotationStyle(); textStyle.strokeColor = .blue; textStyle.textSize = 72
        let rotated = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 80, y: 580, width: 90, height: 80), style: huge, rotationAngle: .pi / 4)
        let text = CaptureAnnotation(kind: .text, rect: NSRect(x: 20, y: 930, width: 200, height: 90), style: textStyle, rotationAngle: -.pi / 8, text: "Boundary")
        let annotations = [rotated, text]
        let processing = CaptureAnnotationRenderer.visibleLongImageProcessingRect(imageSize: image.size, imageRect: rect, annotations: annotations)
        XCTAssertLessThan(processing.minY, rect.minY - 100)
        XCTAssertGreaterThan(processing.maxY, rect.maxY + 40)
        XCTAssertLessThan(processing.height, image.size.height)
        let full = CaptureAnnotationRenderer.renderCompleteLongImage(image: image, annotations: annotations, eraserMasks: [])
        let expected = try cropTopOrigin(full, rect: rect)
        let actual = CaptureAnnotationRenderer.renderVisibleLongImageSlice(image: image, annotations: annotations, eraserMasks: [], imageRect: rect)
        XCTAssertEqual(try pixelBytes(actual), try pixelBytes(expected))
    }

    func testInteractionLockRestoresProgrammaticClipMovementBeforeCommit() throws {
        let controller = makeTallController()
        controller.show()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        overlay.test_activateShapeTool(.rectangle)
        overlay.test_mouseDown(at: NSPoint(x: 30, y: 40))
        let origin = controller.scrollView.contentView.bounds.origin
        controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: origin.y + 200))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: controller.scrollView.contentView)
        XCTAssertEqual(controller.scrollView.contentView.bounds.origin, origin)
        overlay.test_mouseUp(at: NSPoint(x: 60, y: 80))
        controller.stop()
    }

    func testCommitUsesPresentedIDsAndCleansDeletedAnnotationFromOffscreenMasks() throws {
        let style = CaptureAnnotationStyle()
        let visible = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 20, width: 40, height: 40), style: style)
        let offscreen = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 700, width: 40, height: 40), style: style)
        let hiddenMask = EraserMask(rect: NSRect(x: 5, y: 650, width: 20, height: 20), affectedAnnotationIDs: [visible.id, offscreen.id])
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(size: NSSize(width: 200, height: 1_000), color: .white),
            annotations: [visible, offscreen], eraserMasks: [hiddenMask],
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450)
        )
        controller.show()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        overlay.test_setAnnotations([])
        controller.test_commitOverlay()
        XCTAssertEqual(controller.test_fullAnnotations.map(\.id), [offscreen.id])
        XCTAssertEqual(controller.test_fullEraserMasks.count, 1)
        XCTAssertEqual(controller.test_fullEraserMasks[0].affectedAnnotationIDs, [offscreen.id])
        controller.stop()
    }

    func testCommitPreservesUnpresentedMaskAndAddsNewTranslatedMask() throws {
        let style = CaptureAnnotationStyle()
        let visible = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 20, width: 40, height: 40), style: style)
        let offscreen = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 700, width: 40, height: 40), style: style)
        let hiddenMask = EraserMask(rect: NSRect(x: 15, y: 25, width: 10, height: 10), affectedAnnotationIDs: [offscreen.id])
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(size: NSSize(width: 200, height: 1_000), color: .white),
            annotations: [visible, offscreen], eraserMasks: [hiddenMask],
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450)
        )
        controller.show()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let newMask = EraserMask(rect: NSRect(x: 30, y: 60, width: 20, height: 15), affectedAnnotationIDs: [visible.id])
        overlay.test_addEraserMask(newMask)
        controller.test_commitOverlay()
        XCTAssertTrue(controller.test_fullEraserMasks.contains { $0.id == hiddenMask.id })
        let committed = try XCTUnwrap(controller.test_fullEraserMasks.first { $0.id == newMask.id })
        XCTAssertEqual(committed.affectedAnnotationIDs, [visible.id])
        XCTAssertNotEqual(committed.rect, newMask.rect)
        controller.stop()
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
        let bytesPerRow = cg.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * cg.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let created = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let base = storage.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: cg.width,
                    height: cg.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        XCTAssertTrue(created)
        return Data(bytes)
    }

    private func makeTallController() -> LongImageEditorWindowController {
        LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(size: NSSize(width: 200, height: 1_200), color: .white),
            visibleFrame: NSRect(x: 50, y: 40, width: 500, height: 450),
            initialWindowSize: NSSize(width: 400, height: 400)
        )
    }
}
