import CryptoKit
import Foundation

enum CommercialVerificationError: Error, Equatable {
    case emptyField(String)
    case fieldTooLong(String)
    case unknownKey(String)
    case noncanonicalBase64(String)
    case invalidSignatureLength
    case invalidSignature
    case invalidPayload
    case unsupportedSchema(Int)
    case invalidDate(String)
    case notEffective
    case expired
    case invalidWindow
    case windowTooLong
}

final class CommercialSignatureVerifier {
    private let publicKeys: [String: Curve25519.Signing.PublicKey]

    init(publicKeys: [String: Curve25519.Signing.PublicKey]) {
        self.publicKeys = publicKeys
    }

    convenience init(bundle: Bundle) throws {
        guard let values = bundle.object(forInfoDictionaryKey: "XXCommercialSigningPublicKeys") as? [String: String] else {
            throw CommercialVerificationError.invalidPayload
        }
        var keys: [String: Curve25519.Signing.PublicKey] = [:]
        for (keyId, encoded) in values {
            let raw = try Self.canonicalBase64(encoded, field: "publicKey")
            guard raw.count == 32 else { throw CommercialVerificationError.invalidPayload }
            keys[keyId] = try Curve25519.Signing.PublicKey(rawRepresentation: raw)
        }
        self.init(publicKeys: keys)
    }

    func verifyPolicy(_ envelope: SignedEnvelope, at now: Date = Date()) throws -> CommercialPolicy {
        let payload = try verifiedPayload(envelope)
        let policy: CommercialPolicy
        do {
            policy = try CommercialJSON.decoder.decode(CommercialPolicy.self, from: payload)
        } catch let error as CommercialDateDecodingError {
            throw CommercialVerificationError.invalidDate(error.field)
        } catch {
            if let schema = Self.schemaVersion(in: payload), schema != 1 {
                throw CommercialVerificationError.unsupportedSchema(schema)
            }
            throw CommercialVerificationError.invalidPayload
        }
        guard policy.schemaVersion == 1 else {
            throw CommercialVerificationError.unsupportedSchema(policy.schemaVersion)
        }
        try validate(policy, at: now)
        return policy
    }

    func verifyEntitlement(_ envelope: SignedEnvelope) throws -> EntitlementPayload {
        let payload = try verifiedPayload(envelope)
        let entitlement: EntitlementPayload
        do {
            entitlement = try CommercialJSON.decoder.decode(EntitlementPayload.self, from: payload)
        } catch let error as CommercialDateDecodingError {
            throw CommercialVerificationError.invalidDate(error.field)
        } catch {
            if let schema = Self.schemaVersion(in: payload), schema != 1 {
                throw CommercialVerificationError.unsupportedSchema(schema)
            }
            throw CommercialVerificationError.invalidPayload
        }
        guard entitlement.schemaVersion == 1 else {
            throw CommercialVerificationError.unsupportedSchema(entitlement.schemaVersion)
        }
        guard entitlement.deviceHash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              !entitlement.appVersion.isEmpty,
              entitlement.appVersion.count <= 32,
              entitlement.buildNumber >= 0,
              (1...10).contains(entitlement.deviceLimit)
        else { throw CommercialVerificationError.invalidPayload }
        return entitlement
    }

    private func verifiedPayload(_ envelope: SignedEnvelope) throws -> Data {
        guard !envelope.keyId.isEmpty else { throw CommercialVerificationError.emptyField("keyId") }
        guard envelope.keyId.count <= 128 else { throw CommercialVerificationError.fieldTooLong("keyId") }
        guard !envelope.payload.isEmpty else { throw CommercialVerificationError.emptyField("payload") }
        guard envelope.payload.count <= 131_072 else { throw CommercialVerificationError.fieldTooLong("payload") }
        guard envelope.signature.count == 88 else { throw CommercialVerificationError.invalidSignatureLength }
        guard let publicKey = publicKeys[envelope.keyId] else {
            throw CommercialVerificationError.unknownKey(envelope.keyId)
        }
        let payload = try Self.canonicalBase64(envelope.payload, field: "payload")
        let signature = try Self.canonicalBase64(envelope.signature, field: "signature")
        guard signature.count == 64 else { throw CommercialVerificationError.invalidSignatureLength }
        guard publicKey.isValidSignature(signature, for: payload) else {
            throw CommercialVerificationError.invalidSignature
        }
        return payload
    }

