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

enum CommercialPresentationNotice: Equatable {
    case network
    case server
    case storage
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
    case activationRejected
    case deviceLimit
}

@MainActor
protocol CommercialAccessProviding: AnyObject {
    var state: CommercialAccessState { get }
    var snapshot: CommercialAccessSnapshot { get }
    var onStateChange: ((CommercialAccessState) -> Void)? { get set }
    var presentationPolicy: CommercialPolicy? { get }
    var presentationNotice: CommercialPresentationNotice? { get }
    func requestPurchase(for feature: CommercialFeature)
}

extension CommercialAccessProviding {
    var presentationPolicy: CommercialPolicy? { nil }
    var presentationNotice: CommercialPresentationNotice? { nil }
}

@MainActor
protocol CommercialAccessRefreshing: CommercialAccessProviding {
    func refresh() async
}

struct CommercialAccessSnapshot: Equatable {
    let state: CommercialAccessState
    let availableFeatures: Set<CommercialFeature>
    let proBadgedFeatures: Set<CommercialFeature>

    func canUse(_ feature: CommercialFeature) -> Bool {
        availableFeatures.contains(feature)
    }

    func showsProBadge(for feature: CommercialFeature) -> Bool {
        proBadgedFeatures.contains(feature)
    }
}

@MainActor
final class UnrestrictedCommercialAccess: CommercialAccessProviding {
    static let shared = UnrestrictedCommercialAccess()
    let state: CommercialAccessState = .allFree
    let snapshot = CommercialAccessSnapshot(
        state: .allFree,
        availableFeatures: Set(CommercialFeature.allCases),
        proBadgedFeatures: []
    )
    var onStateChange: ((CommercialAccessState) -> Void)?

    private init() {}

    func requestPurchase(for feature: CommercialFeature) {}
}

@MainActor
final class UnavailableCommercialAccess: CommercialAccessProviding {
    let state: CommercialAccessState = .free(reason: .policyUnavailable)
    let snapshot = CommercialAccessSnapshot(
        state: .free(reason: .policyUnavailable),
        availableFeatures: [],
        proBadgedFeatures: []
    )
    var onStateChange: ((CommercialAccessState) -> Void)?
    var purchaseRequestHandler: ((CommercialFeature) -> Void)?

    func requestPurchase(for feature: CommercialFeature) {
        purchaseRequestHandler?(feature)
    }
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
    private let coordinator: CommercialCredentialMutationCoordinator

    init(
        store: CommercialCredentialStoring,
        markerStore: CommercialTerminalMarkerStoring,
        coordinator: CommercialCredentialMutationCoordinator
    ) {
        self.store = store
        self.markerStore = markerStore
        self.coordinator = coordinator
    }

    func loadPolicy() throws -> SignedEnvelope? { try store.loadPolicyEnvelope() }
    func savePolicy(_ envelope: SignedEnvelope) throws { try store.savePolicyEnvelope(envelope) }

    func snapshot(prepareClearance: Bool = false) throws -> CommercialCredentialMutationSnapshot {
        try coordinator.snapshot(
            store: store,
            markerStore: markerStore,
            prepareClearance: prepareClearance
        )
    }

    func commitActive(
        expected: CommercialCredentialMutationSnapshot,
        record: CommercialAccessRecord,
        clearingMarkerNonce: UUID?
    ) throws -> Bool {
        try coordinator.commitActive(
            expected: expected,
            record: record,
            clearingMarkerNonce: clearingMarkerNonce,
            store: store,
            markerStore: markerStore
        )
    }

    func commitTerminal(
        expected: CommercialCredentialMutationSnapshot,
        reason: CommercialTerminalReason
    ) -> CommercialTerminalCommitOutcome {
        coordinator.commitTerminal(
            expected: expected,
            reason: reason,
            store: store,
            markerStore: markerStore
        )
    }

    func cleanupTerminal(
        marker: CommercialTerminalMarker,
        expectedActive: CommercialAccessRecord?
    ) throws -> Bool {
        try coordinator.cleanupTerminal(
            marker: marker,
            expectedActive: expectedActive,
            store: store,
            markerStore: markerStore
        )
    }

    func clearMarker(
        expected: CommercialCredentialMutationSnapshot,
        nonce: UUID
    ) throws -> Bool {
        try coordinator.clearMarker(
            expected: expected,
            nonce: nonce,
            store: store,
            markerStore: markerStore
        )
    }
}

