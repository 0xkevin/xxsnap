import Foundation
import Security

protocol CommercialCredentialStoring: AnyObject {
    func loadPolicyEnvelope() throws -> SignedEnvelope?
    func savePolicyEnvelope(_ envelope: SignedEnvelope) throws
    func loadAccessEnvelope() throws -> SignedEnvelope?
    func saveAccessEnvelope(_ envelope: SignedEnvelope) throws
    func deleteAccessEnvelope() throws
    func loadTimeAnchor() throws -> CommercialTimeAnchor?
    func saveTimeAnchor(_ value: CommercialTimeAnchor) throws
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
        static let timeAnchor = "time-anchor"
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

    func loadAccessEnvelope() throws -> SignedEnvelope? {
        try load(SignedEnvelope.self, account: Account.access)
    }

    func saveAccessEnvelope(_ envelope: SignedEnvelope) throws {
        try save(envelope, account: Account.access)
    }

    func deleteAccessEnvelope() throws {
        try delete(account: Account.access)
        try delete(account: Account.timeAnchor)
    }

    func loadTimeAnchor() throws -> CommercialTimeAnchor? {
        try load(CommercialTimeAnchor.self, account: Account.timeAnchor)
    }

    func saveTimeAnchor(_ value: CommercialTimeAnchor) throws {
        try save(value, account: Account.timeAnchor)
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
