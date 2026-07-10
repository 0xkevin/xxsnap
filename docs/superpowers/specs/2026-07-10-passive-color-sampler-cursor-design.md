# Passive Color Sampler Cursor Design

## Goal

Show the move-cross cursor throughout the selected area whenever passive color sampling is visible and no annotation tool is active, including full-screen selections.

## Root Cause

`SelectionOverlayView.cursorStyle(at:)` currently returns the move cursor only when `shouldStartSelectionMove(at:)` is true. That helper intentionally returns false when the selection fills the screen because a full-screen selection cannot be moved. The cursor then falls through to the generic idle style, which returns the ordinary crosshair inside the selection.

The passive color-sampling cursor is a visual state and must not depend on whether the selection geometry can actually move.

## Required Behavior

- When passive color sampling is visible, no annotation tool is active, and the pointer is inside the locked selection, use the background-aware move cursor (`move` or `moveLight`).
- Apply this rule to both normal and full-screen locked selections.
- Do not make a full-screen selection draggable; only its passive sampling cursor changes.
- Selection resize handles keep their directional resize cursors.
- Toolbar, options panel, measurement controls, and other non-canvas controls keep the arrow cursor.
- Active annotation tools keep their existing drawing cursors.
- Explicit eyedropper mode keeps its eyedropper cursor.
- Outside the selection, existing cursor behavior remains unchanged.

## Architecture

Add a focused passive-sampling cursor condition in `SelectionOverlayView.cursorStyle(at:)` after toolbar/panel, annotation-control, and selection-resize precedence has been resolved, but before the generic idle cursor fallback.

The condition must use the same state that proves the passive sampler is actually visible: `sampledColor` and `sampledPointerPoint` are non-nil, passive sampling is enabled, no annotations exist, no sustained annotation tool is active, and the pointer is inside the locked selection.

Do not change `SelectionToolbarState.shouldStartSelectionMove` or the selection movement handlers. This keeps cursor appearance separate from movement eligibility and avoids geometry regressions.

## Performance

The cursor check reads existing in-memory state during mouse movement. It adds no timer, polling, bitmap sampling, rendering pass, or allocation.

## Tests

Focused tests will verify:

1. A normal locked selection with visible passive sampling uses `move` on a light background.
2. A full-screen locked selection with visible passive sampling also uses `move`.
3. A dark sampled background uses `moveLight`.
4. Selection borders still use resize cursors.
5. Toolbar points still use `arrow`.
6. Rectangle, brush, eyedropper, text, number, magnifier, mosaic, marker, and eraser cursor tests remain unchanged.

## Acceptance Criteria

- The reported initial-capture state displays the move-cross cursor instead of the ordinary crosshair while passive color sampling is visible.
- Full-screen selection movement behavior is unchanged.
- Existing tool, toolbar, and resize cursors do not regress.
