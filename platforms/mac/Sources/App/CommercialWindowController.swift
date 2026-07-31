import AppKit

enum CommercialPresentationNotice: Equatable {
    case network
    case storage
}

struct CommercialPresentationModel: Equatable {
    let state: CommercialAccessState
    let language: AppLanguage
    let policy: CommercialPolicy?
    let now: Date
    let notice: CommercialPresentationNotice?

    init(
        state: CommercialAccessState,
        language: AppLanguage,
        policy: CommercialPolicy?,
        now: Date = Date(),
        notice: CommercialPresentationNotice? = nil
    ) {
        self.state = state
        self.language = language
        self.policy = policy
        self.now = now
        self.notice = notice
    }

    private var isEnglish: Bool { language == .english }

    var showsPreferencesSection: Bool {
        guard policy?.mode == .paid else { return false }
        switch state {
        case .allFree, .allFreeGrace: return false
        case .trial, .free, .pro: return true
        }
    }

    var showsProBadges: Bool { showsPreferencesSection }

    var isPro: Bool {
        if case .pro = state { return true }
        return false
    }

    var title: String { isEnglish ? "License & Purchase" : "授权与购买" }

    var statusText: String {
        switch state {
        case .allFree, .allFreeGrace:
            return isEnglish ? "All features are currently free" : "当前所有功能免费"
        case .trial:
            return isEnglish ? "Pro trial" : "Pro 试用中"
        case .free:
            return isEnglish ? "XxSnap Free" : "XxSnap 免费版"
        case .pro:
            return "XxSnap Pro"
        }
    }

    var trialCountdown: String? {
        guard case let .trial(expiresAt) = state else { return nil }
        let days = max(0, Int(ceil(expiresAt.timeIntervalSince(now) / 86_400)))
        if isEnglish {
            return days == 1 ? "1 day remaining" : "\(days) days remaining"
        }
        return "剩余 \(days) 天"
    }

    var trialTerms: String? {
        guard case .trial = state, let days = policy?.trialDays else { return nil }
        return isEnglish ? "Full \(days)-day trial" : "\(days) 天完整试用"
    }

    var policyCopyText: String? {
        guard case .free = state, let copy = policy?.copy else { return nil }
        return isEnglish ? copy.en.proRequired : copy.zhCN.proRequired
    }

    var priceText: String? {
        guard let purchase = policy?.purchase else { return nil }
        if isEnglish {
            return "Launch price CNY \(purchase.launchPriceCny), regular price CNY \(purchase.regularPriceCny)"
        }
        return "首发 \(purchase.launchPriceCny) 元，正式价 \(purchase.regularPriceCny) 元"
    }

    var detail: String {
        guard let policy else { return "" }
        if isEnglish {
            return "Includes permanent use and \(policy.updateMonths) months of updates. Renew updates for CNY \(policy.purchase.renewalPriceCny)."
        }
        return "永久使用，包含 \(policy.updateMonths) 个月更新；后续更新续费 \(policy.purchase.renewalPriceCny) 元。"
    }

    var maskedEmail: String? {
        guard case let .pro(entitlement) = state else { return nil }
        return entitlement.payload.emailMasked
    }

    var deviceUsage: String? {
        guard case let .pro(entitlement) = state,
              let active = entitlement.payload.activeDevices
        else { return nil }
        let limit = entitlement.payload.deviceLimit
        return isEnglish ? "Devices \(active)/\(limit)" : "设备 \(active)/\(limit)"
    }

    var updatesThrough: String? {
        guard case let .pro(entitlement) = state,
              let date = entitlement.payload.updatesThrough
        else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: isEnglish ? "en_US" : "zh_CN")
        formatter.dateStyle = .long
        let formatted = formatter.string(from: date)
        return isEnglish ? "Updates through \(formatted)" : "免费更新截止：\(formatted)"
    }

    var purchaseURL: URL? {
        guard let purchase = policy?.purchase else { return nil }
        let candidate = language == .english ? purchase.enURL : purchase.zhCNURL
        return CommercialPurchaseURL.isAllowed(candidate) ? candidate : nil
    }

    var noticeText: String? {
        guard let notice else { return nil }
        switch (notice, isEnglish) {
        case (.network, true): return "The server is temporarily unavailable. Your current access is unchanged."
        case (.network, false): return "暂时无法连接服务器，当前授权不受影响。"
        case (.storage, true): return "Your license could not be updated. Your current access is unchanged."
        case (.storage, false): return "授权信息暂时无法更新，当前权限保持不变。"
        }
    }
}