    private func validate(_ policy: CommercialPolicy, at now: Date) throws {
        guard policy.policyId.range(of: "^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$", options: .regularExpression) != nil,
              (1...60).contains(policy.trialDays),
              (1...36).contains(policy.updateMonths),
              (1...10).contains(policy.deviceLimit),
              policy.minimumSafeVersion.range(of: "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$", options: .regularExpression) != nil,
              policy.purchase.regularPriceCny == 68,
              policy.purchase.launchPriceCny == 48,
              policy.purchase.renewalPriceCny == 34,
              Self.validPurchaseURL(policy.purchase.zhCNURL),
              Self.validPurchaseURL(policy.purchase.enURL),
              Self.validCopy(policy.copy.zhCN),
              Self.validCopy(policy.copy.en)
        else { throw CommercialVerificationError.invalidPayload }
        guard policy.effectiveAt < policy.expiresAt else {
            throw CommercialVerificationError.invalidWindow
        }
        guard policy.expiresAt.timeIntervalSince(policy.effectiveAt) <= 30 * 24 * 60 * 60 else {
            throw CommercialVerificationError.windowTooLong
        }
        guard now >= policy.effectiveAt else { throw CommercialVerificationError.notEffective }
        guard now < policy.expiresAt else { throw CommercialVerificationError.expired }
    }

    private static func canonicalBase64(_ value: String, field: String) throws -> Data {
        guard let decoded = Data(base64Encoded: value, options: []),
              decoded.base64EncodedString() == value
        else { throw CommercialVerificationError.noncanonicalBase64(field) }
        return decoded
    }

    private static func schemaVersion(in data: Data) -> Int? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["schemaVersion"] as? Int
    }

    private static func validPurchaseURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme == "https"
            && components.host == "xxsnap.xxsofts.com"
            && components.user == nil
            && components.password == nil
            && (components.port == nil || components.port == 443)
    }

    private static func validCopy(_ entry: CommercialCopyEntry) -> Bool {
        !entry.proRequired.isEmpty && entry.proRequired.count <= 255
            && !entry.trialUnavailable.isEmpty && entry.trialUnavailable.count <= 255
    }
}

enum CommercialBootstrapValidation: Equatable {
    case debug
    case release(buildDate: Date)
}

enum CommercialBootstrapError: Error, Equatable {
    case missingFile
    case insufficientReleaseGrace
}

struct CommercialPolicyBootstrapLoader {
    private let verifier: CommercialSignatureVerifier

    init(verifier: CommercialSignatureVerifier) {
        self.verifier = verifier
    }

    func load(
        data: Data,
        now: Date = Date(),
        validation: CommercialBootstrapValidation
    ) throws -> CommercialPolicy {
        let envelope: SignedEnvelope
        do {
            envelope = try CommercialJSON.decoder.decode(SignedEnvelope.self, from: data)
        } catch {
            throw CommercialVerificationError.invalidPayload
        }
        let policy = try verifier.verifyPolicy(envelope, at: now)
        if case let .release(buildDate) = validation,
           buildDate.addingTimeInterval(14 * 24 * 60 * 60) >= policy.expiresAt {
            throw CommercialBootstrapError.insufficientReleaseGrace
        }
        return policy
    }

    func load(
        url: URL,
        now: Date = Date(),
        validation: CommercialBootstrapValidation
    ) throws -> CommercialPolicy {
        guard let data = try? Data(contentsOf: url) else { throw CommercialBootstrapError.missingFile }
        return try load(data: data, now: now, validation: validation)
    }
}
