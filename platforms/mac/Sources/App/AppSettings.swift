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
            license: LicenseState(plan: .trial)
        )
    }

    init(
        language: AppLanguage,
        paletteVisibleCount: Int,
        interfaceFont: InterfaceFontSettings?,
        hotkeys: [String: HotKeySettings],
        license: LicenseState
    ) {
        self.language = language
        self.paletteVisibleCount = Self.clampedPaletteVisibleCount(paletteVisibleCount)
        self.interfaceFont = interfaceFont
        self.hotkeys = hotkeys
        self.license = license
    }

    private static func clampedPaletteVisibleCount(_ count: Int) -> Int {
        min(maximumPaletteVisibleCount, max(minimumPaletteVisibleCount, count))
    }
}

final class SettingsStore {
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
        case colorSamplerCopyHex
        case colorSamplerCopyRgb
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
        case (.zhHans, .colorSamplerCopyHex):
            return "按 C 复制HEX颜色值"
        case (.zhHans, .colorSamplerCopyRgb):
            return "按 C 复制RGB颜色值"
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
        case (.english, .colorSamplerCopyHex):
            return "Press C to copy HEX"
        case (.english, .colorSamplerCopyRgb):
            return "Press C to copy RGB"
        }
    }
}
