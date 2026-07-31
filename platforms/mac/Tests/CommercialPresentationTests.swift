import AppKit
import XCTest
@testable import xxsnap

final class CommercialPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAllFreeAndGraceHideCommercialPresentation() throws {
        let policy = try makePolicy(mode: "all_free")
        let chinese = CommercialPresentationModel(state: .allFree, language: .zhHans, policy: policy, now: now)
        let english = CommercialPresentationModel(state: .allFreeGrace(until: now.addingTimeInterval(100)), language: .english, policy: policy, now: now)
        XCTAssertFalse(chinese.showsPreferencesSection)
        XCTAssertFalse(english.showsPreferencesSection)
        XCTAssertEqual(chinese.statusText, "当前所有功能免费")
        XCTAssertEqual(english.statusText, "All features are currently free")
    }

    func testPaidFreePresentationUsesSignedPolicyValuesInBothLanguages() throws {
        let policy = try makePolicy()
        let chinese = CommercialPresentationModel(state: .free(reason: .trialExpired), language: .zhHans, policy: policy, now: now)
        let english = CommercialPresentationModel(state: .free(reason: .trialExpired), language: .english, policy: policy, now: now)

        XCTAssertTrue(chinese.showsPreferencesSection)
        XCTAssertEqual(chinese.priceText, "首发 48 元，正式价 68 元")
        XCTAssertTrue(chinese.detail.contains("永久使用"))
        XCTAssertTrue(chinese.detail.contains("12 个月更新"))
        XCTAssertEqual(chinese.policyCopyText, "需要 Pro")
        XCTAssertTrue(english.priceText?.contains("CNY 48") == true)
        XCTAssertTrue(english.detail.contains("permanent use"))
        XCTAssertTrue(english.detail.contains("12 months of updates"))
        XCTAssertEqual(english.policyCopyText, "Pro required")
        XCTAssertEqual(chinese.purchaseButtonTitle, "购买 XxSnap Pro")
        XCTAssertEqual(english.purchaseButtonTitle, "Purchase XxSnap Pro")
        XCTAssertEqual(chinese.activationButtonTitle, "激活")
        XCTAssertEqual(english.activationButtonTitle, "Activate")
    }

    func testTrialCountdownRoundsUpAtZeroOneAndMultipleDayBoundaries() throws {
        let policy = try makePolicy()
        func countdown(_ interval: TimeInterval) -> String? {
            CommercialPresentationModel(
                state: .trial(expiresAt: now.addingTimeInterval(interval)),
                language: .english,
                policy: policy,
                now: now
            ).trialCountdown
        }
        XCTAssertEqual(countdown(0), "0 days remaining")
        XCTAssertEqual(countdown(1), "1 day remaining")
        XCTAssertEqual(countdown(86_400), "1 day remaining")
        XCTAssertEqual(countdown(86_401), "2 days remaining")
        let trial = CommercialPresentationModel(
            state: .trial(expiresAt: now.addingTimeInterval(86_400)),
            language: .zhHans,
            policy: policy,
            now: now
        )
        XCTAssertEqual(trial.trialTerms, "14 天完整试用")
        let englishTrial = CommercialPresentationModel(
            state: .trial(expiresAt: now.addingTimeInterval(86_400)),
            language: .english,
            policy: policy,
            now: now
        )
        XCTAssertEqual(englishTrial.trialTerms, "Full 14-day trial")
        XCTAssertEqual(trial.trialCountdown, "剩余 1 天")
        XCTAssertEqual(trial.statusText, "Pro 试用中")
        XCTAssertEqual(englishTrial.statusText, "Pro trial")
    }

    func testProPresentationShowsSignedMaskedEmailDevicesAndUpdateDate() throws {
        let policy = try makePolicy()
        let payload = try makeEntitlement()
        let model = CommercialPresentationModel(
            state: .pro(CommercialEntitlement(payload: payload)),
            language: .english,
            policy: policy,
            now: now
        )
        XCTAssertEqual(model.maskedEmail, "k***@example.com")
        XCTAssertEqual(model.deviceUsage, "Devices 1/5")
        XCTAssertEqual(model.updatesThrough, "Updates through January 15, 2028")
        let chinese = CommercialPresentationModel(
            state: .pro(CommercialEntitlement(payload: payload)),
            language: .zhHans,
            policy: policy,
            now: now
        )
        XCTAssertEqual(chinese.deviceUsage, "设备 1/5")
        XCTAssertEqual(model.deactivationButtonTitle, "Deactivate This Mac…")
        XCTAssertEqual(chinese.deactivationButtonTitle, "停用本机…")
        XCTAssertEqual(model.deactivationConfirmationTitle, "Deactivate This Mac?")
        XCTAssertEqual(chinese.deactivationConfirmationTitle, "确认停用本机？")
        XCTAssertEqual(model.deactivationConfirmationDetail, "Pro access will be removed from this Mac.")
        XCTAssertEqual(chinese.deactivationConfirmationDetail, "停用后，本机将不再保留 Pro 权限。")
        XCTAssertEqual(model.deactivationConfirmButtonTitle, "Deactivate")
        XCTAssertEqual(chinese.deactivationConfirmButtonTitle, "停用")
        XCTAssertEqual(model.cancelButtonTitle, "Cancel")
        XCTAssertEqual(chinese.cancelButtonTitle, "取消")
        let updated = CommercialPresentationModel(
            state: model.state,
            language: .english,
            policy: try makePolicy(deviceLimit: 2),
            now: now
        )
        XCTAssertEqual(updated.deviceUsage, "Devices 1/2")
    }

    func testServerFailureIsNonBlockingAndKeepsProPresentation() throws {
        let model = CommercialPresentationModel(
            state: .pro(CommercialEntitlement(payload: try makeEntitlement())),
            language: .zhHans,
            policy: try makePolicy(),
            now: now,
            notice: .network
        )
        XCTAssertTrue(model.isPro)
        XCTAssertEqual(model.noticeText, "暂时无法连接服务器，当前授权不受影响。")
        let english = CommercialPresentationModel(
            state: model.state,
            language: .english,
            policy: model.policy,
            now: now,
            notice: .server
        )
        XCTAssertEqual(
            english.noticeText,
            "The server is temporarily unavailable. Your current access is unchanged."
        )
        let chineseServer = CommercialPresentationModel(
            state: model.state, language: .zhHans, policy: model.policy, now: now, notice: .server
        )
        let englishNetwork = CommercialPresentationModel(
            state: model.state, language: .english, policy: model.policy, now: now, notice: .network
        )
        XCTAssertEqual(chineseServer.noticeText, "服务器暂时不可用，当前授权不受影响。")
        XCTAssertEqual(
            englishNetwork.noticeText,
            "The server is temporarily unavailable. Your current access is unchanged."
        )
    }

    func testFreeReasonChoosesOnlyTheMatchingSignedLocalizedCopy() throws {
        let policy = try makePolicy()
        for language in [AppLanguage.zhHans, .english] {
            let unavailable = CommercialPresentationModel(
                state: .free(reason: .trialUnavailable), language: language, policy: policy, now: now
            )
            let expired = CommercialPresentationModel(
                state: .free(reason: .trialExpired), language: language, policy: policy, now: now
            )
            XCTAssertEqual(
                unavailable.policyCopyText,
                language == .english ? "Trial unavailable" : "试用不可用"
            )
            XCTAssertEqual(
                expired.policyCopyText,
                language == .english ? "Pro required" : "需要 Pro"
            )
        }
    }

    func testActivationFormNormalizesAndValidatesWithoutKeepingWhitespace() {
        let value = ActivationFormValue(
            email: "  user@example.com \n",
            code: " xxsnap-abcd-2345-wxyz-6789 "
        )
        XCTAssertEqual(value.email, "user@example.com")
        XCTAssertEqual(value.code, "XXSNAP-ABCD-2345-WXYZ-6789")
        XCTAssertTrue(value.isValid)
        XCTAssertFalse(ActivationFormValue(email: "bad@", code: value.code).isValid)
        XCTAssertFalse(ActivationFormValue(email: value.email, code: "XXSNAP-AAAA-BBBB-CCCC-1111").isValid)
    }

    func testActivationErrorsUseStableLocalizedMessagesOnly() {
        let pairs: [(CommercialActionError, String, String)] = [
            (.invalidEmail, "请输入有效的邮箱地址。", "Enter a valid email address."),
            (.invalidCode, "激活码格式不正确。", "The activation code format is invalid."),
            (.activationRejected, "授权激活失败。", "The license could not be activated."),
            (.deviceLimit, "设备数量已达上限，请管理设备后重试。", "The device limit has been reached. Manage devices and try again."),
            (.network, "暂时无法连接，请稍后重试。", "Unable to connect. Try again later."),
            (.storage, "授权信息无法保存，当前权限保持不变。", "The license could not be saved. Your current access is unchanged."),
            (.invalidPurchaseURL, "购买链接暂时不可用。", "The purchase link is temporarily unavailable."),
        ]
        for (error, chinese, english) in pairs {
            XCTAssertEqual(error.message(language: .zhHans), chinese)
            XCTAssertEqual(error.message(language: .english), english)
        }
    }

    func testPurchaseURLAllowsOnlyExactProductionOrigin() throws {
        XCTAssertTrue(CommercialPurchaseURL.isAllowed(URL(string: "https://xxsnap.xxsofts.com/buy")!))
        XCTAssertTrue(CommercialPurchaseURL.isAllowed(URL(string: "https://xxsnap.xxsofts.com:443/buy")!))
        for value in [
            "http://xxsnap.xxsofts.com/buy",
            "https://evil.xxsofts.com/buy",
            "https://xxsnap.xxsofts.com.evil.test/buy",
            "https://user@xxsnap.xxsofts.com/buy",
            "https://xxsnap.xxsofts.com:444/buy",
        ] {
            XCTAssertFalse(CommercialPurchaseURL.isAllowed(URL(string: value)!))
        }
    }

    func testPreferencesSectionsDynamicallyAddAndRemoveCommercialSection() throws {
        let allFree = CommercialPresentationModel(state: .allFree, language: .zhHans, policy: try makePolicy(mode: "all_free"), now: now)
        let paid = CommercialPresentationModel(state: .free(reason: .trialExpired), language: .english, policy: try makePolicy(), now: now)
        XCTAssertFalse(PreferencesSection.visibleSections(for: allFree).contains(.commercial))
        XCTAssertTrue(PreferencesSection.visibleSections(for: paid).contains(.commercial))
        XCTAssertEqual(PreferencesSection.safeSelection(.save, visible: PreferencesSection.visibleSections(for: paid)), .save)
        XCTAssertEqual(PreferencesSection.safeSelection(.commercial, visible: PreferencesSection.visibleSections(for: allFree)), .general)
    }

    @MainActor
    func testPreferencesToolbarPreservesOtherPageAndFallsBackWhenCommercialDisappears() throws {
        let access = PresentationCommercialAccess(state: .free(reason: .trialExpired), policy: try makePolicy())
        let settings = PresentationSettingsStore()
        let hotkeys = CaptureHotKeyController(
            settingsStore: settings,
            registrar: PresentationHotKeyRegistrar(),
            captureHandler: {},
            teachingPenHandler: {},
            restorePinnedImageHandler: {}
        )
        let controller = PreferencesWindowController(
            settingsStore: settings,
            preferencesSettingsStore: PresentationPreferencesStore(),
            hotKeyController: hotkeys,
            launchAtLoginManager: PresentationLaunchManager(),
            updateChecker: PresentationUpdateChecker(),
            commercialAccess: access,
            commercialActions: access
        )
        defer { controller.close() }
        XCTAssertTrue(controller.window?.toolbar?.items.map(\.label).contains("授权与购买") == true)

        controller.show(section: .save)
        access.state = .allFree
        access.presentationPolicy = try makePolicy(mode: "all_free")
        controller.commercialAccessDidChange()
        XCTAssertTrue(controller.window?.toolbar?.selectedItemIdentifier?.rawValue.hasSuffix(".save") == true)
        XCTAssertFalse(controller.window?.toolbar?.items.map(\.label).contains("授权与购买") == true)
        controller.showCommercialPurchaseIfAvailable()
        XCTAssertTrue(controller.window?.toolbar?.selectedItemIdentifier?.rawValue.hasSuffix(".save") == true)
        controller.show(section: .commercial)
        XCTAssertTrue(controller.window?.toolbar?.selectedItemIdentifier?.rawValue.hasSuffix(".general") == true)

        access.state = .free(reason: .trialExpired)
        access.presentationPolicy = try makePolicy()
        controller.commercialAccessDidChange()
        controller.showCommercialPurchaseIfAvailable()
        XCTAssertTrue(controller.window?.toolbar?.selectedItemIdentifier?.rawValue.hasSuffix(".commercial") == true)
        let commercialChineseView = controller.window?.contentView
        settings.settings.language = .english
        controller.languageDidChange()
        XCTAssertFalse(controller.window?.contentView === commercialChineseView)
        XCTAssertTrue(controller.window?.toolbar?.items.map(\.label).contains("License & Purchase") == true)

        controller.show(section: .save)
        let editedPage = controller.window?.contentView
        settings.settings.language = .zhHans
        controller.languageDidChange()
        XCTAssertTrue(controller.window?.contentView === editedPage)

        controller.show(section: .commercial)
        access.state = .allFree
        access.presentationPolicy = try makePolicy(mode: "all_free")
        controller.commercialAccessDidChange()
        XCTAssertTrue(controller.window?.toolbar?.selectedItemIdentifier?.rawValue.hasSuffix(".general") == true)
    }

    @MainActor
    func testPurchaseActionUsesInjectedOpenerOnlyForAllowedURL() {
        let opener = RecordingCommercialOpener()
        XCTAssertNil(CommercialPurchaseAction.open(URL(string: "https://xxsnap.xxsofts.com/buy"), using: opener))
        XCTAssertEqual(opener.urls.count, 1)
        XCTAssertEqual(
            CommercialPurchaseAction.open(URL(string: "https://evil.example/buy"), using: opener),
            .invalidPurchaseURL
        )
        XCTAssertEqual(opener.urls.count, 1)
    }

    @MainActor
    func testSubmissionCoordinatorPreventsDuplicatesAndPublishesFinalResult() async {
        let actions = SuspendedCommercialActions()
        let coordinator = CommercialOperationCoordinator()
        let form = ActivationFormValue(email: "user@example.com", code: "XXSNAP-ABCD-2345-WXYZ-6789")
        XCTAssertTrue(coordinator.activate(form, using: actions))
        await Task.yield()
        XCTAssertTrue(coordinator.isSubmitting)
        XCTAssertFalse(coordinator.activate(form, using: actions))
        XCTAssertEqual(actions.activationCount, 1)

        actions.completeActivation(.success(()))
        await waitUntil { !coordinator.isSubmitting }
        XCTAssertEqual(coordinator.result, .success)
        XCTAssertFalse(coordinator.isSubmitting)
    }

    @MainActor
    func testDeactivateSuccessAndFailureAreStableAndKeepFailedState() async {
        let actions = ImmediateCommercialActions()
        let coordinator = CommercialOperationCoordinator()
        var confirmationCount = 0
        XCTAssertTrue(coordinator.deactivate(confirm: {
            confirmationCount += 1
            return false
        }, using: actions))
        XCTAssertFalse(coordinator.deactivate(confirm: { true }, using: actions))
        await waitUntil { !coordinator.isSubmitting }
        XCTAssertEqual(confirmationCount, 1)
        XCTAssertEqual(actions.deactivationCount, 0)

        XCTAssertTrue(coordinator.deactivate(confirm: { true }, using: actions))
        await waitUntil { !coordinator.isSubmitting }
        XCTAssertEqual(coordinator.result, .success)
        XCTAssertEqual(actions.deactivationCount, 1)
        actions.deactivationError = .storage
        XCTAssertTrue(coordinator.deactivate(confirm: { true }, using: actions))
        await waitUntil { !coordinator.isSubmitting }
        XCTAssertEqual(coordinator.result, .failure(.storage))
    }

    @MainActor
    func testSharedOperationCoordinatorIsABarrierAcrossPageRebuilds() async {
        let actions = SuspendedCommercialActions()
        let shared = CommercialOperationCoordinator()
        let form = ActivationFormValue(email: "user@example.com", code: "XXSNAP-ABCD-2345-WXYZ-6789")
        XCTAssertTrue(shared.activate(form, using: actions))
        XCTAssertEqual(shared.state, .submitting(.activation))
        let rebuiltPageReads = shared.state
        XCTAssertEqual(rebuiltPageReads, .submitting(.activation))
        XCTAssertFalse(shared.deactivate(confirm: { true }, using: actions))
        XCTAssertFalse(shared.activate(form, using: actions))
        await Task.yield()
        XCTAssertEqual(actions.activationCount, 1)
        actions.completeActivation(.success(()))
        await waitUntil { !shared.isSubmitting }
        XCTAssertEqual(shared.result, .success)
    }

    @MainActor
    func testRebuiltCommercialPageObservesSharedProgressAndOldPageCannotOverwrite() async throws {
        let access = PresentationCommercialAccess(
            state: .free(reason: .trialExpired),
            policy: try makePolicy()
        )
        let actions = SuspendedCommercialActions()
        let shared = CommercialOperationCoordinator()
        let form = ActivationFormValue(email: "user@example.com", code: "XXSNAP-ABCD-2345-WXYZ-6789")
        XCTAssertTrue(shared.activate(form, using: actions))
        await Task.yield()

        let oldPage = CommercialPreferencesViewController(
            access: access,
            actions: actions,
            language: .zhHans,
            operationCoordinator: shared
        )
        _ = oldPage.view
        let oldContent = oldPage.view.subviews.first
        let rebuiltPage = CommercialPreferencesViewController(
            access: access,
            actions: actions,
            language: .english,
            operationCoordinator: shared
        )
        _ = rebuiltPage.view
        let rebuiltSubmittingContent = rebuiltPage.view.subviews.first
        let activation = descendants(of: rebuiltPage.view, type: NSButton.self)
            .first(where: { $0.title == "Activate" })
        XCTAssertEqual(activation?.isEnabled, false)

        actions.completeActivation(.success(()))
        await waitUntil { !shared.isSubmitting }

        XCTAssertTrue(oldPage.view.subviews.first === oldContent)
        XCTAssertFalse(rebuiltPage.view.subviews.first === rebuiltSubmittingContent)
        XCTAssertEqual(
            descendants(of: rebuiltPage.view, type: NSButton.self)
                .first(where: { $0.title == "Activate" })?.isEnabled,
            true
        )
    }

    @MainActor
    func testCommercialPageDisplaysProductionNoticeInBothLanguages() throws {
        let access = PresentationCommercialAccess(
            state: .pro(CommercialEntitlement(payload: try makeEntitlement())),
            policy: try makePolicy()
        )
        access.presentationNotice = .server
        let actions = ImmediateCommercialActions()
        for (language, expected) in [
            (AppLanguage.zhHans, "服务器暂时不可用，当前授权不受影响。"),
            (.english, "The server is temporarily unavailable. Your current access is unchanged."),
        ] {
            let page = CommercialPreferencesViewController(
                access: access,
                actions: actions,
                language: language,
                operationCoordinator: CommercialOperationCoordinator()
            )
            XCTAssertTrue(
                descendants(of: page.view, type: NSTextField.self)
                    .contains(where: { $0.stringValue == expected })
            )
        }
    }

    @MainActor
    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<100 where !predicate() { await Task.yield() }
    }

    private func descendants<T: NSView>(of root: NSView, type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            let current = (child as? T).map { [$0] } ?? []
            return current + descendants(of: child, type: type)
        }
    }

    private func makePolicy(mode: String = "paid", deviceLimit: Int = 5) throws -> CommercialPolicy {
        let json = """
        {"schemaVersion":1,"policyId":"p1","mode":"\(mode)","billingReady":true,"effectiveAt":"2026-01-01T00:00:00Z","expiresAt":"2030-01-01T00:00:00Z","trialDays":14,"updateMonths":12,"deviceLimit":\(deviceLimit),"minimumSafeVersion":"1.0.0","features":{"scroll_capture":true,"ocr":true,"teaching_pen":true},"purchase":{"regularPriceCny":68,"launchPriceCny":48,"renewalPriceCny":34,"zhCNURL":"https://xxsnap.xxsofts.com/zh/buy","enURL":"https://xxsnap.xxsofts.com/en/buy"},"copy":{"zhCN":{"proRequired":"需要 Pro","trialUnavailable":"试用不可用"},"en":{"proRequired":"Pro required","trialUnavailable":"Trial unavailable"}}}
        """
        return try CommercialJSON.decoder.decode(CommercialPolicy.self, from: Data(json.utf8))
    }

    private func makeEntitlement() throws -> EntitlementPayload {
        let json = """
        {"schemaVersion":1,"credentialId":"00000000-0000-0000-0000-000000000001","licenseId":"00000000-0000-0000-0000-000000000002","deviceHash":"device","access":"pro","appVersion":"1.0.0","buildNumber":1,"issuedAt":"2027-01-15T00:00:00Z","expiresAt":null,"purchasedAt":"2027-01-15T00:00:00Z","updatesThrough":"2028-01-15T00:00:00Z","maximumBuildNumber":99,"emailMasked":"k***@example.com","activeDevices":1,"deviceLimit":3}
        """
        return try CommercialJSON.decoder.decode(EntitlementPayload.self, from: Data(json.utf8))
    }
}

