import Foundation

struct DiagnosticApplicationInfo: Equatable {
    let version: String
    let build: String

    static func current(bundle: Bundle = .main) -> DiagnosticApplicationInfo {
        DiagnosticApplicationInfo(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "0.0.0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                ?? "0"
        )
    }
}

struct DiagnosticSystemInfo: Equatable {
    let macOSVersion: String
    let architecture: String

    static func current(processInfo: ProcessInfo = .processInfo) -> DiagnosticSystemInfo {
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        return DiagnosticSystemInfo(
            macOSVersion: processInfo.operatingSystemVersionString,
            architecture: architecture
        )
    }
}

struct DiagnosticBundleManifest: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let appVersion: String
    let appBuild: String
    let macOSVersion: String
    let architecture: String
    let logFileCount: Int
}

protocol DiagnosticArchiveCreating {
    func createArchive(from sourceDirectory: URL, at destinationURL: URL) throws
}

enum DiagnosticBundleExportError: LocalizedError {
    case archiveFailed(Int32)

    var errorDescription: String? {
        switch self {
        case let .archiveFailed(status):
            return "Unable to create the diagnostic archive (status \(status))."
        }
    }
}

struct DittoDiagnosticArchiver: DiagnosticArchiveCreating {
    func createArchive(from sourceDirectory: URL, at destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            sourceDirectory.path,
            destinationURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DiagnosticBundleExportError.archiveFailed(process.terminationStatus)
        }
    }
}

final class DiagnosticBundleExporter {
    private let logStore: DiagnosticLogStore
    private let appInfo: DiagnosticApplicationInfo
    private let systemInfo: DiagnosticSystemInfo
    private let now: () -> Date
    private let nextUUID: () -> UUID
    private let temporaryDirectory: URL
    private let archiver: any DiagnosticArchiveCreating
    private let fileManager: FileManager

    init(
        logStore: DiagnosticLogStore,
        appInfo: DiagnosticApplicationInfo = .current(),
        systemInfo: DiagnosticSystemInfo = .current(),
        now: @escaping () -> Date = Date.init,
        nextUUID: @escaping () -> UUID = UUID.init,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        archiver: any DiagnosticArchiveCreating = DittoDiagnosticArchiver(),
        fileManager: FileManager = .default
    ) {
        self.logStore = logStore
        self.appInfo = appInfo
        self.systemInfo = systemInfo
        self.now = now
        self.nextUUID = nextUUID
        self.temporaryDirectory = temporaryDirectory
        self.archiver = archiver
        self.fileManager = fileManager
    }

    @discardableResult
    func export(to destinationURL: URL) throws -> URL {
        logStore.record(
            category: .export,
            level: .info,
            event: "diagnostic_export_started"
        )
        logStore.flush()
        let stagingID = nextUUID().uuidString.lowercased()
        let stagingDirectory = temporaryDirectory.appendingPathComponent(
            "xxsnap-diagnostics-\(stagingID)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }
        let logsDirectory = stagingDirectory.appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )

        let logFiles = try logStore.copyLogFiles(to: logsDirectory)
        try redactExportedLogs(logFiles)

        let manifest = DiagnosticBundleManifest(
            schemaVersion: 1,
            generatedAt: now(),
            appVersion: appInfo.version,
            appBuild: appInfo.build,
            macOSVersion: systemInfo.macOSVersion,
            architecture: systemInfo.architecture,
            logFileCount: logFiles.count
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: stagingDirectory.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        try archiver.createArchive(from: stagingDirectory, at: destinationURL)
        return destinationURL
    }

    private func redactExportedLogs(_ logFiles: [URL]) throws {
        for (index, sourceURL) in logFiles.enumerated() {
            guard let contents = try? String(contentsOf: sourceURL, encoding: .utf8) else {
                try? fileManager.removeItem(at: sourceURL)
                continue
            }
            let redacted = DiagnosticRedactor.redact(contents)
            try Data(redacted.utf8).write(to: sourceURL, options: .atomic)

            guard DiagnosticRedactor.containsSensitiveData(sourceURL.lastPathComponent) else {
                continue
            }
            let safeURL = sourceURL.deletingLastPathComponent().appendingPathComponent(
                "xxsnap-export-\(index + 1).jsonl"
            )
            if fileManager.fileExists(atPath: safeURL.path) {
                try fileManager.removeItem(at: safeURL)
            }
            try fileManager.moveItem(at: sourceURL, to: safeURL)
        }
    }
}
