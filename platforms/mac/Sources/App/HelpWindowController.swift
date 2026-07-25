import AppKit

@MainActor
final class HelpWindowController: NSWindowController, NSWindowDelegate {
    private let settingsStore: any AppSettingsStoring
    private let contentLoader: any HelpContentLoading

    private var language: AppLanguage = .zhHans
    private var chapters: [HelpChapter] = []
    private var selectedChapterID: String?
    private var scrollOffsets: [String: CGFloat] = [:]
    private var navigationButtons: [String: NSButton] = [:]
    private var contentView: HelpContentView?
    private var imagePreviewController: HelpImagePreviewController?
    private var isSessionActive = false
    private var isShowingError = false
    private var imagePreviewDismissCount = 0

    init(
        settingsStore: any AppSettingsStoring,
        contentLoader: any HelpContentLoading = HelpContentLoader()
    ) {
        self.settingsStore = settingsStore
        self.contentLoader = contentLoader
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        if isSessionActive {
            saveCurrentScrollOffset()
        } else {
            resetSession()
        }
        reloadContent()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isSessionActive = true
    }

    var test_navigationTitles: [String] {
        chapters.map(\.navigationTitle)
    }

    var test_selectedChapterID: String? {
        selectedChapterID
    }

    var test_visibleTexts: [String] {
        contentView?.test_visibleTexts ?? []
    }

    var test_visibleImageCount: Int {
        contentView?.test_visibleImageCount ?? 0
    }

    func test_setScrollOffset(_ offset: CGFloat) {
        contentView?.scrollOffset = offset
    }

    func test_clickNavigationButton(_ chapterID: String) {
        navigationButtons[chapterID]?.performClick(nil)
    }

    func test_navigationButtonState(
        _ chapterID: String
    ) -> NSControl.StateValue {
        navigationButtons[chapterID]?.state ?? .off
    }

    var test_scrollOffset: CGFloat {
        contentView?.scrollOffset ?? 0
    }

    func test_clickFirstImage() {
        contentView?.test_clickFirstImage()
    }

    var test_isImagePreviewVisible: Bool {
        imagePreviewController?.window?.isVisible == true
    }

    func test_dismissImagePreview() {
        imagePreviewController?.dismiss()
    }

    var test_imagePreviewAccessibilityLabel: String? {
        imagePreviewController?.test_imageAccessibilityLabel
    }

    var test_imagePreviewDismissCount: Int {
        imagePreviewDismissCount
    }

    func test_cancelImagePreview() {
        imagePreviewController?.cancelOperation(nil)
    }

    func test_clickImagePreviewCloseButton() {
        imagePreviewController?.test_clickCloseButton()
    }

