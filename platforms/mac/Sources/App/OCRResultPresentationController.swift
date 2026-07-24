import AppKit

@MainActor
final class OCRResultPresentationController {
    fileprivate enum Result: Equatable {
        case success
        case failure
    }

    private static let panelSize = NSSize(width: 176, height: 124)
    private static let displayDuration: TimeInterval = 3
    private static let fadeDuration: TimeInterval = 0.35
    private static let panelIdentifier = NSUserInterfaceItemIdentifier("xxsnap.ocr-copy-success")

    private var panel: NSPanel?
    private var fadeWorkItem: DispatchWorkItem?
    private let successSoundPlayer: (() -> Void)?
    private let successSound: NSSound?

    init(successSoundPlayer: (() -> Void)? = nil) {
        self.successSoundPlayer = successSoundPlayer
        if successSoundPlayer == nil,
           let url = Bundle.main.url(forResource: "notification", withExtension: "mp3") {
            successSound = NSSound(contentsOf: url, byReference: false)
        } else {
            successSound = nil
        }
    }

    func showSuccess(
        near screenRect: NSRect,
        playsSound: Bool = true,
        showsNotification: Bool = true
    ) {
        if playsSound {
            playSuccessSound()
        }
        if showsNotification {
            show(.success, near: screenRect)
        }
    }

    func showFailure(near screenRect: NSRect) {
        show(.failure, near: screenRect)
    }

    private func show(_ result: Result, near screenRect: NSRect) {
        fadeWorkItem?.cancel()
        panel?.orderOut(nil)

        let visibleFrame = targetScreen(for: screenRect)?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? SelectionOverlayWindow.visibleDesktopFrame()
        let frame = Self.panelFrame(in: visibleFrame)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = Self.panelIdentifier
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = OCRResultView(result: result)
        panel.setFrame(frame, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel
        let fadeWorkItem = DispatchWorkItem { [weak self, weak panel] in
            guard let panel else {
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self, weak panel] in
                panel?.orderOut(nil)
                if self?.panel === panel {
                    self?.panel = nil
                }
            }
        }
        self.fadeWorkItem = fadeWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.displayDuration - Self.fadeDuration,
            execute: fadeWorkItem
        )
    }

    private func playSuccessSound() {
        if let successSoundPlayer {
            successSoundPlayer()
            return
        }
        successSound?.stop()
        successSound?.play()
    }

    private func targetScreen(for screenRect: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(screenRect).area < rhs.frame.intersection(screenRect).area
        }
    }

    private static func panelFrame(in visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.minY + visibleFrame.height * 0.28 - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

private extension NSRect {
    var area: CGFloat {
        isNull || isEmpty ? 0 : width * height
    }
}

@MainActor
private final class OCRResultView: NSView {
    init(result: OCRResultPresentationController.Result) {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 176, height: 124)))
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 0.96).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.32).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 10
        layer?.shadowOffset = NSSize(width: 0, height: -2)

        let iconView = NSImageView(image: Self.icon(for: result))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),
        ])

        let title = NSTextField(labelWithString: result == .success ? "识别成功" : "识别失败")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 7
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(title)

        if result == .success {
            let detail = NSTextField(labelWithString: "已复制到剪切板")
            detail.font = .systemFont(ofSize: 13)
            detail.textColor = .secondaryLabelColor
            detail.alignment = .center
            contentStack.addArrangedSubview(detail)
            setAccessibilityLabel("识别成功\n已复制到剪切板")
        } else {
            setAccessibilityLabel("识别失败")
        }

        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private static func icon(for result: OCRResultPresentationController.Result) -> NSImage {
        let resourceName = result == .success ? "correct" : "failed"
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(size: NSSize(width: 30, height: 30))
    }
}
