# xxsnap Eraser Tool Safe V1 Design

## Context

The previous eraser plan proposed ordered render-history entries, `CaptureAnnotation.renderOrder`, eraser masks in `CaptureSelectionResult`, and a renderer path that mixes annotations and masks. That design gives a complete local-erasing model, but it also touches every existing annotation tool, export rendering, mosaic preview caching, and several hot drawing paths. In practice, it risks slow frames and high CPU usage for tools that currently work.

This design intentionally ships a smaller first version. The priority is performance isolation: existing tools must keep their current render and cache paths unless the eraser is actively being used.

## Goals

- Activate the macOS eraser toolbar entry.
- Let users click an existing annotation to delete the whole object.
- Support deleting rectangles, ellipses, arrows, brush paths, marker lines, text, number marks, magnifiers, and mosaic annotations through the same object-deletion behavior.
- Keep erase behavior undoable and redoable.
- Keep existing annotation drawing, mosaic preview caching, copy, and save output unchanged when the eraser is not active.
- Keep the implementation small and isolated so it can be replaced or expanded later if the first version feels insufficient.

## Non-Goals

- Do not implement local pixel-level erasing of existing annotations in V1.
- Do not add eraser masks to `CaptureSelectionResult`.
- Do not add `renderOrder` to `CaptureAnnotation`.
- Do not add a new `CaptureAnnotationRenderer.render(image:annotations:eraserMasks:)` path.
- Do not change the existing `CaptureAnnotationRenderer.render(image:annotations:)` behavior.
- Do not modify mosaic composite cache keys, prefix-cache logic, local composite rendering, or draft redaction caches for eraser support.
- Do not make existing tools pay any per-frame cost for eraser support.

## Chosen Approach

Build the eraser as an object deletion tool, not as a render-layer masking tool.

When the eraser is active, mouse down hit-tests existing annotations using the same hit-test helpers already used for selection and editing. If an annotation is hit, the eraser removes that annotation from the existing `annotations` array and records the deletion as an undoable action. If no annotation is hit, the click does nothing.

Dragging in empty space does not move the screenshot selection and does not create an annotation or mask. The cursor can show an eraser-sized hollow circle preview, but that preview is purely visual and local to the overlay draw pass.

## Architecture

Add a small eraser-specific state boundary in the mac overlay layer:

- `isEraserToolActive`: toggled by the eraser toolbar button.
- `currentEraserSize`: fixed size choice for cursor/preview only, initially one default size is acceptable.
- `pendingEraserDeletion`: optional state only if needed to avoid repeated deletion during one mouse gesture.

This state stays in `SelectionOverlayWindow` or in a small companion type such as `EraserToolState`. It must not be added to `CaptureAnnotation`, `CaptureAnnotationRenderer`, or mosaic cache keys.

The eraser button activation should:

- commit pending text edits;
- close open dropdowns and popovers;
- turn off shape, text, number, magnifier, and eyedropper modes;
- clear transient drawing drafts;
- preserve the current annotations array until the user clicks a hit annotation.

## Interaction

### Toolbar

Clicking the eraser button toggles eraser mode. The toolbar button should show selected state while active.

V1 can use a minimal options toolbar:

- either no options toolbar, using a fixed cursor size;
- or a small eraser-size selector if it is simple to add without disturbing existing options layout.

The preferred implementation is no options toolbar for the first pass. That keeps the first version focused on behavior and performance.

### Cursor

When eraser mode is active:

- over toolbar or option UI: normal arrow cursor;
- over the capture/annotation area: eraser cursor or hollow-circle cursor;
- over an annotation: the same eraser cursor, optionally with hover highlight in a later polish pass.

The cursor must be generated from eraser state only. It must not trigger image recomposition.

### Click To Delete

On mouse down:

1. Ignore toolbar, options toolbar, popovers, and measurement controls.
2. Hit-test annotations from topmost to bottommost.
3. If a hit annotation exists, delete it and record an undoable deletion action.
4. If no annotation is hit, consume the eraser click and do nothing.

