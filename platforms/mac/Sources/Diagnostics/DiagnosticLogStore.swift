import Foundation
import OSLog

enum DiagnosticLogCategory: String, Codable {
    case application
    case capture
    case scrollCapture = "scroll_capture"
    case textRecognition = "text_recognition"
    case teachingPen = "teaching_pen"
    case pin
    case export
}

enum DiagnosticLogLevel: String, Codable {
    case debug
    case info
    case warning
    case error

    fileprivate var osLogType: OSLogType {
        switch self {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        }
    }
}

enum DiagnosticLogDetail {
    case standard
    case detailed
}

struct DiagnosticCaptureSession: Equatable {
    let id: UUID
    let startedAt: Date
    let isDetailed: Bool
}

struct DiagnosticLogEvent: Codable, Equatable {
    let schemaVersion: Int
    let timestamp: Date
    let category: DiagnosticLogCategory
    let level: DiagnosticLogLevel
    let event: String
    let sessionID: UUID?
    let metadata: [String: String]
}

protocol DiagnosticLogging: AnyObject {
    func record(
        category: DiagnosticLogCategory,
        level: DiagnosticLogLevel,
        event: String,
        metadata: [String: String],
        detail: DiagnosticLogDetail
    )
    func beginScrollCaptureSession() -> DiagnosticCaptureSession
    func endScrollCaptureSession(_ session: DiagnosticCaptureSession)
}

extension DiagnosticLogging {
    func record(
        category: DiagnosticLogCategory,
        level: DiagnosticLogLevel,
        event: String,
        metadata: [String: String] = [:],
        detail: DiagnosticLogDetail = .standard
    ) {
        record(
            category: category,
            level: level,
            event: event,
            metadata: metadata,
            detail: detail
        )
    }
}

final class NoopDiagnosticLogger: DiagnosticLogging {
    static let shared = NoopDiagnosticLogger()

    private init() {}

    func record(
        category: DiagnosticLogCategory,
        level: DiagnosticLogLevel,
        event: String,
        metadata: [String: String],
        detail: DiagnosticLogDetail
    ) {}

    func beginScrollCaptureSession() -> DiagnosticCaptureSession {
        DiagnosticCaptureSession(id: UUID(), startedAt: Date(), isDetailed: true)
    }

    func endScrollCaptureSession(_ session: DiagnosticCaptureSession) {}
}

enum DiagnosticRedactor {
    private struct Rule {
        let expression: NSRegularExpression
        let replacement: String
    }

