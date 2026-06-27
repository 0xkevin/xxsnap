---
title: Mosaic Tool Requirements
date: 2026-06-23
topic: mosaic-tool
type: requirements
---

# Mosaic Tool Requirements

## Summary

The existing Mosaic button in the Snipory v2 mac capture toolbar becomes a usable redaction tool. The first version supports both brush-like drag redaction and editable rectangular redaction, with Gaussian blur and pixel mosaic modes available from the secondary toolbar.

---

## Problem Frame

Snipory already supports several annotation tools for pointing, drawing, and highlighting. Redaction is a different job: users need to hide sensitive content quickly before copying or saving a screenshot.

The current product surface already exposes a Mosaic button, but it still behaves as unfinished functionality. This effort should complete that one tool without pulling in other unfinished tools.

This iteration intentionally advances one unfinished annotation tool at a time. Mosaic is the explicitly selected tool for this round, and the surrounding unfinished tools stay parked so the iteration does not expand into a multi-tool delivery.

---

## Key Decisions

- **One tool entry, two redaction types.** The main toolbar keeps a single Mosaic entry, while the secondary toolbar lets users choose Gaussian blur or pixel mosaic.
- **Two drawing behaviors in v1.** Brush-like sliding covers quick freeform redaction, while rectangular redaction covers precise blocks such as account names, tokens, avatars, and form values.
- **Separate values per type.** Gaussian blur and pixel mosaic each support values from `8` to `20`, default to `8`, and can be adjusted independently.
- **Fast path first.** Activating Mosaic immediately puts the user in a ready-to-drag Sliding state, so the common workflow is click Mosaic, drag over sensitive content, then copy or save.
- **Icon state previews intensity.** Gaussian blur uses a circular preview icon, pixel mosaic uses five small squares in a cross shape, and each icon renders a live preview of the current `8...20` value.
- **Single-tool scope.** This work finishes Mosaic only; Text, Number, Magnifier, Eraser, Pin, Scroll Capture, and other unfinished tools stay unchanged unless a required Mosaic integration exposes them.
- **One tool per iteration.** Choosing Mosaic for this round sets sequencing, not a permanent ranking of tool importance; the point is to finish one annotation tool cleanly before starting the next unfinished one.

---

## Requirements

**Tool Activation**

- R1. Clicking the Mosaic toolbar button activates Mosaic mode instead of showing an unfinished-feature message.
- R2. Mosaic mode is mutually exclusive with shape, arrow line, brush, and marker modes.
- R3. The Mosaic toolbar button shows selected state while Mosaic mode is active.
- R4. Switching away from Mosaic mode clears any in-progress Mosaic draft without changing committed annotations.
- R5. The tooltip remains `马赛克`.

**Secondary Toolbar**

- R6. Mosaic mode shows a secondary toolbar for drawing behavior, redaction type, and value controls.
- R7. The toolbar exposes Gaussian blur and pixel mosaic as two selectable redaction types.
- R8. Gaussian blur and pixel mosaic each have a numeric value range of `8...20`.
- R9. Both redaction types default to value `8`.
- R10. Each redaction type remembers its own current value when the user switches between Gaussian blur and pixel mosaic.
- R11. Gaussian blur uses a circular mode icon that previews the current Gaussian blur value.
- R12. Pixel mosaic uses an icon made from five small squares arranged as a cross, and the icon previews the current pixel mosaic value.
- R13. When the user changes a redaction type's value, that type's icon updates immediately to show the corresponding `8...20` strength.
- R14. The toolbar exposes Sliding and Rectangle as two selectable drawing behaviors that are independent from Gaussian blur and pixel mosaic.
- R15. Sliding is the default drawing behavior when Mosaic mode is activated, and the medium dot value `30` is selected by default.
- R16. Sliding behavior uses three mutually exclusive dot-size controls: small dot value `15`, medium dot value `30`, and large dot value `40`.
- R17. Rectangle behavior uses a filled-square control matching the visual intent of the Bootstrap `square-fill` icon.
- R18. Sliding and Rectangle are mutually exclusive drawing behaviors; the user can select either a dot-size behavior or the rectangle behavior, never both at the same time.
- R19. Switching drawing behavior does not change the selected redaction type or that type's remembered value.
- R20. Mosaic mode does not show stroke style, fill, arrow type, shape type, marker-only, or brush-only controls.
- R21. The user can begin Sliding redaction immediately after activating Mosaic without first changing any secondary toolbar control.

**Brush-Like Redaction**

- R22. Pressing and dragging inside the selected screenshot region creates a redaction stroke following the pointer path when Sliding behavior is selected.
- R23. Brush-like redaction uses the currently selected redaction type, that type's current value, and the selected dot size.
- R24. The brush-like cursor is a centered gray dot using color `#D3D3D3`.
- R25. The brush-like cursor size always matches the selected dot-size control and updates immediately when the user chooses a different dot size.
- R26. A committed redaction stroke can be selected, moved, deleted, and included in undo and redo.
- R27. The first version does not need point-by-point path reshaping for committed redaction strokes.

