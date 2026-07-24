import AppKit

enum PreferencesSection: String, CaseIterable {
    case general
    case shortcuts
    case save
    case update
    case about
}

@MainActor
final class PreferencesWindowController: NSWindowController, NSToolbarDelegate, NSTextFieldDelegate {
    var onLanguageChanged: ((AppLanguage) -> Void)?

    private let settingsStore: any AppSettingsStoring
    private let preferencesSettingsStore: any PreferencesSettingsStoring
    private let hotKeyController: CaptureHotKeyController
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let updateChecker: any UpdateChecking
    private let filenameRenderer = FilenameTemplateRenderer()

    private var selectedSection: PreferencesSection = .general
    private var filenameTemplateField: NSTextField?
    private var filenamePreviewLabel: NSTextField?
    private var filenameErrorLabel: NSTextField?
    private var updateStatusText: String?

    init(
        settingsStore: any AppSettingsStoring,
        preferencesSettingsStore: any PreferencesSettingsStoring,
        hotKeyController: CaptureHotKeyController,
        launchAtLoginManager: any LaunchAtLoginManaging,
        updateChecker: any UpdateChecking
    ) {
        self.settingsStore = settingsStore
        self.preferencesSettingsStore = preferencesSettingsStore
        self.hotKeyController = hotKeyController
        self.launchAtLoginManager = launchAtLoginManager
        self.updateChecker = updateChecker

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.animationBehavior = .documentWindow
        window.center()
        super.init(window: window)
        configureToolbar()
        rebuildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(section: PreferencesSection = .general) {
        selectedSection = section
        rebuildContent()
        window?.toolbar?.selectedItemIdentifier = toolbarIdentifier(for: section)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func refresh() {
        configureToolbar()
        rebuildContent()
    }

    private var strings: PreferencesStrings {
        PreferencesStrings(language: settingsStore.load().language)
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: "xxsnap.preferences.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .preference
        toolbar.selectedItemIdentifier = toolbarIdentifier(for: selectedSection)
    }

    private func rebuildContent() {
        guard let window else { return }
        window.title = strings.windowTitle
        window.contentView = makePage(for: selectedSection)
        window.toolbar?.selectedItemIdentifier = toolbarIdentifier(for: selectedSection)
    }

    private func makePage(for section: PreferencesSection) -> NSView {
        switch section {
        case .general:
            return makeGeneralPage()
        case .shortcuts:
            return makeShortcutsPage()
        case .save:
            return makeSavePage()
        case .update:
            return makeUpdatePage()
        case .about:
            return makeAboutPage()
        }
    }

    private func makeGeneralPage() -> NSView {
        let launchSwitch = NSSwitch()
        launchSwitch.target = self
        launchSwitch.action = #selector(toggleLaunchAtLogin(_:))

        let launchStatus = NSTextField(wrappingLabelWithString: "")
        launchStatus.textColor = .secondaryLabelColor
        launchStatus.font = .systemFont(ofSize: 12)
        launchStatus.maximumNumberOfLines = 2

        let systemSettingsButton = NSButton(
            title: strings.openSystemSettings,
            target: self,
            action: #selector(openLoginItemSettings)
        )
        systemSettingsButton.bezelStyle = .rounded
        systemSettingsButton.isHidden = true

        switch launchAtLoginManager.status {
        case .enabled:
            launchSwitch.state = .on
        case .notRegistered:
            launchSwitch.state = .off
        case .requiresApproval:
            launchSwitch.state = .off
            launchStatus.stringValue = strings.needsApproval
            systemSettingsButton.isHidden = false
        case .notFound:
            launchSwitch.state = .off
            launchSwitch.isEnabled = false
            launchStatus.stringValue = strings.serviceUnavailable
        }

        let launchControls = NSStackView(views: [launchSwitch])
        launchControls.orientation = .vertical
        launchControls.alignment = .trailing

        let languagePopup = NSPopUpButton()
        languagePopup.addItems(withTitles: ["English", "中文"])
        languagePopup.selectItem(at: settingsStore.load().language == .english ? 0 : 1)
        languagePopup.target = self
        languagePopup.action = #selector(changeLanguage(_:))
        languagePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true

        let page = makeStandardPage(
            rows: [
                makeRow(
                    title: strings.launchAtLogin,
                    detail: strings.launchAtLoginDetail,
                    control: launchControls
                ),
                makeRow(
                    title: strings.languageTitle,
                    detail: strings.languageDetail,
                    control: languagePopup
                )
            ]
        )

        if !launchStatus.stringValue.isEmpty || !systemSettingsButton.isHidden {
            let statusRow = NSStackView(views: [launchStatus, systemSettingsButton])
            statusRow.orientation = .horizontal
            statusRow.alignment = .centerY
            statusRow.spacing = 10
            statusRow.distribution = .fill
            addFooter(statusRow, to: page)
        }
        return page
    }

    private func makeShortcutsPage() -> NSView {
        let captureRow = makeShortcutRow(
            action: .capture,
            title: strings.captureShortcut,
            detail: strings.captureShortcutDetail
        )
        let captureTextRow = makeShortcutRow(
            action: .recognizeText,
            title: strings.captureText,
            detail: strings.captureTextShortcutDetail
        )
        let teachingPenRow = makeShortcutRow(
            action: .teachingPen,
            title: strings.teachingPen,
            detail: strings.teachingPenShortcutDetail
        )
        let restoreRow = makeShortcutRow(
            action: .restoreMostRecentlyHiddenPinnedImage,
            title: strings.restorePinShortcut,
            detail: strings.restorePinShortcutDetail
        )
        let page = makeStandardPage(rows: [captureRow, captureTextRow, teachingPenRow, restoreRow])

        let resetButton = NSButton(
            title: strings.resetShortcuts,
            target: self,
            action: #selector(resetShortcuts)
        )
        resetButton.bezelStyle = .rounded
        resetButton.isEnabled = !hotKeyController.isCaptureSessionActive

        let footerViews: [NSView]
        if hotKeyController.isCaptureSessionActive {
            footerViews = [secondaryLabel(strings.captureInProgress), resetButton]
        } else {
            footerViews = [NSView(), resetButton]
        }
        let footer = NSStackView(views: footerViews)
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .fill
        addFooter(footer, to: page)
        return page
    }

    private func makeShortcutRow(
        action: HotKeyAction,
        title: String,
        detail: String
    ) -> NSView {
        let isAssigned = hotKeyController.isHotKeyEnabled(for: action)
        let displayValue = isAssigned
            ? HotKeyFormatter.displayString(hotKeyController.configuredHotKey(for: action))
            : nil
        let recorder = ShortcutRecorderControl(
            shortcutTitle: displayValue,
            placeholderTitle: strings.recordShortcut,
            recordingTitle: strings.recording,
            clearToolTip: strings.clearShortcut
        )
        recorder.identifier = NSUserInterfaceItemIdentifier("shortcutRecorderControl")
        recorder.isEnabled = !hotKeyController.isCaptureSessionActive
        recorder.widthAnchor.constraint(equalToConstant: 258).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 42).isActive = true
        recorder.onClear = { [weak self] in
            guard let self else { return }
            let result = self.hotKeyController.disable(action)
            if case .failure(let error) = result {
                self.presentHotKeyError(error)
            }
            self.refresh()
        }
        recorder.onCancel = { [weak self] in
            self?.refresh()
        }
        recorder.onRecorded = { [weak self] settings in
            guard let self else { return }
            let result = self.hotKeyController.apply(settings, to: action)
            if case .failure(let error) = result {
                self.presentHotKeyError(error)
            }
            self.refresh()
        }

        let row = makeRow(title: title, detail: detail, control: recorder)
        row.identifier = NSUserInterfaceItemIdentifier("shortcutRow")
        if let error = hotKeyController.errors[action] {
            row.toolTip = localizedHotKeyError(error)
        }
        return row
    }

    private func makeSavePage() -> NSView {
        let settings = preferencesSettingsStore.load()
        let field = NSTextField(string: settings.filenameTemplate)
        field.identifier = NSUserInterfaceItemIdentifier("filenameTemplateField")
        field.delegate = self
        field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        field.focusRingType = .default
        field.heightAnchor.constraint(equalToConstant: 32).isActive = true
        filenameTemplateField = field

        let titleLabel = NSTextField(labelWithString: strings.filenameTemplate)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        let detailLabel = secondaryLabel(strings.filenameTemplateDetail)
        let editor = NSStackView(views: [titleLabel, detailLabel, field])
        editor.orientation = .vertical
        editor.alignment = .leading
        editor.spacing = 3
        editor.setCustomSpacing(9, after: detailLabel)
        editor.edgeInsets = NSEdgeInsets(top: 13, left: 16, bottom: 14, right: 16)
        field.widthAnchor.constraint(equalTo: editor.widthAnchor, constant: -32).isActive = true

        let page = makeStandardPage(rows: [editor])

        let preview = secondaryLabel("")
        preview.identifier = NSUserInterfaceItemIdentifier("filenamePreviewLabel")
        preview.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        preview.textColor = .labelColor
        preview.lineBreakMode = .byCharWrapping
        preview.maximumNumberOfLines = 2
        filenamePreviewLabel = preview

        let error = secondaryLabel("")
        error.textColor = .systemRed
        error.maximumNumberOfLines = 2
        error.isHidden = true
        filenameErrorLabel = error

        let previewTitle = NSTextField(labelWithString: strings.filenamePreview)
        previewTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        previewTitle.textColor = .secondaryLabelColor

        let fileIcon = NSImageView()
        fileIcon.image = NSImage(
            systemSymbolName: "doc",
            accessibilityDescription: strings.filenamePreview
        )
        fileIcon.contentTintColor = .secondaryLabelColor
        fileIcon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        fileIcon.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let previewRow = NSStackView(views: [fileIcon, preview])
        previewRow.orientation = .horizontal
        previewRow.alignment = .centerY
        previewRow.spacing = 9

        let variables = secondaryLabel(strings.availableVariables)
        let previewPanel = NSStackView(views: [previewTitle, previewRow, error, variables])
        previewPanel.identifier = NSUserInterfaceItemIdentifier("filenamePreviewPanel")
        previewPanel.orientation = .vertical
        previewPanel.alignment = .leading
        previewPanel.spacing = 6
        previewPanel.setCustomSpacing(9, after: previewTitle)
        previewPanel.setCustomSpacing(10, after: previewRow)
        previewPanel.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        previewPanel.wantsLayer = true
        previewPanel.layer?.backgroundColor =
            NSColor.controlBackgroundColor.withAlphaComponent(0.46).cgColor
        previewPanel.layer?.borderColor =
            NSColor.separatorColor.withAlphaComponent(0.24).cgColor
        previewPanel.layer?.borderWidth = 1
        previewPanel.layer?.cornerRadius = 8
        previewRow.widthAnchor.constraint(equalTo: previewPanel.widthAnchor, constant: -28).isActive = true
        variables.widthAnchor.constraint(equalTo: previewPanel.widthAnchor, constant: -28).isActive = true
        addFooter(previewPanel, to: page)
        updateFilenamePreview(template: settings.filenameTemplate)
        return page
    }

    private func makeUpdatePage() -> NSView {
        let settings = preferencesSettingsStore.load()

        let launchSwitch = NSSwitch()
        launchSwitch.state = settings.checksForUpdatesAtLaunch ? .on : .off
        launchSwitch.target = self
        launchSwitch.action = #selector(toggleCheckAtLaunch(_:))

        let intervalPopup = NSPopUpButton()
        for interval in PreferencesSettings.allowedUpdateIntervals {
            intervalPopup.addItem(withTitle: "\(interval) \(strings.hourSuffix)")
            intervalPopup.lastItem?.tag = interval
        }
        intervalPopup.selectItem(withTag: settings.updateCheckIntervalHours)
        intervalPopup.target = self
        intervalPopup.action = #selector(changeUpdateInterval(_:))
        intervalPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true

        let page = makeStandardPage(
            rows: [
                makeRow(title: strings.checkAtLaunch, detail: nil, control: launchSwitch),
                makeRow(title: strings.checkInterval, detail: nil, control: intervalPopup)
            ]
        )

        let status = secondaryLabel(updateStatusText ?? "")
        status.textColor = .systemGreen
        let checkButton = NSButton(
            title: strings.checkNow,
            target: self,
            action: #selector(checkForUpdates)
        )
        checkButton.bezelStyle = .rounded
        let footer = NSStackView(views: [status, checkButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .fill
        addFooter(footer, to: page)
        return page
    }

    private func makeAboutPage() -> NSView {
        let root = makePageRoot()
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 88).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 88).isActive = true

        let appName = NSTextField(labelWithString: "XxSnap")
        appName.font = .systemFont(ofSize: 22, weight: .semibold)

        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "0"
        let version = secondaryLabel("\(strings.version) \(shortVersion) (\(build))")
        let copyright = secondaryLabel(strings.copyright)

        let contact = NSButton(
            title: "zfc.2012@gmail.com",
            target: self,
            action: #selector(openContactEmail)
        )
        contact.isBordered = false
        contact.contentTintColor = .linkColor
        contact.font = .systemFont(ofSize: 12)

        let stack = NSStackView(views: [icon, appName, version, copyright, contact])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 7
        stack.setCustomSpacing(15, after: version)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -8),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -32)
        ])
        return root
    }

    private func makeStandardPage(rows: [NSView]) -> NSView {
        let root = makePageRoot()

        let group = NSStackView()
        group.identifier = NSUserInterfaceItemIdentifier("preferencesGroup")
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 0
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = makeSeparator()
                group.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
            }
            group.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        }
        group.wantsLayer = true
        group.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        group.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.38).cgColor
        group.layer?.borderWidth = 1
        group.layer?.cornerRadius = 8
        group.layer?.masksToBounds = true

        let stack = NSStackView(views: [group])
        stack.identifier = NSUserInterfaceItemIdentifier("pageStack")
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24),
            group.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return root
    }

    private func makeRow(title: String, detail: String?, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2

        let labels: NSStackView
        if let detail {
            let detailLabel = secondaryLabel(detail)
            detailLabel.alignment = .left
            detailLabel.maximumNumberOfLines = 2
            labels = NSStackView(views: [titleLabel, detailLabel])
            labels.orientation = .vertical
            labels.alignment = .leading
            labels.spacing = 3
        } else {
            labels = NSStackView(views: [titleLabel])
            labels.orientation = .vertical
            labels.alignment = .leading
        }

        let row = NSStackView(views: [labels, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 20
        row.edgeInsets = NSEdgeInsets(top: 11, left: 16, bottom: 11, right: 16)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    private func addFooter(_ footer: NSView, to page: NSView) {
        guard let stack = page.subviews.first(where: {
            $0.identifier?.rawValue == "pageStack"
        }) as? NSStackView else { return }
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
    }

    private func makePageRoot() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        return root
    }

    private func makeSeparator() -> NSView {
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func secondaryLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSSwitch) {
        sender.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.launchAtLoginManager.setEnabled(sender.state == .on)
            } catch {
                self.presentError(error.localizedDescription)
            }
            self.refresh()
        }
    }

    @objc private func openLoginItemSettings() {
        launchAtLoginManager.openSystemSettings()
    }

    @objc private func changeLanguage(_ sender: NSPopUpButton) {
        var settings = settingsStore.load()
        let previous = settings.language
        settings.language = sender.indexOfSelectedItem == 0 ? .english : .zhHans
        do {
            try settingsStore.save(settings)
            onLanguageChanged?(settings.language)
        } catch {
            sender.selectItem(at: previous == .english ? 0 : 1)
            presentError(strings.saveFailed)
        }
    }

    @objc private func resetShortcuts() {
        if case .failure(let error) = hotKeyController.restoreDefaults() {
            presentHotKeyError(error)
        }
        refresh()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === filenameTemplateField else { return }
        updateFilenamePreview(template: field.stringValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === filenameTemplateField else { return }
        do {
            _ = try filenameRenderer.filename(template: field.stringValue)
            var settings = preferencesSettingsStore.load()
            let previous = settings.filenameTemplate
            settings.filenameTemplate = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                try preferencesSettingsStore.save(settings)
            } catch {
                field.stringValue = previous
                updateFilenamePreview(template: previous)
                presentError(strings.saveFailed)
            }
        } catch {
            filenameErrorLabel?.stringValue = strings.filenameTemplateError(error)
            filenameErrorLabel?.isHidden = false
        }
    }

    private func updateFilenamePreview(template: String) {
        do {
            let filename = try filenameRenderer.filename(template: template)
            filenamePreviewLabel?.stringValue = filename
            filenameErrorLabel?.stringValue = ""
            filenameErrorLabel?.isHidden = true
        } catch {
            filenamePreviewLabel?.stringValue = ""
            filenameErrorLabel?.stringValue = strings.filenameTemplateError(error)
            filenameErrorLabel?.isHidden = false
        }
    }

    @objc private func toggleCheckAtLaunch(_ sender: NSSwitch) {
        var settings = preferencesSettingsStore.load()
        let previous = settings
        settings.checksForUpdatesAtLaunch = sender.state == .on
        do {
            try preferencesSettingsStore.save(settings)
        } catch {
            sender.state = previous.checksForUpdatesAtLaunch ? .on : .off
            presentError(strings.saveFailed)
        }
    }

    @objc private func changeUpdateInterval(_ sender: NSPopUpButton) {
        var settings = preferencesSettingsStore.load()
        let previous = settings
        settings.updateCheckIntervalHours = sender.selectedTag()
        do {
            try preferencesSettingsStore.save(settings)
        } catch {
            sender.selectItem(withTag: previous.updateCheckIntervalHours)
            presentError(strings.saveFailed)
        }
    }

    @objc private func checkForUpdates() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.updateChecker.checkForUpdates()
            self.updateStatusText = self.strings.upToDate
            self.refresh()
        }
    }

    @objc private func openContactEmail() {
        guard let url = URL(string: "mailto:zfc.2012@gmail.com") else { return }
        NSWorkspace.shared.open(url)
    }

    private func presentHotKeyError(_ error: HotKeyConfigurationError) {
        let message: String
        switch error {
        case .captureInProgress:
            message = strings.captureInProgress
        case .missingModifier:
            message = strings.shortcutNeedsModifier
        case .duplicate:
            message = strings.shortcutConflict
        case .registrationFailed:
            message = strings.shortcutRegistrationFailed
        case .persistenceFailed:
            message = strings.saveFailed
        }
        presentError(message)
    }

    private func localizedHotKeyError(_ error: HotKeyConfigurationError) -> String {
        switch error {
        case .captureInProgress: return strings.captureInProgress
        case .missingModifier: return strings.shortcutNeedsModifier
        case .duplicate: return strings.shortcutConflict
        case .registrationFailed: return strings.shortcutRegistrationFailed
        case .persistenceFailed: return strings.saveFailed
        }
    }

    private func presentError(_ message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = strings.errorTitle
        alert.informativeText = message
        alert.beginSheetModal(for: window)
    }

    private func toolbarIdentifier(for section: PreferencesSection) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("xxsnap.preferences.\(section.rawValue)")
    }

    private func section(for identifier: NSToolbarItem.Identifier) -> PreferencesSection? {
        PreferencesSection.allCases.first(where: { toolbarIdentifier(for: $0) == identifier })
    }

    @objc private func selectToolbarItem(_ sender: NSToolbarItem) {
        guard let section = section(for: sender.itemIdentifier) else { return }
        selectedSection = section
        rebuildContent()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        PreferencesSection.allCases.map(toolbarIdentifier(for:))
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let section = section(for: itemIdentifier) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        item.action = #selector(selectToolbarItem(_:))
        switch section {
        case .general:
            item.label = strings.general
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: strings.general)
        case .shortcuts:
            item.label = strings.shortcuts
            item.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: strings.shortcuts)
        case .save:
            item.label = strings.save
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: strings.save)
        case .update:
            item.label = strings.update
            item.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: strings.update)
        case .about:
            item.label = strings.about
            item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: strings.about)
        }
        return item
    }
}

