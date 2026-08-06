# Continuous Manual Scroll Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the visible automatic single-step scroll workflow with real mouse/trackpad scrolling and a temporary checkmark button in the main capture toolbar.

**Architecture:** Make the selection overlay's toolbar derive a temporary finish button from `scrollCaptureOverlayState`, and let the presentation controller place one transparent native hit target over that drawn button. Start the existing activity-driven sampling path by constructing the default session without an automatic step controller; retain the stitcher, preview, warning, retry, keyboard completion, and cancellation state machines.

**Tech Stack:** Swift 6, AppKit, ScreenCaptureKit, XCTest, the existing C++ scroll-stitching bridge, `xcodebuild`.

---

## File map

- Modify `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`: derive the temporary finish button, disable ordinary buttons, route scroll-mode finish, and expose the finish button geometry.
- Modify `platforms/mac/Sources/ScrollCapture/ScrollCapturePresentationController.swift`: remove the visible step toolbar/guide and place the only click-through hit target over the main-toolbar checkmark.
- Modify `platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift`: expose DEBUG-only construction inspection while retaining activity-driven sampling behavior.
- Modify `platforms/mac/Sources/App/CaptureCoordinator.swift`: construct manual-activity sessions and remove the product-level step callback/update path.
- Modify `platforms/mac/Tests/SelectionToolbarStateTests.swift`: cover dynamic toolbar layout, enabled states, lifecycle restoration, finish routing, and coordinator context.
- Modify `platforms/mac/Tests/ScrollCapturePresentationTests.swift`: replace single-step UI tests with one-main-toolbar-finish-button lifecycle coverage while retaining preview/warning tests.
- Modify `platforms/mac/Resources/Help/zh-Hans.json`: document real manual scrolling and the temporary checkmark.
- Modify `platforms/mac/Resources/Help/en.json`: keep the English help in sync.

### Task 1: Make the main toolbar express scroll-capture state

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift:463-520`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift:16480-16670`

- [ ] **Step 1: Write the failing toolbar-state test**

Replace the current geometry and enabled-state expectations in `testBeginScrollCaptureFreezesSeedAndEntersPassiveModeWithoutOrdinaryCompletion` and add explicit lifecycle coverage:

```swift
let toolbarBefore = try XCTUnwrap(window.test_mainToolbarRect())
XCTAssertNil(window.test_mainToolbarButtonRect(for: .finishEditing))

window.test_beginScrollCapture()

let toolbarDuring = try XCTUnwrap(window.test_mainToolbarRect())
let scrollDuring = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .scroll))
let finishDuring = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .finishEditing))
let geometry = try XCTUnwrap(window.scrollCaptureControlGeometry)

XCTAssertGreaterThan(toolbarDuring.width, toolbarBefore.width)
XCTAssertEqual(finishDuring.minX, scrollDuring.maxX + 8, accuracy: 0.5)
XCTAssertEqual(geometry.finishButtonFrame, window.convertToScreen(finishDuring))
XCTAssertTrue(window.test_toolbarButtonIsSelected(.scroll))
XCTAssertFalse(window.test_toolbarButtonIsEnabled(.scroll))
XCTAssertTrue(window.test_toolbarButtonIsEnabled(.finishEditing))
for button: TestToolbarButton in [.rectangle, .undo, .redo, .cancel, .pin, .save, .copy] {
    XCTAssertFalse(window.test_toolbarButtonIsEnabled(button), "\(button) must be disabled")
}
XCTAssertEqual(
    window.test_tooltipText(for: .finishEditing),
    L10n(language: .zhHans).text(.finishScrollCapture)
)
```

Add a cancellation restoration assertion to the existing cancel test:

```swift
coordinator.test_cancelScrollCapture()
XCTAssertNil(overlay.test_mainToolbarButtonRect(for: .finishEditing))
XCTAssertTrue(overlay.test_toolbarButtonIsEnabled(.scroll))
XCTAssertTrue(overlay.test_toolbarButtonIsEnabled(.cancel))
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testBeginScrollCaptureFreezesSeedAndEntersPassiveModeWithoutOrdinaryCompletion
```

Expected: FAIL because `.finishEditing` is absent during scroll capture and `.scroll`/`.cancel` are still enabled.

- [ ] **Step 3: Implement the derived toolbar layout**

