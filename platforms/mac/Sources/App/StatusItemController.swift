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
        NSLog("xxsnap configuring status item")
        statusItem.length = NSStatusItem.squareLength

        guard let button = statusItem.button else {
            NSLog("xxsnap status item has no button")
            return
        }

        button.title = ""
        let image = statusBarImage()
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "xxsnap 截图"
        NSLog("xxsnap status button configured image=%@ length=%.0f", image == nil ? "missing" : "ok", statusItem.length)

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

    private func statusBarImage() -> NSImage? {
        let image = Bundle.main.url(forResource: "xxsnap", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(named: "xxsnap")
            ?? NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "xxsnap")
            ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "xxsnap")

        image?.accessibilityDescription = "xxsnap"
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        return image
    }
}
