import CryptoKit
import Darwin
import Security
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

    func testArtifactValidatorAcceptsExpectedSHA256AndRejectsMismatch() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("xxsnap-update".utf8).write(to: fileURL)

        XCTAssertNoThrow(try AppUpdateArtifactValidator.verifySHA256(
            of: fileURL,
            expected: "249d2d26d1db422fab869ecc17995abca581f3124528ae9818b76bd7b0fceeb0"
        ))
        XCTAssertThrowsError(try AppUpdateArtifactValidator.verifySHA256(
            of: fileURL,
            expected: String(repeating: "0", count: 64)
        ))
    }

    func testCandidateValidatorRequiresMatchingIdentityAndRelease() throws {
        let release = AppUpdateRelease(
            version: "1.2.0",
            buildNumber: 7,
            downloadURL: URL(string: "https://download.xxsofts.com/api/v1/downloads/latest")!,
            sha256: String(repeating: "a", count: 64),
            releaseNotes: "Update"
        )

        XCTAssertNoThrow(try AppUpdateCandidateValidator.validate(
            info: [
                "CFBundleIdentifier": "com.xxsnap.mac",
                "CFBundleShortVersionString": "1.2.0",
                "CFBundleVersion": "7",
            ],
            release: release,
            expectedBundleIdentifier: "com.xxsnap.mac"
        ))
        XCTAssertThrowsError(try AppUpdateCandidateValidator.validate(
            info: [
                "CFBundleIdentifier": "com.example.fake",
                "CFBundleShortVersionString": "1.2.0",
                "CFBundleVersion": "7",
            ],
            release: release,
            expectedBundleIdentifier: "com.xxsnap.mac"
        ))
    }

    func testUpdateFailuresHaveActionableBilingualMessages() {
        let chinese = PreferencesStrings(language: .zhHans)
        let english = PreferencesStrings(language: .english)

        XCTAssertTrue(chinese.updateFailureReason(
            AppUpdateInstallationError.currentApplicationUnavailable
        ).contains("应用程序"))
        XCTAssertTrue(english.updateFailureReason(
            AppUpdateInstallationError.checksumMismatch
        ).contains("integrity"))
    }

    func testUpdateProcessRunnerCapturesOnlyRequestedOutput() throws {
        let ignored = try AppUpdateProcessRunner.run(
            "/bin/echo",
            arguments: ["ignored"]
        )
        XCTAssertTrue(ignored.standardOutput.isEmpty)

        let captured = try AppUpdateProcessRunner.run(
            "/bin/echo",
            arguments: ["captured"],
            captureStandardOutput: true
        )
        XCTAssertEqual(String(data: captured.standardOutput, encoding: .utf8), "captured\n")
    }

    func testUpdateProcessRunnerStopsTimedOutCommand() {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let markerFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: pidFile)
            try? FileManager.default.removeItem(at: markerFile)
        }
        XCTAssertThrowsError(try AppUpdateProcessRunner.run(
            "/bin/zsh",
            arguments: [
                "-c",
                "(/bin/sleep 0.3; /usr/bin/touch \"$2\") & child=$!; /bin/echo $child > \"$1\"; wait",
                "timeout-test",
                pidFile.path,
                markerFile.path,
            ],
            timeout: 0.05
        )) { error in
            XCTAssertEqual(error as? AppUpdateInstallationError, .commandTimedOut)
        }
        usleep(500_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerFile.path))
        let childPID = try? String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let childPID, let pid = Int32(childPID) {
            XCTAssertNotEqual(kill(pid, 0), 0)
        } else {
            XCTFail("expected child process identifier")
        }
    }

    func testInstallerCodeHashRequirementHasValidRequirementSyntax() {
        let requirement = SystemAppUpdateInstaller.codeHashRequirement(
            for: [
                String(repeating: "a", count: 40),
                String(repeating: "b", count: 40),
            ]
        )
        var parsedRequirement: SecRequirement?

        XCTAssertEqual(
            SecRequirementCreateWithString(
                requirement as CFString,
                SecCSFlags(rawValue: 0),
                &parsedRequirement
            ),
            errSecSuccess
        )
        XCTAssertNotNil(parsedRequirement)
        XCTAssertEqual(
            requirement,
            "(cdhash H\"\(String(repeating: "a", count: 40))\" or "
                + "cdhash H\"\(String(repeating: "b", count: 40))\")"
        )

        let installationRequirement = SystemAppUpdateInstaller.installationRequirement(
            signingRequirement: "identifier \"com.xxsnap.mac\"",
            codeDirectoryRequirement: requirement
        )
        parsedRequirement = nil
        XCTAssertEqual(
            SecRequirementCreateWithString(
                installationRequirement as CFString,
                SecCSFlags(rawValue: 0),
                &parsedRequirement
            ),
            errSecSuccess
        )
        XCTAssertNotNil(parsedRequirement)
    }

    func testInstallerCleanupPreservesOriginalCommandFailure() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let result = try AppUpdateProcessRunner.run(
            "/bin/zsh",
            arguments: [
                "-c",
                SystemAppUpdateInstaller.installScript,
                "installer-cleanup-test",
                workspace.appendingPathComponent("missing.app").path,
                workspace.appendingPathComponent("XxSnap.app").path,
                UUID().uuidString,
                SystemAppUpdateInstaller.codeHashRequirement(
                    for: [String(repeating: "a", count: 40)]
                ),
                "com.xxsnap.mac",
                "1.3.0",
                "6",
                "0",
            ],
            ignoreFailure: true
        )
        let errorOutput = String(data: result.standardError, encoding: .utf8) ?? ""

        XCTAssertNotEqual(result.status, 0)
        XCTAssertFalse(errorOutput.contains("read-only variable"))
    }

    func testInstallerRejectsChangedMetadataBeforeSwap() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staged = workspace.appendingPathComponent("staged.app", isDirectory: true)
        let target = workspace.appendingPathComponent("XxSnap.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: staged.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.xxsnap.mac",
            "CFBundleShortVersionString": "1.2.1",
            "CFBundleVersion": "5",
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: staged.appendingPathComponent("Contents/Info.plist"))
        let sentinel = target.appendingPathComponent("original")
        try Data("original".utf8).write(to: sentinel)

        let result = try AppUpdateProcessRunner.run(
            "/bin/zsh",
            arguments: [
                "-c",
                SystemAppUpdateInstaller.installScript,
                "installer-metadata-test",
                staged.path,
                target.path,
                UUID().uuidString,
                SystemAppUpdateInstaller.codeHashRequirement(
                    for: [String(repeating: "a", count: 40)]
                ),
                "com.xxsnap.mac",
                "1.3.0",
                "6",
                "0",
            ],
            ignoreFailure: true
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("original".utf8))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: workspace.path)
        XCTAssertFalse(leftovers.contains(where: { $0.contains(".update-") }))
    }

    func testPrivilegedInstallerHardensIncomingBeforeVerification() {
        let script = SystemAppUpdateInstaller.installScript
        let chown = script.range(of: "/usr/sbin/chown -R -h root:wheel \"$incoming\"")
        let metadata = script.range(of: "actual_identifier=$(/usr/bin/plutil")
        let signature = script.range(of: "/usr/bin/codesign --verify --deep --strict")

        XCTAssertNotNil(chown)
        XCTAssertNotNil(metadata)
        XCTAssertNotNil(signature)
        if let chown, let metadata, let signature {
            XCTAssertLessThan(chown.lowerBound, metadata.lowerBound)
            XCTAssertLessThan(metadata.lowerBound, signature.lowerBound)
        }
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
