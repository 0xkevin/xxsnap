import AppKit
import Foundation
import Network

struct AppUpdateVersion: Comparable, Equatable {
    private let core: [Int]
    private let prerelease: [String]?

    init?(_ value: String) {
        let withoutBuild = value.split(separator: "+", maxSplits: 1).first.map(String.init) ?? value
        let pieces = withoutBuild.split(separator: "-", maxSplits: 1).map(String.init)
        let components = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              components.allSatisfy({ Int($0) != nil })
        else { return nil }
        let numbers = components.compactMap({ Int($0) })
        core = numbers
        prerelease = pieces.count == 2 ? pieces[1].split(separator: ".").map(String.init) : nil
    }

    static func < (lhs: AppUpdateVersion, rhs: AppUpdateVersion) -> Bool {
        if lhs.core != rhs.core {
            return lhs.core.lexicographicallyPrecedes(rhs.core)
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (left?, right?):
            for index in 0..<min(left.count, right.count) where left[index] != right[index] {
                if let leftNumber = Int(left[index]), let rightNumber = Int(right[index]) {
                    return leftNumber < rightNumber
                }
                if Int(left[index]) != nil { return true }
                if Int(right[index]) != nil { return false }
                return left[index] < right[index]
            }
            return left.count < right.count
        }
    }

    static func isOlder(
        version: String,
        build: Int,
        than targetVersion: String,
        build targetBuild: Int
    ) -> Bool {
        guard let current = AppUpdateVersion(version), let target = AppUpdateVersion(targetVersion) else {
            return false
        }
        if current != target { return current < target }
        return build < targetBuild
    }
}

struct AppUpdateRelease: Codable, Equatable {
    let version: String
    let buildNumber: Int
    let downloadURL: URL
    let sha256: String
    let releaseNotes: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, buildNumber, downloadURL = "downloadUrl", sha256, releaseNotes
    }

    init(version: String, buildNumber: Int, downloadURL: URL, sha256: String, releaseNotes: String) {
        self.version = version
        self.buildNumber = buildNumber
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.releaseNotes = releaseNotes
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        buildNumber = try container.decode(Int.self, forKey: .buildNumber)
        downloadURL = try container.decode(URL.self, forKey: .downloadURL)
        sha256 = try container.decode(String.self, forKey: .sha256)
        releaseNotes = try container.decode(String.self, forKey: .releaseNotes)
    }

    static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let prefix = "/api/v1/downloads/"
        return components.scheme == "https"
            && components.host == "download.xxsofts.com"
            && components.user == nil
            && components.password == nil
            && (components.port == nil || components.port == 443)
            && components.path.hasPrefix(prefix)
            && components.path.count > prefix.count
            && components.query == nil
            && components.fragment == nil
    }
}

struct AppUpdateRequirement: Codable, Equatable {
    let minimumVersion: String
    let minimumBuildNumber: Int
    let enforceAfter: Date

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case minimumVersion, minimumBuildNumber, enforceAfter
    }

    init(minimumVersion: String, minimumBuildNumber: Int, enforceAfter: Date) {
        self.minimumVersion = minimumVersion
        self.minimumBuildNumber = minimumBuildNumber
        self.enforceAfter = enforceAfter
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minimumVersion = try container.decode(String.self, forKey: .minimumVersion)
        minimumBuildNumber = try container.decode(Int.self, forKey: .minimumBuildNumber)
        enforceAfter = try CommercialJSON.date(
            container.decode(String.self, forKey: .enforceAfter),
            field: CodingKeys.enforceAfter.rawValue
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minimumVersion, forKey: .minimumVersion)
        try container.encode(minimumBuildNumber, forKey: .minimumBuildNumber)
        try container.encode(CommercialJSON.string(enforceAfter), forKey: .enforceAfter)
    }
}

struct AppUpdatePolicy: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let expiresAt: Date
    let latest: AppUpdateRelease
    let requirements: [AppUpdateRequirement]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, generatedAt, expiresAt, latest, requirements
    }

    init(
        schemaVersion: Int,
        generatedAt: Date,
        expiresAt: Date,
        latest: AppUpdateRelease,
        requirements: [AppUpdateRequirement]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.latest = latest
        self.requirements = requirements
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try CommercialJSON.date(
            container.decode(String.self, forKey: .generatedAt),
            field: CodingKeys.generatedAt.rawValue
        )
        expiresAt = try CommercialJSON.date(
            container.decode(String.self, forKey: .expiresAt),
            field: CodingKeys.expiresAt.rawValue
        )
        latest = try container.decode(AppUpdateRelease.self, forKey: .latest)
        requirements = try container.decode([AppUpdateRequirement].self, forKey: .requirements)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(CommercialJSON.string(generatedAt), forKey: .generatedAt)
        try container.encode(CommercialJSON.string(expiresAt), forKey: .expiresAt)
        try container.encode(latest, forKey: .latest)
        try container.encode(requirements, forKey: .requirements)
    }
}

