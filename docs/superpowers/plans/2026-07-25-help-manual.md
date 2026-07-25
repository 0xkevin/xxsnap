# XxSnap Help Manual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native in-app Chinese help manual opened from the status menu, with detailed screenshot, pin, OCR, and teaching-pen chapters plus real XxSnap screenshots on solid-color backgrounds.

**Architecture:** Decode the manual from a bundled `zh-Hans.json` into focused Swift content models, render its block types with native AppKit views, and keep the help window independent from settings and capture lifecycles. Bundle the complete `Help` resource folder so Chinese text and images remain editable without embedding long prose in Swift; fall back to Chinese until the approved English manual is added.

**Tech Stack:** Swift 5, AppKit, Foundation `Codable`, XCTest, Xcode project resources, macOS `screencapture`.

---

## File Structure

Create:

- `platforms/mac/Sources/App/HelpContent.swift`
  Owns decoded document types, validation errors, resource lookup, and `HelpContentLoading`.
- `platforms/mac/Sources/App/HelpContentView.swift`
  Renders headings, paragraphs, steps, lists, shortcut tables, figures, notes, warnings, and FAQs as native AppKit views.
- `platforms/mac/Sources/App/HelpImagePreviewController.swift`
  Presents and dismisses a bounded large-image preview without changing chapter state.
- `platforms/mac/Sources/App/HelpWindowController.swift`
  Owns the window, four-item sidebar, selected chapter, per-chapter scroll positions, error page, and window reuse behavior.
- `platforms/mac/Tests/HelpManualTests.swift`
  Covers decoding, validation, rendering structure, navigation, preview, fallbacks, bundled content, and menu integration.
- `platforms/mac/Resources/Help/zh-Hans.json`
  Contains all first-release Chinese manual content.
- `platforms/mac/Resources/Help/Images/zh-Hans/*.png`
  Contains the approved overview and focused screenshots.

Modify:

- `platforms/mac/Sources/App/PreferencesSettings.swift`
  Adds localized Help menu/window/error/fallback strings.
- `platforms/mac/Sources/App/StatusItemController.swift`
  Inserts “帮助…” above “关于…” and invokes an injected help callback.
- `platforms/mac/Sources/App/AppDelegate.swift`
  Creates and retains one `HelpWindowController`.
- `platforms/mac/Tests/AppSettingsTests.swift`
  Updates existing lower-menu expectations and verifies Help localization.
- `platforms/mac/xxsnap.xcodeproj/project.pbxproj`
  Adds four Swift sources, one test source, and a folder reference copied to app and test resources.

Do not modify capture, pin, OCR, teaching-pen, annotation, or editor behavior.

### Task 1: Content Model, Decoder, and Validation

**Files:**
- Create: `platforms/mac/Sources/App/HelpContent.swift`
- Create: `platforms/mac/Tests/HelpManualTests.swift`
- Modify: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the test and source files to the Xcode project**

Add `HelpContent.swift` to the app target and `HelpManualTests.swift` to the test target. Do not add resources yet.

- [ ] **Step 2: Write failing model and validation tests**

Add tests using inline JSON so they do not depend on bundled resources:

