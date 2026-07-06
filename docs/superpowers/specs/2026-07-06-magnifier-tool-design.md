# xxsnap 放大镜工具设计

## Context

xxsnap mac overlay already has a visible main-toolbar entry and bundled assets for the magnifier tool, but the button still shows the unfinished placeholder behavior. Existing requirements define the minimum product behavior: local screenshot magnification, circular or rectangular magnifier regions, adjustable zoom and size, move/delete support, and preview/export consistency.

The overlay also already has mature patterns for annotation creation, selected-annotation outlines, resize handles, color swatches, stroke-width controls, copy/save export, and focused XCTest coverage. This design adds the first shippable magnifier annotation tool on macOS.

## Goals

- Turn the main-toolbar magnifier entry into an active annotation tool.
- Support circular and rectangular magnifier shapes, with circular as the default.
- Support fixed zoom levels: `1.5x`, `2x`, `3x`, and `4x`, with `2x` as the default.
- Create magnifiers by dragging out the magnifier region.
- Let users move, resize, delete, and restyle existing magnifier annotations.
- Let users change magnifier shape, zoom level, border color, and border width after selection.
- Render the magnified content from the original screenshot image only.
- Keep overlay preview and copy/save export visually consistent.

## Non-Goals

- Do not magnify existing annotations, mosaic redactions, text, number marks, or later drawings.
- Do not implement recursive or layer-order-based magnification in the first version.
- Do not add continuous zoom sliders or custom numeric zoom input.
- Do not add rotation, inner shadow controls, blur controls, or lens distortion effects.
- Do not change existing capture, clipboard, save, pin, text, number, mosaic, eyedropper, or shape behavior except for focused shared annotation infrastructure extensions.

## Chosen Approach

Add a dedicated `magnifier` annotation type instead of reusing shape annotations or the eyedropper sampler panel.

The magnifier has its own product semantics: shape, zoom level, source sampling from the original screenshot, selected-state editing, and export rendering. Keeping it as a dedicated annotation type avoids mixing magnification logic into ordinary rectangle/ellipse fill rendering and avoids confusing it with the eyedropper's non-exported sampling magnifier.

## Annotation Model

Each magnifier annotation stores:

- annotation kind: `magnifier`;
- local annotation rect;
- lens shape: `circle` or `rectangle`;
- zoom level: one of `1.5`, `2`, `3`, or `4`;
- border color;
- border width;
- any shared annotation style fields required by the existing toolbar infrastructure.

The annotation rect defines the visible lens bounds. For circular magnifiers, the rect may be non-square while dragging unless `Shift` is held, but the rendered lens uses the standardized rect as an oval. Holding `Shift` locks the rect to a square, producing a true circle.

## Toolbar Design

Clicking the main-toolbar magnifier button toggles magnifier creation mode. The button no longer shows the placeholder alert.

When magnifier creation mode is active, or when an existing magnifier is selected, the second toolbar shows:

1. Shape toggle:
   - circle, default;
   - rectangle.
2. Zoom level control:
   - `1.5x`;
   - `2x`, default;
   - `3x`;
   - `4x`.
3. Stroke width:
   - thin;
   - medium;
   - thick.
4. Color swatches and custom color control, reusing the existing palette behavior.

The toolbar should follow existing options-toolbar visual patterns and avoid introducing a separate popover unless the current options layout cannot fit the zoom choices cleanly.

## Creation Interaction

The user creates a magnifier by dragging:

1. Click the main-toolbar magnifier button.
2. Press inside the overlay to start the magnifier region.
3. Drag to the desired size.
4. Release to create the annotation.

Dragging can start inside or outside the locked screenshot selection, matching the more permissive behavior used by recent annotation tools such as number marks. Copy/save export remains cropped to the locked screenshot selection.

`Shift` constrains the draft:

- circle mode: lock to a square so the visible lens is a true circle;
- rectangle mode: lock to a square, matching existing shape-tool behavior.

Tiny or empty drags are ignored and do not create an annotation.

## Rendering

The magnifier renders in two steps:

1. Draw the magnified source content clipped to the lens shape.
2. Draw the border on top using the selected color and width.

The source content is always sampled from the original screenshot image, not from the current visible annotation composite. This keeps behavior predictable and avoids recursive magnification when magnifiers overlap or when annotations are drawn above the screenshot.

