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
}

struct FeatureGate {
    var license: LicenseState

    func isEnabled(_ feature: Feature) -> Bool {
        switch license.plan {
        case .trial, .pro:
            return true
        case .free:
            switch feature {
            case .scrollCapture, .ocr:
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
        case colorSamplerCopyHex
        case colorSamplerCopyRgb
    }

    var language: AppLanguage

    func text(_ key: Key) -> String {
        switch (language, key) {
        case (.zhHans, .toolbarScrollCapture):
            return "滚动截图"
        case (.zhHans, .colorSamplerCopyHex):
            return "按 C 复制HEX颜色值"
        case (.zhHans, .colorSamplerCopyRgb):
            return "按 C 复制RGB颜色值"
        case (.english, .toolbarScrollCapture):
            return "Scroll Capture"
        case (.english, .colorSamplerCopyHex):
            return "Press C to copy HEX"
        case (.english, .colorSamplerCopyRgb):
            return "Press C to copy RGB"
        }
    }
}