```swift
import AppKit
import XCTest
@testable import xxsnap

final class HelpManualTests: XCTestCase {
    func testHelpContentLoaderDecodesSupportedBlocks() throws {
        let data = Data(Self.completeDocumentJSON.utf8)
        let document = try HelpContentLoader().decode(data)

        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.language, "zh-Hans")
        XCTAssertEqual(document.chapters.map(\.id), [
            "capture", "pin", "ocr", "teaching-pen",
        ])
        XCTAssertEqual(document.chapters[0].shortcuts[0].keys, ["⌘", "`"])
        XCTAssertEqual(document.chapters[0].blocks.count, 8)
    }

    func testHelpContentLoaderRejectsDuplicateChapterIDs() {
        let json = Self.completeDocumentJSON.replacingOccurrences(
            of: #""id":"pin""#,
            with: #""id":"capture""#
        )

        XCTAssertThrowsError(try HelpContentLoader().decode(Data(json.utf8))) {
            XCTAssertEqual($0 as? HelpContentError, .duplicateChapterID("capture"))
        }
    }

    func testHelpContentLoaderRejectsEmptyChapterList() {
        let json = """
        {"version":1,"language":"zh-Hans","windowTitle":"XxSnap 帮助","chapters":[]}
        """

        XCTAssertThrowsError(try HelpContentLoader().decode(Data(json.utf8))) {
            XCTAssertEqual($0 as? HelpContentError, .emptyChapters)
        }
    }

    func testHelpContentLoaderRejectsUnknownBlockType() {
        let json = Self.completeDocumentJSON.replacingOccurrences(
            of: #""type":"paragraph""#,
            with: #""type":"video""#,
            options: [],
            range: Self.completeDocumentJSON.range(of: #""type":"paragraph""#)
        )

        XCTAssertThrowsError(try HelpContentLoader().decode(Data(json.utf8)))
    }
}
```

Define `completeDocumentJSON` with exactly four chapters. The capture chapter must include one block of every supported type:

```swift
private extension HelpManualTests {
    static let completeDocumentJSON = """
    {
      "version": 1,
      "language": "zh-Hans",
      "windowTitle": "XxSnap 帮助",
      "chapters": [
        {
          "id": "capture",
          "navigationTitle": "截图",
          "title": "截图",
          "introduction": "按需要选择区域截图、全屏截图或滚动截图。",
          "tableOfContents": ["区域截图", "标注工具"],
          "shortcuts": [{"action":"区域截图","keys":["⌘","`"]}],
          "blocks": [
            {"type":"heading","level":2,"text":"区域截图"},
            {"type":"paragraph","text":"按住鼠标并拖动，松开后锁定选区。"},
            {"type":"steps","items":[{"text":"启动截图","keys":["⌘","`"]}]},
            {"type":"bullets","items":["拖动边框调整大小"]},
            {"type":"shortcuts","items":[{"action":"复制","keys":["⌘","C"]}]},
            {"type":"image","name":"capture-overview","caption":"区域截图总览","accessibilityLabel":"区域截图界面"},
            {"type":"note","title":"提示","text":"快捷键可以在偏好设置中修改。"},
            {"type":"faq","items":[{"question":"怎么取消？","answer":"按 Esc。"}]}
          ]
        },
        {
          "id": "pin",
          "navigationTitle": "贴图",
          "title": "贴图",
          "introduction": "把截图固定在桌面上。",
          "tableOfContents": ["创建贴图"],
          "shortcuts": [{"action":"贴图","keys":["⌘","1"]}],
          "blocks": [{"type":"paragraph","text":"完成截图后点击贴图。"}]
        },
        {
          "id": "ocr",
          "navigationTitle": "文字识别",
          "title": "文字识别",
          "introduction": "框选文字后自动识别并复制。",
          "tableOfContents": ["开始识别"],
          "shortcuts": [{"action":"识别文字","keys":["⌘","3"]}],
          "blocks": [{"type":"paragraph","text":"松开鼠标后自动识别。"}]
        },
        {
          "id": "teaching-pen",
          "navigationTitle": "教笔",
          "title": "教笔",
          "introduction": "在当前屏幕上直接标注。",
          "tableOfContents": ["开始使用"],
          "shortcuts": [{"action":"教笔","keys":["⌘","2"]}],
          "blocks": [{"type":"warning","title":"注意","text":"再次按快捷键可以退出。"}]
        }
      ]
    }
    """
}
```

- [ ] **Step 3: Run the focused tests and confirm failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test -only-testing:xxsnapTests/HelpManualTests
```

Expected: compilation fails because `HelpContentLoader`, `HelpContentError`, and content models do not exist.

- [ ] **Step 4: Implement the decodable types and validator**

Use these public-internal shapes:

```swift
import AppKit

struct HelpDocument: Decodable, Equatable {
    let version: Int
    let language: String
    let windowTitle: String
    let chapters: [HelpChapter]
}

struct HelpChapter: Decodable, Equatable {
    let id: String
    let navigationTitle: String
    let title: String
    let introduction: String
    let tableOfContents: [String]
    let shortcuts: [HelpShortcut]
    let blocks: [HelpContentBlock]
}

struct HelpShortcut: Decodable, Equatable {
    let action: String
    let keys: [String]
}

struct HelpStep: Decodable, Equatable {
    let text: String
    let keys: [String]?
}

struct HelpFAQItem: Decodable, Equatable {
    let question: String
    let answer: String
}

enum HelpContentBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case steps([HelpStep])
    case bullets([String])
    case shortcuts([HelpShortcut])
    case image(name: String, caption: String, accessibilityLabel: String)
    case note(title: String, text: String)
    case warning(title: String, text: String)
    case faq([HelpFAQItem])
}

enum HelpContentError: Error, Equatable {
    case missingResource(String)
    case emptyChapters
    case duplicateChapterID(String)
    case emptyChapterID
}
```

Give `HelpContentBlock` a custom `Decodable` implementation using a `type` discriminator. Throw `DecodingError.dataCorruptedError` for unknown types. Implement:

```swift
protocol HelpContentLoading {
    func load(language: AppLanguage) throws -> HelpDocument
    func image(named name: String, language: AppLanguage) -> NSImage?
}

final class HelpContentLoader: HelpContentLoading {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func decode(_ data: Data) throws -> HelpDocument {
        let document = try JSONDecoder().decode(HelpDocument.self, from: data)
        try validate(document)
        return document
    }

    func load(language: AppLanguage) throws -> HelpDocument {
        let resourceName = language == .english ? "en" : "zh-Hans"
        let preferredURL = bundle.url(
            forResource: resourceName,
            withExtension: "json",
            subdirectory: "Help"
        )
        let fallbackURL = bundle.url(
            forResource: "zh-Hans",
            withExtension: "json",
            subdirectory: "Help"
        )
        guard let url = preferredURL ?? fallbackURL else {
            throw HelpContentError.missingResource("Help/zh-Hans.json")
        }
        return try decode(Data(contentsOf: url))
    }

    func image(named name: String, language: AppLanguage) -> NSImage? {
        let preferred = language == .english ? "en" : "zh-Hans"
        let subdirectories = [
            "Help/Images/\(preferred)",
            "Help/Images/zh-Hans",
        ]
        for subdirectory in subdirectories {
            if let url = bundle.url(
                forResource: name,
                withExtension: "png",
                subdirectory: subdirectory
            ), let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}
```

