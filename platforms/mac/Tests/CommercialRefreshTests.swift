import Foundation
import XCTest
@testable import xxsnap

@MainActor
final class CommercialRefreshTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60

    func testStartLoadsCacheBeforeNetworkAndReturnsWithoutWaiting() async {
        let controller = RefreshControllerDouble()
        controller.suspendRefresh = true
        let sleeper = VirtualRefreshSleeper()
        let scheduler = CommercialRefreshScheduler(
            controller: controller,
            clock: RefreshClockDouble(now: Date(timeIntervalSince1970: 1_800_000_000)),
            sleeper: sleeper,
            networkMonitor: NoopCommercialNetworkMonitor()
        )

        scheduler.start()
        XCTAssertEqual(controller.operations, [])
        await controller.waitForRefreshStart()

        XCTAssertEqual(controller.operations, [.loadCache, .refresh(validatePaid: false)])
        XCTAssertTrue(controller.cacheAppliedBeforeRefresh)
        scheduler.cancel()
    }

    func testPreparedCacheBuildPathDoesNotReloadBeforeFirstNetworkRequest() async {
        let controller = RefreshControllerDouble()
        let fixture = makeScheduler(controller: controller)

        await fixture.scheduler.prepareFromCache()
        XCTAssertEqual(controller.operations, [.loadCache])
        fixture.scheduler.start()
        await controller.waitForRefreshCount(1)

        XCTAssertEqual(controller.operations, [.loadCache, .refresh(validatePaid: false)])
        fixture.scheduler.cancel()
    }

    func testPaidCredentialYoungerThanSevenDaysDoesNotValidate() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = RefreshControllerDouble()
        controller.paidValidationReferenceDate = now.addingTimeInterval(-(7 * day) + 1)
        let fixture = makeScheduler(controller: controller, now: now)

        fixture.scheduler.start()
        await controller.waitForRefreshCount(1)

        XCTAssertEqual(controller.validateArguments, [false])
        fixture.scheduler.cancel()
    }

    func testPaidCredentialExactlySevenDaysOldValidates() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = RefreshControllerDouble()
        controller.paidValidationReferenceDate = now.addingTimeInterval(-7 * day)
        let fixture = makeScheduler(controller: controller, now: now)

        fixture.scheduler.start()
        await controller.waitForRefreshCount(1)

        XCTAssertEqual(controller.validateArguments, [true])
        fixture.scheduler.cancel()
    }

    func testTrialNeverUsesPaidValidation() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = RefreshControllerDouble()
        controller.paidValidationReferenceDate = nil
        let fixture = makeScheduler(controller: controller, now: now)

        fixture.scheduler.start()
        await controller.waitForRefreshCount(1)

        XCTAssertEqual(controller.validateArguments, [false])
        fixture.scheduler.cancel()
    }

    func testTrustedClockFloorPreventsRollbackFromDeferringValidation() async {
        let serverTime = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = RefreshControllerDouble()
        controller.paidValidationReferenceDate = serverTime.addingTimeInterval(-7 * day)
        controller.trustedNowFloor = serverTime
        let fixture = makeScheduler(controller: controller, now: serverTime.addingTimeInterval(-30 * day))

        fixture.scheduler.start()
        await controller.waitForRefreshCount(1)

        XCTAssertEqual(controller.validateArguments, [true])
        fixture.scheduler.cancel()
    }

    func testRetryBackoffIsFifteenMinutesOneHourThenBoundedSixHours() async {
        let controller = RefreshControllerDouble()
        controller.results = Array(repeating: .retryableFailure, count: 4) + [.success]
        let fixture = makeScheduler(controller: controller)

        fixture.scheduler.start()
        await controller.waitForRefreshCount(1)
        let firstDurations = await fixture.sleeper.recordedDurations()
        XCTAssertEqual(firstDurations, [TimeInterval(15 * 60)])

        for expectedCount in 2...5 {
            await fixture.sleeper.advance()
            await controller.waitForRefreshCount(expectedCount)
        }

        let durations = await fixture.sleeper.recordedDurations()
        XCTAssertEqual(durations, [900, 3_600, 21_600, 21_600, 7 * day])
        fixture.scheduler.cancel()
    }

    func testSuccessResetsRetryBackoff() async {
        let controller = RefreshControllerDouble()
        controller.results = [.retryableFailure, .success, .retryableFailure]
        let fixture = makeScheduler(controller: controller)

        fixture.scheduler.start()
        await controller.waitForRefreshCount(1)
        await fixture.sleeper.advance()
        await controller.waitForRefreshCount(2)
        fixture.scheduler.triggerRefresh()
        await controller.waitForRefreshCount(3)

        let durations = await fixture.sleeper.recordedDurations()
        XCTAssertEqual(Array(durations.suffix(2)), [7 * day, 900])
        fixture.scheduler.cancel()
    }

    func testCancelStopsInFlightWorkAndPreventsLaterRequests() async {
        let controller = RefreshControllerDouble()
        controller.suspendRefresh = true
        let fixture = makeScheduler(controller: controller)

        fixture.scheduler.start()
        await controller.waitForRefreshStart()
        fixture.scheduler.cancel()
        await controller.waitForCancellation()
        await fixture.sleeper.advanceAll()
        await Task.yield()

        XCTAssertEqual(controller.refreshCount, 1)
        XCTAssertEqual(controller.completedRefreshCount, 0)
    }

    func testManualAndNetworkTriggersAreDeduplicatedWithoutOverlap() async {
        let controller = RefreshControllerDouble()
        controller.suspendRefresh = true
        let fixture = makeScheduler(controller: controller)

        fixture.scheduler.start()
        await controller.waitForRefreshStart()
        fixture.scheduler.triggerRefresh()
        fixture.scheduler.networkDidBecomeAvailable()
        fixture.scheduler.triggerRefresh()
        await controller.waitForRefreshCount(2)

        XCTAssertEqual(controller.maximumConcurrentRefreshCount, 1)
        XCTAssertEqual(controller.refreshCount, 2)
        fixture.scheduler.cancel()
    }

    func testTerminalResultDoesNotUseNetworkRetryBackoff() async {
        let controller = RefreshControllerDouble()
        controller.results = [.terminalFailure]
        let fixture = makeScheduler(controller: controller)

        fixture.scheduler.start()
        await controller.waitForRefreshCount(1)

        let durations = await fixture.sleeper.recordedDurations()
        XCTAssertEqual(durations, [7 * day])
        fixture.scheduler.cancel()
    }

    func testXCTestLaunchDependenciesNeverConstructProductionControllerOrScheduler() async {
        var controllerFactoryCalls = 0
        var schedulerFactoryCalls = 0
        let dependencies = CommercialLaunchDependencies.make(
            runtimeContext: CommercialRuntimeContext(
                environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"],
                hasXCTestRuntime: true
            ),
            productionFactory: {
                controllerFactoryCalls += 1
                return UnrestrictedCommercialAccess.shared
            },
            schedulerFactory: { _ in
                schedulerFactoryCalls += 1
                return NoopCommercialRefreshScheduler()
            }
        )

        await dependencies.prepareFromCache()
        dependencies.startRefresh()
        dependencies.triggerRefresh()
        dependencies.cancelRefresh()

        XCTAssertEqual(controllerFactoryCalls, 0)
        XCTAssertEqual(schedulerFactoryCalls, 0)
    }

    private func makeScheduler(
        controller: RefreshControllerDouble,
        now: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> (scheduler: CommercialRefreshScheduler, sleeper: VirtualRefreshSleeper) {
        let sleeper = VirtualRefreshSleeper()
        return (
            CommercialRefreshScheduler(
                controller: controller,
                clock: RefreshClockDouble(now: now),
                sleeper: sleeper,
                networkMonitor: NoopCommercialNetworkMonitor()
            ),
            sleeper
        )
    }
}

