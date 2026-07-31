import Foundation

enum CommercialFeature: String, Codable, CaseIterable, Hashable {
    case scrollCapture = "scroll_capture"
    case ocr
    case teachingPen = "teaching_pen"
}

enum CommercialMode: String, Codable {
    case allFree = "all_free"
    case paid
}

struct SignedEnvelope: Codable, Equatable {
    let keyId: String
    let payload: String
    let signature: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case keyId, payload, signature
    }

    init(keyId: String, payload: String, signature: String) {
        self.keyId = keyId
        self.payload = payload
        self.signature = signature
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyId = try container.decode(String.self, forKey: .keyId)
        payload = try container.decode(String.self, forKey: .payload)
        signature = try container.decode(String.self, forKey: .signature)
    }
}

struct CommercialFeatures: Codable, Equatable {
    var scrollCapture: Bool
    var ocr: Bool
    var teachingPen: Bool

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case scrollCapture = "scroll_capture"
        case ocr
        case teachingPen = "teaching_pen"
    }

    init(scrollCapture: Bool, ocr: Bool, teachingPen: Bool) {
        self.scrollCapture = scrollCapture
        self.ocr = ocr
        self.teachingPen = teachingPen
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scrollCapture = try container.decode(Bool.self, forKey: .scrollCapture)
        ocr = try container.decode(Bool.self, forKey: .ocr)
        teachingPen = try container.decode(Bool.self, forKey: .teachingPen)
    }

    subscript(feature: CommercialFeature) -> Bool {
        switch feature {
        case .scrollCapture: scrollCapture
        case .ocr: ocr
        case .teachingPen: teachingPen
        }
    }
}

struct CommercialPurchase: Codable, Equatable {
    let regularPriceCny: Int
    let launchPriceCny: Int
    let renewalPriceCny: Int
    let zhCNURL: URL
    let enURL: URL

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case regularPriceCny, launchPriceCny, renewalPriceCny, zhCNURL, enURL
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        regularPriceCny = try container.decode(Int.self, forKey: .regularPriceCny)
        launchPriceCny = try container.decode(Int.self, forKey: .launchPriceCny)
        renewalPriceCny = try container.decode(Int.self, forKey: .renewalPriceCny)
        zhCNURL = try container.decode(URL.self, forKey: .zhCNURL)
        enURL = try container.decode(URL.self, forKey: .enURL)
    }
}

struct CommercialCopyEntry: Codable, Equatable {
    let proRequired: String
    let trialUnavailable: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case proRequired, trialUnavailable
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        proRequired = try container.decode(String.self, forKey: .proRequired)
        trialUnavailable = try container.decode(String.self, forKey: .trialUnavailable)
    }
}

struct CommercialCopy: Codable, Equatable {
    let zhCN: CommercialCopyEntry
    let en: CommercialCopyEntry

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case zhCN, en
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zhCN = try container.decode(CommercialCopyEntry.self, forKey: .zhCN)
        en = try container.decode(CommercialCopyEntry.self, forKey: .en)
    }
}

