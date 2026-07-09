import AppKit
import CoreGraphics
import UniformTypeIdentifiers

@MainActor
final class CaptureCoordinator {
    var captureSessionDidEnd: (() -> Void)?

    private var lastCapture: NSImage?
    private let permissionCoordinator: PermissionCoordinator
    private let screenCaptureService: ScreenCaptureService
    private let settingsStore: SettingsStore
    private var captureTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var overlayWindow: SelectionOverlayWindow?
    private var retiredOverlayWindows: [SelectionOverlayWindow] = []
    private var pinnedWindowControllers: [PinnedImageWindowPresenting] = []
    private var frozenDesktopImage: NSImage?
    private let pinnedWindowFactory: @MainActor (NSImage, NSRect) -> PinnedImageWindowPresenting

    init(
        permissionCoordinator: PermissionCoordinator,
        screenCaptureService: ScreenCaptureService,
        settingsStore: SettingsStore = SettingsStore(),
        pinnedWindowFactory: @escaping @MainActor (NSImage, NSRect) -> PinnedImageWindowPresenting = {
            PinnedImageWindowController(image: $0, screenRect: $1)
        }
    ) {
        self.permissionCoordinator = permissionCoordinator
        self.screenCaptureService = screenCaptureService
        self.settingsStore = settingsStore
        self.pinnedWindowFactory = pinnedWindowFactory
    }

    convenience init() {
        self.init(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService()
        )
    }

    func startCapture() {
        NSLog("xxsnap startCapture")
        guard overlayWindow == nil, captureTask == nil, startTask == nil else {
            NSLog("xxsnap startCapture ignored because capture is already active")
            return
        }

        if !permissionCoordinator.hasScreenCapturePermission() {
            NSLog("xxsnap missing screen capture permission")
            guard permissionCoordinator.shouldShowScreenCaptureGuidance() else {
                NSLog("xxsnap suppressing repeated screen capture permission alert")
                return
            }

            if permissionCoordinator.requestScreenCapturePermissionOnce() {
                showPermissionRestartAlert()
            } else {
                showPermissionSettingsAlert()
            }
            return
        }

        startTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.startTask = nil
            }
            let refreshTargetApplication = Self.refreshTargetApplication()

            let backgroundImage: NSImage?
            do {
                backgroundImage = try await screenCaptureService.captureDesktopImage()
                frozenDesktopImage = backgroundImage
            } catch {
                NSLog("xxsnap desktop snapshot failed before overlay: \(error.localizedDescription)")
                backgroundImage = nil
                frozenDesktopImage = nil
            }

            let settings = settingsStore.load()
            let overlayWindow = SelectionOverlayWindow(
                backgroundImage: backgroundImage,
                settings: settings,
                featureGate: FeatureGate(license: settings.license),
                refreshHandler: { [weak self] in
                    guard let self else {
                        return nil
                    }
                    let overlayWindow = self.overlayWindow
                    await Self.sleepForRefreshInterval(nanoseconds: 120_000_000)
                    if let refreshTargetApplication {
                        refreshTargetApplication.activate(options: [])
                        await Self.sleepForRefreshInterval(nanoseconds: 80_000_000)
                        Self.sendRefreshShortcut(to: refreshTargetApplication.processIdentifier)
                        await Self.sleepForRefreshInterval(nanoseconds: 600_000_000)
                    }
                    let refreshedImage = try await self.screenCaptureService.captureDesktopImage()
                    self.frozenDesktopImage = refreshedImage
                    overlayWindow?.present()
                    return refreshedImage
                }
            ) { [weak self] result in
                self?.handleSelection(result)
            }

