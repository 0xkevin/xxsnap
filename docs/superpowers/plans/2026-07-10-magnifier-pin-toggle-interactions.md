# Magnifier And Pinned-Image Toggle Interactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add directional move/resize cursor feedback to selected magnifiers and make standalone `Shift` repeatedly toggle the pinned-image editing toolbar while preserving the existing `Command-T` always-on-top toggle.

**Architecture:** Keep both changes inside the existing AppKit event paths. Magnifier cursor resolution will use only the already-selected annotation and existing handle/body geometry helpers before falling back to the creation crosshair; pinned-image `Shift` handling will call one shared toolbar toggle operation on a valid modifier-key release. No renderer, annotation model, export path, global event monitor, timer, or tracking-area change is required.

**Tech Stack:** Swift, AppKit, XCTest, existing `SelectionOverlayWindow`, `PinnedImageWindowController`, and `SelectionToolbarState` cursor mapping.

---

## File Structure

- Modify `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`: change magnifier cursor precedence while reusing existing selected-annotation hit tests and cached cursors.
- Modify `platforms/mac/Sources/App/PinnedImageWindowController.swift`: route menu and standalone-`Shift` activation through one show/hide toggle.
- Modify `platforms/mac/Tests/SelectionToolbarStateTests.swift`: add cursor regression coverage and change the existing show-only `Shift` expectation into repeatable toggle coverage.
- Do not modify rendering, export, annotation models, project configuration, or resources.

The affected source and test files already contain overlapping uncommitted work. During execution, preserve that work and do not create implementation commits that would accidentally include unrelated hunks. Use diff review checkpoints instead; commit only if the overlapping changes have become safely separable.

### Task 1: Selected magnifier move and resize cursors

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift:2761-2803`

- [ ] **Step 1: Write the failing cursor regression test**

Add this test near the existing magnifier interaction tests:

```swift
func testSelectedMagnifierUsesMoveAndDirectionalResizeCursors() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let selection = NSRect(x: 80, y: 80, width: 260, height: 180)
    window.test_setLockedSelectionRect(selection)
    window.test_setAnnotations([
        CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 40, y: 35, width: 100, height: 80),
            style: CaptureAnnotationStyle(),
            magnifierShape: .rectangle,
            magnifierZoom: 2
        ),
    ])
    window.test_activateMagnifierTool()
    window.test_selectAnnotation(at: 0)

    let expected: [(SelectionToolbarState.OverlayResizeHandle, SelectionToolbarState.OverlayCursorStyle)] = [
        (.topLeft, .resizeTopLeft),
        (.top, .resizeUpDown),
        (.topRight, .resizeTopRight),
        (.left, .resizeLeftRight),
        (.right, .resizeLeftRight),
        (.bottomLeft, .resizeBottomLeft),
        (.bottom, .resizeUpDown),
        (.bottomRight, .resizeBottomRight),
    ]
    for (handle, cursor) in expected {
        let point = try XCTUnwrap(window.test_shapeResizeHandlePoint(handle))
        XCTAssertEqual(window.test_cursorStyle(at: point), cursor, String(describing: handle))
    }

    let magnifierRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
    XCTAssertEqual(
        window.test_cursorStyle(at: NSPoint(x: magnifierRect.midX, y: magnifierRect.midY)),
        .move
    )
    XCTAssertEqual(
        window.test_cursorStyle(at: NSPoint(x: selection.minX + 12, y: selection.minY + 12)),
        .crosshair
    )
}
```

- [ ] **Step 2: Run the new test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testSelectedMagnifierUsesMoveAndDirectionalResizeCursors
```

Expected: FAIL because every non-toolbar point currently returns `.crosshair` while the magnifier tool is active.

- [ ] **Step 3: Implement selected-magnifier cursor precedence**

Replace the existing show-arrow-or-crosshair magnifier branch in `cursorStyle(at:)` with:

```swift
if isMagnifierToolActive {
    if isToolbarOrPanelPoint(point) {
        return .arrow
    }
    if interactionMode == .movingShape {
        return backgroundAwareCursorStyle(.move, at: point)
    }
    if interactionMode == .annotating,
       let handle = textAwareResizeHandle(at: point)?.toolbarStateHandle {
        return backgroundAwareCursorStyle(
            SelectionToolbarState.overlayCursorStyle(for: handle),
            at: point
        )
    }
    if interactionMode == .annotating,
       let selectedAnnotation,
       selectedAnnotation.kind == .magnifier,
       annotationBorderContains(point, for: selectedAnnotation) {
        return backgroundAwareCursorStyle(.move, at: point)
    }
    return .crosshair
}
```

This intentionally checks only the selected annotation. It avoids the reverse scan across all annotations performed by `annotationIndexForBorder(at:)` and keeps mouse-move work constant with annotation count.

- [ ] **Step 4: Run the new test and verify GREEN**

Run the Step 2 command again.

Expected: PASS with all eight handle directions, body move, and off-annotation crosshair assertions green.

- [ ] **Step 5: Review the focused diff**

Run:

```bash
git diff --check -- platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git diff -- platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
```

Expected: no whitespace errors; the cursor implementation contains no new allocation, tracking, rendering, timer, or observer code.

