import AppKit
import XCTest
@testable import xxsnap

@MainActor
final class LongImageEditorTests: XCTestCase {
    func testTextOptionsToolbarRemainsVisibleWithoutCoveringMainToolbar() throws {
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(
                size: NSSize(width: 1_000, height: 8_000),
                color: .white
            ),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_920, height: 2_160),
            initialWindowSize: NSSize(width: 1_000, height: 840)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        overlay.test_activateTextTool()

        let mainToolbar = try XCTUnwrap(overlay.test_mainToolbarRect())
        let optionsToolbar = try XCTUnwrap(overlay.test_optionsToolbarRect)
        let overlayBounds = try XCTUnwrap(overlay.contentView?.bounds)
        XCTAssertTrue(overlayBounds.contains(mainToolbar))
        XCTAssertTrue(overlayBounds.contains(optionsToolbar))
        XCTAssertFalse(
            mainToolbar.intersects(optionsToolbar),
            "main=\(mainToolbar) options=\(optionsToolbar) bounds=\(overlayBounds)"
        )
        controller.stop()
    }

    func testShowReactivatesApplicationSoFinishedCaptureIsVisible() async {
        var activationCount = 0
        var controller: LongImageEditorWindowController!
        var windowWasKeyWhenActivationStarted: Bool?
        controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(size: NSSize(width: 120, height: 800), color: .white),
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 400),
            applicationActivator: {
                activationCount += 1
                windowWasKeyWhenActivationStarted = controller.window?.isKeyWindow
                NSApp.activate(ignoringOtherApps: true)
            }
        )
        controller.show()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(windowWasKeyWhenActivationStarted, false)
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertTrue(controller.window?.firstResponder === controller.scrollView.documentView)
        XCTAssertNotNil(controller.test_editingOverlay)
        controller.stop()
    }

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
        XCTAssertEqual(
            controller.fitWidthScale,
            controller.scrollView.contentSize.width / image.size.width,
            accuracy: 0.0001
        )
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
        var style = CaptureAnnotationStyle()
        style.strokeWidth = 6
        let original = CaptureAnnotation(
            kind: .brush,
            rect: NSRect(x: 20, y: 620, width: 80, height: 40),
            style: style,
            brushPath: CaptureBrushPath(points: [NSPoint(x: 20, y: 620), NSPoint(x: 100, y: 660)])
        )
        let viewport = LongImageAnnotationTranslation.annotation(
            original,
            fromImageSliceOrigin: NSPoint(x: 0, y: 600),
            displayScale: 0.5
        )
        XCTAssertEqual(viewport.rect, NSRect(x: 10, y: 10, width: 40, height: 20))
        XCTAssertEqual(viewport.brushPath?.points, [NSPoint(x: 10, y: 10), NSPoint(x: 50, y: 30)])
        XCTAssertEqual(viewport.style.strokeWidth, 3, accuracy: 0.0001)

        let restored = LongImageAnnotationTranslation.annotation(
            viewport,
            toImageSliceOrigin: NSPoint(x: 0, y: 600),
            displayScale: 0.5
        )
        XCTAssertEqual(restored.rect, original.rect)
        XCTAssertEqual(restored.brushPath?.points, original.brushPath?.points)
        XCTAssertEqual(restored.style.strokeWidth, original.style.strokeWidth, accuracy: 0.0001)
    }

    func testBrushStrokeWidthStaysStableAfterLongImageCommitAtMagnifiedScale() throws {
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(
                size: NSSize(width: 160, height: 1_200),
                color: .white
            ),
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450),
            initialWindowSize: NSSize(width: 400, height: 400)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        XCTAssertGreaterThan(controller.fitWidthScale, 1)

        overlay.test_activateShapeTool(.brush)
        overlay.test_drag(from: NSPoint(x: 80, y: 180), to: NSPoint(x: 180, y: 260))

        let viewportStrokeWidth = try XCTUnwrap(overlay.test_annotation(at: 0)).style.strokeWidth
        let canonicalStrokeWidth = try XCTUnwrap(controller.test_fullAnnotations.first).style.strokeWidth
        XCTAssertEqual(
            canonicalStrokeWidth * controller.fitWidthScale,
            viewportStrokeWidth,
            accuracy: 0.0001
        )
        controller.stop()
    }

    func testUndoRedoToolbarActionsSynchronizeLongImageDocumentAfterRefresh() throws {
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(
                size: NSSize(width: 240, height: 1_200),
                color: .white
            ),
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450),
            initialWindowSize: NSSize(width: 360, height: 360)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)

        overlay.test_activateShapeTool(.rectangle)
        overlay.test_drag(from: NSPoint(x: 80, y: 120), to: NSPoint(x: 180, y: 220))
        XCTAssertEqual(controller.test_fullAnnotations.count, 1)

        overlay.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
        XCTAssertEqual(controller.test_fullAnnotations.count, 0)
        XCTAssertEqual(overlay.test_annotationCount, 0)

        overlay.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command, .shift])
        XCTAssertEqual(controller.test_fullAnnotations.count, 1)
        XCTAssertEqual(overlay.test_annotationCount, 1)
        controller.stop()
    }

    func testChangingSelectedRectangleColorSynchronizesLongImageImmediately() throws {
        let controller = makeTallController()
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)

        overlay.test_activateShapeTool(.rectangle)
        overlay.test_drag(from: NSPoint(x: 80, y: 120), to: NSPoint(x: 180, y: 220))
        let colorPoint = try XCTUnwrap(overlay.test_optionsPaletteColorPoint(at: 8))
        overlay.test_mouseDown(at: colorPoint)
        overlay.test_mouseUp(at: colorPoint)

        let overlayColor = try XCTUnwrap(overlay.test_annotation(at: 0)).style.strokeColor
        let documentColor = try XCTUnwrap(controller.test_fullAnnotations.first).style.strokeColor
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: documentColor),
            SelectionToolbarState.colorSamplerHexString(for: overlayColor)
        )
        controller.stop()
    }

    func testChangingSelectedRectangleShapeSynchronizesLongImageImmediately() throws {
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(
                size: NSSize(width: 1_000, height: 8_000),
                color: .white
            ),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_920, height: 2_160),
            initialWindowSize: NSSize(width: 1_000, height: 840)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)

        overlay.test_activateShapeTool(.rectangle)
        overlay.test_drag(from: NSPoint(x: 80, y: 120), to: NSPoint(x: 180, y: 220))
        let colorPoint = try XCTUnwrap(overlay.test_optionsPaletteColorPoint(at: 8))
        overlay.test_mouseDown(at: colorPoint)
        overlay.test_mouseUp(at: colorPoint)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(
                for: try XCTUnwrap(overlay.test_annotation(at: 0)).style.strokeColor
            ),
            "#3C53D7"
        )

        let ellipseButton = try XCTUnwrap(overlay.test_compactOptionsControlRects().last)
        let ellipsePoint = NSPoint(x: ellipseButton.midX, y: ellipseButton.midY)
        overlay.test_mouseDown(at: ellipsePoint)
        overlay.test_mouseUp(at: ellipsePoint)

        XCTAssertEqual(overlay.test_annotation(at: 0)?.kind, .ellipse)
        XCTAssertEqual(controller.test_fullAnnotations.first?.kind, .ellipse)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(
                for: try XCTUnwrap(overlay.test_annotation(at: 0)).style.strokeColor
            ),
            "#3C53D7"
        )
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(
                for: try XCTUnwrap(controller.test_fullAnnotations.first).style.strokeColor
            ),
            "#3C53D7"
        )
        controller.stop()
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

    func testFractionalVisibleSliceKeepsPixelScaleAndAnnotationRegistration() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 240, height: 1_200, scale: 2)
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 30.5, y: 120.25, width: 50, height: 30),
            style: CaptureAnnotationStyle()
        )
        let geometry = LongImageEditorGeometry(
            imageSize: image.size,
            viewportSize: NSSize(width: 216, height: 90.45),
            scrollOffset: 100.25
        )
        XCTAssertEqual(geometry.fitWidthScale, 0.9, accuracy: 0.001)
        let requested = geometry.visibleImageRect
        let slice = LongImageEditorDocument.visibleSlice(
            image: image,
            annotations: [annotation],
            eraserMasks: [],
            imageRect: requested
        )
        let cg = try XCTUnwrap(slice.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cg.width, 480)
        XCTAssertEqual(cg.height, 201)
        XCTAssertEqual(slice.image.size, requested.size)
        XCTAssertEqual(slice.imageRect, requested)
        XCTAssertEqual(slice.annotations.first?.rect.origin, NSPoint(x: 30.5, y: 20))
    }

    func testRendererFractionalVisibleCropMatchesIndependentSamplingOracle() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 240, height: 1_200, scale: 2)
        let requested = NSRect(x: 0, y: 100.25, width: 240, height: 100.5)
        let actual = CaptureAnnotationRenderer.renderVisibleLongImageSlice(
            image: image,
            annotations: [],
            eraserMasks: [],
            imageRect: requested
        )
        let expected = try fractionallySampleTopOrigin(image, rect: requested)
        XCTAssertEqual(pixelSize(actual), NSSize(width: 480, height: 201))
        XCTAssertEqual(try pixelBytes(actual), try pixelBytes(expected))
    }

    func testThinBarArrowVisualExtentEntersSliceOutsideLineRect() {
        var style = CaptureAnnotationStyle(); style.strokeWidth = 1
        let line = CaptureArrowLine(
            start: NSPoint(x: 30, y: 100), end: NSPoint(x: 150, y: 100), control: NSPoint(x: 90, y: 100),
            startArrowType: .bar, endArrowType: .none
        )
        let annotation = CaptureAnnotation(kind: .arrowLine, rect: line.boundingRect, style: style, arrowLine: line)
        let visual = CaptureAnnotationRenderer.longImageVisualBounds(for: annotation)
        XCTAssertLessThanOrEqual(visual.minY, 94.5)
        let slice = LongImageEditorDocument.visibleSlice(
            image: TestImageFactory.solid(size: NSSize(width: 200, height: 500), color: .white),
            annotations: [annotation], eraserMasks: [], imageRect: NSRect(x: 0, y: 94, width: 200, height: 2)
        )
        XCTAssertEqual(slice.annotations.map(\.id), [annotation.id])
    }

    func testArrowEndpointKindsMatchFullRenderAtSliceBoundary() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 220, height: 900, scale: 2)
        let sliceRect = NSRect(x: 0, y: 295, width: 220, height: 180)
        var style = CaptureAnnotationStyle(); style.strokeColor = .red; style.strokeWidth = 2
        let types: [CaptureArrowType] = [.bar, .dot, .diamond, .normal, .solidArrow, .hollowArrow]
        for (index, type) in types.enumerated() {
            let y = CGFloat(300 + index * 25)
            let line = CaptureArrowLine(
                start: NSPoint(x: 8, y: y), end: NSPoint(x: 205, y: y), control: NSPoint(x: 105, y: y),
                startArrowType: type, endArrowType: type
            )
            let annotation = CaptureAnnotation(kind: .arrowLine, rect: line.boundingRect, style: style, arrowLine: line)
            let full = CaptureAnnotationRenderer.renderCompleteLongImage(image: image, annotations: [annotation], eraserMasks: [])
            let expected = try cropTopOrigin(full, rect: sliceRect)
            let actual = CaptureAnnotationRenderer.renderVisibleLongImageSlice(image: image, annotations: [annotation], eraserMasks: [], imageRect: sliceRect)
            let actualBytes = try pixelBytes(actual), expectedBytes = try pixelBytes(expected)
            if type == .solidArrow || type == .hollowArrow {
                XCTAssertLessThanOrEqual(maxChannelDifference(actualBytes, expectedBytes), 1, "\(type)")
            } else {
                XCTAssertEqual(actualBytes, expectedBytes, "\(type)")
            }
        }
    }

    func testProcessingRectExpandsTransitivelyAcrossMosaicDependencyChain() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 180, height: 1_400, scale: 2)
        let requested = NSRect(x: 0, y: 600, width: 180, height: 120)
        var style = CaptureAnnotationStyle(); style.strokeWidth = 12
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 20)
        let earliest = CaptureAnnotation(kind: .mosaicRectangle, rect: NSRect(x: 20, y: 350, width: 130, height: 80), style: style, mosaicRedaction: redaction)
        let middle = CaptureAnnotation(kind: .mosaicRectangle, rect: NSRect(x: 25, y: 465, width: 125, height: 80), style: style, mosaicRedaction: redaction)
        let latest = CaptureAnnotation(kind: .mosaicRectangle, rect: NSRect(x: 30, y: 580, width: 120, height: 80), style: style, mosaicRedaction: redaction)
        let unrelated = CaptureAnnotation(kind: .mosaicRectangle, rect: NSRect(x: 20, y: 20, width: 130, height: 50), style: style, mosaicRedaction: redaction)
        let annotations = [unrelated, earliest, middle, latest]
        let plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: image.size, imageRect: requested, annotations: annotations, eraserMasks: []
        )
        XCTAssertTrue(plan.annotationIDs.contains(earliest.id))
        XCTAssertTrue(plan.annotationIDs.contains(middle.id))
        XCTAssertTrue(plan.annotationIDs.contains(latest.id))
        XCTAssertFalse(plan.annotationIDs.contains(unrelated.id))
        XCTAssertLessThan(plan.processingRect.minY, 300)
        XCTAssertGreaterThan(plan.processingRect.minY, 100)
        let full = CaptureAnnotationRenderer.renderCompleteLongImage(image: image, annotations: annotations, eraserMasks: [])
        let expected = try cropTopOrigin(full, rect: requested)
        let actual = CaptureAnnotationRenderer.renderVisibleLongImageSlice(image: image, annotations: annotations, eraserMasks: [], imageRect: requested)
        XCTAssertEqual(try pixelBytes(actual), try pixelBytes(expected))
    }

    func testDependencyAnalysisDoesNotLetLaterMosaicChainAffectEarlierDirectMosaic() {
        let requested = NSRect(x: 0, y: 20, width: 180, height: 100)
        var style = CaptureAnnotationStyle(); style.strokeWidth = 10
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 16)
        let direct = CaptureAnnotation(kind: .mosaicRectangle, rect: NSRect(x: 20, y: 35, width: 120, height: 50), style: style, mosaicRedaction: redaction)
        let laterChain = (0..<100).map { index in
            CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 20, y: CGFloat(220 + index * 45), width: 120, height: 60),
                style: style,
                mosaicRedaction: redaction
            )
        }
        let plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: NSSize(width: 180, height: 6_000), imageRect: requested,
            annotations: [direct] + laterChain, eraserMasks: []
        )
        XCTAssertEqual(plan.annotationIDs, [direct.id])
        XCTAssertLessThan(plan.processingRect.maxY, 220)
    }

    func testLateDirectMosaicPullsOnlyEarlierDependencyChainAndMatchesFullRender() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 180, height: 1_200, scale: 2)
        let requested = NSRect(x: 0, y: 610, width: 180, height: 100)
        var mosaicStyle = CaptureAnnotationStyle(); mosaicStyle.strokeWidth = 10
        var ordinaryStyle = CaptureAnnotationStyle(); ordinaryStyle.strokeColor = .red; ordinaryStyle.strokeWidth = 80
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 18)
        let earliest = CaptureAnnotation(kind: .mosaicRectangle, rect: NSRect(x: 20, y: 350, width: 120, height: 70), style: mosaicStyle, mosaicRedaction: redaction)
        let ordinary = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 35, y: 445, width: 90, height: 45), style: ordinaryStyle)
        let middle = CaptureAnnotation(kind: .mosaicRectangle, rect: NSRect(x: 25, y: 500, width: 120, height: 70), style: mosaicStyle, mosaicRedaction: redaction)
        let direct = CaptureAnnotation(kind: .mosaicRectangle, rect: NSRect(x: 30, y: 615, width: 115, height: 65), style: mosaicStyle, mosaicRedaction: redaction)
        let annotations = [earliest, ordinary, middle, direct]
        let plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: image.size, imageRect: requested, annotations: annotations, eraserMasks: []
        )
        XCTAssertEqual(plan.annotationIDs, Set(annotations.map(\.id)))
        let full = CaptureAnnotationRenderer.renderCompleteLongImage(image: image, annotations: annotations, eraserMasks: [])
        let expected = try cropTopOrigin(full, rect: requested)
        let actual = CaptureAnnotationRenderer.renderVisibleLongImageSlice(image: image, annotations: annotations, eraserMasks: [], imageRect: requested)
        XCTAssertEqual(try pixelBytes(actual), try pixelBytes(expected))
    }

    func testLaterAnnotationDirectlyIntersectingRequestedIsAlwaysIncluded() {
        let requested = NSRect(x: 0, y: 400, width: 180, height: 120)
        let style = CaptureAnnotationStyle()
        let early = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 20, y: 410, width: 50, height: 40), style: style)
        let later = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 100, y: 450, width: 50, height: 40), style: style)
        let plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: NSSize(width: 180, height: 1_000), imageRect: requested,
            annotations: [early, later], eraserMasks: []
        )
        XCTAssertEqual(plan.annotationIDs, [early.id, later.id])
    }

    func testDirectMagnifierUsesRawSourceWithoutPullingEarlierMosaicLayers() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 240, height: 6_000, scale: 2)
        let requested = NSRect(x: 0, y: 5_045, width: 240, height: 80)
        var mosaicStyle = CaptureAnnotationStyle(); mosaicStyle.strokeWidth = 1
        let sourceOnlyMosaics = (0..<100).map { _ in
            CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 70, y: 5_025, width: 80, height: 15),
                style: mosaicStyle,
                mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 1)
            )
        }
        let magnifier = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 40, y: 5_000, width: 160, height: 80),
            style: CaptureAnnotationStyle(),
            magnifierShape: .rectangle,
            magnifierZoom: 2
        )
        let annotations = sourceOnlyMosaics + [magnifier]
        let plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: image.size,
            imageRect: requested,
            annotations: annotations,
            eraserMasks: []
        )
        XCTAssertEqual(plan.annotationIDs, [magnifier.id])
        XCTAssertLessThan(plan.processingRect.height, 150)
        XCTAssertLessThanOrEqual(plan.processingRect.minY, 5_020)

        let full = CaptureAnnotationRenderer.renderCompleteLongImage(image: image, annotations: annotations, eraserMasks: [])
        let expected = try cropTopOrigin(full, rect: requested)
        let actual = CaptureAnnotationRenderer.renderVisibleLongImageSlice(
            image: image,
            annotations: annotations,
            eraserMasks: [],
            imageRect: requested
        )
        XCTAssertEqual(try pixelBytes(actual), try pixelBytes(expected))
    }

    func testMagnifierProcessingUsesActualZoomedSourceExtentAndClampsToImageBounds() {
        let imageSize = NSSize(width: 800, height: 1_000)
        let requested = NSRect(x: 450, y: 550, width: 70, height: 60)
        let lens = NSRect(x: 300, y: 400, width: 200, height: 200)
        let zoom2 = CaptureAnnotation(
            kind: .magnifier, rect: lens, style: CaptureAnnotationStyle(), magnifierZoom: 2
        )
        let zoom4 = CaptureAnnotation(
            kind: .magnifier, rect: lens, style: CaptureAnnotationStyle(), magnifierZoom: 4
        )
        let zoom2Plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: imageSize, imageRect: requested, annotations: [zoom2], eraserMasks: []
        )
        let zoom4Plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: imageSize, imageRect: requested, annotations: [zoom4], eraserMasks: []
        )
        XCTAssertEqual(zoom2Plan.processingRect.minY, 450, accuracy: 0.001)
        XCTAssertEqual(zoom4Plan.processingRect.minY, 475, accuracy: 0.001)
        XCTAssertEqual(zoom2Plan.processingRect.minX, 344, accuracy: 0.001)
        XCTAssertEqual(zoom4Plan.processingRect.minX, 372, accuracy: 0.001)
        XCTAssertGreaterThan(zoom4Plan.processingRect.minY, zoom2Plan.processingRect.minY)

        let boundaryLens = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 300, y: -100, width: 200, height: 200),
            style: CaptureAnnotationStyle(),
            magnifierZoom: 2
        )
        let boundaryRequested = NSRect(x: 0, y: 0, width: 800, height: 50)
        let boundaryPlan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: imageSize,
            imageRect: boundaryRequested,
            annotations: [boundaryLens],
            eraserMasks: []
        )
        XCTAssertEqual(boundaryPlan.processingRect, boundaryRequested)
    }

    func testVisibleMagnifierUsesFullCanvasGeometryForHorizontalPartialRetinaSlice() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 600, height: 1_200, scale: 2)
        let requested = NSRect(x: 390, y: 480, width: 60, height: 240)
        let magnifier = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 250, y: 520, width: 160, height: 160),
            style: CaptureAnnotationStyle(),
            magnifierShape: .rectangle,
            magnifierZoom: 2
        )
        let plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: image.size,
            imageRect: requested,
            annotations: [magnifier],
            eraserMasks: []
        )
        XCTAssertEqual(plan.processingRect.minX, 284, accuracy: 0.001)
        XCTAssertLessThan(plan.processingRect.width, 200)
        XCTAssertGreaterThan(plan.processingRect.minX, 0)

        let full = CaptureAnnotationRenderer.renderCompleteLongImage(image: image, annotations: [magnifier], eraserMasks: [])
        let expected = try cropTopOrigin(full, rect: requested)
        let actual = CaptureAnnotationRenderer.renderVisibleLongImageSlice(
            image: image,
            annotations: [magnifier],
            eraserMasks: [],
            imageRect: requested
        )
        XCTAssertEqual(try pixelBytes(actual), try pixelBytes(expected))
    }

    func testVisibleMagnifierPreservesOffsetFallbackAtTrueFullImageEdge() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 600, height: 1_200, scale: 2)
        let requested = NSRect(x: 80, y: 480, width: 80, height: 240)
        let magnifier = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: -40, y: 520, width: 160, height: 160),
            style: CaptureAnnotationStyle(),
            magnifierShape: .rectangle,
            magnifierZoom: 2
        )
        let plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: image.size,
            imageRect: requested,
            annotations: [magnifier],
            eraserMasks: []
        )
        XCTAssertEqual(plan.processingRect.minX, 0, accuracy: 0.001)
        XCTAssertLessThan(plan.processingRect.width, 200)

        let full = CaptureAnnotationRenderer.renderCompleteLongImage(image: image, annotations: [magnifier], eraserMasks: [])
        let expected = try cropTopOrigin(full, rect: requested)
        let actual = CaptureAnnotationRenderer.renderVisibleLongImageSlice(
            image: image,
            annotations: [magnifier],
            eraserMasks: [],
            imageRect: requested
        )
        XCTAssertEqual(try pixelBytes(actual), try pixelBytes(expected))
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

    func testWindowUsesPinnedStyleContextMenuInsteadOfFixedControlStrip() throws {
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
        controller.show()
        let contentView = try XCTUnwrap(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.scrollView.frame, contentView.bounds)
        XCTAssertNotNil(controller.test_editingOverlay)

        let menu = try XCTUnwrap(controller.scrollView.menu)
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? nil : $0.title }, [
            "显示工具条 (⇧)",
            nil,
            "贴图",
            "复制图片",
            "保存图片",
            nil,
            "关闭",
        ])
        let toolbarItem = try XCTUnwrap(menu.items.first { $0.title == "显示工具条 (⇧)" })
        XCTAssertEqual(toolbarItem.state, .on)
        let copyItem = try XCTUnwrap(menu.items.first { $0.title == "复制图片" })
        XCTAssertEqual(copyItem.keyEquivalent, "c")
        XCTAssertEqual(copyItem.keyEquivalentModifierMask, [.command])
        let saveItem = try XCTUnwrap(menu.items.first { $0.title == "保存图片" })
        XCTAssertEqual(saveItem.keyEquivalent, "s")
        XCTAssertEqual(saveItem.keyEquivalentModifierMask, [.command])
        let closeItem = try XCTUnwrap(menu.items.first { $0.title == "关闭" })
        XCTAssertEqual(closeItem.keyEquivalent, "w")
        XCTAssertEqual(closeItem.keyEquivalentModifierMask, [.command])
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(toolbarItem.action), to: toolbarItem.target, from: toolbarItem))
        XCTAssertNil(controller.test_editingOverlay)
        XCTAssertEqual(toolbarItem.state, .off)
        XCTAssertEqual(controller.window?.isVisible, true)
        controller.stop()
    }

    func testShowingLongImageEditorDisplaysEditingToolbarByDefault() throws {
        let controller = makeTallController()
        XCTAssertNil(controller.test_editingOverlay)

        controller.show()

        XCTAssertNotNil(controller.test_editingOverlay)
        let toolbarItem = try XCTUnwrap(
            controller.scrollView.menu?.items.first { $0.title == "显示工具条 (⇧)" }
        )
        XCTAssertEqual(toolbarItem.state, .on)
        controller.stop()
    }

    func testFullScreenCaptureEditorOpensLargerAndFitsWindowHeightToImage() throws {
        let imageSize = NSSize(width: 1_512, height: 982)
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(size: imageSize, color: .white),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_512, height: 950),
            initialWindowSize: NSSize(width: 1_000, height: 840)
        )
        let window = try XCTUnwrap(controller.window)
        let originalWindowFrame = window.frame

        controller.updateTitleStyle(.fullScreenCapture)

        XCTAssertGreaterThan(window.frame.width, originalWindowFrame.width)
        XCTAssertLessThanOrEqual(window.frame.width, originalWindowFrame.width * 1.2)
        let documentView = try XCTUnwrap(controller.scrollView.documentView)
        XCTAssertEqual(documentView.frame.height, controller.scrollView.contentSize.height, accuracy: 1)

        controller.show()

        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        XCTAssertEqual(overlay.frame.height, documentView.frame.height, accuracy: 1)

        let fittedWindowFrame = window.frame
        controller.hideEditingToolbar()
        XCTAssertEqual(window.frame, fittedWindowFrame)
        controller.showEditingToolbar()
        XCTAssertEqual(window.frame, fittedWindowFrame)
        XCTAssertEqual(controller.test_editingOverlay?.frame.height ?? 0, documentView.frame.height, accuracy: 1)
        controller.stop()
    }

    func testFullScreenCapturePresentationDoesNotChangeLongImageEditorLayout() throws {
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(
                size: NSSize(width: 1_512, height: 982),
                color: .white
            ),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_512, height: 950),
            initialWindowSize: NSSize(width: 1_000, height: 840),
            titleStyle: .longCapture
        )
        let window = try XCTUnwrap(controller.window)
        let originalWindowFrame = window.frame

        controller.show()

        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let clipView = controller.scrollView.contentView
        let expectedOverlayFrame = window.convertToScreen(clipView.convert(clipView.bounds, to: nil))
        XCTAssertEqual(window.frame, originalWindowFrame)
        XCTAssertEqual(overlay.frame, expectedOverlayFrame)
        controller.stop()
    }

    func testShiftReleaseTogglesLongImageToolbarLikePinnedImage() throws {
        let controller = makeTallController()
        controller.show()
        let documentView = try XCTUnwrap(controller.scrollView.documentView)
        try XCTUnwrap(controller.window).makeFirstResponder(documentView)

        func flagsEvent(_ modifierFlags: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: 0,
                windowNumber: controller.window?.windowNumber ?? 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 56
            ))
        }

        documentView.flagsChanged(with: try flagsEvent([.shift]))
        XCTAssertNotNil(controller.test_editingOverlay)
        documentView.flagsChanged(with: try flagsEvent([]))
        XCTAssertNil(controller.test_editingOverlay)

        documentView.flagsChanged(with: try flagsEvent([.shift]))
        documentView.flagsChanged(with: try flagsEvent([]))
        let overlay = try XCTUnwrap(controller.test_editingOverlay)

        overlay.test_flagsChanged(modifierFlags: [.shift])
        XCTAssertNotNil(controller.test_editingOverlay)
        overlay.test_flagsChanged(modifierFlags: [])
        XCTAssertNil(controller.test_editingOverlay)
        XCTAssertEqual(controller.window?.isVisible, true)
        controller.stop()
    }

    func testLongImageKeyboardShortcutsWorkWithAndWithoutEditingToolbar() throws {
        var copyCount = 0
        var saveCount = 0
        var closeCount = 0
        let controller = LongImageEditorWindowController(
            image: TestImageFactory.solid(size: NSSize(width: 1_000, height: 8_000), color: .white),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_200, height: 900),
            actions: LongImageEditorActions(
                copy: { _ in copyCount += 1; return true },
                save: { _ in saveCount += 1; return true },
                pin: { _ in true }
            )
        )
        controller.onClose = { closeCount += 1 }
        controller.show()

        func keyEvent(_ keyCode: UInt16, _ characters: String) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: controller.window?.windowNumber ?? 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ))
        }

        let documentView = try XCTUnwrap(controller.scrollView.documentView)
        documentView.keyDown(with: try keyEvent(8, "c"))
        documentView.keyDown(with: try keyEvent(1, "s"))
        XCTAssertEqual(copyCount, 1)
        XCTAssertEqual(saveCount, 1)

        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        overlay.test_keyDown(keyCode: 13, charactersIgnoringModifiers: "w", modifierFlags: [.command])
        XCTAssertEqual(closeCount, 1)
        XCTAssertFalse(controller.window?.isVisible == true)
    }

    func testTallLongImageShowsPersistentVerticalScrollerWithoutWindowResize() throws {
        let controller = makeTallController()
        controller.show()
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let documentView = try XCTUnwrap(controller.scrollView.documentView)
        XCTAssertGreaterThan(documentView.frame.height, controller.scrollView.contentSize.height)
        XCTAssertTrue(controller.scrollView.hasVerticalScroller)
        XCTAssertFalse(controller.scrollView.autohidesScrollers)
        XCTAssertEqual(controller.scrollView.scrollerStyle, .legacy)
        XCTAssertFalse(try XCTUnwrap(controller.scrollView.verticalScroller).isHidden)
        controller.stop()
    }

    func testEditingOverlayLeavesPersistentVerticalScrollerVisible() throws {
        let controller = makeTallController()
        controller.show()
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.showEditingToolbar()

        let window = try XCTUnwrap(controller.window)
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let scroller = try XCTUnwrap(controller.scrollView.verticalScroller)
        let scrollerFrameInWindow = scroller.convert(scroller.bounds, to: nil)
        let scrollerScreenFrame = window.convertToScreen(scrollerFrameInWindow)

        XCTAssertFalse(scroller.isHidden)
        XCTAssertTrue(scroller.isEnabled)
        XCTAssertFalse(overlay.frame.intersects(scrollerScreenFrame))
        controller.stop()
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

    func testLongImageEditorUsesArrowCursorInsideEditingAreaWhenNoToolIsSelected() {
        let editingRect = NSRect(x: 0, y: 0, width: 500, height: 400)
        let overlay = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .longImageEditor(
                windowFrame: editingRect,
                selectionRect: editingRect
            )
        ) { _ in }

        XCTAssertEqual(
            overlay.test_cursorStyle(at: NSPoint(x: editingRect.midX, y: editingRect.midY)),
            .arrow
        )
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

    func testTiledFullExportBoundsTemporaryProcessingForTallDocument() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 400, height: 8_000)
        var style = CaptureAnnotationStyle(); style.strokeColor = .red; style.strokeWidth = 12
        let rectangle = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 40, y: 2_900, width: 220, height: 160),
            style: style
        )
        let mosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 70, y: 3_050, width: 250, height: 180),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 16)
        )
        let mask = EraserMask(
            rect: NSRect(x: 100, y: 2_950, width: 60, height: 60),
            affectedAnnotationIDs: [rectangle.id]
        )
        let output = CaptureAnnotationRenderer.renderLongImage(
            image: image,
            annotations: [rectangle, mosaic],
            eraserMasks: [mask]
        )
        let cg = try XCTUnwrap(output.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cg.width, 400)
        XCTAssertEqual(cg.height, 8_000)
        let metrics = CaptureAnnotationRenderer.test_lastLongImageTileMetrics
        XCTAssertGreaterThan(metrics.tileCount, 10)
        XCTAssertLessThan(metrics.maxTemporaryProcessingPixelHeight, 2_048)
        XCTAssertLessThan(metrics.maxTemporaryProcessingPixels, 400 * 2_048)
    }

    func testHugeMosaicAnnotationsKeepEachTileProcessingBounded() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 400, height: 8_000)
        var style = CaptureAnnotationStyle(); style.strokeWidth = 18
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 20)
        let hugeRectangle = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 30, y: 0, width: 330, height: 8_000),
            style: style,
            mosaicRedaction: redaction
        )
        let hugeStroke = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: NSRect(x: 180, y: 0, width: 30, height: 8_000),
            style: style,
            mosaicStroke: CaptureMosaicStroke(points: [NSPoint(x: 195, y: 0), NSPoint(x: 195, y: 8_000)]),
            mosaicRedaction: redaction
        )
        let request = NSRect(x: 0, y: 3_000, width: 400, height: 512)
        let plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: image.size,
            imageRect: request,
            annotations: [hugeRectangle, hugeStroke],
            eraserMasks: []
        )
        XCTAssertLessThanOrEqual(plan.processingRect.height, request.height + 512)

        _ = CaptureAnnotationRenderer.renderLongImage(
            image: image,
            annotations: [hugeRectangle, hugeStroke],
            eraserMasks: []
        )
        XCTAssertLessThanOrEqual(
            CaptureAnnotationRenderer.test_lastLongImageTileMetrics.maxTemporaryProcessingPixelHeight,
            512 + 512
        )
    }

    func testLongImageExportWithoutEditsReturnsOriginalImageIdentity() {
        let image = TestImageFactory.solid(
            pixelWidth: 320,
            pixelHeight: 640,
            pointSize: NSSize(width: 160, height: 320),
            color: NSColor(deviceRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.45)
        )
        let output = CaptureAnnotationRenderer.renderLongImage(image: image, annotations: [], eraserMasks: [])
        XCTAssertTrue(output === image)
    }

    func testTiledFullExportMatchesLegacyRendererAcrossTileSeams() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 180, height: 1_300, scale: 2)
        var style = CaptureAnnotationStyle(); style.strokeColor = .red; style.strokeWidth = 10
        let rectangle = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 25, y: 235, width: 120, height: 90),
            style: style
        )
        let mosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 35, y: 480, width: 110, height: 100),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 9)
        )
        let magnifier = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 50, y: 745, width: 90, height: 90),
            style: style,
            magnifierShape: .rectangle,
            magnifierZoom: 2
        )
        let mask = EraserMask(
            rect: NSRect(x: 60, y: 260, width: 35, height: 30),
            affectedAnnotationIDs: [rectangle.id]
        )
        let annotations = [rectangle, mosaic, magnifier]
        let tiled = CaptureAnnotationRenderer.renderLongImage(
            image: image, annotations: annotations, eraserMasks: [mask]
        )
        let legacy = CaptureAnnotationRenderer.test_renderLegacyCompleteLongImage(
            image: image, annotations: annotations, eraserMasks: [mask]
        )
        XCTAssertEqual(try pixelBytes(tiled), try pixelBytes(legacy))
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
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let before = controller.visibleImageRect.minY
        overlay.test_scrollWheel(at: NSPoint(x: 100, y: 100), deltaY: -120)
        XCTAssertGreaterThan(controller.visibleImageRect.minY, before)

        overlay.test_activateShapeTool(.rectangle)
        overlay.test_mouseDown(at: NSPoint(x: 150, y: 260))
        let locked = controller.visibleImageRect.minY
        overlay.test_scrollWheel(at: NSPoint(x: 100, y: 100), deltaY: -120)
        XCTAssertEqual(controller.visibleImageRect.minY, locked, accuracy: 0.001)
        overlay.test_mouseUp(at: NSPoint(x: 180, y: 300))
        controller.stop()
    }

    func testNumberSequenceContinuesAcrossNonOverlappingLongImageViewports() throws {
        let controller = makeTallController()
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let markPoint = NSPoint(x: 120, y: 180)

        overlay.test_activateNumberTool()
        overlay.test_mouseDown(at: markPoint)
        overlay.test_mouseUp(at: markPoint)
        XCTAssertEqual(controller.test_fullAnnotations.map(\.numberSequenceIndex), [1])

        overlay.test_scrollWheel(at: NSPoint(x: 100, y: 100), deltaY: -600)
        XCTAssertGreaterThan(controller.visibleImageRect.minY, 0)
        overlay.test_mouseDown(at: markPoint)
        overlay.test_mouseUp(at: markPoint)

        XCTAssertEqual(controller.test_fullAnnotations.map(\.numberSequenceIndex), [1, 2])
        controller.stop()
    }

    func testNumberAnnotationSelectionAndControlsSurviveLongImageRefresh() throws {
        let controller = makeTallController()
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let firstPoint = NSPoint(x: 120, y: 180)
        let secondPoint = NSPoint(x: 220, y: 180)

        overlay.test_activateNumberTool()
        overlay.test_mouseDown(at: firstPoint)
        overlay.test_mouseUp(at: firstPoint)
        overlay.test_mouseDown(at: secondPoint)
        overlay.test_mouseUp(at: secondPoint)

        overlay.test_mouseDown(at: firstPoint)
        overlay.test_mouseUp(at: firstPoint)

        XCTAssertEqual(overlay.test_selectedAnnotationIndex, 0)
        XCTAssertTrue(overlay.test_numberControlsVisible)

        let incrementPoint = try XCTUnwrap(overlay.test_numberIncrementHandlePoint())
        overlay.test_mouseDown(at: incrementPoint)
        overlay.test_mouseUp(at: incrementPoint)

        XCTAssertEqual(controller.test_fullAnnotations.map(\.numberSequenceIndex), [2, 1])
        XCTAssertEqual(overlay.test_selectedAnnotationIndex, 0)
        controller.stop()
    }

    func testEraserClearAllCoversWholeLongImageAndSupportsUndoRedo() throws {
        let first = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 20, y: 40, width: 60, height: 50),
            style: CaptureAnnotationStyle()
        )
        let second = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 30, y: 900, width: 70, height: 60),
            style: CaptureAnnotationStyle()
        )
        let mask = EraserMask(
            rect: NSRect(x: 45, y: 915, width: 15, height: 20),
            affectedAnnotationIDs: [second.id]
        )
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(
                size: NSSize(width: 200, height: 1_200),
                color: .white
            ),
            annotations: [first, second],
            eraserMasks: [mask],
            visibleFrame: NSRect(x: 50, y: 40, width: 500, height: 450),
            initialWindowSize: NSSize(width: 400, height: 400)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)

        overlay.test_activateEraserTool()
        let clearAllPoint = try XCTUnwrap(overlay.test_eraserClearAllOptionPoint())
        overlay.test_mouseDown(at: clearAllPoint)
        overlay.test_mouseUp(at: clearAllPoint)

        XCTAssertTrue(controller.test_fullAnnotations.isEmpty)
        XCTAssertTrue(controller.test_fullEraserMasks.isEmpty)

        overlay.test_keyDown(
            keyCode: 6,
            charactersIgnoringModifiers: "z",
            modifierFlags: [.command]
        )
        XCTAssertEqual(Set(controller.test_fullAnnotations.map(\.id)), [first.id, second.id])
        XCTAssertEqual(controller.test_fullEraserMasks.map(\.id), [mask.id])

        overlay.test_keyDown(
            keyCode: 6,
            charactersIgnoringModifiers: "z",
            modifierFlags: [.command, .shift]
        )
        XCTAssertTrue(controller.test_fullAnnotations.isEmpty)
        XCTAssertTrue(controller.test_fullEraserMasks.isEmpty)
        controller.stop()
    }

    func testCreatingTextKeepsEditorActiveAfterMouseUpAndAcceptsTyping() throws {
        let controller = makeTallController()
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let insertionPoint = NSPoint(x: 100, y: 120)

        overlay.test_activateTextTool()
        overlay.test_mouseDown(at: insertionPoint)
        overlay.test_mouseUp(at: insertionPoint)

        XCTAssertTrue(overlay.test_isEditingTextAnnotation)
        XCTAssertTrue(overlay.test_textEditorIsFirstResponder)

        overlay.firstResponder?.insertText("长图文字")
        overlay.test_commitTextEditing()
        controller.test_commitOverlay()

        XCTAssertEqual(controller.test_fullAnnotations.count, 1)
        XCTAssertEqual(controller.test_fullAnnotations.first?.text, "长图文字")
        controller.stop()
    }

    func testMagnifiedViewportCommitsTextAtCanonicalScaleWithoutClipping() throws {
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(
                size: NSSize(width: 160, height: 1_200),
                color: .white
            ),
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450),
            initialWindowSize: NSSize(width: 400, height: 400)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        XCTAssertGreaterThan(controller.fitWidthScale, 1)

        overlay.test_activateTextTool()
        overlay.test_mouseDown(at: NSPoint(x: 60, y: 120))
        overlay.test_mouseUp(at: NSPoint(x: 60, y: 120))
        overlay.firstResponder?.insertText("字体标注后不会丢字")
        let viewportAnnotation = try XCTUnwrap(overlay.test_annotation(at: 0))
        overlay.test_commitTextEditing()
        controller.test_commitOverlay()

        let canonicalAnnotation = try XCTUnwrap(controller.test_fullAnnotations.first)
        let measuredCanonicalText = NSAttributedString(
            string: canonicalAnnotation.text ?? "",
            attributes: CaptureAnnotationRenderer.textAttributes(style: canonicalAnnotation.style)
        ).boundingRect(
            with: NSSize(width: 10_000, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let canonicalContentRect = CaptureAnnotationRenderer.textContentRect(in: canonicalAnnotation.rect)

        XCTAssertEqual(
            canonicalAnnotation.style.textSize,
            viewportAnnotation.style.textSize / controller.fitWidthScale,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(canonicalContentRect.width, ceil(measuredCanonicalText.width))
        XCTAssertGreaterThanOrEqual(canonicalContentRect.height, ceil(measuredCanonicalText.height))
        controller.stop()
    }

    func testMovingWindowRealignsOverlayToViewportScreenFrame() throws {
        let controller = makeTallController()
        controller.show()
        controller.showEditingToolbar()
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
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        var edited = try XCTUnwrap(overlay.test_annotation(at: 0)); edited.text = "committed on move"
        overlay.test_setAnnotations([edited])
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        XCTAssertEqual(controller.test_fullAnnotations[0].text, "committed on move")
        XCTAssertEqual(controller.test_editingOverlay?.test_annotation(at: 0)?.text, "committed on move")
        controller.stop()
    }

    func testFinishEditingCommitsCurrentEditsAndKeepsLongImageWindowOpen() throws {
        let controller = makeTallController()
        var completionCount = 0
        var completedAnnotations: [CaptureAnnotation] = []
        controller.onFinishEditing = { _, annotations, _ in
            completionCount += 1
            completedAnnotations = annotations
        }
        controller.show()
        let imageView = try XCTUnwrap(controller.scrollView.documentView?.subviews.compactMap { $0 as? NSImageView }.first)
        let verticalScroller = try XCTUnwrap(controller.scrollView.verticalScroller)
        let uneditedPixels = try pixelBytes(try XCTUnwrap(imageView.image))
        XCTAssertFalse(verticalScroller.isHidden)
        XCTAssertTrue(verticalScroller.isEnabled)
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        overlay.test_activateShapeTool(.rectangle)
        overlay.test_drag(from: NSPoint(x: 40, y: 80), to: NSPoint(x: 120, y: 150))
        let finishPoint = try XCTUnwrap(overlay.test_mainToolbarButtonPoint(for: .finishEditing))
        overlay.test_mouseDown(at: finishPoint)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(completedAnnotations.count, 1)
        XCTAssertEqual(controller.test_fullAnnotations.count, 1)
        XCTAssertNil(controller.test_editingOverlay)
        XCTAssertEqual(controller.window?.isVisible, true)
        XCTAssertNotEqual(try pixelBytes(try XCTUnwrap(imageView.image)), uneditedPixels)
        XCTAssertEqual(controller.scrollView.scrollerStyle, .legacy)
        XCTAssertTrue(controller.scrollView.hasVerticalScroller)
        XCTAssertFalse(verticalScroller.isHidden)
        XCTAssertTrue(verticalScroller.isEnabled)
        XCTAssertGreaterThan(
            try XCTUnwrap(controller.scrollView.documentView).frame.height,
            controller.scrollView.contentSize.height
        )
        controller.stop()
    }

    func testFloatingToolbarCopyCommitsEditsAndKeepsLongImageWindowOpen() throws {
        var copiedImage: NSImage?
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(size: NSSize(width: 200, height: 1_000), color: .white),
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450),
            actions: LongImageEditorActions(
                copy: { copiedImage = $0; return true },
                save: { _ in false },
                pin: { _ in false }
            )
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        overlay.test_activateShapeTool(.rectangle)
        overlay.test_drag(from: NSPoint(x: 40, y: 80), to: NSPoint(x: 120, y: 150))
        let copyPoint = try XCTUnwrap(overlay.test_mainToolbarButtonPoint(for: .copy))

        overlay.test_mouseDown(at: copyPoint)

        XCTAssertNotNil(copiedImage)
        XCTAssertEqual(controller.test_fullAnnotations.count, 1)
        XCTAssertNil(controller.test_editingOverlay)
        XCTAssertEqual(controller.window?.isVisible, true)
        controller.stop()
    }

    func testCopySaveAndPinUseSameCompleteRenderedRevisionAndFailureKeepsEditorOpen() throws {
        let image = TestImageFactory.solid(size: NSSize(width: 120, height: 900), color: .white)
        var style = CaptureAnnotationStyle()
        style.strokeColor = .red
        style.strokeWidth = 8
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 15, y: 700, width: 80, height: 100),
            style: style
        )
        let editableAnnotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 10, y: 20, width: 60, height: 50),
            style: style
        )
        var received: [NSImage] = []
        let controller = LongImageEditorWindowController(
            canonicalImage: image,
            annotations: [editableAnnotation, annotation],
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450),
            actions: LongImageEditorActions(
                copy: { received.append($0); return true },
                save: { received.append($0); return false },
                pin: { received.append($0); return true }
            )
        )
        controller.show()

        controller.showEditingToolbar()
        controller.test_performContextMenuAction(.copy)
        controller.test_performContextMenuAction(.save)
        controller.test_performContextMenuAction(.pin)

        XCTAssertEqual(received.count, 3)
        XCTAssertTrue(received[0] === received[1])
        XCTAssertTrue(received[1] === received[2])
        XCTAssertEqual(pixelSize(received[0]), NSSize(width: 120, height: 900))
        XCTAssertNotEqual(try pixelBytes(received[0]), try pixelBytes(image))
        XCTAssertEqual(controller.window?.isVisible, true)
        XCTAssertEqual(controller.test_contextMenuTitles, ["显示工具条 (⇧)", nil, "贴图", "复制图片", "保存图片", nil, "关闭"])

        let firstRevision = controller.test_documentRevision
        controller.windowDidResize(Notification(name: NSWindow.didResizeNotification))
        controller.test_performContextMenuAction(.copy)
        XCTAssertTrue(received[2] === received[3])
        XCTAssertEqual(controller.test_documentRevision, firstRevision)

        var edited = try XCTUnwrap(controller.test_editingOverlay?.test_annotation(at: 0))
        edited.rect.origin.x += 10
        controller.test_editingOverlay?.test_setAnnotations([edited])
        controller.test_performContextMenuAction(.copy)
        controller.test_performContextMenuAction(.save)
        controller.test_performContextMenuAction(.pin)

        XCTAssertEqual(received.count, 7)
        XCTAssertFalse(received[3] === received[4])
        XCTAssertTrue(received[4] === received[5])
        XCTAssertTrue(received[5] === received[6])
        XCTAssertNotEqual(try pixelBytes(received[3]), try pixelBytes(received[4]))
        XCTAssertEqual(controller.test_documentRevision, firstRevision + 1)
        controller.stop()
    }

    func testUneditedActionReusesCanonicalImageWithoutFullSizeRender() {
        let image = TestImageFactory.solid(
            size: NSSize(width: 120, height: 900),
            color: .white
        )
        var received: NSImage?
        let controller = LongImageEditorWindowController(
            canonicalImage: image,
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450),
            actions: LongImageEditorActions(
                copy: { received = $0; return true },
                save: { _ in false },
                pin: { _ in false }
            )
        )
        controller.show()
        controller.test_performContextMenuAction(.copy)
        XCTAssertTrue(received === image)
        XCTAssertTrue(controller.test_cachedRenderedRevision === image)
        controller.stop()
    }

    func testStrictLongImageRendererReportsContextTileAndFinalFailures() throws {
        let image = TestImageFactory.solid(size: NSSize(width: 120, height: 900), color: .white)
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 10, y: 20, width: 60, height: 50),
            style: CaptureAnnotationStyle()
        )

        let stages: [LongImageRenderStage] = [
            .sourceImage,
            .outputContext,
            .sourceCropCGImage,
            .sourceCrop,
            .sourceSampleContext,
            .sourceSampleImage,
            .fullImage,
            .annotationRegionSource,
            .annotationRegionContext,
            .annotationRegionImage,
            .finalCropCGImage,
            .finalCrop,
            .finalSampleContext,
            .finalSampleImage,
            .tileImage,
            .finalImage,
        ]
        for stage in stages {
            XCTAssertThrowsError(try CaptureAnnotationRenderer.test_renderLongImageStrict(
                image: image,
                annotations: [annotation],
                eraserMasks: [],
                failingAt: stage
            )) { error in
                XCTAssertEqual(error as? LongImageRenderError, .creationFailed(stage))
            }
        }
    }

    func testInternalStrictTileFailureKeepsEditorRetryableWithoutExecutingAction() {
        let source = TestImageFactory.solid(size: NSSize(width: 120, height: 900), color: .white)
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 10, y: 20, width: 60, height: 50),
            style: CaptureAnnotationStyle()
        )
        var injectedFailure: LongImageRenderStage? = .annotationRegionContext
        var actionCount = 0
        let controller = LongImageEditorWindowController(
            canonicalImage: source,
            annotations: [annotation],
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450),
            actions: LongImageEditorActions(
                copy: { _ in actionCount += 1; return true },
                save: { _ in XCTFail("unexpected save"); return false },
                pin: { _ in XCTFail("unexpected pin"); return false }
            ),
            renderer: { image, annotations, masks in
                if let injectedFailure {
                    return try CaptureAnnotationRenderer.test_renderLongImageStrict(
                        image: image,
                        annotations: annotations,
                        eraserMasks: masks,
                        failingAt: injectedFailure
                    )
                }
                return try CaptureAnnotationRenderer.renderLongImageStrict(
                    image: image,
                    annotations: annotations,
                    eraserMasks: masks
                )
            }
        )
        controller.show()

        controller.test_performContextMenuAction(.copy)
        XCTAssertEqual(actionCount, 0)
        XCTAssertNil(controller.test_cachedRenderedRevision)
        XCTAssertEqual(
            controller.test_lastRenderError as? LongImageRenderError,
            .creationFailed(.annotationRegionContext)
        )
        XCTAssertEqual(controller.window?.isVisible, true)

        injectedFailure = nil
        controller.test_performContextMenuAction(.copy)
        XCTAssertEqual(actionCount, 1)
        XCTAssertNotNil(controller.test_cachedRenderedRevision)
        XCTAssertNil(controller.test_lastRenderError)
        controller.stop()
    }

    func testRenderFailureSkipsEveryActionAndEachActionCanRetry() {
        let source = TestImageFactory.solid(size: NSSize(width: 120, height: 900), color: .white)
        let rendered = TestImageFactory.solid(size: source.size, color: .red)
        var renderCount = 0
        var actionCounts = [0, 0, 0]
        for actionIndex in 0..<3 {
            var shouldFail = true
            let controller = LongImageEditorWindowController(
                canonicalImage: source,
                visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450),
                actions: LongImageEditorActions(
                    copy: { _ in actionCounts[0] += 1; return true },
                    save: { _ in actionCounts[1] += 1; return true },
                    pin: { _ in actionCounts[2] += 1; return true }
                ),
                renderer: { _, _, _ in
                    renderCount += 1
                    if shouldFail { throw LongImageRenderError.creationFailed(.outputContext) }
                    return rendered
                }
            )
            controller.show()
            let action: CaptureCompletionAction = [.copy, .save, .pin][actionIndex]
            let countsBeforeFailure = actionCounts
            controller.test_performContextMenuAction(action)
            XCTAssertEqual(actionCounts, countsBeforeFailure)
            XCTAssertNil(controller.test_cachedRenderedRevision)
            XCTAssertNotNil(controller.test_lastRenderError)
            XCTAssertEqual(controller.window?.isVisible, true)

            shouldFail = false
            controller.test_performContextMenuAction(action)
            XCTAssertEqual(actionCounts[actionIndex], 1)
            XCTAssertTrue(controller.test_cachedRenderedRevision === rendered)
            XCTAssertNil(controller.test_lastRenderError)
            controller.stop()
        }

        XCTAssertEqual(actionCounts, [1, 1, 1])
        XCTAssertEqual(renderCount, 6)
    }

    func testLongEditorActionsUseEnglishLocalizedLabelsAndTooltips() {
        let controller = LongImageEditorWindowController(
            image: TestImageFactory.solid(size: NSSize(width: 120, height: 500), color: .white),
            visibleFrame: NSRect(x: 0, y: 0, width: 500, height: 450),
            language: .english
        )
        XCTAssertEqual(controller.test_contextMenuTitles, ["Show Toolbar (⇧)", nil, "Pin Image", "Copy Image", "Save Image", nil, "Close"])
        controller.stop()
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
        controller.showEditingToolbar()
        var overlay = try XCTUnwrap(controller.test_editingOverlay)
        let canonicalID = try XCTUnwrap(overlay.test_annotation(at: 0)).id
        overlay.test_scrollWheel(at: NSPoint(x: 100, y: 100), deltaY: -600)
        XCTAssertEqual(overlay.test_annotation(at: 0)?.id, canonicalID)
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
        XCTAssertEqual(processing, rect.integral)
        let plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: image.size,
            imageRect: rect,
            annotations: annotations,
            eraserMasks: []
        )
        XCTAssertEqual(plan.annotationIDs, Set(annotations.map(\.id)))
        let full = CaptureAnnotationRenderer.renderCompleteLongImage(image: image, annotations: annotations, eraserMasks: [])
        let expected = try cropTopOrigin(full, rect: rect)
        let actual = CaptureAnnotationRenderer.renderVisibleLongImageSlice(image: image, annotations: annotations, eraserMasks: [], imageRect: rect)
        XCTAssertEqual(try pixelBytes(actual), try pixelBytes(expected))
    }

    func testInteractionLockRestoresProgrammaticClipMovementBeforeCommit() throws {
        let controller = makeTallController()
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        overlay.test_activateShapeTool(.rectangle)
        overlay.test_mouseDown(at: NSPoint(x: 150, y: 260))
        let origin = controller.scrollView.contentView.bounds.origin
        controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: origin.y + 200))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: controller.scrollView.contentView)
        XCTAssertEqual(controller.scrollView.contentView.bounds.origin, origin)
        overlay.test_mouseUp(at: NSPoint(x: 180, y: 300))
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
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        XCTAssertTrue(overlay.test_deleteAnnotations(at: [0]))
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
        controller.showEditingToolbar()
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

    func testRepeatedResizeCommitsUsingPresentedOverlayGeometryWithoutYDrift() throws {
        let style = CaptureAnnotationStyle()
        let rectangle = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 20, y: 80, width: 60, height: 40),
            style: style
        )
        let text = CaptureAnnotation(
            kind: .text,
            rect: NSRect(x: 90, y: 20, width: 100, height: 45),
            style: style,
            text: "Resize"
        )
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(size: NSSize(width: 200, height: 1_200), color: .white, scale: 2),
            annotations: [rectangle, text],
            visibleFrame: NSRect(x: 0, y: 0, width: 700, height: 800),
            initialWindowSize: NSSize(width: 400, height: 420)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let mask = EraserMask(rect: NSRect(x: 40, y: 80, width: 20, height: 15), affectedAnnotationIDs: [rectangle.id])
        overlay.test_addEraserMask(mask)
        overlay.makeKey()
        overlay.test_activateTextTool()
        let localText = try XCTUnwrap(overlay.editorSnapshot?.annotations.first { $0.id == text.id })
        overlay.test_doubleClick(at: NSPoint(x: localText.rect.midX, y: localText.rect.midY))
        overlay.firstResponder?.insertText("Active")

        func resizeBy100() throws {
            let oldFrame = try XCTUnwrap(controller.window?.frame)
            controller.window?.delegate = nil
            controller.window?.setFrame(
                NSRect(x: oldFrame.minX, y: oldFrame.minY, width: oldFrame.width, height: oldFrame.height + 100),
                display: false
            )
            controller.window?.delegate = controller
            controller.windowDidResize(Notification(name: NSWindow.didResizeNotification))
        }
        try resizeBy100()
        let firstCommittedMaskY = try XCTUnwrap(controller.test_fullEraserMasks.first { $0.id == mask.id }).rect.minY
        let firstActiveTextRect = try XCTUnwrap(controller.test_fullAnnotations.first { $0.id == text.id }).rect
        try resizeBy100()
        try resizeBy100()

        let committedRectangle = try XCTUnwrap(controller.test_fullAnnotations.first { $0.id == rectangle.id }?.rect)
        XCTAssertEqual(committedRectangle.minX, rectangle.rect.minX, accuracy: 0.001)
        XCTAssertEqual(committedRectangle.minY, rectangle.rect.minY, accuracy: 0.001)
        XCTAssertEqual(committedRectangle.width, rectangle.rect.width, accuracy: 0.001)
        XCTAssertEqual(committedRectangle.height, rectangle.rect.height, accuracy: 0.001)
        let committedText = try XCTUnwrap(controller.test_fullAnnotations.first { $0.id == text.id }?.rect)
        XCTAssertEqual(committedText.minX, text.rect.minX, accuracy: 0.001)
        XCTAssertEqual(committedText.minY, text.rect.minY, accuracy: 0.001)
        XCTAssertEqual(committedText.width, text.rect.width, accuracy: 0.001)
        XCTAssertEqual(committedText.height, text.rect.height, accuracy: 0.001)
        let committedMask = try XCTUnwrap(controller.test_fullEraserMasks.first { $0.id == mask.id })
        XCTAssertEqual(committedMask.rect.minY, firstCommittedMaskY, accuracy: 0.001)
        XCTAssertEqual(controller.test_fullAnnotations.first { $0.id == text.id }?.rect, firstActiveTextRect)
        controller.stop()
    }

    func testLongImageOverlayIsChildAndDoesNotRemainOrphanedWhenMiniaturized() throws {
        let controller = makeTallController()
        controller.show()
        controller.showEditingToolbar()
        let window = try XCTUnwrap(controller.window)
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        XCTAssertTrue(window.childWindows?.contains(overlay) == true)

        controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification))
        XCTAssertFalse(overlay.isVisible)
        controller.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification))
        XCTAssertTrue(overlay.isVisible)
        let clipView = controller.scrollView.contentView
        let expectedFrame = window.convertToScreen(clipView.convert(clipView.bounds, to: nil))
        XCTAssertEqual(overlay.frame, expectedFrame)

        controller.stop()
        XCTAssertFalse(window.childWindows?.contains(overlay) == true)
        XCTAssertFalse(overlay.isVisible)
    }

    func testTextDropdownConsumesWheelBeforeLongImageDocumentScroll() throws {
        var documentScrollCount = 0
        let overlay = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .longImageEditor(
                windowFrame: NSRect(x: 0, y: 0, width: 500, height: 400),
                selectionRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                scrollHandler: { _ in documentScrollCount += 1 }
            )
        ) { _ in }
        overlay.test_activateTextTool()
        overlay.test_openTextFontDropdown()
        let dropdown = try XCTUnwrap(overlay.test_textDropdownRect)
        let dropdownOffset = overlay.test_textDropdownScrollOffset

        overlay.test_scrollWheel(at: NSPoint(x: dropdown.midX, y: dropdown.midY), deltaY: -80)

        XCTAssertEqual(documentScrollCount, 0)
        XCTAssertGreaterThan(overlay.test_textDropdownScrollOffset, dropdownOffset)
    }

    func testControllerBakesDependencyAwareCompositeAndSuppressesCommittedRedraw() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 200, height: 1_200, scale: 2)
        var style = CaptureAnnotationStyle(); style.strokeWidth = 8
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 14)
        let earlier = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 20, y: 35, width: 150, height: 70),
            style: style,
            mosaicRedaction: redaction
        )
        let direct = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 25, y: 115, width: 145, height: 65),
            style: style,
            mosaicRedaction: redaction
        )
        let controller = LongImageEditorWindowController(
            canonicalImage: image,
            annotations: [earlier, direct],
            visibleFrame: NSRect(x: 0, y: 0, width: 600, height: 500),
            initialWindowSize: NSSize(width: 400, height: 420)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let background = try XCTUnwrap(overlay.test_backgroundImage)
        let expected = CaptureAnnotationRenderer.renderVisibleLongImageSlice(
            image: image,
            annotations: [earlier, direct],
            eraserMasks: [],
            imageRect: controller.visibleImageRect
        )
        XCTAssertEqual(try pixelBytes(background), try pixelBytes(expected))
        XCTAssertEqual(overlay.test_suppressedAnnotationIDs, Set(overlay.editorSnapshot?.annotations.map(\.id) ?? []))

        overlay.test_setAnnotations([])
        controller.test_commitOverlay()
        controller.test_refreshOverlay()
        XCTAssertTrue(controller.test_fullAnnotations.isEmpty)
        XCTAssertTrue(try XCTUnwrap(controller.test_editingOverlay?.test_suppressedAnnotationIDs).isEmpty)
        controller.stop()
    }

    func testSelectingAnnotationToolDoesNotFlashBakedPreviewOrDisableScroller() throws {
        var style = CaptureAnnotationStyle()
        style.strokeColor = .red
        style.strokeWidth = 8
        let existing = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 20, y: 40, width: 80, height: 60),
            style: style
        )
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(size: NSSize(width: 200, height: 1_000), color: .white),
            annotations: [existing],
            visibleFrame: NSRect(x: 0, y: 0, width: 600, height: 500),
            initialWindowSize: NSSize(width: 400, height: 420)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let initialBackground = try pixelBytes(try XCTUnwrap(overlay.test_backgroundImage))
        let initialSuppressedIDs = overlay.test_suppressedAnnotationIDs
        let rectangleButton = try XCTUnwrap(overlay.test_mainToolbarButtonPoint(for: .rectangle))

        overlay.test_mouseDown(at: rectangleButton)

        XCTAssertTrue(try XCTUnwrap(controller.scrollView.verticalScroller).isEnabled)
        XCTAssertEqual(try pixelBytes(try XCTUnwrap(overlay.test_backgroundImage)), initialBackground)
        XCTAssertEqual(overlay.test_suppressedAnnotationIDs, initialSuppressedIDs)
        overlay.test_mouseUp(at: rectangleButton)
        controller.stop()
    }

    func testStartingNewAnnotationKeepsBakedPreviewStableDuringDrawing() throws {
        var style = CaptureAnnotationStyle()
        style.strokeColor = .red
        style.strokeWidth = 8
        let existing = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 20, y: 40, width: 80, height: 60),
            style: style
        )
        let controller = LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(size: NSSize(width: 200, height: 1_000), color: .white),
            annotations: [existing],
            visibleFrame: NSRect(x: 0, y: 0, width: 600, height: 500),
            initialWindowSize: NSSize(width: 400, height: 420)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        overlay.test_activateShapeTool(.rectangle)
        let initialBackground = try pixelBytes(try XCTUnwrap(overlay.test_backgroundImage))
        let initialSuppressedIDs = overlay.test_suppressedAnnotationIDs
        let startPoint = NSPoint(x: 150, y: 260)

        overlay.test_mouseDown(at: startPoint)

        XCTAssertTrue(try XCTUnwrap(controller.scrollView.verticalScroller).isEnabled)
        XCTAssertEqual(try pixelBytes(try XCTUnwrap(overlay.test_backgroundImage)), initialBackground)
        XCTAssertEqual(overlay.test_suppressedAnnotationIDs, initialSuppressedIDs)
        overlay.test_mouseUp(at: NSPoint(x: 180, y: 300))
        controller.stop()
    }

    func testCheckAndCrossDoNotGrowWhenPointEraserBegins() throws {
        let image = TestImageFactory.solid(size: NSSize(width: 200, height: 1_000), color: .white)
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.textSize = 8
        let check = CaptureAnnotation(
            kind: .numberSequence,
            rect: NSRect(x: 30, y: 40, width: 36, height: 36),
            style: style,
            numberMarkType: .check
        )
        let cross = CaptureAnnotation(
            kind: .numberSequence,
            rect: NSRect(x: 100, y: 110, width: 36, height: 36),
            style: style,
            numberMarkType: .cross
        )
        let controller = LongImageEditorWindowController(
            canonicalImage: image,
            annotations: [check, cross],
            visibleFrame: NSRect(x: 0, y: 0, width: 600, height: 500),
            initialWindowSize: NSSize(width: 400, height: 420)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        overlay.test_activateEraserTool()
        let before = try XCTUnwrap(overlay.test_renderedOverlayImage())
        let beforeCount = redDominantPixelCount(before)
        let bounds = try XCTUnwrap(overlay.contentView?.bounds)
        let mainToolbar = overlay.test_mainToolbarRect() ?? .zero
        let optionsToolbar = overlay.test_optionsToolbarRect ?? .zero
        let annotationRects = overlay.editorSnapshot?.annotations.map(\.rect) ?? []
        let clickPoint = try XCTUnwrap([
            NSPoint(x: 20, y: 20),
            NSPoint(x: bounds.midX, y: bounds.midY),
            NSPoint(x: bounds.maxX - 20, y: bounds.maxY - 20),
        ].first { point in
            !mainToolbar.contains(point)
                && !optionsToolbar.contains(point)
                && !annotationRects.contains(where: { $0.contains(point) })
        })

        overlay.test_mouseDown(at: clickPoint)

        XCTAssertTrue(overlay.test_suppressedAnnotationIDs.isEmpty)
        let during = try XCTUnwrap(overlay.test_renderedOverlayImage())
        let duringCount = redDominantPixelCount(during)
        XCTAssertGreaterThan(beforeCount, 0)
        XCTAssertEqual(
            Double(duringCount),
            Double(beforeCount),
            accuracy: max(20, Double(beforeCount) * 0.3)
        )
        overlay.test_mouseUp(at: clickPoint)
        controller.stop()
    }

    func testBakedPreviewUnsuppressesSelectedAnnotationDuringLiveDragAndRebakesOnMouseUp() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 200, height: 1_000, scale: 2)
        var style = CaptureAnnotationStyle(); style.strokeColor = .red; style.strokeWidth = 8
        let selected = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 30, y: 40, width: 80, height: 60),
            style: style
        )
        let later = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 100, y: 110, width: 70, height: 50),
            style: style
        )
        let controller = LongImageEditorWindowController(
            canonicalImage: image,
            annotations: [selected, later],
            visibleFrame: NSRect(x: 0, y: 0, width: 600, height: 500),
            initialWindowSize: NSSize(width: 400, height: 420)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let local = try XCTUnwrap(overlay.editorSnapshot?.annotations.first { $0.id == selected.id })
        let down = NSPoint(x: local.rect.minX, y: local.rect.midY)
        overlay.test_mouseDown(at: down)

        XCTAssertFalse(overlay.test_suppressedAnnotationIDs.contains(selected.id))
        XCTAssertTrue(overlay.test_suppressedAnnotationIDs.isEmpty)
        let raw = try XCTUnwrap(CaptureAnnotationRenderer.sampleLongImage(image, rect: controller.visibleImageRect))
        XCTAssertEqual(try pixelBytes(try XCTUnwrap(overlay.test_backgroundImage)), try pixelBytes(raw))

        overlay.test_mouseDragged(to: NSPoint(x: down.x + 24, y: down.y + 18))
        XCTAssertNotEqual(overlay.editorSnapshot?.annotations.first { $0.id == selected.id }?.rect, local.rect)
        overlay.test_mouseUp(at: NSPoint(x: down.x + 24, y: down.y + 18))

        XCTAssertEqual(overlay.test_suppressedAnnotationIDs, Set(overlay.editorSnapshot?.annotations.map(\.id) ?? []))
        let expected = CaptureAnnotationRenderer.renderVisibleLongImageSlice(
            image: image,
            annotations: controller.test_fullAnnotations,
            eraserMasks: controller.test_fullEraserMasks,
            imageRect: controller.visibleImageRect
        )
        XCTAssertEqual(try pixelBytes(try XCTUnwrap(overlay.test_backgroundImage)), try pixelBytes(expected))
        controller.stop()
    }

    func testLiveSuffixMagnifierForcesRawBackgroundAndUnsuppressesPrefix() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 200, height: 1_000, scale: 2)
        let style = CaptureAnnotationStyle()
        let prefix = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 20, width: 60, height: 50), style: style)
        let selected = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 40, y: 80, width: 80, height: 60), style: style)
        let magnifier = CaptureAnnotation(
            kind: .magnifier, rect: NSRect(x: 100, y: 100, width: 80, height: 80),
            style: style, magnifierShape: .rectangle, magnifierZoom: 2
        )
        let controller = LongImageEditorWindowController(
            canonicalImage: image, annotations: [prefix, selected, magnifier],
            visibleFrame: NSRect(x: 0, y: 0, width: 600, height: 500),
            initialWindowSize: NSSize(width: 400, height: 420)
        )
        controller.show()
        controller.showEditingToolbar()
        let overlay = try XCTUnwrap(controller.test_editingOverlay)
        let local = try XCTUnwrap(overlay.editorSnapshot?.annotations.first { $0.id == selected.id })
        overlay.test_mouseDown(at: NSPoint(x: local.rect.minX, y: local.rect.midY))
        XCTAssertTrue(overlay.test_suppressedAnnotationIDs.isEmpty)
        let raw = try XCTUnwrap(CaptureAnnotationRenderer.sampleLongImage(image, rect: controller.visibleImageRect))
        XCTAssertEqual(try pixelBytes(try XCTUnwrap(overlay.test_backgroundImage)), try pixelBytes(raw))
        overlay.test_mouseUp(at: NSPoint(x: local.rect.minX, y: local.rect.midY))
        controller.stop()
    }

    func testInvalidMosaicEffectInputsRemainFiniteAndDoNotShrinkProcessing() throws {
        let image = TestImageFactory.verticalDocumentViewport(offset: 0, width: 180, height: 700, scale: 2)
        var style = CaptureAnnotationStyle(); style.strokeWidth = .infinity
        let annotation = CaptureAnnotation(
            kind: .mosaicRectangle, rect: NSRect(x: 20, y: 250, width: 140, height: 180),
            style: style, mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: -20)
        )
        let requested = NSRect(x: 0, y: 300, width: 180, height: 120)
        let plan = CaptureAnnotationRenderer.visibleLongImageRenderPlan(
            imageSize: image.size, imageRect: requested, annotations: [annotation], eraserMasks: []
        )
        XCTAssertTrue(plan.processingRect.minY.isFinite)
        XCTAssertTrue(plan.processingRect.height.isFinite)
        XCTAssertGreaterThanOrEqual(plan.processingRect.height, requested.height)
        let output = CaptureAnnotationRenderer.renderVisibleLongImageSlice(
            image: image, annotations: [annotation], eraserMasks: [], imageRect: requested
        )
        XCTAssertEqual(pixelSize(output), NSSize(width: 360, height: 240))
    }

    func testLongImageExportIgnoresOrphanMasksWhenThereAreNoAnnotations() {
        let image = TestImageFactory.solid(size: NSSize(width: 160, height: 320), color: .red, scale: 2)
        let orphan = EraserMask(rect: NSRect(x: 10, y: 10, width: 20, height: 20), affectedAnnotationIDs: [UUID()])
        XCTAssertTrue(CaptureAnnotationRenderer.renderLongImage(image: image, annotations: [], eraserMasks: [orphan]) === image)
    }

    func testEditorInteractionCallbacksLockAndUnlockDocumentScrolling() throws {
        let controller = LongImageEditorWindowController(
            image: TestImageFactory.solid(size: NSSize(width: 200, height: 1_000), color: .white),
            visibleFrame: NSRect(x: 0, y: 0, width: 600, height: 500),
            initialWindowSize: NSSize(width: 400, height: 420)
        )
        controller.show()
        controller.showEditingToolbar()
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
            retainedController?.showEditingToolbar()
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

    private func fractionallySampleTopOrigin(_ image: NSImage, rect: NSRect) throws -> NSImage {
        let source = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let sx = CGFloat(source.width) / image.size.width, sy = CGFloat(source.height) / image.size.height
        let requested = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy)
        let enclosing = requested.integral.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let crop = try XCTUnwrap(source.cropping(to: enclosing))
        let width = Int(requested.width.rounded()), height = Int(requested.height.rounded())
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: source.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.interpolationQuality = .none
        context.draw(crop, in: CGRect(
            x: enclosing.minX - requested.minX, y: enclosing.minY - requested.minY,
            width: enclosing.width, height: enclosing.height
        ))
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: rect.size)
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

    private func maxChannelDifference(_ lhs: Data, _ rhs: Data) -> Int {
        guard lhs.count == rhs.count else { return .max }
        return zip(lhs, rhs).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
    }

    private func redDominantPixelCount(_ image: NSImage) -> Int {
        guard let bytes = try? pixelBytes(image) else { return 0 }
        return stride(from: 0, to: bytes.count, by: 4).reduce(into: 0) { count, index in
            if bytes[index] > 180,
               bytes[index + 1] < 130,
               bytes[index + 2] < 130,
               bytes[index + 3] > 0 {
                count += 1
            }
        }
    }

    private func makeTallController() -> LongImageEditorWindowController {
        LongImageEditorWindowController(
            canonicalImage: TestImageFactory.solid(size: NSSize(width: 200, height: 1_200), color: .white),
            visibleFrame: NSRect(x: 50, y: 40, width: 500, height: 450),
            initialWindowSize: NSSize(width: 400, height: 400)
        )
    }
}
