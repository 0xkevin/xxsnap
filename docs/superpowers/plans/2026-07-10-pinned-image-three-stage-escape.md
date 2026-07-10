# Pinned Image Three-Stage Escape Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make pinned images progress from active tool to completed editing to hidden state across Escape presses, then restore the most recently hidden pin with Command-1 outside capture.

**Architecture:** Keep tool cancellation inside `SelectionOverlayView`, route a neutral pinned editor Escape through the existing `.finishEditing` result, and distinguish hiding from true closure in `PinnedImageWindowController`. `CaptureCoordinator` owns the recent-hidden reference, while `AppDelegate` dynamically unregisters the global Command-1 restore hotkey during capture so the overlay keeps its existing Command-1 pin shortcut.

**Tech Stack:** Swift 5, AppKit, Carbon HIToolbox, XCTest, Xcode.

---

### Task 1: Make neutral pinned-editor Escape finish editing

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift:2382-2430`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift:679-725`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift:3307-3435`

- [ ] **Step 1: Replace the close-on-second-Escape tests**

Replace the two pinned Escape tests with assertions that a neutral editor Escape hides the toolbar without closing, and that each active tool needs one Escape to deactivate before the next Escape finishes editing:

```swift
@MainActor
func testPinnedImageEditorBaseEscapeFinishesEditingWithoutClosingPin() {
    let controller = PinnedImageWindowController(
        image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
        screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
    )
    var closeCount = 0
    controller.onClose = { closeCount += 1 }
    controller.show()
    controller.test_showEditingToolbar()

    controller.test_editingOverlayKeyDown(
        keyCode: 53,
        charactersIgnoringModifiers: "\u{1b}",
        modifierFlags: []
    )

    XCTAssertEqual(closeCount, 0)
    XCTAssertFalse(controller.test_isToolbarVisible)
    XCTAssertEqual(controller.window?.isVisible, true)
    controller.window?.close()
}

@MainActor
func testPinnedImageActivePrimaryToolsEscapeThenFinishEditing() {
    for key in ["s", "a", "b", "h", "p", "m", "t", "n", "g", "e"] {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        var closeCount = 0
        controller.onClose = { closeCount += 1 }
        controller.show()
        controller.test_showEditingToolbar()
        controller.test_editingOverlayKeyDown(keyCode: 0, charactersIgnoringModifiers: key, modifierFlags: [])

        controller.test_editingOverlayKeyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}", modifierFlags: [])
        XCTAssertEqual(closeCount, 0, key)
        XCTAssertTrue(controller.test_isToolbarVisible, key)

        controller.test_editingOverlayKeyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}", modifierFlags: [])
        XCTAssertEqual(closeCount, 0, key)
        XCTAssertFalse(controller.test_isToolbarVisible, key)
        XCTAssertEqual(controller.window?.isVisible, true, key)
        controller.window?.close()
    }
}
```

Add a third test proving Escape uses the same annotation-baking path as the toolbar button:

```swift
@MainActor
func testPinnedImageEditorEscapeFinishBakesAnnotations() throws {
    let controller = PinnedImageWindowController(
        image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
        screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
    )
    var style = CaptureAnnotationStyle()
    style.strokeColor = .red
    style.fillEnabled = true
    style.fillColor = .red
    let rectangle = CaptureAnnotation(
        kind: .rectangle,
        rect: NSRect(x: 20, y: 20, width: 50, height: 30),
        style: style
    )
    controller.show()
    controller.test_showEditingToolbar()
    controller.test_setEditingOverlayState(annotations: [rectangle], eraserMasks: [])

    controller.test_editingOverlayKeyDown(
        keyCode: 53,
        charactersIgnoringModifiers: "\u{1b}",
        modifierFlags: []
    )

    let pixel = try XCTUnwrap(rgbaRenderPixel(in: controller.image, at: NSPoint(x: 30, y: 30)))
    XCTAssertGreaterThan(pixel.red, 220)
    XCTAssertLessThan(pixel.green, 40)
    XCTAssertLessThan(pixel.blue, 40)
    XCTAssertFalse(controller.test_isToolbarVisible)
    controller.window?.close()
}
```

- [ ] **Step 2: Run the three tests and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorBaseEscapeFinishesEditingWithoutClosingPin \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageActivePrimaryToolsEscapeThenFinishEditing \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorEscapeFinishBakesAnnotations
```

