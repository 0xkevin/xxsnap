import CryptoKit
import Security
import XCTest
@testable import xxsnap

final class CommercialCredentialStoreTests: XCTestCase {
    func testKeychainStoreAtomicallyStoresEnvelopeAndAnchorInOneAccessAccount() throws {
        let keychain = FakeCommercialKeychain()
        let store = CommercialCredentialStore(keychain: keychain)
        let first = envelope("first")
        let second = envelope("second")
        let firstAnchor = anchor(issuedAt: 1_000)
        let secondAnchor = anchor(issuedAt: 2_000)

        XCTAssertNil(try store.loadPolicyEnvelope())
        try store.savePolicyEnvelope(first)
        try store.saveAccessRecord(.active(envelope: first, anchor: firstAnchor))
        XCTAssertEqual(try store.loadPolicyEnvelope(), first)
        XCTAssertEqual(
            try store.loadAccessRecord(),
            .active(envelope: first, anchor: firstAnchor)
        )

        try store.saveAccessRecord(.active(envelope: second, anchor: secondAnchor))
        XCTAssertEqual(
            try store.loadAccessRecord(),
            .active(envelope: second, anchor: secondAnchor)
        )
        XCTAssertEqual(keychain.addedAccounts, ["policy", "access"])
        XCTAssertEqual(keychain.updatedAccounts, ["access"])

        try store.deleteAccessRecord()
        XCTAssertNil(try store.loadAccessRecord())
        XCTAssertEqual(try store.loadPolicyEnvelope(), first)
    }

    func testFailedAtomicUpdateLeavesPreviousEnvelopeAndAnchorTogether() throws {
        let keychain = FakeCommercialKeychain()
        let store = CommercialCredentialStore(keychain: keychain)
        let original = CommercialAccessRecord.active(envelope: envelope("old"), anchor: anchor(issuedAt: 1_000))
        try store.saveAccessRecord(original)
        keychain.updateStatus = errSecInteractionNotAllowed

        XCTAssertThrowsError(
            try store.saveAccessRecord(.active(envelope: envelope("new"), anchor: anchor(issuedAt: 2_000)))
        ) {
            XCTAssertEqual($0 as? CommercialCredentialStoreError, .keychain(errSecInteractionNotAllowed))
        }

        keychain.updateStatus = nil
        XCTAssertEqual(try store.loadAccessRecord(), original)
    }

    func testCorruptAnchorDoesNotHideValidEnvelopeAndLegacyRawEnvelopeFailsSafeForTrial() throws {
        let keychain = FakeCommercialKeychain()
        let store = CommercialCredentialStore(keychain: keychain)
        let validEnvelope = envelope("paid")
        let recordData = try JSONEncoder().encode(
            CommercialAccessRecord.active(envelope: validEnvelope, anchor: anchor(issuedAt: 1_000))
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: recordData) as? [String: Any])
        object["anchor"] = "damaged"
        keychain.items["access"] = try JSONSerialization.data(withJSONObject: object)

        XCTAssertEqual(
            try store.loadAccessRecord(),
            .active(envelope: validEnvelope, anchor: nil)
        )

        keychain.items["access"] = try JSONEncoder().encode(validEnvelope)
        XCTAssertEqual(
            try store.loadAccessRecord(),
            .active(envelope: validEnvelope, anchor: nil)
        )
    }

    func testKeychainStorePropagatesErrorsAndRejectsCorruptData() throws {
        let keychain = FakeCommercialKeychain()
        let store = CommercialCredentialStore(keychain: keychain)
        keychain.items["policy"] = Data("not-json".utf8)
        XCTAssertThrowsError(try store.loadPolicyEnvelope()) {
            XCTAssertEqual($0 as? CommercialCredentialStoreError, .corruptData)
        }

        keychain.copyStatus = errSecAuthFailed
        XCTAssertThrowsError(try store.loadAccessRecord()) {
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
        XCTAssertThrowsError(try CommercialCredentialStore(keychain: deleteKeychain).deleteAccessRecord()) {
            XCTAssertEqual($0 as? CommercialCredentialStoreError, .keychain(errSecAuthFailed))
        }
    }

    func testTerminalTombstoneReplacesCredentialInSameAccessAccount() throws {
        let keychain = FakeCommercialKeychain()
        let store = CommercialCredentialStore(keychain: keychain)
        try store.saveAccessRecord(.active(envelope: envelope("private"), anchor: anchor(issuedAt: 1_000)))
        try store.saveAccessRecord(.terminal(.revoked))

        XCTAssertEqual(try store.loadAccessRecord(), .terminal(.revoked))
        XCTAssertEqual(keychain.addedAccounts, ["access"])
        XCTAssertEqual(keychain.updatedAccounts, ["access"])
    }

    func testTerminalMarkerPersistsOnlyNonSensitiveVersionAndReason() throws {
        let suite = "com.xxsnap.tests.terminal-marker.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CommercialTerminalMarkerStore(userDefaults: defaults)

        try store.saveTerminalMarker(.revoked)

        XCTAssertEqual(try store.loadTerminalMarker(), .revoked)
        let domain = try XCTUnwrap(defaults.persistentDomain(forName: suite))
        let data = try XCTUnwrap(domain.values.compactMap { $0 as? Data }.first)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["schemaVersion", "reason"])
        XCTAssertEqual(payload["schemaVersion"] as? Int, 1)
        XCTAssertEqual(payload["reason"] as? String, "revoked")
        try store.deleteTerminalMarker()
        XCTAssertNil(try store.loadTerminalMarker())
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

    private func anchor(issuedAt: TimeInterval) -> CommercialTimeAnchor {
        CommercialTimeAnchor(issuedAt: Date(timeIntervalSince1970: issuedAt), systemUptime: 123)
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
