import Foundation
import Darwin
import XCTest
@testable import xxsnap

final class DiagnosticLoggingTests: XCTestCase {
    func testPaidPolicyIgnoredInFreeReleaseUsesStableDiagnosticCode() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticLogStore(directoryURL: directory)

        store.record(.policyRefresh(
            mode: .paid,
            policyID: "00000000-0000-0000-0000-000000000001",
            expired: false,
            result: .failure,
            error: .paidPolicyIgnoredInFreeRelease
        ))
        store.flush()

        let event = try XCTUnwrap(readEvents(in: directory).first)
        XCTAssertEqual(event.metadata["stable_error_code"], "paid_policy_ignored_in_free_release")
        XCTAssertEqual(event.metadata["policy_mode"], "paid")
        XCTAssertEqual(event.metadata["request_result"], "failure")
    }

    func testCommercialDiagnosticAdapterWritesAndExportsOnlyWhitelistedJSONLFields() throws {
        let directory = try makeTemporaryDirectory()
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        let store = DiagnosticLogStore(directoryURL: directory)
        store.record(.policyRefresh(
            mode: .allFree,
            policyID: "00000000-0000-0000-0000-000000000001",
            expired: true,
            result: .failure,
            error: .policyExpired
        ))
        store.record(.accessStateChanged(accessKind: .free))
        store.record(.accessRequest(
            operation: .validate,
            accessKind: .pro,
            result: .failure,
            error: .network
        ))
        store.record(.accessRequest(
            operation: .trial,
            accessKind: .free,
            result: .failure,
            error: .trialUnavailable
        ))
        store.record(.accessRequest(
            operation: .terminal,
            accessKind: .free,
            result: .success,
            error: .licenseRevoked
        ))
        store.record(.featureIntercept(
            feature: .ocr,
            accessKind: .free,
            result: .blocked
        ))
        store.flush()

        let events = readEvents(in: directory)
        XCTAssertEqual(events.map(\.category), Array(repeating: .commercial, count: 6))
        XCTAssertEqual(events.map(\.event), [
            "commercial_policy_refresh",
            "commercial_access_state_changed",
            "commercial_access_validate",
            "commercial_access_trial",
            "commercial_access_terminal",
            "commercial_feature_intercept",
        ])
        let commercialMetadataWhitelist: Set<String> = [
            "policy_mode", "policy_id", "policy_expired", "access_kind",
            "commercial_feature", "request_result", "stable_error_code",
        ]
        for event in events {
            XCTAssertTrue(
                Set(event.metadata.keys).isSubset(of: commercialMetadataWhitelist),
                "event=\(event.event), keys=\(event.metadata.keys.sorted())"
            )
        }
        XCTAssertEqual(Set(events[0].metadata.keys), [
            "policy_mode", "policy_id", "policy_expired", "request_result",
            "stable_error_code",
        ])
        XCTAssertEqual(events[0].metadata["request_result"], "failure")
        XCTAssertEqual(events[0].metadata["stable_error_code"], "policy_expired")
        XCTAssertEqual(events[1].metadata, ["access_kind": "free"])
        XCTAssertEqual(events[2].metadata, [
            "access_kind": "pro",
            "request_result": "failure",
            "stable_error_code": "network",
        ])
        XCTAssertEqual(events[3].metadata, [
            "access_kind": "free",
            "request_result": "failure",
            "stable_error_code": "trial_unavailable",
        ])
        XCTAssertEqual(events[4].metadata, [
            "access_kind": "free",
            "request_result": "success",
            "stable_error_code": "license_revoked",
        ])
        XCTAssertEqual(events[5].metadata, [
            "commercial_feature": "ocr",
            "access_kind": "free",
            "request_result": "blocked",
        ])
        let raw = try String(contentsOf: XCTUnwrap(logFiles(in: directory).first))
        for forbidden in [
            "email", "activation_code", "device_hash", "payload", "signature",
            "license_id", "credential_id", "raw_error"
        ] {
            XCTAssertFalse(raw.contains(forbidden), forbidden)
        }

        let archiver = RecordingDiagnosticArchiver()
        let exporter = DiagnosticBundleExporter(
            logStore: store,
            temporaryDirectory: stagingParent,
            archiver: archiver
        )
        _ = try exporter.export(to: stagingParent.appendingPathComponent("support.zip"))
        let exported = archiver.logFileContents.values.joined(separator: "\n")
        XCTAssertFalse(DiagnosticRedactor.containsSensitiveData(exported))
        XCTAssertTrue(exported.contains("commercial_policy_refresh"))
        XCTAssertTrue(exported.contains("commercial_feature_intercept"))
        XCTAssertTrue(exported.contains(#""request_result":"blocked""#))
        XCTAssertTrue(exported.contains(#""stable_error_code":"network""#))
    }

    func testCommercialMetadataUsesAllowlistAndRejectsSecretKeyVariants() {
        let metadata = DiagnosticMetadata.sanitized([
            "policy_mode": "all_free",
            "policy_id": "rollout-1",
            "policy_expired": "false",
            "access_kind": "free",
            "commercial_feature": "ocr",
            "request_result": "success",
            "stable_error_code": "network_unavailable",
            "Email": "person@invalid.test",
            "ACTIVATION-CODE": "XXSNAP-ABCD-EFGH-JKLM-NPQR",
            "DeviceHash": String(repeating: "a", count: 64),
            "signedPayload": "payload",
            "SIGNATURE": "signature",
            "licenseId": "license",
            "license_status": "active",
            "Credential_ID": "credential",
            "Authorization": "Bearer header.payload.signature",
            "code": "secret",
            "refreshToken": "token",
        ])

        XCTAssertEqual(
            Set(metadata.keys),
            Set([
                "policy_mode", "policy_id", "policy_expired", "access_kind",
                "commercial_feature", "request_result", "stable_error_code",
            ])
        )
    }

    func testCommercialAllowlistRequiresExactSnakeCaseKeys() {
        let metadata = DiagnosticMetadata.sanitized([
            "policy_mode": "paid",
            "Policy-Mode": "paid",
            "POLICY_MODE": "paid",
            "policyMode": "paid",
            "stable_error_code": "network_unavailable",
            "StableErrorCode": "network_unavailable",
        ])

        XCTAssertEqual(metadata, [
            "policy_mode": "paid",
            "stable_error_code": "network_unavailable",
        ])
    }

    func testRedactorCoversFlexibleSecretAndFieldSeparators() {
        let unsafe = """
        XXSNAP_ab12_cd34_ef56 payload c2VjcmV0 signature=deadbeef \
        license:abc credential xyz person@example.test Bearer abc.def.ghi \
        abc.def.ghi aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        """
        let sanitized = DiagnosticRedactor.redact(unsafe)

        XCTAssertFalse(DiagnosticRedactor.containsSensitiveData(sanitized))
        XCTAssertFalse(sanitized.contains("person@example.test"))
        XCTAssertFalse(sanitized.contains("c2VjcmV0"))
        XCTAssertFalse(sanitized.contains("deadbeef"))
    }

    func testRedactorRemovesEveryNonemptyXXSNAPDashTokenButKeepsBrandName() {
        let cases = [
            ("XXSNAP-secret", "[REDACTED]"),
            ("XXSNAP-ABCD", "[REDACTED]"),
            ("xxsnap-z", "[REDACTED]"),
            ("prefixXXSNAP-ABCD", "prefix[REDACTED]"),
            ("activation_XXSNAP-ABCD", "activation_[REDACTED]"),
            (#""XXSNAP-ABCD""#, #""[REDACTED]""#),
            (#"{"value":"XXSNAP-secret"}"#, #"{"value":"[REDACTED]"}"#),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(DiagnosticRedactor.redact(input), expected, input)
        }
        XCTAssertEqual(DiagnosticRedactor.redact("XxSnap"), "XxSnap")
        XCTAssertEqual(DiagnosticRedactor.redact("Use XxSnap for capture"), "Use XxSnap for capture")
    }

    func testRecursiveJSONSanitizerDropsSensitiveKeyNamesWithoutDroppingOperationalKeys() throws {
        let sensitiveKeys = [
            "person@example.test",
            "prefixXXSNAP-ABCD",
            "Bearer abc.def.ghi",
            "abc.def.ghi",
            String(repeating: "a", count: 64),
            "license_id",
            "credential",
            "signed_payload",
            "signature",
        ]
        var nested: [String: Any] = [
            "stable_error_code": "network_unavailable",
            "duration_ms": 42,
        ]
        for key in sensitiveKeys { nested[key] = "must-not-export" }

        let sanitized = try XCTUnwrap(
            DiagnosticRedactor.sanitizeJSONObject([
                "policy_mode": "all_free",
                "operation": "diagnostic_export",
                "nested": nested,
            ]) as? [String: Any]
        )
        let sanitizedNested = try XCTUnwrap(sanitized["nested"] as? [String: Any])

        XCTAssertEqual(Set(sanitized.keys), ["policy_mode", "operation", "nested"])
        XCTAssertEqual(Set(sanitizedNested.keys), ["stable_error_code", "duration_ms"])
    }

    func testShortXXSNAPSecretUsesSameSanitizedEventAndJSONLValue() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var osLogMessages: [String] = []
        let store = DiagnosticLogStore(
            directoryURL: directory,
            osLogSink: { _, message in osLogMessages.append(message) }
        )

        store.record(
            category: .application,
            level: .info,
            event: "activation_XXSNAP-ABCD",
            metadata: ["request_result": "XXSNAP-secret"]
        )
        store.flush()

        let event = try XCTUnwrap(readEvents(in: directory).first)
        XCTAssertEqual(event.event, "activation__redacted_")
        XCTAssertFalse(event.event.lowercased().contains("xxsnap"))
        XCTAssertFalse(event.event.lowercased().contains("abcd"))
        XCTAssertEqual(event.metadata["request_result"], "[REDACTED]")
        XCTAssertEqual(osLogMessages, ["application activation__redacted_"])
        XCTAssertFalse(osLogMessages.joined().lowercased().contains("xxsnap"))
        XCTAssertFalse(osLogMessages.joined().lowercased().contains("abcd"))
        XCTAssertFalse(osLogMessages.joined().lowercased().contains("secret"))
        let raw = try String(contentsOf: XCTUnwrap(logFiles(in: directory).first))
        XCTAssertFalse(raw.lowercased().contains("xxsnap"))
        XCTAssertFalse(raw.lowercased().contains("abcd"))
        XCTAssertFalse(raw.lowercased().contains("secret"))
    }

    func testMetadataValuesAndEventMessagesAreRedactedWithoutBreakingSafeDiagnostics() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticLogStore(directoryURL: directory)
        let unsafeValues = [
            "person@invalid.test",
            "XXSNAP-ABCD-EFGH-JKLM-NPQR",
            "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.deadbeef",
            String(repeating: "a", count: 64),
            #"{"signed_payload":"c2VjcmV0","signature":"c2ln"}"#,
        ].joined(separator: " | ")

        store.record(
            category: .application,
            level: .warning,
            event: "server_message_\(unsafeValues)",
            metadata: [
                "direction": "down",
                "policy_mode": "all_free",
                "request_result": unsafeValues,
            ]
        )
        store.flush()

        let logURL = try XCTUnwrap(logFiles(in: directory).first)
        let raw = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertFalse(DiagnosticRedactor.containsSensitiveData(raw))
        let event = try XCTUnwrap(readEvents(in: directory).first)
        XCTAssertEqual(event.metadata["direction"], "down")
        XCTAssertEqual(event.metadata["policy_mode"], "all_free")
        XCTAssertTrue(event.metadata["request_result"]?.contains("[REDACTED]") == true)
    }

    func testExporterRedactsHistoricalLogContentsAsFinalDefense() throws {
        let directory = try makeTemporaryDirectory()
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        let historical = directory.appendingPathComponent("third-party.jsonl")
        try Data(
            """
            {"message":"person@invalid.test Bearer eyJ.aWQ.sig","metadata":{"policy_mode":"all_free","stable_error_code":"network_unavailable","activation_code":"XXSNAP-ABCD-EFGH-JKLM-NPQR","device_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}
            """.utf8
        ).write(to: historical)
        let archiver = RecordingDiagnosticArchiver()
        let exporter = DiagnosticBundleExporter(
            logStore: DiagnosticLogStore(directoryURL: directory),
            temporaryDirectory: stagingParent,
            archiver: archiver
        )

        _ = try exporter.export(to: stagingParent.appendingPathComponent("support.zip"))

        let exportedText = archiver.logFileContents.values.joined(separator: "\n")
        XCTAssertFalse(DiagnosticRedactor.containsSensitiveData(exportedText))
        XCTAssertTrue(exportedText.contains("policy_mode"))
        XCTAssertTrue(exportedText.contains("all_free"))
        XCTAssertTrue(exportedText.contains("network_unavailable"))
        for line in exportedText.split(separator: "\n") {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
        }
    }

    func testExporterDropsInvalidLinesRecursivelySanitizesAndAlwaysUsesSafeNames() throws {
        let directory = try makeTemporaryDirectory()
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        let unsafeName = directory.appendingPathComponent("historical-input.jsonl")
        try Data(
            """
            not-json
            {"message":"credential abc XXSNAP-ABCD","nested":{"payload":"secret","items":[{"email":"person@example.test"}],"stable_error_code":"network_unavailable"}}
            """.utf8
        ).write(to: unsafeName)
        let archiver = RecordingDiagnosticArchiver()
        let exporter = DiagnosticBundleExporter(
            logStore: DiagnosticLogStore(directoryURL: directory),
            temporaryDirectory: stagingParent,
            archiver: archiver
        )

        _ = try exporter.export(to: stagingParent.appendingPathComponent("support.zip"))

        XCTAssertEqual(archiver.manifest?.logFileCount, archiver.logFileNames.count)
        XCTAssertTrue(archiver.logFileNames.allSatisfy {
            $0.range(of: #"^diagnostic-log-[0-9]{3}\.jsonl$"#, options: .regularExpression) != nil
        })
        XCTAssertFalse(archiver.logFileNames.joined().contains("@"))
        let text = archiver.logFileContents.values.joined(separator: "\n")
        XCTAssertFalse(text.contains("not-json"))
        XCTAssertFalse(text.contains("person@example.test"))
        XCTAssertFalse(text.contains("XXSNAP-ABCD"))
        XCTAssertFalse(text.contains("\"payload\""))
        XCTAssertTrue(text.contains("stable_error_code"))
        for line in text.split(separator: "\n") {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
        }
    }

    func testExporterRejectsSymlinksHardLinksAndNonRegularEntriesBeforeReading() throws {
        let directory = try makeTemporaryDirectory()
        let outside = try makeTemporaryDirectory()
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outside)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        let outsideLog = outside.appendingPathComponent("outside.jsonl")
        try Data(#"{"marker":"LEAK_OUTSIDE_SECRET"}"#.utf8).write(to: outsideLog)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("a-symlink.jsonl"),
            withDestinationURL: outsideLog
        )
        try FileManager.default.linkItem(
            at: outsideLog,
            to: directory.appendingPathComponent("b-hard-link.jsonl")
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("c-directory.jsonl"),
            withIntermediateDirectories: false
        )
        try Data(#"{"marker":"SAFE_LOCAL"}"#.utf8).write(
            to: directory.appendingPathComponent("d-regular.jsonl")
        )
        let archiver = RecordingDiagnosticArchiver()
        let exporter = DiagnosticBundleExporter(
            logStore: DiagnosticLogStore(directoryURL: directory),
            temporaryDirectory: stagingParent,
            archiver: archiver,
            limits: .init(
                maximumFileCount: 10,
                maximumFileBytes: 1_024,
                maximumTotalReadBytes: 4_096
            )
        )

        _ = try exporter.export(to: stagingParent.appendingPathComponent("support.zip"))

        let text = archiver.logFileContents.values.joined(separator: "\n")
        XCTAssertTrue(text.contains("SAFE_LOCAL"))
        XCTAssertFalse(text.contains("LEAK_OUTSIDE_SECRET"))
        XCTAssertEqual(archiver.manifest?.logFileCount, archiver.logFileNames.count)
        XCTAssertTrue(archiver.logFileNames.allSatisfy {
            $0.range(of: #"^diagnostic-log-[0-9]{3}\.jsonl$"#, options: .regularExpression) != nil
        })
    }

    func testExporterRejectsSourceDirectorySymlinkWithoutFollowingIt() throws {
        let parent = try makeTemporaryDirectory()
        let realLogs = parent.appendingPathComponent("real-logs", isDirectory: true)
        let linkedLogs = parent.appendingPathComponent("linked-logs", isDirectory: true)
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: parent)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        try FileManager.default.createDirectory(at: realLogs, withIntermediateDirectories: false)
        try Data(#"{"marker":"LEAK_ROOT_SYMLINK"}"#.utf8).write(
            to: realLogs.appendingPathComponent("outside.jsonl")
        )
        try FileManager.default.createSymbolicLink(at: linkedLogs, withDestinationURL: realLogs)
        let archiver = RecordingDiagnosticArchiver()
        let exporter = DiagnosticBundleExporter(
            logStore: DiagnosticLogStore(directoryURL: linkedLogs),
            temporaryDirectory: stagingParent,
            archiver: archiver
        )

        _ = try exporter.export(to: stagingParent.appendingPathComponent("support.zip"))

        XCTAssertEqual(archiver.manifest?.logFileCount, 0)
        XCTAssertTrue(archiver.logFileContents.isEmpty)
    }

    func testExporterKeepsUsingOpenedDirectoryWhenSourcePathIsRenamedAndReplacedBySymlink() throws {
        let parent = try makeTemporaryDirectory()
        let source = parent.appendingPathComponent("logs", isDirectory: true)
        let movedSource = parent.appendingPathComponent("moved-logs", isDirectory: true)
        let replacement = parent.appendingPathComponent("replacement", isDirectory: true)
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: parent)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: false)
        try Data(#"{"marker":"SAFE_FIXED_DIRECTORY"}"#.utf8).write(
            to: source.appendingPathComponent("capture.jsonl")
        )
        try Data(#"{"marker":"LEAK_REPLACEMENT_SYMLINK"}"#.utf8).write(
            to: replacement.appendingPathComponent("capture.jsonl")
        )
        let archiver = RecordingDiagnosticArchiver()
        var mutationError: Error?
        let exporter = DiagnosticBundleExporter(
            logStore: DiagnosticLogStore(directoryURL: source),
            temporaryDirectory: stagingParent,
            archiver: archiver,
            sourceEnumerationHook: {
                do {
                    try FileManager.default.moveItem(at: source, to: movedSource)
                    try FileManager.default.createSymbolicLink(
                        at: source,
                        withDestinationURL: replacement
                    )
                } catch {
                    mutationError = error
                }
            }
        )

        _ = try exporter.export(to: stagingParent.appendingPathComponent("support.zip"))

        XCTAssertNil(mutationError)
        let text = archiver.logFileContents.values.joined(separator: "\n")
        XCTAssertTrue(text.contains("SAFE_FIXED_DIRECTORY"))
        XCTAssertFalse(text.contains("LEAK_REPLACEMENT_SYMLINK"))
    }

    func testExporterSafelySkipsChildReplacedBySymlinkAfterEnumeration() throws {
        let directory = try makeTemporaryDirectory()
        let outside = try makeTemporaryDirectory()
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outside)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        let candidate = directory.appendingPathComponent("capture.jsonl")
        let movedCandidate = directory.appendingPathComponent("moved-after-enumeration.jsonl")
        let outsideLog = outside.appendingPathComponent("outside.jsonl")
        try Data(#"{"marker":"SAFE_ORIGINAL_CHILD"}"#.utf8).write(to: candidate)
        try Data(#"{"marker":"LEAK_CHILD_SYMLINK"}"#.utf8).write(to: outsideLog)
        let archiver = RecordingDiagnosticArchiver()
        var mutationError: Error?
        let exporter = DiagnosticBundleExporter(
            logStore: DiagnosticLogStore(directoryURL: directory),
            temporaryDirectory: stagingParent,
            archiver: archiver,
            sourceEnumerationHook: {
                do {
                    try FileManager.default.moveItem(at: candidate, to: movedCandidate)
                    try FileManager.default.createSymbolicLink(
                        at: candidate,
                        withDestinationURL: outsideLog
                    )
                } catch {
                    mutationError = error
                }
            }
        )

        _ = try exporter.export(to: stagingParent.appendingPathComponent("support.zip"))

        XCTAssertNil(mutationError)
        let text = archiver.logFileContents.values.joined(separator: "\n")
        XCTAssertFalse(text.contains("LEAK_CHILD_SYMLINK"))
        XCTAssertFalse(text.contains("SAFE_ORIGINAL_CHILD"))
    }

    func testExporterRejectsSubdirectoriesAndUnusualSourceNames() throws {
        let directory = try makeTemporaryDirectory()
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        try Data(#"{"marker":"SAFE_NAME"}"#.utf8).write(
            to: directory.appendingPathComponent("safe-input.jsonl")
        )
        for (name, marker) in [
            ("unsafe@name.jsonl", "LEAK_AT_NAME"),
            ("line\nbreak.jsonl", "LEAK_CONTROL_NAME"),
            ("unicode-秘密.jsonl", "LEAK_UNICODE_NAME"),
        ] {
            try Data("{\"marker\":\"\(marker)\"}".utf8).write(
                to: directory.appendingPathComponent(name)
            )
        }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("nested.jsonl"),
            withIntermediateDirectories: false
        )
        let archiver = RecordingDiagnosticArchiver()
        let exporter = DiagnosticBundleExporter(
            logStore: DiagnosticLogStore(
                directoryURL: directory,
                configuration: .init(
                    maximumFileSize: 5 * 1_024 * 1_024,
                    maximumFileCount: 20,
                    retentionInterval: 7 * 24 * 60 * 60
                )
            ),
            temporaryDirectory: stagingParent,
            archiver: archiver,
            limits: .init(
                maximumFileCount: 20,
                maximumFileBytes: 1_024,
                maximumTotalReadBytes: 20 * 1_024
            )
        )

        _ = try exporter.export(to: stagingParent.appendingPathComponent("support.zip"))

        let text = archiver.logFileContents.values.joined(separator: "\n")
        XCTAssertTrue(text.contains("SAFE_NAME"))
        XCTAssertFalse(text.contains("LEAK_AT_NAME"))
        XCTAssertFalse(text.contains("LEAK_CONTROL_NAME"))
        XCTAssertFalse(text.contains("LEAK_UNICODE_NAME"))
    }

    func testExporterClosesDirectoryEnumerationAndFileDescriptorsAcrossRepeatedExports() throws {
        let directory = try makeTemporaryDirectory()
        let outside = try makeTemporaryDirectory()
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outside)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        try Data(#"{"marker":"SAFE_DESCRIPTOR_TEST"}"#.utf8).write(
            to: directory.appendingPathComponent("regular.jsonl")
        )
        let hardLinkTarget = outside.appendingPathComponent("hard-link-target.jsonl")
        try Data(#"{"marker":"REJECT_HARD_LINK"}"#.utf8).write(to: hardLinkTarget)
        try FileManager.default.linkItem(
            at: hardLinkTarget,
            to: directory.appendingPathComponent("hard-link.jsonl")
        )
        let store = DiagnosticLogStore(
            directoryURL: directory,
            configuration: .init(
                maximumFileSize: 5 * 1_024 * 1_024,
                maximumFileCount: 20,
                retentionInterval: 7 * 24 * 60 * 60
            )
        )
        let baseline = openFileDescriptorCount()

        for index in 0..<20 {
            let exporter = DiagnosticBundleExporter(
                logStore: store,
                temporaryDirectory: stagingParent,
                archiver: RecordingDiagnosticArchiver()
            )
            _ = try exporter.export(
                to: stagingParent.appendingPathComponent("support-\(index).zip")
            )
        }

        XCTAssertLessThanOrEqual(openFileDescriptorCount(), baseline + 3)
    }

    func testExporterSkipsFileLargerThanPerFileBudgetWithoutReadingSecretIntoBundle() throws {
        let directory = try makeTemporaryDirectory()
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        try Data(
            (#"{"marker":"LEAK_OVERSIZED_SECRET","padding":""#
                + String(repeating: "x", count: 128) + #""}"#).utf8
        ).write(to: directory.appendingPathComponent("a-oversized.jsonl"))
        try Data(#"{"marker":"SAFE_SMALL"}"#.utf8).write(
            to: directory.appendingPathComponent("b-small.jsonl")
        )
        let archiver = RecordingDiagnosticArchiver()
        let exporter = DiagnosticBundleExporter(
            logStore: DiagnosticLogStore(directoryURL: directory),
            temporaryDirectory: stagingParent,
            archiver: archiver,
            limits: .init(
                maximumFileCount: 10,
                maximumFileBytes: 64,
                maximumTotalReadBytes: 1_024
            )
        )

        _ = try exporter.export(to: stagingParent.appendingPathComponent("support.zip"))

        let text = archiver.logFileContents.values.joined(separator: "\n")
        XCTAssertEqual(archiver.manifest?.logFileCount, 1)
        XCTAssertTrue(text.contains("SAFE_SMALL"))
        XCTAssertFalse(text.contains("LEAK_OVERSIZED_SECRET"))
    }

    func testExporterLimitsSourceFileCountAndKeepsManifestAtActualOutputCount() throws {
        let directory = try makeTemporaryDirectory()
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        for (name, marker) in [("a", "FIRST"), ("b", "SECOND"), ("c", "EXCLUDED_SECRET")] {
            try Data("{\"marker\":\"\(marker)\"}".utf8).write(
                to: directory.appendingPathComponent("\(name).jsonl")
            )
        }
        let archiver = RecordingDiagnosticArchiver()
        let exporter = DiagnosticBundleExporter(
            logStore: DiagnosticLogStore(directoryURL: directory),
            temporaryDirectory: stagingParent,
            archiver: archiver,
            limits: .init(
                maximumFileCount: 2,
                maximumFileBytes: 512,
                maximumTotalReadBytes: 4_096
            )
        )

        _ = try exporter.export(to: stagingParent.appendingPathComponent("support.zip"))

        let text = archiver.logFileContents.values.joined(separator: "\n")
        XCTAssertEqual(archiver.manifest?.logFileCount, 2)
        XCTAssertEqual(archiver.logFileNames, ["diagnostic-log-001.jsonl", "diagnostic-log-002.jsonl"])
        XCTAssertTrue(text.contains("FIRST"))
        XCTAssertTrue(text.contains("SECOND"))
        XCTAssertFalse(text.contains("EXCLUDED_SECRET"))
    }

    func testExporterStopsAtTotalReadBudgetAndDoesNotIncludeLaterSecret() throws {
        let directory = try makeTemporaryDirectory()
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        let first = Data(#"{"marker":"FIRST_WITH_PADDING_123456"}"#.utf8)
        let second = Data(#"{"marker":"LEAK_TOTAL_SECRET_123456"}"#.utf8)
        try first.write(to: directory.appendingPathComponent("a.jsonl"))
        try second.write(to: directory.appendingPathComponent("b.jsonl"))
        let archiver = RecordingDiagnosticArchiver()
        let exporter = DiagnosticBundleExporter(
            logStore: DiagnosticLogStore(directoryURL: directory),
            temporaryDirectory: stagingParent,
            archiver: archiver,
            limits: .init(
                maximumFileCount: 10,
                maximumFileBytes: 512,
                maximumTotalReadBytes: first.count + 4
            )
        )

        _ = try exporter.export(to: stagingParent.appendingPathComponent("support.zip"))

        let text = archiver.logFileContents.values.joined(separator: "\n")
        XCTAssertEqual(archiver.manifest?.logFileCount, 1)
        XCTAssertTrue(text.contains("FIRST_WITH_PADDING_123456"))
        XCTAssertFalse(text.contains("LEAK_TOTAL_SECRET_123456"))
    }

    func testStoreWritesJSONLineAndRejectsSensitiveMetadata() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = DiagnosticLogStore(
            directoryURL: directory,
            configuration: .init(),
            now: { now }
        )

        store.record(
            category: .scrollCapture,
            level: .info,
            event: "step_completed",
            metadata: [
                "direction": "down",
                "confidence": "0.98",
                "url": "https://private.example",
                "ocrText": "private words",
                "filePath": "/Users/example/private.png",
            ]
        )
        store.flush()

        let event = try XCTUnwrap(readEvents(in: directory).first)
        XCTAssertEqual(event.category, .scrollCapture)
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.event, "step_completed")
        XCTAssertEqual(event.metadata["direction"], "down")
        XCTAssertEqual(event.metadata["confidence"], "0.98")
        XCTAssertNil(event.metadata["url"])
        XCTAssertNil(event.metadata["ocrText"])
        XCTAssertNil(event.metadata["filePath"])
        XCTAssertEqual(event.timestamp, now)
    }

    func testStoreRotatesAndBoundsLogFileCount() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var nextUUIDValue = 0
        let store = DiagnosticLogStore(
            directoryURL: directory,
            configuration: .init(
                maximumFileSize: 320,
                maximumFileCount: 2,
                retentionInterval: TimeInterval(7 * 24 * 60 * 60)
            ),
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            nextUUID: {
                nextUUIDValue += 1
                return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", nextUUIDValue))!
            }
        )

        for index in 0..<12 {
            store.record(
                category: .application,
                level: .info,
                event: "rotation_probe",
                metadata: ["sequence": "\(index)", "padding": String(repeating: "x", count: 80)]
            )
        }
        store.flush()

        let files = try logFiles(in: directory)
        XCTAssertEqual(files.count, 2)
        XCTAssertGreaterThan(readEvents(in: directory).count, 0)
    }

    func testStoreRemovesFilesOutsideRetentionWindow() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expired = directory.appendingPathComponent("xxsnap-expired.jsonl")
        try Data("expired\n".utf8).write(to: expired)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-(8 * 24 * 60 * 60))],
            ofItemAtPath: expired.path
        )
        let store = DiagnosticLogStore(
            directoryURL: directory,
            configuration: .init(
                retentionInterval: TimeInterval(7 * 24 * 60 * 60)
            ),
            now: { now }
        )

        store.performMaintenance()
        store.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
    }

    func testEveryScrollCaptureSessionIncludesDetailedDiagnostics() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticLogStore(directoryURL: directory)

        let firstSession = store.beginScrollCaptureSession()
        XCTAssertTrue(firstSession.isDetailed)
        store.endScrollCaptureSession(firstSession)

        let secondSession = store.beginScrollCaptureSession()
        XCTAssertTrue(secondSession.isDetailed)
        store.endScrollCaptureSession(secondSession)
    }

    func testDetailedEventsAreWrittenForEveryScrollCaptureSession() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticLogStore(directoryURL: directory)

        let firstSession = store.beginScrollCaptureSession()
        store.record(
            category: .scrollCapture,
            level: .debug,
            event: "first_session_detail",
            detail: .detailed
        )
        store.endScrollCaptureSession(firstSession)
        let secondSession = store.beginScrollCaptureSession()
        store.record(
            category: .scrollCapture,
            level: .debug,
            event: "second_session_detail",
            detail: .detailed
        )
        store.endScrollCaptureSession(secondSession)
        store.flush()

        XCTAssertEqual(
            readEvents(in: directory).map(\.event),
            ["first_session_detail", "second_session_detail"]
        )
    }

    @MainActor
    func testCaptureCoordinatorRecordsRequestsForEveryPrimaryFeature() {
        let logger = RecordingFeatureDiagnosticLogger()
        let coordinator = CaptureCoordinator(
            permissionCoordinator: SilentDeniedPermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            diagnosticLogger: logger
        )

        coordinator.startCapture()
        coordinator.startFullScreenCapture()
        coordinator.startTextRecognition()
        coordinator.toggleTeachingPen()

        XCTAssertTrue(logger.events.contains {
            $0.category == .capture && $0.event == "region_capture_requested"
        })
        XCTAssertTrue(logger.events.contains {
            $0.category == .capture && $0.event == "full_screen_capture_requested"
        })
        XCTAssertTrue(logger.events.contains {
            $0.category == .textRecognition && $0.event == "text_recognition_requested"
        })
        XCTAssertTrue(logger.events.contains {
            $0.category == .teachingPen && $0.event == "teaching_pen_requested"
        })
    }

    func testExporterCreatesManifestAndArchiveThenRemovesStagingDirectory() throws {
        let directory = try makeTemporaryDirectory()
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        let store = DiagnosticLogStore(directoryURL: directory)
        store.record(category: .application, level: .info, event: "app_started")
        store.flush()
        let archiver = RecordingDiagnosticArchiver()
        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let exporter = DiagnosticBundleExporter(
            logStore: store,
            appInfo: .init(version: "1.2.3", build: "45"),
            systemInfo: .init(macOSVersion: "macOS Test", architecture: "arm64"),
            now: { generatedAt },
            nextUUID: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
            temporaryDirectory: stagingParent,
            archiver: archiver
        )
        let destination = stagingParent.appendingPathComponent("support.zip")

        let result = try exporter.export(to: destination)

        XCTAssertEqual(result, destination)
        XCTAssertEqual(try Data(contentsOf: destination), Data("archive".utf8))
        let manifest = try XCTUnwrap(archiver.manifest)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.generatedAt, generatedAt)
        XCTAssertEqual(manifest.appVersion, "1.2.3")
        XCTAssertEqual(manifest.appBuild, "45")
        XCTAssertEqual(manifest.macOSVersion, "macOS Test")
        XCTAssertEqual(manifest.architecture, "arm64")
        XCTAssertEqual(manifest.logFileCount, 1)
        XCTAssertEqual(archiver.logFileNames, ["diagnostic-log-001.jsonl"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: stagingParent
                    .appendingPathComponent("xxsnap-diagnostics-00000000-0000-0000-0000-000000000001")
                    .path
            )
        )
    }

    func testExporterRemovesStagingDirectoryWhenArchiveCreationFails() throws {
        let directory = try makeTemporaryDirectory()
        let stagingParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: stagingParent)
        }
        let store = DiagnosticLogStore(directoryURL: directory)
        let archiver = RecordingDiagnosticArchiver(error: DiagnosticTestError.failed)
        let stagingUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let exporter = DiagnosticBundleExporter(
            logStore: store,
            appInfo: .init(version: "1", build: "1"),
            systemInfo: .init(macOSVersion: "macOS Test", architecture: "arm64"),
            nextUUID: { stagingUUID },
            temporaryDirectory: stagingParent,
            archiver: archiver
        )

        XCTAssertThrowsError(
            try exporter.export(to: stagingParent.appendingPathComponent("failed.zip"))
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: stagingParent
                    .appendingPathComponent("xxsnap-diagnostics-\(stagingUUID.uuidString.lowercased())")
                    .path
            )
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("xxsnap-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func logFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "jsonl" }
    }

    private func readEvents(in directory: URL) -> [DiagnosticLogEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? logFiles(in: directory))?
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { url -> [DiagnosticLogEvent] in
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    return []
                }
                return contents
                    .split(separator: "\n")
                    .compactMap { try? decoder.decode(DiagnosticLogEvent.self, from: Data($0.utf8)) }
            } ?? []
    }

    private func openFileDescriptorCount() -> Int {
        (0..<Int(getdtablesize())).reduce(into: 0) { count, descriptor in
            if fcntl(Int32(descriptor), F_GETFD) >= 0 { count += 1 }
        }
    }
}

