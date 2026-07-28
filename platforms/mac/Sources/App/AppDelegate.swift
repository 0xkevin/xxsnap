import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var captureCoordinator: CaptureCoordinator?
    private var statusItemController: StatusItemController?
    private var hotKeyController: CaptureHotKeyController?
    private var preferencesWindowController: PreferencesWindowController?
    private var helpWindowController: HelpWindowController?
    private var diagnosticSupportController: DiagnosticSupportController?
    private var settingsStore: SettingsStore?
    private var preferencesSettingsStore: PreferencesSettingsStore?
    private let diagnosticLogStore = DiagnosticLogStore.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("xxsnap applicationDidFinishLaunching")
        diagnosticLogStore.performMaintenance()
        let appInfo = DiagnosticApplicationInfo.current()
        diagnosticLogStore.record(
            category: .application,
            level: .info,
            event: "application_started",
            metadata: [
                "app_build": appInfo.build,
                "app_version": appInfo.version,
            ]
        )
        ProcessInfo.processInfo.disableAutomaticTermination("xxsnap menu bar app stays available for capture")
        let settingsStore = SettingsStore()
        let preferencesSettingsStore = PreferencesSettingsStore()
        let filenameProvider = CaptureFilenameProvider(settingsStore: preferencesSettingsStore)
        let updateChecker = PlaceholderUpdateChecker()
        let captureCoordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            settingsStore: settingsStore,
            preferencesSettingsStore: preferencesSettingsStore,
            filenameProvider: filenameProvider,
            diagnosticLogger: diagnosticLogStore
        )
        self.settingsStore = settingsStore
        self.preferencesSettingsStore = preferencesSettingsStore
        self.captureCoordinator = captureCoordinator
        let helpWindowController = HelpWindowController(settingsStore: settingsStore)
        self.helpWindowController = helpWindowController
        let hotKeyController = CaptureHotKeyController(
            settingsStore: settingsStore,
            captureHandler: {
                captureCoordinator.startCapture()
            },
            fullScreenCaptureHandler: {
                captureCoordinator.startFullScreenCapture()
            },
            recognizeTextHandler: {
                captureCoordinator.startTextRecognition()
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
        let diagnosticSupportController = DiagnosticSupportController(
            logStore: diagnosticLogStore,
            exporter: DiagnosticBundleExporter(logStore: diagnosticLogStore),
            settingsStore: settingsStore
        )
        self.diagnosticSupportController = diagnosticSupportController
        let statusItemController = StatusItemController(
            captureCoordinator: captureCoordinator,
            settingsStore: settingsStore,
            hotKeyController: hotKeyController,
            updateChecker: updateChecker,
            showPreferences: { [weak preferencesWindowController] section in
                preferencesWindowController?.show(section: section)
            },
            showHelp: { [weak helpWindowController] in
                helpWindowController?.show()
            },
            exportDiagnostics: { [weak diagnosticSupportController] in
                diagnosticSupportController?.exportDiagnostics()
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
        diagnosticLogStore.record(
            category: .application,
            level: .info,
            event: "application_will_terminate"
        )
        diagnosticLogStore.flush()
    }
}
