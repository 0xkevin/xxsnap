# Manual Capture Acceptance Checklist

Use this checklist after building the exact Debug app from `build/xcode-derived`. Record the macOS version, display arrangement and scale, input device, target app/version, result (`通过` / `失败` / `待人工`) and saved-output location for every executed row. A row is not passed by automated XCTest alone.

## Basic capture regression

- [ ] With Screen Recording permission already granted, launch the app, choose `Capture`, select a region, and confirm the overlay locks the selection.
- [ ] Without Screen Recording permission, confirm the app requests permission once and guides the user to relaunch; repeated capture attempts in the same process do not repeatedly prompt.
- [ ] Move and resize a locked region, including a tiny/empty drag, and confirm there is no crash.
- [ ] Capture another app window and confirm the selected display/rectangle is captured, xxsnap UI is excluded, and a non-primary display does not capture the primary desktop.
- [ ] Draw a magnifier, change its shape, scale, border and size, then confirm copy/save match the overlay and the lens still samples the original screenshot pixels.

## Scroll-capture test setup

- [ ] Use a Trial or Pro license so the Scroll Capture button is visible; record the active plan.
- [ ] Record whether xxsnap has macOS Accessibility permission. Finish Scroll Capture/Cancel buttons are the permission-independent path; target-app-frontmost keyboard checks require that permission.
- [ ] Prepare four deterministic targets: a long Safari page without a fixed header, the same or equivalent page with a fixed header, a long Chrome page without a fixed header, and the same or equivalent page with a fixed header.
- [ ] Prepare an ordinary long document in Preview and, where available, a long plain-text document in a text editor. Include numbered rows or other unique seam markers.
- [ ] For browser targets and Preview D1/D2, begin at the top. For direction-lock rows D3-D6, begin in the middle as specified. Lock a region wholly inside the scrollable content, add a visible first-screen annotation, and start Scroll Capture.
- [ ] Confirm the original toolbar remains visible and passive during collection; only Finish Scroll Capture and Cancel are actionable, and the target app continues receiving scroll input.

## Browser and document matrix

| ID | Target | Fixed header | Input | Expected checks | Result / evidence |
| --- | --- | --- | --- | --- | --- |
| B1 | Safari long page | No | Mouse wheel | Seams stay ordered; each row appears once; output reaches the final viewport. | 待人工 |
| B2 | Safari long page | Yes | Trackpad with inertia | Header is not repeated; body seams stay ordered; inertial tail frames are not duplicated. | 待人工 |
| B3 | Chrome long page | No | Trackpad with inertia | Seams stay ordered; exact repeats are discarded; preview follows the tail. | 待人工 |
| B4 | Chrome long page | Yes | Mouse wheel | Header is not repeated; body content is complete; scrollbar handling follows the confidence rules below. | 待人工 |
| D1 | The same Preview long document | N/A | Mouse wheel | Page/text order is preserved, with no missing or repeated strip at page boundaries. | 待人工（未执行物理鼠标） |
| D2 | The same Preview long document | N/A | Trackpad with inertia | The mouse result is reproducible with trackpad inertia; the final page is neither duplicated nor truncated. | 待人工（未执行物理触控板） |
| D3 | Same long plain-text document, start in the middle | N/A | Mouse or trackpad; first reliable movement Up | Session locks `Up`; new lines are prepended above the seed, and the result remains in natural top-to-bottom order. | 待人工（目标应用/设备可用时） |
| D4 | Same document and middle start as D3 | N/A | Mouse or trackpad; first reliable movement Down | Session locks `Down`; new lines are appended below the seed, and the result remains in natural top-to-bottom order. | 待人工（目标应用/设备可用时） |
| D5 | Same document and middle start as D3 | N/A | Reverse after locking `Up` or `Down` | Reverse movement remains review/dedup: it neither changes the lock nor extends the seed's other end; capture of the other end requires a new session. | 待人工（目标应用/设备可用时） |
| D6 | Same document with a fixed header/footer and a repeated or low-detail section | Yes | Mouse or trackpad | Awaiting fixed-band evidence continues sampling, clears any prior low-confidence warning, and does not show a new warning or pause. A genuine low-confidence frame warns without pausing; sustained low-confidence/stable frames may idle the timer, and the next wheel/trackpad event immediately rearms it. | 待人工（目标应用/设备可用时） |

