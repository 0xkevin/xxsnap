# xxsnap Rename and Text Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the active v2 product to xxsnap and ship the first mac text annotation tool.

**Architecture:** Treat `project.yml` as the source of truth for Xcode project identity, regenerate the checked-in project with XcodeGen, and keep the shared C++ core namespace/include paths unchanged. Add text annotations to the existing mac overlay annotation model so preview, selection, movement, undo/redo, copy, save, and export all flow through the same `CaptureAnnotation` array used by the existing tools.

**Tech Stack:** Swift/AppKit, XCTest, XcodeGen, xcodebuild, macOS codesign/security tools, CMake for the shared core smoke check.

---

## File Structure

- Modify: `project.yml` to rename targets, scheme, Bundle IDs, product names, signing identity, resources, and test host.
- Historical rename from formerly known as Snipory v2: regenerate/rename `platforms/mac/snipory.xcodeproj` to `platforms/mac/xxsnap.xcodeproj` with XcodeGen.
- Rename resources: `platforms/mac/Resources/Snipory.png`, `platforms/mac/Resources/Snipory.icns`, `platforms/mac/Resources/Icons/Snipory.png`, and `platforms/mac/Resources/Icons/Snipory.icns` to xxsnap names.
- Rename bridge/test files only where the filename is user/product identity rather than core behavior: `Sources/Bridge/SniporyMac-Bridging-Header.h` and `Tests/SniporyMacTests.swift`.
- Modify app identity strings in `platforms/mac/Sources/App/*.swift`.
- Modify overlay model, rendering, interaction, options toolbar, and test helpers in `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`, `SelectionOverlayWindow.swift`, and `SelectionToolbarState.swift`.
- Modify tests in `platforms/mac/Tests/*.swift`.
- Modify docs and commands in `README.md`, relevant `docs/**/*.md`, and platform manual checklists after the directory rename.
- Historical rename from formerly known as Snipory v2: move repository directory from `/Users/kevin/Projects/open-source/Snipory/snipory-v2` to `/Users/kevin/Projects/open-source/Snipory/xxsnap` after this plan has been committed.

---

### Task 1: Add xxsnap Identity Tests Before Renaming

**Files:**
- Modify: `platforms/mac/Tests/AppSettingsTests.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing tests for user-visible product identity**

Add this test to `AppSettingsTests`:

```swift
func testBundleIdentityUsesXxsnap() {
    XCTAssertEqual(Bundle.main.bundleIdentifier, "com.xxsnap.mac")
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "xxsnap")
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "xxsnap")
}
```

Update `testDefaultCaptureFilenameIncludesTimestampToSecond` in `SelectionToolbarStateTests` to expect:

```swift
XCTAssertEqual(
    CaptureCoordinator.defaultCaptureFilename(date: date, timeZone: TimeZone(secondsFromGMT: 0)!),
    "xxsnap 截图 19700101-000000.png"
)
```

Add this test near the refresh self-ignore coverage:

```swift
func testCaptureRefreshIgnoresXxsnapAsRefreshTarget() {
    XCTAssertFalse(
        CaptureCoordinator.shouldRefreshTargetApplication(
            targetBundleIdentifier: "com.xxsnap.mac",
            mainBundleIdentifier: "com.xxsnap.mac"
        )
    )
    XCTAssertTrue(
        CaptureCoordinator.shouldRefreshTargetApplication(
            targetBundleIdentifier: "com.apple.finder",
            mainBundleIdentifier: "com.xxsnap.mac"
        )
    )
}
```

- [ ] **Step 2: Run tests and verify identity failures**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/AppSettingsTests/testBundleIdentityUsesXxsnap -only-testing:xxsnapTests/SelectionToolbarStateTests/testDefaultCaptureFilenameIncludesTimestampToSecond -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureRefreshIgnoresXxsnapAsRefreshTarget
```

Expected: FAIL because the Bundle ID/display name and default filename still use Snipory.

- [ ] **Step 3: Do not implement yet**

Leave these tests failing until Task 2 changes the product identity.

---

### Task 2: Rename mac Product Identity and Signing Configuration

