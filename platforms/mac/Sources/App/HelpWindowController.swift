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
    private var navigationIndicatorViews: [String: NSView] = [:]
    private weak var navigationStack: HelpNavigationStackView?
    private weak var sidebarView: HelpSidebarView?
    private var workspaceAppearanceObserver: NSObjectProtocol?
    private var systemColorsObserver: NSObjectProtocol?
    private var hasInitializedNavigationSelection = false
    private var contentView: HelpContentView?
    private var imagePreviewController: HelpImagePreviewController?
    private var isSessionActive = false
    private var isShowingError = false
    private var hasBuiltWindow = false
    private var imagePreviewDismissCount = 0

    init(
        settingsStore: any AppSettingsStoring,
        contentLoader: any HelpContentLoading = HelpContentLoader()
    ) {
        self.settingsStore = settingsStore
        self.contentLoader = contentLoader
        super.init(window: nil)
        startObservingSystemAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let workspaceAppearanceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                workspaceAppearanceObserver
            )
        }
        if let systemColorsObserver {
            NotificationCenter.default.removeObserver(systemColorsObserver)
        }
    }

    func show() {
        if !hasBuiltWindow {
            buildWindow()
        }
        if isSessionActive {
            saveCurrentScrollOffset()
        } else {
            resetSession()
        }
        reloadContent()
        applySystemAppearance()
        NSApp.activate(ignoringOtherApps: true)
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

    var test_selectedNavigationIndicators: [String] {
        navigationIndicatorViews.compactMap { chapterID, indicator in
            indicator.isHidden ? nil : chapterID
        }.sorted()
    }

    func test_navigationIndicator(
        for chapterID: String
    ) -> (
        isPositionedLeftOfButton: Bool,
        width: CGFloat,
        height: CGFloat,
        color: NSColor
    )? {
        guard
            let button = navigationButtons[chapterID],
            let indicator = navigationIndicatorViews[chapterID],
            !indicator.isHidden,
            let row = indicator.superview,
            let layerColor = indicator.layer?.backgroundColor,
            let color = NSColor(cgColor: layerColor)
        else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        let indicatorFrame = indicator.convert(indicator.bounds, to: row)
        let buttonFrame = button.convert(button.bounds, to: row)
        return (
            indicatorFrame.maxX <= buttonFrame.minX,
            indicatorFrame.width,
            indicatorFrame.height,
            color
        )
    }

    var test_contentBackgroundState: (
        helpContentLayerColor: NSColor?,
        scrollViewDrawsBackground: Bool,
        scrollViewBackgroundColor: NSColor,
        clipViewDrawsBackground: Bool,
        clipViewBackgroundColor: NSColor,
        documentViewLayerColor: NSColor?
    ) {
        contentView?.test_backgroundState ?? (
            nil,
            false,
            .clear,
            false,
            .clear,
            nil
        )
    }

    var test_contentAppearanceName: NSAppearance.Name? {
        contentView?.appliedAppearanceName
    }

    var test_onNextSystemAppearanceRefresh: ((Bool) -> Void)?

    func test_applySystemAppearance(
        increaseContrast: Bool,
        accentColor: NSColor
    ) {
        applySystemAppearance(
            increaseContrast: increaseContrast,
            accentColor: accentColor
        )
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
        contentView?.clear()
        isSessionActive = false
        resetSession()
        updateNavigationSelection()
    }

    private func buildWindow() {
        let strings = PreferencesStrings(language: settingsStore.load().language)
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
        window.title = strings.helpWindowTitle
        window.contentMinSize = NSSize(width: 760, height: 512)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.animationBehavior = .documentWindow
        window.delegate = self
        window.center()
        self.window = window
        hasBuiltWindow = true

        let helpContentView = HelpContentView(
            imageUnavailableText: strings.helpImageUnavailable
        ) { [weak self] name in
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
        let strings = PreferencesStrings(language: language)
        contentView.imageUnavailableText = strings.helpImageUnavailable
        imagePreviewController?.dismiss()
        imagePreviewController = nil

        do {
            let document = try contentLoader.load(language: language)
            chapters = document.chapters
            window.title = strings.helpWindowTitle
            if !chapters.contains(where: { $0.id == selectedChapterID }) {
                selectedChapterID = chapters.contains { $0.id == "capture" }
                    ? "capture"
                    : chapters.first?.id
            }
            window.contentView = makeSplitContent(contentView)
            isShowingError = false
            renderSelectedChapter()
        } catch {
            window.title = strings.helpWindowTitle
            window.contentView = makeSplitContent(contentView)
            contentView.renderError(strings.helpLoadFailed)
            isShowingError = true
            navigationButtons.values.forEach { $0.isEnabled = false }
        }
    }

    private func makeSplitContent(_ helpContentView: HelpContentView) -> NSView {
        let rootFrame = window?.contentLayoutRect
            ?? NSRect(x: 0, y: 0, width: 980, height: 700)
        let root = NSView(frame: rootFrame)
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 760),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: 512)
        ])

        let sidebar = HelpSidebarView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.onEffectiveAppearanceChange = { [weak self] in
            self?.refreshNavigationAppearance()
        }
        sidebar.refreshBackground()
        sidebarView = sidebar

        let navigationStack = HelpNavigationStackView()
        navigationStack.translatesAutoresizingMaskIntoConstraints = false
        navigationStack.orientation = .vertical
        navigationStack.alignment = .leading
        navigationStack.spacing = 6
        navigationStack.setAccessibilityRole(.group)
        self.navigationStack = navigationStack

        navigationButtons = [:]
        navigationIndicatorViews = [:]
        hasInitializedNavigationSelection = false
        for chapter in chapters {
            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false

            let indicator = NSView()
            indicator.identifier = NSUserInterfaceItemIdentifier(
                "\(chapter.id)-indicator"
            )
            indicator.translatesAutoresizingMaskIntoConstraints = false
            indicator.wantsLayer = true
            indicator.isHidden = true
            indicator.setAccessibilityElement(false)

            let button = HelpNavigationButton(
                title: chapter.navigationTitle,
                target: self,
                action: #selector(selectNavigationButton(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(chapter.id)
            button.setButtonType(.momentaryChange)
            button.setAccessibilityRole(.button)
            button.isBordered = false
            button.image = nil
            button.imagePosition = .noImage
            button.alignment = .left
            button.contentTintColor = .labelColor
            if let cell = button.cell as? NSButtonCell {
                cell.showsStateBy = []
                cell.highlightsBy = .contentsCellMask
            }
            button.translatesAutoresizingMaskIntoConstraints = false

            row.addSubview(indicator)
            row.addSubview(button)
            navigationStack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: navigationStack.widthAnchor),
                row.heightAnchor.constraint(equalToConstant: 34),
                indicator.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                indicator.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                indicator.widthAnchor.constraint(equalToConstant: 3),
                indicator.heightAnchor.constraint(
                    equalTo: button.heightAnchor,
                    constant: -10
                ),
                button.leadingAnchor.constraint(
                    equalTo: indicator.trailingAnchor,
                    constant: 8
                ),
                button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                button.topAnchor.constraint(equalTo: row.topAnchor),
                button.bottomAnchor.constraint(equalTo: row.bottomAnchor)
            ])
            navigationButtons[chapter.id] = button
            navigationIndicatorViews[chapter.id] = indicator
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

    private func startObservingSystemAppearance() {
        workspaceAppearanceObserver = NSWorkspace.shared.notificationCenter
            .addObserver(
                forName: NSWorkspace
                    .accessibilityDisplayOptionsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.systemAppearanceDidChange()
                }
            }
        systemColorsObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.systemAppearanceDidChange()
            }
        }
    }

    private func systemAppearanceDidChange() {
        applySystemAppearance()
        let callback = test_onNextSystemAppearanceRefresh
        test_onNextSystemAppearanceRefresh = nil
        callback?(Thread.isMainThread)
    }

    private func applySystemAppearance(
        increaseContrast: Bool = NSWorkspace.shared
            .accessibilityDisplayShouldIncreaseContrast,
        accentColor: NSColor = .controlAccentColor
    ) {
        contentView?.applySystemAppearance(
            increaseContrast: increaseContrast
        )
        refreshNavigationAppearance(accentColor: accentColor)
    }

    private func refreshNavigationAppearance(
        accentColor: NSColor = .controlAccentColor
    ) {
        sidebarView?.refreshBackground()
        navigationIndicatorViews.values.forEach { indicator in
            indicator.layer?.backgroundColor = resolvedCGColor(
                accentColor,
                for: indicator.effectiveAppearance
            )
        }
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
        var didChangeSelection = false
        for (chapterID, button) in navigationButtons {
            let isSelected = chapterID == selectedChapterID
            let wasSelected = (button as? HelpNavigationButton)?.isCurrent
                ?? button.isAccessibilitySelected()
            button.state = isSelected ? .on : .off
            button.font = .systemFont(
                ofSize: 14,
                weight: isSelected ? .semibold : .regular
            )
            button.setAccessibilitySelected(isSelected)
            (button as? HelpNavigationButton)?.isCurrent = isSelected
            navigationIndicatorViews[chapterID]?.isHidden = !isSelected

            guard hasInitializedNavigationSelection, wasSelected != isSelected else {
                continue
            }
            didChangeSelection = true
            NSAccessibility.post(element: button, notification: .valueChanged)
        }

        let selectedButton = selectedChapterID.flatMap {
            navigationButtons[$0]
        }
        let selectedButtons = selectedButton.map { [$0] } ?? []
        navigationStack?.selectedButtons = selectedButtons
        navigationStack?.setAccessibilitySelectedChildren(selectedButtons)
        if hasInitializedNavigationSelection, didChangeSelection,
           let navigationStack {
            NSAccessibility.post(
                element: navigationStack,
                notification: .selectedChildrenChanged
            )
        }
        hasInitializedNavigationSelection = true
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

@MainActor
private final class HelpSidebarView: NSView {
    var onEffectiveAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackground()
        onEffectiveAppearanceChange?()
    }

    func refreshBackground() {
        wantsLayer = true
        layer?.backgroundColor = resolvedCGColor(
            .windowBackgroundColor,
            for: effectiveAppearance
        )
    }
}