For every executed row, save a representative PNG outside the repository and inspect the entire image at 100% zoom, especially the first seam, last seam, fixed bands and right edge.

## Sampling, direction lock, blocking pause, review and repeat behavior

- [ ] From a middle viewport, scroll in one direction with the mouse wheel in short bursts; confirm the first unique reliable movement locks `Up` or `Down`, then stop and confirm sampling settles without appending stationary duplicates.
- [ ] Repeat with a trackpad fling and allow inertia to finish; confirm the result's active edge is neither duplicated nor truncated.
- [ ] Stop on an unchanged viewport long enough to produce exact-repeat frames; confirm output height does not grow.
- [ ] After locking `Down`, scroll upward; confirm reverse frames are classified as review/dedup, do not change the lock, and do not prepend content above the seed. Return downward through accepted content and beyond the tail; confirm new content resumes exclusively below the seed.
- [ ] After locking `Up`, scroll downward; confirm reverse frames are classified as review/dedup, do not change the lock, and do not append content below the seed. Return upward through accepted content and beyond the head; confirm new content resumes exclusively above the seed in natural document order.
- [ ] Scroll the live preview away from the active edge; confirm it stops following while capture continues. Return it to the bottom for `Down` or the top for `Up`, and confirm following resumes.
- [ ] Use a repeated/low-detail region that produces low match confidence; confirm a non-blocking warning appears while collection remains active and the accepted preview is retained. Allow sustained low-confidence/stable frames to idle the sampling timer, then confirm the next wheel or trackpad event immediately rearms sampling without restarting the session.
- [ ] While fixed-header/footer classification is awaiting enough movement evidence, confirm normal sampling continues, any prior low-confidence warning is cleared once, and no new warning or pause is shown.
- [ ] With Safari frontmost and xxsnap granted Accessibility permission, verify `Return` and keypad `Enter` on separate active/resource-paused runs each trigger Finish Scroll Capture exactly once; verify `Esc` cancels and restores the locked selection/first-screen annotations.
- [ ] Repeat the target-frontmost keyboard check with Chrome. Confirm a local/global duplicate delivery cannot finish or cancel twice.
- [ ] Without Accessibility permission, do not mark target-frontmost shortcuts passed. Verify the on-screen Finish Scroll Capture and Cancel buttons still complete/cancel reliably; also verify shortcuts continue to work when the xxsnap overlay itself owns the key event.
- [ ] After a scroll cancel, verify ordinary screenshot escape behavior is unchanged: the first local `Esc` exits an active annotation tool and the second local `Esc` closes the ordinary capture.

## Fixed bands and scrollbar confidence

- [ ] On fixed-header browser targets, verify a stable top band is detected only after repeated movement and is not repeated in the output.
- [ ] On a target with a clearly persistent moving scrollbar at the right edge, verify the high-confidence scrollbar strip is cropped consistently from the complete image.
- [ ] On a target with ambiguous right-edge content (for example a narrow persistent sidebar, border, or content that resembles a scrollbar), verify the edge is preserved rather than cropped without sufficient confidence.
- [ ] Compare widths before and after confirmed scrollbar cropping; verify no alternating width or visible right-edge notch occurs between segments.

## Placement, displays and scale matrix

