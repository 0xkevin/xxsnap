import Foundation
import Network

enum CommercialRefreshResult: Equatable {
    case success
    case retryableFailure
    case terminalFailure
    case cancelled
}

struct CommercialPaidValidationContext: Equatable {
    let lastSuccessfulValidation: CommercialTimeAnchor?
    let currentUptime: TimeInterval
    let trustedNowFloor: Date?
}

@MainActor
protocol CommercialRefreshControlling: AnyObject {
    var paidValidationContext: CommercialPaidValidationContext? { get }
    func loadCachedCommercialState() async
    func beginCommercialRefreshGeneration() async -> CommercialRefreshGeneration
    func invalidateCommercialRefreshGeneration() async
    func performCommercialRefresh(
        generation: CommercialRefreshGeneration,
        validatePaidCredential: Bool
    ) async -> CommercialRefreshResult
}

protocol CommercialRefreshClock: AnyObject, Sendable {
    var now: Date { get }
}

final class SystemCommercialRefreshClock: CommercialRefreshClock, @unchecked Sendable {
    var now: Date { Date() }
}

protocol CommercialRefreshSleeping: Sendable {
    func sleep(for interval: TimeInterval) async throws
}

struct SystemCommercialRefreshSleeper: CommercialRefreshSleeping {
    func sleep(for interval: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0, interval) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

@MainActor
protocol CommercialNetworkMonitoring: AnyObject {
    func start(onRecovery: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class SystemCommercialNetworkMonitor: CommercialNetworkMonitoring {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.xxsnap.commercial-network-monitor")
    private var previousStatus: NWPath.Status?

    func start(onRecovery: @escaping @MainActor () -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let previous = previousStatus
                previousStatus = path.status
                if previous == .unsatisfied, path.status == .satisfied {
                    onRecovery()
                }
            }
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
        previousStatus = nil
    }
}

@MainActor
final class NoopCommercialNetworkMonitor: CommercialNetworkMonitoring {
    func start(onRecovery: @escaping @MainActor () -> Void) {}
    func cancel() {}
}

@MainActor
protocol CommercialRefreshScheduling: AnyObject {
    func prepareFromCache() async
    func start()
    func triggerRefresh()
    func networkDidBecomeAvailable()
    func cancel()
}

@MainActor
final class NoopCommercialRefreshScheduler: CommercialRefreshScheduling {
    func prepareFromCache() async {}
    func start() {}
    func triggerRefresh() {}
    func networkDidBecomeAvailable() {}
    func cancel() {}
}

@MainActor
final class CommercialRefreshScheduler: CommercialRefreshScheduling {
    private static let validationInterval: TimeInterval = 7 * 24 * 60 * 60
    private static let retryIntervals: [TimeInterval] = [15 * 60, 60 * 60, 6 * 60 * 60]

    private let controller: any CommercialRefreshControlling
    private let clock: any CommercialRefreshClock
    private let sleeper: any CommercialRefreshSleeping
    private let networkMonitor: any CommercialNetworkMonitoring

    private var task: Task<Void, Never>?
    private var invalidationTask: Task<Void, Never>?
    private var generation = 0
    private var started = false
    private var cacheLoaded = false

    init(
        controller: any CommercialRefreshControlling,
        clock: any CommercialRefreshClock = SystemCommercialRefreshClock(),
        sleeper: any CommercialRefreshSleeping = SystemCommercialRefreshSleeper(),
        networkMonitor: (any CommercialNetworkMonitoring)? = nil
    ) {
        self.controller = controller
        self.clock = clock
        self.sleeper = sleeper
        self.networkMonitor = networkMonitor ?? SystemCommercialNetworkMonitor()
    }

    func start() {
        guard !started else { return }
        started = true
        networkMonitor.start { [weak self] in self?.networkDidBecomeAvailable() }
        replaceLoop(loadCache: !cacheLoaded)
    }