**Files:**
- Modify: `platforms/mac/project.yml`
- Rename: `platforms/mac/Resources/Snipory.png` -> `platforms/mac/Resources/xxsnap.png`
- Rename: `platforms/mac/Resources/Snipory.icns` -> `platforms/mac/Resources/xxsnap.icns`
- Rename: `platforms/mac/Resources/Icons/Snipory.png` -> `platforms/mac/Resources/Icons/xxsnap.png`
- Rename: `platforms/mac/Resources/Icons/Snipory.icns` -> `platforms/mac/Resources/Icons/xxsnap.icns`
- Rename: `platforms/mac/Sources/Bridge/SniporyMac-Bridging-Header.h` -> `platforms/mac/Sources/Bridge/xxsnap-Bridging-Header.h`
- Historical rename from formerly known as Snipory v2: `platforms/mac/snipory.xcodeproj` -> `platforms/mac/xxsnap.xcodeproj`
- Modify: `platforms/mac/Sources/App/AppDelegate.swift`
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift`
- Modify: `platforms/mac/Sources/App/CaptureControlWindowController.swift`
- Modify: `platforms/mac/Sources/App/StatusItemController.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Tests/*.swift`

- [ ] **Step 1: Check for a signing identity**

Run:

```bash
security find-identity -v -p codesigning | rg "xxsnap Local Dev" || true
```

Expected: either one identity line for `xxsnap Local Dev`, or no output.

- [ ] **Step 2: Create local signing identity when missing**

If Step 1 returns no identity, run:

```bash
tmpdir="$(mktemp -d)"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj "/CN=xxsnap Local Dev/" \
  -keyout "$tmpdir/xxsnap-local-dev.key" \
  -out "$tmpdir/xxsnap-local-dev.crt"
openssl pkcs12 -export \
  -inkey "$tmpdir/xxsnap-local-dev.key" \
  -in "$tmpdir/xxsnap-local-dev.crt" \
  -name "xxsnap Local Dev" \
  -passout pass: \
  -out "$tmpdir/xxsnap-local-dev.p12"
security import "$tmpdir/xxsnap-local-dev.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "" -T /usr/bin/codesign -T /usr/bin/security
security find-identity -v -p codesigning | rg "xxsnap Local Dev"
```

Expected: `security find-identity` prints one valid `xxsnap Local Dev` identity. If import fails because the keychain is locked or user approval is required, stop this task and report the exact command output.

- [ ] **Step 3: Rename files**

Run:

```bash
mv platforms/mac/Resources/Snipory.png platforms/mac/Resources/xxsnap.png
mv platforms/mac/Resources/Snipory.icns platforms/mac/Resources/xxsnap.icns
mv platforms/mac/Resources/Icons/Snipory.png platforms/mac/Resources/Icons/xxsnap.png
mv platforms/mac/Resources/Icons/Snipory.icns platforms/mac/Resources/Icons/xxsnap.icns
mv platforms/mac/Sources/Bridge/SniporyMac-Bridging-Header.h platforms/mac/Sources/Bridge/xxsnap-Bridging-Header.h
```

Expected: each `mv` succeeds.

- [ ] **Step 4: Update `project.yml`**

Replace the mac project identity with:

```yaml
name: xxsnap
options:
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: 5.0
    MACOSX_DEPLOYMENT_TARGET: 15.0
    GENERATE_INFOPLIST_FILE: YES
    CURRENT_PROJECT_VERSION: 1
    MARKETING_VERSION: 0.1.0
targets:
  xxsnap:
    type: application
    platform: macOS
    sources:
      - Sources
      - Resources/Assets.xcassets
      - Resources/xxsnap.png
      - Resources/xxsnap.icns
      - Resources/Icons/pin-to-screen.svg
      - Resources/Icons/copy-to-clipboard.svg
      - Resources/Icons/save-to-file.svg
      - Resources/Icons/refresh-svgrepo-com.svg
      - Resources/Icons/refresh-svgrepo-com2.svg
      - Resources/Icons/refresh-left-svgrepo-com.svg
      - Resources/Icons/refresh (1).svg
      - Resources/Icons/refresh-svgrepo-com3.svg
      - Resources/Icons/eyedropper.svg
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.xxsnap.mac
        PRODUCT_NAME: xxsnap
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        INFOPLIST_KEY_CFBundleDisplayName: xxsnap
        INFOPLIST_KEY_CFBundleName: xxsnap
        INFOPLIST_KEY_CFBundleIconFile: xxsnap
        INFOPLIST_KEY_LSUIElement: YES
        ENABLE_DEBUG_DYLIB: NO
        SWIFT_OBJC_BRIDGING_HEADER: Sources/Bridge/xxsnap-Bridging-Header.h
        CODE_SIGN_STYLE: Manual
        CODE_SIGNING_ALLOWED: YES
        CODE_SIGNING_REQUIRED: YES
        CODE_SIGN_IDENTITY: "xxsnap Local Dev"
  xxsnapTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests
    dependencies:
      - target: xxsnap
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.xxsnap.mac.tests
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/xxsnap.app/Contents/MacOS/xxsnap"
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGNING_REQUIRED: NO
        CODE_SIGN_IDENTITY: ""
schemes:
  xxsnap:
    build:
      targets:
        xxsnap: all
        xxsnapTests: [test]
    test:
      targets:
        - name: xxsnapTests
```

- [ ] **Step 5: Regenerate and rename the Xcode project**

Run:

```bash
rm -rf platforms/mac/snipory.xcodeproj # formerly known as Snipory v2 project path
(
  cd platforms/mac
  xcodegen generate
)
test -d platforms/mac/xxsnap.xcodeproj
test -f platforms/mac/xxsnap.xcodeproj/xcshareddata/xcschemes/xxsnap.xcscheme
```

Expected: `xcodegen` succeeds and `xxsnap.xcodeproj` exists.

- [ ] **Step 6: Rename Swift module imports in tests**

Run:

```bash
perl -pi -e 's/@testable import Snipory/@testable import xxsnap/g' platforms/mac/Tests/*.swift
```

Expected: no test file imports `Snipory`.

- [ ] **Step 7: Replace user-visible product strings**

Apply these replacements in app and overlay code:

```swift
// AppDelegate.swift
NSLog("xxsnap applicationDidFinishLaunching")
ProcessInfo.processInfo.disableAutomaticTermination("xxsnap menu bar app stays available for capture")
NSLog("xxsnap applicationWillTerminate")
let hotKeyID = EventHotKeyID(signature: fourCharacterCode("xxsp"), id: 1)
NSLog("xxsnap hotkey handler install failed status=%d", handlerStatus)
NSLog("xxsnap registered hotkey command-backtick")
NSLog("xxsnap hotkey registration failed status=%d", hotKeyStatus)

// StatusItemController.swift
NSLog("xxsnap configuring status item")
NSLog("xxsnap status item has no button")
let image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "xxsnap")
    ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "xxsnap")
button.toolTip = "xxsnap 截图"
NSLog("xxsnap status button configured image=%@ length=%.0f", image == nil ? "missing" : "ok", statusItem.length)

// CaptureControlWindowController.swift
window.title = "xxsnap"

// CaptureCoordinator.swift
alert.informativeText = "请在系统设置中允许 xxsnap 录屏，然后退出并重新打开 xxsnap。"
alert.messageText = "xxsnap 没有录屏权限"
alert.informativeText = "请在系统设置 > 隐私与安全性 > 录屏与系统录音中打开 xxsnap。打开后需要重启 xxsnap。"
return "xxsnap 截图 \(formatter.string(from: date)).png"
```

Also replace `NSLog` prefixes in touched overlay/app files from `snipory` or `Snipory` to `xxsnap` when the message is product-facing diagnostic text.

- [ ] **Step 8: Run identity tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/AppSettingsTests/testBundleIdentityUsesXxsnap -only-testing:xxsnapTests/SelectionToolbarStateTests/testDefaultCaptureFilenameIncludesTimestampToSecond -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureRefreshIgnoresXxsnapAsRefreshTarget
```

Expected: PASS.

- [ ] **Step 9: Commit product identity rename**

Run:

```bash
git add platforms/mac/project.yml platforms/mac/xxsnap.xcodeproj platforms/mac/Resources platforms/mac/Sources platforms/mac/Tests
git add -u platforms/mac
git commit -m "build(mac): rename app identity to xxsnap"
```

Expected: commit succeeds.

---

### Task 3: Rename v2 Directory to `xxsnap`

**Files:**
- Historical rename from formerly known as Snipory v2: `/Users/kevin/Projects/open-source/Snipory/snipory-v2` -> `/Users/kevin/Projects/open-source/Snipory/xxsnap`
- Modify: `README.md`
- Modify: `docs/**/*.md`
- Leave external workspace instructions unchanged; update only files tracked by this repository.

- [ ] **Step 1: Leave the repo directory**

Run:

```bash
cd /Users/kevin/Projects/open-source/Snipory
```

Expected: current directory is the workspace root.

- [ ] **Step 2: Move the repository**

Run:

```bash
mv snipory-v2 xxsnap # formerly known as Snipory v2 directory
cd /Users/kevin/Projects/open-source/Snipory/xxsnap
git status --short --branch
```

Expected: same branch `feat/xxsnap-text-rename`; no new changes solely from the directory move because `.git` moved with the directory.

- [ ] **Step 3: Update README run commands**

Replace the README header and restart commands with:

```markdown
# xxsnap

