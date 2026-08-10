import AppKit
import CoreGraphics
import CoreVideo
import ScreenCaptureKit
import XCTest
@testable import xxsnap

final class ScreenCaptureServiceTests: XCTestCase {
    @MainActor
    func testScrollStreamConfigurationPreservesEnoughIntermediateFramesForFastScrolling() {
        let configuration = ScreenCaptureService.makeScrollStreamConfiguration(width: 320, height: 200)

        // Match PixPin's proven 100 ms cadence. Capturing faster than the serial
        // matcher can consume frames only evicts the overlap-preserving frames.
        XCTAssertEqual(configuration.minimumFrameInterval, CMTime(value: 1, timescale: 10))
        XCTAssertEqual(configuration.queueDepth, 5)
        XCTAssertEqual(ScreenCaptureService.scrollCaptureFrameBufferCapacity, 8)
    }

    func testScrollFrameAdmissionDoesNotDropSparseOrDuplicateFrames() {
        let detector = ScrollCaptureFrameChangeDetector()
        let baseline = [UInt8](repeating: 120, count: 144)
        var sparseListMovement = baseline
        sparseListMovement[17] = 255

        XCTAssertTrue(detector.shouldEnqueue(signature: baseline))
        XCTAssertTrue(detector.shouldEnqueue(signature: baseline))
        XCTAssertTrue(detector.shouldEnqueue(signature: sparseListMovement))
    }

    func testScrollFrameChangeDetectorKeepsContinuousViewportMovement() {
        let detector = ScrollCaptureFrameChangeDetector()
        let baseline = [UInt8](repeating: 30, count: 144)
        var scrolled = baseline
        for index in stride(from: 0, to: scrolled.count, by: 8) {
            scrolled[index] = 220
        }

        XCTAssertTrue(detector.shouldEnqueue(signature: baseline))
        XCTAssertTrue(detector.shouldEnqueue(signature: scrolled))
        XCTAssertTrue(detector.shouldEnqueue(signature: scrolled))

        detector.reset()
        XCTAssertTrue(detector.shouldEnqueue(signature: scrolled))
    }

    func testScrollFrameBufferKeepsTheOldestRetainedFrameForStitchContinuity() async throws {
        let buffer = ScrollCaptureFrameBuffer(capacity: 3)
        let first = NSImage(size: NSSize(width: 1, height: 1))
        let second = NSImage(size: NSSize(width: 2, height: 2))
        let third = NSImage(size: NSSize(width: 3, height: 3))
        let fourth = NSImage(size: NSSize(width: 4, height: 4))

        buffer.enqueue(first)
        buffer.enqueue(second)
        buffer.enqueue(third)
        buffer.enqueue(fourth)

        let delivered = try await buffer.nextImage()
        XCTAssertTrue(delivered === second)
    }

    func testScrollFrameBufferDeliversRetainedFramesInCaptureOrder() async throws {
        let buffer = ScrollCaptureFrameBuffer(capacity: 3)
        let first = NSImage(size: NSSize(width: 1, height: 1))
        let second = NSImage(size: NSSize(width: 2, height: 2))
        let third = NSImage(size: NSSize(width: 3, height: 3))

        buffer.enqueue(first)
        buffer.enqueue(second)
        buffer.enqueue(third)

        let deliveredFirst = try await buffer.nextImage(maximumWait: 0.01)
        let deliveredSecond = try await buffer.nextImage(maximumWait: 0.01)
        let deliveredThird = try await buffer.nextImage(maximumWait: 0.01)
        XCTAssertTrue(deliveredFirst === first)
        XCTAssertTrue(deliveredSecond === second)
        XCTAssertTrue(deliveredThird === third)
    }

    func testScrollFrameBufferCanDiscardFramesCapturedBeforeAStep() async throws {
        let buffer = ScrollCaptureFrameBuffer(capacity: 3)
        let stale = NSImage(size: NSSize(width: 1, height: 1))
        let fresh = NSImage(size: NSSize(width: 2, height: 2))
        buffer.enqueue(stale)

        buffer.discardBufferedImages()
        buffer.enqueue(fresh)

        let delivered = try await buffer.nextImage()
        XCTAssertTrue(delivered === fresh)
    }

    func testScrollFrameBufferReusesLatestFrameWhenScreenStopsProducingFrames() async throws {
        let buffer = ScrollCaptureFrameBuffer(capacity: 3)
        let latest = NSImage(size: NSSize(width: 2, height: 2))
        buffer.enqueue(latest)
        _ = try await buffer.nextImage()

        let startedAt = ContinuousClock.now
        let delivered = try await buffer.nextImage(maximumWait: 0.02)

        XCTAssertTrue(delivered === latest)
        XCTAssertLessThan(startedAt.duration(to: .now), .milliseconds(200))
    }

