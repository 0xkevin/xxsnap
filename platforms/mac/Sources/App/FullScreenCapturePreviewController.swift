import AppKit

struct FullScreenCapturePreviewActions {
    let open: @MainActor () -> Void
    let copy: @MainActor () -> Void
    let save: @MainActor () -> Void
    let pin: @MainActor () -> Void
}

struct FullScreenCapturePreviewContext {
    let image: NSImage
    let visibleFrame: NSRect
    let language: AppLanguage
    let actions: FullScreenCapturePreviewActions
}

@MainActor
protocol FullScreenCapturePreviewPresenting: AnyObject {
    var onClose: (() -> Void)? { get set }
    func show()
    func stop()
    func updateLanguage(_ language: AppLanguage)
}

@MainActor
final class FullScreenCapturePreviewController: NSObject, FullScreenCapturePreviewPresenting {
    private static let maximumSize = NSSize(width: 320, height: 220)
    private static let screenInset: CGFloat = 20

    private let panel: NSPanel
    private let imageView: FullScreenCapturePreviewImageView
    private let actions: FullScreenCapturePreviewActions
    private var language: AppLanguage
    private var stopped = false
    var onClose: (() -> Void)?

    init(context: FullScreenCapturePreviewContext) {
        actions = context.actions
        language = context.language
        let frame = Self.previewFrame(
            imageSize: context.image.size,
            visibleFrame: context.visibleFrame
        )
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        imageView = FullScreenCapturePreviewImageView(frame: NSRect(origin: .zero, size: frame.size))
        super.init()
        configurePanel(image: context.image)
    }

    func show() {
        guard !stopped else { return }
        panel.orderFrontRegardless()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        panel.orderOut(nil)
        imageView.image = nil
        panel.contentView = nil
        let callback = onClose
        onClose = nil
        callback?()
    }

    func updateLanguage(_ language: AppLanguage) {
        guard self.language != language, !stopped else { return }
        self.language = language
        imageView.menu = makeContextMenu()
    }

    static func previewFrame(imageSize: NSSize, visibleFrame: NSRect) -> NSRect {
        let availableWidth = max(1, visibleFrame.width - screenInset * 2)
        let availableHeight = max(1, visibleFrame.height - screenInset * 2)
        let maximumWidth = min(maximumSize.width, availableWidth)
        let maximumHeight = min(maximumSize.height, availableHeight)
        let width = max(imageSize.width, 1)
        let height = max(imageSize.height, 1)
        let scale = min(maximumWidth / width, maximumHeight / height, 1)
        let size = NSSize(width: width * scale, height: height * scale)
        return NSRect(
            x: visibleFrame.maxX - screenInset - size.width,
            y: visibleFrame.minY + screenInset,
            width: size.width,
            height: size.height
        )
    }

    private func configurePanel(image: NSImage) {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        imageView.layer?.borderWidth = 1
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.openHandler = { [weak self] in
            self?.open()
        }
        imageView.menu = makeContextMenu()
        panel.contentView = imageView
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let toolbarItem = menuItem(
            title: language == .english ? "Show Toolbar (⇧)" : "显示工具条 (⇧)",
            action: #selector(openFromMenu(_:))
        )
        toolbarItem.state = .off
        menu.addItem(toolbarItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: language == .english ? "Pin Image" : "贴图",
            action: #selector(pinPressed(_:))
        ))
        menu.addItem(menuItem(
            title: language == .english ? "Copy Image" : "复制图片",
            action: #selector(copyPressed(_:)),
            keyEquivalent: "c",
            modifierMask: [.command]
        ))
        menu.addItem(menuItem(
            title: language == .english ? "Save Image" : "保存图片",
            action: #selector(savePressed(_:)),
            keyEquivalent: "s",
            modifierMask: [.command]
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: language == .english ? "Close" : "关闭",
            action: #selector(closePressed(_:)),
            keyEquivalent: "w",
            modifierMask: [.command]
        ))
        return menu
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifierMask
        item.target = self
        return item
    }

    private func open() {
        guard !stopped else { return }
        stop()
        actions.open()
    }

    @objc private func openFromMenu(_ sender: Any?) {
        open()
    }

    @objc private func copyPressed(_ sender: Any?) {
        actions.copy()
    }

    @objc private func savePressed(_ sender: Any?) {
        actions.save()
    }

    @objc private func pinPressed(_ sender: Any?) {
        actions.pin()
    }

    @objc private func closePressed(_ sender: Any?) {
        stop()
    }

#if DEBUG
    var test_contextMenuTitles: [String?] {
        imageView.menu?.items.map { $0.isSeparatorItem ? nil : $0.title } ?? []
    }

    func test_triggerOpen() {
        open()
    }
#endif
}

private final class FullScreenCapturePreviewImageView: NSImageView {
    var openHandler: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        openHandler?()
    }
}