**Rectangular Redaction**

- R28. Selecting Rectangle behavior changes the cursor to a crosshair framing cursor for rectangular selection.
- R29. Dragging inside the selected screenshot region creates a redaction rectangle from press point to release point when Rectangle behavior is selected.
- R30. A committed redaction rectangle can be selected, moved, resized, deleted, and included in undo and redo.
- R31. A selected redaction rectangle can switch between Gaussian blur and pixel mosaic without being redrawn.
- R32. A selected redaction rectangle can update its value within `8...20` without being redrawn.
- R33. Redaction rectangles should support precise blocking of text, avatars, tokens, and other bounded sensitive regions.

**Selection And Editing**

- R34. When no Mosaic annotation is selected, the secondary toolbar controls the defaults for the next redaction.
- R35. When a single redaction rectangle is selected, redaction type and value controls update that rectangle, while drawing behavior controls set the default for the next redaction.
- R36. When a single redaction stroke is selected, redaction type, value, and dot-size controls update that stroke.
- R37. The first version does not require multi-selection for Mosaic annotations.
- R38. Each committed type, value, or dot-size edit is included in undo and redo.

**Draft Bounds And Cancellation**

- R39. Mosaic redaction can extend beyond the selected screenshot bounds while the user is dragging.
- R40. Overlay preview clips any out-of-bounds redaction area to the selected screenshot bounds.
- R41. Releasing outside the selected screenshot bounds commits only the in-bounds redaction result.
- R42. Pressing `Esc` exits the entire capture action and returns to the normal desktop, regardless of the active Mosaic drawing behavior or tool state.

**Accessibility**

- R43. Every Mosaic icon-only control has an accessible name, including Gaussian blur, pixel mosaic, small dot, medium dot, large dot, and rectangle redaction.
- R44. Drawing behavior, redaction type, value, and dot-size controls expose their selected or current value state.
- R45. Redaction type, value, drawing behavior, and dot-size controls can be reached through the existing toolbar focus model or equivalent keyboard access.
- R46. Selected Mosaic annotations can be deleted with the existing keyboard delete behavior.
- R47. Mosaic undo and redo follow the existing `Command + Z` and `Command + Shift + Z` behavior.
- R48. Mosaic toolbar focus and selected-state visuals follow the existing annotation toolbar patterns.

**Rendering And Export**

- R49. Overlay preview and final copied or saved output use the same redaction type and value.
- R50. Redaction output is clipped to the selected screenshot image bounds during copy and save.
- R51. Gaussian blur visually obscures the underlying screenshot content without replacing it with a flat color.
- R52. Pixel mosaic visually obscures the underlying screenshot content as blocky mosaic cells rather than a translucent overlay.
- R53. Rendering must preserve the original exported image dimensions.

**Tool Isolation**

- R54. This work must not implement or redesign Text, Number, Magnifier, Eraser, Pin, Scroll Capture, or other unfinished tools.
- R55. Existing shape, arrow line, brush, marker, copy, save, cancel, undo, redo, and selection workflows should keep their current behavior unless a Mosaic interaction requires shared-state consistency.
- R56. The user guide should move Mosaic from the unfinished-tools list into the supported-tools list when the tool ships.

---

## Key Flows

- F1. Brush-like Mosaic redaction
  - **Trigger:** The user activates Mosaic mode and keeps or chooses Sliding behavior.
  - **Steps:** The user chooses Gaussian blur or pixel mosaic, sets that type's value, chooses a dot size, presses inside the selected screenshot region, drags over sensitive content, and releases.
  - **Outcome:** A committed redaction stroke appears, can be selected or deleted, and appears in copied or saved output.
  - **Covered by:** R1, R6, R7, R8, R14, R15, R16, R21, R22, R23, R24, R25, R36, R39, R40, R41, R49.

- F2. Fast Mosaic redaction
  - **Trigger:** The user activates Mosaic mode and wants to redact immediately.
  - **Steps:** The user clicks Mosaic, drags over sensitive content with the default Sliding medium dot, then copies or saves.
  - **Outcome:** The user can complete a common redaction without first changing secondary toolbar controls.
  - **Covered by:** R1, R7, R8, R9, R15, R16, R21, R22, R23, R49.

- F3. Rectangular Mosaic redaction
  - **Trigger:** The user activates Mosaic mode and chooses Rectangle behavior from the secondary toolbar.
  - **Steps:** The user drags a rectangle over a bounded sensitive region, then adjusts type or value from the secondary toolbar.
  - **Outcome:** A committed redaction rectangle updates in place and can be moved, resized, deleted, copied, or saved.
  - **Covered by:** R14, R17, R18, R28, R29, R30, R31, R32, R33, R35, R39, R40, R41, R49.