xxsnap is the native-shell screenshot and annotation rewrite formerly known as Snipory v2:

- shared C++ core
- native macOS shell
- future native Windows shell

The legacy Qt project remains in `../snipory` as a migration reference.

Restart command:

```bash
pkill -f "/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/xxsnap.app/Contents/MacOS/xxsnap" || true
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/xxsnap.app
pgrep -af "xxsnap.app/Contents/MacOS/xxsnap"
```
```

- [ ] **Step 4: Update docs paths and command examples**

Run these targeted replacements:

```bash
perl -pi -e 's/Snipory v2/xxsnap/g; s/snipory-v2/xxsnap/g; s/Snipory\\.app/xxsnap.app/g; s/Contents\\/MacOS\\/Snipory/Contents\\/MacOS\\/xxsnap/g; s/platforms\\/mac\\/snipory\\.xcodeproj/platforms\\/mac\\/xxsnap.xcodeproj/g; s/-scheme snipory/-scheme xxsnap/g; s/sniporyTests/xxsnapTests/g' README.md docs/**/*.md platforms/mac/Tests/manual-capture-checklist.md platforms/mac/packaging/README.md platforms/win/**/*.md # formerly known as Snipory v2 replacement recipe
```

Then manually inspect the references to `../snipory` and keep them unchanged because the legacy Qt project is still the migration reference.

- [ ] **Step 5: Rename project title in CMake only**

Change the top-level `CMakeLists.txt` project line to:

```cmake
project(xxsnap LANGUAGES CXX)
```

Do not rename `snipory_core`, include paths, or C++ namespaces in this task.

- [ ] **Step 6: Run docs/path scan**

Run:

```bash
rg -n "snipory-v2|Snipory\\.app|Contents/MacOS/Snipory|com\\.snipory\\.v2\\.mac|Snipory 截图|Snipory 没有录屏权限" README.md docs platforms/mac platforms/win CMakeLists.txt # formerly known as Snipory v2 stale scan
```

Expected: no output, except historical references in committed design/plan docs where the text explicitly says “formerly known as” or `../snipory`.

- [ ] **Step 7: Verify build from new path**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit directory/docs rename**

Run:

```bash
git add README.md CMakeLists.txt docs platforms/mac/Tests/manual-capture-checklist.md platforms/mac/packaging/README.md platforms/win
git commit -m "docs: move v2 workflow to xxsnap"
```

Expected: commit succeeds.

---

### Task 4: Add Text Annotation Model and Renderer Tests

**Files:**
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Tests/SniporyMacTests.swift` or renamed `platforms/mac/Tests/xxsnapMacTests.swift`

