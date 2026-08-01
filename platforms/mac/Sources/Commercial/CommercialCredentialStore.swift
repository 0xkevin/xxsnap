import Foundation
import Security

protocol CommercialCredentialStoring: AnyObject {
    func loadPolicyEnvelope() throws -> SignedEnvelope?
    func savePolicyEnvelope(_ envelope: SignedEnvelope) throws
    func loadPolicyRecord() throws -> CommercialPolicyRecord?
    func savePolicyRecord(_ record: CommercialPolicyRecord) throws
    func loadAccessRecord() throws -> CommercialAccessRecord?
    func saveAccessRecord(_ record: CommercialAccessRecord) throws
    func deleteAccessRecord() throws
    func compareAndDeleteTerminalAccessRecord(expectedNonce: UUID) throws -> Bool
}

extension CommercialCredentialStoring {
    func loadPolicyRecord() throws -> CommercialPolicyRecord? {
        try loadPolicyEnvelope().map { CommercialPolicyRecord(envelope: $0, timeAnchor: nil) }
    }

    func savePolicyRecord(_ record: CommercialPolicyRecord) throws {
        try savePolicyEnvelope(record.envelope)
    }
}

protocol CommercialTerminalMarkerStoring: AnyObject {
    func loadTerminalMarker() throws -> CommercialTerminalMarker?
    func prepareClearanceMarker() throws -> CommercialTerminalMarker?
    func saveTerminalMarker(_ marker: CommercialTerminalMarker) throws
    func compareAndDeleteTerminalMarker(expectedNonce: UUID) throws -> Bool
}

struct CommercialTimeAnchor: Codable, Equatable {
    let issuedAt: Date
    let systemUptime: TimeInterval

    private enum CodingKeys: String, CodingKey { case issuedAt, systemUptime }

    init(issuedAt: Date, systemUptime: TimeInterval) {
        self.issuedAt = issuedAt
        self.systemUptime = systemUptime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        issuedAt = try CommercialJSON.date(
            container.decode(String.self, forKey: .issuedAt),
            field: CodingKeys.issuedAt.rawValue
        )
        systemUptime = try container.decode(TimeInterval.self, forKey: .systemUptime)
        guard systemUptime.isFinite, systemUptime >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .systemUptime,
                in: container,
                debugDescription: "Invalid uptime"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(CommercialJSON.string(issuedAt), forKey: .issuedAt)
        try container.encode(systemUptime, forKey: .systemUptime)
    }
}

struct CommercialPolicyTimeAnchor: Codable, Equatable {
    let serverVerifiedAt: Date
    let systemUptime: TimeInterval
    let bootSessionID: String

    private enum CodingKeys: String, CodingKey {
        case serverVerifiedAt, systemUptime, bootSessionID
    }

    init(serverVerifiedAt: Date, systemUptime: TimeInterval, bootSessionID: String) {
        self.serverVerifiedAt = serverVerifiedAt
        self.systemUptime = systemUptime
        self.bootSessionID = bootSessionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverVerifiedAt = try CommercialJSON.date(
            container.decode(String.self, forKey: .serverVerifiedAt),
            field: CodingKeys.serverVerifiedAt.rawValue
        )
        systemUptime = try container.decode(TimeInterval.self, forKey: .systemUptime)
        bootSessionID = try container.decode(String.self, forKey: .bootSessionID)
        guard systemUptime.isFinite,
              systemUptime >= 0,
              !bootSessionID.isEmpty,
              bootSessionID.utf8.count <= 128
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .systemUptime,
                in: container,
                debugDescription: "Invalid policy time anchor"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            CommercialJSON.string(serverVerifiedAt),
            forKey: .serverVerifiedAt
        )
        try container.encode(systemUptime, forKey: .systemUptime)
        try container.encode(bootSessionID, forKey: .bootSessionID)
    }
}

