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
        let controller = makeController()
        defer { controller.close() }
        controller.show()

        controller.test_setScrollOffset(240)
        controller.test_selectChapter("pin")
        controller.test_setScrollOffset(90)
        controller.test_selectChapter("capture")
        XCTAssertEqual(controller.test_scrollOffset, 240, accuracy: 1)

        controller.test_selectChapter("pin")
        XCTAssertEqual(controller.test_scrollOffset, 90, accuracy: 1)
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
    private let document: HelpDocument?
    private let images: [String: NSImage]
    private let error: Error?

    init(
        document: HelpDocument? = nil,
        images: [String: NSImage] = [:],
        error: Error? = nil
    ) {
        self.document = document
        self.images = images
        self.error = error
    }

    func load(language: AppLanguage) throws -> HelpDocument {
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