- [ ] **Step 1: Rename test file if not already renamed**

If Task 2 did not rename `SniporyMacTests.swift`, run:

```bash
mv platforms/mac/Tests/SniporyMacTests.swift platforms/mac/Tests/xxsnapMacTests.swift
```

Then rename the class:

```swift
final class xxsnapMacTests: XCTestCase {
```

- [ ] **Step 2: Write failing renderer test**

Add this test to the mac renderer test file:

```swift
func testAnnotationRendererDrawsTextAnnotation() throws {
    let image = try makeSolidImage(size: NSSize(width: 180, height: 100), color: .white)
    var style = CaptureAnnotationStyle()
    style.strokeColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    style.textSize = 24

    let annotation = CaptureAnnotation(
        kind: .text,
        rect: NSRect(x: 24, y: 28, width: 80, height: 34),
        style: style,
        text: "Hi"
    )

    let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [annotation])
    let cgImage = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))

    var foundRedPixel = false
    for y in 25..<70 {
        for x in 20..<120 {
            let pixel = try rgbaPixel(in: cgImage, x: x, y: y)
            if pixel.red > 180 && pixel.green < 90 && pixel.blue < 90 && pixel.alpha == 255 {
                foundRedPixel = true
                break
            }
        }
        if foundRedPixel {
            break
        }
    }

    XCTAssertTrue(foundRedPixel)
}
```

- [ ] **Step 3: Run renderer test and verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/xxsnapMacTests/testAnnotationRendererDrawsTextAnnotation
```

Expected: FAIL because `.text`, `style.textSize`, and `CaptureAnnotation.text` do not exist yet.

- [ ] **Step 4: Add text model fields**

In `CaptureAnnotationRenderer.swift`, update `CaptureAnnotationKind`:

```swift
enum CaptureAnnotationKind {
    case rectangle
    case ellipse
    case arrowLine
    case brush
    case marker
    case mosaicStroke
    case mosaicRectangle
    case text
}
```

Update `CaptureAnnotationStyle`:

```swift
struct CaptureAnnotationStyle {
    var strokeColor: NSColor = NSColor(calibratedRed: 245 / 255, green: 34 / 255, blue: 45 / 255, alpha: 1)
    var strokeWidth: CGFloat = 3
    var strokePattern: CaptureStrokePattern = .solid
    var fillEnabled = false
    var fillColor: NSColor = NSColor(calibratedRed: 245 / 255, green: 34 / 255, blue: 45 / 255, alpha: 1)
    var cornerRadius: CGFloat = 0
    var textSize: CGFloat = 24
}
```

Update `CaptureAnnotation`:

```swift
struct CaptureAnnotation {
    var kind: CaptureAnnotationKind
    var rect: NSRect
    var style: CaptureAnnotationStyle
    var rotationAngle: CGFloat = 0
    var arrowLine: CaptureArrowLine?
    var brushPath: CaptureBrushPath?
    var markerLine: CaptureMarkerLine?
    var mosaicStroke: CaptureMosaicStroke?
    var mosaicRedaction: CaptureMosaicRedaction?
    var text: String?
}
```

- [ ] **Step 5: Add shared text attributes**

In `CaptureAnnotationRenderer`, add:

```swift
static func textFont(size: CGFloat) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: .medium)
}

static func textAttributes(style: CaptureAnnotationStyle) -> [NSAttributedString.Key: Any] {
    [
        .font: textFont(size: style.textSize),
        .foregroundColor: style.strokeColor,
    ]
}
```

- [ ] **Step 6: Draw text in export renderer**

In `draw(_ annotation:in:scaleX:scaleY:)`, before shape drawing, add:

```swift
if annotation.kind == .text {
    drawTextAnnotation(annotation, in: context, scaleX: scaleX, scaleY: scaleY)
    return
}
```

Add:

```swift
private static func drawTextAnnotation(_ annotation: CaptureAnnotation, in context: CGContext, scaleX: CGFloat, scaleY: CGFloat) {
    guard let text = annotation.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
    }

    let rect = annotation.rect.standardized
    let pixelRect = CGRect(
        x: rect.minX * scaleX,
        y: rect.minY * scaleY,
        width: rect.width * scaleX,
        height: rect.height * scaleY
    )
    let scaledStyle = CaptureAnnotationStyle(
        strokeColor: annotation.style.strokeColor,
        strokeWidth: annotation.style.strokeWidth,
        strokePattern: annotation.style.strokePattern,
        fillEnabled: annotation.style.fillEnabled,
        fillColor: annotation.style.fillColor,
        cornerRadius: annotation.style.cornerRadius,
        textSize: annotation.style.textSize * ((scaleX + scaleY) / 2)
    )
    let attributed = NSAttributedString(string: text, attributes: textAttributes(style: scaledStyle))
    NSGraphicsContext.saveGraphicsState()
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = graphicsContext
    attributed.draw(in: pixelRect)
    NSGraphicsContext.restoreGraphicsState()
}
```

If Swift does not synthesize that memberwise initializer after adding the field, set `var scaledStyle = annotation.style` and then assign `scaledStyle.textSize = ...`.

- [ ] **Step 7: Draw text in overlay preview**

In `SelectionOverlayWindow.swift`, at the top of `drawAnnotation(_:inOverlay:)`, add:

```swift
if annotation.kind == .text {
    drawTextAnnotation(annotation, inOverlay: inOverlay)
    return
}
```

Add:

```swift
private func drawTextAnnotation(_ annotation: CaptureAnnotation, inOverlay: Bool) {
    guard let text = annotation.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
    }
    let rect = inOverlay ? overlayRect(fromLocalAnnotationRect: annotation.rect) : annotation.rect
    text.draw(
        in: rect.standardized,
        withAttributes: CaptureAnnotationRenderer.textAttributes(style: annotation.style)
    )
}
```

- [ ] **Step 8: Update switch exhaustiveness**

Update all `switch CaptureAnnotationKind` statements to include `.text`. For support helpers use:

```swift
case .text:
    return true
