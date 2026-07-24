import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let captureCoordinator: CaptureCoordinator
    private let settingsStore: any AppSettingsStoring
    private let hotKeyController: CaptureHotKeyController
    private let updateChecker: any UpdateChecking
    private let showPreferences: (PreferencesSection) -> Void
    private let statusItem: NSStatusItem

    init(
        captureCoordinator: CaptureCoordinator,
        settingsStore: any AppSettingsStoring,
        hotKeyController: CaptureHotKeyController,
        updateChecker: any UpdateChecking,
        showPreferences: @escaping (PreferencesSection) -> Void
    ) {
        self.captureCoordinator = captureCoordinator
        self.settingsStore = settingsStore
        self.hotKeyController = hotKeyController
        self.updateChecker = updateChecker
        self.showPreferences = showPreferences
        statusItem = NSStatusBar.system.statusItem(withLength: 92)
        super.init()
        configureStatusItem()
    }

    @objc func capture() {
        captureCoordinator.startCapture()
    }

    @objc func teachingPen() {
        captureCoordinator.toggleTeachingPen()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc func openPreferences() {
        showPreferences(.general)
    }

    @objc func openAbout() {
        showPreferences(.about)
    }

    @objc func checkForUpdates() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.updateChecker.checkForUpdates()
            let strings = PreferencesStrings(language: self.settingsStore.load().language)
            let alert = NSAlert()
            alert.messageText = strings.upToDate
            alert.informativeText = "XxSnap \(self.versionText)"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
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
            title: strings.teachingPen,
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
            title: strings.aboutXxSnap,
            action: #selector(openAbout),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: strings.quit, action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        for item in menu.items where item.action != nil {
            item.target = self
        }

        statusItem.menu = menu
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

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "0"
        return "\(version) (\(build))"
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