struct CommercialPolicyRecord: Codable, Equatable {
    let envelope: SignedEnvelope
    let timeAnchor: CommercialPolicyTimeAnchor?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, envelope, timeAnchor
    }

    init(envelope: SignedEnvelope, timeAnchor: CommercialPolicyTimeAnchor?) {
        self.envelope = envelope
        self.timeAnchor = timeAnchor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported policy-record schema"
            )
        }
        envelope = try container.decode(SignedEnvelope.self, forKey: .envelope)
        timeAnchor = try? container.decodeIfPresent(
            CommercialPolicyTimeAnchor.self,
            forKey: .timeAnchor
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(envelope, forKey: .envelope)
        try container.encodeIfPresent(timeAnchor, forKey: .timeAnchor)
    }
}

enum CommercialTerminalReason: String, Codable, Equatable {
    case refunded
    case revoked
    case deviceDeactivated = "device_deactivated"
}

struct CommercialTerminalMarker: Codable, Equatable {
    let reason: CommercialTerminalReason
    let nonce: UUID

    init(reason: CommercialTerminalReason, nonce: UUID = UUID()) {
        self.reason = reason
        self.nonce = nonce
    }
}

struct CommercialAccessRecord: Codable, Equatable {
    enum Status: String, Codable { case active, terminal }

    let status: Status
    let envelope: SignedEnvelope?
    let anchor: CommercialTimeAnchor?
    /// Independent proof of the last successful `/validate` response.  The
    /// entitlement issue date is not a validation timestamp.
    let lastSuccessfulValidation: CommercialTimeAnchor?
    let terminalReason: CommercialTerminalReason?
    let terminalMarkerNonce: UUID?
    let clearsTerminalMarkerNonce: UUID?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, status, envelope, anchor, lastSuccessfulValidation
        case terminalReason, terminalMarkerNonce
        case clearsTerminalMarkerNonce
    }

    static func active(
        envelope: SignedEnvelope,
        anchor: CommercialTimeAnchor?,
        lastSuccessfulValidation: CommercialTimeAnchor? = nil,
        clearsTerminalMarkerNonce: UUID? = nil
    ) -> Self {
        Self(
            status: .active,
            envelope: envelope,
            anchor: anchor,
            lastSuccessfulValidation: lastSuccessfulValidation,
            terminalReason: nil,
            terminalMarkerNonce: nil,
            clearsTerminalMarkerNonce: clearsTerminalMarkerNonce
        )
    }

    static func terminal(_ reason: CommercialTerminalReason, nonce: UUID = UUID()) -> Self {
        Self(
            status: .terminal,
            envelope: nil,
            anchor: nil,
            lastSuccessfulValidation: nil,
            terminalReason: reason,
            terminalMarkerNonce: nonce,
            clearsTerminalMarkerNonce: nil
        )
    }

    private init(
        status: Status,
        envelope: SignedEnvelope?,
        anchor: CommercialTimeAnchor?,
        lastSuccessfulValidation: CommercialTimeAnchor?,
        terminalReason: CommercialTerminalReason?,
        terminalMarkerNonce: UUID?,
        clearsTerminalMarkerNonce: UUID?
    ) {
        self.status = status
        self.envelope = envelope
        self.anchor = anchor
        self.lastSuccessfulValidation = lastSuccessfulValidation
        self.terminalReason = terminalReason
        self.terminalMarkerNonce = terminalMarkerNonce
        self.clearsTerminalMarkerNonce = clearsTerminalMarkerNonce
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 || schemaVersion == 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported access-record schema"
            )
        }
        status = try container.decode(Status.self, forKey: .status)
        envelope = try container.decodeIfPresent(SignedEnvelope.self, forKey: .envelope)
        // A damaged monotonic-time anchor must not make a valid paid envelope unreadable.
        anchor = try? container.decodeIfPresent(CommercialTimeAnchor.self, forKey: .anchor)
        lastSuccessfulValidation = schemaVersion >= 2
            ? (try? container.decodeIfPresent(CommercialTimeAnchor.self, forKey: .lastSuccessfulValidation))
            : nil
        terminalReason = try container.decodeIfPresent(CommercialTerminalReason.self, forKey: .terminalReason)
        terminalMarkerNonce = try container.decodeIfPresent(UUID.self, forKey: .terminalMarkerNonce)
        clearsTerminalMarkerNonce = try container.decodeIfPresent(UUID.self, forKey: .clearsTerminalMarkerNonce)
        guard (status == .active && envelope != nil && terminalReason == nil && terminalMarkerNonce == nil)
                || (status == .terminal && envelope == nil && terminalReason != nil
                    && clearsTerminalMarkerNonce == nil)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Inconsistent access record"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(2, forKey: .schemaVersion)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(envelope, forKey: .envelope)
        try container.encodeIfPresent(anchor, forKey: .anchor)
        try container.encodeIfPresent(lastSuccessfulValidation, forKey: .lastSuccessfulValidation)
        try container.encodeIfPresent(terminalReason, forKey: .terminalReason)
        try container.encodeIfPresent(terminalMarkerNonce, forKey: .terminalMarkerNonce)
        try container.encodeIfPresent(clearsTerminalMarkerNonce, forKey: .clearsTerminalMarkerNonce)
    }
}