    func testScrollFrameBufferKeepsAcceptingNewerFramesWhileQueueIsFull() async throws {
        let buffer = ScrollCaptureFrameBuffer(capacity: 2)
        XCTAssertTrue(buffer.canAcceptImage)

        buffer.enqueue(NSImage(size: NSSize(width: 1, height: 1)))
        buffer.enqueue(NSImage(size: NSSize(width: 2, height: 2)))
        XCTAssertTrue(buffer.canAcceptImage)

        _ = try await buffer.nextImage()
        XCTAssertTrue(buffer.canAcceptImage)
    }

    @MainActor
    func testSourceRectConvertsAppKitBottomOriginToScreenCaptureTopOrigin() {
        let sourceRect = ScreenCaptureService.sourceRect(
            for: NSRect(x: 100, y: 150, width: 300, height: 200),
            in: NSRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(sourceRect, CGRect(x: 100, y: 550, width: 300, height: 200))
    }

    @MainActor
    func testSourceRectIsRelativeToASecondaryScreenFrame() {
        let sourceRect = ScreenCaptureService.sourceRect(
            for: NSRect(x: -1_800, y: 100, width: 320, height: 200),
            in: NSRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        )

        XCTAssertEqual(sourceRect, CGRect(x: 120, y: 780, width: 320, height: 200))
    }

    @MainActor
    func testRegionCaptureMatchesTheSameAppKitScreenAreaInDesktopCapture() async throws {
        guard NSScreen.screens.count == 1, let screen = NSScreen.main else {
            throw XCTSkip("Coordinate regression test requires one display")
        }
        let selection = NSRect(
            x: screen.frame.minX + 80,
            y: screen.frame.maxY - 360,
            width: min(320, screen.frame.width - 160),
            height: 180
        )
        guard selection.width > 0 else {
            throw XCTSkip("Display is too narrow for the coordinate regression test")
        }

        let service = ScreenCaptureService()
        let desktop = try await service.captureDesktopImage()
        let region = try await service.captureImage(in: selection)
        let desktopSelection = NSRect(
            x: selection.minX - screen.frame.minX,
            y: selection.minY - screen.frame.minY,
            width: selection.width,
            height: selection.height
        )
        let expected = try XCTUnwrap(CaptureCoordinator.crop(image: desktop, rect: desktopSelection))

        XCTAssertLessThan(try meanAbsoluteLuminanceDistance(expected, region), 0.03)
    }

    @MainActor
    func testConformsToScrollRegionCapturingWithoutAdapter() {
        let service: any ScrollRegionCapturing = ScreenCaptureService()
        XCTAssertTrue(service is ScreenCaptureService)
    }

    @MainActor
    func testStreamingScrollCapturerPrimesAndReturnsNextCanonicalFrame() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No main screen") }
        let selection = NSRect(
            x: screen.frame.minX + 120,
            y: screen.frame.minY + 120,
            width: min(320, screen.frame.width - 240),
            height: min(200, screen.frame.height - 240)
        )
        guard selection.width > 0, selection.height > 0 else {
            throw XCTSkip("Display is too small")
        }
        let capturer = StreamingScrollRegionCapturer(service: ScreenCaptureService())

        try await capturer.primeCapture(in: selection)
        let frame = try await capturer.captureImage(in: selection)

        XCTAssertEqual(frame.size.width, selection.width, accuracy: 0.001)
        XCTAssertEqual(frame.size.height, selection.height, accuracy: 0.001)
        let pixels = try XCTUnwrap(frame.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(pixels.width, Int(ceil(selection.width * screen.backingScaleFactor)))
        XCTAssertEqual(pixels.height, Int(ceil(selection.height * screen.backingScaleFactor)))
    }

    @MainActor
    func testScreenshotConfigurationUsesNativeBgraOutput() {
        let configuration = ScreenCaptureService.makeScreenshotConfiguration(width: 320, height: 200)

        XCTAssertEqual(configuration.width, 320)
        XCTAssertEqual(configuration.height, 200)
        XCTAssertEqual(configuration.pixelFormat, kCVPixelFormatType_32BGRA)
        XCTAssertFalse(configuration.showsCursor)
        let colorSpaceName = configuration.colorSpaceName as String?
        XCTAssertTrue(colorSpaceName == nil || colorSpaceName?.isEmpty == true)
        XCTAssertFalse(configuration.scalesToFit)
        if #available(macOS 15.0, *) {
            XCTAssertEqual(configuration.captureDynamicRange, SCCaptureDynamicRange.SDR)
        }
    }

