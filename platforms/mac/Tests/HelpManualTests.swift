import AppKit
import XCTest
@testable import xxsnap

final class HelpManualTests: XCTestCase {
    func testDecodeLoadsAllChaptersAndSupportedBlockTypes() throws {
        let document = try HelpContentLoader().decode(validDocumentData)

        XCTAssertEqual(
            document.chapters.map(\.id),
            ["capture", "pin", "ocr", "teaching-pen"]
        )

        let capture = try XCTUnwrap(document.chapters.first)
        XCTAssertEqual(capture.shortcuts.first?.keys, ["⌘", "`"])
        XCTAssertEqual(
            capture.blocks,
            [
                .heading(level: 2, text: "开始区域截图"),
                .paragraph("选择一种截图方式。"),
                .steps([
                    HelpStep(text: "按下截图快捷键。", keys: ["⌘", "`"]),
                    HelpStep(text: "按住鼠标并拖动，松开后锁定选区。", keys: nil)
                ]),
                .bullets(["窗口截图", "区域截图"]),
                .shortcuts([
                    HelpShortcut(action: "截图", keys: ["⌘", "`"])
                ]),
                .image(
                    name: "capture-overview",
                    caption: "截图选区示例",
                    accessibilityLabel: "已锁定区域的截图选区"
                ),
                .note(title: "提示", text: "按 Esc 可以取消截图。"),
                .warning(title: "注意", text: "截图前请确认没有敏感信息。"),
                .faq([
                    HelpFAQItem(
                        question: "怎么取消？",
                        answer: "按 Esc 即可取消。"
                    )
                ])
            ]
        )

        let teachingPen = try XCTUnwrap(
            document.chapters.first { $0.id == "teaching-pen" }
        )
        XCTAssertEqual(
            teachingPen.blocks,
            [.warning(title: "隐私", text: "演示时请避免展示敏感信息。")]
        )
    }

    @MainActor
    func testShowBuildsHelpWindowWithDefaultCaptureChapter() throws {
        let controller = makeController()
        defer { controller.close() }

        controller.show()

        XCTAssertEqual(controller.window?.title, "XxSnap 帮助")
        XCTAssertEqual(
            controller.test_navigationTitles,
            ["截图", "贴图", "文字识别", "教笔"]
        )
        XCTAssertEqual(controller.test_selectedChapterID, "capture")
    }

    @MainActor
    func testShowReloadsCurrentLanguageWhileReusingWindow() throws {
        let chineseDocument = try sampleDocument()
        let englishDocument = document(
            basedOn: chineseDocument,
            language: "en",
            windowTitle: "XxSnap Help",
            captureTitle: "Capture screenshots"
        )
        let loader = FakeHelpContentLoader(
            loadHandler: { language, _ in
                language == .english ? englishDocument : chineseDocument
            }
        )
        let settingsStore = FakeHelpAppSettingsStore()
        let controller = HelpWindowController(
            settingsStore: settingsStore,
            contentLoader: loader
        )
        defer { controller.close() }

        controller.show()
        let firstWindow = try XCTUnwrap(controller.window)
        XCTAssertEqual(firstWindow.title, "XxSnap 帮助")
        XCTAssertTrue(controller.test_visibleTexts.contains("区域截图"))

        var settings = settingsStore.load()
        settings.language = .english
        try settingsStore.save(settings)
        controller.show()

        XCTAssertTrue(controller.window === firstWindow)
        XCTAssertEqual(controller.window?.title, "XxSnap Help")
        XCTAssertTrue(
            controller.test_visibleTexts.contains("Capture screenshots")
        )
        XCTAssertEqual(loader.loadedLanguages, [.zhHans, .english])
    }

