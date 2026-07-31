import AppKit
import Carbon.HIToolbox

enum HotKeyAction: String, CaseIterable {
    case capture
    case fullScreenCapture
    case recognizeText
    case teachingPen
    case restoreMostRecentlyHiddenPinnedImage

    var identifier: UInt32 {
        switch self {
        case .capture: return 1
        case .restoreMostRecentlyHiddenPinnedImage: return 2
        case .teachingPen: return 3
        case .recognizeText: return 4
        case .fullScreenCapture: return 5
        }
    }

    var defaultSettings: HotKeySettings {
        switch self {
        case .capture:
            return HotKeySettings(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(cmdKey))
        case .fullScreenCapture:
            return HotKeySettings(
                keyCode: UInt32(kVK_ANSI_1),
                modifiers: UInt32(cmdKey | shiftKey)
            )
        case .recognizeText:
            return HotKeySettings(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey))
        case .teachingPen:
            return HotKeySettings(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey))
        case .restoreMostRecentlyHiddenPinnedImage:
            return HotKeySettings(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey))
        }
    }
}

enum HotKeyConfigurationError: LocalizedError, Equatable {
    case captureInProgress
    case fixedToolbarConflict(FixedToolbarShortcut)
    case configurableConflict(HotKeyAction)
    case missingModifier
    case duplicate
    case registrationFailed(OSStatus)
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .captureInProgress:
            return "截图进行中"
        case .fixedToolbarConflict:
            return "快捷键与截图工具栏快捷键冲突"
        case .configurableConflict:
            return "快捷键已被其他动作使用"
        case .missingModifier:
            return "快捷键必须包含修饰键"
        case .duplicate:
            return "快捷键已被其他动作使用"
        case .registrationFailed:
            return "快捷键注册失败"
        case .persistenceFailed:
            return "快捷键保存失败"
        }
    }
}

final class HotKeyRegistrationToken {
    fileprivate let reference: EventHotKeyRef?

    init(reference: EventHotKeyRef? = nil) {
        self.reference = reference
    }
}

struct GlobalHotKeyRegistrationError: Error, Equatable {
    let status: OSStatus
}

protocol GlobalHotKeyRegistering: AnyObject {
    var onHotKeyPressed: ((HotKeyAction) -> Void)? { get set }
    func register(
        _ settings: HotKeySettings,
        action: HotKeyAction
    ) -> Result<HotKeyRegistrationToken, GlobalHotKeyRegistrationError>
    func unregister(_ token: HotKeyRegistrationToken)
}

final class CarbonGlobalHotKeyRegistrar: GlobalHotKeyRegistering {
    var onHotKeyPressed: ((HotKeyAction) -> Void)?

    private var eventHandlerRef: EventHandlerRef?

    init() {
        installEventHandler()
    }

    deinit {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register(
        _ settings: HotKeySettings,
        action: HotKeyAction
    ) -> Result<HotKeyRegistrationToken, GlobalHotKeyRegistrationError> {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: fourCharacterCode("xxsp"),
            id: action.identifier
        )
        let status = RegisterEventHotKey(
            settings.keyCode,
            settings.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            NSLog("xxsnap hotkey registration failed id=%u status=%d", action.identifier, status)
            return .failure(GlobalHotKeyRegistrationError(status: status))
        }
        return .success(HotKeyRegistrationToken(reference: reference))
    }

    func unregister(_ token: HotKeyRegistrationToken) {
        if let reference = token.reference {
            UnregisterEventHotKey(reference)
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }
                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard parameterStatus == noErr,
                      let action = HotKeyAction.allCases.first(where: { $0.identifier == hotKeyID.id })
                else {
                    return noErr
                }
                let registrar = Unmanaged<CarbonGlobalHotKeyRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    registrar.onHotKeyPressed?(action)
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
        if status != noErr {
            NSLog("xxsnap hotkey handler install failed status=%d", status)
        }
    }
}

@MainActor
final class CaptureHotKeyController {
    var onStateChange: (() -> Void)?