Validation must reject an empty chapter list, empty IDs, and duplicate IDs. It must not reject a missing image because image absence is handled by the renderer.

- [ ] **Step 5: Run the focused tests**

Run the command from Step 3.

Expected: all `HelpManualTests` in Task 1 pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add \
  platforms/mac/Sources/App/HelpContent.swift \
  platforms/mac/Tests/HelpManualTests.swift \
  platforms/mac/xxsnap.xcodeproj/project.pbxproj
git commit -m "feat(mac): add help manual content model"
```

### Task 2: Native Chapter Renderer and Help Window

**Files:**
- Create: `platforms/mac/Sources/App/HelpContentView.swift`
- Create: `platforms/mac/Sources/App/HelpImagePreviewController.swift`
- Create: `platforms/mac/Sources/App/HelpWindowController.swift`
- Modify: `platforms/mac/Tests/HelpManualTests.swift`
- Modify: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing window and rendering tests**

Add a `FakeHelpContentLoader` returning the decoded inline document and configurable images. Add tests:

```swift
@MainActor
func testHelpWindowShowsFourChaptersAndStartsOnCapture() throws {
    let loader = FakeHelpContentLoader(document: try sampleDocument())
    let controller = HelpWindowController(
        settingsStore: FakeHelpAppSettingsStore(),
        contentLoader: loader
    )
    defer { controller.close() }

    controller.show()
    controller.window?.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(controller.test_navigationTitles, [
        "截图", "贴图", "文字识别", "教笔",
    ])
    XCTAssertEqual(controller.test_selectedChapterID, "capture")
    XCTAssertEqual(controller.window?.title, "XxSnap 帮助")
}

@MainActor
func testHelpContentViewRendersEverySupportedBlock() throws {
    let loader = FakeHelpContentLoader(document: try sampleDocument())
    loader.images["capture-overview"] = solidImage(
        size: NSSize(width: 800, height: 450),
        color: .systemBlue
    )
    let controller = HelpWindowController(
        settingsStore: FakeHelpAppSettingsStore(),
        contentLoader: loader
    )
    defer { controller.close() }

    controller.show()

    XCTAssertTrue(controller.test_visibleTexts.contains("区域截图"))
    XCTAssertTrue(controller.test_visibleTexts.contains("按住鼠标并拖动，松开后锁定选区。"))
    XCTAssertTrue(controller.test_visibleTexts.contains("怎么取消？"))
    XCTAssertEqual(controller.test_visibleImageCount, 1)
}

@MainActor
func testMissingHelpImageShowsFallbackWithoutHidingText() throws {
    let controller = HelpWindowController(
        settingsStore: FakeHelpAppSettingsStore(),
        contentLoader: FakeHelpContentLoader(document: try sampleDocument())
    )
    defer { controller.close() }

    controller.show()

    XCTAssertTrue(controller.test_visibleTexts.contains("图片暂时无法显示"))
    XCTAssertTrue(controller.test_visibleTexts.contains("区域截图总览"))
}

@MainActor
func testChapterSwitchRestoresInMemoryScrollPosition() throws {
    let controller = makeHelpWindowController()
    defer { controller.close() }
    controller.show()

    controller.test_setScrollOffset(240)
    controller.test_selectChapter(id: "pin")
    controller.test_setScrollOffset(90)
    controller.test_selectChapter(id: "capture")

    XCTAssertEqual(controller.test_scrollOffset, 240, accuracy: 1)
    controller.test_selectChapter(id: "pin")
    XCTAssertEqual(controller.test_scrollOffset, 90, accuracy: 1)
}

@MainActor
func testClickingImagePresentsPreviewAndEscapeDismissesIt() throws {
    let controller = makeHelpWindowController(withCaptureImage: true)
    defer { controller.close() }
    controller.show()

    controller.test_clickFirstImage()
    XCTAssertTrue(controller.test_isImagePreviewVisible)

    controller.test_dismissImagePreview()
    XCTAssertFalse(controller.test_isImagePreviewVisible)
}

@MainActor
func testBrokenHelpDocumentShowsErrorPage() {
    let controller = HelpWindowController(
        settingsStore: FakeHelpAppSettingsStore(),
        contentLoader: ThrowingHelpContentLoader()
    )
    defer { controller.close() }

    controller.show()

    XCTAssertTrue(controller.test_visibleTexts.contains("帮助内容暂时无法打开"))
}
```

- [ ] **Step 2: Run the tests and confirm failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test -only-testing:xxsnapTests/HelpManualTests
```

