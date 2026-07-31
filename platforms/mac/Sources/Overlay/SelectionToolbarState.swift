import AppKit
import Carbon.HIToolbox

enum FixedToolbarShortcut: String, Equatable, CaseIterable {
    case rectangle
    case polyline
    case pen
    case marker
    case eyedropper
    case mosaic
    case text
    case number
    case magnifier
    case eraser
    case scroll
    case undo
    case redo
    case cancel
    case save
    case copy
}

enum SelectionToolbarState {
    struct ToolbarShortcut: Equatable {
        let key: String
        let modifiers: NSEvent.ModifierFlags
        let iconName: String?
        let displayText: String
        let keyCode: UInt32?

        init(
            key: String,
            modifiers: NSEvent.ModifierFlags,
            iconName: String?,
            displayText: String,
            keyCode: UInt32? = nil
        ) {
            self.key = key
            self.modifiers = modifiers
            self.iconName = iconName
            self.displayText = displayText
            self.keyCode = keyCode
        }

        func matches(
            charactersIgnoringModifiers: String?,
            keyCode eventKeyCode: UInt16? = nil,
            modifierFlags: NSEvent.ModifierFlags
        ) -> Bool {
            let relevantModifiers = modifierFlags.intersection([.command, .control, .option, .shift])
            if let keyCode {
                return eventKeyCode.map(UInt32.init) == keyCode
                    && relevantModifiers == modifiers
            }

            guard charactersIgnoringModifiers?.lowercased() == key.lowercased() else {
                return false
            }

            let isPlainLetter = modifiers.isEmpty && key.count == 1 && key.first?.isLetter == true
            if isPlainLetter {
                return relevantModifiers.intersection([.command, .control, .option]).isEmpty
            }
            return relevantModifiers == modifiers
        }
    }

    static let defaultPinShortcut = ToolbarShortcut(
        key: "1",
        modifiers: .command,
        iconName: "command",
        displayText: "1",
        keyCode: UInt32(kVK_ANSI_1)
    )

    private static let toolbarShortcuts: [String: ToolbarShortcut] = {
        let command = NSEvent.ModifierFlags.command
        return [
            "rectangle": ToolbarShortcut(key: "s", modifiers: [], iconName: nil, displayText: "S"),
            "polyline": ToolbarShortcut(key: "a", modifiers: [], iconName: nil, displayText: "A"),
            "pen": ToolbarShortcut(key: "b", modifiers: [], iconName: nil, displayText: "B"),
            "marker": ToolbarShortcut(key: "h", modifiers: [], iconName: nil, displayText: "H"),
            "eyedropper": ToolbarShortcut(key: "p", modifiers: [], iconName: nil, displayText: "P"),
            "mosaic": ToolbarShortcut(key: "m", modifiers: [], iconName: nil, displayText: "M"),
            "text": ToolbarShortcut(key: "t", modifiers: [], iconName: nil, displayText: "T"),
            "number": ToolbarShortcut(key: "n", modifiers: [], iconName: nil, displayText: "N"),
            "magnifier": ToolbarShortcut(key: "g", modifiers: [], iconName: nil, displayText: "G"),
            "eraser": ToolbarShortcut(key: "e", modifiers: [], iconName: nil, displayText: "E"),
            "scroll": ToolbarShortcut(key: "r", modifiers: [], iconName: nil, displayText: "R"),
            "undo": ToolbarShortcut(key: "z", modifiers: command, iconName: "command", displayText: "Z"),
            "redo": ToolbarShortcut(key: "z", modifiers: [command, .shift], iconName: "command", displayText: "⇧Z"),
            "cancel": ToolbarShortcut(key: "\u{1b}", modifiers: [], iconName: nil, displayText: "ESC"),
            "save": ToolbarShortcut(key: "s", modifiers: command, iconName: "command", displayText: "S"),
            "copy": ToolbarShortcut(key: "c", modifiers: command, iconName: "command", displayText: "C"),
            "finishEditing": ToolbarShortcut(key: "\u{1b}", modifiers: [], iconName: nil, displayText: "ESC"),
        ]
    }()

