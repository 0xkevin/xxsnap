# Windows Shape Annotation Foundation Implementation Plan

**Goal:** Add a portable annotation document with undo/redo and expose fully working rectangle/ellipse drawing on Windows, including macOS-matching options, live preview, hit testing, editing, and export composition.

**Architecture:** C++17 domain types own annotation identity, geometry, style, selection, and reversible commands. Win32 input translates pointer/keyboard events into domain operations; Direct2D renders the same document used by final BGRA composition. The rectangle toolbar action remains hidden until the complete draw/edit/export slice is connected.

**macOS reference:** `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`, `SelectionToolbarState.swift`, and `SelectionOverlayWindow.swift`.

## Task 1: Lock portable annotation types and macOS defaults

- Create `platforms/win/src/annotation/AnnotationTypes.h`.
- Create `platforms/win/tests/TestAnnotationTypes.cpp`.
- Define stable IDs, points, standardized rectangles, RGBA colors, stroke patterns, rectangle/ellipse kinds, rotation, and `AnnotationStyle`.
- Lock macOS defaults: red `245/34/45/255`, width `3`; primary shape activation width `4`, radius `5`; fill disabled; solid stroke.
- Add `/W4 /WX /permissive-` Modern and Legacy tests.

## Task 2: Implement AnnotationDocument and reversible history

- Create `AnnotationDocument.h/.cpp` and `TestAnnotationDocument.cpp`.
- Support add, delete, move, resize, rotate, style change, selection, clear selection, undo, redo, and redo invalidation after a new command.
- Preserve document order and stable IDs across undo/redo.
- Reject invalid IDs and no-op edits without corrupting history.

## Task 3: Add rectangle/ellipse interaction controller

- Create `ShapeInteraction.h/.cpp` and tests for draw, cancel, move, eight resize handles, rotation, and bounds clipping.
- Keep drafts outside the committed document until pointer-up.
- Match macOS minimum-size, standardization, and tool-switch commit/cancel semantics.

## Task 4: Reproduce the macOS shape options toolbar

- Extend toolbar catalog/layout/state for shape mode only.
- Lock 10-DIP horizontal padding, 30/40-DIP heights, `[2,4,7]` widths, six stroke patterns, fill toggle, rectangle/ellipse toggle, radius `0...30`, and palette behavior.
- Derive all option icons from unchanged macOS resources and share render/input layout.

## Task 5: Render live shapes and editing affordances

- Add `AnnotationRenderer.h/.cpp` using Direct2D.
- Render solid/dashed/sketch outlines, optional fill, rounded rectangles, ellipses, selection handles, rotation handle, and live draft.
- Rebuild device resources without losing the portable document.
- Add deterministic render snapshots at 96/120/144/192 DPI.

## Task 6: Connect toolbar and overlay input

- Let `OverlayInputRouter` emit non-terminal toolbar actions and annotation interaction events.
- Enable `ToolbarAction::rectangle` only after drawing, editing, options, and rendering are connected.
- Connect Ctrl+Z/Ctrl+Shift+Z, Delete, Escape, and tool shortcuts using Windows Ctrl mappings.
- Verify selection creation behavior remains unchanged when no annotation tool is active.

## Task 7: Compose annotations into copy/save output

- Add `AnnotatedSelectionComposer.h/.cpp` and pixel tests.
- Render the document into the same BGRA result consumed by clipboard and PNG paths.
- Assert preview geometry and exported pixels agree for rectangle/ellipse, fill, stroke, radius, pattern, rotation, and crop edges.

## Task 8: Full matrix and visual acceptance

- Run asset verification and Modern x64/x86 plus Legacy x64/x86 matrices.
- Verify Win7 imports and subsystem remain valid.
- Inspect 100%, 150%, and 200% in Parallels against the same macOS states.
- Only then expose the rectangle button in normal capture sessions.

## Completion gate

- Rectangle/ellipse creation, selection, move, resize, rotate, style changes, undo, redo, copy, and save are real.
- The options toolbar and icons match macOS; no placeholder interaction is visible.
- Renderer, input, and export consume the same annotation document and geometry.
- All four Windows build targets pass.
