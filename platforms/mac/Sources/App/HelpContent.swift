import AppKit
import Foundation

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
    case image(
        name: String,
        caption: String,
        accessibilityLabel: String
    )
    case note(title: String, text: String)
    case warning(title: String, text: String)
    case faq([HelpFAQItem])
}

extension HelpContentBlock: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case level
        case text
        case items
        case name
        case caption
        case accessibilityLabel
        case title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "heading":
            self = .heading(
                level: try container.decode(Int.self, forKey: .level),
                text: try container.decode(String.self, forKey: .text)
            )
        case "paragraph":
            self = .paragraph(
                try container.decode(String.self, forKey: .text)
            )
        case "steps":
            self = .steps(
                try container.decode([HelpStep].self, forKey: .items)
            )
        case "bullets":
            self = .bullets(
                try container.decode([String].self, forKey: .items)
            )
        case "shortcuts":
            self = .shortcuts(
                try container.decode([HelpShortcut].self, forKey: .items)
            )
        case "image":
            self = .image(
                name: try container.decode(String.self, forKey: .name),
                caption: try container.decode(String.self, forKey: .caption),
                accessibilityLabel: try container.decode(
                    String.self,
                    forKey: .accessibilityLabel
                )
            )
        case "note":
            self = .note(
                title: try container.decode(String.self, forKey: .title),
                text: try container.decode(String.self, forKey: .text)
            )
        case "warning":
            self = .warning(
                title: try container.decode(String.self, forKey: .title),
                text: try container.decode(String.self, forKey: .text)
            )
        case "faq":
            self = .faq(
                try container.decode([HelpFAQItem].self, forKey: .items)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown help content block type: \(type)"
            )
        }
    }
}

enum HelpContentError: Error, Equatable {
    case missingResource(String)
    case emptyChapters
    case duplicateChapterID(String)
    case emptyChapterID
}

protocol HelpContentLoading {
    func load(language: AppLanguage) throws -> HelpDocument
    func image(named: String, language: AppLanguage) -> NSImage?
}

struct HelpContentLoader: HelpContentLoading {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func load(language: AppLanguage) throws -> HelpDocument {
        let resourceNames: [String]
        switch language {
        case .zhHans:
            resourceNames = ["zh-Hans"]
        case .english:
            resourceNames = ["en", "zh-Hans"]
        }

        for resourceName in resourceNames {
            if let url = bundle.url(
                forResource: resourceName,
                withExtension: "json",
                subdirectory: "Help"
            ) {
                return try decode(Data(contentsOf: url))
            }
        }

        throw HelpContentError.missingResource("Help/zh-Hans.json")
    }

    func image(named name: String, language: AppLanguage) -> NSImage? {
        let directories: [String]
        switch language {
        case .zhHans:
            directories = ["Help/Images/zh-Hans"]
        case .english:
            directories = ["Help/Images/en", "Help/Images/zh-Hans"]
        }

        for directory in directories {
            if let url = bundle.url(
                forResource: name,
                withExtension: "png",
                subdirectory: directory
            ),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }

    func decode(_ data: Data) throws -> HelpDocument {
        let document = try JSONDecoder().decode(HelpDocument.self, from: data)
        guard !document.chapters.isEmpty else {
            throw HelpContentError.emptyChapters
        }

        var chapterIDs = Set<String>()
        for chapter in document.chapters {
            guard !chapter.id.isEmpty else {
                throw HelpContentError.emptyChapterID
            }
            guard chapterIDs.insert(chapter.id).inserted else {
                throw HelpContentError.duplicateChapterID(chapter.id)
            }
        }

        return document
    }
}
