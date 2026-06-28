# Window Region Selection and Slower Wheel Zoom Design

## Context

Snipory v2 mac already supports hover-to-select regions before the screenshot selection is locked. The current implementation uses macOS window candidates plus synthetic menu bar and Dock candidates. This is reliable for whole windows and system UI strips, but it does not understand smaller visual structures inside a window.

The same overlay also supports mouse-wheel resizing after a selection is locked. The current resize curve still feels too fast for precise adjustment, so this design slows the wheel response while preserving the ability to expand to the full current screen.

Pixel-based paragraph and small-control recognition was explored and then reverted because it was not reliable enough and made the initial hover path feel slow. The active design intentionally returns to window/system-bar recognition only.

## User Goal

Users want the initial selection overlay to stay fast and predictable:

- after screenshot capture starts, moving the pointer should continuously update to the current selectable window or system bar region until the user confirms it;
- top and bottom system areas, including the menu bar and Dock/status bar area, should remain selectable;
- when the user clicks the left mouse button, the current hover region should become the locked screenshot selection and hover recognition should stop;
- after the selection is locked, pointer movement with no active annotation tool should only update color sampling inside the locked selection;
- the hover path must not scan screenshot pixels for paragraphs, chat bubbles, subtle cards, or small controls.

Users also want wheel-based resizing to be gentler. Each wheel step should produce a smaller visual change, while repeated scrolling should still reach the screen frame maximum.

## Recommended Approach

Keep the initial hover path on the existing macOS window candidate model. The overlay should query already captured window candidates and synthetic system UI candidates, then choose the frontmost selectable region under the pointer.

No OCR, accessibility lookup, or screenshot-pixel analysis should run during live hover. This returns the interaction to the earlier fast behavior.

## Candidate Sources

Region candidates should be resolved in this order:

1. System UI candidates such as menu bar and Dock.
2. Existing whole-window candidates.

This preserves current system UI behavior and keeps ordinary app windows as the fallback target.

## Live Hover and Lock-In

Window recognition runs only during the initial selecting state, before the user has clicked the left mouse button.

While the user moves the pointer, the overlay should immediately resolve the best window or system UI region under the pointer and animate the hover rectangle toward it.

When the user clicks the left mouse button:

- if there is a current hover target under the pointer, lock that target as the screenshot selection;
- clear hover state;
- enter the normal annotation/color-sampling state;
- do not keep updating hover-recognized regions after the click.

After lock-in, if no annotation tool is active, moving the pointer should only drive the color sampler within the locked selection. Window recognition must not compete with color sampling, annotation hit testing, or selection resizing after this point.

## Wheel Zoom Tuning

Wheel zoom remains available for the locked selection across tools, with the same existing ignore rules for toolbar, panels, active drags, drawing, resizing, rotating, and Mosaic value editing.

The resize curve should be slowed from the current feel:

- reduce the exponential scale base from the current fast value to a gentler value around `1.02`;
- clamp per-event scroll delta tightly enough that a single wheel event cannot jump the selection too far;
- animate the visible selection toward the new target rect instead of jumping instantly;
- keep the minimum selection size at `64 x 64` points;
- keep the maximum as the full `NSScreen.frame` of the current screen, including menu bar and Dock;
- preserve pointer anchoring when the pointer is inside the selection and center anchoring when it is outside controls.

Repeated wheel scrolling must still be able to expand a selection to the full screen frame.

When the selection rect changes by wheel zoom, existing annotations should retain their current overlay/screen positions. This includes ordinary rect annotations, arrow lines, brush paths, marker lines, and mosaic strokes. The selection-local coordinates can change internally, but the user should not see drawn annotations drift while the selection expands or shrinks.

## Architecture

Keep implementation mac-overlay scoped.

- `SelectionOverlayWindow.swift` continues to own pointer movement, hover state, animation, and selection lock-in.
- `WindowSelectionState.swift` continues to own macOS window and system UI candidates.
- Do not add or keep live paragraph, chat bubble, small rectangle, or subtle-control pixel scanning in the hover path.
- Do not change copy, save, pin, annotation rendering, or eyedropper behavior.

## Testing

Add focused mac tests for:

- wheel zoom changes less per moderate wheel delta than the current fast curve;
- repeated wheel zoom can still reach full screen bounds;
- wheel zoom animates toward its target rather than snapping immediately;
- wheel zoom preserves visible annotation positions, including mosaic strokes;
- initial hover immediately tracks an ordinary window region under the pointer;
- left mouse down locks the current window/system region and stops further hover recognition;
- repeated initial hover mouse moves stay responsive without screenshot-pixel scanning;
- system menu bar and Dock candidates still win in their regions;
- fallback to whole-window selection works for ordinary app content.

Run the mac XCTest target when possible:

```bash
xcodebuild -project platforms/mac/snipory.xcodeproj -scheme snipory -configuration Debug -derivedDataPath build/xcode-derived test
```

If the full XCTest target is blocked by signing, permissions, or environment-sensitive screen capture tests, run the nearest focused tests and the mac app build, then report the exact blocker.

## Out of Scope

- OCR text recognition or selecting by actual text content.
- Accessibility API element selection.
- Paragraph, chat bubble, subtle card, or small-control pixel recognition.
- Cross-platform inner-region detection in the shared core.
- Changing locked-selection export, copy, save, pin, or annotation undo/redo behavior.
