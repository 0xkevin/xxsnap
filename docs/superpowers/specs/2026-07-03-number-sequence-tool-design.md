# xxsnap 序号工具设计

## Context

xxsnap already has a visible main-toolbar entry and bundled icon assets for the number sequence tool, but the feature is still a placeholder. Existing requirements say the tool must support incremental numbering, move, delete, reorder rules, color, and size. The capture overlay also has mature patterns for text editing, selection outlines, color palettes, size dropdowns, export rendering, and selected-annotation handles.

This design covers the first shippable mac implementation of the number sequence tool and its companion symbol marks: numbered circles, standalone check marks, and standalone cross marks.

## Goals

- Turn the main-toolbar number entry into an active annotation tool.
- Remove the small bottom-right triangle indicator from the existing main-toolbar number icon.
- Show a second options toolbar when the number tool is active or a number/symbol mark is selected.
- Support three mark types from the first options control:
  - numbered circle, default;
  - green check mark;
  - red cross mark.
- Support font-size-based scaling from `3...72`.
- Support color changes for marks on the screenshot canvas.
- Allow creating marks both inside and outside the locked screenshot selection.
- Support moving, deleting, resizing, and adjacent reordering for numbered marks.
- Keep preview and copy/save export visually consistent.

## Non-Goals

- Do not implement freeform text editing inside a number mark.
- Do not support arbitrary custom icon uploads.
- Do not support drag-and-drop reordering across non-adjacent numbers in the first version.
- Do not make check/cross marks participate in the numeric sequence.
- Do not change existing capture, clipboard, save, pin, text, mosaic, or shape behavior except where the shared toolbar/annotation infrastructure needs a focused extension.

## Chosen Approach

Add a dedicated `numberSequence` annotation type instead of reusing `text`.

The mark has its own product semantics, selected-state controls, cursor behavior, reorder logic, and export renderer. A dedicated type keeps automatic numbering and adjacent swaps separate from normal text annotations.

Check and cross marks are modeled as sibling variants of the same number-sequence tool. They share the same toolbar, color, size, move, delete, resize, cursor, preview, and export behavior, but they do not consume numeric sequence positions.

## Toolbar Design

The main toolbar keeps the existing number icon shape, but the icon is always black. It does not change color when the user changes the mark color. The color control affects only marks on the screenshot canvas and the creation cursor preview.

Clicking the main-toolbar number button toggles number creation mode. When active, the second toolbar appears with this layout:

1. Mark type dropdown:
   - numbered circle icon, default;
   - green check icon;
   - red cross icon.
2. Separator.
3. Font size dropdown, values `3...72`.
4. Separator.
5. Color swatches/custom color control, using the existing palette behavior.

Default colors:

- numbered circle: current annotation color, falling back to the first palette color;
- check mark: green;
- cross mark: red.

After selecting check or cross, the default color can still be replaced through the color control.

The SVG source for the check mark is:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="green" class="bi bi-check2" viewBox="0 0 16 16">
  <path d="M13.854 3.646a.5.5 0 0 1 0 .708l-7 7a.5.5 0 0 1-.708 0l-3.5-3.5a.5.5 0 1 1 .708-.708L6.5 10.293l6.646-6.647a.5.5 0 0 1 .708 0"/>
</svg>
```

The SVG source for the cross mark is:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="red" class="bi bi-x-lg" viewBox="0 0 16 16">
  <path d="M2.146 2.854a.5.5 0 1 1 .708-.708L8 7.293l5.146-5.147a.5.5 0 0 1 .708.708L8.707 8l5.147 5.146a.5.5 0 0 1-.708.708L8 8.707l-5.146 5.147a.5.5 0 0 1-.708-.708L7.293 8z"/>
</svg>
```

## Creation Interaction

When the number tool is active, the mouse cursor becomes a mark cursor:

- numbered circle mode: cursor shows the current number icon;
- check mode: cursor shows a standalone check mark with no background circle;
- cross mode: cursor shows a standalone cross mark with no background circle.

The cursor preview uses the current mark color and current size. If the toolbar icon is black, the cursor can still be colored.

Clicking on the overlay creates the selected mark type at that point. Creation is allowed inside the locked screenshot selection and outside it. The first version keeps the existing export crop rules: marks outside the screenshot selection are visible in the overlay but are clipped from copy/save output.

When the pointer moves over the main toolbar, the second toolbar, the top-left pixel-value display, or the top-left size/aspect-ratio controls, the cursor returns to the normal pointer. This prevents the colored mark cursor from obscuring controls.

## Mark Model

Each number-sequence annotation stores:

- stable annotation id;
- mark type: `number`, `check`, or `cross`;
- local overlay position and bounding rect;
- style color;
- font size, clamped to `3...72`;
- creation order for numeric marks.

The displayed number is derived from numeric mark order, not stored as permanent display text. This keeps delete and reorder operations deterministic.

Check and cross marks do not affect numeric ordering. For example, if the overlay has numeric marks `1, 2`, one check mark, and numeric mark `3`, deleting numeric mark `2` makes the numeric marks display `1, 2`; the check mark remains unchanged.

## Size and Rendering

Font size controls the glyph size and also scales the surrounding circle. The circle diameter is derived from the font size plus padding, with a minimum hit target so small marks remain selectable. Resizing through the bottom-right handle changes the font size and clamps it to `3...72`.

