# Smart Region Detection and Slower Wheel Zoom Design

## Context

Snipory v2 mac already supports hover-to-select regions before the screenshot selection is locked. The current implementation uses macOS window candidates plus synthetic menu bar and Dock candidates. This is reliable for whole windows and system UI strips, but it does not understand smaller visual structures inside a window.

The same overlay also supports mouse-wheel resizing after a selection is locked. The current resize curve still feels too fast for precise adjustment, so this design slows the wheel response while preserving the ability to expand to the full current screen.

## User Goal

Users want the initial selection overlay to feel more intelligent:

- when the pointer is over a paragraph or a block of text, the hover rectangle should prefer that paragraph instead of the entire window;
- when the pointer is over a small regular rectangular UI element, such as a button, input box, checkbox-like square, or compact card, the hover rectangle should be able to lock onto that element;
- when no confident inner region is found, the existing window, menu bar, and Dock behavior should continue to work.

Users also want wheel-based resizing to be gentler. Each wheel step should produce a smaller visual change, while repeated scrolling should still reach the screen frame maximum.

## Recommended Approach

Add a lightweight image-based candidate layer to the existing mac overlay. This layer analyzes pixels from the frozen screenshot image near the pointer and proposes local regions. It does not use OCR or accessibility APIs for this iteration.

This approach keeps the behavior fast, offline, and deterministic. It also avoids adding async OCR latency to pointer movement. The detector only needs to find useful visual bounds, not understand the text content.

## Candidate Sources

Region candidates should be resolved in this order:

1. System UI candidates such as menu bar and Dock.
2. Smart image candidates inside ordinary window content.
3. Existing whole-window candidates.

This preserves current system UI behavior while allowing paragraphs and small UI boxes to beat whole-window selection inside app windows.

## Paragraph Detection

The smart detector should inspect a bounded local area around the pointer, not the full desktop on every mouse move.

Paragraph detection should:

- sample the frozen screenshot pixels around the pointer;
- classify high-contrast foreground pixels against nearby background;
- group nearby foreground pixels into line-like components;
- merge adjacent text lines when they have similar horizontal extents and modest vertical gaps;
- add a small padding around the merged result so the hover rectangle feels natural;
- reject candidates that are too tiny, too sparse, or too close to the full window size.

The result does not need semantic OCR. A paragraph candidate is a visual text block candidate.

## Small Rectangle Detection

Small regular rectangle detection should identify compact UI elements that have visible straight edges or a consistent filled rectangular area.

The detector should:

- scan a local area around the pointer for horizontal and vertical edge runs;
- prefer closed or nearly closed rectangular outlines;
- allow small gaps caused by antialiasing, shadows, rounded corners, or focus rings;
- include filled rectangular regions when their boundary contrast is clear;
- reject oversized regions that are better handled by window selection;
- reject extremely thin separators unless they form a usable box.

This should cover common UI boxes such as small buttons, input fields, checkboxes, table cells, and compact cards.

## Stability and Hysteresis

Smart hover selection should not flicker while the pointer moves across a paragraph or control.

The overlay should keep the current hover animation path, but add candidate stability rules:

- prefer the previous smart candidate while the pointer remains inside it and the new candidate is similar;
- switch immediately only when the new candidate is clearly smaller, closer to the pointer, or higher confidence;
- fall back to the window candidate when no smart candidate is found;
- keep all candidate rects clipped to the overlay bounds.

## Wheel Zoom Tuning

Wheel zoom remains available for the locked selection across tools, with the same existing ignore rules for toolbar, panels, active drags, drawing, resizing, rotating, and Mosaic value editing.

The resize curve should be slowed from the current feel:

- reduce the exponential scale base from the current fast value to a gentler value around `1.02`;
- clamp per-event scroll delta tightly enough that a single wheel event cannot jump the selection too far;
- keep the minimum selection size at `64 x 64` points;
- keep the maximum as the full `NSScreen.frame` of the current screen, including menu bar and Dock;
- preserve pointer anchoring when the pointer is inside the selection and center anchoring when it is outside controls.

Repeated wheel scrolling must still be able to expand a selection to the full screen frame.

## Architecture

Keep implementation mac-overlay scoped.

- `SelectionOverlayWindow.swift` continues to own pointer movement, hover state, animation, and selection lock-in.
- `WindowSelectionState.swift` continues to own macOS window and system UI candidates.
- Add a small, pure helper for smart region detection so paragraph and rectangle detection can be tested without opening the overlay UI.
- Reuse the frozen screenshot bitmap already used by the overlay as the image source.
- Do not change copy, save, pin, annotation rendering, or eyedropper behavior.

The helper should return a candidate rect plus a confidence or kind value, allowing `SelectionOverlayWindow` to decide priority against existing window candidates.

## Testing

Add focused mac tests for:

- wheel zoom changes less per moderate wheel delta than the current fast curve;
- repeated wheel zoom can still reach full screen bounds;
- paragraph-like synthetic pixels merge into one padded paragraph candidate;
- separated text blocks do not merge across large gaps;
- a small rectangular outline under the pointer is detected as a compact region;
- thin separators or noisy sparse pixels are rejected;
- smart paragraph and rectangle candidates are preferred over ordinary whole-window candidates;
- system menu bar and Dock candidates still win in their regions;
- fallback to whole-window selection still works when no smart candidate is found.

Run the mac XCTest target when possible:

```bash
xcodebuild -project platforms/mac/snipory.xcodeproj -scheme snipory -configuration Debug -derivedDataPath build/xcode-derived test
```

If the full XCTest target is blocked by signing, permissions, or environment-sensitive screen capture tests, run the nearest focused tests and the mac app build, then report the exact blocker.

## Out of Scope

- OCR text recognition or selecting by actual text content.
- Accessibility API element selection.
- Cross-platform smart detection in the shared core.
- Changing locked-selection export, copy, save, pin, or annotation undo/redo behavior.