    func prepareFromCache() async {
        guard !cacheLoaded, !Task.isCancelled else { return }
        await controller.loadCachedCommercialState()
        guard !Task.isCancelled else { return }
        cacheLoaded = true
    }

    func triggerRefresh() {
        guard started else { return }
        replaceLoop(loadCache: !cacheLoaded)
    }

    func networkDidBecomeAvailable() {
        triggerRefresh()
    }

    func cancel() {
        guard started || task != nil else { return }
        started = false
        generation += 1
        task?.cancel()
        task = nil
        enqueueGenerationInvalidation()
        networkMonitor.cancel()
    }

    private func replaceLoop(loadCache: Bool) {
        generation += 1
        let expectedGeneration = generation
        let previous = task
        previous?.cancel()
        let invalidation = enqueueGenerationInvalidation()
        task = Task { [weak self] in
            await invalidation.value
            if let previous { await previous.value }
            guard let self,
                  self.started,
                  self.generation == expectedGeneration,
                  !Task.isCancelled
            else { return }
            await self.runLoop(loadCache: loadCache, generation: expectedGeneration)
        }
    }

    private func runLoop(loadCache: Bool, generation: Int) async {
        if loadCache {
            await controller.loadCachedCommercialState()
            guard isCurrent(generation) else { return }
            cacheLoaded = true
        }

        var retryIndex = 0
        while isCurrent(generation) {
            let shouldValidate = paidValidationIsDue()
            let refreshGeneration = await controller.beginCommercialRefreshGeneration()
            guard isCurrent(generation) else { return }

            let result = await controller.performCommercialRefresh(
                generation: refreshGeneration,
                validatePaidCredential: shouldValidate
            )
            guard isCurrent(generation) else { return }

            let delay: TimeInterval
            switch result {
            case .retryableFailure:
                delay = Self.retryIntervals[min(retryIndex, Self.retryIntervals.count - 1)]
                retryIndex = min(retryIndex + 1, Self.retryIntervals.count - 1)
            case .success, .terminalFailure:
                retryIndex = 0
                delay = nextSuccessDelay()
            case .cancelled:
                return
            }

            do {
                try await sleeper.sleep(for: delay)
            } catch {
                return
            }
        }
    }

    private func nextSuccessDelay() -> TimeInterval {
        guard let context = controller.paidValidationContext,
              let reference = context.lastSuccessfulValidation,
              context.currentUptime >= reference.systemUptime
        else {
            return Self.validationInterval
        }
        let monotonicNow = reference.issuedAt.addingTimeInterval(
            context.currentUptime - reference.systemUptime
        )
        let effectiveNow = max(clock.now, context.trustedNowFloor ?? .distantPast, monotonicNow)
        let deadline = reference.issuedAt.addingTimeInterval(Self.validationInterval)
        guard deadline > effectiveNow else { return Self.validationInterval }
        return deadline.timeIntervalSince(effectiveNow)
    }

    private func paidValidationIsDue() -> Bool {
        guard let context = controller.paidValidationContext else { return false }
        guard let reference = context.lastSuccessfulValidation,
              context.currentUptime >= reference.systemUptime
        else { return true }
        let monotonicNow = reference.issuedAt.addingTimeInterval(
            context.currentUptime - reference.systemUptime
        )
        let effectiveNow = max(clock.now, context.trustedNowFloor ?? .distantPast, monotonicNow)
        return effectiveNow.timeIntervalSince(reference.issuedAt) >= Self.validationInterval
    }

    private func isCurrent(_ expectedGeneration: Int) -> Bool {
        started && generation == expectedGeneration && !Task.isCancelled
    }

    @discardableResult
    private func enqueueGenerationInvalidation() -> Task<Void, Never> {
        let pending = invalidationTask
        let controller = self.controller
        let next = Task {
            if let pending { await pending.value }
            await controller.invalidateCommercialRefreshGeneration()
        }
        invalidationTask = next
        return next
    }
}