```

for post-draw editing, and:

```swift
case .text:
    return false
```

for geometry handle editing.

- [ ] **Step 9: Run renderer test and verify pass**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/xxsnapMacTests/testAnnotationRendererDrawsTextAnnotation
```

Expected: PASS.

- [ ] **Step 10: Commit model and renderer**

Run:

```bash
git add platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests
git commit -m "feat(mac): render text annotations"
```

Expected: commit succeeds.

---

### Task 5: Implement Text Tool Creation and Editing

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Add failing text tool interaction tests**

Add these tests to `SelectionToolbarStateTests`:

```swift
func testClickingTextToolTogglesTextModeAndSelectedState() {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 240, height: 160))

    guard let point = window.test_mainToolbarButtonPoint(for: .text) else {
        return XCTFail("Expected text toolbar button")
    }

    window.test_mouseDown(at: point)
    window.test_mouseUp(at: point)

    XCTAssertTrue(window.test_isTextToolActive)
    XCTAssertTrue(window.test_textToolbarButtonIsSelected)
    XCTAssertEqual(window.test_optionsToolbarMode, .text)
}

func testTextToolCreatesEditableAnnotationAndCommitsTypedText() {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 240, height: 160))
    window.test_activateTextTool()

    window.test_mouseDown(at: NSPoint(x: 140, y: 150))
    window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "a")
    window.test_keyDown(keyCode: 11, charactersIgnoringModifiers: "b")
    window.test_keyDown(keyCode: 36, charactersIgnoringModifiers: "\r")

    XCTAssertEqual(window.test_selectedAnnotationKind, .text)
    XCTAssertEqual(window.test_textAnnotation(at: 0), "ab")
    XCTAssertFalse(window.test_isEditingTextAnnotation)
}

func testEmptyTextDraftIsDiscardedOnEscape() {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 240, height: 160))
    window.test_activateTextTool()

    window.test_mouseDown(at: NSPoint(x: 140, y: 150))
    window.test_keyDown(keyCode: 53)

    XCTAssertNil(window.test_annotationRect(at: 0))
    XCTAssertFalse(window.test_isEditingTextAnnotation)
}
```

Add `.text` to `TestToolbarButton`.

- [ ] **Step 2: Run text interaction tests and verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testClickingTextToolTogglesTextModeAndSelectedState -only-testing:xxsnapTests/SelectionToolbarStateTests/testTextToolCreatesEditableAnnotationAndCommitsTypedText -only-testing:xxsnapTests/SelectionToolbarStateTests/testEmptyTextDraftIsDiscardedOnEscape
```

Expected: FAIL because text mode helpers and behavior do not exist.

- [ ] **Step 3: Add text tool state**

In `SelectionOverlayWindow.swift`, add state near the other tool state:

```swift
private var isTextToolActive = false
private var editingTextAnnotationIndex: Int?
private var textDraftCreatedDuringCurrentEdit = false
private let defaultTextAnnotationSize = NSSize(width: 160, height: 36)
```

- [ ] **Step 4: Add text mode activation helpers**

Add:

```swift
private func toggleTextTool() {
    commitCurrentTextEdit()
    if isTextToolActive {
        isTextToolActive = false
        selectedAnnotationIndex = nil
        invalidateCursorRectsAndRefresh()
        return
    }

    rememberCurrentStyleForActiveTool()
    isTextToolActive = true
    isEyedropperToolActive = false
    isShapeToolActive = false
    activeShapeKind = nil
    selectedAnnotationIndex = nil
    showsCornerRadiusPanel = false
    showsStrokeStyleMenu = false
    showsStartArrowTypeMenu = false
    showsEndArrowTypeMenu = false
    shapeStartPoint = nil
    shapeCurrentPoint = nil
    brushDraftPoints.removeAll()
    mosaicDraftPoints.removeAll()
    currentStyle.textSize = 24
    invalidateCursorRectsAndRefresh()
}

private func activateTextTool() {
    if !isTextToolActive {
        toggleTextTool()
    }
}
```

Update `perform(_:)`:

```swift
case .text:
    toggleTextTool()
```

Remove `.text` from the placeholder case.

- [ ] **Step 5: Wire selected state and toolbar mode**

Update `buttonMatchesCurrentTool`:

```swift
case .text:
    return isTextToolActive