Consuming the click matters: dragging after a missed eraser click must not move the screenshot selection.

### Drag

Dragging in eraser mode must not:

- move the screenshot selection;
- resize the screenshot selection;
- create shape annotations;
- create eraser masks;
- trigger mosaic preview recomposition.

If a deletion already happened on mouse down, continued dragging during the same gesture should not repeatedly delete more objects in V1. This avoids surprising bulk deletion and keeps the implementation simple.

## Undo And Redo

The current undo model is mostly stack-based for appended annotations. Eraser deletion removes an annotation from an arbitrary index, so V1 needs a narrow undo history extension.

Use a small command-style history only for eraser deletion if that is the least invasive option:

- deletion action stores the removed annotation and original index;
- undo reinserts it at the original index if possible;
- redo removes the same restored annotation again.

This should not require converting all existing annotation mutations to command history in V1. Existing undo behavior for normal append/remove can remain as-is unless tests reveal a direct conflict.

If mixing the current `redoAnnotations` stack with eraser deletion becomes risky, the implementation should prefer the smallest isolated compatibility layer rather than a full history rewrite.

## Rendering And Export

There is no new render path in V1.

After an eraser deletes an object, overlay preview and copy/save export naturally reflect the remaining `annotations` array. Existing renderer and mosaic paths continue to render the current annotations exactly as before.

This is the core performance guarantee: eraser affects the annotation list, not the renderer architecture.

## Performance Guardrails

Implementation must preserve these rules:

- No changes to `CaptureAnnotationRenderer.render(image:annotations:)` for eraser support.
- No full-image recomposition on mouse move in eraser mode.
- No modification to mosaic cache keys for eraser state.
- No eraser state inside `CaptureAnnotation`.
- No per-frame sorting of all annotations for eraser support.
- No transparency-layer masking path for existing annotations in V1.
- No invalidating mosaic caches when a missed eraser click or drag does nothing.

Deleting a mosaic annotation may reset mosaic preview caches because the annotation list changed. That is acceptable and already matches comparable deletion behavior.

## Error Handling And Edge Cases

- Clicking empty capture space in eraser mode does nothing and keeps the selection fixed.
- Dragging after clicking empty capture space keeps the selection fixed.
- Clicking toolbar or popover UI in eraser mode should operate that UI normally.
- Deleting a selected annotation clears or updates selection state consistently.
- Deleting a number mark should preserve existing number-renumbering behavior.
- Deleting text while a text editor exists should commit or close editing before deletion.
- If hit-testing returns no object, no history entry is created.

## Testing

Add focused mac XCTest coverage for:

- eraser toolbar button activates eraser mode instead of showing the placeholder alert;
- activating eraser mode deactivates shape, text, number, magnifier, and eyedropper modes;
- eraser click deletes a rectangle annotation;
- eraser click deletes text, number, magnifier, and mosaic annotations through representative tests;
- eraser click in empty capture space does not move the locked selection;
- eraser drag in empty capture space does not move the locked selection;
- eraser deletion is undoable and redoable;
- eraser deletion leaves copy/save result using the normal annotation export path;
- missed eraser clicks do not reset mosaic preview caches;
- existing number, text, mosaic, magnifier, and basic shape tests still pass.

Run focused tests during implementation, then at least the mac XCTest target:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Known local note: before this design, full mac tests had unrelated magnifier renderer pixel failures. If those persist, report them separately and verify the eraser-focused tests plus a relevant regression subset.

## Acceptance Criteria

- Eraser toolbar entry is no longer a placeholder.
- Eraser mode can delete existing annotation objects by click.
- Empty eraser clicks and drags do not move or resize the screenshot selection.
- Deletions are undoable and redoable.
- Existing renderer and mosaic cache architecture are not changed for V1.
- Existing tools do not do additional eraser-related work when eraser mode is inactive.
- Performance remains stable during eraser hover and drag because no full-image eraser compositing is performed.
