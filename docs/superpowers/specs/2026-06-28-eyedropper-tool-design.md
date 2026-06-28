# Eyedropper Tool Design

## Context

xxsnap mac already has a default color sampler in the screenshot overlay. That sampler appears only when no annotation tool is active and no annotations exist, which makes it useful for early inspection but awkward once the user has started marking up the screenshot.

This design adds an explicit eyedropper button to the main capture toolbar and a global mouse-wheel resize shortcut for the locked screenshot selection. The work is mac-overlay scoped for this iteration and should follow the existing `SelectionOverlayWindow` and `SelectionToolbarState` patterns. It should not change snapshot export, annotation undo/redo, or the existing copy/save actions.

## User Goal

Users need a fast way to inspect and copy colors while editing a selected screenshot. They should be able to click an eyedropper button near the Mosaic tool, hover anywhere inside the selected screenshot region, and copy the visible color under the pointer.

The sampled color should reflect what the user currently sees in the screenshot region. If the user has drawn a rectangle, brush stroke, marker, arrow, or mosaic redaction, the eyedropper samples that visible result. If they want the original color behind a redaction or annotation, they can move or delete that annotation first.

Users should also be able to quickly refine the screenshot selection size after it is locked, regardless of the currently active tool. Mouse-wheel zooming gives them a fast way to expand or shrink the selected area without aiming for resize handles.

## Toolbar Entry

- Add a main toolbar button immediately to the left of `mosaic`.
- Use the workspace asset `/Users/kevin/Projects/open-source/Snipory/eyedropper.svg`.
- Bundle the asset for the mac app so the toolbar and cursor can load it from app resources.
- The button tooltip is `取色`.
- The button shows selected state while explicit eyedropper mode is active.
- Clicking the button toggles explicit eyedropper mode on or off.

## Tool Activation

- Eyedropper mode is mutually exclusive with rectangle/ellipse, arrow line, brush, marker, and mosaic modes.
- Activating eyedropper mode clears any active annotation draft and hides annotation options UI.
- Switching to any annotation tool exits eyedropper mode.
- Exiting eyedropper mode returns to the normal no-tool state.
- Eyedropper mode does not create annotations and does not participate in undo/redo history.

## Sampling Region

- Explicit eyedropper sampling is limited to the locked screenshot selection rectangle.
- Inside the selection, moving the pointer updates the sampler preview and sampled color.
- Outside the selection, over toolbars, or over option panels, the sampler hides and no new color is sampled.
- Pressing the copy shortcut while no valid in-selection sample exists is ignored.
- The existing default no-tool sampler keeps its current behavior and constraints.

## Sampling Source

Default no-tool sampling continues to sample the frozen original background image.

Explicit eyedropper sampling uses the current visible selected-screenshot result:

- the original selected screenshot image;
- committed annotations such as rectangle, ellipse, arrow, brush, and marker;
- committed mosaic redactions;
- current style effects that are already visible in the overlay preview.

The implementation may render or cache a selection-sized composite image for sampling, but the sampled result must match the visible committed screenshot content. Draft annotations are out of scope for this iteration because eyedropper mode cannot draw at the same time.

## Cursor

- Inside the selected screenshot region, eyedropper mode uses the same eyedropper icon shape as `eyedropper.svg`.
- The cursor hotspot is the tip of the eyedropper.
- Outside the selected screenshot region and over toolbar or option panels, the cursor falls back to the normal arrow.
- If the SVG cannot be loaded, the cursor falls back to the standard arrow instead of blocking the capture workflow.

## Sampler Preview

Eyedropper mode reuses the existing color sampler panel:

- magnified pixel grid;
- sampled color swatch;
- current color value;
- copy hint;
- copy success state;
- `Shift` format toggle between HEX and RGB.

The panel should stay visually consistent with the current default sampler. The only behavior difference is the explicit tool's activation rule and sampling source.

## Clipboard Semantics

Keep screenshot copy and color copy separate:

- In eyedropper mode, pressing `C` copies only the current color text in the selected format.
- Pressing `Shift` toggles the sampler format between HEX and RGB, matching the existing sampler behavior.
- The toolbar copy button and `Command+C` continue to copy only the current screenshot result.
- The system clipboard follows the last explicit copy action. Copying a color replaces prior clipboard contents; copying a screenshot replaces prior color text.

This avoids ambiguous multi-type clipboard results where some destination apps paste text and others paste the image.

## Hit Testing

When eyedropper mode is active:

- mouse movement updates sampling state;
- mouse down and drag inside the selection update the sample point but do not select, move, resize, or create annotations;
- mouse down and drag outside the selection do not move the selection;
- toolbar and panel clicks keep their existing behavior so users can switch tools or run copy/save/cancel actions.

## Global Selection Wheel Zoom

Mouse-wheel zoom applies to the locked screenshot selection across tools, not only in eyedropper mode.

- When a screenshot selection is locked, scrolling the mouse wheel resizes the selection.
- Wheel zoom does not switch the active tool and does not clear selected annotations.
- Wheel zoom is ignored while the overlay is selecting an initial region, drawing an annotation, moving/resizing/rotating an annotation, moving/resizing the selection through drag handles, dragging the toolbar, or editing Mosaic values.
- Wheel zoom is ignored when the pointer is over the main toolbar, options toolbar, popovers, panels, or other controls.
- Scrolling up expands the selection; scrolling down shrinks it.
- If the pointer is inside the locked selection, scaling uses the pointer as the anchor point.
- If the pointer is outside the locked selection but not over a control, scaling uses the selection center as the anchor point.
- The maximum selection size is the full `NSScreen.frame` of the screen containing the current selection center, including menu bar and Dock regions.
- The minimum selection size is `64 x 64` points. This is large enough to remain visible and recoverable while still supporting precise color and UI sampling.
- Existing annotations should remap with the selection, reusing the current selection-resize behavior so their relative positions and sizes remain visually aligned.
- Wheel zoom is a selection adjustment, not an annotation edit. It does not add an annotation undo/redo entry.

## Testing

Add focused mac tests for:

- toolbar button order places eyedropper immediately before mosaic;
- `eyedropper.svg` is bundled and readable by the mac target;
- clicking the eyedropper button toggles explicit eyedropper mode and selected state;
- activating another tool exits eyedropper mode;
- explicit eyedropper mode can show and copy a color even when annotations exist;
- explicit eyedropper mode hides outside the locked selection and does not sample outside it;
- eyedropper mode does not move the selection or annotations on mouse down/drag;
- `C` in eyedropper mode copies only color text;
- `Command+C` still copies the screenshot result;
- sampling reflects a committed annotation color rather than the original background at that point;
- wheel zoom expands and shrinks the locked selection in any active tool state where no interaction is in progress;
- wheel zoom clamps to full `NSScreen.frame` maximum and `64 x 64` point minimum;
- wheel zoom uses the pointer anchor inside the selection and the selection-center anchor outside it;
- wheel zoom is ignored over toolbar/options/panels and during drawing, moving, resizing, rotating, toolbar drag, or Mosaic value editing;
- existing annotations remap with the selection during wheel zoom.

Run the mac XCTest target when possible:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

If the full XCTest target is blocked by signing, permissions, or environment-sensitive screen capture tests, run the nearest focused tests and the mac app build, then report the exact blocker.
