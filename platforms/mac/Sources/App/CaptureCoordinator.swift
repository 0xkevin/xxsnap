import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@MainActor
protocol ScrollCaptureSessionRunning: AnyObject {
    func start() async throws
    func performStep(direction: ScrollCaptureDirection) async throws
    func finish() async throws -> NSImage
    @discardableResult func cancel() -> ScrollCaptureSeed
}

extension ScrollCaptureSessionRunning {
    func performStep(direction: ScrollCaptureDirection) async throws {}
}

extension ScrollCaptureSession: ScrollCaptureSessionRunning {}

@MainActor
protocol ScrollCapturePresenting: AnyObject {
    func start()
    func stop()
    func updatePreview(
        _ image: NSImage,
        following edge: ScrollCapturePreviewEdge,
        viewport: ScrollCapturePreviewViewport
    )
    func moveViewportIndicator(_ activity: ScrollCaptureScrollActivity)
    func setWarning(_ text: String)
    func clearWarning()
    func updatePlacement(selectionFrame: NSRect, visibleFrame: NSRect)
    func resetTerminalActionsForRetry()
    func updateLanguage(_ language: AppLanguage)
}

extension ScrollCapturePresenting {
    func updateLanguage(_ language: AppLanguage) {}
}

extension ScrollCapturePresentationController: ScrollCapturePresenting {}

@MainActor
protocol LongImageEditorPresenting: AnyObject {
    var onClose: (() -> Void)? { get set }
    func show()
    func updateLanguage(_ language: AppLanguage)
    func updateTitleStyle(_ style: LongImageEditorTitleStyle)
}

extension LongImageEditorPresenting {
    func updateLanguage(_ language: AppLanguage) {}
    func updateTitleStyle(_ style: LongImageEditorTitleStyle) {}
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
}

private enum ScrollCaptureLifecyclePhase: Equatable {
    case idle
    case starting
    case finishPending
    case active
    case finishing
    case cancelling
}

private enum CaptureOverlayMode {
    case region
    case textRecognition
    case teachingPen
}

private final class CaptureLanguageSnapshot {
    var language: AppLanguage

    init(language: AppLanguage) {
        self.language = language
    }
}

@MainActor
final class CaptureCoordinator {
    var captureOverlayDidPresent: (() -> Void)?
    var captureSessionDidEnd: (() -> Void)?
    var shortcutFeedbackDidRequest: ((NSEvent) -> Void)?

    private var lastCapture: NSImage?
    private let permissionCoordinator: any ScreenCapturePermissionCoordinating
    private let screenCaptureService: ScreenCaptureService
    private let settingsStore: SettingsStore
    private let preferencesSettingsStore: any PreferencesSettingsStoring
    private let filenameProvider: any CaptureFilenameProviding
    private let languageSnapshot: CaptureLanguageSnapshot
    private var captureTask: Task<Void, Never>?
    private var fullScreenCaptureTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var overlayWindow: SelectionOverlayWindow?
    private var activeOverlayMode: CaptureOverlayMode?
    private var suspendedTeachingPenOverlay: SelectionOverlayWindow?
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
    private let ocrTextRecognizer: any OCRTextRecognizing
    private let qrCodeRecognizer: any QRCodeRecognizing
    private let textCopyHandler: @MainActor (String) -> Bool
    private let ocrResultPresenter: OCRResultPresentationController
    private let frontmostApplicationResolver: @MainActor () -> NSRunningApplication?
    private let applicationActivator: @MainActor (NSRunningApplication) -> Void
    private let scrollCaptureTargetDetector: any ScrollCaptureTargetDetecting
    private let selectionFallbackCapture: @MainActor (NSRect) async throws -> NSImage
    private let desktopFallbackCapture: @MainActor () async throws -> NSImage
    private let fullScreenCapturePreviewFactory: @MainActor (
        FullScreenCapturePreviewContext
    ) -> any FullScreenCapturePreviewPresenting
    private let fullScreenCaptureVisibleFrameResolver: @MainActor () -> NSRect
    private let fullScreenCaptureSoundPlayer: @MainActor () -> Void
    private let diagnosticLogger: any DiagnosticLogging
    private let commercialAccess: any CommercialAccessProviding
    private var fullScreenCapturePreview: (any FullScreenCapturePreviewPresenting)?
    private var longImageEditor: (any LongImageEditorPresenting)?
    private var scrollCaptureSession: (any ScrollCaptureSessionRunning)?
    private var scrollCapturePresentation: (any ScrollCapturePresenting)?
    private var scrollCaptureTask: Task<Void, Never>?
    private var scrollCaptureSeed: ScrollCaptureSeed?
    private var scrollCaptureFinishPending = false
    private var scrollCaptureMessageKey: L10n.Key?
    private var scrollCapturePhase: ScrollCaptureLifecyclePhase = .idle
    private var scrollCaptureGeneration: UInt64 = 0
    private var captureTargetApplication: NSRunningApplication?

