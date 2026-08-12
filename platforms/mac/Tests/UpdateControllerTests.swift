import CryptoKit
import XCTest
@testable import xxsnap

final class UpdateControllerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSemanticVersionComparisonUsesBuildNumberForEqualVersions() throws {
        XCTAssertLessThan(try XCTUnwrap(AppUpdateVersion("1.9.9")), try XCTUnwrap(AppUpdateVersion("2.0.0")))
        XCTAssertLessThan(try XCTUnwrap(AppUpdateVersion("1.0.0-beta.1")), try XCTUnwrap(AppUpdateVersion("1.0.0")))
        XCTAssertTrue(AppUpdateVersion.isOlder(
            version: "1.0.0",
            build: 1,
            than: "1.0.0",
            build: 2
        ))
        XCTAssertFalse(AppUpdateVersion.isOlder(
            version: "1.1.0",
            build: 1,
            than: "1.0.0",
            build: 99
        ))
    }

    func testEvaluatorReturnsOptionalUpdateWithoutRequirement() throws {
        let result = AppUpdatePolicyEvaluator.evaluate(
            policy: policy(requirements: []),
            currentVersion: "1.0.0",
            currentBuild: 2
        )

        guard case let .available(release) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(release.version, "1.1.0")
        XCTAssertEqual(release.buildNumber, 3)
    }

    func testEvaluatorUsesSignedServerTimeForGraceAndMandatoryStates() throws {
        let future = AppUpdateRequirement(
            minimumVersion: "1.1.0",
            minimumBuildNumber: 2,
            enforceAfter: now.addingTimeInterval(3_600)
        )
        let grace = AppUpdatePolicyEvaluator.evaluate(
            policy: policy(requirements: [future]),
            currentVersion: "1.0.0",
            currentBuild: 1
        )
        guard case let .grace(_, deadline) = grace else { return XCTFail("expected grace") }
        XCTAssertEqual(deadline, future.enforceAfter)

        let expired = AppUpdateRequirement(
            minimumVersion: "1.1.0",
            minimumBuildNumber: 2,
            enforceAfter: now.addingTimeInterval(-1)
        )
        let mandatory = AppUpdatePolicyEvaluator.evaluate(
            policy: policy(requirements: [expired]),
            currentVersion: "1.0.0",
            currentBuild: 1
        )
        guard case let .required(_, deadline) = mandatory else { return XCTFail("expected required") }
        XCTAssertEqual(deadline, expired.enforceAfter)
    }

    func testEvaluatorDoesNotBlockAClientThatMeetsTheMinimumVersion() throws {
        let requirement = AppUpdateRequirement(
            minimumVersion: "1.1.0",
            minimumBuildNumber: 2,
            enforceAfter: now.addingTimeInterval(-1)
        )
        let result = AppUpdatePolicyEvaluator.evaluate(
            policy: policy(requirements: [requirement]),
            currentVersion: "1.1.0",
            currentBuild: 3
        )

        XCTAssertEqual(result, .upToDate)
    }

    func testUpdateDownloadURLOnlyAllowsProductionDownloadEndpoint() {
        XCTAssertTrue(AppUpdateRelease.isAllowedDownloadURL(
            URL(string: "https://download.xxsofts.com/api/v1/downloads/123")!
        ))
        for value in [
            "http://download.xxsofts.com/api/v1/downloads/123",
            "https://download.xxsofts.com.evil.test/api/v1/downloads/123",
            "https://download.xxsofts.com/other/123",
            "https://user@download.xxsofts.com/api/v1/downloads/123",
        ] {
            XCTAssertFalse(AppUpdateRelease.isAllowedDownloadURL(URL(string: value)!))
        }
    }

    func testVerifierAcceptsFreshSignedUpdatePolicyAndRejectsTampering() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let verifier = CommercialSignatureVerifier(publicKeys: ["update-key": privateKey.publicKey])
        let payload = try JSONEncoder().encode(policy(requirements: []))
        let envelope = SignedEnvelope(
            keyId: "update-key",
            payload: payload.base64EncodedString(),
            signature: try privateKey.signature(for: payload).base64EncodedString()
        )

        XCTAssertEqual(try verifier.verifyUpdatePolicy(envelope, at: now), policy(requirements: []))

        let tampered = SignedEnvelope(
            keyId: envelope.keyId,
            payload: Data("{}".utf8).base64EncodedString(),
            signature: envelope.signature
        )
        XCTAssertThrowsError(try verifier.verifyUpdatePolicy(tampered, at: now))
    }

    private func policy(requirements: [AppUpdateRequirement]) -> AppUpdatePolicy {
        AppUpdatePolicy(
            schemaVersion: 1,
            generatedAt: now,
            expiresAt: now.addingTimeInterval(600),
            latest: AppUpdateRelease(
                version: "1.1.0",
                buildNumber: 3,
                downloadURL: URL(string: "https://download.xxsofts.com/api/v1/downloads/latest")!,
                sha256: String(repeating: "a", count: 64),
                releaseNotes: "Update"
            ),
            requirements: requirements
        )
    }
}
