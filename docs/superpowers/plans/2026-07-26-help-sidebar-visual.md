# Help Sidebar Visual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Help window's visible radio controls with text navigation that uses a left accent bar, and give the reading area a solid white background.

**Architecture:** Keep chapter selection and scroll restoration in `HelpWindowController`. Add a small `HelpNavigationButton` AppKit subclass for drawing the selected accent bar, while `HelpContentView` owns the white backgrounds for its scroll and document surfaces.

**Tech Stack:** Swift 5, AppKit, XCTest, Xcode 17

---

### Task 1: Preserve the Existing Help Window Sizing Fix

**Files:**
- Modify: `platforms/mac/Sources/App/HelpWindowController.swift`
- Test: `platforms/mac/Tests/HelpManualTests.swift`

- [ ] **Step 1: Run the focused English-window regression test**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/HelpManualTests/testBundledEnglishHelpWindowShowsSidebarAndBody
```

Expected: PASS. The test verifies that the English Help window still loads the
Chinese fallback manual and keeps a content area taller than 500 points.

- [ ] **Step 2: Commit the already-verified sizing fix**

```bash
git add platforms/mac/Sources/App/HelpWindowController.swift \
  platforms/mac/Tests/HelpManualTests.swift
git commit -m "fix(mac): preserve full help window content"
```

### Task 2: Specify Text Navigation and White Reading Backgrounds

**Files:**
- Test: `platforms/mac/Tests/HelpManualTests.swift`

- [ ] **Step 1: Replace the radio-specific test with the desired button semantics**

Replace `testSidebarUsesRadioGroupAccessibilitySemantics` with assertions that
exercise the real sidebar:

```swift
@MainActor
func testSidebarUsesBorderlessButtonsWithAccentSelection() throws {
    let controller = makeController()
    defer { controller.close() }

    controller.show()

    let root = try XCTUnwrap(controller.window?.contentView)
    let buttons = descendantViews(of: NSButton.self, in: root)
        .filter { ["截图", "贴图", "文字识别", "教笔"].contains($0.title) }

    XCTAssertEqual(buttons.count, 4)
    XCTAssertTrue(buttons.allSatisfy { $0.accessibilityRole() == .button })
    XCTAssertTrue(buttons.allSatisfy { !$0.isBordered })
    XCTAssertEqual(controller.test_selectedNavigationIndicators, ["capture"])

    controller.test_clickNavigationButton("pin")

    XCTAssertEqual(controller.test_selectedNavigationIndicators, ["pin"])
}
```

- [ ] **Step 2: Add a focused white-background test**

```swift
@MainActor
func testHelpReadingAreaUsesSolidWhiteBackground() throws {
    let controller = makeController()
    defer { controller.close() }

    controller.show()

    XCTAssertTrue(controller.test_contentUsesWhiteBackground)
}
```

- [ ] **Step 3: Run the two new tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/HelpManualTests/testSidebarUsesBorderlessButtonsWithAccentSelection \
  -only-testing:xxsnapTests/HelpManualTests/testHelpReadingAreaUsesSolidWhiteBackground
```

Expected: FAIL because the sidebar still exposes radio controls and neither
test inspection property exists yet.

### Task 3: Implement the Confirmed B Visual Treatment

**Files:**
- Modify: `platforms/mac/Sources/App/HelpWindowController.swift`
- Modify: `platforms/mac/Sources/App/HelpContentView.swift`
- Test: `platforms/mac/Tests/HelpManualTests.swift`

- [ ] **Step 1: Add a borderless navigation button with a selected accent bar**

Add a file-private AppKit button in `HelpWindowController.swift`:

```swift
@MainActor
private final class HelpNavigationButton: NSButton {
    var isCurrent = false {
        didSet {
            font = .systemFont(
                ofSize: 14,
                weight: isCurrent ? .semibold : .regular
            )
            setAccessibilitySelected(isCurrent)
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isCurrent else { return }

        NSColor.controlAccentColor.setFill()
        NSBezierPath(
            rect: NSRect(
                x: 0,
                y: 5,
                width: 3,
                height: max(0, bounds.height - 10)
            )
        ).fill()
    }
}
```

Construct each chapter entry as an unbordered button:

```swift
let button = HelpNavigationButton(
    title: chapter.navigationTitle,
    target: self,
    action: #selector(selectNavigationButton(_:))
)
button.setButtonType(.momentaryChange)
button.setAccessibilityRole(.button)
button.isBordered = false
button.alignment = .left
button.contentTintColor = .labelColor
```

Change the navigation stack role from `.radioGroup` to `.group`. In
`updateNavigationSelection`, set `isCurrent` on each `HelpNavigationButton` and
keep its accessibility selected state synchronized.

- [ ] **Step 2: Expose focused selection state for tests**

Add this controller inspection property:

```swift
var test_selectedNavigationIndicators: [String] {
    navigationButtons.compactMap { chapterID, button in
        (button as? HelpNavigationButton)?.isCurrent == true
            ? chapterID
            : nil
    }.sorted()
}
```

- [ ] **Step 3: Give every reading surface a white background**

In `HelpContentView.configureLayout`:

```swift
wantsLayer = true
layer?.backgroundColor = NSColor.white.cgColor

scrollView.drawsBackground = true
scrollView.backgroundColor = .white
scrollView.contentView.drawsBackground = true
scrollView.contentView.backgroundColor = .white

documentView.wantsLayer = true
documentView.layer?.backgroundColor = NSColor.white.cgColor
```

Expose a focused test property:

```swift
var test_usesWhiteBackground: Bool {
    layer?.backgroundColor == NSColor.white.cgColor
        && scrollView.backgroundColor == .white
        && scrollView.contentView.backgroundColor == .white
        && documentView.layer?.backgroundColor == NSColor.white.cgColor
}
```

Forward it from `HelpWindowController`:

```swift
var test_contentUsesWhiteBackground: Bool {
    contentView?.test_usesWhiteBackground == true
}
```

- [ ] **Step 4: Run the two focused tests and verify GREEN**

Run the command from Task 2, Step 3.

Expected: both tests PASS.

- [ ] **Step 5: Run the complete related test set**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived test \
  -only-testing:xxsnapTests/HelpManualTests \
  -only-testing:xxsnapTests/AppSettingsTests
```

Expected: all Help and settings tests PASS.

- [ ] **Step 6: Commit the visual change**

```bash
git add platforms/mac/Sources/App/HelpWindowController.swift \
  platforms/mac/Sources/App/HelpContentView.swift \
  platforms/mac/Tests/HelpManualTests.swift
git commit -m "feat(mac): clarify help chapter navigation"
```

### Task 4: Build and Restart the Debug App

**Files:**
- Verify: `platforms/mac/xxsnap.xcodeproj`

- [ ] **Step 1: Build the Debug scheme**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap -configuration Debug \
  -derivedDataPath build/xcode-derived build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Restart only the canonical Debug app**

```bash
pkill -f "XxSnap.app/Contents/MacOS/XxSnap" || true
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app
pgrep -af "/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/MacOS/XxSnap"
```

Expected: exactly one canonical XxSnap executable is running.

- [ ] **Step 3: Check the final worktree**

```bash
git diff --check
git status --short --branch
```

Expected: no whitespace errors and no uncommitted implementation files.
