import AppKit
import ObjectiveC.runtime
import XCTest
@testable import xxsnap

final class ScrollCaptureBridgeTests: XCTestCase {
    func testAppendKindRawValueMatrixMatchesCoreContract() {
        XCTAssertEqual(
            [
                ScrollCaptureAppendKind.acceptedInitial,
                .acceptedAppend,
                .duplicateDiscarded,
                .reviewDiscarded,
                .awaitingEvidence,
                .lowConfidenceDiscarded,
                .resourceLimit,
            ].map(\.rawValue),
            Array(0...6)
        )
    }

    func testDirectionRawValueMatrixMatchesCoreContract() {
        XCTAssertEqual(
            [ScrollCaptureDirection.unknown, .down, .up].map(\.rawValue),
            Array(0...2)
        )
        XCTAssertEqual(
            ScrollCaptureAppendUpdate.testValue(kind: .duplicateDiscarded).direction,
            .unknown
        )
    }

    func testPreferredDirectionIsForwardedToCoreAppend() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        let first = TestImageFactory.verticalDocumentViewport(offset: 0, width: 64, height: 96)
        let second = TestImageFactory.verticalDocumentViewport(offset: 32, width: 64, height: 96)

        XCTAssertEqual(try bridge.append(first).kind, .acceptedInitial)
        let update = try bridge.append(second, preferredDirection: .down)

