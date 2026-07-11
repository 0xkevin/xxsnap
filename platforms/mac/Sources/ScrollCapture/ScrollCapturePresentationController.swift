import AppKit

enum ScrollCaptureOverlayState: Equatable {
    case inactive
    case capturing
    case paused(message: String)
}

@MainActor
final class ScrollCapturePresentationController: NSObject {
    private let controlPanel: NSPanel
    private let previewPanel: NSPanel
    private let scrollView = NSScrollView()
    private let imageView = NSImageView()
    private let warningLabel = NSTextField(labelWithString: "")
    private let onFinish: () -> Void
    private let onCancel: () -> Void
    private var isProgrammaticScroll = false
    private(set) var isFollowingTail = true
    private var reviewPosition: CGFloat = 1
    private var stopped = false

    init(
        toolbarFrame: NSRect,
        selectionFrame: NSRect,
        visibleFrame: NSRect,
        language: AppLanguage,
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onFinish = onFinish
        self.onCancel = onCancel
        controlPanel = NSPanel(
            contentRect: toolbarFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let previewSize = NSSize(width: 300, height: min(480, max(240, visibleFrame.height * 0.6)))
        let previewFrame = Self.previewFrame(
            selection: selectionFrame,
            previewSize: previewSize,
            visibleFrame: visibleFrame
        )
        previewPanel = NSPanel(
            contentRect: previewFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configureControlPanel(language: language)
        configurePreviewPanel()
    }

    private func configureControlPanel(language: AppLanguage) {
        controlPanel.level = .screenSaver
        controlPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        controlPanel.isOpaque = false
        controlPanel.backgroundColor = .clear
        controlPanel.hasShadow = false
        let content = NSView(frame: NSRect(origin: .zero, size: controlPanel.frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        content.layer?.cornerRadius = 6
        let finish = NSButton(title: L10n(language: language).text(.finishScrollCapture), target: self, action: #selector(finishPressed))
        finish.bezelStyle = .rounded
        finish.frame = NSRect(x: max(4, content.bounds.maxX - 156), y: 3, width: 112, height: 22)
        let cancel = NSButton(title: L10n(language: language).text(.cancel), target: self, action: #selector(cancelPressed))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: max(4, content.bounds.maxX - 40), y: 3, width: 36, height: 22)
        content.addSubview(finish)
        content.addSubview(cancel)
        controlPanel.contentView = content
    }

    private func configurePreviewPanel() {
        previewPanel.level = .screenSaver
        previewPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        previewPanel.isOpaque = false
        previewPanel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        previewPanel.hasShadow = true

        let content = NSView(frame: NSRect(origin: .zero, size: previewPanel.frame.size))
        warningLabel.frame = NSRect(x: 8, y: 6, width: content.bounds.width - 16, height: 22)
        warningLabel.textColor = .systemOrange
        warningLabel.isHidden = true
        scrollView.frame = NSRect(x: 0, y: 30, width: content.bounds.width, height: content.bounds.height - 30)
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = imageView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        content.addSubview(scrollView)
        content.addSubview(warningLabel)
        previewPanel.contentView = content
    }

    func start() {
        stopped = false
        controlPanel.orderFrontRegardless()
        previewPanel.orderFrontRegardless()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        controlPanel.orderOut(nil)
        previewPanel.orderOut(nil)
    }

    func updatePreview(_ image: NSImage) {
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        let width = max(1, scrollView.contentSize.width)
        let height = max(scrollView.contentSize.height, image.size.height * width / max(image.size.width, 1))
        imageView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let newMax = max(0, height - scrollView.contentSize.height)
        isProgrammaticScroll = true
        if isFollowingTail {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: newMax))
            reviewPosition = 1
        } else {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: newMax * reviewPosition))
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isProgrammaticScroll = false
    }

    func setWarning(_ text: String) {
        warningLabel.stringValue = text
        warningLabel.isHidden = false
    }

    func clearWarning() {
        warningLabel.stringValue = ""
        warningLabel.isHidden = true
    }

    func updatePlacement(selectionFrame: NSRect, visibleFrame: NSRect) {
        previewPanel.setFrame(Self.previewFrame(
            selection: selectionFrame,
            previewSize: previewPanel.frame.size,
            visibleFrame: visibleFrame
        ), display: false)
    }

    @objc private func finishPressed() { onFinish() }
    @objc private func cancelPressed() { onCancel() }

    @objc private func scrollBoundsChanged() {
        guard !isProgrammaticScroll else { return }
        let maxY = max(0, imageView.frame.height - scrollView.contentSize.height)
        let y = min(maxY, max(0, scrollView.contentView.bounds.minY))
        isFollowingTail = maxY - y <= 2
        reviewPosition = maxY > 0 ? y / maxY : 1
    }

    static func previewFrame(
        selection: NSRect,
        previewSize: NSSize,
        visibleFrame: NSRect,
        spacing: CGFloat = 12
    ) -> NSRect {
        let selection = selection.standardized
        let visible = visibleFrame.standardized
        let size = NSSize(width: min(previewSize.width, visible.width), height: min(previewSize.height, visible.height))
        struct Candidate { let frame: NSRect; let space: CGFloat; let order: Int }
        let centeredY = min(max(selection.midY - size.height / 2, visible.minY), visible.maxY - size.height)
        let centeredX = min(max(selection.midX - size.width / 2, visible.minX), visible.maxX - size.width)
        let candidates = [
            Candidate(frame: NSRect(x: selection.maxX + spacing, y: centeredY, width: size.width, height: size.height), space: visible.maxX - selection.maxX, order: 0),
            Candidate(frame: NSRect(x: selection.minX - spacing - size.width, y: centeredY, width: size.width, height: size.height), space: selection.minX - visible.minX, order: 1),
            Candidate(frame: NSRect(x: centeredX, y: selection.maxY + spacing, width: size.width, height: size.height), space: visible.maxY - selection.maxY, order: 2),
            Candidate(frame: NSRect(x: centeredX, y: selection.minY - spacing - size.height, width: size.width, height: size.height), space: selection.minY - visible.minY, order: 3),
        ]
        if let best = candidates.filter({ visible.contains($0.frame) && !$0.frame.intersects(selection) })
            .sorted(by: { $0.space == $1.space ? $0.order < $1.order : $0.space > $1.space }).first {
            return best.frame
        }
        let insideX = min(max(selection.maxX - size.width - spacing, visible.minX), visible.maxX - size.width)
        let insideY = min(max(selection.minY + spacing, visible.minY), visible.maxY - size.height)
        return NSRect(x: insideX, y: insideY, width: size.width, height: size.height)
    }

#if DEBUG
    var test_controlStyleMask: NSWindow.StyleMask { controlPanel.styleMask }
    var test_controlFrame: NSRect { controlPanel.frame }
    var test_controlCanBecomeKey: Bool { controlPanel.canBecomeKey }
    var test_hasVisiblePanels: Bool { controlPanel.isVisible || previewPanel.isVisible }
    var test_isFollowingTail: Bool { isFollowingTail }
    var test_reviewPosition: CGFloat { reviewPosition }
    var test_warningText: String? { warningLabel.isHidden ? nil : warningLabel.stringValue }
    var test_previewImage: NSImage? { imageView.image }
    func test_triggerFinish() { finishPressed() }
    func test_triggerCancel() { cancelPressed() }
    func test_userReviewedAwayFromBottom(position: CGFloat) {
        isFollowingTail = false
        reviewPosition = min(1, max(0, position))
    }
    func test_userReturnedToBottom() { isFollowingTail = true; reviewPosition = 1 }
#endif
}
