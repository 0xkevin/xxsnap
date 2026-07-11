import AppKit
import CoreVideo
import ScreenCaptureKit

@MainActor
final class ScreenCaptureService: ScrollRegionCapturing {
    static func makeScreenshotConfiguration(width: Int, height: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, width)
        configuration.height = max(1, height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = false
        configuration.showsCursor = false
        if #available(macOS 15.0, *) {
            configuration.captureDynamicRange = .SDR
        }
        return configuration
    }

    static func retagScreenshotImage(_ image: CGImage, colorSpace: CGColorSpace) -> CGImage {
        image.copy(colorSpace: colorSpace) ?? image
    }

    static func includeSystemChrome(in filter: SCContentFilter) {
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }
    }

    func captureDesktopImage() async throws -> NSImage {
        let desktopFrame = NSScreen.screens.reduce(into: NSRect.null) { partialResult, screen in
            partialResult = partialResult.union(screen.frame)
        }
        guard !desktopFrame.isNull, !desktopFrame.isEmpty else {
            throw ScreenCaptureServiceError.displayNotFound
        }

        let shareableContent = try await SCShareableContent.current
        let currentProcessID = pid_t(NSRunningApplication.current.processIdentifier)
        let excludedApplications = shareableContent.applications.filter { $0.processID == currentProcessID }

        let targets = displayTargets(from: shareableContent.displays)
        if targets.count == 1, let target = targets.first {
            let filter = SCContentFilter(
                display: target.display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            Self.includeSystemChrome(in: filter)

            let configuration = Self.makeScreenshotConfiguration(
                width: Int(ceil(target.display.frame.width * target.scale)),
                height: Int(ceil(target.display.frame.height * target.scale))
            )

            let capturedImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let cgImage = Self.retagScreenshotImage(capturedImage, colorSpace: target.colorSpace)

            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: target.display.frame.width, height: target.display.frame.height)
            )
        }

        let snapshot = NSImage(size: desktopFrame.size)
        snapshot.lockFocus()
        NSGraphicsContext.current?.shouldAntialias = true
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: desktopFrame.size).fill()

        for target in targets {
            let filter = SCContentFilter(
                display: target.display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            Self.includeSystemChrome(in: filter)

            let configuration = Self.makeScreenshotConfiguration(
                width: Int(ceil(target.display.frame.width * target.scale)),
                height: Int(ceil(target.display.frame.height * target.scale))
            )

            let capturedImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let cgImage = Self.retagScreenshotImage(capturedImage, colorSpace: target.colorSpace)

            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: target.display.frame.width, height: target.display.frame.height)
            )
            let destination = NSRect(
                x: target.display.frame.minX - desktopFrame.minX,
                y: target.display.frame.minY - desktopFrame.minY,
                width: target.display.frame.width,
                height: target.display.frame.height
            )
            image.draw(in: destination, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        }

        snapshot.unlockFocus()
        return snapshot
    }

    func captureImage(in selectionRect: NSRect) async throws -> NSImage {
        let normalizedSelection = selectionRect.standardized
        guard !normalizedSelection.isEmpty else {
            throw ScreenCaptureServiceError.emptySelection
        }

        let shareableContent = try await SCShareableContent.current
        guard let target = targetDisplay(for: normalizedSelection, displays: shareableContent.displays) else {
            throw ScreenCaptureServiceError.displayNotFound
        }

        let clippedSelection = normalizedSelection.intersection(target.display.frame)
        guard !clippedSelection.isEmpty else {
            throw ScreenCaptureServiceError.selectionOutsideDisplay
        }

        let currentProcessID = pid_t(NSRunningApplication.current.processIdentifier)
        let excludedApplications = shareableContent.applications.filter { $0.processID == currentProcessID }
        let filter = SCContentFilter(
            display: target.display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        Self.includeSystemChrome(in: filter)

        let relativeRect = CGRect(
            x: clippedSelection.minX - target.display.frame.minX,
            y: clippedSelection.minY - target.display.frame.minY,
            width: clippedSelection.width,
            height: clippedSelection.height
        )

        let configuration = Self.makeScreenshotConfiguration(
            width: Int(ceil(relativeRect.width * target.scale)),
            height: Int(ceil(relativeRect.height * target.scale))
        )
        configuration.sourceRect = relativeRect

        let capturedImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let cgImage = Self.retagScreenshotImage(capturedImage, colorSpace: target.colorSpace)

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: clippedSelection.width, height: clippedSelection.height)
        )
    }
}

private extension ScreenCaptureService {
    struct DisplayTarget {
        let display: SCDisplay
        let scale: CGFloat
        let colorSpace: CGColorSpace
    }

    func displayTargets(from displays: [SCDisplay]) -> [DisplayTarget] {
        NSScreen.screens.compactMap { screen -> DisplayTarget? in
            guard
                let displayIDValue = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                let display = displays.first(where: { $0.displayID == CGDirectDisplayID(displayIDValue.uint32Value) })
            else {
                return nil
            }

            let colorSpace = CGDisplayCopyColorSpace(CGDirectDisplayID(displayIDValue.uint32Value))
            return DisplayTarget(display: display, scale: screen.backingScaleFactor, colorSpace: colorSpace)
        }
    }

    func targetDisplay(for selectionRect: NSRect, displays: [SCDisplay]) -> DisplayTarget? {
        let rankedDisplays = displayTargets(from: displays).compactMap { target -> (DisplayTarget, CGFloat)? in
            let intersection = selectionRect.intersection(target.display.frame)
            guard !intersection.isEmpty else {
                return nil
            }

            let area = intersection.width * intersection.height
            return (target, area)
        }

        return rankedDisplays.max(by: { $0.1 < $1.1 })?.0
    }
}

private enum ScreenCaptureServiceError: LocalizedError {
    case emptySelection
    case displayNotFound
    case selectionOutsideDisplay

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "The selected region was empty."
        case .displayNotFound:
            return "Unable to match the selected region to a display."
        case .selectionOutsideDisplay:
            return "The selected region fell outside the target display."
        }
    }
}
