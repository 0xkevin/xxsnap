# Toolbar Shortcuts Design

## Goal

Add consistent keyboard shortcuts to the screenshot and pinned-image editing toolbars, expose the same shortcuts in tooltips, and add standard shortcuts to the pinned-image context menu without changing existing annotation behavior or rendering performance.

## Shortcut Map

| Action | Shortcut |
| --- | --- |
| Shape | S |
| Arrow line | A |
| Pen | B |
| Highlighter | H |
| Eyedropper / measurement | P |
| Mosaic | M |
| Text | T |
| Number | N |
| Magnifier | G |
| Eraser | E |
| Undo | Command-Z |
| Redo | Command-Shift-Z |
| Exit screenshot | Escape |
| Pin image | Command-1 |
| Save | Command-S |
| Copy to clipboard | Command-C |
| Finish pinned-image editing | Escape |

Scrolling capture remains without a shortcut until the feature is implemented.

Letter shortcuts are case-insensitive. They apply only when Command, Control, and Option are not pressed. Active text entry and input-method composition keep ownership of ordinary letter keys so typing never switches tools.

## Architecture

Use one shortcut descriptor registry as the source of truth for toolbar key matching and tooltip presentation. The descriptor records the key and modifiers plus the visual representation required by the tooltip. Existing toolbar actions remain the execution path; shortcuts invoke the same action methods as mouse clicks.

The tooltip renderer supports both plain letter shortcuts and modifier shortcuts. Plain keys render as text, for example `Shape (S)`. Command shortcuts continue using the bundled pure-white Command SVG. Redo renders the Command SVG followed by `Shift-Z` using the existing compact tooltip layout.

## Context Rules

- In the normal screenshot overlay, Escape cancels and exits capture.
- In the pinned-image editing overlay, Escape completes the current edit, bakes annotations, and hides the toolbar.
- Command-C and Command-S use the existing copy/save completion paths in both screenshot and pinned-image editing contexts.
- Command-1 pins only when the pin action is available.
- Disabled undo and redo actions consume their shortcuts without mutating state.

## Pinned-Image Menu

The context menu uses these labels and key equivalents:

| Menu item | Shortcut |
| --- | --- |
| Copy image | Command-C |
| Save image | Command-S |
| Close | Command-W |
| Close all pinned images | Command-Shift-W |

The previous `Save image...` label becomes `Save image`. These shortcuts work whether the editing toolbar is visible or hidden. Closing all pinned images affects pinned-image windows only.

## Testing

Add focused tests for:

- Every toolbar shortcut and its selected/action state.
- Uppercase and lowercase letter equivalence.
- Text editor and input-method ownership of ordinary letters.
- Context-specific Escape behavior.
- Tooltip titles and shortcut rendering descriptors.
- Pinned-image menu labels, key equivalents, and modifier masks.
- Pinned-image copy, save, close, and close-all dispatch with the toolbar visible and hidden.

No full toolbar layout or rendering architecture changes are required.
