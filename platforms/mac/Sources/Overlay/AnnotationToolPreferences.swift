import AppKit
import Foundation

enum AnnotationToolPreferencesScope: String, Codable, CaseIterable {
    case capture
    case longImage
    case pinnedImage
    case teachingPen
}

struct PersistedAnnotationColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init?(_ color: NSColor) {
        guard let converted = color.usingColorSpace(.sRGB) else { return nil }
        red = Double(converted.redComponent)
        green = Double(converted.greenComponent)
        blue = Double(converted.blueComponent)
        alpha = Double(converted.alphaComponent)
    }

    var color: NSColor? {
        let components = [red, green, blue, alpha]
        guard components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        return NSColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

struct PersistedAnnotationStyle: Codable, Equatable {
    let strokeColor: PersistedAnnotationColor?
    let strokeWidth: Double
    let strokePattern: Int
    let fillEnabled: Bool
    let fillColor: PersistedAnnotationColor?
    let cornerRadius: Double
    let textSize: Double
    let textFontFamily: String?
    let textBold: Bool
    let textItalic: Bool
    let textOutlineEnabled: Bool
    let textOutlineColor: PersistedAnnotationColor?

    init(_ style: CaptureAnnotationStyle) {
        strokeColor = PersistedAnnotationColor(style.strokeColor)
        strokeWidth = Double(style.strokeWidth)
        strokePattern = style.strokePattern.rawValue
        fillEnabled = style.fillEnabled
        fillColor = PersistedAnnotationColor(style.fillColor)
        cornerRadius = Double(style.cornerRadius)
        textSize = Double(style.textSize)
        textFontFamily = style.textFontFamily
        textBold = style.textBold
        textItalic = style.textItalic
        textOutlineEnabled = style.textOutlineEnabled
        textOutlineColor = PersistedAnnotationColor(style.textOutlineColor)
    }

    func restored(fallback: CaptureAnnotationStyle) -> CaptureAnnotationStyle {
        var style = fallback
        if let color = strokeColor?.color { style.strokeColor = color }
        if strokeWidth.isFinite { style.strokeWidth = max(1, min(200, CGFloat(strokeWidth))) }
        if let pattern = CaptureStrokePattern(rawValue: strokePattern) { style.strokePattern = pattern }
        style.fillEnabled = fillEnabled
        if let color = fillColor?.color { style.fillColor = color }
        if cornerRadius.isFinite { style.cornerRadius = max(0, min(30, CGFloat(cornerRadius))) }
        if textSize.isFinite { style.textSize = max(3, min(72, CGFloat(textSize))) }
        if let textFontFamily, !textFontFamily.isEmpty, textFontFamily.count <= 200 {
            style.textFontFamily = textFontFamily
        } else {
            style.textFontFamily = nil
        }
        style.textBold = textBold
        style.textItalic = textItalic
        style.textOutlineEnabled = textOutlineEnabled
        if let color = textOutlineColor?.color { style.textOutlineColor = color }
        return style
    }
}

struct AnnotationToolPreferences: Codable, Equatable {
    var shapeStyle: PersistedAnnotationStyle
    var arrowStyle: PersistedAnnotationStyle
    var brushStyle: PersistedAnnotationStyle
    var markerStyle: PersistedAnnotationStyle
    var mosaicStyle: PersistedAnnotationStyle
    var textStyle: PersistedAnnotationStyle
    var numberStyle: PersistedAnnotationStyle
    var magnifierStyle: PersistedAnnotationStyle
    var preferredShapeKind: String
    var preferredMosaicKind: String
    var startArrowType: Int
    var endArrowType: Int
    var eraserMode: String
    var magnifierShape: String
    var magnifierZoom: Double
    var numberMarkType: String
    var mosaicRedactionType: String
    var gaussianBlurValue: Int
    var pixelMosaicValue: Int
    var customColor: PersistedAnnotationColor?
}

protocol AnnotationToolPreferencesStoring {
    func load(scope: AnnotationToolPreferencesScope) -> AnnotationToolPreferences?
    func save(_ preferences: AnnotationToolPreferences, scope: AnnotationToolPreferencesScope)
}

final class AnnotationToolPreferencesStore: AnnotationToolPreferencesStoring {
    static let shared = AnnotationToolPreferencesStore(
        isEnabled: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    )

    private let userDefaults: UserDefaults
    private let keyPrefix: String
    private let isEnabled: Bool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "xxsnap.annotation-tool-preferences.v1",
        isEnabled: Bool = true
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
        self.isEnabled = isEnabled
    }

    func load(scope: AnnotationToolPreferencesScope) -> AnnotationToolPreferences? {
        guard isEnabled,
              let data = userDefaults.data(forKey: key(for: scope))
        else { return nil }
        return try? decoder.decode(AnnotationToolPreferences.self, from: data)
    }

    func save(_ preferences: AnnotationToolPreferences, scope: AnnotationToolPreferencesScope) {
        guard isEnabled, let data = try? encoder.encode(preferences) else { return }
        userDefaults.set(data, forKey: key(for: scope))
    }

    private func key(for scope: AnnotationToolPreferencesScope) -> String {
        "\(keyPrefix).\(scope.rawValue)"
    }
}
