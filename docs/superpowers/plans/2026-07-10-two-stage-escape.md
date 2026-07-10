# Two-Stage Escape Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ESC leave every active annotation tool before a subsequent ESC closes the current capture or pinned-image window.

**Architecture:** Add one state-driven escape consumer to `SelectionOverlayView`, evaluated before toolbar shortcut dispatch. If the view does not consume ESC, `SelectionOverlayWindow` performs the surface-level action: cancel a normal capture or route `.closeCurrent` to the owning pinned-image controller.

**Tech Stack:** Swift 5, AppKit, XCTest, Xcode.

---

### Task 1: Specify the two-stage behavior with failing tests

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Add normal-capture tool coverage**

Add a table-driven test using the primary tool shortcuts `s`, `a`, `b`, `h`, `p`, `m`, `t`, `n`, `g`, and `e`. For each shortcut, create a locked selection, activate the tool, press ESC once, and assert that the completion callback has not run. Press ESC again and assert one nil completion.

```swift
func testActivePrimaryToolsRequireTwoEscapesToCloseCapture() {
    for key in ["s", "a", "b", "h", "p", "m", "t", "n", "g", "e"] {
        var completions = 0
        var result: CaptureSelectionResult?
        let window = SelectionOverlayWindow(backgroundImage: nil) {
            completions += 1
            result = $0
        }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: key)

        window.test_keyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}")
        XCTAssertEqual(completions, 0, key)

        window.test_keyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}")
        XCTAssertEqual(completions, 1, key)
        XCTAssertNil(result, key)
    }
}
```

- [ ] **Step 2: Replace the old pinned-editor ESC expectation**

Replace `testPinnedImageEditorEscapeFinishesEditingAndKeepsAnnotations` with controller-level tests that verify a neutral pinned editor closes on one ESC and every active primary tool requires two ESC presses.

```swift
func testPinnedImageEditorBaseEscapeClosesCurrentPin() {
    let controller = PinnedImageWindowController(
        image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
        screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
    )
    var closeCount = 0
    controller.onClose = { closeCount += 1 }
    controller.test_showEditingToolbar()

    controller.test_editingOverlayKeyDown(
        keyCode: 53,
        charactersIgnoringModifiers: "\u{1b}",
        modifierFlags: []
    )

    XCTAssertEqual(closeCount, 1)
}

func testPinnedImageActivePrimaryToolsRequireTwoEscapesToClosePin() {
    for key in ["s", "a", "b", "h", "p", "m", "t", "n", "g", "e"] {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        var closeCount = 0
        controller.onClose = { closeCount += 1 }
        controller.test_showEditingToolbar()
        controller.test_editingOverlayKeyDown(keyCode: 0, charactersIgnoringModifiers: key, modifierFlags: [])

        controller.test_editingOverlayKeyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}", modifierFlags: [])
        XCTAssertEqual(closeCount, 0, key)
        XCTAssertTrue(controller.test_isToolbarVisible, key)

        controller.test_editingOverlayKeyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}", modifierFlags: [])
        XCTAssertEqual(closeCount, 1, key)
    }
}
```

- [ ] **Step 3: Verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testActivePrimaryToolsRequireTwoEscapesToCloseCapture \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorBaseEscapeClosesCurrentPin \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageActivePrimaryToolsRequireTwoEscapesToClosePin
```

Expected: FAIL because active tools currently dispatch the cancel/finish toolbar action on the first ESC, and a neutral pinned editor only finishes its overlay instead of closing the pin.

### Task 2: Implement the state-driven escape consumer

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`

- [ ] **Step 1: Intercept ESC before specialized editors and toolbar shortcuts**

At the start of `SelectionOverlayView.handleKeyDown(_:)`, after the text-editor pass-through check, add:

```swift
if event.keyCode == 53 {
    return cancelActiveToolForEscape()
}
```

This must return `false` in the base state so the owning window performs the second-level action.

- [ ] **Step 2: Add the centralized tool cleanup**

Add `cancelActiveToolForEscape() -> Bool` beside the keyboard handlers. It must detect all sustained tools and transient editors, then perform these concrete mutations before returning `true`:

```swift
private func cancelActiveToolForEscape() -> Bool {
    let hasActiveTool = isShapeToolActive
        || isEyedropperToolActive
        || isTextToolActive
        || isNumberToolActive
        || isMagnifierToolActive
        || isEraserToolActive
    let hasTransientToolState = isEditingTextAnnotation
        || editingNumberAnnotationIndex != nil
        || mosaicValueEditingText != nil
        || activeTextDropdown != nil
        || activeNumberDropdown
        || activeMagnifierZoomDropdown
        || showsStrokeStyleMenu
        || showsCornerRadiusPanel
        || showsStartArrowTypeMenu
        || showsEndArrowTypeMenu
    guard hasActiveTool || hasTransientToolState else {
        return false
    }

    commitCurrentTextEdit()
    commitNumberEditingIfNeeded()
    mosaicValueEditingText = nil
    clearPendingTextEdit()
    closeTextDropdown()
    closeMagnifierZoomDropdown()
    rememberCurrentStyleForActiveTool()

    isShapeToolActive = false
    activeShapeKind = nil
    isEyedropperToolActive = false
    isTextToolActive = false
    isNumberToolActive = false
    isMagnifierToolActive = false
    isEraserToolActive = false
    activeNumberDropdown = false
    clearEyedropperMeasurement()
    clearColorSampler()
    clearEraserRectangleState()

    shapeStartPoint = nil
    shapeCurrentPoint = nil
    brushDraftPoints.removeAll()
    mosaicDraftPoints.removeAll()
    selectedAnnotationIndex = nil
    revealedNumberControlsIndex = nil
    showsStrokeStyleMenu = false
    showsCornerRadiusPanel = false
    showsStartArrowTypeMenu = false
    showsEndArrowTypeMenu = false
    interactionMode = lockedSelectionRect == nil ? .selecting : .annotating
    resetMosaicPreviewCaches()
    invalidateCursorRectsAndRefresh()
    needsDisplay = true
    return true
}
```

- [ ] **Step 3: Route base ESC by surface type**

Add a `SelectionOverlayWindow.performBaseEscape()` helper and use it from both `processMonitoredKeyDown` and `keyDown` instead of calling `cancelOperation` directly:

```swift
private func performBaseEscape() {
    if configuration.showsFinishEditingButton,
       let handler = configuration.pinnedImageWindowCommandHandler {
        handler(.closeCurrent)
    } else {
        cancelOperation(nil)
    }
}
```

Keep `cancelOperation(_:)` unchanged so the pinned window delegate can dismiss the editing overlay during window closure without recursively requesting another close.

- [ ] **Step 4: Verify GREEN**

Run the focused command from Task 1 Step 3.

Expected: all three tests pass.

### Task 3: Protect drafts and existing shortcuts

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Extend draft tests**

Update the existing empty-text ESC test to assert the completion callback is not invoked and the text tool is inactive after the first ESC. Add a shape-draft test that begins a rectangle drag without mouse-up, presses ESC, and asserts no annotation was committed and the window remains open.

- [ ] **Step 2: Run the related keyboard suite**

Run the new two-stage tests plus existing tests for empty/whitespace text drafts, normal base ESC, pinned hidden-toolbar Escape/Delete closure, Shift toolbar toggle, copy/save shortcuts, and Command-W closure.

Expected: all selected tests pass and existing shortcut behavior is unchanged.

- [ ] **Step 3: Commit the implementation**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift \
  platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "fix(mac): make escape exit tools before closing"
```

### Task 4: Full verification and restart

**Files:**
- Verify: `platforms/mac/xxsnap.xcodeproj`
- Verify: `build/xcode-derived/Build/Products/Debug/XxSnap.app`

- [ ] **Step 1: Run the full macOS test target**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test
```

Expected: the new ESC tests pass; compare any full-suite failures with the known six unrelated magnifier/number-control baseline failures.

- [ ] **Step 2: Build the Debug app**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Restart and verify the process**

Terminate the exact Debug binary, open `build/xcode-derived/Build/Products/Debug/XxSnap.app`, and confirm the same binary path with `pgrep -af`.

Expected: one running Debug process from `build/xcode-derived`.