struct CommercialPolicy: Codable, Equatable {
    let schemaVersion: Int
    let policyId: String
    var mode: CommercialMode
    let billingReady: Bool
    let effectiveAt: Date
    let expiresAt: Date
    let trialDays: Int
    let updateMonths: Int
    let deviceLimit: Int
    let minimumSafeVersion: String
    var features: CommercialFeatures
    let purchase: CommercialPurchase
    let copy: CommercialCopy

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, policyId, mode, billingReady, effectiveAt, expiresAt
        case trialDays, updateMonths, deviceLimit, minimumSafeVersion, features, purchase, copy
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        policyId = try container.decode(String.self, forKey: .policyId)
        mode = try container.decode(CommercialMode.self, forKey: .mode)
        billingReady = try container.decode(Bool.self, forKey: .billingReady)
        effectiveAt = try CommercialJSON.date(
            container.decode(String.self, forKey: .effectiveAt),
            field: CodingKeys.effectiveAt.rawValue
        )
        expiresAt = try CommercialJSON.date(
            container.decode(String.self, forKey: .expiresAt),
            field: CodingKeys.expiresAt.rawValue
        )
        trialDays = try container.decode(Int.self, forKey: .trialDays)
        updateMonths = try container.decode(Int.self, forKey: .updateMonths)
        deviceLimit = try container.decode(Int.self, forKey: .deviceLimit)
        minimumSafeVersion = try container.decode(String.self, forKey: .minimumSafeVersion)
        features = try container.decode(CommercialFeatures.self, forKey: .features)
        purchase = try container.decode(CommercialPurchase.self, forKey: .purchase)
        copy = try container.decode(CommercialCopy.self, forKey: .copy)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(policyId, forKey: .policyId)
        try container.encode(mode, forKey: .mode)
        try container.encode(billingReady, forKey: .billingReady)
        try container.encode(CommercialJSON.string(effectiveAt), forKey: .effectiveAt)
        try container.encode(CommercialJSON.string(expiresAt), forKey: .expiresAt)
        try container.encode(trialDays, forKey: .trialDays)
        try container.encode(updateMonths, forKey: .updateMonths)
        try container.encode(deviceLimit, forKey: .deviceLimit)
        try container.encode(minimumSafeVersion, forKey: .minimumSafeVersion)
        try container.encode(features, forKey: .features)
        try container.encode(purchase, forKey: .purchase)
        try container.encode(copy, forKey: .copy)
    }
}

struct CommercialPolicyAccessSnapshot: Equatable {
    let availableFeatures: Set<CommercialFeature>
    let paidFeatures: Set<CommercialFeature>
    let showsProBadges: Bool
}

extension CommercialPolicy {
    var accessSnapshot: CommercialPolicyAccessSnapshot {
        if mode == .allFree {
            return CommercialPolicyAccessSnapshot(
                availableFeatures: Set(CommercialFeature.allCases),
                paidFeatures: [],
                showsProBadges: false
            )
        }
        let paid = Set(CommercialFeature.allCases.filter { features[$0] })
        return CommercialPolicyAccessSnapshot(
            availableFeatures: Set(CommercialFeature.allCases).subtracting(paid),
            paidFeatures: paid,
            showsProBadges: !paid.isEmpty
        )
    }
}

enum CommercialAccessKind: String, Codable {
    case allFree = "all_free"
    case trial
    case free
    case pro
}