    private let settingsStore: any AppSettingsStoring
    private let registrar: any GlobalHotKeyRegistering
    private let handlers: [HotKeyAction: () -> Void]
    private let hotKeyFeedbackHandler: (HotKeySettings) -> Void
    private let keyCodeCharacterResolver: (UInt32) -> String?
    private let registrationOrder: [HotKeyAction]
    private var configured: [HotKeyAction: HotKeySettings] = [:]
    private var disabledActions: Set<HotKeyAction> = []
    private var registrations: [HotKeyAction: HotKeyRegistrationToken] = [:]
    private(set) var errors: [HotKeyAction: HotKeyConfigurationError] = [:]
    private(set) var isCaptureSessionActive = false

    init(
        settingsStore: any AppSettingsStoring = SettingsStore(),
        registrar: any GlobalHotKeyRegistering = CarbonGlobalHotKeyRegistrar(),
        keyCodeCharacterResolver: @escaping (UInt32) -> String? =
            KeyboardLayoutCharacterResolver.charactersIgnoringModifiers(for:),
        captureHandler: @escaping () -> Void,
        fullScreenCaptureHandler: @escaping () -> Void = {},
        recognizeTextHandler: @escaping () -> Void = {},
        hotKeyFeedbackHandler: @escaping (HotKeySettings) -> Void = { _ in },
        teachingPenHandler: @escaping () -> Void,
        restorePinnedImageHandler: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.registrar = registrar
        self.hotKeyFeedbackHandler = hotKeyFeedbackHandler
        self.keyCodeCharacterResolver = keyCodeCharacterResolver
        handlers = [
            .capture: captureHandler,
            .fullScreenCapture: fullScreenCaptureHandler,
            .recognizeText: recognizeTextHandler,
            .teachingPen: teachingPenHandler,
            .restoreMostRecentlyHiddenPinnedImage: restorePinnedImageHandler
        ]

        let storedSettings = settingsStore.load()
        let stored = storedSettings.hotkeys
        disabledActions = Set(storedSettings.disabledHotkeys.compactMap(HotKeyAction.init(rawValue:)))
        let explicitlyConfiguredActions = HotKeyAction.allCases.filter {
            stored[$0.rawValue] != nil
        }
        registrationOrder = explicitlyConfiguredActions + HotKeyAction.allCases.filter {
            !explicitlyConfiguredActions.contains($0)
        }
        for action in HotKeyAction.allCases {
            configured[action] = stored[action.rawValue] ?? action.defaultSettings
        }
        registrar.onHotKeyPressed = { [weak self] action in
            Task { @MainActor in
                guard let self else { return }
                self.hotKeyFeedbackHandler(self.configuredHotKey(for: action))
                self.handlers[action]?()
            }
        }
        registerConfiguredHotKeys()
    }

    func configuredHotKey(for action: HotKeyAction) -> HotKeySettings {
        configured[action] ?? action.defaultSettings
    }

    func registeredHotKey(for action: HotKeyAction) -> HotKeySettings? {
        registrations[action] == nil ? nil : configuredHotKey(for: action)
    }

    func isRegistered(_ settings: HotKeySettings) -> Bool {
        HotKeyAction.allCases.contains {
            registeredHotKey(for: $0) == settings
        }
    }

    func isHotKeyEnabled(for action: HotKeyAction) -> Bool {
        !disabledActions.contains(action)
    }

