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
    private let sourceEnumerationHook: () -> Void

    init(
        logStore: DiagnosticLogStore,
        appInfo: DiagnosticApplicationInfo = .current(),
        systemInfo: DiagnosticSystemInfo = .current(),
        now: @escaping () -> Date = Date.init,
        nextUUID: @escaping () -> UUID = UUID.init,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        archiver: any DiagnosticArchiveCreating = DittoDiagnosticArchiver(),
        fileManager: FileManager = .default,
        limits: Limits = .standard,
        sourceEnumerationHook: @escaping () -> Void = {}
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
        self.sourceEnumerationHook = sourceEnumerationHook
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
        guard let directoryDescriptor = openSourceDirectory(sourceDirectory) else { return [] }
        defer { Darwin.close(directoryDescriptor) }
        guard let sourceNames = boundedSourceNames(in: directoryDescriptor) else { return [] }
        sourceEnumerationHook()

        var remainingReadBytes = max(0, limits.maximumTotalReadBytes)
        var outputs: [URL] = []
        for sourceName in sourceNames {
            guard remainingReadBytes > 1 else { break }
            guard let contents = readBoundedRegularFile(
                named: sourceName,
                in: directoryDescriptor,
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

    private func openSourceDirectory(_ sourceDirectory: URL) -> Int32? {
        let descriptor = retryingOnInterrupt {
            Darwin.open(
                sourceDirectory.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else { return nil }
        var status = stat()
        guard retryingOnInterrupt({ fstat(descriptor, &status) }) == 0,
              (status.st_mode & S_IFMT) == S_IFDIR
        else {
            Darwin.close(descriptor)
            return nil
        }
        return descriptor
    }

    private func boundedSourceNames(in directoryDescriptor: Int32) -> [String]? {
        let duplicate = retryingOnInterrupt { Darwin.dup(directoryDescriptor) }
        guard duplicate >= 0 else { return nil }
        guard let directory = directoryStream(for: duplicate) else {
            Darwin.close(duplicate)
            return nil
        }
        defer { closedir(directory) }

        let maximumCount = max(0, limits.maximumFileCount)
        guard maximumCount > 0 else { return [] }
        var names: [String] = []
        while true {
            errno = 0
            if let entry = readdir(directory) {
                guard let name = directoryEntryName(entry), isSafeLogFileName(name) else {
                    continue
                }
                names.append(name)
                names.sort()
                if names.count > maximumCount { names.removeLast() }
                continue
            }
            if errno == EINTR { continue }
            guard errno == 0 else { return nil }
            return names
        }
    }

    private func directoryEntryName(_ entry: UnsafeMutablePointer<dirent>) -> String? {
        let length = Int(entry.pointee.d_namlen)
        guard length > 0 else { return nil }
        return withUnsafeBytes(of: &entry.pointee.d_name) { bytes in
            guard length <= bytes.count else { return nil }
            return String(bytes: bytes.prefix(length), encoding: .utf8)
        }
    }

    private func isSafeLogFileName(_ name: String) -> Bool {
        let suffix = ".jsonl"
        guard name.hasSuffix(suffix), name.utf8.count <= 180 else { return false }
        let stem = name.dropLast(suffix.count)
        guard !stem.isEmpty else { return false }
        return stem.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || byte == 45
                || byte == 95
        }
    }

    private func readBoundedRegularFile(
        named sourceName: String,
        in directoryDescriptor: Int32,
        remainingReadBytes: inout Int
    ) -> Data? {
        let descriptor = retryingOnInterrupt {
            sourceName.withCString {
                Darwin.openat(
                    directoryDescriptor,
                    $0,
                    O_RDONLY | O_NOFOLLOW | O_CLOEXEC
                )
            }
        }
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        var status = stat()
        guard retryingOnInterrupt({ fstat(descriptor, &status) }) == 0,
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

    private func directoryStream(for descriptor: Int32) -> UnsafeMutablePointer<DIR>? {
        while true {
            errno = 0
            let directory = fdopendir(descriptor)
            if directory != nil || errno != EINTR { return directory }
        }
    }

    private func retryingOnInterrupt(_ operation: () -> Int32) -> Int32 {
        while true {
            let result = operation()
            if result >= 0 || errno != EINTR { return result }
        }
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