private actor CommercialDeviceWorker {
    private let device: CommercialDeviceIdentifying
    init(device: CommercialDeviceIdentifying) { self.device = device }
    func hash() throws -> String { try device.deviceHash() }
    func name() -> String { device.displayName() }
}

@MainActor
final class CommercialAccessController: CommercialAccessRefreshing {
    private struct PresentationState: Equatable {
        let accessState: CommercialAccessState
        let proBadges: Set<CommercialFeature>
    }

    private struct PresentationDetails: Equatable {
        let policy: CommercialPolicy?
        let notice: CommercialPresentationNotice?
    }

    private static let graceInterval: TimeInterval = 14 * 24 * 60 * 60

    private(set) var state: CommercialAccessState = .free(reason: .policyUnavailable)
    var onStateChange: ((CommercialAccessState) -> Void)? {
        didSet { lastNotifiedPresentation = nil }
    }
    var onPresentationChange: (() -> Void)? {
        didSet { lastNotifiedDetails = nil }
    }
    var purchaseRequestHandler: ((CommercialFeature) -> Void)?

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
    var presentationPolicy: CommercialPolicy? { policy }
    private(set) var presentationNotice: CommercialPresentationNotice?
    private var accessEnvelope: SignedEnvelope?
    private var entitlement: EntitlementPayload?
    private var timeAnchor: CommercialTimeAnchor?
    private var generation = 0
    private var trialRequestAttempted = false
    private var terminalDenyActive = false
    private var terminalMarker: CommercialTerminalMarker?
    private var pendingTerminalAccess: CommercialAccessRecord?
    private(set) var hasPendingTerminalCleanup = false
    private var lastNotifiedPresentation: PresentationState?
    private var lastNotifiedDetails: PresentationDetails?