enum UpdateCheckResult: Equatable {
    case upToDate
    case available(AppUpdateRelease)
    case grace(AppUpdateRelease, deadline: Date)
    case required(AppUpdateRelease, deadline: Date)
    case unavailable
}

enum AppUpdatePolicyEvaluator {
    static func evaluate(
        policy: AppUpdatePolicy,
        currentVersion: String,
        currentBuild: Int
    ) -> UpdateCheckResult {
        let applicable = policy.requirements.filter {
            AppUpdateVersion.isOlder(
                version: currentVersion,
                build: currentBuild,
                than: $0.minimumVersion,
                build: $0.minimumBuildNumber
            )
        }
        if let enforced = applicable
            .filter({ $0.enforceAfter <= policy.generatedAt })
            .max(by: { $0.minimumBuildNumber < $1.minimumBuildNumber }) {
            return .required(policy.latest, deadline: enforced.enforceAfter)
        }
        if let upcoming = applicable.min(by: { $0.enforceAfter < $1.enforceAfter }) {
            return .grace(policy.latest, deadline: upcoming.enforceAfter)
        }
        if AppUpdateVersion.isOlder(
            version: currentVersion,
            build: currentBuild,
            than: policy.latest.version,
            build: policy.latest.buildNumber
        ) {
            return .available(policy.latest)
        }
        return .upToDate
    }
}

struct AppUpdateFetchResponse: Equatable {
    let envelope: SignedEnvelope
    let serverDate: Date?
}

protocol AppUpdatePolicyFetching {
    func fetchPolicy(locale: AppLanguage) async throws -> AppUpdateFetchResponse
}

@MainActor
final class SystemAppUpdateNetworkMonitor: CommercialNetworkMonitoring {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.xxsnap.update-network-monitor")
    private var previousStatus: NWPath.Status?

    func start(onRecovery: @escaping @MainActor () -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let previous = previousStatus
                previousStatus = path.status
                if previous != .satisfied, path.status == .satisfied {
                    onRecovery()
                }
            }
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
        previousStatus = nil
    }
}

final class AppUpdatePolicyClient: AppUpdatePolicyFetching {
    private let origin: URL
    private let session: URLSession
    private let redirectDelegate = CommercialSessionDelegate()

    init(origin: URL, session: URLSession) throws {
        guard CommercialPolicyClient.isAllowedProductionOrigin(origin) else {
            throw CommercialPolicyClientError.invalidOrigin
        }
        self.origin = origin
        self.session = session
    }

    convenience init(bundle: Bundle = .main, session: URLSession = .shared) throws {
        guard let value = bundle.object(forInfoDictionaryKey: "XXCommercialAPIOrigin") as? String,
              let origin = URL(string: value)
        else { throw CommercialPolicyClientError.invalidOrigin }
        try self.init(origin: origin, session: session)
    }

    func fetchPolicy(locale: AppLanguage) async throws -> AppUpdateFetchResponse {
        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
            throw CommercialPolicyClientError.invalidOrigin
        }
        components.path = "/api/v1/releases/update-policy"
        components.queryItems = [URLQueryItem(name: "locale", value: locale == .english ? "en" : "zh-CN")]
        guard let url = components.url else { throw CommercialPolicyClientError.invalidOrigin }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request, delegate: redirectDelegate)
            guard let http = response as? HTTPURLResponse else {
                throw CommercialPolicyClientError.malformedResponse
            }
            guard http.statusCode == 200 else {
                throw CommercialPolicyClientError.unexpectedStatus(http.statusCode)
            }
            guard let envelope = try? JSONDecoder().decode(SignedEnvelope.self, from: data) else {
                throw CommercialPolicyClientError.malformedResponse
            }
            return AppUpdateFetchResponse(
                envelope: envelope,
                serverDate: Self.httpDate(http.value(forHTTPHeaderField: "Date"))
            )
        } catch let error as CommercialPolicyClientError {
            throw error
        } catch {
            throw CommercialPolicyClientError.transport
        }
    }

    private static func httpDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        return formatter.date(from: value)
    }
}