The lens rect is the destination. The source rect is centered on the same overlay point and scaled by the inverse zoom level. For example, a `160 x 160` lens at `2x` samples an `80 x 80` source region centered at the lens center, then draws it into the `160 x 160` destination.

If the source rect extends beyond the available original screenshot image, rendering clips to the available source content. It should not stretch edge pixels to fill missing source area.

Preview and export must use the same geometry, clipping, source sampling, interpolation, shape, and border rules.

## Selection And Editing

Selected magnifiers show the same kind of dashed selection outline and resize handles used by other editable geometry annotations.

All magnifier annotations support:

- selecting by clicking the lens body or border;
- moving by dragging the selected lens;
- resizing through existing resize handles;
- deleting via the delete handle or `Delete` / Forward Delete;
- changing shape through the options toolbar;
- changing zoom level through the options toolbar;
- changing border width through the options toolbar;
- changing border color through the options toolbar.

Changing shape, zoom, border width, or color while a magnifier is selected updates that annotation and also updates future magnifier creation defaults where that matches existing toolbar behavior.

## Data Flow

The overlay keeps magnifier annotations in the same annotation list as shapes, arrows, brush paths, marker lines, text, number marks, and mosaic annotations. Creation appends a new annotation. Selection and geometry editing reuse existing annotation-index state where possible.

Export maps local annotation geometry through the same overlay-to-export coordinate conversion path as existing annotations. Since the magnifier source is the original screenshot image, the renderer must preserve a way to sample the pre-annotation image during copy/save rendering.

Magnifier annotations are ordinary non-mosaic annotations for ordering purposes. They do not participate in mosaic redaction sampling, and mosaic logic should not treat them as redaction sources. When drawn above or below other annotations, only the magnifier border and lens output follow normal annotation list order; the content inside the lens still comes from the original screenshot.

## Error Handling And Edge Cases

- Creating with no locked selection is ignored.
- Clicks on main toolbar, options toolbar, popovers, or top-left measurement/pixel UI do not create magnifiers.
- Tiny drags below the existing usable annotation threshold are ignored.
- If source sampling reaches outside the original screenshot image, only the available source pixels are drawn.
- If the original screenshot image is unavailable, the magnifier annotation draws only its border and selection outline rather than crashing.
- If a stored zoom value is missing or invalid, fall back to `2x`.
- If a stored lens shape is missing or invalid, fall back to circle.
- Existing undo/redo behavior should include magnifier creation and deletion. Style edits should follow the repository's current annotation-history behavior for comparable tools.

## Testing

Add focused mac XCTest coverage for:

- clicking the magnifier toolbar button enters magnifier mode instead of showing a placeholder;
- the magnifier options toolbar exposes shape, zoom level, stroke width, and color controls;
- circular mode is default and zoom defaults to `2x`;
- shape can switch between circle and rectangle;
- zoom can switch between `1.5x`, `2x`, `3x`, and `4x`;
- drag creation produces a magnifier annotation;
- `Shift` constrains circular and rectangular drafts to square geometry;
- tiny drags do not create annotations;
- selected magnifiers can move, resize, delete, and update style;
- magnified content is sampled from the original screenshot and does not include existing arrows, text, number marks, mosaic redactions, or other annotations;
- source sampling clips at original image bounds without stretching edge pixels;
- overlay preview and copy/save export render matching magnifier output;
- existing annotation tools continue to behave as before.

Run the mac XCTest target after implementation:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Manual smoke check:

- start screenshot capture;
- select the magnifier tool;
- verify the second toolbar and default circle / `2x` state;
- drag-create circular and rectangular magnifiers;
- hold `Shift` while creating to verify square locking;
- move, resize, delete, recolor, and change zoom;
- draw another annotation before or after the magnifier and verify the lens still shows original screenshot pixels;
- copy/save and compare exported output to overlay behavior.

## Acceptance Criteria

- The magnifier tool is no longer a placeholder.
- The default magnifier is circular at `2x`.
- Users can switch between circular and rectangular lenses.
- Users can select zoom levels `1.5x`, `2x`, `3x`, and `4x`.
- Users can change border color and width.
- Users can drag-create, move, resize, and delete magnifiers.
- The lens magnifies only original screenshot pixels.
- Preview and copy/save export are visually consistent.
- Existing annotation tools continue to behave as before.
