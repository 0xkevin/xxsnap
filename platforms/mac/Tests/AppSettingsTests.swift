import Carbon.HIToolbox
import CoreImage.CIFilterBuiltins
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
        XCTAssertTrue(settings.disabledHotkeys.isEmpty)
    }

    func testCaptureCoordinatorResolvesConfiguredPinFunctionKey() throws {
        var settings = AppSettings.default
        settings.hotkeys[HotKeyAction.restoreMostRecentlyHiddenPinnedImage.rawValue] =
            HotKeySettings(keyCode: UInt32(kVK_F1), modifiers: 0)

        let shortcut = try XCTUnwrap(
            CaptureCoordinator.pinToolbarShortcut(from: settings)
        )

        XCTAssertEqual(shortcut.displayText, "F1")
        XCTAssertEqual(
            CaptureCoordinator.pinToolbarShortcut(from: .default),
            SelectionToolbarState.defaultPinShortcut
        )
    }

    func testCaptureCoordinatorClearsDisabledPinShortcut() {
        var settings = AppSettings.default
        settings.hotkeys[HotKeyAction.restoreMostRecentlyHiddenPinnedImage.rawValue] =
            HotKeySettings(keyCode: UInt32(kVK_F1), modifiers: 0)
        settings.disabledHotkeys.insert(
            HotKeyAction.restoreMostRecentlyHiddenPinnedImage.rawValue
        )

        XCTAssertNil(CaptureCoordinator.pinToolbarShortcut(from: settings))
    }

    func testSettingsStoreDecodesExistingSettingsWithoutDisabledHotKeys() {
        let suiteName = "com.snipory.tests.settings.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(
            Data(
                """
                {
                  "language": "english",
                  "paletteVisibleCount": 8,
                  "hotkeys": {},
                  "license": { "plan": "trial" }
                }
                """.utf8
            ),
            forKey: "appSettings.v1"
        )

        let settings = SettingsStore(userDefaults: defaults).load()

        XCTAssertEqual(settings.language, .english)
        XCTAssertEqual(settings.paletteVisibleCount, 8)
        XCTAssertTrue(settings.disabledHotkeys.isEmpty)
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

    func testPreferencesSettingsDefaultsAndPersistence() throws {
        let suiteName = "com.xxsnap.tests.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = PreferencesSettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.load(), .default)
        XCTAssertFalse(PreferencesSettings.default.disablesTextRecognitionSound)
        XCTAssertFalse(
            PreferencesSettings.default.disablesTextRecognitionSuccessNotification
        )
        XCTAssertTrue(PreferencesSettings.default.showsShortcutFeedback)
        XCTAssertTrue(PreferencesSettings.default.showsSystemShortcutFeedback)

        let settings = PreferencesSettings(
            filenameTemplate: "Capture {yyyyMMdd}_{HHmmss}",
            checksForUpdatesAtLaunch: false,
            updateCheckIntervalHours: 6,
            disablesTextRecognitionSound: false,
            disablesTextRecognitionSuccessNotification: false
        )
        try store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testPreferencesSettingsRecoversOnlyInvalidFields() {
        let suiteName = "com.xxsnap.tests.preferences.partial.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(
            Data(
                """
                {
                  "filenameTemplate": "Archive {yyyyMMdd}",
                  "checksForUpdatesAtLaunch": "invalid",
                  "updateCheckIntervalHours": 6
                }
                """.utf8
            ),
            forKey: "preferencesSettings.v1"
        )

        let settings = PreferencesSettingsStore(userDefaults: defaults).load()

        XCTAssertEqual(settings.filenameTemplate, "Archive {yyyyMMdd}")
        XCTAssertEqual(
            settings.checksForUpdatesAtLaunch,
            PreferencesSettings.default.checksForUpdatesAtLaunch
        )
        XCTAssertEqual(settings.updateCheckIntervalHours, 6)
        XCTAssertFalse(settings.disablesTextRecognitionSound)
        XCTAssertFalse(settings.disablesTextRecognitionSuccessNotification)
        XCTAssertTrue(settings.showsShortcutFeedback)
        XCTAssertTrue(settings.showsSystemShortcutFeedback)
    }

    func testPreferencesSettingsMigratesOldEnabledDisableSwitchDefaultsOnce() throws {
        let suiteName = "com.xxsnap.tests.preferences.feedback-migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(
            Data(
                """
                {
                  "filenameTemplate": "xxsnap_截图_{yyyyMMdd}_{HHmmss}",
                  "checksForUpdatesAtLaunch": true,
                  "updateCheckIntervalHours": 24,
                  "disablesTextRecognitionSound": true,
                  "disablesTextRecognitionSuccessNotification": true
                }
                """.utf8
            ),
            forKey: "preferencesSettings.v1"
        )
        let store = PreferencesSettingsStore(userDefaults: defaults)

        var settings = store.load()
        XCTAssertFalse(settings.disablesTextRecognitionSound)
        XCTAssertFalse(settings.disablesTextRecognitionSuccessNotification)

        settings.disablesTextRecognitionSound = true
        settings.disablesTextRecognitionSuccessNotification = true
        try store.save(settings)

        XCTAssertTrue(store.load().disablesTextRecognitionSound)
        XCTAssertTrue(store.load().disablesTextRecognitionSuccessNotification)
    }

    func testFilenameTemplateRendererUsesSupportedVariablesAndAddsPng() throws {
        let calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 7,
            day: 23,
            hour: 16,
            minute: 8,
            second: 35
        ))!

        let filename = try FilenameTemplateRenderer().filename(
            template: PreferencesSettings.defaultFilenameTemplate,
            date: date,
            timeZone: timeZone
        )

        XCTAssertEqual(filename, "xxsnap_截图_20260723_160835.png")
    }

    func testFilenameTemplateRendererRejectsUnsafeOrUnknownValues() {
        let renderer = FilenameTemplateRenderer()

        XCTAssertThrowsError(try renderer.filename(template: "   ")) {
            XCTAssertEqual($0 as? FilenameTemplateError, .empty)
        }
        XCTAssertThrowsError(try renderer.filename(template: "folder/name")) {
            XCTAssertEqual($0 as? FilenameTemplateError, .pathSeparator)
        }
        XCTAssertThrowsError(try renderer.filename(template: "capture {date}")) {
            XCTAssertEqual($0 as? FilenameTemplateError, .unknownVariable("{date}"))
        }
    }

    func testCaptureFilenameProviderFallsBackWhenStoredTemplateIsInvalid() {
        let store = FakePreferencesSettingsStore()
        store.settings.filenameTemplate = "invalid/name"
        let provider = CaptureFilenameProvider(settingsStore: store)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 7,
            day: 23,
            hour: 16,
            minute: 8,
            second: 35
        ))!

        XCTAssertEqual(
            provider.suggestedFilename(date: date, timeZone: timeZone),
            "xxsnap_截图_20260723_160835.png"
        )
    }

    func testPreferencesSettingsMigratesLegacyDefaultFilenameTemplate() throws {
        let suiteName = "com.xxsnap.tests.preferences.filename-migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(
            try JSONEncoder().encode(PreferencesSettings(
                filenameTemplate: "xxsnap 截图 {yyyyMMdd}-{HHmmss}",
                checksForUpdatesAtLaunch: true,
                updateCheckIntervalHours: 24
            )),
            forKey: "preferencesSettings.v1"
        )

        let store = PreferencesSettingsStore(userDefaults: defaults)

        XCTAssertEqual(
            store.load().filenameTemplate,
            "xxsnap_截图_{yyyyMMdd}_{HHmmss}"
        )
        XCTAssertEqual(
            store.load().filenameTemplate,
            PreferencesSettings.defaultFilenameTemplate
        )
    }

    @MainActor
    func testHotKeyControllerPersistsSuccessfulChanges() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)
        let replacement = HotKeySettings(
            keyCode: HotKeyAction.capture.defaultSettings.keyCode + 2,
            modifiers: HotKeyAction.capture.defaultSettings.modifiers
        )

        assertHotKeySuccess(controller.apply(replacement, to: .capture))
        XCTAssertEqual(controller.configuredHotKey(for: .capture), replacement)
        XCTAssertEqual(store.settings.hotkeys[HotKeyAction.capture.rawValue], replacement)
        XCTAssertEqual(registrar.registered[.capture], replacement)
    }

    @MainActor
    func testHotKeyControllerAcceptsStandaloneFunctionKeys() {
        for keyCode in [kVK_F1, kVK_F12] {
            let store = FakeAppSettingsStore()
            let registrar = FakeGlobalHotKeyRegistrar()
            let controller = makeHotKeyController(store: store, registrar: registrar)
            let shortcut = HotKeySettings(keyCode: UInt32(keyCode), modifiers: 0)

            assertHotKeySuccess(controller.apply(shortcut, to: .capture))
            XCTAssertEqual(controller.registeredHotKey(for: .capture), shortcut)
            XCTAssertEqual(store.settings.hotkeys[HotKeyAction.capture.rawValue], shortcut)
        }
    }

    @MainActor
    func testHotKeyControllerStillRejectsStandaloneOrdinaryKeys() {
        for keyCode in [kVK_ANSI_Q, kVK_ANSI_1] {
            let store = FakeAppSettingsStore()
            let registrar = FakeGlobalHotKeyRegistrar()
            let controller = makeHotKeyController(store: store, registrar: registrar)
            let shortcut = HotKeySettings(keyCode: UInt32(keyCode), modifiers: 0)

            assertHotKeyFailure(
                controller.apply(shortcut, to: .capture),
                equals: .missingModifier
            )
        }
    }

    @MainActor
    func testHotKeyControllerRejectsFixedToolbarShortcutWithoutChangingState() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)
        let shortcut = HotKeySettings(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey)
        )

        assertHotKeyFailure(
            controller.apply(shortcut, to: .capture),
            equals: .fixedToolbarConflict(.save)
        )
        XCTAssertEqual(
            controller.configuredHotKey(for: .capture),
            HotKeyAction.capture.defaultSettings
        )
        XCTAssertEqual(
            controller.registeredHotKey(for: .capture),
            HotKeyAction.capture.defaultSettings
        )
        XCTAssertEqual(
            registrar.registered[.capture],
            HotKeyAction.capture.defaultSettings
        )
        XCTAssertNil(store.settings.hotkeys[HotKeyAction.capture.rawValue])
    }

    @MainActor
    func testHotKeyControllerRejectsCommandEscapeWithoutChangingState() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)
        let originalConfigured = controller.configuredHotKey(for: .capture)
        let originalRegistered = controller.registeredHotKey(for: .capture)
        let originalRegistrations = registrar.registered
        let originalSettings = store.settings

        assertHotKeyFailure(
            controller.apply(
                HotKeySettings(
                    keyCode: UInt32(kVK_Escape),
                    modifiers: UInt32(cmdKey)
                ),
                to: .capture
            ),
            equals: .fixedToolbarConflict(.cancel)
        )

        XCTAssertEqual(controller.configuredHotKey(for: .capture), originalConfigured)
        XCTAssertEqual(controller.registeredHotKey(for: .capture), originalRegistered)
        XCTAssertEqual(registrar.registered, originalRegistrations)
        XCTAssertEqual(store.settings, originalSettings)
    }

    @MainActor
    func testHotKeyControllerDisablesAndReenablesIndividualShortcut() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)

        assertHotKeySuccess(controller.disable(.capture))

        XCTAssertFalse(controller.isHotKeyEnabled(for: .capture))
        XCTAssertNil(controller.registeredHotKey(for: .capture))
        XCTAssertNil(registrar.registered[.capture])
        XCTAssertTrue(store.settings.disabledHotkeys.contains(HotKeyAction.capture.rawValue))

        let replacement = HotKeySettings(
            keyCode: HotKeyAction.capture.defaultSettings.keyCode + 2,
            modifiers: HotKeyAction.capture.defaultSettings.modifiers
        )
        assertHotKeySuccess(controller.apply(replacement, to: .capture))

        XCTAssertTrue(controller.isHotKeyEnabled(for: .capture))
        XCTAssertEqual(controller.registeredHotKey(for: .capture), replacement)
        XCTAssertFalse(store.settings.disabledHotkeys.contains(HotKeyAction.capture.rawValue))
    }

    @MainActor
    func testDisabledHotKeyRemainsDisabledAfterControllerRestarts() {
        let store = FakeAppSettingsStore()
        store.settings.disabledHotkeys = [HotKeyAction.teachingPen.rawValue]
        let registrar = FakeGlobalHotKeyRegistrar()

        let controller = makeHotKeyController(store: store, registrar: registrar)

        XCTAssertFalse(controller.isHotKeyEnabled(for: .teachingPen))
        XCTAssertNil(controller.registeredHotKey(for: .teachingPen))
        XCTAssertNil(registrar.registered[.teachingPen])
    }

    @MainActor
    func testTeachingPenUsesCommandTwoAndRemainsRegisteredDuringCapture() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)

        XCTAssertEqual(
            HotKeyFormatter.displayString(HotKeyAction.teachingPen.defaultSettings),
            "⌘2"
        )
        XCTAssertEqual(
            controller.registeredHotKey(for: .teachingPen),
            HotKeyAction.teachingPen.defaultSettings
        )

        controller.setCaptureSessionActive(true)

        XCTAssertEqual(
            controller.registeredHotKey(for: .teachingPen),
            HotKeyAction.teachingPen.defaultSettings
        )
    }

    @MainActor
    func testGlobalHotKeyShowsFeedbackBeforeRunningExistingAction() async {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        var events: [String] = []
        let controller = CaptureHotKeyController(
            settingsStore: store,
            registrar: registrar,
            captureHandler: {
                events.append("action")
            },
            hotKeyFeedbackHandler: { settings in
                events.append("feedback:\(HotKeyFormatter.displayString(settings))")
            },
            teachingPenHandler: {},
            restorePinnedImageHandler: {}
        )

        registrar.onHotKeyPressed?(.capture)
        for _ in 0..<10 where events.count < 2 {
            await Task.yield()
        }

        XCTAssertEqual(events, ["feedback:⌘`", "action"])
        _ = controller
    }

    @MainActor
    func testTeachingPenDefaultDoesNotReplaceStoredCommandTwoShortcut() {
        let store = FakeAppSettingsStore()
        let storedRestoreShortcut = HotKeyAction.teachingPen.defaultSettings
        store.settings.hotkeys = [
            HotKeyAction.capture.rawValue: HotKeyAction.capture.defaultSettings,
            HotKeyAction.restoreMostRecentlyHiddenPinnedImage.rawValue: storedRestoreShortcut,
        ]
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)

        XCTAssertEqual(
            controller.registeredHotKey(for: .restoreMostRecentlyHiddenPinnedImage),
            storedRestoreShortcut
        )
        XCTAssertNil(controller.registeredHotKey(for: .teachingPen))
        XCTAssertEqual(controller.errors[.teachingPen], .duplicate)
    }

    @MainActor
    func testTeachingPenRegistersImmediatelyAfterStoredCommandTwoIsReleased() {
        let store = FakeAppSettingsStore()
        let storedRestoreShortcut = HotKeyAction.teachingPen.defaultSettings
        store.settings.hotkeys = [
            HotKeyAction.capture.rawValue: HotKeyAction.capture.defaultSettings,
            HotKeyAction.restoreMostRecentlyHiddenPinnedImage.rawValue: storedRestoreShortcut,
        ]
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)
        let replacementRestoreShortcut = HotKeySettings(
            keyCode: UInt32(kVK_ANSI_4),
            modifiers: HotKeyAction.restoreMostRecentlyHiddenPinnedImage.defaultSettings.modifiers
        )

        assertHotKeySuccess(controller.apply(
            replacementRestoreShortcut,
            to: .restoreMostRecentlyHiddenPinnedImage
        ))

        XCTAssertEqual(
            controller.registeredHotKey(for: .teachingPen),
            HotKeyAction.teachingPen.defaultSettings
        )
        XCTAssertNil(controller.errors[.teachingPen])
    }

    @MainActor
    func testHotKeyControllerRejectsDuplicatesWithoutChangingRegistration() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)
        let restoreShortcut = controller.configuredHotKey(
            for: .restoreMostRecentlyHiddenPinnedImage
        )

        assertHotKeyFailure(
            controller.apply(restoreShortcut, to: .capture),
            equals: .configurableConflict(.restoreMostRecentlyHiddenPinnedImage)
        )
        XCTAssertEqual(
            controller.configuredHotKey(for: .capture),
            HotKeyAction.capture.defaultSettings
        )
        XCTAssertEqual(registrar.registered[.capture], HotKeyAction.capture.defaultSettings)
    }

    @MainActor
    func testHotKeyControllerReportsConfigurableConflictBeforeReplacement() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)
        let occupied = controller.configuredHotKey(for: .recognizeText)
        let originalRegistrations = registrar.registered

        assertHotKeyFailure(
            controller.apply(occupied, to: .capture),
            equals: .configurableConflict(.recognizeText)
        )

        XCTAssertEqual(
            controller.configuredHotKey(for: .capture),
            HotKeyAction.capture.defaultSettings
        )
        XCTAssertEqual(controller.configuredHotKey(for: .recognizeText), occupied)
        XCTAssertTrue(controller.isHotKeyEnabled(for: .capture))
        XCTAssertTrue(controller.isHotKeyEnabled(for: .recognizeText))
        XCTAssertEqual(registrar.registered, originalRegistrations)
    }

    @MainActor
    func testHotKeyControllerReplacesConfigurableConflictAndClearsPreviousAction() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)
        let occupied = controller.configuredHotKey(for: .recognizeText)

        assertHotKeySuccess(
            controller.apply(occupied, to: .capture, replacing: .recognizeText)
        )

        XCTAssertEqual(controller.registeredHotKey(for: .capture), occupied)
        XCTAssertEqual(registrar.registered[.capture], occupied)
        XCTAssertFalse(controller.isHotKeyEnabled(for: .recognizeText))
        XCTAssertNil(controller.registeredHotKey(for: .recognizeText))
        XCTAssertNil(registrar.registered[.recognizeText])
        XCTAssertTrue(
            store.settings.disabledHotkeys.contains(HotKeyAction.recognizeText.rawValue)
        )
        XCTAssertNil(store.settings.hotkeys[HotKeyAction.recognizeText.rawValue])
    }

    @MainActor
    func testHotKeyControllerRollsBackBothActionsWhenReplacementPersistenceFails() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)
        let oldCapture = controller.configuredHotKey(for: .capture)
        let occupied = controller.configuredHotKey(for: .recognizeText)
        let originalStoreSettings = store.settings
        let originalRegistrations = registrar.registered
        store.shouldFailSave = true

        assertHotKeyFailure(
            controller.apply(occupied, to: .capture, replacing: .recognizeText),
            equals: .persistenceFailed
        )

        XCTAssertEqual(controller.configuredHotKey(for: .capture), oldCapture)
        XCTAssertEqual(controller.configuredHotKey(for: .recognizeText), occupied)
        XCTAssertTrue(controller.isHotKeyEnabled(for: .capture))
        XCTAssertTrue(controller.isHotKeyEnabled(for: .recognizeText))
        XCTAssertEqual(registrar.registered, originalRegistrations)
        XCTAssertEqual(store.settings, originalStoreSettings)
        XCTAssertNil(controller.errors[.capture])
        XCTAssertNil(controller.errors[.recognizeText])
    }

    @MainActor
    func testHotKeyControllerRollsBackBothActionsWhenReplacementRegistrationFails() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)
        let oldCapture = controller.configuredHotKey(for: .capture)
        let occupied = controller.configuredHotKey(for: .recognizeText)
        let originalStoreSettings = store.settings
        let originalRegistrations = registrar.registered
        registrar.failedSettings[.capture] = occupied

        assertHotKeyFailure(
            controller.apply(occupied, to: .capture, replacing: .recognizeText),
            equals: .registrationFailed(FakeGlobalHotKeyRegistrar.failureStatus)
        )

        XCTAssertEqual(controller.configuredHotKey(for: .capture), oldCapture)
        XCTAssertEqual(controller.configuredHotKey(for: .recognizeText), occupied)
        XCTAssertTrue(controller.isHotKeyEnabled(for: .capture))
        XCTAssertTrue(controller.isHotKeyEnabled(for: .recognizeText))
        XCTAssertEqual(registrar.registered, originalRegistrations)
        XCTAssertEqual(store.settings, originalStoreSettings)
        XCTAssertNil(controller.errors[.capture])
        XCTAssertNil(controller.errors[.recognizeText])
    }

    @MainActor
    func testHotKeyControllerRollsBackWhenPersistenceFails() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)
        let replacement = HotKeySettings(
            keyCode: HotKeyAction.capture.defaultSettings.keyCode + 2,
            modifiers: HotKeyAction.capture.defaultSettings.modifiers
        )
        store.shouldFailSave = true

        assertHotKeyFailure(
            controller.apply(replacement, to: .capture),
            equals: .persistenceFailed
        )
        XCTAssertEqual(
            controller.configuredHotKey(for: .capture),
            HotKeyAction.capture.defaultSettings
        )
        XCTAssertEqual(registrar.registered[.capture], HotKeyAction.capture.defaultSettings)
    }

    @MainActor
    func testHotKeyControllerDisablesRestoreShortcutDuringCapture() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)

        controller.setCaptureSessionActive(true)

        XCTAssertNil(controller.registeredHotKey(for: .restoreMostRecentlyHiddenPinnedImage))
        assertHotKeyFailure(
            controller.apply(HotKeyAction.capture.defaultSettings, to: .capture),
            equals: .captureInProgress
        )

        controller.setCaptureSessionActive(false)

        XCTAssertEqual(
            controller.registeredHotKey(for: .restoreMostRecentlyHiddenPinnedImage),
            HotKeyAction.restoreMostRecentlyHiddenPinnedImage.defaultSettings
        )
    }

    @MainActor
    func testFixedToolbarConflictRemainsRejectedAfterCaptureSessionEnds() {
        let store = FakeAppSettingsStore()
        let shortcut = HotKeySettings(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey)
        )
        store.settings.hotkeys = [
            HotKeyAction.restoreMostRecentlyHiddenPinnedImage.rawValue: shortcut
        ]
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)

        XCTAssertNil(controller.registeredHotKey(for: .restoreMostRecentlyHiddenPinnedImage))
        XCTAssertEqual(
            controller.errors[.restoreMostRecentlyHiddenPinnedImage],
            .fixedToolbarConflict(.save)
        )

        controller.setCaptureSessionActive(true)
        controller.setCaptureSessionActive(false)

        XCTAssertNil(controller.registeredHotKey(for: .restoreMostRecentlyHiddenPinnedImage))
        XCTAssertEqual(
            controller.errors[.restoreMostRecentlyHiddenPinnedImage],
            .fixedToolbarConflict(.save)
        )
    }

    @MainActor
    func testHotKeyControllerRestoresPreviousConfigurationWhenDefaultRegistrationFails() {
        let store = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = makeHotKeyController(store: store, registrar: registrar)
        let customCapture = HotKeySettings(
            keyCode: HotKeyAction.capture.defaultSettings.keyCode + 2,
            modifiers: HotKeyAction.capture.defaultSettings.modifiers
        )
        let customRestore = HotKeySettings(
            keyCode: HotKeyAction.restoreMostRecentlyHiddenPinnedImage.defaultSettings.keyCode + 3,
            modifiers: HotKeyAction.restoreMostRecentlyHiddenPinnedImage.defaultSettings.modifiers
        )
        assertHotKeySuccess(controller.apply(customCapture, to: .capture))
        assertHotKeySuccess(
            controller.apply(customRestore, to: .restoreMostRecentlyHiddenPinnedImage)
        )
        registrar.failedSettings[.restoreMostRecentlyHiddenPinnedImage] =
            HotKeyAction.restoreMostRecentlyHiddenPinnedImage.defaultSettings

        assertHotKeyFailure(
            controller.restoreDefaults(),
            equals: .registrationFailed(FakeGlobalHotKeyRegistrar.failureStatus)
        )
        XCTAssertEqual(controller.configuredHotKey(for: .capture), customCapture)
        XCTAssertEqual(
            controller.configuredHotKey(for: .restoreMostRecentlyHiddenPinnedImage),
            customRestore
        )
        XCTAssertEqual(registrar.registered[.capture], customCapture)
        XCTAssertEqual(
            registrar.registered[.restoreMostRecentlyHiddenPinnedImage],
            customRestore
        )
    }

    @MainActor
    func testPreferencesWindowBuildsEveryPageAndRefreshesToolbarLanguage() {
        let settingsStore = FakeAppSettingsStore()
        let preferencesStore = FakePreferencesSettingsStore()
        let hotKeyController = makeHotKeyController(
            store: settingsStore,
            registrar: FakeGlobalHotKeyRegistrar()
        )
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: preferencesStore,
            hotKeyController: hotKeyController,
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer {
            controller.close()
        }

        XCTAssertEqual(
            controller.window?.toolbar?.items.map(\.label),
            ["通用", "快捷键", "保存", "更新", "捐赠", "关于"]
        )
        XCTAssertEqual(controller.window?.contentLayoutRect.width ?? 0, 680, accuracy: 1)
        XCTAssertEqual(controller.window?.contentLayoutRect.height ?? 0, 480, accuracy: 1)
        XCTAssertFalse(controller.window?.styleMask.contains(.resizable) == true)
        for section in PreferencesSection.allCases {
            controller.show(section: section)
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(
                controller.window?.contentLayoutRect.height ?? 0,
                480,
                accuracy: 1,
                "\(section.rawValue) should keep the settings window height stable"
            )
            XCTAssertFalse(
                controller.window?.contentView?.subviews.isEmpty ?? true,
                "\(section.rawValue) page should not be blank"
            )
            if section != .about && section != .donation {
                let root = controller.window?.contentView
                let group = descendants(of: root, matching: NSStackView.self).first {
                    $0.identifier?.rawValue == "preferencesGroup"
                }
                XCTAssertNotNil(group)
                XCTAssertGreaterThanOrEqual(
                    group?.frame.width ?? 0,
                    (root?.bounds.width ?? 0) - 70,
                    "\(section.rawValue) group should fill the page"
                )
                let groupFrameInRoot = group.flatMap { group in
                    root.map { group.convert(group.bounds, to: $0) }
                }
                XCTAssertEqual(
                    groupFrameInRoot?.midX ?? 0,
                    root?.bounds.midX ?? 0,
                    accuracy: 1,
                    "\(section.rawValue) group should be centered"
                )
            }
        }

        settingsStore.settings.language = .english
        controller.refresh()

        XCTAssertEqual(
            controller.window?.toolbar?.items.map(\.label),
            ["General", "Shortcuts", "Save", "Update", "Donate", "About"]
        )
        controller.show(section: .about)
        let imageViews = descendants(
            of: controller.window?.contentView,
            matching: NSImageView.self
        )
        XCTAssertTrue(imageViews.contains(where: { $0.image === NSApp.applicationIconImage }))
        XCTAssertFalse(NSApp.applicationIconImage.isTemplate)
    }

    @MainActor
    func testGeneralPreferencesPersistTextRecognitionFeedbackSwitches() throws {
        let settingsStore = FakeAppSettingsStore()
        let preferencesStore = FakePreferencesSettingsStore()
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: preferencesStore,
            hotKeyController: makeHotKeyController(
                store: settingsStore,
                registrar: FakeGlobalHotKeyRegistrar()
            ),
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer {
            controller.close()
        }

        controller.show(section: .general)
        let labels = descendants(
            of: controller.window?.contentView,
            matching: NSTextField.self
        ).map(\.stringValue)
        XCTAssertTrue(labels.contains("禁用文字/二维码识别提示音"))
        XCTAssertTrue(labels.contains("禁用文字/二维码识别通知"))

        let switches = descendants(
            of: controller.window?.contentView,
            matching: NSSwitch.self
        )
        let soundSwitch = try XCTUnwrap(switches.first {
            $0.identifier?.rawValue == "disableTextRecognitionSound"
        })
        let notificationSwitch = try XCTUnwrap(switches.first {
            $0.identifier?.rawValue == "disableTextRecognitionSuccessNotification"
        })
        XCTAssertEqual(soundSwitch.state, .off)
        XCTAssertEqual(notificationSwitch.state, .off)

        soundSwitch.performClick(nil)
        notificationSwitch.performClick(nil)

        XCTAssertTrue(preferencesStore.settings.disablesTextRecognitionSound)
        XCTAssertTrue(preferencesStore.settings.disablesTextRecognitionSuccessNotification)
    }

    @MainActor
    func testSavePreferencesUsesWideEditorAndFramedPreview() {
        let settingsStore = FakeAppSettingsStore()
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: FakePreferencesSettingsStore(),
            hotKeyController: makeHotKeyController(
                store: settingsStore,
                registrar: FakeGlobalHotKeyRegistrar()
            ),
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer {
            controller.close()
        }

        controller.show(section: .save)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let fields = descendants(of: controller.window?.contentView, matching: NSTextField.self)
        let templateField = fields.first {
            $0.identifier?.rawValue == "filenameTemplateField"
        }
        XCTAssertGreaterThanOrEqual(templateField?.frame.width ?? 0, 560)
        XCTAssertEqual(templateField?.frame.height ?? 0, 32, accuracy: 1)

        let stacks = descendants(of: controller.window?.contentView, matching: NSStackView.self)
        let previewPanel = stacks.first {
            $0.identifier?.rawValue == "filenamePreviewPanel"
        }
        XCTAssertNotNil(previewPanel)
        XCTAssertGreaterThanOrEqual(previewPanel?.frame.width ?? 0, 610)
        XCTAssertTrue(fields.contains {
            $0.identifier?.rawValue == "filenamePreviewLabel"
                && $0.stringValue.hasSuffix(".png")
        })
    }

    @MainActor
    func testShortcutRecorderUsesSingleFieldWithCurrentShortcut() {
        let settingsStore = FakeAppSettingsStore()
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: FakePreferencesSettingsStore(),
            hotKeyController: makeHotKeyController(
                store: settingsStore,
                registrar: FakeGlobalHotKeyRegistrar()
            ),
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer {
            controller.close()
        }

        controller.show(section: .shortcuts)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let recorderControls = descendants(of: controller.window?.contentView, matching: NSView.self)
            .filter { $0.identifier?.rawValue == "shortcutRecorderControl" }
        let recorderButtons = descendants(of: controller.window?.contentView, matching: NSButton.self)
            .filter { $0.identifier?.rawValue == "shortcutRecorderButton" }
        let clearButtons = descendants(of: controller.window?.contentView, matching: NSButton.self)
            .filter { $0.identifier?.rawValue == "shortcutClearButton" }
        let legacyBadges = descendants(of: controller.window?.contentView, matching: NSView.self)
            .filter { $0.identifier?.rawValue == "shortcutValueBadge" }

        XCTAssertEqual(recorderControls.count, HotKeyAction.allCases.count)
        XCTAssertEqual(recorderButtons.count, HotKeyAction.allCases.count)
        XCTAssertEqual(clearButtons.count, HotKeyAction.allCases.count)
        XCTAssertTrue(legacyBadges.isEmpty)
        for control in recorderControls {
            XCTAssertEqual(control.frame.size, NSSize(width: 258, height: 42))
        }
        XCTAssertEqual(
            Set(recorderButtons.map(\.title)),
            Set(HotKeyAction.allCases.map {
                HotKeyFormatter.displayString($0.defaultSettings)
            })
        )
        XCTAssertTrue(clearButtons.allSatisfy { !$0.isHidden })
    }

    @MainActor
    func testGeneralPreferencesEnableShortcutFeedbackByDefaultAndPersistChanges() throws {
        let settingsStore = FakeAppSettingsStore()
        let preferencesStore = FakePreferencesSettingsStore()
        let systemShortcutMonitor = FakeSystemShortcutMonitor()
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: preferencesStore,
            hotKeyController: makeHotKeyController(
                store: settingsStore,
                registrar: FakeGlobalHotKeyRegistrar()
            ),
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker(),
            systemShortcutMonitor: systemShortcutMonitor
        )
        defer {
            controller.close()
        }

        controller.show(section: .general)
        let feedbackSwitch = try XCTUnwrap(
            descendants(
                of: controller.window?.contentView,
                matching: NSSwitch.self
            ).first {
                $0.identifier?.rawValue == "showShortcutFeedback"
            }
        )

        XCTAssertEqual(feedbackSwitch.state, .on)
        let systemFeedbackSwitch = try XCTUnwrap(
            descendants(
                of: controller.window?.contentView,
                matching: NSSwitch.self
            ).first {
                $0.identifier?.rawValue == "showSystemShortcutFeedback"
            }
        )
        XCTAssertEqual(systemFeedbackSwitch.state, .on)

        feedbackSwitch.performClick(nil)

        XCTAssertFalse(preferencesStore.settings.showsShortcutFeedback)

        systemFeedbackSwitch.performClick(nil)

        XCTAssertFalse(preferencesStore.settings.showsSystemShortcutFeedback)
        XCTAssertEqual(systemShortcutMonitor.refreshCount, 1)
    }

    @MainActor
    func testShortcutDisplaySettingsMoveToGeneralAndAlignRight() throws {
        let settingsStore = FakeAppSettingsStore()
        let preferencesStore = FakePreferencesSettingsStore()
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: preferencesStore,
            hotKeyController: makeHotKeyController(
                store: settingsStore,
                registrar: FakeGlobalHotKeyRegistrar()
            ),
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer { controller.close() }

        controller.show(section: .shortcuts)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            controller.window?.contentLayoutRect.height ?? 0,
            480,
            accuracy: 1
        )
        let actionGroup = try XCTUnwrap(
            descendants(
                of: controller.window?.contentView,
                matching: NSStackView.self
            ).first { $0.identifier?.rawValue == "preferencesGroup" }
        )
        XCTAssertEqual(
            actionGroup.arrangedSubviews.filter {
                $0.identifier?.rawValue == "shortcutRow"
            }.count,
            HotKeyAction.allCases.count
        )
        XCTAssertTrue(
            descendants(
                of: controller.window?.contentView,
                matching: NSSwitch.self
            ).filter {
                ["showShortcutFeedback", "showSystemShortcutFeedback"].contains(
                    $0.identifier?.rawValue
                )
            }.isEmpty
        )

        controller.show(section: .general)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let root = try XCTUnwrap(controller.window?.contentView)
        let generalGroup = try XCTUnwrap(
            descendants(of: root, matching: NSStackView.self).first {
                $0.identifier?.rawValue == "preferencesGroup"
            }
        )
        let feedbackSwitches = descendants(of: root, matching: NSSwitch.self).filter {
            ["showShortcutFeedback", "showSystemShortcutFeedback"].contains(
                $0.identifier?.rawValue
            )
        }
        XCTAssertEqual(feedbackSwitches.count, 2)
        let groupFrame = generalGroup.convert(generalGroup.bounds, to: root)
        let switchRightEdges = feedbackSwitches.map {
            $0.convert($0.bounds, to: root).maxX
        }
        XCTAssertEqual(switchRightEdges[0], switchRightEdges[1], accuracy: 1)
        XCTAssertGreaterThan(switchRightEdges[0], groupFrame.maxX - 18)
        XCTAssertLessThan(switchRightEdges[0], groupFrame.maxX)

        let chineseLabels = descendants(of: root, matching: NSTextField.self).map(\.stringValue)
        XCTAssertTrue(chineseLabels.contains("显示 XxSnap 快捷键"))
        XCTAssertTrue(chineseLabels.contains("显示其他应用快捷键"))

        settingsStore.settings.language = .english
        controller.refresh()
        controller.show(section: .general)
        let englishLabels = descendants(
            of: controller.window?.contentView,
            matching: NSTextField.self
        ).map(\.stringValue)
        XCTAssertTrue(englishLabels.contains("Show XxSnap shortcuts"))
        XCTAssertTrue(englishLabels.contains("Show shortcuts from other apps"))
    }

    @MainActor
    func testGeneralSystemShortcutPermissionKeepsSwitchAtRightEdge() throws {
        let settingsStore = FakeAppSettingsStore()
        let preferencesStore = FakePreferencesSettingsStore()
        preferencesStore.settings.showsSystemShortcutFeedback = true
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: preferencesStore,
            hotKeyController: makeHotKeyController(
                store: settingsStore,
                registrar: FakeGlobalHotKeyRegistrar()
            ),
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker(),
            systemShortcutMonitor: FakeSystemShortcutMonitor()
        )
        defer { controller.close() }

        controller.show(section: .general)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let root = try XCTUnwrap(controller.window?.contentView)
        let group = try XCTUnwrap(
            descendants(of: root, matching: NSStackView.self).first {
                $0.identifier?.rawValue == "preferencesGroup"
            }
        )
        let feedbackSwitch = try XCTUnwrap(
            descendants(of: root, matching: NSSwitch.self).first {
                $0.identifier?.rawValue == "showSystemShortcutFeedback"
            }
        )
        let permissionButton = try XCTUnwrap(
            descendants(of: root, matching: NSButton.self).first {
                $0.title == "打开输入监控"
            }
        )
        let groupFrame = group.convert(group.bounds, to: root)
        let switchFrame = feedbackSwitch.convert(feedbackSwitch.bounds, to: root)
        let buttonFrame = permissionButton.convert(permissionButton.bounds, to: root)

        XCTAssertGreaterThan(switchFrame.maxX, groupFrame.maxX - 18)
        XCTAssertLessThan(switchFrame.maxX, groupFrame.maxX)
        XCTAssertLessThanOrEqual(buttonFrame.maxX, switchFrame.minX)
    }

    @MainActor
    func testSystemShortcutMonitorRequiresSettingAndPermission() {
        let store = FakePreferencesSettingsStore()
        let source = FakeGlobalKeyEventSource()
        let permission = FakeSystemShortcutPermissionProvider()
        let monitor = SystemShortcutMonitor(
            settingsStore: store,
            eventSource: source,
            permissionProvider: permission
        )

        monitor.refresh()
        XCTAssertFalse(source.isRunning)

        store.settings.showsSystemShortcutFeedback = true
        monitor.refresh()
        XCTAssertFalse(source.isRunning)

        permission.isGranted = true
        monitor.refresh()
        XCTAssertTrue(source.isRunning)

        store.settings.showsSystemShortcutFeedback = false
        monitor.refresh()
        XCTAssertFalse(source.isRunning)
    }

    @MainActor
    func testSystemShortcutMonitorFiltersTypingRepeatsAndOwnShortcuts() throws {
        let store = FakePreferencesSettingsStore()
        store.settings.showsSystemShortcutFeedback = true
        let source = FakeGlobalKeyEventSource()
        let permission = FakeSystemShortcutPermissionProvider()
        permission.isGranted = true
        let ownShortcut = HotKeyAction.capture.defaultSettings
        var received: [HotKeySettings] = []
        let monitor = SystemShortcutMonitor(
            settingsStore: store,
            eventSource: source,
            permissionProvider: permission,
            shouldIgnore: { $0 == ownShortcut }
        )
        monitor.onShortcutPressed = { received.append($0) }
        monitor.refresh()

        source.send(try makeKeyEvent(keyCode: UInt16(kVK_ANSI_A)))
        source.send(try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_A),
            modifiers: [.shift]
        ))
        source.send(try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_C),
            modifiers: [.command]
        ))
        source.send(try makeKeyEvent(keyCode: UInt16(kVK_Escape)))
        source.send(try makeKeyEvent(keyCode: UInt16(kVK_F5)))
        source.send(try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_C),
            modifiers: [.command],
            isARepeat: true
        ))
        source.send(try makeKeyEvent(
            keyCode: UInt16(ownShortcut.keyCode),
            modifiers: [.command]
        ))

        XCTAssertEqual(
            received.map(HotKeyFormatter.displayString),
            ["⌘C", "Esc", "F5"]
        )
    }

    @MainActor
    func testSystemShortcutFeedbackUsesItsOwnSetting() throws {
        let store = FakePreferencesSettingsStore()
        store.settings.showsShortcutFeedback = false
        store.settings.showsSystemShortcutFeedback = true
        let controller = ShortcutFeedbackPresentationController(
            settingsStore: store,
            visibleFrameProvider: {
                NSRect(x: 0, y: 0, width: 1_200, height: 800)
            }
        )
        defer { controller.hide() }

        controller.showSystemShortcut(
            HotKeySettings(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey))
        )

        XCTAssertNotNil(controller.panel)
        XCTAssertEqual(
            (controller.panel?.contentView as? ShortcutFeedbackBubbleView)?.shortcutText,
            "⌘C"
        )
    }

    @MainActor
    func testShortcutFeedbackBubbleUsesCurrentScreenBottomRightAndSlowFade() throws {
        let store = FakePreferencesSettingsStore()
        let visibleFrame = NSRect(x: 120, y: 80, width: 1_440, height: 900)
        let controller = ShortcutFeedbackPresentationController(
            settingsStore: store,
            visibleFrameProvider: { visibleFrame }
        )
        defer {
            controller.hide()
        }

        controller.show(HotKeyAction.recognizeText.defaultSettings)

        let panel = try XCTUnwrap(controller.panel)
        let bubble = try XCTUnwrap(panel.contentView as? ShortcutFeedbackBubbleView)
        XCTAssertEqual(bubble.shortcutText, "⌘3")
        XCTAssertEqual(panel.frame.maxX, visibleFrame.maxX - 28, accuracy: 0.5)
        XCTAssertEqual(panel.frame.minY, visibleFrame.minY + 28, accuracy: 0.5)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.sharingType, .none)
        XCTAssertEqual(ShortcutFeedbackPresentationController.holdDuration, 3)
        XCTAssertGreaterThanOrEqual(
            ShortcutFeedbackPresentationController.fadeDuration,
            0.8
        )
        XCTAssertGreaterThan(
            bubble.triangleTip.x,
            bubble.bubbleBodyRect.maxX
        )
        XCTAssertEqual(
            bubble.triangleTip.y,
            bubble.bubbleBodyRect.midY,
            accuracy: 0.5
        )
    }

    @MainActor
    func testShortcutFeedbackRespectsDisabledSettingAndReusesOnePanel() throws {
        let store = FakePreferencesSettingsStore()
        let controller = ShortcutFeedbackPresentationController(
            settingsStore: store,
            visibleFrameProvider: {
                NSRect(x: 0, y: 0, width: 1_200, height: 800)
            }
        )
        defer {
            controller.hide()
        }

        controller.show(HotKeyAction.capture.defaultSettings)
        let firstPanel = try XCTUnwrap(controller.panel)

        controller.show(HotKeyAction.fullScreenCapture.defaultSettings)

        XCTAssertTrue(controller.panel === firstPanel)
        XCTAssertEqual(
            (firstPanel.contentView as? ShortcutFeedbackBubbleView)?.shortcutText,
            "⇧⌘1"
        )

        store.settings.showsShortcutFeedback = false
        controller.show(HotKeyAction.recognizeText.defaultSettings)

        XCTAssertNil(controller.panel)
    }

    @MainActor
    func testShortcutRowsAlignLabelsLeftAndControlsRight() {
        let settingsStore = FakeAppSettingsStore()
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: FakePreferencesSettingsStore(),
            hotKeyController: makeHotKeyController(
                store: settingsStore,
                registrar: FakeGlobalHotKeyRegistrar()
            ),
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer {
            controller.close()
        }

        controller.show(section: .shortcuts)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let rows = descendants(of: controller.window?.contentView, matching: NSStackView.self)
            .filter { $0.identifier?.rawValue == "shortcutRow" }
        XCTAssertEqual(rows.count, HotKeyAction.allCases.count)
        var recorderFrames: [NSRect] = []

        for row in rows {
            guard
                let labels = row.arrangedSubviews.first as? NSStackView,
                let controls = row.arrangedSubviews.last
            else {
                XCTFail("Expected shortcut row labels and controls")
                continue
            }

            XCTAssertEqual(labels.alignment, .leading)
            for label in labels.arrangedSubviews.compactMap({ $0 as? NSTextField }) {
                XCTAssertEqual(label.alignment, .left)
            }

            XCTAssertEqual(controls.identifier?.rawValue, "shortcutRecorderControl")
            XCTAssertEqual(controls.frame.width, 258, accuracy: 1)
            XCTAssertEqual(
                controls.frame.maxX,
                row.bounds.maxX - row.edgeInsets.right,
                accuracy: 1
            )
            recorderFrames.append(controls.frame)
        }
        for frame in recorderFrames.dropFirst() {
            XCTAssertEqual(frame.minX, recorderFrames[0].minX, accuracy: 1)
            XCTAssertEqual(frame.maxX, recorderFrames[0].maxX, accuracy: 1)
        }
    }

    @MainActor
    func testShortcutClearButtonDisablesShortcutAndShowsPlaceholder() {
        let settingsStore = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: FakePreferencesSettingsStore(),
            hotKeyController: makeHotKeyController(
                store: settingsStore,
                registrar: registrar
            ),
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer {
            controller.close()
        }

        controller.show(section: .shortcuts)
        let rows = descendants(of: controller.window?.contentView, matching: NSStackView.self)
            .filter { $0.identifier?.rawValue == "shortcutRow" }
        let captureControl = rows.first?.arrangedSubviews.last
        let clearButton = descendants(of: captureControl, matching: NSButton.self)
            .first { $0.identifier?.rawValue == "shortcutClearButton" }

        clearButton?.performClick(nil)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(settingsStore.settings.disabledHotkeys.contains(HotKeyAction.capture.rawValue))
        XCTAssertNil(registrar.registered[.capture])
        let refreshedRows = descendants(of: controller.window?.contentView, matching: NSStackView.self)
            .filter { $0.identifier?.rawValue == "shortcutRow" }
        let refreshedCaptureControl = refreshedRows.first?.arrangedSubviews.last
        let recorder = descendants(of: refreshedCaptureControl, matching: NSButton.self)
            .first { $0.identifier?.rawValue == "shortcutRecorderButton" }
        let refreshedClearButton = descendants(of: refreshedCaptureControl, matching: NSButton.self)
            .first { $0.identifier?.rawValue == "shortcutClearButton" }
        XCTAssertEqual(recorder?.title, "录制快捷键")
        XCTAssertEqual(refreshedClearButton?.isHidden, true)
    }

    @MainActor
    func testShortcutRecorderAcceptsCommandNumberAfterShortcutWasCleared() throws {
        let settingsStore = FakeAppSettingsStore()
        settingsStore.settings.disabledHotkeys = [HotKeyAction.teachingPen.rawValue]
        let registrar = FakeGlobalHotKeyRegistrar()
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: FakePreferencesSettingsStore(),
            hotKeyController: makeHotKeyController(
                store: settingsStore,
                registrar: registrar
            ),
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer {
            controller.close()
        }

        controller.show(section: .shortcuts)
        let rows = descendants(of: controller.window?.contentView, matching: NSStackView.self)
            .filter { $0.identifier?.rawValue == "shortcutRow" }
        let teachingPenControl = rows[3].arrangedSubviews.last
        let recorder = try XCTUnwrap(
            descendants(of: teachingPenControl, matching: NSButton.self)
                .first { $0.identifier?.rawValue == "shortcutRecorderButton" }
        )
        recorder.performClick(nil)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "2",
            charactersIgnoringModifiers: "2",
            isARepeat: false,
            keyCode: UInt16(HotKeyAction.teachingPen.defaultSettings.keyCode)
        ))

        XCTAssertTrue(recorder.performKeyEquivalent(with: event))
        XCTAssertFalse(
            settingsStore.settings.disabledHotkeys.contains(HotKeyAction.teachingPen.rawValue)
        )
        XCTAssertEqual(
            settingsStore.settings.hotkeys[HotKeyAction.teachingPen.rawValue],
            HotKeyAction.teachingPen.defaultSettings
        )
        XCTAssertEqual(
            registrar.registered[.teachingPen],
            HotKeyAction.teachingPen.defaultSettings
        )
    }

    @MainActor
    func testShortcutRecorderConfirmsBeforeReplacingAnotherConfigurableAction() throws {
        let settingsStore = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let hotKeyController = makeHotKeyController(
            store: settingsStore,
            registrar: registrar
        )
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: FakePreferencesSettingsStore(),
            hotKeyController: hotKeyController,
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer {
            controller.window?.sheets.forEach { controller.window?.endSheet($0) }
            controller.close()
        }
        let originalRegistrations = registrar.registered

        controller.show(section: .shortcuts)
        let recorder = try captureShortcutRecorder(in: controller)
        try recordCommandShortcut(
            on: recorder,
            keyCode: HotKeyAction.recognizeText.defaultSettings.keyCode,
            characters: "3"
        )

        XCTAssertTrue(waitUntil { controller.window?.sheets.count == 1 })
        let sheet = try XCTUnwrap(controller.window?.sheets.first)
        let sheetText = descendants(of: sheet.contentView, matching: NSTextField.self)
            .map(\.stringValue)
            .joined(separator: " ")
        XCTAssertTrue(sheetText.contains("文字/二维码识别"))
        XCTAssertEqual(registrar.registered, originalRegistrations)
        XCTAssertTrue(hotKeyController.isHotKeyEnabled(for: .capture))
        XCTAssertTrue(hotKeyController.isHotKeyEnabled(for: .recognizeText))

        let replaceButton = try XCTUnwrap(
            descendants(of: sheet.contentView, matching: NSButton.self)
                .first { $0.title == "覆盖" }
        )
        replaceButton.performClick(nil)

        XCTAssertTrue(waitUntil {
            registrar.registered[.capture] == HotKeyAction.recognizeText.defaultSettings
                && controller.window?.sheets.isEmpty == true
        })
        XCTAssertEqual(
            registrar.registered[.capture],
            HotKeyAction.recognizeText.defaultSettings
        )
        XCTAssertNil(registrar.registered[.recognizeText])
        XCTAssertFalse(hotKeyController.isHotKeyEnabled(for: .recognizeText))
        XCTAssertTrue(
            settingsStore.settings.disabledHotkeys.contains(
                HotKeyAction.recognizeText.rawValue
            )
        )
        XCTAssertNil(
            settingsStore.settings.hotkeys[HotKeyAction.recognizeText.rawValue]
        )
    }

    @MainActor
    func testShortcutRecorderCancelsConfigurableConflictWithoutChangingAssignments() throws {
        let settingsStore = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let hotKeyController = makeHotKeyController(
            store: settingsStore,
            registrar: registrar
        )
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: FakePreferencesSettingsStore(),
            hotKeyController: hotKeyController,
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer {
            controller.window?.sheets.forEach { controller.window?.endSheet($0) }
            controller.close()
        }
        let originalRegistrations = registrar.registered
        let originalSettings = settingsStore.settings

        controller.show(section: .shortcuts)
        let recorder = try captureShortcutRecorder(in: controller)
        try recordCommandShortcut(
            on: recorder,
            keyCode: HotKeyAction.recognizeText.defaultSettings.keyCode,
            characters: "3"
        )

        XCTAssertTrue(waitUntil { controller.window?.sheets.count == 1 })
        let sheet = try XCTUnwrap(controller.window?.sheets.first)
        let cancelButton = try XCTUnwrap(
            descendants(of: sheet.contentView, matching: NSButton.self)
                .first { $0.title == "取消" }
        )
        cancelButton.performClick(nil)

        XCTAssertTrue(waitUntil { controller.window?.sheets.isEmpty == true })
        XCTAssertEqual(registrar.registered, originalRegistrations)
        XCTAssertEqual(settingsStore.settings, originalSettings)
        XCTAssertTrue(hotKeyController.isHotKeyEnabled(for: .capture))
        XCTAssertTrue(hotKeyController.isHotKeyEnabled(for: .recognizeText))
    }

    @MainActor
    func testShortcutRecorderRejectsFixedToolbarConflictWithNamedMessage() throws {
        let settingsStore = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let hotKeyController = makeHotKeyController(
            store: settingsStore,
            registrar: registrar
        )
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: FakePreferencesSettingsStore(),
            hotKeyController: hotKeyController,
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer {
            controller.window?.sheets.forEach { controller.window?.endSheet($0) }
            controller.close()
        }
        let originalRegistrations = registrar.registered
        let originalSettings = settingsStore.settings

        controller.show(section: .shortcuts)
        let recorder = try captureShortcutRecorder(in: controller)
        try recordCommandShortcut(
            on: recorder,
            keyCode: UInt32(kVK_ANSI_S),
            characters: "s"
        )

        XCTAssertTrue(waitUntil { controller.window?.sheets.count == 1 })
        let sheet = try XCTUnwrap(controller.window?.sheets.first)
        let sheetText = descendants(of: sheet.contentView, matching: NSTextField.self)
            .map(\.stringValue)
            .joined(separator: " ")
        XCTAssertTrue(sheetText.contains("与“保存”快捷键冲突"))
        let buttons = descendants(of: sheet.contentView, matching: NSButton.self)
        XCTAssertEqual(buttons.count, 1)
        buttons.first?.performClick(nil)

        XCTAssertTrue(waitUntil { controller.window?.sheets.isEmpty == true })
        XCTAssertEqual(registrar.registered, originalRegistrations)
        XCTAssertEqual(settingsStore.settings, originalSettings)
        XCTAssertTrue(hotKeyController.isHotKeyEnabled(for: .capture))
    }

    @MainActor
    func testShortcutRecorderRejectsEscapeWithNamedFixedConflict() throws {
        let settingsStore = FakeAppSettingsStore()
        let registrar = FakeGlobalHotKeyRegistrar()
        let hotKeyController = makeHotKeyController(
            store: settingsStore,
            registrar: registrar
        )
        let controller = PreferencesWindowController(
            settingsStore: settingsStore,
            preferencesSettingsStore: FakePreferencesSettingsStore(),
            hotKeyController: hotKeyController,
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer {
            controller.window?.sheets.forEach { controller.window?.endSheet($0) }
            controller.close()
        }
        let originalCapture = hotKeyController.configuredHotKey(for: .capture)
        let originalRegistrations = registrar.registered
        let originalSettings = settingsStore.settings

        controller.show(section: .shortcuts)
        let recorder = try captureShortcutRecorder(in: controller)
        recorder.performClick(nil)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: recorder.window?.windowNumber ?? 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)
        ))

        XCTAssertTrue(recorder.performKeyEquivalent(with: event))
        XCTAssertTrue(waitUntil { controller.window?.sheets.count == 1 })
        let sheet = try XCTUnwrap(controller.window?.sheets.first)
        let sheetText = descendants(of: sheet.contentView, matching: NSTextField.self)
            .map(\.stringValue)
            .joined(separator: " ")
        XCTAssertTrue(sheetText.contains("与“取消 / 完成编辑”快捷键冲突"))
        XCTAssertEqual(hotKeyController.configuredHotKey(for: .capture), originalCapture)
        XCTAssertEqual(registrar.registered, originalRegistrations)
        XCTAssertEqual(settingsStore.settings, originalSettings)

        let buttons = descendants(of: sheet.contentView, matching: NSButton.self)
        XCTAssertEqual(buttons.count, 1)
        buttons.first?.performClick(nil)
        XCTAssertTrue(waitUntil { controller.window?.sheets.isEmpty == true })
    }

    func testPreferencesMenuUsesRequestedLowerSectionTitles() {
        let chinese = PreferencesStrings(language: .zhHans)
        XCTAssertEqual(chinese.preferences, "偏好设置…")
        XCTAssertEqual(chinese.checkForUpdates, "检查更新…")
        XCTAssertEqual(chinese.supportDeveloper, "支持开发者 ☕️")
        XCTAssertEqual(chinese.help, "帮助…")
        XCTAssertEqual(chinese.exportDiagnostics, "导出诊断日志…")
        XCTAssertEqual(chinese.helpWindowTitle, "XxSnap 帮助")
        XCTAssertEqual(chinese.helpLoadFailed, "帮助内容暂时无法打开")
        XCTAssertEqual(chinese.helpImageUnavailable, "图片暂时无法显示")
        XCTAssertEqual(chinese.aboutXxSnap, "关于…")
        XCTAssertEqual(chinese.quit, "退出")

        let english = PreferencesStrings(language: .english)
        XCTAssertEqual(english.preferences, "Settings...")
        XCTAssertEqual(english.checkForUpdates, "Check for Updates…")
        XCTAssertEqual(english.supportDeveloper, "Support the Developer ☕️")
        XCTAssertEqual(english.help, "Help...")
        XCTAssertEqual(english.exportDiagnostics, "Export Diagnostic Logs…")
        XCTAssertEqual(english.helpWindowTitle, "XxSnap Help")
        XCTAssertEqual(
            english.helpLoadFailed,
            "Help content is temporarily unavailable."
        )
        XCTAssertEqual(
            english.helpImageUnavailable,
            "The image is temporarily unavailable."
        )
        XCTAssertEqual(english.aboutXxSnap, "About...")
        XCTAssertEqual(english.quit, "Quit")
    }

    func testShortcutConflictMessagesNameActionsInBothLanguages() {
        let chinese = PreferencesStrings(language: .zhHans)
        XCTAssertEqual(
            chinese.fixedShortcutConflict(.rectangle),
            "与“形状”快捷键冲突，禁止覆盖，请重新设置！"
        )
        XCTAssertEqual(chinese.hotKeyActionName(.recognizeText), "文字/二维码识别")
        XCTAssertEqual(chinese.fixedShortcutName(.rectangle), "形状")
        XCTAssertEqual(chinese.fixedShortcutName(.cancel), "取消 / 完成编辑")
        XCTAssertTrue(chinese.configurableShortcutConflict(.recognizeText).contains("文字/二维码识别"))
        XCTAssertTrue(chinese.configurableShortcutConflict(.recognizeText).contains("是否覆盖"))
        XCTAssertTrue(chinese.configurableShortcutConflict(.recognizeText).contains("清空"))
        XCTAssertEqual(chinese.replaceShortcut, "覆盖")
        XCTAssertEqual(chinese.cancelShortcutReplacement, "取消")

        let english = PreferencesStrings(language: .english)
        XCTAssertEqual(
            english.fixedShortcutConflict(.rectangle),
            "This shortcut conflicts with “Shape”. It cannot be overridden. Choose another shortcut."
        )
        XCTAssertEqual(
            english.hotKeyActionName(.recognizeText),
            "Text / QR Code Recognition"
        )
        XCTAssertEqual(english.fixedShortcutName(.rectangle), "Shape")
        XCTAssertEqual(english.fixedShortcutName(.cancel), "Cancel / Finish Editing")
        XCTAssertTrue(
            english.configurableShortcutConflict(.recognizeText)
                .contains("Text / QR Code Recognition")
        )
        XCTAssertTrue(english.configurableShortcutConflict(.recognizeText).contains("Replace"))
        XCTAssertTrue(english.configurableShortcutConflict(.recognizeText).contains("cleared"))
        XCTAssertEqual(english.replaceShortcut, "Replace")
        XCTAssertEqual(english.cancelShortcutReplacement, "Cancel")

        for shortcut in FixedToolbarShortcut.allCases where shortcut != .cancel {
            XCTAssertEqual(
                chinese.fixedShortcutName(shortcut),
                L10n(language: .zhHans).toolbarTooltip(for: shortcut.rawValue),
                "Chinese \(shortcut.rawValue)"
            )
            XCTAssertEqual(
                english.fixedShortcutName(shortcut),
                L10n(language: .english).toolbarTooltip(for: shortcut.rawValue),
                "English \(shortcut.rawValue)"
            )
        }
    }

    func testPreferencesWindowRetainsSettingsTitle() {
        XCTAssertEqual(PreferencesStrings(language: .zhHans).windowTitle, "XxSnap 设置")
        XCTAssertEqual(PreferencesStrings(language: .english).windowTitle, "XxSnap Settings")
    }

    func testStatusMenuSupportsStandaloneFunctionKeyEquivalent() throws {
        let equivalent = try XCTUnwrap(HotKeyFormatter.menuEquivalent(
            HotKeySettings(keyCode: UInt32(kVK_F1), modifiers: 0)
        ))

        XCTAssertEqual(
            equivalent.0.unicodeScalars.first?.value,
            UInt32(NSEvent.SpecialKey.f1.rawValue)
        )
        XCTAssertEqual(equivalent.1, [])
    }

    func testDonationPageUsesRequestedEnglishMessage() {
        XCTAssertEqual(
            PreferencesStrings(language: .english).donationMessage,
            "Support continued development with a donation."
        )
    }

    @MainActor
    func testStatusMenuLowerSectionOpensDonationAndQuits() throws {
        let store = FakeAppSettingsStore()
        let hotKeyController = makeHotKeyController(
            store: store,
            registrar: FakeGlobalHotKeyRegistrar()
        )
        var shownSections: [PreferencesSection] = []
        var showHelpCount = 0
        var exportDiagnosticsCount = 0
        var quitCount = 0
        let controller = StatusItemController(
            captureCoordinator: CaptureCoordinator(
                permissionCoordinator: PermissionCoordinator(),
                screenCaptureService: ScreenCaptureService()
            ),
            settingsStore: store,
            hotKeyController: hotKeyController,
            updateChecker: FakeUpdateChecker(),
            showPreferences: { shownSections.append($0) },
            showHelp: { showHelpCount += 1 },
            exportDiagnostics: { exportDiagnosticsCount += 1 },
            terminationHandler: { quitCount += 1 }
        )

        let lowerItems = Array(controller.test_menuItems.suffix(7))
        XCTAssertEqual(controller.test_statusItemLength, NSStatusItem.squareLength)
        XCTAssertTrue(controller.test_statusButtonIsEnabled)
        XCTAssertEqual(
            lowerItems.map(\.title),
            [
                "偏好设置…",
                "检查更新…",
                "支持开发者 ☕️",
                "帮助…",
                "导出诊断日志…",
                "关于…",
                "退出"
            ]
        )
        XCTAssertFalse(lowerItems.contains(where: \.isSeparatorItem))

        let supportItem = try XCTUnwrap(
            lowerItems.first { $0.title == "支持开发者 ☕️" }
        )
        XCTAssertEqual(supportItem.action, #selector(StatusItemController.openDonation))
        XCTAssertTrue(supportItem.target === controller)
        controller.openDonation()
        XCTAssertEqual(shownSections, [.donation])

        let helpItem = try XCTUnwrap(lowerItems.first { $0.title == "帮助…" })
        XCTAssertEqual(helpItem.action, #selector(StatusItemController.openHelp))
        XCTAssertTrue(helpItem.target === controller)
        controller.openHelp()
        XCTAssertEqual(showHelpCount, 1)

        XCTAssertFalse(
            controller.test_menuItems.contains {
                $0.title == "为下一次滚动截图开启诊断"
                    || $0.title == "Enable Diagnostics for Next Scroll Capture"
            }
        )

        let exportDiagnosticsItem = try XCTUnwrap(
            lowerItems.first { $0.title == "导出诊断日志…" }
        )
        XCTAssertEqual(
            exportDiagnosticsItem.action,
            #selector(StatusItemController.exportDiagnostics)
        )
        XCTAssertTrue(exportDiagnosticsItem.target === controller)
        controller.exportDiagnostics()
        XCTAssertEqual(exportDiagnosticsCount, 1)

        let quitItem = try XCTUnwrap(lowerItems.first { $0.title == "退出" })
        XCTAssertEqual(quitItem.action, #selector(StatusItemController.quit))
        XCTAssertTrue(quitItem.target === controller)
        controller.quit()
        XCTAssertEqual(quitCount, 1)
    }

    @MainActor
    func testDonationPageShowsMessageAndBothPaymentImages() throws {
        let controller = PreferencesWindowController(
            settingsStore: FakeAppSettingsStore(),
            preferencesSettingsStore: FakePreferencesSettingsStore(),
            hotKeyController: makeHotKeyController(
                store: FakeAppSettingsStore(),
                registrar: FakeGlobalHotKeyRegistrar()
            ),
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer { controller.close() }

        controller.show(section: .donation)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let labels = descendants(
            of: controller.window?.contentView,
            matching: NSTextField.self
        )
        let messageLabel = labels.first {
            $0.stringValue == "如果这个软件对您有所帮助，欢迎通过捐赠支持我们持续维护与改进 ☕️"
        }
        XCTAssertNotNil(messageLabel)
        XCTAssertEqual(messageLabel?.font?.pointSize ?? 0, 13, accuracy: 0.1)
        let imageViews = descendants(
            of: controller.window?.contentView,
            matching: NSImageView.self
        )
        let alipay = imageViews.first {
            $0.identifier?.rawValue == "alipayDonationImage"
        }
        let wechatPay = imageViews.first {
            $0.identifier?.rawValue == "wechatPayDonationImage"
        }
        XCTAssertNotNil(alipay?.image)
        XCTAssertNotNil(wechatPay?.image)
        XCTAssertEqual(alipay?.frame.height ?? 0, 300, accuracy: 1)
        XCTAssertEqual(wechatPay?.frame.height ?? 0, 300, accuracy: 1)

        let stacks = descendants(
            of: controller.window?.contentView,
            matching: NSStackView.self
        )
        let donationStack = stacks.first {
            guard let messageLabel else { return false }
            return $0.arrangedSubviews.contains(messageLabel)
        }
        XCTAssertTrue(donationStack?.arrangedSubviews.last === messageLabel)

        let root = controller.window?.contentView
        let contentViews = [messageLabel, alipay, wechatPay].compactMap { $0 }
        let contentFrame = contentViews.reduce(NSRect.null) { partial, view in
            partial.union(view.convert(view.bounds, to: root))
        }
        XCTAssertGreaterThan(contentFrame.width, 440)
        XCTAssertGreaterThan(
            contentFrame.midY,
            (root?.bounds.midY ?? 0) + 8
        )
    }

    func testDonationImagesAreBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "alipay", withExtension: "jpg"))
        XCTAssertNotNil(Bundle.main.url(forResource: "wechatpay", withExtension: "jpg"))
    }

    @MainActor
    func testAboutPageAddsFeedbackAndSupportPrefixToEmail() {
        let store = FakeAppSettingsStore()
        let controller = PreferencesWindowController(
            settingsStore: store,
            preferencesSettingsStore: FakePreferencesSettingsStore(),
            hotKeyController: makeHotKeyController(
                store: store,
                registrar: FakeGlobalHotKeyRegistrar()
            ),
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer { controller.close() }

        controller.show(section: .about)
        let buttons = descendants(
            of: controller.window?.contentView,
            matching: NSButton.self
        )
        XCTAssertTrue(buttons.contains {
            $0.title == "问题反馈或技术支持：zfc.2012@gmail.com"
        })
    }

    @MainActor
    func testAboutPageUsesReportIssuePrefixForEnglishEmail() {
        let store = FakeAppSettingsStore()
        var settings = AppSettings.default
        settings.language = .english
        try? store.save(settings)
        let controller = PreferencesWindowController(
            settingsStore: store,
            preferencesSettingsStore: FakePreferencesSettingsStore(),
            hotKeyController: makeHotKeyController(
                store: store,
                registrar: FakeGlobalHotKeyRegistrar()
            ),
            launchAtLoginManager: FakeLaunchAtLoginManager(),
            updateChecker: FakeUpdateChecker()
        )
        defer { controller.close() }

        controller.show(section: .about)
        let buttons = descendants(
            of: controller.window?.contentView,
            matching: NSButton.self
        )
        XCTAssertTrue(buttons.contains {
            $0.title == "Report Issue: zfc.2012@gmail.com"
        })
    }

    func testAboutPageUsesCorrectXxsoftsDomainInBothLanguages() {
        XCTAssertEqual(
            PreferencesStrings(language: .zhHans).copyright,
            "版权所有 © 2026 xxsofts.com"
        )
        XCTAssertEqual(
            PreferencesStrings(language: .english).copyright,
            "Copyright © 2026 xxsofts.com"
        )
    }

    func testPresentationPenUsesFormalEnglishName() {
        let strings = PreferencesStrings(language: .english)

        XCTAssertEqual(strings.teachingPen, "Presentation Pen")
        XCTAssertEqual(
            strings.teachingPenShortcutDetail,
            "Start full-screen presentation annotation"
        )
    }

    func testTextAndQRCodeRecognitionStringsUseUnifiedProductName() {
        XCTAssertEqual(PreferencesStrings(language: .zhHans).captureText, "文字/二维码识别")
        XCTAssertEqual(
            PreferencesStrings(language: .english).captureText,
            "Text / QR Code Recognition"
        )
        XCTAssertEqual(
            PreferencesStrings(language: .english).captureTextShortcutDetail,
            "Recognize text or a QR code in a selected screen area"
        )
    }

    func testCaptureTextDefaultShortcutIsCommand3() {
        XCTAssertEqual(HotKeyAction.recognizeText.defaultSettings.keyCode, UInt32(kVK_ANSI_3))
        XCTAssertEqual(HotKeyAction.recognizeText.defaultSettings.modifiers, UInt32(cmdKey))
    }

    func testFullScreenCaptureStringsUseProfessionalEnglishName() {
        XCTAssertEqual(PreferencesStrings(language: .zhHans).fullScreenCapture, "全屏截图")
        XCTAssertEqual(PreferencesStrings(language: .english).fullScreenCapture, "Full Screen Capture")
        XCTAssertEqual(
            PreferencesStrings(language: .english).fullScreenCaptureShortcutDetail,
            "Capture the entire visible desktop immediately"
        )
    }

    func testFullScreenCaptureEditorUsesDedicatedTitle() {
        XCTAssertEqual(
            L10n(language: .zhHans).text(.fullScreenCaptureEditorTitle),
            "全屏截图编辑"
        )
        XCTAssertEqual(
            L10n(language: .english).text(.fullScreenCaptureEditorTitle),
            "Full Screen Capture Editor"
        )
    }

    func testFullScreenCaptureDefaultShortcutIsCommandShift1() {
        XCTAssertEqual(HotKeyAction.fullScreenCapture.defaultSettings.keyCode, UInt32(kVK_ANSI_1))
        XCTAssertEqual(
            HotKeyAction.fullScreenCapture.defaultSettings.modifiers,
            UInt32(cmdKey | shiftKey)
        )
    }

    func testFullScreenCaptureSoundIsBundled() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "fullscreencutsound", withExtension: "mp3")
        )
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 1_000)
    }

    func testOCRJoinCandidatesSortsTopToBottomThenLeftToRight() {
        let candidates = [
            RecognizedTextCandidate(text: "World", boundingBox: CGRect(x: 0.45, y: 0.70, width: 0.2, height: 0.1)),
            RecognizedTextCandidate(text: "Hello", boundingBox: CGRect(x: 0.10, y: 0.70, width: 0.2, height: 0.1)),
            RecognizedTextCandidate(text: "Second line", boundingBox: CGRect(x: 0.10, y: 0.40, width: 0.5, height: 0.1)),
        ]

        XCTAssertEqual(OCRTextRecognitionService.join(candidates), "Hello World\nSecond line")
    }

    func testOCRJoinCandidatesTrimsEmptyTextAndWhitespace() {
        let candidates = [
            RecognizedTextCandidate(text: "  Alpha  ", boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.1)),
            RecognizedTextCandidate(text: "   ", boundingBox: CGRect(x: 0.3, y: 0.8, width: 0.2, height: 0.1)),
            RecognizedTextCandidate(text: "Beta", boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.1)),
        ]

        XCTAssertEqual(OCRTextRecognitionService.join(candidates), "Alpha\nBeta")
    }

    func testOCROnlyAttemptsEmbeddedKoreanRepairForGroupedChineseText() {
        XCTAssertFalse(
            OCRTextRecognitionService.shouldAttemptEmbeddedKoreanRepair("普通中文文字识别")
        )
        XCTAssertFalse(
            OCRTextRecognitionService.shouldAttemptEmbeddedKoreanRepair("한국어와 中文")
        )
        XCTAssertTrue(
            OCRTextRecognitionService.shouldAttemptEmbeddedKoreanRepair("韩语声母（示例）说明")
        )
    }

    func testQRCodeRecognitionPrefersLargestCandidate() throws {
        let candidates = [
            QRCodeCandidate(
                payload: "small-center",
                boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
            ),
            QRCodeCandidate(
                payload: "large-edge",
                boundingBox: CGRect(x: 0.05, y: 0.05, width: 0.3, height: 0.3)
            ),
        ]

        XCTAssertEqual(
            QRCodeRecognitionService.preferredCandidate(from: candidates)?.payload,
            "large-edge"
        )
    }

    func testQRCodeRecognitionUsesDistanceFromCenterToBreakSizeTie() throws {
        let candidates = [
            QRCodeCandidate(
                payload: "edge",
                boundingBox: CGRect(x: 0.05, y: 0.05, width: 0.2, height: 0.2)
            ),
            QRCodeCandidate(
                payload: "center",
                boundingBox: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
            ),
        ]

        XCTAssertEqual(
            QRCodeRecognitionService.preferredCandidate(from: candidates)?.payload,
            "center"
        )
    }

    @MainActor
    func testQRCodeRecognitionReadsGeneratedQRCode() async throws {
        let expectedPayload = "https://xxsnap.xxsofts.com/download"
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(expectedPayload.utf8)
        filter.correctionLevel = "M"
        let output = try XCTUnwrap(filter.outputImage).transformed(
            by: CGAffineTransform(scaleX: 12, y: 12)
        )
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)

        let result = try await QRCodeRecognitionService().recognizeQRCode(in: image)

        XCTAssertEqual(result?.payload, expectedPayload)
    }

    @MainActor
    func testOCRRecognizesVerticallyArrangedChineseText() async throws {
        let text = "竖排文字识别"
        let image = try makeVerticalTextImage(text)

        let result = try await OCRTextRecognitionService().recognizeText(in: image)

        XCTAssertEqual(
            result.components(separatedBy: .whitespacesAndNewlines).joined(),
            text
        )
    }

    @MainActor
    func testOCRRecognizesTwoVerticalKoreanColumns() async throws {
        let url = try XCTUnwrap(
            Bundle(for: AppSettingsTests.self).url(
                forResource: "vertical-korean",
                withExtension: "png"
            )
        )
        let image = try XCTUnwrap(NSImage(contentsOf: url))

        let result = try await OCRTextRecognitionService().recognizeText(in: image)

        XCTAssertEqual(result, "조선어\n한국어")
    }

    @MainActor
    func testOCRPreservesKoreanInsideHorizontalChineseText() async throws {
        let url = try XCTUnwrap(
            Bundle(for: AppSettingsTests.self).url(
                forResource: "mixed-chinese-korean",
                withExtension: "png"
            )
        )
        let image = try XCTUnwrap(NSImage(contentsOf: url))

        let result = try await OCRTextRecognitionService().recognizeText(in: image)

        XCTAssertEqual(result, "韩语有十九个初声（초성）、二十一个中声（중성）以及二十七个终声（종성）。")
        XCTAssertTrue(result.contains("초성"), "result=\(result)")
        XCTAssertTrue(result.contains("중성"), "result=\(result)")
        XCTAssertTrue(result.contains("종성"), "result=\(result)")
    }

    func testTextRecognitionOverlayConfigurationHidesScreenshotTools() throws {
        let configuration = SelectionOverlayConfiguration.textRecognition()

        XCTAssertFalse(configuration.showsAnnotationToolbarButtons)
        XCTAssertTrue(configuration.hiddenMainToolbarButtons.contains(.scroll))
        XCTAssertTrue(configuration.hiddenMainToolbarButtons.contains(.cancel))
        XCTAssertTrue(configuration.hiddenMainToolbarButtons.contains(.pin))
        XCTAssertTrue(configuration.hiddenMainToolbarButtons.contains(.save))
        XCTAssertTrue(configuration.hiddenMainToolbarButtons.contains(.copy))
        XCTAssertFalse(configuration.allowsSelectionGeometryEditing)
        XCTAssertFalse(configuration.showsSelectionMeasurementControl)
        XCTAssertEqual(configuration.outsideSelectionDimAlpha, 0)
        let fillColor = try XCTUnwrap(configuration.selectionFillColor)
        XCTAssertEqual(fillColor.whiteComponent, 0.70, accuracy: 0.001)
        XCTAssertEqual(fillColor.alphaComponent, 0.28, accuracy: 0.001)
    }

    func testCorrectIconIsBundledForTextRecognitionSuccess() {
        XCTAssertNotNil(Bundle.main.url(forResource: "correct", withExtension: "svg"))
    }

    func testFailedIconIsBundledForTextRecognitionFailure() {
        XCTAssertNotNil(Bundle.main.url(forResource: "failed", withExtension: "svg"))
    }

    func testNotificationSoundIsBundledForTextRecognitionSuccess() {
        XCTAssertNotNil(Bundle.main.url(forResource: "notification", withExtension: "mp3"))
    }

    func testSettingsStoreIgnoresLegacyLicenseWithoutChangingOtherSettings() {
        let data = Data(
            """
            {
              "language": "english",
              "paletteVisibleCount": 8,
              "interfaceFont": {"familyName":"Menlo","pointSize":14,"weight":0.4},
              "hotkeys": {"capture":{"keyCode":122,"modifiers":0}},
              "disabledHotkeys": ["teachingPen"],
              "license": {"plan":"pro"}
            }
            """.utf8
        )

        let settings = try? JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings?.language, .english)
        XCTAssertEqual(settings?.paletteVisibleCount, 8)
        XCTAssertEqual(settings?.interfaceFont?.familyName, "Menlo")
        XCTAssertEqual(settings?.hotkeys["capture"]?.keyCode, 122)
        XCTAssertEqual(settings?.disabledHotkeys, ["teachingPen"])
        let encoded = settings.flatMap { try? JSONEncoder().encode($0) }
        XCTAssertFalse(String(data: encoded ?? Data(), encoding: .utf8)?.contains("license") == true)
    }

    func testL10nDefaultsToChineseAndSupportsEnglish() {
        XCTAssertEqual(L10n(language: .zhHans).text(.toolbarScrollCapture), "滚动截图")
        XCTAssertEqual(L10n(language: .english).text(.toolbarScrollCapture), "Scroll Capture")
        XCTAssertEqual(L10n(language: .zhHans).text(.colorSamplerCopyHex), "按 C 复制HEX颜色值")
        XCTAssertEqual(L10n(language: .zhHans).text(.colorSamplerCopyRgb), "按 C 复制RGB颜色值")
        XCTAssertEqual(L10n(language: .english).text(.colorSamplerCopyHex), "Press C to copy HEX")
        XCTAssertEqual(L10n(language: .english).text(.colorSamplerCopyRgb), "Press C to copy RGB")
        XCTAssertEqual(L10n(language: .zhHans).toolbarTooltip(for: "save"), "保存")
        XCTAssertEqual(L10n(language: .english).toolbarTooltip(for: "save"), "Save")
        XCTAssertEqual(
            L10n(language: .english).text(.screenRecordingPermissionRequired),
            "Screen Recording Permission Required"
        )
        XCTAssertEqual(
            PreferencesStrings(language: .english).filenameTemplateError(FilenameTemplateError.empty),
            "The filename template cannot be empty."
        )
    }

    func testOverlapWarningDescribesNonblockingMatchingInBothLanguages() {
        let chinese = L10n(language: .zhHans).text(.scrollCaptureLowConfidence)
        let english = L10n(language: .english).text(.scrollCaptureLowConfidence)

        XCTAssertEqual(chinese, "暂无法识别到拼接位置，将继续尝试拼接")
        XCTAssertFalse(chinese.contains("暂停"))
        XCTAssertEqual(english, "Overlap not found yet. Continuing to stitch.")
        XCTAssertFalse(english.localizedCaseInsensitiveContains("paused"))
        XCTAssertTrue(L10n(language: .zhHans).text(.scrollCaptureResourceLimit).contains("暂停"))
        XCTAssertTrue(L10n(language: .english).text(.scrollCaptureResourceLimit).localizedCaseInsensitiveContains("paused"))
    }

    @MainActor
    private func makeHotKeyController(
        store: FakeAppSettingsStore,
        registrar: FakeGlobalHotKeyRegistrar
    ) -> CaptureHotKeyController {
        CaptureHotKeyController(
            settingsStore: store,
            registrar: registrar,
            keyCodeCharacterResolver: { keyCode in
                [
                    UInt32(kVK_ANSI_S): "s",
                    UInt32(kVK_ANSI_A): "a",
                    UInt32(kVK_ANSI_B): "b",
                    UInt32(kVK_ANSI_H): "h",
                    UInt32(kVK_ANSI_P): "p",
                    UInt32(kVK_ANSI_M): "m",
                    UInt32(kVK_ANSI_T): "t",
                    UInt32(kVK_ANSI_N): "n",
                    UInt32(kVK_ANSI_G): "g",
                    UInt32(kVK_ANSI_E): "e",
                    UInt32(kVK_ANSI_R): "r",
                    UInt32(kVK_ANSI_Z): "z",
                    UInt32(kVK_ANSI_C): "c",
                ][keyCode]
            },
            captureHandler: {},
            teachingPenHandler: {},
            restorePinnedImageHandler: {}
        )
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        isARepeat: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: isARepeat,
            keyCode: keyCode
        ))
    }

    private func assertHotKeySuccess(
        _ result: Result<Void, HotKeyConfigurationError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .failure(let error) = result {
            XCTFail("Expected success, got \(error)", file: file, line: line)
        }
    }

    private func assertHotKeyFailure(
        _ result: Result<Void, HotKeyConfigurationError>,
        equals expected: HotKeyConfigurationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success:
            XCTFail("Expected failure \(expected), got success", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    private func descendants<View: NSView>(
        of root: NSView?,
        matching type: View.Type
    ) -> [View] {
        guard let root else { return [] }
        return root.subviews.flatMap { view in
            ([view as? View].compactMap { $0 }) + descendants(of: view, matching: type)
        }
    }

    @MainActor
    private func captureShortcutRecorder(
        in controller: PreferencesWindowController
    ) throws -> NSButton {
        let rows = descendants(
            of: controller.window?.contentView,
            matching: NSStackView.self
        ).filter { $0.identifier?.rawValue == "shortcutRow" }
        let captureControl = try XCTUnwrap(rows.first?.arrangedSubviews.last)
        return try XCTUnwrap(
            descendants(of: captureControl, matching: NSButton.self)
                .first { $0.identifier?.rawValue == "shortcutRecorderButton" }
        )
    }

    @MainActor
    private func recordCommandShortcut(
        on recorder: NSButton,
        keyCode: UInt32,
        characters: String
    ) throws {
        recorder.performClick(nil)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: recorder.window?.windowNumber ?? 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ))
        XCTAssertTrue(recorder.performKeyEquivalent(with: event))
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 1,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.01)
            )
        }
        return condition()
    }

    @MainActor
    private func makeVerticalTextImage(_ text: String) throws -> NSImage {
        let characters = Array(text)
        let size = NSSize(width: 240, height: CGFloat(characters.count) * 100 + 120)
        let image = NSImage(size: size)
        let font = try XCTUnwrap(NSFont(name: "PingFang SC", size: 72))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, character) in characters.enumerated() {
            let value = String(character) as NSString
            let glyphSize = value.size(withAttributes: attributes)
            value.draw(
                at: NSPoint(
                    x: (size.width - glyphSize.width) / 2,
                    y: size.height - 100 - CGFloat(index) * 100
                ),
                withAttributes: attributes
            )
        }
        image.unlockFocus()
        return image
    }
}

