import CryptoKit
import Darwin
import Foundation

enum AppUpdateInstallationError: LocalizedError, Equatable {
    case invalidDownload
    case checksumMismatch
    case invalidDiskImage
    case applicationMissing
    case identityMismatch
    case versionMismatch
    case signatureInvalid
    case currentApplicationUnavailable
    case permissionDenied
    case commandTimedOut
    case commandFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidDownload: return "The update download is invalid."
        case .checksumMismatch: return "The downloaded update failed its integrity check."
        case .invalidDiskImage: return "The update disk image could not be opened."
        case .applicationMissing: return "The update does not contain XxSnap."
        case .identityMismatch: return "The update belongs to a different application."
        case .versionMismatch: return "The downloaded version does not match the update information."
        case .signatureInvalid: return "The update has an invalid code signature."
        case .currentApplicationUnavailable: return "This copy of XxSnap cannot be updated in place."
        case .permissionDenied: return "Administrator permission is required to install the update."
        case .commandTimedOut: return "The update command timed out."
        case let .commandFailed(message): return message
        case .cancelled: return "The update was cancelled."
        }
    }
}

enum AppUpdateArtifactValidator {
    static func verifySHA256(of fileURL: URL, expected: String) throws {
        let normalized = expected.lowercased()
        guard normalized.count == 64,
              normalized.allSatisfy({ $0.isHexDigit })
        else { throw AppUpdateInstallationError.invalidDownload }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == normalized else { throw AppUpdateInstallationError.checksumMismatch }
    }
}

enum AppUpdateCandidateValidator {
    static func validate(
        info: [String: Any],
        release: AppUpdateRelease,
        expectedBundleIdentifier: String
    ) throws {
        guard info["CFBundleIdentifier"] as? String == expectedBundleIdentifier else {
            throw AppUpdateInstallationError.identityMismatch
        }
        guard info["CFBundleShortVersionString"] as? String == release.version,
              let build = info["CFBundleVersion"] as? String,
              Int(build) == release.buildNumber
        else { throw AppUpdateInstallationError.versionMismatch }
    }
}

struct AppUpdateProcessResult {
    let status: Int32
    let standardOutput: Data
    let standardError: Data
}

enum AppUpdateProcessRunner {
    static func run(
        _ executable: String,
        arguments: [String],
        captureStandardOutput: Bool = false,
        ignoreFailure: Bool = false,
        timeout: TimeInterval = 300
    ) throws -> AppUpdateProcessResult {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.xxsnap.update-process", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputURL = workspace.appendingPathComponent("stdout")
        let errorURL = workspace.appendingPathComponent("stderr")
        let outputHandle = try Self.captureHandle(at: outputURL)
        let errorHandle = try Self.captureHandle(at: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let processIdentifier = try spawn(
            executable,
            arguments: arguments,
            standardOutput: outputHandle,
            standardError: errorHandle
        )
        let deadline = Date().addingTimeInterval(timeout)
        var waitStatus: Int32 = 0
        while true {
            let waitResult = waitpid(processIdentifier, &waitStatus, WNOHANG)
            if waitResult == processIdentifier { break }
            if waitResult == -1, errno != EINTR {
                throw AppUpdateInstallationError.commandFailed(
                    String(cString: strerror(errno))
                )
            }
            if Date() >= deadline {
                terminateProcessGroup(processIdentifier)
                while waitpid(processIdentifier, &waitStatus, 0) == -1, errno == EINTR {}
                throw AppUpdateInstallationError.commandTimedOut
            }
            usleep(10_000)
        }
        try? outputHandle.close()
        try? errorHandle.close()
        let result = AppUpdateProcessResult(
            status: exitStatus(from: waitStatus),
            standardOutput: captureStandardOutput ? Self.read(at: outputURL, limit: 1_048_576) : Data(),
            standardError: Self.read(at: errorURL, limit: 65_536)
        )
        if !ignoreFailure, result.status != 0 {
            let detail = String(data: result.standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppUpdateInstallationError.commandFailed(
                detail?.isEmpty == false ? detail! : "The update command failed (status \(result.status))."
            )
        }
        return result
    }

    private static func spawn(
        _ executable: String,
        arguments: [String],
        standardOutput: FileHandle,
        standardError: FileHandle
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0,
              posix_spawnattr_init(&attributes) == 0
        else { throw AppUpdateInstallationError.commandFailed("Unable to prepare update command.") }
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&attributes)
        }

        guard posix_spawn_file_actions_adddup2(
            &fileActions,
            standardOutput.fileDescriptor,
            STDOUT_FILENO
        ) == 0,
        posix_spawn_file_actions_adddup2(
            &fileActions,
            standardError.fileDescriptor,
            STDERR_FILENO
        ) == 0,
        posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)
        ) == 0,
        posix_spawnattr_setpgroup(&attributes, 0) == 0
        else { throw AppUpdateInstallationError.commandFailed("Unable to configure update command.") }

        let command = [executable] + arguments
        let cStrings = command.map { strdup($0)! }
        defer { cStrings.forEach { free($0) } }
        var argv: [UnsafeMutablePointer<CChar>?] = cStrings.map { $0 }
        argv.append(nil)
        var processIdentifier = pid_t()
        let spawnStatus = executable.withCString { executablePath in
            argv.withUnsafeMutableBufferPointer { buffer in
                posix_spawn(
                    &processIdentifier,
                    executablePath,
                    &fileActions,
                    &attributes,
                    buffer.baseAddress,
                    environ
                )
            }
        }
        guard spawnStatus == 0 else {
            throw AppUpdateInstallationError.commandFailed(
                String(cString: strerror(spawnStatus))
            )
        }
        return processIdentifier
    }

    private static func terminateProcessGroup(_ processIdentifier: pid_t) {
        _ = kill(-processIdentifier, SIGTERM)
        let gracefulDeadline = Date().addingTimeInterval(2)
        while kill(-processIdentifier, 0) == 0, Date() < gracefulDeadline {
            usleep(10_000)
        }
        if kill(-processIdentifier, 0) == 0 {
            _ = kill(-processIdentifier, SIGKILL)
        }
    }

    private static func exitStatus(from waitStatus: Int32) -> Int32 {
        let terminationSignal = waitStatus & 0x7f
        return terminationSignal == 0
            ? (waitStatus >> 8) & 0xff
            : 128 + terminationSignal
    }

    private static func captureHandle(at url: URL) throws -> FileHandle {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw AppUpdateInstallationError.commandFailed("Unable to create update process output.")
        }
        return try FileHandle(forWritingTo: url)
    }

    private static func read(at url: URL, limit: Int) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: limit)) ?? Data()
    }
}