```

Add `.text` to `SelectionToolbarState.OptionsToolbarMode` and make `optionsToolbarMode` return `.text` when `isTextToolActive`.

Update `SelectionToolbarState.shouldShowOptionsToolbar` or the caller to show options for text mode.

- [ ] **Step 6: Add text annotation creation**

Add:

```swift
private func beginTextEditing(at point: NSPoint) {
    guard let lockedSelectionRect = lockedSelectionRect?.standardized, lockedSelectionRect.contains(point) else {
        return
    }
    let localPoint = localPoint(fromOverlayPoint: point, selectionRect: lockedSelectionRect)
    var rect = NSRect(origin: localPoint, size: defaultTextAnnotationSize)
    rect.origin.x = min(rect.origin.x, max(0, lockedSelectionRect.width - rect.width))
    rect.origin.y = min(rect.origin.y, max(0, lockedSelectionRect.height - rect.height))
    var style = currentStyle
    style.strokeWidth = 0
    style.strokePattern = .solid
    style.fillEnabled = false
    style.textSize = currentStyle.textSize == 0 ? 24 : currentStyle.textSize
    let annotation = CaptureAnnotation(kind: .text, rect: rect, style: style, text: "")
    annotations.append(annotation)
    selectedAnnotationIndex = annotations.indices.last
    editingTextAnnotationIndex = selectedAnnotationIndex
    textDraftCreatedDuringCurrentEdit = true
    redoAnnotations.removeAll()
    needsDisplay = true
}
```

At the start of annotation hit testing in `handleAnnotatingMouseDown(at:)`, after toolbar/options handling and before shape drawing, add:

```swift
if isTextToolActive {
    if let hitIndex = annotationIndexForBorder(at: point), annotations[hitIndex].kind == .text {
        selectAnnotation(at: hitIndex)
        editingTextAnnotationIndex = hitIndex
        textDraftCreatedDuringCurrentEdit = false
        needsDisplay = true
        return
    }
    beginTextEditing(at: point)
    return
}
```

- [ ] **Step 7: Add key handling for text editing**

At the top of `handleKeyDown(_:)`, before Escape cancels the whole overlay, add:

```swift
if handleTextEditingKeyDown(event) {
    return true
}
```

Add:

```swift
private func handleTextEditingKeyDown(_ event: NSEvent) -> Bool {
    guard let index = editingTextAnnotationIndex, annotations.indices.contains(index), annotations[index].kind == .text else {
        return false
    }

    if event.keyCode == 53 {
        if textDraftCreatedDuringCurrentEdit, (annotations[index].text ?? "").isEmpty {
            annotations.remove(at: index)
            selectedAnnotationIndex = nil
        }
        editingTextAnnotationIndex = nil
        textDraftCreatedDuringCurrentEdit = false
        needsDisplay = true
        return true
    }

    if event.keyCode == 36 || event.keyCode == 76 {
        commitCurrentTextEdit()
        return true
    }

    if event.keyCode == 51 {
        var text = annotations[index].text ?? ""
        guard !text.isEmpty else {
            if textDraftCreatedDuringCurrentEdit {
                annotations.remove(at: index)
                selectedAnnotationIndex = nil
                editingTextAnnotationIndex = nil
                textDraftCreatedDuringCurrentEdit = false
                needsDisplay = true
                return true
            }
            return false
        }
        text.removeLast()
        updateTextAnnotation(at: index, text: text)
        return true
    }

    guard !event.modifierFlags.contains(.command), let characters = event.characters, !characters.isEmpty else {
        return false
    }

    let filtered = characters.filter { !$0.isNewline && !$0.isControl }
    guard !filtered.isEmpty else {
        return false
    }
    updateTextAnnotation(at: index, text: (annotations[index].text ?? "") + String(filtered))
    return true
}

private func commitCurrentTextEdit() {
    guard let index = editingTextAnnotationIndex, annotations.indices.contains(index) else {
        editingTextAnnotationIndex = nil
        textDraftCreatedDuringCurrentEdit = false
        return
    }
    if (annotations[index].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        annotations.remove(at: index)
        selectedAnnotationIndex = nil
    }
    editingTextAnnotationIndex = nil
    textDraftCreatedDuringCurrentEdit = false
    needsDisplay = true
}
```

- [ ] **Step 8: Measure text annotation rects**

Add:

```swift
private func updateTextAnnotation(at index: Int, text: String) {
    guard annotations.indices.contains(index), annotations[index].kind == .text else {
        return
    }
    annotations[index].text = text
    annotations[index].rect.size = textAnnotationSize(text: text, style: annotations[index].style)
    redoAnnotations.removeAll()
    needsDisplay = true
}

private func textAnnotationSize(text: String, style: CaptureAnnotationStyle) -> NSSize {
    let displayText = text.isEmpty ? "文字" : text
    let bounds = NSString(string: displayText).boundingRect(
        with: NSSize(width: 480, height: 200),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: CaptureAnnotationRenderer.textAttributes(style: style)
    )
    return NSSize(width: ceil(bounds.width) + 8, height: ceil(bounds.height) + 6)
}
```

- [ ] **Step 9: Add test helpers**

Under `#if DEBUG`, add:

