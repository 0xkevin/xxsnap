import Foundation

enum AppLanguage: String, Codable, Equatable {
    case zhHans
    case english
}

enum LicensePlan: String, Codable, Equatable {
    case trial
    case free
    case pro
}

struct LicenseState: Codable, Equatable {
    var plan: LicensePlan

    init(plan: LicensePlan = .trial) {
        self.plan = plan
    }
}

struct InterfaceFontSettings: Codable, Equatable {
    var familyName: String
    var pointSize: Double
    var weight: Double?
}

struct HotKeySettings: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
}

struct AppSettings: Codable, Equatable {
    static let minimumPaletteVisibleCount = 4
    static let maximumPaletteVisibleCount = 20

    var language: AppLanguage
    var interfaceFont: InterfaceFontSettings?
    var hotkeys: [String: HotKeySettings]
    var disabledHotkeys: Set<String>
    var license: LicenseState

    var paletteVisibleCount: Int {
        didSet {
            paletteVisibleCount = Self.clampedPaletteVisibleCount(paletteVisibleCount)
        }
    }

    static var `default`: AppSettings {
        AppSettings(
            language: .zhHans,
            paletteVisibleCount: maximumPaletteVisibleCount,
            interfaceFont: nil,
            hotkeys: [:],
            disabledHotkeys: [],
            license: LicenseState(plan: .trial)
        )
    }

    init(
        language: AppLanguage,
        paletteVisibleCount: Int,
        interfaceFont: InterfaceFontSettings?,
        hotkeys: [String: HotKeySettings],
        disabledHotkeys: Set<String> = [],
        license: LicenseState
    ) {
        self.language = language
        self.paletteVisibleCount = Self.clampedPaletteVisibleCount(paletteVisibleCount)
        self.interfaceFont = interfaceFont
        self.hotkeys = hotkeys
        self.disabledHotkeys = disabledHotkeys
        self.license = license
    }

    private enum CodingKeys: String, CodingKey {
        case language
        case interfaceFont
        case hotkeys
        case disabledHotkeys
        case license
        case paletteVisibleCount
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.default
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language)
            ?? defaults.language
        interfaceFont = try container.decodeIfPresent(
            InterfaceFontSettings.self,
            forKey: .interfaceFont
        )
        hotkeys = try container.decodeIfPresent(
            [String: HotKeySettings].self,
            forKey: .hotkeys
        ) ?? defaults.hotkeys
        disabledHotkeys = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .disabledHotkeys
        ) ?? defaults.disabledHotkeys
        license = try container.decodeIfPresent(LicenseState.self, forKey: .license)
            ?? defaults.license
        let decodedPaletteCount = try container.decodeIfPresent(
            Int.self,
            forKey: .paletteVisibleCount
        ) ?? defaults.paletteVisibleCount
        paletteVisibleCount = Self.clampedPaletteVisibleCount(decodedPaletteCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(language, forKey: .language)
        try container.encodeIfPresent(interfaceFont, forKey: .interfaceFont)
        try container.encode(hotkeys, forKey: .hotkeys)
        try container.encode(disabledHotkeys, forKey: .disabledHotkeys)
        try container.encode(license, forKey: .license)
        try container.encode(paletteVisibleCount, forKey: .paletteVisibleCount)
    }

    private static func clampedPaletteVisibleCount(_ count: Int) -> Int {
        min(maximumPaletteVisibleCount, max(minimumPaletteVisibleCount, count))
    }
}

protocol AppSettingsStoring: AnyObject {
    func load() -> AppSettings
    func save(_ settings: AppSettings) throws
}

final class SettingsStore: AppSettingsStoring {
    private let key = "appSettings.v1"
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> AppSettings {
        guard
            let data = userDefaults.data(forKey: key),
            let settings = try? decoder.decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    func save(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        userDefaults.set(data, forKey: key)
    }
}

enum Feature: String, Codable, Equatable {
    case scrollCapture
    case ocr
    case customPalette
    case customFont
    case customHotkeys
    case sketchStrokePatterns
}

struct FeatureGate {
    var license: LicenseState

