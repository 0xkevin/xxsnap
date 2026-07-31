import Foundation

enum CommercialFreeReason: Equatable {
    case policyUnavailable
    case policyInvalid
    case policyExpired
    case credentialInvalid
    case trialUnavailable
    case trialExpired
    case buildNotEligible
    case clockRequiresValidation
    case serverDenied
}

struct CommercialEntitlement: Equatable {
    let payload: EntitlementPayload
}

enum CommercialAccessState: Equatable {
    case allFree
    case allFreeGrace(until: Date)
    case trial(expiresAt: Date)
    case free(reason: CommercialFreeReason)
    case pro(CommercialEntitlement)
}

enum CommercialAccessControllerError: Error, Equatable {
    case identityUnavailable
    case noCredential
    case invalidCredential
    case storage
    case network
}

protocol CommercialTimeProviding: AnyObject {
    var now: Date { get }
    var currentUptime: TimeInterval { get }
}

final class SystemCommercialClock: CommercialTimeProviding {
    var now: Date { Date() }
    var currentUptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

private actor CommercialCredentialWorker {
    private let store: CommercialCredentialStoring
    private let markerStore: CommercialTerminalMarkerStoring

    init(store: CommercialCredentialStoring, markerStore: CommercialTerminalMarkerStoring) {
        self.store = store
        self.markerStore = markerStore
    }

    func loadPolicy() throws -> SignedEnvelope? { try store.loadPolicyEnvelope() }
    func savePolicy(_ envelope: SignedEnvelope) throws { try store.savePolicyEnvelope(envelope) }
    func loadAccess() throws -> CommercialAccessRecord? { try store.loadAccessRecord() }
    func saveAccess(_ record: CommercialAccessRecord) throws { try store.saveAccessRecord(record) }
    func deleteAccess() throws { try store.deleteAccessRecord() }
    func loadTerminalMarker() throws -> CommercialTerminalMarker? {
        try markerStore.loadTerminalMarker()
    }
    func prepareClearanceMarker() throws -> CommercialTerminalMarker? {
        try markerStore.prepareClearanceMarker()
    }
    func saveTerminalMarker(_ marker: CommercialTerminalMarker) throws {
        try markerStore.saveTerminalMarker(marker)
    }
    func compareAndDeleteTerminalMarker(expectedNonce: UUID?) throws -> Bool {
        try markerStore.compareAndDeleteTerminalMarker(expectedNonce: expectedNonce)
    }
}

private actor CommercialDeviceWorker {
    private let device: CommercialDeviceIdentifying
    init(device: CommercialDeviceIdentifying) { self.device = device }
    func hash() throws -> String { try device.deviceHash() }
    func name() -> String { device.displayName() }
}

@MainActor
final class CommercialAccessController {
    private static let graceInterval: TimeInterval = 14 * 24 * 60 * 60

    private(set) var state: CommercialAccessState = .free(reason: .policyUnavailable)
    var onStateChange: ((CommercialAccessState) -> Void)?

    private let worker: CommercialCredentialWorker
    private let verifier: CommercialSignatureVerifier
    private let client: CommercialPolicyFetching
    private let deviceWorker: CommercialDeviceWorker
    private let appVersion: String
    private let buildNumber: Int
    private let locale: CommercialLocale
    private let clock: CommercialTimeProviding
    private let bootstrapEnvelope: () throws -> SignedEnvelope?

    private var policy: CommercialPolicy?
    private var accessEnvelope: SignedEnvelope?
    private var entitlement: EntitlementPayload?
    private var timeAnchor: CommercialTimeAnchor?
    private var generation = 0
    private var trialRequestAttempted = false
    private var terminalDenyActive = false
    private var terminalMarker: CommercialTerminalMarker?
    private(set) var hasPendingTerminalCleanup = false

    init(
        store: CommercialCredentialStoring,
        markerStore: CommercialTerminalMarkerStoring,
        verifier: CommercialSignatureVerifier,
        client: CommercialPolicyFetching,
        device: CommercialDeviceIdentifying,
        appVersion: String,
        buildNumber: Int,
        locale: CommercialLocale,
        clock: CommercialTimeProviding = SystemCommercialClock(),
        bootstrapEnvelope: @escaping () throws -> SignedEnvelope?
    ) {
        worker = CommercialCredentialWorker(store: store, markerStore: markerStore)
        self.verifier = verifier
        self.client = client
        deviceWorker = CommercialDeviceWorker(device: device)
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.locale = locale
        self.clock = clock
        self.bootstrapEnvelope = bootstrapEnvelope
    }

