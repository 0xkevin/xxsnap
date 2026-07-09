import AppKit

struct PinnedImageWindowGeometry {
    static let maxScreenFraction: CGFloat = 0.8
    static let minLongSide: CGFloat = 96
    static let shadowOutset: CGFloat = 18

    static func fittedImageSize(imageSize: NSSize, visibleFrame: NSRect) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: minLongSide, height: minLongSide)
        }

        let maxSize = NSSize(
            width: max(minLongSide, visibleFrame.width * maxScreenFraction),
            height: max(minLongSide, visibleFrame.height * maxScreenFraction)
        )
        let fitFactor = min(1, maxSize.width / imageSize.width, maxSize.height / imageSize.height)
        let minFactor = minLongSide / max(imageSize.width, imageSize.height)
        let factor = max(fitFactor, minFactor)
        return NSSize(width: imageSize.width * factor, height: imageSize.height * factor)
    }

    static func scaledSize(
        currentSize: NSSize,
        aspectRatio: CGFloat,
        scaleFactor: CGFloat,
        visibleFrame: NSRect
    ) -> NSSize {
        guard currentSize.width > 0, currentSize.height > 0, aspectRatio > 0 else {
            return currentSize
        }

        let maxSize = NSSize(
            width: max(minLongSide, visibleFrame.width * maxScreenFraction),
            height: max(minLongSide, visibleFrame.height * maxScreenFraction)
        )
        let proposedWidth = currentSize.width * scaleFactor
        let proposedHeight = proposedWidth / aspectRatio
        let maxFactor = min(maxSize.width / currentSize.width, maxSize.height / currentSize.height)
        let minFactor = minLongSide / max(currentSize.width, currentSize.height)
        let clampedFactor = min(max(scaleFactor, minFactor), maxFactor)

        if proposedHeight <= maxSize.height, proposedWidth <= maxSize.width,
           max(proposedWidth, proposedHeight) >= minLongSide {
            return NSSize(width: proposedWidth, height: proposedHeight)
        }

        return NSSize(width: currentSize.width * clampedFactor, height: currentSize.height * clampedFactor)
    }

    static func movedOrigin(globalMouse: NSPoint, dragOffset: NSPoint) -> NSPoint {
        NSPoint(x: globalMouse.x - dragOffset.x, y: globalMouse.y - dragOffset.y)
    }

    static func windowFrame(forImageFrame imageFrame: NSRect) -> NSRect {
        imageFrame.insetBy(dx: -shadowOutset, dy: -shadowOutset)
    }

    static func imageFrame(inWindowFrame windowFrame: NSRect) -> NSRect {
        windowFrame.insetBy(dx: shadowOutset, dy: shadowOutset)
    }
}

@MainActor
protocol PinnedImageWindowPresenting: AnyObject {
    var image: NSImage { get }
    var screenRect: NSRect { get }
    func show()
}

@MainActor
final class PinnedImageWindowController: NSWindowController, PinnedImageWindowPresenting {
    let image: NSImage
    let screenRect: NSRect
    var onClose: (() -> Void)?
    private let imageAspectRatio: CGFloat