private final class SilentDeniedPermissionCoordinator: ScreenCapturePermissionCoordinating {
    func hasScreenCapturePermission() -> Bool { false }
    func shouldShowScreenCaptureGuidance() -> Bool { false }
    func requestScreenCapturePermissionOnce() -> Bool { false }
}

private final class RecordingFeatureDiagnosticLogger: DiagnosticLogging {
    struct Event {
        let category: DiagnosticLogCategory
        let event: String
    }

    private(set) var events: [Event] = []

    func record(
        category: DiagnosticLogCategory,
        level: DiagnosticLogLevel,
        event: String,
        metadata: [String: String],
        detail: DiagnosticLogDetail
    ) {
        events.append(Event(category: category, event: event))
    }

    func beginScrollCaptureSession() -> DiagnosticCaptureSession {
        DiagnosticCaptureSession(id: UUID(), startedAt: Date(), isDetailed: true)
    }

    func endScrollCaptureSession(_ session: DiagnosticCaptureSession) {}
}

private enum DiagnosticTestError: Error {
    case failed
}

private final class RecordingDiagnosticArchiver: DiagnosticArchiveCreating {
    private let error: Error?
    private(set) var manifest: DiagnosticBundleManifest?
    private(set) var logFileNames: [String] = []
    private(set) var logFileContents: [String: String] = [:]

    init(error: Error? = nil) {
        self.error = error
    }

    func createArchive(from sourceDirectory: URL, at destinationURL: URL) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        manifest = try decoder.decode(
            DiagnosticBundleManifest.self,
            from: Data(contentsOf: sourceDirectory.appendingPathComponent("manifest.json"))
        )
        logFileNames = try FileManager.default.contentsOfDirectory(
            at: sourceDirectory.appendingPathComponent("logs"),
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .sorted()
        logFileContents = try Dictionary(uniqueKeysWithValues: logFileNames.map { name in
            let url = sourceDirectory.appendingPathComponent("logs").appendingPathComponent(name)
            return (name, try String(contentsOf: url, encoding: .utf8))
        })
        if let error {
            throw error
        }
        try Data("archive".utf8).write(to: destinationURL)
    }
}