    func apply(
        _ settings: HotKeySettings,
        to action: HotKeyAction,
        replacing requestedReplacement: HotKeyAction? = nil
    ) -> Result<Void, HotKeyConfigurationError> {
        guard !isCaptureSessionActive else {
            return .failure(.captureInProgress)
        }
        if let conflict = SelectionToolbarState.fixedShortcutConflict(
            for: settings,
            keyCodeCharacterResolver: keyCodeCharacterResolver
        ) {
            return .failure(.fixedToolbarConflict(conflict))
        }
        guard HotKeyFormatter.isValidGlobalShortcut(settings) else {
            return .failure(.missingModifier)
        }
        let occupant = HotKeyAction.allCases.first {
            $0 != action
                && !disabledActions.contains($0)
                && configuredHotKey(for: $0) == settings
        }
        if let occupant, occupant != requestedReplacement {
            return .failure(.configurableConflict(occupant))
        }
        if occupant == nil, let requestedReplacement {
            return .failure(.configurableConflict(requestedReplacement))
        }

        let previousConfigured = configured
        let previouslyDisabled = disabledActions
        let previousErrors = errors
        let affectedActions = [action] + [occupant].compactMap { $0 }
        let previouslyRegistered = Set(affectedActions.filter {
            registrations[$0] != nil
        })
        if configuredHotKey(for: action) == settings,
           registrations[action] != nil,
           !disabledActions.contains(action) {
            errors[action] = nil
            return .success(())
        }

        for affectedAction in affectedActions {
            if let token = registrations.removeValue(forKey: affectedAction) {
                registrar.unregister(token)
            }
        }
        switch registrar.register(settings, action: action) {
        case .failure(let error):
            rollbackApplyTransaction(
                configured: previousConfigured,
                disabledActions: previouslyDisabled,
                errors: previousErrors,
                affectedActions: affectedActions,
                previouslyRegistered: previouslyRegistered
            )
            notifyStateChange()
            return .failure(.registrationFailed(error.status))
        case .success(let token):
            registrations[action] = token
        }

        configured[action] = settings
        disabledActions.remove(action)
        if let occupant {
            disabledActions.insert(occupant)
            errors[occupant] = nil
        }
        do {
            try persistConfiguredHotKeys()
            errors[action] = nil
            reconcileMissingRegistrations()
            notifyStateChange()
            return .success(())
        } catch {
            rollbackApplyTransaction(
                configured: previousConfigured,
                disabledActions: previouslyDisabled,
                errors: previousErrors,
                affectedActions: affectedActions,
                previouslyRegistered: previouslyRegistered
            )
            notifyStateChange()
            return .failure(.persistenceFailed)
        }
    }

    func disable(_ action: HotKeyAction) -> Result<Void, HotKeyConfigurationError> {
        guard !isCaptureSessionActive else {
            return .failure(.captureInProgress)
        }
        if disabledActions.contains(action) {
            errors[action] = nil
            return .success(())
        }

        if let token = registrations.removeValue(forKey: action) {
            registrar.unregister(token)
        }
        disabledActions.insert(action)
        do {
            try persistConfiguredHotKeys()
            errors[action] = nil
            reconcileMissingRegistrations()
            notifyStateChange()
            return .success(())
        } catch {
            disabledActions.remove(action)
            restoreRegistrationIfValid(configuredHotKey(for: action), action: action)
            errors[action] = .persistenceFailed
            notifyStateChange()
            return .failure(.persistenceFailed)
        }
    }

    func restoreDefaults() -> Result<Void, HotKeyConfigurationError> {
        guard !isCaptureSessionActive else {
            return .failure(.captureInProgress)
        }

        let previous = configured
        let previouslyDisabled = disabledActions
        unregisterAll()
        configured = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map {
            ($0, $0.defaultSettings)
        })
        disabledActions.removeAll()

        var firstFailure: HotKeyConfigurationError?
        for action in HotKeyAction.allCases {
            switch registrar.register(configuredHotKey(for: action), action: action) {
            case .success(let token):
                registrations[action] = token
            case .failure(let error):
                firstFailure = .registrationFailed(error.status)
            }
            if firstFailure != nil { break }
        }

        if let firstFailure {
            unregisterAll()
            configured = previous
            disabledActions = previouslyDisabled
            restoreAllRegistrations()
            notifyStateChange()
            return .failure(firstFailure)
        }