@MainActor
private final class ShortcutRecorderControl: NSView {
    var onRecorded: ((HotKeySettings) -> Void)?
    var onCancel: (() -> Void)?
    var onClear: (() -> Void)?

    var isEnabled = true {
        didSet {
            recorderButton.isEnabled = isEnabled
            clearButton.isEnabled = isEnabled
        }
    }

    private let recorderButton: ShortcutRecorderButton
    private let clearButton: NSButton
    private let hasShortcut: Bool

    init(
        shortcutTitle: String?,
        placeholderTitle: String,
        recordingTitle: String,
        clearToolTip: String
    ) {
        hasShortcut = shortcutTitle != nil
        recorderButton = ShortcutRecorderButton(
            title: shortcutTitle ?? placeholderTitle,
            usesPlaceholderStyle: shortcutTitle == nil
        )
        clearButton = NSButton(
            image: NSImage(
                systemSymbolName: "xmark.circle.fill",
                accessibilityDescription: clearToolTip
            ) ?? NSImage(),
            target: nil,
            action: nil
        )
        super.init(frame: .zero)

        recorderButton.identifier = NSUserInterfaceItemIdentifier("shortcutRecorderButton")
        recorderButton.recordingTitle = recordingTitle
        recorderButton.onRecorded = { [weak self] settings in
            self?.onRecorded?(settings)
        }
        recorderButton.onCancel = { [weak self] in
            self?.onCancel?()
        }
        recorderButton.onRecordingStateChange = { [weak self] isRecording in
            guard let self else { return }
            self.clearButton.isHidden = isRecording || !self.hasShortcut
        }

        clearButton.identifier = NSUserInterfaceItemIdentifier("shortcutClearButton")
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.toolTip = clearToolTip
        clearButton.target = self
        clearButton.action = #selector(clearShortcut)
        clearButton.isHidden = !hasShortcut

        recorderButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(recorderButton)
        addSubview(clearButton)
        NSLayoutConstraint.activate([
            recorderButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            recorderButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            recorderButton.topAnchor.constraint(equalTo: topAnchor),
            recorderButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 24),
            clearButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func clearShortcut() {
        guard isEnabled, hasShortcut else { return }
        onClear?()
    }
}

@MainActor
private final class ShortcutRecorderButton: NSButton {
    var recordingTitle = "Press shortcut…"
    var onRecorded: ((HotKeySettings) -> Void)?
    var onCancel: (() -> Void)?
    var onRecordingStateChange: ((Bool) -> Void)?

    private let idleTitle: String
    private let usesPlaceholderStyle: Bool
    private var isRecording = false

    init(title: String, usesPlaceholderStyle: Bool) {
        idleTitle = title
        self.usesPlaceholderStyle = usesPlaceholderStyle
        super.init(frame: .zero)
        setDisplayedTitle(title, placeholder: usesPlaceholderStyle)
        bezelStyle = .rounded
        controlSize = .large
        focusRingType = .default
        target = self
        action = #selector(beginRecording)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        guard isEnabled else { return }
        isRecording = true
        setDisplayedTitle(recordingTitle, placeholder: true)
        onRecordingStateChange?(true)
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        record(event)
        return true
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == 53 {
            finishRecording()
            onCancel?()
            return
        }
        let settings = HotKeyFormatter.settings(from: event)
        finishRecording()
        onRecorded?(settings)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            finishRecording()
            onCancel?()
        }
        return super.resignFirstResponder()
    }

    private func finishRecording() {
        isRecording = false
        setDisplayedTitle(idleTitle, placeholder: usesPlaceholderStyle)
        onRecordingStateChange?(false)
    }

    private func setDisplayedTitle(_ value: String, placeholder: Bool) {
        title = value
        attributedTitle = NSAttributedString(
            string: value,
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: 16,
                    weight: placeholder ? .regular : .semibold
                ),
                .foregroundColor: placeholder
                    ? NSColor.placeholderTextColor
                    : NSColor.labelColor
            ]
        )
    }
}
