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

    init(store: CommercialCredentialStoring) { self.store = store }

    func loadPolicy() throws -> SignedEnvelope? { try store.loadPolicyEnvelope() }
    func savePolicy(_ envelope: SignedEnvelope) throws { try store.savePolicyEnvelope(envelope) }
    func loadAccess() throws -> SignedEnvelope? { try store.loadAccessEnvelope() }
    func saveAccess(_ envelope: SignedEnvelope, anchor: CommercialTimeAnchor) throws {
        try store.saveAccessEnvelope(envelope)
        try store.saveTimeAnchor(anchor)
    }
    func deleteAccess() throws { try store.deleteAccessEnvelope() }
    func loadAnchor() throws -> CommercialTimeAnchor? { try store.loadTimeAnchor() }
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

    init(
        store: CommercialCredentialStoring,
        verifier: CommercialSignatureVerifier,
        client: CommercialPolicyFetching,
        device: CommercialDeviceIdentifying,
        appVersion: String,
        buildNumber: Int,
        locale: CommercialLocale,
        clock: CommercialTimeProviding = SystemCommercialClock(),
        bootstrapEnvelope: @escaping () throws -> SignedEnvelope?
    ) {
        worker = CommercialCredentialWorker(store: store)
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
        case let .free(reason):
            guard let policy else { return false }
            if policy.mode == .allFree, reason == .policyExpired {
                return false
            }
            return !policy.features[feature]
        }
    }

    func refresh() async {
        let token = beginOperation()
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

            if let accessEnvelope {
                await validateCachedAccess(accessEnvelope, token: token)
            } else if !trialRequestAttempted {
                trialRequestAttempted = true
                await requestTrial(token: token)
            }
        } catch {
            // Local signed access remains authoritative during transport outages.
        }
    }

    func activate(email: String, code: String) async throws {
        let token = beginOperation()
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
        do { try await persistAccess(envelope, payload: payload) }
        catch { throw CommercialAccessControllerError.storage }
        guard isCurrent(token) else { return }
        accessEnvelope = envelope
        entitlement = payload
        resolveState()
    }

    func deactivateCurrentDevice() async throws {
        let token = beginOperation()
        let envelope: SignedEnvelope?
        if let accessEnvelope {
            envelope = accessEnvelope
        } else {
            envelope = try? await worker.loadAccess()
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
                try? await worker.deleteAccess()
                guard isCurrent(token) else { return }
                clearLocalAccess()
                resolveState()
                return
            }
            throw sanitized(error)
        }
        guard isCurrent(token) else { return }
        do { try await worker.deleteAccess() }
        catch { throw CommercialAccessControllerError.storage }
        clearLocalAccess()
        resolveState()
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
            let cachedAccess = try await worker.loadAccess()
            let cachedAnchor = try await worker.loadAnchor()
            guard isCurrent(token) else { return }
            accessEnvelope = cachedAccess
            entitlement = try cachedAccess.map(verifier.verifyEntitlement)
            timeAnchor = cachedAnchor
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
            accessEnvelope = nil
            entitlement = nil
            timeAnchor = nil
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
            try await persistAccess(refreshed, payload: payload)
            guard isCurrent(token) else { return }
            accessEnvelope = refreshed
            entitlement = payload
            resolveState()
        } catch {
            guard isCurrent(token), Self.isTerminal(error) else { return }
            try? await worker.deleteAccess()
            guard isCurrent(token) else { return }
            clearLocalAccess()
            resolveState()
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
            try await persistAccess(envelope, payload: payload)
            guard isCurrent(token) else { return }
            accessEnvelope = envelope
            entitlement = payload
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

    private func persistAccess(_ envelope: SignedEnvelope, payload: EntitlementPayload) async throws {
        let anchor = CommercialTimeAnchor(issuedAt: payload.issuedAt, systemUptime: clock.currentUptime)
        try await worker.saveAccess(envelope, anchor: anchor)
        timeAnchor = anchor
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
        guard case let CommercialPolicyClientError.server(_, detail) = error else { return false }
        return ["license_refunded", "license_revoked", "device_deactivated"].contains(detail.code)
    }
}
