import AppKit
import XCTest
@testable import xxsnap

final class HelpManualTests: XCTestCase {
    func testBundledChineseManualHasCompleteChapterContent() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))
        let document = try loader.load(language: .zhHans)

        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.language, "zh-Hans")
        XCTAssertEqual(document.windowTitle, "XxSnap 帮助")
        XCTAssertEqual(
            document.chapters.map(\.id),
            ["capture", "pin", "ocr", "teaching-pen"]
        )

        let expectations: [(id: String, blocks: Int, text: [String])] = [
            ("capture", 35, ["滚动截图", "取色", "橡皮擦"]),
            ("pin", 16, ["恢复最近隐藏的贴图"]),
            ("ocr", 18, ["在本机完成", "竖排文字"]),
            ("teaching-pen", 20, ["右键", "文字识别"])
        ]

        for expectation in expectations {
            let chapter = try XCTUnwrap(
                document.chapters.first { $0.id == expectation.id }
            )
            XCTAssertGreaterThanOrEqual(
                chapter.blocks.count,
                expectation.blocks,
                "\(expectation.id) 正文块数量不足"
            )
            for text in expectation.text {
                XCTAssertTrue(
                    chapter.flattenedText.contains(text),
                    "\(expectation.id) 缺少正文：\(text)"
                )
            }
            XCTAssertFalse(
                chapter.shortcuts.isEmpty,
                "\(expectation.id) 缺少章节快捷键"
            )
            XCTAssertTrue(
                chapter.blocks.contains(where: \.isImage),
                "\(expectation.id) 缺少图片块"
            )
            XCTAssertTrue(
                chapter.blocks.contains(where: \.isFAQ),
                "\(expectation.id) 缺少常见问题"
            )
        }
    }

    func testBundledChineseManualUsesRequiredImagesAndChapterDetails() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))
        let document = try loader.load(language: .zhHans)
        let expectedImages: Set<String> = [
            "capture-region-overview",
            "capture-selection-adjust",
            "capture-toolbar-overview",
            "capture-annotation-tools",
            "capture-fullscreen-preview",
            "capture-fullscreen-editor",
            "capture-scroll-session",
            "capture-long-editor",
            "pin-overview",
            "pin-context-menu",
            "pin-toolbar",
            "pin-scale-opacity",
            "ocr-selection",
            "ocr-success",
            "ocr-failure",
            "ocr-settings",
            "teaching-pen-overview",
            "teaching-pen-toolbar",
            "teaching-pen-options",
            "teaching-pen-ocr"
        ]

        XCTAssertEqual(Set(document.chapters.flatMap(\.imageNames)), expectedImages)

        let capture = try XCTUnwrap(
            document.chapters.first { $0.id == "capture" }
        )
        XCTAssertEqual(capture.imageNames.count, 8)
        XCTAssertGreaterThanOrEqual(capture.faqCount, 6)
        XCTAssertTrue(capture.hasShortcut(action: "区域截图", keys: ["⌘", "`"]))
        XCTAssertTrue(capture.hasShortcut(action: "全屏截图", keys: ["⌘", "⇧", "1"]))
        XCTAssertTrue(capture.hasShortcut(action: "复制", keys: ["⌘", "C"]))
        XCTAssertTrue(capture.hasShortcut(action: "保存", keys: ["⌘", "S"]))
        XCTAssertTrue(capture.hasShortcut(action: "贴图", keys: ["⌘", "1"]))
        XCTAssertTrue(capture.hasShortcut(action: "撤销", keys: ["⌘", "Z"]))
        XCTAssertTrue(capture.hasShortcut(action: "重做", keys: ["⌘", "⇧", "Z"]))
        XCTAssertTrue(
            capture.hasShortcut(
                action: "退出当前工具 / 取消截图",
                keys: ["Esc"]
            )
        )

        let pin = try XCTUnwrap(document.chapters.first { $0.id == "pin" })
        XCTAssertEqual(pin.imageNames.count, 4)
        XCTAssertGreaterThanOrEqual(pin.faqCount, 4)

        let ocr = try XCTUnwrap(document.chapters.first { $0.id == "ocr" })
        XCTAssertEqual(ocr.imageNames.count, 4)
        XCTAssertGreaterThanOrEqual(ocr.faqCount, 5)

        let teachingPen = try XCTUnwrap(
            document.chapters.first { $0.id == "teaching-pen" }
        )
        XCTAssertEqual(teachingPen.imageNames.count, 4)
        XCTAssertGreaterThanOrEqual(teachingPen.faqCount, 5)
    }

    func testCaptureManualDocumentsActualEscapeAndAnnotationWorkflows() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))
        let document = try loader.load(language: .zhHans)
        let capture = try XCTUnwrap(
            document.chapters.first { $0.id == "capture" }
        )
        let text = capture.flattenedText

        XCTAssertTrue(text.contains("第一次按 Esc 退出当前工具"))
        XCTAssertTrue(text.contains("再按一次 Esc 取消截图"))
        XCTAssertTrue(text.contains("按 C 复制"))
        XCTAssertTrue(text.contains("第一次点击确定测距起点"))
        XCTAssertTrue(text.contains("第二次点击确定终点"))
        XCTAssertTrue(text.contains("Shift"))
        XCTAssertTrue(text.contains("HEX"))
        XCTAssertTrue(text.contains("RGB"))
        XCTAssertTrue(text.contains("水平、垂直或 45 度"))

        for option in [
            "滑动打码",
            "矩形打码",
            "高斯模糊",
            "像素马赛克",
            "强度",
            "笔刷大小"
        ] {
            XCTAssertTrue(text.contains(option), "马赛克缺少选项：\(option)")
        }
        XCTAssertFalse(text.contains("边缘样式"))

        XCTAssertTrue(text.contains("Return 用来换行"))
        XCTAssertTrue(text.contains("点击文字框外"))
        XCTAssertTrue(text.contains("切换工具"))
        XCTAssertTrue(text.contains("复制、保存或贴图"))

        XCTAssertTrue(text.contains("移动后按新位置重新采样原始截图"))
        XCTAssertTrue(text.contains("不会放大后来添加的标注"))
        XCTAssertFalse(text.contains("仍指向原来的区域"))
    }

    func testCaptureManualDocumentsFullscreenPreviewAndAutomaticScrollWorkflow() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))
        let document = try loader.load(language: .zhHans)
        let capture = try XCTUnwrap(
            document.chapters.first { $0.id == "capture" }
        )
        let text = capture.flattenedText

        XCTAssertTrue(text.contains("右下角缩略图"))
        XCTAssertTrue(text.contains("单击缩略图"))
        XCTAssertTrue(text.contains("预览窗没有底部按钮"))
        XCTAssertTrue(
            text.contains(
                "右键菜单提供显示工具条、贴图、复制图片、保存图片和关闭"
            )
        )

        XCTAssertTrue(text.contains("辅助功能权限"))
        XCTAssertTrue(text.contains("没有权限"))
        XCTAssertTrue(text.contains("退出滚动截图并恢复原选区"))
        XCTAssertTrue(text.contains("方向下拉菜单"))
        XCTAssertTrue(text.contains("向下滚动"))
        XCTAssertTrue(text.contains("向上滚动"))
        XCTAssertTrue(text.contains("开始单步滚动"))
        XCTAssertTrue(text.contains("结束滚动截图"))
        XCTAssertTrue(text.contains("每点一次开始单步滚动"))
        XCTAssertTrue(text.contains("XxSnap 会自动推动目标页面一段并采集"))
        XCTAssertTrue(text.contains("第一次成功采集后，方向会锁定"))
        XCTAssertTrue(text.contains("不能改成反向"))
        XCTAssertTrue(text.contains("物理滚轮会被拦截"))
        XCTAssertTrue(text.contains("预览面板不接收鼠标"))
        XCTAssertTrue(text.contains("不能手动回看"))
        XCTAssertTrue(text.contains("Return 或 Enter 完成，Esc 取消"))
        XCTAssertTrue(text.contains("全局键监听依赖辅助功能权限"))
        XCTAssertTrue(text.contains("结束滚动截图和取消按钮始终是可靠入口"))
        XCTAssertTrue(text.contains("资源上限"))
        XCTAssertTrue(text.contains("阻塞暂停"))
        XCTAssertTrue(text.contains("不再继续接收"))
        XCTAssertTrue(text.contains("已接受的内容"))
        XCTAssertTrue(text.contains("页面动画或重叠不足"))
        XCTAssertTrue(text.contains("等页面稳定后再试一步"))
        XCTAssertTrue(text.contains("达到资源上限后不能继续单步"))
        XCTAssertTrue(text.contains("只能完成已接受的长图或取消"))
        XCTAssertFalse(text.contains("只支持手动纵向滚动"))
        XCTAssertFalse(text.contains("反向滚动只用于回看"))
        XCTAssertFalse(text.contains("回到当前扩展端后恢复跟随"))
    }

    func testPinAndOCRManualBoundariesMatchCurrentProduct() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))
        let document = try loader.load(language: .zhHans)
        let pin = try XCTUnwrap(
            document.chapters.first { $0.id == "pin" }
        )
        let pinText = pin.flattenedText

        XCTAssertTrue(pin.hasShortcut(action: "从当前截图创建贴图", keys: ["⌘", "1"]))
        XCTAssertTrue(pin.hasShortcut(action: "恢复最近隐藏的贴图", keys: ["⌘", "1"]))
        XCTAssertTrue(pinText.contains("默认快捷键是 Command+1"))
        XCTAssertTrue(pinText.contains("设置页"))
        XCTAssertTrue(pinText.contains("截图编辑上下文"))
        XCTAssertTrue(pinText.contains("创建时经过屏幕适配的初始显示尺寸"))
        XCTAssertFalse(pinText.contains("看原尺寸"))
        XCTAssertFalse(pinText.contains("原始像素尺寸"))
        XCTAssertTrue(pinText.contains("工具条隐藏时，按 Esc 直接隐藏贴图"))
        XCTAssertTrue(pinText.contains("工具条显示但没有激活主工具时"))
        XCTAssertTrue(pinText.contains("先结束编辑并隐藏工具条"))
        XCTAssertTrue(pinText.contains("贴图仍显示"))
        XCTAssertTrue(pinText.contains("主工具激活时"))
        XCTAssertTrue(pinText.contains("第一次 Esc 退出当前工具"))
        XCTAssertTrue(pinText.contains("第二次结束编辑并隐藏工具条"))
        XCTAssertTrue(pinText.contains("第三次才隐藏贴图"))
        XCTAssertTrue(
            pinText.contains(
                "工具条隐藏时，Delete 或 Backspace 会关闭当前贴图"
            )
        )
        XCTAssertTrue(pinText.contains("编辑工具条显示时"))
        XCTAssertTrue(pinText.contains("可能删除当前选中的标注"))
        XCTAssertFalse(pinText.contains("按 Delete 或 Backspace 会关闭当前贴图"))

        let ocr = try XCTUnwrap(
            document.chapters.first { $0.id == "ocr" }
        )
        let ocrText = ocr.flattenedText
        XCTAssertTrue(ocrText.contains("长截图编辑器"))
        XCTAssertTrue(ocrText.contains("全屏截图编辑器"))
        XCTAssertTrue(ocrText.contains("教笔"))
        XCTAssertTrue(ocrText.contains("暂时不接收鼠标"))
        XCTAssertTrue(ocrText.contains("完成后恢复"))
        XCTAssertFalse(ocrText.contains("区域截图编辑器"))
    }

    func testTeachingPenManualNamesEveryAvailableTool() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))
        let document = try loader.load(language: .zhHans)
        let teachingPen = try XCTUnwrap(
            document.chapters.first { $0.id == "teaching-pen" }
        )

        for tool in [
            "画笔",
            "形状",
            "箭头",
            "荧光笔",
            "文字",
            "序号",
            "马赛克",
            "取色",
            "橡皮擦",
            "放大镜",
            "复制",
            "保存"
        ] {
            XCTAssertTrue(
                teachingPen.flattenedText.contains(tool),
                "教笔缺少工具说明：\(tool)"
            )
        }
    }

    func testEnglishManualFallsBackToBundledChineseDocument() throws {
        let bundle = Bundle(for: HelpManualTests.self)
        let loader = HelpContentLoader(bundle: bundle)

        XCTAssertNil(
            bundle.url(
                forResource: "en",
                withExtension: "json",
                subdirectory: "Help"
            )
        )
        let document = try loader.load(language: .english)

        XCTAssertEqual(document.language, "zh-Hans")
        XCTAssertEqual(document.windowTitle, "XxSnap 帮助")
    }

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
    func testShowUsesSettingsLanguageForWindowChrome() throws {
        let englishDocument = document(
            basedOn: try sampleDocument(),
            language: "en",
            windowTitle: "Ignored document title",
            captureTitle: "Capture screenshots"
        )
        let controller = makeController(
            language: .english,
            loader: FakeHelpContentLoader(document: englishDocument)
        )
        defer { controller.close() }

        controller.show()

        XCTAssertEqual(controller.window?.title, "XxSnap Help")
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
    func testRepeatedShowPreservesOpenSessionAndCloseStartsFreshSession() throws {
        let controller = makeController(
            loader: FakeHelpContentLoader(document: try tallDocument())
        )
        defer { controller.close() }
        controller.show()
        let firstWindow = try XCTUnwrap(controller.window)

        controller.test_setScrollOffset(240)
        let captureOffset = controller.test_scrollOffset
        XCTAssertEqual(captureOffset, 240, accuracy: 1)
        controller.test_clickNavigationButton("pin")
        controller.test_setScrollOffset(90)
        let pinOffset = controller.test_scrollOffset
        XCTAssertEqual(pinOffset, 90, accuracy: 1)

        controller.show()

        XCTAssertTrue(controller.window === firstWindow)
        XCTAssertEqual(controller.test_selectedChapterID, "pin")
        XCTAssertEqual(controller.test_scrollOffset, pinOffset, accuracy: 1)
        controller.test_clickNavigationButton("capture")
        XCTAssertEqual(controller.test_scrollOffset, captureOffset, accuracy: 1)

        firstWindow.close()
        controller.show()

        XCTAssertTrue(controller.window === firstWindow)
        XCTAssertEqual(controller.test_selectedChapterID, "capture")
        XCTAssertEqual(controller.test_scrollOffset, 0, accuracy: 1)
    }

    @MainActor
    func testFailedReloadKeepsOpenSessionStateForNextRetry() throws {
        let document = try tallDocument()
        let loader = FakeHelpContentLoader(
            loadHandler: { _, callCount in
                if callCount == 2 {
                    throw FakeHelpContentError.failed
                }
                return document
            }
        )
        let controller = makeController(loader: loader)
        defer { controller.close() }
        controller.show()

        controller.test_clickNavigationButton("pin")
        controller.test_setScrollOffset(90)
        let pinOffset = controller.test_scrollOffset

        controller.show()
        XCTAssertTrue(
            controller.test_visibleTexts.contains("帮助内容暂时无法打开")
        )

        controller.show()

        XCTAssertEqual(controller.test_selectedChapterID, "pin")
        XCTAssertEqual(controller.test_scrollOffset, pinOffset, accuracy: 1)
        XCTAssertEqual(loader.loadCallCount, 3)
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
    func testMissingImageUsesSettingsLanguageForFallback() throws {
        let controller = makeController(
            language: .english,
            loader: FakeHelpContentLoader(document: try sampleDocument())
        )
        defer { controller.close() }

        controller.show()

        XCTAssertTrue(
            controller.test_visibleTexts.contains(
                "The image is temporarily unavailable."
            )
        )
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
        controller.test_clickNavigationButton("pin")
        controller.test_setScrollOffset(90)
        let pinOffset = controller.test_scrollOffset
        XCTAssertEqual(pinOffset, 90, accuracy: 1)
        controller.test_clickNavigationButton("capture")
        XCTAssertEqual(controller.test_scrollOffset, captureOffset, accuracy: 1)

        controller.test_clickNavigationButton("pin")
        XCTAssertEqual(controller.test_scrollOffset, pinOffset, accuracy: 1)
    }

    @MainActor
    func testClickingSelectedNavigationButtonKeepsSelectionAndBody() throws {
        let controller = makeController()
        defer { controller.close() }
        controller.show()

        controller.test_clickNavigationButton("pin")
        XCTAssertEqual(controller.test_selectedChapterID, "pin")
        XCTAssertEqual(controller.test_navigationButtonState("pin"), .on)
        XCTAssertTrue(
            controller.test_visibleTexts.contains("让参考内容保持可见。")
        )

        controller.test_clickNavigationButton("pin")

        XCTAssertEqual(controller.test_selectedChapterID, "pin")
        XCTAssertEqual(controller.test_navigationButtonState("pin"), .on)
        XCTAssertTrue(
            controller.test_visibleTexts.contains("让参考内容保持可见。")
        )
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
    func testImagePreviewPropagatesAccessibilityAndDismissesThroughActions() throws {
        let loader = FakeHelpContentLoader(
            document: try sampleDocument(),
            images: ["capture-overview": solidImage()]
        )
        let controller = makeController(loader: loader)
        defer { controller.close() }
        controller.show()

        controller.test_clickFirstImage()
        XCTAssertTrue(controller.test_isImagePreviewVisible)
        XCTAssertEqual(
            controller.test_imagePreviewAccessibilityLabel,
            "已锁定区域的截图选区"
        )
        XCTAssertEqual(controller.window?.childWindows?.count, 1)
        XCTAssertEqual(controller.test_imagePreviewDismissCount, 0)

        controller.test_cancelImagePreview()
        XCTAssertFalse(controller.test_isImagePreviewVisible)
        XCTAssertEqual(controller.window?.childWindows?.count, 0)
        XCTAssertEqual(controller.test_imagePreviewDismissCount, 1)
        controller.test_cancelImagePreview()
        XCTAssertEqual(controller.test_imagePreviewDismissCount, 1)

        controller.test_clickFirstImage()
        XCTAssertTrue(controller.test_isImagePreviewVisible)
        XCTAssertEqual(controller.window?.childWindows?.count, 1)

        controller.test_clickImagePreviewCloseButton()

        XCTAssertFalse(controller.test_isImagePreviewVisible)
        XCTAssertEqual(controller.window?.childWindows?.count, 0)
        XCTAssertEqual(controller.test_imagePreviewDismissCount, 2)
        controller.test_clickImagePreviewCloseButton()
        XCTAssertEqual(controller.test_imagePreviewDismissCount, 2)
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

    @MainActor
    func testLoaderFailureUsesSettingsLanguageForWindowChrome() {
        let controller = makeController(
            language: .english,
            loader: FakeHelpContentLoader(error: FakeHelpContentError.failed)
        )
        defer { controller.close() }

        controller.show()

        XCTAssertEqual(controller.window?.title, "XxSnap Help")
        XCTAssertTrue(
            controller.test_visibleTexts.contains(
                "Help content is temporarily unavailable."
            )
        )
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
        language: AppLanguage = .zhHans,
        loader: FakeHelpContentLoader? = nil
    ) -> HelpWindowController {
        var settings = AppSettings.default
        settings.language = language
        return HelpWindowController(
            settingsStore: FakeHelpAppSettingsStore(settings: settings),
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

private extension HelpChapter {
    var flattenedText: String {
        ([title, introduction] + tableOfContents + blocks.map(\.flattenedText))
            .joined(separator: "\n")
    }

    var imageNames: [String] {
        blocks.compactMap(\.imageName)
    }

    var faqCount: Int {
        blocks.reduce(0) { $0 + $1.faqCount }
    }

    func hasShortcut(action: String, keys: [String]) -> Bool {
        shortcuts.contains(HelpShortcut(action: action, keys: keys))
    }
}

private extension HelpContentBlock {
    var flattenedText: String {
        switch self {
        case let .heading(_, text), let .paragraph(text):
            return text
        case let .steps(items):
            return items.map(\.text).joined(separator: "\n")
        case let .bullets(items):
            return items.joined(separator: "\n")
        case let .shortcuts(items):
            return items.map(\.action).joined(separator: "\n")
        case let .image(_, caption, accessibilityLabel):
            return [caption, accessibilityLabel].joined(separator: "\n")
        case let .note(title, text), let .warning(title, text):
            return [title, text].joined(separator: "\n")
        case let .faq(items):
            return items.flatMap { [$0.question, $0.answer] }.joined(separator: "\n")
        }
    }

    var isImage: Bool {
        if case .image = self {
            return true
        }
        return false
    }

    var isFAQ: Bool {
        if case .faq = self {
            return true
        }
        return false
    }

    var imageName: String? {
        if case let .image(name, _, _) = self {
            return name
        }
        return nil
    }

    var faqCount: Int {
        if case let .faq(items) = self {
            return items.count
        }
        return 0
    }
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
