import CryptoKit
import Foundation
import XCTest
@testable import xxsnap

final class CommercialPolicyTests: XCTestCase {
    private let testPublicKey = try! Curve25519.Signing.PublicKey(
        rawRepresentation: Data(base64Encoded: "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=")!
    )
    private let goldenEnvelope = SignedEnvelope(
        keyId: "fixed-test-key",
        payload: "eyJiaWxsaW5nUmVhZHkiOmZhbHNlLCJjb3B5Ijp7ImVuIjp7InByb1JlcXVpcmVkIjoiUHJvIHJlcXVpcmVkIiwidHJpYWxVbmF2YWlsYWJsZSI6IlRyaWFsIHVuYXZhaWxhYmxlIG9uIHRoaXMgZGV2aWNlIn0sInpoQ04iOnsicHJvUmVxdWlyZWQiOiLpnIDopoHkuJPkuJrniYgiLCJ0cmlhbFVuYXZhaWxhYmxlIjoi5q2k6K6+5aSH5peg5rOV6K+V55SoIn19LCJkZXZpY2VMaW1pdCI6MywiZWZmZWN0aXZlQXQiOiIyMDI2LTA3LTMxVDAwOjAwOjAwLjEyMzQ1NloiLCJleHBpcmVzQXQiOiIyMDI2LTA4LTMwVDAwOjAwOjAwWiIsImZlYXR1cmVzIjp7Im9jciI6ZmFsc2UsInNjcm9sbF9jYXB0dXJlIjpmYWxzZSwidGVhY2hpbmdfcGVuIjpmYWxzZX0sIm1pbmltdW1TYWZlVmVyc2lvbiI6IjEuMC4wIiwibW9kZSI6ImFsbF9mcmVlIiwicG9saWN5SWQiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJwdXJjaGFzZSI6eyJlblVSTCI6Imh0dHBzOi8veHhzbmFwLnh4c29mdHMuY29tL3B1cmNoYXNlL2VuIiwibGF1bmNoUHJpY2VDbnkiOjQ4LCJyZWd1bGFyUHJpY2VDbnkiOjY4LCJyZW5ld2FsUHJpY2VDbnkiOjM0LCJ6aENOVVJMIjoiaHR0cHM6Ly94eHNuYXAueHhzb2Z0cy5jb20vcHVyY2hhc2UvemgtY24ifSwic2NoZW1hVmVyc2lvbiI6MSwidHJpYWxEYXlzIjoxNCwidXBkYXRlTW9udGhzIjoxMn0=",
        signature: "0t4UHpS462VIR2bL8v/26r4uIV9B04yG1wAx/4iMSo8xiurxgj3X/aUFFeopgsooBVjLQASzPvk71tih++86DQ=="
    )

    func testCommercialFeatureWireSetContainsExactlyThreeProducts() {
        XCTAssertEqual(
            Set(CommercialFeature.allCases),
            [.scrollCapture, .ocr, .teachingPen]
        )
        XCTAssertEqual(
            Set(CommercialFeature.allCases.map(\.rawValue)),
            ["scroll_capture", "ocr", "teaching_pen"]
        )
    }