    init(
        store: CommercialCredentialStoring,
        markerStore: CommercialTerminalMarkerStoring,
        coordinator: CommercialCredentialMutationCoordinator = .shared,
        verifier: CommercialSignatureVerifier,
        client: CommercialPolicyFetching,
        device: CommercialDeviceIdentifying,
        appVersion: String,
        buildNumber: Int,
        locale: CommercialLocale,
        clock: CommercialTimeProviding = SystemCommercialClock(),
        bootstrapEnvelope: @escaping () throws -> SignedEnvelope?
    ) {
        worker = CommercialCredentialWorker(
            store: store,
            markerStore: markerStore,
            coordinator: coordinator
        )
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

    func showsProBadge(for feature: CommercialFeature) -> Bool {
        guard case .free = state,
              let policy,
              policy.mode == .paid
        else { return false }
        return policy.features[feature]
    }

    var snapshot: CommercialAccessSnapshot {
        CommercialAccessSnapshot(
            state: state,
            availableFeatures: Set(CommercialFeature.allCases.filter { canUse($0) }),
            proBadgedFeatures: Set(CommercialFeature.allCases.filter { showsProBadge(for: $0) })
        )
    }

    func requestPurchase(for feature: CommercialFeature) {
        purchaseRequestHandler?(feature)
    }

    func refresh() async {
        let token = beginOperation()
        if terminalDenyActive, hasPendingTerminalCleanup {
            do {
                guard let terminalMarker else { throw CommercialAccessControllerError.storage }
                hasPendingTerminalCleanup = try await worker.cleanupTerminal(
                    marker: terminalMarker,
                    expectedActive: pendingTerminalAccess
                )
                if !hasPendingTerminalCleanup { pendingTerminalAccess = nil }
            } catch {
                hasPendingTerminalCleanup = true
            }
        }
        await loadLocalState(token: token)
        guard isCurrent(token) else { return }
        resolveState()
        notifyPresentationIfNeeded()

        do {
            let envelope = try await client.fetchPolicy(locale: locale)
            guard isCurrent(token) else { return }
            let verified = try verifier.verifyPolicy(envelope, at: clock.now)
            try await worker.savePolicy(envelope)
            guard isCurrent(token) else { return }
            policy = verified
            presentationNotice = nil
            resolveState()
            notifyPresentationIfNeeded()
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
            guard isCurrent(token) else { return }
            presentationNotice = Self.notice(for: error)
            notifyPresentationIfNeeded()
        }
    }

    func activate(email: String, code: String) async throws {
        let token = beginOperation()
        let snapshot: CommercialCredentialMutationSnapshot
        do { snapshot = try await worker.snapshot(prepareClearance: true) }
        catch { throw CommercialAccessControllerError.storage }
        let expectedMarker = snapshot.marker
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
        let anchor = CommercialTimeAnchor(
            issuedAt: payload.issuedAt,
            systemUptime: clock.currentUptime
        )
        let record = CommercialAccessRecord.active(
            envelope: envelope,
            anchor: anchor,
            clearsTerminalMarkerNonce: expectedMarker?.nonce
        )
        let committed: Bool
        do {
            committed = try await worker.commitActive(
                expected: snapshot,
                record: record,
                clearingMarkerNonce: expectedMarker?.nonce
            )
        }
        catch { throw CommercialAccessControllerError.storage }
        guard isCurrent(token) else { return }
        guard committed else {
            await loadLocalState(token: token)
            resolveState()
            throw CommercialAccessControllerError.storage
        }
        accessEnvelope = envelope
        entitlement = payload
        timeAnchor = anchor
        terminalDenyActive = false
        terminalMarker = nil
        pendingTerminalAccess = nil
        hasPendingTerminalCleanup = false
        resolveState()
    }

    func deactivateCurrentDevice() async throws {
        let token = beginOperation()
        let snapshot: CommercialCredentialMutationSnapshot
        do { snapshot = try await worker.snapshot() }
        catch { throw CommercialAccessControllerError.storage }
        let envelope = snapshot.access?.envelope
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
                guard try await applyTerminal(reason, token: token, expected: snapshot) else {
                    throw CommercialAccessControllerError.storage
                }
                return
            }
            throw sanitized(error)
        }
        guard isCurrent(token) else { return }
        guard try await applyTerminal(.deviceDeactivated, token: token, expected: snapshot) else {
            throw CommercialAccessControllerError.storage
        }
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
            let snapshot = try await worker.snapshot()
            guard isCurrent(token) else { return }
            terminalDenyActive = snapshot.marker != nil
            terminalMarker = snapshot.marker
            let cachedAccess = snapshot.access
            if cachedAccess?.status == .terminal {
                terminalDenyActive = true
                let marker = snapshot.marker ?? CommercialTerminalMarker(
                    reason: cachedAccess?.terminalReason ?? .revoked,
                    nonce: cachedAccess?.terminalMarkerNonce ?? UUID()
                )
                terminalMarker = marker
                clearLocalAccess()
                setState(.free(reason: .serverDenied))
                do {
                    hasPendingTerminalCleanup = try await worker.cleanupTerminal(
                        marker: marker,
                        expectedActive: nil
                    )
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
                        guard let nonce = cachedAccess.clearsTerminalMarkerNonce,
                              try await worker.clearMarker(expected: snapshot, nonce: nonce)
                        else {
                            throw CommercialAccessControllerError.storage
                        }
                        terminalDenyActive = false
                        terminalMarker = nil
                        pendingTerminalAccess = nil
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
        } catch let error as CommercialCredentialSnapshotError {
            if case .access(marker: nil) = error, entitlement?.access == .pro {
                // Preserve an already verified paid credential across transient
                // Keychain read failures only when the deny marker is absent.
                return
            }
            terminalDenyActive = true
            terminalMarker = nil
            clearLocalAccess()
            setState(.free(reason: .serverDenied))
        } catch {
            terminalDenyActive = true
            terminalMarker = nil
            clearLocalAccess()
            setState(.free(reason: .serverDenied))
        }
    }

