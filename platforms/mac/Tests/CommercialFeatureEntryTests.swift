import AppKit
import XCTest
@testable import xxsnap

private func entryTestImage(size: NSSize) -> NSImage {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let image = NSImage(size: size)
    image.addRepresentation(representation)
    return image
}

@MainActor
private final class EntryTestCommercialAccess: CommercialAccessProviding {
    var state: CommercialAccessState
    var onStateChange: ((CommercialAccessState) -> Void)?
    var denied: Set<CommercialFeature>
    private(set) var purchaseRequests: [CommercialFeature] = []
    var purchaseDidRequest: ((CommercialFeature) -> Void)?

    init(
        state: CommercialAccessState = .free(reason: .trialUnavailable),
        denied: Set<CommercialFeature> = []
    ) {
        self.state = state
        self.denied = denied
    }

    func canUse(_ feature: CommercialFeature) -> Bool {
        !denied.contains(feature)
    }

    func showsProBadge(for feature: CommercialFeature) -> Bool {
        if case .free = state { return denied.contains(feature) }
        return false
    }

    var snapshot: CommercialAccessSnapshot {
        CommercialAccessSnapshot(
            state: state,
            availableFeatures: Set(CommercialFeature.allCases).subtracting(denied),
            proBadgedFeatures: Set(CommercialFeature.allCases.filter(showsProBadge(for:)))
        )
    }

    func requestPurchase(for feature: CommercialFeature) {
        purchaseRequests.append(feature)
        purchaseDidRequest?(feature)
    }

    func update(state: CommercialAccessState, denied: Set<CommercialFeature>) {
        self.state = state
        self.denied = denied
        onStateChange?(state)
    }
}

private final class EntryTestPermissionCoordinator: ScreenCapturePermissionCoordinating {
    private(set) var preflightCount = 0
    private(set) var guidanceCount = 0
    private(set) var requestCount = 0

    func hasScreenCapturePermission() -> Bool {
        preflightCount += 1
        return false
    }

    func shouldShowScreenCaptureGuidance() -> Bool {
        guidanceCount += 1
        return true
    }

    func requestScreenCapturePermissionOnce() -> Bool {
        requestCount += 1
        return false
    }
}

private final class EntryTestSettingsStore: AppSettingsStoring {
    var settings = AppSettings.default
    func load() -> AppSettings { settings }
    func save(_ settings: AppSettings) throws { self.settings = settings }
}

private final class EntryTestHotKeyRegistrar: GlobalHotKeyRegistering {
    var onHotKeyPressed: ((HotKeyAction) -> Void)?
    func register(
        _ settings: HotKeySettings,
        action: HotKeyAction
    ) -> Result<HotKeyRegistrationToken, GlobalHotKeyRegistrationError> {
        .success(HotKeyRegistrationToken())
    }
    func unregister(_ token: HotKeyRegistrationToken) {}
}

@MainActor
final class CommercialFeatureEntryTests: XCTestCase {
    func testCommercialFeatureListContainsOnlyTheThreeProFeatures() {
        XCTAssertEqual(
            Set(CommercialFeature.allCases),
            Set([.scrollCapture, .ocr, .teachingPen])
        )
    }

    func testOCRAndTeachingPenStopBeforePermissionWhenDenied() {
        let access = EntryTestCommercialAccess(denied: [.ocr, .teachingPen])
        let permission = EntryTestPermissionCoordinator()
        let coordinator = CaptureCoordinator(
            permissionCoordinator: permission,
            screenCaptureService: ScreenCaptureService(),
            commercialAccess: access
        )

        coordinator.startTextRecognition()
        coordinator.toggleTeachingPen()

        XCTAssertEqual(access.purchaseRequests, [.ocr, .teachingPen])
        XCTAssertEqual(permission.preflightCount, 0)
        XCTAssertEqual(permission.guidanceCount, 0)
        XCTAssertEqual(permission.requestCount, 0)
        XCTAssertNil(coordinator.test_overlayWindow)
    }

    func testRunningTeachingPenCanAlwaysExitAfterAccessBecomesFree() async {
        let access = EntryTestCommercialAccess(state: .allFree)
        let coordinator = CaptureCoordinator(
            permissionCoordinator: EntryTestPermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            commercialAccess: access
        )
        var completionCount = 0
        let overlay = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .teachingPen(windowFrame: NSRect(x: 0, y: 0, width: 640, height: 420))
        ) { _ in completionCount += 1 }
        coordinator.test_installTeachingPenOverlayWindow(overlay)
        access.update(state: .free(reason: .trialExpired), denied: [.teachingPen])

        coordinator.toggleTeachingPen()
        await Task.yield()