    convenience init(bundle: Bundle = .main, session: URLSession = .shared) throws {
        let verifier = try CommercialSignatureVerifier(bundle: bundle)
        let client = try CommercialPolicyClient(bundle: bundle, session: session)
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let buildNumber = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        self.init(
            store: CommercialCredentialStore(),
            markerStore: CommercialTerminalMarkerStore(),
            verifier: verifier,
            client: client,
            device: CommercialDeviceIdentity(),
            appVersion: appVersion,
            buildNumber: buildNumber,
            locale: Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zhHans : .english,
            bootstrapEnvelope: {
                guard let url = bundle.url(
                    forResource: "commercial-policy-bootstrap",
                    withExtension: "json",
                    subdirectory: "Commercial"
                ) ?? bundle.url(forResource: "commercial-policy-bootstrap", withExtension: "json")
                else { return nil }
                let data = try Data(contentsOf: url)
                return try CommercialJSON.decoder.decode(SignedEnvelope.self, from: data)
            }
        )
    }

    func canUse(_ feature: CommercialFeature) -> Bool {
        switch state {
        case .allFree, .allFreeGrace, .trial, .pro:
            return true
        case .free:
            guard let policy else { return false }
            if policy.mode == .allFree {
                return false
            }
            return !policy.features[feature]
        }
    }

    func refresh() async {
        let token = beginOperation()
        if terminalDenyActive, hasPendingTerminalCleanup {
            do {
                guard let terminalMarker else { throw CommercialAccessControllerError.storage }
                try await worker.saveTerminalMarker(terminalMarker)
                try await worker.deleteAccess()
                hasPendingTerminalCleanup = false
            } catch {
                hasPendingTerminalCleanup = true
            }
        }
        await loadLocalState(token: token)
        guard isCurrent(token) else { return }
        resolveState()

        do {
            let envelope = try await client.fetchPolicy(locale: locale)
            guard isCurrent(token) else { return }
            let verified = try verifier.verifyPolicy(envelope, at: clock.now)
            try await worker.savePolicy(envelope)
            guard isCurrent(token) else { return }
            policy = verified
            resolveState()
            guard verified.mode == .paid else { return }

            if let accessEnvelope, entitlement?.access == .pro {
                await validateCachedAccess(accessEnvelope, token: token)
            } else if entitlement?.access == .trial {
                return
            } else if !terminalDenyActive, !trialRequestAttempted {
                trialRequestAttempted = true
                await requestTrial(token: token)
            }
        } catch {
            // Local signed access remains authoritative during transport outages.
        }
    }

    func activate(email: String, code: String) async throws {
        let token = beginOperation()
        let expectedMarker: CommercialTerminalMarker?
        do { expectedMarker = try await worker.prepareClearanceMarker() }
        catch { throw CommercialAccessControllerError.storage }
        if let expectedMarker {
            terminalDenyActive = true
            terminalMarker = expectedMarker
            resolveState()
        }
        let identity = try await clientIdentity()
        let deviceName = await deviceWorker.name()
        let request = CommercialLicenseActivateRequest(
            email: email,
            activationCode: code,
            deviceName: deviceName,
            identity: identity
        )
        let envelope: SignedEnvelope
        do { envelope = try await client.activate(request, locale: locale) }
        catch { throw sanitized(error) }
        guard isCurrent(token) else { return }
        let payload = try verifiedEntitlement(envelope, expectedDeviceHash: identity.deviceHash)
        guard payload.access == .pro else { throw CommercialAccessControllerError.invalidCredential }
        do {
            try await persistAccess(
                envelope,
                payload: payload,
                clearsTerminalMarkerNonce: expectedMarker?.nonce
            )
        }
        catch { throw CommercialAccessControllerError.storage }
        guard isCurrent(token) else { return }
        accessEnvelope = envelope
        entitlement = payload
        do {
            guard try await worker.compareAndDeleteTerminalMarker(
                expectedNonce: expectedMarker?.nonce
            ) else {
                throw CommercialAccessControllerError.storage
            }
            terminalDenyActive = false
            terminalMarker = nil
            hasPendingTerminalCleanup = false
        } catch {
            terminalDenyActive = true
            setState(.free(reason: .serverDenied))
            throw CommercialAccessControllerError.storage
        }
        resolveState()
    }

