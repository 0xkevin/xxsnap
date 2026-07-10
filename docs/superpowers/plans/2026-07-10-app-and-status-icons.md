# macOS App and Status Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the macOS app icon with the supplied color icon set and the menu-bar icon with the supplied transparent monochrome artwork.

**Architecture:** Keep the existing AppIcon asset catalog layout and status-item loading code unchanged. Copy source PNGs into the existing resource filenames so Xcode and runtime resource lookups continue to work without new code paths.

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
- Modify: `platforms/mac/Resources/Icons/xxsnap.png`

- [ ] **Step 1: Verify source dimensions and transparency**

Run `sips -g pixelWidth -g pixelHeight -g hasAlpha` for all color source PNGs and the monochrome `icon-128.png`.

Expected: color dimensions are 16, 32, 32, 64, 128, 256, 256, 512, 512, and 1024 pixels; monochrome `icon-128.png` is 128×128 with alpha.

- [ ] **Step 2: Copy color PNGs into matching asset slots**

Copy each `icon-<size>[@2x].png` from `xxsnap-icons-v1-彩色/mac/AppIcon.appiconset` to the corresponding `icon_<size>x<size>[@2x].png` destination. Do not resize or re-encode the supplied artwork.

- [ ] **Step 3: Replace the menu-bar resource**

Copy `xxsnap-icons-v1-黑白/mac/AppIcon.appiconset/icon-128.png` to `platforms/mac/Resources/Icons/xxsnap.png`. Keep `StatusItemController.statusBarImage()` unchanged so the image remains an 18×18 point template image.

- [ ] **Step 4: Verify copied content and asset metadata**

Run SHA-256 comparisons between every source/destination pair, validate destination dimensions with `sips`, and run `git diff --check`.

Expected: every source/destination hash pair matches; all ten AppIcon slots have their declared pixel dimensions; status icon is 128×128 with alpha; `git diff --check` exits successfully.

- [ ] **Step 5: Commit the isolated resource replacement**

```bash
git add platforms/mac/Resources/Assets.xcassets/AppIcon.appiconset/*.png \
  platforms/mac/Resources/Icons/xxsnap.png
git commit -m "feat(mac): refresh app and status icons"
```

### Task 2: Build and restart the app

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

Check the built app's `Assets.car` and copied `xxsnap.png`; verify the packaged status icon is 128×128 with alpha and matches the monochrome source hash.

- [ ] **Step 3: Restart and verify the process**

Terminate the existing Debug binary, open `build/xcode-derived/Build/Products/Debug/XxSnap.app`, and query the exact binary path with `pgrep -af`.

Expected: one running XxSnap process from the `build/xcode-derived` Debug app path.
