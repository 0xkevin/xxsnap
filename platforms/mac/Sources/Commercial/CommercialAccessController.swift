import Foundation
import Darwin

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
    case credentialBindingInvalid
    case deviceDeactivated
    case buildNotEntitled
    case licenseRevoked
    case licenseRefunded
    case trialAlreadyUsed
    case trialUnavailable
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
final class UnrestrictedCommercialAccess: CommercialAccessRefreshing, CommercialRefreshControlling {
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
    func refresh() async {}
    private let generationWorker = CommercialRefreshGenerationWorker()
    var paidValidationContext: CommercialPaidValidationContext? { nil }
    func loadCachedCommercialState() async {}
    func beginCommercialRefreshGeneration() async -> CommercialRefreshGeneration {
        await generationWorker.begin()
    }
    func invalidateCommercialRefreshGeneration() async {
        await generationWorker.invalidate()
    }
    func performCommercialRefresh(
        generation: CommercialRefreshGeneration,
        validatePaidCredential: Bool
    ) async -> CommercialRefreshResult {
        .success
    }
}

private actor CommercialRefreshGenerationWorker {
    private let coordinator = CommercialCredentialMutationCoordinator()

    func begin() -> CommercialRefreshGeneration { coordinator.beginRefreshGeneration() }
    func invalidate() { coordinator.invalidateRefreshGeneration() }
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
    var bootSessionID: String { get }
}

extension CommercialTimeProviding {
    var bootSessionID: String { "unknown-boot-session" }
}

final class SystemCommercialClock: CommercialTimeProviding {
    var now: Date { Date() }
    var currentUptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
    let bootSessionID: String = {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib = [CTL_KERN, KERN_BOOTTIME]
        if sysctl(&mib, u_int(mib.count), &bootTime, &size, nil, 0) == 0 {
            return "\(bootTime.tv_sec).\(bootTime.tv_usec)"
        }
        let approximate = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        return "approx-\(Int64(approximate.rounded()))"
    }()
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

    func loadPolicy() throws -> CommercialPolicyRecord? { try store.loadPolicyRecord() }
    func beginRefreshGeneration() -> CommercialRefreshGeneration {
        coordinator.beginRefreshGeneration()
    }
    func invalidateRefreshGeneration() {
        coordinator.invalidateRefreshGeneration()
    }
    func isRefreshGenerationCurrent(_ generation: CommercialRefreshGeneration) -> Bool {
        coordinator.isRefreshGenerationCurrent(generation)
    }
    func savePolicy(
        _ record: CommercialPolicyRecord,
        refresh: CommercialRefreshGeneration
    ) throws -> Bool {
        try coordinator.savePolicy(record, refresh: refresh, store: store)
    }