struct EntitlementPayload: Codable, Equatable {
    let schemaVersion: Int
    let credentialId: UUID
    let licenseId: UUID?
    let deviceHash: String
    let access: CommercialAccessKind
    let appVersion: String
    let buildNumber: Int
    let issuedAt: Date
    let expiresAt: Date?
    let purchasedAt: Date?
    let updatesThrough: Date?
    let maximumBuildNumber: Int?
    let emailMasked: String?
    let activeDevices: Int?
    let deviceLimit: Int

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, credentialId, licenseId, deviceHash, access, appVersion, buildNumber
        case issuedAt, expiresAt, purchasedAt, updatesThrough, maximumBuildNumber
        case emailMasked, activeDevices, deviceLimit
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        credentialId = try container.decode(UUID.self, forKey: .credentialId)
        licenseId = try container.decodeRequiredOptional(UUID.self, forKey: .licenseId)
        deviceHash = try container.decode(String.self, forKey: .deviceHash)
        access = try container.decode(CommercialAccessKind.self, forKey: .access)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        buildNumber = try container.decode(Int.self, forKey: .buildNumber)
        issuedAt = try CommercialJSON.date(container.decode(String.self, forKey: .issuedAt), field: CodingKeys.issuedAt.rawValue)
        expiresAt = try CommercialJSON.optionalDate(container, key: .expiresAt)
        purchasedAt = try CommercialJSON.optionalDate(container, key: .purchasedAt)
        updatesThrough = try CommercialJSON.optionalDate(container, key: .updatesThrough)
        maximumBuildNumber = try container.decodeRequiredOptional(Int.self, forKey: .maximumBuildNumber)
        emailMasked = try container.decodeRequiredOptional(String.self, forKey: .emailMasked)
        activeDevices = try container.decodeRequiredOptional(Int.self, forKey: .activeDevices)
        deviceLimit = try container.decode(Int.self, forKey: .deviceLimit)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(credentialId, forKey: .credentialId)
        try container.encodeIfPresent(licenseId, forKey: .licenseId)
        try container.encode(deviceHash, forKey: .deviceHash)
        try container.encode(access, forKey: .access)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(buildNumber, forKey: .buildNumber)
        try container.encode(CommercialJSON.string(issuedAt), forKey: .issuedAt)
        try container.encode(expiresAt.map(CommercialJSON.string), forKey: .expiresAt)
        try container.encode(purchasedAt.map(CommercialJSON.string), forKey: .purchasedAt)
        try container.encode(updatesThrough.map(CommercialJSON.string), forKey: .updatesThrough)
        try container.encodeIfPresent(maximumBuildNumber, forKey: .maximumBuildNumber)
        try container.encodeIfPresent(emailMasked, forKey: .emailMasked)
        try container.encodeIfPresent(activeDevices, forKey: .activeDevices)
        try container.encode(deviceLimit, forKey: .deviceLimit)
    }
}

enum CommercialLocale: Equatable {
    case english
    case zhHans

    var acceptLanguage: String {
        switch self {
        case .english: "en"
        case .zhHans: "zh-CN"
        }
    }
}

struct CommercialClientIdentity: Codable, Equatable {
    let deviceHash: String
    let appVersion: String
    let buildNumber: Int

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case deviceHash, appVersion, buildNumber
    }

    init(deviceHash: String, appVersion: String, buildNumber: Int) {
        self.deviceHash = deviceHash
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceHash = try container.decode(String.self, forKey: .deviceHash)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        buildNumber = try container.decode(Int.self, forKey: .buildNumber)
    }
}

struct CommercialTrialStartRequest: Codable, Equatable {
    let deviceHash: String
    let appVersion: String
    let buildNumber: Int

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case deviceHash, appVersion, buildNumber
    }

    init(identity: CommercialClientIdentity) {
        deviceHash = identity.deviceHash
        appVersion = identity.appVersion
        buildNumber = identity.buildNumber
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceHash = try container.decode(String.self, forKey: .deviceHash)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        buildNumber = try container.decode(Int.self, forKey: .buildNumber)
    }
}

struct CommercialLicenseActivateRequest: Codable, Equatable {
    let email: String
    let activationCode: String
    let deviceHash: String
    let deviceName: String
    let appVersion: String
    let buildNumber: Int

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case email, activationCode, deviceHash, deviceName, appVersion, buildNumber
    }

    init(
        email: String,
        activationCode: String,
        deviceName: String,
        identity: CommercialClientIdentity
    ) {
        self.email = email
        self.activationCode = activationCode
        deviceHash = identity.deviceHash
        self.deviceName = deviceName
        appVersion = identity.appVersion
        buildNumber = identity.buildNumber
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decode(String.self, forKey: .email)
        activationCode = try container.decode(String.self, forKey: .activationCode)
        deviceHash = try container.decode(String.self, forKey: .deviceHash)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        buildNumber = try container.decode(Int.self, forKey: .buildNumber)
    }
}

