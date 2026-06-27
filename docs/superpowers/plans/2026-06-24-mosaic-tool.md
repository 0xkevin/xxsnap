---
title: Mosaic Tool Implementation Plan
type: feat
date: 2026-06-24
origin: docs/brainstorms/2026-06-23-mosaic-tool-requirements.md
---

# Mosaic Tool Implementation Plan

## Summary

This plan turns the existing mac capture-toolbar `马赛克` button into a shippable annotation tool in `snipory-v2`. The implementation stays inside the current mac overlay architecture, adds two concrete Mosaic annotation kinds for sliding and rectangle redaction, and uses one shared raster redaction pipeline so overlay preview and exported output stay visually aligned.

---

## Problem Frame

`snipory-v2` already has a visible Mosaic entry in the main toolbar, but it still routes to the unfinished-tool placeholder. The finalized requirements define Mosaic as the next single-tool iteration: activate quickly, support Gaussian blur and pixel mosaic, support both sliding and rectangle workflows, and leave other unfinished tools untouched (see origin: `docs/brainstorms/2026-06-23-mosaic-tool-requirements.md`).

The current overlay system is already strong on activation, selection, movement, delete, undo/redo, and export for shape, arrow, brush, and marker annotations. The main implementation challenge is not “how to add another button”; it is “how to add a pixel-based redaction effect without forking preview and export behavior into two drifting code paths.”

---

## Requirements

- R1. Replace the Mosaic placeholder with a real tool activation flow, selected state, and tool isolation behavior matching origin `R1-R5`, `R54-R55`.
- R2. Add a Mosaic-specific secondary toolbar that exposes redaction type, type value, and drawing behavior while hiding unrelated shape, arrow, brush, and marker controls, matching origin `R6-R21`.
- R3. Support two redaction types, `gaussianBlur` and `pixelMosaic`, each with its own remembered integer value in the inclusive range `8...20`, default `8`, matching origin `R7-R13`.
- R4. Support two mutually exclusive drawing behaviors: sliding redaction with dot sizes `15 / 30 / 40` and rectangle redaction with a filled-square control, matching origin `R14-R19`.
- R5. Enter Mosaic in the fast path by default: activating the tool immediately enables sliding redaction with medium dot `30`, a gray `#D3D3D3` circular cursor, and no required secondary-toolbar interaction, matching origin `R15`, `R21-R25`.
- R6. Commit sliding redactions as selectable, movable Mosaic stroke annotations and rectangle redactions as selectable, movable, resizable Mosaic rectangle annotations, matching origin `R26-R38`.
- R7. Let Mosaic drafts extend beyond the locked screenshot bounds during drag, but clip preview and committed/exported output to the screenshot bounds, matching origin `R39-R41`, `R49-R53`.
- R8. Preserve whole-capture cancel, delete, undo, redo, and keyboard accessibility behavior for Mosaic, matching origin `R42-R48`.
- R9. Render dynamic Mosaic toolbar icons that preview current Gaussian blur and pixel mosaic intensity, including the circular blur glyph and five-square cross glyph, matching origin `R11-R13`.
- R10. Update user-facing documentation so Mosaic moves from unfinished to supported once the feature ships, matching origin `R56`.

---

## Key Technical Decisions

- KTD1. **Model Mosaic as two concrete annotation kinds with shared redaction metadata.** Add `mosaicStroke` and `mosaicRectangle` to `CaptureAnnotationKind`, and store shared effect metadata (`type`, `value`) alongside shape-specific geometry. This fits the existing kind-driven selection, move, resize, and undo code better than introducing a generic “tool type” abstraction mid-stream.
- KTD2. **Use one shared raster redaction helper for preview and export.** Gaussian blur and pixel mosaic are image-processing effects, so the implementation should not invent one approximation for the overlay and another for copy/save. A dedicated helper under `platforms/mac/Sources/Overlay/` should own filter application, clipping, and compositing; `SelectionOverlayWindow` and `CaptureAnnotationRenderer` should both call into it.
- KTD3. **Keep Mosaic inside the existing overlay window instead of creating a detached tool subsystem.** `SelectionOverlayWindow` already owns toolbar hit testing, annotation drafting, selection state, cursor updates, and export handoff. Extending that path is smaller and safer than building a parallel overlay controller only for Mosaic.
- KTD4. **Use a stepped integer value control, not a freeform slider.** The requirements only need the inclusive `8...20` range and live icon updates. A stepped control is easier to draw inside the custom toolbar, easier to make keyboard-accessible, and lower risk than adding a draggable slider to a view that currently relies on explicit hit-test rectangles.
- KTD5. **Treat out-of-bounds drag as a Mosaic-specific drafting rule, not a global annotation behavior change.** Existing tools clamp their live geometry more tightly. Mosaic alone needs off-bounds drafting with in-bounds commit clipping, so the special-case logic should stay scoped to Mosaic kinds.