@MainActor
protocol UpdateChecking {
    var blocksAppUse: Bool { get }
    func checkForUpdates() async -> UpdateCheckResult
    func presentUpdateResult(_ result: UpdateCheckResult, manual: Bool)
    func presentRequiredUpdate()
}

extension UpdateChecking {
    var blocksAppUse: Bool { false }
    func presentUpdateResult(_ result: UpdateCheckResult, manual: Bool) {}
    func presentRequiredUpdate() {}
}

@MainActor
final class AppUpdateController: UpdateChecking {
    private let fetcher: any AppUpdatePolicyFetching
    private let verifier: CommercialSignatureVerifier
    private let currentVersion: String
    private let currentBuild: Int
    private let networkMonitor: any CommercialNetworkMonitoring
    private let downloader: any AppUpdateDownloading
    private let installer: any AppUpdateInstalling
    private let applicationURL: URL
    private var periodicTask: Task<Void, Never>?
    private var checkTask: Task<UpdateCheckResult, Never>?
    private var updateTask: Task<Void, Never>?
    private var state: UpdateCheckResult = .upToDate
    private var isPresenting = false
    private var started = false
    var onStateChange: (() -> Void)?

    init(
        bundle: Bundle = .main,
        fetcher: (any AppUpdatePolicyFetching)? = nil,
        networkMonitor: (any CommercialNetworkMonitoring)? = nil,
        downloader: (any AppUpdateDownloading)? = nil,
        installer: (any AppUpdateInstalling)? = nil
    ) throws {
        self.fetcher = try fetcher ?? AppUpdatePolicyClient(bundle: bundle)
        verifier = try CommercialSignatureVerifier(bundle: bundle)
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        currentBuild = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        self.networkMonitor = networkMonitor ?? SystemAppUpdateNetworkMonitor()
        self.downloader = downloader ?? AppUpdateDownloadService()
        self.installer = installer ?? SystemAppUpdateInstaller(bundle: bundle)
        applicationURL = bundle.bundleURL
    }

    var blocksAppUse: Bool {
        if case .required = state { return true }
        return false
    }