    @MainActor
    func testShowRetriesAfterLoaderFailureAndRecoversInSameWindow() throws {
        let expectedDocument = try sampleDocument()
        let loader = FakeHelpContentLoader(
            loadHandler: { _, callCount in
                if callCount == 1 {
                    throw FakeHelpContentError.failed
                }
                return expectedDocument
            }
        )
        let controller = makeController(loader: loader)
        defer { controller.close() }

        controller.show()
        let firstWindow = try XCTUnwrap(controller.window)
        XCTAssertTrue(
            controller.test_visibleTexts.contains("帮助内容暂时无法打开")
        )

        controller.show()

        XCTAssertTrue(controller.window === firstWindow)
        XCTAssertEqual(controller.window?.title, "XxSnap 帮助")
        XCTAssertTrue(controller.test_visibleTexts.contains("区域截图"))
        XCTAssertEqual(loader.loadCallCount, 2)
    }

    @MainActor
    func testCaptureChapterRendersAllSupportedBlocksAndLoadedImage() throws {
        let loader = FakeHelpContentLoader(
            document: try sampleDocument(),
            images: ["capture-overview": solidImage()]
        )
        let controller = makeController(loader: loader)
        defer { controller.close() }

        controller.show()

        XCTAssertEqual(controller.test_visibleImageCount, 1)
        XCTAssertTrue(controller.test_visibleTexts.contains("区域截图"))
        XCTAssertTrue(
            controller.test_visibleTexts.contains(
                "按住鼠标并拖动，松开后锁定选区。"
            )
        )
        XCTAssertTrue(controller.test_visibleTexts.contains("怎么取消？"))
    }

    @MainActor
    func testMissingImageShowsFallbackAndCaptionWithoutDroppingBody() throws {
        let controller = makeController(
            loader: FakeHelpContentLoader(document: try sampleDocument())
        )
        defer { controller.close() }

        controller.show()

        XCTAssertEqual(controller.test_visibleImageCount, 0)
        XCTAssertTrue(controller.test_visibleTexts.contains("图片暂时无法显示"))
        XCTAssertTrue(controller.test_visibleTexts.contains("截图选区示例"))
        XCTAssertTrue(controller.test_visibleTexts.contains("选择一种截图方式。"))
        XCTAssertTrue(controller.test_visibleTexts.contains("怎么取消？"))
    }

    @MainActor
    func testChapterSwitchRestoresSessionScrollOffsets() throws {
        let controller = makeController(
            loader: FakeHelpContentLoader(document: try tallDocument())
        )
        defer { controller.close() }
        controller.show()

        controller.test_setScrollOffset(240)
        let captureOffset = controller.test_scrollOffset
        XCTAssertEqual(captureOffset, 240, accuracy: 1)
        controller.test_selectChapter("pin")
        controller.test_setScrollOffset(90)
        let pinOffset = controller.test_scrollOffset
        XCTAssertEqual(pinOffset, 90, accuracy: 1)
        controller.test_selectChapter("capture")
        XCTAssertEqual(controller.test_scrollOffset, captureOffset, accuracy: 1)

        controller.test_selectChapter("pin")
        XCTAssertEqual(controller.test_scrollOffset, pinOffset, accuracy: 1)
    }

    @MainActor
    func testScrollOffsetReportsClipViewClampedPosition() throws {
        let controller = makeController(
            loader: FakeHelpContentLoader(document: try tallDocument())
        )
        defer { controller.close() }
        controller.show()

        controller.test_setScrollOffset(10_000)

        XCTAssertGreaterThan(controller.test_scrollOffset, 0)
        XCTAssertLessThan(controller.test_scrollOffset, 10_000)
    }

    @MainActor
    func testClickingImageOpensAndDismissesPreview() throws {
        let loader = FakeHelpContentLoader(
            document: try sampleDocument(),
            images: ["capture-overview": solidImage()]
        )
        let controller = makeController(loader: loader)
        defer { controller.close() }
        controller.show()

        controller.test_clickFirstImage()
        XCTAssertTrue(controller.test_isImagePreviewVisible)

        controller.test_dismissImagePreview()
        XCTAssertFalse(controller.test_isImagePreviewVisible)
    }

    @MainActor
    func testLoaderFailureShowsErrorPage() {
        let controller = makeController(
            loader: FakeHelpContentLoader(error: FakeHelpContentError.failed)
        )
        defer { controller.close() }

        controller.show()

        XCTAssertTrue(
            controller.test_visibleTexts.contains("帮助内容暂时无法打开")
        )
        XCTAssertNotNil(controller.window)
    }