    func windowWillClose(_ notification: Notification) {
        imagePreviewController?.dismiss()
        imagePreviewController = nil
        isSessionActive = false
        resetSession()
        updateNavigationSelection()
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable
            ],
            backing: .buffered,
            defer: false
        )
        window.title = "XxSnap 帮助"
        window.minSize = NSSize(width: 760, height: 540)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.animationBehavior = .documentWindow
        window.delegate = self
        window.center()
        self.window = window

        let helpContentView = HelpContentView { [weak self] name in
            guard let self else { return nil }
            return self.contentLoader.image(named: name, language: self.language)
        }
        helpContentView.onImageSelected = {
            [weak self] image, caption, accessibilityLabel in
            self?.showImagePreview(
                image: image,
                caption: caption,
                accessibilityLabel: accessibilityLabel
            )
        }
        contentView = helpContentView
    }

    private func reloadContent() {
        guard let window, let contentView else { return }

        language = settingsStore.load().language
        imagePreviewController?.dismiss()
        imagePreviewController = nil

        do {
            let document = try contentLoader.load(language: language)
            chapters = document.chapters
            window.title = document.windowTitle
            if !chapters.contains(where: { $0.id == selectedChapterID }) {
                selectedChapterID = chapters.contains { $0.id == "capture" }
                    ? "capture"
                    : chapters.first?.id
            }
            window.contentView = makeSplitContent(contentView)
            isShowingError = false
            renderSelectedChapter()
        } catch {
            window.title = "XxSnap 帮助"
            window.contentView = makeSplitContent(contentView)
            contentView.renderError("帮助内容暂时无法打开")
            isShowingError = true
            navigationButtons.values.forEach { $0.isEnabled = false }
        }
    }

    private func makeSplitContent(_ helpContentView: HelpContentView) -> NSView {
        let root = NSView()

        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let navigationStack = NSStackView()
        navigationStack.translatesAutoresizingMaskIntoConstraints = false
        navigationStack.orientation = .vertical
        navigationStack.alignment = .leading
        navigationStack.spacing = 6

        navigationButtons = [:]
        for chapter in chapters {
            let button = NSButton(
                title: chapter.navigationTitle,
                target: self,
                action: #selector(selectNavigationButton(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(chapter.id)
            button.setButtonType(.toggle)
            button.bezelStyle = .recessed
            button.alignment = .left
            button.font = .systemFont(ofSize: 14, weight: .medium)
            button.translatesAutoresizingMaskIntoConstraints = false
            navigationStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: navigationStack.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            navigationButtons[chapter.id] = button
        }

        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator

        helpContentView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        root.addSubview(separator)
        root.addSubview(helpContentView)
        sidebar.addSubview(navigationStack)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 190),

            navigationStack.leadingAnchor.constraint(
                equalTo: sidebar.leadingAnchor,
                constant: 18
            ),
            navigationStack.trailingAnchor.constraint(
                equalTo: sidebar.trailingAnchor,
                constant: -18
            ),
            navigationStack.topAnchor.constraint(
                equalTo: sidebar.topAnchor,
                constant: 24
            ),

            separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: root.topAnchor),
            separator.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            helpContentView.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            helpContentView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            helpContentView.topAnchor.constraint(equalTo: root.topAnchor),
            helpContentView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        updateNavigationSelection()
        return root
    }

    @objc
    private func selectNavigationButton(_ sender: NSButton) {
        guard let chapterID = sender.identifier?.rawValue else { return }
        selectChapter(chapterID)
    }

    private func selectChapter(_ chapterID: String) {
        guard chapters.contains(where: { $0.id == chapterID }) else { return }
        guard chapterID != selectedChapterID else {
            updateNavigationSelection()
            return
        }

        saveCurrentScrollOffset()
        selectedChapterID = chapterID
        renderSelectedChapter()
        updateNavigationSelection()
    }

    private func renderSelectedChapter() {
        guard
            let selectedChapterID,
            let chapter = chapters.first(where: { $0.id == selectedChapterID }),
            let contentView
        else {
            return
        }
        contentView.render(chapter)
        contentView.scrollOffset = scrollOffsets[selectedChapterID] ?? 0
    }

    private func updateNavigationSelection() {
        for (chapterID, button) in navigationButtons {
            button.state = chapterID == selectedChapterID ? .on : .off
        }
    }

    private func saveCurrentScrollOffset() {
        guard
            !isShowingError,
            let selectedChapterID,
            chapters.contains(where: { $0.id == selectedChapterID }),
            let contentView
        else {
            return
        }
        scrollOffsets[selectedChapterID] = contentView.scrollOffset
    }

    private func resetSession() {
        scrollOffsets.removeAll()
        selectedChapterID = nil
        isShowingError = false
    }

    private func showImagePreview(
        image: NSImage,
        caption: String,
        accessibilityLabel: String
    ) {
        guard let window else { return }
        imagePreviewController?.dismiss()

        let previewController = HelpImagePreviewController(
            image: image,
            caption: caption,
            accessibilityLabel: accessibilityLabel
        )
        previewController.onDismiss = { [weak self, weak previewController] in
            guard let self, self.imagePreviewController === previewController else {
                return
            }
            self.imagePreviewDismissCount += 1
            self.imagePreviewController = nil
        }
        imagePreviewController = previewController
        previewController.show(over: window)
    }
}