Expected: FAIL because pinned base Escape currently sends `.closeCurrent`.

- [ ] **Step 3: Route pinned base Escape through `.finishEditing`**

Replace `SelectionOverlayWindow.performBaseEscape()` and add the view method beside `handleKeyDown(_:)`:

```swift
private func performBaseEscape() {
    if let overlayView = contentView as? SelectionOverlayView,
       overlayView.finishPinnedImageEditingForEscape() {
        return
    }
    cancelOperation(nil)
}
```

```swift
func finishPinnedImageEditingForEscape() -> Bool {
    guard configuration.showsFinishEditingButton else {
        return false
    }
    finish(action: .finishEditing)
    return true
}
```

- [ ] **Step 4: Re-run the three focused tests and verify GREEN**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorBaseEscapeFinishesEditingWithoutClosingPin \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageActivePrimaryToolsEscapeThenFinishEditing \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorEscapeFinishBakesAnnotations
```

Expected: 3 tests pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift \
  platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "fix(mac): finish pinned editing before closing"
```

### Task 2: Hide pinned windows on Escape without changing true close

**Files:**
- Modify: `platforms/mac/Sources/App/PinnedImageWindowController.swift:67-85`
- Modify: `platforms/mac/Sources/App/PinnedImageWindowController.swift:360-410`
- Modify: `platforms/mac/Sources/App/PinnedImageWindowController.swift:1090-1105`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift:5-18`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift:2973-2987`

- [ ] **Step 1: Add failing hide-versus-close tests**

Replace `FakePinnedWindow` with:

```swift
@MainActor
private final class FakePinnedWindow: PinnedImageWindowPresenting {
    let image: NSImage
    let screenRect: NSRect
    var onHide: (() -> Void)?
    var onClose: (() -> Void)?
    private(set) var showCount = 0
    var didShow: Bool { showCount > 0 }

    init(image: NSImage, screenRect: NSRect) {
        self.image = image
        self.screenRect = screenRect
    }

    func show() { showCount += 1 }
    func simulateHide() { onHide?() }
    func simulateClose() { onClose?() }
}
```

Replace the existing combined Escape/Delete close test with:

```swift
@MainActor
func testPinnedImageEscapeHidesWithoutClosingWhenToolbarIsHidden() {
    let controller = PinnedImageWindowController(
        image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
        screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
    )
    var hideCount = 0
    var closeCount = 0
    controller.onHide = { hideCount += 1 }
    controller.onClose = { closeCount += 1 }
    controller.show()

    controller.test_keyDown(keyCode: 53)

    XCTAssertEqual(hideCount, 1)
    XCTAssertEqual(closeCount, 0)
    XCTAssertEqual(controller.window?.isVisible, false)
    controller.window?.close()
}

@MainActor
func testPinnedImageDeleteKeysStillCloseWhenToolbarIsHidden() {
    for keyCode in [UInt16(51), UInt16(117)] {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        var hideCount = 0
        var closeCount = 0
        controller.onHide = { hideCount += 1 }
        controller.onClose = { closeCount += 1 }
        controller.test_keyDown(keyCode: keyCode)
        XCTAssertEqual(hideCount, 0, "keyCode=\(keyCode)")
        XCTAssertEqual(closeCount, 1, "keyCode=\(keyCode)")
    }
}
```

Extend `testPinnedImageActivePrimaryToolsEscapeThenFinishEditing` to prove the third Escape hides each pin:

```swift
var hideCount = 0
controller.onHide = { hideCount += 1 }

// Insert after the second-Escape toolbar and visibility assertions.
controller.test_keyDown(keyCode: 53)
XCTAssertEqual(hideCount, 1, key)
XCTAssertEqual(closeCount, 0, key)
XCTAssertEqual(controller.window?.isVisible, false, key)
```

