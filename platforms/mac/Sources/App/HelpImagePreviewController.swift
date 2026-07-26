import AppKit

@MainActor
final class HelpImagePreviewController: NSWindowController, NSWindowDelegate {
    var onDismiss: (() -> Void)?

    private let image: NSImage
    private let caption: String
    private let imageAccessibilityLabel: String
    private weak var parentWindow: NSWindow?
    private weak var previewImageView: NSImageView?
    private var didNotifyDismiss = false
    private var isDismissing = false

    init(image: NSImage, caption: String, accessibilityLabel: String) {
        self.image = image
        self.caption = caption
        imageAccessibilityLabel = accessibilityLabel
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(over parentWindow: NSWindow) {
        if window == nil {
            window = makeWindow(visibleFrame: parentWindow.screen?.visibleFrame)
        }
        guard let window else { return }

        self.parentWindow = parentWindow
        if !(parentWindow.childWindows ?? []).contains(window) {
            parentWindow.addChildWindow(window, ordered: .above)
        }
        center(window, in: parentWindow.screen?.visibleFrame)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(self)
    }

    func dismiss() {
        guard !isDismissing, let window else { return }
        isDismissing = true
        detachFromParent(window)
        window.close()
        finishDismiss()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1B}" {
            dismiss()
            return
        }
        super.keyDown(with: event)
    }

    var test_imageAccessibilityLabel: String? {
        previewImageView?.accessibilityLabel()
    }

    func test_clickCloseButton() {
        window?.standardWindowButton(.closeButton)?.performClick(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        detachFromParent(closingWindow)
        finishDismiss()
    }

    private func makeWindow(visibleFrame: NSRect?) -> NSWindow {
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable]
        let screenFrame = visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maximumFrameSize = NSSize(
            width: floor(screenFrame.width * 0.9),
            height: floor(screenFrame.height * 0.9)
        )

        let sampleContentRect = NSRect(x: 0, y: 0, width: 100, height: 100)
        let sampleFrameRect = NSWindow.frameRect(
            forContentRect: sampleContentRect,
            styleMask: styleMask
        )
        let decorationWidth = sampleFrameRect.width - sampleContentRect.width
        let decorationHeight = sampleFrameRect.height - sampleContentRect.height
        let maximumContentSize = NSSize(
            width: max(1, maximumFrameSize.width - decorationWidth),
            height: max(1, maximumFrameSize.height - decorationHeight)
        )

        let captionHeight: CGFloat = caption.isEmpty ? 24 : 58
        let imageSize = image.size.width > 0 && image.size.height > 0
            ? image.size
            : NSSize(width: 640, height: 360)
        let scale = min(
            1,
            maximumContentSize.width / imageSize.width,
            max(1, maximumContentSize.height - captionHeight) / imageSize.height
        )
        let scaledImageSize = NSSize(
            width: floor(imageSize.width * scale),
            height: floor(imageSize.height * scale)
        )
        let contentSize = NSSize(
            width: min(maximumContentSize.width, max(320, scaledImageSize.width)),
            height: min(
                maximumContentSize.height,
                max(220, scaledImageSize.height + captionHeight)
            )
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = caption.isEmpty ? "图片预览" : caption
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.animationBehavior = .utilityWindow
        window.maxSize = maximumFrameSize
        window.delegate = self
        window.contentView = makeContentView(
            imageSize: scaledImageSize,
            maximumContentSize: maximumContentSize
        )
        return window
    }

    private func makeContentView(
        imageSize: NSSize,
        maximumContentSize: NSSize
    ) -> NSView {
        let root = NSView()

        let imageView = HelpPreviewImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.onClick = { [weak self] in
            self?.dismiss()
        }
        imageView.setAccessibilityLabel(imageAccessibilityLabel)
        previewImageView = imageView

        let captionLabel = NSTextField(wrappingLabelWithString: caption)
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.alignment = .center
        captionLabel.font = .systemFont(ofSize: 13)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.maximumNumberOfLines = 2
        captionLabel.isHidden = caption.isEmpty

        root.addSubview(imageView)
        root.addSubview(captionLabel)
        let aspectRatio = imageSize.width > 0
            ? imageSize.height / imageSize.width
            : CGFloat(9.0 / 16.0)
        let aspectConstraint = imageView.heightAnchor.constraint(
            equalTo: imageView.widthAnchor,
            multiplier: aspectRatio
        )
        aspectConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(
                greaterThanOrEqualTo: root.leadingAnchor,
                constant: 16
            ),
            imageView.trailingAnchor.constraint(
                lessThanOrEqualTo: root.trailingAnchor,
                constant: -16
            ),
            imageView.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            imageView.widthAnchor.constraint(
                lessThanOrEqualToConstant: max(1, maximumContentSize.width - 32)
            ),
            imageView.heightAnchor.constraint(
                lessThanOrEqualToConstant: max(1, maximumContentSize.height - 74)
            ),
            aspectConstraint,
            captionLabel.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: 20
            ),
            captionLabel.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -20
            ),
            captionLabel.topAnchor.constraint(
                equalTo: imageView.bottomAnchor,
                constant: 10
            ),
            captionLabel.bottomAnchor.constraint(
                equalTo: root.bottomAnchor,
                constant: -14
            )
        ])
        return root
    }

    private func center(_ window: NSWindow, in visibleFrame: NSRect?) {
        let frame = visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        window.setFrameOrigin(
            NSPoint(
                x: frame.midX - window.frame.width / 2,
                y: frame.midY - window.frame.height / 2
            )
        )
    }

    private func detachFromParent(_ window: NSWindow) {
        if (parentWindow?.childWindows ?? []).contains(window) {
            parentWindow?.removeChildWindow(window)
        }
        parentWindow = nil
    }

    private func finishDismiss() {
        guard !didNotifyDismiss else { return }
        didNotifyDismiss = true
        isDismissing = false
        onDismiss?()
    }
}

@MainActor
private final class HelpPreviewImageView: NSImageView {
    var onClick: (() -> Void)?

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onClick?()
    }
}
