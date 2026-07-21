# xxsnap Eraser Tool Design

## Context

xxsnap already has a visible Eraser toolbar entry, a bundled `eraser-tool.svg` icon, and a tooltip title of `橡皮擦`, but the button still uses the unfinished placeholder behavior. The current mac overlay has mature annotation creation, hit testing, selection, undo/redo, preview rendering, and copy/save export patterns for shape, arrow, brush, marker, mosaic, text, number sequence, and magnifier tools.

This design turns the Eraser entry into a shippable mixed eraser tool. The tool supports object deletion by click, freehand local erasing by circular cursor drag, and rectangular area erasing by drag-selecting a box.

## Goals

- Activate the existing Eraser toolbar button instead of showing the placeholder alert.
- Support object-level deletion when the user clicks an existing annotation without a meaningful drag.
- Support local erasing across all visible annotations by applying eraser masks to the annotation layer.
- Support two local erasing modes: circular freehand erasing and rectangular area erasing.
- Show an empty-circle eraser cursor whose diameter matches the selected eraser size in circular mode.
- Keep erasing scoped to annotations only; never erase the original screenshot pixels.
- Keep overlay preview and copy/save export visually consistent.
- Include object deletion and local eraser masks in undo/redo.

## Non-Goals

- Do not structurally split annotation geometry in the first version.
- Do not edit text glyph contents, arrow vector points, shape paths, or magnifier source sampling data when erasing locally.
- Do not erase the captured screenshot background.
- Do not add multi-select, eraser history panels, pressure sensitivity, tablet-specific behavior, or custom numeric size input.
- Do not change pin, scroll capture, screenshot permissions, clipboard, save, or unrelated annotation behavior.

## Chosen Approach

Use a unified visible eraser mask model for local erasing, plus click-to-delete for fast object removal.

The local eraser does not mutate each annotation into new geometry. Instead, it records eraser mask entries and applies them to the rendered annotation layer. This gives one consistent behavior for all annotation kinds, including shapes, arrows, brush paths, marker lines, mosaic redactions, text, number marks, and magnifiers.

This approach is intentionally different from structural cutting. Structural cutting would require separate geometry and rendering rules for every annotation kind and would be especially fragile for text, rounded shapes, arrows, magnifiers, and mosaic redactions. A mask model matches the requested "erase what I see" behavior while keeping the implementation bounded.

## Eraser Model

Add committed eraser mask entries to the same ordered render history as annotations, or to an equivalent structure that preserves relative order between annotations and masks. Each entry stores:

- eraser kind: `freehand` or `rectangle`;
- creation order;
- eraser size for freehand masks;
- local points for freehand masks;
- local rect for rectangle masks.

Eraser masks are not ordinary visible annotations and are not selectable as drawn objects in the first version. They are edit history operations that affect how annotations render. They are kept until undone, replaced by a new history branch after undo, or until the capture session ends.

The mask coordinate space should follow the existing local annotation coordinate model so selection resizing, overlay preview, and export conversion remain consistent with existing annotation infrastructure.

## Toolbar Design

Clicking the main-toolbar Eraser button toggles eraser mode. Eraser mode is mutually exclusive with shape, arrow line, brush, marker, mosaic, text, number sequence, magnifier, and eyedropper modes.

When eraser mode is active, the secondary toolbar shows:

1. Erasing mode:
   - circular freehand, default;
   - rectangular area.
2. Eraser size for circular freehand mode:
   - small: `12px`;
   - medium: `24px`, default;
   - large: `40px`.

The toolbar should follow existing icon-button and selected-state patterns. Rectangular area mode keeps the size controls visible and enabled, but the selected size affects only the next circular freehand erase. This avoids layout shifts when switching between circular and rectangular modes.

## Cursor Design

Circular freehand mode uses a custom empty-circle cursor:

- the circle diameter equals the current eraser size;
- the circle is hollow, with no filled center;
- the stroke should remain visible on light and dark content, using a white outer stroke plus dark inner stroke, or the repository's existing background-aware cursor strategy;
- the cursor hotspot is the circle center;
- the cursor updates immediately when the user changes eraser size.

Rectangular area mode uses a crosshair or rectangular framing cursor consistent with existing rectangle-style drawing behavior.

Over the main toolbar, secondary toolbar, menus, popovers, copy/save/cancel controls, and other non-canvas UI, the cursor falls back to the normal arrow.

## Interaction

### Activation

Clicking the Eraser toolbar button enters eraser mode and closes transient tool UI such as color, stroke, arrow, text, number, magnifier, and eyedropper panels. Clicking Eraser again exits eraser mode.

Switching to another tool clears any in-progress eraser draft but keeps committed eraser masks and annotation deletions.

### Object Deletion

In eraser mode, a press and release with movement below the existing drag threshold is treated as a click. If the click hits one or more annotations, xxsnap deletes the topmost hit annotation. If no annotation is hit, nothing happens.

This click deletion path uses existing hit testing order and deletion behavior where possible. It should be included in undo/redo as one delete operation.

### Circular Freehand Erasing

Circular freehand mode is the default local erasing mode.

The user presses and drags over the overlay. Once movement exceeds the drag threshold, xxsnap starts an eraser draft path. The live preview applies a circular mask centered on each path segment with the selected eraser diameter. Releasing the mouse commits one freehand eraser mask entry.

Tiny or empty drags are ignored and do not create a history entry. Freehand erasing can start inside or outside the locked screenshot selection, matching recent permissive annotation behavior, but copy/save export remains clipped to the selected screenshot image.