struct CommercialCredentialMutationSnapshot: Equatable {
    let revision: UInt64
    let marker: CommercialTerminalMarker?
    let access: CommercialAccessRecord?
}

struct CommercialRefreshGeneration: Equatable, Sendable {
    fileprivate let value: UInt64
}

enum CommercialCredentialSnapshotError: Error {
    case marker
    case access(marker: CommercialTerminalMarker?)
}

struct CommercialTerminalCommitOutcome {
    let committed: Bool
    let marker: CommercialTerminalMarker?
    let cleanupPending: Bool
    let storageFailed: Bool
}

final class CommercialCredentialMutationCoordinator: @unchecked Sendable {
    static let shared = CommercialCredentialMutationCoordinator()

    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var refreshGeneration: UInt64 = 0

    func beginRefreshGeneration() -> CommercialRefreshGeneration {
        lock.lock()
        defer { lock.unlock() }
        refreshGeneration &+= 1
        return CommercialRefreshGeneration(value: refreshGeneration)
    }

    func invalidateRefreshGeneration() {
        lock.lock()
        refreshGeneration &+= 1
        lock.unlock()
    }

    func isRefreshGenerationCurrent(_ generation: CommercialRefreshGeneration) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return refreshGeneration == generation.value
    }

    func savePolicy(
        _ envelope: SignedEnvelope,
        refresh: CommercialRefreshGeneration,
        store: CommercialCredentialStoring
    ) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard refreshGeneration == refresh.value else { return false }
        try store.savePolicyEnvelope(envelope)
        return true
    }

    func savePolicy(
        _ record: CommercialPolicyRecord,
        refresh: CommercialRefreshGeneration,
        store: CommercialCredentialStoring
    ) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard refreshGeneration == refresh.value else { return false }
        try store.savePolicyRecord(record)
        return true
    }

    func snapshot(
        store: CommercialCredentialStoring,
        markerStore: CommercialTerminalMarkerStoring,
        prepareClearance: Bool = false
    ) throws -> CommercialCredentialMutationSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let marker: CommercialTerminalMarker?
        do {
            marker = try prepareClearance
                ? markerStore.prepareClearanceMarker()
                : markerStore.loadTerminalMarker()
        } catch {
            throw CommercialCredentialSnapshotError.marker
        }
        let access: CommercialAccessRecord?
        do { access = try store.loadAccessRecord() }
        catch { throw CommercialCredentialSnapshotError.access(marker: marker) }
        return CommercialCredentialMutationSnapshot(
            revision: revision,
            marker: marker,
            access: access
        )
    }

    func commitActive(
        expected: CommercialCredentialMutationSnapshot,
        record: CommercialAccessRecord,
        clearingMarkerNonce: UUID?,
        refresh: CommercialRefreshGeneration? = nil,
        store: CommercialCredentialStoring,
        markerStore: CommercialTerminalMarkerStoring
    ) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard refresh.map({ refreshGeneration == $0.value }) ?? true,
              revision == expected.revision,
              try markerStore.loadTerminalMarker() == expected.marker,
              try store.loadAccessRecord() == expected.access
        else { return false }
        if let clearingMarkerNonce {
            guard expected.marker?.nonce == clearingMarkerNonce else { return false }
        } else {
            guard expected.marker == nil else { return false }
        }
        try store.saveAccessRecord(record)
        revision &+= 1
        if let clearingMarkerNonce {
            guard try markerStore.compareAndDeleteTerminalMarker(expectedNonce: clearingMarkerNonce) else {
                return false
            }
        }
        return true
    }

    func commitTerminal(
        expected: CommercialCredentialMutationSnapshot,
        reason: CommercialTerminalReason,
        refresh: CommercialRefreshGeneration? = nil,
        store: CommercialCredentialStoring,
        markerStore: CommercialTerminalMarkerStoring
    ) -> CommercialTerminalCommitOutcome {
        lock.lock()
        defer { lock.unlock() }
        guard (refresh.map { refreshGeneration == $0.value } ?? true),
              revision == expected.revision else {
            return CommercialTerminalCommitOutcome(
                committed: false, marker: nil, cleanupPending: false, storageFailed: false
            )
        }
        do {
            guard try markerStore.loadTerminalMarker() == expected.marker,
                  try store.loadAccessRecord() == expected.access
            else {
                return CommercialTerminalCommitOutcome(
                    committed: false, marker: nil, cleanupPending: false, storageFailed: false
                )
            }
        } catch {
            revision &+= 1
            return CommercialTerminalCommitOutcome(
                committed: true,
                marker: CommercialTerminalMarker(reason: reason),
                cleanupPending: true,
                storageFailed: true
            )
        }

        let marker = CommercialTerminalMarker(reason: reason)
        var markerSaved = false
        var tombstoneSaved = false
        var tombstoneDeleted = false
        do {
            try markerStore.saveTerminalMarker(marker)
            markerSaved = true
        } catch {}
        do {
            try store.saveAccessRecord(.terminal(reason, nonce: marker.nonce))
            tombstoneSaved = true
        } catch {}
        if markerSaved, tombstoneSaved {
            do {
                tombstoneDeleted = try store.compareAndDeleteTerminalAccessRecord(
                    expectedNonce: marker.nonce
                )
            } catch {}
        }
        revision &+= 1
        let failed = !markerSaved || !tombstoneSaved || !tombstoneDeleted
        return CommercialTerminalCommitOutcome(
            committed: true,
            marker: marker,
            cleanupPending: failed,
            storageFailed: failed
        )
    }

    func cleanupTerminal(
        marker: CommercialTerminalMarker,
        expectedActive: CommercialAccessRecord?,
        store: CommercialCredentialStoring,
        markerStore: CommercialTerminalMarkerStoring
    ) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let currentMarker = try markerStore.loadTerminalMarker()
        let initialAccess = try store.loadAccessRecord()
        if currentMarker == nil {
            guard let initialAccess,
                  initialAccess.status == .terminal || initialAccess == expectedActive
            else { return false }
            try markerStore.saveTerminalMarker(marker)
            revision &+= 1
        } else if currentMarker?.nonce != marker.nonce {
            return false
        }

        guard let currentAccess = initialAccess else { return false }
        switch currentAccess.status {
        case .active:
            if currentAccess.clearsTerminalMarkerNonce == marker.nonce { return false }
            guard currentAccess == expectedActive else { return false }
            try store.saveAccessRecord(.terminal(marker.reason, nonce: marker.nonce))
            revision &+= 1
        case .terminal:
            if currentAccess.terminalMarkerNonce != marker.nonce {
                try store.saveAccessRecord(.terminal(marker.reason, nonce: marker.nonce))
                revision &+= 1
            }
        }
        let deleted = try store.compareAndDeleteTerminalAccessRecord(expectedNonce: marker.nonce)
        if deleted { revision &+= 1 }
        return !deleted
    }

    func clearMarker(
        expected: CommercialCredentialMutationSnapshot,
        nonce: UUID,
        store: CommercialCredentialStoring,
        markerStore: CommercialTerminalMarkerStoring
    ) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard revision == expected.revision,
              try markerStore.loadTerminalMarker() == expected.marker,
              try store.loadAccessRecord() == expected.access,
              expected.marker?.nonce == nonce
        else { return false }
        guard try markerStore.compareAndDeleteTerminalMarker(expectedNonce: nonce) else {
            return false
        }
        revision &+= 1
        return true
    }
}