struct ActivationFormValue: Equatable {
    let email: String
    let code: String

    init(email: String, code: String) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var isValidEmail: Bool {
        guard !email.contains(where: \.isWhitespace) else { return false }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    var isValidCode: Bool {
        code.range(
            of: #"^XXSNAP-[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$"#,
            options: .regularExpression
        ) != nil
    }

    var isValid: Bool { isValidEmail && isValidCode }
}

enum CommercialActionError: Equatable {
    case invalidEmail
    case invalidCode
    case activationRejected
    case deviceLimit
    case network
    case storage
    case invalidPurchaseURL

    func message(language: AppLanguage) -> String {
        let english = language == .english
        switch self {
        case .invalidEmail: return english ? "Enter a valid email address." : "请输入有效的邮箱地址。"
        case .invalidCode: return english ? "The activation code format is invalid." : "激活码格式不正确。"
        case .activationRejected: return english ? "The license could not be activated." : "授权激活失败。"
        case .deviceLimit: return english ? "The device limit has been reached. Manage devices and try again." : "设备数量已达上限，请管理设备后重试。"
        case .network: return english ? "Unable to connect. Try again later." : "暂时无法连接，请稍后重试。"
        case .storage: return english ? "The license could not be saved. Your current access is unchanged." : "授权信息无法保存，当前权限保持不变。"
        case .invalidPurchaseURL: return english ? "The purchase link is temporarily unavailable." : "购买链接暂时不可用。"
        }
    }
}

enum CommercialPurchaseURL {
    static func isAllowed(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https"
            && components.host?.lowercased() == "xxsnap.xxsofts.com"
            && components.user == nil
            && components.password == nil
            && (components.port == nil || components.port == 443)
    }
}

@MainActor
protocol CommercialURLOpening {
    func open(_ url: URL) -> Bool
}

extension NSWorkspace: CommercialURLOpening {}

@MainActor
enum CommercialPurchaseAction {
    static func open(
        _ url: URL?,
        using opener: any CommercialURLOpening
    ) -> CommercialActionError? {
        guard let url, CommercialPurchaseURL.isAllowed(url), opener.open(url) else {
            return .invalidPurchaseURL
        }
        return nil
    }
}

@MainActor
protocol CommercialLicenseActing: AnyObject {
    func activate(email: String, code: String) async throws
    func deactivateCurrentDevice() async throws
}

extension CommercialAccessController: CommercialLicenseActing {}

enum CommercialSubmissionResult: Equatable {
    case success
    case failure(CommercialActionError)
    case ignored
}

@MainActor
final class CommercialActionCoordinator {
    private(set) var isSubmitting = false
    private var generation = 0

    func invalidatePendingPresentation() {
        generation += 1
        isSubmitting = false
    }

    func activate(
        _ form: ActivationFormValue,
        using actions: any CommercialLicenseActing
    ) async -> CommercialSubmissionResult {
        guard !isSubmitting else { return .ignored }
        guard form.isValidEmail else { return .failure(.invalidEmail) }
        guard form.isValidCode else { return .failure(.invalidCode) }
        return await perform { try await actions.activate(email: form.email, code: form.code) }
    }

    func deactivate(
        using actions: any CommercialLicenseActing
    ) async -> CommercialSubmissionResult {
        guard !isSubmitting else { return .ignored }
        return await perform { try await actions.deactivateCurrentDevice() }
    }

