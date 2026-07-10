# Pinned Image Three-Stage Escape and Restore Design

## Goal

Make Escape move a pinned image through editing states without prematurely destroying it, and allow the most recently hidden pinned image to be restored with Command-1 when no capture overlay is active.

## Current Problem

The pinned-image editor currently routes a base-state Escape directly to `closeCurrent`. That destroys the pinned window on the second Escape after leaving a tool. The non-editor pinned window also treats Escape, Delete, and Forward Delete identically by closing the window. Once closed, `CaptureCoordinator` removes the controller, so there is no object or state that Command-1 can restore.

Command-1 already means “pin the current selection” while the capture overlay is active. The restore shortcut must not replace or intercept that existing behavior.

## Required Behavior

### Escape state progression

When a pinned-image editing toolbar is visible:

1. If a sustained annotation tool or transient draft/editor is active, the first Escape cancels the active tool or draft and returns the editor to its neutral state. The pinned image and editing toolbar stay visible.
2. From the neutral editor state, the next Escape performs the same completion path as the “完成编辑” button. Valid annotations are baked into the pinned image, transient empty drafts are discarded, and the editing toolbar disappears. The pinned image stays visible.
3. With no editing toolbar visible, the next Escape hides the pinned image window without closing or destroying its controller. The hidden controller becomes the most recently hidden pinned image.

If the editor is already neutral when Escape is first pressed, it starts at step 2. If the toolbar is already hidden, Escape starts at step 3.

Activating another tool after step 1 returns the state to step 1 for the next Escape. No timing window is involved.

### Restore shortcut

- When no capture overlay is active, Command-1 restores the most recently hidden pinned image.
- Restore reuses the original controller and window, preserving image content, annotations already baked into the image, position, size, opacity, and window level.
- When a capture overlay is active, Command-1 keeps its existing meaning: pin the current capture selection.
- If several pinned images have been hidden, Command-1 restores only the one hidden most recently.
- If no hidden pinned image exists, Command-1 does nothing.

### True close behavior

Escape hiding is distinct from closing:

- Delete, Forward Delete, Command-W, the context-menu “关闭” action, and “关闭全部贴图” continue to close and destroy pinned windows.
- Closing a hidden cached pinned image removes it from the recent-hidden slot, so Command-1 cannot restore a destroyed window.
- Application termination continues to destroy all in-memory pinned-image state.

## Architecture

### Selection overlay

`SelectionOverlayView` keeps the existing state-driven first Escape consumer for active tools and drafts.

For a pinned-image editor, `SelectionOverlayWindow` changes its base Escape action from `.closeCurrent` to the same `.finishEditing` completion path used by the toolbar button. Normal capture overlays keep their existing base Escape cancellation behavior.

### Pinned image controller

`PinnedImageWindowController` adds an explicit hide action for Escape in its non-editor content view. Hiding calls `orderOut` and notifies its owner without invoking `windowWillClose`. `PinnedImageWindowPresenting` exposes hide and close lifecycle callbacks so coordinator behavior remains testable through the existing fake factory.

True close paths remain unchanged. The controller exposes only the lifecycle callbacks needed by its owner: hidden and closed.

### Capture coordinator

`CaptureCoordinator` remains the owner of live pinned controllers and tracks one strong reference to the most recently hidden controller. It provides:

- whether a capture overlay/session is active;
- an action that restores the recent hidden pin only when capture is inactive;
- cleanup when the cached controller is truly closed.

Restoring calls the controller’s existing `show()` path and clears the recent-hidden slot. Hiding the same or another pin updates the slot to the most recently hidden controller.

### Application hotkey routing

`AppDelegate` registers Command-1 as a second Carbon application hotkey while no capture overlay is active. `CaptureCoordinator` reports capture-overlay presentation and completion through lifecycle callbacks. `AppDelegate` unregisters the restore hotkey before the overlay accepts input and registers it again after the capture session ends.

Dynamic registration is required because a registered Carbon hotkey consumes the key event globally. Merely ignoring the handler during capture would prevent the overlay from receiving its existing Command-1 “pin current selection” shortcut. The implementation must not add input-monitoring permission requirements, timers, polling, image copying, or controller recreation.

## State Flow

```text
active editor tool
    -- Escape --> neutral editor, toolbar visible
    -- Escape --> editing completed, toolbar hidden, pin visible
    -- Escape --> pin hidden and cached
    -- Command-1 with no capture --> same pin visible again
```

## Performance

- Escape handling remains event-driven.
- Hidden pinned windows retain their existing controller and image; no bitmap duplication or rerender occurs during hide or restore.
- Annotation baking occurs only through the existing finish-editing path.
- Only one recent-hidden controller reference is tracked, so restore bookkeeping is constant time and constant additional state.

## Tests

Focused tests will verify:

1. Every sustained pinned-image tool needs three Escape presses to progress through tool cancellation, editing completion, and hiding.
2. A neutral pinned editor needs two Escape presses: finish editing, then hide.
3. A pin with its toolbar already hidden needs one Escape to hide.
4. Finish-editing through Escape bakes valid annotations before hiding the toolbar.
5. Hidden pins stay alive and can be restored with Command-1 while no capture is active.
6. The most recently hidden pin wins when multiple pins are hidden.
7. Command-1 still pins the current selection during capture and does not restore cached content.
8. Delete, Forward Delete, Command-W, and context-menu close still destroy the pin and invalidate any recent-hidden reference.
9. Existing Shift toolbar toggling, copy/save shortcuts, and normal-capture two-stage Escape behavior remain unchanged.

## Acceptance Criteria

- The observed pinned-image Escape sequence exactly matches the three stages above.
- Hidden pinned images are not counted as closed and keep their visual/window state.
- Command-1 restores the most recently hidden pin only outside capture.
- Existing capture Command-1 behavior is preserved.
- No timer, polling loop, image copy, or window reconstruction is introduced.
