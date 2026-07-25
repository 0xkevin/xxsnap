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
                .heading(level: 2, text: "Capture"),
                .paragraph("Choose a capture mode."),
                .steps([
                    HelpStep(text: "Press the shortcut.", keys: ["⌘", "`"]),
                    HelpStep(text: "Select an area.", keys: nil)
                ]),
                .bullets(["Window capture", "Area capture"]),
                .shortcuts([
                    HelpShortcut(action: "Capture", keys: ["⌘", "`"])
                ]),
                .image(
                    name: "capture-overview",
                    caption: "Capture overlay",
                    accessibilityLabel: "Capture overlay with a selected area"
                ),
                .note(title: "Tip", text: "Press Escape to cancel."),
                .faq([
                    HelpFAQItem(
                        question: "Can I cancel?",
                        answer: "Yes, press Escape."
                    )
                ])
            ]
        )

        let teachingPen = try XCTUnwrap(
            document.chapters.first { $0.id == "teaching-pen" }
        )
        XCTAssertEqual(
            teachingPen.blocks,
            [.warning(title: "Privacy", text: "Avoid revealing sensitive data.")]
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

    private static let validDocumentJSON = """
        {
          "version": 1,
          "language": "en",
          "windowTitle": "XxSnap Help",
          "chapters": [
            {
              "id": "capture",
              "navigationTitle": "Capture",
              "title": "Capture screenshots",
              "introduction": "Capture any part of the screen.",
              "tableOfContents": ["Start capture"],
              "shortcuts": [
                { "action": "Capture", "keys": ["⌘", "`"] }
              ],
              "blocks": [
                { "type": "heading", "level": 2, "text": "Capture" },
                { "type": "paragraph", "text": "Choose a capture mode." },
                {
                  "type": "steps",
                  "items": [
                    { "text": "Press the shortcut.", "keys": ["⌘", "`"] },
                    { "text": "Select an area." }
                  ]
                },
                {
                  "type": "bullets",
                  "items": ["Window capture", "Area capture"]
                },
                {
                  "type": "shortcuts",
                  "items": [
                    { "action": "Capture", "keys": ["⌘", "`"] }
                  ]
                },
                {
                  "type": "image",
                  "name": "capture-overview",
                  "caption": "Capture overlay",
                  "accessibilityLabel": "Capture overlay with a selected area"
                },
                {
                  "type": "note",
                  "title": "Tip",
                  "text": "Press Escape to cancel."
                },
                {
                  "type": "faq",
                  "items": [
                    {
                      "question": "Can I cancel?",
                      "answer": "Yes, press Escape."
                    }
                  ]
                }
              ]
            },
            {
              "id": "pin",
              "navigationTitle": "Pin",
              "title": "Pin screenshots",
              "introduction": "Keep references visible.",
              "tableOfContents": [],
              "shortcuts": [],
              "blocks": []
            },
            {
              "id": "ocr",
              "navigationTitle": "OCR",
              "title": "Recognize text",
              "introduction": "Extract text from screenshots.",
              "tableOfContents": [],
              "shortcuts": [],
              "blocks": []
            },
            {
              "id": "teaching-pen",
              "navigationTitle": "Teaching Pen",
              "title": "Present clearly",
              "introduction": "Draw while presenting.",
              "tableOfContents": [],
              "shortcuts": [],
              "blocks": [
                {
                  "type": "warning",
                  "title": "Privacy",
                  "text": "Avoid revealing sensitive data."
                }
              ]
            }
          ]
        }
        """
}
