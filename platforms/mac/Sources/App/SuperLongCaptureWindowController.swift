import AppKit

private final class SuperLongCapturePanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        // Saving a super-long capture is destructive only through the explicit button.
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { return }
        super.keyDown(with: event)
    }
}

@MainActor
final class SuperLongCaptureWarningWindowController: NSWindowController {
    static let contentWidth: CGFloat = 348

    let titleLabel = NSTextField(labelWithString: "")
    let bodyLabel = NSTextField(wrappingLabelWithString: "")
    let noteLabel = NSTextField(wrappingLabelWithString: "")
    let limitLabel = NSTextField(wrappingLabelWithString: "")
    let continueButton = NSButton()

    init(language: AppLanguage) {
        let panel = Self.makePanel()
        super.init(window: panel)
        configure(language: language)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show() {
        guard let window else { return }
        window.center()
        window.orderFrontRegardless()
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    @objc private func continueCapture() {
        dismiss()
    }

    private func configure(language: AppLanguage) {
        guard let contentView = window?.contentView else { return }
        let l10n = L10n(language: language)
        titleLabel.stringValue = l10n.text(.scrollCaptureSuperLongTitle)
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .labelColor

        bodyLabel.stringValue = l10n.text(.scrollCaptureSuperLongBody)
        noteLabel.stringValue = l10n.text(.scrollCaptureSuperLongNote)
        limitLabel.stringValue = l10n.text(.scrollCaptureSuperLongLimit)
        [bodyLabel, noteLabel, limitLabel].forEach { label in
            label.alignment = .left
            label.lineBreakMode = .byWordWrapping
            label.usesSingleLineMode = false
            label.maximumNumberOfLines = 0
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabelColor
        }
        noteLabel.textColor = .labelColor

        let icon = NSImageView(image: NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        ) ?? NSImage())
        icon.contentTintColor = .systemOrange
        icon.symbolConfiguration = .init(pointSize: 32, weight: .medium)
        icon.setContentHuggingPriority(.required, for: .vertical)

        continueButton.title = l10n.text(.scrollCaptureSuperLongContinue)
        continueButton.bezelStyle = .rounded
        continueButton.keyEquivalent = "\r"
        continueButton.target = self
        continueButton.action = #selector(continueCapture)
        continueButton.controlSize = .large

        let stack = NSStackView(views: [icon, titleLabel, bodyLabel, noteLabel, limitLabel, continueButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(8, after: icon)
        stack.setCustomSpacing(16, after: limitLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
            icon.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bodyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            noteLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            limitLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            continueButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            continueButton.heightAnchor.constraint(equalToConstant: 36),
        ])
        contentView.layoutSubtreeIfNeeded()
        window?.setContentSize(NSSize(width: Self.contentWidth, height: stack.fittingSize.height + 44))
    }

    private static func makePanel() -> SuperLongCapturePanel {
        let panel = SuperLongCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 300),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.level = .modalPanel
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 18
        panel.contentView?.layer?.masksToBounds = true
        return panel
    }
}

@MainActor
final class SuperLongCaptureSaveProgressWindowController: NSWindowController {
    static let contentWidth: CGFloat = 348

    let titleLabel = NSTextField(labelWithString: "")
    let stageLabel = NSTextField(labelWithString: "")
    let percentageLabel = NSTextField(labelWithString: "0%")
    let pathLabel = NSTextField(labelWithString: "")
    let escapeNoteLabel = NSTextField(wrappingLabelWithString: "")
    let progressIndicator = NSProgressIndicator()
    let cancelButton = NSButton()

    private let l10n: L10n
    private let selectionFrame: NSRect?
    private var onCancel: (() -> Void)?
    private var didRequestCancel = false
    private(set) var displayedProgress = 0.0

    init(
        destination: URL,
        selectionFrame: NSRect? = nil,
        language: AppLanguage,
        onCancel: @escaping () -> Void
    ) {
        self.l10n = L10n(language: language)
        self.selectionFrame = selectionFrame?.standardized
        self.onCancel = onCancel
        let panel = SuperLongCaptureWarningWindowController.makeSavePanel()
        super.init(window: panel)
        configure(destination: destination)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        if let selectionFrame, !selectionFrame.isEmpty {
            window.setFrameOrigin(NSPoint(
                x: selectionFrame.midX - window.frame.width / 2,
                y: selectionFrame.midY - window.frame.height / 2
            ))
        } else {
            window.center()
        }
        window.orderFrontRegardless()
    }

    func updateProgress(_ progress: Double) {
        guard progress.isFinite else { return }
        displayedProgress = max(displayedProgress, min(1, max(0, progress)))
        progressIndicator.doubleValue = displayedProgress * 100
        percentageLabel.stringValue = "\(Int((displayedProgress * 100).rounded()))%"
    }

    func dismiss() {
        window?.orderOut(nil)
        close()
    }

    @objc private func cancelSaving() {
        guard !didRequestCancel else { return }
        didRequestCancel = true
        cancelButton.isEnabled = false
        cancelButton.title = l10n.text(.scrollCaptureSaveCancelling)
        onCancel?()
        onCancel = nil
    }

    private func configure(destination: URL) {
        guard let contentView = window?.contentView else { return }
        titleLabel.stringValue = l10n.text(.scrollCaptureSaveTitle)
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        stageLabel.stringValue = l10n.text(.scrollCaptureSaveStage)
        stageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        percentageLabel.alignment = .right
        percentageLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.doubleValue = 0
        progressIndicator.style = .bar

        pathLabel.stringValue = destination.path
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.maximumNumberOfLines = 1

        escapeNoteLabel.stringValue = l10n.text(.scrollCaptureSaveEscapeNote)
        escapeNoteLabel.alignment = .left
        escapeNoteLabel.textColor = .tertiaryLabelColor
        escapeNoteLabel.font = .systemFont(ofSize: 11)
        escapeNoteLabel.lineBreakMode = .byWordWrapping
        escapeNoteLabel.maximumNumberOfLines = 0

        cancelButton.title = l10n.text(.scrollCaptureSaveCancel)
        cancelButton.bezelStyle = .rounded
        cancelButton.contentTintColor = .systemRed
        cancelButton.target = self
        cancelButton.action = #selector(cancelSaving)

        let statusRow = NSStackView(views: [stageLabel, percentageLabel])
        statusRow.orientation = .horizontal
        statusRow.distribution = .fill
        let separator = NSBox()
        separator.boxType = .separator
        let stack = NSStackView(views: [titleLabel, statusRow, progressIndicator, pathLabel, escapeNoteLabel, separator, cancelButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(16, after: escapeNoteLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progressIndicator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pathLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            escapeNoteLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cancelButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cancelButton.heightAnchor.constraint(equalToConstant: 34),
        ])
        contentView.layoutSubtreeIfNeeded()
        window?.setContentSize(NSSize(width: Self.contentWidth, height: stack.fittingSize.height + 44))
    }
}

fileprivate extension SuperLongCaptureWarningWindowController {
    static func makeSavePanel() -> SuperLongCapturePanel {
        let panel = SuperLongCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 260),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.level = .modalPanel
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 18
        panel.contentView?.layer?.masksToBounds = true
        return panel
    }
}