    static let colorSamplerCopyHintText = L10n(language: .zhHans).text(.colorSamplerCopyHex)
    static let colorSamplerCopySuccessText = "复制成功"
    static let colorSamplerCopySuccessDuration: TimeInterval = 1.2
    static let colorSamplerCopySuccessTextColor = NSColor.systemGreen
    static let colorSamplerCoordinateTextColor = NSColor.white
    static let colorSamplerValueTextColor = NSColor.white
    static let colorSamplerCopyHintTextColor = NSColor.white
    static let colorSamplerSwitchHintTextColor = NSColor.white
    static let toolbarSelectedBackgroundAlpha: CGFloat = 0
    static let measurementControlSelectedBackgroundAlpha: CGFloat = 0.34
    static let optionsToolbarHorizontalPadding: CGFloat = 10
    static let textOptionIconSize: CGFloat = 15
    static let textEmphasisIconSize: CGFloat = 20
    static let textDropdownBackgroundColor = NSColor.white
    static let textDropdownScrollbarTrackColor = NSColor.black.withAlphaComponent(0.14)
    static let textDropdownScrollbarThumbColor = NSColor.black.withAlphaComponent(0.46)
    static let textSizeValues: [CGFloat] = (3...72).map { CGFloat($0) }
    static let numberSizeValues: [CGFloat] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 20, 24, 32, 40, 48, 60, 72]
    static let eyedropperCursorSize = NSSize(width: 24, height: 24)
    static let eyedropperIconSize: CGFloat = 18
    static let eyedropperCursorHotSpot = NSPoint(x: 3.6, y: 20.4)
    static let eyedropperSampleOffset = NSSize(width: 0, height: 0)

    static func mainToolbarDragHandleIconColor(enabled: Bool) -> NSColor {
        enabled
            ? NSColor(deviceWhite: 0.48, alpha: 0.75)
            : .disabledControlTextColor
    }

    enum ColorSamplerCopyMode: Equatable {
        case hex
        case rgb
    }

    enum FillPreviewShape: Equatable {
        case rectangle
        case ellipse
    }

    struct FillPreviewStyle: Equatable {
        var shape: FillPreviewShape
        var color: NSColor
        var showsStrokeOutline: Bool
    }

    enum SwatchSelection: Equatable {
        case palette(Int)
        case custom
    }

    enum StrokeMenuSelection: Equatable {
        case item(Int)
        case menuBackground
        case outside
    }

    enum ArrowTypeMenuSelection: Equatable {
        case item(Int)
        case menuBackground
        case outside
    }

    enum OptionsToolbarMode: Equatable {
        case shape
        case arrowLine
        case brush
        case marker
        case mosaic
        case text
        case numberSequence
        case magnifier
        case eraser
    }

    struct OptionsToolbarLayout: Equatable {
        var strokeWidths: [NSRect]
        var textSizes: [NSRect]
        var textBold: NSRect
        var textItalic: NSRect
        var textOutline: NSRect
        var textFont: NSRect
        var textSize: NSRect
        var numberMarkType: NSRect
        var numberSize: NSRect
        var magnifierZoom: NSRect
        var magnifierZooms: [NSRect]
        var fillToggle: NSRect?
        var rectangleMode: NSRect?
        var ellipseMode: NSRect?
        var eraserPointMode: NSRect?
        var eraserRectangleMode: NSRect?
        var eraserClearAllSeparator: NSRect?
        var eraserClearAll: NSRect?
        var strokeStyle: NSRect
        var startArrowType: NSRect?
        var endArrowType: NSRect?
        var colorSwatches: [NSRect]
    }

    enum MeasurementControl: Equatable {
        case cornerStyle
        case aspectRatioLock
        case refresh
    }

    struct MeasurementControlLayout: Equatable {
        var panel: NSRect
        var label: NSRect
        var labelSeparator: NSRect
        var cornerStyle: NSRect
        var aspectRatio: NSRect
        var refreshSeparator: NSRect
        var refresh: NSRect
    }

    struct ArrowLineActivationState {
        var style: CaptureAnnotationStyle
        var startArrowType: CaptureArrowType
        var endArrowType: CaptureArrowType
    }

    enum ArrowTypeEndpoint: Equatable {
        case start
        case end
    }

    struct ArrowTypePair: Equatable {
        var start: CaptureArrowType
        var end: CaptureArrowType
    }

    enum ArrowLineHitTarget: Equatable {
        case start
        case end
        case control
        case body
        case none
    }

    enum BrushRotationHitTarget: Equatable {
        case start
        case end
        case none
    }

    struct StrokePatternOption: Equatable {
        var pattern: CaptureStrokePattern
        var requiresPremiumAccess: Bool
        var isEnabled: Bool
    }

    enum OverlayCursorStyle: Equatable {
        case arrow
        case crosshair
        case textInput
        case eyedropper
        case move
        case moveLight
        case resizeLeftRight
        case resizeLeftRightLight
        case resizeUpDown
        case resizeUpDownLight
        case resizeTopLeft
        case resizeTopLeftLight
        case resizeTopRight
        case resizeTopRightLight
        case resizeBottomLeft
        case resizeBottomLeftLight
        case resizeBottomRight
        case resizeBottomRightLight
        case rotationHandle
        case eraser
        case brush
        case brushLight
        case marker
        case markerLight
        case eyedropperLight
        case numberMark
        case numberCheck
        case numberCross
    }

    static let defaultFillPreviewColor = NSColor.systemGray
    static let defaultMarkerColor = NSColor(srgbRed: 179 / 255, green: 235 / 255, blue: 0 / 255, alpha: 1)
    static let rotationHandleInset: CGFloat = 14
    static let magnifierZoomValues: [CGFloat] = [1.5, 2, 3, 4]

    static func strokeWidthValues(for mode: OptionsToolbarMode) -> [CGFloat] {
        switch mode {
        case .shape:
            return [2, 4, 7]
        case .arrowLine:
            return [3, 4, 6]
        case .brush:
            return [3, 5, 7]
        case .marker:
            return [14, 18, 22]
        case .mosaic:
            return [15, 25, 35]
        case .magnifier:
            return [2, 4, 7]
        case .text, .numberSequence, .eraser:
            return []
        }
    }

    static func strokeWidthPreviewLineWidth(for width: CGFloat, mode: OptionsToolbarMode) -> CGFloat {
        guard mode == .marker else {
            return width
        }

        let markerWidths = strokeWidthValues(for: .marker)
        let brushWidths = strokeWidthValues(for: .brush)
        guard let index = markerWidths.firstIndex(of: width), brushWidths.indices.contains(index) else {
            return width
        }
        return brushWidths[index]
    }

    static func markerCursorDotDiameter(for strokeWidth: CGFloat) -> CGFloat {
        switch strokeWidth {
        case ..<16:
            return 10
        case ..<20:
            return 13
        default:
            return 16
        }
    }

    static func showsStrokeStyleField(for mode: OptionsToolbarMode) -> Bool {
        mode != .marker && mode != .mosaic && mode != .text && mode != .numberSequence && mode != .magnifier && mode != .eraser
    }

    static func shouldShowOptionsToolbar(isPrimaryShapeToolActive: Bool) -> Bool {
        isPrimaryShapeToolActive
    }

    static func toggledPrimaryShapeTool(current: CaptureAnnotationKind?, defaultShape: CaptureAnnotationKind) -> CaptureAnnotationKind? {
        current == nil ? defaultShape : nil
    }

    static func styleForPrimaryShapeToolActivation(
        currentStyle: CaptureAnnotationStyle,
        paletteColors: [NSColor]
    ) -> CaptureAnnotationStyle {
        var style = currentStyle
        style.strokeWidth = strokeWidthValues(for: .shape)[1]
        style.cornerRadius = 5
        applyDefaultPaletteColor(to: &style, paletteColors: paletteColors)

        return style
    }

    static func tooltipTitle(
        for identifier: String,
        language: AppLanguage = .zhHans
    ) -> String? {
        L10n(language: language).toolbarTooltip(for: identifier)
    }

    static func toolbarShortcut(
        for identifier: String,
        pinShortcut: ToolbarShortcut? = defaultPinShortcut
    ) -> ToolbarShortcut? {
        if identifier == "pin" {
            return pinShortcut
        }
        return toolbarShortcuts[identifier]
    }

    static func fixedShortcutConflict(for settings: HotKeySettings) -> FixedToolbarShortcut? {
        if settings.keyCode == UInt32(kVK_Escape) {
            return .cancel
        }
        guard let candidate = HotKeyFormatter.toolbarShortcut(from: settings) else {
            return nil
        }
        return FixedToolbarShortcut.allCases.first { shortcut in
            toolbarShortcuts[shortcut.rawValue]?.matches(
                charactersIgnoringModifiers: candidate.key,
                modifierFlags: candidate.modifiers
            ) == true
        }
    }

    static func tooltipShortcutIconImage(named name: String, tint: NSColor, size: CGFloat) -> NSImage? {
        guard let source = Bundle.main.url(forResource: name, withExtension: "svg").flatMap(NSImage.init(contentsOf:)) else {
            return nil
        }

        let targetSize = NSSize(width: size, height: size)
        let targetRect = NSRect(origin: .zero, size: targetSize)
        let mask = NSImage(size: targetSize)
        mask.lockFocus()
        NSColor.clear.setFill()
        targetRect.fill()
        source.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1)
        mask.unlockFocus()

        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSColor.clear.setFill()
        targetRect.fill()
        tint.setFill()
        targetRect.fill()
        mask.draw(in: targetRect, from: .zero, operation: .destinationIn, fraction: 1)
        image.unlockFocus()
        return image
    }

    static func toolbarIconInset(for resourceName: String) -> CGFloat {
        switch resourceName {
        case "screenshot":
            return -1
        case "number-sequence":
            return 3
        case "trash":
            return 3
        case "arrow", "masaike2", "text-tool", "straw-ranging", "scroll-screen2", "undo-enabled", "undo-disabled", "redo-enabled", "redo-disabled":
            return 0
        default:
            return 2
        }
    }

    static let eraserCursorIconResourceName = "eraser-tool"

    static func usesFixedColorToolbarIconResource(_ resourceName: String) -> Bool {
        switch resourceName {
        case "undo-enabled", "undo-disabled", "redo-enabled", "redo-disabled":
            return true
        default:
            return false
        }
    }

    static func fillPreviewStyle(currentShapeKind: CaptureAnnotationKind, currentStyle: CaptureAnnotationStyle) -> FillPreviewStyle {
        FillPreviewStyle(
            shape: currentShapeKind == .ellipse ? .ellipse : .rectangle,
            color: currentStyle.fillEnabled ? currentStyle.fillColor : defaultFillPreviewColor,
            showsStrokeOutline: false
        )
    }

    static func mosaicDefaultRedactionValue(for type: CaptureMosaicRedactionType) -> Int {
        8
    }

    static func mosaicCursorDotDiameter(for strokeWidth: CGFloat) -> CGFloat {
        max(6, strokeWidth * 0.52)
    }

    static func mosaicPreviewDotDiameter(for strokeWidth: CGFloat) -> CGFloat {
        switch strokeWidth {
        case ..<20:
            return 5
        case ..<35:
            return 8
        default:
            return 11
        }
    }

    static func mosaicPreviewProgress(for value: Int) -> CGFloat {
        let clamped = min(20, max(5, value))
        return CGFloat(clamped - 5) / 15
    }

    static func mosaicPreviewBackgroundColor(for value: Int) -> NSColor {
        let progress = mosaicPreviewProgress(for: value)
        let tone = 0.88 - progress * 0.32
        return NSColor(
            srgbRed: tone,
            green: tone,
            blue: tone,
            alpha: 1
        )
    }

    static func strokePatternOptions(
        canUsePremiumStrokePatterns: Bool,
        mode: OptionsToolbarMode = .shape
    ) -> [StrokePatternOption] {
        let patterns: [CaptureStrokePattern]
        switch mode {
        case .brush:
            patterns = [.solid, .dashLong, .dashNarrow, .dashLongShort]
        case .marker, .text, .numberSequence, .magnifier, .eraser:
            patterns = [.solid]
        case .shape, .arrowLine, .mosaic:
            patterns = CaptureStrokePattern.allCases
        }

        return patterns.map { pattern in
            StrokePatternOption(
                pattern: pattern,
                requiresPremiumAccess: pattern.requiresPremiumAccess,
                isEnabled: true
            )
        }
    }

    static func arrowLineActivationState(
        currentStyle: CaptureAnnotationStyle,
        paletteColors: [NSColor]
    ) -> ArrowLineActivationState {
        var style = styleForPrimaryShapeToolActivation(currentStyle: currentStyle, paletteColors: paletteColors)
        style.strokeWidth = strokeWidthValues(for: .arrowLine)[1]
        return ArrowLineActivationState(
            style: style,
            startArrowType: .none,
            endArrowType: .normal
        )
    }

    static func brushActivationStyle(
        currentStyle: CaptureAnnotationStyle,
        paletteColors: [NSColor]
    ) -> CaptureAnnotationStyle {
        var style = currentStyle
        style.strokeWidth = strokeWidthValues(for: .brush)[0]
        if style.strokePattern.isSketch {
            style.strokePattern = .solid
        }
        style.fillEnabled = false
        applyDefaultPaletteColor(to: &style, paletteColors: paletteColors)

        return style
    }

    static func mosaicActivationStyle(
        currentStyle: CaptureAnnotationStyle,
        paletteColors: [NSColor],
        strokeWidth: CGFloat
    ) -> CaptureAnnotationStyle {
        var style = currentStyle
        style.strokeWidth = strokeWidth
        style.fillEnabled = false
        applyDefaultPaletteColor(to: &style, paletteColors: paletteColors)
        return style
    }

    static func markerActivationStyle(currentStyle: CaptureAnnotationStyle) -> CaptureAnnotationStyle {
        var style = currentStyle
        style.strokeColor = defaultMarkerColor
        style.fillColor = defaultMarkerColor
        style.strokeWidth = strokeWidthValues(for: .marker)[1]
        style.strokePattern = .solid
        style.fillEnabled = false
        return style
    }

    static func snappedMarkerEndPoint(start: NSPoint, rawEnd: NSPoint, isShiftPressed: Bool) -> NSPoint {
        guard isShiftPressed else {
            return rawEnd
        }

        let dx = rawEnd.x - start.x
        let dy = rawEnd.y - start.y
        guard hypot(dx, dy) >= 0.001 else {
            return rawEnd
        }

        let directions = [
            NSPoint(x: 1, y: 0),
            NSPoint(x: sqrt(0.5), y: sqrt(0.5)),
            NSPoint(x: 0, y: 1),
            NSPoint(x: -sqrt(0.5), y: sqrt(0.5)),
            NSPoint(x: -1, y: 0),
            NSPoint(x: -sqrt(0.5), y: -sqrt(0.5)),
            NSPoint(x: 0, y: -1),
            NSPoint(x: sqrt(0.5), y: -sqrt(0.5)),
        ]
        let best = directions.max { lhs, rhs in
            (dx * lhs.x + dy * lhs.y) < (dx * rhs.x + dy * rhs.y)
        } ?? directions[0]
        let projectedLength = dx * best.x + dy * best.y

        return NSPoint(
            x: start.x + best.x * projectedLength,
            y: start.y + best.y * projectedLength
        )
    }

    static func annotationKindSupportsPostDrawEditing(_ kind: CaptureAnnotationKind) -> Bool {
        switch kind {
        case .rectangle, .ellipse, .arrowLine, .marker, .text, .numberSequence, .magnifier, .mosaicStroke, .mosaicRectangle:
            return true
        case .brush:
            return false
        }
    }

    static func annotationKindSupportsGeometryEditing(_ kind: CaptureAnnotationKind) -> Bool {
        switch kind {
        case .rectangle, .ellipse, .text, .numberSequence, .magnifier, .mosaicRectangle:
            return true
        case .arrowLine, .brush, .marker, .mosaicStroke:
            return false
        }
    }

    static func updatedSelectedAnnotationStyle(
        kind: CaptureAnnotationKind,
        existingStyle: CaptureAnnotationStyle,
        currentStyle: CaptureAnnotationStyle
    ) -> CaptureAnnotationStyle {
        annotationKindSupportsPostDrawEditing(kind) ? currentStyle : existingStyle
    }

    static func arrowTypesAfterSelection(
        currentStart: CaptureArrowType,
        currentEnd: CaptureArrowType,
        selectedType: CaptureArrowType,
        endpoint: ArrowTypeEndpoint
    ) -> ArrowTypePair {
        var next = ArrowTypePair(start: currentStart, end: currentEnd)

        switch endpoint {
        case .start:
            next.start = selectedType
            if requiresSingleEndedArrowSelection(selectedType)
                || (selectedType != .none && requiresSingleEndedArrowSelection(next.end)) {
                next.end = .none
            }
        case .end:
            next.end = selectedType
            if requiresSingleEndedArrowSelection(selectedType)
                || (selectedType != .none && requiresSingleEndedArrowSelection(next.start)) {
                next.start = .none
            }
        }

        return next
    }

    static func optionsToolbarLayout(
        in optionsRect: NSRect,
        paletteCount: Int,
        mode: OptionsToolbarMode
    ) -> OptionsToolbarLayout {
        OptionsToolbarLayout(
            strokeWidths: strokeWidthValues(for: mode).isEmpty ? [] : strokeWidthRects(in: optionsRect),
            textSizes: mode == .text ? [textSizeFieldRect(in: optionsRect)] : [],
            textBold: mode == .text ? textBoldRect(in: optionsRect) : .zero,
            textItalic: mode == .text ? textItalicRect(in: optionsRect) : .zero,
            textOutline: mode == .text ? textOutlineRect(in: optionsRect) : .zero,
            textFont: mode == .text ? textFontFieldRect(in: optionsRect) : .zero,
            textSize: mode == .text ? textSizeFieldRect(in: optionsRect) : .zero,
            numberMarkType: mode == .numberSequence ? numberMarkTypeFieldRect(in: optionsRect) : .zero,
            numberSize: mode == .numberSequence ? numberSizeFieldRect(in: optionsRect) : .zero,
            magnifierZoom: mode == .magnifier ? magnifierZoomFieldRect(in: optionsRect) : .zero,
            magnifierZooms: [],
            fillToggle: mode == .shape ? fillToggleRect(in: optionsRect) : nil,
            rectangleMode: rectangleModeRect(in: optionsRect, mode: mode),
            ellipseMode: ellipseModeRect(in: optionsRect, mode: mode),
            eraserPointMode: mode == .eraser ? eraserPointModeRect(in: optionsRect) : nil,
            eraserRectangleMode: mode == .eraser ? eraserRectangleModeRect(in: optionsRect) : nil,
            eraserClearAllSeparator: mode == .eraser ? eraserClearAllSeparatorRect(in: optionsRect) : nil,
            eraserClearAll: mode == .eraser ? eraserClearAllRect(in: optionsRect) : nil,
            strokeStyle: strokeStyleRect(in: optionsRect, mode: mode),
            startArrowType: mode == .arrowLine ? startArrowTypeFieldRect(in: optionsRect, mode: mode) : nil,
            endArrowType: mode == .arrowLine ? endArrowTypeFieldRect(in: optionsRect, mode: mode) : nil,
            colorSwatches: mode == .mosaic || mode == .eraser ? [] : colorSwatchRects(in: optionsRect, paletteCount: paletteCount, mode: mode)
        )
    }

    private static func rectangleModeRect(in optionsRect: NSRect, mode: OptionsToolbarMode) -> NSRect? {
        switch mode {
        case .shape:
            return rectangleModeButtonRect(in: optionsRect)
        case .magnifier:
            return magnifierRectangleModeButtonRect(in: optionsRect)
        case .mosaic:
            return mosaicRectangleButtonRect(in: optionsRect, mode: mode)
        case .arrowLine, .brush, .marker, .text, .numberSequence, .eraser:
            return nil
        }
    }

    private static func ellipseModeRect(in optionsRect: NSRect, mode: OptionsToolbarMode) -> NSRect? {
        switch mode {
        case .shape:
            return ellipseModeButtonRect(in: optionsRect)
        case .magnifier:
            return magnifierEllipseModeButtonRect(in: optionsRect)
        case .arrowLine, .brush, .marker, .mosaic, .text, .numberSequence, .eraser:
            return nil
        }
    }

    static func eraserPointModeRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 8, y: optionControlY(in: optionsRect), width: 20, height: 20)
    }

    static func eraserRectangleModeRect(in optionsRect: NSRect) -> NSRect {
        let point = eraserPointModeRect(in: optionsRect)
        return NSRect(x: point.maxX + 4, y: optionControlY(in: optionsRect), width: 20, height: 20)
    }

    static func eraserClearAllSeparatorRect(in optionsRect: NSRect) -> NSRect {
        let rectangle = eraserRectangleModeRect(in: optionsRect)
        let clearAll = eraserClearAllRect(in: optionsRect)
        let x = rectangle.maxX + (clearAll.minX - rectangle.maxX) / 2
        return NSRect(x: floor(x) + 0.25, y: optionsRect.midY - 6, width: 1.5, height: 12)
    }

    static func eraserClearAllRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.maxX - 28, y: optionControlY(in: optionsRect), width: 20, height: 20)
    }

    static func measurementControlLayout(
        anchoredTo selectionRect: NSRect,
        textSize: NSSize,
        inside safeBounds: NSRect
    ) -> MeasurementControlLayout {
        let labelWidth = ceil(textSize.width) + 18
        let buttonSize: CGFloat = 20
        let buttonGap: CGFloat = 8
        let separatorWidth: CGFloat = 1
        let separatorGap: CGFloat = 8
        let textSeparatorGap: CGFloat = 8
        let trailingPadding: CGFloat = 7
        let panelWidth = labelWidth
            + textSeparatorGap + separatorWidth + separatorGap
            + buttonSize + buttonGap + buttonSize
            + separatorGap + separatorWidth + separatorGap
            + buttonSize + trailingPadding
        let panelHeight: CGFloat = 24
        var panel = NSRect(x: selectionRect.minX, y: selectionRect.maxY + 8, width: panelWidth, height: panelHeight)
        if panel.maxY > safeBounds.maxY - 8 {
            panel.origin.y = selectionRect.minY - 32
        }
        panel = clamp(rect: panel, inside: safeBounds.insetBy(dx: 8, dy: 8))

        let label = NSRect(x: panel.minX, y: panel.minY, width: labelWidth, height: panel.height)
        let separatorY = panel.midY - 7
        let labelSeparator = NSRect(x: label.maxX + textSeparatorGap, y: separatorY, width: separatorWidth, height: 14)
        let firstButtonX = labelSeparator.maxX + separatorGap
        let refreshSeparator = NSRect(
            x: firstButtonX + buttonSize + buttonGap + buttonSize + separatorGap,
            y: separatorY,
            width: separatorWidth,
            height: 14
        )
        let buttonY = panel.midY - buttonSize / 2
        return MeasurementControlLayout(
            panel: panel,
            label: label,
            labelSeparator: labelSeparator,
            cornerStyle: NSRect(x: firstButtonX, y: buttonY, width: buttonSize, height: buttonSize),
            aspectRatio: NSRect(x: firstButtonX + buttonSize + buttonGap, y: buttonY, width: buttonSize, height: buttonSize),
            refreshSeparator: refreshSeparator,
            refresh: NSRect(x: refreshSeparator.maxX + separatorGap, y: buttonY, width: buttonSize, height: buttonSize)
        )
    }

    static func measurementControl(at point: NSPoint, in layout: MeasurementControlLayout) -> MeasurementControl? {
        if layout.cornerStyle.contains(point) {
            return .cornerStyle
        }
        if layout.aspectRatio.contains(point) {
            return .aspectRatioLock
        }
        if layout.refresh.contains(point) {
            return .refresh
        }
        return nil
    }

    static func selectionHandlePoints(in rect: NSRect, cornerRadius: CGFloat) -> [NSPoint] {
        if cornerRadius > 0 {
            return [
                NSPoint(x: rect.midX, y: rect.maxY),
                NSPoint(x: rect.minX, y: rect.midY),
                NSPoint(x: rect.maxX, y: rect.midY),
                NSPoint(x: rect.midX, y: rect.minY),
            ]
        }

        return [
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.midX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.midY),
            NSPoint(x: rect.maxX, y: rect.midY),
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.midX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
        ]
    }

    static func resizedSelectionRect(
        from startRect: NSRect,
        handle: OverlayResizeHandle,
        point: NSPoint,
        lockAspectRatio: Bool
    ) -> NSRect {
        guard lockAspectRatio, startRect.width > 0, startRect.height > 0 else {
            return resizedRectWithoutAspectLock(from: startRect, handle: handle, point: point)
        }

        let ratio = startRect.width / startRect.height
        let anchor: NSPoint
        switch handle {
        case .topLeft:
            anchor = NSPoint(x: startRect.maxX, y: startRect.minY)
        case .top:
            anchor = NSPoint(x: startRect.midX, y: startRect.minY)
        case .topRight:
            anchor = NSPoint(x: startRect.minX, y: startRect.minY)
        case .left:
            anchor = NSPoint(x: startRect.maxX, y: startRect.midY)
        case .right:
            anchor = NSPoint(x: startRect.minX, y: startRect.midY)
        case .bottomLeft:
            anchor = NSPoint(x: startRect.maxX, y: startRect.maxY)
        case .bottom:
            anchor = NSPoint(x: startRect.midX, y: startRect.maxY)
        case .bottomRight:
            anchor = NSPoint(x: startRect.minX, y: startRect.maxY)
        }

        let rawWidth: CGFloat
        let rawHeight: CGFloat
        switch handle {
        case .top, .bottom:
            rawHeight = abs(point.y - anchor.y)
            rawWidth = rawHeight * ratio
        case .left, .right:
            rawWidth = abs(point.x - anchor.x)
            rawHeight = rawWidth / ratio
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let pointWidth = abs(point.x - anchor.x)
            let pointHeight = abs(point.y - anchor.y)
            if pointWidth / max(pointHeight, 0.001) > ratio {
                rawWidth = pointWidth
                rawHeight = pointWidth / ratio
            } else {
                rawHeight = pointHeight
                rawWidth = pointHeight * ratio
            }
        }

        let signedWidth: CGFloat
        let signedHeight: CGFloat
        switch handle {
        case .top, .bottom:
            signedWidth = rawWidth
        case .left, .right:
            signedWidth = signedMagnitude(rawWidth, delta: point.x - anchor.x, defaultSign: defaultHorizontalSign(for: handle))
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            signedWidth = signedMagnitude(rawWidth, delta: point.x - anchor.x, defaultSign: defaultHorizontalSign(for: handle))
        }
        switch handle {
        case .left, .right:
            signedHeight = rawHeight
        case .top, .bottom:
            signedHeight = signedMagnitude(rawHeight, delta: point.y - anchor.y, defaultSign: defaultVerticalSign(for: handle))
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            signedHeight = signedMagnitude(rawHeight, delta: point.y - anchor.y, defaultSign: defaultVerticalSign(for: handle))
        }

        let centerAdjustedAnchor: NSPoint
        switch handle {
        case .top, .bottom:
            centerAdjustedAnchor = NSPoint(x: anchor.x - signedWidth / 2, y: anchor.y)
            return NSRect(
                x: min(centerAdjustedAnchor.x, centerAdjustedAnchor.x + signedWidth),
                y: min(centerAdjustedAnchor.y, centerAdjustedAnchor.y + signedHeight),
                width: abs(signedWidth),
                height: abs(signedHeight)
            )
        case .left, .right:
            centerAdjustedAnchor = NSPoint(x: anchor.x, y: anchor.y - signedHeight / 2)
            return NSRect(
                x: min(centerAdjustedAnchor.x, centerAdjustedAnchor.x + signedWidth),
                y: min(centerAdjustedAnchor.y, centerAdjustedAnchor.y + signedHeight),
                width: abs(signedWidth),
                height: abs(signedHeight)
            )
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return NSRect(
                x: min(anchor.x, anchor.x + signedWidth),
                y: min(anchor.y, anchor.y + signedHeight),
                width: abs(signedWidth),
                height: abs(signedHeight)
            )
        }
    }

    static func wheelZoomedSelectionRect(
        from startRect: NSRect,
        anchor: NSPoint,
        deltaY: CGFloat,
        inside bounds: NSRect,
        minimumSize: CGFloat = 64
    ) -> NSRect {
        let normalizedStartRect = startRect.standardized
        guard normalizedStartRect.width > 0, normalizedStartRect.height > 0 else {
            return normalizedStartRect
        }

        let desiredScale = wheelZoomScale(for: deltaY)
        let minimumScale = max(
            minimumSize / max(normalizedStartRect.width, 1),
            minimumSize / max(normalizedStartRect.height, 1)
        )
        let scale = max(desiredScale, minimumScale)
        let zoomed = scaledSelectionRect(
            from: normalizedStartRect,
            anchor: anchor,
            scale: scale
        )
        let clipped = zoomed.standardized.intersection(bounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
            return clamp(rect: zoomed, inside: bounds)
        }
        return clamp(rect: clipped, inside: bounds)
    }

    private static func signedMagnitude(_ magnitude: CGFloat, delta: CGFloat, defaultSign: CGFloat) -> CGFloat {
        guard delta != 0 else {
            return magnitude * defaultSign
        }
        return magnitude * (delta < 0 ? -1 : 1)
    }

    private static func wheelZoomScale(for deltaY: CGFloat) -> CGFloat {
        guard deltaY != 0 else {
            return 1
        }

        let clampedDelta = max(-6, min(6, deltaY))
        return pow(1.02, clampedDelta)
    }

    private static func scaledSelectionRect(
        from startRect: NSRect,
        anchor: NSPoint,
        scale: CGFloat
    ) -> NSRect {
        let minX = anchor.x - (anchor.x - startRect.minX) * scale
        let maxX = anchor.x + (startRect.maxX - anchor.x) * scale
        let minY = anchor.y - (anchor.y - startRect.minY) * scale
        let maxY = anchor.y + (startRect.maxY - anchor.y) * scale
        return NSRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    private static func defaultHorizontalSign(for handle: OverlayResizeHandle) -> CGFloat {
        switch handle {
        case .topLeft, .left, .bottomLeft:
            return -1
        default:
            return 1
        }
    }

    private static func defaultVerticalSign(for handle: OverlayResizeHandle) -> CGFloat {
        switch handle {
        case .bottomLeft, .bottom, .bottomRight:
            return -1
        default:
            return 1
        }
    }

    static func colorSwatchRects(
        in optionsRect: NSRect,
        paletteCount: Int,
        mode: OptionsToolbarMode = .shape
    ) -> [NSRect] {
        return (0...paletteCount).map { index in
            let rows = colorSwatchRowCount(paletteCount: paletteCount)
            let columns = colorSwatchColumnCount(paletteCount: paletteCount)
            let startX = colorSwatchStartXOffset(mode: mode)
            if index == paletteCount {
                let customSize = customColorSwatchSize(paletteCount: paletteCount)
                return NSRect(
                    x: optionsRect.minX + startX + CGFloat(columns) * 16 + 2,
                    y: optionsRect.midY - customSize / 2,
                    width: customSize,
                    height: customSize
                )
            }

            let column = index % columns
            let row = rows == 1 ? 0 : index / columns
            let firstRowY = rows == 1 ? optionsRect.midY - 6 : optionsRect.minY + 23
            return NSRect(
                x: optionsRect.minX + startX + CGFloat(column) * 16,
                y: firstRowY - CGFloat(row) * 16,
                width: 12,
                height: 12
            )
        }
    }

    static func optionsToolbarWidth(paletteCount: Int, mode: OptionsToolbarMode = .shape) -> CGFloat {
        let clampedCount = min(
            AppSettings.maximumPaletteVisibleCount,
            max(AppSettings.minimumPaletteVisibleCount, paletteCount)
        )
        if mode == .mosaic {
            return 252
        }
        if mode == .eraser {
            return 100
        }
        let columns = colorSwatchColumnCount(paletteCount: clampedCount)
        let customSize = customColorSwatchSize(paletteCount: clampedCount)
        let paletteWidth = colorSwatchStartXOffset(mode: mode) + CGFloat(columns) * 16 + 2 + customSize + optionsToolbarHorizontalPadding
        if mode == .magnifier {
            return max(430, paletteWidth)
        }
        return paletteWidth
    }

    static func optionsToolbarHeight(
        paletteCount: Int,
        mode: OptionsToolbarMode = .shape
    ) -> CGFloat {
        _ = paletteCount
        if mode == .mosaic || mode == .eraser {
            return 28
        }
        return colorSwatchRowCount(paletteCount: paletteCount) == 1 ? 30 : 40
    }

    static func arrowTypeSampleRect(in rect: NSRect, pointsRight: Bool) -> NSRect {
        let sampleWidth = min(CGFloat(22), max(8, rect.width - 8))
        let sampleHeight = max(8, rect.height)
        return NSRect(
            x: rect.minX + min(6, max(0, (rect.width - sampleWidth) / 2)),
            y: rect.midY - sampleHeight / 2,
            width: sampleWidth,
            height: sampleHeight
        )
    }

    static func arrowTypeDisclosureRect(in field: NSRect) -> NSRect {
        NSRect(x: field.maxX - 10, y: field.midY - 2.5, width: 6, height: 4)
    }

    static func swatchHitTarget(
        at point: NSPoint,
        in optionsRect: NSRect,
        paletteCount: Int,
        mode: OptionsToolbarMode = .shape
    ) -> SwatchSelection? {
        let rects = colorSwatchRects(in: optionsRect, paletteCount: paletteCount, mode: mode)
        return swatchHitTarget(at: point, in: rects)
    }

    static func swatchHitTarget(
        at point: NSPoint,
        in rects: [NSRect]
    ) -> SwatchSelection? {
        guard let customRect = rects.last else {
            return nil
        }

        for index in 0..<max(0, rects.count - 1) where rects[index].insetBy(dx: -3, dy: -3).contains(point) {
            return .palette(index)
        }

        if customRect.insetBy(dx: -2, dy: -2).contains(point) {
            return .custom
        }

        return nil
    }

    private static func colorSwatchRowCount(paletteCount: Int) -> Int {
        paletteCount <= 10 ? 1 : 2
    }

    private static func colorSwatchColumnCount(paletteCount: Int) -> Int {
        let rows = colorSwatchRowCount(paletteCount: paletteCount)
        return max(1, Int(ceil(Double(max(0, paletteCount)) / Double(rows))))
    }

    private static func customColorSwatchSize(paletteCount: Int) -> CGFloat {
        colorSwatchRowCount(paletteCount: paletteCount) == 1 ? 20 : 32
    }

    private static func colorSwatchStartXOffset(mode: OptionsToolbarMode) -> CGFloat {
        switch mode {
        case .shape:
            return 329
        case .arrowLine:
            return 322
        case .brush:
            return 214
        case .marker:
            return 102
        case .magnifier:
            return 236
        case .text:
            return 350
        case .numberSequence:
            return 148
        case .mosaic, .eraser:
            return 0
        }
    }

    static func strokeWidthRects(in optionsRect: NSRect) -> [NSRect] {
        (0..<3).map { index in
            NSRect(
                x: optionsRect.minX + optionsToolbarHorizontalPadding + CGFloat(index) * 24,
                y: optionControlY(in: optionsRect),
                width: 20,
                height: 20
            )
        }
    }

    static func textSizeRects(in optionsRect: NSRect) -> [NSRect] {
        [textSizeFieldRect(in: optionsRect)]
    }

    static func textBoldRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + optionsToolbarHorizontalPadding, y: optionControlY(in: optionsRect), width: 22, height: 20)
    }

    static func textItalicRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 38, y: optionControlY(in: optionsRect), width: 22, height: 20)
    }

    static func textOutlineRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 66, y: optionControlY(in: optionsRect), width: 22, height: 20)
    }

    static func textFontFieldRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 108, y: optionControlY(in: optionsRect), width: 154, height: 20)
    }

    static func textSizeFieldRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 282, y: optionControlY(in: optionsRect), width: 48, height: 20)
    }

    static func numberMarkTypeFieldRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + optionsToolbarHorizontalPadding, y: optionControlY(in: optionsRect), width: 48, height: 20)
    }

    static func numberSizeFieldRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 78, y: optionControlY(in: optionsRect), width: 48, height: 20)
    }

    static func magnifierZoomRects(in optionsRect: NSRect) -> [NSRect] {
        []
    }

    static func magnifierZoomFieldRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 160, y: optionControlY(in: optionsRect), width: 58, height: 20)
    }

    static func installedTextFontFamilies() -> [String] {
        let families = NSFontManager.shared.availableFontFamilies
        let systemFamily = NSFont.systemFont(ofSize: 12).familyName
        let allFamilies = systemFamily.map { families + [$0] } ?? families
        return sortedTextFontFamilies(allFamilies)
    }

    static func sortedTextFontFamilies(
        _ families: [String],
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> [String] {
        let uniqueFamilies = Array(Set(families.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
        let preferChineseFonts = preferredLanguages.first.map(isChinesePreferredLanguage) ?? false
        return uniqueFamilies.sorted { lhs, rhs in
            let lhsPreferred = isPreferredTextFontFamily(lhs, preferChineseFonts: preferChineseFonts)
            let rhsPreferred = isPreferredTextFontFamily(rhs, preferChineseFonts: preferChineseFonts)
            if lhsPreferred != rhsPreferred {
                return lhsPreferred
            }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    static func textFontDisplayName(
        for family: String,
        language: AppLanguage = .zhHans
    ) -> String {
        let normalized = family.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == "System" || normalized == NSFont.systemFont(ofSize: 12).familyName {
            return language == .zhHans ? "系统" : "System"
        }
        if language == .zhHans,
           let displayName = localizedChineseTextFontDisplayNames[normalized] {
            return displayName
        }
        return normalized
    }

    private static func isPreferredTextFontFamily(_ family: String, preferChineseFonts: Bool) -> Bool {
        let isChineseFont = isChineseTextFontFamily(family)
        return preferChineseFonts ? isChineseFont : !isChineseFont
    }

    private static func isChinesePreferredLanguage(_ language: String) -> Bool {
        language.lowercased().hasPrefix("zh")
    }

    private static func isChineseTextFontFamily(_ family: String) -> Bool {
        localizedChineseTextFontDisplayNames[family] != nil || textContainsCJK(textFontDisplayName(for: family))
    }

    private static func textContainsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }

    private static let localizedChineseTextFontDisplayNames: [String: String] = [
        "PingFang SC": "苹方-简",
        "PingFang TC": "蘋方-繁",
        "PingFang HK": "蘋方-港",
        "Songti SC": "宋体-简",
        "Songti TC": "宋體-繁",
        "Heiti SC": "黑体-简",
        "Heiti TC": "黑體-繁",
        "Kaiti SC": "楷体-简",
        "Kaiti TC": "楷體-繁",
        "STSong": "华文宋体",
        "STHeiti": "华文黑体",
        "STKaiti": "华文楷体",
        "STFangsong": "华文仿宋",
        "STYuanti": "华文圆体",
        "Hiragino Sans GB": "冬青黑体简体中文",
        "Microsoft YaHei": "微软雅黑",
        "Microsoft JhengHei": "微软正黑体",
        "SimSun": "宋体",
        "SimHei": "黑体",
        "KaiTi": "楷体",
        "FangSong": "仿宋",
    ]

    static func fillToggleRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 90, y: optionControlY(in: optionsRect), width: 20, height: 20)
    }

    private static func mosaicTypeButtonRect(in optionsRect: NSRect, mode: OptionsToolbarMode) -> NSRect {
        guard mode == .mosaic else {
            return .zero
        }
        return NSRect(x: optionsRect.minX + 90, y: optionControlY(in: optionsRect), width: 20, height: 20)
    }

    private static func mosaicRectangleButtonRect(in optionsRect: NSRect, mode: OptionsToolbarMode) -> NSRect {
        guard mode == .mosaic else {
            return .zero
        }
        return NSRect(x: optionsRect.minX + 88, y: optionControlY(in: optionsRect), width: 20, height: 20)
    }

    static func mosaicRedactionTypeButtonRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 118, y: optionControlY(in: optionsRect), width: 20, height: 20)
    }

    static func mosaicRedactionValueRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 148, y: optionControlY(in: optionsRect), width: 94, height: 20)
    }

    static func rectangleModeButtonRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 130, y: optionControlY(in: optionsRect), width: 26, height: 20)
    }

    static func ellipseModeButtonRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 162, y: optionControlY(in: optionsRect), width: 22, height: 20)
    }

    private static func magnifierRectangleModeButtonRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 92, y: optionControlY(in: optionsRect), width: 26, height: 20)
    }

    private static func magnifierEllipseModeButtonRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 124, y: optionControlY(in: optionsRect), width: 22, height: 20)
    }

    static func strokeStyleFieldRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 204, y: optionControlY(in: optionsRect), width: 102, height: 20)
    }

    static func startArrowTypeFieldRect(in optionsRect: NSRect) -> NSRect {
        startArrowTypeFieldRect(in: optionsRect, mode: .shape)
    }

    static func endArrowTypeFieldRect(in optionsRect: NSRect) -> NSRect {
        endArrowTypeFieldRect(in: optionsRect, mode: .shape)
    }

    private static func compactStrokeStyleFieldRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 96, y: optionControlY(in: optionsRect), width: 94, height: 20)
    }

    private static func strokeStyleRect(in optionsRect: NSRect, mode: OptionsToolbarMode) -> NSRect {
        switch mode {
        case .shape:
            return strokeStyleFieldRect(in: optionsRect)
        case .arrowLine, .brush:
            return compactStrokeStyleFieldRect(in: optionsRect)
        case .marker, .mosaic, .text, .numberSequence, .magnifier, .eraser:
            return .zero
        }
    }

    private static func startArrowTypeFieldRect(in optionsRect: NSRect, mode: OptionsToolbarMode) -> NSRect {
        switch mode {
        case .shape:
            return NSRect(x: optionsRect.minX + 316, y: optionControlY(in: optionsRect), width: 42, height: 20)
        case .arrowLine:
            return NSRect(x: optionsRect.minX + 208, y: optionControlY(in: optionsRect), width: 42, height: 20)
        case .brush, .marker, .mosaic, .text, .numberSequence, .magnifier, .eraser:
            return .zero
        }
    }

    private static func endArrowTypeFieldRect(in optionsRect: NSRect, mode: OptionsToolbarMode) -> NSRect {
        switch mode {
        case .shape:
            return NSRect(x: optionsRect.minX + 364, y: optionControlY(in: optionsRect), width: 42, height: 20)
        case .arrowLine:
            return NSRect(x: optionsRect.minX + 256, y: optionControlY(in: optionsRect), width: 42, height: 20)
        case .brush, .marker, .mosaic, .text, .numberSequence, .magnifier, .eraser:
            return .zero
        }
    }

    private static func optionControlY(in optionsRect: NSRect) -> CGFloat {
        optionsRect.midY - 10
    }

    static func strokeStyleMenuItemRects(in menu: NSRect, itemCount: Int) -> [NSRect] {
        (0..<itemCount).map { index in
            NSRect(x: menu.minX + 4, y: menu.maxY - 28 - CGFloat(index) * 24, width: menu.width - 8, height: 20)
        }
    }

    static func strokeMenuHitTarget(at point: NSPoint, in menu: NSRect, itemCount: Int) -> StrokeMenuSelection {
        guard menu.contains(point) else {
            return .outside
        }

        for (index, rect) in strokeStyleMenuItemRects(in: menu, itemCount: itemCount).enumerated() where rect.contains(point) {
            return .item(index)
        }
        return .menuBackground
    }

    static func arrowTypeMenuItemRects(in menu: NSRect, itemCount: Int) -> [NSRect] {
        (0..<itemCount).map { index in
            NSRect(x: menu.minX + 4, y: menu.maxY - 28 - CGFloat(index) * 24, width: menu.width - 8, height: 20)
        }
    }

    static func arrowTypeMenuHitTarget(at point: NSPoint, in menu: NSRect, itemCount: Int) -> ArrowTypeMenuSelection {
        guard menu.contains(point) else {
            return .outside
        }

        for (index, rect) in arrowTypeMenuItemRects(in: menu, itemCount: itemCount).enumerated() where rect.contains(point) {
            return .item(index)
        }
        return .menuBackground
    }

    static func arrowLineHitTarget(
        at point: NSPoint,
        line: CaptureArrowLine,
        hitOutset: CGFloat = 7
    ) -> ArrowLineHitTarget {
        if distance(from: point, to: line.start) <= hitOutset {
            return .start
        }
        if distance(from: point, to: line.end) <= hitOutset {
            return .end
        }
        if distance(from: point, to: line.control) <= hitOutset {
            return .control
        }
        if distanceFromQuadraticCurve(point: point, line: line, sampleCount: 32) <= hitOutset {
            return .body
        }
        return .none
    }

    static func brushRotationHitTarget(
        at point: NSPoint,
        path: CaptureBrushPath,
        hitOutset: CGFloat = 12
    ) -> BrushRotationHitTarget {
        guard path.points.count >= 2 else {
            return .none
        }
        if let start = brushRotationHandlePoint(for: .start, path: path), distance(from: point, to: start) <= hitOutset {
            return .start
        }
        if let end = brushRotationHandlePoint(for: .end, path: path), distance(from: point, to: end) <= hitOutset {
            return .end
        }
        return .none
    }

    static func brushRotationHandlePoint(
        for handle: BrushRotationHitTarget,
        path: CaptureBrushPath,
        inset: CGFloat = rotationHandleInset
    ) -> NSPoint? {
        guard path.points.count >= 2 else {
            return nil
        }

        switch handle {
        case .start:
            return insetPoint(from: path.points[0], toward: path.points[1], inset: inset)
        case .end:
            return insetPoint(from: path.points[path.points.count - 1], toward: path.points[path.points.count - 2], inset: inset)
        case .none:
            return nil
        }
    }

    static func markerRotationHandlePoint(
        for handle: BrushRotationHitTarget,
        line: CaptureMarkerLine,
        inset: CGFloat = rotationHandleInset
    ) -> NSPoint? {
        switch handle {
        case .start:
            return insetPoint(from: line.start, toward: line.end, inset: inset)
        case .end:
            return insetPoint(from: line.end, toward: line.start, inset: inset)
        case .none:
            return nil
        }
    }

    static func markerRotationHitTarget(
        at point: NSPoint,
        line: CaptureMarkerLine,
        hitOutset: CGFloat = 12
    ) -> BrushRotationHitTarget {
        if let start = markerRotationHandlePoint(for: .start, line: line), distance(from: point, to: start) <= hitOutset {
            return .start
        }
        if let end = markerRotationHandlePoint(for: .end, line: line), distance(from: point, to: end) <= hitOutset {
            return .end
        }
        return .none
    }

    static func resizedMarkerLine(
        _ line: CaptureMarkerLine,
        dragging handle: BrushRotationHitTarget,
        to point: NSPoint
    ) -> CaptureMarkerLine {
        switch handle {
        case .start:
            return CaptureMarkerLine(start: point, end: line.end)
        case .end:
            return CaptureMarkerLine(start: line.start, end: point)
        case .none:
            return line
        }
    }

    static func brushRotationHandleAngle(
        for handle: BrushRotationHitTarget,
        path: CaptureBrushPath
    ) -> CGFloat? {
        guard path.points.count >= 2 else {
            return nil
        }

        let from: NSPoint
        let to: NSPoint
        switch handle {
        case .start:
            from = path.points[1]
            to = path.points[0]
        case .end:
            from = path.points[path.points.count - 2]
            to = path.points[path.points.count - 1]
        case .none:
            return nil
        }

        let dx = to.x - from.x
        let dy = to.y - from.y
        guard hypot(dx, dy) >= 0.001 else {
            return nil
        }
        return atan2(dy, dx)
    }

    static func rotatedBrushPath(
        _ path: CaptureBrushPath,
        dragging handle: BrushRotationHitTarget,
        to point: NSPoint
    ) -> CaptureBrushPath {
        guard path.points.count >= 2, let start = path.points.first, let end = path.points.last else {
            return path
        }

        let fixed: NSPoint
        let moving: NSPoint
        switch handle {
        case .start:
            fixed = end
            moving = start
        case .end:
            fixed = start
            moving = end
        case .none:
            return path
        }

        let source = NSPoint(x: moving.x - fixed.x, y: moving.y - fixed.y)
        let target = NSPoint(x: point.x - fixed.x, y: point.y - fixed.y)
        let sourceLengthSquared = source.x * source.x + source.y * source.y
        guard sourceLengthSquared >= 0.001 else {
            return path
        }

        let a = (target.x * source.x + target.y * source.y) / sourceLengthSquared
        let b = (target.y * source.x - target.x * source.y) / sourceLengthSquared
        return CaptureBrushPath(points: path.points.map { original in
            let x = original.x - fixed.x
            let y = original.y - fixed.y
            return NSPoint(
                x: fixed.x + a * x - b * y,
                y: fixed.y + b * x + a * y
            )
        })
    }

    static func overlayCursorStyle(
        isSelecting: Bool,
        isToolbarOrPanelPoint: Bool,
        resizeHandle: OverlayResizeHandle?,
        selectionResizeHandle: OverlayResizeHandle?,
        isAnnotationBorder: Bool,
        isInsideSelection: Bool,
        isShapeToolActive: Bool = false,
        currentShapeKind: CaptureAnnotationKind = .rectangle
    ) -> OverlayCursorStyle {
        if isToolbarOrPanelPoint {
            return .arrow
        }

        if let resizeHandle {
            return overlayCursorStyle(for: resizeHandle)
        }

        if isAnnotationBorder {
            return .move
        }

        if let selectionResizeHandle {
            return overlayCursorStyle(for: selectionResizeHandle)
        }

        if isShapeToolActive, currentShapeKind == .brush || currentShapeKind == .marker {
            return currentShapeKind == .brush ? .brush : .marker
        }

        if isShapeToolActive {
            return .crosshair
        }

        if isSelecting || isInsideSelection {
            return .crosshair
        }

        return .arrow
    }

    enum OverlayResizeHandle: Equatable {
        case topLeft
        case top
        case topRight
        case left
        case right
        case bottomLeft
        case bottom
        case bottomRight
    }

    enum AnnotatingMouseDownTarget: Equatable {
        case shapeResize(OverlayResizeHandle)
        case annotationMove
        case selectionResize(OverlayResizeHandle)
        case selectionMove
        case none
    }

    static func annotatingMouseDownTarget(
        shapeResizeHandle: OverlayResizeHandle?,
        isAnnotationBorder: Bool,
        selectionResizeHandle: OverlayResizeHandle?,
        selectionMoveEligible: Bool
    ) -> AnnotatingMouseDownTarget {
        if let shapeResizeHandle {
            return .shapeResize(shapeResizeHandle)
        }

        if isAnnotationBorder {
            return .annotationMove
        }

        if let selectionResizeHandle {
            return .selectionResize(selectionResizeHandle)
        }

        if selectionMoveEligible {
            return .selectionMove
        }

        return .none
    }

    static func overlayCursorStyle(for resizeHandle: OverlayResizeHandle) -> OverlayCursorStyle {
        switch resizeHandle {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft:
            return .resizeTopLeft
        case .topRight:
            return .resizeTopRight
        case .bottomLeft:
            return .resizeBottomLeft
        case .bottomRight:
            return .resizeBottomRight
        }
    }

    static func selectionResizeHandle(at point: NSPoint, in rect: NSRect, edgeOutset: CGFloat = 12) -> OverlayResizeHandle? {
        let rect = rect.standardized
        guard rect.width >= 8, rect.height >= 8 else {
            return nil
        }

        let hitRect = rect.insetBy(dx: -edgeOutset, dy: -edgeOutset)
        guard hitRect.contains(point) else {
            return nil
        }

        let left = abs(point.x - rect.minX) <= edgeOutset
        let right = abs(point.x - rect.maxX) <= edgeOutset
        let top = abs(point.y - rect.maxY) <= edgeOutset
        let bottom = abs(point.y - rect.minY) <= edgeOutset

        switch (left, right, top, bottom) {
        case (true, _, true, _):
            return .topLeft
        case (_, true, true, _):
            return .topRight
        case (true, _, _, true):
            return .bottomLeft
        case (_, true, _, true):
            return .bottomRight
        case (true, _, _, _):
            return .left
        case (_, true, _, _):
            return .right
        case (_, _, true, _):
            return .top
        case (_, _, _, true):
            return .bottom
        default:
            return nil
        }
    }

    static func toolbarRect(size: NSSize, anchoredTo anchor: NSRect, inside bounds: NSRect, allowsInsidePlacement: Bool = true) -> NSRect {
        let gap: CGFloat = 8
        let safeBounds = bounds.insetBy(dx: gap, dy: gap)
        let outsideCandidates = [
            NSRect(x: anchor.maxX - size.width, y: anchor.minY - gap - size.height, width: size.width, height: size.height),
            NSRect(x: anchor.maxX - size.width, y: anchor.maxY + gap, width: size.width, height: size.height),
            NSRect(x: anchor.maxX + gap, y: anchor.minY + gap, width: size.width, height: size.height),
            NSRect(x: anchor.maxX + gap, y: anchor.maxY - gap - size.height, width: size.width, height: size.height),
            NSRect(x: anchor.minX - gap - size.width, y: anchor.minY + gap, width: size.width, height: size.height),
            NSRect(x: anchor.minX - gap - size.width, y: anchor.maxY - gap - size.height, width: size.width, height: size.height),
        ]
        let insideCandidates = [
            NSRect(x: anchor.maxX - size.width - gap, y: anchor.minY + gap, width: size.width, height: size.height),
            NSRect(x: anchor.maxX - size.width - gap, y: anchor.maxY - gap - size.height, width: size.width, height: size.height),
        ]
        let candidates = allowsInsidePlacement ? outsideCandidates + insideCandidates : outsideCandidates

        for rect in candidates where safeBounds.contains(rect) {
            return rect
        }

        if !allowsInsidePlacement {
            for rect in outsideCandidates {
                let clamped = clamp(rect: rect, inside: safeBounds)
                if !clamped.intersects(anchor) {
                    return clamped
                }
            }
        }

        return clamp(rect: candidates[0], inside: safeBounds)
    }

    static func contextualToolbarRect(
        size: NSSize,
        pointer: NSPoint,
        inside bounds: NSRect,
        gap: CGFloat = 6,
        margin: CGFloat = 4
    ) -> NSRect {
        let safeBounds = bounds.insetBy(dx: margin, dy: margin)
        let x = pointer.x + gap + size.width <= safeBounds.maxX
            ? pointer.x + gap
            : pointer.x - gap - size.width
        let y = pointer.y - gap - size.height >= safeBounds.minY
            ? pointer.y - gap - size.height
            : pointer.y + gap
        return clamp(
            rect: NSRect(x: x, y: y, width: size.width, height: size.height),
            inside: safeBounds
        )
    }

    static func attachedToolbarRect(
        size: NSSize,
        attachedTo toolbar: NSRect,
        inside bounds: NSRect,
        gap: CGFloat = 4,
        margin: CGFloat = 4
    ) -> NSRect {
        let safeBounds = bounds.insetBy(dx: margin, dy: margin)
        let rightX = toolbar.maxX + gap
        let leftX = toolbar.minX - gap - size.width
        let x: CGFloat
        if rightX + size.width <= safeBounds.maxX {
            x = rightX
        } else if leftX >= safeBounds.minX {
            x = leftX
        } else {
            let rightSpace = safeBounds.maxX - toolbar.maxX
            let leftSpace = toolbar.minX - safeBounds.minX
            x = rightSpace >= leftSpace ? rightX : leftX
        }
        let y = toolbar.maxY - size.height
        return clamp(
            rect: NSRect(x: x, y: y, width: size.width, height: size.height),
            inside: safeBounds
        )
    }

    static func localScreenBounds(
        containing point: NSPoint,
        windowFrame: NSRect,
        screenFrames: [NSRect]
    ) -> NSRect? {
        let screenPoint = NSPoint(
            x: point.x + windowFrame.minX,
            y: point.y + windowFrame.minY
        )
        guard let screenFrame = screenFrames.first(where: { $0.contains(screenPoint) }) else {
            return nil
        }
        return NSRect(
            x: screenFrame.minX - windowFrame.minX,
            y: screenFrame.minY - windowFrame.minY,
            width: screenFrame.width,
            height: screenFrame.height
        )
    }

    static func isFullScreenSelection(_ selectionRect: NSRect, in screenBounds: NSRect, tolerance: CGFloat = 1) -> Bool {
        let selection = selectionRect.standardized
        let screen = screenBounds.standardized
        return abs(selection.minX - screen.minX) <= tolerance
            && abs(selection.minY - screen.minY) <= tolerance
            && abs(selection.width - screen.width) <= tolerance
            && abs(selection.height - screen.height) <= tolerance
    }

    static func draggedToolbarRect(baseRect: NSRect, offset: NSSize, inside bounds: NSRect) -> NSRect {
        let gap: CGFloat = 8
        let requested = baseRect.offsetBy(dx: offset.width, dy: offset.height)
        return clamp(rect: requested, inside: bounds.insetBy(dx: gap, dy: gap))
    }

    static func popoverRect(size: NSSize, anchoredTo anchor: NSRect, inside bounds: NSRect) -> NSRect {
        let gap: CGFloat = 8
        let safeBounds = bounds.insetBy(dx: gap, dy: gap)
        var rect = NSRect(
            x: anchor.midX - size.width / 2,
            y: anchor.minY - gap - size.height,
            width: size.width,
            height: size.height
        )

        if rect.minY < safeBounds.minY {
            rect.origin.y = anchor.maxY + gap
        }

        return clamp(rect: rect, inside: safeBounds)
    }

    static func tooltipRect(textSize: NSSize, anchoredTo anchor: NSRect, inside bounds: NSRect) -> NSRect {
        let padding = NSSize(width: 16, height: 10)
        let size = NSSize(width: textSize.width + padding.width, height: textSize.height + padding.height)
        let gap: CGFloat = 8
        let safeBounds = bounds.insetBy(dx: gap, dy: gap)
        var rect = NSRect(
            x: anchor.midX - size.width / 2,
            y: anchor.maxY + gap,
            width: size.width,
            height: size.height
        )

        if rect.maxY > safeBounds.maxY {
            rect.origin.y = anchor.minY - gap - size.height
        }

        return clamp(rect: rect, inside: safeBounds)
    }

    static func shouldShowColorSampler(
        isShapeToolActive: Bool,
        hasAnnotations: Bool,
        pointer: NSPoint,
        selectionRect: NSRect?
    ) -> Bool {
        guard !isShapeToolActive, !hasAnnotations, let selectionRect else {
            return false
        }

        let rect = selectionRect.standardized
        return pointer.x >= rect.minX
            && pointer.x <= rect.maxX
            && pointer.y >= rect.minY
            && pointer.y <= rect.maxY
    }

    static func shouldShowExplicitColorSampler(
        pointer: NSPoint,
        selectionRect: NSRect?
    ) -> Bool {
        guard let selectionRect else {
            return false
        }

        let rect = selectionRect.standardized
        return pointer.x >= rect.minX
            && pointer.x <= rect.maxX
            && pointer.y >= rect.minY
            && pointer.y <= rect.maxY
    }

    static func shouldStartSelectionMove(
        isShapeToolActive: Bool,
        pointer: NSPoint,
        selectionRect: NSRect?,
        screenBounds: NSRect,
        selectionResizeHandle: OverlayResizeHandle?
    ) -> Bool {
        guard
            !isShapeToolActive,
            selectionResizeHandle == nil,
            let selectionRect
        else {
            return false
        }

        let rect = selectionRect.standardized
        guard rect.contains(pointer) else {
            return false
        }

        return canMoveSelectionRect(rect, inside: screenBounds)
    }

    static func movedSelectionRect(
        startRect: NSRect,
        pointer: NSPoint,
        pointerOffset: NSPoint,
        inside bounds: NSRect
    ) -> NSRect {
        let rect = startRect.standardized
        let requested = NSRect(
            x: pointer.x - pointerOffset.x,
            y: pointer.y - pointerOffset.y,
            width: rect.width,
            height: rect.height
        )
        return clamp(rect: requested, inside: bounds.standardized)
    }

    private static func resizedRectWithoutAspectLock(
        from startRect: NSRect,
        handle: OverlayResizeHandle,
        point: NSPoint
    ) -> NSRect {
        var minX = startRect.minX
        var maxX = startRect.maxX
        var minY = startRect.minY
        var maxY = startRect.maxY

        switch handle {
        case .topLeft:
            minX = point.x
            maxY = point.y
        case .top:
            maxY = point.y
        case .topRight:
            maxX = point.x
            maxY = point.y
        case .left:
            minX = point.x
        case .right:
            maxX = point.x
        case .bottomLeft:
            minX = point.x
            minY = point.y
        case .bottom:
            minY = point.y
        case .bottomRight:
            maxX = point.x
            minY = point.y
        }

        return NSRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    private static func canMoveSelectionRect(_ rect: NSRect, inside bounds: NSRect) -> Bool {
        let rect = rect.standardized
        let bounds = bounds.standardized
        return abs(rect.width - bounds.width) > 0.5 || abs(rect.height - bounds.height) > 0.5
    }

    static func colorSamplerRect(size: NSSize, pointer: NSPoint, inside bounds: NSRect) -> NSRect {
        let gap: CGFloat = 14
        let safeBounds = bounds.insetBy(dx: 8, dy: 8)
        var rect = NSRect(
            x: pointer.x + gap,
            y: pointer.y - size.height - gap,
            width: size.width,
            height: size.height
        )

        if rect.maxX > safeBounds.maxX {
            rect.origin.x = pointer.x - gap - size.width
        }

        if rect.minY < safeBounds.minY {
            rect.origin.y = pointer.y + gap
        }

        return clamp(rect: rect, inside: safeBounds)
    }

    static func colorSamplerCopyHintRect(textSize: NSSize, infoRect: NSRect, swatchRect: NSRect) -> NSRect {
        let y = max(infoRect.minY + 16, swatchRect.minY - textSize.height - 7)
        return NSRect(
            x: infoRect.midX - textSize.width / 2,
            y: y,
            width: textSize.width,
            height: textSize.height
        )
    }

    static func colorSamplerSwitchHintRect(textSize: NSSize, infoRect: NSRect, copyHintRect: NSRect) -> NSRect {
        let y = max(infoRect.minY + 4, copyHintRect.minY - textSize.height - 6)
        return NSRect(
            x: infoRect.midX - textSize.width / 2,
            y: y,
            width: textSize.width,
            height: textSize.height
        )
    }

    static func sampleColor(atPixelX x: Int, y: Int, in cgImage: CGImage) -> NSColor? {
        let x = max(0, min(cgImage.width - 1, x))
        let y = max(0, min(cgImage.height - 1, y))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return sampleColor(atPixelX: x, y: y, in: bitmap)
    }

    static func sampleColor(atPixelX x: Int, y: Int, in bitmap: NSBitmapImageRep) -> NSColor? {
        let x = max(0, min(bitmap.pixelsWide - 1, x))
        let y = max(0, min(bitmap.pixelsHigh - 1, y))
        if let rawColor = rawSampleColor(atPixelX: x, y: y, in: bitmap) {
            return rawColor
        }
        guard let color = bitmap.colorAt(x: x, y: y) else {
            return nil
        }

        return color.usingColorSpace(.sRGB) ?? color
    }

    static func colorSamplerDebugDescription(atPixelX x: Int, y: Int, in bitmap: NSBitmapImageRep, color: NSColor) -> String {
        let x = max(0, min(bitmap.pixelsWide - 1, x))
        let y = max(0, min(bitmap.pixelsHigh - 1, y))
        var pixel = [Int](repeating: 0, count: max(bitmap.samplesPerPixel, 4))
        if bitmap.samplesPerPixel > 0 {
            bitmap.getPixel(&pixel, atX: x, y: y)
        }
        let colorSpaceName = (bitmap.colorSpace.cgColorSpace?.name as String?) ?? bitmap.colorSpace.localizedName ?? "unknown"
        return "pixel=(\(x),\(y)) size=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh) spp=\(bitmap.samplesPerPixel) bps=\(bitmap.bitsPerSample) format=\(bitmap.bitmapFormat.rawValue) alphaFirst=\(bitmap.bitmapFormat.contains(.alphaFirst)) colorSpace=\(colorSpaceName) raw=\(pixel) hex=\(colorSamplerHexString(for: color)) rgb=\(colorSamplerRgbString(for: color))"
    }

    private static func rawSampleColor(atPixelX x: Int, y: Int, in bitmap: NSBitmapImageRep) -> NSColor? {
        guard
            bitmap.samplesPerPixel >= 3,
            bitmap.bitsPerSample > 0,
            bitmap.colorSpace.colorSpaceModel == .rgb,
            !bitmap.bitmapFormat.contains(.floatingPointSamples)
        else {
            return nil
        }

        var pixel = [Int](repeating: 0, count: bitmap.samplesPerPixel)
        bitmap.getPixel(&pixel, atX: x, y: y)

        let maxSample = CGFloat((1 << min(bitmap.bitsPerSample, 16)) - 1)
        guard maxSample > 0 else {
            return nil
        }

        let usesAlphaFirstLayout = bitmap.bitmapFormat.contains(.alphaFirst) && bitmap.samplesPerPixel >= 4
        let redIndex = usesAlphaFirstLayout ? 1 : 0
        let greenIndex = usesAlphaFirstLayout ? 2 : 1
        let blueIndex = usesAlphaFirstLayout ? 3 : 2
        let alphaIndex = usesAlphaFirstLayout ? 0 : 3

        let red = min(1, max(0, CGFloat(pixel[redIndex]) / maxSample))
        let green = min(1, max(0, CGFloat(pixel[greenIndex]) / maxSample))
        let blue = min(1, max(0, CGFloat(pixel[blueIndex]) / maxSample))
        let alpha = bitmap.hasAlpha && bitmap.samplesPerPixel >= 4
            ? min(1, max(0, CGFloat(pixel[alphaIndex]) / maxSample))
            : 1

        let sourceColor = NSColor(
            colorSpace: colorSpaceForRawByteSample(from: bitmap),
            components: [red, green, blue, alpha],
            count: 4
        )
        return sourceColor.usingColorSpace(.sRGB) ?? sourceColor
    }

    private static func colorSpaceForRawByteSample(from bitmap: NSBitmapImageRep) -> NSColorSpace {
        if let colorSpaceName = bitmap.colorSpace.cgColorSpace?.name {
            if colorSpaceName == CGColorSpace.displayP3 as CFString {
                return bitmap.colorSpace
            }
            return .sRGB
        }

        if bitmap.colorSpace.cgColorSpace != nil {
            return bitmap.colorSpace
        }

        return .sRGB
    }

    static func colorSamplerHexString(for color: NSColor) -> String {
        let rgb = srgbColor(color)
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func colorSamplerRgbString(for color: NSColor) -> String {
        let rgb = srgbColor(color)
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return "\(red), \(green), \(blue)"
    }

    private static func srgbColor(_ color: NSColor) -> NSColor {
        let converted = color.usingColorSpace(.sRGB) ?? color
        return converted.withAlphaComponent(1)
    }

    private static func applyDefaultPaletteColor(to style: inout CaptureAnnotationStyle, paletteColors: [NSColor]) {
        guard let firstPaletteColor = paletteColors.first else {
            return
        }

        let color = srgbColor(firstPaletteColor)
        style.strokeColor = color
        style.fillColor = color
    }

    private static func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let left = srgbColor(lhs)
        let right = srgbColor(rhs)
        return abs(left.redComponent - right.redComponent) < 0.001
            && abs(left.greenComponent - right.greenComponent) < 0.001
            && abs(left.blueComponent - right.blueComponent) < 0.001
    }

    private static func requiresSingleEndedArrowSelection(_ type: CaptureArrowType) -> Bool {
        switch type {
        case .solidArrow, .hollowArrow:
            return true
        case .none, .bar, .dot, .diamond, .normal:
            return false
        }
    }

    private static func distanceFromQuadraticCurve(point: NSPoint, line: CaptureArrowLine, sampleCount: Int) -> CGFloat {
        guard sampleCount > 1 else {
            return distanceFromSegment(point: point, start: line.start, end: line.end)
        }

        var nearest = CGFloat.greatestFiniteMagnitude
        var previous = line.start
        for index in 1...sampleCount {
            let t = CGFloat(index) / CGFloat(sampleCount)
            let current = quadraticPoint(start: line.start, control: line.control, end: line.end, t: t)
            nearest = min(nearest, distanceFromSegment(point: point, start: previous, end: current))
            previous = current
        }
        return nearest
    }

    static func quadraticPoint(start: NSPoint, control: NSPoint, end: NSPoint, t: CGFloat) -> NSPoint {
        let u = 1 - t
        return NSPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }

    static func markerLineContains(point: NSPoint, line: CaptureMarkerLine, hitOutset: CGFloat) -> Bool {
        distanceFromSegment(point: point, start: line.start, end: line.end) <= hitOutset
    }

    static func distanceFromSegment(point: NSPoint, start: NSPoint, end: NSPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return distance(from: point, to: start)
        }

        let rawT = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let t = min(1, max(0, rawT))
        let projection = NSPoint(x: start.x + t * dx, y: start.y + t * dy)
        return distance(from: point, to: projection)
    }

    private static func distance(from lhs: NSPoint, to rhs: NSPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func insetPoint(from endpoint: NSPoint, toward neighbor: NSPoint, inset: CGFloat) -> NSPoint {
        let dx = neighbor.x - endpoint.x
        let dy = neighbor.y - endpoint.y
        let length = hypot(dx, dy)
        guard length >= 0.001 else {
            return endpoint
        }
        let distance = min(inset, length / 2)
        return NSPoint(
            x: endpoint.x + dx / length * distance,
            y: endpoint.y + dy / length * distance
        )
    }

    static func toggledColorSamplerCopyMode(from mode: ColorSamplerCopyMode) -> ColorSamplerCopyMode {
        switch mode {
        case .hex:
            return .rgb
        case .rgb:
            return .hex
        }
    }

    static func colorSamplerCopyHintText(for mode: ColorSamplerCopyMode, l10n: L10n = L10n(language: .zhHans)) -> String {
        switch mode {
        case .hex:
            return l10n.text(.colorSamplerCopyHex)
        case .rgb:
            return l10n.text(.colorSamplerCopyRgb)
        }
    }

    static func isColorSamplerCopyShortcut(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard charactersIgnoringModifiers?.lowercased() == "c" else {
            return false
        }

        return !modifierFlags.contains(.command)
            && !modifierFlags.contains(.control)
            && !modifierFlags.contains(.option)
    }

    static func localAnnotationRect(fromOverlayRect overlayRect: NSRect, selectionRect: NSRect) -> NSRect {
        NSRect(
            x: overlayRect.minX - selectionRect.minX,
            y: overlayRect.minY - selectionRect.minY,
            width: overlayRect.width,
            height: overlayRect.height
        )
    }

    static func localAnnotationRectsPreservingOverlayPositions(_ overlayRects: [NSRect], selectionRect: NSRect) -> [NSRect] {
        overlayRects.map { localAnnotationRect(fromOverlayRect: $0, selectionRect: selectionRect) }
    }

    static func shapeBorderContains(point: NSPoint, rect: NSRect, kind: CaptureAnnotationKind, cornerRadius: CGFloat, hitOutset: CGFloat = 6) -> Bool {
        guard kind != .arrowLine, kind != .brush, kind != .marker, kind != .numberSequence else {
            return false
        }

        let rect = rect.standardized
        let outer = shapePath(in: rect.insetBy(dx: -hitOutset, dy: -hitOutset), kind: kind, cornerRadius: cornerRadius + hitOutset)
        let inner = shapePath(in: rect.insetBy(dx: hitOutset, dy: hitOutset), kind: kind, cornerRadius: max(0, cornerRadius - hitOutset))

        let border = NSBezierPath()
        border.append(outer)
        if inner.bounds.width > 0, inner.bounds.height > 0 {
            border.append(inner)
            border.windingRule = .evenOdd
        }
        return border.contains(point)
    }

    private static func clamp(rect: NSRect, inside bounds: NSRect) -> NSRect {
        var rect = rect
        if rect.maxX > bounds.maxX {
            rect.origin.x = bounds.maxX - rect.width
        }
        if rect.minX < bounds.minX {
            rect.origin.x = bounds.minX
        }
        if rect.maxY > bounds.maxY {
            rect.origin.y = bounds.maxY - rect.height
        }
        if rect.minY < bounds.minY {
            rect.origin.y = bounds.minY
        }
        return rect
    }

    private static func shapePath(in rect: NSRect, kind: CaptureAnnotationKind, cornerRadius: CGFloat) -> NSBezierPath {
        switch kind {
        case .arrowLine, .brush, .marker, .text, .numberSequence, .magnifier, .mosaicStroke, .mosaicRectangle:
            NSBezierPath()
        case .rectangle where cornerRadius > 0:
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        case .rectangle:
            NSBezierPath(rect: rect)
        case .ellipse:
            NSBezierPath(ovalIn: rect)
        }
    }
}
