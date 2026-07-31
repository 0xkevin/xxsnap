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

            for feature in CommercialFeature.allCases {
                XCTAssertEqual(
                    controller.canUse(feature),
                    expectedAllowed,
                    "feature=\(feature), age=\(age), state=\(controller.state)"
                )
            }
            if age <= 14 {
                guard case .allFreeGrace = controller.state else { return XCTFail("expected grace") }
            } else {
                guard case .free = controller.state else { return XCTFail("expected free") }
            }
        }
    }

    func testProBadgesAppearOnlyForPaidFreeStateAndPurchaseUsesCallback() async throws {
        let allFree = try Fixture(now: now)
        allFree.store.policy = try allFree.policy(
            mode: .allFree,
            expiresAt: now.addingTimeInterval(.day)
        )
        allFree.client.fetchResult = .failure(URLError(.notConnectedToInternet))
        let allFreeController = allFree.controller()
        await allFreeController.refresh()
        XCTAssertFalse(allFreeController.showsProBadge(for: .scrollCapture))
        XCTAssertFalse(allFreeController.showsProBadge(for: .ocr))
        XCTAssertFalse(allFreeController.showsProBadge(for: .teachingPen))

        let paid = try Fixture(now: now)
        paid.store.policy = try paid.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        paid.client.fetchResult = .failure(URLError(.notConnectedToInternet))
        let paidController = paid.controller()
        await paidController.refresh()
        guard case .free = paidController.state else { return XCTFail("expected paid free state") }
        XCTAssertTrue(paidController.showsProBadge(for: .scrollCapture))
        XCTAssertTrue(paidController.showsProBadge(for: .ocr))
        XCTAssertTrue(paidController.showsProBadge(for: .teachingPen))

        var purchaseRequests: [CommercialFeature] = []
        paidController.purchaseRequestHandler = { purchaseRequests.append($0) }
        paidController.requestPurchase(for: .ocr)
        XCTAssertEqual(purchaseRequests, [.ocr])
    }

    func testPaidPolicyFeatureChangesNotifyEvenWhenAccessStateStaysFree() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(
            mode: .paid,
            expiresAt: now.addingTimeInterval(.day)
        )
        fixture.client.fetchResult = .success(try fixture.policy(
            mode: .paid,
            expiresAt: now.addingTimeInterval(.day),
            paidFeatures: [.ocr]
        ))
        let controller = fixture.controller()
        var snapshots: [Set<CommercialFeature>] = []
        controller.onStateChange = { _ in
            snapshots.append(Set(CommercialFeature.allCases.filter {
                controller.showsProBadge(for: $0)
            }))
        }

        await controller.refresh()

        XCTAssertEqual(snapshots, [Set(CommercialFeature.allCases), [.ocr]])
        guard case .free = controller.state else { return XCTFail("state must stay free") }
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
        let oldNonce = UUID()
        try fixture.store.saveAccessRecord(
            .active(
                envelope: try fixture.entitlement(access: .pro, maximumBuildNumber: 100),
                anchor: nil,
                clearsTerminalMarkerNonce: oldNonce
            )
        )
        fixture.client.fetchResult = .success(try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day)))
        fixture.client.validateResult = .failure(fixture.serverError("license_refunded"))
        fixture.store.saveAccessError = CommercialCredentialStoreError.keychain(errSecInteractionNotAllowed)
        fixture.store.deleteAccessError = CommercialCredentialStoreError.keychain(errSecInteractionNotAllowed)
        let controller = fixture.controller()

        await controller.refresh()

        XCTAssertEqual(controller.state, .free(reason: .serverDenied))
        XCTAssertTrue(controller.hasPendingTerminalCleanup)
        XCTAssertNotNil(fixture.store.access, "failed fallback must be treated as pending, not silently lost")
        XCTAssertNotEqual(fixture.marker.storedMarker?.nonce, oldNonce)

        fixture.client.fetchResult = .failure(URLError(.timedOut))
        let restartedWhileStorageFails = fixture.controller()
        await restartedWhileStorageFails.refresh()
        XCTAssertEqual(restartedWhileStorageFails.state, .free(reason: .serverDenied))
        XCTAssertFalse(restartedWhileStorageFails.canUse(.ocr))

        fixture.store.saveAccessError = nil
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
        let marker = CommercialTerminalMarker(reason: .revoked)
        fixture.marker.storedMarker = marker
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
        XCTAssertEqual(fixture.store.accessRecord?.clearsTerminalMarkerNonce, marker.nonce)

        let restarted = fixture.controller()
        await restarted.refresh()
        XCTAssertEqual(restarted.state, .free(reason: .serverDenied))

        fixture.marker.deleteError = nil
        await restarted.refresh()
        guard case .pro = restarted.state else { return XCTFail("saved activation should recover after marker clears") }
        XCTAssertNil(fixture.marker.reason)
    }

    func testPresentationExposesOnlyVerifiedPolicyAndMapsStableActivationFailures() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.client.fetchResult = .failure(URLError(.timedOut))
        let controller = fixture.controller()
        await controller.refresh()
        XCTAssertEqual(controller.presentationPolicy?.mode, .paid)

        for (code, expected) in [
            ("device_limit_reached", CommercialAccessControllerError.deviceLimit),
            ("license_not_found", CommercialAccessControllerError.activationRejected),
        ] {
            fixture.client.activateResult = .failure(fixture.serverError(code))
            do {
                try await controller.activate(email: "person@example.com", code: "XXSNAP-ABCD-2345-WXYZ-6789")
                XCTFail("expected \(code)")
            } catch {
                XCTAssertEqual(error as? CommercialAccessControllerError, expected)
            }
        }
    }

    func testMarkerCannotBeClearedByMismatchedMissingOrTrialNonce() async throws {
        for scenario in ["mismatch", "missing", "trial"] {
            let fixture = try Fixture(now: now)
            fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
            let marker = CommercialTerminalMarker(reason: .revoked)
            fixture.marker.storedMarker = marker
            let access: CommercialAccessKind = scenario == "trial" ? .trial : .pro
            let envelope = try fixture.entitlement(
                access: access,
                expiresAt: access == .trial ? now.addingTimeInterval(.day) : nil,
                maximumBuildNumber: access == .pro ? 100 : nil
            )
            let clearingNonce: UUID? = scenario == "missing"
                ? nil
                : (scenario == "mismatch" ? UUID() : marker.nonce)
            try fixture.store.saveAccessRecord(
                .active(
                    envelope: envelope,
                    anchor: CommercialTimeAnchor(issuedAt: now, systemUptime: 1_000),
                    clearsTerminalMarkerNonce: clearingNonce
                )
            )
            fixture.client.fetchResult = .failure(URLError(.timedOut))
            let controller = fixture.controller()

            await controller.refresh()

            XCTAssertEqual(controller.state, .free(reason: .serverDenied), scenario)
            XCTAssertEqual(fixture.marker.storedMarker, marker, scenario)
        }
    }

    func testActivationCannotDeleteMarkerReplacedDuringCompareAndClear() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        let original = CommercialTerminalMarker(reason: .revoked)
        let replacement = CommercialTerminalMarker(reason: .refunded)
        fixture.marker.storedMarker = original
        fixture.client.activateResult = .success(try fixture.entitlement(access: .pro, maximumBuildNumber: 100))
        fixture.marker.onCompareAndDelete = { [weak markerStore = fixture.marker] _ in
            markerStore?.storedMarker = replacement
        }
        let controller = fixture.controller()

        do {
            try await controller.activate(email: "person@example.com", code: "PRIVATE")
            XCTFail("replacement marker must keep access denied")
        } catch {
            XCTAssertEqual(error as? CommercialAccessControllerError, .storage)
        }

        XCTAssertEqual(controller.state, .free(reason: .serverDenied))
        XCTAssertEqual(fixture.marker.storedMarker, replacement)
        XCTAssertEqual(fixture.store.accessRecord?.clearsTerminalMarkerNonce, original.nonce)
    }

    func testCorruptMarkerIsNormalizedBeforeFailedActivationAndRemainsDenied() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
        fixture.client.fetchResult = .failure(URLError(.notConnectedToInternet))
        fixture.client.activateResult = .failure(URLError(.notConnectedToInternet))
        let controller = fixture.controller()
        await controller.refresh()
        guard case .pro = controller.state else { return XCTFail("precondition requires cached Pro") }
        fixture.marker.loadError = CommercialTerminalMarkerStoreError.corruptData

        do {
            try await controller.activate(email: "person@example.com", code: "PRIVATE")
            XCTFail("network failure must be sanitized")
        } catch {
            XCTAssertEqual(error as? CommercialAccessControllerError, .network)
        }

        XCTAssertEqual(fixture.client.activateCalls, 1)
        XCTAssertNil(fixture.marker.loadError)
        XCTAssertNotNil(fixture.marker.storedMarker)
        XCTAssertEqual(controller.state, .free(reason: .serverDenied))
    }

    func testValidProActivationNormalizesAndClearsCorruptMarkerAcrossRestart() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.marker.loadError = CommercialTerminalMarkerStoreError.corruptData
        fixture.client.fetchResult = .failure(URLError(.notConnectedToInternet))
        fixture.client.activateResult = .success(try fixture.entitlement(access: .pro, maximumBuildNumber: 100))
        let controller = fixture.controller()
        await controller.refresh()

        try await controller.activate(email: "person@example.com", code: "PRIVATE")

        guard case .pro = controller.state else { return XCTFail("valid Pro must recover") }
        XCTAssertNil(fixture.marker.storedMarker)
        let restarted = fixture.controller()
        await restarted.refresh()
        guard case .pro = restarted.state else { return XCTFail("saved Pro must survive restart") }
    }

    func testNewTerminalMarkerAfterCorruptNormalizationCannotBeClearedByOldNonce() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.marker.loadError = CommercialTerminalMarkerStoreError.corruptData
        let replacement = CommercialTerminalMarker(reason: .refunded)
        fixture.client.activateResult = .success(try fixture.entitlement(access: .pro, maximumBuildNumber: 100))
        fixture.marker.onCompareAndDelete = { [weak markerStore = fixture.marker] _ in
            markerStore?.storedMarker = replacement
        }
        let controller = fixture.controller()

        do {
            try await controller.activate(email: "person@example.com", code: "PRIVATE")
            XCTFail("new terminal marker must win")
        } catch {
            XCTAssertEqual(error as? CommercialAccessControllerError, .storage)
        }

        XCTAssertEqual(fixture.marker.storedMarker, replacement)
        XCTAssertEqual(controller.state, .free(reason: .serverDenied))
    }

    func testTrialActivationCannotClearNormalizedCorruptMarker() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.marker.loadError = CommercialTerminalMarkerStoreError.corruptData
        fixture.client.activateResult = .success(
            try fixture.entitlement(access: .trial, expiresAt: now.addingTimeInterval(.day))
        )
        let controller = fixture.controller()

        do {
            try await controller.activate(email: "person@example.com", code: "PRIVATE")
            XCTFail("trial is not an activation clearance")
        } catch {
            XCTAssertEqual(error as? CommercialAccessControllerError, .invalidCredential)
        }

        XCTAssertNil(fixture.marker.loadError)
        XCTAssertNotNil(fixture.marker.storedMarker)
        XCTAssertNil(fixture.store.access)
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

    func testPresentationCallbackFiresWhenSignedPolicyCopyChangesWithoutAccessStateChange() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.client.fetchResult = .success(
            try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day), updateMonths: 24)
        )
        let controller = fixture.controller()
        var stateCallbackCount = 0
        var presentationCallbackCount = 0
        controller.onStateChange = { _ in stateCallbackCount += 1 }
        controller.onPresentationChange = { presentationCallbackCount += 1 }

        await controller.refresh()

        XCTAssertEqual(controller.state, .free(reason: .trialUnavailable))
        XCTAssertEqual(controller.presentationPolicy?.updateMonths, 24)
        XCTAssertEqual(controller.presentationNotice, .network)
        XCTAssertEqual(stateCallbackCount, 1)
        XCTAssertEqual(presentationCallbackCount, 3)
    }

    func testRefreshFailurePublishesStableNoticeWithoutChangingAccessStateCallback() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        let cachedAccess = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
        fixture.store.access = cachedAccess
        fixture.client.fetchResult = .failure(URLError(.timedOut))
        let controller = fixture.controller()
        var states: [CommercialAccessState] = []
        var presentationChanges = 0
        controller.onStateChange = { states.append($0) }
        controller.onPresentationChange = { presentationChanges += 1 }

        await controller.refresh()

        guard case .pro = controller.state else { return XCTFail("network failure must retain Pro") }
        XCTAssertEqual(controller.presentationNotice, .network)
        XCTAssertEqual(states.count, 1)
        XCTAssertGreaterThanOrEqual(presentationChanges, 1)

        fixture.client.fetchResult = .success(
            try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        )
        fixture.client.validateResult = .success(cachedAccess)
        await controller.refresh()
        XCTAssertNil(controller.presentationNotice)
        XCTAssertEqual(states.count, 1, "notice changes must not masquerade as access-state changes")
    }

    func testValidationNetworkFailureKeepsProAndPublishesNotice() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
        fixture.client.fetchResult = .success(
            try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        )
        fixture.client.validateResult = .failure(URLError(.timedOut))
        let controller = fixture.controller()

        await controller.refresh()

        guard case .pro = controller.state else { return XCTFail("validation outage must retain Pro") }
        XCTAssertEqual(controller.presentationNotice, .network)
    }

    func testRefreshServerFailureUsesStableServerNotice() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.client.fetchResult = .failure(fixture.serverError("temporary_backend_detail"))
        let controller = fixture.controller()

        await controller.refresh()

        XCTAssertEqual(controller.presentationNotice, .server)
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

    func testOldValidationFromAnotherControllerCannotRestoreAccessAfterTerminalCommit() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 50)
        fixture.client.fetchResult = .success(try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day)))
        fixture.client.suspendValidation = true
        let validationStarted = expectation(description: "controller A validation started")
        fixture.client.onValidate = { validationStarted.fulfill() }
        let controllerA = fixture.controller()
        let controllerB = fixture.controller()

        let staleRefresh = Task { await controllerA.refresh() }
        await fulfillment(of: [validationStarted], timeout: 1)
        try await controllerB.deactivateCurrentDevice()
        fixture.client.resumeValidation(
            with: .success(try fixture.entitlement(access: .pro, maximumBuildNumber: 100))
        )
        await staleRefresh.value

        XCTAssertNil(fixture.store.access, "stale validation must not replace terminal state")
        XCTAssertNotNil(fixture.marker.storedMarker)
        let restarted = fixture.controller()
        fixture.client.fetchResult = .failure(URLError(.notConnectedToInternet))
        await restarted.refresh()
        XCTAssertEqual(restarted.state, .free(reason: .serverDenied))
    }

    func testOldTerminalCleanupFromAnotherControllerCannotDeleteReactivatedAccess() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 50)
        fixture.client.fetchResult = .failure(URLError(.notConnectedToInternet))
        fixture.store.deleteAccessError = CommercialCredentialStoreError.keychain(errSecInteractionNotAllowed)
        let controllerA = fixture.controller()
        await controllerA.refresh()
        do {
            try await controllerA.deactivateCurrentDevice()
            XCTFail("terminal cleanup must be pending")
        } catch {
            XCTAssertEqual(error as? CommercialAccessControllerError, .storage)
        }
        XCTAssertTrue(controllerA.hasPendingTerminalCleanup)

        let controllerB = fixture.controller()
        fixture.client.activateResult = .success(try fixture.entitlement(access: .pro, maximumBuildNumber: 100))
        try await controllerB.activate(email: "person@example.com", code: "PRIVATE")
        let reactivationCommitted = expectation(description: "controller B reactivation committed")
        reactivationCommitted.fulfill()
        await fulfillment(of: [reactivationCommitted], timeout: 1)

        fixture.store.deleteAccessError = nil
        await controllerA.refresh()

        XCTAssertNotNil(fixture.store.access, "old cleanup must not delete newer active record")
        let restarted = fixture.controller()
        await restarted.refresh()
        guard case .pro = restarted.state else { return XCTFail("reactivated Pro must survive restart") }
    }

    func testWrongTypeMarkerFailsClosedAtStartup() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.store.access = try fixture.entitlement(access: .pro, maximumBuildNumber: 100)
        fixture.client.fetchResult = .failure(URLError(.notConnectedToInternet))
        let suite = "com.xxsnap.tests.wrong-type-startup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("not-data", forKey: "commercial.terminal-deny.v1")
        let controller = fixture.controller(markerStore: CommercialTerminalMarkerStore(userDefaults: defaults))

        await controller.refresh()

        XCTAssertEqual(controller.state, .free(reason: .serverDenied))
    }

    func testWrongTypeMarkerCanOnlyBeClearedByValidActivation() async throws {
        let fixture = try Fixture(now: now)
        fixture.store.policy = try fixture.policy(mode: .paid, expiresAt: now.addingTimeInterval(.day))
        fixture.client.activateResult = .success(try fixture.entitlement(access: .pro, maximumBuildNumber: 100))
        let suite = "com.xxsnap.tests.wrong-type-activation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(99, forKey: "commercial.terminal-deny.v1")
        let markerStore = CommercialTerminalMarkerStore(userDefaults: defaults)
        let controller = fixture.controller(markerStore: markerStore)

        try await controller.activate(email: "person@example.com", code: "PRIVATE")

        guard case .pro = controller.state else { return XCTFail("valid Pro activation must recover") }
        XCTAssertNil(try markerStore.loadTerminalMarker())
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
    let coordinator = CommercialCredentialMutationCoordinator()
    let clock: MutableCommercialClock
    let buildNumber: Int
    var bootstrap: SignedEnvelope?

    init(now: Date, buildNumber: Int = 42) throws {
        clock = MutableCommercialClock(now: now, currentUptime: 1_000)
        self.buildNumber = buildNumber
    }

    @MainActor func controller(
        markerStore: CommercialTerminalMarkerStoring? = nil
    ) -> CommercialAccessController {
        CommercialAccessController(
            store: store,
            markerStore: markerStore ?? marker,
            coordinator: coordinator,
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

    func policy(
        mode: CommercialMode,
        expiresAt: Date,
        paidFeatures: Set<CommercialFeature>? = nil,
        updateMonths: Int = 12
    ) throws -> SignedEnvelope {
        let effective = min(clock.now.addingTimeInterval(-.day), expiresAt.addingTimeInterval(-30 * .day))
        let paidFeatures = paidFeatures
            ?? (mode == .paid ? Set(CommercialFeature.allCases) : [])
        let object: [String: Any] = [
            "schemaVersion": 1, "policyId": "00000000-0000-0000-0000-000000000001",
            "mode": mode.rawValue, "billingReady": mode == .paid,
            "effectiveAt": iso(effective), "expiresAt": iso(expiresAt),
            "trialDays": 14, "updateMonths": updateMonths, "deviceLimit": 3,
            "minimumSafeVersion": "1.0.0",
            "features": [
                "scroll_capture": paidFeatures.contains(.scrollCapture),
                "ocr": paidFeatures.contains(.ocr),
                "teaching_pen": paidFeatures.contains(.teachingPen),
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
    var storedMarker: CommercialTerminalMarker?
    var reason: CommercialTerminalReason? {
        get { storedMarker?.reason }
        set { storedMarker = newValue.map { CommercialTerminalMarker(reason: $0) } }
    }
    var loadError: Error?
    var saveError: Error?
    var deleteError: Error?
    var onCompareAndDelete: ((UUID) -> Void)?

    func loadTerminalMarker() throws -> CommercialTerminalMarker? {
        if let loadError { throw loadError }
        return storedMarker
    }

    func prepareClearanceMarker() throws -> CommercialTerminalMarker? {
        if loadError as? CommercialTerminalMarkerStoreError == .corruptData {
            let marker = CommercialTerminalMarker(reason: .revoked)
            storedMarker = marker
            loadError = nil
            return marker
        }
        if let loadError { throw loadError }
        return storedMarker
    }

    func saveTerminalMarker(_ marker: CommercialTerminalMarker) throws {
        if let saveError { throw saveError }
        storedMarker = marker
    }

    func compareAndDeleteTerminalMarker(expectedNonce: UUID) throws -> Bool {
        if let deleteError { throw deleteError }
        if let loadError { throw loadError }
        onCompareAndDelete?(expectedNonce)
        onCompareAndDelete = nil
        guard storedMarker?.nonce == expectedNonce else { return false }
        storedMarker = nil
        return true
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
    var accessRecord: CommercialAccessRecord? { record }
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
    func compareAndDeleteTerminalAccessRecord(expectedNonce: UUID) throws -> Bool {
        if let deleteAccessError { throw deleteAccessError }
        guard record?.status == .terminal,
              record?.terminalMarkerNonce == expectedNonce
        else { return false }
        record = nil
        return true
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
    var activateCalls = 0
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
        activateCalls += 1; lastActivation = request; return try activateResult.get()
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