    func testPythonGoldenPolicyVectorVerifiesWithoutReserializingPayload() throws {
        let verifier = CommercialSignatureVerifier(publicKeys: ["fixed-test-key": testPublicKey])

        let policy = try verifier.verifyPolicy(
            goldenEnvelope,
            at: instant("2026-08-01T00:00:00Z")
        )

        XCTAssertEqual(policy.schemaVersion, 1)
        XCTAssertEqual(policy.policyId, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(policy.mode, .allFree)
        XCTAssertEqual(policy.minimumSafeVersion, "1.0.0")
        XCTAssertEqual(policy.effectiveAt, instant("2026-07-31T00:00:00.123456Z"))
        XCTAssertEqual(policy.purchase.zhCNURL.absoluteString, "https://xxsnap.xxsofts.com/purchase/zh-cn")
        XCTAssertEqual(policy.copy.zhCN.proRequired, "需要专业版")
    }

    func testFullPolicyJSONRejectsUnknownOrMissingFields() throws {
        let raw = try XCTUnwrap(Data(base64Encoded: goldenEnvelope.payload))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        object["unexpected"] = true

        XCTAssertThrowsError(try CommercialJSON.decoder.decode(CommercialPolicy.self, from: JSONSerialization.data(withJSONObject: object)))

        object.removeValue(forKey: "unexpected")
        object.removeValue(forKey: "copy")
        XCTAssertThrowsError(try CommercialJSON.decoder.decode(CommercialPolicy.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testAllFreeSnapshotOpensEveryFeatureAndHidesProBadges() throws {
        let policy = try verifiedGoldenPolicy()

        let snapshot = policy.accessSnapshot

        XCTAssertFalse(snapshot.showsProBadges)
        XCTAssertEqual(snapshot.availableFeatures, Set(CommercialFeature.allCases))
        XCTAssertTrue(snapshot.paidFeatures.isEmpty)
    }

    func testPaidSnapshotOnlyMarksPolicyFeaturesAsPaid() throws {
        var policy = try verifiedGoldenPolicy()
        policy.mode = .paid
        policy.features = .init(scrollCapture: true, ocr: false, teachingPen: true)

        let snapshot = policy.accessSnapshot

        XCTAssertTrue(snapshot.showsProBadges)
        XCTAssertEqual(snapshot.paidFeatures, [.scrollCapture, .teachingPen])
        XCTAssertEqual(snapshot.availableFeatures, [.ocr])
    }

    func testVerifierRejectsUnknownKeyTamperingAndNoncanonicalBase64() throws {
        let verifier = CommercialSignatureVerifier(publicKeys: ["fixed-test-key": testPublicKey])
        XCTAssertThrowsError(
            try verifier.verifyPolicy(
                SignedEnvelope(keyId: "missing", payload: goldenEnvelope.payload, signature: goldenEnvelope.signature),
                at: instant("2026-08-01T00:00:00Z")
            )
        ) { XCTAssertEqual($0 as? CommercialVerificationError, .unknownKey("missing")) }

        var tamperedPayload = try XCTUnwrap(Data(base64Encoded: goldenEnvelope.payload))
        tamperedPayload[tamperedPayload.startIndex] ^= 1
        XCTAssertThrowsError(
            try verifier.verifyPolicy(
                SignedEnvelope(keyId: "fixed-test-key", payload: tamperedPayload.base64EncodedString(), signature: goldenEnvelope.signature),
                at: instant("2026-08-01T00:00:00Z")
            )
        ) { XCTAssertEqual($0 as? CommercialVerificationError, .invalidSignature) }

        XCTAssertThrowsError(
            try verifier.verifyPolicy(
                SignedEnvelope(keyId: "fixed-test-key", payload: "AB==", signature: goldenEnvelope.signature),
                at: instant("2026-08-01T00:00:00Z")
            )
        ) { XCTAssertEqual($0 as? CommercialVerificationError, .noncanonicalBase64("payload")) }
    }

    func testVerifierEnforcesEnvelopeSizesBeforeCrypto() {
        let verifier = CommercialSignatureVerifier(publicKeys: ["fixed-test-key": testPublicKey])
        XCTAssertThrowsError(
            try verifier.verifyPolicy(
                SignedEnvelope(keyId: String(repeating: "k", count: 129), payload: goldenEnvelope.payload, signature: goldenEnvelope.signature),
                at: instant("2026-08-01T00:00:00Z")
            )
        ) { XCTAssertEqual($0 as? CommercialVerificationError, .fieldTooLong("keyId")) }

        XCTAssertThrowsError(
            try verifier.verifyPolicy(
                SignedEnvelope(keyId: "fixed-test-key", payload: String(repeating: "A", count: 131_073), signature: goldenEnvelope.signature),
                at: instant("2026-08-01T00:00:00Z")
            )
        ) { XCTAssertEqual($0 as? CommercialVerificationError, .fieldTooLong("payload")) }
    }

    func testVerifierReturnsStableSchemaDateAndWindowErrors() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let verifier = CommercialSignatureVerifier(publicKeys: ["fixed-test-key": privateKey.publicKey])
        let goldenVerifier = CommercialSignatureVerifier(publicKeys: ["fixed-test-key": testPublicKey])

        XCTAssertThrowsError(try verifier.verifyPolicy(signedPolicy(overrides: ["schemaVersion": 2], privateKey: privateKey), at: instant("2026-08-01T00:00:00Z"))) {
            XCTAssertEqual($0 as? CommercialVerificationError, .unsupportedSchema(2))
        }
        XCTAssertThrowsError(try verifier.verifyPolicy(signedPolicy(overrides: ["effectiveAt": "not-a-date"], privateKey: privateKey), at: instant("2026-08-01T00:00:00Z"))) {
            XCTAssertEqual($0 as? CommercialVerificationError, .invalidDate("effectiveAt"))
        }
        XCTAssertThrowsError(try goldenVerifier.verifyPolicy(goldenEnvelope, at: instant("2026-07-31T00:00:00Z"))) {
            XCTAssertEqual($0 as? CommercialVerificationError, .notEffective)
        }
        XCTAssertThrowsError(try goldenVerifier.verifyPolicy(goldenEnvelope, at: instant("2026-08-30T00:00:00Z"))) {
            XCTAssertEqual($0 as? CommercialVerificationError, .expired)
        }
        XCTAssertThrowsError(try verifier.verifyPolicy(signedPolicy(overrides: ["effectiveAt": "2026-07-30T23:59:59Z"], privateKey: privateKey), at: instant("2026-08-01T00:00:00Z"))) {
            XCTAssertEqual($0 as? CommercialVerificationError, .windowTooLong)
        }
    }

    func testEntitlementPayloadMatchesBackendWireContractIncludingBuildIdentity() throws {
        let json = Data("""
        {"schemaVersion":1,"credentialId":"00000000-0000-0000-0000-000000000010","licenseId":"00000000-0000-0000-0000-000000000020","deviceHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","access":"pro","appVersion":"1.2.3","buildNumber":42,"issuedAt":"2026-08-01T08:00:00.123456Z","expiresAt":null,"purchasedAt":"2026-07-01T00:00:00Z","updatesThrough":"2027-07-01T00:00:00Z","maximumBuildNumber":99,"emailMasked":"b***@example.com","activeDevices":1,"deviceLimit":3}
        """.utf8)

        let payload = try CommercialJSON.decoder.decode(EntitlementPayload.self, from: json)

        XCTAssertEqual(payload.appVersion, "1.2.3")
        XCTAssertEqual(payload.buildNumber, 42)
        XCTAssertEqual(payload.access, .pro)
        XCTAssertEqual(payload.issuedAt, instant("2026-08-01T08:00:00.123456Z"))

        var incomplete = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        incomplete.removeValue(forKey: "licenseId")
        XCTAssertThrowsError(
            try CommercialJSON.decoder.decode(
                EntitlementPayload.self,
                from: JSONSerialization.data(withJSONObject: incomplete)
            )
        )
    }

    func testBootstrapAcceptsValidPolicyAndRejectsExpiryAndReleaseGraceBoundary() throws {
        let verifier = CommercialSignatureVerifier(publicKeys: ["fixed-test-key": testPublicKey])
        let loader = CommercialPolicyBootstrapLoader(verifier: verifier)

        XCTAssertNoThrow(try loader.load(data: encoded(goldenEnvelope), now: instant("2026-08-01T00:00:00Z"), validation: .debug))
        XCTAssertThrowsError(try loader.load(data: encoded(goldenEnvelope), now: instant("2026-08-30T00:00:00Z"), validation: .debug)) {
            XCTAssertEqual($0 as? CommercialVerificationError, .expired)
        }
        XCTAssertNoThrow(try loader.load(data: encoded(goldenEnvelope), now: instant("2026-08-01T00:00:00Z"), validation: .release(buildDate: instant("2026-08-15T23:59:59Z"))))
        XCTAssertThrowsError(try loader.load(data: encoded(goldenEnvelope), now: instant("2026-08-01T00:00:00Z"), validation: .release(buildDate: instant("2026-08-16T00:00:00Z")))) {
            XCTAssertEqual($0 as? CommercialBootstrapError, .insufficientReleaseGrace)
        }
    }

    func testInfoContainsPinnedOriginAndSigningKeyDictionary() throws {
        let infoURL = sourceRoot.appendingPathComponent("platforms/mac/Resources/Info.plist")
        let infoData = try Data(contentsOf: infoURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(info["XXCommercialAPIOrigin"] as? String, "https://download.xxsofts.com")
        let keys = try XCTUnwrap(info["XXCommercialSigningPublicKeys"] as? [String: String])
        XCTAssertEqual(keys.keys.sorted(), ["commercial-ed25519-2026-01"])
        XCTAssertFalse(try XCTUnwrap(keys["commercial-ed25519-2026-01"]).isEmpty)
    }

    func testCommittedBootstrapIsActuallySignedByBackendDevelopmentKeyAndBounded() throws {
        let resource = sourceRoot.appendingPathComponent(
            "platforms/mac/Resources/Commercial/commercial-policy-bootstrap.json"
        )
        let publicKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: Data(base64Encoded: "iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w=")!
        )
        let policy = try CommercialPolicyBootstrapLoader(
            verifier: CommercialSignatureVerifier(
                publicKeys: ["commercial-ed25519-2026-01": publicKey]
            )
        ).load(
            url: resource,
            now: instant("2026-08-01T00:00:00Z"),
            validation: .debug
        )

        XCTAssertEqual(policy.mode, .allFree)
        XCTAssertFalse(policy.billingReady)
        XCTAssertEqual(policy.features, .init(scrollCapture: false, ocr: false, teachingPen: false))
        XCTAssertLessThanOrEqual(policy.effectiveAt, instant("2026-07-31T23:59:59Z"))
        XCTAssertLessThanOrEqual(policy.expiresAt, instant("2026-08-30T00:00:00Z"))
        XCTAssertLessThanOrEqual(policy.expiresAt.timeIntervalSince(policy.effectiveAt), 30 * 24 * 60 * 60)
    }

    func testNetworkMethodsUseExactPathsMethodsHeadersTimeoutAndCamelCaseBodies() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
            XCTAssertEqual(request.timeoutInterval, 15)
            switch request.url?.path {
            case "/api/v1/commercial/policy":
                XCTAssertEqual(request.httpMethod, "GET")
            case "/api/v1/commercial/trials/start":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(try self.jsonBody(request), [
                    "appVersion": AnyHashable("1.2.3"),
                    "buildNumber": AnyHashable(42),
                    "deviceHash": AnyHashable(String(repeating: "a", count: 64)),
                ])
            case "/api/v1/commercial/licenses/activate":
                XCTAssertEqual(request.httpMethod, "POST")
                let body = try self.jsonBody(request)
                XCTAssertEqual(body["activationCode"], "XXSNAP-2345-6789-ABCD-EFGH")
                XCTAssertEqual(body["deviceName"], "Kevin's Mac")
                XCTAssertNil(body["code"])
            case "/api/v1/commercial/licenses/validate":
                XCTAssertEqual(request.httpMethod, "POST")
                let body = try self.jsonObject(request)
                XCTAssertNotNil(body["credential"] as? [String: Any])
                XCTAssertEqual(body["appVersion"] as? String, "1.2.3")
                XCTAssertEqual(body["buildNumber"] as? Int, 42)
            case "/api/v1/commercial/licenses/deactivate":
                XCTAssertEqual(request.httpMethod, "POST")
                let body = try self.jsonObject(request)
                XCTAssertEqual(body["deviceHash"] as? String, String(repeating: "a", count: 64))
                XCTAssertNil(body["appVersion"])
                return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
            }
            return self.envelopeResponse(for: request)
        }
        let identity = CommercialClientIdentity(deviceHash: String(repeating: "a", count: 64), appVersion: "1.2.3", buildNumber: 42)

        _ = try await client.fetchPolicy(locale: .english)
        _ = try await client.startTrial(.init(identity: identity), locale: .english)
        _ = try await client.activate(.init(email: "buyer@example.com", activationCode: "XXSNAP-2345-6789-ABCD-EFGH", deviceName: "Kevin's Mac", identity: identity), locale: .english)
        _ = try await client.validate(.init(credential: goldenEnvelope, identity: identity), locale: .english)
        try await client.deactivate(.init(credential: goldenEnvelope, deviceHash: identity.deviceHash), locale: .english)
    }

    func testClientSendsSelectedEnglishAndChineseLocales() async throws {
        var languages: [String] = []
        let client = try makeClient { request in
            languages.append(request.value(forHTTPHeaderField: "Accept-Language") ?? "")
            return self.envelopeResponse(for: request)
        }

        _ = try await client.fetchPolicy(locale: .english)
        _ = try await client.fetchPolicy(locale: .zhHans)

        XCTAssertEqual(languages, ["en", "zh-CN"])
    }

    func testClientRejectsNonHTTPSWrongHostCredentialsAndNonstandardPort() throws {
        for value in [
            "http://download.xxsofts.com",
            "https://admin.xxsofts.com",
            "https://user@download.xxsofts.com",
            "https://download.xxsofts.com:444",
        ] {
            XCTAssertThrowsError(try CommercialPolicyClient(origin: URL(string: value)!, session: .shared)) {
                XCTAssertEqual($0 as? CommercialPolicyClientError, .invalidOrigin)
            }
        }
    }

    func testClientMapsMalformedSuccessAndStable422And409ErrorEnvelopes() async throws {
        let malformed = try makeClient { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        await assertClientError(.malformedResponse) { try await malformed.fetchPolicy(locale: .english) }

        let validation = try makeClient { request in
            let body = Data("""
            {"error":{"code":"validation_error","message":"Request validation failed","fields":[{"loc":["body","deviceHash"],"type":"string_pattern_mismatch","message":"String should match pattern"}]}}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!, body)
        }
        do {
            _ = try await validation.fetchPolicy(locale: .english)
            XCTFail("Expected server error")
        } catch let error as CommercialPolicyClientError {
            guard case let .server(status, detail) = error else { return XCTFail("Wrong error \(error)") }
            XCTAssertEqual(status, 422)
            XCTAssertEqual(detail.code, "validation_error")
            XCTAssertEqual(detail.fields?.first?.location, [.text("body"), .text("deviceHash")])
        }

        let conflict = try makeClient { request in
            let body = Data("""
            {"error":{"code":"trial_already_used","message":"此设备已使用过试用资格"}}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!, body)
        }
        do {
            _ = try await conflict.fetchPolicy(locale: .zhHans)
            XCTFail("Expected server error")
        } catch let error as CommercialPolicyClientError {
            guard case let .server(status, detail) = error else { return XCTFail("Wrong error \(error)") }
            XCTAssertEqual(status, 409)
            XCTAssertEqual(detail.code, "trial_already_used")
            XCTAssertEqual(detail.message, "此设备已使用过试用资格")
        }
    }

    private func verifiedGoldenPolicy() throws -> CommercialPolicy {
        try CommercialSignatureVerifier(publicKeys: ["fixed-test-key": testPublicKey])
            .verifyPolicy(goldenEnvelope, at: instant("2026-08-01T00:00:00Z"))
    }

    private func signedPolicy(
        overrides: [String: Any],
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> SignedEnvelope {
        let raw = try XCTUnwrap(Data(base64Encoded: goldenEnvelope.payload))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        object.merge(overrides) { _, new in new }
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return SignedEnvelope(
            keyId: "fixed-test-key",
            payload: payload.base64EncodedString(),
            signature: try privateKey.signature(for: payload).base64EncodedString()
        )
    }

    private func encoded(_ envelope: SignedEnvelope) throws -> Data {
        try JSONEncoder().encode(envelope)
    }

    private func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) throws -> CommercialPolicyClient {
        CommercialTestURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommercialTestURLProtocol.self]
        return try CommercialPolicyClient(
            origin: URL(string: "https://download.xxsofts.com")!,
            session: URLSession(configuration: configuration)
        )
    }

    private func envelopeResponse(for request: URLRequest) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            try! JSONEncoder().encode(goldenEnvelope)
        )
    }

    private func jsonObject(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try requestBody(request)) as? [String: Any])
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: AnyHashable] {
        let object = try jsonObject(request)
        return Dictionary(uniqueKeysWithValues: object.compactMap { key, value in
            (value as? AnyHashable).map { (key, $0) }
        })
    }

    private func assertClientError<T>(
        _ expected: CommercialPolicyClientError,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? CommercialPolicyClientError, expected)
        }
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func instant(_ value: String) -> Date {
        try! CommercialJSON.date(value, field: "test")
    }
}

private final class CommercialTestURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
