# macOS 14 Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native XxSnap app build and run with a macOS 14.0 deployment target without changing its macOS 15 behavior.

**Architecture:** Route the four dark diagonal resize cursors through an availability-aware `NSCursor` compatibility helper. The helper keeps `NSCursor.frameResize` on macOS 15 and uses the existing XxSnap cursor renderer on macOS 14; existing guarded ScreenCaptureKit behavior remains unchanged.

**Tech Stack:** Swift 5, AppKit, XCTest, XcodeGen, Xcode build settings

---

### Task 1: Add the diagonal cursor compatibility path

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`

- [ ] **Step 1: Write the failing fallback-cursor test**

Add a test that requests all four diagonal cursors with `prefersSystemCursor: false`, verifies 24-by-24 images and centered hot spots, verifies top-left equals bottom-right, verifies top-right equals bottom-left, and verifies the two diagonal orientations differ.

```swift
func testDiagonalResizeCursorFallbacksUseCenteredCustomImages() throws {
    let topLeft = NSCursor.xxsnapFrameResize(position: .topLeft, prefersSystemCursor: false)
    let topRight = NSCursor.xxsnapFrameResize(position: .topRight, prefersSystemCursor: false)
    let bottomLeft = NSCursor.xxsnapFrameResize(position: .bottomLeft, prefersSystemCursor: false)
    let bottomRight = NSCursor.xxsnapFrameResize(position: .bottomRight, prefersSystemCursor: false)

    for cursor in [topLeft, topRight, bottomLeft, bottomRight] {
        XCTAssertEqual(cursor.image.size, NSSize(width: 24, height: 24))
        XCTAssertEqual(cursor.hotSpot, NSPoint(x: 12, y: 12))
    }

    XCTAssertEqual(try rgbaBytes(in: topLeft.image), try rgbaBytes(in: bottomRight.image))
    XCTAssertEqual(try rgbaBytes(in: topRight.image), try rgbaBytes(in: bottomLeft.image))
    XCTAssertNotEqual(try rgbaBytes(in: topLeft.image), try rgbaBytes(in: topRight.image))
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap \
  -configuration Debug -derivedDataPath build/xcode-derived \
  test -only-testing:xxsnapTests/SelectionToolbarStateTests/testDiagonalResizeCursorFallbacksUseCenteredCustomImages
```

Expected: compilation fails because `xxsnapFrameResize` and its position type do not exist.

- [ ] **Step 3: Implement the minimal availability-aware cursor helper**

Add an XxSnap-owned position enum and `NSCursor.xxsnapFrameResize(position:prefersSystemCursor:)`. Inside `if #available(macOS 15.0, *)`, preserve the matching system `frameResize` calls. Otherwise return dark custom cursors rendered at `-.pi / 4` or `.pi / 4`.

Replace the four direct `NSCursor.frameResize` calls in `nsCursor(for:)` with the compatibility helper. Leave all light cursor paths unchanged.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the focused command from Step 2.

Expected: the test passes with zero failures.

- [ ] **Step 5: Commit the cursor compatibility change**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift \
  platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "fix(mac): add macOS 14 resize cursor fallback"
```

### Task 2: Lower and document the deployment target

**Files:**
- Modify: `platforms/mac/project.yml`
- Regenerate: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`
- Modify: `README.md`

- [ ] **Step 1: Change the source deployment setting**

Set the base `MACOSX_DEPLOYMENT_TARGET` in `platforms/mac/project.yml` from `15.0` to `14.0`.

- [ ] **Step 2: Regenerate and inspect the checked-in Xcode project**

Run:

```bash
cd platforms/mac
xcodegen generate
cd ../..
rg -n "MACOSX_DEPLOYMENT_TARGET" platforms/mac/project.yml \
  platforms/mac/xxsnap.xcodeproj/project.pbxproj
```

Expected: every deployment-target occurrence is `14.0`.

- [ ] **Step 3: Document the supported version**

Add `macOS 14.0 or newer` to the README product summary.

- [ ] **Step 4: Verify the effective build settings**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap \
  -configuration Debug -showBuildSettings |
rg "MACOSX_DEPLOYMENT_TARGET = 14.0"
```

Expected: the app and test targets inherit `14.0`.

- [ ] **Step 5: Commit the configuration change**

```bash
git add README.md platforms/mac/project.yml platforms/mac/xxsnap.xcodeproj/project.pbxproj
git commit -m "build(mac): support macOS 14"
```

### Task 3: Verify the complete macOS target

**Files:**
- No source changes expected

- [ ] **Step 1: Run the full macOS test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap \
  -configuration Debug -derivedDataPath build/xcode-derived test
```

Expected: `TEST SUCCEEDED`, zero test failures.

- [ ] **Step 2: Build explicitly for macOS 14**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap \
  -configuration Debug -derivedDataPath build/xcode-derived \
  MACOSX_DEPLOYMENT_TARGET=14.0 build
```

Expected: `BUILD SUCCEEDED` with no unguarded-availability errors.

- [ ] **Step 3: Inspect the built app metadata**

```bash
defaults read \
  build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/Info \
  LSMinimumSystemVersion
```

Expected: `14.0`.

- [ ] **Step 4: Review final scope**

Run:

```bash
git status --short
git diff main...HEAD --check
git diff main...HEAD --stat
```

Expected: clean worktree, no whitespace errors, and changes limited to the design/plan docs, cursor compatibility, tests, deployment configuration, generated Xcode project, and README.