### Task 2: Repeatable standalone-Shift toolbar toggle

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift:2935-2951`
- Modify: `platforms/mac/Sources/App/PinnedImageWindowController.swift:324-330`
- Modify: `platforms/mac/Sources/App/PinnedImageWindowController.swift:1045-1056`

- [ ] **Step 1: Change the existing test to require repeated toggling**

Replace `testPinnedImageShiftReleaseShowsToolbarOnceWithoutTogglingItOff` with:

```swift
@MainActor
func testPinnedImageShiftReleaseTogglesToolbarOnAndOff() {
    let controller = PinnedImageWindowController(
        image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
        screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
    )

    controller.test_flagsChanged(modifierFlags: [.shift])
    XCTAssertFalse(controller.test_isToolbarVisible)

    controller.test_flagsChanged(modifierFlags: [])
    XCTAssertTrue(controller.test_isToolbarVisible)

    controller.test_flagsChanged(modifierFlags: [.shift])
    controller.test_flagsChanged(modifierFlags: [])
    XCTAssertFalse(controller.test_isToolbarVisible)
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
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageShiftReleaseTogglesToolbarOnAndOff
```

Expected: FAIL because the second standalone `Shift` release leaves the toolbar visible.

- [ ] **Step 3: Add one shared toolbar toggle operation**

Change the context-menu selector to delegate to a callable toggle:

```swift
@objc private func toggleEditingToolbarFromMenu() {
    toggleEditingToolbar()
}

fileprivate func toggleEditingToolbar() {
    if editingOverlayWindow == nil {
        showEditingToolbar()
    } else {
        hideEditingToolbar()
    }
}
```

Update `flagsChanged(with:)` so a standalone `Shift` press is accepted in either visibility state and release invokes the shared toggle:

```swift
override func flagsChanged(with event: NSEvent) {
    let relevantModifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
    if relevantModifiers == [.shift], dragOffset == nil {
        shiftToolbarShortcutCandidate = true
    } else if relevantModifiers.isEmpty, shiftToolbarShortcutCandidate {
        shiftToolbarShortcutCandidate = false
        controller?.toggleEditingToolbar()
    } else {
        shiftToolbarShortcutCandidate = false
    }
    super.flagsChanged(with: event)
}
```

Do not alter `cancelShiftToolbarShortcutCandidate()`: keyboard, mouse, mixed-modifier, and drag cancellation continue using the existing path.

- [ ] **Step 4: Run toggle and cancellation tests and verify GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageShiftReleaseTogglesToolbarOnAndOff \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageShiftShortcutCancelsWhenCombinedWithOtherInput \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageShiftShortcutDoesNotStartWhileDragging \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageContextMenuTogglesToolbarVisibilityAndState
```

Expected: PASS. The shortcut toggles both directions, while invalid sequences and dragging remain no-ops.

- [ ] **Step 5: Review the focused diff**

Run:

```bash
git diff --check -- platforms/mac/Sources/App/PinnedImageWindowController.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git diff -- platforms/mac/Sources/App/PinnedImageWindowController.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
```

Expected: no whitespace errors; menu and keyboard paths share the same state transition, and the event handler performs no idle work.

### Task 3: Always-on-top and full regression verification

**Files:**
- Verify: `platforms/mac/Sources/App/PinnedImageWindowController.swift`
- Verify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Verify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Extend the existing always-on-top regression with menu-state assertions**

Replace the existing test with:

```swift
func testPinnedImageAlwaysOnTopShortcutSynchronizesEditingOverlayLevel() throws {
    for showsToolbar in [false, true] {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        if showsToolbar {
            controller.test_showEditingToolbar()
            XCTAssertEqual(controller.test_editingOverlayWindowLevel, .floating)
        }
        XCTAssertEqual(
            try XCTUnwrap(controller.makeContextMenu().items.first { $0.title == "置顶" }).state,
            .on
        )

        let sendShortcut = {
            if showsToolbar {
                controller.test_editingOverlayKeyDown(
                    keyCode: 17,
                    charactersIgnoringModifiers: "t",
                    modifierFlags: [.command]
                )
            } else {
                controller.test_keyDown(
                    keyCode: 17,
                    charactersIgnoringModifiers: "t",
                    modifierFlags: [.command]
                )
            }
        }
        sendShortcut()

        XCTAssertEqual(controller.test_windowLevel, .normal)
        XCTAssertEqual(
            try XCTUnwrap(controller.makeContextMenu().items.first { $0.title == "置顶" }).state,
            .off
        )
        if showsToolbar {
            XCTAssertEqual(controller.test_editingOverlayWindowLevel, .normal)
        }

        sendShortcut()
        XCTAssertEqual(controller.test_windowLevel, .floating)
        XCTAssertEqual(
            try XCTUnwrap(controller.makeContextMenu().items.first { $0.title == "置顶" }).state,
            .on
        )
        if showsToolbar {
            XCTAssertEqual(controller.test_editingOverlayWindowLevel, .floating)
        }
        controller.window?.close()
    }
}
```

- [ ] **Step 2: Verify the existing always-on-top toggle contract**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageAlwaysOnTopShortcutSynchronizesEditingOverlayLevel \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageEditingOverlayInheritsCurrentWindowLevelWhenShown \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageResetAndAlwaysOnTopShortcutsRequireExactModifiers
```

Expected: PASS. The first `Command-T` changes floating to normal, the second changes normal to floating, the overlay stays synchronized, and invalid modifier combinations do nothing. No production change is needed for behavior that already passes.

- [ ] **Step 3: Run all focused interaction regressions together**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testSelectedMagnifierUsesMoveAndDirectionalResizeCursors \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testSelectedMagnifierCanResizeMoveDeleteAndRestyle \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testMagnifierKeepsCrosshairCursorInsideSelection \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageShiftReleaseTogglesToolbarOnAndOff \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageShiftShortcutCancelsWhenCombinedWithOtherInput \
  -only-testing:xxsnapTests/SelectionToolbarStateTests/testPinnedImageAlwaysOnTopShortcutSynchronizesEditingOverlayLevel
```

Expected: PASS.

- [ ] **Step 4: Run the full macOS test target**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test
```

Expected: `** TEST SUCCEEDED **` with no newly introduced failures.

- [ ] **Step 5: Build the exact debug app used for manual validation**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Perform the manual smoke check**

Use the built debug app and verify:

1. Select a magnifier; hover all four corners, all four sides, the frame interior, and empty canvas.
2. Confirm the cursor changes without visible flicker, redraw, or lag as annotation count increases.
3. On a pinned image, press and release standalone `Shift` at least four times; the toolbar alternates each time.
4. Confirm `Shift` plus another modifier, mouse input, or drag does not toggle the toolbar.
5. Press `Command-T` repeatedly with the toolbar hidden and visible; the pinned image and editing overlay remain on the same window level.

- [ ] **Step 7: Final scope and performance audit**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Inspect the task-specific hunks and confirm:

- no renderer, export, annotation model, resource, or project-file change was added for this task;
- magnifier hover checks only the selected annotation and existing handle geometry;
- no cursor is constructed inside `cursorStyle(at:)`;
- no global monitor, timer, observer, polling loop, tracking area, or continuous invalidation was added;
- unrelated pre-existing work remains present and unchanged.