    func testDecodeRejectsDuplicateChapterID() {
        let json = validDocumentJSON.replacingOccurrences(
            of: #""id": "pin""#,
            with: #""id": "capture""#
        )

        XCTAssertThrowsError(try HelpContentLoader().decode(Data(json.utf8))) {
            XCTAssertEqual(
                $0 as? HelpContentError,
                .duplicateChapterID("capture")
            )
        }
    }

    func testDecodeRejectsEmptyChapters() {
        let data = Data(
            """
            {
              "version": 1,
              "language": "en",
              "windowTitle": "XxSnap Help",
              "chapters": []
            }
            """.utf8
        )

        XCTAssertThrowsError(try HelpContentLoader().decode(data)) {
            XCTAssertEqual($0 as? HelpContentError, .emptyChapters)
        }
    }

    func testDecodeRejectsEmptyChapterID() {
        let json = validDocumentJSON.replacingOccurrences(
            of: #""id": "capture""#,
            with: #""id": """#
        )

        XCTAssertThrowsError(try HelpContentLoader().decode(Data(json.utf8))) {
            XCTAssertEqual($0 as? HelpContentError, .emptyChapterID)
        }
    }

    func testDecodeRejectsWhitespaceOnlyChapterID() {
        let json = validDocumentJSON.replacingOccurrences(
            of: #""id": "capture""#,
            with: #""id": " \n\t""#
        )

        XCTAssertThrowsError(try HelpContentLoader().decode(Data(json.utf8))) {
            XCTAssertEqual($0 as? HelpContentError, .emptyChapterID)
        }
    }

    func testDecodeRejectsUnknownBlockType() {
        let json = validDocumentJSON.replacingOccurrences(
            of: #""type": "paragraph""#,
            with: #""type": "video""#
        )

        XCTAssertThrowsError(try HelpContentLoader().decode(Data(json.utf8))) {
            guard case DecodingError.dataCorrupted = $0 else {
                return XCTFail("Expected dataCorrupted, got \($0)")
            }
        }
    }

    private var validDocumentData: Data {
        Data(Self.validDocumentJSON.utf8)
    }

    private var validDocumentJSON: String {
        Self.validDocumentJSON
    }

    @MainActor
    private func makeController(
        loader: FakeHelpContentLoader? = nil
    ) -> HelpWindowController {
        HelpWindowController(
            settingsStore: FakeHelpAppSettingsStore(),
            contentLoader: loader ?? FakeHelpContentLoader(
                document: try! sampleDocument()
            )
        )
    }

    private func sampleDocument() throws -> HelpDocument {
        try HelpContentLoader().decode(validDocumentData)
    }

    private func tallDocument() throws -> HelpDocument {
        let source = try sampleDocument()
        let filler = (1...80).map {
            HelpContentBlock.paragraph("用于滚动位置测试的正文段落 \($0)。")
        }
        let chapters = source.chapters.map { chapter in
            guard chapter.id == "capture" || chapter.id == "pin" else {
                return chapter
            }
            return HelpChapter(
                id: chapter.id,
                navigationTitle: chapter.navigationTitle,
                title: chapter.title,
                introduction: chapter.introduction,
                tableOfContents: chapter.tableOfContents,
                shortcuts: chapter.shortcuts,
                blocks: chapter.blocks + filler
            )
        }
        return HelpDocument(
            version: source.version,
            language: source.language,
            windowTitle: source.windowTitle,
            chapters: chapters
        )
    }

    private func document(
        basedOn source: HelpDocument,
        language: String,
        windowTitle: String,
        captureTitle: String
    ) -> HelpDocument {
        let chapters = source.chapters.map { chapter in
            guard chapter.id == "capture" else { return chapter }
            return HelpChapter(
                id: chapter.id,
                navigationTitle: chapter.navigationTitle,
                title: captureTitle,
                introduction: chapter.introduction,
                tableOfContents: chapter.tableOfContents,
                shortcuts: chapter.shortcuts,
                blocks: chapter.blocks
            )
        }
        return HelpDocument(
            version: source.version,
            language: language,
            windowTitle: windowTitle,
            chapters: chapters
        )
    }