- F4. Switching redaction types
  - **Trigger:** The user switches between Gaussian blur and pixel mosaic in the secondary toolbar.
  - **Steps:** The toolbar updates the selected mode icon and restores that type's current value.
  - **Outcome:** New redactions use the selected type and value; selected existing redactions update according to the single-selection rules.
  - **Covered by:** R7, R10, R11, R12, R13, R34, R35, R36, R38.

---

## Acceptance Examples

- AE1. **Covers R1, R5.** Given the capture overlay is locked, when the user clicks the Mosaic button, then Mosaic mode activates and no `马赛克功能开发中。` message appears.
- AE2. **Covers R8, R9, R10.** Given Mosaic mode is active, when the user changes Gaussian blur to `14`, switches to pixel mosaic, sets it to `20`, and switches back, then Gaussian blur still shows `14`.
- AE3. **Covers R11, R12, R13.** Given either redaction type is selected, when its value changes from `8` to `20`, then its icon immediately previews the stronger blur or mosaic effect.
- AE4. **Covers R14, R15, R16, R18, R19.** Given Mosaic mode is active, when the user switches between Sliding and Rectangle, then only one drawing behavior is selected and the selected redaction type with its remembered value stays unchanged.
- AE5. **Covers R1, R9, R15, R16, R21.** Given the capture overlay is locked, when the user clicks Mosaic and immediately drags over sensitive content, then Sliding redaction starts with value `8` and medium dot value `30` without any required toolbar adjustment.
- AE6. **Covers R16, R22, R23, R24, R25, R36.** Given pixel mosaic value `8` and Sliding are selected, when the user chooses medium dot value `30` and drags across a line of sensitive text, then the gray cursor dot and committed stroke use the medium dot size.
- AE7. **Covers R17, R28, R29, R32, R35.** Given Rectangle behavior is selected, when the user drags a redaction rectangle and changes the value, then the cursor uses the crosshair framing shape and the rectangle keeps its position intent while updating size and intensity.
- AE8. **Covers R34, R35, R36, R38.** Given no Mosaic annotation is selected, a selected rectangle, or a selected stroke, when the user changes type, value, or dot size, then the change applies according to the current selection state and can be undone.
- AE9. **Covers R39, R40, R41.** Given the user starts a Mosaic redaction inside the selected screenshot and drags outside the screenshot bounds, when the user releases outside the bounds, then only the in-bounds clipped redaction result is committed.
- AE10. **Covers R42.** Given any Mosaic drawing behavior or draft is active, when the user presses `Esc`, then the entire capture action exits and the normal desktop returns.
- AE11. **Covers R43, R44, R45, R46, R47, R48.** Given Mosaic mode is active, when the user navigates the secondary toolbar and selected annotations with keyboard or assistive technology, then icon-only controls expose names, values, selection state, delete, undo, and redo according to existing toolbar patterns.
- AE12. **Covers R49, R50, R53.** Given a screenshot contains committed redactions, when the user copies or saves, then the exported image dimensions match the selected screenshot and include the redactions clipped to that image.
- AE13. **Covers R54, R55.** Given Mosaic ships, when the user clicks Text, Number, Magnifier, Eraser, Pin, or another unfinished tool, then this Mosaic work has not silently changed those tools' scope or behavior.

---

## Scope Boundaries

- In scope: activating the existing Mosaic toolbar button, Mosaic-specific secondary toolbar controls, brush-like redaction, rectangular redaction, preview rendering, export rendering, selection, movement, resizing where applicable, deletion, and undo or redo integration.
- Deferred for later: automatic privacy detection, OCR-driven redaction suggestions, batch redaction, per-point stroke reshaping, redaction history panels, and advanced presets beyond the `8...20` value range.
- Out of scope: implementing Text, Number, Magnifier, Eraser, Pin, Scroll Capture, or any other unfinished tool as part of this effort.

---

## Dependencies And Assumptions

- The work is scoped to `platforms/mac/` for this iteration.
- Existing annotation workflows provide the product pattern for activation, selected state, secondary toolbar behavior, undo and redo, copy, save, and deletion.
- The exact visual interpolation between values `8` and `20` can be decided during planning as long as the icon and background visibly change with the value.

---

## Sources

- `docs/annotation-tools-user-guide.md:7` documents the currently supported annotation tools and still lists Mosaic as unfinished.
- `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift:2290` maps the Mosaic placeholder label to `马赛克`.
- `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift:2318` shows unfinished tool buttons currently display a transient `功能开发中` message.
- `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift:5033` shows Mosaic already exists in the main toolbar button list.
- `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift:5080` shows Mosaic already has a toolbar icon resource mapping.
