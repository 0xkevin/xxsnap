import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import ScreenCaptureKit

@MainActor
final class StreamingScrollRegionCapturer: ScrollRegionCapturing, ScrollRegionCapturePriming, ScrollRegionCaptureBuffering {
    private static let nextFrameMaximumWait: TimeInterval = 0.35

    private let service: ScreenCaptureService
    private var frameStream: ScrollCaptureFrameStream?

    init(service: ScreenCaptureService) {
        self.service = service
    }

    func primeCapture(in selectionRect: NSRect) async throws {
        _ = try await captureImage(in: selectionRect)
    }

    func captureImage(in selectionRect: NSRect) async throws -> NSImage {
        let isStartingStream = frameStream == nil
        if frameStream == nil {
            frameStream = try await service.startScrollFrameStream(in: selectionRect)
        }
        guard let frameStream else { throw ScreenCaptureServiceError.streamStopped }
        return try await frameStream.nextImage(
            maximumWait: isStartingStream ? nil : Self.nextFrameMaximumWait
        )
    }

    func discardBufferedFrames() {
        frameStream?.discardBufferedImages()
    }

    deinit {
        frameStream?.stop()
    }
}

final class ScrollCaptureFrameStream: @unchecked Sendable {
    private let stream: SCStream
    private let receiver: ScrollCaptureFrameReceiver

    fileprivate init(stream: SCStream, receiver: ScrollCaptureFrameReceiver) {
        self.stream = stream
        self.receiver = receiver
    }

    func nextImage(maximumWait: TimeInterval? = nil) async throws -> NSImage {
        NSLog("xxsnap scroll-capture stream awaiting next frame")
        return try await receiver.nextImage(maximumWait: maximumWait)
    }

    func discardBufferedImages() {
        receiver.discardBufferedImages()
    }

    func stop() {
        receiver.stop()
        let stream = self.stream
        Task { try? await stream.stopCapture() }
    }

}

final class ScrollCaptureFrameChangeDetector: @unchecked Sendable {
    func shouldEnqueue(signature: [UInt8]) -> Bool {
        !signature.isEmpty
    }

    func shouldEnqueue(pixelBuffer: CVPixelBuffer) -> Bool {
        true
    }

    func reset() {}
}

final class ScrollCaptureFrameBuffer: @unchecked Sendable {
    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<NSImage, Error>
        let timeout: DispatchWorkItem?
    }

    private static let timeoutQueue = DispatchQueue(
        label: "com.xxsnap.scroll-capture-frame-timeout",
        qos: .userInitiated
    )

    private let capacity: Int
    private let lock = NSLock()
    private var images: [NSImage] = []
    private var latestImage: NSImage?
    private var waiter: Waiter?
    private var nextWaiterID: UInt64 = 0
    private var stopped = false

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var canAcceptImage: Bool {
        lock.lock()
        let result = !stopped
        lock.unlock()
        return result
    }

    func enqueue(_ image: NSImage) {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        latestImage = image
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.timeout?.cancel()
            waiter.continuation.resume(returning: image)
            return
        }
        images.append(image)
        if images.count > capacity {
            images.removeFirst(images.count - capacity)
        }
        lock.unlock()
    }

    func nextImage(maximumWait: TimeInterval? = nil) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if stopped {
                lock.unlock()
                continuation.resume(throwing: ScreenCaptureServiceError.streamStopped)
                return
            }
            if !images.isEmpty {
                // Stitching needs a chain of overlapping frames. When matching is
                // slower than the capture stream, preserve capture order instead of
                // jumping straight to the newest frame and losing the overlap.
                let image = images.removeFirst()
                lock.unlock()
                continuation.resume(returning: image)
                return
            }
            let waiterID = nextWaiterID
            nextWaiterID &+= 1
            let timeout = maximumWait.map { maximumWait in
                DispatchWorkItem { [weak self] in
                    self?.resumeTimedOutWaiter(id: waiterID)
                }
            }
            waiter = Waiter(id: waiterID, continuation: continuation, timeout: timeout)
            lock.unlock()
            if let timeout, let maximumWait {
                Self.timeoutQueue.asyncAfter(
                    deadline: .now() + max(0, maximumWait),
                    execute: timeout
                )
            }
        }
    }

    func discardBufferedImages() {
        lock.lock()
        images.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func stop() {
        lock.lock()
        stopped = true
        images.removeAll(keepingCapacity: false)
        latestImage = nil
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        waiter?.timeout?.cancel()
        waiter?.continuation.resume(throwing: ScreenCaptureServiceError.streamStopped)
    }

    private func resumeTimedOutWaiter(id: UInt64) {
        lock.lock()
        guard let waiter, waiter.id == id else {
            lock.unlock()
            return
        }
        self.waiter = nil
        let latestImage = self.latestImage
        lock.unlock()
        if let latestImage {
            waiter.continuation.resume(returning: latestImage)
        } else {
            waiter.continuation.resume(throwing: ScreenCaptureServiceError.frameTimedOut)
        }
    }
}

