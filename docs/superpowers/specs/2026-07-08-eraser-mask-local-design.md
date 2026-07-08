# xxsnap Local Eraser Mask Design

## Context

The current eraser implementation is deliberately safe: point mode deletes whole annotation objects, rectangle mode deletes intersecting annotation objects, and clear-all removes all annotations. It keeps eraser behavior isolated from the renderer and avoids changing existing tools.

The next step is local erasing. The design must preserve the same safety principle: existing tools should not pay runtime cost when local erasing is unused, and a local eraser change must be easy to roll back.

## Goals

- Add local rectangular erasing for annotations.
- Keep screenshot pixels unchanged; erasing only affects annotation output.
- Support local erasing across all annotation kinds, including mosaic annotations.
- Mark locally erased annotations as damaged so they cannot be selected, moved, resized, restyled, or edited.
- Keep damaged annotations removable by point eraser and by clear-all.
- Keep mask state independent from ordinary annotation editing paths.
- Preserve undo and redo for local eraser mask creation.
- Avoid high-frequency compositing while the mouse is moving or dragging.
- Avoid affecting existing tools when no local eraser masks exist.

## Non-Goals

- Do not erase the screenshot background image.
- Do not implement freehand eraser strokes in this version.
- Do not split rectangle, text, arrow, brush, marker, mosaic, or magnifier geometry into editable fragments.
- Do not allow editing damaged annotations.
- Do not add mask handling to every tool-specific edit path.
- Do not change mosaic cache behavior for normal drawing and editing.
- Do not make existing tools run mask compositing when no masks exist.

## Chosen Approach

Use an independent rectangular eraser mask layer.

When rectangle eraser mode is active, dragging still shows the existing blue dashed rectangle preview. On mouse up, instead of deleting intersecting annotations, the overlay creates an `EraserMask` for the rectangle. The mask stores which annotations it affects by stable annotation id. Affected annotations become damaged and are skipped by selection and edit hit-testing.

Rendering remains simple:

- Without masks: use the existing annotation rendering path.
- With masks: draw annotations into an annotation layer, apply the eraser masks to that layer, then composite the masked annotation layer over the original screenshot.

This keeps local erasing as a final annotation-layer composition step. The original screenshot remains untouched, so erased mosaic regions reveal the original screenshot underneath.

## Data Model

Add stable identity to annotations:

```swift
typealias AnnotationID = UUID

struct CaptureAnnotation {
    var id: AnnotationID
    ...
}
```

Existing annotation initializers and tests should default to a new UUID so most call sites do not need to pass ids manually.

Add independent eraser masks:

```swift
struct EraserMask: Equatable {
    var id: UUID
    var rect: NSRect
    var affectedAnnotationIDs: Set<AnnotationID>
}
```

Store masks in the overlay beside the annotation list:

```swift
private var eraserMasks: [EraserMask] = []
```

Damaged state is derived from masks, not stored permanently in annotations:

```swift
private var damagedAnnotationIDs: Set<AnnotationID> {
    Set(eraserMasks.flatMap(\.affectedAnnotationIDs))
}
```

If repeated computation becomes noisy, this can be cached and rebuilt when masks or annotations change, but the first implementation should keep the source of truth simple.

## Interaction

### Point Eraser

Point mode keeps the current whole-object deletion behavior.

It can delete normal annotations and damaged annotations. This gives users a way to clean up partially erased objects without requiring selection.

### Rectangle Local Eraser

Rectangle mode changes from whole-object deletion to local mask creation.

On drag:

- Draw only the blue dashed preview rectangle.
- Do not create a mask.
- Do not recomposite the annotation layer.
- Do not touch mosaic caches.

On mouse up:

1. Ignore rectangles smaller than the existing minimum threshold.
2. Convert the preview rectangle to annotation-local coordinates if needed.
3. Find annotations whose erase bounds intersect the rectangle.
4. If no annotations intersect, do not create a mask or history entry.
5. Create an `EraserMask` with the rectangle and affected annotation ids.
6. Append the mask and record one undoable history entry.
7. Re-render the overlay once.

### Clear All

Clear-all removes both annotations and eraser masks.

Undo restores both annotations and eraser masks. Redo clears both again. This keeps clear-all consistent with local eraser mask history and avoids leaving masks that reference removed annotations.

### Editing Damaged Annotations

