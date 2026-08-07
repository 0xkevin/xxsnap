# Super-Long Scroll Save Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export super-long scroll captures as pixel-identical PNG files while presenting a narrow warning card and a real, explicitly cancellable save-progress card.

**Architecture:** The C++ stitcher will expose a top-down final-row visitor so export never creates or rescales a preview image. The Objective-C++ bridge will encode those rows into a zlib-compressed PNG beside the destination as a hidden `.part` file, publish monotonic row progress, and atomically replace the destination only after completion. Swift will propagate cancellation into the encoder and coordinate two focused AppKit panel controllers for warning and save progress.

**Tech Stack:** C++20, Objective-C++, zlib, AppKit, Swift concurrency, XCTest, Qt Test, XcodeGen.

---

### Task 1: Stream pixel-identical final rows from the stitcher

**Files:**
- Modify: `core/include/snipory/core/scroll/ScrollStitchSession.h`
- Modify: `core/src/scroll/ScrollStitchSession.cpp`
- Test: `core/tests/TestScrollStitchSession.cpp`

- [ ] **Step 1: Write failing row-stream tests**

Add tests that visit all final rows, concatenate them, and compare the bytes with `finalizeIncludingPending()`. Cover downward output, upward pending output, left/right scrollbar crop, the default isolated-white seam repair, and early visitor cancellation. The key assertion is:

```cpp
std::vector<std::uint8_t> streamed;
QVERIFY(session.visitFinalRows(true, [&](const std::uint8_t* row, std::size_t bytes, int, int) {
    streamed.insert(streamed.end(), row, row + bytes);
    return true;
}));
const auto final = session.finalizeIncludingPending();
QCOMPARE(streamed, final.pixels);
```

- [ ] **Step 2: Run the focused core test and confirm failure**

Run: `cmake --build build --target test_scroll_stitch_session -j8 && ./build/core/test_scroll_stitch_session`

Expected: compilation fails because `visitFinalRows` does not exist.

- [ ] **Step 3: Add the public visitor contract**

Add `#include <functional>` and this alias/method to `ScrollStitchSession.h`:

```cpp
using FinalRowVisitor = std::function<bool(
    const std::uint8_t* pixels,
    std::size_t bytes,
    int row,
    int totalRows)>;

[[nodiscard]] bool visitFinalRows(
    bool includePending,
    const FinalRowVisitor& visitor) const;
```

- [ ] **Step 4: Refactor composition through the visitor**

Move the existing committed/pending row traversal from `copyFinalPixels` into `visitFinalRows`. Crop the scrollbar before invoking the visitor. Preserve `seamWhiteCoverage` blending. For the default isolated-white repair, retain three cropped rows, repair the middle row when both neighbors are available, and then emit the oldest row. Return `false` immediately when the visitor returns `false`.

Rewrite `copyFinalPixels` as a small adapter that copies each visited row to its top-down or bottom-up destination offset. This ensures the legacy final image and new streaming export share exactly one composition path.

- [ ] **Step 5: Run core tests**

Run: `cmake --build build --target test_scroll_stitch_session -j8 && ./build/core/test_scroll_stitch_session`

Expected: all `TestScrollStitchSession` cases pass.

### Task 2: Implement lossless streaming PNG, progress, atomic publish, and cancellation

**Files:**
- Modify: `platforms/mac/Sources/Bridge/ScrollCaptureBridge.h`
- Modify: `platforms/mac/Sources/Bridge/ScrollCaptureBridge.mm`
- Modify: `platforms/mac/project.yml`
- Regenerate: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`
- Test: `platforms/mac/Tests/ScrollCaptureBridgeTests.swift`

- [ ] **Step 1: Write failing bridge tests**

Add tests for:

```swift
try bridge.writePNG(to: url) { progressValues.append($0) }
XCTAssertEqual(progressValues.last, 1)
XCTAssertEqual(progressValues, progressValues.sorted())
```

Decode an opaque and a partially transparent image and compare rendered BGRA bytes with the source. Add a cancellation test that calls `bridge.cancelPNGWrite()` from the progress callback, asserts a user-cancelled error, confirms that neither the target nor a `.part` sibling remains, and confirms an existing target remains byte-for-byte unchanged after cancellation.

- [ ] **Step 2: Run bridge tests and confirm API failures**

Run: `xcodebuild test -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -destination 'platform=macOS' -only-testing:xxsnapTests/ScrollCaptureBridgeTests`

Expected: compilation fails because progress and cancellation APIs do not exist.

- [ ] **Step 3: Add the bridge API and cancellation state**

Declare:

```objc
typedef void (^ScrollCapturePNGProgressHandler)(double progress);
- (BOOL)writePNGToURL:(NSURL *)url
             progress:(nullable ScrollCapturePNGProgressHandler)progress
                error:(NSError **)error
    NS_SWIFT_NAME(writePNG(to:progress:));
