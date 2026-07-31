import Foundation

struct PreferencesSettings: Codable, Equatable {
    static let allowedUpdateIntervals = [1, 6, 12, 24, 48, 72]
    static let defaultFilenameTemplate = "xxsnap_截图_{yyyyMMdd}_{HHmmss}"
    fileprivate static let legacyDefaultFilenameTemplate = "xxsnap 截图 {yyyyMMdd}-{HHmmss}"

    var filenameTemplate: String
    var checksForUpdatesAtLaunch: Bool
    var updateCheckIntervalHours: Int
    var disablesTextRecognitionSound: Bool
    var disablesTextRecognitionSuccessNotification: Bool
    var showsShortcutFeedback: Bool
    var showsSystemShortcutFeedback: Bool

    static let `default` = PreferencesSettings(
        filenameTemplate: defaultFilenameTemplate,
        checksForUpdatesAtLaunch: true,
        updateCheckIntervalHours: 24,
        disablesTextRecognitionSound: false,
        disablesTextRecognitionSuccessNotification: false,
        showsShortcutFeedback: true,
        showsSystemShortcutFeedback: true
    )

    init(
        filenameTemplate: String,
        checksForUpdatesAtLaunch: Bool,
        updateCheckIntervalHours: Int,
        disablesTextRecognitionSound: Bool = false,
        disablesTextRecognitionSuccessNotification: Bool = false,
        showsShortcutFeedback: Bool = true,
        showsSystemShortcutFeedback: Bool = true
    ) {
        self.filenameTemplate = filenameTemplate
        self.checksForUpdatesAtLaunch = checksForUpdatesAtLaunch
        self.updateCheckIntervalHours = Self.normalizedUpdateInterval(updateCheckIntervalHours)
        self.disablesTextRecognitionSound = disablesTextRecognitionSound
        self.disablesTextRecognitionSuccessNotification = disablesTextRecognitionSuccessNotification
        self.showsShortcutFeedback = showsShortcutFeedback
        self.showsSystemShortcutFeedback = showsSystemShortcutFeedback
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
        disablesTextRecognitionSound =
            (try? container.decode(Bool.self, forKey: .disablesTextRecognitionSound))
            ?? defaults.disablesTextRecognitionSound
        disablesTextRecognitionSuccessNotification =
            (try? container.decode(Bool.self, forKey: .disablesTextRecognitionSuccessNotification))
            ?? defaults.disablesTextRecognitionSuccessNotification
        showsShortcutFeedback =
            (try? container.decode(Bool.self, forKey: .showsShortcutFeedback))
            ?? defaults.showsShortcutFeedback
        showsSystemShortcutFeedback =
            (try? container.decode(Bool.self, forKey: .showsSystemShortcutFeedback))
            ?? defaults.showsSystemShortcutFeedback
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
    private let textRecognitionFeedbackDefaultsMigrationKey =
        "preferencesSettings.textRecognitionFeedbackDefaults.v2"
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> PreferencesSettings {
        let needsFeedbackDefaultsMigration = !userDefaults.bool(
            forKey: textRecognitionFeedbackDefaultsMigrationKey
        )
        guard
            let data = userDefaults.data(forKey: key),
            var settings = try? decoder.decode(PreferencesSettings.self, from: data)
        else {
            userDefaults.set(true, forKey: textRecognitionFeedbackDefaultsMigrationKey)
            return .default
        }
        var needsSave = false
        if settings.filenameTemplate == PreferencesSettings.legacyDefaultFilenameTemplate {
            settings.filenameTemplate = PreferencesSettings.defaultFilenameTemplate
            needsSave = true
        }
        if needsFeedbackDefaultsMigration {
            if settings.disablesTextRecognitionSound,
               settings.disablesTextRecognitionSuccessNotification {
                settings.disablesTextRecognitionSound = false
                settings.disablesTextRecognitionSuccessNotification = false
                needsSave = true
            }
            userDefaults.set(true, forKey: textRecognitionFeedbackDefaultsMigrationKey)
        }
        if needsSave {
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
    var fullScreenCapture: String { isEnglish ? "Full Screen Capture" : "全屏截图" }
    var captureText: String { isEnglish ? "Capture Text" : "识别文字" }
    var teachingPen: String { isEnglish ? "Presentation Pen" : "教笔" }
    var preferences: String { isEnglish ? "Settings..." : "偏好设置…" }
    var checkForUpdates: String { isEnglish ? "Check for Updates…" : "检查更新…" }
    var supportDeveloper: String {
        isEnglish ? "Support the Developer ☕️" : "支持开发者 ☕️"
    }
    var help: String { isEnglish ? "Help..." : "帮助…" }
    var exportDiagnostics: String {
        isEnglish ? "Export Diagnostic Logs…" : "导出诊断日志…"
    }
    var diagnosticExportPanelTitle: String {
        isEnglish ? "Export Diagnostic Logs" : "导出诊断日志"
    }
    var diagnosticExportSucceededTitle: String {
        isEnglish ? "Diagnostic Logs Exported" : "诊断日志已导出"
    }
    var diagnosticExportSucceededMessage: String {
        isEnglish
            ? "The diagnostic archive is ready to send to support."
            : "诊断压缩包已生成，可以发送给技术支持。"
    }
    var diagnosticExportFailedTitle: String {
        isEnglish ? "Unable to Export Diagnostic Logs" : "无法导出诊断日志"
    }
    var diagnosticExportFailedMessage: String {
        isEnglish
            ? "Please choose another location and try again."
            : "请选择其他位置后重试。"
    }
    var helpWindowTitle: String { isEnglish ? "XxSnap Help" : "XxSnap 帮助" }
    var helpLoadFailed: String {
        isEnglish
            ? "Help content is temporarily unavailable."
            : "帮助内容暂时无法打开"
    }
    var helpImageUnavailable: String {
        isEnglish
            ? "The image is temporarily unavailable."
            : "图片暂时无法显示"
    }
    var aboutXxSnap: String { isEnglish ? "About..." : "关于…" }
    var quit: String { isEnglish ? "Quit" : "退出" }
    var windowTitle: String { isEnglish ? "XxSnap Settings" : "XxSnap 设置" }
    var general: String { isEnglish ? "General" : "通用" }
    var shortcuts: String { isEnglish ? "Shortcuts" : "快捷键" }
    var save: String { isEnglish ? "Save" : "保存" }
    var update: String { isEnglish ? "Update" : "更新" }
    var donation: String { isEnglish ? "Donate" : "捐赠" }
    var about: String { isEnglish ? "About" : "关于" }
    var donationMessage: String {
        isEnglish
            ? "Support continued development with a donation."
            : "如果这个软件对您有所帮助，欢迎通过捐赠支持我们持续维护与改进 ☕️"
    }
    var contactEmail: String {
        isEnglish
            ? "Report Issue: zfc.2012@gmail.com"
            : "问题反馈或技术支持：zfc.2012@gmail.com"
    }
    var launchAtLogin: String { isEnglish ? "Launch at login" : "开机自启动" }
    var launchAtLoginDetail: String {
        isEnglish ? "Run XxSnap automatically after signing in to macOS" : "登录 macOS 后自动运行 XxSnap"
    }
    var languageTitle: String { isEnglish ? "Language" : "语言" }
    var languageDetail: String {
        isEnglish ? "Menu and settings update immediately" : "菜单和设置立即切换"
    }
    var disableTextRecognitionSound: String {
        isEnglish ? "Disable Capture Text sound" : "禁用识别文字提示音"
    }
    var disableTextRecognitionSoundDetail: String {
        isEnglish ? "Do not play a sound after successful recognition" : "识别成功后不播放提示音"
    }
    var disableTextRecognitionSuccessNotification: String {
        isEnglish ? "Disable Capture Text notification" : "禁用识别文字通知"
    }
    var disableTextRecognitionSuccessNotificationDetail: String {
        isEnglish
            ? "Hide successful recognition notifications; failures are always shown"
            : "不显示识别成功提示，识别失败仍会正常提示"
    }
    var showShortcutFeedback: String {
        isEnglish ? "Show XxSnap shortcuts" : "显示 XxSnap 快捷键"
    }
    var showShortcutFeedbackDetail: String {
        isEnglish
            ? "Show XxSnap shortcuts in the lower-right corner of the current screen"
            : "按 XxSnap 快捷键时，在当前屏幕右下角显示按键组合"
    }
    var showSystemShortcutFeedback: String {
        isEnglish ? "Show shortcuts from other apps" : "显示其他应用快捷键"
    }
    var showSystemShortcutFeedbackDetail: String {
        isEnglish
            ? "Shows combinations with ⌘, ⌃, or ⌥, plus Esc and function keys; normal typing is never recorded"
            : "显示包含 ⌘、⌃、⌥ 的组合键，以及 Esc 和功能键，不记录普通输入"
    }
    var inputMonitoringPermissionRequired: String {
        isEnglish
            ? "Allow XxSnap in Input Monitoring to use this option"
            : "需要在“输入监控”中允许 XxSnap"
    }
    var openInputMonitoringSettings: String {
        isEnglish ? "Open Input Monitoring" : "打开输入监控"
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
    var fullScreenCaptureShortcutDetail: String {
        isEnglish ? "Capture the entire visible desktop immediately" : "立即截取整个可见桌面"
    }
    var captureTextShortcutDetail: String {
        isEnglish ? "Capture text from a selected screen area" : "框选屏幕区域并识别文字"
    }
    var teachingPenShortcutDetail: String {
        isEnglish ? "Start full-screen presentation annotation" : "进入全屏教笔标注模式"
    }
    var restorePinShortcut: String {
        isEnglish ? "Restore most recently hidden pin" : "恢复最近隐藏的贴图"
    }
    var restorePinShortcutDetail: String {
        isEnglish ? "Temporarily unavailable during capture" : "截图进行中会暂时停用"
    }
    var record: String { isEnglish ? "Record" : "录制" }
    var recordShortcut: String { isEnglish ? "Record Shortcut" : "录制快捷键" }
    var recording: String { isEnglish ? "Press shortcut…" : "请按快捷键…" }
    var clearShortcut: String { isEnglish ? "Clear Shortcut" : "清除快捷键" }
    var resetShortcuts: String { isEnglish ? "Restore Defaults" : "恢复默认快捷键" }
    var captureInProgress: String { isEnglish ? "Capture in progress" : "截图进行中" }
    var shortcutNeedsModifier: String {
        isEnglish ? "Include Command, Option, Control, or Shift." : "快捷键必须包含 Command、Option、Control 或 Shift。"
    }
    var shortcutConflict: String {
        isEnglish ? "This shortcut is already in use." : "该快捷键已被占用。"
    }
    var replaceShortcut: String { isEnglish ? "Replace" : "覆盖" }
    var cancelShortcutReplacement: String { isEnglish ? "Cancel" : "取消" }
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
    var copyright: String { isEnglish ? "Copyright © 2026 xxsofts.com" : "版权所有 © 2026 xxsofts.com" }
    var saveFailed: String { isEnglish ? "The setting could not be saved." : "设置保存失败。" }
    var errorTitle: String { isEnglish ? "XxSnap Error" : "XxSnap 错误" }

    func hotKeyActionName(_ action: HotKeyAction) -> String {
        switch action {
        case .capture:
            return isEnglish ? "Capture" : "截图"
        case .fullScreenCapture:
            return isEnglish ? "Full Screen Capture" : "全屏截图"
        case .recognizeText:
            return isEnglish ? "Capture Text" : "识别文字"
        case .teachingPen:
            return isEnglish ? "Presentation Pen" : "教笔"
        case .restoreMostRecentlyHiddenPinnedImage:
            return isEnglish
                ? "Restore Most Recently Hidden Pin"
                : "恢复最近隐藏的贴图"
        }
    }

    func fixedShortcutName(_ shortcut: FixedToolbarShortcut) -> String {
        switch shortcut {
        case .cancel:
            return isEnglish
                ? "Cancel / Finish Editing"
                : "取消 / 完成编辑"
        case .rectangle, .polyline, .pen, .marker, .eyedropper, .mosaic,
             .text, .number, .magnifier, .eraser, .scroll, .undo, .redo,
             .save, .copy:
            return L10n(language: language).toolbarTooltip(for: shortcut.rawValue)
                ?? shortcut.rawValue
        }
    }

    func fixedShortcutConflict(_ shortcut: FixedToolbarShortcut) -> String {
        let actionName = fixedShortcutName(shortcut)
        return isEnglish
            ? "This shortcut conflicts with “\(actionName)”. It cannot be overridden. Choose another shortcut."
            : "与“\(actionName)”快捷键冲突，禁止覆盖，请重新设置！"
    }

    func configurableShortcutConflict(_ action: HotKeyAction) -> String {
        let actionName = hotKeyActionName(action)
        return isEnglish
            ? "This shortcut is assigned to “\(actionName)”. Replace it? The shortcut for “\(actionName)” will be cleared."
            : "该快捷键已分配给“\(actionName)”。是否覆盖？覆盖后将清空“\(actionName)”的快捷键。"
    }

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
