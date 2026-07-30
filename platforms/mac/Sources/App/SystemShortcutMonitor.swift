import AppKit
import CoreGraphics

@MainActor
protocol GlobalKeyEventSourcing: AnyObject {
    var onKeyDown: ((NSEvent) -> Void)? { get set }
    var isRunning: Bool { get }

    func start()
    func stop()
}

@MainActor
final class NSEventGlobalKeyEventSource: GlobalKeyEventSourcing {
    var onKeyDown: ((NSEvent) -> Void)?
    private(set) var isRunning = false

    private var monitorToken: Any?

    func start() {
        guard monitorToken == nil else { return }
        monitorToken = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            Task { @MainActor [weak self] in
                self?.onKeyDown?(event)
            }
        }
        isRunning = monitorToken != nil
    }

    func stop() {
        if let monitorToken {
            NSEvent.removeMonitor(monitorToken)
        }
        monitorToken = nil
        isRunning = false
    }

    deinit {
        if let monitorToken {
            NSEvent.removeMonitor(monitorToken)
        }
    }
}

@MainActor
protocol SystemShortcutPermissionProviding: AnyObject {
    var isGranted: Bool { get }

    @discardableResult
    func request() -> Bool
    func openSystemSettings()
}

@MainActor
final class InputMonitoringPermissionProvider: SystemShortcutPermissionProviding {
    var isGranted: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    func request() -> Bool {
        CGRequestListenEventAccess()
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
protocol SystemShortcutMonitoring: AnyObject {
    var hasPermission: Bool { get }
    var isMonitoring: Bool { get }

    @discardableResult
    func requestPermission() -> Bool
    func refresh()
    func stop()
    func openSystemSettings()
}

@MainActor
final class SystemShortcutMonitor: SystemShortcutMonitoring {
    var onShortcutPressed: ((HotKeySettings) -> Void)?

    var hasPermission: Bool {
        permissionProvider.isGranted
    }

    var isMonitoring: Bool {
        eventSource.isRunning
    }

    private let settingsStore: any PreferencesSettingsStoring
    private let eventSource: any GlobalKeyEventSourcing
    private let permissionProvider: any SystemShortcutPermissionProviding
    private let shouldIgnore: (HotKeySettings) -> Bool

    init(
        settingsStore: any PreferencesSettingsStoring,
        eventSource: (any GlobalKeyEventSourcing)? = nil,
        permissionProvider: (any SystemShortcutPermissionProviding)? = nil,
        shouldIgnore: @escaping (HotKeySettings) -> Bool = { _ in false }
    ) {
        self.settingsStore = settingsStore
        self.eventSource = eventSource ?? NSEventGlobalKeyEventSource()
        self.permissionProvider =
            permissionProvider ?? InputMonitoringPermissionProvider()
        self.shouldIgnore = shouldIgnore
        self.eventSource.onKeyDown = { [weak self] event in
            self?.handle(event)
        }
    }

    @discardableResult
    func requestPermission() -> Bool {
        let granted = permissionProvider.request()
        refresh()
        return granted
    }

    func refresh() {
        guard settingsStore.load().showsSystemShortcutFeedback,
              permissionProvider.isGranted
        else {
            eventSource.stop()
            return
        }
        eventSource.start()
    }

    func stop() {
        eventSource.stop()
    }

    func openSystemSettings() {
        permissionProvider.openSystemSettings()
    }

    func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let settings = HotKeyFormatter.settings(from: event)
        guard HotKeyFormatter.isDisplayableSystemShortcut(settings),
              !shouldIgnore(settings)
        else { return }
        onShortcutPressed?(settings)
    }
}
