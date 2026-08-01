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
    typealias SchedulerFactory = @MainActor (
        any CommercialAccessRefreshing
    ) -> any CommercialRefreshScheduling

    let access: any CommercialAccessProviding
    private let scheduler: any CommercialRefreshScheduling
    private let refreshHandler: @MainActor () async -> Void

    static func make(
        productionFactory: ProductionFactory = { try CommercialAccessController() },
        schedulerFactory: SchedulerFactory = { access in
            guard let controller = access as? any CommercialRefreshControlling else {
                return NoopCommercialRefreshScheduler()
            }
            return CommercialRefreshScheduler(controller: controller)
        }
    ) -> CommercialLaunchDependencies {
#if DEBUG
        return make(
            runtimeContext: .current,
            productionFactory: productionFactory,
            schedulerFactory: schedulerFactory
        )
#else
        return makeProduction(
            productionFactory: productionFactory,
            schedulerFactory: schedulerFactory
        )
#endif
    }

#if DEBUG
    static func make(
        runtimeContext: CommercialRuntimeContext,
        productionFactory: ProductionFactory,
        schedulerFactory: SchedulerFactory = { access in
            guard let controller = access as? any CommercialRefreshControlling else {
                return NoopCommercialRefreshScheduler()
            }
            return CommercialRefreshScheduler(controller: controller)
        }
    ) -> CommercialLaunchDependencies {
        if runtimeContext.isXCTestHost {
            return CommercialLaunchDependencies(
                access: UnrestrictedCommercialAccess.shared,
                scheduler: NoopCommercialRefreshScheduler(),
                refreshHandler: {}
            )
        }
        return makeProduction(
            productionFactory: productionFactory,
            schedulerFactory: schedulerFactory
        )
    }
#endif

    private static func makeProduction(
        productionFactory: ProductionFactory,
        schedulerFactory: SchedulerFactory
    ) -> CommercialLaunchDependencies {
        guard let controller = try? productionFactory() else {
            return CommercialLaunchDependencies(
                access: UnavailableCommercialAccess(),
                scheduler: NoopCommercialRefreshScheduler(),
                refreshHandler: {}
            )
        }
        return CommercialLaunchDependencies(
            access: controller,
            scheduler: schedulerFactory(controller),
            refreshHandler: { await controller.refresh() }
        )
    }

    func refresh() async { await refreshHandler() }
    func prepareFromCache() async { await scheduler.prepareFromCache() }
    func startRefresh() { scheduler.start() }
    func triggerRefresh() { scheduler.triggerRefresh() }
    func cancelRefresh() { scheduler.cancel() }
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
    private var commercialLaunchDependencies: CommercialLaunchDependencies?
    private var commercialLaunchTask: Task<Void, Never>?
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
        let commercialDependencies = CommercialLaunchDependencies.make(
            productionFactory: {
                try CommercialAccessController(diagnosticLogger: self.diagnosticLogStore)
            }
        )
        let commercialAccess = commercialDependencies.access
        self.commercialLaunchDependencies = commercialDependencies
        commercialLaunchTask = Task { @MainActor [weak self] in
            await commercialDependencies.prepareFromCache()
            guard let self, !Task.isCancelled else { return }
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
                systemShortcutMonitor: systemShortcutMonitor,
                commercialAccess: commercialAccess,
                commercialActions: commercialAccess as? any CommercialLicenseActing
            )
            self.preferencesWindowController = preferencesWindowController
            let purchaseRequest: (CommercialFeature) -> Void = { [weak preferencesWindowController] _ in
                Task { @MainActor in
                    preferencesWindowController?.showCommercialPurchaseIfAvailable()
                }
            }
            if let controller = commercialAccess as? CommercialAccessController {
                controller.purchaseRequestHandler = purchaseRequest
            } else if let unavailable = commercialAccess as? UnavailableCommercialAccess {
                unavailable.purchaseRequestHandler = purchaseRequest
            }
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

            let refreshController = commercialAccess as? CommercialAccessController
            commercialAccess.onStateChange = {
                [weak self, weak refreshController, weak captureCoordinator,
                 weak statusItemController, weak preferencesWindowController] state in
                captureCoordinator?.commercialAccessDidChange()
                statusItemController?.refresh()
                preferencesWindowController?.commercialAccessDidChange()
                if case .pro = state,
                   refreshController?.paidValidationContext?.lastSuccessfulValidation == nil {
                    self?.commercialLaunchDependencies?.triggerRefresh()
                }
            }
            if let controller = commercialAccess as? CommercialAccessController {
                controller.onPresentationChange = { [weak preferencesWindowController] in
                    preferencesWindowController?.commercialAccessDidChange()
                }
            }
            commercialDependencies.startRefresh()

            preferencesWindowController.onLanguageChanged = { [weak captureCoordinator, weak statusItemController, weak preferencesWindowController] language in
                captureCoordinator?.updateLanguage(language)
                statusItemController?.refresh()
                preferencesWindowController?.languageDidChange()
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        systemShortcutMonitor?.refresh()
        preferencesWindowController?.refresh()
        commercialLaunchDependencies?.triggerRefresh()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("xxsnap applicationWillTerminate")
        commercialLaunchTask?.cancel()
        commercialLaunchDependencies?.cancelRefresh()
        systemShortcutMonitor?.stop()
        diagnosticLogStore.record(
            category: .application,
            level: .info,
            event: "application_will_terminate"
        )
        diagnosticLogStore.flush()
    }
}