private enum TestStoreError: Error {
    case failed
}

private final class FakePreferencesSettingsStore: PreferencesSettingsStoring {
    var settings = PreferencesSettings.default

    func load() -> PreferencesSettings {
        settings
    }

    func save(_ settings: PreferencesSettings) throws {
        self.settings = settings
    }
}

private final class FakeAppSettingsStore: AppSettingsStoring {
    var settings = AppSettings.default
    var shouldFailSave = false

    func load() -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) throws {
        if shouldFailSave {
            throw TestStoreError.failed
        }
        self.settings = settings
    }
}

private final class FakeGlobalHotKeyRegistrar: GlobalHotKeyRegistering {
    static let failureStatus: OSStatus = -1

    var onHotKeyPressed: ((HotKeyAction) -> Void)?
    var failedSettings: [HotKeyAction: HotKeySettings] = [:]
    private(set) var registered: [HotKeyAction: HotKeySettings] = [:]

    private var actionsByToken: [ObjectIdentifier: HotKeyAction] = [:]

    func register(
        _ settings: HotKeySettings,
        action: HotKeyAction
    ) -> Result<HotKeyRegistrationToken, GlobalHotKeyRegistrationError> {
        if failedSettings[action] == settings {
            return .failure(GlobalHotKeyRegistrationError(status: Self.failureStatus))
        }
        let token = HotKeyRegistrationToken()
        actionsByToken[ObjectIdentifier(token)] = action
        registered[action] = settings
        return .success(token)
    }

