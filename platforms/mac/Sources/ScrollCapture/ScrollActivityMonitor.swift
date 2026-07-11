import AppKit

protocol ScrollEventMonitorRegistering: AnyObject {
    func addLocal(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any
    func addGlobal(_ handler: @escaping (NSEvent) -> Void) -> Any?
    func remove(_ monitor: Any)
}

private final class AppKitScrollEventMonitorRegistrar: ScrollEventMonitorRegistering {
    func addLocal(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: handler)!
    }

    func addGlobal(_ handler: @escaping (NSEvent) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: handler)
    }

    func remove(_ monitor: Any) { NSEvent.removeMonitor(monitor) }
}

@MainActor
protocol ScrollActivityMonitoring: AnyObject {
    func start(_ callback: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class ScrollActivityMonitor: ScrollActivityMonitoring {
    private let registrar: any ScrollEventMonitorRegistering
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(registrar: any ScrollEventMonitorRegistering = AppKitScrollEventMonitorRegistrar()) {
        self.registrar = registrar
    }

    func start(_ callback: @escaping @MainActor () -> Void) {
        guard localMonitor == nil, globalMonitor == nil else { return }

        localMonitor = registrar.addLocal { event in
            Task { @MainActor in callback() }
            return event
        }
        globalMonitor = registrar.addGlobal { _ in
            Task { @MainActor in callback() }
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
    }

    isolated deinit {
        if let localMonitor { registrar.remove(localMonitor) }
        if let globalMonitor { registrar.remove(globalMonitor) }
    }
}