### Rectangular Area Erasing

Rectangular area mode lets the user erase a whole region at once.

The user selects rectangular area mode in the secondary toolbar, presses, drags out a rectangle, and releases. During the drag, the overlay shows the draft rectangle and previews the erased annotation layer inside it. On release, xxsnap commits one rectangle eraser mask entry.

Tiny or empty rectangles are ignored. A click without meaningful drag still follows object deletion semantics.

## Rendering

Preview and export should share the same conceptual pipeline:

1. Draw the original screenshot as the background.
2. Render all visible annotations into an intermediate annotation layer in annotation order.
3. Apply committed eraser masks, plus any active draft mask, to clear pixels from the annotation layer.
4. Composite the resulting annotation layer over the screenshot background.

Eraser masks affect the annotation layer only. The original screenshot pixels are never cleared or recolored.

This rule means local erasing can partially remove:

- rectangle and ellipse strokes or fills;
- arrow lines and arrowheads;
- brush paths;
- marker lines;
- mosaic stroke and rectangle redaction output;
- text glyphs and text outline;
- number, check, and cross marks;
- magnifier border and visible lens output.

The eraser should operate on final visible annotation output, not on individual annotation source data. If a later annotation is drawn over an erased area, it remains visible unless a later eraser mask also clears it. Therefore eraser mask creation order participates in annotation-layer rendering order. In the first version, committing an eraser mask should place it at the end of the current annotation stack so it erases annotations that were visible at the time and any earlier annotations. New annotations drawn after that eraser mask render above it.

## Selection And Editing

Eraser masks themselves are not selectable or directly editable in the first version. Users can undo and redo eraser mask operations. Existing selected annotations remain selectable and editable according to existing tool rules after switching away from eraser mode.

If an annotation with local eraser masks applied is later moved or resized, the mask remains in overlay-local space rather than being attached to that annotation. This preserves "erase what was visible here" semantics and avoids complex per-object mask ownership in the first version.

## Undo And Redo

Object deletion and each committed eraser mask are single undoable actions.

- Undo after object deletion restores the deleted annotation.
- Undo after freehand local erasing removes the committed freehand mask.
- Undo after rectangular area erasing removes the committed rectangle mask.
- Redo reapplies the corresponding deletion or mask.
- Starting a new annotation or eraser operation after undo follows the repository's existing redo-clearing behavior.

No history entry is created for cancelled drafts, clicks that hit no annotation, or tiny invalid drags.

## Error Handling And Edge Cases

- Activating Eraser with no locked selection is ignored or exits cleanly without crashing.
- Presses on toolbar or panel UI do not begin erasing.
- Eraser masks outside the selected screenshot bounds may be previewed on overlay annotations, but export remains clipped to the selected screenshot bounds.
- If the annotation layer cannot be created, the app should fall back to drawing annotations normally rather than crashing.
- If an eraser cursor image cannot be generated, fall back to a crosshair or arrow cursor while keeping eraser behavior available.
- The eraser should not delete or clear the underlying screenshot, even when there are no annotations.
- Rectangular area erase with negative drag direction should standardize the rect and erase the intended area.

## Testing

Add focused mac XCTest coverage for:

- clicking the Eraser toolbar button enters eraser mode instead of showing a placeholder;
- eraser mode is mutually exclusive with existing annotation and eyedropper modes;
- the secondary toolbar exposes circular freehand mode, rectangular area mode, and `12 / 24 / 40px` sizes;
- `24px` circular freehand is the default;
- the circular eraser cursor is hollow and follows the selected size;
- switching size updates the cursor diameter;
- clicking an annotation deletes the topmost hit annotation;
- clicking empty screenshot area does nothing;
- dragging in circular freehand mode creates one eraser mask;
- rectangular area mode creates one rectangular eraser mask;
- tiny circular drags and tiny rectangles do not create mask entries;
- local masks erase annotation pixels but leave screenshot background pixels intact;
- masks affect shapes, arrows, brush paths, marker lines, mosaic redactions, text, number marks, and magnifiers;
- eraser mask order means newer annotations drawn after a mask remain visible above that mask;
- overlay preview and copy/save export render matching erased results;
- undo/redo restores object deletions and removes/reapplies eraser masks;
- existing annotation tools continue to behave as before.

Run the mac XCTest target after implementation:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Manual smoke check:

- start screenshot capture;
- select a screenshot region;
- activate Eraser and verify no placeholder appears;
- confirm the empty-circle cursor is visible and tracks `12 / 24 / 40px`;
- draw several annotation types and click-delete the topmost one;
- freehand erase across multiple annotation types and verify screenshot pixels remain;
- switch to rectangular area mode and erase a block of annotations;
- draw a new annotation after erasing and verify it appears above earlier eraser masks;
- undo and redo object deletion, freehand erasing, and rectangular erasing;
- copy/save and compare exported output to overlay behavior.

## Acceptance Criteria

- The Eraser toolbar entry is no longer a placeholder.
- Eraser mode supports object deletion by click.
- Eraser mode supports circular freehand local erasing with a hollow circle cursor.
- The hollow circle cursor size matches the selected eraser size.
- Eraser mode supports rectangular area erasing.
- Local erasing affects all annotation kinds visually.
- Local erasing never clears original screenshot pixels.
- New annotations drawn after an eraser mask remain visible above that mask.
- Object deletion and local erasing participate in undo/redo.
- Overlay preview and copy/save export are visually consistent.