enum CommercialTerminalMarkerStoreError: Error, Equatable {
    case corruptData
    case persistenceFailed
}

final class CommercialTerminalMarkerStore: CommercialTerminalMarkerStoring {
    private static let key = "commercial.terminal-deny.v1"
    private static let lock = NSLock()

    private struct Payload: Codable {
        let schemaVersion: Int
        let reason: CommercialTerminalReason
        let nonce: UUID
    }

    private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
    }

    func loadTerminalMarker() throws -> CommercialTerminalMarker? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try loadUnlocked()
    }

    func prepareClearanceMarker() throws -> CommercialTerminalMarker? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard defaults.object(forKey: Self.key) != nil else { return nil }
        if let marker = try? loadUnlocked() { return marker }
        let marker = CommercialTerminalMarker(reason: .revoked)
        try saveUnlocked(marker)
        return marker
    }

    func saveTerminalMarker(_ marker: CommercialTerminalMarker) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        try saveUnlocked(marker)
    }

    private func saveUnlocked(_ marker: CommercialTerminalMarker) throws {
        let data = try JSONEncoder().encode(
            Payload(schemaVersion: 1, reason: marker.reason, nonce: marker.nonce)
        )
        defaults.set(data, forKey: Self.key)
        guard defaults.synchronize() else {
            throw CommercialTerminalMarkerStoreError.persistenceFailed
        }
    }

    func compareAndDeleteTerminalMarker(expectedNonce: UUID) throws -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let current = try loadUnlocked()
        guard current?.nonce == expectedNonce else { return false }
        defaults.removeObject(forKey: Self.key)
        guard defaults.synchronize() else {
            throw CommercialTerminalMarkerStoreError.persistenceFailed
        }
        return true
    }

    private func loadUnlocked() throws -> CommercialTerminalMarker? {
        guard let object = defaults.object(forKey: Self.key) else { return nil }
        guard let data = object as? Data else {
            throw CommercialTerminalMarkerStoreError.corruptData
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schemaVersion == 1
        else { throw CommercialTerminalMarkerStoreError.corruptData }
        return CommercialTerminalMarker(reason: payload.reason, nonce: payload.nonce)
    }
}