Update `mainToolbarButtons()` so the checkmark is inserted only for scroll capture:

```swift
if configuration.showsAnnotationToolbarButtons {
    buttons.append(.scroll)
    if scrollCaptureOverlayState != .inactive {
        buttons.append(.finishEditing)
    }
}
```

Keep the finish button visually attached to scroll and preserve the separator before undo:

```swift
private func mainToolbarExtraGap(after button: ToolbarButton) -> CGFloat {
    switch button {
    case .eraser:
        return 8
    case .scroll:
        return scrollCaptureOverlayState == .inactive ? 8 : 0
    case .finishEditing:
        return scrollCaptureOverlayState == .inactive ? 0 : 8
    case .redo:
        return 8
    default:
        return 0
    }
}
```

Ensure configured editor completion does not duplicate the temporary button:

```swift
if configuration.showsFinishEditingButton, !buttons.contains(.finishEditing) {
    buttons.append(.finishEditing)
}
```

Change the active-state enable policy and geometry lookup:

```swift
private func isToolbarButtonEnabled(_ button: ToolbarButton) -> Bool {
    if scrollCaptureOverlayState != .inactive {
        return button == .finishEditing
    }
    // existing undo/redo/default behavior
}

guard let finishButtonFrame = frames[.finishEditing] else { return nil }
return ScrollCaptureControlGeometry(
    toolbarFrame: toolbarFrame,
    finishButtonFrame: finishButtonFrame
)
```

For tooltips, return `.finishScrollCapture` when `.finishEditing` is the temporary scroll button. Do not change the ordinary editor tooltip.

- [ ] **Step 4: Route the temporary button without changing editor completion**

In `performToolbarButton(_:)`, use the scroll state to disambiguate the shared icon:

```swift
case .finishEditing:
    if scrollCaptureOverlayState != .inactive {
        scrollCaptureFinishDidRequest?()
    } else {
        finish(action: .finishEditing)
    }
```

The overlay window itself remains mouse-passive during capture; this branch is exercised by focused test hooks and protects the normal editor behavior. The presentation hit panel added in Task 2 is the live click path.

- [ ] **Step 5: Run the focused toolbar tests and verify GREEN**

Run the Task 1 command plus the existing normal finish-editing test:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testBeginScrollCaptureFreezesSeedAndEntersPassiveModeWithoutOrdinaryCompletion \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorFinishCompletesSynchronously
```

Expected: both tests PASS and ordinary editor completion still returns `.finishEditing`.

- [ ] **Step 6: Commit the toolbar state change**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift \
  platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): add scroll capture finish control to main toolbar"
```

### Task 2: Remove the visible single-step controls

**Files:**
- Modify: `platforms/mac/Tests/ScrollCapturePresentationTests.swift`
- Modify: `platforms/mac/Sources/ScrollCapture/ScrollCapturePresentationController.swift`
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift:21-75,680-820,910-960`

- [ ] **Step 1: Replace step-toolbar tests with a failing main-toolbar hit-target test**

Delete tests whose only contract is direction menu, step button, step progress, step toolbar placement, or step guide presentation. Update `testControlPanelIsNonactivatingAndLifecycleIsIdempotent` to assert:

```swift
XCTAssertEqual(controller.test_finishButtonFrame, finish)
XCTAssertEqual(controller.test_controlHitTargetCount, 1)
XCTAssertEqual(controller.test_interactiveWindowFrames, [toolbar])
XCTAssertTrue(controller.test_toolbarPointIsInteractive(
    NSPoint(x: finish.midX, y: finish.midY)
))
XCTAssertFalse(controller.test_toolbarPointIsInteractive(
    NSPoint(x: cancel.midX, y: cancel.midY)
))
XCTAssertFalse(controller.test_hasVisibleStepControls)
XCTAssertEqual(controller.test_finishButtonToolTip, "Finish Scroll Capture")
XCTAssertEqual(controller.test_finishAccessibilityLabel, "Finish Scroll Capture")
```

Construct the controller without `cancelButtonFrame`, `onStep`, or `onCancel`:

```swift
let controller = ScrollCapturePresentationController(
    toolbarFrame: toolbar,
    finishButtonFrame: finish,
    selectionFrame: selection,
    visibleFrame: visible,
    language: .english,
    onFinish: { finishes += 1 }
)
```

- [ ] **Step 2: Run the presentation test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/ScrollCapturePresentationTests/testControlPanelIsNonactivatingAndLifecycleIsIdempotent
```