---

## Scope Boundaries

- In scope: mac overlay activation, secondary-toolbar controls, Mosaic annotation models, preview rendering, export rendering, selection/editing rules, dynamic cursor behavior, focused tests, and user-guide updates.
- Deferred for later: multi-select Mosaic editing, OCR-assisted redaction, preset packs beyond raw values `8...20`, path reshaping for committed sliding strokes, and work on Text/Number/Magnifier/Eraser/Pin/Scroll Capture.
- Out of scope: redesigning the main toolbar, moving shared annotation code into `core/`, or changing the behavior of completed tools except where Mosaic must integrate with shared selection or undo state.

---

## Sources / Research

- `docs/brainstorms/2026-06-23-mosaic-tool-requirements.md` is the origin document and source of behavioral truth.
- `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift` already contains the main-toolbar button wiring, placeholder handling, draft/commit flow, selection movement, `Esc` cancellation, and export handoff that Mosaic should follow.
- `platforms/mac/Sources/Overlay/SelectionToolbarState.swift` already defines the second-toolbar layout system, tooltip naming, hit testing, and cursor-style helpers that Mosaic should extend.
- `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift` already owns export-time annotation rendering and is the right integration point for final-image redaction compositing.
- `platforms/mac/Tests/SelectionToolbarStateTests.swift` and `platforms/mac/Tests/SniporyMacTests.swift` already cover marker/brush/renderer behavior with the same style of focused tests Mosaic needs.
- `docs/annotation-tools-user-guide.md` is the user-facing doc that still lists Mosaic as unfinished.

---

## Implementation Units

### U1. Mosaic Annotation Model And Shared Redaction Renderer

- **Goal:** Introduce Mosaic annotation kinds and a shared image-processing helper that can apply Gaussian blur and pixel mosaic to bounded regions for both overlay preview and exported output.
- **Files:**
  - Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
  - Add: `platforms/mac/Sources/Overlay/CaptureRedactionRenderer.swift`
  - Modify: `platforms/mac/Tests/SniporyMacTests.swift`
- **Design:**
  - Extend `CaptureAnnotationKind` with `mosaicStroke` and `mosaicRectangle`.
  - Extend `CaptureAnnotation` with Mosaic-specific payload needed for both geometry classes: redaction type, value, and either stroke path plus dot diameter or rectangle geometry.
  - Implement a shared renderer helper that accepts a source image, selection-space bounds, and Mosaic annotation geometry, then applies either `CIGaussianBlur` or `CIPixellate` and composites the filtered pixels back into the source image through a mask.
  - Keep clipping inside the renderer helper so overlay preview and export both honor the same in-bounds result when draft or committed geometry crosses the screenshot edge.
- **Patterns to follow:** Reuse `CaptureAnnotationRenderer.render(image:annotations:)` as the export entry point and the existing marker/brush model structs as the shape for geometry payload types.
- **Test scenarios:**
  - Verify Gaussian blur changes pixels inside the target region while keeping pixels outside the region unchanged.
  - Verify pixel mosaic renders blocky output rather than a translucent overlay.
  - Verify out-of-bounds geometry only affects in-bounds pixels in the final image.
  - Verify export dimensions stay identical to the source image dimensions.
  - Verify the same annotation list can render both rectangle and sliding Mosaic geometry.

### U2. Mosaic Toolbar State, Hit Testing, And Dynamic Icon Controls

- **Goal:** Add a dedicated Mosaic second-toolbar layout with mutually exclusive drawing-behavior controls, mutually exclusive redaction-type controls, per-type remembered values, and live preview icons.
- **Files:**
  - Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
  - Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`
- **Design:**
  - Add a Mosaic toolbar mode and a Mosaic-specific layout model instead of forcing the existing shape/arrow/marker `OptionsToolbarLayout` to represent unrelated controls.
  - Add helper functions for Mosaic dot sizes (`15 / 30 / 40`), per-type default values (`8`), stepped value increment/decrement, accessible names, and preview-color/intensity mapping for icon backgrounds.
  - Add drawing helpers for the blur preview circle and the five-square mosaic cross so the icon visuals update as the current value changes from `8` to `20`.
  - Add toolbar hit-testing helpers for sliding-dot controls, rectangle control, type controls, and stepped value buttons/readout.
- **Patterns to follow:** Reuse the current tooltip and rect-based hit-testing pattern in `SelectionToolbarState` rather than introducing AppKit controls into the custom overlay.
- **Test scenarios:**
  - Verify Mosaic layout hides fill, stroke-style, arrow-type, and color-swatch controls while exposing only Mosaic controls.
  - Verify switching between Gaussian blur and pixel mosaic preserves independent values.
  - Verify switching between sliding and rectangle stays mutually exclusive and leaves the selected redaction type/value unchanged.
  - Verify the default Mosaic activation state is sliding + medium dot `30` + Gaussian blur value `8`.
  - Verify preview helper output changes as values move between `8` and `20`.
  - Verify accessible names and selected-state metadata exist for blur, mosaic, small dot, medium dot, large dot, and rectangle controls.

### U3. Overlay Activation, Drafting, Selection Editing, And Cursor Behavior

- **Goal:** Replace the Mosaic placeholder path with a full overlay interaction flow for creation, editing, movement, resizing, undo/redo, and cancellation.
- **Files:**
  - Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
  - Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`
