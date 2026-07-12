import AppKit
import CoreGraphics
import UniformTypeIdentifiers

@MainActor
protocol ScrollCaptureSessionRunning: AnyObject {
    func start() async throws
    func finish() async throws -> NSImage
    @discardableResult func cancel() -> ScrollCaptureSeed
}

extension ScrollCaptureSession: ScrollCaptureSessionRunning {}

@MainActor
protocol ScrollCapturePresenting: AnyObject {
    func start()
    func stop()
    func updatePreview(_ image: NSImage, following edge: ScrollCapturePreviewEdge)
    func setWarning(_ text: String)
    func clearWarning()
    func updatePlacement(selectionFrame: NSRect, visibleFrame: NSRect)
    func resetTerminalActionsForRetry()
}

extension ScrollCapturePresentationController: ScrollCapturePresenting {}

@MainActor
protocol LongImageEditorPresenting: AnyObject {
    var onClose: (() -> Void)? { get set }
    func show()
}

extension LongImageEditorWindowController: LongImageEditorPresenting {}

enum LongImageFallbackChoice {
    case save
    case cancel
}

struct ScrollCapturePresentationContext {
    let geometry: ScrollCaptureControlGeometry
    let selectionFrame: NSRect
    let visibleFrame: NSRect
    let language: AppLanguage
    let onFinish: @MainActor () -> Void
    let onCancel: @MainActor () -> Void
}

private enum ScrollCaptureLifecyclePhase: Equatable {
    case idle
    case starting
    case finishPending
    case active
    case finishing
    case cancelling
}

@MainActor
final class CaptureCoordinator {
    var captureOverlayDidPresent: (() -> Void)?
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
    private var mostRecentlyHiddenPinnedWindow: PinnedImageWindowPresenting?
    private var frozenDesktopImage: NSImage?
    private let pinnedWindowFactory: @MainActor (NSImage, NSRect) -> PinnedImageWindowPresenting
    private let scrollCaptureSessionFactory: @MainActor (
        ScrollCaptureSeed,
        @escaping @MainActor (ScrollCapturePresentationUpdate) -> Void
    ) -> any ScrollCaptureSessionRunning
    private let scrollCapturePresentationFactory: @MainActor (
        ScrollCapturePresentationContext
    ) -> any ScrollCapturePresenting
    private let longImageHandoff: (@MainActor (NSImage, ScrollCaptureSeed) -> Void)?
    private let longImageEditorFactory: @MainActor (
        NSImage, ScrollCaptureSeed, LongImageEditorActions
    ) throws -> (any LongImageEditorPresenting)?
    private let longImageFallbackPresenter: @MainActor (NSImage) -> LongImageFallbackChoice
    private let longImageCopyHandler: (@MainActor (NSImage) -> Bool)?
    private let longImageSaveHandler: (@MainActor (NSImage) -> Bool)?
    private var longImageEditor: (any LongImageEditorPresenting)?
    private var longImageLifecycleActive = false
    private var scrollCaptureSession: (any ScrollCaptureSessionRunning)?
    private var scrollCapturePresentation: (any ScrollCapturePresenting)?
    private var scrollCaptureTask: Task<Void, Never>?
    private var scrollCaptureSeed: ScrollCaptureSeed?
    private var scrollCaptureFinishPending = false
    private var scrollCapturePhase: ScrollCaptureLifecyclePhase = .idle
    private var scrollCaptureGeneration: UInt64 = 0

