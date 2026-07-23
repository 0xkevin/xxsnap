import Foundation

struct PreferencesSettings: Codable, Equatable {
    static let allowedUpdateIntervals = [1, 6, 12, 24, 48, 72]
    static let defaultFilenameTemplate = "xxsnap_截图_{yyyyMMdd}_{HHmmss}"
    fileprivate static let legacyDefaultFilenameTemplate = "xxsnap 截图 {yyyyMMdd}-{HHmmss}"

    var filenameTemplate: String
    var checksForUpdatesAtLaunch: Bool
    var updateCheckIntervalHours: Int

    static let `default` = PreferencesSettings(
        filenameTemplate: defaultFilenameTemplate,
        checksForUpdatesAtLaunch: true,
        updateCheckIntervalHours: 24
    )

    init(
        filenameTemplate: String,
        checksForUpdatesAtLaunch: Bool,
        updateCheckIntervalHours: Int
    ) {
        self.filenameTemplate = filenameTemplate
        self.checksForUpdatesAtLaunch = checksForUpdatesAtLaunch
        self.updateCheckIntervalHours = Self.normalizedUpdateInterval(updateCheckIntervalHours)
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.default
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filenameTemplate = (try? container.decode(String.self, forKey: .filenameTemplate))
            ?? defaults.filenameTemplate
        checksForUpdatesAtLaunch = (try? container.decode(Bool.self, forKey: .checksForUpdatesAtLaunch))
            ?? defaults.checksForUpdatesAtLaunch
        let decodedInterval = (try? container.decode(Int.self, forKey: .updateCheckIntervalHours))
            ?? defaults.updateCheckIntervalHours
        updateCheckIntervalHours = Self.normalizedUpdateInterval(decodedInterval)
    }

    private static func normalizedUpdateInterval(_ value: Int) -> Int {
        allowedUpdateIntervals.contains(value) ? value : 24
    }
}

protocol PreferencesSettingsStoring: AnyObject {
    func load() -> PreferencesSettings
    func save(_ settings: PreferencesSettings) throws
}

final class PreferencesSettingsStore: PreferencesSettingsStoring {
    private let key = "preferencesSettings.v1"
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> PreferencesSettings {
        guard
            let data = userDefaults.data(forKey: key),
            var settings = try? decoder.decode(PreferencesSettings.self, from: data)
        else {
            return .default
        }
        if settings.filenameTemplate == PreferencesSettings.legacyDefaultFilenameTemplate {
            settings.filenameTemplate = PreferencesSettings.defaultFilenameTemplate
            try? save(settings)
        }
        return settings
    }

    func save(_ settings: PreferencesSettings) throws {
        let data = try encoder.encode(settings)
        userDefaults.set(data, forKey: key)
    }
}

enum FilenameTemplateError: LocalizedError, Equatable {
    case empty
    case pathSeparator
    case unknownVariable(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "文件名模板不能为空"
        case .pathSeparator:
            return "文件名模板不能包含路径分隔符"
        case .unknownVariable(let variable):
            return "不支持的变量：\(variable)"
        }
    }
}

struct FilenameTemplateRenderer {
    private static let supportedVariables = ["{yyyyMMdd}", "{HHmmss}"]

    func filename(
        template: String,
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FilenameTemplateError.empty
        }
        guard !trimmed.contains("/"),
              !trimmed.contains(":"),
              !trimmed.contains("\0"),
              !trimmed.contains("\n"),
              !trimmed.contains("\r")
        else {
            throw FilenameTemplateError.pathSeparator
        }

        var unresolvedCheck = trimmed
        for variable in Self.supportedVariables {
            unresolvedCheck = unresolvedCheck.replacingOccurrences(of: variable, with: "")
        }
        if let range = unresolvedCheck.range(of: #"\{[^{}]*\}"#, options: .regularExpression) {
            throw FilenameTemplateError.unknownVariable(String(unresolvedCheck[range]))
        }
        if unresolvedCheck.contains("{") || unresolvedCheck.contains("}") {
            throw FilenameTemplateError.unknownVariable(
                unresolvedCheck.first(where: { $0 == "{" || $0 == "}" }).map(String.init) ?? ""
            )
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyyMMdd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HHmmss"

        let rendered = trimmed
            .replacingOccurrences(of: "{yyyyMMdd}", with: dateFormatter.string(from: date))
            .replacingOccurrences(of: "{HHmmss}", with: timeFormatter.string(from: date))
        return rendered.lowercased().hasSuffix(".png") ? rendered : "\(rendered).png"
    }
}

protocol CaptureFilenameProviding: AnyObject {
    func suggestedFilename(date: Date, timeZone: TimeZone) -> String
}

extension CaptureFilenameProviding {
    func suggestedFilename() -> String {
        suggestedFilename(date: Date(), timeZone: .current)
    }
}

final class CaptureFilenameProvider: CaptureFilenameProviding {
    private let settingsStore: any PreferencesSettingsStoring
    private let renderer: FilenameTemplateRenderer

    init(
        settingsStore: any PreferencesSettingsStoring = PreferencesSettingsStore(),
        renderer: FilenameTemplateRenderer = FilenameTemplateRenderer()
    ) {
        self.settingsStore = settingsStore
        self.renderer = renderer
    }

