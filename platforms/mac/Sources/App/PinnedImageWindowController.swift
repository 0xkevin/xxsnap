import AppKit

struct PinnedImageWindowGeometry {
    static let maxScreenFraction: CGFloat = 0.8
    static let minLongSide: CGFloat = 96

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
}

@MainActor
protocol PinnedImageWindowPresenting: AnyObject {
    var image: NSImage { get }
    func show()
}

@MainActor
final class PinnedImageWindowController: NSWindowController, PinnedImageWindowPresenting {
    let image: NSImage
    var onClose: (() -> Void)?
    private let imageAspectRatio: CGFloat

    init(image: NSImage, visibleFrame: NSRect? = NSScreen.main?.visibleFrame) {
        self.image = image
        self.imageAspectRatio = image.size.width / max(image.size.height, 1)
        let screenFrame = visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let fittedSize = PinnedImageWindowGeometry.fittedImageSize(imageSize: image.size, visibleFrame: screenFrame)
        let origin = NSPoint(
            x: screenFrame.midX - fittedSize.width / 2,
            y: screenFrame.midY - fittedSize.height / 2
        )
        let window = PinnedImageWindow(
            contentRect: NSRect(origin: origin, size: fittedSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = PinnedImageContentView(image: image)
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
        let newSize = PinnedImageWindowGeometry.scaledSize(
            currentSize: window.frame.size,
            aspectRatio: imageAspectRatio,
            scaleFactor: factor,
            visibleFrame: visibleFrame
        )
        guard newSize.width > 0, newSize.height > 0 else {
            return
        }

        let anchor = anchorInScreen ?? NSPoint(x: window.frame.midX, y: window.frame.midY)
        let xRatio = (anchor.x - window.frame.minX) / max(window.frame.width, 1)
        let yRatio = (anchor.y - window.frame.minY) / max(window.frame.height, 1)
        let newOrigin = NSPoint(
            x: anchor.x - newSize.width * xRatio,
            y: anchor.y - newSize.height * yRatio
        )
        window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
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
    private let closeDiameter: CGFloat = 18

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

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        image.draw(in: bounds)
        drawCloseButton()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if closeButtonRect.contains(point) {
            window?.close()
            return
        }
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
        if event.keyCode == 53 {
            window?.close()
            return
        }
        super.keyDown(with: event)
    }

    private var closeButtonRect: NSRect {
        NSRect(x: bounds.maxX - closeDiameter - 7, y: bounds.maxY - closeDiameter - 7, width: closeDiameter, height: closeDiameter)
    }

    private func drawCloseButton() {
        let rect = closeButtonRect
        NSColor.black.withAlphaComponent(0.58).setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.8
        path.move(to: NSPoint(x: rect.minX + 5, y: rect.minY + 5))
        path.line(to: NSPoint(x: rect.maxX - 5, y: rect.maxY - 5))
        path.move(to: NSPoint(x: rect.maxX - 5, y: rect.minY + 5))
        path.line(to: NSPoint(x: rect.minX + 5, y: rect.maxY - 5))
        path.stroke()
    }
}