    func deactivateCurrentDevice() async throws {
        let token = beginOperation()
        let envelope: SignedEnvelope?
        if let accessEnvelope {
            envelope = accessEnvelope
        } else {
            envelope = try? await worker.loadAccess()?.envelope
        }
        guard let envelope else {
            throw CommercialAccessControllerError.noCredential
        }
        let hash: String
        do { hash = try await deviceWorker.hash() }
        catch { throw CommercialAccessControllerError.identityUnavailable }
        do {
            let payload = try verifier.verifyEntitlement(envelope)
            guard payload.deviceHash == hash else {
                throw CommercialAccessControllerError.invalidCredential
            }
        } catch let error as CommercialAccessControllerError {
            throw error
        } catch {
            throw CommercialAccessControllerError.invalidCredential
        }
        let request = CommercialLicenseDeactivateRequest(credential: envelope, deviceHash: hash)
        do {
            try await client.deactivate(request, locale: locale)
        } catch {
            if Self.isTerminal(error) {
                let reason = Self.terminalReason(error) ?? .deviceDeactivated
                try await applyTerminal(reason, token: token)
                return
            }
            throw sanitized(error)
        }
        guard isCurrent(token) else { return }
        try await applyTerminal(.deviceDeactivated, token: token)
    }

    private func loadLocalState(token: Int) async {
        do {
            let cachedPolicy = try await worker.loadPolicy()
            guard isCurrent(token) else { return }

            if let cachedPolicy {
                policy = try verifier.verifyPolicyEnvelope(cachedPolicy)
                if clock.now < policy!.effectiveAt { throw CommercialVerificationError.notEffective }
            } else if let bootstrap = try bootstrapEnvelope() {
                policy = try verifier.verifyPolicyEnvelope(bootstrap)
                if clock.now < policy!.effectiveAt { throw CommercialVerificationError.notEffective }
            } else {
                policy = nil
            }
        } catch {
            policy = nil
            setState(.free(reason: .policyInvalid))
        }

        do {
            if let marker = try await worker.loadTerminalMarker() {
                terminalDenyActive = true
                terminalMarker = marker
            }
        } catch {
            // A corrupt or temporarily unreadable deny marker is itself a reason
            // to fail closed until an explicit activation can clear it.
            terminalDenyActive = true
        }

        do {
            let cachedAccess = try await worker.loadAccess()
            guard isCurrent(token) else { return }
            if cachedAccess?.status == .terminal {
                terminalDenyActive = true
                let marker = terminalMarker ?? CommercialTerminalMarker(
                    reason: cachedAccess?.terminalReason ?? .revoked
                )
                terminalMarker = marker
                clearLocalAccess()
                setState(.free(reason: .serverDenied))
                do {
                    try await worker.saveTerminalMarker(marker)
                    try await worker.deleteAccess()
                    hasPendingTerminalCleanup = false
                } catch {
                    hasPendingTerminalCleanup = true
                }
                return
            }
            if terminalDenyActive {
                if let cachedAccess,
                   cachedAccess.status == .active,
                   cachedAccess.clearsTerminalMarkerNonce == terminalMarker?.nonce,
                   await validMarkerClearingAccess(cachedAccess)
                {
                    do {
                        guard try await worker.compareAndDeleteTerminalMarker(
                            expectedNonce: cachedAccess.clearsTerminalMarkerNonce
                        ) else {
                            throw CommercialAccessControllerError.storage
                        }
                        terminalDenyActive = false
                        terminalMarker = nil
                        hasPendingTerminalCleanup = false
                    } catch {
                        clearLocalAccess()
                        setState(.free(reason: .serverDenied))
                        return
                    }
                } else {
                    clearLocalAccess()
                    return
                }
            }
            accessEnvelope = cachedAccess?.envelope
            entitlement = try cachedAccess?.envelope.map(verifier.verifyEntitlement)
            timeAnchor = cachedAccess?.anchor
            if let entitlement {
                let hash = try await deviceWorker.hash()
                guard isCurrent(token) else { return }
                guard entitlement.deviceHash == hash else {
                    accessEnvelope = nil
                    self.entitlement = nil
                    timeAnchor = nil
                    return
                }
            }
        } catch {
            // A transient Keychain/anchor read failure must not revoke an already
            // verified paid credential held by this controller. Trials fail closed.
            if entitlement?.access != .pro {
                accessEnvelope = nil
                entitlement = nil
                timeAnchor = nil
            }
        }
    }

