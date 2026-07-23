import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

@MainActor
protocol LaunchAtLoginManaging: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ isEnabled: Bool) async throws
    func openSystemSettings()
}

@MainActor
final class LaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func setEnabled(_ isEnabled: Bool) async throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try await SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum UpdateCheckResult: Equatable {
    case placeholderUpToDate
}

protocol UpdateChecking {
    func checkForUpdates() async -> UpdateCheckResult
}

struct PlaceholderUpdateChecker: UpdateChecking {
    func checkForUpdates() async -> UpdateCheckResult {
        .placeholderUpToDate
    }
}