- (void)cancelPNGWrite NS_SWIFT_NAME(cancelPNGWrite());
```

Keep the current `writePNG(to:)` method as a convenience wrapper. Store an `std::atomic_bool` in `BridgeImplementation`; reset it at export start and set it from `cancelPNGWrite`.

- [ ] **Step 4: Implement a bounded-memory PNG writer**

In `ScrollCaptureBridge.mm`, write the PNG signature, IHDR, consecutive IDAT chunks, and IEND. Use `deflateInit2`/`deflate`/`deflateEnd` from zlib. For every visited BGRA row:

```cpp
rgba[x * 4 + 0] = unpremultiply(bgra[x * 4 + 2], alpha);
rgba[x * 4 + 1] = unpremultiply(bgra[x * 4 + 1], alpha);
rgba[x * 4 + 2] = unpremultiply(bgra[x * 4 + 0], alpha);
rgba[x * 4 + 3] = alpha;
```

Choose the least-cost PNG filter among None, Sub, Up, Average, and Paeth. Emit progress only when the integer half-percent changes; calculate it from visited rows and report `1.0` only after IEND, `fflush`, and `fsync` succeed.

- [ ] **Step 5: Make publication atomic**

Create `.<destination-name>.<UUID>.part` in the same directory. On success, use `replaceItemAtURL` when the destination exists or `moveItemAtURL` otherwise. On every error and cancellation path, close and delete the temporary file without touching an existing destination.

Use an NSError with `NSCocoaErrorDomain` and `NSUserCancelledError` for explicit cancellation so Swift can distinguish it from a retryable export failure.

- [ ] **Step 6: Link zlib and regenerate the project**

Add `OTHER_LDFLAGS: "$(inherited) -lz"` to the macOS target settings in `project.yml`, then run:

`cd platforms/mac && xcodegen generate`

Expected: `xxsnap.xcodeproj/project.pbxproj` contains `OTHER_LDFLAGS = "$(inherited) -lz"` and includes any new source files.

- [ ] **Step 7: Run bridge tests**

Run the focused `xcodebuild test` command from Step 2.

Expected: lossless Retina, 100,538-pixel height, progress, cancellation, cleanup, and existing-file preservation tests pass.

### Task 3: Propagate progress and cancellation through the Swift session

**Files:**
- Modify: `platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift`
- Test: `platforms/mac/Tests/ScrollCaptureSessionTests.swift`

- [ ] **Step 1: Write failing async session tests**

Change the fake stitcher to record a progress closure and suspend export. Verify progress is forwarded, cancellation invokes the stitcher cancellation closure, the session becomes `.cancelled`, and retryable encoder failures still become `.paused(.captureFailure)`.

- [ ] **Step 2: Run session tests and confirm signature failures**

Run: `xcodebuild test -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -destination 'platform=macOS' -only-testing:xxsnapTests/ScrollCaptureSessionTests`

Expected: compilation fails until the progress/cancellation contract is added.

- [ ] **Step 3: Extend the stitcher contract**

Replace the direct-export method with:

```swift
func writePNG(
    to url: URL,
    progress: @escaping @Sendable (Double) -> Void
) async throws
func cancelPNGWrite()
```

The bridge worker runs synchronous encoding in `Task.detached` and wraps it in `withTaskCancellationHandler`; `onCancel` calls `bridge.cancelPNGWrite()`.

- [ ] **Step 4: Extend `finishSaving`**

Use:

```swift
func finishSaving(
    to url: URL,
    progress: @escaping @Sendable (Double) -> Void
) async throws
```

Forward progress without creating an `NSImage`. Map `NSUserCancelledError` or task cancellation to `CancellationError`, clear the stitcher, transition to `.cancelled`, and close diagnostics as a user cancellation. Preserve the existing paused-and-retry behavior for all non-cancellation errors.

- [ ] **Step 5: Enforce the supported PNG height ceiling**

Add `private static let maximumSuperLongPNGPixelHeight = 2_000_000`. When an accepted append reaches that height, disarm sampling, retain the current stitched pixels, enter `.paused(.resourceLimit)`, and keep save-only completion available. Add a test whose output height is exactly 2,000,000 and assert collection pauses without discarding the result.

- [ ] **Step 6: Run session tests**

Run the focused command from Step 2.

Expected: all session tests pass, including finish, progress, cancellation, and retry.

### Task 4: Build the approved warning and progress cards

**Files:**
- Create: `platforms/mac/Sources/App/SuperLongCaptureWindowController.swift`
- Modify: `platforms/mac/Sources/App/AppSettings.swift`
- Modify: `platforms/mac/project.yml`
- Regenerate: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`
- Test: `platforms/mac/Tests/AppSettingsTests.swift`
- Test: `platforms/mac/Tests/ScrollCapturePresentationTests.swift`

- [ ] **Step 1: Write failing UI-model tests**