struct CommercialLicenseValidateRequest: Codable, Equatable {
    let credential: SignedEnvelope
    let deviceHash: String
    let appVersion: String
    let buildNumber: Int

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case credential, deviceHash, appVersion, buildNumber
    }

    init(credential: SignedEnvelope, identity: CommercialClientIdentity) {
        self.credential = credential
        deviceHash = identity.deviceHash
        appVersion = identity.appVersion
        buildNumber = identity.buildNumber
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        credential = try container.decode(SignedEnvelope.self, forKey: .credential)
        deviceHash = try container.decode(String.self, forKey: .deviceHash)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        buildNumber = try container.decode(Int.self, forKey: .buildNumber)
    }
}

struct CommercialLicenseDeactivateRequest: Codable, Equatable {
    let credential: SignedEnvelope
    let deviceHash: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case credential, deviceHash
    }

    init(credential: SignedEnvelope, deviceHash: String) {
        self.credential = credential
        self.deviceHash = deviceHash
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        credential = try container.decode(SignedEnvelope.self, forKey: .credential)
        deviceHash = try container.decode(String.self, forKey: .deviceHash)
    }
}

enum CommercialErrorLocation: Codable, Equatable {
    case text(String)
    case index(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .text(value)
        } else if let value = try? container.decode(Int.self) {
            self = .index(value)
        } else {
            throw DecodingError.typeMismatch(
                CommercialErrorLocation.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected string or integer")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(value): try container.encode(value)
        case let .index(value): try container.encode(value)
        }
    }
}

struct CommercialAPIErrorField: Codable, Equatable {
    let location: [CommercialErrorLocation]
    let type: String
    let message: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case location = "loc"
        case type, message
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        location = try container.decode([CommercialErrorLocation].self, forKey: .location)
        type = try container.decode(String.self, forKey: .type)
        message = try container.decode(String.self, forKey: .message)
    }
}

struct CommercialAPIErrorDetail: Codable, Equatable {
    let code: String
    let message: String
    let fields: [CommercialAPIErrorField]?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code, message, fields
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        fields = try container.decodeIfPresent([CommercialAPIErrorField].self, forKey: .fields)
    }
}

struct CommercialAPIErrorEnvelope: Codable, Equatable {
    let error: CommercialAPIErrorDetail

    private enum CodingKeys: String, CodingKey, CaseIterable { case error }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        error = try decoder.container(keyedBy: CodingKeys.self)
            .decode(CommercialAPIErrorDetail.self, forKey: .error)
    }
}

enum CommercialJSON {
    static var decoder: JSONDecoder { JSONDecoder() }

    static func date(_ value: String, field: String) throws -> Date {
        guard value.hasSuffix("Z") else {
            throw CommercialDateDecodingError(field: field)
        }
        let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'", "yyyy-MM-dd'T'HH:mm:ss.SSSSS'Z'", "yyyy-MM-dd'T'HH:mm:ss.SSSS'Z'", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd'T'HH:mm:ss.SS'Z'", "yyyy-MM-dd'T'HH:mm:ss.S'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let result = formatter.date(from: value) {
                return result
            }
        }
        throw CommercialDateDecodingError(field: field)
    }

    static func string(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }

    fileprivate static func optionalDate<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        key: K
    ) throws -> Date? {
        guard let value = try container.decodeRequiredOptional(String.self, forKey: key) else { return nil }
        return try date(value, field: key.stringValue)
    }
}

private extension KeyedDecodingContainer {
    func decodeRequiredOptional<T: Decodable>(
        _ type: T.Type,
        forKey key: Key
    ) throws -> T? {
        guard contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                .init(codingPath: codingPath, debugDescription: "Required nullable field is missing")
            )
        }
        return try decodeIfPresent(type, forKey: key)
    }
}

struct CommercialDateDecodingError: Error, Equatable {
    let field: String
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private extension Decoder {
    func rejectUnknownKeys(allowed: [String]) throws {
        let container = try container(keyedBy: AnyCodingKey.self)
        let unexpected = Set(container.allKeys.map(\.stringValue)).subtracting(allowed)
        guard unexpected.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath, debugDescription: "Unexpected keys: \(unexpected.sorted())")
            )
        }
    }
}