    init(
        permissionCoordinator: PermissionCoordinator,
        screenCaptureService: ScreenCaptureService,
        settingsStore: SettingsStore = SettingsStore(),
        pinnedWindowFactory: @escaping @MainActor (NSImage, NSRect) -> PinnedImageWindowPresenting = {
            PinnedImageWindowController(image: $0, screenRect: $1)
        },
        scrollCaptureSessionFactory: (@MainActor (
            ScrollCaptureSeed,
            @escaping @MainActor (ScrollCapturePresentationUpdate) -> Void
        ) -> any ScrollCaptureSessionRunning)? = nil,
        scrollCapturePresentationFactory: @escaping @MainActor (
            ScrollCapturePresentationContext
        ) -> any ScrollCapturePresenting = CaptureCoordinator.makeScrollCapturePresentation,
        screenVisibleFrameResolver: (@MainActor (NSRect) -> NSRect)? = nil,
        longImageHandoff: (@MainActor (NSImage, ScrollCaptureSeed) -> Void)? = nil,
        longImageEditorFactory: (@MainActor (
            NSImage, ScrollCaptureSeed, LongImageEditorActions
        ) throws -> (any LongImageEditorPresenting)?)? = nil,
        longImageFallbackPresenter: (@MainActor (NSImage) -> LongImageFallbackChoice)? = nil,
        longImageCopyHandler: (@MainActor (NSImage) -> Bool)? = nil,
        longImageSaveHandler: (@MainActor (NSImage) -> Bool)? = nil
    ) {
        self.permissionCoordinator = permissionCoordinator
        self.screenCaptureService = screenCaptureService
        self.settingsStore = settingsStore
        self.pinnedWindowFactory = pinnedWindowFactory
        self.scrollCaptureSessionFactory = scrollCaptureSessionFactory ?? { seed, update in
            let maximumAcceptedBytes = Self.defaultScrollCaptureMaximumAcceptedBytes
            guard let bridge = ScrollCaptureBridge(maximumAcceptedBytes: maximumAcceptedBytes) else {
                preconditionFailure("Unable to create scroll capture bridge")
            }
            return ScrollCaptureSession(
                seed: seed,
                capturer: screenCaptureService,
                stitcher: bridge,
                clock: ContinuousScrollCaptureClock(),
                activityMonitor: ScrollActivityMonitor(),
                presentation: update
            )
        }
        self.scrollCapturePresentationFactory = scrollCapturePresentationFactory
        let resolveVisibleFrame = screenVisibleFrameResolver ?? Self.visibleFrame(containing:)
        self.longImageHandoff = longImageHandoff
        self.longImageEditorFactory = longImageEditorFactory ?? { image, seed, actions in
            LongImageEditorWindowController(
                image: image,
                seed: seed,
                visibleFrame: resolveVisibleFrame(seed.screenRect),
                actions: actions,
                language: settingsStore.load().language
            )
        }
        self.longImageFallbackPresenter = longImageFallbackPresenter ?? Self.presentLongImageFallback
        self.longImageCopyHandler = longImageCopyHandler
        self.longImageSaveHandler = longImageSaveHandler
    }

    convenience init() {
        self.init(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService()
        )
    }

    deinit {
        scrollCaptureTask?.cancel()
        let presentation = scrollCapturePresentation
        let session = scrollCaptureSession
        Task { @MainActor in
            presentation?.stop()
            _ = session?.cancel()
        }
    }

    @discardableResult
    func restoreMostRecentlyHiddenPinnedWindow() -> Bool {
        guard overlayWindow == nil,
              let controller = mostRecentlyHiddenPinnedWindow
        else {
            return false
        }
        mostRecentlyHiddenPinnedWindow = nil
        controller.show()
        return true
    }

    func startCapture() {
        NSLog("xxsnap startCapture")
        guard canStartCapture else {
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
            self.installScrollCaptureCallbacks(on: overlayWindow)
            self.captureOverlayDidPresent?()
            overlayWindow.present()
        }
    }

    private var canStartCapture: Bool {
        overlayWindow == nil
            && captureTask == nil
            && startTask == nil
            && !longImageLifecycleActive
            && scrollCapturePhase == .idle
    }

    private static var defaultScrollCaptureMaximumAcceptedBytes: UInt {
        // Cap the stitcher's retained image storage while scaling down on memory-constrained Macs.
        let physical = ProcessInfo.processInfo.physicalMemory
        let desired = min(UInt64(512 * 1_024 * 1_024), max(UInt64(128 * 1_024 * 1_024), physical / 8))
        return UInt(min(desired, UInt64(UInt.max)))
    }

    private static func makeScrollCapturePresentation(
        _ context: ScrollCapturePresentationContext
    ) -> any ScrollCapturePresenting {
        ScrollCapturePresentationController(
            toolbarFrame: context.geometry.toolbarFrame,
            finishButtonFrame: context.geometry.finishButtonFrame,
            cancelButtonFrame: context.geometry.cancelButtonFrame,
            selectionFrame: context.selectionFrame,
            visibleFrame: context.visibleFrame,
            language: context.language,
            onFinish: context.onFinish,
            onCancel: context.onCancel
        )
    }