        XCTAssertEqual(update.kind, .acceptedAppend)
        XCTAssertEqual(update.direction, .down)
    }

    func testExpectedPointAdvanceResolvesRetinaStationaryWatermarkAmbiguity() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        XCTAssertEqual(
            try bridge.append(
                TestImageFactory.sparseChatWithStationaryWatermark(offset: 40),
                preferredDirection: .down,
                expectedAdvance: 0
            ).kind,
            .acceptedInitial
        )

        let update = try bridge.append(
            TestImageFactory.sparseChatWithStationaryWatermark(offset: 80),
            preferredDirection: .down,
            expectedAdvance: 40
        )

        XCTAssertEqual(update.kind, .acceptedAppend)
        XCTAssertEqual(update.appendedHeight, 80)
        XCTAssertEqual(update.outputHeight, 320)
    }

    func testViewportSizedAppendAndPreviewCompleteWithinInteractiveBudget() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 128 * 1024 * 1024))
        let first = TestImageFactory.verticalDocumentViewportWithFixedFooter(
            offset: 0,
            pointWidth: 847,
            pointHeight: 807,
            footerPointHeight: 96,
            scale: 2
        )
        XCTAssertEqual(try bridge.append(first).kind, .acceptedInitial)
        let liveFrames = [140, 280, 420].map { offset in
            TestImageFactory.verticalDocumentViewportWithFixedFooter(
                offset: offset,
                pointWidth: 847,
                pointHeight: 807,
                footerPointHeight: 96,
                scale: 2
            )
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        var update: ScrollCaptureAppendUpdate?
        for frame in liveFrames {
            update = try bridge.append(
                frame,
                preferredDirection: .down,
                expectedAdvance: 140
            )
        }
        let preview = try bridge.preview(maximumWidth: 600)
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt

        XCTAssertNotNil(update)
        XCTAssertNotNil(preview)
        XCTAssertLessThan(elapsed, 0.5, "three appends and preview took \(elapsed) seconds")
    }

    func testTenSequentialScrollFramesRemainInWidthFittedPreview() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 32 * 1024 * 1024))
        let offsets = stride(from: 0, through: 320, by: 32)
        let updates = try offsets.map { offset in
            try bridge.append(
                TestImageFactory.verticalDocumentViewport(offset: offset, width: 64, height: 96),
                preferredDirection: .down
            )
        }

        XCTAssertEqual(updates.first?.kind, .acceptedInitial)
        XCTAssertTrue(updates.dropFirst().allSatisfy { $0.kind == .acceptedAppend })
        XCTAssertEqual(updates.last?.outputHeight, 416)

        let preview = try bridge.preview(maximumWidth: 32)
        XCTAssertEqual(preview.representations.first?.pixelsWide, 32)
        XCTAssertEqual(preview.representations.first?.pixelsHigh, 208)
    }

    func testRuntimeInitializerCannotCreateDefaultAppendUpdate() throws {
        let object = try XCTUnwrap(class_createInstance(ScrollCaptureAppendUpdate.self, 0))
        let selector = NSSelectorFromString("init")
        let method = try XCTUnwrap(class_getInstanceMethod(ScrollCaptureAppendUpdate.self, selector))
        typealias Initializer = @convention(c) (UnsafeMutableRawPointer, Selector) -> UnsafeMutableRawPointer?
        let initialize = unsafeBitCast(method_getImplementation(method), to: Initializer.self)
        let retainedObject = Unmanaged.passRetained(object as AnyObject)

        let result = initialize(retainedObject.toOpaque(), selector)
        if let result {
            Unmanaged<AnyObject>.fromOpaque(result).release()
        }

        XCTAssertNil(result)
    }

    func testRejectsClearlyNonUniformImageScale() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 1_000_000))
        let image = TestImageFactory.solid(
            pixelWidth: 100,
            pixelHeight: 200,
            pointSize: CGSize(width: 100, height: 100),
            color: .black
        )

        assertBridgeError { try bridge.append(image) }
    }

    func testAcceptsOnePixelRepresentationRoundingWithUnifiedScale() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 1_000_000))
        let image = TestImageFactory.solid(
            pixelWidth: 100,
            pixelHeight: 101,
            pointSize: CGSize(width: 50, height: 50),
            color: .black
        )

        XCTAssertEqual(try bridge.append(image).kind, .acceptedInitial)
        let final = try XCTUnwrap(bridge.finalImage())
        XCTAssertEqual(100 / final.size.width, 2.01, accuracy: 0.001)
        XCTAssertEqual(101 / final.size.height, 2.01, accuracy: 0.001)
    }

    func testRuntimeAllocatedUninitializedBridgeReturnsErrorInsteadOfCrashing() throws {
        let object = try XCTUnwrap(class_createInstance(ScrollCaptureBridge.self, 0))
        let bridge = try XCTUnwrap(object as? ScrollCaptureBridge)

        assertBridgeError {
            try bridge.append(TestImageFactory.solid(size: CGSize(width: 8, height: 8), color: .black))
        }
        assertBridgeError { try bridge.preview(maximumHeight: 8) }
        assertBridgeError { try bridge.finalImage() }
    }

    func testFinalImagePreservesVisualCornerOrientation() throws {
        let source = TestImageFactory.fourCornerMarkers()
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 1_000_000))
        _ = try bridge.append(source)
        let final = try XCTUnwrap(bridge.finalImage())

        let points = [(2, 2), (21, 2), (2, 17), (21, 17)]
        XCTAssertEqual(renderedPixels(source, at: points), renderedPixels(final, at: points))
    }

    func testInitialFrameHasNoSeamAndDuplicateDoesNotAddAnotherBoundary() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        let first = TestImageFactory.verticalDocumentViewport(offset: 0, width: 64, height: 96)
        let second = TestImageFactory.verticalDocumentViewport(offset: 32, width: 64, height: 96)

        XCTAssertEqual(try bridge.append(first).kind, .acceptedInitial)
        let initialFinal = try XCTUnwrap(bridge.finalImage())
        XCTAssertEqual(renderedBGRAPixels(initialFinal), renderedBGRAPixels(first))

        XCTAssertEqual(try bridge.append(second).kind, .acceptedAppend)
        let beforeDuplicate = try XCTUnwrap(bridge.finalImage())
        XCTAssertEqual(try bridge.append(second).kind, .duplicateDiscarded)
        let afterDuplicate = try XCTUnwrap(bridge.finalImage())

        XCTAssertEqual(afterDuplicate.representations.first?.pixelsHigh, 128)
        XCTAssertEqual(renderedBGRAPixels(afterDuplicate), renderedBGRAPixels(beforeDuplicate))
    }

    func testReviewAndLowConfidenceAreMappedWithoutChangingTheAcceptedBaseline() throws {
        let reverseBridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        _ = try reverseBridge.append(TestImageFactory.verticalDocumentViewport(offset: 0))
        _ = try reverseBridge.append(TestImageFactory.verticalDocumentViewport(offset: 32))
        XCTAssertEqual(
            try reverseBridge.append(TestImageFactory.verticalDocumentViewport(offset: 0)).kind,
            .reviewDiscarded
        )

        let recoveringBridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        _ = try recoveringBridge.append(TestImageFactory.verticalDocumentViewport(offset: 0))
        XCTAssertEqual(
            try recoveringBridge.append(
                TestImageFactory.verticalDocumentViewport(offset: 500),
                preferredDirection: .down
            ).kind,
            .lowConfidenceDiscarded
        )
        XCTAssertEqual(
            try recoveringBridge.append(
                TestImageFactory.verticalDocumentViewport(offset: 532),
                preferredDirection: .down
            ).kind,
            .lowConfidenceDiscarded
        )
    }

    func testFirstReliableUpwardMovementPrependsInNaturalOrder() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        let offsets = [96, 64, 32, 0]

        let updates = try offsets.map { offset in
            try bridge.append(TestImageFactory.verticalDocumentViewport(
                offset: offset,
                width: 64,
                height: 96
            ))
        }

        XCTAssertEqual(updates.map(\.kind), [
            .acceptedInitial,
            .acceptedAppend,
            .acceptedAppend,
            .acceptedAppend,
        ])
        XCTAssertEqual(updates.dropFirst().map(\.direction), [.up, .up, .up])
        let final = try XCTUnwrap(bridge.finalImage())
        let expected = TestImageFactory.verticalDocument(width: 64, height: 192)
        assertRenderedPixelsEqual(
            final,
            expected,
            seamRows: [32, 64, 96],
            scale: 1
        )
    }

    func testFixedRegionEvidenceMapsAsAwaitingWithoutLosingFinalPixels() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 32 * 1024 * 1024))
        let seed = TestImageFactory.verticalDocumentViewportWithFixedFooter(offset: 0, scale: 1)

        XCTAssertEqual(try bridge.append(seed).kind, .acceptedInitial)
        for offset in [15, 30] {
            let update = try bridge.append(
                TestImageFactory.verticalDocumentViewportWithFixedFooter(offset: offset, scale: 1)
            )
            XCTAssertEqual(update.kind, .awaitingEvidence)
            XCTAssertEqual(try XCTUnwrap(bridge.finalImage()).size.height, seed.size.height + CGFloat(offset))
        }

        let confirmation = try bridge.append(
            TestImageFactory.verticalDocumentViewportWithFixedFooter(offset: 45, scale: 1)
        )
        XCTAssertEqual(confirmation.kind, .acceptedAppend)
        let final = try XCTUnwrap(bridge.finalImage())
        let expected = TestImageFactory.downwardDocumentWithFixedFooter(
            initialScrollingHeight: 280 - 64,
            appendedHeight: 45,
            footerHeight: 64,
            width: 60,
            scale: 1
        )
        assertRenderedPixelsEqual(final, expected, seamRows: [280, 295, 310], scale: 1)
    }

    func testOneXFinalDoesNotModifyPixelsAtAcceptedBoundary() throws {
        let scale: CGFloat = 1
        let width = 64
        let height = 96
        let seamY = 96
        let sourceSeamY = 64
        let sampleX = 13
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        let first = TestImageFactory.verticalDocumentViewport(
            offset: 0, width: width, height: height, scale: scale
        )
        let second = replacingBGRAPixel(
            in: TestImageFactory.verticalDocumentViewport(
                offset: 32, width: width, height: height, scale: scale
            ),
            x: sampleX,
            topDownY: sourceSeamY,
            with: [10, 20, 30, 80]
        )

        XCTAssertEqual(try bridge.append(first).kind, .acceptedInitial)
        let update = try bridge.append(second)
        let final = try XCTUnwrap(bridge.finalImage())
        let firstPixels = renderedBGRAPixels(first)
        let secondPixels = renderedBGRAPixels(second)
        let finalPixels = renderedBGRAPixels(final)
        let sourcePixel = bgraPixel(
            secondPixels, width: width, x: sampleX, y: sourceSeamY
        )

        XCTAssertEqual(update.kind, .acceptedAppend)
        XCTAssertEqual(update.direction, .down)
        XCTAssertEqual(update.appendedHeight, 32)
        XCTAssertEqual(update.outputHeight, 128)
        XCTAssertEqual(final.representations.first?.pixelsWide, width)
        XCTAssertEqual(final.representations.first?.pixelsHigh, 128)
        XCTAssertEqual(final.size.height, 128, accuracy: 0.001)
        XCTAssertEqual(sourcePixel, [10, 20, 30, 80])
        XCTAssertEqual(
            bgraPixel(finalPixels, width: width, x: sampleX, y: seamY),
            sourcePixel
        )
        XCTAssertEqual(
            bgraPixel(finalPixels, width: width, x: sampleX, y: seamY - 1),
            bgraPixel(firstPixels, width: width, x: sampleX, y: height - 1)
        )
        XCTAssertEqual(
            bgraPixel(finalPixels, width: width, x: sampleX, y: seamY + 1),
            bgraPixel(secondPixels, width: width, x: sampleX, y: sourceSeamY + 1)
        )
    }

    func testTwoXFinalDoesNotModifyPixelsAtAcceptedBoundary() throws {
        let scale: CGFloat = 2
        let pointWidth = 64
        let pointHeight = 96
        let pixelWidth = Int(CGFloat(pointWidth) * scale)
        let seamY = Int(CGFloat(pointHeight) * scale)
        let sourceSeamY = Int(CGFloat(64) * scale)
        let sampleX = 26
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        let first = TestImageFactory.verticalDocumentViewport(
            offset: 0, width: pointWidth, height: pointHeight, scale: scale
        )
        let second = TestImageFactory.verticalDocumentViewport(
            offset: 32, width: pointWidth, height: pointHeight, scale: scale
        )

        XCTAssertEqual(try bridge.append(first).kind, .acceptedInitial)
        let update = try bridge.append(second)
        let final = try XCTUnwrap(bridge.finalImage())
        let firstPixels = renderedBGRAPixels(first)
        let secondPixels = renderedBGRAPixels(second)
        let finalPixels = renderedBGRAPixels(final)
        let sourcePixel = bgraPixel(
            secondPixels, width: pixelWidth, x: sampleX, y: sourceSeamY
        )

        XCTAssertEqual(update.kind, .acceptedAppend)
        XCTAssertEqual(update.appendedHeight, 64)
        XCTAssertEqual(update.outputHeight, 256)
        XCTAssertEqual(final.representations.first?.pixelsWide, pixelWidth)
        XCTAssertEqual(final.representations.first?.pixelsHigh, 256)
        XCTAssertEqual(final.size.height, 128, accuracy: 0.001)
        XCTAssertEqual(
            bgraPixel(finalPixels, width: pixelWidth, x: sampleX, y: seamY),
            sourcePixel
        )
        XCTAssertEqual(
            bgraPixel(finalPixels, width: pixelWidth, x: sampleX, y: seamY - 1),
            bgraPixel(firstPixels, width: pixelWidth, x: sampleX, y: seamY - 1)
        )
        XCTAssertEqual(
            bgraPixel(finalPixels, width: pixelWidth, x: sampleX, y: seamY + 1),
            bgraPixel(secondPixels, width: pixelWidth, x: sampleX, y: sourceSeamY + 1)
        )
    }

    func testRejectedTwoXSeedDoesNotAffectAcceptedOneXBoundaryPixels() throws {
        let width = 64
        let height = 96
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 80_000))
        let rejectedSeed = TestImageFactory.verticalDocumentViewport(
            offset: 0, width: width, height: height, scale: 2
        )
        let acceptedSeed = TestImageFactory.verticalDocumentViewport(
            offset: 0, width: width, height: height, scale: 1
        )
        let second = TestImageFactory.verticalDocumentViewport(
            offset: 32, width: width, height: height, scale: 1
        )

        XCTAssertEqual(try bridge.append(rejectedSeed).kind, .resourceLimit)
        XCTAssertEqual(try bridge.append(acceptedSeed).kind, .acceptedInitial)
        let update = try bridge.append(second)
        let final = try XCTUnwrap(bridge.finalImage())
        let finalPixels = renderedBGRAPixels(final)
        let secondPixels = renderedBGRAPixels(second)
        let sourcePixel = bgraPixel(secondPixels, width: width, x: 13, y: 64)
        let seamPixel = bgraPixel(finalPixels, width: width, x: 13, y: 96)

        XCTAssertEqual(update.kind, .acceptedAppend)
        XCTAssertEqual(update.outputHeight, 128)
        XCTAssertEqual(final.representations.first?.pixelsWide, width)
        XCTAssertEqual(final.representations.first?.pixelsHigh, 128)
        XCTAssertEqual(final.size, CGSize(width: 64, height: 128))
        assertSeamPixel(seamPixel, source: sourcePixel, scale: 1)
    }

    func testDownsampledPreviewAndFinalUseTheSameMappedSeamCoverage() throws {
        let width = 64
        let height = 96
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        let first = TestImageFactory.verticalDocumentViewport(offset: 0, width: width, height: height)
        let second = TestImageFactory.verticalDocumentViewport(offset: 32, width: width, height: height)

        XCTAssertEqual(try bridge.append(first).kind, .acceptedInitial)
        XCTAssertEqual(try bridge.append(second).kind, .acceptedAppend)
        let final = try XCTUnwrap(bridge.finalImage())
        let preview = try XCTUnwrap(bridge.preview(maximumHeight: 64))
        let sourcePixels = renderedBGRAPixels(second)
        let finalPixels = renderedBGRAPixels(final)
        let previewPixels = renderedBGRAPixels(preview)
        let sourcePixel = bgraPixel(sourcePixels, width: width, x: 12, y: 64)
        let finalSeam = bgraPixel(finalPixels, width: width, x: 12, y: 96)
        let previewSeam = bgraPixel(previewPixels, width: 32, x: 6, y: 48)

        XCTAssertEqual(preview.representations.first?.pixelsWide, 32)
        XCTAssertEqual(preview.representations.first?.pixelsHigh, 64)
        assertSeamPixel(finalSeam, source: sourcePixel, scale: 1)
        assertSeamPixel(previewSeam, source: sourcePixel, scale: 1)
        XCTAssertEqual(previewSeam, finalSeam)
        XCTAssertEqual(
            bgraPixel(previewPixels, width: 32, x: 6, y: 47),
            bgraPixel(finalPixels, width: width, x: 12, y: 94)
        )
        XCTAssertEqual(
            bgraPixel(previewPixels, width: 32, x: 6, y: 49),
            bgraPixel(finalPixels, width: width, x: 12, y: 98)
        )
    }

    func testInitialTwoXFrameKeepsFinalAndPreviewPixelAndPointDimensions() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        let source = TestImageFactory.verticalDocumentViewport(
            offset: 0, width: 40, height: 80, scale: 2
        )
        XCTAssertEqual(try bridge.append(source).kind, .acceptedInitial)

        let preview = try XCTUnwrap(bridge.preview(maximumHeight: 80))
        let final = try XCTUnwrap(bridge.finalImage())

        XCTAssertEqual(preview.representations.first?.pixelsWide, 40)
        XCTAssertEqual(preview.representations.first?.pixelsHigh, 80)
        XCTAssertEqual(preview.size.width, 20, accuracy: 0.001)
        XCTAssertEqual(preview.size.height, 40, accuracy: 0.001)
        XCTAssertEqual(final.representations.first?.pixelsWide, 80)
        XCTAssertEqual(final.representations.first?.pixelsHigh, 160)
        XCTAssertEqual(final.size.width, 40, accuracy: 0.001)
        XCTAssertEqual(final.size.height, 80, accuracy: 0.001)
    }

    func testPreviewLimitsPixelWidthSoLongPreviewKeepsAStableDisplayWidth() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        for offset in [0, 32, 64] {
            _ = try bridge.append(TestImageFactory.verticalDocumentViewport(
                offset: offset, width: 64, height: 96, scale: 1
            ))
        }

        let preview = try XCTUnwrap(bridge.preview(maximumWidth: 32))

        XCTAssertEqual(preview.representations.first?.pixelsWide, 32)
        XCTAssertGreaterThan(try XCTUnwrap(preview.representations.first?.pixelsHigh), 48)
        XCTAssertEqual(preview.size.width, 32, accuracy: 0.001)
    }

    func testInvalidInputsReturnErrorsWithoutCrashing() throws {
        XCTAssertNil(ScrollCaptureBridge(maximumAcceptedBytes: 0))
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 1_000_000))

        assertBridgeError { try bridge.append(NSImage(size: .zero)) }
        assertBridgeError { try bridge.preview(maximumHeight: 0) }
        assertBridgeError { try bridge.preview(maximumWidth: 0) }
        assertBridgeError { try bridge.finalImage() }
    }

    func testResourceLimitKeepsPreviouslyAcceptedFinalImage() throws {
        let frame = TestImageFactory.verticalDocumentViewport(offset: 0, width: 32, height: 48)
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 32 * 48 * 4 + 1024))
        XCTAssertEqual(try bridge.append(frame).kind, .acceptedInitial)

        let update = try bridge.append(TestImageFactory.verticalDocumentViewport(
            offset: 16, width: 32, height: 48
        ))

        XCTAssertEqual(update.kind, .resourceLimit)
        XCTAssertEqual(update.direction, .unknown)
        let final = try XCTUnwrap(bridge.finalImage())
        XCTAssertEqual(final.representations.first?.pixelsHigh, 48)
    }

    func testDefaultFixedBandBudgetUsesPointsForTwoXImages() throws {
        try assertFixedFooterIsRetainedOnce(scale: 2)
    }

    func testDefaultFixedBandBudgetKeepsOneXBehavior() throws {
        try assertFixedFooterIsRetainedOnce(scale: 1)
    }

    func testAutomaticFixedBandBudgetHandlesLargeChatComposer() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 32 * 1024 * 1024))
        let offsets = [0, 20, 40, 60]
        let updates = try offsets.map { offset in
            try bridge.append(
                TestImageFactory.verticalDocumentViewportWithFixedFooter(
                    offset: offset,
                    pointWidth: 320,
                    pointHeight: 280,
                    footerPointHeight: 120,
                    scale: 2
                ),
                preferredDirection: .down
            )
        }

        XCTAssertEqual(
            updates.map { $0.kind.rawValue },
            [
                ScrollCaptureAppendKind.acceptedInitial.rawValue,
                ScrollCaptureAppendKind.awaitingEvidence.rawValue,
                ScrollCaptureAppendKind.awaitingEvidence.rawValue,
                ScrollCaptureAppendKind.acceptedAppend.rawValue,
            ]
        )
        XCTAssertEqual(updates.last?.outputHeight, (280 + 60) * 2)
    }

    private func assertFixedFooterIsRetainedOnce(scale: CGFloat) throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 32 * 1024 * 1024))
        let offsets = [0, 15, 30, 45, 60]
        var kinds: [ScrollCaptureAppendKind] = []
        for offset in offsets {
            kinds.append(try bridge.append(TestImageFactory.verticalDocumentViewportWithFixedFooter(
                offset: offset,
                scale: scale
            )).kind)
        }

        let final = try XCTUnwrap(bridge.finalImage())
        XCTAssertEqual(final.representations.first?.pixelsHigh, Int((280 + 60) * scale))
        XCTAssertEqual(final.size.height, 340, accuracy: 0.001)
        XCTAssertEqual(kinds.last?.rawValue, ScrollCaptureAppendKind.acceptedAppend.rawValue)
    }

    private func renderedPixels(_ image: NSImage, at points: [(Int, Int)]) -> [[UInt8]] {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        let bytes = bitmap.bitmapData!
        return points.map { x, y in
            let offset = y * bitmap.bytesPerRow + x * 4
            return Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
        }
    }

    private func renderedBGRAPixels(_ image: NSImage) -> [UInt8] {
        let representation = image.representations.max {
            $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
        }
        let width = representation?.pixelsWide ?? Int(image.size.width)
        let height = representation?.pixelsHigh ?? Int(image.size.height)
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )!
            context.interpolationQuality = .none
            var rect = NSRect(origin: .zero, size: image.size)
            let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    private func expectedSeamChannel(
        _ value: UInt8,
        alpha _: UInt8 = 255,
        scale _: CGFloat
    ) -> UInt8 {
        value
    }

    private func bgraPixel(
        _ pixels: [UInt8],
        width: Int,
        x: Int,
        y: Int
    ) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(pixels[offset..<(offset + 4)])
    }

    private func assertSeamPixel(
        _ actual: [UInt8],
        source: [UInt8],
        scale: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, 4, file: file, line: line)
        XCTAssertEqual(source.count, 4, file: file, line: line)
        guard actual.count == 4, source.count == 4 else { return }
        XCTAssertNotEqual(source[0], source[1], file: file, line: line)
        XCTAssertNotEqual(source[0], source[2], file: file, line: line)
        XCTAssertNotEqual(source[1], source[2], file: file, line: line)
        for channel in 0..<3 {
            XCTAssertEqual(
                actual[channel],
                expectedSeamChannel(source[channel], alpha: source[3], scale: scale),
                "Unexpected BGRA channel \(channel)",
                file: file,
                line: line
            )
        }
        XCTAssertEqual(actual[3], source[3], "Seam changed alpha", file: file, line: line)
    }

    private func replacingBGRAPixel(
        in image: NSImage,
        x: Int,
        topDownY: Int,
        with pixel: [UInt8]
    ) -> NSImage {
        precondition(pixel.count == 4)
        var proposedRect = NSRect(origin: .zero, size: image.size)
        let source = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)!
        let sourceData = source.dataProvider!.data!
        var bytes = Data(
            bytes: CFDataGetBytePtr(sourceData)!,
            count: CFDataGetLength(sourceData)
        )
        let providerY = source.height - 1 - topDownY
        let offset = providerY * source.bytesPerRow + x * 4
        bytes.replaceSubrange(offset..<(offset + 4), with: pixel)
        let provider = CGDataProvider(data: bytes as CFData)!
        let replacement = CGImage(
            width: source.width,
            height: source.height,
            bitsPerComponent: source.bitsPerComponent,
            bitsPerPixel: source.bitsPerPixel,
            bytesPerRow: source.bytesPerRow,
            space: source.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: source.bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: source.renderingIntent
        )!
        let representation = NSBitmapImageRep(cgImage: replacement)
        representation.size = image.size
        let result = NSImage(size: image.size)
        result.addRepresentation(representation)
        return result
    }

    private func assertRenderedPixelsEqual(
        _ actualImage: NSImage,
        _ expectedImage: NSImage,
        seamRows: Set<Int>,
        scale: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = renderedBGRAPixels(actualImage)
        let expected = renderedBGRAPixels(expectedImage)
        let representation = expectedImage.representations.max {
            $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
        }
        let width = representation?.pixelsWide ?? Int(expectedImage.size.width)
        let height = representation?.pixelsHigh ?? Int(expectedImage.size.height)
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        XCTAssertEqual(expected.count, width * height * 4, file: file, line: line)
        XCTAssertTrue(
            seamRows.allSatisfy { $0 >= 0 && $0 < height },
            "Expected seam row is outside the image",
            file: file,
            line: line
        )
        guard actual.count == expected.count,
              expected.count == width * height * 4,
              seamRows.allSatisfy({ $0 >= 0 && $0 < height }) else { return }

        var changedSeamRows = Set<Int>()
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let actualPixel = Array(actual[offset..<(offset + 4)])
                let expectedPixel = Array(expected[offset..<(offset + 4)])
                if !seamRows.contains(y) {
                    if actualPixel != expectedPixel {
                        XCTFail(
                            "Rendered BGRA buffers differ outside seam at (\(x), \(y))",
                            file: file,
                            line: line
                        )
                        return
                    }
                    continue
                }
                let expectedSeamPixel = [
                    expectedSeamChannel(expectedPixel[0], alpha: expectedPixel[3], scale: scale),
                    expectedSeamChannel(expectedPixel[1], alpha: expectedPixel[3], scale: scale),
                    expectedSeamChannel(expectedPixel[2], alpha: expectedPixel[3], scale: scale),
                    expectedPixel[3],
                ]
                if actualPixel != expectedSeamPixel {
                    XCTFail(
                        "Unexpected seam coverage at (\(x), \(y))",
                        file: file,
                        line: line
                    )
                    return
                }
                if expectedPixel[3] > 0,
                   expectedPixel[..<3].contains(where: { $0 < expectedPixel[3] }),
                   actualPixel != expectedPixel {
                    changedSeamRows.insert(y)
                }
            }
        }
        XCTAssertTrue(
            changedSeamRows.isEmpty,
            "Accepted boundaries must not alter source pixels",
            file: file,
            line: line
        )
    }

    private func assertBridgeError<T>(
        _ expression: () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            let error = error as NSError
            XCTAssertEqual(error.domain, "com.xxsnap.scroll-capture-bridge", file: file, line: line)
            XCTAssertFalse(error.localizedDescription.isEmpty, file: file, line: line)
        }
    }
}
