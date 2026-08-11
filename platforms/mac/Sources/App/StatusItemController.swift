import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let captureCoordinator: CaptureCoordinator
    private let settingsStore: any AppSettingsStoring
    private let hotKeyController: CaptureHotKeyController
    private let updateChecker: any UpdateChecking
    private let showPreferences: (PreferencesSection) -> Void
    private let showHelp: @MainActor () -> Void
    private let openURL: @MainActor (URL) -> Void
    private let exportDiagnosticsHandler: @MainActor () -> Void
    private let terminationHandler: @MainActor () -> Void
    private let statusItem: NSStatusItem
    private let commercialAccess: any CommercialAccessProviding

    init(
        captureCoordinator: CaptureCoordinator,
        settingsStore: any AppSettingsStoring,
        hotKeyController: CaptureHotKeyController,
        updateChecker: any UpdateChecking,
        showPreferences: @escaping (PreferencesSection) -> Void,
        showHelp: @escaping @MainActor () -> Void,
        openURL: @escaping @MainActor (URL) -> Void = { url in
            _ = NSWorkspace.shared.open(url)
        },
        exportDiagnostics: @escaping @MainActor () -> Void = {},
        commercialAccess: (any CommercialAccessProviding)? = nil,
        terminationHandler: @escaping @MainActor () -> Void = {
            NSApplication.shared.terminate(nil)
        }
    ) {
        self.captureCoordinator = captureCoordinator
        self.settingsStore = settingsStore
        self.hotKeyController = hotKeyController
        self.updateChecker = updateChecker
        self.showPreferences = showPreferences
        self.showHelp = showHelp
        self.openURL = openURL
        self.exportDiagnosticsHandler = exportDiagnostics
        self.commercialAccess = commercialAccess ?? UnrestrictedCommercialAccess.shared
        self.terminationHandler = terminationHandler
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
    }

    @objc func capture() {
        guard allowCoreAction() else { return }
        captureCoordinator.startCapture()
    }

    @objc func fullScreenCapture() {
        guard allowCoreAction() else { return }
        captureCoordinator.startFullScreenCapture()
    }

    @objc func captureText() {
        guard allowCoreAction() else { return }
        captureCoordinator.startTextRecognition()
    }

    @objc func teachingPen() {
        guard allowCoreAction() else { return }
        captureCoordinator.toggleTeachingPen()
    }

    @objc func quit() {
        terminationHandler()
    }

    @objc func openPreferences() {
        showPreferences(.general)
    }

    @objc func openAbout() {
        showPreferences(.about)
    }

    @objc func openDonation() {
        showPreferences(.donation)
    }

    @objc func openHelp() {
        showHelp()
    }

    @objc func openGitHubFeedback() {
        guard let url = URL(string: "https://github.com/0xkevin/xxsnap/issues/new/choose") else {
            return
        }
        openURL(url)
    }

    @objc func exportDiagnostics() {
        exportDiagnosticsHandler()
    }

    @objc func checkForUpdates() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.updateChecker.checkForUpdates()
            self.updateChecker.presentUpdateResult(result, manual: true)
        }
    }

    func refresh() {
        configureStatusItem()
    }

    private func configureStatusItem() {
        NSLog("xxsnap configuring status item")
        statusItem.length = NSStatusItem.squareLength

        guard let button = statusItem.button else {
            NSLog("xxsnap status item has no button")
            return
        }

        button.title = ""
        let image = statusBarImage()
        button.image = image
        button.imagePosition = .imageOnly
        let strings = PreferencesStrings(language: settingsStore.load().language)
        button.toolTip = strings.appTooltip
        NSLog("xxsnap status button configured image=%@ length=%.0f", image == nil ? "missing" : "ok", statusItem.length)

        let menu = NSMenu()
        menu.addItem(makeHotKeyMenuItem(
            title: strings.capture,
            action: #selector(capture),
            hotKeyAction: .capture
        ))
        menu.addItem(makeHotKeyMenuItem(
            title: strings.fullScreenCapture,
            action: #selector(fullScreenCapture),
            hotKeyAction: .fullScreenCapture
        ))
        menu.addItem(makeHotKeyMenuItem(
            title: commercialTitle(strings.captureText, feature: .ocr),
            action: #selector(captureText),
            hotKeyAction: .recognizeText
        ))
        menu.addItem(makeHotKeyMenuItem(
            title: commercialTitle(strings.teachingPen, feature: .teachingPen),
            action: #selector(teachingPen),
            hotKeyAction: .teachingPen
        ))
        menu.addItem(.separator())
        let preferencesItem = NSMenuItem(
            title: strings.preferences,
            action: #selector(openPreferences),
            keyEquivalent: ""
        )
        menu.addItem(preferencesItem)
        menu.addItem(NSMenuItem(
            title: strings.checkForUpdates,
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: strings.supportDeveloper,
            action: #selector(openDonation),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: strings.help,
            action: #selector(openHelp),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: strings.githubFeedback,
            action: #selector(openGitHubFeedback),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: strings.exportDiagnostics,
            action: #selector(exportDiagnostics),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: strings.aboutXxSnap,
            action: #selector(openAbout),
            keyEquivalent: ""
        ))
        let quitItem = NSMenuItem(title: strings.quit, action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        for item in menu.items where item.action != nil {
            item.target = self
        }

        statusItem.menu = menu
    }

    var test_menuItems: [NSMenuItem] {
        statusItem.menu?.items ?? []
    }

    var test_statusItemLength: CGFloat {
        statusItem.length
    }

    var test_statusButtonIsEnabled: Bool {
        statusItem.button?.isEnabled == true
    }

    private func makeHotKeyMenuItem(
        title: String,
        action: Selector,
        hotKeyAction: HotKeyAction
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if let registered = hotKeyController.registeredHotKey(for: hotKeyAction),
           let equivalent = HotKeyFormatter.menuEquivalent(registered) {
            item.keyEquivalent = equivalent.0
            item.keyEquivalentModifierMask = equivalent.1
        }
        return item
    }

    private func commercialTitle(_ title: String, feature: CommercialFeature) -> String {
        commercialAccess.snapshot.showsProBadge(for: feature) ? "\(title)  PRO" : title
    }

    private func allowCoreAction() -> Bool {
        guard !updateChecker.blocksAppUse else {
            updateChecker.presentRequiredUpdate()
            return false
        }
        return true
    }

    private func statusBarImage() -> NSImage? {
        let image = Bundle.main.url(forResource: "xxsnap", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(named: "xxsnap")
            ?? NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "xxsnap")
            ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "xxsnap")

        image?.accessibilityDescription = "xxsnap"
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        return image
    }
}
