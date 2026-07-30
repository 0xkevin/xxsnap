import AppKit

@MainActor
final class OCRResultPresentationController {
    fileprivate enum Result: Equatable {
        case success
        case failure
    }

    fileprivate struct Copy {
        let title: String
        let detail: String?
        let accessibilityLabel: String
    }

    private static let chinesePanelSize = NSSize(width: 176, height: 124)
    private static let englishPanelSize = NSSize(width: 248, height: 132)
    private static let displayDuration: TimeInterval = 3
    private static let fadeDuration: TimeInterval = 0.35
    private static let panelIdentifier = NSUserInterfaceItemIdentifier("xxsnap.ocr-copy-success")

    private var panel: NSPanel?
    private var fadeWorkItem: DispatchWorkItem?
    private let languageProvider: () -> AppLanguage
    private let successSoundPlayer: (() -> Void)?
    private let successSound: NSSound?

    convenience init(successSoundPlayer: (() -> Void)? = nil) {
        self.init(
            languageProvider: { .zhHans },
            successSoundPlayer: successSoundPlayer
        )
    }

    init(
        languageProvider: @escaping () -> AppLanguage,
        successSoundPlayer: (() -> Void)? = nil
    ) {
        self.languageProvider = languageProvider
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
        let language = languageProvider()
        let copy = Self.copy(for: result, language: language)
        let panelSize = Self.panelSize(for: language)
        let frame = Self.panelFrame(in: visibleFrame, size: panelSize)
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
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = OCRResultView(
            result: result,
            copy: copy,
            size: panelSize
        )
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

    private static func panelSize(for language: AppLanguage) -> NSSize {
        language == .english ? englishPanelSize : chinesePanelSize
    }

    private static func panelFrame(in visibleFrame: NSRect, size: NSSize) -> NSRect {
        NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 100,
            width: size.width,
            height: size.height
        )
    }

    private static func copy(for result: Result, language: AppLanguage) -> Copy {
        switch (language, result) {
        case (.zhHans, .success):
            return Copy(
                title: "识别成功",
                detail: "已复制到剪切板",
                accessibilityLabel: "识别成功\n已复制到剪切板"
            )
        case (.zhHans, .failure):
            return Copy(
                title: "识别失败",
                detail: nil,
                accessibilityLabel: "识别失败"
            )
        case (.english, .success):
            return Copy(
                title: "Recognition Successful",
                detail: "Copied to Clipboard",
                accessibilityLabel: "Recognition Successful\nCopied to Clipboard"
            )
        case (.english, .failure):
            return Copy(
                title: "Recognition Failed",
                detail: nil,
                accessibilityLabel: "Recognition Failed"
            )
        }
    }
}

private extension NSRect {
    var area: CGFloat {
        isNull || isEmpty ? 0 : width * height
    }
}

@MainActor
private final class OCRResultView: NSView {
    init(
        result: OCRResultPresentationController.Result,
        copy: OCRResultPresentationController.Copy,
        size: NSSize
    ) {
        super.init(frame: NSRect(origin: .zero, size: size))
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

        let title = NSTextField(labelWithString: copy.title)
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

        if let detailCopy = copy.detail {
            let detail = NSTextField(labelWithString: detailCopy)
            detail.font = .systemFont(ofSize: 13)
            detail.textColor = .secondaryLabelColor
            detail.alignment = .center
            contentStack.addArrangedSubview(detail)
        }
        setAccessibilityLabel(copy.accessibilityLabel)

        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
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
