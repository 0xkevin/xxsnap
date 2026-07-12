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
    private let finishPanel: NSPanel
    private let cancelPanel: NSPanel
    private let previewPanel: NSPanel
    private let controlFrame: NSRect
    private let scrollView = NSScrollView()
    private let imageView = NSImageView()
    private let warningLabel = NSTextField(labelWithString: "")
    private let onFinish: () -> Void
    private let onCancel: () -> Void
    private var boundsObserver: NSObjectProtocol?
    private var isProgrammaticScroll = false
    private(set) var isFollowingTail = true
    private var reviewOffset: CGFloat = 0
    private var followEdge: ScrollCapturePreviewEdge = .bottom
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
        self.controlFrame = toolbarFrame
        controlPanel = NSPanel(
            contentRect: toolbarFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        finishPanel = NSPanel(
            contentRect: finishButtonFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        cancelPanel = NSPanel(
            contentRect: cancelButtonFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let previewSize = NSSize(width: 300, height: min(480, max(240, visibleFrame.height * 0.6)))
        let previewFrame = Self.previewFrameAvoidingControl(
            selection: selectionFrame,
            previewSize: previewSize,
            visibleFrame: visibleFrame,
            controlFrame: toolbarFrame
        )
        previewPanel = NSPanel(
            contentRect: previewFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configureControlPanel()
        let l10n = L10n(language: language)
        configureHitPanel(finishPanel, action: #selector(finishPressed), label: l10n.text(.finishScrollCapture))
        configureHitPanel(cancelPanel, action: #selector(cancelPressed), label: l10n.text(.cancel))
        configurePreviewPanel()
        installBoundsObserver()
    }

    private func configureControlPanel() {
        controlPanel.level = .screenSaver
        controlPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        controlPanel.isOpaque = false
        controlPanel.backgroundColor = .clear
        controlPanel.hasShadow = false
        controlPanel.ignoresMouseEvents = true
        controlPanel.contentView = NSView(frame: NSRect(origin: .zero, size: controlPanel.frame.size))
    }

    private func configureHitPanel(_ panel: NSPanel, action: Selector, label: String) {
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        let button = NSButton(frame: NSRect(origin: .zero, size: panel.frame.size))
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.setAccessibilityRole(.button)
        button.target = self
        button.action = action
        panel.contentView = button
    }

    private func configurePreviewPanel() {
        previewPanel.level = .screenSaver
        previewPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        previewPanel.isOpaque = false
        previewPanel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        previewPanel.hasShadow = true

        let content = NSView(frame: NSRect(origin: .zero, size: previewPanel.frame.size))
        warningLabel.frame = NSRect(x: 8, y: 6, width: content.bounds.width - 16, height: 44)
        warningLabel.textColor = .systemOrange
        warningLabel.isHidden = true
        warningLabel.maximumNumberOfLines = 2
        warningLabel.lineBreakMode = .byWordWrapping
        warningLabel.cell?.wraps = true
        scrollView.frame = NSRect(x: 0, y: 54, width: content.bounds.width, height: content.bounds.height - 54)
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
        finishPanel.orderFrontRegardless()
        cancelPanel.orderFrontRegardless()
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
        finishPanel.orderOut(nil)
        cancelPanel.orderOut(nil)
        previewPanel.orderOut(nil)
        imageView.image = nil
        warningLabel.stringValue = ""
        warningLabel.isHidden = true
        warningLabel.toolTip = nil
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

    func updatePreview(_ image: NSImage, following edge: ScrollCapturePreviewEdge) {
        guard !stopped else { return }
        let previousDocumentHeight = imageView.frame.height
        followEdge = edge
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        let width = max(1, scrollView.contentSize.width)
        let height = max(scrollView.contentSize.height, image.size.height * width / max(image.size.width, 1))
        imageView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        isProgrammaticScroll = true
        let maximumOffset = max(0, height - scrollView.contentSize.height)
        if isFollowingTail {
            reviewOffset = edge == .bottom ? 0 : maximumOffset
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: reviewOffset))
        } else {
            let growth = max(0, height - previousDocumentHeight)
            if edge == .bottom {
                reviewOffset = min(reviewOffset + growth, maximumOffset)
            } else {
                reviewOffset = min(reviewOffset, maximumOffset)
            }
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: reviewOffset))
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isProgrammaticScroll = false
    }

    func setWarning(_ text: String) {
        guard !stopped else { return }
        warningLabel.stringValue = text
        warningLabel.toolTip = text
        warningLabel.isHidden = false
    }

    func clearWarning() {
        warningLabel.stringValue = ""
        warningLabel.toolTip = nil
        warningLabel.isHidden = true
    }

    func updatePlacement(selectionFrame: NSRect, visibleFrame: NSRect) {
        previewPanel.setFrame(Self.previewFrameAvoidingControl(
            selection: selectionFrame,
            previewSize: previewPanel.frame.size,
            visibleFrame: visibleFrame,
            controlFrame: controlFrame
        ), display: false)
    }

    func resetTerminalActionsForRetry() {
        guard !stopped else { return }
        terminalActionTriggered = false
        [finishPanel, cancelPanel].forEach { panel in
            (panel.contentView as? NSControl)?.isEnabled = true
            panel.ignoresMouseEvents = false
        }
    }

    @objc private func finishPressed() { triggerTerminalAction(onFinish) }
    @objc private func cancelPressed() { triggerTerminalAction(onCancel) }

    private func triggerTerminalAction(_ action: () -> Void) {
        guard !terminalActionTriggered else { return }
        terminalActionTriggered = true
        [finishPanel, cancelPanel].forEach { panel in
            (panel.contentView as? NSControl)?.isEnabled = false
            panel.ignoresMouseEvents = true
        }
        action()
    }

    @objc private func scrollBoundsChanged() {
        guard !isProgrammaticScroll else { return }
        reviewOffset = max(0, scrollView.documentVisibleRect.minY)
        let maximumOffset = max(0, imageView.frame.height - scrollView.contentSize.height)
        isFollowingTail = followEdge == .bottom
            ? reviewOffset <= 2
            : reviewOffset >= maximumOffset - 2
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

    private static func previewFrameAvoidingControl(
        selection: NSRect,
        previewSize: NSSize,
        visibleFrame: NSRect,
        controlFrame: NSRect,
        spacing: CGFloat = 12
    ) -> NSRect {
        let base = previewFrame(
            selection: selection,
            previewSize: previewSize,
            visibleFrame: visibleFrame,
            spacing: spacing
        )
        guard base.intersects(controlFrame) else { return base }

        let visible = visibleFrame.standardized
        let selectionArea = selection.standardized.intersection(visible)
        let control = controlFrame.standardized.intersection(visible)
        let desired = NSSize(
            width: min(previewSize.width, visible.width),
            height: min(previewSize.height, visible.height)
        )
        let regions = availablePreviewRegions(around: control, inside: visible, spacing: spacing)
        let preferredRegions = availablePreviewRegions(around: control, inside: selectionArea, spacing: spacing) + regions

        if let region = preferredRegions.first(where: { $0.width >= desired.width && $0.height >= desired.height }) {
            return NSRect(origin: region.origin, size: desired)
        }
        guard let largest = regions.max(by: { $0.width * $0.height < $1.width * $1.height }),
              largest.width > 0,
              largest.height > 0 else {
            return NSRect(origin: visible.origin, size: .zero)
        }
        return NSRect(
            origin: largest.origin,
            size: NSSize(width: min(desired.width, largest.width), height: min(desired.height, largest.height))
        )
    }

    private static func availablePreviewRegions(
        around control: NSRect,
        inside bounds: NSRect,
        spacing: CGFloat
    ) -> [NSRect] {
        guard !bounds.isNull, !bounds.isEmpty else { return [] }
        return [
            NSRect(x: bounds.minX, y: max(bounds.minY, control.maxY + spacing), width: bounds.width, height: max(0, bounds.maxY - max(bounds.minY, control.maxY + spacing))),
            NSRect(x: bounds.minX, y: bounds.minY, width: max(0, min(bounds.maxX, control.minX - spacing) - bounds.minX), height: bounds.height),
            NSRect(x: min(bounds.maxX, control.maxX + spacing), y: bounds.minY, width: max(0, bounds.maxX - min(bounds.maxX, control.maxX + spacing)), height: bounds.height),
            NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, min(bounds.maxY, control.minY - spacing) - bounds.minY)),
        ].filter { $0.width > 0 && $0.height > 0 && !$0.intersects(control) }
    }

#if DEBUG
    var test_controlStyleMask: NSWindow.StyleMask { controlPanel.styleMask }
    var test_controlFrame: NSRect { controlPanel.frame }
    var test_controlCanBecomeKey: Bool { controlPanel.canBecomeKey }
    var test_controlIgnoresMouseEvents: Bool { controlPanel.ignoresMouseEvents }
    var test_controlIsOpaque: Bool { controlPanel.isOpaque }
    var test_controlBackgroundColor: NSColor { controlPanel.backgroundColor }
    var test_finishButtonFrame: NSRect { finishPanel.frame }
    var test_cancelButtonFrame: NSRect { cancelPanel.frame }
    var test_finishButtonToolTip: String? { (finishPanel.contentView as? NSButton)?.toolTip }
    var test_cancelButtonToolTip: String? { (cancelPanel.contentView as? NSButton)?.toolTip }
    var test_finishAccessibilityLabel: String? { (finishPanel.contentView as? NSButton)?.accessibilityLabel() }
    var test_cancelAccessibilityLabel: String? { (cancelPanel.contentView as? NSButton)?.accessibilityLabel() }
    var test_accessibilityRoles: [NSAccessibility.Role] {
        [finishPanel, cancelPanel].compactMap { ($0.contentView as? NSButton)?.accessibilityRole() }
    }
    var test_controlHitTargetCount: Int { [finishPanel, cancelPanel].compactMap { $0.contentView as? NSButton }.count }
    var test_controlHitTargetsAreTransparent: Bool {
        [finishPanel, cancelPanel].compactMap { $0.contentView as? NSButton }.allSatisfy { $0.isTransparent && !$0.isBordered }
    }
    var test_interactiveWindowFrames: [NSRect] { [finishPanel.frame, cancelPanel.frame] }
    func test_toolbarPointIsInteractive(_ point: NSPoint) -> Bool {
        [finishPanel, cancelPanel].contains { !$0.ignoresMouseEvents && $0.frame.contains(point) }
    }
    var test_hasVisiblePanels: Bool { controlPanel.isVisible || finishPanel.isVisible || cancelPanel.isVisible || previewPanel.isVisible }
    var test_previewFrame: NSRect { previewPanel.frame }
    var test_isFollowingTail: Bool { isFollowingTail }
    var test_visibleRect: NSRect { scrollView.documentVisibleRect }
    var test_contentWidth: CGFloat { scrollView.contentSize.width }
    var test_documentHeight: CGFloat { imageView.frame.height }
    var test_reviewOffset: CGFloat { reviewOffset }
    var test_hasBoundsObserver: Bool { boundsObserver != nil }
    var test_warningText: String? { warningLabel.isHidden ? nil : warningLabel.stringValue }
    var test_warningFrame: NSRect { warningLabel.frame }
    var test_warningWraps: Bool { warningLabel.lineBreakMode == .byWordWrapping && warningLabel.maximumNumberOfLines == 2 }
    var test_warningToolTip: String? { warningLabel.toolTip }
    var test_previewImage: NSImage? { imageView.image }
    func test_triggerFinish() { (finishPanel.contentView as? NSButton)?.performClick(nil) }
    func test_triggerCancel() { (cancelPanel.contentView as? NSButton)?.performClick(nil) }
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