@MainActor
private final class RefreshControllerDouble: CommercialRefreshControlling {
    enum Operation: Equatable {
        case loadCache
        case refresh(validatePaid: Bool)
    }

    var paidValidationReferenceDate: Date?
    var trustedNowFloor: Date?
    var results: [CommercialRefreshResult] = [.success]
    var suspendRefresh = false
    private(set) var operations: [Operation] = []
    private(set) var validateArguments: [Bool] = []
    private(set) var cacheAppliedBeforeRefresh = false
    private(set) var refreshCount = 0
    private(set) var completedRefreshCount = 0
    private(set) var maximumConcurrentRefreshCount = 0
    private var activeRefreshCount = 0

    func loadCachedCommercialState() async {
        operations.append(.loadCache)
    }

    func performCommercialRefresh(validatePaidCredential: Bool) async -> CommercialRefreshResult {
        cacheAppliedBeforeRefresh = operations.last == .loadCache || cacheAppliedBeforeRefresh
        operations.append(.refresh(validatePaid: validatePaidCredential))
        validateArguments.append(validatePaidCredential)
        refreshCount += 1
        activeRefreshCount += 1
        maximumConcurrentRefreshCount = max(maximumConcurrentRefreshCount, activeRefreshCount)
        defer { activeRefreshCount -= 1 }
        if suspendRefresh {
            do { try await Task.sleep(for: .seconds(3_600)) }
            catch { return .cancelled }
        }
        guard !Task.isCancelled else { return .cancelled }
        completedRefreshCount += 1
        return results.isEmpty ? .success : results.removeFirst()
    }

    func waitForRefreshStart() async {
        await waitForRefreshCount(1)
    }

    func waitForRefreshCount(_ count: Int) async {
        for _ in 0..<10_000 where refreshCount < count { await Task.yield() }
    }

    func waitForCancellation() async {
        for _ in 0..<10_000 where activeRefreshCount > 0 { await Task.yield() }
    }
}

private final class RefreshClockDouble: CommercialRefreshClock, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}

private actor VirtualRefreshSleeper: CommercialRefreshSleeping {
    private struct Waiter {
        let continuation: CheckedContinuation<Void, Error>
    }

    private var durations: [TimeInterval] = []
    private var waiters: [Waiter] = []

    func sleep(for interval: TimeInterval) async throws {
        durations.append(interval)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelAll() }
        }
    }

    func recordedDurations() -> [TimeInterval] { durations }

    func advance() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().continuation.resume()
    }

    func advanceAll() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.continuation.resume() }
    }

    private func cancelAll() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.continuation.resume(throwing: CancellationError()) }
    }
}