private final class ScrollCaptureFrameReceiver: NSObject, SCStreamOutput, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let pointSize: NSSize
    private let colorSpace: CGColorSpace
    private let frameBuffer = ScrollCaptureFrameBuffer(
        capacity: ScreenCaptureService.scrollCaptureFrameBufferCapacity
    )
    private let changeDetector = ScrollCaptureFrameChangeDetector()

    init(pointSize: NSSize, colorSpace: CGColorSpace) {
        self.pointSize = pointSize
        self.colorSpace = colorSpace
    }

    func nextImage(maximumWait: TimeInterval? = nil) async throws -> NSImage {
        try await frameBuffer.nextImage(maximumWait: maximumWait)
    }

    func discardBufferedImages() {
        frameBuffer.discardBufferedImages()
        changeDetector.reset()
    }

    func stop() {
        frameBuffer.stop()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              sampleBuffer.isValid,
              frameBuffer.canAcceptImage,
              let pixelBuffer = sampleBuffer.imageBuffer,
              changeDetector.shouldEnqueue(pixelBuffer: pixelBuffer)
        else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(
            ciImage,
            from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)),
            format: .BGRA8,
            colorSpace: colorSpace
        ) else { return }
        let image = NSImage(cgImage: cgImage, size: pointSize)

        frameBuffer.enqueue(image)
    }
}

@MainActor
final class ScreenCaptureService: ScrollRegionCapturing {
    nonisolated static let scrollCaptureFrameBufferCapacity = 8

    private var cachedShareableContent: SCShareableContent?

    func prepareShareableContent() async {
        guard CGPreflightScreenCaptureAccess() else { return }
        _ = try? await shareableContent()
    }

    static func sourceRect(for selectionRect: NSRect, in screenFrame: NSRect) -> CGRect {
        CGRect(
            x: selectionRect.minX - screenFrame.minX,
            y: screenFrame.maxY - selectionRect.maxY,
            width: selectionRect.width,
            height: selectionRect.height
        )
    }

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