    init(
        permissionCoordinator: any ScreenCapturePermissionCoordinating,
        screenCaptureService: ScreenCaptureService,
        settingsStore: SettingsStore = SettingsStore(),
        preferencesSettingsStore: any PreferencesSettingsStoring = PreferencesSettingsStore(),
        filenameProvider: any CaptureFilenameProviding = CaptureFilenameProvider(),
        pinnedWindowFactory: (@MainActor (NSImage, NSRect) -> PinnedImageWindowPresenting)? = nil,
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
        longImageSaveHandler: (@MainActor (NSImage) -> Bool)? = nil,
        ocrTextRecognizer: any OCRTextRecognizing = OCRTextRecognitionService(),
        qrCodeRecognizer: any QRCodeRecognizing = QRCodeRecognitionService(),
        textCopyHandler: (@MainActor (String) -> Bool)? = nil,
        ocrResultPresenter: OCRResultPresentationController? = nil,
        frontmostApplicationResolver: @escaping @MainActor () -> NSRunningApplication? = CaptureCoordinator.refreshTargetApplication,
        applicationActivator: @escaping @MainActor (NSRunningApplication) -> Void = { application in
            application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        },
        scrollCaptureTargetDetector: any ScrollCaptureTargetDetecting = ScrollCaptureTargetDetector(),
        selectionFallbackCapture: (@MainActor (NSRect) async throws -> NSImage)? = nil,
        desktopFallbackCapture: (@MainActor () async throws -> NSImage)? = nil,
        fullScreenCapturePreviewFactory: (@MainActor (
            FullScreenCapturePreviewContext
        ) -> any FullScreenCapturePreviewPresenting)? = nil,
        fullScreenCaptureVisibleFrameResolver: (@MainActor () -> NSRect)? = nil,
        fullScreenCaptureSoundPlayer: (@MainActor () -> Void)? = nil,
        diagnosticLogger: any DiagnosticLogging = NoopDiagnosticLogger.shared,
        commercialAccess: (any CommercialAccessProviding)? = nil
    ) {
        self.permissionCoordinator = permissionCoordinator
        self.screenCaptureService = screenCaptureService
        self.settingsStore = settingsStore
        self.preferencesSettingsStore = preferencesSettingsStore
        self.filenameProvider = filenameProvider
        let languageSnapshot = CaptureLanguageSnapshot(language: settingsStore.load().language)
        self.languageSnapshot = languageSnapshot
        self.pinnedWindowFactory = pinnedWindowFactory ?? { image, screenRect in
            PinnedImageWindowController(
                image: image,
                screenRect: screenRect,
                filenameProvider: filenameProvider,
                language: languageSnapshot.language
            )
        }
        self.scrollCaptureSessionFactory = scrollCaptureSessionFactory ?? { seed, update in
            let maximumAcceptedBytes = Self.defaultScrollCaptureMaximumAcceptedBytes
            guard let bridge = ScrollCaptureBridgeWorker(maximumAcceptedBytes: maximumAcceptedBytes) else {
                preconditionFailure("Unable to create scroll capture bridge")
            }
            return ScrollCaptureSession(
                seed: seed,
                capturer: StreamingScrollRegionCapturer(service: screenCaptureService),
                stitcher: bridge,
                clock: ContinuousScrollCaptureClock(),
                activityMonitor: ScrollActivityMonitor(),
                diagnosticLogger: diagnosticLogger,
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
                language: languageSnapshot.language
            )
        }
        self.longImageFallbackPresenter = longImageFallbackPresenter ?? { image in
            Self.presentLongImageFallback(image, language: languageSnapshot.language)
        }
        self.longImageCopyHandler = longImageCopyHandler
        self.longImageSaveHandler = longImageSaveHandler
        self.ocrTextRecognizer = ocrTextRecognizer
        self.qrCodeRecognizer = qrCodeRecognizer
        self.textCopyHandler = textCopyHandler ?? Self.copyTextToPasteboard
        self.ocrResultPresenter = ocrResultPresenter ?? OCRResultPresentationController(
            languageProvider: { languageSnapshot.language }
        )
        self.frontmostApplicationResolver = frontmostApplicationResolver
        self.applicationActivator = applicationActivator
        self.scrollCaptureTargetDetector = scrollCaptureTargetDetector
        self.selectionFallbackCapture = selectionFallbackCapture ?? { rect in
            try await screenCaptureService.captureImage(in: rect)
        }
        self.desktopFallbackCapture = desktopFallbackCapture ?? {
            try await screenCaptureService.captureDesktopImage()
        }
        self.fullScreenCapturePreviewFactory = fullScreenCapturePreviewFactory ?? {
            FullScreenCapturePreviewController(context: $0)
        }
        self.fullScreenCaptureVisibleFrameResolver = fullScreenCaptureVisibleFrameResolver
            ?? Self.currentScreenVisibleFrame
        self.diagnosticLogger = diagnosticLogger
        self.commercialAccess = commercialAccess ?? UnrestrictedCommercialAccess.shared
        if let fullScreenCaptureSoundPlayer {
            self.fullScreenCaptureSoundPlayer = fullScreenCaptureSoundPlayer
        } else {
            let sound = Bundle.main.url(
                forResource: "fullscreencutsound",
                withExtension: "mp3"
            ).flatMap {
                NSSound(contentsOf: $0, byReference: false)
            }
            self.fullScreenCaptureSoundPlayer = {
                sound?.stop()
                sound?.play()
            }
        }
    }

    convenience init() {
        self.init(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService()
        )
    }