```swift
func test_activateTextTool() {
    activateTextTool()
}

var test_isTextToolActive: Bool {
    isTextToolActive
}

var test_textToolbarButtonIsSelected: Bool {
    buttonMatchesCurrentTool(.text)
}

var test_isEditingTextAnnotation: Bool {
    editingTextAnnotationIndex != nil
}

func test_textAnnotation(at index: Int) -> String? {
    guard annotations.indices.contains(index) else {
        return nil
    }
    return annotations[index].text
}
```

Expose these through `SelectionOverlayWindow` test methods.

- [ ] **Step 10: Run text interaction tests and verify pass**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testClickingTextToolTogglesTextModeAndSelectedState -only-testing:xxsnapTests/SelectionToolbarStateTests/testTextToolCreatesEditableAnnotationAndCommitsTypedText -only-testing:xxsnapTests/SelectionToolbarStateTests/testEmptyTextDraftIsDiscardedOnEscape
```

Expected: PASS.

- [ ] **Step 11: Commit text creation/editing**

Run:

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): add editable text annotation tool"
```

Expected: commit succeeds.

---

### Task 6: Add Text Move, Delete, Color, and Size Controls

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionToolbarState.swift`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Add failing behavior tests**

Add:

```swift
func testTextAnnotationCanMoveDeleteAndChangeColor() {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 180))
    window.test_activateTextTool()
    window.test_mouseDown(at: NSPoint(x: 140, y: 150))
    window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "a")
    window.test_keyDown(keyCode: 36, charactersIgnoringModifiers: "\r")

    let before = window.test_annotationRect(at: 0)
    window.test_mouseDown(at: NSPoint(x: 145, y: 155))
    window.test_mouseDragged(to: NSPoint(x: 175, y: 175))
    window.test_mouseUp(at: NSPoint(x: 175, y: 175))
    let after = window.test_annotationRect(at: 0)

    XCTAssertNotEqual(before?.origin.x, after?.origin.x)
    XCTAssertNotEqual(before?.origin.y, after?.origin.y)

    window.test_selectPaletteColor(index: 1)
    XCTAssertEqual(window.test_annotationStyle(at: 0)?.strokeColor, window.test_paletteColor(at: 1))

    window.test_keyDown(keyCode: 51)
    XCTAssertNil(window.test_annotationRect(at: 0))
}

func testTextOptionsToolbarUsesThreeFontSizes() {
    XCTAssertEqual(SelectionToolbarState.textSizeValues, [16, 24, 32])

    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 180))
    window.test_activateTextTool()
    XCTAssertEqual(window.test_optionsToolbarMode, .text)
    XCTAssertEqual(window.test_textSizeOptionsCount, 3)
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testTextAnnotationCanMoveDeleteAndChangeColor -only-testing:xxsnapTests/SelectionToolbarStateTests/testTextOptionsToolbarUsesThreeFontSizes
```

Expected: FAIL because text move/style controls are incomplete.

- [ ] **Step 3: Add text toolbar mode**

In `SelectionToolbarState`, add:

```swift
static let textSizeValues: [CGFloat] = [16, 24, 32]
```

Add `.text` to `OptionsToolbarMode`.

Update `strokeWidthValues(for:)`, layout, separators, and `showsStrokeStyleField(for:)` so `.text` has no stroke style, no fill, and three text-size buttons plus color swatches.

- [ ] **Step 4: Draw text size controls**

In `drawOptionsToolbar(for:)`, for `.text` draw three buttons:

```swift
private func drawTextSizeControls(in optionsRect: NSRect) {
    let rects = textSizeRects(in: optionsRect)
    for (index, rect) in rects.enumerated() {
        let size = SelectionToolbarState.textSizeValues[index]
        drawToolbarButton(optionButtonBackgroundRect(for: rect), symbol: nil, selected: currentStyle.textSize == size, enabled: true)
        let label = "\(Int(size))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: currentStyle.textSize == size ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let textSize = NSString(string: label).size(withAttributes: attributes)
        NSString(string: label).draw(
            in: NSRect(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2, width: textSize.width, height: textSize.height),
            withAttributes: attributes
        )
    }
}
```

Use a helper `textSizeRects(in:)` parallel to existing stroke width rect helpers.

- [ ] **Step 5: Handle text option clicks**

In `handleOptionsClick(at:)`, add:

```swift
if optionsToolbarMode == .text {
    for (index, rect) in textSizeRects(in: optionsRect).enumerated() where optionButtonBackgroundRect(for: rect).contains(point) {
        currentStyle.textSize = SelectionToolbarState.textSizeValues[index]
        rememberCurrentStyleForActiveTool()
        applyCurrentStyleToSelectedAnnotation()
        if let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex), annotations[selectedAnnotationIndex].kind == .text {
            annotations[selectedAnnotationIndex].rect.size = textAnnotationSize(
                text: annotations[selectedAnnotationIndex].text ?? "",
                style: annotations[selectedAnnotationIndex].style
            )
        }
        needsDisplay = true
        return true
    }
}
```

- [ ] **Step 6: Let text annotations move and delete**

Update `annotationBorderContains` for `.text`:

```swift
if annotation.kind == .text {
    return overlayRect(fromLocalAnnotationRect: annotation.rect).standardized.insetBy(dx: -4, dy: -4).contains(point)
}
```

Update `activeToolCanEdit(annotationKind:)`:

```swift
case .text:
    return kind == .text