    static func makeScrollStreamConfiguration(width: Int, height: Int) -> SCStreamConfiguration {
        let configuration = makeScreenshotConfiguration(width: width, height: height)
        configuration.scalesToFit = true
        configuration.queueDepth = 5
        // PixPin samples on a 100 ms timer. Feeding this serial stitcher at 30 fps
        // creates backlog and eventually evicts the intermediate overlap frames.
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
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

        let shareableContent = try await shareableContent()

        let targets = displayTargets(from: shareableContent.displays)
        if targets.count == 1, let target = targets.first {
            let filter = SCContentFilter(
                display: target.display,
                excludingApplications: [],
                exceptingWindows: []
            )
            Self.includeSystemChrome(in: filter)

            let configuration = Self.makeScreenshotConfiguration(
                width: Int(ceil(target.screenFrame.width * target.scale)),
                height: Int(ceil(target.screenFrame.height * target.scale))
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
                excludingApplications: [],
                exceptingWindows: []
            )
            Self.includeSystemChrome(in: filter)

            let configuration = Self.makeScreenshotConfiguration(
                width: Int(ceil(target.screenFrame.width * target.scale)),
                height: Int(ceil(target.screenFrame.height * target.scale))
            )

            let capturedImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let cgImage = Self.retagScreenshotImage(capturedImage, colorSpace: target.colorSpace)

            let image = NSImage(
                cgImage: cgImage,
                size: target.screenFrame.size
            )
            let destination = NSRect(
                x: target.screenFrame.minX - desktopFrame.minX,
                y: target.screenFrame.minY - desktopFrame.minY,
                width: target.screenFrame.width,
                height: target.screenFrame.height
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

        let shareableContent = try await shareableContent()
        guard let target = targetDisplay(for: normalizedSelection, displays: shareableContent.displays) else {
            throw ScreenCaptureServiceError.displayNotFound
        }

        let clippedSelection = normalizedSelection.intersection(target.screenFrame)
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

        let relativeRect = Self.sourceRect(for: clippedSelection, in: target.screenFrame)

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

    func startScrollFrameStream(in selectionRect: NSRect) async throws -> ScrollCaptureFrameStream {
        let normalizedSelection = selectionRect.standardized
        guard !normalizedSelection.isEmpty else { throw ScreenCaptureServiceError.emptySelection }
        let shareableContent = try await shareableContent()
        guard let target = targetDisplay(for: normalizedSelection, displays: shareableContent.displays) else {
            throw ScreenCaptureServiceError.displayNotFound
        }
        let clippedSelection = normalizedSelection.intersection(target.screenFrame)
        guard !clippedSelection.isEmpty else { throw ScreenCaptureServiceError.selectionOutsideDisplay }

        let currentProcessID = pid_t(NSRunningApplication.current.processIdentifier)
        let excludedApplications = shareableContent.applications.filter { $0.processID == currentProcessID }
        let filter = SCContentFilter(
            display: target.display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        Self.includeSystemChrome(in: filter)
        let relativeRect = Self.sourceRect(for: clippedSelection, in: target.screenFrame)
        let configuration = Self.makeScrollStreamConfiguration(
            width: Int(ceil(relativeRect.width * target.scale)),
            height: Int(ceil(relativeRect.height * target.scale))
        )
        configuration.sourceRect = relativeRect

        let receiver = ScrollCaptureFrameReceiver(
            pointSize: clippedSelection.size,
            colorSpace: target.colorSpace
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(
            receiver,
            type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "com.xxsnap.scroll-capture.frames", qos: .userInteractive)
        )
        try await stream.startCapture()
        return ScrollCaptureFrameStream(stream: stream, receiver: receiver)
    }
}

private extension ScreenCaptureService {
    func shareableContent() async throws -> SCShareableContent {
        let displayIDs = activeDisplayIDs()
        if let cachedShareableContent,
           !displayIDs.isEmpty,
           Set(cachedShareableContent.displays.map(\.displayID)) == displayIDs {
            return cachedShareableContent
        }

        let content = try await SCShareableContent.current
        cachedShareableContent = content
        return content
    }

    func activeDisplayIDs() -> Set<CGDirectDisplayID> {
        Set(NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { CGDirectDisplayID($0.uint32Value) }
        })
    }

    struct DisplayTarget {
        let display: SCDisplay
        let screenFrame: NSRect
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
            return DisplayTarget(
                display: display,
                screenFrame: screen.frame,
                scale: screen.backingScaleFactor,
                colorSpace: colorSpace
            )
        }
    }

    func targetDisplay(for selectionRect: NSRect, displays: [SCDisplay]) -> DisplayTarget? {
        let rankedDisplays = displayTargets(from: displays).compactMap { target -> (DisplayTarget, CGFloat)? in
            let intersection = selectionRect.intersection(target.screenFrame)
            guard !intersection.isEmpty else {
                return nil
            }

            let area = intersection.width * intersection.height
            return (target, area)
        }

        return rankedDisplays.max(by: { $0.1 < $1.1 })?.0
    }
}

enum ScreenCaptureServiceError: LocalizedError {
    case emptySelection
    case displayNotFound
    case selectionOutsideDisplay
    case streamStopped
    case frameTimedOut

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "The selected region was empty."
        case .displayNotFound:
            return "Unable to match the selected region to a display."
        case .selectionOutsideDisplay:
            return "The selected region fell outside the target display."
        case .streamStopped:
            return "The scrolling capture stream stopped."
        case .frameTimedOut:
            return "The scrolling capture stream did not produce a frame in time."
        }
    }
}