    @MainActor
    private func solidImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 640, height: 360))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 640, height: 360).fill()
        image.unlockFocus()
        return image
    }

    private static let validDocumentJSON = """
        {
          "version": 1,
          "language": "zh-Hans",
          "windowTitle": "XxSnap 帮助",
          "chapters": [
            {
              "id": "capture",
              "navigationTitle": "截图",
              "title": "区域截图",
              "introduction": "截取屏幕任意区域。",
              "tableOfContents": ["开始截图"],
              "shortcuts": [
                { "action": "截图", "keys": ["⌘", "`"] }
              ],
              "blocks": [
                { "type": "heading", "level": 2, "text": "开始区域截图" },
                { "type": "paragraph", "text": "选择一种截图方式。" },
                {
                  "type": "steps",
                  "items": [
                    { "text": "按下截图快捷键。", "keys": ["⌘", "`"] },
                    { "text": "按住鼠标并拖动，松开后锁定选区。" }
                  ]
                },
                {
                  "type": "bullets",
                  "items": ["窗口截图", "区域截图"]
                },
                {
                  "type": "shortcuts",
                  "items": [
                    { "action": "截图", "keys": ["⌘", "`"] }
                  ]
                },
                {
                  "type": "image",
                  "name": "capture-overview",
                  "caption": "截图选区示例",
                  "accessibilityLabel": "已锁定区域的截图选区"
                },
                {
                  "type": "note",
                  "title": "提示",
                  "text": "按 Esc 可以取消截图。"
                },
                {
                  "type": "warning",
                  "title": "注意",
                  "text": "截图前请确认没有敏感信息。"
                },
                {
                  "type": "faq",
                  "items": [
                    {
                      "question": "怎么取消？",
                      "answer": "按 Esc 即可取消。"
                    }
                  ]
                }
              ]
            },
            {
              "id": "pin",
              "navigationTitle": "贴图",
              "title": "贴图",
              "introduction": "让参考内容保持可见。",
              "tableOfContents": [],
              "shortcuts": [],
              "blocks": []
            },
            {
              "id": "ocr",
              "navigationTitle": "文字识别",
              "title": "文字识别",
              "introduction": "提取截图中的文字。",
              "tableOfContents": [],
              "shortcuts": [],
              "blocks": []
            },
            {
              "id": "teaching-pen",
              "navigationTitle": "教笔",
              "title": "教笔",
              "introduction": "演示时直接在屏幕上绘制。",
              "tableOfContents": [],
              "shortcuts": [],
              "blocks": [
                {
                  "type": "warning",
                  "title": "隐私",
                  "text": "演示时请避免展示敏感信息。"
                }
              ]
            }
          ]
        }
        """
}

private enum FakeHelpContentError: Error {
    case failed
}

private final class FakeHelpContentLoader: HelpContentLoading {
    typealias LoadHandler = (AppLanguage, Int) throws -> HelpDocument

    private let document: HelpDocument?
    private let images: [String: NSImage]
    private let error: Error?
    private let loadHandler: LoadHandler?

    private(set) var loadedLanguages: [AppLanguage] = []
    var loadCallCount: Int {
        loadedLanguages.count
    }

    init(
        document: HelpDocument? = nil,
        images: [String: NSImage] = [:],
        error: Error? = nil,
        loadHandler: LoadHandler? = nil
    ) {
        self.document = document
        self.images = images
        self.error = error
        self.loadHandler = loadHandler
    }

    func load(language: AppLanguage) throws -> HelpDocument {
        loadedLanguages.append(language)
        if let loadHandler {
            return try loadHandler(language, loadCallCount)
        }
        if let error {
            throw error
        }
        return try XCTUnwrap(document)
    }

    func image(named name: String, language: AppLanguage) -> NSImage? {
        images[name]
    }
}

private final class FakeHelpAppSettingsStore: AppSettingsStoring {
    private var settings: AppSettings

    init(settings: AppSettings = .default) {
        self.settings = settings
    }

    func load() -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) throws {
        self.settings = settings
    }
}
