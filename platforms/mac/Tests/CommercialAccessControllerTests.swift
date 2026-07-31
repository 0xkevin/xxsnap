import CryptoKit
import Security
import XCTest
@testable import xxsnap

@MainActor
final class CommercialAccessControllerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testAllFreePolicyAndExactFourteenDayGraceBoundaries() async throws {
        for (age, expectedAllowed) in [(13.0, true), (14.0, true), (14.1, false)] {
            let fixture = try Fixture(now: now)
            fixture.store.policy = try fixture.policy(mode: .allFree, expiresAt: now.addingTimeInterval(-age * .day))
            fixture.client.fetchResult = .failure(URLError(.notConnectedToInternet))
            let controller = fixture.controller()

            await controller.refresh()

            XCTAssertEqual(controller.canUse(.ocr), expectedAllowed, "age=\(age), state=\(controller.state)")
            if age <= 14 {
                guard case .allFreeGrace = controller.state else { return XCTFail("expected grace") }
            } else {
                guard case .free = controller.state else { return XCTFail("expected free") }
            }
        }
    }

    func testUsesBootstrapOnlyWhenPolicyCacheIsAbsent() async throws {
        let fixture = try Fixture(now: now)
        fixture.bootstrap = try fixture.policy(mode: .allFree, expiresAt: now.addingTimeInterval(.day))
        fixture.client.fetchResult = .failure(URLError(.notConnectedToInternet))
        let controller = fixture.controller()
        await controller.refresh()
        XCTAssertEqual(controller.state, .allFree)

        let invalidCacheFixture = try Fixture(now: now)
        invalidCacheFixture.store.policy = SignedEnvelope(keyId: "wrong", payload: "AA==", signature: String(repeating: "A", count: 88))
        invalidCacheFixture.bootstrap = try invalidCacheFixture.policy(mode: .allFree, expiresAt: now.addingTimeInterval(.day))
        invalidCacheFixture.client.fetchResult = .failure(URLError(.notConnectedToInternet))
        let invalidController = invalidCacheFixture.controller()
        await invalidController.refresh()
        guard case .free(reason: .policyInvalid) = invalidController.state else { return XCTFail("invalid cache must not fall back") }
    }

    func testPaidCredentialRequiresBuildEligibilityAndSurvivesNetworkFailure() async throws {
        let fixture = try Fixture(now: now, buildNumber: 42)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 42)
        fixture.client.fetchResult = .failure(URLError(.timedOut))
        let controller = fixture.controller()
        await controller.refresh()
        guard case .pro = controller.state else { return XCTFail("expected pro") }
        XCTAssertTrue(controller.canUse(.teachingPen))

        let ineligible = try Fixture(now: now, buildNumber: 43)
        ineligible.store.policy = try ineligible.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        ineligible.store.access = try ineligible.entitlement(access: .pro, maximumBuildNumber: 42)
        ineligible.client.fetchResult = .failure(URLError(.timedOut))
        let ineligibleController = ineligible.controller()
        await ineligibleController.refresh()
        XCTAssertEqual(ineligibleController.state, .free(reason: .buildNotEligible))
    }

    func testValidPaidCredentialSurvivesMissingPolicyAndExpiredAllFreePolicy() async throws {
        let missing = try Fixture(now: now, buildNumber: 42)
        missing.store.access = try missing.entitlement(access: .pro, maximumBuildNumber: 42)
        missing.client.fetchResult = .failure(URLError(.timedOut))
        let missingController = missing.controller()
        await missingController.refresh()
        guard case .pro = missingController.state else { return XCTFail("paid must survive missing policy") }

        let expired = try Fixture(now: now, buildNumber: 42)
        expired.store.policy = try expired.policy(mode: .allFree, expiresAt: now.addingTimeInterval(-15 * .day))
        expired.store.access = try expired.entitlement(access: .pro, maximumBuildNumber: 42)
        expired.client.fetchResult = .failure(URLError(.timedOut))
        let expiredController = expired.controller()
        await expiredController.refresh()
        guard case .pro = expiredController.state else { return XCTFail("paid must follow expired all-free grace") }
    }

    func testValidTrialAndExpirationUseAnchoredEffectiveTime() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .trial, expiresAt: now.addingTimeInterval(100))
        fixture.store.anchor = CommercialTimeAnchor(issuedAt: now, systemUptime: 1_000)
        fixture.clock.currentUptime = 1_050
        fixture.client.fetchResult = .failure(URLError(.timedOut))
        let controller = fixture.controller()
        await controller.refresh()
        XCTAssertEqual(controller.state, .trial(expiresAt: now.addingTimeInterval(100)))

        fixture.clock.now = now.addingTimeInterval(-10_000)
        fixture.clock.currentUptime = 1_201
        await controller.refresh()
        XCTAssertEqual(controller.state, .free(reason: .trialExpired))
    }

    func testUptimeResetDoesNotExtendTrialButDoesNotRevokePaid() async throws {
        let trial = try Fixture(now: now)
        trial.store.policy = try trial.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        trial.store.access = try trial.entitlement(access: .trial, expiresAt: now.addingTimeInterval(.day))
        trial.store.anchor = CommercialTimeAnchor(issuedAt: now, systemUptime: 10_000)
        trial.clock.currentUptime = 5
        trial.client.fetchResult = .failure(URLError(.timedOut))
        let trialController = trial.controller()
        await trialController.refresh()
        XCTAssertEqual(trialController.state, .free(reason: .clockRequiresValidation))

        let paid = try Fixture(now: now)
        paid.store.policy = try paid.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        paid.store.access = try paid.entitlement(access: .pro, maximumBuildNumber: 100)
        paid.store.anchor = CommercialTimeAnchor(issuedAt: now, systemUptime: 10_000)
        paid.clock.currentUptime = 5
        paid.client.fetchResult = .failure(URLError(.timedOut))
        let paidController = paid.controller()
        await paidController.refresh()
        guard case .pro = paidController.state else { return XCTFail("paid must fail open") }
    }

    func testMissingOrCorruptAnchorFailsOpenForPaidButRequiresValidationForTrial() async throws {
        for corrupt in [false, true] {
            let paid = try Fixture(now: now)
            paid.store.policy = try paid.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
            paid.store.access = try paid.entitlement(access: .pro, maximumBuildNumber: 100)
            paid.store.anchor = nil
            paid.store.simulatesCorruptAnchor = corrupt
            paid.client.fetchResult = .failure(URLError(.timedOut))
            let paidController = paid.controller()
            await paidController.refresh()
            guard case .pro = paidController.state else { return XCTFail("paid anchor corrupt=\(corrupt) must fail open") }

            let trial = try Fixture(now: now)
            trial.store.policy = try trial.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
            trial.store.access = try trial.entitlement(access: .trial, expiresAt: now.addingTimeInterval(.day))
            trial.store.anchor = nil
            trial.store.simulatesCorruptAnchor = corrupt
            trial.client.fetchResult = .failure(URLError(.timedOut))
            let trialController = trial.controller()
            await trialController.refresh()
            XCTAssertEqual(trialController.state, .free(reason: .clockRequiresValidation))
        }
    }

    func testTrialCredentialNeverCallsPaidValidationEndpoint() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .trial, expiresAt: now.addingTimeInterval(.day))
        fixture.store.anchor = CommercialTimeAnchor(issuedAt: now, systemUptime: 1_000)
        fixture.client.fetchResult = .success(try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day)))
        let controller = fixture.controller()

        await controller.refresh()

        XCTAssertEqual(fixture.client.validateCalls, 0)
        guard case .trial = controller.state else { return XCTFail("trial should remain local") }
    }

    func testPaidPolicyWithoutCredentialAttemptsTrialOnlyOnce() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.client.fetchResult = .success(try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day)))
        fixture.client.trialResult = .failure(URLError(.notConnectedToInternet))
        let controller = fixture.controller()
        await controller.refresh()
        await controller.refresh()
        XCTAssertEqual(fixture.client.trialCalls, 1)
    }

    func testSuccessfulTrialIsVerifiedAnchoredAndEnabled() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.client.fetchResult = .success(try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day)))
        fixture.client.trialResult = .success(try fixture.entitlement(access: .trial, expiresAt: now.addingTimeInterval(.day)))
        let controller = fixture.controller()

        await controller.refresh()

        guard case .trial = controller.state else { return XCTFail("expected trial") }
        XCTAssertNotNil(fixture.store.anchor)
        XCTAssertTrue(controller.canUse(.scrollCapture))
    }

    func testForwardClockRequestsValidationWithoutRevokingPaidOnNetworkFailure() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
        fixture.store.anchor = CommercialTimeAnchor(issuedAt: now, systemUptime: 1_000)
        fixture.clock.now = now.addingTimeInterval(365 * .day)
        fixture.clock.currentUptime = 1_001
        fixture.client.fetchResult = .failure(URLError(.timedOut))
        let controller = fixture.controller()

        await controller.refresh()

        guard case .pro = controller.state else { return XCTFail("forward clock must not revoke paid") }
        XCTAssertEqual(fixture.client.fetchCalls, 1)
    }

    func testOrdinaryDeactivateFailureKeepsCredential() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
        fixture.client.deactivateResult = .failure(URLError(.timedOut))
        let controller = fixture.controller()
        await controller.refresh()

        do {
            try await controller.deactivateCurrentDevice()
            XCTFail("expected sanitized network failure")
        } catch {
            XCTAssertEqual(error as? CommercialAccessControllerError, .network)
        }
        XCTAssertNotNil(fixture.store.access)
    }

    func testTerminalValidationErrorsDeleteCredentialButOrdinaryErrorsDoNot() async throws {
        for code in ["license_refunded", "license_revoked", "device_deactivated"] {
            let fixture = try Fixture(now: now)
            fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
            fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
            fixture.client.fetchResult = .success(try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day)))
            fixture.client.validateResult = .failure(fixture.serverError(code))
            let controller = fixture.controller()
            await controller.refresh()
            XCTAssertNil(fixture.store.access, code)
        }

        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
        fixture.client.fetchResult = .success(try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day)))
        fixture.client.validateResult = .failure(URLError(.timedOut))
        let controller = fixture.controller()
        await controller.refresh()
        XCTAssertNotNil(fixture.store.access)
        guard case .pro = controller.state else { return XCTFail("network failure must retain pro") }
    }

    func testTerminalTombstonePreventsProRecoveryWhenCleanupDeleteFailsAndAfterRestart() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
        fixture.client.fetchResult = .success(try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day)))
        fixture.client.validateResult = .failure(fixture.serverError("license_revoked"))
        fixture.store.deleteAccessError = CommercialCredentialStoreError.keychain(errSecInteractionNotAllowed)
        let controller = fixture.controller()

        await controller.refresh()

        XCTAssertEqual(controller.state, .free(reason: .serverDenied))
        XCTAssertTrue(fixture.store.isTerminalTombstone)
        XCTAssertTrue(controller.hasPendingTerminalCleanup)

        fixture.client.fetchResult = .failure(URLError(.timedOut))
        let restarted = fixture.controller()
        await restarted.refresh()
        XCTAssertEqual(restarted.state, .free(reason: .serverDenied))
        XCTAssertFalse(restarted.canUse(.ocr))
    }

    func testAllFreePolicyStillWinsWhileTerminalTombstoneAwaitsCleanup() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .allFree, expiresAt: now.addingTimeInterval(.day))
        try fixture.store.saveAccessRecord(.terminal(.revoked))
        fixture.store.deleteAccessError = CommercialCredentialStoreError.keychain(errSecInteractionNotAllowed)
        fixture.client.fetchResult = .failure(URLError(.timedOut))
        let controller = fixture.controller()

        await controller.refresh()

        XCTAssertEqual(controller.state, .allFree)
        XCTAssertTrue(controller.canUse(.ocr))
        XCTAssertTrue(controller.hasPendingTerminalCleanup)
    }

    func testTerminalMarkerReadFailureIsConservativeButAllFreeStillWins() async throws {
        let paid = try Fixture(now: now)
        paid.store.policy = try paid.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        paid.store.access = try paid.entitlement(access: .pro, maximumBuildNumber: 100)
        paid.marker.loadError = CommercialTerminalMarkerStoreError.corruptData
        paid.client.fetchResult = .failure(URLError(.timedOut))
        let paidController = paid.controller()
        await paidController.refresh()
        XCTAssertEqual(paidController.state, .free(reason: .serverDenied))

        let allFree = try Fixture(now: now)
        allFree.store.policy = try allFree.policy(mode: .allFree, expiresAt: now.addingTimeInterval(.day))
        allFree.marker.loadError = CommercialTerminalMarkerStoreError.corruptData
        allFree.client.fetchResult = .failure(URLError(.timedOut))
        let allFreeController = allFree.controller()
        await allFreeController.refresh()
        XCTAssertEqual(allFreeController.state, .allFree)
    }

    func testTombstoneWriteAndFallbackDeleteFailureIsObservableFailClosedAndRetryable() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
        fixture.client.fetchResult = .success(try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day)))
        fixture.client.validateResult = .failure(fixture.serverError("license_refunded"))
        fixture.store.saveAccessError = CommercialCredentialStoreError.keychain(errSecInteractionNotAllowed)
        fixture.store.deleteAccessError = CommercialCredentialStoreError.keychain(errSecInteractionNotAllowed)
        let controller = fixture.controller()

        await controller.refresh()

        XCTAssertEqual(controller.state, .free(reason: .serverDenied))
        XCTAssertTrue(controller.hasPendingTerminalCleanup)
        XCTAssertNotNil(fixture.store.access, "failed fallback must be treated as pending, not silently lost")

        fixture.client.fetchResult = .failure(URLError(.timedOut))
        let restartedWhileStorageFails = fixture.controller()
        await restartedWhileStorageFails.refresh()
        XCTAssertEqual(restartedWhileStorageFails.state, .free(reason: .serverDenied))
        XCTAssertFalse(restartedWhileStorageFails.canUse(.ocr))

        fixture.store.deleteAccessError = nil
        await controller.refresh()
        XCTAssertFalse(controller.hasPendingTerminalCleanup)
        XCTAssertNil(fixture.store.access)
        XCTAssertEqual(controller.state, .free(reason: .serverDenied))
    }

    func testMarkerWriteFailureKeepsKeychainTombstoneAcrossRestartUntilMarkerRecovers() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
        fixture.marker.saveError = CommercialTerminalMarkerStoreError.persistenceFailed
        fixture.client.fetchResult = .success(try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day)))
        fixture.client.validateResult = .failure(fixture.serverError("license_revoked"))
        let controller = fixture.controller()

        await controller.refresh()

        XCTAssertEqual(controller.state, .free(reason: .serverDenied))
        XCTAssertTrue(fixture.store.isTerminalTombstone)
        XCTAssertTrue(controller.hasPendingTerminalCleanup)

        fixture.client.fetchResult = .failure(URLError(.timedOut))
        let restarted = fixture.controller()
        await restarted.refresh()
        XCTAssertEqual(restarted.state, .free(reason: .serverDenied))
        XCTAssertTrue(fixture.store.isTerminalTombstone)

        fixture.marker.saveError = nil
        await restarted.refresh()
        XCTAssertEqual(restarted.state, .free(reason: .serverDenied))
        XCTAssertNil(fixture.store.access)
        XCTAssertEqual(fixture.marker.reason, .revoked)
    }

    func testSuccessfulActivationClearsMarkerSafelyAndRetriesClearAcrossRestart() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.marker.reason = .revoked
        fixture.client.fetchResult = .failure(URLError(.timedOut))
        fixture.client.activateResult = .success(try fixture.entitlement(access: .pro, maximumBuildNumber: 100))
        let controller = fixture.controller()
        await controller.refresh()
        XCTAssertEqual(controller.state, .free(reason: .serverDenied))

        fixture.marker.deleteError = CommercialTerminalMarkerStoreError.persistenceFailed
        do {
            try await controller.activate(email: "person@example.com", code: "PRIVATE")
            XCTFail("marker clear failure must stay fail-closed")
        } catch {
            XCTAssertEqual(error as? CommercialAccessControllerError, .storage)
        }
        XCTAssertEqual(controller.state, .free(reason: .serverDenied))
        XCTAssertNotNil(fixture.marker.reason)

        let restarted = fixture.controller()
        await restarted.refresh()
        XCTAssertEqual(restarted.state, .free(reason: .serverDenied))

        fixture.marker.deleteError = nil
        await restarted.refresh()
        guard case .pro = restarted.state else { return XCTFail("saved activation should recover after marker clears") }
        XCTAssertNil(fixture.marker.reason)
    }

    func testMarkerCannotBeClearedByNonProAccessRecordFlag() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.marker.reason = .revoked
        let trial = try fixture.entitlement(access: .trial, expiresAt: now.addingTimeInterval(.day))
        try fixture.store.saveAccessRecord(
            .active(
                envelope: trial,
                anchor: CommercialTimeAnchor(issuedAt: now, systemUptime: 1_000),
                clearsTerminalMarker: true
            )
        )
        fixture.client.fetchResult = .failure(URLError(.timedOut))
        let controller = fixture.controller()

        await controller.refresh()

        XCTAssertEqual(controller.state, .free(reason: .serverDenied))
        XCTAssertEqual(fixture.marker.reason, .revoked)
    }

    func testDeactivateCleanupFailureLeavesPersistentFreeTombstoneAcrossRestart() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
        fixture.store.deleteAccessError = CommercialCredentialStoreError.keychain(errSecInteractionNotAllowed)
        let controller = fixture.controller()
        await controller.refresh()

        do {
            try await controller.deactivateCurrentDevice()
            XCTFail("cleanup failure must be reported")
        } catch {
            XCTAssertEqual(error as? CommercialAccessControllerError, .storage)
        }
        XCTAssertEqual(controller.state, .free(reason: .serverDenied))
        XCTAssertTrue(fixture.store.isTerminalTombstone)

        let restarted = fixture.controller()
        await restarted.refresh()
        XCTAssertEqual(restarted.state, .free(reason: .serverDenied))
    }

    func testActivateAndDeactivateVerifyStoreAndUseAnonymousIdentity() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.client.activateResult = .success(try fixture.entitlement(access: .pro, maximumBuildNumber: 100))
        let controller = fixture.controller()

        try await controller.activate(email: "person@example.com", code: "SECRET-CODE")
        XCTAssertNotNil(fixture.store.access)
        XCTAssertEqual(fixture.client.lastActivation?.deviceHash, fixture.device.hash)
        XCTAssertEqual(fixture.client.lastActivation?.deviceName, fixture.device.name)

        try await controller.deactivateCurrentDevice()
        XCTAssertNil(fixture.store.access)
        XCTAssertEqual(fixture.client.lastDeactivation?.deviceHash, fixture.device.hash)
    }

    func testStateCallbackOnlyFiresWhenStateActuallyChanges() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .allFree, expiresAt: now.addingTimeInterval(.day))
        fixture.client.fetchResult = .failure(URLError(.timedOut))
        let controller = fixture.controller()
        var states: [CommercialAccessState] = []
        controller.onStateChange = { states.append($0) }
        await controller.refresh()
        await controller.refresh()
        XCTAssertEqual(states, [.allFree])
    }

    func testLateRefreshResponseCannotOverwriteNewerActivation() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 50)
        fixture.client.fetchResult = .success(try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day)))
        let stale = try fixture.entitlement(access: .pro, maximumBuildNumber: 50)
        let activated = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
        fixture.client.activateResult = .success(activated)
        fixture.client.suspendValidation = true
        let validationStarted = expectation(description: "validation started")
        fixture.client.onValidate = { validationStarted.fulfill() }
        let controller = fixture.controller()

        let refreshTask = Task { await controller.refresh() }
        await fulfillment(of: [validationStarted], timeout: 1)
        try await controller.activate(email: "person@example.com", code: "PRIVATE")
        fixture.client.resumeValidation(with: .success(stale))
        await refreshTask.value

        guard case let .pro(entitlement) = controller.state else { return XCTFail("expected pro") }
        XCTAssertEqual(entitlement.payload.maximumBuildNumber, 100)
    }
}

