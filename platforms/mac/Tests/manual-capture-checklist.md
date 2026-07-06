# Manual Capture MVP Checklist

Use this checklist to verify the native macOS screenshot MVP after building `xxsnap`.

## Current MVP expectation

- [ ] Launch the app and choose `Capture` from the status item menu.
- [ ] If permission is already granted, a selection overlay appears.

## Permission flow

- [ ] On a machine without Screen Recording permission, choosing `Capture` requests permission once.
- [ ] Repeating `Capture` in the same app session does not bounce the permission prompt repeatedly once a request has already been made.
- [ ] After granting permission and relaunching if needed, choosing `Capture` opens the selection overlay.

## Overlay interaction

- [ ] The overlay covers the full desktop area and allows click-drag-release selection.
- [ ] The overlay dismisses immediately on mouse up before async capture work begins.
- [ ] A tiny or empty drag does not crash the app.

## Capture correctness

- [ ] Selecting an area that overlaps another app window captures the real window contents, not wallpaper.
- [ ] Capturing a region on the current display returns only the selected rectangle.
- [ ] If multiple displays are connected, selecting on a non-primary display captures content from that display instead of the primary desktop.
- [ ] The app excludes its own UI from the captured image.

## Output flow

- [ ] A successful capture copies the image to the system clipboard.
- [ ] The current build has a save helper available in code for PNG export once UI wiring is added.

## Magnifier tool smoke check

- [ ] Start capture and lock a screenshot selection.
- [ ] Click the magnifier toolbar button and verify the second toolbar appears.
- [ ] Verify default shape is circle and default zoom is `2x`.
- [ ] Drag-create a circular magnifier.
- [ ] Hold `Shift` while dragging and verify the lens is square/circular.
- [ ] Switch to rectangle and create a rectangular magnifier.
- [ ] Change zoom to `1.5x`, `3x`, and `4x`.
- [ ] Change border color and width.
- [ ] Move, resize, and delete a selected magnifier.
- [ ] Draw text or an arrow over the screenshot and verify the magnifier still shows original screenshot pixels.
- [ ] Copy and save, then compare exported output with overlay preview.

## Notes

- Task 6 wires clipboard output and prepares save behavior for later UI exposure.
