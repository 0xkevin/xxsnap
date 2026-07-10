import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var captureCoordinator: CaptureCoordinator?
    private var statusItemController: StatusItemController?
    private var hotKeyController: CaptureHotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("xxsnap applicationDidFinishLaunching")
        ProcessInfo.processInfo.disableAutomaticTermination("xxsnap menu bar app stays available for capture")
        let captureCoordinator = CaptureCoordinator()
        self.captureCoordinator = captureCoordinator
        statusItemController = StatusItemController(captureCoordinator: captureCoordinator)
        let hotKeyController = CaptureHotKeyController(
            captureHandler: {
                captureCoordinator.startCapture()
            },
            restorePinnedImageHandler: {
                captureCoordinator.restoreMostRecentlyHiddenPinnedWindow()
            }
        )
        self.hotKeyController = hotKeyController
        captureCoordinator.captureOverlayDidPresent = { [weak hotKeyController] in
            hotKeyController?.setRestorePinnedImageHotKeyEnabled(false)
        }
        captureCoordinator.captureSessionDidEnd = { [weak hotKeyController] in
            hotKeyController?.setRestorePinnedImageHotKeyEnabled(true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("xxsnap applicationWillTerminate")
    }
}

private final class CaptureHotKeyController {
    private enum HotKeyID {
        static let capture: UInt32 = 1
        static let restorePinnedImage: UInt32 = 2
    }

    private var captureHotKeyRef: EventHotKeyRef?
    private var restorePinnedImageHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let captureHandler: () -> Void
    private let restorePinnedImageHandler: () -> Void

    init(
        captureHandler: @escaping () -> Void,
        restorePinnedImageHandler: @escaping () -> Void
    ) {
        self.captureHandler = captureHandler
        self.restorePinnedImageHandler = restorePinnedImageHandler
        installEventHandler()
        captureHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_Grave),
            modifiers: UInt32(cmdKey),
            id: HotKeyID.capture
        )
        setRestorePinnedImageHotKeyEnabled(true)
    }

    deinit {
        if let captureHotKeyRef {
            UnregisterEventHotKey(captureHotKeyRef)
        }
        if let restorePinnedImageHotKeyRef {
            UnregisterEventHotKey(restorePinnedImageHotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func setRestorePinnedImageHotKeyEnabled(_ isEnabled: Bool) {
        if isEnabled {
            guard restorePinnedImageHotKeyRef == nil else {
                return
            }
            restorePinnedImageHotKeyRef = registerHotKey(
                keyCode: UInt32(kVK_ANSI_1),
                modifiers: UInt32(cmdKey),
                id: HotKeyID.restorePinnedImage
            )
        } else if let restorePinnedImageHotKeyRef {
            UnregisterEventHotKey(restorePinnedImageHotKeyRef)
            self.restorePinnedImageHotKeyRef = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
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
                guard parameterStatus == noErr else {
                    return noErr
                }

                let controller = Unmanaged<CaptureHotKeyController>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    switch hotKeyID.id {
                    case HotKeyID.capture:
                        controller.captureHandler()
                    case HotKeyID.restorePinnedImage:
                        controller.restorePinnedImageHandler()
                    default:
                        break
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            NSLog("xxsnap hotkey handler install failed status=%d", handlerStatus)
            return
        }
    }

    private func registerHotKey(
        keyCode: UInt32,
        modifiers: UInt32,
        id: UInt32
    ) -> EventHotKeyRef? {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharacterCode("xxsp"), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status != noErr {
            NSLog("xxsnap hotkey registration failed id=%u status=%d", id, status)
        }
        return status == noErr ? reference : nil
    }
}

private func fourCharacterCode(_ string: String) -> FourCharCode {
    string.utf8.reduce(0) { result, character in
        (result << 8) + FourCharCode(character)
    }
}
