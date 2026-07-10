# macOS App and Status Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the macOS app icon with the supplied color icon set and the menu-bar icon with the supplied transparent monochrome artwork.

**Architecture:** Keep the existing AppIcon asset catalog layout, `CFBundleIconFile`, and status-item loading code unchanged. Copy source PNGs into the existing resource filenames and regenerate the existing ICNS so Xcode and runtime resource lookups continue to work without new code paths.

**Tech Stack:** macOS AppKit, Xcode asset catalogs, PNG resources, `xcodebuild`.

---

### Task 1: Replace and validate icon resources

**Files:**
- Modify: `platforms/mac/Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16.png`
- Modify: `platforms/mac/Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png`
- Modify: `platforms/mac/Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32.png`
- Modify: `platforms/mac/Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png`
- Modify: `platforms/mac/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png`
- Modify: `platforms/mac/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png`
- Modify: `platforms/mac/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png`
- Modify: `platforms/mac/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png`
- Modify: `platforms/mac/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png`
- Modify: `platforms/mac/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`
- Modify: `platforms/mac/Resources/xxsnap.icns`
- Modify: `platforms/mac/Resources/xxsnap.png`

- [ ] **Step 1: Verify source dimensions and transparency**

Run `sips -g pixelWidth -g pixelHeight -g hasAlpha` for all color source PNGs and the monochrome `icon-128.png`.

Expected: color dimensions are 16, 32, 32, 64, 128, 256, 256, 512, 512, and 1024 pixels; monochrome `icon-128.png` is 128×128 with alpha.

- [ ] **Step 2: Copy color PNGs into matching asset slots**

Copy each `icon-<size>[@2x].png` from `xxsnap-icons-v1-彩色/mac/AppIcon.appiconset` to the corresponding `icon_<size>x<size>[@2x].png` destination. Do not resize or re-encode the supplied artwork.

- [ ] **Step 3: Generate the application ICNS**

Copy the ten color PNGs into a temporary `.iconset` directory using `icon_16x16.png` through `icon_512x512@2x.png` names, then run `iconutil -c icns` to replace `platforms/mac/Resources/xxsnap.icns`. Keep `CFBundleIconFile = xxsnap` unchanged.

- [ ] **Step 4: Replace the menu-bar resource**

Convert `xxsnap-icons-v1-黑白/mac/AppIcon.appiconset/icon-128.png` into a template PNG by using inverse luminance as alpha and removing the source's light checkerboard background. Write the processed result to `platforms/mac/Resources/xxsnap.png`. Keep `StatusItemController.statusBarImage()` unchanged so the image remains an 18×18 point template image.

- [ ] **Step 5: Verify copied content and asset metadata**

Run SHA-256 comparisons between every AppIcon PNG source/destination pair, expand `xxsnap.icns` with `iconutil`, validate dimensions with `sips`, verify the status PNG has more than 50% fully transparent pixels and more than 10% visible pixels, and run `git diff --check`.

Expected: every AppIcon source/destination hash pair matches; all ten AppIcon slots and expanded ICNS entries have their declared pixel dimensions; status icon is 128×128 with a transparent background and visible glyph; `git diff --check` exits successfully.

- [ ] **Step 6: Commit the isolated resource replacement**

```bash
git add platforms/mac/Resources/Assets.xcassets/AppIcon.appiconset/*.png \
  platforms/mac/Resources/xxsnap.icns platforms/mac/Resources/xxsnap.png
git commit -m "feat(mac): refresh app and status icons"
```

### Task 2: Widen the status icon seams

**Files:**
- Modify: `platforms/mac/Resources/xxsnap.png`
- Test: `platforms/mac/Tests/xxsnapMacTests.swift`

- [ ] **Step 1: Add a failing visible-area upper bound**

Add this assertion to `testStatusBarTemplateIconHasTransparentBackgroundAndVisibleGlyph()` after the existing lower bound:

```swift
XCTAssertLessThan(visiblePixelCount, pixelCount / 5)
```

The lower bound protects glyph visibility; the upper bound requires enough transparent seam area to keep all three joins readable.

- [ ] **Step 2: Run the focused test and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/xxsnapMacTests/testStatusBarTemplateIconHasTransparentBackgroundAndVisibleGlyph
```

Expected: FAIL because the current visible pixel count is not less than one fifth of the 128×128 canvas.

- [ ] **Step 3: Apply the approved 3px alpha-mask erosion**

Extract the current PNG alpha channel, apply ImageMagick `-morphology Erode Disk:3`, and copy the eroded mask back as opacity over a black 128×128 canvas. Replace only `platforms/mac/Resources/xxsnap.png`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2 again.

Expected: PASS; transparent pixels remain more than half, visible pixels remain more than one tenth and less than one fifth of the canvas.

- [ ] **Step 5: Verify the 36px status-bar preview**

Resize the alpha channel to 36×36 and inspect the three internal seams. Compare the opaque bounds with the previous `30x32+3+2` baseline.

Expected: all three seams are approximately two pixels wide; each outer edge moves inward by no more than one display pixel.

- [ ] **Step 6: Commit the seam refinement**

```bash
git add platforms/mac/Resources/xxsnap.png platforms/mac/Tests/xxsnapMacTests.swift
git commit -m "fix(mac): widen status icon seams"
```

### Task 3: Build and restart the app

**Files:**
- Verify: `platforms/mac/xxsnap.xcodeproj`
- Verify: `build/xcode-derived/Build/Products/Debug/XxSnap.app`

- [ ] **Step 1: Build the Debug app**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived build
```

Expected: `** BUILD SUCCEEDED **` with no asset-catalog errors.

- [ ] **Step 2: Verify packaged resources**

Check the built app's copied `xxsnap.icns` and `xxsnap.png`; verify the packaged status icon is 128×128 and byte-identical to the processed runtime resource, and verify the packaged ICNS matches the regenerated source ICNS.

- [ ] **Step 3: Restart and verify the process**

Terminate the existing Debug binary, open `build/xcode-derived/Build/Products/Debug/XxSnap.app`, and query the exact binary path with `pgrep -af`.

Expected: one running XxSnap process from the `build/xcode-derived` Debug app path.