    init(image: NSImage, screenRect: NSRect? = nil, visibleFrame: NSRect? = NSScreen.main?.visibleFrame) {
        self.image = image
        let requestedRect = screenRect?.standardized ?? NSRect(origin: .zero, size: image.size)
        self.screenRect = requestedRect.isEmpty ? NSRect(origin: .zero, size: image.size) : requestedRect
        self.imageAspectRatio = image.size.width / max(image.size.height, 1)
        let screenFrame = visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let initialImageFrame = self.screenRect.isEmpty
            ? NSRect(
                x: screenFrame.midX - image.size.width / 2,
                y: screenFrame.midY - image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            )
            : self.screenRect
        let initialFrame = PinnedImageWindowGeometry.windowFrame(forImageFrame: initialImageFrame)
        let window = PinnedImageWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = PinnedImageContentView(image: image)
        view.frame = NSRect(origin: .zero, size: initialFrame.size)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        super.init(window: window)
        window.delegate = self
        view.controller = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func scale(by factor: CGFloat, around anchorInScreen: NSPoint? = nil) {
        guard let window else {
            return
        }
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let currentImageFrame = PinnedImageWindowGeometry.imageFrame(inWindowFrame: window.frame)
        let newImageSize = PinnedImageWindowGeometry.scaledSize(
            currentSize: currentImageFrame.size,
            aspectRatio: imageAspectRatio,
            scaleFactor: factor,
            visibleFrame: visibleFrame
        )
        guard newImageSize.width > 0, newImageSize.height > 0 else {
            return
        }

        let anchor = anchorInScreen ?? NSPoint(x: currentImageFrame.midX, y: currentImageFrame.midY)
        let xRatio = (anchor.x - currentImageFrame.minX) / max(currentImageFrame.width, 1)
        let yRatio = (anchor.y - currentImageFrame.minY) / max(currentImageFrame.height, 1)
        let newImageOrigin = NSPoint(
            x: anchor.x - newImageSize.width * xRatio,
            y: anchor.y - newImageSize.height * yRatio
        )
        let newImageFrame = NSRect(origin: newImageOrigin, size: newImageSize)
        window.setFrame(PinnedImageWindowGeometry.windowFrame(forImageFrame: newImageFrame), display: true)
    }
}

extension PinnedImageWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

private final class PinnedImageWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }
}

private final class PinnedImageContentView: NSView {
    let image: NSImage
    weak var controller: PinnedImageWindowController?
    private var dragOffset: NSPoint?

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        let imageRect = bounds.insetBy(
            dx: PinnedImageWindowGeometry.shadowOutset,
            dy: PinnedImageWindowGeometry.shadowOutset
        )
        drawBlueOuterShadow(around: imageRect)
        image.draw(in: imageRect)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if window != nil {
            dragOffset = event.locationInWindow
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOffset, let window else {
            return
        }
        let origin = PinnedImageWindowGeometry.movedOrigin(
            globalMouse: NSEvent.mouseLocation,
            dragOffset: dragOffset
        )
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        dragOffset = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.deltaY != 0 else {
            return
        }
        let factor = event.deltaY > 0 ? 1.08 : 0.92
        controller?.scale(by: factor, around: NSEvent.mouseLocation)
    }

    override func magnify(with event: NSEvent) {
        controller?.scale(by: 1 + event.magnification, around: NSEvent.mouseLocation)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.keyCode == 51 || event.keyCode == 117 {
            window?.close()
            return
        }
        super.keyDown(with: event)
    }

    private func drawBlueOuterShadow(around imageRect: NSRect) {
        drawShadowLayer(
            around: imageRect,
            color: NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.82, alpha: 0.42),
            blur: 16,
            offset: .zero
        )
        drawShadowLayer(
            around: imageRect,
            color: NSColor(calibratedRed: 0.28, green: 0.64, blue: 1, alpha: 0.34),
            blur: 7,
            offset: NSSize(width: 0, height: -1)
        )
        NSColor(calibratedRed: 0.36, green: 0.65, blue: 0.92, alpha: 0.28).setStroke()
        let edge = NSBezierPath(rect: imageRect.insetBy(dx: 0.5, dy: 0.5))
        edge.lineWidth = 1
        edge.stroke()
    }

    private func drawShadowLayer(around imageRect: NSRect, color: NSColor, blur: CGFloat, offset: NSSize) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = offset
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(rect: imageRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

#if DEBUG
extension PinnedImageWindowController {
    var test_drawsBlueShadow: Bool {
        true
    }

    var test_drawsCloseButton: Bool {
        false
    }

    func test_keyDown(keyCode: UInt16) {
        guard let contentView = window?.contentView else {
            return
        }
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
        if let event {
            contentView.keyDown(with: event)
        }
    }

    func test_renderedContentImage() -> NSImage {
        let contentBounds = window?.contentView?.bounds ?? NSRect(origin: .zero, size: image.size)
        let rendered = NSImage(size: contentBounds.size)
        rendered.lockFocus()
        window?.contentView?.draw(contentBounds)
        rendered.unlockFocus()
        return rendered
    }
}
#endif