@MainActor
private final class SuspendedCommercialActions: CommercialLicenseActing {
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var activationCount = 0
    func activate(email: String, code: String) async throws {
        activationCount += 1
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func deactivateCurrentDevice() async throws {}
    func completeActivation(_ result: Result<Void, Error>) { continuation?.resume(with: result) }
}

@MainActor
private final class ImmediateCommercialActions: CommercialLicenseActing {
    var deactivationError: CommercialAccessControllerError?
    private(set) var deactivationCount = 0
    func activate(email: String, code: String) async throws {}
    func deactivateCurrentDevice() async throws {
        deactivationCount += 1
        if let deactivationError { throw deactivationError }
    }
}

@MainActor
private final class PresentationCommercialAccess: CommercialAccessProviding, CommercialLicenseActing {
    var state: CommercialAccessState
    var presentationPolicy: CommercialPolicy?
    var presentationNotice: CommercialPresentationNotice?
    var onStateChange: ((CommercialAccessState) -> Void)?
    init(state: CommercialAccessState, policy: CommercialPolicy?) {
        self.state = state
        presentationPolicy = policy
    }
    var snapshot: CommercialAccessSnapshot {
        CommercialAccessSnapshot(state: state, availableFeatures: [], proBadgedFeatures: [])
    }
    func requestPurchase(for feature: CommercialFeature) {}
    func activate(email: String, code: String) async throws {}
    func deactivateCurrentDevice() async throws {}
}

private final class PresentationSettingsStore: AppSettingsStoring {
    var settings = AppSettings.default
    func load() -> AppSettings { settings }
    func save(_ settings: AppSettings) throws { self.settings = settings }
}

private final class PresentationPreferencesStore: PreferencesSettingsStoring {
    var settings = PreferencesSettings.default
    func load() -> PreferencesSettings { settings }
    func save(_ settings: PreferencesSettings) throws { self.settings = settings }
}

private final class PresentationHotKeyRegistrar: GlobalHotKeyRegistering {
    var onHotKeyPressed: ((HotKeyAction) -> Void)?
    func register(_ settings: HotKeySettings, action: HotKeyAction) -> Result<HotKeyRegistrationToken, GlobalHotKeyRegistrationError> { .success(HotKeyRegistrationToken()) }
    func unregister(_ token: HotKeyRegistrationToken) {}
}

@MainActor
private final class PresentationLaunchManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus = .notRegistered
    func setEnabled(_ isEnabled: Bool) async throws {}
    func openSystemSettings() {}
}

private struct PresentationUpdateChecker: UpdateChecking {
    func checkForUpdates() async -> UpdateCheckResult { .placeholderUpToDate }
}

@MainActor
private final class RecordingCommercialOpener: CommercialURLOpening {
    private(set) var urls: [URL] = []
    func open(_ url: URL) -> Bool { urls.append(url); return true }
}
