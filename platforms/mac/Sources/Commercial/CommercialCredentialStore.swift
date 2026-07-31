import Foundation
import Security

protocol CommercialCredentialStoring: AnyObject {
    func loadPolicyEnvelope() throws -> SignedEnvelope?
    func savePolicyEnvelope(_ envelope: SignedEnvelope) throws
    func loadAccessRecord() throws -> CommercialAccessRecord?
    func saveAccessRecord(_ record: CommercialAccessRecord) throws
    func deleteAccessRecord() throws
}

protocol CommercialTerminalMarkerStoring: AnyObject {
    func loadTerminalMarker() throws -> CommercialTerminalMarker?
    func saveTerminalMarker(_ marker: CommercialTerminalMarker) throws
    func compareAndDeleteTerminalMarker(expectedNonce: UUID?) throws -> Bool
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
    let terminalReason: CommercialTerminalReason?
    let clearsTerminalMarkerNonce: UUID?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, status, envelope, anchor, terminalReason, clearsTerminalMarkerNonce
    }

    static func active(
        envelope: SignedEnvelope,
        anchor: CommercialTimeAnchor?,
        clearsTerminalMarkerNonce: UUID? = nil
    ) -> Self {
        Self(
            status: .active,
            envelope: envelope,
            anchor: anchor,
            terminalReason: nil,
            clearsTerminalMarkerNonce: clearsTerminalMarkerNonce
        )
    }

    static func terminal(_ reason: CommercialTerminalReason) -> Self {
        Self(
            status: .terminal,
            envelope: nil,
            anchor: nil,
            terminalReason: reason,
            clearsTerminalMarkerNonce: nil
        )
    }

    private init(
        status: Status,
        envelope: SignedEnvelope?,
        anchor: CommercialTimeAnchor?,
        terminalReason: CommercialTerminalReason?,
        clearsTerminalMarkerNonce: UUID?
    ) {
        self.status = status
        self.envelope = envelope
        self.anchor = anchor
        self.terminalReason = terminalReason
        self.clearsTerminalMarkerNonce = clearsTerminalMarkerNonce
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == 1 else {
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
        terminalReason = try container.decodeIfPresent(CommercialTerminalReason.self, forKey: .terminalReason)
        clearsTerminalMarkerNonce = try container.decodeIfPresent(UUID.self, forKey: .clearsTerminalMarkerNonce)
        guard (status == .active && envelope != nil && terminalReason == nil)
                || (status == .terminal && envelope == nil && terminalReason != nil && clearsTerminalMarkerNonce == nil)
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
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(envelope, forKey: .envelope)
        try container.encodeIfPresent(anchor, forKey: .anchor)
        try container.encodeIfPresent(terminalReason, forKey: .terminalReason)
        try container.encodeIfPresent(clearsTerminalMarkerNonce, forKey: .clearsTerminalMarkerNonce)
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

    func saveTerminalMarker(_ marker: CommercialTerminalMarker) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let data = try JSONEncoder().encode(
            Payload(schemaVersion: 1, reason: marker.reason, nonce: marker.nonce)
        )
        defaults.set(data, forKey: Self.key)
        guard defaults.synchronize() else {
            throw CommercialTerminalMarkerStoreError.persistenceFailed
        }
    }

    func compareAndDeleteTerminalMarker(expectedNonce: UUID?) throws -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let current = try loadUnlocked()
        guard current?.nonce == expectedNonce else { return false }
        if current != nil {
            defaults.removeObject(forKey: Self.key)
        }
        guard defaults.synchronize() else {
            throw CommercialTerminalMarkerStoreError.persistenceFailed
        }
        return true
    }

    private func loadUnlocked() throws -> CommercialTerminalMarker? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
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
        try load(SignedEnvelope.self, account: Account.policy)
    }

    func savePolicyEnvelope(_ envelope: SignedEnvelope) throws {
        try save(envelope, account: Account.policy)
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