    private func installScrollCaptureCallbacks(on overlay: SelectionOverlayWindow) {
        overlay.onScrollCaptureRequested = { [weak self, weak overlay] seed in
            guard let self, self.overlayWindow === overlay else { return }
            self.requestScrollCapture(seed: seed)
        }
        overlay.onScrollCaptureFinishRequested = { [weak self, weak overlay] in
            guard let self, self.overlayWindow === overlay else { return }
            self.finishScrollCapture()
        }
        overlay.onScrollCaptureCancelRequested = { [weak self, weak overlay] in
            guard let self, self.overlayWindow === overlay else { return }
            self.cancelScrollCapture()
        }
    }

    private func requestScrollCapture(seed: ScrollCaptureSeed) {
        guard scrollCapturePhase == .idle,
              scrollCaptureSession == nil,
              scrollCapturePresentation == nil,
              scrollCaptureTask == nil,
              let overlay = overlayWindow
        else { return }

        scrollCaptureFinishPending = false
        scrollCapturePhase = .starting
        overlay.setScrollCaptureCapturing()
        scrollCaptureGeneration &+= 1
        let generation = scrollCaptureGeneration
        let language = settingsStore.load().language
        guard let geometry = overlay.scrollCaptureControlGeometry else {
            overlay.restoreAfterScrollCaptureCancellation()
            overlay.present()
            scrollCaptureFinishPending = false
            scrollCapturePhase = .idle
            return
        }
        let visibleFrame = Self.visibleFrame(containing: seed.screenRect)
        let presentation = scrollCapturePresentationFactory(ScrollCapturePresentationContext(
            geometry: geometry,
            selectionFrame: seed.screenRect,
            visibleFrame: visibleFrame,
            language: language,
            onFinish: { [weak self] in self?.finishScrollCapture() },
            onCancel: { [weak self] in self?.cancelScrollCapture() }
        ))
        let session = scrollCaptureSessionFactory(seed) { [weak self] update in
            self?.receiveScrollCaptureUpdate(update, generation: generation)
        }
        scrollCaptureSeed = seed
        scrollCaptureSession = session
        scrollCapturePresentation = presentation
        presentation.updatePlacement(selectionFrame: seed.screenRect, visibleFrame: visibleFrame)
        presentation.start()
        scrollCaptureTask = Task { @MainActor [weak self, weak session] in
            do {
                try await session?.start()
                guard let self, self.scrollCaptureGeneration == generation,
                      self.scrollCaptureSession === session else { return }
                switch self.scrollCapturePhase {
                case .starting:
                    self.scrollCaptureTask = nil
                    self.scrollCaptureFinishPending = false
                    self.scrollCapturePhase = .active
                case .finishPending:
                    self.scrollCaptureTask = nil
                    self.finishScrollCapture()
                case .idle, .active, .finishing, .cancelling:
                    return
                }
            } catch {
                guard let self, self.scrollCaptureGeneration == generation,
                      self.scrollCaptureSession === session else { return }
                self.recoverScrollCaptureOverlay(generation: generation)
            }
        }
    }