enum CommercialCredentialStoreError: Error, Equatable {
    case keychain(OSStatus)
    case corruptData
}

protocol CommercialKeychainAccessing: AnyObject {
    func copy(service: String, account: String) -> (OSStatus, Data?)
    func add(service: String, account: String, data: Data) -> OSStatus
    func update(service: String, account: String, data: Data) -> OSStatus
    func delete(service: String, account: String) -> OSStatus
}

final class SystemCommercialKeychain: CommercialKeychainAccessing {
    func copy(service: String, account: String) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        return (status, result as? Data)
    }

    func add(service: String, account: String, data: Data) -> OSStatus {
        SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data,
        ] as CFDictionary, nil)
    }

    func update(service: String, account: String, data: Data) -> OSStatus {
        SecItemUpdate([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary, [kSecValueData: data] as CFDictionary)
    }

    func delete(service: String, account: String) -> OSStatus {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary)
    }
}

final class CommercialCredentialStore: CommercialCredentialStoring {
    static let service = "com.xxsnap.mac.commercial"
    private enum Account {
        static let policy = "policy"
        static let access = "access"
    }

    private let keychain: CommercialKeychainAccessing
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(keychain: CommercialKeychainAccessing = SystemCommercialKeychain()) {
        self.keychain = keychain
    }