    func start(showOptionalAtLaunch: Bool, intervalHours: Int) {
        guard !started else { return }
        started = true
        networkMonitor.start { [weak self] in
            self?.refreshInBackground(showOptional: false)
        }
        refreshInBackground(showOptional: showOptionalAtLaunch)
        periodicTask = Task { @MainActor [weak self] in
            let interval = UInt64(max(1, intervalHours)) * 60 * 60 * 1_000_000_000
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { return }
                self?.refreshInBackground(showOptional: false)
            }
        }
    }

    func stop() {
        periodicTask?.cancel()
        periodicTask = nil
        networkMonitor.cancel()
        started = false
    }

    func checkForUpdates() async -> UpdateCheckResult {
        if let checkTask { return await checkTask.value }
        let task = Task { @MainActor [weak self] () -> UpdateCheckResult in
            guard let self else { return .unavailable }
            do {
                let response = try await fetcher.fetchPolicy(locale: currentLanguage)
                let serverNow = response.serverDate ?? Date()
                let policy = try verifier.verifyUpdatePolicy(response.envelope, at: serverNow)
                return AppUpdatePolicyEvaluator.evaluate(
                    policy: policy,
                    currentVersion: currentVersion,
                    currentBuild: currentBuild
                )
            } catch {
                return .unavailable
            }
        }
        checkTask = task
        let result = await task.value
        checkTask = nil
        if result == .unavailable, case .required = state { return state }
        if result != .unavailable { setState(result) }
        return result
    }

    func presentUpdateResult(_ result: UpdateCheckResult, manual: Bool) {
        guard !isPresenting, updateTask == nil else { return }
        switch result {
        case .upToDate where !manual, .unavailable where !manual:
            return
        default:
            break
        }
        isPresenting = true
        defer { isPresenting = false }
        let strings = PreferencesStrings(language: currentLanguage)
        let alert = NSAlert()
        switch result {
        case .upToDate:
            alert.messageText = strings.upToDate
            alert.informativeText = "XxSnap \(currentVersion) (\(currentBuild))"
            alert.addButton(withTitle: strings.confirm)
        case let .available(release):
            configureUpdateAlert(
                alert,
                release: release,
                title: strings.updateAvailableTitle,
                detail: release.releaseNotes,
                strings: strings
            )
        case let .grace(release, deadline):
            configureUpdateAlert(
                alert,
                release: release,
                title: strings.updateGraceTitle,
                detail: strings.updateGraceDetail(deadline: deadline),
                strings: strings
            )
        case let .required(release, deadline):
            alert.alertStyle = .critical
            alert.messageText = strings.updateRequiredTitle
            alert.informativeText = strings.updateRequiredDetail(version: release.version, deadline: deadline)
            alert.addButton(withTitle: strings.downloadUpdate)
            alert.addButton(withTitle: strings.quit)
        case .unavailable:
            alert.alertStyle = .warning
            alert.messageText = strings.updateUnavailableTitle
            alert.informativeText = strings.updateUnavailableDetail
            alert.addButton(withTitle: strings.confirm)
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch result {
        case let .available(release), let .grace(release, _):
            if response == .alertFirstButtonReturn { beginUpdate(release, strings: strings) }
        case let .required(release, _):
            if response == .alertFirstButtonReturn {
                beginUpdate(release, strings: strings)
            } else {
                NSApplication.shared.terminate(nil)
            }
        default:
            break
        }
    }

    func presentRequiredUpdate() {
        guard case .required = state else { return }
        presentUpdateResult(state, manual: true)
    }

    private var currentLanguage: AppLanguage {
        SettingsStore().load().language
    }

    private func refreshInBackground(showOptional: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await checkForUpdates()
            if case .required = result {
                presentUpdateResult(result, manual: false)
            } else if showOptional {
                presentUpdateResult(result, manual: false)
            }
        }
    }

    private func setState(_ newState: UpdateCheckResult) {
        guard state != newState else { return }
        state = newState
        onStateChange?()
    }

    private func configureUpdateAlert(
        _ alert: NSAlert,
        release: AppUpdateRelease,
        title: String,
        detail: String,
        strings: PreferencesStrings
    ) {
        alert.messageText = title
        alert.informativeText = detail.isEmpty ? "XxSnap \(release.version)" : detail
        alert.addButton(withTitle: strings.downloadUpdate)
        alert.addButton(withTitle: strings.later)
    }

    private func beginUpdate(_ release: AppUpdateRelease, strings: PreferencesStrings) {
        guard updateTask == nil,
              AppUpdateRelease.isAllowedDownloadURL(release.downloadURL)
        else { return }
        let progress = UpdateProgressWindowController(version: release.version, strings: strings)
        progress.onCancel = { [weak self] in
            self?.downloader.cancel()
        }
        progress.update(stage: .downloading(nil))
        progress.show()

        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var acceptsDownloadProgress = true
            do {
                let downloadedURL = try await downloader.download(release: release) { [weak progress] value in
                    guard acceptsDownloadProgress else { return }
                    progress?.update(stage: .downloading(value))
                }
                acceptsDownloadProgress = false
                defer { cleanupDownload(downloadedURL) }
                progress.update(stage: .verifying)
                let prepared = try await Task.detached(priority: .userInitiated) { [installer] in
                    try installer.prepare(downloadURL: downloadedURL, release: release)
                }.value
                progress.update(stage: .installing)
                try await Task.detached(priority: .userInitiated) { [installer] in
                    try installer.install(prepared)
                }.value
                progress.close()
                updateTask = nil
                relaunchInstalledApplication()
            } catch {
                acceptsDownloadProgress = false
                progress.close()
                updateTask = nil
                presentUpdateFailure(error, strings: strings)
            }
        }
    }

    private func cleanupDownload(_ fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    private func presentUpdateFailure(_ error: Error, strings: PreferencesStrings) {
        let alert = NSAlert()
        if error as? AppUpdateInstallationError == .cancelled {
            alert.messageText = strings.updateCancelledTitle
            alert.informativeText = ""
        } else {
            alert.alertStyle = .warning
            alert.messageText = strings.updateFailedTitle
            let detail = strings.updateFailureReason(error)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            alert.informativeText = detail.isEmpty
                ? strings.updateFailedDetail
                : "\(strings.updateFailedDetail)\n\n\(detail)"
        }
        alert.addButton(withTitle: strings.confirm)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func relaunchInstalledApplication() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "pid=\"$1\"; app=\"$2\"; count=0; while /bin/kill -0 \"$pid\" 2>/dev/null && [ \"$count\" -lt 300 ]; do /bin/sleep 0.2; count=$((count + 1)); done; /usr/bin/open \"$app\"",
            "xxsnap-relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            applicationURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            NSApplication.shared.terminate(nil)
        } catch {
            NSWorkspace.shared.open(applicationURL)
            NSApplication.shared.terminate(nil)
        }
    }
}

@MainActor
struct UnavailableUpdateChecker: UpdateChecking {
    func checkForUpdates() async -> UpdateCheckResult { .unavailable }
}