struct PreparedAppUpdate: Sendable {
    let applicationURL: URL
    let workspaceURL: URL
    let codeDirectoryRequirement: String
    let bundleIdentifier: String
    let version: String
    let buildNumber: Int
}

protocol AppUpdateInstalling: Sendable {
    func prepare(downloadURL: URL, release: AppUpdateRelease) throws -> PreparedAppUpdate
    func install(_ prepared: PreparedAppUpdate) throws
}

struct SystemAppUpdateInstaller: AppUpdateInstalling, @unchecked Sendable {
    private let fileManager: FileManager
    private let currentApplicationURL: URL
    private let expectedBundleIdentifier: String

    init(bundle: Bundle = .main, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        currentApplicationURL = bundle.bundleURL
        expectedBundleIdentifier = bundle.bundleIdentifier ?? "com.xxsnap.mac"
    }

    func prepare(downloadURL: URL, release: AppUpdateRelease) throws -> PreparedAppUpdate {
        try AppUpdateArtifactValidator.verifySHA256(of: downloadURL, expected: release.sha256)
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("com.xxsnap.update", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        var keepsWorkspace = false
        defer {
            if !keepsWorkspace { try? fileManager.removeItem(at: workspace) }
        }

        let attach = try AppUpdateProcessRunner.run(
            "/usr/bin/hdiutil",
            arguments: ["attach", "-readonly", "-nobrowse", "-plist", downloadURL.path],
            captureStandardOutput: true
        )
        guard let mountURL = Self.mountURL(from: attach.standardOutput) else {
            throw AppUpdateInstallationError.invalidDiskImage
        }
        defer {
            let result = try? AppUpdateProcessRunner.run(
                "/usr/bin/hdiutil",
                arguments: ["detach", mountURL.path],
                ignoreFailure: true
            )
            if result?.status != 0 {
                _ = try? AppUpdateProcessRunner.run(
                    "/usr/bin/hdiutil",
                    arguments: ["detach", "-force", mountURL.path],
                    ignoreFailure: true
                )
            }
        }

        guard let candidate = Self.application(in: mountURL, fileManager: fileManager) else {
            throw AppUpdateInstallationError.applicationMissing
        }
        try validate(candidate, release: release)
        let codeDirectoryRequirement = try Self.codeDirectoryRequirement(for: candidate)
        let staged = workspace.appendingPathComponent("XxSnap.app", isDirectory: true)
        _ = try AppUpdateProcessRunner.run(
            "/usr/bin/ditto",
            arguments: [candidate.path, staged.path]
        )
        // The artifact is authenticated by the signed policy hash before this point.
        _ = try AppUpdateProcessRunner.run(
            "/usr/bin/xattr",
            arguments: ["-dr", "com.apple.quarantine", staged.path]
        )
        let stagedSignature = try AppUpdateProcessRunner.run(
            "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", "-R=\(codeDirectoryRequirement)", staged.path],
            ignoreFailure: true
        )
        guard stagedSignature.status == 0 else {
            throw AppUpdateInstallationError.signatureInvalid
        }
        keepsWorkspace = true
        return PreparedAppUpdate(
            applicationURL: staged,
            workspaceURL: workspace,
            codeDirectoryRequirement: codeDirectoryRequirement,
            bundleIdentifier: expectedBundleIdentifier,
            version: release.version,
            buildNumber: release.buildNumber
        )
    }