- [ ] **Step 2: Run the two tests and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEscapeHidesWithoutClosingWhenToolbarIsHidden \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageDeleteKeysStillCloseWhenToolbarIsHidden
```

Expected: compile failure because `onHide` does not exist.

- [ ] **Step 3: Add lifecycle callbacks and hide behavior**

Use this protocol and controller state:

```swift
@MainActor
protocol PinnedImageWindowPresenting: AnyObject {
    var image: NSImage { get }
    var screenRect: NSRect { get }
    var onHide: (() -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    func show()
}
```

```swift
var onHide: (() -> Void)?
var onClose: (() -> Void)?

fileprivate func hidePinnedWindow() {
    guard window?.isVisible == true else { return }
    window?.orderOut(nil)
    onHide?()
}
```

Split content-view keyboard behavior:

```swift
if event.keyCode == 53 {
    controller?.hidePinnedWindow()
    return
}
if event.keyCode == 51 || event.keyCode == 117 {
    window?.close()
    return
}
```

- [ ] **Step 4: Run Task 1 and Task 2 focused tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorBaseEscapeFinishesEditingWithoutClosingPin \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageActivePrimaryToolsEscapeThenFinishEditing \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorEscapeFinishBakesAnnotations \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEscapeHidesWithoutClosingWhenToolbarIsHidden \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageDeleteKeysStillCloseWhenToolbarIsHidden
```

Expected: the two hide/close tests and the three Task 1 tests pass with 0 failures.

- [ ] **Step 5: Commit**

```bash
git add platforms/mac/Sources/App/PinnedImageWindowController.swift \
  platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): hide pinned images on escape"
```

### Task 3: Cache and restore the most recently hidden pin

**Files:**
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift:5-35`
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift:225-242`
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift:330-350`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift:9088-9140`

- [ ] **Step 1: Add failing coordinator tests**

Add tests that create two pins with the existing fake factory, call `simulateHide()` in order, and verify only the last hidden pin is shown again:

```swift
@MainActor
func testCaptureCoordinatorRestoresMostRecentlyHiddenPinnedWindow() async throws {
    let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
    var pinnedWindows: [FakePinnedWindow] = []
    let coordinator = CaptureCoordinator(
        permissionCoordinator: PermissionCoordinator(),
        screenCaptureService: ScreenCaptureService(),
        pinnedWindowFactory: { image, screenRect in
            let window = FakePinnedWindow(image: image, screenRect: screenRect)
            pinnedWindows.append(window)
            return window
        }
    )

    for index in 0..<2 {
        let completion = expectation(description: "pin \(index)")
        coordinator.captureSessionDidEnd = { completion.fulfill() }
        coordinator.test_handleSelection(
            CaptureSelectionResult(
                screenRect: NSRect(x: CGFloat(index * 100), y: 0, width: 80, height: 60),
                snapshotRect: NSRect(origin: .zero, size: image.size),
                action: .pin
            ),
            frozenDesktopImage: image
        )
        await fulfillment(of: [completion], timeout: 2)
    }

    pinnedWindows[0].simulateHide()
    pinnedWindows[1].simulateHide()

    XCTAssertTrue(coordinator.restoreMostRecentlyHiddenPinnedWindow())
    XCTAssertEqual(pinnedWindows[0].showCount, 1)
    XCTAssertEqual(pinnedWindows[1].showCount, 2)
    XCTAssertFalse(coordinator.restoreMostRecentlyHiddenPinnedWindow())
}
```

Add a second test that hides and then closes one fake pin before restore:

```swift
@MainActor
func testCaptureCoordinatorCloseInvalidatesRecentHiddenPinnedWindow() async throws {
    let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
    var pinnedWindow: FakePinnedWindow?
    let coordinator = CaptureCoordinator(
        permissionCoordinator: PermissionCoordinator(),
        screenCaptureService: ScreenCaptureService(),
        pinnedWindowFactory: { image, screenRect in
            let window = FakePinnedWindow(image: image, screenRect: screenRect)
            pinnedWindow = window
            return window
        }
    )
    let completion = expectation(description: "pin")
    coordinator.captureSessionDidEnd = { completion.fulfill() }
    coordinator.test_handleSelection(
        CaptureSelectionResult(
            screenRect: NSRect(x: 0, y: 0, width: 80, height: 60),
            snapshotRect: NSRect(origin: .zero, size: image.size),
            action: .pin
        ),
        frozenDesktopImage: image
    )
    await fulfillment(of: [completion], timeout: 2)

    let pinnedWindow = try XCTUnwrap(pinnedWindow)
    pinnedWindow.simulateHide()
    pinnedWindow.simulateClose()

    XCTAssertFalse(coordinator.restoreMostRecentlyHiddenPinnedWindow())
    XCTAssertEqual(coordinator.test_pinnedWindowCount, 0)
}
```

- [ ] **Step 2: Run both coordinator tests and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureCoordinatorRestoresMostRecentlyHiddenPinnedWindow \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureCoordinatorCloseInvalidatesRecentHiddenPinnedWindow
```

Expected: compile failure because `restoreMostRecentlyHiddenPinnedWindow()` is undefined.

- [ ] **Step 3: Implement recent-hidden ownership**

Add coordinator state and restore action:

```swift
var captureOverlayDidPresent: (() -> Void)?
private var mostRecentlyHiddenPinnedWindow: PinnedImageWindowPresenting?

@discardableResult
func restoreMostRecentlyHiddenPinnedWindow() -> Bool {
    guard overlayWindow == nil,
          let controller = mostRecentlyHiddenPinnedWindow
    else { return false }
    mostRecentlyHiddenPinnedWindow = nil
    controller.show()
    return true
}
```

Replace the concrete callback setup in `.pin` with identity-based protocol callbacks that avoid a controller/closure retain cycle:

```swift
let controller = pinnedWindowFactory(exportedImage, result.screenRect)
pinnedWindowControllers.append(controller)
let controllerID = ObjectIdentifier(controller)
controller.onHide = { [weak self] in
    guard let self,
          let hidden = self.pinnedWindowControllers.first(where: {
              ObjectIdentifier($0) == controllerID
          })
    else { return }
    self.mostRecentlyHiddenPinnedWindow = hidden
}
controller.onClose = { [weak self] in
    guard let self else { return }
    self.pinnedWindowControllers.removeAll {
        ObjectIdentifier($0) == controllerID
    }
    if let recent = self.mostRecentlyHiddenPinnedWindow,
       ObjectIdentifier(recent) == controllerID {
        self.mostRecentlyHiddenPinnedWindow = nil
    }
}
controller.show()
```

Call `captureOverlayDidPresent?()` after assigning `self.overlayWindow` and before `overlayWindow.present()`.

- [ ] **Step 4: Run coordinator tests plus `testCaptureCoordinatorPinCreatesPinnedWindowWithRenderedImage`**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureCoordinatorRestoresMostRecentlyHiddenPinnedWindow \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureCoordinatorCloseInvalidatesRecentHiddenPinnedWindow \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureCoordinatorPinCreatesPinnedWindowWithRenderedImage
```

Expected: 3 tests pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add platforms/mac/Sources/App/CaptureCoordinator.swift \
  platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): restore the most recently hidden pin"