            self.overlayWindow = overlayWindow
            overlayWindow.present()
        }
    }

    private func showPermissionRestartAlert() {
        let alert = NSAlert()
        alert.messageText = "需要录屏权限"
        alert.informativeText = "请在系统设置中允许 xxsnap 录屏，然后退出并重新打开 xxsnap。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            openScreenCaptureSettings()
        }
    }

    private func showPermissionSettingsAlert() {
        let alert = NSAlert()
        alert.messageText = "xxsnap 没有录屏权限"
        alert.informativeText = "请在系统设置 > 隐私与安全性 > 录屏与系统录音中打开 xxsnap。打开后需要重启 xxsnap。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            openScreenCaptureSettings()
        }
    }

    private func openScreenCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated static func shouldRefreshTargetApplication(
        targetBundleIdentifier: String?,
        mainBundleIdentifier: String?
    ) -> Bool {
        guard let targetBundleIdentifier, !targetBundleIdentifier.isEmpty else {
            return false
        }
        return targetBundleIdentifier != mainBundleIdentifier
    }

    private static func refreshTargetApplication() -> NSRunningApplication? {
        let app = NSWorkspace.shared.frontmostApplication
        guard shouldRefreshTargetApplication(
            targetBundleIdentifier: app?.bundleIdentifier,
            mainBundleIdentifier: Bundle.main.bundleIdentifier
        ) else {
            return nil
        }
        return app
    }

    private static func sendRefreshShortcut(to processIdentifier: pid_t) {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 15, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 15, keyDown: false)
        else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
    }

    private static func sleepForRefreshInterval(nanoseconds: UInt64) async {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
        } catch {
        }
    }

    private func handleSelection(_ result: CaptureSelectionResult?) {
        if let overlayWindow {
            retiredOverlayWindows.append(overlayWindow)
        }
        overlayWindow = nil

        guard let result, !result.screenRect.isEmpty else {
            NSLog("xxsnap selection cancelled or empty")
            frozenDesktopImage = nil
            captureSessionDidEnd?()
            return
        }
        NSLog("xxsnap handling selection annotations=%ld rect=(%.0f, %.0f, %.0f, %.0f)", result.annotations.count, result.screenRect.minX, result.screenRect.minY, result.screenRect.width, result.screenRect.height)

        captureTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.captureTask = nil
                self.captureSessionDidEnd?()
            }

            do {
                let image: NSImage
                if let frozenDesktopImage = self.frozenDesktopImage,
                   let croppedImage = Self.crop(image: frozenDesktopImage, rect: result.snapshotRect) {
                    image = croppedImage
                } else {
                    image = try await screenCaptureService.captureImage(in: result.screenRect)
                }
                let exportedImage = CaptureAnnotationRenderer.render(
                    image: image,
                    annotations: result.annotations,
                    eraserMasks: result.eraserMasks
                )
                lastCapture = exportedImage
                self.frozenDesktopImage = nil
                switch result.action {
                case .copy:
                    copyToPasteboard(exportedImage)
                case .save:
                    if !saveLastCapture(exportedImage) {
                        NSLog("xxsnap save was cancelled or failed")
                    }
                case .pin:
                    let controller = pinnedWindowFactory(exportedImage, result.screenRect)
                    pinnedWindowControllers.append(controller)
                    if let pinnedController = controller as? PinnedImageWindowController {
                        pinnedController.onClose = { [weak self, weak pinnedController] in
                            guard let pinnedController else {
                                return
                            }
                            self?.pinnedWindowControllers.removeAll { $0 === pinnedController }
                        }
                    }
                    controller.show()
                }
                NSLog(
                    "xxsnap capture completed: %.0fx%.0f",
                    exportedImage.size.width,
                    exportedImage.size.height
                )
            } catch {
                self.frozenDesktopImage = nil
                NSLog("xxsnap capture failed: \(error.localizedDescription)")
            }
        }
    }

    static func crop(image: NSImage, rect: NSRect) -> NSImage? {
        let normalizedRect = rect.standardized
        guard !normalizedRect.isEmpty else {
            return nil
        }

        let imageBounds = NSRect(origin: .zero, size: image.size)
        let clippedRect = normalizedRect.intersection(imageBounds)
        guard !clippedRect.isEmpty else {
            return nil
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let pixelRect = CGRect(
            x: clippedRect.minX * scaleX,
            y: (image.size.height - clippedRect.maxY) * scaleY,
            width: clippedRect.width * scaleX,
            height: clippedRect.height * scaleY
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard !pixelRect.isEmpty, let croppedImage = cgImage.cropping(to: pixelRect) else {
            return nil
        }

        return NSImage(cgImage: croppedImage, size: clippedRect.size)
    }

    @discardableResult
    func saveLastCapture(_ image: NSImage? = nil) -> Bool {
        guard
            let imageToSave = image ?? lastCapture,
            let tiffData = imageToSave.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return false
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = Self.defaultCaptureFilename()
        savePanel.level = .modalPanel

        NSApp.activate(ignoringOtherApps: true)
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            return false
        }

        do {
            try pngData.write(to: destinationURL)
            return true
        } catch {
            NSLog("xxsnap save failed: \(error.localizedDescription)")
            return false
        }
    }

    private func copyToPasteboard(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    nonisolated static func defaultCaptureFilename(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "xxsnap 截图 \(formatter.string(from: date)).png"
    }
}

#if DEBUG
extension CaptureCoordinator {
    var test_lastCapture: NSImage? {
        lastCapture
    }

    var test_pinnedWindowCount: Int {
        pinnedWindowControllers.count
    }

    func test_handleSelection(_ result: CaptureSelectionResult?, frozenDesktopImage: NSImage?) {
        self.frozenDesktopImage = frozenDesktopImage
        handleSelection(result)
    }
}
#endif
