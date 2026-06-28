# Arrow Line Tool Design

## Context

xxsnap mac currently has the first annotation tool implemented for rectangle and ellipse shapes. The second main toolbar button is already represented by the `polyline` tool and uses the `arrow-line` icon, but its tooltip and behavior still act as unfinished functionality.

This design implements the second tool as the arrow line annotation tool in `xxsnap/platforms/mac`. The existing Swift/AppKit overlay remains the UI boundary for this change. The legacy Qt project is a reference only and is not modified.

## User Goal

Users can activate the second toolbar button, see arrow-line-specific options, draw an arrow line on the selected screenshot area by dragging from mouse down to mouse up, and edit the created arrow line afterward. The exported copied/saved image must include the same arrow line appearance shown in the overlay.

## Tool Activation And Toolbar Rules

- Change the second toolbar button tooltip from `直线` to `箭头线`.
- Activating the rectangle tool and activating the arrow line tool are mutually exclusive.
- Reuse the same options toolbar container, but switch visible controls by active tool.
- Shared controls for rectangle/ellipse and arrow line:
  - three stroke width buttons;
  - stroke pattern dropdown;
  - palette swatches and custom color picker.
- Rectangle/ellipse active state:
  - show fill toggle;
  - show rectangle and ellipse selectors;
  - show the rectangle corner-radius panel when its disclosure is clicked;
  - hide start arrow type and end arrow type controls.
- Arrow line active state:
  - hide fill toggle;
  - hide rectangle and ellipse selectors;
  - hide corner-radius panel and shape-specific controls;
  - show start arrow type and end arrow type dropdowns immediately after the stroke pattern dropdown;
  - place a separator to the right of the end arrow type dropdown before the color swatches.
- Selecting an existing annotation switches the options toolbar to that annotation's tool type so shape-only controls are not shown for arrow lines and arrow controls are not shown for shapes.

## Arrow Type Options

Both start and end arrow type dropdowns contain the same six options:

1. `没有箭头的实线`
2. `有燕尾的箭头线`
3. `普通箭头线`
4. `由细到粗的实心箭头线`
5. `由细到粗的空心箭头线`
6. `手绘箭头线`

The start arrow type preview points left. The end arrow type preview points right. The dropdown fields should be compact and sit next to each other.

Default arrow line style:

- stroke width: `2`;
- stroke color and fill color: first palette color;
- stroke pattern: preserve the current pattern unless it has not been changed;
- start arrow type: `没有箭头的实线`;
- end arrow type: `普通箭头线`.

## Drawing And Editing Behavior

- Drawing starts when the mouse is pressed in the screenshot overlay and ends when the mouse is released.
- The arrow line stores:
  - start point;
  - end point;
  - one control point;
  - style;
  - start arrow type;
  - end arrow type.
- A newly drawn arrow line creates its control point at the midpoint between start and end, so it initially appears straight.
- Dragging the control point bends the line into a quadratic curve.
- Hovering or mouse-down near the curve body selects/moves the whole arrow line.
- Hovering or mouse-down near either endpoint allows shortening or lengthening by dragging that endpoint.
- Hovering or mouse-down on the control point allows changing the curve.
- Existing stroke width, stroke pattern, and color controls update the selected arrow line.
- Stroke pattern choices apply to arrow lines, including dashed and sketch styles.

## Rendering

Overlay rendering and final copy/save rendering both draw the arrow line from the same model:

- straight line when the control point is at the midpoint;
- quadratic curve when the control point is dragged away;
- optional start arrowhead pointing along the curve toward the start;
- optional end arrowhead pointing along the curve toward the end;
- line dash and sketch style matching the selected stroke pattern;
- stroke width and color matching the options toolbar.

For this mac-first iteration, rendering may live in the existing Swift renderer. The shared C++ core can be expanded later after the mac interaction model stabilizes.

## Testing

Add focused Swift tests for:

- tooltip title for the second tool is `箭头线`;
- options toolbar layout switches between shape controls and arrow line controls;
- arrow type menus hit-test all six items;
- default arrow line style uses the first palette color and expected start/end arrow types;
- arrow line hit testing distinguishes body, start endpoint, end endpoint, and control point;
- renderer changes image pixels when drawing an arrow line.

Run the mac XCTest target when available. If local signing or Xcode configuration blocks full tests, run the closest compile or test command and report the blocker.