    func loadPolicyEnvelope() throws -> SignedEnvelope? {
        try loadPolicyRecord()?.envelope
    }

    func savePolicyEnvelope(_ envelope: SignedEnvelope) throws {
        try savePolicyRecord(CommercialPolicyRecord(envelope: envelope, timeAnchor: nil))
    }

    func loadPolicyRecord() throws -> CommercialPolicyRecord? {
        let (status, data) = keychain.copy(service: Self.service, account: Account.policy)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CommercialCredentialStoreError.keychain(status) }
        guard let data else { throw CommercialCredentialStoreError.corruptData }
        if let record = try? decoder.decode(CommercialPolicyRecord.self, from: data) {
            return record
        }
        if let legacyEnvelope = try? decoder.decode(SignedEnvelope.self, from: data) {
            return CommercialPolicyRecord(envelope: legacyEnvelope, timeAnchor: nil)
        }
        throw CommercialCredentialStoreError.corruptData
    }

    func savePolicyRecord(_ record: CommercialPolicyRecord) throws {
        try save(record, account: Account.policy)
    }

    func loadAccessRecord() throws -> CommercialAccessRecord? {
        let (status, data) = keychain.copy(service: Self.service, account: Account.access)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CommercialCredentialStoreError.keychain(status) }
        guard let data else { throw CommercialCredentialStoreError.corruptData }
        if let record = try? decoder.decode(CommercialAccessRecord.self, from: data) {
            return record
        }
        // Commercial storage has not shipped yet. Accept the development-build raw
        // envelope once; paid stays fail-open, while a legacy trial must revalidate
        // because its separately stored anchor was not atomic.
        if let legacyEnvelope = try? decoder.decode(SignedEnvelope.self, from: data) {
            return .active(envelope: legacyEnvelope, anchor: nil)
        }
        throw CommercialCredentialStoreError.corruptData
    }

    func saveAccessRecord(_ record: CommercialAccessRecord) throws {
        try save(record, account: Account.access)
    }

    func deleteAccessRecord() throws {
        try delete(account: Account.access)
    }

    func compareAndDeleteTerminalAccessRecord(expectedNonce: UUID) throws -> Bool {
        guard let current = try loadAccessRecord(),
              current.status == .terminal,
              current.terminalMarkerNonce == expectedNonce
        else { return false }
        try deleteAccessRecord()
        return true
    }

    private func load<Value: Decodable>(_ type: Value.Type, account: String) throws -> Value? {
        let (status, data) = keychain.copy(service: Self.service, account: account)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CommercialCredentialStoreError.keychain(status) }
        guard let data, let value = try? decoder.decode(type, from: data) else {
            throw CommercialCredentialStoreError.corruptData
        }
        return value
    }

    private func save<Value: Encodable>(_ value: Value, account: String) throws {
        let data: Data
        do { data = try encoder.encode(value) } catch { throw CommercialCredentialStoreError.corruptData }
        let updateStatus = keychain.update(service: Self.service, account: account, data: data)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CommercialCredentialStoreError.keychain(updateStatus)
        }
        let addStatus = keychain.add(service: Self.service, account: account, data: data)
        if addStatus == errSecDuplicateItem {
            let retryStatus = keychain.update(service: Self.service, account: account, data: data)
            guard retryStatus == errSecSuccess else { throw CommercialCredentialStoreError.keychain(retryStatus) }
            return
        }
        guard addStatus == errSecSuccess else { throw CommercialCredentialStoreError.keychain(addStatus) }
    }

    private func delete(account: String) throws {
        let status = keychain.delete(service: Self.service, account: account)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CommercialCredentialStoreError.keychain(status)
        }
    }
}
