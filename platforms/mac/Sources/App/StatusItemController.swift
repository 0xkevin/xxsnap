import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let captureCoordinator: CaptureCoordinator
    private let statusItem: NSStatusItem

    init(captureCoordinator: CaptureCoordinator) {
        self.captureCoordinator = captureCoordinator
        statusItem = NSStatusBar.system.statusItem(withLength: 92)
        super.init()
        configureStatusItem()
    }

    @objc func capture() {
        captureCoordinator.startCapture()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func configureStatusItem() {
        NSLog("snipory configuring status item")
        statusItem.length = NSStatusItem.squareLength

        guard let button = statusItem.button else {
            NSLog("snipory status item has no button")
            return
        }

        button.title = ""
        let image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Snipory")
            ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snipory")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "Snipory 截图"
        NSLog("snipory status button configured image=%@ length=%.0f", image == nil ? "missing" : "ok", statusItem.length)

        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "截图", action: #selector(capture), keyEquivalent: "`")
        captureItem.keyEquivalentModifierMask = [.command]
        menu.addItem(captureItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }

        statusItem.menu = menu
    }
}
