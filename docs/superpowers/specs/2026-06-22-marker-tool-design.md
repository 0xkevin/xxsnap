# Marker Tool Design

## Context

xxsnap mac already has rectangle/ellipse, arrow line, and brush annotation tools in the screenshot overlay. The main toolbar still shows the `marker` button as an unfinished placeholder. This design turns that button into an independent highlighter-style annotation tool.

The marker tool is mac-overlay scoped for this iteration. It should follow the existing `SelectionOverlayWindow`, `SelectionToolbarState`, and `CaptureAnnotationRenderer` patterns, and it should not change the behavior of existing shape, arrow line, brush, copy, save, undo, or redo flows.

## User Goal

Users can click the `标记` toolbar button and drag across a screenshot to create a straight highlighter mark. The mark should feel like a soft highlighter stroke: visually light, rounded, editable after drawing, and readable over screenshot content.

## Tool Activation

- Clicking the `marker` toolbar button activates marker mode instead of showing `标记功能开发中。`
- Marker mode is mutually exclusive with rectangle/ellipse, arrow line, and brush modes.
- The marker toolbar button shows selected state while marker mode is active.
- Switching away from marker mode clears marker draft state and hides marker-only option UI.
- The tooltip remains `标记`.

## Cursor

- Inside the selected screenshot region, marker mode uses a circular dot cursor.
- The cursor hotspot is the circle center.
- The cursor dot fill follows the current marker color.
- The cursor uses a soft white outer ring instead of a black border.
- Outside the selected screenshot region and over toolbar or option panels, the cursor falls back to the normal arrow.

## Default Style

- Default marker color: `#FF7F03`.
- Default marker width: `18`.
- Available marker widths: `14`, `18`, `22`.
- Marker opacity is fixed at `65%`.
- Marker line cap and line join are rounded.
- Marker line style is always solid; dashed or sketch stroke patterns are not shown for marker mode.

If the user changes marker color or width, subsequent marker annotations should reuse the current marker settings. The fixed opacity remains `65%`.

## Drawing Behavior

- Pressing the mouse inside the selection starts a marker draft at the press point.
- Dragging previews one straight highlighter line from the start point to the current pointer.
- Releasing the mouse commits the marker annotation if the line length is at least `8` points.
- Default dragging uses a free-angle straight line.
- Holding `Shift` while dragging snaps the end point to the nearest horizontal, vertical, or 45-degree direction relative to the start point.
- The stored marker coordinates are relative to the selected screenshot rect, matching existing annotations.
- Marker strokes may be previewed beyond the selected rect while drawing, but exported copy/save output remains clipped by the selected snapshot image bounds.

## Editing Behavior

- A committed marker can be selected by clicking near its stroke.
- Selected marker annotations can be moved as a whole.
- Selected marker annotations can have their width and color changed through the marker options toolbar.
- Selected marker annotations can be deleted with the existing delete-key behavior.
- Marker annotations do not expose endpoint handles, curve controls, arrow controls, rotation handles, fill controls, or stroke pattern controls.
- Undo and redo should include marker creation, movement, style updates, and deletion using the existing annotation history behavior.

## Options Toolbar

Marker mode gets its own options toolbar mode. It shows only:

- width buttons for `14`, `18`, and `22`;
- palette color swatches;
- custom color picker.

It hides:

- fill toggle;
- rectangle/ellipse selectors;
- corner radius panel;
- start and end arrow type controls;
- stroke style menu.

Selecting an existing marker switches the options toolbar to marker mode. Selecting an existing shape, arrow line, or brush keeps using that annotation type's existing toolbar mode.

## Data Model

Add an independent marker annotation type rather than reusing brush or arrow line internals.

- Add `CaptureAnnotationKind.marker`.
- Add a lightweight marker model with `start` and `end` points.
- Store marker data on `CaptureAnnotation` in the same style as `arrowLine` and `brushPath`.
- Keep marker style color and width in `CaptureAnnotationStyle`.
- Keep marker opacity as a marker rendering rule, not a generic style property, so existing tools are not affected.

This avoids inheriting brush path rotation behavior or arrow line curve and arrowhead behavior.

## Rendering

Overlay rendering and final copy/save rendering should use the same visual rule:

- straight line from marker start to marker end;
- stroke width from marker style;
- stroke color with fixed `65%` opacity;
- rounded line cap and join;
- no dash pattern.

Renderer output must preserve the original image dimensions.

## Hit Testing And Movement

- Hit testing uses distance from pointer to the marker segment.
- The hit outset should account for marker width, with a small minimum tolerance so narrow markers remain easy to select.
- Moving a marker translates both start and end points by the drag delta.
- Selection outline, if shown, should not imply resize handles; a subtle selected stroke or existing selection affordance is enough.

## Testing

Add focused tests for:

- marker button activation no longer shows the placeholder path;
- marker default style is `#FF7F03`, width `18`, fixed opacity `65%`;
- marker options toolbar shows only width and color controls;
- marker drag creates a straight marker annotation;
- `Shift` dragging snaps to horizontal, vertical, or 45-degree directions;
- short marker drags below `8` points are ignored;
- selected marker can move without changing size or style;
- selected marker color and width updates apply to that marker;
- delete key removes the selected marker;
- renderer draws a semi-transparent rounded marker line without changing image dimensions.

Run the mac XCTest target when possible:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

If full tests are blocked by the existing screen-capture environment-sensitive test, run focused marker-related tests and the mac app build, then report the exact blocker.
