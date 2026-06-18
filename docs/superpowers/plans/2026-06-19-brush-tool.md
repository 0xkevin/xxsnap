# Brush Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the third Snipory v2 mac annotation tool as a freehand brush with width, stroke pattern, and color controls.

**Architecture:** Extend the existing mac-only annotation model and overlay interaction flow. Reuse the current options toolbar container with a new brush mode, and render brush paths in both overlay drawing and final image export. Keep coordinates relative to the selected capture rect so drawing outside the selection remains visible in the overlay but is naturally clipped out of exported screenshots.

**Tech Stack:** Swift, AppKit, XCTest, existing `SelectionOverlayWindow`, `SelectionToolbarState`, and `CaptureAnnotationRenderer`.

---

### Task 1: Toolbar State

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`

- [ ] **Step 1: Write failing toolbar tests**

Add tests that assert brush mode uses stroke widths `[3, 5, 7]`, shows no fill/shape/arrow controls, and places color swatches after the stroke style field with separator-equivalent spacing.

- [ ] **Step 2: Run the focused test**

Run:

```bash
xcodebuild -project platforms/mac/snipory.xcodeproj -scheme snipory -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:SniporyTests/SelectionToolbarStateTests
```

Expected: fails because `.brush` mode and brush widths do not exist.

- [ ] **Step 3: Implement toolbar state**

Add `.brush` to `OptionsToolbarMode`, return `[3, 5, 7]` for brush widths, and use a compact layout with stroke widths, stroke style, then colors.

- [ ] **Step 4: Re-run focused test**

Expected: Selection toolbar state tests pass.

### Task 2: Brush Model And Renderer

**Files:**
- Modify: `platforms/mac/Tests/SniporyMacTests.swift`
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`

- [ ] **Step 1: Write failing renderer tests**

Add tests that a brush annotation changes pixels, that dashed stroke pattern changes rendered output, and that path points outside the image bounds do not expand the image or crash rendering.

- [ ] **Step 2: Run focused renderer tests**

Expected: fails because brush annotation kind and path model do not exist.

- [ ] **Step 3: Implement brush model and rendering**

Add `.brush`, a `CaptureBrushPath` point list, store it on `CaptureAnnotation`, and render it as a stroked path using current stroke color, width, and stroke pattern.

- [ ] **Step 4: Re-run focused renderer tests**

Expected: renderer tests pass.

### Task 3: Overlay Interaction

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write focused interaction-state tests where pure helpers exist**

Assert the pen tooltip remains `画笔`, brush activation defaults to first palette color and width `5`, and toolbar icon selection maps pen to brush mode.

- [ ] **Step 2: Implement overlay activation and drawing**

Make the pen button activate `.brush` instead of showing the placeholder. During drag, append points clamped to overlay bounds, store local points relative to the selected rect, draw the draft path and committed brush paths in overlay coordinates, and reuse style/color/stroke pattern updates for selected brush annotations.

- [ ] **Step 3: Preserve export clipping behavior**

Keep `CaptureSelectionResult.snapshotRect` unchanged and do not expand exported image bounds for brush paths outside the selected rect.

### Task 4: Verification

**Files:**
- No code changes.

- [ ] **Step 1: Run full mac XCTest target**

Run:

```bash
xcodebuild -project platforms/mac/snipory.xcodeproj -scheme snipory -configuration Debug -derivedDataPath build/xcode-derived test
```

- [ ] **Step 2: Run app build if tests are blocked**

Run:

```bash
xcodebuild -project platforms/mac/snipory.xcodeproj -scheme snipory -configuration Debug -derivedDataPath build/xcode-derived build
```

- [ ] **Step 3: Report exact verification status**

State which test/build commands passed or failed and any local blocker.
