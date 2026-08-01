import Foundation
import Darwin

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
    struct Limits {
        static let standard = Limits(
            maximumFileCount: 5,
            maximumFileBytes: 5 * 1_024 * 1_024,
            maximumTotalReadBytes: 20 * 1_024 * 1_024
        )

        let maximumFileCount: Int
        let maximumFileBytes: Int
        let maximumTotalReadBytes: Int
    }

    private let logStore: DiagnosticLogStore
    private let appInfo: DiagnosticApplicationInfo
    private let systemInfo: DiagnosticSystemInfo
    private let now: () -> Date
    private let nextUUID: () -> UUID
    private let temporaryDirectory: URL
    private let archiver: any DiagnosticArchiveCreating
    private let fileManager: FileManager
    private let limits: Limits

    init(
        logStore: DiagnosticLogStore,
        appInfo: DiagnosticApplicationInfo = .current(),
        systemInfo: DiagnosticSystemInfo = .current(),
        now: @escaping () -> Date = Date.init,
        nextUUID: @escaping () -> UUID = UUID.init,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        archiver: any DiagnosticArchiveCreating = DittoDiagnosticArchiver(),
        fileManager: FileManager = .default,
        limits: Limits = .standard
    ) {
        self.logStore = logStore
        self.appInfo = appInfo
        self.systemInfo = systemInfo
        self.now = now
        self.nextUUID = nextUUID
        self.temporaryDirectory = temporaryDirectory
        self.archiver = archiver
        self.fileManager = fileManager
        self.limits = limits
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

        let logFiles = try sanitizeLogs(
            from: logStore.directoryURL,
            to: logsDirectory
        )

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

    private func sanitizeLogs(from sourceDirectory: URL, to outputDirectory: URL) throws -> [URL] {
        let root = sourceDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let sourceURLs = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "jsonl" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var remainingReadBytes = max(0, limits.maximumTotalReadBytes)
        var inspectedFileCount = 0
        var outputs: [URL] = []
        for sourceURL in sourceURLs {
            guard inspectedFileCount < max(0, limits.maximumFileCount),
                  remainingReadBytes > 1,
                  isSafeRegularCandidate(sourceURL, within: root)
            else { continue }
            inspectedFileCount += 1
            guard let contents = readBoundedRegularFile(
                sourceURL,
                remainingReadBytes: &remainingReadBytes
            ) else { continue }
            let lines = sanitizedLines(from: contents)
            guard !lines.isEmpty else { continue }
            let destination = outputDirectory.appendingPathComponent(
                String(format: "diagnostic-log-%03d.jsonl", outputs.count + 1)
            )
            var sanitizedContents = Data()
            for line in lines {
                sanitizedContents.append(line)
                sanitizedContents.append(0x0A)
            }
            do {
                try sanitizedContents.write(to: destination, options: .atomic)
                outputs.append(destination)
            } catch {
                try? fileManager.removeItem(at: destination)
            }
        }
        return outputs
    }

    private func isSafeRegularCandidate(_ sourceURL: URL, within root: URL) -> Bool {
        guard let values = try? sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ),
        values.isSymbolicLink != true,
        values.isRegularFile == true
        else { return false }

        let resolved = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return resolved.path.hasPrefix(rootPath)
    }

    private func readBoundedRegularFile(
        _ sourceURL: URL,
        remainingReadBytes: inout Int
    ) -> Data? {
        let descriptor = Darwin.open(sourceURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_nlink == 1,
              status.st_size >= 0,
              let fileSize = Int(exactly: status.st_size)
        else { return nil }

        let contentLimit = min(
            max(0, limits.maximumFileBytes),
            max(0, remainingReadBytes - 1)
        )
        guard fileSize <= contentLimit else { return nil }
        let readLimit = contentLimit + 1
        var data = Data()
        do {
            while data.count < readLimit {
                guard let chunk = try handle.read(upToCount: readLimit - data.count),
                      !chunk.isEmpty
                else { break }
                data.append(chunk)
            }
        } catch {
            remainingReadBytes = max(0, remainingReadBytes - data.count)
            return nil
        }
        remainingReadBytes = max(0, remainingReadBytes - data.count)
        guard data.count == fileSize, data.count <= contentLimit else { return nil }
        return data
    }

    private func sanitizedLines(from contents: Data) -> [Data] {
        guard let string = String(data: contents, encoding: .utf8) else { return [] }
        return string.split(whereSeparator: \.isNewline).compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                  let sanitized = DiagnosticRedactor.sanitizeJSONObject(object),
                  JSONSerialization.isValidJSONObject(sanitized),
                  let data = try? JSONSerialization.data(
                    withJSONObject: sanitized,
                    options: [.sortedKeys]
                  )
            else { return nil }
            return data
        }
    }
}
