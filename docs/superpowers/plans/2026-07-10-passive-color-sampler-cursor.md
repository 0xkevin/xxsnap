# Passive Color Sampler Cursor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the background-aware move-cross cursor whenever passive color sampling is visible inside a locked selection, including full-screen selections.

**Architecture:** Derive a focused `isPassiveColorSamplerVisible` state from the same conditions used to draw the sampler, then insert that cursor rule after toolbar/control and resize precedence but before movement eligibility and generic idle fallback. Do not change selection movement geometry or any active-tool cursor logic.

**Tech Stack:** Swift 5, AppKit, XCTest, Xcode.

---

### Task 1: Lock the passive-sampler cursor behavior with tests

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift:4300-4380`

- [ ] **Step 1: Add full-screen passive sampler cursor tests**

Add these tests beside the existing overlay cursor tests:

```swift
func testPassiveColorSamplerUsesMoveCursorForFullScreenSelection() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let screen = try XCTUnwrap(NSScreen.main)
    let selection = NSRect(
        x: screen.frame.minX - window.frame.minX,
        y: screen.frame.minY - window.frame.minY,
        width: screen.frame.width,
        height: screen.frame.height
    )
    let point = NSPoint(x: selection.midX, y: selection.midY)
    window.test_setLockedSelectionRect(selection)

    window.test_updateColorSampler(at: point)

    XCTAssertTrue(window.test_isColorSamplerVisible)
    XCTAssertEqual(window.test_cursorStyle(at: point), .move)
}

func testPassiveColorSamplerUsesLightMoveCursorOnDarkFullScreenSelection() throws {
    let background = solidImage(size: desktopImageSize(), color: .black)
    let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
    let screen = try XCTUnwrap(NSScreen.main)
    let selection = NSRect(
        x: screen.frame.minX - window.frame.minX,
        y: screen.frame.minY - window.frame.minY,
        width: screen.frame.width,
        height: screen.frame.height
    )
    let point = NSPoint(x: selection.midX, y: selection.midY)
    window.test_setLockedSelectionRect(selection)

    window.test_updateColorSampler(at: point)

    XCTAssertTrue(window.test_isColorSamplerVisible)
    XCTAssertEqual(window.test_cursorStyle(at: point), .moveLight)
}

func testFullScreenSelectionKeepsCrosshairUntilPassiveSamplerIsVisible() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let screen = try XCTUnwrap(NSScreen.main)
    let selection = NSRect(
        x: screen.frame.minX - window.frame.minX,
        y: screen.frame.minY - window.frame.minY,
        width: screen.frame.width,
        height: screen.frame.height
    )
    let point = NSPoint(x: selection.midX, y: selection.midY)
    window.test_setLockedSelectionRect(selection)

    XCTAssertFalse(window.test_isColorSamplerVisible)
    XCTAssertEqual(window.test_cursorStyle(at: point), .crosshair)
}
```

- [ ] **Step 2: Run the new tests and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPassiveColorSamplerUsesMoveCursorForFullScreenSelection \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPassiveColorSamplerUsesLightMoveCursorOnDarkFullScreenSelection \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testFullScreenSelectionKeepsCrosshairUntilPassiveSamplerIsVisible
```

Expected: the first two tests fail with `crosshair` instead of `move`/`moveLight`; the third passes.

### Task 2: Decouple passive-sampler appearance from movement eligibility

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift:2794-3003`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift:3835-3905`

- [ ] **Step 1: Add a visibility helper that mirrors sampler drawing state**

Add beside `updateColorSampler(at:)`:

```swift
private var isPassiveColorSamplerVisible: Bool {
    guard configuration.allowsPassiveColorSampler,
          !isEyedropperToolActive,
          let sampledPointerPoint,
          sampledColor != nil
    else {
        return false
    }

    return SelectionToolbarState.shouldShowColorSampler(
        isShapeToolActive: isShapeToolActive,
        hasAnnotations: !annotations.isEmpty,
        pointer: sampledPointerPoint,
        selectionRect: colorSamplerSelectionRect
    )
}
```

- [ ] **Step 2: Insert the passive-sampler cursor rule at the correct precedence**

In `cursorStyle(at:)`, after selection resize-handle handling and before `shouldStartSelectionMove(at:)`, add:

```swift
if interactionMode == .annotating,
   isPassiveColorSamplerVisible,
   isInsideSelection,
   !isToolbarOrPanelPoint(point) {
    return backgroundAwareCursorStyle(.move, at: point)
}
```

This leaves toolbar, panel, annotation-control, and resize cursors untouched and does not call the selection movement path.

- [ ] **Step 3: Run the three new tests and verify GREEN**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPassiveColorSamplerUsesMoveCursorForFullScreenSelection \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPassiveColorSamplerUsesLightMoveCursorOnDarkFullScreenSelection \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testFullScreenSelectionKeepsCrosshairUntilPassiveSamplerIsVisible
```

Expected: 3 tests pass, 0 failures.

- [ ] **Step 4: Run focused cursor regressions**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPassiveColorSamplerUsesMoveCursorForFullScreenSelection \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPassiveColorSamplerUsesLightMoveCursorOnDarkFullScreenSelection \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testFullScreenSelectionKeepsCrosshairUntilPassiveSamplerIsVisible \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testOverlayWindowUsesDrawingCursorInsideSelectionImmediatelyAfterToolSwitch \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testOverlayWindowUsesLightBrushCursorOnBlackBackground \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testOverlayWindowUsesLightEyedropperCursorOnBlackBackground \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testOverlayWindowUsesLightSelectionResizeCursorsOnBlackBackground \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierKeepsCrosshairCursorInsideSelection \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditorOverlayUsesMoveCursorInsideSelectionWhenNoToolSelected
```

Expected: 9 tests pass, 0 failures.

- [ ] **Step 5: Commit the cursor fix**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift \
  platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "fix(mac): restore passive sampler move cursor"
```

### Task 3: Full verification, build, and restart

**Files:**
- Verify: `platforms/mac/xxsnap.xcodeproj`
- Verify: `build/xcode-derived/Build/Products/Debug/XxSnap.app`

- [ ] **Step 1: Run the full macOS test target**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test
```

Expected: new cursor tests pass; any full-suite failures match the known six unrelated magnifier and number-control baseline failures.

- [ ] **Step 2: Build the Debug application**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived build
```

Expected: exit code 0.

- [ ] **Step 3: Restart the exact Debug build**

```bash
pkill -f '/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/MacOS/XxSnap'
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app
pgrep -af '/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/MacOS/XxSnap'
```

Expected: one process from the exact `build/xcode-derived` path.

- [ ] **Step 4: Manual smoke check**

Start capture, lock a selection without choosing a tool, and move the pointer through the selection interior, border, and toolbar. Confirm move-cross inside, resize cursors on borders, and arrow over the toolbar. Repeat on a dark area and confirm the light move-cross variant remains visible.

- [ ] **Step 5: Confirm repository state**

```bash
git status --short --branch
git log -4 --oneline
```

Expected: `feature/pin-tool` is clean and contains `fix(mac): restore passive sampler move cursor`.