    func unregister(_ token: HotKeyRegistrationToken) {
        guard let action = actionsByToken.removeValue(forKey: ObjectIdentifier(token)) else {
            return
        }
        registered[action] = nil
    }
}

@MainActor
private final class FakeGlobalKeyEventSource: GlobalKeyEventSourcing {
    var onKeyDown: ((NSEvent) -> Void)?
    private(set) var isRunning = false

    func start() {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }

    func send(_ event: NSEvent) {
        guard isRunning else { return }
        onKeyDown?(event)
    }
}

@MainActor
private final class FakeSystemShortcutPermissionProvider:
    SystemShortcutPermissionProviding {
    var isGranted = false
    private(set) var requestCount = 0
    private(set) var openSettingsCount = 0

    func request() -> Bool {
        requestCount += 1
        return isGranted
    }

    func openSystemSettings() {
        openSettingsCount += 1
    }
}

@MainActor
private final class FakeSystemShortcutMonitor: SystemShortcutMonitoring {
    var hasPermission = false
    var isMonitoring = false
    private(set) var requestCount = 0
    private(set) var refreshCount = 0
    private(set) var stopCount = 0
    private(set) var openSettingsCount = 0

    func requestPermission() -> Bool {
        requestCount += 1
        return hasPermission
    }

    func refresh() {
        refreshCount += 1
    }

    func stop() {
        stopCount += 1
        isMonitoring = false
    }

    func openSystemSettings() {
        openSettingsCount += 1
    }
}

@MainActor
private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus = .notRegistered

    func setEnabled(_ isEnabled: Bool) async throws {
        status = isEnabled ? .enabled : .notRegistered
    }

    func openSystemSettings() {}
}

private struct FakeUpdateChecker: UpdateChecking {
    func checkForUpdates() async -> UpdateCheckResult {
        .upToDate
    }
}
