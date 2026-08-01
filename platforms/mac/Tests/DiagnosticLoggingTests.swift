import Foundation
import XCTest
@testable import xxsnap

final class DiagnosticLoggingTests: XCTestCase {
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
        let unsafeName = directory.appendingPathComponent("license-person@example.test-token.jsonl")
        try Data(
            """
            not-json
            {"message":"credential abc","nested":{"payload":"secret","items":[{"email":"person@example.test"}],"stable_error_code":"network_unavailable"}}
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
        XCTAssertFalse(text.contains("\"payload\""))
        XCTAssertTrue(text.contains("stable_error_code"))
        for line in text.split(separator: "\n") {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
        }
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