```

### Task 4: Dynamically route global Command-1

**Files:**
- Modify: `platforms/mac/Sources/App/AppDelegate.swift:4-112`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift:2175-2195`

- [ ] **Step 1: Verify the existing capture Command-1 test passes before registration changes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testCommandOneCompletesSelectionAsPin
```

Expected: PASS. This protects Command-1 pinning inside capture.

- [ ] **Step 2: Generalize the Carbon controller to two hotkeys**

Replace its stored state and initializer with:

```swift
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
```

Add dynamic registration:

```swift
func setRestorePinnedImageHotKeyEnabled(_ isEnabled: Bool) {
    if isEnabled {
        guard restorePinnedImageHotKeyRef == nil else { return }
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

private func registerHotKey(
    keyCode: UInt32,
    modifiers: UInt32,
    id: UInt32
) -> EventHotKeyRef? {
    var reference: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: fourCharacterCode("xxsp"), id: id)
    let status = RegisterEventHotKey(
        keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference
    )
    if status != noErr {
        NSLog("xxsnap hotkey registration failed id=%u status=%d", id, status)
    }
    return status == noErr ? reference : nil
}
```

After reading `EventHotKeyID` in the installed Carbon callback, dispatch with:

```swift
let controller = Unmanaged<CaptureHotKeyController>
    .fromOpaque(userData)
    .takeUnretainedValue()
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
```

Unregister both optional references in `deinit`:

```swift
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
```

- [ ] **Step 3: Wire capture lifecycle to registration**

Use this AppDelegate initialization:

```swift
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
```

- [ ] **Step 4: Build and run focused lifecycle regressions**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testCommandOneCompletesSelectionAsPin \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureCoordinatorRestoresMostRecentlyHiddenPinnedWindow \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureCoordinatorCloseInvalidatesRecentHiddenPinnedWindow \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorBaseEscapeFinishesEditingWithoutClosingPin \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageActivePrimaryToolsEscapeThenFinishEditing \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEscapeHidesWithoutClosingWhenToolbarIsHidden \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageShiftReleaseTogglesToolbarOnAndOff \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorKeyboardCloseRoutesToOwningController
```

Expected: all selected tests pass; build exits 0.

- [ ] **Step 5: Commit**

```bash
git add platforms/mac/Sources/App/AppDelegate.swift
git commit -m "feat(mac): restore hidden pins with command one"
```

### Task 5: Full verification and restart

**Files:**
- Verify: `platforms/mac/xxsnap.xcodeproj`
- Verify: `build/xcode-derived/Build/Products/Debug/XxSnap.app`

- [ ] **Step 1: Run the complete focused keyboard suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorBaseEscapeFinishesEditingWithoutClosingPin \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageActivePrimaryToolsEscapeThenFinishEditing \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorEscapeFinishBakesAnnotations \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEscapeHidesWithoutClosingWhenToolbarIsHidden \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageDeleteKeysStillCloseWhenToolbarIsHidden \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureCoordinatorRestoresMostRecentlyHiddenPinnedWindow \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureCoordinatorCloseInvalidatesRecentHiddenPinnedWindow \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testCommandOneCompletesSelectionAsPin \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageShiftReleaseTogglesToolbarOnAndOff \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorKeyboardCloseRoutesToOwningController \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageKeyboardCopyAndSaveReuseImageActionsWhenToolbarIsHidden \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testNormalCaptureEscapeCancelsSelection
```

Expected: all selected tests pass with 0 failures.

- [ ] **Step 2: Run the full macOS test target**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test
```

Expected: all new tests pass. Any suite failures must match the known six unrelated magnifier and number-control baseline failures.

- [ ] **Step 3: Build the Debug application**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived build
```

Expected: exit code 0.

- [ ] **Step 4: Restart the exact Debug build**

```bash
pkill -f '/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/MacOS/XxSnap'
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app
pgrep -af '/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/MacOS/XxSnap'
```

Expected: one process from the exact `build/xcode-derived` path.

- [ ] **Step 5: Manual smoke test**

1. Create a pin with Command-1, show its toolbar, and activate Rectangle.
2. Escape 1 deactivates Rectangle while keeping the toolbar.
3. Escape 2 applies editing, hides the toolbar, and keeps the pin visible.
4. Escape 3 hides the pin.
5. Command-1 with no capture restores the same position, size, opacity, and level.
6. Command-1 during capture pins the current selection instead of restoring cached content.
7. Delete and Command-W truly close a pin and make it unavailable for restore.

- [ ] **Step 6: Confirm repository state**

```bash
git status --short --branch
git log -6 --oneline
```

Expected: `feature/pin-tool` is clean and contains the implementation commits.
