import AppKit

enum SelectionToolbarState {
    static let colorSamplerCopyHintText = L10n(language: .zhHans).text(.colorSamplerCopyHex)
    static let colorSamplerCopySuccessText = "复制成功"
    static let colorSamplerCopySuccessDuration: TimeInterval = 1.2
    static let colorSamplerCopySuccessTextColor = NSColor.systemGreen
    static let colorSamplerCoordinateTextColor = NSColor.white
    static let colorSamplerValueTextColor = NSColor.white
    static let colorSamplerCopyHintTextColor = NSColor.white
    static let colorSamplerSwitchHintTextColor = NSColor.white

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

    enum OverlayCursorStyle: Equatable {
        case arrow
        case crosshair
        case move
        case resizeLeftRight
        case resizeUpDown
        case resizeTopLeft
        case resizeTopRight
        case resizeBottomLeft
        case resizeBottomRight
    }

    static let defaultFillPreviewColor = NSColor.systemGray

    static func shouldShowOptionsToolbar(isPrimaryShapeToolActive: Bool) -> Bool {
        isPrimaryShapeToolActive
    }

    static func toggledPrimaryShapeTool(current: CaptureAnnotationKind?, defaultShape: CaptureAnnotationKind) -> CaptureAnnotationKind? {
        current == nil ? defaultShape : nil
    }

    static func tooltipTitle(for identifier: String) -> String? {
        [
            "rectangle": "形状标注",
            "polyline": "直线",
            "pen": "画笔",
            "marker": "标记",
            "mosaic": "马赛克",
            "text": "文字",
            "number": "序号",
            "magnifier": "放大镜",
            "eraser": "橡皮擦",
            "undo": "撤销",
            "redo": "重做",
            "cancel": "取消",
            "pin": "贴图",
            "save": "保存",
            "copy": "复制到剪切板",
            "scroll": "滚动截图",
            "strokeWidthThin": "细线",
            "strokeWidthMedium": "中线",
            "strokeWidthThick": "粗线",
            "fill": "填充",
            "shapeRectangle": "方形",
            "shapeEllipse": "圆形",
            "strokeStyle": "线条类型",
            "customColor": "自定义颜色",
        ][identifier]
    }

    static func fillPreviewStyle(currentShapeKind: CaptureAnnotationKind, currentStyle: CaptureAnnotationStyle) -> FillPreviewStyle {
        FillPreviewStyle(
            shape: currentShapeKind == .ellipse ? .ellipse : .rectangle,
            color: currentStyle.fillEnabled ? currentStyle.fillColor : defaultFillPreviewColor,
            showsStrokeOutline: false
        )
    }

    static func colorSwatchRects(in optionsRect: NSRect, paletteCount: Int) -> [NSRect] {
        (0...paletteCount).map { index in
            let rows = colorSwatchRowCount(paletteCount: paletteCount)
            let columns = colorSwatchColumnCount(paletteCount: paletteCount)
            if index == paletteCount {
                let customSize = customColorSwatchSize(paletteCount: paletteCount)
                return NSRect(
                    x: optionsRect.minX + 325 + CGFloat(columns) * 16 + 2,
                    y: optionsRect.midY - customSize / 2,
                    width: customSize,
                    height: customSize
                )
            }

            let column = index % columns
            let row = rows == 1 ? 0 : index / columns
            let firstRowY = rows == 1 ? optionsRect.midY - 6 : optionsRect.minY + 23
            return NSRect(
                x: optionsRect.minX + 325 + CGFloat(column) * 16,
                y: firstRowY - CGFloat(row) * 16,
                width: 12,
                height: 12
            )
        }
    }

    static func optionsToolbarWidth(paletteCount: Int) -> CGFloat {
        let clampedCount = min(
            AppSettings.maximumPaletteVisibleCount,
            max(AppSettings.minimumPaletteVisibleCount, paletteCount)
        )
        let columns = colorSwatchColumnCount(paletteCount: clampedCount)
        let customSize = customColorSwatchSize(paletteCount: clampedCount)
        return 325 + CGFloat(columns) * 16 + customSize + 13
    }

    static func optionsToolbarHeight(paletteCount: Int) -> CGFloat {
        colorSwatchRowCount(paletteCount: paletteCount) == 1 ? 30 : 40
    }

    static func swatchHitTarget(at point: NSPoint, in optionsRect: NSRect, paletteCount: Int) -> SwatchSelection? {
        let rects = colorSwatchRects(in: optionsRect, paletteCount: paletteCount)
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

    static func overlayCursorStyle(
        isSelecting: Bool,
        isToolbarOrPanelPoint: Bool,
        resizeHandle: OverlayResizeHandle?,
        selectionResizeHandle: OverlayResizeHandle?,
        isAnnotationBorder: Bool,
        isInsideSelection: Bool
    ) -> OverlayCursorStyle {
        if isToolbarOrPanelPoint {
            return .arrow
        }

        if let resizeHandle {
            return overlayCursorStyle(for: resizeHandle)
        }

        if let selectionResizeHandle {
            return overlayCursorStyle(for: selectionResizeHandle)
        }

        if isAnnotationBorder {
            return .move
        }

        if isSelecting || isInsideSelection {
            return .crosshair
        }

        return .crosshair
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

    static func selectionResizeHandle(at point: NSPoint, in rect: NSRect, edgeOutset: CGFloat = 5) -> OverlayResizeHandle? {
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
        case .rectangle where cornerRadius > 0:
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        case .rectangle:
            NSBezierPath(rect: rect)
        case .ellipse:
            NSBezierPath(ovalIn: rect)
        }
    }
}
