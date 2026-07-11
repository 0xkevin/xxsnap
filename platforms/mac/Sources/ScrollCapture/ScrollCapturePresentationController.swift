import AppKit

enum ScrollCaptureOverlayState: Equatable {
    case inactive
    case capturing
    case paused(message: String)
}

struct ScrollCaptureControlGeometry: Equatable {
    let toolbarFrame: NSRect
    let finishButtonFrame: NSRect
    let cancelButtonFrame: NSRect
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
    private var boundsObserver: NSObjectProtocol?
    private var isProgrammaticScroll = false
    private(set) var isFollowingTail = true
    private var reviewOffset: CGFloat = 0
    private var terminalActionTriggered = false
    private var hasStarted = false
    private var stopped = false

    init(
        toolbarFrame: NSRect,
        finishButtonFrame: NSRect,
        cancelButtonFrame: NSRect,
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
        configureControlPanel(
            finishButtonFrame: finishButtonFrame.offsetBy(dx: -toolbarFrame.minX, dy: -toolbarFrame.minY),
            cancelButtonFrame: cancelButtonFrame.offsetBy(dx: -toolbarFrame.minX, dy: -toolbarFrame.minY)
        )
        configurePreviewPanel()
        installBoundsObserver()
    }

    deinit {
        MainActor.assumeIsolated {
            cleanup()
        }
    }

    private func configureControlPanel(finishButtonFrame: NSRect, cancelButtonFrame: NSRect) {
        controlPanel.level = .screenSaver
        controlPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        controlPanel.isOpaque = false
        controlPanel.backgroundColor = .clear
        controlPanel.hasShadow = false
        let content = NSView(frame: NSRect(origin: .zero, size: controlPanel.frame.size))
        let finish = transparentHitTarget(frame: finishButtonFrame, action: #selector(finishPressed))
        let cancel = transparentHitTarget(frame: cancelButtonFrame, action: #selector(cancelPressed))
        content.addSubview(finish)
        content.addSubview(cancel)
        controlPanel.contentView = content
    }

    private func transparentHitTarget(frame: NSRect, action: Selector) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.target = self
        button.action = action
        return button
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
        content.addSubview(scrollView)
        content.addSubview(warningLabel)
        previewPanel.contentView = content
    }

    func start() {
        guard !hasStarted, !stopped else { return }
        hasStarted = true
        controlPanel.orderFrontRegardless()
        previewPanel.orderFrontRegardless()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        cleanup()
    }

    private func cleanup() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        controlPanel.orderOut(nil)
        previewPanel.orderOut(nil)
        imageView.image = nil
        warningLabel.stringValue = ""
        warningLabel.isHidden = true
        scrollView.documentView = nil
    }

    private func installBoundsObserver() {
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrollBoundsChanged() }
        }
    }

    func updatePreview(_ image: NSImage) {
        guard !stopped else { return }
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        let width = max(1, scrollView.contentSize.width)
        let height = max(scrollView.contentSize.height, image.size.height * width / max(image.size.width, 1))
        imageView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        isProgrammaticScroll = true
        if isFollowingTail {
            scrollView.contentView.scroll(to: .zero)
            reviewOffset = 0
        } else {
            let maximumOffset = max(0, height - scrollView.contentSize.height)
            reviewOffset = min(reviewOffset, maximumOffset)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: reviewOffset))
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isProgrammaticScroll = false
    }

    func setWarning(_ text: String) {
        guard !stopped else { return }
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

    @objc private func finishPressed() { triggerTerminalAction(onFinish) }
    @objc private func cancelPressed() { triggerTerminalAction(onCancel) }

    private func triggerTerminalAction(_ action: () -> Void) {
        guard !terminalActionTriggered else { return }
        terminalActionTriggered = true
        controlPanel.contentView?.subviews.compactMap { $0 as? NSControl }.forEach { $0.isEnabled = false }
        controlPanel.ignoresMouseEvents = true
        action()
    }

    @objc private func scrollBoundsChanged() {
        guard !isProgrammaticScroll else { return }
        reviewOffset = max(0, scrollView.documentVisibleRect.minY)
        isFollowingTail = reviewOffset <= 2
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
    var test_controlIsOpaque: Bool { controlPanel.isOpaque }
    var test_controlBackgroundColor: NSColor { controlPanel.backgroundColor }
    var test_finishButtonFrame: NSRect { (controlPanel.contentView?.subviews.first as? NSButton)?.frame ?? .zero }
    var test_cancelButtonFrame: NSRect { (controlPanel.contentView?.subviews.last as? NSButton)?.frame ?? .zero }
    var test_controlHitTargetCount: Int { controlPanel.contentView?.subviews.compactMap { $0 as? NSButton }.count ?? 0 }
    var test_controlHitTargetsAreTransparent: Bool {
        controlPanel.contentView?.subviews.compactMap { $0 as? NSButton }.allSatisfy { $0.isTransparent && !$0.isBordered } ?? false
    }
    var test_hasVisiblePanels: Bool { controlPanel.isVisible || previewPanel.isVisible }
    var test_isFollowingTail: Bool { isFollowingTail }
    var test_visibleRect: NSRect { scrollView.documentVisibleRect }
    var test_reviewOffset: CGFloat { reviewOffset }
    var test_hasBoundsObserver: Bool { boundsObserver != nil }
    var test_warningText: String? { warningLabel.isHidden ? nil : warningLabel.stringValue }
    var test_previewImage: NSImage? { imageView.image }
    func test_triggerFinish() { (controlPanel.contentView?.subviews.first as? NSButton)?.performClick(nil) }
    func test_triggerCancel() { (controlPanel.contentView?.subviews.last as? NSButton)?.performClick(nil) }
    func test_userScroll(to offset: CGFloat) {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        scrollBoundsChanged()
    }
    func test_postBoundsChangeNotification() {
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }
#endif
}