Expected: compilation fails because the three help UI types do not exist.

- [ ] **Step 3: Implement `HelpContentView`**

Build the page with `NSScrollView` containing a vertical `NSStackView`. Use separate helper methods for each block:

```swift
@MainActor
final class HelpContentView: NSView {
    var onImageSelected: ((NSImage, String) -> Void)?

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let imageLoader: (String) -> NSImage?
    private let imageFallbackText: String

    init(
        imageFallbackText: String,
        imageLoader: @escaping (String) -> NSImage?
    ) {
        self.imageLoader = imageLoader
        self.imageFallbackText = imageFallbackText
        super.init(frame: .zero)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func render(_ chapter: HelpChapter) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        appendPageTitle(chapter)
        appendTableOfContents(chapter.tableOfContents)
        appendShortcutTable(chapter.shortcuts)
        chapter.blocks.forEach(append)
    }

    var scrollOffset: CGFloat {
        get { scrollView.contentView.bounds.origin.y }
        set {
            scrollView.contentView.scroll(
                to: NSPoint(x: 0, y: max(0, newValue))
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
```

Layout rules:

- Page horizontal insets: 44 points; vertical insets: 32/64.
- Maximum readable content width: 760 points, centered when wider.
- Sidebar is not part of `HelpContentView`.
- Use system label and secondary-label colors.
- Use `NSTextField(wrappingLabelWithString:)` for all prose.
- Set content hugging so long text wraps rather than enlarging the window.
- Render shortcut keys as individual fixed-height keycap labels.
- Render note and warning as full-width bands with a three-point leading rule.
- Render an image in a dedicated figure view; calculate height from the image aspect ratio and update on width changes.
- Missing images show `图片暂时无法显示` plus the original caption.
- Set image buttons borderless and add accessibility labels.

- [ ] **Step 4: Implement image preview**

Use a borderless child window or sheet owned by the Help window:

```swift
@MainActor
final class HelpImagePreviewController: NSWindowController {
    private let imageView = NSImageView()
    var onDismiss: (() -> Void)?

    func show(image: NSImage, caption: String, parent: NSWindow) {
        imageView.image = image
        window?.title = caption
        sizeToFit(image: image, visibleFrame: parent.screen?.visibleFrame)
        parent.addChildWindow(window!, ordered: .above)
        window?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        if let parent = window?.parent, let window {
            parent.removeChildWindow(window)
        }
        close()
        onDismiss?()
    }
}
```

Give the preview a real close button and handle `cancelOperation(_:)` so `Esc` dismisses it. Keep the image aspect ratio and cap the preview at 90% of the screen’s visible frame.

- [ ] **Step 5: Implement `HelpWindowController`**

Use `NSSplitView` with a 190-point sidebar and the content view:

```swift
@MainActor
final class HelpWindowController: NSWindowController {
    private let settingsStore: any AppSettingsStoring
    private let contentLoader: any HelpContentLoading
    private var document: HelpDocument?
    private var selectedChapterID: String?
    private var scrollOffsets: [String: CGFloat] = [:]
    private var imagePreviewController: HelpImagePreviewController?

    init(
        settingsStore: any AppSettingsStoring,
        contentLoader: any HelpContentLoading = HelpContentLoader()
    ) {
        self.settingsStore = settingsStore
        self.contentLoader = contentLoader
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        reloadContent()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
```

Window rules:

- Default content size: `980 × 700`.
- Minimum content size: `760 × 540`.
- Style masks: titled, closable, miniaturizable, resizable.
- Window release on close: false, allowing reuse.
- Default chapter after a fresh controller is `capture`.
- Store outgoing scroll position before changing chapters.
- Reuse one content view, rebuilding its arranged subviews for the selected chapter.
- On loader failure, replace the split content with an error page containing `帮助内容暂时无法打开`.
- Expose narrow `test_` accessors under the same pattern used elsewhere in the project.

- [ ] **Step 6: Run the focused tests**

Run the command from Step 2.

Expected: all HelpManual tests pass.

- [ ] **Step 7: Commit Task 2**

```bash
git add \
  platforms/mac/Sources/App/HelpContentView.swift \
  platforms/mac/Sources/App/HelpImagePreviewController.swift \
  platforms/mac/Sources/App/HelpWindowController.swift \
  platforms/mac/Tests/HelpManualTests.swift \
  platforms/mac/xxsnap.xcodeproj/project.pbxproj
git commit -m "feat(mac): add native help window"
```

### Task 3: Status Menu Integration and Window Lifecycle

**Files:**
- Modify: `platforms/mac/Sources/App/PreferencesSettings.swift`
- Modify: `platforms/mac/Sources/App/StatusItemController.swift`
- Modify: `platforms/mac/Sources/App/AppDelegate.swift`
- Modify: `platforms/mac/Tests/AppSettingsTests.swift`
- Modify: `platforms/mac/Tests/HelpManualTests.swift`

- [ ] **Step 1: Write failing localization and menu tests**

Update the string test:

```swift
func testPreferencesMenuUsesRequestedLowerSectionTitles() {
    let chinese = PreferencesStrings(language: .zhHans)
    XCTAssertEqual(chinese.help, "帮助…")
    XCTAssertEqual(chinese.helpWindowTitle, "XxSnap 帮助")
    XCTAssertEqual(chinese.helpLoadFailed, "帮助内容暂时无法打开")
    XCTAssertEqual(chinese.helpImageUnavailable, "图片暂时无法显示")

    let english = PreferencesStrings(language: .english)
    XCTAssertEqual(english.help, "Help...")
    XCTAssertEqual(english.helpWindowTitle, "XxSnap Help")
}
```

Update the lower menu test to expect six items:

```swift
let lowerItems = Array(controller.test_menuItems.suffix(6))
XCTAssertEqual(
    lowerItems.map(\.title),
    ["偏好设置…", "检查更新…", "支持开发者 ☕️", "帮助…", "关于…", "退出"]
)
```

Inject a counter:

```swift
var helpOpenCount = 0
let controller = StatusItemController(
    captureCoordinator: captureCoordinator,
    settingsStore: store,
    hotKeyController: hotKeyController,
    updateChecker: FakeUpdateChecker(),
    showPreferences: { shownSections.append($0) },
    showHelp: { helpOpenCount += 1 },
    terminationHandler: { quitCount += 1 }
)

let helpItem = try XCTUnwrap(lowerItems.first { $0.title == "帮助…" })
XCTAssertEqual(helpItem.action, #selector(StatusItemController.openHelp))
controller.openHelp()
XCTAssertEqual(helpOpenCount, 1)
```

- [ ] **Step 2: Run the focused tests and confirm failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/AppSettingsTests/testPreferencesMenuUsesRequestedLowerSectionTitles \
  -only-testing:xxsnapTests/AppSettingsTests/testStatusMenuLowerSectionOpensDonationAndQuits
```

Expected: compilation fails because the new strings, callback, and selector do not exist.

- [ ] **Step 3: Add localized strings**

Add to `PreferencesStrings`:

```swift
var help: String { isEnglish ? "Help..." : "帮助…" }
var helpWindowTitle: String { isEnglish ? "XxSnap Help" : "XxSnap 帮助" }
var helpLoadFailed: String {
    isEnglish ? "Help content is temporarily unavailable." : "帮助内容暂时无法打开"
}
var helpImageUnavailable: String {
    isEnglish ? "The image is temporarily unavailable." : "图片暂时无法显示"
}
```

- [ ] **Step 4: Wire the menu callback**

Add a required `showHelp: @escaping @MainActor () -> Void` dependency to `StatusItemController`, store it, and implement:

```swift
@objc func openHelp() {
    showHelp()
}
```

Insert the Help menu item immediately before About:

```swift
menu.addItem(NSMenuItem(
    title: strings.help,
    action: #selector(openHelp),
    keyEquivalent: ""
))
menu.addItem(NSMenuItem(
    title: strings.aboutXxSnap,
    action: #selector(openAbout),
    keyEquivalent: ""
))
```

Update every test construction site to provide `showHelp: {}`.

- [ ] **Step 5: Retain one help controller in `AppDelegate`**

Add:

```swift
private var helpWindowController: HelpWindowController?
```

Create it after stores are initialized:

```swift
let helpWindowController = HelpWindowController(settingsStore: settingsStore)
self.helpWindowController = helpWindowController
```

Pass:

```swift
showHelp: { [weak helpWindowController] in
    helpWindowController?.show()
}
```

Do not add Help to `PreferencesSection` or `PreferencesWindowController`.

- [ ] **Step 6: Run focused tests**

Run the command from Step 2 and all Help tests:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/AppSettingsTests/testPreferencesMenuUsesRequestedLowerSectionTitles \
  -only-testing:xxsnapTests/AppSettingsTests/testStatusMenuLowerSectionOpensDonationAndQuits \
  -only-testing:xxsnapTests/HelpManualTests
```

Expected: all selected tests pass.

- [ ] **Step 7: Commit Task 3**

```bash
git add \
  platforms/mac/Sources/App/AppDelegate.swift \
  platforms/mac/Sources/App/PreferencesSettings.swift \
  platforms/mac/Sources/App/StatusItemController.swift \
  platforms/mac/Tests/AppSettingsTests.swift \
  platforms/mac/Tests/HelpManualTests.swift
git commit -m "feat(mac): open help manual from status menu"
```

### Task 4: Complete Chinese Manual and Bundle Resources

