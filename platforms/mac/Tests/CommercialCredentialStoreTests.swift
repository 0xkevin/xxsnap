import CryptoKit
import Security
import XCTest
@testable import xxsnap

final class CommercialCredentialStoreTests: XCTestCase {
    func testKeychainStoreAddsLoadsUpdatesAndDeletesSeparateAccounts() throws {
        let keychain = FakeCommercialKeychain()
        let store = CommercialCredentialStore(keychain: keychain)
        let first = envelope("first")
        let second = envelope("second")

        XCTAssertNil(try store.loadPolicyEnvelope())
        try store.savePolicyEnvelope(first)
        try store.saveAccessEnvelope(first)
        XCTAssertEqual(try store.loadPolicyEnvelope(), first)
        XCTAssertEqual(try store.loadAccessEnvelope(), first)

        try store.saveAccessEnvelope(second)
        XCTAssertEqual(try store.loadAccessEnvelope(), second)
        XCTAssertEqual(keychain.addedAccounts, ["policy", "access"])
        XCTAssertEqual(keychain.updatedAccounts, ["access"])

        try store.deleteAccessEnvelope()
        XCTAssertNil(try store.loadAccessEnvelope())
        XCTAssertEqual(try store.loadPolicyEnvelope(), first)
    }

    func testKeychainStorePropagatesErrorsAndRejectsCorruptData() throws {
        let keychain = FakeCommercialKeychain()
        let store = CommercialCredentialStore(keychain: keychain)
        keychain.items["policy"] = Data("not-json".utf8)
        XCTAssertThrowsError(try store.loadPolicyEnvelope()) {
            XCTAssertEqual($0 as? CommercialCredentialStoreError, .corruptData)
        }

        keychain.copyStatus = errSecAuthFailed
        XCTAssertThrowsError(try store.loadAccessEnvelope()) {
            XCTAssertEqual($0 as? CommercialCredentialStoreError, .keychain(errSecAuthFailed))
        }
    }

    func testKeychainStorePropagatesAddUpdateAndDeleteErrors() throws {
        let addKeychain = FakeCommercialKeychain()
        addKeychain.addStatus = errSecAuthFailed
        XCTAssertThrowsError(try CommercialCredentialStore(keychain: addKeychain).savePolicyEnvelope(envelope("value"))) {
            XCTAssertEqual($0 as? CommercialCredentialStoreError, .keychain(errSecAuthFailed))
        }

        let updateKeychain = FakeCommercialKeychain()
        updateKeychain.items["policy"] = Data()
        updateKeychain.updateStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try CommercialCredentialStore(keychain: updateKeychain).savePolicyEnvelope(envelope("value"))) {
            XCTAssertEqual($0 as? CommercialCredentialStoreError, .keychain(errSecInteractionNotAllowed))
        }

        let deleteKeychain = FakeCommercialKeychain()
        deleteKeychain.items["access"] = Data()
        deleteKeychain.deleteStatus = errSecAuthFailed
        XCTAssertThrowsError(try CommercialCredentialStore(keychain: deleteKeychain).deleteAccessEnvelope()) {
            XCTAssertEqual($0 as? CommercialCredentialStoreError, .keychain(errSecAuthFailed))
        }
    }

    func testAnchorUsesDedicatedKeychainAccountAndNeverUserDefaults() throws {
        let keychain = FakeCommercialKeychain()
        let store = CommercialCredentialStore(keychain: keychain)
        let anchor = CommercialTimeAnchor(
            issuedAt: Date(timeIntervalSince1970: 1_000),
            systemUptime: 123
        )

        try store.saveTimeAnchor(anchor)
        XCTAssertEqual(try store.loadTimeAnchor(), anchor)
        XCTAssertEqual(keychain.addedAccounts, ["time-anchor"])
        try store.deleteAccessEnvelope()
        XCTAssertNil(try store.loadTimeAnchor())
    }

    func testDeviceIdentityProducesStableLowercaseHashAndTruncatesDisplayName() throws {
        let identity = CommercialDeviceIdentity(
            platformUUIDProvider: { "ABCDEF12-3456-7890-ABCD-EF1234567890" },
            hostNameProvider: { String(repeating: "机", count: 121) }
        )
        let expected = SHA256.hash(
            data: Data("com.xxsnap.mac\0abcdef12-3456-7890-abcd-ef1234567890".utf8)
        ).map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(try identity.deviceHash(), expected)
        XCTAssertEqual(identity.displayName().count, 120)
        XCTAssertEqual(try identity.deviceHash().count, 64)
    }

    func testDeviceIdentityFailsSafelyForMissingOrBlankUUID() {
        for value in [nil, "   "] as [String?] {
            let identity = CommercialDeviceIdentity(platformUUIDProvider: { value })
            XCTAssertThrowsError(try identity.deviceHash()) {
                XCTAssertEqual($0 as? CommercialDeviceIdentityError, .platformUUIDUnavailable)
            }
        }
    }

    private func envelope(_ value: String) -> SignedEnvelope {
        SignedEnvelope(keyId: "key", payload: Data(value.utf8).base64EncodedString(), signature: String(repeating: "A", count: 88))
    }
}

private final class FakeCommercialKeychain: CommercialKeychainAccessing {
    var items: [String: Data] = [:]
    var copyStatus: OSStatus?
    var addStatus: OSStatus?
    var updateStatus: OSStatus?
    var deleteStatus: OSStatus?
    var addedAccounts: [String] = []
    var updatedAccounts: [String] = []

    func copy(service: String, account: String) -> (OSStatus, Data?) {
        if let copyStatus { return (copyStatus, nil) }
        guard let data = items[account] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data)
    }

    func add(service: String, account: String, data: Data) -> OSStatus {
        if let addStatus { return addStatus }
        guard items[account] == nil else { return errSecDuplicateItem }
        addedAccounts.append(account)
        items[account] = data
        return errSecSuccess
    }

    func update(service: String, account: String, data: Data) -> OSStatus {
        if let updateStatus { return updateStatus }
        guard items[account] != nil else { return errSecItemNotFound }
        updatedAccounts.append(account)
        items[account] = data
        return errSecSuccess
    }

    func delete(service: String, account: String) -> OSStatus {
        if let deleteStatus { return deleteStatus }
        guard items.removeValue(forKey: account) != nil else { return errSecItemNotFound }
        return errSecSuccess
    }
}
