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
            ["capture", "pin", "ocr", "teaching-pen", "report-issue"]
        )

        let expectations: [(id: String, blocks: Int, text: [String])] = [
            ("capture", 35, ["滚动截图", "取色", "橡皮擦"]),
            ("pin", 16, ["恢复最近隐藏的贴图"]),
            ("ocr", 18, ["在本机完成", "竖排文字"]),
            ("teaching-pen", 20, ["右键", "文字/二维码识别"])
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
        XCTAssertTrue(capture.hasShortcut(action: "区域截图（默认）", keys: ["⌘", "`"]))
        XCTAssertTrue(capture.hasShortcut(action: "全屏截图（默认）", keys: ["⌘", "⇧", "1"]))
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
        let captureText = capture.flattenedText
        XCTAssertTrue(captureText.contains("默认快捷键"))
        XCTAssertTrue(captureText.contains("Command+`"))
        XCTAssertTrue(captureText.contains("Command+Shift+1"))
        XCTAssertTrue(captureText.contains("修改或禁用"))
        XCTAssertTrue(captureText.contains("菜单或设置"))

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

    func testEveryBundledHelpImageReferenceResolves() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))
        let document = try loader.load(language: .zhHans)

        let imageNames = document.chapters.flatMap(\.imageNames)
        XCTAssertEqual(Set(imageNames).count, 20)
        for name in imageNames {
            XCTAssertNotNil(
                loader.image(named: name, language: .zhHans),
                name
            )
        }
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

    func testCaptureManualDocumentsFullscreenPreviewAndContinuousManualScrollWorkflow() throws {
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

        XCTAssertTrue(text.contains("直接用鼠标滚轮或触控板滚动"))
        XCTAssertTrue(text.contains("第一次可靠移动会锁定拼接方向"))
        XCTAssertTrue(text.contains("反向滚动只用于回看，不会拼接"))
        XCTAssertTrue(text.contains("滚动截图右侧临时出现的对勾"))
        XCTAssertTrue(text.contains("Return 或 Enter 完成，Esc 取消"))
        XCTAssertTrue(text.contains("基本滚动截图不需要辅助功能权限"))
        XCTAssertTrue(text.contains("全局快捷键可能需要辅助功能权限"))
        XCTAssertTrue(text.contains("预览面板不接收鼠标"))
        XCTAssertTrue(text.contains("不能手动回看"))
        XCTAssertTrue(text.contains("资源上限"))
        XCTAssertTrue(text.contains("阻塞暂停"))
        XCTAssertTrue(text.contains("不再继续接收"))
        XCTAssertTrue(text.contains("已接受的内容"))
        XCTAssertTrue(text.contains("页面动画或重叠不足"))
        XCTAssertTrue(text.contains("等页面稳定后继续滚动"))
        XCTAssertTrue(text.contains("达到资源上限后不能继续采集"))
        XCTAssertTrue(text.contains("只能完成已接受的长图或取消"))

        for obsoleteText in [
            "自动滚动",
            "物理滚轮会被拦截",
            "方向下拉菜单",
            "开始单步滚动",
            "每点一次",
            "自动推动目标页面",
            "不能改成反向",
            "达到资源上限后不能继续单步"
        ] {
            XCTAssertFalse(text.contains(obsoleteText), "滚动截图仍包含旧说明：\(obsoleteText)")
        }

        let scrollSessionCaption = try XCTUnwrap(
            capture.caption(forImageNamed: "capture-scroll-session")
        )
        let scrollSessionLabel = try XCTUnwrap(
            capture.accessibilityLabel(forImageNamed: "capture-scroll-session")
        )
        XCTAssertTrue(scrollSessionCaption.contains("鼠标滚轮或触控板"))
        XCTAssertTrue(scrollSessionCaption.contains("临时对勾"))
        XCTAssertTrue(scrollSessionLabel.contains("滚动截图按钮右侧的临时对勾"))
        XCTAssertFalse(scrollSessionCaption.contains("单步"))
        XCTAssertFalse(scrollSessionLabel.contains("方向下拉菜单"))
    }

    func testEnglishCaptureManualDocumentsContinuousManualScrollWorkflow() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))
        let document = try loader.load(language: .english)
        let capture = try XCTUnwrap(
            document.chapters.first { $0.id == "capture" }
        )
        let text = capture.flattenedText

        XCTAssertTrue(text.contains("scroll directly with your mouse wheel or trackpad"))
        XCTAssertTrue(text.contains("first reliable movement locks the stitching direction"))
        XCTAssertTrue(text.contains("Scrolling in reverse only reviews earlier content; it is not stitched"))
        XCTAssertTrue(text.contains("temporary checkmark to the right of Scroll Capture"))
        XCTAssertTrue(text.contains("Return or Enter finishes, and Esc cancels"))
        XCTAssertTrue(text.contains("Basic Scroll Capture does not need Accessibility permission"))
        XCTAssertTrue(text.contains("Global shortcuts may need Accessibility permission"))

        for obsoleteText in [
            "automatic scrolling",
            "blocks your physical scroll wheel",
            "direction menu",
            "Start Scroll Step",
            "step-by-step scrolling panel",
            "move the target page automatically"
        ] {
            XCTAssertFalse(text.contains(obsoleteText), "Scroll Capture still contains obsolete copy: \(obsoleteText)")
        }

        let scrollSessionCaption = try XCTUnwrap(
            capture.caption(forImageNamed: "capture-scroll-session")
        )
        let scrollSessionLabel = try XCTUnwrap(
            capture.accessibilityLabel(forImageNamed: "capture-scroll-session")
        )
        XCTAssertTrue(scrollSessionCaption.contains("mouse wheel or trackpad"))
        XCTAssertTrue(scrollSessionCaption.contains("temporary checkmark"))
        XCTAssertTrue(scrollSessionLabel.contains("temporary checkmark to the right of Scroll Capture"))
        XCTAssertFalse(scrollSessionCaption.contains("step-by-step"))
        XCTAssertFalse(scrollSessionLabel.contains("direction menu"))
    }

    func testPinAndOCRManualBoundariesMatchCurrentProduct() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))
        let document = try loader.load(language: .zhHans)
        let pin = try XCTUnwrap(
            document.chapters.first { $0.id == "pin" }
        )
        let pinText = pin.flattenedText

        XCTAssertTrue(pin.hasShortcut(action: "从当前截图创建贴图", keys: ["⌘", "1"]))
        XCTAssertTrue(pin.hasShortcut(action: "恢复最近隐藏的贴图（默认）", keys: ["⌘", "1"]))
        XCTAssertTrue(pinText.contains("默认快捷键是 Command+1"))
        XCTAssertTrue(pinText.contains("设置页"))
        XCTAssertTrue(pinText.contains("修改或禁用"))
        XCTAssertTrue(pinText.contains("菜单或设置"))
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
        XCTAssertTrue(ocrText.contains("Command+3"))
        XCTAssertTrue(ocrText.contains("默认快捷键"))
        XCTAssertTrue(ocrText.contains("修改或禁用"))
        XCTAssertTrue(ocrText.contains("菜单或设置"))

        for imageName in ["ocr-success", "ocr-failure"] {
            let label = try XCTUnwrap(
                ocr.accessibilityLabel(forImageNamed: imageName)
            )
            XCTAssertTrue(label.contains("屏幕中间靠下"))
            XCTAssertFalse(label.contains("屏幕中央"))
        }
    }

    func testTeachingPenManualNamesEveryAvailableTool() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))
        let document = try loader.load(language: .zhHans)
        let teachingPen = try XCTUnwrap(
            document.chapters.first { $0.id == "teaching-pen" }
        )
        let text = teachingPen.flattenedText

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
                text.contains(tool),
                "教笔缺少工具说明：\(tool)"
            )
        }

        XCTAssertTrue(text.contains("Command+2"))
        XCTAssertTrue(text.contains("默认快捷键"))
        XCTAssertTrue(text.contains("修改或禁用"))
        XCTAssertTrue(text.contains("菜单或设置"))
        XCTAssertTrue(text.contains("先按 Esc 退出当前工具"))
        XCTAssertTrue(text.contains("支持后续编辑"))
        XCTAssertTrue(text.contains("选中后移动"))
        XCTAssertTrue(text.contains("调整大小"))
        XCTAssertTrue(text.contains("滑动或矩形马赛克"))
        XCTAssertTrue(text.contains("控制点调整"))
        XCTAssertTrue(text.contains("画笔笔迹"))
        XCTAssertTrue(text.contains("不能直接单击选中"))
        XCTAssertTrue(text.contains("不能直接缩放"))
        XCTAssertFalse(text.contains("单击已有标注可选中它"))
    }

    func testBundledEnglishManualLoadsEnglishDocument() throws {
        let bundle = Bundle(for: HelpManualTests.self)
        let loader = HelpContentLoader(bundle: bundle)

        XCTAssertNotNil(
            bundle.url(
                forResource: "en",
                withExtension: "json",
                subdirectory: "Help"
            )
        )
        let document = try loader.load(language: .english)

        XCTAssertEqual(document.language, "en")
        XCTAssertEqual(document.windowTitle, "XxSnap Help")
        XCTAssertEqual(
            document.chapters.map(\.navigationTitle),
            ["Capture", "Pin", "Text / QR Code Recognition", "Presentation Pen", "Report Issue"]
        )
        XCTAssertTrue(
            document.chapters.first?.flattenedText.contains("Region Capture")
                == true
        )
    }

    func testBundledEnglishManualHasLocalizedImageForEveryReference() throws {
        let bundle = Bundle(for: HelpManualTests.self)
        let loader = HelpContentLoader(bundle: bundle)
        let document = try loader.load(
            language: .english
        )

        for imageName in document.chapters.flatMap(\.imageNames) {
            let englishURL = try XCTUnwrap(
                bundle.url(
                    forResource: imageName,
                    withExtension: "png",
                    subdirectory: "Help/Images/en"
                ),
                "Missing localized English help image: \(imageName)"
            )
            let chineseURL = try XCTUnwrap(
                bundle.url(
                    forResource: imageName,
                    withExtension: "png",
                    subdirectory: "Help/Images/zh-Hans"
                )
            )
            let englishImage = try XCTUnwrap(NSImage(contentsOf: englishURL))
            let chineseImage = try XCTUnwrap(NSImage(contentsOf: chineseURL))

            XCTAssertEqual(
                englishImage.size,
                chineseImage.size,
                "Localized image dimensions differ: \(imageName)"
            )
            XCTAssertNotNil(
                loader.image(named: imageName, language: .english),
                "English loader did not resolve: \(imageName)"
            )
        }

        let loadedSuccess = try XCTUnwrap(
            loader.image(named: "ocr-success", language: .english)
        )
        let englishSuccessURL = try XCTUnwrap(
            bundle.url(
                forResource: "ocr-success",
                withExtension: "png",
                subdirectory: "Help/Images/en"
            )
        )
        let englishSuccess = try XCTUnwrap(
            NSImage(contentsOf: englishSuccessURL)
        )
        XCTAssertEqual(
            loadedSuccess.tiffRepresentation,
            englishSuccess.tiffRepresentation
        )
    }

    func testEnglishManualUsesRuntimeProductTerminology() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))
        let document = try loader.load(language: .english)
        let visibleText = (
            [document.windowTitle]
                + document.chapters.flatMap(\.visibleStrings)
        ).joined(separator: "\n")
        let headings = document.chapters.flatMap { chapter in
            chapter.blocks.compactMap(\.headingText)
        }

        XCTAssertEqual(
            document.chapters.map(\.navigationTitle),
            ["Capture", "Pin", "Text / QR Code Recognition", "Presentation Pen", "Report Issue"]
        )
        XCTAssertTrue(visibleText.contains("Choose Capture from the menu"))
        XCTAssertFalse(
            visibleText.contains("Choose Region Capture from the menu")
        )
        XCTAssertFalse(visibleText.contains("restore the Pin from the menu"))
        XCTAssertTrue(visibleText.contains("Long Capture Editor"))
        XCTAssertTrue(visibleText.contains("Disable Text / QR Code Recognition sound"))
        XCTAssertTrue(visibleText.contains("Disable Text / QR Code Recognition notification"))
        XCTAssertTrue(visibleText.contains("Open Link"))
        XCTAssertTrue(visibleText.contains("QR code"))
        XCTAssertFalse(visibleText.contains("Teaching Pen"))
        XCTAssertTrue(visibleText.contains("temporary checkmark"))
        XCTAssertFalse(visibleText.contains("Start Scroll Step"))
        XCTAssertTrue(headings.contains("Pen"))
        XCTAssertTrue(headings.contains("Redact"))
        XCTAssertTrue(visibleText.contains("Clear All"))
        XCTAssertTrue(
            visibleText.contains("Restore most recently hidden pin")
        )
        XCTAssertFalse(visibleText.contains("Start One Step"))
        XCTAssertFalse(headings.contains("Pencil"))
        XCTAssertFalse(headings.contains("Mosaic"))
        XCTAssertFalse(visibleText.contains("Restore Recent Hidden Pin"))
    }

    func testEnglishManualMirrorsChineseStructureAndContainsNoChineseText() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))
        let chinese = try loader.load(language: .zhHans)
        let english = try loader.load(language: .english)

        XCTAssertEqual(english.chapters.map(\.id), chinese.chapters.map(\.id))
        XCTAssertEqual(english.chapters.count, chinese.chapters.count)

        for (chineseChapter, englishChapter) in zip(
            chinese.chapters,
            english.chapters
        ) {
            XCTAssertEqual(englishChapter.id, chineseChapter.id)
            XCTAssertEqual(
                englishChapter.blocks.map(\.structureKind),
                chineseChapter.blocks.map(\.structureKind),
                "\(englishChapter.id) block structure differs"
            )
            XCTAssertEqual(
                englishChapter.shortcuts.count,
                chineseChapter.shortcuts.count,
                "\(englishChapter.id) shortcut entry count differs"
            )
            let chineseKeySequences = chineseChapter.allShortcutKeySequences
            let englishKeySequences = englishChapter.allShortcutKeySequences
            XCTAssertEqual(
                englishKeySequences.count,
                chineseKeySequences.count,
                "\(englishChapter.id) shortcut key sequence count differs"
            )
            for (chineseKeys, englishKeys) in zip(
                chineseKeySequences,
                englishKeySequences
            ) {
                XCTAssertTrue(
                    shortcutKeysMatch(
                        chinese: chineseKeys,
                        english: englishKeys
                    ),
                    "\(englishChapter.id) shortcut keys differ: "
                        + "\(chineseKeys) / \(englishKeys)"
                )
            }
            XCTAssertEqual(
                englishChapter.tableOfContents.count,
                chineseChapter.tableOfContents.count,
                "\(englishChapter.id) table of contents count differs"
            )
            XCTAssertEqual(
                englishChapter.imageNames,
                chineseChapter.imageNames,
                "\(englishChapter.id) image order differs"
            )
        }

        var visibleEnglishText = [english.windowTitle]
        for chapter in english.chapters {
            visibleEnglishText.append(contentsOf: chapter.visibleStrings)
        }
        for text in visibleEnglishText {
            XCTAssertFalse(
                text.containsCommonChineseCharacter,
                "English manual contains Chinese text: \(text)"
            )
        }
    }

    private func shortcutKeysMatch(
        chinese: [String],
        english: [String]
    ) -> Bool {
        chinese == english
            || (chinese == ["右键"] && english == ["Right-click"])
    }

    @MainActor
    func testBundledEnglishHelpWindowShowsSidebarAndBody() throws {
        var settings = AppSettings.default
        settings.language = .english
        let settingsStore = FakeHelpAppSettingsStore(settings: settings)
        let controller = HelpWindowController(
            settingsStore: settingsStore,
            contentLoader: HelpContentLoader(bundle: .main)
        )
        defer { controller.close() }

        controller.show()

        XCTAssertEqual(controller.window?.title, "XxSnap Help")
        XCTAssertEqual(
            controller.test_navigationTitles,
            ["Capture", "Pin", "Text / QR Code Recognition", "Presentation Pen", "Report Issue"]
        )
        XCTAssertTrue(controller.test_visibleTexts.contains("Region Capture"))
        XCTAssertTrue(
            controller.test_visibleTexts.contains {
                $0.localizedCaseInsensitiveContains("drag to select")
            }
        )
        XCTAssertEqual(controller.window?.contentMinSize.width, 760)
        XCTAssertEqual(controller.window?.contentMinSize.height, 512)
        XCTAssertGreaterThan(controller.window?.frame.height ?? 0, 500)
        XCTAssertGreaterThan(controller.window?.contentView?.frame.height ?? 0, 500)
    }

    func testBundledHelpProvidesBilingualIssueReportingInstructions() throws {
        let loader = HelpContentLoader(bundle: Bundle(for: HelpManualTests.self))

        let chinese = try loader.load(language: .zhHans)
        let chineseReport = try XCTUnwrap(
            chinese.chapters.first { $0.id == "report-issue" }
        )
        XCTAssertEqual(chineseReport.navigationTitle, "问题反馈")
        XCTAssertTrue(chineseReport.visibleStrings.contains("zfc.2012@gmail.com"))
        XCTAssertTrue(
            chineseReport.visibleStrings.contains {
                $0.contains("导出诊断日志")
            }
        )

        let english = try loader.load(language: .english)
        let englishReport = try XCTUnwrap(
            english.chapters.first { $0.id == "report-issue" }
        )
        XCTAssertEqual(englishReport.navigationTitle, "Report Issue")
        XCTAssertTrue(englishReport.visibleStrings.contains("zfc.2012@gmail.com"))
        XCTAssertTrue(
            englishReport.visibleStrings.contains {
                $0.localizedCaseInsensitiveContains("Export Diagnostic Logs")
            }
        )
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
            ["截图", "贴图", "文字/二维码识别", "教笔"]
        )
        XCTAssertEqual(controller.test_selectedChapterID, "capture")
    }

    @MainActor
    func testSidebarUsesBorderlessButtonsWithAccentSelection() throws {
        let controller = makeController()
        defer { controller.close() }

        controller.show()

        let root = try XCTUnwrap(controller.window?.contentView)
        let buttons = descendantViews(of: NSButton.self, in: root)
            .filter { ["截图", "贴图", "文字/二维码识别", "教笔"].contains($0.title) }
        let captureButton = try XCTUnwrap(
            buttons.first { $0.identifier?.rawValue == "capture" }
        )
        let pinButton = try XCTUnwrap(
            buttons.first { $0.identifier?.rawValue == "pin" }
        )
        let navigationGroup = try XCTUnwrap(
            captureButton.superview?.superview
        )
        let indicatorViews = descendantViews(of: NSView.self, in: root)
            .filter { $0.identifier?.rawValue.hasSuffix("-indicator") == true }
        let captureIndicatorView = try XCTUnwrap(
            indicatorViews.first {
                $0.identifier?.rawValue == "capture-indicator"
            }
        )
        let pinIndicatorView = try XCTUnwrap(
            indicatorViews.first {
                $0.identifier?.rawValue == "pin-indicator"
            }
        )
        let selectedAttribute = NSAccessibility.Attribute.selected
        let selectedChildrenAttribute = NSAccessibility.Attribute
            .selectedChildren
        let valueAttribute = NSAccessibility.Attribute.value
        let selectedChildIDs: () -> [String] = {
            let selectedChildren = navigationGroup
                .accessibilityAttributeValue(
                    selectedChildrenAttribute
                ) as? [NSButton]
            return selectedChildren?
                .compactMap { $0.identifier?.rawValue }
                .sorted() ?? []
        }
        let fontWeight: (NSButton) throws -> Int = { button in
            NSFontManager.shared.weight(of: try XCTUnwrap(button.font))
        }
        let referenceFontWeight: (
            NSButton,
            NSFont.Weight
        ) throws -> Int = { button, weight in
            let pointSize = try XCTUnwrap(button.font).pointSize
            let referenceFont = NSFont.systemFont(
                ofSize: pointSize,
                weight: weight
            )
            return NSFontManager.shared.weight(of: referenceFont)
        }

        XCTAssertEqual(buttons.count, 4)
        XCTAssertEqual(indicatorViews.count, 4)
        XCTAssertTrue(
            buttons.allSatisfy { $0.accessibilityRole() == .button }
        )
        XCTAssertEqual(navigationGroup.accessibilityRole(), .group)
        XCTAssertTrue(
            navigationGroup.accessibilityAttributeNames()
                .contains(selectedChildrenAttribute)
        )
        for button in buttons {
            let cell = try XCTUnwrap(button.cell as? NSButtonCell)
            XCTAssertFalse(button.isBordered, button.title)
            XCTAssertNil(button.image, button.title)
            XCTAssertEqual(button.imagePosition, .noImage, button.title)
            XCTAssertEqual(cell.showsStateBy, [], button.title)
            XCTAssertEqual(
                cell.highlightsBy,
                .contentsCellMask,
                button.title
            )

            var ancestor: NSView? = button.superview
            while let view = ancestor {
                XCTAssertNotEqual(
                    view.accessibilityRole(),
                    .radioGroup,
                    "\(button.title) ancestor: \(type(of: view))"
                )
                if view === root {
                    break
                }
                ancestor = view.superview
            }
            XCTAssertTrue(
                button.accessibilityAttributeNames().contains(selectedAttribute),
                button.title
            )
            XCTAssertFalse(
                button.accessibilityAttributeValue(valueAttribute) is NSNumber,
                "\(button.title) must not expose numeric AXValue"
            )
        }
        XCTAssertEqual(
            controller.test_selectedNavigationIndicators,
            ["capture"]
        )
        XCTAssertEqual(selectedChildIDs(), ["capture"])
        let captureIndicator: (
            isPositionedLeftOfButton: Bool,
            width: CGFloat,
            height: CGFloat,
            color: NSColor
        ) = try XCTUnwrap(
            controller.test_navigationIndicator(for: "capture")
        )
        XCTAssertTrue(captureIndicator.isPositionedLeftOfButton)
        XCTAssertEqual(captureIndicator.width, 3, accuracy: 0.01)
        XCTAssertGreaterThan(captureIndicator.height, captureIndicator.width)
        XCTAssertFalse(captureIndicatorView.isHidden)
        XCTAssertTrue(pinIndicatorView.isHidden)
        let captureIndicatorFrame = captureIndicatorView.convert(
            captureIndicatorView.bounds,
            to: root
        )
        let captureButtonFrame = captureButton.convert(
            captureButton.bounds,
            to: root
        )
        XCTAssertLessThanOrEqual(
            captureIndicatorFrame.maxX,
            captureButtonFrame.minX
        )
        assertColor(
            captureIndicator.color,
            matches: .controlAccentColor,
            appearance: root.effectiveAppearance,
            message: "capture indicator"
        )
        assertColor(
            try XCTUnwrap(
                captureIndicatorView.layer?.backgroundColor.flatMap(
                    NSColor.init(cgColor:)
                )
            ),
            matches: .controlAccentColor,
            appearance: root.effectiveAppearance,
            message: "capture indicator layer"
        )
        XCTAssertNil(controller.test_navigationIndicator(for: "pin"))
        XCTAssertEqual(
            buttons.filter { $0.isAccessibilitySelected() }.map(\.title),
            ["截图"]
        )
        XCTAssertEqual(
            captureButton.accessibilityAttributeValue(selectedAttribute) as? Bool,
            true
        )
        XCTAssertEqual(
            pinButton.accessibilityAttributeValue(selectedAttribute) as? Bool,
            false
        )
        for button in buttons {
            let expectedWeight: NSFont.Weight = button === captureButton
                ? .semibold
                : .regular
            XCTAssertEqual(
                try fontWeight(button),
                try referenceFontWeight(button, expectedWeight),
                button.title
            )
        }

        controller.test_clickNavigationButton("pin")

        XCTAssertEqual(controller.test_selectedNavigationIndicators, ["pin"])
        XCTAssertEqual(selectedChildIDs(), ["pin"])
        let pinIndicator: (
            isPositionedLeftOfButton: Bool,
            width: CGFloat,
            height: CGFloat,
            color: NSColor
        ) = try XCTUnwrap(
            controller.test_navigationIndicator(for: "pin")
        )
        XCTAssertTrue(pinIndicator.isPositionedLeftOfButton)
        XCTAssertEqual(pinIndicator.width, 3, accuracy: 0.01)
        XCTAssertGreaterThan(pinIndicator.height, pinIndicator.width)
        XCTAssertTrue(captureIndicatorView.isHidden)
        XCTAssertFalse(pinIndicatorView.isHidden)
        let pinIndicatorFrame = pinIndicatorView.convert(
            pinIndicatorView.bounds,
            to: root
        )
        let pinButtonFrame = pinButton.convert(pinButton.bounds, to: root)
        XCTAssertLessThanOrEqual(pinIndicatorFrame.maxX, pinButtonFrame.minX)
        assertColor(
            pinIndicator.color,
            matches: .controlAccentColor,
            appearance: root.effectiveAppearance,
            message: "pin indicator"
        )
        assertColor(
            try XCTUnwrap(
                pinIndicatorView.layer?.backgroundColor.flatMap(
                    NSColor.init(cgColor:)
                )
            ),
            matches: .controlAccentColor,
            appearance: root.effectiveAppearance,
            message: "pin indicator layer"
        )
        XCTAssertNil(controller.test_navigationIndicator(for: "capture"))
        XCTAssertEqual(
            buttons.filter { $0.isAccessibilitySelected() }.map(\.title),
            ["贴图"]
        )
        XCTAssertEqual(
            captureButton.accessibilityAttributeValue(selectedAttribute) as? Bool,
            false
        )
        XCTAssertEqual(
            pinButton.accessibilityAttributeValue(selectedAttribute) as? Bool,
            true
        )
        for button in buttons {
            let expectedWeight: NSFont.Weight = button === pinButton
                ? .semibold
                : .regular
            XCTAssertEqual(
                try fontWeight(button),
                try referenceFontWeight(button, expectedWeight),
                button.title
            )
        }
    }

    @MainActor
    func testSidebarAndIndicatorFollowEffectiveAppearanceChanges() throws {
        let controller = makeController()
        defer { controller.close() }

        controller.show()

        let window = try XCTUnwrap(controller.window)
        let root = try XCTUnwrap(window.contentView)
        root.layoutSubtreeIfNeeded()
        let sidebar = try XCTUnwrap(
            root.subviews.first {
                !($0 is NSBox) && !($0 is HelpContentView)
            }
        )
        let captureIndicator = try XCTUnwrap(
            descendantViews(of: NSView.self, in: sidebar).first {
                $0.identifier?.rawValue == "capture-indicator"
            }
        )

        for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(
                NSAppearance(named: appearanceName)
            )
            window.appearance = appearance
            root.layoutSubtreeIfNeeded()
            sidebar.viewDidChangeEffectiveAppearance()
            root.layoutSubtreeIfNeeded()

            XCTAssertEqual(
                sidebar.effectiveAppearance.bestMatch(
                    from: [.aqua, .darkAqua]
                ),
                appearanceName
            )
            assertColor(
                try XCTUnwrap(
                    sidebar.layer?.backgroundColor.flatMap(
                        NSColor.init(cgColor:)
                    )
                ),
                matches: .windowBackgroundColor,
                appearance: sidebar.effectiveAppearance,
                message: "\(appearanceName.rawValue) sidebar"
            )
            assertColor(
                try XCTUnwrap(
                    captureIndicator.layer?.backgroundColor.flatMap(
                        NSColor.init(cgColor:)
                    )
                ),
                matches: .controlAccentColor,
                appearance: captureIndicator.effectiveAppearance,
                message: "\(appearanceName.rawValue) indicator"
            )
        }
    }

    @MainActor
    func testHelpReadingAreaUsesSolidWhiteBackground() throws {
        let controller = makeController()
        defer { controller.close() }

        controller.show()

        let state: (
            helpContentLayerColor: NSColor?,
            scrollViewDrawsBackground: Bool,
            scrollViewBackgroundColor: NSColor,
            clipViewDrawsBackground: Bool,
            clipViewBackgroundColor: NSColor,
            documentViewLayerColor: NSColor?
        ) = controller.test_contentBackgroundState
        let appearance = try XCTUnwrap(
            controller.window?.contentView?.effectiveAppearance
        )
        let helpContentView = try XCTUnwrap(
            descendantViews(
                of: HelpContentView.self,
                in: try XCTUnwrap(controller.window?.contentView)
            ).first
        )
        let expectedAppearance: NSAppearance.Name = NSWorkspace.shared
            .accessibilityDisplayShouldIncreaseContrast
            ? .accessibilityHighContrastAqua
            : .aqua

        assertColor(
            try XCTUnwrap(state.helpContentLayerColor),
            matches: .white,
            appearance: appearance,
            message: "HelpContentView layer"
        )
        XCTAssertTrue(
            state.scrollViewDrawsBackground,
            "NSScrollView must draw its white background"
        )
        assertColor(
            state.scrollViewBackgroundColor,
            matches: .white,
            appearance: appearance,
            message: "NSScrollView"
        )
        XCTAssertTrue(
            state.clipViewDrawsBackground,
            "NSClipView must draw its white background"
        )
        assertColor(
            state.clipViewBackgroundColor,
            matches: .white,
            appearance: appearance,
            message: "NSClipView"
        )
        assertColor(
            try XCTUnwrap(state.documentViewLayerColor),
            matches: .white,
            appearance: appearance,
            message: "documentView layer"
        )
        XCTAssertEqual(helpContentView.appearance?.name, expectedAppearance)
    }

    @MainActor
    func testSystemAppearanceRefreshUpdatesReusedHelpWindow() async throws {
        let controller = makeController()
        defer { controller.close() }

        controller.show()
        let originalWindow = try XCTUnwrap(controller.window)
        controller.show()

        XCTAssertTrue(controller.window === originalWindow)

        controller.test_applySystemAppearance(
            increaseContrast: true,
            accentColor: .systemRed
        )

        XCTAssertEqual(
            controller.test_contentAppearanceName,
            .accessibilityHighContrastAqua
        )
        assertColor(
            try XCTUnwrap(
                controller.test_navigationIndicator(for: "capture")
            ).color,
            matches: .systemRed,
            appearance: originalWindow.effectiveAppearance,
            message: "refreshed high-contrast indicator"
        )

        controller.test_applySystemAppearance(
            increaseContrast: false,
            accentColor: .systemGreen
        )

        XCTAssertEqual(controller.test_contentAppearanceName, .aqua)
        assertColor(
            try XCTUnwrap(
                controller.test_navigationIndicator(for: "capture")
            ).color,
            matches: .systemGreen,
            appearance: originalWindow.effectiveAppearance,
            message: "refreshed Aqua indicator"
        )

        let refreshExpectation = expectation(
            description: "system color notification refreshes on main thread"
        )
        controller.test_onNextSystemAppearanceRefresh = { isMainThread in
            XCTAssertTrue(isMainThread)
            refreshExpectation.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread)
            NotificationCenter.default.post(
                name: NSColor.systemColorsDidChangeNotification,
                object: nil
            )
        }

        await fulfillment(of: [refreshExpectation], timeout: 2)

        let expectedAppearance: NSAppearance.Name = NSWorkspace.shared
            .accessibilityDisplayShouldIncreaseContrast
            ? .accessibilityHighContrastAqua
            : .aqua
        XCTAssertEqual(
            controller.test_contentAppearanceName,
            expectedAppearance
        )
        assertColor(
            try XCTUnwrap(
                controller.test_navigationIndicator(for: "capture")
            ).color,
            matches: .controlAccentColor,
            appearance: originalWindow.effectiveAppearance,
            message: "notification-refreshed indicator"
        )
    }

    @MainActor
    func testRenderedHelpTitlesExposeHeadingAccessibilityRole() throws {
        let controller = makeController()
        defer { controller.close() }

        controller.show()

        let root = try XCTUnwrap(controller.window?.contentView)
        let labels = descendantViews(of: NSTextField.self, in: root)
        let expectedLevels = [
            "区域截图": 1,
            "目录": 2,
            "快捷键": 2,
            "开始区域截图": 2
        ]
        for (title, level) in expectedLevels {
            let label = try XCTUnwrap(labels.first { $0.stringValue == title })
            XCTAssertEqual(
                label.accessibilityRole()?.rawValue,
                "AXHeading",
                title
            )
            XCTAssertEqual(
                label.accessibilityAttributeValue(
                    NSAccessibility.Attribute(rawValue: "AXHeadingLevel")
                ) as? Int,
                level,
                title
            )
        }
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
    func testBodyUsesThumbnailAndReloadsOriginalOnlyWhenPreviewOpens() throws {
        let original = solidImage(size: NSSize(width: 2400, height: 1350))
        let loader = FakeHelpContentLoader(
            document: try sampleDocument(),
            images: ["capture-overview": original]
        )
        let controller = makeController(loader: loader)
        defer { controller.close() }

        controller.show()

        let root = try XCTUnwrap(controller.window?.contentView)
        let bodyImage = try XCTUnwrap(
            descendantViews(of: NSButton.self, in: root)
                .compactMap(\.image)
                .first
        )
        XCTAssertFalse(bodyImage === original)
        XCTAssertLessThanOrEqual(max(bodyImage.size.width, bodyImage.size.height), 1_440)
        XCTAssertEqual(loader.imageRequests.map(\.name), ["capture-overview"])

        controller.test_clickFirstImage()

        XCTAssertTrue(controller.test_isImagePreviewVisible)
        XCTAssertEqual(
            loader.imageRequests.map(\.name),
            ["capture-overview", "capture-overview"]
        )
    }

    @MainActor
    func testClosingClearsThumbnailsAndReopeningReloadsThem() throws {
        let loader = FakeHelpContentLoader(
            document: try sampleDocument(),
            images: [
                "capture-overview": solidImage(
                    size: NSSize(width: 2400, height: 1350)
                )
            ]
        )
        let controller = makeController(loader: loader)
        defer { controller.close() }

        controller.show()
        let firstWindow = try XCTUnwrap(controller.window)
        XCTAssertEqual(controller.test_visibleImageCount, 1)
        XCTAssertEqual(loader.imageRequests.count, 1)

        firstWindow.close()

        XCTAssertEqual(controller.test_visibleImageCount, 0)

        controller.show()
        XCTAssertTrue(controller.window === firstWindow)
        XCTAssertEqual(controller.test_visibleImageCount, 1)
        XCTAssertEqual(loader.imageRequests.count, 2)

        controller.test_clickFirstImage()
        XCTAssertTrue(controller.test_isImagePreviewVisible)
        XCTAssertEqual(loader.imageRequests.count, 3)
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
    func testImagePreviewEscapeKeyDownEventClosesPreview() throws {
        let loader = FakeHelpContentLoader(
            document: try sampleDocument(),
            images: ["capture-overview": solidImage()]
        )
        let controller = makeController(loader: loader)
        defer { controller.close() }
        controller.show()
        controller.test_clickFirstImage()

        let previewWindow = try XCTUnwrap(controller.window?.childWindows?.first)
        let escape = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: previewWindow.windowNumber,
                context: nil,
                characters: "\u{1B}",
                charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false,
                keyCode: 53
            )
        )

        previewWindow.sendEvent(escape)

        XCTAssertFalse(controller.test_isImagePreviewVisible)
        XCTAssertEqual(controller.window?.childWindows?.count, 0)
        XCTAssertEqual(controller.test_imagePreviewDismissCount, 1)
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
    private func solidImage(
        size: NSSize = NSSize(width: 640, height: 360)
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    @MainActor
    private func descendantViews<T: NSView>(
        of type: T.Type,
        in root: NSView
    ) -> [T] {
        var matches: [T] = []
        if let match = root as? T {
            matches.append(match)
        }
        for subview in root.subviews {
            matches.append(contentsOf: descendantViews(of: type, in: subview))
        }
        return matches
    }

    @MainActor
    private func assertColor(
        _ actual: NSColor,
        matches expected: NSColor,
        appearance: NSAppearance,
        accuracy: CGFloat = 0.001,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        typealias RGBA = (
            red: CGFloat,
            green: CGFloat,
            blue: CGFloat,
            alpha: CGFloat
        )

        func components(of color: NSColor) -> RGBA? {
            guard let converted = color.usingColorSpace(.extendedSRGB) else {
                return nil
            }
            return (
                converted.redComponent,
                converted.greenComponent,
                converted.blueComponent,
                converted.alphaComponent
            )
        }

        var actualComponents: RGBA?
        var expectedComponents: RGBA?
        appearance.performAsCurrentDrawingAppearance {
            actualComponents = components(of: actual)
            expectedComponents = components(of: expected)
        }

        guard
            let actualComponents,
            let expectedComponents
        else {
            XCTFail(
                "\(message) could not be resolved in extended sRGB",
                file: file,
                line: line
            )
            return
        }

        XCTAssertEqual(
            actualComponents.red,
            expectedComponents.red,
            accuracy: accuracy,
            "\(message) red",
            file: file,
            line: line
        )
        XCTAssertEqual(
            actualComponents.green,
            expectedComponents.green,
            accuracy: accuracy,
            "\(message) green",
            file: file,
            line: line
        )
        XCTAssertEqual(
            actualComponents.blue,
            expectedComponents.blue,
            accuracy: accuracy,
            "\(message) blue",
            file: file,
            line: line
        )
        XCTAssertEqual(
            actualComponents.alpha,
            expectedComponents.alpha,
            accuracy: accuracy,
            "\(message) alpha",
            file: file,
            line: line
        )
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
              "navigationTitle": "文字/二维码识别",
              "title": "文字/二维码识别",
              "introduction": "提取截图中的文字或二维码内容。",
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

    var visibleStrings: [String] {
        [
            navigationTitle,
            title,
            introduction
        ]
            + tableOfContents
            + shortcuts.flatMap { [$0.action] + $0.keys }
            + blocks.flatMap(\.visibleStrings)
    }

    var allShortcutKeySequences: [[String]] {
        shortcuts.map(\.keys) + blocks.flatMap(\.shortcutKeySequences)
    }

    var faqCount: Int {
        blocks.reduce(0) { $0 + $1.faqCount }
    }

    func hasShortcut(action: String, keys: [String]) -> Bool {
        shortcuts.contains(HelpShortcut(action: action, keys: keys))
    }

    func accessibilityLabel(forImageNamed name: String) -> String? {
        blocks.first { $0.imageName == name }?.imageAccessibilityLabel
    }

    func caption(forImageNamed name: String) -> String? {
        blocks.first { $0.imageName == name }?.imageCaption
    }
}

private extension HelpContentBlock {
    var structureKind: String {
        switch self {
        case let .heading(level, _):
            return "heading:\(level)"
        case .paragraph:
            return "paragraph"
        case let .steps(items):
            return "steps:\(items.count)"
        case let .bullets(items):
            return "bullets:\(items.count)"
        case let .shortcuts(items):
            return "shortcuts:\(items.count)"
        case .image:
            return "image"
        case .note:
            return "note"
        case .warning:
            return "warning"
        case let .faq(items):
            return "faq:\(items.count)"
        }
    }

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

    var headingText: String? {
        if case let .heading(_, text) = self {
            return text
        }
        return nil
    }

    var visibleStrings: [String] {
        switch self {
        case let .heading(_, text), let .paragraph(text):
            return [text]
        case let .steps(items):
            return items.flatMap { [$0.text] + ($0.keys ?? []) }
        case let .bullets(items):
            return items
        case let .shortcuts(items):
            return items.flatMap { [$0.action] + $0.keys }
        case let .image(_, caption, accessibilityLabel):
            return [caption, accessibilityLabel]
        case let .note(title, text), let .warning(title, text):
            return [title, text]
        case let .faq(items):
            return items.flatMap { [$0.question, $0.answer] }
        }
    }

    var shortcutKeySequences: [[String]] {
        switch self {
        case let .steps(items):
            return items.compactMap(\.keys)
        case let .shortcuts(items):
            return items.map(\.keys)
        default:
            return []
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

    var imageAccessibilityLabel: String? {
        if case let .image(_, _, accessibilityLabel) = self {
            return accessibilityLabel
        }
        return nil
    }

    var imageCaption: String? {
        if case let .image(_, caption, _) = self {
            return caption
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

private extension String {
    var containsCommonChineseCharacter: Bool {
        unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
        }
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
    private(set) var imageRequests: [(name: String, language: AppLanguage)] = []
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
        imageRequests.append((name, language))
        return images[name]
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
