import AppKit
import ApplicationServices

protocol ScrollEventMonitorRegistering: AnyObject {
    func addLocal(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any
    func addGlobal(_ handler: @escaping (NSEvent) -> Void) -> Any?
    func addGlobalKeyDown(_ handler: @escaping (NSEvent) -> Void) -> Any?
    func remove(_ monitor: Any)
}

private final class AppKitScrollEventMonitorRegistrar: ScrollEventMonitorRegistering {
    func addLocal(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: handler)!
    }

    func addGlobal(_ handler: @escaping (NSEvent) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: handler)
    }

    func addGlobalKeyDown(_ handler: @escaping (NSEvent) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    func remove(_ monitor: Any) { NSEvent.removeMonitor(monitor) }
}

@MainActor
protocol ScrollActivityMonitoring: AnyObject {
    func start(_ callback: @escaping @MainActor () -> Void)
    func start(
        onScrollActivity: @escaping @MainActor () -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    )
    func stop()
}

extension ScrollActivityMonitoring {
    func start(
        onScrollActivity: @escaping @MainActor () -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    ) {
        start(onScrollActivity)
    }
}

@MainActor
final class ScrollActivityMonitor: ScrollActivityMonitoring {
    private let registrar: any ScrollEventMonitorRegistering
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var globalKeyMonitor: Any?

    init(registrar: any ScrollEventMonitorRegistering = AppKitScrollEventMonitorRegistrar()) {
        self.registrar = registrar
    }

    func start(_ callback: @escaping @MainActor () -> Void) {
        start(onScrollActivity: callback, onTerminalCommand: { _ in })
    }

    func start(
        onScrollActivity: @escaping @MainActor () -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    ) {
        guard localMonitor == nil, globalMonitor == nil, globalKeyMonitor == nil else { return }

        localMonitor = registrar.addLocal { event in
            Task { @MainActor in onScrollActivity() }
            return event
        }
        globalMonitor = registrar.addGlobal { _ in
            Task { @MainActor in onScrollActivity() }
        }
        globalKeyMonitor = registrar.addGlobalKeyDown { event in
            guard !event.isARepeat,
                  let command = Self.terminalCommand(for: event.keyCode) else { return }
            Task { @MainActor in onTerminalCommand(command) }
        }
        if !AXIsProcessTrusted(), !CGPreflightListenEventAccess() {
            NSLog("xxsnap global scroll-capture keys require Accessibility or Input Monitoring permission; toolbar controls remain available")
        }
    }

    private static func terminalCommand(for keyCode: UInt16) -> ScrollCaptureTerminalCommand? {
        switch keyCode {
        case 36, 76: return .finish
        case 53: return .cancel
        default: return nil
        }
    }

    func stop() {
        if let localMonitor {
            registrar.remove(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            registrar.remove(globalMonitor)
            self.globalMonitor = nil
        }
        if let globalKeyMonitor {
            registrar.remove(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    isolated deinit {
        if let localMonitor { registrar.remove(localMonitor) }
        if let globalMonitor { registrar.remove(globalMonitor) }
        if let globalKeyMonitor { registrar.remove(globalKeyMonitor) }
    }
}
