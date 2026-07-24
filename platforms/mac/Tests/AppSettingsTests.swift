import Carbon.HIToolbox
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
        XCTAssertEqual(settings.license.plan, .trial)
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

        let settings = PreferencesSettings(
            filenameTemplate: "Capture {yyyyMMdd}_{HHmmss}",
            checksForUpdatesAtLaunch: false,
            updateCheckIntervalHours: 6
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
            equals: .duplicate
        )
        XCTAssertEqual(
            controller.configuredHotKey(for: .capture),
            HotKeyAction.capture.defaultSettings
        )
        XCTAssertEqual(registrar.registered[.capture], HotKeyAction.capture.defaultSettings)
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
            ["通用", "快捷键", "保存", "更新", "关于"]
        )
        XCTAssertEqual(controller.window?.contentLayoutRect.width ?? 0, 680, accuracy: 1)
        XCTAssertEqual(controller.window?.contentLayoutRect.height ?? 0, 320, accuracy: 1)
        XCTAssertFalse(controller.window?.styleMask.contains(.resizable) == true)
        for section in PreferencesSection.allCases {
            controller.show(section: section)
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            XCTAssertFalse(
                controller.window?.contentView?.subviews.isEmpty ?? true,
                "\(section.rawValue) page should not be blank"
            )
            if section != .about {
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
            ["General", "Shortcuts", "Save", "Update", "About"]
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
        let teachingPenControl = rows[2].arrangedSubviews.last
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

    func testPreferencesMenuUsesShortAboutTitle() {
        XCTAssertEqual(PreferencesStrings(language: .zhHans).aboutXxSnap, "关于")
        XCTAssertEqual(PreferencesStrings(language: .english).aboutXxSnap, "About")
    }

    func testPresentationPenUsesFormalEnglishName() {
        let strings = PreferencesStrings(language: .english)

        XCTAssertEqual(strings.teachingPen, "Presentation Pen")
        XCTAssertEqual(
            strings.teachingPenShortcutDetail,
            "Start full-screen presentation annotation"
        )
    }

    func testCaptureTextStringsUseRequestedEnglishName() {
        XCTAssertEqual(PreferencesStrings(language: .zhHans).captureText, "识别文字")
        XCTAssertEqual(PreferencesStrings(language: .english).captureText, "Capture Text")
        XCTAssertEqual(
            PreferencesStrings(language: .english).captureTextShortcutDetail,
            "Capture text from a selected screen area"
        )
    }

    func testCaptureTextDefaultShortcutIsCommand3() {
        XCTAssertEqual(HotKeyAction.recognizeText.defaultSettings.keyCode, UInt32(kVK_ANSI_3))
        XCTAssertEqual(HotKeyAction.recognizeText.defaultSettings.modifiers, UInt32(cmdKey))
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

    func testTextRecognitionOverlayConfigurationHidesScreenshotTools() {
        let configuration = SelectionOverlayConfiguration.textRecognition()

        XCTAssertFalse(configuration.showsAnnotationToolbarButtons)
        XCTAssertTrue(configuration.hiddenMainToolbarButtons.contains(.scroll))
        XCTAssertTrue(configuration.hiddenMainToolbarButtons.contains(.pin))
        XCTAssertTrue(configuration.hiddenMainToolbarButtons.contains(.save))
        XCTAssertFalse(configuration.hiddenMainToolbarButtons.contains(.copy))
        XCTAssertFalse(configuration.hiddenMainToolbarButtons.contains(.cancel))
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
            captureHandler: {},
            teachingPenHandler: {},
            restorePinnedImageHandler: {}
        )
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
private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus = .notRegistered

    func setEnabled(_ isEnabled: Bool) async throws {
        status = isEnabled ? .enabled : .notRegistered
    }

    func openSystemSettings() {}
}

private struct FakeUpdateChecker: UpdateChecking {
    func checkForUpdates() async -> UpdateCheckResult {
        .placeholderUpToDate
    }
}