    func install(_ prepared: PreparedAppUpdate) throws {
        defer { try? fileManager.removeItem(at: prepared.workspaceURL) }
        guard currentApplicationURL.pathExtension == "app",
              fileManager.fileExists(atPath: currentApplicationURL.path),
              currentApplicationURL.path.hasPrefix("/Volumes/") == false
        else { throw AppUpdateInstallationError.currentApplicationUnavailable }

        let parent = currentApplicationURL.deletingLastPathComponent()
        let suffix = UUID().uuidString
        let signingRequirement = try Self.installedSignerRequirement(for: currentApplicationURL)
        let installationRequirement = Self.installationRequirement(
            signingRequirement: signingRequirement,
            codeDirectoryRequirement: prepared.codeDirectoryRequirement
        )
        let arguments = [
            prepared.applicationURL.path,
            currentApplicationURL.path,
            suffix,
            installationRequirement,
            prepared.bundleIdentifier,
            prepared.version,
            String(prepared.buildNumber),
        ]

        if fileManager.isWritableFile(atPath: parent.path) {
            _ = try AppUpdateProcessRunner.run(
                "/bin/zsh",
                arguments: ["-c", Self.installScript, "xxsnap-update"] + arguments + ["0"]
            )
        } else {
            try installWithAdministratorPrivileges(
                arguments: arguments + ["1"]
            )
        }
    }