private extension TimeInterval {
    static let day: TimeInterval = 86_400
}

private final class Fixture {
    let privateKey = Curve25519.Signing.PrivateKey()
    let store = MemoryCommercialStore()
    let client = FakeCommercialClient()
    let device = FakeCommercialDevice()
    let marker = MemoryTerminalMarkerStore()
    let clock: MutableCommercialClock
    let buildNumber: Int
    var bootstrap: SignedEnvelope?

    init(now: Date, buildNumber: Int = 42) throws {
        clock = MutableCommercialClock(now: now, currentUptime: 1_000)
        self.buildNumber = buildNumber
    }

    @MainActor func controller() -> CommercialAccessController {
        CommercialAccessController(
            store: store,
            markerStore: marker,
            verifier: CommercialSignatureVerifier(publicKeys: ["test": privateKey.publicKey]),
            client: client,
            device: device,
            appVersion: "1.0.0",
            buildNumber: buildNumber,
            locale: .english,
            clock: clock,
            bootstrapEnvelope: { [weak self] in self?.bootstrap }
        )
    }

    func policy(mode: CommercialMode, expiresAt: Date) throws -> SignedEnvelope {
        let effective = min(clock.now.addingTimeInterval(-.day), expiresAt.addingTimeInterval(-30 * .day))
        let object: [String: Any] = [
            "schemaVersion": 1, "policyId": "00000000-0000-0000-0000-000000000001",
            "mode": mode.rawValue, "billingReady": mode == .paid,
            "effectiveAt": iso(effective), "expiresAt": iso(expiresAt),
            "trialDays": 14, "updateMonths": 12, "deviceLimit": 3,
            "minimumSafeVersion": "1.0.0",
            "features": [
                "scroll_capture": mode == .paid,
                "ocr": mode == .paid,
                "teaching_pen": mode == .paid,
            ],
            "purchase": ["regularPriceCny": 68, "launchPriceCny": 48, "renewalPriceCny": 34,
                         "zhCNURL": "https://xxsnap.xxsofts.com/zh-CN/buy", "enURL": "https://xxsnap.xxsofts.com/en/buy"],
            "copy": ["zhCN": ["proRequired": "需要专业版", "trialUnavailable": "试用不可用"],
                     "en": ["proRequired": "Pro required", "trialUnavailable": "Trial unavailable"]],
        ]
        return try sign(object)
    }