    deinit {
        scrollCaptureTask?.cancel()
        fullScreenCaptureTask?.cancel()
        let presentation = scrollCapturePresentation
        let session = scrollCaptureSession
        let fullScreenPreview = fullScreenCapturePreview
        Task { @MainActor in
            presentation?.stop()
            _ = session?.cancel()
            fullScreenPreview?.stop()
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
        startCapture(mode: .region)
    }

    func startFullScreenCapture() {
        diagnosticLogger.record(
            category: .capture,
            level: .info,
            event: "full_screen_capture_requested"
        )
        guard canStartCapture else {
            NSLog("xxsnap full-screen capture ignored because capture is already active")
            diagnosticLogger.record(
                category: .capture,
                level: .warning,
                event: "full_screen_capture_ignored_busy"
            )
            return
        }
        languageSnapshot.language = settingsStore.load().language
        guard permissionCoordinator.hasScreenCapturePermission() else {
            diagnosticLogger.record(
                category: .capture,
                level: .warning,
                event: "full_screen_capture_permission_missing"
            )
            guard permissionCoordinator.shouldShowScreenCaptureGuidance() else { return }
            if permissionCoordinator.requestScreenCapturePermissionOnce() {
                showPermissionRestartAlert()
            } else {
                showPermissionSettingsAlert()
            }
            return
        }

        captureOverlayDidPresent?()
        diagnosticLogger.record(
            category: .capture,
            level: .info,
            event: "full_screen_capture_started"
        )
        fullScreenCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.fullScreenCaptureTask = nil
                self.captureSessionDidEnd?()
            }
            do {
                let image = try await self.desktopFallbackCapture()
                guard !Task.isCancelled else { return }
                self.lastCapture = image
                self.presentFullScreenCapturePreview(image)
                self.fullScreenCaptureSoundPlayer()
                self.diagnosticLogger.record(
                    category: .capture,
                    level: .info,
                    event: "full_screen_capture_completed",
                    metadata: Self.sizeMetadata(image.size)
                )
                NSLog(
                    "xxsnap full-screen capture completed: %.0fx%.0f",
                    image.size.width,
                    image.size.height
                )
            } catch {
                self.diagnosticLogger.record(
                    category: .capture,
                    level: .error,
                    event: "full_screen_capture_failed",
                    metadata: ["error_type": String(describing: type(of: error))]
                )
                NSLog("xxsnap full-screen capture failed: \(error.localizedDescription)")
            }
        }
    }

    func startTextRecognition() {
        guard commercialAccess.snapshot.canUse(.ocr) else {
            commercialAccess.requestPurchase(for: .ocr)
            return
        }
        startCapture(mode: .textRecognition)
    }

    func toggleTeachingPen() {
        if activeOverlayMode == .teachingPen {
            diagnosticLogger.record(
                category: .teachingPen,
                level: .info,
                event: "teaching_pen_exit_requested"
            )
            if let overlayWindow {
                overlayWindow.cancel()
            } else {
                startTask?.cancel()
            }
            return
        }
        guard commercialAccess.snapshot.canUse(.teachingPen) else {
            commercialAccess.requestPurchase(for: .teachingPen)
            return
        }
        startCapture(mode: .teachingPen)
    }

    private func startCapture(mode: CaptureOverlayMode) {
        NSLog("xxsnap startCapture mode=%@", String(describing: mode))
        diagnosticLogger.record(
            category: diagnosticCategory(for: mode),
            level: .info,
            event: diagnosticRequestEvent(for: mode)
        )
        let teachingPenToSuspend = mode == .textRecognition && canSuspendTeachingPen
            ? overlayWindow
            : nil
        guard canStartCapture || teachingPenToSuspend != nil else {
            NSLog("xxsnap startCapture ignored because capture is already active")
            diagnosticLogger.record(
                category: diagnosticCategory(for: mode),
                level: .warning,
                event: diagnosticEventPrefix(for: mode) + "_ignored_busy"
            )
            return
        }

        languageSnapshot.language = settingsStore.load().language
        if !permissionCoordinator.hasScreenCapturePermission() {
            NSLog("xxsnap missing screen capture permission")
            diagnosticLogger.record(
                category: diagnosticCategory(for: mode),
                level: .warning,
                event: diagnosticEventPrefix(for: mode) + "_permission_missing"
            )
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

        captureTargetApplication = frontmostApplicationResolver()
        if teachingPenToSuspend == nil {
            activeOverlayMode = mode
        }

        startTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.startTask = nil
                if self.overlayWindow == nil {
                    if !self.restoreSuspendedTeachingPen() {
                        self.activeOverlayMode = nil
                    }
                }
            }
            let refreshTargetApplication = self.captureTargetApplication

            let backgroundImage: NSImage?
            if mode == .region {
                do {
                    backgroundImage = try await desktopFallbackCapture()
                    frozenDesktopImage = backgroundImage
                    diagnosticLogger.record(
                        category: diagnosticCategory(for: mode),
                        level: .debug,
                        event: diagnosticEventPrefix(for: mode) + "_desktop_snapshot_ready",
                        metadata: backgroundImage.map { Self.sizeMetadata($0.size) } ?? [:]
                    )
                } catch {
                    NSLog("xxsnap desktop snapshot failed before overlay: \(error.localizedDescription)")
                    diagnosticLogger.record(
                        category: diagnosticCategory(for: mode),
                        level: .error,
                        event: diagnosticEventPrefix(for: mode) + "_desktop_snapshot_failed",
                        metadata: ["error_type": String(describing: type(of: error))]
                    )
                    backgroundImage = nil
                    frozenDesktopImage = nil
                }
            } else {
                backgroundImage = nil
                frozenDesktopImage = nil
            }
            guard !Task.isCancelled else {
                frozenDesktopImage = nil
                return
            }

            if let teachingPenToSuspend {
                guard self.overlayWindow === teachingPenToSuspend,
                      self.activeOverlayMode == .teachingPen
                else {
                    self.frozenDesktopImage = nil
                    return
                }
                teachingPenToSuspend.ignoresMouseEvents = true
                self.suspendedTeachingPenOverlay = teachingPenToSuspend
                self.overlayWindow = nil
                self.activeOverlayMode = mode
            }

            var settings = settingsStore.load()
            settings.language = self.languageSnapshot.language
            var configuration: SelectionOverlayConfiguration
            switch mode {
            case .region:
                configuration = .default
            case .textRecognition:
                configuration = .textRecognition()
            case .teachingPen:
                configuration = .teachingPen(windowFrame: SelectionOverlayWindow.desktopFrame())
            }
            configuration.pinToolbarShortcut = Self.pinToolbarShortcut(from: settings)
            configuration.shortcutFeedbackHandler = { [weak self] event in
                self?.shortcutFeedbackDidRequest?(event)
            }
            let overlayWindow = SelectionOverlayWindow(
                backgroundImage: backgroundImage,
                settings: settings,
                commercialAccess: commercialAccess,
                configuration: configuration,
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
            if mode == .region {
                self.installScrollCaptureCallbacks(on: overlayWindow)
            }
            self.captureOverlayDidPresent?()
            overlayWindow.present()
            self.diagnosticLogger.record(
                category: self.diagnosticCategory(for: mode),
                level: .info,
                event: self.diagnosticEventPrefix(for: mode) + "_overlay_presented"
            )
        }
    }

    private func diagnosticCategory(
        for mode: CaptureOverlayMode
    ) -> DiagnosticLogCategory {
        switch mode {
        case .region:
            return .capture
        case .textRecognition:
            return .textRecognition
        case .teachingPen:
            return .teachingPen
        }
    }

    private func diagnosticEventPrefix(for mode: CaptureOverlayMode) -> String {
        switch mode {
        case .region:
            return "region_capture"
        case .textRecognition:
            return "text_recognition"
        case .teachingPen:
            return "teaching_pen"
        }
    }

    private func diagnosticRequestEvent(for mode: CaptureOverlayMode) -> String {
        diagnosticEventPrefix(for: mode) + "_requested"
    }

    private var canStartCapture: Bool {
        overlayWindow == nil
            && captureTask == nil
            && fullScreenCaptureTask == nil
            && startTask == nil
            && scrollCapturePhase == .idle
    }

    private var canSuspendTeachingPen: Bool {
        activeOverlayMode == .teachingPen
            && overlayWindow != nil
            && suspendedTeachingPenOverlay == nil
            && captureTask == nil
            && fullScreenCaptureTask == nil
            && startTask == nil
            && scrollCapturePhase == .idle
    }

    @discardableResult
    private func restoreSuspendedTeachingPen() -> Bool {
        guard let teachingPen = suspendedTeachingPenOverlay else {
            return false
        }
        suspendedTeachingPenOverlay = nil
        overlayWindow = teachingPen
        activeOverlayMode = .teachingPen
        teachingPen.ignoresMouseEvents = false
        teachingPen.contentView?.needsDisplay = true
        teachingPen.present()
        return true
    }

    func updateLanguage(_ language: AppLanguage) {
        languageSnapshot.language = language
        overlayWindow?.updateLanguage(language)
        scrollCapturePresentation?.updateLanguage(language)
        longImageEditor?.updateLanguage(language)
        fullScreenCapturePreview?.updateLanguage(language)
        pinnedWindowControllers.forEach { $0.updateLanguage(language) }

        guard let scrollCaptureMessageKey else { return }
        let message = L10n(language: language).text(scrollCaptureMessageKey)
        if case .paused = overlayWindow?.scrollCaptureOverlayState {
            overlayWindow?.setScrollCapturePaused(message: message)
        }
        scrollCapturePresentation?.setWarning(message)
    }

    func commercialAccessDidChange() {
        overlayWindow?.commercialAccessDidChange()
    }

    private static var defaultScrollCaptureMaximumAcceptedBytes: UInt {
        // Keep enough headroom for final-image materialization while allowing long captures
        // to scale with the host instead of stopping at the old fixed 512 MiB ceiling.
        let physical = ProcessInfo.processInfo.physicalMemory
        let desired = min(
            UInt64(4 * 1_024 * 1_024 * 1_024),
            max(UInt64(512 * 1_024 * 1_024), physical / 16)
        )
        return UInt(min(desired, UInt64(UInt.max)))
    }

    private static func makeScrollCapturePresentation(
        _ context: ScrollCapturePresentationContext
    ) -> any ScrollCapturePresenting {
        ScrollCapturePresentationController(
            toolbarFrame: context.geometry.toolbarFrame,
            finishButtonFrame: context.geometry.finishButtonFrame,
            selectionFrame: context.selectionFrame,
            visibleFrame: context.visibleFrame,
            language: context.language,
            onFinish: context.onFinish
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
        guard commercialAccess.snapshot.canUse(.scrollCapture) else {
            commercialAccess.requestPurchase(for: .scrollCapture)
            return
        }
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
        let targetApplication = captureTargetApplication ?? frontmostApplicationResolver()
        captureTargetApplication = targetApplication
        let targetProcessIdentifier = targetApplication?.processIdentifier
        let detector = scrollCaptureTargetDetector
        scrollCaptureTask = Task { @MainActor [weak self, weak overlay] in
            let resolvedScreenRect: NSRect?
            if let targetProcessIdentifier {
                resolvedScreenRect = await detector.scrollableRegion(
                    in: seed.screenRect,
                    processIdentifier: targetProcessIdentifier
                )
            } else {
                resolvedScreenRect = nil
            }
            guard let self,
                  let overlay,
                  !Task.isCancelled,
                  self.scrollCaptureGeneration == generation,
                  self.scrollCapturePhase == .starting || self.scrollCapturePhase == .finishPending,
                  self.overlayWindow === overlay
            else { return }

            self.scrollCaptureTask = nil
            let adjustedSeed = resolvedScreenRect.flatMap {
                overlay.applyScrollCaptureTarget(screenRect: $0)
            }
            let didResolveTarget = adjustedSeed != nil
            if !didResolveTarget {
                overlay.markScrollCaptureTargetFallback()
            }
            let targetSeed = adjustedSeed ?? seed
            let captureSeed = ScrollCaptureSeed(
                screenRect: targetSeed.screenRect,
                snapshotRect: targetSeed.snapshotRect,
                frozenImage: targetSeed.frozenImage,
                annotations: targetSeed.annotations,
                eraserMasks: targetSeed.eraserMasks,
                targetApplicationProcessIdentifier: targetProcessIdentifier
            )
            NSLog(
                "xxsnap scroll-capture target original=%@ final=%@ pid=%d result=%@",
                NSStringFromRect(seed.screenRect),
                NSStringFromRect(captureSeed.screenRect),
                targetProcessIdentifier ?? -1,
                didResolveTarget ? "resolved" : "fallback"
            )
            self.startResolvedScrollCapture(
                captureSeed: captureSeed,
                targetApplication: targetApplication,
                overlay: overlay,
                generation: generation
            )
        }
    }

    private func startResolvedScrollCapture(
        captureSeed: ScrollCaptureSeed,
        targetApplication: NSRunningApplication?,
        overlay: SelectionOverlayWindow,
        generation: UInt64
    ) {
        guard scrollCaptureGeneration == generation,
              scrollCapturePhase == .starting || scrollCapturePhase == .finishPending,
              overlayWindow === overlay,
              scrollCaptureTask == nil,
              scrollCaptureSession == nil,
              scrollCapturePresentation == nil
        else { return }
        let language = languageSnapshot.language
        guard let geometry = overlay.scrollCaptureControlGeometry else {
            scrollCaptureGeneration &+= 1
            overlay.restoreAfterScrollCaptureCancellation()
            overlay.present()
            scrollCaptureFinishPending = false
            scrollCapturePhase = .idle
            return
        }
        let visibleFrame = Self.visibleFrame(containing: captureSeed.screenRect)
        let presentation = scrollCapturePresentationFactory(ScrollCapturePresentationContext(
            geometry: geometry,
            selectionFrame: captureSeed.screenRect,
            visibleFrame: visibleFrame,
            language: language,
            onFinish: { [weak self] in self?.finishScrollCapture() }
        ))
        let session = scrollCaptureSessionFactory(captureSeed) { [weak self] update in
            self?.receiveScrollCaptureUpdate(update, generation: generation)
        }
        scrollCaptureSeed = captureSeed
        scrollCaptureSession = session
        scrollCapturePresentation = presentation
        presentation.updatePlacement(selectionFrame: captureSeed.screenRect, visibleFrame: visibleFrame)
        // Keep the transparent selection chrome visible, but return foreground ownership to
        // the application underneath so it receives the user's scroll-wheel events.
        if let targetApplication {
            applicationActivator(targetApplication)
        } else {
            NSApp.deactivate()
        }
        // Present after the target application activation so AppKit does not immediately
        // reorder the new controls behind the application being activated.
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

    private static func currentScreenVisibleFrame() -> NSRect {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? SelectionOverlayWindow.visibleDesktopFrame()
    }

    private static func sizeMetadata(_ size: NSSize) -> [String: String] {
        [
            "width": String(Int(size.width.rounded())),
            "height": String(Int(size.height.rounded())),
        ]
    }

    private func receiveScrollCaptureUpdate(
        _ update: ScrollCapturePresentationUpdate,
        generation: UInt64
    ) {
        guard generation == scrollCaptureGeneration,
              let overlay = overlayWindow,
              let presentation = scrollCapturePresentation
        else { return }
        let l10n = L10n(language: languageSnapshot.language)
        switch update {
        case .terminalCommand(.finish):
            finishScrollCapture()
        case .terminalCommand(.cancel):
            cancelScrollCapture()
        case .preview(let image, let edge, let viewport):
            NSLog(
                "xxsnap scroll-capture coordinator preview edge=%@ image=%@ viewport=%ld output=%ld",
                String(describing: edge),
                NSStringFromSize(image.size),
                viewport.viewportHeight,
                viewport.outputHeight
            )
            overlay.setScrollCaptureOutputHeight(viewport.outputHeight)
            presentation.updatePreview(image, following: edge, viewport: viewport)
        case .viewportScroll(let activity):
            presentation.moveViewportIndicator(activity)
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
            scrollCaptureMessageKey = key
            overlay.setScrollCapturePaused(message: message)
            presentation.setWarning(message)
        case .warning(.lowConfidence):
            overlay.setScrollCaptureCapturing()
            scrollCaptureMessageKey = .scrollCaptureLowConfidence
            presentation.setWarning(l10n.text(.scrollCaptureLowConfidence))
        case .warning(.noMovement):
            overlay.setScrollCaptureCapturing()
            scrollCaptureMessageKey = .scrollCaptureNoMovement
            presentation.setWarning(l10n.text(.scrollCaptureNoMovement))
        case .warning(nil):
            scrollCaptureMessageKey = nil
            presentation.clearWarning()
        case .stepState:
            break
        case .state:
            break
        }
    }

    private func finishScrollCapture() {
        NSLog(
            "xxsnap scroll-capture coordinator finish requested phase=%@ task=%@ session=%@ presentation=%@",
            String(describing: scrollCapturePhase),
            scrollCaptureTask == nil ? "nil" : "active",
            scrollCaptureSession == nil ? "nil" : "present",
            scrollCapturePresentation == nil ? "nil" : "present"
        )
        switch scrollCapturePhase {
        case .starting:
            scrollCaptureFinishPending = true
            scrollCapturePhase = .finishPending
            return
        case .active:
            if scrollCaptureTask != nil {
                scrollCaptureFinishPending = true
                scrollCapturePhase = .finishPending
                return
            }
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
        NSLog("xxsnap scroll-capture coordinator entering finishing")
        scrollCapturePhase = .finishing
        scrollCaptureFinishPending = false
        let generation = scrollCaptureGeneration
        scrollCaptureTask = Task { @MainActor [weak self, weak session] in
            do {
                guard let image = try await session?.finish() else { return }
                NSLog("xxsnap scroll-capture session returned final image size=%@", NSStringFromSize(image.size))
                guard let self, self.scrollCaptureGeneration == generation,
                      self.scrollCaptureSession === session else { return }
                self.scrollCapturePresentation?.stop()
                self.scrollCapturePresentation = nil
                self.scrollCaptureSession = nil
                self.scrollCaptureSeed = nil
                self.scrollCaptureMessageKey = nil
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
                    self.presentLongImageEditor(image: image, seed: seed)
                    self.captureSessionDidEnd?()
                }
            } catch {
                NSLog("xxsnap scroll-capture finish failed: %@", String(describing: error))
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
        scrollCapturePhase = .cancelling
        scrollCaptureGeneration &+= 1
        scrollCaptureTask?.cancel()
        scrollCaptureTask = nil
        _ = scrollCaptureSession?.cancel()
        scrollCapturePresentation?.stop()
        scrollCapturePresentation = nil
        scrollCaptureSession = nil
        scrollCaptureSeed = nil
        scrollCaptureMessageKey = nil
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
        scrollCaptureMessageKey = nil
        scrollCaptureFinishPending = false
        overlayWindow?.restoreAfterScrollCaptureCancellation()
        overlayWindow?.present()
        scrollCapturePhase = .idle
    }

    private func presentLongImageEditor(
        image: NSImage,
        seed: ScrollCaptureSeed,
        titleStyle: LongImageEditorTitleStyle = .longCapture
    ) {
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
            editor.updateTitleStyle(titleStyle)
            longImageEditor = editor
            let editorID = ObjectIdentifier(editor)
            editor.onClose = { [weak self] in
                guard let self, let current = self.longImageEditor,
                      ObjectIdentifier(current) == editorID else { return }
                self.longImageEditor = nil
            }
            editor.show()
        } catch {
            presentLongImageFallback(image)
        }
    }

    private func presentFullScreenCapturePreview(_ image: NSImage) {
        fullScreenCapturePreview?.stop()
        fullScreenCapturePreview = nil

        let visibleFrame = fullScreenCaptureVisibleFrameResolver()
        let desktopFrame = SelectionOverlayWindow.desktopFrame()
        let seed = ScrollCaptureSeed(
            screenRect: desktopFrame,
            snapshotRect: NSRect(origin: .zero, size: image.size),
            frozenImage: image,
            annotations: [],
            eraserMasks: []
        )
        let actions = FullScreenCapturePreviewActions(
            open: { [weak self] in
                guard let self else { return }
                self.presentLongImageEditor(
                    image: image,
                    seed: seed,
                    titleStyle: .fullScreenCapture
                )
            },
            copy: { [weak self] in
                self?.copyToPasteboard(image)
            },
            save: { [weak self] in
                guard let self else { return }
                _ = self.saveLastCapture(image)
            },
            pin: { [weak self] in
                self?.presentPinnedImage(image, screenRect: visibleFrame)
            }
        )
        let preview = fullScreenCapturePreviewFactory(FullScreenCapturePreviewContext(
            image: image,
            visibleFrame: visibleFrame,
            language: languageSnapshot.language,
            actions: actions
        ))
        let previewID = ObjectIdentifier(preview)
        preview.onClose = { [weak self] in
            guard let self,
                  let current = self.fullScreenCapturePreview,
                  ObjectIdentifier(current) == previewID
            else { return }
            self.fullScreenCapturePreview = nil
        }
        fullScreenCapturePreview = preview
        preview.show()
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
            return
        }
    }

    private static func presentLongImageFallback(
        _ image: NSImage,
        language: AppLanguage
    ) -> LongImageFallbackChoice {
        let alert = NSAlert()
        let l10n = L10n(language: language)
        alert.messageText = l10n.text(.longImageEditorUnavailable)
        alert.informativeText = l10n.text(.longImageEditorUnavailableDetail)
        alert.addButton(withTitle: l10n.text(.longImageSave))
        alert.addButton(withTitle: l10n.text(.cancel))
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
        let l10n = L10n(language: languageSnapshot.language)
        alert.messageText = l10n.text(.screenRecordingPermissionRequired)
        alert.informativeText = l10n.text(.screenRecordingPermissionRestartDetail)
        alert.addButton(withTitle: l10n.text(.openSystemSettings))
        alert.addButton(withTitle: l10n.text(.later))
        if alert.runModal() == .alertFirstButtonReturn {
            openScreenCaptureSettings()
        }
    }

    private func showPermissionSettingsAlert() {
        let alert = NSAlert()
        let l10n = L10n(language: languageSnapshot.language)
        alert.messageText = l10n.text(.screenRecordingPermissionMissing)
        alert.informativeText = l10n.text(.screenRecordingPermissionSettingsDetail)
        alert.addButton(withTitle: l10n.text(.openSystemSettings))
        alert.addButton(withTitle: l10n.text(.cancel))
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
        let completedOverlayMode = activeOverlayMode
        let completedCategory = completedOverlayMode.map(diagnosticCategory(for:)) ?? .capture
        let completedEventPrefix = completedOverlayMode.map(diagnosticEventPrefix(for:))
            ?? "region_capture"
        if let overlayWindow, completedOverlayMode == .region {
            retiredOverlayWindows.append(overlayWindow)
        }
        overlayWindow = nil
        activeOverlayMode = nil

        guard let result, !result.screenRect.isEmpty else {
            NSLog("xxsnap selection cancelled or empty")
            diagnosticLogger.record(
                category: completedCategory,
                level: .info,
                event: completedEventPrefix + "_cancelled"
            )
            frozenDesktopImage = nil
            if !restoreSuspendedTeachingPen() {
                captureSessionDidEnd?()
            }
            return
        }
        NSLog("xxsnap handling selection annotations=%ld rect=(%.0f, %.0f, %.0f, %.0f)", result.annotations.count, result.screenRect.minX, result.screenRect.minY, result.screenRect.width, result.screenRect.height)
        diagnosticLogger.record(
            category: completedCategory,
            level: .info,
            event: completedEventPrefix + "_selection_completed",
            metadata: [
                "action": String(describing: result.action),
                "annotation_count": String(result.annotations.count),
                "width": String(Int(result.screenRect.width.rounded())),
                "height": String(Int(result.screenRect.height.rounded())),
            ]
        )

        captureTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.captureTask = nil
                if !self.restoreSuspendedTeachingPen() {
                    self.captureSessionDidEnd?()
                }
            }

            do {
                let image: NSImage
                if let frozenDesktopImage = self.frozenDesktopImage {
                    let imageBounds = NSRect(origin: .zero, size: frozenDesktopImage.size)
                    if result.snapshotRect.standardized == imageBounds {
                        image = frozenDesktopImage
                    } else if let croppedImage = Self.crop(
                        image: frozenDesktopImage,
                        rect: result.snapshotRect
                    ) {
                        image = croppedImage
                    } else {
                        image = try await captureFallbackImage(
                            for: completedOverlayMode,
                            screenRect: result.screenRect
                        )
                    }
                } else {
                    image = try await captureFallbackImage(
                        for: completedOverlayMode,
                        screenRect: result.screenRect
                    )
                }
                if completedOverlayMode == .textRecognition {
                    self.diagnosticLogger.record(
                        category: .textRecognition,
                        level: .info,
                        event: "text_recognition_started"
                    )
                    await handleTextRecognition(image, screenRect: result.screenRect)
                    self.frozenDesktopImage = nil
                    return
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
                    self.diagnosticLogger.record(
                        category: completedCategory,
                        level: .info,
                        event: completedEventPrefix + "_copied"
                    )
                case .save:
                    if !saveLastCapture(exportedImage) {
                        NSLog("xxsnap save was cancelled or failed")
                        self.diagnosticLogger.record(
                            category: completedCategory,
                            level: .warning,
                            event: completedEventPrefix + "_save_not_completed"
                        )
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
                    self.diagnosticLogger.record(
                        category: .pin,
                        level: .info,
                        event: "pinned_capture_presented",
                        metadata: Self.sizeMetadata(exportedImage.size)
                    )
                case .finishEditing:
                    break
                }
                self.diagnosticLogger.record(
                    category: completedCategory,
                    level: .info,
                    event: completedEventPrefix + "_completed",
                    metadata: Self.sizeMetadata(exportedImage.size)
                )
                NSLog(
                    "xxsnap capture completed: %.0fx%.0f",
                    exportedImage.size.width,
                    exportedImage.size.height
                )
            } catch {
                self.frozenDesktopImage = nil
                if completedOverlayMode == .textRecognition {
                    self.ocrResultPresenter.showFailure(near: result.screenRect)
                }
                self.diagnosticLogger.record(
                    category: completedCategory,
                    level: .error,
                    event: completedEventPrefix + "_failed",
                    metadata: ["error_type": String(describing: type(of: error))]
                )
                NSLog("xxsnap capture failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleTextRecognition(_ image: NSImage, screenRect: NSRect) async {
        async let qrCodeAttempt = recognitionAttempt {
            try await qrCodeRecognizer.recognizeQRCode(in: image)
        }
        async let textAttempt = recognitionAttempt {
            try await ocrTextRecognizer.recognizeText(in: image)
        }
        let (qrCodeResult, textResult) = await (qrCodeAttempt, textAttempt)
        let qrCodePayload = qrCodeResult.successValue.flatMap { $0 }?.payload
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text = textResult.successValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let recognizedContent = [qrCodePayload, text]
            .compactMap { $0 }
            .first { !$0.isEmpty }

        guard let recognizedContent else {
            ocrResultPresenter.showFailure(near: screenRect)
            diagnosticLogger.record(
                category: .textRecognition,
                level: qrCodeResult.isFailure && textResult.isFailure ? .error : .warning,
                event: qrCodeResult.isFailure && textResult.isFailure
                    ? "text_recognition_failed"
                    : "text_recognition_empty_result"
            )
            NSLog("xxsnap text and QR code recognition completed without a result")
            return
        }
        guard textCopyHandler(recognizedContent) else {
            ocrResultPresenter.showFailure(near: screenRect)
            diagnosticLogger.record(
                category: .textRecognition,
                level: .error,
                event: "text_recognition_copy_failed"
            )
            NSLog("xxsnap text and QR code recognition copy failed")
            return
        }
        let preferences = preferencesSettingsStore.load()
        let recognizedQRCode = qrCodePayload == recognizedContent
        if recognizedQRCode {
            ocrResultPresenter.showQRCodeSuccess(
                payload: recognizedContent,
                near: screenRect,
                playsSound: !preferences.disablesTextRecognitionSound,
                showsNotification: !preferences.disablesTextRecognitionSuccessNotification
            )
        } else {
            ocrResultPresenter.showSuccess(
                near: screenRect,
                playsSound: !preferences.disablesTextRecognitionSound,
                showsNotification: !preferences.disablesTextRecognitionSuccessNotification
            )
        }
        diagnosticLogger.record(
            category: .textRecognition,
            level: .info,
            event: recognizedQRCode
                ? "qr_code_recognition_completed"
                : "text_recognition_completed",
            metadata: ["character_count": String(recognizedContent.count)]
        )
        NSLog(
            "xxsnap %@ recognition copied %ld characters",
            recognizedQRCode ? "QR code" : "text",
            recognizedContent.count
        )
    }

    private func captureFallbackImage(
        for mode: CaptureOverlayMode?,
        screenRect: NSRect
    ) async throws -> NSImage {
        if mode == .teachingPen {
            return try await desktopFallbackCapture()
        }
        return try await selectionFallbackCapture(screenRect)
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
            let cgImage = imageToSave.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            diagnosticLogger.record(
                category: .capture,
                level: .error,
                event: "capture_save_source_unavailable"
            )
            return false
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = filenameProvider.suggestedFilename()
        savePanel.level = .modalPanel

        NSApp.activate(ignoringOtherApps: true)
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            diagnosticLogger.record(
                category: .capture,
                level: .info,
                event: "capture_save_cancelled"
            )
            return false
        }

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            diagnosticLogger.record(
                category: .capture,
                level: .error,
                event: "capture_save_destination_unavailable"
            )
            return false
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        let didSave = CGImageDestinationFinalize(destination)
        if !didSave {
            try? FileManager.default.removeItem(at: destinationURL)
            NSLog("xxsnap save failed: ImageIO could not encode PNG")
            diagnosticLogger.record(
                category: .capture,
                level: .error,
                event: "capture_save_failed"
            )
        } else {
            diagnosticLogger.record(
                category: .capture,
                level: .info,
                event: "capture_save_completed",
                metadata: Self.sizeMetadata(imageToSave.size)
            )
        }
        return didSave
    }

    private func copyToPasteboard(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private static func copyTextToPasteboard(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    nonisolated static func defaultCaptureFilename(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        (try? FilenameTemplateRenderer().filename(
            template: PreferencesSettings.defaultFilenameTemplate,
            date: date,
            timeZone: timeZone
        )) ?? "xxsnap_截图.png"
    }

    nonisolated static func pinToolbarShortcut(
        from settings: AppSettings
    ) -> SelectionToolbarState.ToolbarShortcut? {
        let action = HotKeyAction.restoreMostRecentlyHiddenPinnedImage
        guard !settings.disabledHotkeys.contains(action.rawValue) else {
            return nil
        }
        return HotKeyFormatter.toolbarShortcut(
            from: settings.hotkeys[action.rawValue] ?? action.defaultSettings
        )
    }
}

private func recognitionAttempt<Value>(
    _ operation: () async throws -> Value
) async -> Result<Value, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}

private extension Result {
    var successValue: Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }

    var isFailure: Bool {
        guard case .failure = self else { return false }
        return true
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

    func test_makeScrollCaptureSession(seed: ScrollCaptureSeed) -> any ScrollCaptureSessionRunning {
        scrollCaptureSessionFactory(seed) { _ in }
    }

    var test_overlayWindow: SelectionOverlayWindow? {
        overlayWindow
    }

    var test_hasSuspendedTeachingPen: Bool {
        suspendedTeachingPenOverlay != nil
    }

    var test_isTextRecognitionOverlayActive: Bool {
        activeOverlayMode == .textRecognition && overlayWindow != nil
    }

    var test_isTeachingPenOverlayActive: Bool {
        activeOverlayMode == .teachingPen && overlayWindow != nil
    }

    func test_installOverlayWindow(_ overlay: SelectionOverlayWindow) {
        overlayWindow = overlay
        installScrollCaptureCallbacks(on: overlay)
    }

    func test_installTeachingPenOverlayWindow(_ overlay: SelectionOverlayWindow) {
        overlayWindow = overlay
        activeOverlayMode = .teachingPen
    }

    func test_installTextRecognitionOverlayWindow(_ overlay: SelectionOverlayWindow) {
        overlayWindow = overlay
        activeOverlayMode = .textRecognition
    }

    func test_requestScrollCapture(seed: ScrollCaptureSeed) {
        overlayWindow?.test_setLockedSelectionRect(seed.snapshotRect)
        overlayWindow?.test_prepareScrollCaptureTargetResolution()
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