    private func validate(_ applicationURL: URL, release: AppUpdateRelease) throws {
        guard let bundle = Bundle(url: applicationURL), let info = bundle.infoDictionary else {
            throw AppUpdateInstallationError.applicationMissing
        }
        try AppUpdateCandidateValidator.validate(
            info: info,
            release: release,
            expectedBundleIdentifier: expectedBundleIdentifier
        )
        let signature = try AppUpdateProcessRunner.run(
            "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", applicationURL.path],
            ignoreFailure: true
        )
        guard signature.status == 0 else { throw AppUpdateInstallationError.signatureInvalid }
    }

    private func installWithAdministratorPrivileges(arguments: [String]) throws {
        let result = try AppUpdateProcessRunner.run(
            "/usr/bin/osascript",
            arguments: [
                "-e",
                Self.administratorAppleScript,
                "/bin/zsh",
                "-c",
                Self.installScript,
                "xxsnap-update",
            ] + arguments,
            ignoreFailure: true,
            timeout: 900
        )
        guard result.status == 0 else {
            let message = String(data: result.standardError, encoding: .utf8) ?? ""
            if message.contains("(-128)") { throw AppUpdateInstallationError.cancelled }
            throw AppUpdateInstallationError.permissionDenied
        }
    }

    private static func signingRequirement(for applicationURL: URL) throws -> String {
        let result = try AppUpdateProcessRunner.run(
            "/usr/bin/codesign",
            arguments: ["-d", "-r-", applicationURL.path],
            captureStandardOutput: true,
            ignoreFailure: true
        )
        guard result.status == 0,
              let requirement = designatedRequirement(
                  standardOutput: result.standardOutput,
                  standardError: result.standardError
              )
        else { throw AppUpdateInstallationError.signatureInvalid }
        return requirement
    }

    static func designatedRequirement(standardOutput: Data, standardError: Data) -> String? {
        let prefix = "designated => "
        for data in [standardOutput, standardError] {
            guard let output = String(data: data, encoding: .utf8) else { continue }
            if let requirement = output
                .split(separator: "\n")
                .first(where: { $0.hasPrefix(prefix) })?
                .dropFirst(prefix.count),
               !requirement.isEmpty {
                return String(requirement)
            }
        }
        return nil
    }

    private static func installedSignerRequirement(for applicationURL: URL) throws -> String {
        #if XX_UPDATE_TEST_MODE
        // Explicit local test builds may replace a locally signed client with the production-signed release.
        return ""
        #else
        return try signingRequirement(for: applicationURL)
        #endif
    }

    private static func codeDirectoryRequirement(for applicationURL: URL) throws -> String {
        var hashes: [String] = []
        for architecture in ["arm64", "x86_64"] {
            let result = try AppUpdateProcessRunner.run(
                "/usr/bin/codesign",
                arguments: ["-d", "--arch", architecture, "--verbose=4", applicationURL.path],
                ignoreFailure: true
            )
            guard result.status == 0,
                  let output = String(data: result.standardError, encoding: .utf8),
                  let hash = output
                    .split(separator: "\n")
                    .first(where: { $0.hasPrefix("CDHash=") })?
                    .dropFirst("CDHash=".count),
                  hash.count >= 40,
                  hash.allSatisfy({ $0.isHexDigit })
            else { continue }
            hashes.append(String(hash).lowercased())
        }
        guard !hashes.isEmpty else { throw AppUpdateInstallationError.signatureInvalid }
        return codeHashRequirement(for: hashes)
    }

    static func codeHashRequirement(for hashes: [String]) -> String {
        let clauses = hashes.map { "cdhash H\"\($0)\"" }
        return clauses.count == 1 ? clauses[0] : "(\(clauses.joined(separator: " or ")))"
    }

    static func installationRequirement(
        signingRequirement: String,
        codeDirectoryRequirement: String
    ) -> String {
        guard !signingRequirement.isEmpty else { return codeDirectoryRequirement }
        return "(\(signingRequirement)) and (\(codeDirectoryRequirement))"
    }

    private static func mountURL(from plistData: Data) -> URL? {
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
              let dictionary = plist as? [String: Any],
              let entities = dictionary["system-entities"] as? [[String: Any]],
              let path = entities.compactMap({ $0["mount-point"] as? String }).first
        else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func application(in mountURL: URL, fileManager: FileManager) -> URL? {
        if let direct = try? fileManager.contentsOfDirectory(
            at: mountURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).first(where: { $0.pathExtension.lowercased() == "app" }) {
            return direct
        }
        return nil
    }

    private static let administratorAppleScript = """
    on run argv
        set commandText to quoted form of item 1 of argv
        repeat with argumentValue in items 2 thru -1 of argv
            set commandText to commandText & " " & quoted form of argumentValue
        end repeat
        do shell script commandText with administrator privileges
    end run
    """

    static let installScript = """
    #!/bin/zsh
    set -euo pipefail
    staged="$1"
    target="$2"
    suffix="$3"
    installation_requirement="$4"
    expected_identifier="$5"
    expected_version="$6"
    expected_build="$7"
    privileged_install="$8"
    parent="${target:h}"
    name="${target:t}"
    incoming="$parent/.$name.update-$suffix"
    backup="$parent/.$name.backup-$suffix"
    swapped=0
    cleanup() {
        exit_status=$?
        trap - EXIT HUP INT TERM
        if (( swapped == 1 )) && [[ ! -e "$target" && -e "$backup" ]]; then
            /bin/mv "$backup" "$target" || true
        fi
        /bin/rm -rf "$incoming"
        exit $exit_status
    }
    trap cleanup EXIT HUP INT TERM
    umask 077
    if [[ "$privileged_install" == "1" ]]; then
        /bin/mkdir -m 700 "$incoming"
    fi
    /usr/bin/ditto "$staged" "$incoming"
    if [[ "$privileged_install" == "1" ]]; then
        /bin/chmod -RN "$incoming"
        /usr/sbin/chown -R -h root:wheel "$incoming"
        /bin/chmod -R u+rwX,go+rX,go-w "$incoming"
    fi
    info_plist="$incoming/Contents/Info.plist"
    actual_identifier=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info_plist")
    actual_version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$info_plist")
    actual_build=$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$info_plist")
    [[ "$actual_identifier" == "$expected_identifier" ]]
    [[ "$actual_version" == "$expected_version" ]]
    [[ "$actual_build" == "$expected_build" ]]
    /usr/bin/codesign --verify --deep --strict "-R=$installation_requirement" "$incoming"
    swapped=1
    /bin/mv "$target" "$backup"
    /bin/mv "$incoming" "$target"
    swapped=0
    /bin/rm -rf "$backup" || true
    """
}