        XCTAssertEqual(completionCount, 1)
        XCTAssertTrue(access.purchaseRequests.isEmpty)
    }

    func testDeniedScrollCaptureStaysVisibleShowsProAndHasNoCaptureSideEffect() throws {
        let access = EntryTestCommercialAccess(denied: [.scrollCapture])
        var scrollRequests = 0
        let window = SelectionOverlayWindow(
            backgroundImage: entryTestImage(size: NSSize(width: 640, height: 420)),
            commercialAccess: access
        ) { _ in }
        window.onScrollCaptureRequested = { _ in scrollRequests += 1 }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 60, width: 300, height: 220))

        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .scroll))
        XCTAssertTrue(window.test_showsProBadge(for: .scroll))
        XCTAssertTrue(window.test_handleKeyDown(
            keyCode: 15,
            charactersIgnoringModifiers: "r",
            modifierFlags: []
        ))
        XCTAssertEqual(access.purchaseRequests, [.scrollCapture])
        XCTAssertEqual(scrollRequests, 0)
        XCTAssertEqual(window.scrollCaptureOverlayState, .inactive)
    }

    func testAllFreeAndGraceHideProBadgeAndAllowScrollCapture() {
        for state in [
            CommercialAccessState.allFree,
            .allFreeGrace(until: Date().addingTimeInterval(3600)),
        ] {
            let access = EntryTestCommercialAccess(state: state)
            var requestCount = 0
            let window = SelectionOverlayWindow(
                backgroundImage: entryTestImage(size: NSSize(width: 640, height: 420)),
                commercialAccess: access
            ) { _ in }
            window.onScrollCaptureRequested = { _ in requestCount += 1 }
            window.test_setLockedSelectionRect(NSRect(x: 80, y: 60, width: 300, height: 220))

            XCTAssertFalse(window.test_showsProBadge(for: .scroll))
            XCTAssertTrue(window.test_handleKeyDown(
                keyCode: 15,
                charactersIgnoringModifiers: "r",
                modifierFlags: []
            ))
            XCTAssertEqual(requestCount, 1)
            XCTAssertTrue(access.purchaseRequests.isEmpty)
        }
    }

    func testOverlayReadsCurrentCommercialSnapshotInsteadOfCachingOldState() {
        let access = EntryTestCommercialAccess(state: .allFree)
        let window = SelectionOverlayWindow(
            backgroundImage: entryTestImage(size: NSSize(width: 640, height: 420)),
            commercialAccess: access
        ) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 60, width: 300, height: 220))
        XCTAssertFalse(window.test_showsProBadge(for: .scroll))

        access.update(state: .free(reason: .trialExpired), denied: [.scrollCapture])

        XCTAssertTrue(window.test_showsProBadge(for: .scroll))
    }

    func testPaidFreeStateNeverRestrictsAnnotationToolsOrLineStyles() {
        let access = EntryTestCommercialAccess(
            state: .free(reason: .trialUnavailable),
            denied: Set(CommercialFeature.allCases)
        )
        var settings = AppSettings.default
        settings.paletteVisibleCount = 4
        settings.interfaceFont = InterfaceFontSettings(
            familyName: "Menlo",
            pointSize: 14,
            weight: 0.4
        )
        let window = SelectionOverlayWindow(
            backgroundImage: entryTestImage(size: NSSize(width: 640, height: 420)),
            settings: settings,
            commercialAccess: access
        ) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 60, width: 300, height: 220))

        for button in [
            TestToolbarButton.rectangle,
            .arrow,
            .pen,
            .marker,
            .eyedropper,
            .mosaic,
            .text,
            .number,
            .magnifier,
            .eraser,
            .pin,
            .save,
            .copy,
        ] {
            XCTAssertNotNil(window.test_mainToolbarButtonRect(for: button), "button=\(button)")
            XCTAssertTrue(window.test_toolbarButtonIsEnabled(button), "button=\(button)")
        }
        XCTAssertEqual(
            SelectionToolbarState.strokePatternOptions().map(\.pattern),
            CaptureStrokePattern.allCases
        )
        XCTAssertTrue(SelectionToolbarState.strokePatternOptions().allSatisfy(\.isEnabled))
    }

    func testMenuAndGlobalHotKeysRouteThroughCoordinatorAndRefreshProTitles() async {
        let access = EntryTestCommercialAccess(denied: [.ocr, .teachingPen])
        let permission = EntryTestPermissionCoordinator()
        let settings = EntryTestSettingsStore()
        let coordinator = CaptureCoordinator(
            permissionCoordinator: permission,
            screenCaptureService: ScreenCaptureService(),
            commercialAccess: access
        )
        let registrar = EntryTestHotKeyRegistrar()
        let hotKeys = CaptureHotKeyController(
            settingsStore: settings,
            registrar: registrar,
            keyCodeCharacterResolver: { _ in nil },
            captureHandler: {},
            recognizeTextHandler: { coordinator.startTextRecognition() },
            teachingPenHandler: { coordinator.toggleTeachingPen() },
            restorePinnedImageHandler: {}
        )
        let status = StatusItemController(
            captureCoordinator: coordinator,
            settingsStore: settings,
            hotKeyController: hotKeys,
            updateChecker: PlaceholderUpdateChecker(),
            showPreferences: { _ in },
            showHelp: {},
            commercialAccess: access
        )

        XCTAssertEqual(status.test_menuItems[2].title, "识别文字  PRO")
        XCTAssertEqual(status.test_menuItems[3].title, "教笔  PRO")
        status.captureText()
        status.teachingPen()
        XCTAssertEqual(access.purchaseRequests, [.ocr, .teachingPen])
        let hotKeyRequests = expectation(description: "commercial hot keys route through coordinator")
        hotKeyRequests.expectedFulfillmentCount = 2
        access.purchaseDidRequest = { _ in hotKeyRequests.fulfill() }
        registrar.onHotKeyPressed?(.recognizeText)
        registrar.onHotKeyPressed?(.teachingPen)
        await fulfillment(of: [hotKeyRequests], timeout: 1)
        XCTAssertEqual(access.purchaseRequests, [.ocr, .teachingPen, .ocr, .teachingPen])
        XCTAssertEqual(permission.preflightCount, 0)

        access.update(state: .allFree, denied: [])
        status.refresh()
        XCTAssertEqual(status.test_menuItems[2].title, "识别文字")
        XCTAssertEqual(status.test_menuItems[3].title, "教笔")
    }
}