    private static func visibleFrame(containing rect: NSRect) -> NSRect {
        let point = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })?.visibleFrame
            ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? rect
    }

    private func receiveScrollCaptureUpdate(
        _ update: ScrollCapturePresentationUpdate,
        generation: UInt64
    ) {
        guard generation == scrollCaptureGeneration,
              let overlay = overlayWindow,
              let presentation = scrollCapturePresentation
        else { return }
        let l10n = L10n(language: settingsStore.load().language)
        switch update {
        case .terminalCommand(.finish):
            finishScrollCapture()
        case .terminalCommand(.cancel):
            cancelScrollCapture()
        case .preview(let image, let edge):
            presentation.updatePreview(image, following: edge)
        case .append:
            break
        case .state(.capturing):
            overlay.setScrollCaptureCapturing()
        case .state(.paused(let reason)):
            let key: L10n.Key
            switch reason {
            case .resourceLimit: key = .scrollCaptureResourceLimit
            case .captureFailure: key = .scrollCaptureFailure
            }
            let message = l10n.text(key)
            overlay.setScrollCapturePaused(message: message)
            presentation.setWarning(message)
        case .warning(.lowConfidence):
            overlay.setScrollCaptureCapturing()
            presentation.setWarning(l10n.text(.scrollCaptureLowConfidence))
        case .warning(nil):
            presentation.clearWarning()
        case .state:
            break
        }
    }

    private func finishScrollCapture() {
        switch scrollCapturePhase {
        case .starting:
            scrollCaptureFinishPending = true
            scrollCapturePhase = .finishPending
            return
        case .active:
            break
        case .finishPending:
            guard scrollCaptureFinishPending, scrollCaptureTask == nil else { return }
        case .idle, .finishing, .cancelling:
            return
        }
        guard let session = scrollCaptureSession,
              let seed = scrollCaptureSeed,
              scrollCapturePresentation != nil,
              scrollCaptureTask == nil
        else { return }
        scrollCapturePhase = .finishing
        scrollCaptureFinishPending = false
        let generation = scrollCaptureGeneration
        scrollCaptureTask = Task { @MainActor [weak self, weak session] in
            do {
                guard let image = try await session?.finish() else { return }
                guard let self, self.scrollCaptureGeneration == generation,
                      self.scrollCaptureSession === session else { return }
                self.scrollCapturePresentation?.stop()
                self.scrollCapturePresentation = nil
                self.scrollCaptureSession = nil
                self.scrollCaptureSeed = nil
                self.scrollCaptureTask = nil
                if let overlay = self.overlayWindow {
                    overlay.finishScrollCaptureAndDismiss()
                    self.overlayWindow = nil
                }
                self.frozenDesktopImage = nil
                self.lastCapture = image
                self.scrollCaptureFinishPending = false
                self.scrollCapturePhase = .idle
                if let longImageHandoff = self.longImageHandoff {
                    longImageHandoff(image, seed)
                    self.captureSessionDidEnd?()
                } else {
                    self.longImageLifecycleActive = true
                    self.presentLongImageEditor(image: image, seed: seed)
                }
            } catch {
                guard let self, self.scrollCaptureGeneration == generation,
                      self.scrollCaptureSession === session else { return }
                self.scrollCaptureTask = nil
                self.scrollCaptureFinishPending = false
                self.scrollCapturePhase = .active
                self.scrollCapturePresentation?.resetTerminalActionsForRetry()
                self.overlayWindow?.resetScrollCaptureTerminalActionsForRetry()
            }
        }
    }

    private func cancelScrollCapture() {
        switch scrollCapturePhase {
        case .starting, .active:
            break
        case .idle, .finishPending, .finishing, .cancelling:
            return
        }
        guard let session = scrollCaptureSession else { return }
        scrollCapturePhase = .cancelling
        scrollCaptureGeneration &+= 1
        scrollCaptureTask?.cancel()
        scrollCaptureTask = nil
        _ = session.cancel()
        scrollCapturePresentation?.stop()
        scrollCapturePresentation = nil
        scrollCaptureSession = nil
        scrollCaptureSeed = nil
        scrollCaptureFinishPending = false
        overlayWindow?.restoreAfterScrollCaptureCancellation()
        overlayWindow?.present()
        scrollCapturePhase = .idle
    }

    private func recoverScrollCaptureOverlay(generation: UInt64) {
        guard scrollCaptureGeneration == generation else { return }
        scrollCaptureGeneration &+= 1
        scrollCaptureTask = nil
        scrollCapturePresentation?.stop()
        scrollCapturePresentation = nil
        _ = scrollCaptureSession?.cancel()
        scrollCaptureSession = nil
        scrollCaptureSeed = nil
        scrollCaptureFinishPending = false
        overlayWindow?.restoreAfterScrollCaptureCancellation()
        overlayWindow?.present()
        scrollCapturePhase = .idle
    }

    private func presentLongImageEditor(image: NSImage, seed: ScrollCaptureSeed) {
        let actions = LongImageEditorActions(
            copy: { [weak self] rendered in
                guard let self else { return false }
                if let handler = self.longImageCopyHandler { return handler(rendered) }
                self.copyToPasteboard(rendered)
                return true
            },
            save: { [weak self] rendered in
                guard let self else { return false }
                return self.longImageSaveHandler?(rendered) ?? self.saveLastCapture(rendered)
            },
            pin: { [weak self] rendered in
                guard let self else { return false }
                self.presentPinnedImage(rendered, screenRect: NSRect(origin: seed.screenRect.origin, size: rendered.size))
                return true
            }
        )
        do {
            guard let editor = try longImageEditorFactory(image, seed, actions) else {
                presentLongImageFallback(image)
                return
            }
            longImageEditor = editor
            let editorID = ObjectIdentifier(editor)
            editor.onClose = { [weak self] in
                guard let self, let current = self.longImageEditor,
                      ObjectIdentifier(current) == editorID else { return }
                self.longImageEditor = nil
                self.longImageLifecycleActive = false
                self.captureSessionDidEnd?()
            }
            editor.show()
        } catch {
            presentLongImageFallback(image)
        }
    }

    private func presentLongImageFallback(_ image: NSImage) {
        while true {
            switch longImageFallbackPresenter(image) {
            case .save:
                let didSave = longImageSaveHandler?(image) ?? saveLastCapture(image)
                if !didSave { continue }
            case .cancel:
                break
            }
            longImageEditor = nil
            longImageLifecycleActive = false
            captureSessionDidEnd?()
            return
        }
    }

    private static func presentLongImageFallback(_ image: NSImage) -> LongImageFallbackChoice {
        let alert = NSAlert()
        alert.messageText = "无法打开长截图编辑器"
        alert.informativeText = "完整长截图已保留。是否立即保存为 PNG？"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn ? .save : .cancel
    }

    private func presentPinnedImage(_ image: NSImage, screenRect: NSRect) {
        let controller = pinnedWindowFactory(image, screenRect)
        pinnedWindowControllers.append(controller)
        let controllerID = ObjectIdentifier(controller)
        controller.onHide = { [weak self] in
            guard let self,
                  let hidden = self.pinnedWindowControllers.first(where: { ObjectIdentifier($0) == controllerID })
            else { return }
            self.mostRecentlyHiddenPinnedWindow = hidden
        }
        controller.onClose = { [weak self] in
            guard let self else { return }
            self.pinnedWindowControllers.removeAll { ObjectIdentifier($0) == controllerID }
            if let recent = self.mostRecentlyHiddenPinnedWindow, ObjectIdentifier(recent) == controllerID {
                self.mostRecentlyHiddenPinnedWindow = nil
            }
        }
        controller.show()
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
                    let controllerID = ObjectIdentifier(controller)
                    controller.onHide = { [weak self] in
                        guard let self,
                              let hiddenController = self.pinnedWindowControllers.first(where: {
                                  ObjectIdentifier($0) == controllerID
                              })
                        else {
                            return
                        }
                        self.mostRecentlyHiddenPinnedWindow = hiddenController
                    }
                    controller.onClose = { [weak self] in
                        guard let self else {
                            return
                        }
                        self.pinnedWindowControllers.removeAll {
                            ObjectIdentifier($0) == controllerID
                        }
                        if let recent = self.mostRecentlyHiddenPinnedWindow,
                           ObjectIdentifier(recent) == controllerID {
                            self.mostRecentlyHiddenPinnedWindow = nil
                        }
                    }
                    controller.show()
                case .finishEditing:
                    break
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
    var test_isScrollCapturePhaseIdle: Bool { scrollCapturePhase == .idle }
    var test_canStartCapture: Bool { canStartCapture }
    var test_lastCapture: NSImage? {
        lastCapture
    }

    var test_hasLongImageEditor: Bool { longImageEditor != nil }
    var test_longImageEditorWindowFrame: NSRect? {
        (longImageEditor as? LongImageEditorWindowController)?.test_initialWindowFrame
    }

    var test_pinnedWindowCount: Int {
        pinnedWindowControllers.count
    }

    var test_retiredOverlayCount: Int {
        retiredOverlayWindows.count
    }

    var test_hasScrollCaptureSession: Bool {
        scrollCaptureSession != nil
    }

    var test_overlayWindow: SelectionOverlayWindow? {
        overlayWindow
    }

    func test_installOverlayWindow(_ overlay: SelectionOverlayWindow) {
        overlayWindow = overlay
        installScrollCaptureCallbacks(on: overlay)
    }

    func test_requestScrollCapture(seed: ScrollCaptureSeed) {
        overlayWindow?.test_setLockedSelectionRect(seed.snapshotRect)
        requestScrollCapture(seed: seed)
    }

    func test_cancelScrollCapture() {
        cancelScrollCapture()
    }

    func test_handleSelection(_ result: CaptureSelectionResult?, frozenDesktopImage: NSImage?) {
        self.frozenDesktopImage = frozenDesktopImage
        handleSelection(result)
    }
}
#endif