    private func perform(
        _ operation: () async throws -> Void
    ) async -> CommercialSubmissionResult {
        isSubmitting = true
        generation += 1
        let token = generation
        let result: CommercialSubmissionResult
        do {
            try await operation()
            result = .success
        } catch let error as CommercialAccessControllerError {
            result = .failure(Self.map(error))
        } catch {
            result = .failure(.network)
        }
        guard token == generation else { return .ignored }
        isSubmitting = false
        return result
    }

    private static func map(_ error: CommercialAccessControllerError) -> CommercialActionError {
        switch error {
        case .storage: return .storage
        case .deviceLimit: return .deviceLimit
        case .activationRejected, .invalidCredential, .noCredential: return .activationRejected
        case .network, .identityUnavailable: return .network
        }
    }
}

@MainActor
final class CommercialPreferencesViewController: NSViewController {
    typealias DeactivationConfirmation = @MainActor (NSWindow?, AppLanguage) async -> Bool

    private let access: any CommercialAccessProviding
    private let actions: any CommercialLicenseActing
    private let urlOpener: any CommercialURLOpening
    private let confirmDeactivation: DeactivationConfirmation
    private let actionCoordinator = CommercialActionCoordinator()
    private var language: AppLanguage
    private var emailField: NSTextField?
    private var codeField: NSSecureTextField?
    private var primaryButton: NSButton?
    private var spinner: NSProgressIndicator?
    private var errorLabel: NSTextField?

    init(
        access: any CommercialAccessProviding,
        actions: any CommercialLicenseActing,
        language: AppLanguage,
        urlOpener: any CommercialURLOpening = NSWorkspace.shared,
        confirmDeactivation: @escaping DeactivationConfirmation = CommercialPreferencesViewController.defaultConfirmation
    ) {
        self.access = access
        self.actions = actions
        self.language = language
        self.urlOpener = urlOpener
        self.confirmDeactivation = confirmDeactivation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
        render()
    }

    func update(language: AppLanguage) {
        self.language = language
        render()
    }

    private var model: CommercialPresentationModel {
        CommercialPresentationModel(
            state: access.state,
            language: language,
            policy: access.presentationPolicy
        )
    }

