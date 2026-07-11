import AppKit
import CoreGraphics
import CoreVideo
import ScreenCaptureKit
import XCTest
@testable import xxsnap

final class ScreenCaptureServiceTests: XCTestCase {
    @MainActor
    func testConformsToScrollRegionCapturingWithoutAdapter() {
        let service: any ScrollRegionCapturing = ScreenCaptureService()
        XCTAssertTrue(service is ScreenCaptureService)
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