    private func validateCachedAccess(_ envelope: SignedEnvelope, token: Int) async {
        let snapshot: CommercialCredentialMutationSnapshot
        do {
            snapshot = try await worker.snapshot()
            guard snapshot.marker == nil,
                  snapshot.access?.status == .active,
                  snapshot.access?.envelope == envelope
            else { return }
        } catch {
            guard isCurrent(token) else { return }
            presentationNotice = .storage
            notifyPresentationIfNeeded()
            return
        }
        do {
            let identity = try await clientIdentity()
            let refreshed = try await client.validate(
                CommercialLicenseValidateRequest(credential: envelope, identity: identity),
                locale: locale
            )
            guard isCurrent(token) else { return }
            let payload = try verifiedEntitlement(refreshed, expectedDeviceHash: identity.deviceHash)
            let anchor = CommercialTimeAnchor(
                issuedAt: payload.issuedAt,
                systemUptime: clock.currentUptime
            )
            let record = CommercialAccessRecord.active(envelope: refreshed, anchor: anchor)
            guard try await worker.commitActive(
                expected: snapshot,
                record: record,
                clearingMarkerNonce: nil
            ) else { return }
            guard isCurrent(token) else { return }
            accessEnvelope = refreshed
            entitlement = payload
            timeAnchor = anchor
            resolveState()
        } catch {
            guard isCurrent(token) else { return }
            if Self.isTerminal(error) {
                let reason = Self.terminalReason(error) ?? .revoked
                _ = try? await applyTerminal(reason, token: token, expected: snapshot)
            } else {
                presentationNotice = Self.notice(for: error)
                notifyPresentationIfNeeded()
            }
        }
    }

    private func requestTrial(token: Int) async {
        let snapshot: CommercialCredentialMutationSnapshot
        do {
            snapshot = try await worker.snapshot()
            guard snapshot.marker == nil else { return }
        } catch {
            guard isCurrent(token) else { return }
            presentationNotice = .storage
            notifyPresentationIfNeeded()
            return
        }
        do {
            let identity = try await clientIdentity()
            let envelope = try await client.startTrial(
                CommercialTrialStartRequest(identity: identity),
                locale: locale
            )
            guard isCurrent(token) else { return }
            let payload = try verifiedEntitlement(envelope, expectedDeviceHash: identity.deviceHash)
            guard payload.access == .trial else { return }
            let anchor = CommercialTimeAnchor(
                issuedAt: payload.issuedAt,
                systemUptime: clock.currentUptime
            )
            let record = CommercialAccessRecord.active(envelope: envelope, anchor: anchor)
            guard try await worker.commitActive(
                expected: snapshot,
                record: record,
                clearingMarkerNonce: nil
            ) else { return }
            guard isCurrent(token) else { return }
            accessEnvelope = envelope
            entitlement = payload
            timeAnchor = anchor
            terminalDenyActive = false
            resolveState()
        } catch {
            // A trial is server-owned and one-time. Keep the deterministic free state.
            guard isCurrent(token) else { return }
            presentationNotice = Self.notice(for: error)
            notifyPresentationIfNeeded()
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

    private func applyTerminal(
        _ reason: CommercialTerminalReason,
        token: Int,
        expected: CommercialCredentialMutationSnapshot
    ) async throws -> Bool {
        guard isCurrent(token) else { return false }
        let outcome = await worker.commitTerminal(expected: expected, reason: reason)
        guard outcome.committed, let marker = outcome.marker else { return false }
        guard isCurrent(token) else { return true }
        terminalDenyActive = true
        terminalMarker = marker
        pendingTerminalAccess = expected.access
        hasPendingTerminalCleanup = outcome.cleanupPending
        clearLocalAccess()
        setState(.free(reason: .serverDenied))
        if outcome.storageFailed {
            throw CommercialAccessControllerError.storage
        }
        return true
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
        notifyPresentationIfNeeded()
    }

    private func notifyPresentationIfNeeded() {
        let snapshot = PresentationState(
            accessState: state,
            proBadges: self.snapshot.proBadgedFeatures
        )
        if let onStateChange, snapshot != lastNotifiedPresentation {
            lastNotifiedPresentation = snapshot
            onStateChange(state)
        }
        let details = PresentationDetails(policy: policy, notice: presentationNotice)
        if let onPresentationChange, details != lastNotifiedDetails {
            lastNotifiedDetails = details
            onPresentationChange()
        }
    }

    private static func notice(for error: Error) -> CommercialPresentationNotice {
        if error is CommercialCredentialStoreError { return .storage }
        if error is URLError { return .network }
        if case CommercialPolicyClientError.transport = error { return .network }
        return .server
    }

    private func sanitized(_ error: Error) -> CommercialAccessControllerError {
        if error is CommercialAccessControllerError {
            return error as! CommercialAccessControllerError
        }
        if case let CommercialPolicyClientError.server(_, detail) = error {
            switch detail.code {
            case "device_limit_reached": return .deviceLimit
            case "license_not_found", "license_not_active", "license_refunded", "license_revoked":
                return .activationRejected
            default: break
            }
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