Expected: build/test FAIL because the old controller still exposes the step toolbar and old initializer.

- [ ] **Step 3: Reduce presentation context to completion only**

Change the context and factory call in `CaptureCoordinator.swift`:

```swift
struct ScrollCapturePresentationContext {
    let geometry: ScrollCaptureControlGeometry
    let selectionFrame: NSRect
    let visibleFrame: NSRect
    let language: AppLanguage
    let onFinish: @MainActor () -> Void
}
```

Remove `onStep` and `onCancel` wiring, remove `performScrollCaptureStep(direction:)`, and ignore `.stepState` presentation updates:

```swift
case .stepState:
    break
```

Keep `Esc` cancellation in `SelectionOverlayWindow` and `ScrollActivityMonitor` unchanged.

- [ ] **Step 4: Make the control panel contain only the finish hit target**

In `ScrollCapturePresentationController`, configure `finishButton` inside `controlPanel`:

```swift
configureControlButton(
    finishButton,
    frame: finishButtonFrame.offsetBy(dx: -controlFrame.minX, dy: -controlFrame.minY),
    action: #selector(finishPressed),
    label: finishLabel
)
content.addSubview(finishButton)
```

Delete the direction popup, start button, stop button, progress indicator, step panel, step guide panel, their layout helpers, selectors, and DEBUG accessors. `start()` should order only `controlPanel` and `previewPanel`; `cleanup()` should close/detach only the remaining panels.

Update preview and warning placement to avoid only `controlFrame` and `previewPanel.frame`, never a step-toolbar frame.

Keep `resetTerminalActionsForRetry()` limited to:

```swift
terminalActionTriggered = false
finishButton.isEnabled = true
controlPanel.ignoresMouseEvents = false
```

- [ ] **Step 5: Run all presentation tests and verify GREEN**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/ScrollCapturePresentationTests
```

Expected: PASS with no test referring to direction menus, single-step buttons, a step toolbar, or a step guide.

- [ ] **Step 6: Commit the presentation simplification**

```bash
git add platforms/mac/Sources/App/CaptureCoordinator.swift \
  platforms/mac/Sources/ScrollCapture/ScrollCapturePresentationController.swift \
  platforms/mac/Tests/ScrollCapturePresentationTests.swift \
  platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "refactor(mac): remove scroll capture step toolbar"