    private func validateCachedAccess(_ envelope: SignedEnvelope, token: Int) async {
        do {
            let identity = try await clientIdentity()
            let refreshed = try await client.validate(
                CommercialLicenseValidateRequest(credential: envelope, identity: identity),
                locale: locale
            )
            guard isCurrent(token) else { return }
            let payload = try verifiedEntitlement(refreshed, expectedDeviceHash: identity.deviceHash)
            try await persistAccess(refreshed, payload: payload, clearsTerminalMarkerNonce: nil)
            guard isCurrent(token) else { return }
            accessEnvelope = refreshed
            entitlement = payload
            resolveState()
        } catch {
            guard isCurrent(token), Self.isTerminal(error) else { return }
            let reason = Self.terminalReason(error) ?? .revoked
            try? await applyTerminal(reason, token: token)
        }
    }

    private func requestTrial(token: Int) async {
        do {
            let identity = try await clientIdentity()
            let envelope = try await client.startTrial(
                CommercialTrialStartRequest(identity: identity),
                locale: locale
            )
            guard isCurrent(token) else { return }
            let payload = try verifiedEntitlement(envelope, expectedDeviceHash: identity.deviceHash)
            guard payload.access == .trial else { return }
            try await persistAccess(envelope, payload: payload, clearsTerminalMarkerNonce: nil)
            guard isCurrent(token) else { return }
            accessEnvelope = envelope
            entitlement = payload
            terminalDenyActive = false
            resolveState()
        } catch {
            // A trial is server-owned and one-time. Keep the deterministic free state.
        }
    }

    private func resolveState() {
        let effective = effectiveTime()
        if let policy, policy.mode == .allFree {
            if effective.now < policy.expiresAt {
                setState(.allFree)
                return
            }
            let graceUntil = policy.expiresAt.addingTimeInterval(Self.graceInterval)
            if effective.now <= graceUntil {
                setState(.allFreeGrace(until: graceUntil))
                return
            }
        }
        if terminalDenyActive {
            setState(.free(reason: .serverDenied))
            return
        }

        if let entitlement, entitlement.issuedAt <= effective.now {
            switch entitlement.access {
        case .pro:
            guard let maximum = entitlement.maximumBuildNumber, buildNumber <= maximum else {
                setState(.free(reason: .buildNotEligible))
                return
            }
            if let expiry = entitlement.expiresAt, effective.now >= expiry {
                setState(.free(reason: .credentialInvalid))
                return
            }
            setState(.pro(CommercialEntitlement(payload: entitlement)))
            return
        case .trial:
            guard !effective.uptimeReset,
                  timeAnchor?.issuedAt == entitlement.issuedAt
            else {
                setState(.free(reason: .clockRequiresValidation))
                return
            }
            guard let expiresAt = entitlement.expiresAt, effective.now < expiresAt else {
                setState(.free(reason: .trialExpired))
                return
            }
            setState(.trial(expiresAt: expiresAt))
            return
        case .free, .allFree:
            break
            }
        } else if entitlement != nil {
            setState(.free(reason: .credentialInvalid))
            return
        }

        guard let policy else {
            if state != .free(reason: .policyInvalid) {
                setState(.free(reason: .policyUnavailable))
            }
            return
        }
        guard effective.now < policy.expiresAt else {
            setState(.free(reason: .policyExpired))
            return
        }
        setState(.free(reason: .trialUnavailable))
    }

    private func effectiveTime() -> (now: Date, uptimeReset: Bool) {
        guard let timeAnchor else { return (clock.now, false) }
        guard clock.currentUptime >= timeAnchor.systemUptime else {
            return (max(clock.now, timeAnchor.issuedAt), true)
        }
        let monotonic = timeAnchor.issuedAt.addingTimeInterval(clock.currentUptime - timeAnchor.systemUptime)
        return (max(clock.now, monotonic), false)
    }

