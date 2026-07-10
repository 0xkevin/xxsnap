# Magnifier And Pinned-Image Toggle Interaction Design

## Goal

Refine two existing macOS interactions without changing annotation behavior, pinned-image rendering, or hot-path performance:

- make an existing magnifier annotation expose move and directional resize cursors;
- make the pinned-image toolbar `Shift` shortcut and always-on-top shortcut behave as repeatable toggles.

## Scope

### Magnifier cursor feedback

When the magnifier tool is active and an editable magnifier is selected, cursor precedence is:

1. A corner resize handle shows the matching diagonal resize cursor.
2. A side resize handle shows the matching horizontal or vertical resize cursor.
3. Any remaining point inside the magnifier's bounding frame shows the move cursor.
4. Toolbar and panel points show the arrow cursor.
5. Points that do not hit the selected magnifier continue to show the magnifier creation crosshair.

The existing background-aware light and dark cursor variants remain in use. Geometry, resize behavior, selection rendering, and magnifier sampling are unchanged.

### Pinned-image toolbar toggle

A standalone `Shift` press and release toggles the pinned-image editing toolbar:

- hidden becomes visible;
- visible becomes hidden;
- repeated standalone presses continue alternating the state.

The existing safety rules remain unchanged: combining `Shift` with another modifier, pressing another key, clicking, dragging, or otherwise starting another interaction cancels the pending toggle.

### Always-on-top toggle

The existing `Command-T` shortcut remains the always-on-top shortcut. Each valid press toggles between floating and normal window levels. If the editing overlay is visible, its level remains synchronized with the pinned-image window. The context-menu checked state continues reflecting the current level.

## Implementation Approach

Use the existing generic annotation hit-testing and cursor mapping before the magnifier creation-mode fallback. This removes the current early crosshair return that bypasses selected-annotation handles and body hits, while preserving the shared resize and background-aware cursor behavior.

For the `Shift` shortcut, allow a standalone press to become a candidate regardless of the current toolbar visibility. On release, invoke one shared toolbar toggle path instead of a show-only path. Menu activation and keyboard activation use that same toggle operation.

Keep `Command-T` on the current window-command dispatch path. Add regression coverage for repeated toggling rather than introducing a second command or event monitor.

## Performance Constraints

- Do not add tracking areas, global event monitors, timers, observers, or polling.
- Do not allocate cursor images or recalculate annotation rendering during mouse movement.
- Reuse the existing constant-time selected-annotation handle/body hit tests and cached cursor instances.
- Do not change magnifier rendering, screenshot sampling, annotation export, or pinned-image image composition.
- Cursor evaluation must remain a small set of geometry checks already used by other editable annotations.
- Shortcut handling remains event-driven and performs no work while idle.

## Testing

Add focused XCTest regression coverage before production changes:

- selected magnifier corners map to the four matching diagonal resize cursors;
- selected magnifier sides map to horizontal or vertical resize cursors;
- the selected magnifier frame interior maps to the move cursor;
- points away from the selected magnifier retain the creation crosshair;
- two standalone `Shift` press-release sequences show and then hide the editing toolbar;
- cancelled `Shift` sequences still do not toggle the toolbar;
- repeated `Command-T` presses alternate normal and floating levels and keep the editing overlay synchronized;
- invalid modifier combinations remain ignored.

Run the focused tests first, then the complete macOS test target. Perform a manual smoke check of magnifier hover feedback and repeated pinned-image toggles in the built debug app.

## Acceptance Criteria

- Magnifier edges, corners, and interior show the agreed directional resize and move cursors.
- Repeated standalone `Shift` presses alternate the pinned-image editing toolbar between visible and hidden.
- Repeated `Command-T` presses alternate always-on-top state and synchronize any visible editing overlay.
- Existing cancellation, selection, drawing, resizing, rendering, export, and pinned-image behaviors remain unchanged.
- No new continuous work, rendering pass, event monitor, or cursor allocation is added to interaction hot paths.