    func suggestedFilename(date: Date, timeZone: TimeZone) -> String {
        let template = settingsStore.load().filenameTemplate
        return (try? renderer.filename(template: template, date: date, timeZone: timeZone))
            ?? (try? renderer.filename(
                template: PreferencesSettings.defaultFilenameTemplate,
                date: date,
                timeZone: timeZone
            ))
            ?? "xxsnap_截图.png"
    }
}

struct PreferencesStrings {
    let language: AppLanguage

    private var isEnglish: Bool { language == .english }

    var appTooltip: String { isEnglish ? "XxSnap Capture" : "xxsnap 截图" }
    var capture: String { isEnglish ? "Capture" : "截图" }
    var preferences: String { isEnglish ? "Preferences…" : "首选项…" }
    var checkForUpdates: String { isEnglish ? "Check for Updates…" : "检查更新…" }
    var aboutXxSnap: String { isEnglish ? "About" : "关于" }
    var quit: String { isEnglish ? "Quit" : "退出" }
    var windowTitle: String { isEnglish ? "XxSnap Preferences" : "XxSnap 首选项" }
    var general: String { isEnglish ? "General" : "通用" }
    var shortcuts: String { isEnglish ? "Shortcuts" : "快捷键" }
    var save: String { isEnglish ? "Save" : "保存" }
    var update: String { isEnglish ? "Update" : "更新" }
    var about: String { isEnglish ? "About" : "关于" }
    var launchAtLogin: String { isEnglish ? "Launch at login" : "开机自启动" }
    var launchAtLoginDetail: String {
        isEnglish ? "Run XxSnap automatically after signing in to macOS" : "登录 macOS 后自动运行 XxSnap"
    }
    var languageTitle: String { isEnglish ? "Language" : "语言" }
    var languageDetail: String {
        isEnglish ? "Menu and preferences update immediately" : "菜单和首选项立即切换"
    }
    var needsApproval: String {
        isEnglish ? "Allow XxSnap in System Settings to finish enabling this option." : "需要在系统设置中允许 XxSnap。"
    }
    var openSystemSettings: String { isEnglish ? "Open System Settings" : "打开系统设置" }
    var serviceUnavailable: String {
        isEnglish ? "The login item service is unavailable." : "开机启动服务不可用。"
    }
    var captureShortcut: String { isEnglish ? "Capture" : "截图" }
    var captureShortcutDetail: String {
        isEnglish ? "Start a new region capture" : "开始一次新的区域截图"
    }
    var restorePinShortcut: String {
        isEnglish ? "Restore most recently hidden pin" : "恢复最近隐藏的贴图"
    }
    var restorePinShortcutDetail: String {
        isEnglish ? "Temporarily unavailable during capture" : "截图进行中会暂时停用"
    }
    var record: String { isEnglish ? "Record" : "录制" }
    var recording: String { isEnglish ? "Press shortcut…" : "请按快捷键…" }
    var resetShortcuts: String { isEnglish ? "Restore Defaults" : "恢复默认快捷键" }
    var captureInProgress: String { isEnglish ? "Capture in progress" : "截图进行中" }
    var shortcutNeedsModifier: String {
        isEnglish ? "Include Command, Option, Control, or Shift." : "快捷键必须包含 Command、Option、Control 或 Shift。"
    }
    var shortcutConflict: String {
        isEnglish ? "This shortcut is already in use." : "该快捷键已被占用。"
    }
    var shortcutRegistrationFailed: String {
        isEnglish ? "The shortcut could not be registered." : "快捷键注册失败。"
    }
    var filenameTemplate: String { isEnglish ? "Filename template" : "文件名模板" }
    var filenameTemplateDetail: String {
        isEnglish ? "The PNG extension is added automatically" : "PNG 扩展名会自动补充"
    }
    var filenamePreview: String { isEnglish ? "Preview" : "预览" }
    var availableVariables: String {
        isEnglish ? "Variables: {yyyyMMdd}, {HHmmss}" : "可用变量：{yyyyMMdd}、{HHmmss}"
    }
    var checkAtLaunch: String { isEnglish ? "Check at launch" : "启动时检查更新" }
    var checkInterval: String { isEnglish ? "Automatic check interval" : "自动检查间隔" }
    var checkNow: String { isEnglish ? "Check Now" : "立即检查" }
    var upToDate: String { isEnglish ? "You're up to date" : "已是最新版本" }
    var hourSuffix: String { isEnglish ? "hours" : "小时" }
    var version: String { isEnglish ? "Version" : "版本" }
    var copyright: String { isEnglish ? "Copyright © 2026 xxsoft.com" : "版权所有 © 2026 xxsoft.com" }
    var saveFailed: String { isEnglish ? "The setting could not be saved." : "设置保存失败。" }
    var errorTitle: String { isEnglish ? "XxSnap Error" : "XxSnap 错误" }

    func filenameTemplateError(_ error: Error) -> String {
        guard let error = error as? FilenameTemplateError else {
            return error.localizedDescription
        }
        switch error {
        case .empty:
            return isEnglish ? "The filename template cannot be empty." : "文件名模板不能为空"
        case .pathSeparator:
            return isEnglish
                ? "The filename template cannot contain path separators."
                : "文件名模板不能包含路径分隔符"
        case .unknownVariable(let variable):
            return isEnglish ? "Unsupported variable: \(variable)" : "不支持的变量：\(variable)"
        }
    }
}