Assert the Chinese and English strings include 29,000 pixels, original-pixel lossless saving, the 2,000,000-pixel PNG limit, Esc semantics, and cancel labels. Instantiate each controller and assert content width is 348 points, title alignment is centered, body alignment is left, wrapping is enabled, progress is determinate, Esc is consumed, and repeated cancel clicks invoke the callback once.

- [ ] **Step 2: Run focused UI tests and confirm failure**

Run: `xcodebuild test -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -destination 'platform=macOS' -only-testing:xxsnapTests/AppSettingsTests -only-testing:xxsnapTests/ScrollCapturePresentationTests`

Expected: compilation fails because the new controller and localization keys do not exist.

- [ ] **Step 3: Add exact localized copy**

Add localization keys for warning title/body/callout/limit/action and save title/stage/Esc/cancel/cancelling. Use the approved Chinese copy from the design spec and equivalent concise English copy.

- [ ] **Step 4: Implement the narrow warning controller**

Create a borderless, shadowed `NSPanel` with a 348-point content card, 18-point corner radius, 40-point amber warning icon, centered title, left-aligned wrapping labels, and full-width blue continue button. Present it modally and close only through the button.

- [ ] **Step 5: Implement the save-progress controller**

Create a matching panel with title, stage/percentage row, determinate progress indicator, middle-truncated destination path, Esc note, and a separate red cancel row. Clamp progress to `0...1`, keep it monotonic, consume Esc in the panel subclass, and disable/change the button after its first click.

- [ ] **Step 6: Regenerate project and run UI tests**

Run `cd platforms/mac && xcodegen generate`, then the focused test command from Step 2.

Expected: localization and controller behavior tests pass.

### Task 5: Integrate progress UI and explicit discard cancellation

**Files:**
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing coordinator tests**

Inject a fake progress presenter. Verify it opens only after the save destination is chosen, receives monotonic progress, closes on success/error/cancel, reveals only successful destinations, leaves the session available after retryable failure, and fully tears down the overlay/session after explicit cancel. Verify cancelling the save panel before encoding does not show progress and leaves terminal actions retryable.

- [ ] **Step 2: Run coordinator tests and confirm failure**

Run: `xcodebuild test -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -destination 'platform=macOS' -only-testing:xxsnapTests/SelectionToolbarStateTests`

Expected: tests fail until the progress presenter and cancellation cleanup are connected.

- [ ] **Step 3: Replace the old warning alert**

Route `enteredSuperLongMode` to `SuperLongCaptureWarningWindowController`, remove the old `NSAlert` construction and descendant-text-field alignment workaround, and reactivate the captured target app after the modal warning closes.

- [ ] **Step 4: Present and update save progress**

After the user selects a URL, create and show a `SuperLongCaptureSaveProgressWindowController`. Pass a throttled `@Sendable` progress closure to `finishSaving`; dispatch UI updates to `MainActor` and ignore stale capture generations.

- [ ] **Step 5: Implement explicit cancel cleanup**

The progress controller's cancel callback cancels the active save task. After the encoder confirms cancellation, close the panel, stop presentation, dismiss the overlay, clear session/seed/frozen image, set lifecycle to idle, and invoke `captureSessionDidEnd`. Do not reveal a file and do not restore the capture overlay.

- [ ] **Step 6: Preserve retryable failures**

For non-cancellation export errors, close progress UI, reset terminal actions, leave the session in paused failure state, and allow the user to choose a destination and retry.

- [ ] **Step 7: Run coordinator tests**

Run the focused command from Step 2.

Expected: all super-long coordinator lifecycle tests pass.

### Task 6: Full regression and application verification

**Files:**
- Modify: `platforms/mac/Tests/manual-capture-checklist.md`

- [ ] **Step 1: Update manual acceptance checks**

Document the A-style warning, real progress, Esc no-op, explicit cancel cleanup, existing-file preservation, Finder reveal, and 100% zoom clarity checks.

- [ ] **Step 2: Run core suite**

Run: `cmake --build build -j8 && ctest --test-dir build --output-on-failure`

Expected: all core tests pass.

- [ ] **Step 3: Run macOS suite**

Run: `xcodebuild test -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -destination 'platform=macOS'`

Expected: all macOS tests pass; any pre-existing unrelated flaky snapshot test is recorded separately and rerun once.

- [ ] **Step 4: Build an optimized app**

Run: `xcodebuild build -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Verify a generated super-long PNG**

Create or capture a PNG taller than 100,000 pixels. Use `sips -g pixelWidth -g pixelHeight` and ImageMagick 100% crops from the top, middle, and bottom to confirm original width, full height, and sharp text. Cancel a second export midway and confirm neither the target nor a hidden `.part` remains.

- [ ] **Step 6: Review the final diff**

Run: `git diff --check` and `git status --short`.

Expected: no whitespace errors; only the approved scroll-capture work and the already-existing branch changes are present.