    private func clientIdentity() async throws -> CommercialClientIdentity {
        do {
            return CommercialClientIdentity(
                deviceHash: try await deviceWorker.hash(),
                appVersion: appVersion,
                buildNumber: buildNumber
            )
        } catch {
            throw CommercialAccessControllerError.identityUnavailable
        }
    }

    private func verifiedEntitlement(
        _ envelope: SignedEnvelope,
        expectedDeviceHash: String
    ) throws -> EntitlementPayload {
        let payload: EntitlementPayload
        do { payload = try verifier.verifyEntitlement(envelope) }
        catch { throw CommercialAccessControllerError.invalidCredential }
        guard payload.deviceHash == expectedDeviceHash,
              payload.appVersion == appVersion,
              payload.buildNumber == buildNumber
        else { throw CommercialAccessControllerError.invalidCredential }
        return payload
    }

    private func validMarkerClearingAccess(_ record: CommercialAccessRecord) async -> Bool {
        guard let envelope = record.envelope,
              let hash = try? await deviceWorker.hash(),
              let payload = try? verifiedEntitlement(envelope, expectedDeviceHash: hash)
        else { return false }
        return payload.access == .pro
    }

    private func persistAccess(
        _ envelope: SignedEnvelope,
        payload: EntitlementPayload,
        clearsTerminalMarkerNonce: UUID?
    ) async throws {
        let anchor = CommercialTimeAnchor(issuedAt: payload.issuedAt, systemUptime: clock.currentUptime)
        try await worker.saveAccess(
            .active(
                envelope: envelope,
                anchor: anchor,
                clearsTerminalMarkerNonce: clearsTerminalMarkerNonce
            )
        )
        timeAnchor = anchor
    }

    private func applyTerminal(_ reason: CommercialTerminalReason, token: Int) async throws {
        guard isCurrent(token) else { return }
        terminalDenyActive = true
        let marker = CommercialTerminalMarker(reason: reason)
        terminalMarker = marker
        clearLocalAccess()
        setState(.free(reason: .serverDenied))

        let markerSaved: Bool
        do {
            try await worker.saveTerminalMarker(marker)
            markerSaved = true
        } catch {
            markerSaved = false
        }

        do {
            try await worker.saveAccess(.terminal(reason))
        } catch {
            // If the atomic Keychain deny write itself is unavailable, removing
            // the old credential is the safe fallback. The independent marker
            // still protects restarts when available.
            do { try await worker.deleteAccess() }
            catch {
                hasPendingTerminalCleanup = true
                throw CommercialAccessControllerError.storage
            }
            hasPendingTerminalCleanup = false
            throw CommercialAccessControllerError.storage
        }
        guard isCurrent(token) else { return }
        guard markerSaved else {
            // Keep the Keychain tombstone until the independent marker can be
            // persisted; deleting it now would make a restart ambiguous.
            hasPendingTerminalCleanup = true
            throw CommercialAccessControllerError.storage
        }
        do {
            try await worker.deleteAccess()
            hasPendingTerminalCleanup = false
        } catch {
            hasPendingTerminalCleanup = true
            throw CommercialAccessControllerError.storage
        }
    }

    private func clearLocalAccess() {
        accessEnvelope = nil
        entitlement = nil
        timeAnchor = nil
    }

    private func beginOperation() -> Int {
        generation += 1
        return generation
    }

    private func isCurrent(_ token: Int) -> Bool { generation == token }

    private func setState(_ newState: CommercialAccessState) {
        guard state != newState else { return }
        state = newState
        onStateChange?(newState)
    }

    private func sanitized(_ error: Error) -> CommercialAccessControllerError {
        if error is CommercialAccessControllerError {
            return error as! CommercialAccessControllerError
        }
        return .network
    }

    private static func isTerminal(_ error: Error) -> Bool {
        terminalReason(error) != nil
    }

    private static func terminalReason(_ error: Error) -> CommercialTerminalReason? {
        guard case let CommercialPolicyClientError.server(_, detail) = error else { return nil }
        switch detail.code {
        case "license_refunded": return .refunded
        case "license_revoked": return .revoked
        case "device_deactivated": return .deviceDeactivated
        default: return nil
        }
    }
}
