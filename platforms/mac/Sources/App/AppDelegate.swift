import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var captureCoordinator: CaptureCoordinator?
    private var statusItemController: StatusItemController?
    private var hotKeyController: CaptureHotKeyController?
    private var preferencesWindowController: PreferencesWindowController?
    private var settingsStore: SettingsStore?
    private var preferencesSettingsStore: PreferencesSettingsStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("xxsnap applicationDidFinishLaunching")
        ProcessInfo.processInfo.disableAutomaticTermination("xxsnap menu bar app stays available for capture")
        let settingsStore = SettingsStore()
        let preferencesSettingsStore = PreferencesSettingsStore()
        let filenameProvider = CaptureFilenameProvider(settingsStore: preferencesSettingsStore)
        let updateChecker = PlaceholderUpdateChecker()
        let captureCoordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            settingsStore: settingsStore,
            filenameProvider: filenameProvider
        )
        self.settingsStore = settingsStore
        self.preferencesSettingsStore = preferencesSettingsStore
        self.captureCoordinator = captureCoordinator
        let hotKeyController = CaptureHotKeyController(
            settingsStore: settingsStore,
            captureHandler: {
                captureCoordinator.startCapture()
            },
            teachingPenHandler: {
                captureCoordinator.toggleTeachingPen()
            },
            restorePinnedImageHandler: {
                captureCoordinator.restoreMostRecentlyHiddenPinnedWindow()
            }
        )
        self.hotKeyController = hotKeyController
        let preferencesWindowController = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: preferencesSettingsStore,
            hotKeyController: hotKeyController,
            launchAtLoginManager: LaunchAtLoginManager(),
            updateChecker: updateChecker
        )
        self.preferencesWindowController = preferencesWindowController
        let statusItemController = StatusItemController(
            captureCoordinator: captureCoordinator,
            settingsStore: settingsStore,
            hotKeyController: hotKeyController,
            updateChecker: updateChecker,
            showPreferences: { [weak preferencesWindowController] section in
                preferencesWindowController?.show(section: section)
            }
        )
        self.statusItemController = statusItemController

        preferencesWindowController.onLanguageChanged = { [weak captureCoordinator, weak statusItemController, weak preferencesWindowController] language in
            captureCoordinator?.updateLanguage(language)
            statusItemController?.refresh()
            preferencesWindowController?.refresh()
        }
        hotKeyController.onStateChange = { [weak statusItemController, weak preferencesWindowController] in
            statusItemController?.refresh()
            preferencesWindowController?.refresh()
        }
        captureCoordinator.captureOverlayDidPresent = { [weak hotKeyController, weak preferencesWindowController] in
            hotKeyController?.setCaptureSessionActive(true)
            preferencesWindowController?.refresh()
        }
        captureCoordinator.captureSessionDidEnd = { [weak hotKeyController, weak preferencesWindowController] in
            hotKeyController?.setCaptureSessionActive(false)
            preferencesWindowController?.refresh()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("xxsnap applicationWillTerminate")
    }
}