Damaged annotations cannot be selected or edited by normal tools.

Selection, movement, resize handles, text editing, number controls, style application, rotation handles, arrow handles, brush endpoint controls, marker endpoint controls, magnifier controls, and mosaic controls should skip damaged annotation ids.

Point eraser hit-testing should not skip damaged ids.

## Rendering

### Overlay Preview

If `eraserMasks.isEmpty`, keep the existing overlay annotation drawing path.

If masks exist:

1. Draw annotations into an offscreen transparent annotation layer.
2. Apply every eraser mask with a clear operation to that annotation layer.
3. Draw the masked annotation layer over the screenshot preview.
4. Draw non-edit UI such as toolbars, selection frame, and active rectangle preview normally.

The mask should affect all annotation kinds uniformly, including mosaic annotations. Since the mask clears the annotation layer, erased mosaic areas reveal the original screenshot underneath.

### Export

Export must match overlay output:

1. Render annotations as before into an annotation layer.
2. Apply eraser masks to the annotation layer.
3. Composite the masked annotation layer over the original screenshot.

The public export route can stay unchanged when there are no masks. When masks exist, add a separate renderer entry point rather than changing every caller:

```swift
CaptureAnnotationRenderer.render(
    image: image,
    annotations: annotations,
    eraserMasks: eraserMasks
)
```

The existing `render(image:annotations:)` must remain available and unchanged for callers that do not use masks.

## Undo And Redo

Add history entries for mask creation:

```swift
case addEraserMask(mask: EraserMask)
```

Undoing a mask creation removes that mask. Redo restores it. Damaged state is derived from current masks, so restoring editability is automatic after undo.

Deletion history must handle masks safely:

- When deleting an annotation, keep existing masks in place but filter mask references through the current annotation id set.
- Undoing annotation deletion restores the annotation. If any existing mask still references its id, the annotation is damaged again.
- Damaged-state calculation and export must ignore mask ids that do not exist in the current annotation list.

## Performance Guardrails

- No mask compositing on mouse move.
- No mask compositing during rectangle drag; only draw the dashed preview.
- No annotation-layer offscreen rendering when `eraserMasks.isEmpty`.
- No path splitting.
- No per-tool geometry mutation.
- No global renderer or mosaic cache rewrite.
- No mask checks inside tool paths unless the path is about hit-testing, selecting, or editing an existing annotation.
- Intersection detection on commit should use bounding rects first and only fall back to detailed hit bounds where already available.

## Edge Cases

- Empty rectangle erases nothing and creates no history entry.
- A mask that intersects only the screenshot background does nothing.
- Multiple masks can affect the same annotation; the annotation remains damaged until all masks affecting it are undone or removed.
- Deleting a damaged annotation should not crash mask rendering.
- Undoing a local erase should make affected annotations editable again if no other mask affects them.
- Redoing a local erase should make affected annotations damaged again.
- Saving and copying should include local eraser effects.
- Existing object deletion mode should still work.

## Testing

Add focused mac XCTest coverage:

- rectangle eraser creates a mask instead of deleting the intersected annotation;
- masked area is transparent in the annotation layer and reveals the original screenshot;
- local erasing affects mosaic annotations and reveals the original screenshot beneath;
- locally erased annotations cannot be selected, moved, resized, restyled, or text edited;
- point eraser can delete damaged annotations;
- clear-all clears masks and annotations;
- undo and redo restore and reapply local masks;
- an empty rectangle creates no mask or history entry;
- export output matches overlay local eraser output;
- no-mask rendering still uses the existing renderer behavior;
- existing eraser object deletion tests still pass;
- representative rectangle, text, arrow, brush, marker, mosaic, magnifier, and number tests still pass.

Run focused local eraser tests first, then run the relevant mac test suite:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

If the known unrelated magnifier renderer pixel tests still fail, report them separately and include the focused local eraser test results.

## Acceptance Criteria

- Rectangle eraser locally removes annotation pixels without modifying the screenshot background.
- Mosaic local erasing reveals the original screenshot below the erased area.
- Damaged annotations cannot be edited by existing tools.
- Damaged annotations can still be removed by point eraser and clear-all.
- Undo and redo work for local eraser masks.
- Copy and save include local eraser effects.
- Existing tools do not pay mask-rendering cost when no masks exist.
- The implementation remains isolated enough to revert from the feature branch without touching unrelated tools.