        do {
            try persistConfiguredHotKeys()
            errors.removeAll()
            notifyStateChange()
            return .success(())
        } catch {
            unregisterAll()
            configured = previous
            disabledActions = previouslyDisabled
            restoreAllRegistrations()
            notifyStateChange()
            return .failure(.persistenceFailed)
        }
    }

    func setCaptureSessionActive(_ isActive: Bool) {
        guard isCaptureSessionActive != isActive else { return }
        isCaptureSessionActive = isActive
        let restoreAction = HotKeyAction.restoreMostRecentlyHiddenPinnedImage
        if isActive {
            if let token = registrations.removeValue(forKey: restoreAction) {
                registrar.unregister(token)
            }
        } else if registrations[restoreAction] == nil,
                  !disabledActions.contains(restoreAction) {
            restoreRegistrationIfValid(
                configuredHotKey(for: restoreAction),
                action: restoreAction
            )
        }
        notifyStateChange()
    }

    private func registerConfiguredHotKeys() {
        for action in registrationOrder where !disabledActions.contains(action) {
            restoreRegistrationIfValid(configuredHotKey(for: action), action: action)
        }
    }

    private func restoreAllRegistrations() {
        for action in registrationOrder where !disabledActions.contains(action) {
            restoreRegistrationIfValid(configuredHotKey(for: action), action: action)
        }
    }

    private func reconcileMissingRegistrations() {
        for action in registrationOrder
            where registrations[action] == nil && !disabledActions.contains(action) {
            restoreRegistrationIfValid(configuredHotKey(for: action), action: action)
        }
    }

    private func hasRegisteredConflict(
        _ settings: HotKeySettings,
        excluding action: HotKeyAction
    ) -> Bool {
        registrations.keys.contains {
            $0 != action && configuredHotKey(for: $0) == settings
        }
    }

    private func restoreRegistrationIfValid(
        _ settings: HotKeySettings,
        action: HotKeyAction
    ) {
        if let conflict = SelectionToolbarState.fixedShortcutConflict(
            for: settings,
            keyCodeCharacterResolver: keyCodeCharacterResolver
        ) {
            errors[action] = .fixedToolbarConflict(conflict)
            return
        }
        guard HotKeyFormatter.isValidGlobalShortcut(settings) else {
            errors[action] = .missingModifier
            return
        }
        guard !hasRegisteredConflict(settings, excluding: action) else {
            errors[action] = .duplicate
            return
        }
        restoreRegistration(settings, action: action)
    }

    private func restoreRegistration(_ settings: HotKeySettings, action: HotKeyAction) {
        if action == .restoreMostRecentlyHiddenPinnedImage, isCaptureSessionActive {
            return
        }
        switch registrar.register(settings, action: action) {
        case .success(let token):
            registrations[action] = token
            errors[action] = nil
        case .failure(let error):
            registrations[action] = nil
            errors[action] = .registrationFailed(error.status)
        }
    }

    private func unregisterAll() {
        for token in registrations.values {
            registrar.unregister(token)
        }
        registrations.removeAll()
    }

    private func rollbackApplyTransaction(
        configured previousConfigured: [HotKeyAction: HotKeySettings],
        disabledActions previouslyDisabled: Set<HotKeyAction>,
        errors previousErrors: [HotKeyAction: HotKeyConfigurationError],
        affectedActions: [HotKeyAction],
        previouslyRegistered: Set<HotKeyAction>
    ) {
        for affectedAction in affectedActions {
            if let token = registrations.removeValue(forKey: affectedAction) {
                registrar.unregister(token)
            }
        }
        configured = previousConfigured
        disabledActions = previouslyDisabled
        errors = previousErrors
        for affectedAction in HotKeyAction.allCases
            where previouslyRegistered.contains(affectedAction) {
            restoreRegistrationIfValid(
                configuredHotKey(for: affectedAction),
                action: affectedAction
            )
            if registrations[affectedAction] != nil {
                errors[affectedAction] = previousErrors[affectedAction]
            }
        }
    }

    private func persistConfiguredHotKeys() throws {
        var settings = settingsStore.load()
        for action in HotKeyAction.allCases {
            if disabledActions.contains(action) {
                settings.hotkeys.removeValue(forKey: action.rawValue)
            } else {
                settings.hotkeys[action.rawValue] = configuredHotKey(for: action)
            }
        }
        settings.disabledHotkeys = Set(disabledActions.map(\.rawValue))
        try settingsStore.save(settings)
    }

    private func notifyStateChange() {
        onStateChange?()
    }
}