- **Design:**
  - Route toolbar button `.mosaic` into real tool activation instead of `showPlaceholder(for:)`.
  - Add Mosaic-specific activation state storage: current redaction type, remembered values per type, current drawing behavior, current dot size, and current draft payload.
  - Default activation to sliding with medium dot `30`, gray circular cursor, and Gaussian blur value `8`.
  - Add Mosaic draft generation for two cases:
    - Sliding mode accumulates a path similar to brush input, but stores dot size and allows path points outside the locked selection.
    - Rectangle mode drafts a rectangle from press to release and keeps crosshair cursor behavior.
  - Add selection-edit rules:
    - Selected Mosaic rectangle: editable type and value, movable and resizable.
    - Selected Mosaic stroke: editable type, value, and dot size; movable but not point-by-point reshaped.
    - No Mosaic selection: toolbar edits the defaults for the next Mosaic annotation.
  - Extend cursor logic with a Mosaic circular cursor whose diameter tracks `15 / 30 / 40` live, and retain crosshair for rectangle mode.
  - Ensure `Esc`, `Delete`, `Command+Z`, and `Command+Shift+Z` operate through the existing capture-level code paths.
- **Patterns to follow:** Reuse the draft/commit structure already used by brush, marker, and rectangle annotations, and keep annotation movement/selection in the shared overlay path.
- **Test scenarios:**
  - Verify clicking the Mosaic toolbar button no longer shows the unfinished message.
  - Verify immediate drag after activation creates a sliding Mosaic annotation with medium dot `30`.
  - Verify changing dot size updates cursor size immediately.
  - Verify rectangle mode uses the crosshair cursor and creates a movable/resizable rectangle annotation.
  - Verify dragging outside the locked selection still previews and commits only the clipped in-bounds result.
  - Verify selected rectangle type/value edits update the selected annotation, while selected stroke dot-size edits update the selected stroke.
  - Verify undo/redo capture draw, delete, and post-draw value/type/dot-size edits.
  - Verify `Esc` cancels the entire capture even when a Mosaic draft is active.

### U4. User Guide And Final Verification

- **Goal:** Publish the shipped behavior in the user guide and verify the mac target with focused automated coverage plus a manual smoke check.
- **Files:**
  - Modify: `docs/annotation-tools-user-guide.md`
- **Design:**
  - Move Mosaic from the unfinished list into the supported-tools section.
  - Document activation, Gaussian blur vs pixel mosaic, value range `8...20`, sliding dot sizes `15 / 30 / 40`, rectangle mode, selection/editing rules, and clipping/export behavior.
- **Verification:**
  - Run focused mac tests covering renderer and overlay interactions first.
  - Run the full mac test target once Mosaic passes focused coverage.
  - Build and launch the debug app for a manual smoke check: click Mosaic, drag immediately, switch blur/mosaic, switch dot sizes, switch rectangle mode, drag beyond selection, copy/save, and cancel with `Esc`.

---

## Risks & Dependencies

- **Retina and coordinate-space drift:** Raster filters, overlay coordinates, and selection-local coordinates must align exactly. Mitigation: add bitmap tests with nontrivial coordinates and out-of-bounds geometry.
- **Preview performance:** Re-filtering the selection image on every drag can get expensive. Mitigation: keep the shared helper scoped to the selection crop, not the full desktop image, and cache intermediate source images where straightforward.
- **State collision with existing tool activation:** `SelectionOverlayWindow` currently assumes the second toolbar belongs to shape-like tools. Mitigation: add Mosaic as an explicit extension of that state machine instead of piggybacking on placeholder logic.
- **Accessibility drift in icon-only controls:** Mosaic adds more icon-only controls than current tools. Mitigation: keep accessible-name generation in `SelectionToolbarState` and add assertions in tests.

---

## Acceptance Focus

- F1. Fast path redaction from main-toolbar click to immediate sliding draw must work without any second-toolbar change (origin `F2`, `AE5`).
- F2. The user must be able to switch between Gaussian blur and pixel mosaic and get remembered per-type values plus live icon updates (origin `F4`, `AE2-AE4`).
- F3. Sliding and rectangle Mosaic annotations must both remain editable under the single-selection rules defined in the requirements (origin `F1`, `F3`, `AE7-AE8`).
- F4. Copy/save output must match preview behavior for clipping and image dimensions (origin `AE9`, `AE12`).
