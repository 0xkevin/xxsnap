import CryptoKit
import Darwin
import Security
import XCTest
@testable import xxsnap

final class UpdateControllerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    func testUpdateDialogKeepsFixedSizeAndScrollsLongReleaseNotes() throws {
        let notes = (1...80).map { "\($0). 更新说明内容" }.joined(separator: "\n")
        let release = AppUpdateRelease(
            version: "1.4.0",
            buildNumber: 8,
            downloadURL: URL(string: "https://download.xxsofts.com/api/v1/downloads/latest")!,
            sha256: String(repeating: "a", count: 64),
            releaseNotes: notes
        )
        let controller = UpdateAvailableWindowController(
            release: release,
            title: "发现新版本",
            notice: nil,
            currentVersion: "1.3.0",
            currentBuild: 6,
            strings: PreferencesStrings(language: .zhHans)
        )

        let window = try XCTUnwrap(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.contentLayoutRect.width, 560, accuracy: 0.5)
        XCTAssertEqual(window.contentLayoutRect.height, 520, accuracy: 0.5)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(controller.releaseNotesScrollView.hasVerticalScroller)
        XCTAssertTrue(controller.releaseNotesTextView.isVerticallyResizable)
        XCTAssertEqual(controller.releaseNotesTextView.string, notes)
        XCTAssertGreaterThan(
            controller.releaseNotesTextView.frame.height,
            controller.releaseNotesScrollView.contentSize.height
        )
        let contentView = try XCTUnwrap(window.contentView)
        let downloadButtonFrame = controller.downloadButton.convert(
            controller.downloadButton.bounds,
            to: contentView
        )
        XCTAssertLessThanOrEqual(downloadButtonFrame.maxY, 72)
    }

    @MainActor
    func testUpdateDialogRendersMarkdownReleaseNotes() throws {
        let markdown = """
        # Highlights

        - Added **bold text**
        - Improved *italic text* and `inline code`
        1. Kept numbered lists

        Read the [release page](https://xxsnap.xxsofts.com/releases/).
        """
        let controller = makeUpdateDialog(releaseNotes: markdown)
        let rendered = try XCTUnwrap(controller.releaseNotesTextView.textStorage)

        XCTAssertFalse(rendered.string.contains("# Highlights"))
        XCTAssertTrue(rendered.string.contains("Highlights"))
        XCTAssertTrue(rendered.string.contains("• Added bold text"))
        XCTAssertTrue(rendered.string.contains("1. Kept numbered lists"))

        let headingRange = (rendered.string as NSString).range(of: "Highlights")
        let headingFont = try XCTUnwrap(
            rendered.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertGreaterThan(headingFont.pointSize, 13.5)

        let boldRange = (rendered.string as NSString).range(of: "bold text")
        let boldFont = try XCTUnwrap(rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))

        let italicRange = (rendered.string as NSString).range(of: "italic text")
        let italicFont = try XCTUnwrap(
            rendered.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))

        let codeRange = (rendered.string as NSString).range(of: "inline code")
        let codeFont = try XCTUnwrap(rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: codeFont).contains(.fixedPitchFontMask))

        let linkRange = (rendered.string as NSString).range(of: "release page")
        XCTAssertEqual(
            rendered.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL,
            URL(string: "https://xxsnap.xxsofts.com/releases/")
        )
    }

    @MainActor
    func testUpdateDialogOnlyActivatesWebLinksInMarkdown() throws {
        let controller = makeUpdateDialog(
            releaseNotes: """
            [HTTPS](https://xxsnap.xxsofts.com/) [HTTP](http://xxsnap.xxsofts.com/)
            [JavaScript](javascript:alert(1)) [File](file:///tmp/release-notes)
            [Data](data:text/plain,hello) [Custom](xxsnap://release)
            <https://xxsnap.xxsofts.com/releases/>
            """
        )
        let rendered = try XCTUnwrap(controller.releaseNotesTextView.textStorage)
        let renderedString = rendered.string as NSString
        let httpsRange = renderedString.range(of: "HTTPS")
        let httpRange = renderedString.range(of: "HTTP", options: [], range: NSRange(location: 6, length: renderedString.length - 6))

        XCTAssertEqual(
            rendered.attribute(.link, at: httpsRange.location, effectiveRange: nil) as? URL,
            URL(string: "https://xxsnap.xxsofts.com/")
        )
        XCTAssertEqual(
            rendered.attribute(.link, at: httpRange.location, effectiveRange: nil) as? URL,
            URL(string: "http://xxsnap.xxsofts.com/")
        )
        for label in ["JavaScript", "File", "Data", "Custom"] {
            let range = renderedString.range(of: label)
            XCTAssertNil(rendered.attribute(.link, at: range.location, effectiveRange: nil))
        }
        let autoLinkRange = renderedString.range(of: "https://xxsnap.xxsofts.com/releases/")
        XCTAssertEqual(
            rendered.attribute(.link, at: autoLinkRange.location, effectiveRange: nil) as? URL,
            URL(string: "https://xxsnap.xxsofts.com/releases/")
        )
    }

    @MainActor
    func testUpdateDialogPreservesMarkdownSyntaxInsideCodeBlocks() throws {
        let controller = makeUpdateDialog(
            releaseNotes: """
            ```json
            {"message":"**literal markdown**"}
            ```
            ## Parsed after code
            """
        )
        let rendered = try XCTUnwrap(controller.releaseNotesTextView.textStorage)
        let literalRange = (rendered.string as NSString).range(of: "**literal markdown**")

        XCTAssertNotEqual(literalRange.location, NSNotFound)
        let font = try XCTUnwrap(
            rendered.attribute(.font, at: literalRange.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask))

        let headingRange = (rendered.string as NSString).range(of: "Parsed after code")
        let headingFont = try XCTUnwrap(
            rendered.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertGreaterThan(headingFont.pointSize, 13.5)
    }

    @MainActor
    func testUpdateDialogUsesMatchingMarkdownCodeFences() throws {
        let controller = makeUpdateDialog(
            releaseNotes: """
            ````markdown
            ```example
            [Literal link](https://example.com/)
            ```
            ````
            ~~~json
            {"message":"**tilde literal**"}
            ~~~
            """
        )
        let rendered = try XCTUnwrap(controller.releaseNotesTextView.textStorage)
        let renderedString = rendered.string as NSString
        let fenceLikeRange = renderedString.range(of: "```example")
        let literalLinkRange = renderedString.range(of: "Literal link")
        let tildeLiteralRange = renderedString.range(of: "**tilde literal**")

        XCTAssertNotEqual(fenceLikeRange.location, NSNotFound)
        XCTAssertNotEqual(tildeLiteralRange.location, NSNotFound)
        XCTAssertNil(rendered.attribute(.link, at: literalLinkRange.location, effectiveRange: nil))
        for range in [fenceLikeRange, literalLinkRange, tildeLiteralRange] {
            let font = try XCTUnwrap(
                rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            )
            XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask))
        }
    }

    @MainActor
    func testUpdateDialogReturnsDownloadResponse() {
        let controller = makeUpdateDialog()
        DispatchQueue.main.async {
            controller.downloadButton.performClick(nil)
        }

        XCTAssertEqual(controller.runModal(), .alertFirstButtonReturn)
    }

    @MainActor
    func testUpdateDialogCloseReturnsLaterResponse() throws {
        let controller = makeUpdateDialog()
        let window = try XCTUnwrap(controller.window)
        DispatchQueue.main.async {
            window.performClose(nil)
        }

        XCTAssertEqual(controller.runModal(), .alertSecondButtonReturn)
    }

    func testUpdateVersionTitleIncludesVersionAndBuildInBothLanguages() {
        XCTAssertEqual(
            PreferencesStrings(language: .zhHans).updateVersionReady("1.4.0", build: 8),
            "XxSnap 1.4.0（8）现已推出"
        )
        XCTAssertEqual(
            PreferencesStrings(language: .english).updateVersionReady("1.4.0", build: 8),
            "XxSnap 1.4.0 (8) is now available"
        )
    }

    @MainActor
    private func makeUpdateDialog(
        releaseNotes: String = "Update notes",
        notice: String? = nil
    ) -> UpdateAvailableWindowController {
        let release = AppUpdateRelease(
            version: "1.4.0",
            buildNumber: 8,
            downloadURL: URL(string: "https://download.xxsofts.com/api/v1/downloads/latest")!,
            sha256: String(repeating: "a", count: 64),
            releaseNotes: releaseNotes
        )
        return UpdateAvailableWindowController(
            release: release,
            title: "发现新版本",
            notice: notice,
            currentVersion: "1.3.0",
            currentBuild: 6,
            strings: PreferencesStrings(language: .zhHans)
        )
    }

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

    func testInstallerReadsDesignatedRequirementFromCodesignStandardOutput() {
        let requirement = "identifier \"com.xxsnap.mac\" and anchor apple generic"
        let standardOutput = Data("designated => \(requirement)\n".utf8)
        let standardError = Data("Executable=/Applications/XxSnap.app/Contents/MacOS/XxSnap\n".utf8)

        XCTAssertEqual(
            SystemAppUpdateInstaller.designatedRequirement(
                standardOutput: standardOutput,
                standardError: standardError
            ),
            requirement
        )
    }

    func testInstallerFallsBackToDesignatedRequirementFromCodesignStandardError() {
        let requirement = "identifier \"com.xxsnap.mac\" and anchor apple generic"
        let standardOutput = Data("Executable=/Applications/XxSnap.app/Contents/MacOS/XxSnap\n".utf8)
        let standardError = Data("designated => \(requirement)\n".utf8)

        XCTAssertEqual(
            SystemAppUpdateInstaller.designatedRequirement(
                standardOutput: standardOutput,
                standardError: standardError
            ),
            requirement
        )
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