    func isEnabled(_ feature: Feature) -> Bool {
        switch license.plan {
        case .trial, .pro:
            return true
        case .free:
            switch feature {
            case .scrollCapture, .ocr, .sketchStrokePatterns:
                return false
            case .customPalette, .customFont, .customHotkeys:
                return true
            }
        }
    }
}

struct L10n {
    enum Key {
        case toolbarScrollCapture
        case finishScrollCapture
        case cancel
        case scrollCaptureLowConfidence
        case scrollCaptureNoMovement
        case scrollCaptureResourceLimit
        case scrollCaptureFailure
        case longImageCopy
        case longImageSave
        case longImagePin
        case longImageFinish
        case longImageClose
        case longImageEditorTitle
        case longImageEditorUnavailable
        case longImageEditorUnavailableDetail
        case screenRecordingPermissionRequired
        case screenRecordingPermissionRestartDetail
        case screenRecordingPermissionMissing
        case screenRecordingPermissionSettingsDetail
        case openSystemSettings
        case later
        case confirm
        case colorSamplerCopyHex
        case colorSamplerCopyRgb
        case colorSamplerCopySuccess
        case colorSamplerSwitchMode
        case cornerRadius
    }

    var language: AppLanguage

    func text(_ key: Key) -> String {
        switch (language, key) {
        case (.zhHans, .toolbarScrollCapture):
            return "滚动截图"
        case (.zhHans, .finishScrollCapture):
            return "完成滚动截图"
        case (.zhHans, .cancel):
            return "取消"
        case (.zhHans, .scrollCaptureLowConfidence):
            return "暂无法识别到拼接位置，将继续尝试拼接"
        case (.zhHans, .scrollCaptureNoMovement):
            return "未检测到滚动，正在自动切换选区内的滚动位置"
        case (.zhHans, .scrollCaptureResourceLimit):
            return "已达到资源限制，滚动截图已暂停"
        case (.zhHans, .scrollCaptureFailure):
            return "截图失败，请重试"
        case (.zhHans, .longImageCopy): return "复制"
        case (.zhHans, .longImageSave): return "保存"
        case (.zhHans, .longImagePin): return "贴图"
        case (.zhHans, .longImageFinish): return "完成编辑"
        case (.zhHans, .longImageClose): return "关闭"
        case (.zhHans, .longImageEditorTitle): return "长截图编辑"
        case (.zhHans, .longImageEditorUnavailable): return "无法打开长截图编辑器"
        case (.zhHans, .longImageEditorUnavailableDetail):
            return "完整长截图已保留。是否立即保存为 PNG？"
        case (.zhHans, .screenRecordingPermissionRequired): return "需要录屏权限"
        case (.zhHans, .screenRecordingPermissionRestartDetail):
            return "请在系统设置中允许 xxsnap 录屏，然后退出并重新打开 xxsnap。"
        case (.zhHans, .screenRecordingPermissionMissing): return "xxsnap 没有录屏权限"
        case (.zhHans, .screenRecordingPermissionSettingsDetail):
            return "请在系统设置 > 隐私与安全性 > 录屏与系统录音中打开 xxsnap。打开后需要重启 xxsnap。"
        case (.zhHans, .openSystemSettings): return "打开系统设置"
        case (.zhHans, .later): return "稍后"
        case (.zhHans, .confirm): return "确定"
        case (.zhHans, .colorSamplerCopyHex):
            return "按 C 复制HEX颜色值"
        case (.zhHans, .colorSamplerCopyRgb):
            return "按 C 复制RGB颜色值"
        case (.zhHans, .colorSamplerCopySuccess): return "复制成功"
        case (.zhHans, .colorSamplerSwitchMode): return "按 Shift 切换 RGB/HEX"
        case (.zhHans, .cornerRadius): return "圆角半径"
        case (.english, .toolbarScrollCapture):
            return "Scroll Capture"
        case (.english, .finishScrollCapture):
            return "Finish Scroll Capture"
        case (.english, .cancel):
            return "Cancel"
        case (.english, .scrollCaptureLowConfidence):
            return "Overlap not found yet. Continuing to stitch."
        case (.english, .scrollCaptureNoMovement):
            return "No movement detected. Trying another point inside the selection."
        case (.english, .scrollCaptureResourceLimit):
            return "Resource limit reached. Scroll capture is paused."
        case (.english, .scrollCaptureFailure):
            return "Capture failed. Please try again."
        case (.english, .longImageCopy): return "Copy"
        case (.english, .longImageSave): return "Save"
        case (.english, .longImagePin): return "Pin"
        case (.english, .longImageFinish): return "Finish"
        case (.english, .longImageClose): return "Close"
        case (.english, .longImageEditorTitle): return "Long Capture Editor"
        case (.english, .longImageEditorUnavailable): return "Unable to Open Long Capture Editor"
        case (.english, .longImageEditorUnavailableDetail):
            return "The complete long capture is preserved. Save it as PNG now?"
        case (.english, .screenRecordingPermissionRequired): return "Screen Recording Permission Required"
        case (.english, .screenRecordingPermissionRestartDetail):
            return "Allow xxsnap to record the screen in System Settings, then quit and reopen xxsnap."
        case (.english, .screenRecordingPermissionMissing): return "xxsnap Cannot Record the Screen"
        case (.english, .screenRecordingPermissionSettingsDetail):
            return "Enable xxsnap in System Settings > Privacy & Security > Screen & System Audio Recording, then restart xxsnap."
        case (.english, .openSystemSettings): return "Open System Settings"
        case (.english, .later): return "Later"
        case (.english, .confirm): return "OK"
        case (.english, .colorSamplerCopyHex):
            return "Press C to copy HEX"
        case (.english, .colorSamplerCopyRgb):
            return "Press C to copy RGB"
        case (.english, .colorSamplerCopySuccess): return "Copied"
        case (.english, .colorSamplerSwitchMode): return "Press Shift to switch RGB/HEX"
        case (.english, .cornerRadius): return "Corner Radius"
        }
    }