    func entitlement(
        access: CommercialAccessKind,
        expiresAt: Date? = nil,
        maximumBuildNumber: Int? = nil
    ) throws -> SignedEnvelope {
        let object: [String: Any] = [
            "schemaVersion": 1, "credentialId": UUID().uuidString.lowercased(),
            "licenseId": access == .pro ? UUID().uuidString.lowercased() : NSNull(),
            "deviceHash": device.hash, "access": access.rawValue,
            "appVersion": "1.0.0", "buildNumber": buildNumber,
            "issuedAt": iso(clock.now), "expiresAt": expiresAt.map(iso) ?? NSNull(),
            "purchasedAt": access == .pro ? iso(clock.now) : NSNull(),
            "updatesThrough": access == .pro ? iso(clock.now.addingTimeInterval(365 * .day)) : NSNull(),
            "maximumBuildNumber": maximumBuildNumber ?? NSNull(), "emailMasked": NSNull(),
            "activeDevices": access == .pro ? 1 : NSNull(), "deviceLimit": 3,
        ]
        return try sign(object)
    }

    func serverError(_ code: String) -> CommercialPolicyClientError {
        .server(status: 403, error: try! CommercialJSON.decoder.decode(
            CommercialAPIErrorDetail.self,
            from: Data("{\"code\":\"\(code)\",\"message\":\"terminal\",\"fields\":null}".utf8)
        ))
    }