Numbered marks render as a filled circle in the selected color with a centered number. The inner number color should be readable: use white on dark or saturated fills, and switch to a dark text color on very light fills.

Check and cross marks render as standalone glyphs with no background circle. Their default glyph colors are green and red, but user color changes replace those glyph colors.

Preview and export must share the same geometry, font sizing, colors, and foreground contrast rule.

## Selection, Handles, and Editing

Selected number/symbol marks show a dashed blue selection frame around the mark.

All mark types support:

- drag the mark body to move it;
- right-top blue `x` handle to delete;
- right-bottom blue circular handle to resize within the `3...72` font size range;
- Delete / Forward Delete key to delete.

Numeric marks additionally show:

- left-top `+` handle;
- left-bottom `-` handle.

The handles swap the selected numeric mark with its adjacent numeric neighbor:

- `+` swaps with the next numeric mark;
- `-` swaps with the previous numeric mark;
- the first numeric mark disables `-`;
- the last numeric mark disables `+`;
- middle numeric marks enable both.

Example: if numeric marks display `1, 2, 3, 4, 5, 6`, selecting `5` and clicking `+` swaps it with `6`, so the selected mark displays `6` and the adjacent mark displays `5`. Selecting `2` and clicking `+` swaps it with `3`. Only one adjacent swap happens per click.

When a page has 10 numeric marks, numeric mark `10` has only `-` enabled. If a new numeric mark `11` is added, the previous `10` becomes a middle mark and both `+` and `-` become enabled.

Check and cross marks do not show `+` or `-`, because they do not participate in numeric ordering.

## Cursor States

- Creation over drawable overlay: colored mark cursor for the active mark type.
- Hover over selected mark body: cross-shaped move cursor.
- Drag selected mark body: cross-shaped move cursor.
- Hover or drag bottom-right resize handle: diagonal resize cursor.
- Hover over delete, `+`, or `-` handles: normal pointer cursor.
- Hover over any toolbar, pixel-value display, size display, or aspect-ratio controls: normal pointer cursor.

## Data Flow

The overlay keeps number-sequence annotations in the same annotation list as existing shapes, arrows, text, marker, and mosaic annotations. Creation appends a new annotation. Numeric display values are calculated from the ordered subset of `numberSequence` annotations with mark type `number`.

Deleting a numeric mark removes it from the annotation list and recalculates display numbers for remaining numeric marks. Deleting a check or cross mark removes only that mark.

Adjacent swaps update numeric ordering metadata for the two affected numeric marks and then recalculate display numbers. Other annotations keep their order and geometry.

Export maps overlay/local annotation geometry through the same coordinate conversion path as existing annotations, then clips to the exported screenshot bounds through the existing export behavior.

## Error Handling and Edge Cases

- Clicks on toolbars or top-left measurement/pixel UI do not create marks.
- Creating with no locked selection is ignored.
- If size input or resizing produces a value below `3`, clamp to `3`.
- If size input or resizing produces a value above `72`, clamp to `72`.
- If a selected numeric mark has no previous or next numeric neighbor, the unavailable reorder handle is disabled and does nothing.
- If the user changes mark type while a numeric mark is selected, convert that annotation to the new mark type and recalculate numeric order.
- If the user changes color while a mark is selected, apply it to that mark and update future creation style.

## Testing

Add focused mac XCTest coverage for:

- main-toolbar number icon no longer shows the bottom-right triangle and remains black regardless of selected color;
- clicking number tool shows the second toolbar with mark type dropdown, size dropdown `3...72`, separators, and color controls;
- type dropdown switches between number, check, and cross;
- check defaults to green and cross defaults to red, while color controls can override both;
- creation cursor changes to the current mark type and color;
- cursor returns to normal pointer over toolbars and top-left measurement/pixel UI;
- marks can be created inside and outside the locked selection;
- numeric marks auto-increment and delete-triggered renumbering is continuous;
- check/cross marks do not affect numeric order;
- selected marks show dashed frame, delete handle, and resize handle;
- numeric marks show `+`/`-` handles with correct enabled/disabled states;
- `+` and `-` swap only adjacent numeric marks;
- moving a mark preserves numeric order;
- resizing clamps font size to `3...72`;
- preview and export render numbered circles plus standalone check/cross marks with matching size, color, contrast, and clipping behavior.

Run the mac test target after implementation:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Manual smoke check:

- start screenshot capture;
- select the number tool;
- verify the second toolbar and colored creation cursor;
- create numeric marks inside and outside the selection;
- create check and cross marks;
- move, delete, resize, and reorder numeric marks;
- verify cursor restoration over toolbars and top-left UI;
- copy/save and compare exported output to overlay behavior.

## Acceptance Criteria

- The number tool is no longer a placeholder.
- The main-toolbar number icon is black and has no bottom-right triangle marker.
- The second toolbar matches the approved layout and supports mark type, size, and color controls.
- Number/check/cross creation cursors match active type and color, and return to normal pointer over controls.
- Numeric marks auto-number, delete-renumber, and adjacent-swap correctly.
- Check/cross marks render without background circles and share size, color, move, delete, resize, preview, and export behavior without changing numeric order.
- Marks can be created outside the screenshot selection in the overlay.
- Existing annotation tools continue to behave as before.