    private func render(notice: CommercialActionError? = nil) {
        guard isViewLoaded else { return }
        view.subviews.forEach { $0.removeFromSuperview() }
        emailField = nil
        codeField = nil
        primaryButton = nil
        spinner = nil
        errorLabel = nil
        let model = model

        let title = label(model.title, size: 22, weight: .semibold)
        let status = label(model.statusText, size: 15, weight: .medium)
        let stack = NSStackView(views: [title, status])
        stack.identifier = NSUserInterfaceItemIdentifier("commercialPreferencesPage")
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let countdown = model.trialCountdown { stack.addArrangedSubview(label(countdown)) }
        if let terms = model.trialTerms { stack.addArrangedSubview(label(terms)) }
        if let policyCopy = model.policyCopyText { stack.addArrangedSubview(label(policyCopy, wrapping: true)) }
        if let price = model.priceText, !model.isPro { stack.addArrangedSubview(label(price)) }
        if !model.detail.isEmpty { stack.addArrangedSubview(label(model.detail, wrapping: true)) }

        if model.isPro {
            if let email = model.maskedEmail { stack.addArrangedSubview(label(email)) }
            if let devices = model.deviceUsage { stack.addArrangedSubview(label(devices)) }
            if let updates = model.updatesThrough { stack.addArrangedSubview(label(updates)) }
            let deactivate = NSButton(
                title: language == .english ? "Deactivate This Mac…" : "停用本机…",
                target: self,
                action: #selector(deactivateDevice)
            )
            deactivate.bezelStyle = .rounded
            deactivate.setAccessibilityLabel(language == .english ? "Deactivate this Mac" : "停用本机")
            primaryButton = deactivate
            stack.addArrangedSubview(deactivate)
        } else {
            let purchase = NSButton(
                title: language == .english ? "Purchase XxSnap Pro" : "购买 XxSnap Pro",
                target: self,
                action: #selector(openPurchase)
            )
            purchase.bezelStyle = .rounded
            purchase.isEnabled = model.purchaseURL != nil
            purchase.setAccessibilityLabel(purchase.title)
            stack.addArrangedSubview(purchase)

            let email = NSTextField()
            email.placeholderString = language == .english ? "License email" : "授权邮箱"
            email.setAccessibilityLabel(language == .english ? "License email" : "授权邮箱")
            let code = NSSecureTextField()
            code.placeholderString = "XXSNAP-XXXX-XXXX-XXXX-XXXX"
            code.setAccessibilityLabel(language == .english ? "Activation code" : "激活码")
            emailField = email
            codeField = code
            for field in [email, code] {
                field.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
                stack.addArrangedSubview(field)
            }
            let activation = NSButton(
                title: language == .english ? "Activate" : "激活",
                target: self,
                action: #selector(activateLicense)
            )
            activation.keyEquivalent = "\r"
            activation.bezelStyle = .rounded
            primaryButton = activation
            let progress = NSProgressIndicator()
            progress.style = .spinning
            progress.controlSize = .small
            progress.isDisplayedWhenStopped = false
            spinner = progress
            let row = NSStackView(views: [activation, progress])
            row.orientation = .horizontal
            row.spacing = 8
            stack.addArrangedSubview(row)
        }

        if let notice {
            let error = label(notice.message(language: language), wrapping: true)
            error.textColor = .systemRed
            error.setAccessibilityRole(.staticText)
            errorLabel = error
            stack.addArrangedSubview(error)
        } else if let noticeText = model.noticeText {
            stack.addArrangedSubview(label(noticeText, wrapping: true))
        }

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -34),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 30),
        ])
    }

    @objc private func openPurchase() {
        if let error = CommercialPurchaseAction.open(model.purchaseURL, using: urlOpener) {
            render(notice: error)
        }
    }

    @objc private func activateLicense() {
        let form = ActivationFormValue(
            email: emailField?.stringValue ?? "",
            code: codeField?.stringValue ?? ""
        )
        setSubmitting(true)
        Task { [weak self] in
            guard let self else { return }
            let result = await actionCoordinator.activate(form, using: actions)
            handle(result)
        }
    }

    @objc private func deactivateDevice() {
        setSubmitting(true)
        Task { [weak self] in
            guard let self else { return }
            guard await confirmDeactivation(view.window, language) else {
                setSubmitting(false)
                return
            }
            let result = await actionCoordinator.deactivate(using: actions)
            handle(result)
        }
    }

    private func handle(_ result: CommercialSubmissionResult) {
        switch result {
        case .success:
            render()
        case let .failure(error):
            setSubmitting(false)
            render(notice: error)
        case .ignored:
            setSubmitting(actionCoordinator.isSubmitting)
        }
    }

    private func setSubmitting(_ value: Bool) {
        primaryButton?.isEnabled = !value
        if value { spinner?.startAnimation(nil) } else { spinner?.stopAnimation(nil) }
    }

    private func label(
        _ value: String,
        size: CGFloat = NSFont.systemFontSize,
        weight: NSFont.Weight = .regular,
        wrapping: Bool = false
    ) -> NSTextField {
        let field = wrapping
            ? NSTextField(wrappingLabelWithString: value)
            : NSTextField(labelWithString: value)
        field.font = .systemFont(ofSize: size, weight: weight)
        if wrapping { field.maximumNumberOfLines = 3 }
        return field
    }

    private static func defaultConfirmation(
        window: NSWindow?,
        language: AppLanguage
    ) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = language == .english ? "Deactivate This Mac?" : "确认停用本机？"
        alert.informativeText = language == .english
            ? "Pro access will be removed from this Mac."
            : "停用后，本机将不再保留 Pro 权限。"
        alert.addButton(withTitle: language == .english ? "Deactivate" : "停用")
        alert.addButton(withTitle: language == .english ? "Cancel" : "取消")
        if let window {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0 == .alertFirstButtonReturn) }
            }
        }
        return alert.runModal() == .alertFirstButtonReturn
    }
}
