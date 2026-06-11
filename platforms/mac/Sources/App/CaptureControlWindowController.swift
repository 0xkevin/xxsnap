import AppKit

@MainActor
final class CaptureControlWindowController: NSWindowController {
    private let captureCoordinator: CaptureCoordinator

    init(captureCoordinator: CaptureCoordinator) {
        self.captureCoordinator = captureCoordinator

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 96))
        let captureButton = NSButton(title: "截图", target: nil, action: #selector(capture))
        let quitButton = NSButton(title: "退出", target: nil, action: #selector(quit))

        captureButton.bezelStyle = .rounded
        captureButton.frame = NSRect(x: 20, y: 48, width: 180, height: 28)
        quitButton.bezelStyle = .rounded
        quitButton.frame = NSRect(x: 20, y: 14, width: 180, height: 28)

        contentView.addSubview(captureButton)
        contentView.addSubview(quitButton)

        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Snipory"
        window.contentView = contentView
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        captureButton.target = self
        quitButton.target = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func capture() {
        captureCoordinator.startCapture()
    }

    @objc private func quit() {
        AppTermination.isUserInitiated = true
        NSApplication.shared.terminate(nil)
    }
}