| ID | Geometry / display case | Expected checks | Result / evidence |
| --- | --- | --- | --- |
| P1 | Full-screen selection | Toolbar remains usable; preview uses a safe fallback and does not block Finish/Cancel. | 待人工 |
| P2 | Region with room outside | Preview is placed outside the selected region and stays inside the visible screen. | 待人工 |
| P3 | Region with no outside room | Preview falls back inside a safe area and does not overlap the Finish/Cancel hit regions. | 待人工 |
| P4 | Selection against each screen edge/corner | Toolbar and preview remain on-screen and actionable. | 待人工 |
| P5 | Multi-display, selection on non-primary display | Capture, toolbar, preview, long-image editor and subsequent pin stay on the capture display; output uses the selected coordinates. | 待人工（需多屏） |
| P6 | Retina display | Point-to-pixel conversion is sharp and seams/annotations align at native scale. | 待人工 |
| P7 | Non-Retina display or scaled external display | Capture dimensions, seams, preview and annotations align without 2x/1x drift. | 待人工（需对应显示器） |

## Long-image editing and output

- [ ] Add rectangle/text/arrow or another visible annotation before starting Scroll Capture; after completion, confirm it remains at the first-screen image position in the long-image editor and output.
- [ ] In the long-image editor, scroll to multiple distant sections and add, select, move, edit and delete annotations; confirm edits stay in full-image coordinates after scrolling or resizing the editor.
- [ ] Confirm the annotation toolbar stays available over the visible long-image slice and that scrolling is locked only during an active annotation gesture.
- [ ] Click Copy and paste into a separate app; confirm the entire long image, including first-screen and newly added annotations, is present.
- [ ] Click Save, save PNG outside the repository, reopen it, and compare dimensions/content with the editor result.
- [ ] Click Pin and confirm the complete long image is pinned, initially fitted on-screen while preserving aspect ratio, and remains movable/zoomable.
- [ ] Click Finish editing and Close in separate runs; confirm each ends the editor once without repeating an earlier output action.

## Failure and resource recovery

- [ ] Force or use a test build with a small accepted-byte budget; confirm the resource guard pauses collection, preserves the accepted preview, and leaves Finish Scroll Capture/Cancel available.
- [ ] Finish after the resource guard pauses; confirm the retained accepted segments compose and enter the editor.
- [ ] Simulate a transient frame-capture failure; confirm this blocking failure pauses collection, shows a warning, keeps accepted content available, and ignores later scroll activity instead of rearming sampling. Confirm the only reliable paths are Finish with the accepted result or Cancel.
- [ ] Simulate final composition failure; confirm the session/accepted engine state remains alive for another Finish attempt or Cancel.
- [ ] Simulate long-image editor creation returning `nil` and throwing; confirm the completed image is retained and a Save/Cancel fallback appears.
- [ ] In the fallback, cancel the save panel once and confirm the fallback offers Save/Cancel again; then save successfully and verify the PNG. Canceling the fallback must end cleanly without claiming a save.

## Run record

- Automated core/XCTest results belong in the task handoff or CI log, not as substitutes for unchecked manual rows above.
- Real Safari/Chrome scrolling, mouse/trackpad inertia, visual seam inspection, multi-display and Retina/non-Retina rows must remain `待人工` until executed on the named hardware/app combination.

### 2026-07-12 UI smoke attempt

- Computer Use runtime initialization succeeded once with `sky-ready`, but subsequent `sky.list_apps()` and `sky.get_app_state({app:'Google Chrome'})` calls repeatedly failed with the exact error `Sky Computer Use native pipe startup failed`.
- Because the native control pipe could not start reliably, Safari、Chrome、Preview and XxSnap UI could not be operated or inspected with trustworthy evidence. The environment also could not distinguish physical mouse input from physical trackpad input. This is an automation-environment blocker, not a product failure.
- Browser/document seam inspection, fixed-header and scrollbar behavior, target-app-frontmost Return/keypad Enter/Esc with and without Accessibility permission, mouse/trackpad inertia, long-image copy/save/pin, multi-display, and Retina/non-Retina checks remain `待人工`.
- Terminal verification found exactly one product process: PID `41041`, executable `/Users/kevin/Projects/open-source/Snipory/xxsnap/.worktrees/scroll-capture-impl/build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/MacOS/XxSnap`. Process-query helper noise is excluded from this record.