```

### Task 3: Make real scrolling the default capture driver

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift:12000-12500`
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift:220-240`
- Modify: `platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift:289-350`

- [ ] **Step 1: Add a failing default-session construction test**

Add DEBUG-only inspection to `ScrollCaptureSession` and a coordinator helper that constructs a session through the configured factory:

```swift
#if DEBUG
var test_hasAutomaticStepController: Bool { stepController != nil }
#endif
```

```swift
#if DEBUG
func test_makeScrollCaptureSession(seed: ScrollCaptureSeed) -> any ScrollCaptureSessionRunning {
    scrollCaptureSessionFactory(seed) { _ in }
}
#endif
```

Add this test:

```swift
@MainActor
func testDefaultScrollCaptureUsesManualActivitySampling() {
    let coordinator = CaptureCoordinator(
        permissionCoordinator: PermissionCoordinator(),
        screenCaptureService: ScreenCaptureService()
    )
    let session = coordinator.test_makeScrollCaptureSession(
        seed: scrollCaptureSeedForCoordinatorTests()
    ) as? ScrollCaptureSession

    XCTAssertNotNil(session)
    XCTAssertFalse(session?.test_hasAutomaticStepController ?? true)
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testDefaultScrollCaptureUsesManualActivitySampling
```

Expected: FAIL because the current default factory injects `AutomaticScrollCaptureStepController`.

- [ ] **Step 3: Construct the default session without automatic scrolling**

Remove the `AutomaticScrollCaptureStepController` argument from the default factory:

```swift
return ScrollCaptureSession(
    seed: seed,
    capturer: StreamingScrollRegionCapturer(service: screenCaptureService),
    stitcher: bridge,
    clock: ContinuousScrollCaptureClock(),
    activityMonitor: ScrollActivityMonitor(),
    diagnosticLogger: diagnosticLogger,
    presentation: update
)
```

This selects the existing `startActivityMonitor()` branch, so physical scroll events are not intercepted and scroll activity arms `runSamplingTick()`.

- [ ] **Step 4: Run manual-activity session and coordinator tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testDefaultScrollCaptureUsesManualActivitySampling \
  -only-testing:xxsnapTests/ScrollCaptureSessionTests
```

Expected: PASS, including existing tests that prove scroll activity arms sampling, later activity re-arms it, and terminal commands only publish in capturable states.

- [ ] **Step 5: Commit the driver change**

```bash
git add platforms/mac/Sources/App/CaptureCoordinator.swift \
  platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift \
  platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): drive scroll capture from physical scrolling"
```

### Task 4: Update the built-in help

**Files:**
- Modify: `platforms/mac/Resources/Help/zh-Hans.json:184-216`
- Modify: `platforms/mac/Resources/Help/en.json:187-216`

- [ ] **Step 1: Replace obsolete single-step instructions**

The Chinese steps must say:

```json
{
  "type": "steps",
  "items": [
    { "text": "锁定网页、文档或列表的内容区域，避开固定不动的侧栏。" },
    { "text": "点击滚动截图后，直接使用鼠标滚轮或触控板滚动目标内容。" },
    { "text": "采集完成后，点击滚动截图图标右侧临时出现的对勾。" }
  ]
}
```

State that the first reliable movement locks direction, reverse movement is review only, the physical wheel is not blocked, Accessibility is only needed for global key monitoring, and `Esc` cancels. Update the `capture-scroll-session` caption/accessibility label to describe the main-toolbar checkmark and preview; remove every mention of direction menus, Start Scroll Step, or repeated clicking.

Apply the same meaning to `en.json` using concise native English.

- [ ] **Step 2: Validate both JSON files**

```bash
plutil -lint platforms/mac/Resources/Help/zh-Hans.json
plutil -lint platforms/mac/Resources/Help/en.json
rg -n "单步|方向下拉|Start Scroll Step|direction menu|blocks your physical scroll" \
  platforms/mac/Resources/Help/zh-Hans.json \
  platforms/mac/Resources/Help/en.json
```

Expected: both files report `OK`; `rg` returns no matches in the scroll-capture documentation.

- [ ] **Step 3: Commit the help update**

```bash
git add platforms/mac/Resources/Help/zh-Hans.json \
  platforms/mac/Resources/Help/en.json
git commit -m "docs(mac): explain continuous manual scroll capture"
```

### Task 5: Full verification and handoff

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run whitespace and stale-contract checks**

```bash
git diff --check
rg -n "onStep|performScrollCaptureStep|stepPanel|stepGuidePanel|Start Scroll Step|开始单步滚动" \
  platforms/mac/Sources/App/CaptureCoordinator.swift \
  platforms/mac/Sources/ScrollCapture/ScrollCapturePresentationController.swift \
  platforms/mac/Tests/ScrollCapturePresentationTests.swift \
  platforms/mac/Resources/Help
```

Expected: `git diff --check` succeeds and the stale-contract search returns no matches.

- [ ] **Step 2: Run focused macOS regression suites**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests \
  -only-testing:xxsnapTests/ScrollCapturePresentationTests \
  -only-testing:xxsnapTests/ScrollCaptureSessionTests
```

Expected: all three suites PASS.

- [ ] **Step 3: Run the full macOS test target**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Build the application**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Perform manual acceptance before claiming parity**

Launch `build/xcode-derived/Build/Products/Debug/XxSnap.app` and verify:

1. Start a region capture and confirm no checkmark is present before scroll capture.
2. Click Scroll Capture and confirm the checkmark appears immediately to its right.
3. Confirm all other toolbar buttons are disabled and the old second toolbar never appears.
4. Scroll with a mouse wheel, then a trackpad, and confirm the target page receives both forms of input.
5. Click the checkmark and confirm the long-image editor opens and the temporary checkmark disappears.
6. Repeat once with `Esc` and confirm the original selection and normal toolbar return.
7. Test at least Chrome, Safari, Finder, Preview/PDF, and one Electron app before comparing results with PixPin.

- [ ] **Step 6: Commit any verification-only fixes, then report evidence**

```bash
git status --short
git log --oneline --decorate -6
```

Report changed files, focused/full test outcomes, build outcome, what was manually exercised, and any application category still requiring the user's test.