**Files:**
- Create: `platforms/mac/Resources/Help/zh-Hans.json`
- Modify: `platforms/mac/Tests/HelpManualTests.swift`
- Modify: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`
- Reference: `docs/annotation-tools-user-guide.md`
- Reference: `docs/superpowers/specs/2026-07-25-help-manual-design.md`

- [ ] **Step 1: Add failing bundled-content coverage tests**

Add the `Help` folder reference to both app and test resource phases, then write:

```swift
func testBundledChineseHelpContainsCompleteManual() throws {
    let document = try HelpContentLoader(bundle: Bundle(for: Self.self))
        .load(language: .zhHans)

    XCTAssertEqual(document.chapters.map(\.id), [
        "capture", "pin", "ocr", "teaching-pen",
    ])

    let capture = try XCTUnwrap(document.chapters.first { $0.id == "capture" })
    let pin = try XCTUnwrap(document.chapters.first { $0.id == "pin" })
    let ocr = try XCTUnwrap(document.chapters.first { $0.id == "ocr" })
    let pen = try XCTUnwrap(document.chapters.first { $0.id == "teaching-pen" })

    XCTAssertGreaterThanOrEqual(capture.blocks.count, 35)
    XCTAssertGreaterThanOrEqual(pin.blocks.count, 16)
    XCTAssertGreaterThanOrEqual(ocr.blocks.count, 18)
    XCTAssertGreaterThanOrEqual(pen.blocks.count, 20)

    XCTAssertTrue(capture.flattenedText.contains("滚动截图"))
    XCTAssertTrue(capture.flattenedText.contains("取色"))
    XCTAssertTrue(capture.flattenedText.contains("橡皮擦"))
    XCTAssertTrue(pin.flattenedText.contains("恢复最近隐藏的贴图"))
    XCTAssertTrue(ocr.flattenedText.contains("在本机完成"))
    XCTAssertTrue(ocr.flattenedText.contains("竖排文字"))
    XCTAssertTrue(pen.flattenedText.contains("右键"))
    XCTAssertTrue(pen.flattenedText.contains("文字识别"))
}

func testEveryChineseHelpChapterHasShortcutsOverviewImageAndFAQ() throws {
    let document = try bundledChineseDocument()

    for chapter in document.chapters {
        XCTAssertFalse(chapter.shortcuts.isEmpty, chapter.id)
        XCTAssertTrue(chapter.blocks.contains(where: \.isImage), chapter.id)
        XCTAssertTrue(chapter.blocks.contains(where: \.isFAQ), chapter.id)
    }
}

func testEnglishLanguageFallsBackToChineseUntilTranslationShips() throws {
    let document = try HelpContentLoader(bundle: Bundle(for: Self.self))
        .load(language: .english)

    XCTAssertEqual(document.language, "zh-Hans")
    XCTAssertEqual(document.windowTitle, "XxSnap 帮助")
}
```

Add test-only computed helpers `flattenedText`, `isImage`, and `isFAQ` without changing production behavior.

- [ ] **Step 2: Run tests and confirm missing-resource failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test -only-testing:xxsnapTests/HelpManualTests
```

Expected: bundled content tests fail because `Help/zh-Hans.json` is absent.

- [ ] **Step 3: Write the full Chinese JSON**

Use the approved schema and write natural, direct Chinese. Content requirements:

Capture:

- Minimum 35 content blocks and 8 image references.
- Explain region capture, full-screen capture, scroll capture, copy, save, pin, undo, redo, and cancel.
- Give each annotation tool its own heading and plain-language explanation: eyedropper/ranging, shape, arrow, brush, highlighter, mosaic, text, sequence marks, magnifier, and eraser.
- Include default shortcuts for region capture, full-screen capture, copy, save, pin, undo, redo, and cancel.
- Include at least six FAQs.

Pin:

- Minimum 16 blocks and 4 image references.
- Explain creation from each capture/editor path, movement, scrolling/pinch scaling, context menu, toolbar editing, opacity, always-on-top, hiding, restoring, close, and close all.
- Include `Command + 1` creation and restore shortcuts with a note that actual configured shortcuts appear in Settings.
- Include at least four FAQs.

OCR:

- Minimum 18 blocks and 4 image references.
- Explain automatic recognition/copy, success/failure notifications, sound settings, horizontal/vertical/mixed Chinese-English-Korean text, offline privacy, quality tips, and independent use over capture editors and teaching pen.
- State clearly that disabling success notifications never disables failure notifications.
- Include at least five FAQs.

Teaching pen:

- Minimum 20 blocks and 4 image references.
- Explain toggle entry, default brush, right-click toolbar, toolbar dismissal, every available tool, style controls, moving/deleting annotations, copy/save, multi-display considerations, and independent OCR/capture use.
- Explain that OCR temporarily lets pointer events pass through while keeping pen marks visible, then restores the same annotations.
- Include at least five FAQs.

Use the approved image names:

```text
capture-region-overview
capture-selection-adjust
capture-toolbar-overview
capture-annotation-tools
capture-fullscreen-preview
capture-fullscreen-editor
capture-scroll-session
capture-long-editor
pin-overview
pin-context-menu
pin-toolbar
pin-scale-opacity
ocr-selection
ocr-success
ocr-failure
ocr-settings
teaching-pen-overview
teaching-pen-toolbar
teaching-pen-options
teaching-pen-ocr
```

Do not mention unfinished or unavailable features. Do not use phrases such as “轻松实现”“一站式”“提升效率”“赋能” or repetitive conclusion paragraphs.