```

Update `selectAnnotation(at:)` to activate text mode for `.text` without calling `activateShapeTool`:

```swift
if annotation.kind == .text {
    isTextToolActive = true
    isShapeToolActive = false
    isEyedropperToolActive = false
    currentStyle = annotation.style
    return
}
```

The existing `deleteSelectedAnnotation()` and move code should then work for text because text uses `rect`.

- [ ] **Step 7: Apply style updates to text**

Ensure `SelectionToolbarState.annotationKindSupportsPostDrawEditing(.text)` returns `true` and `updatedSelectedAnnotationStyle` keeps `.text` kind unchanged. In `applyCurrentStyleToSelectedAnnotation`, skip the branch that assigns `annotations[selectedAnnotationIndex].kind = currentShapeKind` when selected kind is `.text`.

- [ ] **Step 8: Add missing test helpers**

Add debug helpers:

```swift
var test_textSizeOptionsCount: Int {
    guard let optionsToolbarRect else {
        return 0
    }
    return textSizeRects(in: optionsToolbarRect).count
}

func test_selectPaletteColor(index: Int) {
    guard let optionsToolbarRect, colorSwatchRects(in: optionsToolbarRect).indices.contains(index) else {
        return
    }
    _ = handleOptionsClick(at: colorSwatchRects(in: optionsToolbarRect)[index].center)
}

func test_paletteColor(at index: Int) -> NSColor? {
    guard colors.indices.contains(index) else {
        return nil
    }
    return colors[index]
}
```

If `NSRect.center` does not exist, use `NSPoint(x: rect.midX, y: rect.midY)`.

- [ ] **Step 9: Run behavior tests and verify pass**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testTextAnnotationCanMoveDeleteAndChangeColor -only-testing:xxsnapTests/SelectionToolbarStateTests/testTextOptionsToolbarUsesThreeFontSizes
```

Expected: PASS.

- [ ] **Step 10: Commit text styling and editing controls**

Run:

```bash
git add platforms/mac/Sources/Overlay/SelectionToolbarState.swift platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): add text style controls"
```

Expected: commit succeeds.

---

### Task 7: Verify Full Test Suite, Signing, and Runtime Registration

**Files:**
- No source files expected unless verification finds a bug.

- [ ] **Step 1: Run Swift tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Expected: all `xxsnapTests` pass.

- [ ] **Step 2: Run CMake core tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake -S . -B build -DBUILD_TESTING=ON -DCMAKE_PREFIX_PATH="$(brew --prefix qtbase)"
cmake --build build
ctest --test-dir build --output-on-failure
```

Expected: core build succeeds and all CTest tests pass.

- [ ] **Step 3: Verify signing identity on built app**

Run:

```bash
codesign -dv --verbose=4 build/xcode-derived/Build/Products/Debug/xxsnap.app 2>&1 | rg "Authority|Identifier|TeamIdentifier"
```

Expected: output includes `Authority=xxsnap Local Dev` and `Identifier=com.xxsnap.mac`.

- [ ] **Step 4: Stop old Snipory instances**

Run:

```bash
pkill -f "/Users/kevin/Projects/open-source/Snipory/snipory-v2/build/xcode-derived/Build/Products/Debug/Snipory.app/Contents/MacOS/Snipory" || true
pkill -f "Snipory.app/Contents/MacOS/Snipory" || true
pgrep -af "Snipory.app/Contents/MacOS/Snipory" || true
```

Expected: final `pgrep` prints no old Snipory process.

- [ ] **Step 5: Launch xxsnap debug app**

Run:

```bash
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/xxsnap.app
pgrep -af "xxsnap.app/Contents/MacOS/xxsnap"
```

Expected: one running xxsnap debug app process.

- [ ] **Step 6: Manual text smoke check**

Use the running menu bar app:

1. Start capture with the status item or command-backtick.
2. Create a selection.
3. Click the text tool.
4. Click inside the selection and type `xxsnap`.
5. Press Enter to commit.
6. Move the text annotation.
7. Change color and size.
8. Copy or save the screenshot.

Expected: the copied/saved image contains the moved, styled text. If macOS asks for screen-recording permission for `xxsnap`, grant it and restart the app.

- [ ] **Step 7: Commit verification fixes if any**

If verification required source changes, run:

```bash
git add platforms/mac/Sources platforms/mac/Tests platforms/mac/project.yml platforms/mac/xxsnap.xcodeproj README.md docs CMakeLists.txt
git commit -m "fix(mac): stabilize xxsnap text tool"
```

Expected: commit succeeds. Skip this step if verification found no issues and the working tree is clean.

---

## Self-Review Checklist

- Spec coverage: Tasks cover product rename, Bundle ID, signing identity, old-process stop, directory rename, text create/edit/move/delete/color/size, preview/export, tests, and manual smoke validation.
- Scope control: Legacy `../snipory`, shared C++ namespace/include paths, rich text, custom fonts, rotation, and cross-platform text model are explicitly out of scope.
- Type consistency: Text model uses `CaptureAnnotationKind.text`, `CaptureAnnotation.text`, and `CaptureAnnotationStyle.textSize`; all test helpers reference those names.
- Verification: Xcode tests, CMake tests, codesign inspection, process cleanup, app launch, and manual smoke check are included.
