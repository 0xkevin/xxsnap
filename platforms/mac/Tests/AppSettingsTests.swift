import XCTest
@testable import xxsnap

final class AppSettingsTests: XCTestCase {
    func testBundleIdentityUsesXxsnap() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.xxsnap.mac")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "XxSnap")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "XxSnap")
    }

    func testAppDelegateAllowsProgrammaticTerminationForCleanRestarts() {
        let delegate = AppDelegate()

        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateNow)
    }

    func testDefaultSettingsUseChineseAndFullPalette() {
        let settings = AppSettings.default

        XCTAssertEqual(settings.language, .zhHans)
        XCTAssertEqual(settings.paletteVisibleCount, 20)
        XCTAssertNil(settings.interfaceFont)
        XCTAssertTrue(settings.hotkeys.isEmpty)
        XCTAssertEqual(settings.license.plan, .trial)
    }

    func testPaletteVisibleCountIsClampedToSupportedRange() {
        var settings = AppSettings.default

        settings.paletteVisibleCount = 1
        XCTAssertEqual(settings.paletteVisibleCount, 4)

        settings.paletteVisibleCount = 30
        XCTAssertEqual(settings.paletteVisibleCount, 20)
    }

    func testSettingsStorePersistsSettings() throws {
        let suiteName = "com.snipory.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = SettingsStore(userDefaults: defaults)

        var settings = AppSettings.default
        settings.language = .english
        settings.paletteVisibleCount = 8
        try store.save(settings)

        XCTAssertEqual(store.load().language, .english)
        XCTAssertEqual(store.load().paletteVisibleCount, 8)
    }

    func testFeatureGateKeepsTrialFullyOpenAndRestrictsFreeCoreFeatures() {
        XCTAssertTrue(FeatureGate(license: LicenseState(plan: .trial)).isEnabled(.scrollCapture))
        XCTAssertTrue(FeatureGate(license: LicenseState(plan: .trial)).isEnabled(.ocr))
        XCTAssertTrue(FeatureGate(license: LicenseState(plan: .trial)).isEnabled(.sketchStrokePatterns))
        XCTAssertTrue(FeatureGate(license: LicenseState(plan: .free)).isEnabled(.customPalette))
        XCTAssertFalse(FeatureGate(license: LicenseState(plan: .free)).isEnabled(.scrollCapture))
        XCTAssertFalse(FeatureGate(license: LicenseState(plan: .free)).isEnabled(.ocr))
        XCTAssertFalse(FeatureGate(license: LicenseState(plan: .free)).isEnabled(.sketchStrokePatterns))
        XCTAssertTrue(FeatureGate(license: LicenseState(plan: .pro)).isEnabled(.scrollCapture))
        XCTAssertTrue(FeatureGate(license: LicenseState(plan: .pro)).isEnabled(.sketchStrokePatterns))
    }

    func testL10nDefaultsToChineseAndSupportsEnglish() {
        XCTAssertEqual(L10n(language: .zhHans).text(.toolbarScrollCapture), "滚动截图")
        XCTAssertEqual(L10n(language: .english).text(.toolbarScrollCapture), "Scroll Capture")
        XCTAssertEqual(L10n(language: .zhHans).text(.colorSamplerCopyHex), "按 C 复制HEX颜色值")
        XCTAssertEqual(L10n(language: .zhHans).text(.colorSamplerCopyRgb), "按 C 复制RGB颜色值")
        XCTAssertEqual(L10n(language: .english).text(.colorSamplerCopyHex), "Press C to copy HEX")
        XCTAssertEqual(L10n(language: .english).text(.colorSamplerCopyRgb), "Press C to copy RGB")
    }
}