- [ ] **Step 4: Run a Chinese prose cleanup pass**

Invoke the `humanizer-zh` skill over `zh-Hans.json`. Preserve exact menu labels, shortcut names, file names, and behavioral facts. Specifically remove:

- canned openings;
- repeated “通过……可以……” sentence structures;
- needless summaries after short sections;
- exaggerated benefits;
- second-person lecturing;
- terms that do not appear in the app.

Then validate JSON syntax:

```bash
plutil -lint platforms/mac/Resources/Help/zh-Hans.json
```

Expected: `OK`.

- [ ] **Step 5: Add the Help folder to both resource phases**

In `project.pbxproj`:

- Add one folder `PBXFileReference` for `Help`, with `lastKnownFileType = folder`.
- Add one app `PBXBuildFile` and one test `PBXBuildFile` pointing to the same folder reference.
- Add the folder reference under the Resources group.
- Add the app build file to the app Resources phase.
- Add the test build file to the test Resources phase.

This must copy the directory as `Help/`, preserving `Images/zh-Hans/`.

- [ ] **Step 6: Run bundled-content tests**

Run the command from Step 2.

Expected: model, renderer, window, and content coverage tests pass. Image fallback is allowed until Task 5.

- [ ] **Step 7: Commit Task 4**

```bash
git add \
  platforms/mac/Resources/Help/zh-Hans.json \
  platforms/mac/Tests/HelpManualTests.swift \
  platforms/mac/xxsnap.xcodeproj/project.pbxproj
git commit -m "docs(mac): add Chinese help manual"
```

### Task 5: Capture and Bundle Real Help Images

**Files:**
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/capture-region-overview.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/capture-selection-adjust.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/capture-toolbar-overview.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/capture-annotation-tools.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/capture-fullscreen-preview.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/capture-fullscreen-editor.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/capture-scroll-session.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/capture-long-editor.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/pin-overview.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/pin-context-menu.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/pin-toolbar.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/pin-scale-opacity.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/ocr-selection.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/ocr-success.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/ocr-failure.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/ocr-settings.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/teaching-pen-overview.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/teaching-pen-toolbar.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/teaching-pen-options.png`
- Create: `platforms/mac/Resources/Help/Images/zh-Hans/teaching-pen-ocr.png`
- Modify: `platforms/mac/Tests/HelpManualTests.swift`

- [ ] **Step 1: Add a failing image completeness test**

```swift
func testEveryBundledHelpImageReferenceResolves() throws {
    let loader = HelpContentLoader(bundle: Bundle(for: Self.self))
    let document = try loader.load(language: .zhHans)

    let imageNames = document.chapters.flatMap(\.blocks).compactMap(\.imageName)
    XCTAssertEqual(Set(imageNames).count, 20)
    for name in imageNames {
        XCTAssertNotNil(loader.image(named: name, language: .zhHans), name)
    }
}
```

Expected: failure listing all missing PNG files.

- [ ] **Step 2: Build and restart the current app**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  build

pkill -f "/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/MacOS/XxSnap" || true
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app
```

Confirm the launched process uses this exact build path.

- [ ] **Step 3: Prepare a solid-color capture background**

Create a large plain PNG using the existing macOS graphics stack or a tiny temporary AppKit program. Use one of:

- light gray `#F2F4F6`;
- light blue `#EAF2F7`;
- light green `#EDF5EF`.

Open it full-screen in Preview behind XxSnap. Hide unrelated applications and ensure no wallpaper, personal data, browser content, or other image is visible within any capture.

- [ ] **Step 4: Capture the eight screenshot chapter images**

Use the running XxSnap app and the exact states named by the files:

- region overview: locked region, size label, full main toolbar;
- selection adjust: selected region with square handles and no unrelated window;
- toolbar overview: close crop showing every main-toolbar item;
- annotation tools: representative shape, arrow, brush, marker, mosaic, text, sequence, magnifier, and eraser result on the solid background;
- full-screen preview: bottom-right preview after capture;
- full-screen editor: editor open at its normal fitted size;
- scroll session: active manual scroll capture with preview and controls;
- long editor: completed long-image editor with its own title and toolbar.

Capture with `screencapture -R<x,y,w,h> <absolute-output-path>` so every file is a cropped PNG without desktop edges.

- [ ] **Step 5: Capture the four pin images**

Use a pin created from the solid background:

- overview: one clean pin with its blue outer shadow;
- context menu: complete right-click menu visible;
- toolbar: pin toolbar visible with a representative annotation;
- scale/opacity: context menu or state clearly showing scale/opacity behavior without another image behind it.

- [ ] **Step 6: Capture the four OCR images**

Use large, plain black Chinese text rendered directly on a white or approved solid background:

- selection: active thin white square-corner selection border;
- success: success panel at the lower-middle position;
- failure: failure panel at the same position;
- settings: General settings with both OCR feedback checkboxes visible.

Do not include the sample Korean test images as a background. OCR help images must remain visually simple.

- [ ] **Step 7: Capture the four teaching-pen images**

Use the approved solid background:

- overview: full-screen pen annotations with no toolbar;
- toolbar: right-click compact toolbar;
- options: one representative options panel beside the compact toolbar;
- OCR: pen marks remain visible while the OCR selection is active.

- [ ] **Step 8: Add restrained callouts where needed**

Only overview images may receive red circular number badges. Add no prose directly over screenshots. Keep badges outside text and controls. If callouts are added, use lossless image editing and inspect the final pixels; do not alter or regenerate XxSnap interface text.

- [ ] **Step 9: Inspect every image**

Run:

```bash
sips -g pixelWidth -g pixelHeight \
  platforms/mac/Resources/Help/Images/zh-Hans/*.png
```

Expected:

- every image is PNG;
- every image is at least 900 pixels wide or an intentionally tight control crop at least 500 pixels wide;
- no image exceeds 3200 pixels on either dimension.

Use `view_image` for each file. Check:

- XxSnap UI is sharp and not stretched;
- background is one solid color;
- no wallpaper, other window, personal data, or unrelated image appears;
- callouts do not cover controls or text;
- no text is clipped;
- filename matches the state shown.

- [ ] **Step 10: Run the image completeness test**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test -only-testing:xxsnapTests/HelpManualTests/testEveryBundledHelpImageReferenceResolves
```

Expected: pass with all 20 images resolved.

- [ ] **Step 11: Commit Task 5**

```bash
git add \
  platforms/mac/Resources/Help/Images/zh-Hans \
  platforms/mac/Tests/HelpManualTests.swift
git commit -m "docs(mac): add help manual screenshots"
```

### Task 6: Integration Verification and Visual Polish

**Files:**
- Modify only files already introduced by Tasks 1–5 when verification finds a help-specific defect.

- [ ] **Step 1: Run all help and menu tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test \
  -only-testing:xxsnapTests/HelpManualTests \
  -only-testing:xxsnapTests/AppSettingsTests
```

Expected: all selected tests pass. If an unrelated pre-existing test fails, rerun the failing test alone and record the exact result before deciding whether it is related.

- [ ] **Step 2: Build the app**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Restart the built app**

```bash
pkill -f "/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/MacOS/XxSnap" || true
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app
pgrep -af "XxSnap.app/Contents/MacOS/XxSnap"
```

Expected: one process running from `build/xcode-derived`.

- [ ] **Step 4: Perform the Chinese manual smoke test**

Check in the running app:

1. Status menu order is Settings, Check for Updates, Support the Developer, Help, About, Quit.
2. Help opens one `XxSnap 帮助` window and repeated menu clicks reuse it.
3. Window defaults to Screenshot and remains usable at `760 × 540`.
4. Each sidebar chapter switches immediately.
5. Scroll positions restore when switching away and back.
6. All shortcut keycaps render without clipping.
7. All 20 images are crisp, keep aspect ratio, and use only a solid background.
8. Clicking each image opens a bounded preview; `Esc` closes it.
9. Opening Help while pin, long editor, full-screen editor, OCR, or teaching pen is active does not close or mutate those features.
10. Closing Help and reopening starts at Screenshot.

- [ ] **Step 5: Check English-language fallback**

Switch the app interface to English and open Help:

- status item title is `Help...`;
- window chrome can use English strings;
- first-stage body falls back to the complete Chinese manual;
- no blank chapter or load error appears.

Return the app to the user’s previous language after verification.

- [ ] **Step 6: Run formatting and repository checks**

```bash
git diff --check
git status --short
```

Expected: no whitespace errors and only intentional help-manual changes.

- [ ] **Step 7: Commit help-specific polish if needed**

If Steps 1–6 required fixes:

```bash
git add \
  platforms/mac/Sources/App/HelpContent.swift \
  platforms/mac/Sources/App/HelpContentView.swift \
  platforms/mac/Sources/App/HelpImagePreviewController.swift \
  platforms/mac/Sources/App/HelpWindowController.swift \
  platforms/mac/Sources/App/AppDelegate.swift \
  platforms/mac/Sources/App/PreferencesSettings.swift \
  platforms/mac/Sources/App/StatusItemController.swift \
  platforms/mac/Resources/Help \
  platforms/mac/Tests/HelpManualTests.swift \
  platforms/mac/Tests/AppSettingsTests.swift \
  platforms/mac/xxsnap.xcodeproj/project.pbxproj
git commit -m "fix(mac): polish help manual experience"
```

If no fixes were needed, do not create an empty commit.

## Completion Criteria

- The status menu contains “帮助…” directly above “关于…”.
- The native help window follows the approved left-sidebar layout.
- The complete Chinese manual covers all four requested areas and all annotation tools.
- Shortcuts appear in chapter tables and relevant steps.
- All 20 bundled images show actual XxSnap UI on a clean solid-color background.
- Help remains independent from capture, pin, OCR, teaching pen, and editor windows.
- Missing content and missing-image fallbacks behave as designed.
- Focused XCTest suites and the Debug build pass.
- The current Debug app is restarted from `build/xcode-derived` for user review.