    @MainActor
    func testNativeScreenshotTaggedWithDisplayColorSpacePreservesSolidWindowByteValues() async throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("No screen available")
        }
        let windowFrame = NSRect(
            x: screen.frame.minX + 120,
            y: screen.frame.minY + 120,
            width: 180,
            height: 180
        )
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: CGFloat(26) / 255, alpha: 1)
        window.level = .screenSaver
        window.orderFrontRegardless()
        window.display()
        defer {
            window.orderOut(nil)
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        let shareableContent = try await SCShareableContent.current
        guard
            let displayIDValue = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let display = shareableContent.displays.first(where: { $0.displayID == CGDirectDisplayID(displayIDValue.uint32Value) })
        else {
            throw XCTSkip("Unable to match screen to ScreenCaptureKit display")
        }

        let scale = screen.backingScaleFactor
        let configuration = ScreenCaptureService.makeScreenshotConfiguration(
            width: Int(ceil(display.frame.width * scale)),
            height: Int(ceil(display.frame.height * scale))
        )
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let taggedImage = ScreenCaptureService.retagScreenshotImage(
            cgImage,
            colorSpace: CGDisplayCopyColorSpace(CGDirectDisplayID(displayIDValue.uint32Value))
        )
        let samplePoint = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
        let pixelX = Int((samplePoint.x - display.frame.minX) * scale)
        let pixelY = Int((display.frame.maxY - samplePoint.y) * scale)
        let color = try XCTUnwrap(SelectionToolbarState.sampleColor(atPixelX: pixelX, y: pixelY, in: taggedImage))

        XCTAssertEqual(color.redComponent, 1, accuracy: 2 / 255)
        XCTAssertEqual(color.greenComponent, 0, accuracy: 2 / 255)
        XCTAssertEqual(color.blueComponent, CGFloat(26) / 255, accuracy: 2 / 255)
    }

    @MainActor
    func testDesktopSnapshotIncludesCurrentApplicationWindows() async throws {
        guard NSScreen.screens.count == 1, let screen = NSScreen.main else {
            throw XCTSkip("Current application capture regression test requires one display")
        }
        let windowFrame = NSRect(
            x: screen.frame.minX + 160,
            y: screen.frame.minY + 160,
            width: 160,
            height: 160
        )
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 0.5, alpha: 1)
        window.level = .screenSaver
        window.orderFrontRegardless()
        window.display()
        defer {
            window.orderOut(nil)
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        let snapshot = try await ScreenCaptureService().captureDesktopImage()
        let cgImage = try XCTUnwrap(
            snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let scale = screen.backingScaleFactor
        let samplePoint = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
        let color = try XCTUnwrap(
            SelectionToolbarState.sampleColor(
                atPixelX: Int((samplePoint.x - screen.frame.minX) * scale),
                y: Int((screen.frame.maxY - samplePoint.y) * scale),
                in: cgImage
            )
        )

        XCTAssertEqual(color.redComponent, 1, accuracy: 2 / 255)
        XCTAssertEqual(color.greenComponent, 0, accuracy: 2 / 255)
        XCTAssertEqual(color.blueComponent, 0.5, accuracy: 2 / 255)
    }

    @MainActor
    func testDisplayContentFilterExplicitlyIncludesMenuBarWhenAvailable() async throws {
        guard #available(macOS 14.2, *) else {
            throw XCTSkip("SCContentFilter.includeMenuBar is available on macOS 14.2 and newer")
        }
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("No screen available")
        }

        let shareableContent = try await SCShareableContent.current
        guard
            let displayIDValue = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let display = shareableContent.displays.first(where: { $0.displayID == CGDirectDisplayID(displayIDValue.uint32Value) })
        else {
            throw XCTSkip("Unable to match screen to ScreenCaptureKit display")
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        filter.includeMenuBar = false

        ScreenCaptureService.includeSystemChrome(in: filter)

        XCTAssertTrue(filter.includeMenuBar)
    }

}

private func meanAbsoluteLuminanceDistance(_ left: NSImage, _ right: NSImage) throws -> Double {
    let leftImage = try XCTUnwrap(left.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let rightImage = try XCTUnwrap(right.cgImage(forProposedRect: nil, context: nil, hints: nil))
    XCTAssertEqual(leftImage.width, rightImage.width)
    XCTAssertEqual(leftImage.height, rightImage.height)
    guard leftImage.width == rightImage.width, leftImage.height == rightImage.height else { return 1 }

    var difference = 0.0
    var samples = 0
    let step = max(1, min(leftImage.width, leftImage.height) / 64)
    for y in stride(from: 0, to: leftImage.height, by: step) {
        for x in stride(from: 0, to: leftImage.width, by: step) {
            let leftColor = try XCTUnwrap(SelectionToolbarState.sampleColor(atPixelX: x, y: y, in: leftImage))
            let rightColor = try XCTUnwrap(SelectionToolbarState.sampleColor(atPixelX: x, y: y, in: rightImage))
            let leftLuminance = 0.299 * leftColor.redComponent
                + 0.587 * leftColor.greenComponent
                + 0.114 * leftColor.blueComponent
            let rightLuminance = 0.299 * rightColor.redComponent
                + 0.587 * rightColor.greenComponent
                + 0.114 * rightColor.blueComponent
            difference += abs(leftLuminance - rightLuminance)
            samples += 1
        }
    }
    return samples > 0 ? difference / Double(samples) : 1
}
