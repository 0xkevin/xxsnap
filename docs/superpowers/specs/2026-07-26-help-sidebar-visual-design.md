# Help Sidebar Visual Design

## Goal

Make the Help window easier to scan by removing radio-button indicators from
the chapter navigation and giving the navigation and reading areas visibly
different backgrounds.

## Confirmed Appearance

- The left sidebar keeps the system window background color.
- Chapter entries are borderless text buttons with no radio circle.
- The selected chapter shows a 3-point vertical system-accent-color bar on its
  left edge.
- The selected chapter text uses a semibold system font and remains the normal
  label color.
- Unselected chapter text uses the regular system font and normal label color.
- The right content area, including its scroll view and document view, uses a
  solid white background.
- The existing divider between the sidebar and content area remains.

## Interaction

- Clicking a chapter switches the right-side content immediately.
- Exactly one chapter is visually selected at a time.
- Clicking the current chapter keeps it selected and does not clear the page.
- Existing chapter scroll-position restoration remains unchanged.

## Accessibility

- The navigation container is exposed as a navigation group rather than a
  radio group.
- Each chapter entry is exposed as a button.
- The active chapter continues to expose its selected state without using
  radio-button semantics.

## Implementation Scope

- Update the sidebar button construction and selected-state rendering in
  `HelpWindowController`.
- Give `HelpContentView`, its scroll view, and its document view an explicit
  white background.
- Replace radio-specific assertions with button and visual-state assertions.
- Keep help content, image preview behavior, window sizing, chapter order, and
  localization unchanged.

## Verification

- Add focused tests for borderless navigation buttons, the accent selection
  bar, selected text weight, and white content background.
- Run `HelpManualTests` and `AppSettingsTests`.
- Build the Debug app and restart the local XxSnap process.