    private func sign(_ object: [String: Any]) throws -> SignedEnvelope {
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return SignedEnvelope(
            keyId: "test", payload: payload.base64EncodedString(),
            signature: try privateKey.signature(for: payload).base64EncodedString()
        )
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private final class MemoryTerminalMarkerStore: CommercialTerminalMarkerStoring {
    var reason: CommercialTerminalReason?
    var loadError: Error?
    var saveError: Error?
    var deleteError: Error?

    func loadTerminalMarker() throws -> CommercialTerminalReason? {
        if let loadError { throw loadError }
        return reason
    }

    func saveTerminalMarker(_ reason: CommercialTerminalReason) throws {
        if let saveError { throw saveError }
        self.reason = reason
    }

    func deleteTerminalMarker() throws {
        if let deleteError { throw deleteError }
        reason = nil
    }
}

private final class MemoryCommercialStore: CommercialCredentialStoring {
    var policy: SignedEnvelope?
    private var record: CommercialAccessRecord?
    var access: SignedEnvelope? {
        get { record?.status == .active ? record?.envelope : nil }
        set {
            record = newValue.map { .active(envelope: $0, anchor: anchor) }
        }
    }
    var anchor: CommercialTimeAnchor? {
        get { record?.anchor }
        set {
            if let envelope = record?.envelope {
                record = .active(envelope: envelope, anchor: newValue)
            }
        }
    }
    var simulatesCorruptAnchor = false
    var deleteAccessError: Error?
    var saveAccessError: Error?
    var isTerminalTombstone: Bool { record?.status == .terminal }
    func loadPolicyEnvelope() throws -> SignedEnvelope? { policy }
    func savePolicyEnvelope(_ envelope: SignedEnvelope) throws { policy = envelope }
    func loadAccessRecord() throws -> CommercialAccessRecord? {
        guard simulatesCorruptAnchor, let envelope = record?.envelope else { return record }
        return .active(envelope: envelope, anchor: nil)
    }
    func saveAccessRecord(_ value: CommercialAccessRecord) throws {
        if let saveAccessError { throw saveAccessError }
        record = value
    }
    func deleteAccessRecord() throws {
        if let deleteAccessError { throw deleteAccessError }
        record = nil
    }
}

private final class FakeCommercialDevice: CommercialDeviceIdentifying {
    let hash = String(repeating: "a", count: 64)
    let name = "Test Mac"
    func deviceHash() throws -> String { hash }
    func displayName() -> String { name }
}

private final class MutableCommercialClock: CommercialTimeProviding {
    var now: Date
    var currentUptime: TimeInterval
    init(now: Date, currentUptime: TimeInterval) { self.now = now; self.currentUptime = currentUptime }
}

private final class FakeCommercialClient: CommercialPolicyFetching {
    var fetchResult: Result<SignedEnvelope, Error> = .failure(URLError(.notConnectedToInternet))
    var trialResult: Result<SignedEnvelope, Error> = .failure(URLError(.notConnectedToInternet))
    var activateResult: Result<SignedEnvelope, Error> = .failure(URLError(.notConnectedToInternet))
    var validateResult: Result<SignedEnvelope, Error> = .failure(URLError(.notConnectedToInternet))
    var deactivateResult: Result<Void, Error> = .success(())
    var trialCalls = 0
    var fetchCalls = 0
    var validateCalls = 0
    var lastActivation: CommercialLicenseActivateRequest?
    var lastDeactivation: CommercialLicenseDeactivateRequest?
    var suspendValidation = false
    var onValidate: (() -> Void)?
    private var validateContinuation: CheckedContinuation<SignedEnvelope, Error>?

    func fetchPolicy(locale: CommercialLocale) async throws -> SignedEnvelope {
        fetchCalls += 1; return try fetchResult.get()
    }
    func startTrial(_ request: CommercialTrialStartRequest, locale: CommercialLocale) async throws -> SignedEnvelope {
        trialCalls += 1; return try trialResult.get()
    }
    func activate(_ request: CommercialLicenseActivateRequest, locale: CommercialLocale) async throws -> SignedEnvelope {
        lastActivation = request; return try activateResult.get()
    }
    func validate(_ request: CommercialLicenseValidateRequest, locale: CommercialLocale) async throws -> SignedEnvelope {
        validateCalls += 1
        if suspendValidation {
            return try await withCheckedThrowingContinuation { continuation in
                validateContinuation = continuation
                onValidate?()
            }
        }
        return try validateResult.get()
    }
    func deactivate(_ request: CommercialLicenseDeactivateRequest, locale: CommercialLocale) async throws {
        lastDeactivation = request; try deactivateResult.get()
    }

    func resumeValidation(with result: Result<SignedEnvelope, Error>) {
        suspendValidation = false
        let continuation = validateContinuation
        validateContinuation = nil
        continuation?.resume(with: result)
    }
}
