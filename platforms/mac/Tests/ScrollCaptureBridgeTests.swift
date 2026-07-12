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

    func testDuplicateIsDiscardedAndInitialFrameRemainsFinal() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        let first = TestImageFactory.verticalDocumentViewport(offset: 0)
        let duplicate = TestImageFactory.verticalDocumentViewport(offset: 0)

        XCTAssertEqual(try bridge.append(first).kind, .acceptedInitial)
        XCTAssertEqual(try bridge.append(duplicate).kind, .duplicateDiscarded)
        XCTAssertNotNil(try bridge.finalImage())
    }

    func testReviewAndLowConfidenceKindsAreMapped() throws {
        let reverseBridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        _ = try reverseBridge.append(TestImageFactory.verticalDocumentViewport(offset: 0))
        _ = try reverseBridge.append(TestImageFactory.verticalDocumentViewport(offset: 32))
        XCTAssertEqual(
            try reverseBridge.append(TestImageFactory.verticalDocumentViewport(offset: 0)).kind,
            .reviewDiscarded
        )

        let unrelatedBridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        _ = try unrelatedBridge.append(TestImageFactory.verticalDocumentViewport(offset: 0))
        XCTAssertEqual(
            try unrelatedBridge.append(
                TestImageFactory.solid(size: CGSize(width: 64, height: 96), color: .gray)
            ).kind,
            .lowConfidenceDiscarded
        )
    }

    func testFirstReliableUpwardMovementPrependsInNaturalOrder() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        let offsets = [96, 64, 32, 0]

        let kinds = try offsets.map { offset in
            try bridge.append(TestImageFactory.verticalDocumentViewport(
                offset: offset,
                width: 64,
                height: 96
            )).kind
        }

        XCTAssertEqual(kinds, [
            .acceptedInitial,
            .acceptedAppend,
            .acceptedAppend,
            .acceptedAppend,
        ])
        let final = try XCTUnwrap(bridge.finalImage())
        let expected = TestImageFactory.verticalDocument(width: 64, height: 192)
        assertRenderedPixelsEqual(final, expected)
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
            assertRenderedPixelsEqual(try XCTUnwrap(bridge.finalImage()), seed)
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
        assertRenderedPixelsEqual(final, expected)
    }

    func testAppendPreservesDocumentDirectionAndSeamPixels() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        let first = TestImageFactory.verticalDocumentViewport(offset: 0, width: 64, height: 96)
        let second = TestImageFactory.verticalDocumentViewport(offset: 32, width: 64, height: 96)

        _ = try bridge.append(first)
        let update = try bridge.append(second)
        let final = try XCTUnwrap(bridge.finalImage())

        XCTAssertEqual(update.kind, .acceptedAppend)
        XCTAssertEqual(update.appendedHeight, 32)
        XCTAssertEqual(update.outputHeight, 128)
        XCTAssertEqual(final.representations.first?.pixelsWide, 64)
        XCTAssertEqual(final.representations.first?.pixelsHigh, 128)
        guard update.kind == .acceptedAppend,
              final.representations.first?.pixelsHigh == 128 else { return }
        XCTAssertEqual(
            renderedPixels(final, at: [(13, 96)]),
            renderedPixels(first, at: [(13, 64)])
        )
        XCTAssertEqual(
            renderedPixels(final, at: [(13, 31)]),
            renderedPixels(second, at: [(13, 31)])
        )
    }

    func testPreviewLimitsPixelHeightAndPreservesTwoXPointScale() throws {
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 16 * 1024 * 1024))
        _ = try bridge.append(TestImageFactory.verticalDocumentViewport(
            offset: 0, width: 40, height: 80, scale: 2
        ))

        let preview = try XCTUnwrap(bridge.preview(maximumHeight: 80))

        XCTAssertEqual(preview.representations.first?.pixelsWide, 40)
        XCTAssertEqual(preview.representations.first?.pixelsHigh, 80)
        XCTAssertEqual(preview.size.width, 20, accuracy: 0.001)
        XCTAssertEqual(preview.size.height, 40, accuracy: 0.001)
    }

    func testInvalidInputsReturnErrorsWithoutCrashing() throws {
        XCTAssertNil(ScrollCaptureBridge(maximumAcceptedBytes: 0))
        let bridge = try XCTUnwrap(ScrollCaptureBridge(maximumAcceptedBytes: 1_000_000))

        assertBridgeError { try bridge.append(NSImage(size: .zero)) }
        assertBridgeError { try bridge.preview(maximumHeight: 0) }
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
        let final = try XCTUnwrap(bridge.finalImage())
        XCTAssertEqual(final.representations.first?.pixelsHigh, 48)
    }

    func testDefaultFixedBandBudgetUsesPointsForTwoXImages() throws {
        try assertFixedFooterIsRetainedOnce(scale: 2)
    }

    func testDefaultFixedBandBudgetKeepsOneXBehavior() throws {
        try assertFixedFooterIsRetainedOnce(scale: 1)
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

    private func assertRenderedPixelsEqual(
        _ actualImage: NSImage,
        _ expectedImage: NSImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = renderedBGRAPixels(actualImage)
        let expected = renderedBGRAPixels(expectedImage)
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        guard actual.count == expected.count else { return }
        XCTAssertNil(
            actual.indices.first { actual[$0] != expected[$0] },
            "Rendered BGRA buffers differ",
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