private func resolvedCGColor(
    _ color: NSColor,
    for appearance: NSAppearance
) -> CGColor {
    var resolvedColor: CGColor?
    appearance.performAsCurrentDrawingAppearance {
        resolvedColor = color.cgColor
    }
    guard let resolvedColor else {
        preconditionFailure("Appearance color resolution did not execute")
    }
    return resolvedColor
}

@MainActor
private final class HelpNavigationStackView: NSStackView {
    var selectedButtons: [NSButton] = []

    override func accessibilityAttributeNames() -> [NSAccessibility.Attribute] {
        var attributes = super.accessibilityAttributeNames()
        if !attributes.contains(.selectedChildren) {
            attributes.append(.selectedChildren)
        }
        return attributes
    }

    override func accessibilityAttributeValue(
        _ attribute: NSAccessibility.Attribute
    ) -> Any? {
        if attribute == .selectedChildren {
            return selectedButtons
        }
        return super.accessibilityAttributeValue(attribute)
    }
}

@MainActor
private final class HelpNavigationButton: NSButton {
    var isCurrent = false

    override func accessibilityAttributeNames() -> [NSAccessibility.Attribute] {
        var attributes = super.accessibilityAttributeNames()
        attributes.removeAll { $0 == .value }
        if !attributes.contains(.selected) {
            attributes.append(.selected)
        }
        return attributes
    }

    override func accessibilityAttributeValue(
        _ attribute: NSAccessibility.Attribute
    ) -> Any? {
        if attribute == .selected {
            return isCurrent
        }
        if attribute == .value {
            return nil
        }
        return super.accessibilityAttributeValue(attribute)
    }
}