    func saveBootstrapPolicy(_ record: CommercialPolicyRecord) throws {
        try store.savePolicyRecord(record)
    }

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
        clearingMarkerNonce: UUID?,
        refresh: CommercialRefreshGeneration? = nil
    ) throws -> Bool {
        try coordinator.commitActive(
            expected: expected,
            record: record,
            clearingMarkerNonce: clearingMarkerNonce,
            refresh: refresh,
            store: store,
            markerStore: markerStore
        )
    }

    func commitTerminal(
        expected: CommercialCredentialMutationSnapshot,
        reason: CommercialTerminalReason,
        refresh: CommercialRefreshGeneration? = nil
    ) -> CommercialTerminalCommitOutcome {
        coordinator.commitTerminal(
            expected: expected,
            reason: reason,
            refresh: refresh,
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

private actor CommercialBootstrapWorker {
    private let loadEnvelope: @Sendable () throws -> SignedEnvelope?

    init(loadEnvelope: @escaping @Sendable () throws -> SignedEnvelope?) {
        self.loadEnvelope = loadEnvelope
    }

    func load() throws -> SignedEnvelope? { try loadEnvelope() }
}

private actor CommercialDeviceWorker {
    private let device: CommercialDeviceIdentifying
    init(device: CommercialDeviceIdentifying) { self.device = device }
    func hash() throws -> String { try device.deviceHash() }
    func name() -> String { device.displayName() }
}

@MainActor
final class CommercialAccessController: CommercialAccessRefreshing, CommercialRefreshControlling {
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
    private let bootstrapWorker: CommercialBootstrapWorker
    private let verifier: CommercialSignatureVerifier
    private let client: CommercialPolicyFetching
    private let deviceWorker: CommercialDeviceWorker
    private let appVersion: String
    private let buildNumber: Int
    private let locale: CommercialLocale
    private let releasePhase: CommercialReleasePhase
    private let clock: CommercialTimeProviding
    private let diagnosticLogger: any CommercialDiagnosticLogging

    private var policy: CommercialPolicy?
    private var policyTimeAnchor: CommercialPolicyTimeAnchor?
    var presentationPolicy: CommercialPolicy? { policy }
    var paidValidationContext: CommercialPaidValidationContext? {
        guard entitlement?.access == .pro else { return nil }
        return CommercialPaidValidationContext(
            lastSuccessfulValidation: lastSuccessfulValidation,
            currentUptime: clock.currentUptime,
            trustedNowFloor: effectiveTime().now
        )
    }
    private(set) var presentationNotice: CommercialPresentationNotice?
    private var accessEnvelope: SignedEnvelope?
    private var entitlement: EntitlementPayload?
    private var timeAnchor: CommercialTimeAnchor?
    private var lastSuccessfulValidation: CommercialTimeAnchor?
    private var generation = 0
    private var trialRequestSettled = false
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
        releasePhase: CommercialReleasePhase,
        clock: CommercialTimeProviding = SystemCommercialClock(),
        diagnosticLogger: any CommercialDiagnosticLogging = NoopCommercialDiagnosticLogger.shared,
        bootstrapEnvelope: @escaping @Sendable () throws -> SignedEnvelope?
    ) {
        worker = CommercialCredentialWorker(
            store: store,
            markerStore: markerStore,
            coordinator: coordinator
        )
        bootstrapWorker = CommercialBootstrapWorker(loadEnvelope: bootstrapEnvelope)
        self.verifier = verifier
        self.client = client
        deviceWorker = CommercialDeviceWorker(device: device)
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.locale = locale
        self.releasePhase = releasePhase
        self.clock = clock
        self.diagnosticLogger = diagnosticLogger
        if releasePhase == .free {
            state = .allFree
        }
    }

    convenience init(
        bundle: Bundle = .main,
        session: URLSession = .shared,
        diagnosticLogger: any CommercialDiagnosticLogging = NoopCommercialDiagnosticLogger.shared
    ) throws {
        let verifier = try CommercialSignatureVerifier(bundle: bundle)
        let client = try CommercialPolicyClient(bundle: bundle, session: session)
        let releasePhase = try CommercialReleasePhase(bundle: bundle)
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
            releasePhase: releasePhase,
            diagnosticLogger: diagnosticLogger,
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
        guard releasePhase == .paid else { return true }
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
        guard releasePhase == .paid else { return false }
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
        if !snapshot.canUse(feature) {
            diagnosticLogger.record(.featureIntercept(
                feature: feature,
                accessKind: Self.diagnosticAccessKind(state),
                result: .blocked
            ))
        }
        purchaseRequestHandler?(feature)
    }

    func refresh() async {
        await loadCachedCommercialState()
        guard !Task.isCancelled else { return }
        let refreshGeneration = await beginCommercialRefreshGeneration()
        _ = await performCommercialRefresh(
            generation: refreshGeneration,
            validatePaidCredential: true
        )
    }

    func beginCommercialRefreshGeneration() async -> CommercialRefreshGeneration {
        await worker.beginRefreshGeneration()
    }

    func invalidateCommercialRefreshGeneration() async {
        await worker.invalidateRefreshGeneration()
    }

    func loadCachedCommercialState() async {
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
        guard isCurrent(token), !Task.isCancelled else { return }
        resolveState()
        notifyPresentationIfNeeded()
    }

    func performCommercialRefresh(
        generation refreshGeneration: CommercialRefreshGeneration,
        validatePaidCredential: Bool
    ) async -> CommercialRefreshResult {
        let token = beginOperation()
        guard await refreshIsCurrent(refreshGeneration), !Task.isCancelled else { return .cancelled }
        do {
            let response = try await client.fetchPolicyResponse(locale: locale)
            let envelope = response.envelope
            guard isCurrent(token), await refreshIsCurrent(refreshGeneration), !Task.isCancelled else {
                return .cancelled
            }
            let verificationTime = response.serverVerifiedAt ?? clock.now
            let verified = try verifier.verifyPolicy(envelope, at: verificationTime)
            let anchor = response.serverVerifiedAt.map {
                CommercialPolicyTimeAnchor(
                    serverVerifiedAt: $0,
                    systemUptime: clock.currentUptime,
                    bootSessionID: clock.bootSessionID
                )
            }
            if releasePhase == .free, verified.mode == .paid {
                presentationNotice = nil
                resolveState()
                notifyPresentationIfNeeded()
                logPolicyRefresh(
                    policy: verified,
                    at: verificationTime,
                    result: .failure,
                    error: .paidPolicyIgnoredInFreeRelease
                )
                return .success
            }
            let record = CommercialPolicyRecord(envelope: envelope, timeAnchor: anchor)
            guard !Task.isCancelled else { return .cancelled }
            guard try await worker.savePolicy(record, refresh: refreshGeneration) else {
                return .cancelled
            }
            guard isCurrent(token), await refreshIsCurrent(refreshGeneration), !Task.isCancelled else {
                return .cancelled
            }
            policy = verified
            policyTimeAnchor = anchor
            presentationNotice = nil
            resolveState()
            notifyPresentationIfNeeded()
            if verified.mode == .allFree, anchor == nil {
                logPolicyRefresh(
                    policy: verified,
                    at: verificationTime,
                    result: .failure,
                    error: .clockValidationRequired
                )
                return .retryableFailure
            }
            logPolicyRefresh(
                policy: verified,
                at: verificationTime,
                result: .success,
                error: nil
            )
            guard verified.mode == .paid else { return .success }

            if let accessEnvelope, entitlement?.access == .pro {
                guard validatePaidCredential else { return .success }
                return await validateCachedAccess(
                    accessEnvelope,
                    token: token,
                    refresh: refreshGeneration
                )
            } else if entitlement?.access == .trial {
                return .success
            } else if !terminalDenyActive, !trialRequestSettled {
                return await requestTrial(token: token, refresh: refreshGeneration)
            }
            return Task.isCancelled ? .cancelled : .success
        } catch {
            // Local signed access remains authoritative during transport outages.
            guard isCurrent(token), await refreshIsCurrent(refreshGeneration), !Task.isCancelled else {
                return .cancelled
            }
            presentationNotice = Self.notice(for: error)
            notifyPresentationIfNeeded()
            logPolicyRefreshFailure(error)
            return .retryableFailure
        }
    }

    func activate(email: String, code: String) async throws {
        let token = beginOperation()
        let snapshot: CommercialCredentialMutationSnapshot
        do { snapshot = try await worker.snapshot(prepareClearance: true) }
        catch {
            publishNotice(.storage, token: token)
            throw CommercialAccessControllerError.storage
        }
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
        catch {
            publishNotice(Self.notice(for: error), token: token)
            throw sanitized(error)
        }
        guard isCurrent(token) else { return }
        let payload: EntitlementPayload
        do { payload = try verifiedEntitlement(envelope, expectedDeviceHash: identity.deviceHash) }
        catch {
            publishNotice(.server, token: token)
            throw error
        }
        guard payload.access == .pro else {
            publishNotice(.server, token: token)
            throw CommercialAccessControllerError.invalidCredential
        }
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
        catch {
            publishNotice(.storage, token: token)
            throw CommercialAccessControllerError.storage
        }
        guard isCurrent(token) else { return }
        guard committed else {
            await loadLocalState(token: token)
            resolveState()
            publishNotice(.storage, token: token)
            throw CommercialAccessControllerError.storage
        }
        accessEnvelope = envelope
        entitlement = payload
        timeAnchor = anchor
        lastSuccessfulValidation = nil
        terminalDenyActive = false
        terminalMarker = nil
        pendingTerminalAccess = nil
        hasPendingTerminalCleanup = false
        presentationNotice = nil
        resolveState()
        notifyPresentationIfNeeded()
    }

    func deactivateCurrentDevice() async throws {
        let token = beginOperation()
        let snapshot: CommercialCredentialMutationSnapshot
        do { snapshot = try await worker.snapshot() }
        catch {
            publishNotice(.storage, token: token)
            throw CommercialAccessControllerError.storage
        }
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
                presentationNotice = nil
                do {
                    guard try await applyTerminal(reason, token: token, expected: snapshot) else {
                        throw CommercialAccessControllerError.storage
                    }
                } catch {
                    publishNotice(.storage, token: token)
                    throw error
                }
                notifyPresentationIfNeeded()
                return
            }
            publishNotice(Self.notice(for: error), token: token)
            throw sanitized(error)
        }
        guard isCurrent(token) else { return }
        presentationNotice = nil
        do {
            guard try await applyTerminal(.deviceDeactivated, token: token, expected: snapshot) else {
                throw CommercialAccessControllerError.storage
            }
        } catch {
            publishNotice(.storage, token: token)
            throw error
        }
        notifyPresentationIfNeeded()
    }

    private func loadLocalState(token: Int) async {
        do {
            let cachedRecord = try await worker.loadPolicy()
            guard isCurrent(token) else { return }

            if let cachedRecord {
                let verified = try verifier.verifyPolicyEnvelope(cachedRecord.envelope)
                if verified.mode != .allFree, clock.now < verified.effectiveAt {
                    throw CommercialVerificationError.notEffective
                }
                if releasePhase == .free, verified.mode == .paid {
                    policy = nil
                    policyTimeAnchor = nil
                    logPolicyRefresh(
                        policy: verified,
                        at: clock.now,
                        result: .failure,
                        error: .paidPolicyIgnoredInFreeRelease
                    )
                } else {
                    policy = verified
                    policyTimeAnchor = cachedRecord.timeAnchor
                    let policyNow = trustedPolicyTime()
                    let isTrusted = verified.mode != .allFree || policyNow != nil
                    logPolicyRefresh(
                        policy: verified,
                        at: policyNow ?? clock.now,
                        result: isTrusted ? .success : .failure,
                        error: isTrusted ? nil : .clockValidationRequired
                    )
                }
            } else if let bootstrap = try await bootstrapWorker.load() {
                let verified = try verifier.verifyPolicyEnvelope(bootstrap)
                if releasePhase == .free, verified.mode == .paid {
                    policy = nil
                    policyTimeAnchor = nil
                    logPolicyRefresh(
                        policy: verified,
                        at: clock.now,
                        result: .failure,
                        error: .paidPolicyIgnoredInFreeRelease
                    )
                } else {
                    let record = CommercialPolicyRecord(envelope: bootstrap, timeAnchor: nil)
                    let cacheError: CommercialDiagnosticErrorCode?
                    do {
                        try await worker.saveBootstrapPolicy(record)
                        cacheError = .clockValidationRequired
                    } catch {
                        cacheError = .storage
                    }
                    policy = verified
                    policyTimeAnchor = nil
                    logPolicyRefresh(
                        policy: verified,
                        at: clock.now,
                        result: .failure,
                        error: cacheError
                    )
                }
            } else {
                policy = nil
                policyTimeAnchor = nil
            }
        } catch {
            policy = nil
            policyTimeAnchor = nil
            if releasePhase == .paid {
                setState(.free(reason: .policyInvalid))
            }
            logPolicyRefreshFailure(error)
        }

        guard releasePhase == .paid else { return }

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
            lastSuccessfulValidation = cachedAccess?.lastSuccessfulValidation
            if let entitlement {
                let hash = try await deviceWorker.hash()
                guard isCurrent(token) else { return }
                guard entitlement.deviceHash == hash else {
                    accessEnvelope = nil
                    self.entitlement = nil
                    timeAnchor = nil
                    lastSuccessfulValidation = nil
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

    private func validateCachedAccess(
        _ envelope: SignedEnvelope,
        token: Int,
        refresh: CommercialRefreshGeneration
    ) async -> CommercialRefreshResult {
        guard await refreshIsCurrent(refresh), !Task.isCancelled else { return .cancelled }
        let snapshot: CommercialCredentialMutationSnapshot
        do {
            snapshot = try await worker.snapshot()
            guard snapshot.marker == nil,
                  snapshot.access?.status == .active,
                  snapshot.access?.envelope == envelope
            else { return .success }
        } catch {
            guard isCurrent(token), !Task.isCancelled else { return .cancelled }
            presentationNotice = .storage
            notifyPresentationIfNeeded()
            logAccessRequest(
                .validate,
                result: .failure,
                error: .storage,
                accessKind: Self.diagnosticAccessKind(state)
            )
            return .retryableFailure
        }
        do {
            let identity = try await clientIdentity()
            guard isCurrent(token), await refreshIsCurrent(refresh), !Task.isCancelled else {
                return .cancelled
            }
            let refreshed = try await client.validate(
                CommercialLicenseValidateRequest(credential: envelope, identity: identity),
                locale: locale
            )
            guard isCurrent(token), await refreshIsCurrent(refresh), !Task.isCancelled else {
                return .cancelled
            }
            let payload = try verifiedEntitlement(refreshed, expectedDeviceHash: identity.deviceHash)
            let anchor = CommercialTimeAnchor(
                issuedAt: payload.issuedAt,
                systemUptime: clock.currentUptime
            )
            let validationAnchor = CommercialTimeAnchor(
                issuedAt: payload.issuedAt,
                systemUptime: clock.currentUptime
            )
            let record = CommercialAccessRecord.active(
                envelope: refreshed,
                anchor: anchor,
                lastSuccessfulValidation: validationAnchor
            )
            guard !Task.isCancelled else { return .cancelled }
            guard try await worker.commitActive(
                expected: snapshot,
                record: record,
                clearingMarkerNonce: nil,
                refresh: refresh
            ) else {
                return await refreshIsCurrent(refresh) ? .retryableFailure : .cancelled
            }
            guard isCurrent(token), await refreshIsCurrent(refresh), !Task.isCancelled else {
                return .cancelled
            }
            accessEnvelope = refreshed
            entitlement = payload
            timeAnchor = anchor
            lastSuccessfulValidation = validationAnchor
            presentationNotice = nil
            resolveState()
            notifyPresentationIfNeeded()
            logAccessRequest(
                .validate,
                result: .success,
                error: nil,
                accessKind: Self.diagnosticAccessKind(state)
            )
            return .success
        } catch {
            guard isCurrent(token), await refreshIsCurrent(refresh), !Task.isCancelled else {
                return .cancelled
            }
            if Self.isTerminal(error) {
                let reason = Self.terminalReason(error) ?? .revoked
                let stableError = Self.diagnosticTerminalError(reason)
                logAccessRequest(
                    .validate,
                    result: .failure,
                    error: stableError,
                    accessKind: .pro
                )
                let applied = try? await applyTerminal(
                    reason,
                    token: token,
                    expected: snapshot,
                    refresh: refresh
                )
                if applied != true, !(await refreshIsCurrent(refresh)) { return .cancelled }
                return .terminalFailure
            } else {
                presentationNotice = Self.notice(for: error)
                notifyPresentationIfNeeded()
                logAccessRequest(
                    .validate,
                    result: .failure,
                    error: Self.diagnosticError(error),
                    accessKind: Self.diagnosticAccessKind(state)
                )
                return .retryableFailure
            }
        }
    }

    private func requestTrial(
        token: Int,
        refresh: CommercialRefreshGeneration
    ) async -> CommercialRefreshResult {
        guard await refreshIsCurrent(refresh), !Task.isCancelled else { return .cancelled }
        let snapshot: CommercialCredentialMutationSnapshot
        do {
            snapshot = try await worker.snapshot()
            guard snapshot.marker == nil else { return .success }
        } catch {
            guard isCurrent(token), await refreshIsCurrent(refresh) else { return .cancelled }
            presentationNotice = .storage
            notifyPresentationIfNeeded()
            logAccessRequest(
                .trial,
                result: .failure,
                error: .storage,
                accessKind: Self.diagnosticAccessKind(state)
            )
            return .retryableFailure
        }
        do {
            let identity = try await clientIdentity()
            guard isCurrent(token), await refreshIsCurrent(refresh), !Task.isCancelled else {
                return .cancelled
            }
            let envelope = try await client.startTrial(
                CommercialTrialStartRequest(identity: identity),
                locale: locale
            )
            guard isCurrent(token), await refreshIsCurrent(refresh), !Task.isCancelled else {
                return .cancelled
            }
            let payload = try verifiedEntitlement(envelope, expectedDeviceHash: identity.deviceHash)
            guard payload.access == .trial else { return .retryableFailure }
            let anchor = CommercialTimeAnchor(
                issuedAt: payload.issuedAt,
                systemUptime: clock.currentUptime
            )
            let record = CommercialAccessRecord.active(envelope: envelope, anchor: anchor)
            guard try await worker.commitActive(
                expected: snapshot,
                record: record,
                clearingMarkerNonce: nil,
                refresh: refresh
            ) else {
                return await refreshIsCurrent(refresh) ? .retryableFailure : .cancelled
            }
            guard isCurrent(token), await refreshIsCurrent(refresh), !Task.isCancelled else {
                return .cancelled
            }
            accessEnvelope = envelope
            entitlement = payload
            timeAnchor = anchor
            lastSuccessfulValidation = nil
            trialRequestSettled = true
            terminalDenyActive = false
            resolveState()
            notifyPresentationIfNeeded()
            logAccessRequest(
                .trial,
                result: .success,
                error: nil,
                accessKind: Self.diagnosticAccessKind(state)
            )
            return .success
        } catch {
            guard isCurrent(token), await refreshIsCurrent(refresh), !Task.isCancelled else {
                return .cancelled
            }
            presentationNotice = Self.notice(for: error)
            notifyPresentationIfNeeded()
            logAccessRequest(
                .trial,
                result: .failure,
                error: Self.diagnosticError(error),
                accessKind: Self.diagnosticAccessKind(state)
            )
            if Self.isSettledTrialResponse(error) {
                trialRequestSettled = true
                return .terminalFailure
            }
            return .retryableFailure
        }
    }

    private func resolveState() {
        guard releasePhase == .paid else {
            setState(.allFree)
            return
        }
        let effective = effectiveTime()
        if let policy,
           policy.mode == .allFree,
           let policyNow = trustedPolicyTime()
        {
            if policyNow < policy.effectiveAt {
                setState(.free(reason: .clockRequiresValidation))
                return
            }
            if policyNow < policy.expiresAt {
                setState(.allFree)
                return
            }
            let graceUntil = policy.expiresAt.addingTimeInterval(Self.graceInterval)
            if policyNow <= graceUntil {
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
        if policy.mode == .allFree, trustedPolicyTime() == nil {
            setState(.free(reason: .clockRequiresValidation))
            return
        }
        guard effective.now < policy.expiresAt else {
            setState(.free(reason: .policyExpired))
            return
        }
        setState(.free(reason: .trialUnavailable))
    }

    private func trustedPolicyTime() -> Date? {
        guard let anchor = policyTimeAnchor,
              anchor.bootSessionID == clock.bootSessionID,
              clock.currentUptime >= anchor.systemUptime
        else { return nil }
        let monotonic = anchor.serverVerifiedAt.addingTimeInterval(
            clock.currentUptime - anchor.systemUptime
        )
        return max(clock.now, monotonic)
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
        expected: CommercialCredentialMutationSnapshot,
        refresh: CommercialRefreshGeneration? = nil
    ) async throws -> Bool {
        if let refresh, !(await refreshIsCurrent(refresh)) { return false }
        guard isCurrent(token) else { return false }
        let outcome = await worker.commitTerminal(
            expected: expected,
            reason: reason,
            refresh: refresh
        )
        guard outcome.committed, let marker = outcome.marker else {
            logAccessRequest(
                .terminal,
                result: .failure,
                error: .storage,
                accessKind: Self.diagnosticAccessKind(state)
            )
            return false
        }
        if let refresh, !(await refreshIsCurrent(refresh)) { return true }
        guard isCurrent(token) else { return true }
        terminalDenyActive = true
        terminalMarker = marker
        pendingTerminalAccess = expected.access
        hasPendingTerminalCleanup = outcome.cleanupPending
        clearLocalAccess()
        setState(.free(reason: .serverDenied))
        if outcome.storageFailed {
            logAccessRequest(
                .terminal,
                result: .failure,
                error: .storage,
                accessKind: Self.diagnosticAccessKind(state)
            )
            throw CommercialAccessControllerError.storage
        }
        logAccessRequest(
            .terminal,
            result: .success,
            error: Self.diagnosticTerminalError(reason),
            accessKind: Self.diagnosticAccessKind(state)
        )
        return true
    }

    private func clearLocalAccess() {
        accessEnvelope = nil
        entitlement = nil
        timeAnchor = nil
        lastSuccessfulValidation = nil
    }

    private func beginOperation() -> Int {
        generation += 1
        return generation
    }

    private func isCurrent(_ token: Int) -> Bool { generation == token }

    private func refreshIsCurrent(_ refresh: CommercialRefreshGeneration) async -> Bool {
        await worker.isRefreshGenerationCurrent(refresh)
    }

    private func setState(_ newState: CommercialAccessState) {
        guard state != newState else { return }
        state = newState
        diagnosticLogger.record(.accessStateChanged(
            accessKind: Self.diagnosticAccessKind(newState)
        ))
        notifyPresentationIfNeeded()
    }

    private func logPolicyRefresh(
        policy: CommercialPolicy,
        at effectiveDate: Date,
        result: CommercialDiagnosticResult,
        error: CommercialDiagnosticErrorCode?
    ) {
        diagnosticLogger.record(.policyRefresh(
            mode: policy.mode,
            policyID: policy.policyId,
            expired: effectiveDate >= policy.expiresAt,
            result: result,
            error: error
        ))
    }

    private func logPolicyRefreshFailure(_ error: Error) {
        let referenceDate = trustedPolicyTime() ?? clock.now
        diagnosticLogger.record(.policyRefresh(
            mode: policy?.mode,
            policyID: policy?.policyId,
            expired: policy.map { referenceDate >= $0.expiresAt },
            result: .failure,
            error: Self.diagnosticError(error)
        ))
    }

    private func logAccessRequest(
        _ operation: CommercialDiagnosticOperation,
        result: CommercialDiagnosticResult,
        error: CommercialDiagnosticErrorCode?,
        accessKind: CommercialDiagnosticAccessKind
    ) {
        diagnosticLogger.record(.accessRequest(
            operation: operation,
            accessKind: accessKind,
            result: result,
            error: error
        ))
    }

    private static func diagnosticAccessKind(
        _ state: CommercialAccessState
    ) -> CommercialDiagnosticAccessKind {
        switch state {
        case .allFree: return .allFree
        case .allFreeGrace: return .allFreeGrace
        case .trial: return .trial
        case .pro: return .pro
        case .free: return .free
        }
    }

    private static func diagnosticError(_ error: Error) -> CommercialDiagnosticErrorCode {
        if error is CommercialCredentialStoreError { return .storage }
        if error is URLError { return .network }
        if case CommercialPolicyClientError.transport = error { return .network }
        if let verification = error as? CommercialVerificationError {
            return verification == .expired ? .policyExpired : .invalidPolicy
        }
        if let controller = error as? CommercialAccessControllerError {
            switch controller {
            case .storage: return .storage
            case .network, .identityUnavailable: return .network
            case .trialUnavailable, .trialAlreadyUsed: return .trialUnavailable
            case .licenseRevoked: return .licenseRevoked
            case .licenseRefunded: return .licenseRefunded
            case .deviceDeactivated: return .deviceDeactivated
            default: return .invalidCredential
            }
        }
        return .server
    }

    private static func diagnosticTerminalError(
        _ reason: CommercialTerminalReason
    ) -> CommercialDiagnosticErrorCode {
        switch reason {
        case .revoked: return .licenseRevoked
        case .refunded: return .licenseRefunded
        case .deviceDeactivated: return .deviceDeactivated
        }
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
        if let error = error as? CommercialAccessControllerError {
            switch error {
            case .storage: return .storage
            case .network, .identityUnavailable: return .network
            default: return .server
            }
        }
        return .server
    }

    private func publishNotice(_ notice: CommercialPresentationNotice, token: Int) {
        guard isCurrent(token) else { return }
        presentationNotice = notice
        notifyPresentationIfNeeded()
    }

    private func sanitized(_ error: Error) -> CommercialAccessControllerError {
        if error is CommercialAccessControllerError {
            return error as! CommercialAccessControllerError
        }
        if case let CommercialPolicyClientError.server(_, detail) = error {
            switch detail.code {
            case "device_limit_reached": return .deviceLimit
            case "activation_invalid": return .activationRejected
            case "credential_invalid": return .invalidCredential
            case "credential_binding_invalid": return .credentialBindingInvalid
            case "device_deactivated": return .deviceDeactivated
            case "build_not_entitled": return .buildNotEntitled
            case "license_revoked": return .licenseRevoked
            case "license_refunded": return .licenseRefunded
            case "trial_already_used": return .trialAlreadyUsed
            case "trial_unavailable": return .trialUnavailable
            default: break
            }
        }
        return .network
    }

    private static func isTerminal(_ error: Error) -> Bool {
        terminalReason(error) != nil
    }

    private static func isSettledTrialResponse(_ error: Error) -> Bool {
        guard case let CommercialPolicyClientError.server(_, detail) = error else { return false }
        switch detail.code {
        case "trial_already_used", "trial_unavailable", "trial_expired": return true
        default: return false
        }
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
