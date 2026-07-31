import AppKit

#if DEBUG
struct CommercialRuntimeContext {
    let environment: [String: String]
    let hasXCTestRuntime: Bool

    var isXCTestHost: Bool {
        environment["XCTestConfigurationFilePath"] != nil && hasXCTestRuntime
    }

    static var current: CommercialRuntimeContext {
        let hasXCTestCase = NSClassFromString("XCTestCase") != nil
        let hasLoadedTestBundle = Bundle.allBundles.contains {
            $0.bundleURL.pathExtension == "xctest"
        }
        return CommercialRuntimeContext(
            environment: ProcessInfo.processInfo.environment,
            hasXCTestRuntime: hasXCTestCase && hasLoadedTestBundle
        )
    }
}
#endif

@MainActor
struct CommercialLaunchDependencies {
    typealias ProductionFactory = @MainActor () throws -> any CommercialAccessRefreshing

    let access: any CommercialAccessProviding
    private let refreshHandler: @MainActor () async -> Void

    static func make(
        productionFactory: ProductionFactory = { try CommercialAccessController() }
    ) -> CommercialLaunchDependencies {
#if DEBUG
        return make(
            runtimeContext: .current,
            productionFactory: productionFactory
        )
#else
        return makeProduction(productionFactory: productionFactory)
#endif
    }

#if DEBUG
    static func make(
        runtimeContext: CommercialRuntimeContext,
        productionFactory: ProductionFactory
    ) -> CommercialLaunchDependencies {
        if runtimeContext.isXCTestHost {
            return CommercialLaunchDependencies(
                access: UnrestrictedCommercialAccess.shared,
                refreshHandler: {}
            )
        }
        return makeProduction(productionFactory: productionFactory)
    }
#endif

    private static func makeProduction(
        productionFactory: ProductionFactory
    ) -> CommercialLaunchDependencies {
        guard let controller = try? productionFactory() else {
            return CommercialLaunchDependencies(
                access: UnavailableCommercialAccess(),
                refreshHandler: {}
            )
        }
        return CommercialLaunchDependencies(
            access: controller,
            refreshHandler: { await controller.refresh() }
        )
    }

    func refresh() async {
        await refreshHandler()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var captureCoordinator: CaptureCoordinator?
    private var statusItemController: StatusItemController?
    private var hotKeyController: CaptureHotKeyController?
    private var shortcutFeedbackPresentationController: ShortcutFeedbackPresentationController?
    private var systemShortcutMonitor: SystemShortcutMonitor?
    private var preferencesWindowController: PreferencesWindowController?
    private var helpWindowController: HelpWindowController?
    private var diagnosticSupportController: DiagnosticSupportController?
    private var settingsStore: SettingsStore?
    private var preferencesSettingsStore: PreferencesSettingsStore?
    private var commercialAccess: (any CommercialAccessProviding)?
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
        let commercialDependencies = CommercialLaunchDependencies.make()
        let commercialAccess = commercialDependencies.access
        let captureCoordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            settingsStore: settingsStore,
            preferencesSettingsStore: preferencesSettingsStore,
            filenameProvider: filenameProvider,
            diagnosticLogger: diagnosticLogStore,
            commercialAccess: commercialAccess
        )
        self.settingsStore = settingsStore
        self.preferencesSettingsStore = preferencesSettingsStore
        self.captureCoordinator = captureCoordinator
        self.commercialAccess = commercialAccess
        let helpWindowController = HelpWindowController(settingsStore: settingsStore)
        self.helpWindowController = helpWindowController
        let shortcutFeedbackPresentationController = ShortcutFeedbackPresentationController(
            settingsStore: preferencesSettingsStore
        )
        self.shortcutFeedbackPresentationController = shortcutFeedbackPresentationController
        captureCoordinator.shortcutFeedbackDidRequest = {
            [weak shortcutFeedbackPresentationController] event in
            shortcutFeedbackPresentationController?.show(
                HotKeyFormatter.settings(from: event)
            )
        }
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
            hotKeyFeedbackHandler: { [weak shortcutFeedbackPresentationController] settings in
                shortcutFeedbackPresentationController?.show(settings)
            },
            teachingPenHandler: {
                captureCoordinator.toggleTeachingPen()
            },
            restorePinnedImageHandler: {
                captureCoordinator.restoreMostRecentlyHiddenPinnedWindow()
            }
        )
        self.hotKeyController = hotKeyController
        let systemShortcutMonitor = SystemShortcutMonitor(
            settingsStore: preferencesSettingsStore,
            shouldIgnore: { [weak hotKeyController] settings in
                hotKeyController?.isRegistered(settings) == true
            }
        )
        systemShortcutMonitor.onShortcutPressed = {
            [weak shortcutFeedbackPresentationController] settings in
            shortcutFeedbackPresentationController?.showSystemShortcut(settings)
        }
        systemShortcutMonitor.refresh()
        self.systemShortcutMonitor = systemShortcutMonitor
        let preferencesWindowController = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: preferencesSettingsStore,
            hotKeyController: hotKeyController,
            launchAtLoginManager: LaunchAtLoginManager(),
            updateChecker: updateChecker,
            systemShortcutMonitor: systemShortcutMonitor
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
            },
            commercialAccess: commercialAccess
        )
        self.statusItemController = statusItemController

        commercialAccess.onStateChange = {
            [weak captureCoordinator, weak statusItemController] _ in
            captureCoordinator?.commercialAccessDidChange()
            statusItemController?.refresh()
        }
        Task { @MainActor in
            await commercialDependencies.refresh()
        }

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

    func applicationDidBecomeActive(_ notification: Notification) {
        systemShortcutMonitor?.refresh()
        preferencesWindowController?.refresh()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("xxsnap applicationWillTerminate")
        systemShortcutMonitor?.stop()
        diagnosticLogStore.record(
            category: .application,
            level: .info,
            event: "application_will_terminate"
        )
        diagnosticLogStore.flush()
    }
}
