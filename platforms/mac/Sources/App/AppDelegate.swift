import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var captureCoordinator: CaptureCoordinator?
    private var statusItemController: StatusItemController?
    private var hotKeyController: CaptureHotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("snipory applicationDidFinishLaunching")
        ProcessInfo.processInfo.disableAutomaticTermination("Snipory menu bar app stays available for capture")
        let captureCoordinator = CaptureCoordinator()
        self.captureCoordinator = captureCoordinator
        statusItemController = StatusItemController(captureCoordinator: captureCoordinator)
        hotKeyController = CaptureHotKeyController {
            captureCoordinator.startCapture()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("snipory applicationWillTerminate")
    }
}

private final class CaptureHotKeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let captureHandler: () -> Void

    init(captureHandler: @escaping () -> Void) {
        self.captureHandler = captureHandler
        install()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func install() {
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
                guard parameterStatus == noErr, hotKeyID.id == 1 else {
                    return noErr
                }

                let controller = Unmanaged<CaptureHotKeyController>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    controller.captureHandler()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            NSLog("snipory hotkey handler install failed status=%d", handlerStatus)
            return
        }

        let hotKeyID = EventHotKeyID(signature: fourCharacterCode("Snip"), id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_Grave),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if hotKeyStatus == noErr {
            NSLog("snipory registered hotkey command-backtick")
        } else {
            NSLog("snipory hotkey registration failed status=%d", hotKeyStatus)
        }
    }
}

private func fourCharacterCode(_ string: String) -> FourCharCode {
    string.utf8.reduce(0) { result, character in
        (result << 8) + FourCharCode(character)
    }
}