    func toolbarTooltip(for identifier: String) -> String? {
        let chinese = [
            "rectangle": "形状",
            "polyline": "箭头线",
            "pen": "画笔",
            "marker": "荧光笔",
            "eyedropper": "取色 ｜ 测距",
            "mosaic": "马赛克",
            "mosaicBlur": "高斯",
            "mosaicPixel": "马赛克",
            "mosaicSmallDot": "细",
            "mosaicMediumDot": "中",
            "mosaicLargeDot": "粗",
            "mosaicRectangle": "矩形模糊",
            "text": "文字",
            "number": "序号",
            "magnifier": "放大镜",
            "eraser": "橡皮擦",
            "eraserPoint": "橡皮擦",
            "eraserRectangle": "矩形擦除",
            "eraserClearAll": "清除所有",
            "undo": "撤销",
            "redo": "重做",
            "cancel": "取消",
            "pin": "贴图",
            "save": "保存",
            "copy": "复制到剪切板",
            "finishEditing": "完成编辑",
            "scroll": "滚动截图",
            "strokeWidthThin": "细",
            "strokeWidthMedium": "中",
            "strokeWidthThick": "粗",
            "fill": "填充",
            "shapeRectangle": "方形",
            "shapeEllipse": "圆形",
            "strokeStyle": "线条类型",
            "textBold": "加粗",
            "textItalic": "斜体",
            "textOutline": "描边",
            "startArrowType": "开始箭头",
            "endArrowType": "结束箭头",
            "customColor": "自定义颜色",
            "cornerStyle": "直角/圆角切换",
            "aspectRatioLockedOn": "锁定长宽比(开)",
            "aspectRatioLockedOff": "锁定长宽比(关)",
            "refreshCapture": "刷新截图",
        ]
        let english = [
            "rectangle": "Shape",
            "polyline": "Arrow",
            "pen": "Pen",
            "marker": "Highlighter",
            "eyedropper": "Color Picker | Measure",
            "mosaic": "Redact",
            "mosaicBlur": "Gaussian Blur",
            "mosaicPixel": "Pixelate",
            "mosaicSmallDot": "Thin",
            "mosaicMediumDot": "Medium",
            "mosaicLargeDot": "Thick",
            "mosaicRectangle": "Rectangle Blur",
            "text": "Text",
            "number": "Number",
            "magnifier": "Magnifier",
            "eraser": "Eraser",
            "eraserPoint": "Eraser",
            "eraserRectangle": "Rectangle Eraser",
            "eraserClearAll": "Clear All",
            "undo": "Undo",
            "redo": "Redo",
            "cancel": "Cancel",
            "pin": "Pin",
            "save": "Save",
            "copy": "Copy to Clipboard",
            "finishEditing": "Finish Editing",
            "scroll": "Scroll Capture",
            "strokeWidthThin": "Thin",
            "strokeWidthMedium": "Medium",
            "strokeWidthThick": "Thick",
            "fill": "Fill",
            "shapeRectangle": "Rectangle",
            "shapeEllipse": "Ellipse",
            "strokeStyle": "Line Style",
            "textBold": "Bold",
            "textItalic": "Italic",
            "textOutline": "Outline",
            "startArrowType": "Start Arrow",
            "endArrowType": "End Arrow",
            "customColor": "Custom Color",
            "cornerStyle": "Square/Rounded Corners",
            "aspectRatioLockedOn": "Lock Aspect Ratio (On)",
            "aspectRatioLockedOff": "Lock Aspect Ratio (Off)",
            "refreshCapture": "Refresh Capture",
        ]
        return (language == .zhHans ? chinese : english)[identifier]
    }

    func unavailableFeatureMessage(_ feature: String) -> String {
        language == .zhHans ? "\(feature)功能开发中。" : "\(feature) is under development."
    }
}