    private static let rules: [Rule] = [
        (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[REDACTED]"),
        (#"(?i)\bXXSNAP-[A-Z0-9_-]+"#, "[REDACTED]"),
        (#"(?i)\bXXSNAP(?:[_:][A-Z0-9]{2,}){2,}\b"#, "[REDACTED]"),
        (#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#, "[REDACTED]"),
        (#"\b[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]{2,}\b"#, "[REDACTED]"),
        (#"(?i)\b[a-f0-9]{64}\b"#, "[REDACTED]"),
        (
            #"(?i)((?:\"|')?(?:activation[_-]?code|license[_-]?code|credential[_-]?code|auth[_-]?code|recovery[_-]?code|secret[_-]?code|\bcode\b|[A-Za-z0-9_-]*payload[A-Za-z0-9_-]*|signature|device[_-]?hash|license[_-]?id|credential[_-]?id|\blicense\b|\bcredential\b|authorization|[A-Za-z0-9_-]*token[A-Za-z0-9_-]*)(?:\"|')?\s*(?::|=|\s)\s*)(?:\"[^\"]*\"|'[^']*'|[^\s,}]+)"#,
            "$1[REDACTED]"
        ),
    ].compactMap { pattern, replacement in
        try? Rule(expression: NSRegularExpression(pattern: pattern), replacement: replacement)
    }

    static func redact(_ value: String) -> String {
        rules.reduce(value) { partial, rule in
            let range = NSRange(partial.startIndex..<partial.endIndex, in: partial)
            return rule.expression.stringByReplacingMatches(
                in: partial,
                range: range,
                withTemplate: rule.replacement
            )
        }
    }

    static func containsSensitiveData(_ value: String) -> Bool {
        redact(value) != value
    }

    static func sanitizeJSONObject(_ value: Any, key: String? = nil) -> Any? {
        if let key, DiagnosticMetadata.mustDrop(key) { return nil }
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                guard !DiagnosticMetadata.mustDrop(entry.key),
                      let sanitized = sanitizeJSONObject(entry.value, key: entry.key)
                else { return }
                result[entry.key] = sanitized
            }
        case let array as [Any]:
            return array.compactMap { sanitizeJSONObject($0) }
        case let string as String:
            return redact(string)
        case is NSNull, is NSNumber:
            return value
        default:
            return redact(String(describing: value))
        }
    }
}

enum DiagnosticMetadata {
    private static let allowedCommercialKeys: Set<String> = [
        "policy_mode",
        "policy_id",
        "policy_expired",
        "access_kind",
        "commercial_feature",
        "request_result",
        "stable_error_code",
    ]
    private static let allowedCommercialNormalizedKeys = Set(
        allowedCommercialKeys.map(normalize)
    )

    private static let forbiddenKeyTerms = [
        "account",
        "activationcode",
        "authorization",
        "clipboard",
        "code",
        "credentialid",
        "devicehash",
        "email",
        "filename",
        "image",
        "licenseid",
        "ocr",
        "path",
        "payload",
        "screenshot",
        "signature",
        "signedpayload",
        "text",
        "title",
        "token",
        "url",
        "userinput",
    ]

    private static let commercialKeyTerms = [
        "access",
        "activation",
        "billing",
        "commercial",
        "credential",
        "device",
        "entitlement",
        "license",
        "policy",
        "trial",
    ]

    static func sanitized(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { result, entry in
            let normalizedKey = normalize(entry.key)
            let isAllowedCommercialKey = allowedCommercialKeys.contains(entry.key)
            let isCommercialKey = commercialKeyTerms.contains(where: normalizedKey.contains)
            guard !allowedCommercialNormalizedKeys.contains(normalizedKey)
                    || isAllowedCommercialKey else { return }
            guard !isCommercialKey || isAllowedCommercialKey else { return }
            guard isAllowedCommercialKey
                    || !forbiddenKeyTerms.contains(where: normalizedKey.contains) else { return }
            let flattened = entry.value
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            result[entry.key] = String(DiagnosticRedactor.redact(flattened).prefix(256))
        }
    }

    static func mustDrop(_ key: String) -> Bool {
        if allowedCommercialKeys.contains(key) { return false }
        let normalizedKey = normalize(key)
        if allowedCommercialNormalizedKeys.contains(normalizedKey) { return true }
        return commercialKeyTerms.contains(where: normalizedKey.contains)
            || forbiddenKeyTerms.contains(where: normalizedKey.contains)
    }

    private static func normalize(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

final class DiagnosticLogStore: DiagnosticLogging, @unchecked Sendable {
    struct Configuration {
        var maximumFileSize: Int = 5 * 1_024 * 1_024
        var maximumFileCount: Int = 5
        var retentionInterval: TimeInterval = 7 * 24 * 60 * 60
    }

    static let shared = DiagnosticLogStore()

    let directoryURL: URL

    private let configuration: Configuration
    private let now: () -> Date
    private let nextUUID: () -> UUID
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.xxsnap.diagnostic-log-store")
    private let systemLogger = Logger(subsystem: "com.xxsnap.mac", category: "diagnostics")
    private var activeSession: DiagnosticCaptureSession?

    init(
        directoryURL: URL = DiagnosticLogStore.defaultDirectoryURL(),
        configuration: Configuration = .init(),
        now: @escaping () -> Date = Date.init,
        nextUUID: @escaping () -> UUID = UUID.init,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.configuration = configuration
        self.now = now
        self.nextUUID = nextUUID
        self.fileManager = fileManager
    }

    func record(
        category: DiagnosticLogCategory,
        level: DiagnosticLogLevel,
        event: String,
        metadata: [String: String] = [:],
        detail: DiagnosticLogDetail = .standard
    ) {
        queue.async { [self] in
            if detail == .detailed, activeSession?.isDetailed != true {
                return
            }
            let sanitizedEvent = Self.sanitizedEventName(event)
            systemLogger.log(
                level: level.osLogType,
                "\(category.rawValue, privacy: .public) \(sanitizedEvent, privacy: .public)"
            )
            let logEvent = DiagnosticLogEvent(
                schemaVersion: 1,
                timestamp: now(),
                category: category,
                level: level,
                event: sanitizedEvent,
                sessionID: activeSession?.id,
                metadata: DiagnosticMetadata.sanitized(metadata)
            )
            append(logEvent)
        }
    }

    func beginScrollCaptureSession() -> DiagnosticCaptureSession {
        queue.sync {
            let currentDate = now()
            let session = DiagnosticCaptureSession(
                id: nextUUID(),
                startedAt: currentDate,
                isDetailed: true
            )
            activeSession = session
            return session
        }
    }

    func endScrollCaptureSession(_ session: DiagnosticCaptureSession) {
        queue.sync {
            if activeSession?.id == session.id {
                activeSession = nil
            }
        }
    }

    func performMaintenance() {
        queue.async { [self] in
            ensureDirectoryExists()
            removeExpiredFiles()
            enforceFileCount()
        }
    }

    func flush() {
        queue.sync {}
    }

    func logFileURLsSnapshot() -> [URL] {
        queue.sync {
            ensureDirectoryExists()
            removeExpiredFiles()
            enforceFileCount()
            return logFileURLs()
        }
    }

    func copyLogFiles(to destinationDirectory: URL) throws -> [URL] {
        try queue.sync {
            ensureDirectoryExists()
            removeExpiredFiles()
            enforceFileCount()
            return try logFileURLs().map { sourceURL in
                let destinationURL = destinationDirectory.appendingPathComponent(
                    sourceURL.lastPathComponent
                )
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                return destinationURL
            }
        }
    }

    private func append(_ event: DiagnosticLogEvent) {
        ensureDirectoryExists()
        removeExpiredFiles()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(event) else { return }
        data.append(0x0A)
        let currentURL = directoryURL.appendingPathComponent("xxsnap-current.jsonl")
        let currentSize = ((try? currentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if currentSize > 0, currentSize + data.count > configuration.maximumFileSize {
            rotateCurrentFile(at: currentURL)
        }
        if !fileManager.fileExists(atPath: currentURL.path) {
            fileManager.createFile(atPath: currentURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: currentURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
        enforceFileCount()
    }

    private func rotateCurrentFile(at currentURL: URL) {
        guard fileManager.fileExists(atPath: currentURL.path) else { return }
        let milliseconds = Int(now().timeIntervalSince1970 * 1_000)
        let rotatedURL = directoryURL.appendingPathComponent(
            "xxsnap-\(milliseconds)-\(nextUUID().uuidString.lowercased()).jsonl"
        )
        try? fileManager.moveItem(at: currentURL, to: rotatedURL)
    }

    private func removeExpiredFiles() {
        let cutoff = now().addingTimeInterval(-configuration.retentionInterval)
        for url in logFileURLs() {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            if let modified, modified < cutoff {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func enforceFileCount() {
        let files = logFileURLs().sorted {
            modificationDate(for: $0) < modificationDate(for: $1)
        }
        let excessCount = max(0, files.count - max(1, configuration.maximumFileCount))
        for url in files.prefix(excessCount) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func logFileURLs() -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ))?
        .filter { $0.pathExtension == "jsonl" } ?? []
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private func ensureDirectoryExists() {
        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private static func sanitizedEventName(_ event: String) -> String {
        DiagnosticRedactor.redact(event)
            .lowercased()
            .map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" }
            .reduce(into: "") { $0.append($1) }
    }

    private static func defaultDirectoryURL() -> URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("XxSnap", isDirectory: true)
    }
}