struct HotKeyFormatter {
    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9", UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab", UInt32(kVK_Delete): "Delete",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_ForwardDelete): "Forward Delete",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "Home", UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "Page Up", UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
    ]

    private static let menuKeys: [UInt32: String] = [
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9"
    ]

    static func displayString(_ settings: HotKeySettings) -> String {
        var value = ""
        if settings.modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if settings.modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if settings.modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if settings.modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        value += keyNames[settings.keyCode] ?? "Key \(settings.keyCode)"
        return value
    }

    static func toolbarShortcut(
        from settings: HotKeySettings
    ) -> SelectionToolbarState.ToolbarShortcut? {
        let key = eventCharacters(for: settings.keyCode) ?? ""
        let modifiers = eventModifierFlags(from: settings.modifiers)
        let commandOnly = modifiers == .command
        return SelectionToolbarState.ToolbarShortcut(
            key: key,
            modifiers: modifiers,
            iconName: commandOnly ? "command" : nil,
            displayText: commandOnly
                ? (keyNames[settings.keyCode] ?? key.uppercased())
                : displayString(settings),
            keyCode: settings.keyCode
        )
    }

    static func hasSupportedModifier(_ settings: HotKeySettings) -> Bool {
        let supported = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        return settings.modifiers & supported != 0
    }

    static func isValidGlobalShortcut(_ settings: HotKeySettings) -> Bool {
        hasSupportedModifier(settings)
            || standaloneFunctionKeyCodes.contains(settings.keyCode)
    }

    static func isDisplayableSystemShortcut(_ settings: HotKeySettings) -> Bool {
        let meaningfulModifiers = UInt32(cmdKey | optionKey | controlKey)
        if settings.modifiers & meaningfulModifiers != 0 {
            return true
        }
        return standaloneSystemKeyCodes.contains(settings.keyCode)
    }

    static func settings(from event: NSEvent) -> HotKeySettings {
        var modifiers: UInt32 = 0
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return HotKeySettings(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    static func menuEquivalent(_ settings: HotKeySettings) -> (String, NSEvent.ModifierFlags)? {
        let key: String?
        if let mapped = menuKeys[settings.keyCode] {
            key = mapped
        } else {
            key = keyNames[settings.keyCode]?.lowercased().count == 1
                ? keyNames[settings.keyCode]?.lowercased()
                : nil
        }
        guard let key else { return nil }
        var flags: NSEvent.ModifierFlags = []
        if settings.modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if settings.modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if settings.modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if settings.modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return (key, flags)
    }

    private static let standaloneFunctionKeyCodes: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
        UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
        UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12)
    ]

    private static let standaloneSystemKeyCodes =
        standaloneFunctionKeyCodes.union([UInt32(kVK_Escape)])

    private static let functionKeys: [UInt32: NSEvent.SpecialKey] = [
        UInt32(kVK_F1): .f1, UInt32(kVK_F2): .f2, UInt32(kVK_F3): .f3,
        UInt32(kVK_F4): .f4, UInt32(kVK_F5): .f5, UInt32(kVK_F6): .f6,
        UInt32(kVK_F7): .f7, UInt32(kVK_F8): .f8, UInt32(kVK_F9): .f9,
        UInt32(kVK_F10): .f10, UInt32(kVK_F11): .f11, UInt32(kVK_F12): .f12
    ]

    private static func eventCharacters(for keyCode: UInt32) -> String? {
        if keyCode == UInt32(kVK_Escape) {
            return "\u{1b}"
        }
        if let functionKey = functionKeys[keyCode] {
            return String(functionKey.unicodeScalar)
        }
        guard let keyName = keyNames[keyCode], keyName.count == 1 else {
            return nil
        }
        return keyName.lowercased()
    }

    static func eventModifierFlags(from modifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }
}

private func fourCharacterCode(_ string: String) -> FourCharCode {
    string.utf8.reduce(0) { result, character in
        (result << 8) + FourCharCode(character)
    }
}
