import AppKit
import ObjectiveC.runtime
import XCTest
@testable import xxsnap

final class ScrollCaptureBridgeTests: XCTestCase {
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
            .pausedLowConfidence
        )
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
