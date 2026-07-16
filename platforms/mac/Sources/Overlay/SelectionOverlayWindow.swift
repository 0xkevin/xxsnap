import AppKit

enum TestMosaicRectangleRotationHandleGlyph {
    case refreshDot
}

enum TestToolbarButton {
    case rectangle
    case arrow
    case pen
    case marker
    case eyedropper
    case mosaic
    case text
    case number
    case magnifier
    case eraser
    case undo
    case redo
    case cancel
    case pin
    case save
    case copy
    case scroll
    case finishEditing
}

enum SelectionOverlayToolbarButton: Hashable {
    case scroll
    case cancel
    case pin
}

enum PinnedImageWindowCommand {
    case resetSize
    case toggleAlwaysOnTop
    case closeCurrent
    case closeAll

    init?(event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased()
        let relevantModifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        switch (key, relevantModifiers) {
        case ("r", [.command]):
            self = .resetSize
        case ("t", [.command]):
            self = .toggleAlwaysOnTop
        case ("w", [.command]):
            self = .closeCurrent
        case ("w", [.command, .shift]):
            self = .closeAll
        default:
            return nil
        }
    }
}

struct SelectionOverlayConfiguration {
    var windowFrame: NSRect?
    var windowLevel: NSWindow.Level
    var initialLockedSelectionRect: NSRect?
    var hiddenMainToolbarButtons: Set<SelectionOverlayToolbarButton>
    var showsFinishEditingButton: Bool
    var allowsSelectionGeometryEditing: Bool
    var showsSelectionBorder: Bool
    var showsMosaicRectangleSelectionOutline: Bool
    var showsSelectionMeasurementControl: Bool
    var allowsPassiveColorSampler: Bool
    var usesArrowCursorWhenIdle: Bool
    var outsideSelectionDimAlpha: CGFloat
    var usesWindowBoundsForLayout: Bool
    var completesBeforeOrderingOut: Bool
    var initialAnnotations: [CaptureAnnotation]
    var initialEraserMasks: [EraserMask]
    var suppressedAnnotationIDs: Set<AnnotationID>
    var annotationInteractionBegan: (() -> Void)?
    var annotationInteractionTargetBegan: ((AnnotationID?) -> Void)?
    var annotationInteractionEnded: (() -> Void)?
    var longImageScrollHandler: ((CGFloat) -> Void)?
    var pinnedImageScaleHandler: ((CGFloat, NSPoint) -> Void)?
    var pinnedImageDragBegan: ((NSPoint) -> Void)?
    var pinnedImageDragChanged: ((NSPoint) -> Void)?
    var pinnedImageDragEnded: (() -> Void)?
    var pinnedImageContextMenuHandler: ((NSPoint) -> Void)?
    var pinnedImageWindowCommandHandler: ((PinnedImageWindowCommand) -> Void)?
    var pinnedImageToolbarToggleHandler: (() -> Void)?

    static let `default` = SelectionOverlayConfiguration(
        windowFrame: nil,
        windowLevel: .screenSaver,
        initialLockedSelectionRect: nil,
        hiddenMainToolbarButtons: [],
        showsFinishEditingButton: false,
        allowsSelectionGeometryEditing: true,
        showsSelectionBorder: true,
        showsMosaicRectangleSelectionOutline: true,
        showsSelectionMeasurementControl: true,
        allowsPassiveColorSampler: true,
        usesArrowCursorWhenIdle: false,
        outsideSelectionDimAlpha: 0.34,
        usesWindowBoundsForLayout: false,
        completesBeforeOrderingOut: false,
        initialAnnotations: [],
        initialEraserMasks: [],
        suppressedAnnotationIDs: [],
        annotationInteractionBegan: nil,
        annotationInteractionTargetBegan: nil,
        annotationInteractionEnded: nil,
        longImageScrollHandler: nil,
        pinnedImageScaleHandler: nil,
        pinnedImageDragBegan: nil,
        pinnedImageDragChanged: nil,
        pinnedImageDragEnded: nil,
        pinnedImageContextMenuHandler: nil,
        pinnedImageWindowCommandHandler: nil,
        pinnedImageToolbarToggleHandler: nil
    )

    static func pinnedImageEditor(
        windowFrame: NSRect,
        selectionRect: NSRect,
        pinnedImageScaleHandler: ((CGFloat, NSPoint) -> Void)? = nil,
        pinnedImageDragBegan: ((NSPoint) -> Void)? = nil,
        pinnedImageDragChanged: ((NSPoint) -> Void)? = nil,
        pinnedImageDragEnded: (() -> Void)? = nil,
        pinnedImageContextMenuHandler: ((NSPoint) -> Void)? = nil,
        pinnedImageWindowCommandHandler: ((PinnedImageWindowCommand) -> Void)? = nil,
        pinnedImageToolbarToggleHandler: (() -> Void)? = nil
    ) -> SelectionOverlayConfiguration {
        SelectionOverlayConfiguration(
            windowFrame: windowFrame,
            windowLevel: .floating,
            initialLockedSelectionRect: selectionRect,
            hiddenMainToolbarButtons: [.scroll, .cancel, .pin],
            showsFinishEditingButton: true,
            allowsSelectionGeometryEditing: false,
            showsSelectionBorder: false,
            showsMosaicRectangleSelectionOutline: false,
            showsSelectionMeasurementControl: false,
            allowsPassiveColorSampler: false,
            usesArrowCursorWhenIdle: true,
            outsideSelectionDimAlpha: 0,
            usesWindowBoundsForLayout: true,
            completesBeforeOrderingOut: true,
            initialAnnotations: [],
            initialEraserMasks: [],
            suppressedAnnotationIDs: [],
            annotationInteractionBegan: nil,
            annotationInteractionTargetBegan: nil,
            annotationInteractionEnded: nil,
            longImageScrollHandler: nil,
            pinnedImageScaleHandler: pinnedImageScaleHandler,
            pinnedImageDragBegan: pinnedImageDragBegan,
            pinnedImageDragChanged: pinnedImageDragChanged,
            pinnedImageDragEnded: pinnedImageDragEnded,
            pinnedImageContextMenuHandler: pinnedImageContextMenuHandler,
            pinnedImageWindowCommandHandler: pinnedImageWindowCommandHandler,
            pinnedImageToolbarToggleHandler: pinnedImageToolbarToggleHandler
        )
    }

    static func longImageEditor(
        windowFrame: NSRect,
        selectionRect: NSRect,
        initialAnnotations: [CaptureAnnotation] = [],
        initialEraserMasks: [EraserMask] = [],
        suppressedAnnotationIDs: Set<AnnotationID> = [],
        interactionBegan: (() -> Void)? = nil,
        interactionTargetBegan: ((AnnotationID?) -> Void)? = nil,
        interactionEnded: (() -> Void)? = nil,
        scrollHandler: ((CGFloat) -> Void)? = nil
    ) -> SelectionOverlayConfiguration {
        SelectionOverlayConfiguration(
            windowFrame: windowFrame,
            windowLevel: .floating,
            initialLockedSelectionRect: selectionRect,
            hiddenMainToolbarButtons: [.scroll, .cancel, .pin],
            showsFinishEditingButton: true,
            allowsSelectionGeometryEditing: false,
            showsSelectionBorder: false,
            showsMosaicRectangleSelectionOutline: false,
            showsSelectionMeasurementControl: false,
            allowsPassiveColorSampler: false,
            usesArrowCursorWhenIdle: true,
            outsideSelectionDimAlpha: 0,
            usesWindowBoundsForLayout: true,
            completesBeforeOrderingOut: true,
            initialAnnotations: initialAnnotations,
            initialEraserMasks: initialEraserMasks,
            suppressedAnnotationIDs: suppressedAnnotationIDs,
            annotationInteractionBegan: interactionBegan,
            annotationInteractionTargetBegan: interactionTargetBegan,
            annotationInteractionEnded: interactionEnded,
            longImageScrollHandler: scrollHandler,
            pinnedImageScaleHandler: nil,
            pinnedImageDragBegan: nil,
            pinnedImageDragChanged: nil,
            pinnedImageDragEnded: nil,
            pinnedImageContextMenuHandler: nil,
            pinnedImageWindowCommandHandler: nil,
            pinnedImageToolbarToggleHandler: nil
        )
    }

#if DEBUG
    static func pinnedImageEditor(selectionRect: NSRect) -> SelectionOverlayConfiguration {
        pinnedImageEditor(
            windowFrame: NSRect(origin: .zero, size: NSSize(width: 640, height: 420)),
            selectionRect: selectionRect
        )
    }
#endif
}

private extension NSAlert {
    static func showTransient(message: String, in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "确定")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

extension NSCursor {
    static func xxsnapBrushRotationHandle(angle: CGFloat) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let hotSpot = brushRotationHandleCenter
        let image = NSImage(size: size)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.translateBy(x: hotSpot.x, y: hotSpot.y)
            context.rotate(by: angle)
            context.scaleBy(x: 0.68, y: 0.68)
            context.translateBy(x: -hotSpot.x, y: -hotSpot.y)
        }
        drawBrushRotationHandleIcon()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: hotSpot)
    }

    static let brushRotationHandleCenter = NSPoint(x: 11.34, y: 11.6)
    static let brushRotationHandleRadius: CGFloat = 5.6
    static let brushRotationHandleColor = NSColor.systemBlue

    static let xxsnapMosaicRectangleRotationHandle: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let hotSpot = NSPoint(x: size.width / 2, y: size.height / 2)
        guard let image = svgImage(named: "refresh (1)") else {
            return NSCursor.xxsnapBrushRotationHandle(angle: 0)
        }

        let cursorImage = NSImage(size: size)
        cursorImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let iconSize = NSSize(width: 18, height: 18)
        image.draw(in: NSRect(
            x: (size.width - iconSize.width) / 2,
            y: (size.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        ))
        cursorImage.unlockFocus()
        return NSCursor(image: cursorImage, hotSpot: hotSpot)
    }()

    static func svgImage(named name: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: "svg").flatMap(NSImage.init(contentsOf:))
    }

    static let xxsnapEyedropper: NSCursor = eyedropperCursor(tint: nil)
    static let xxsnapEyedropperLight: NSCursor = eyedropperCursor(tint: .white)
    static let xxsnapEraser: NSCursor = eraserCursor()

    private static func eyedropperCursor(tint: NSColor?) -> NSCursor {
        let size = SelectionToolbarState.eyedropperCursorSize
        let hotSpot = SelectionToolbarState.eyedropperCursorHotSpot
        let iconSize = SelectionToolbarState.eyedropperIconSize
        let inset: CGFloat = (size.width - iconSize) / 2

        guard let image = svgImage(named: "eyedropper") else {
            return NSCursor.arrow
        }

        let cursorImage = NSImage(size: size)
        cursorImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: inset, y: inset, width: iconSize, height: iconSize),
            from: NSRect.zero,
            operation: .copy,
            fraction: 1.0
        )
        if let tint {
            tint.setFill()
            NSRect(x: inset, y: inset, width: iconSize, height: iconSize).fill(using: .sourceAtop)
        }
        cursorImage.unlockFocus()
        return NSCursor(image: cursorImage, hotSpot: hotSpot)
    }

    private static func eraserCursor() -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let hotSpot = NSPoint(x: 7, y: 17)
        let iconSize: CGFloat = 18
        let inset = (size.width - iconSize) / 2

        if let image = svgImage(named: SelectionToolbarState.eraserCursorIconResourceName) {
            let cursorImage = NSImage(size: size)
            cursorImage.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(
                in: NSRect(x: inset, y: inset, width: iconSize, height: iconSize),
                from: .zero,
                operation: .copy,
                fraction: 1.0
            )
            cursorImage.unlockFocus()
            return NSCursor(image: cursorImage, hotSpot: hotSpot)
        }

        if let symbol = NSImage(
            systemSymbolName: "eraser",
            accessibilityDescription: "Eraser"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)) {
            let cursorImage = NSImage(size: size)
            cursorImage.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            symbol.draw(in: NSRect(x: inset, y: inset, width: iconSize, height: iconSize))
            cursorImage.unlockFocus()
            return NSCursor(image: cursorImage, hotSpot: hotSpot)
        }

        return NSCursor.arrow
    }

    static func drawBrushRotationHandleIcon() {
        let icon = brushRotationHandleStrokePath()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        icon.lineWidth = 3
        icon.lineCapStyle = .round
        icon.lineJoinStyle = .round
        icon.stroke()

        brushRotationHandleColor.setStroke()
        icon.lineWidth = 1.5
        icon.stroke()

        let topArrow = brushRotationHandleTopArrowPath()
        let bottomArrow = brushRotationHandleBottomArrowPath()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        [topArrow, bottomArrow].forEach { arrow in
            arrow.lineWidth = 2
            arrow.lineJoinStyle = .round
            arrow.stroke()
        }
        brushRotationHandleColor.setFill()
        topArrow.fill()
        bottomArrow.fill()
    }

    static func brushRotationHandleStrokePath() -> NSBezierPath {
        let path = NSBezierPath()
        path.appendArc(
            withCenter: brushRotationHandleCenter,
            radius: brushRotationHandleRadius,
            startAngle: 90,
            endAngle: -90,
            clockwise: true
        )
        return path
    }

    static func brushRotationHandleTopArrowPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 6.25879066, y: 5.92861018))
        path.line(to: NSPoint(x: 10.9136098, y: 8.82605023))
        path.line(to: NSPoint(x: 11.5144367, y: 4.36634093))
        path.close()
        return path
    }

    static func brushRotationHandleBottomArrowPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 7.46651105, y: 18.0662478))
        path.line(to: NSPoint(x: 12.9418948, y: 18.3537765))
        path.line(to: NSPoint(x: 11.3129929, y: 14.158937))
        path.close()
        return path
    }

    static let xxsnapMove: NSCursor = moveCursor(foreground: .black, outline: NSColor.white.withAlphaComponent(0.9))
    static let xxsnapMoveLight: NSCursor = moveCursor(foreground: .white, outline: NSColor.black.withAlphaComponent(0.75))
    static let xxsnapResizeLeftRightLight: NSCursor = resizeCursor(angle: 0, foreground: .white)
    static let xxsnapResizeUpDownLight: NSCursor = resizeCursor(angle: .pi / 2, foreground: .white)
    static let xxsnapResizeTopLeftLight: NSCursor = resizeCursor(angle: -.pi / 4, foreground: .white)
    static let xxsnapResizeTopRightLight: NSCursor = resizeCursor(angle: .pi / 4, foreground: .white)
    static let xxsnapResizeBottomLeftLight: NSCursor = resizeCursor(angle: .pi / 4, foreground: .white)
    static let xxsnapResizeBottomRightLight: NSCursor = resizeCursor(angle: -.pi / 4, foreground: .white)

    private static func moveCursor(foreground: NSColor, outline: NSColor) -> NSCursor {
        let size = NSSize(width: 28, height: 28)
        if let symbol = NSImage(
            systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
            accessibilityDescription: "Move"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .light)) {
            let image = NSImage(size: size)
            image.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            symbol.draw(in: NSRect(x: 3, y: 3, width: 22, height: 22))
            foreground.setFill()
            NSRect(x: 3, y: 3, width: 22, height: 22).fill(using: .sourceAtop)
            image.unlockFocus()
            return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
        }

        let image = NSImage(size: size)
        image.lockFocus()

        let outlinePath = NSBezierPath()
        drawMoveCursor(into: outlinePath, offset: .zero)
        outline.setStroke()
        outlinePath.lineWidth = 4
        outlinePath.lineCapStyle = .round
        outlinePath.lineJoinStyle = .round
        outlinePath.stroke()

        let path = NSBezierPath()
        drawMoveCursor(into: path, offset: .zero)
        foreground.setStroke()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }

    private static func resizeCursor(angle: CGFloat, foreground: NSColor) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let image = NSImage(size: size)
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: angle)
            context.translateBy(x: -center.x, y: -center.y)
        }

        let path = NSBezierPath()
        path.move(to: NSPoint(x: 5, y: 12))
        path.line(to: NSPoint(x: 19, y: 12))
        path.move(to: NSPoint(x: 5, y: 12))
        path.line(to: NSPoint(x: 9, y: 8))
        path.move(to: NSPoint(x: 5, y: 12))
        path.line(to: NSPoint(x: 9, y: 16))
        path.move(to: NSPoint(x: 19, y: 12))
        path.line(to: NSPoint(x: 15, y: 8))
        path.move(to: NSPoint(x: 19, y: 12))
        path.line(to: NSPoint(x: 15, y: 16))

        NSColor.black.withAlphaComponent(0.75).setStroke()
        path.lineWidth = 5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        foreground.setStroke()
        path.lineWidth = 2
        path.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: center)
    }

    static let xxsnapBrush: NSCursor = brushCursor(tint: nil)
    static let xxsnapBrushLight: NSCursor = brushCursor(tint: .white)

    private static func brushCursor(tint: NSColor?) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        // Hot spot at the pencil tip (lower-left area of the icon).
        // This ensures the drawn line follows the tip, not the cursor center.
        let tipHotSpot = NSPoint(x: 6, y: 18)
        let iconSize: CGFloat = 18
        let inset: CGFloat = (size.width - iconSize) / 2

        // Try loading from pencil-tool.svg resource
        if let svgUrl = Bundle.main.url(forResource: "pencil-tool", withExtension: "svg"),
           let image = NSImage(contentsOf: svgUrl) {
            let scaled = NSImage(size: size)
            scaled.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(
                in: NSRect(x: inset, y: inset, width: iconSize, height: iconSize),
                from: NSRect.zero,
                operation: .copy,
                fraction: 1.0
            )
            if let tint {
                tint.setFill()
                NSRect(x: inset, y: inset, width: iconSize, height: iconSize).fill(using: .sourceAtop)
            }
            scaled.unlockFocus()
            return NSCursor(image: scaled, hotSpot: tipHotSpot)
        }

        // Fallback: draw a simple pencil icon using SF Symbols
        if let symbol = NSImage(
            systemSymbolName: "pencil",
            accessibilityDescription: "Brush"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)) {
            let image = NSImage(size: size)
            image.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            symbol.draw(in: NSRect(x: inset, y: inset, width: iconSize, height: iconSize))
            if let tint {
                tint.setFill()
                NSRect(x: inset, y: inset, width: iconSize, height: iconSize).fill(using: .sourceAtop)
            }
            image.unlockFocus()
            return NSCursor(image: image, hotSpot: tipHotSpot)
        }

        // Ultimate fallback: standard arrow
        return NSCursor.arrow
    }

    static func xxsnapMarker(color: NSColor, strokeWidth: CGFloat) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let diameter = SelectionToolbarState.markerCursorDotDiameter(for: strokeWidth)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.white.withAlphaComponent(0.92).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - diameter / 2 - 1,
                y: center.y - diameter / 2 - 1,
                width: diameter + 2,
                height: diameter + 2
            )
        ).fill()
        color.withAlphaComponent(0.95).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )
        ).fill()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: center)
    }

    static func xxsnapMosaicDot(diameter: CGFloat) -> NSCursor {
        let side = max(24, ceil(diameter) + 4)
        let size = NSSize(width: side, height: side)
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - diameter / 2 - 1, y: center.y - diameter / 2 - 1, width: diameter + 2, height: diameter + 2)).fill()
        NSColor(calibratedWhite: 211 / 255, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)).fill()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: center)
    }

    static func drawMoveCursor(into path: NSBezierPath, offset: NSPoint) {
        let center = NSPoint(x: 14 + offset.x, y: 14 + offset.y)
        path.move(to: NSPoint(x: center.x, y: 4 + offset.y))
        path.line(to: NSPoint(x: center.x, y: 24 + offset.y))
        path.move(to: NSPoint(x: 4 + offset.x, y: center.y))
        path.line(to: NSPoint(x: 24 + offset.x, y: center.y))

        path.move(to: NSPoint(x: center.x, y: 24 + offset.y))
        path.line(to: NSPoint(x: 10 + offset.x, y: 20 + offset.y))
        path.move(to: NSPoint(x: center.x, y: 24 + offset.y))
        path.line(to: NSPoint(x: 18 + offset.x, y: 20 + offset.y))

        path.move(to: NSPoint(x: center.x, y: 4 + offset.y))
        path.line(to: NSPoint(x: 10 + offset.x, y: 8 + offset.y))
        path.move(to: NSPoint(x: center.x, y: 4 + offset.y))
        path.line(to: NSPoint(x: 18 + offset.x, y: 8 + offset.y))

        path.move(to: NSPoint(x: 4 + offset.x, y: center.y))
        path.line(to: NSPoint(x: 8 + offset.x, y: 10 + offset.y))
        path.move(to: NSPoint(x: 4 + offset.x, y: center.y))
        path.line(to: NSPoint(x: 8 + offset.x, y: 18 + offset.y))

        path.move(to: NSPoint(x: 24 + offset.x, y: center.y))
        path.line(to: NSPoint(x: 20 + offset.x, y: 10 + offset.y))
        path.move(to: NSPoint(x: 24 + offset.x, y: center.y))
        path.line(to: NSPoint(x: 20 + offset.x, y: 18 + offset.y))
    }
}

struct SelectionOverlayEditorSnapshot {
    var annotations: [CaptureAnnotation]
    var eraserMasks: [EraserMask]
    var revision: UInt64
}

final class SelectionOverlayWindow: NSWindow {
    static let defaultPaletteColors: [NSColor] = [
        paletteColor(0xFF001A),
        paletteColor(0x8A8A8A),
        paletteColor(0x000000),
        paletteColor(0xA3000D),
        paletteColor(0xFF7E06),
        paletteColor(0xFFF300),
        paletteColor(0x00BE4E),
        paletteColor(0x00B0EF),
        paletteColor(0x3C53D7),
        paletteColor(0xBB4AB0),
        paletteColor(0xFFFFFF),
        paletteColor(0xCACACA),
        paletteColor(0xCE815D),
        paletteColor(0xFFB2D0),
        paletteColor(0xFFCC00),
        paletteColor(0xF5E7B5),
        paletteColor(0xB3EB00),
        paletteColor(0x8EE1EE),
        paletteColor(0x6F9EC8),
        paletteColor(0xD0C6EC),
    ]

    private let selectionHandler: (CaptureSelectionResult?) -> Void
    private let configuration: SelectionOverlayConfiguration
    private var didCompleteSelection = false
    private var escapeKeyMonitor: Any?
    var onScrollCaptureRequested: ((ScrollCaptureSeed) -> Void)?
    var onScrollCaptureFinishRequested: (() -> Void)?
    var onScrollCaptureCancelRequested: (() -> Void)?
    private(set) var scrollCaptureOverlayState: ScrollCaptureOverlayState = .inactive
    private var scrollCaptureTerminalActionTriggered = false

    init(
        backgroundImage: NSImage?,
        settings: AppSettings = .default,
        featureGate: FeatureGate = FeatureGate(license: LicenseState()),
        configuration: SelectionOverlayConfiguration = .default,
        refreshHandler: (() async throws -> NSImage?)? = nil,
        selectionHandler: @escaping (CaptureSelectionResult?) -> Void
    ) {
        let frame = configuration.windowFrame ?? Self.desktopFrame()

        self.selectionHandler = selectionHandler
        self.configuration = configuration

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isOpaque = false
        ignoresMouseEvents = false
        level = configuration.windowLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let overlayView = SelectionOverlayView(
            frame: NSRect(origin: .zero, size: frame.size),
            backgroundImage: backgroundImage,
            settings: settings,
            featureGate: featureGate,
            configuration: configuration,
            refreshHandler: refreshHandler
        )
        overlayView.selectionDidFinish = { [weak self] result in
            self?.completeSelection(with: result)
        }
        overlayView.scrollCaptureDidRequest = { [weak self] seed in
            guard let self else { return }
            self.setScrollCaptureCapturing()
            self.onScrollCaptureRequested?(seed)
        }
        overlayView.scrollCaptureCancelDidRequest = { [weak self] in
            self?.requestScrollCaptureCancel()
        }
        overlayView.scrollCaptureFinishDidRequest = { [weak self] in
            self?.requestScrollCaptureFinish()
        }

        contentView = overlayView
        acceptsMouseMovedEvents = true
        installEscapeKeyMonitor()
    }

    deinit {
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
        }
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }


    func present() {
        NSApp.activate(ignoringOtherApps: true)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(contentView)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didCompleteSelection else {
                return
            }
            self.makeKeyAndOrderFront(nil)
            self.makeFirstResponder(self.contentView)
        }
    }

    func updatePinnedImageEditor(
        windowFrame: NSRect,
        backgroundImage: NSImage?,
        selectionRect: NSRect
    ) {
        setFrame(windowFrame, display: false)
        guard let overlayView = contentView as? SelectionOverlayView else {
            return
        }
        overlayView.frame = NSRect(origin: .zero, size: windowFrame.size)
        overlayView.updatePinnedImageEditor(backgroundImage: backgroundImage, selectionRect: selectionRect)
        makeFirstResponder(overlayView)
    }

    var editorSnapshot: SelectionOverlayEditorSnapshot? {
        (contentView as? SelectionOverlayView)?.editorSnapshot
    }

    func updateLongImageEditor(
        windowFrame: NSRect,
        backgroundImage: NSImage?,
        selectionRect: NSRect,
        annotations: [CaptureAnnotation],
        eraserMasks: [EraserMask],
        suppressedAnnotationIDs: Set<AnnotationID> = []
    ) {
        setFrame(windowFrame, display: false)
        guard let overlayView = contentView as? SelectionOverlayView else { return }
        overlayView.frame = NSRect(origin: .zero, size: windowFrame.size)
        overlayView.updateLongImageEditor(
            backgroundImage: backgroundImage,
            selectionRect: selectionRect,
            annotations: annotations,
            eraserMasks: eraserMasks,
            suppressedAnnotationIDs: suppressedAnnotationIDs
        )
        makeFirstResponder(overlayView)
    }

    func updateLongImageEditorPresentation(
        backgroundImage: NSImage?,
        suppressedAnnotationIDs: Set<AnnotationID>
    ) {
        (contentView as? SelectionOverlayView)?.updateLongImageEditorPresentation(
            backgroundImage: backgroundImage,
            suppressedAnnotationIDs: suppressedAnnotationIDs
        )
    }

    private func installEscapeKeyMonitor() {
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: makeKeyDownMonitorHandler()
        )
    }

    private func makeKeyDownMonitorHandler() -> (NSEvent) -> NSEvent? {
        { [weak self] event in
            guard let self else {
                return event
            }
            return self.handleMonitoredKeyDown(event)
        }
    }

    private func handleMonitoredKeyDown(_ event: NSEvent) -> NSEvent? {
        processMonitoredKeyDown(event, isOwned: ownsMonitoredKeyEvent(event))
    }

    private func processMonitoredKeyDown(_ event: NSEvent, isOwned: Bool) -> NSEvent? {
        guard !didCompleteSelection, isOwned else {
            return event
        }
        if event.keyCode == 53, scrollCaptureOverlayState != .inactive {
            requestScrollCaptureCancel()
            return nil
        }
        if Self.isScrollCaptureFinishKey(event.keyCode), scrollCaptureOverlayState != .inactive {
            requestScrollCaptureFinish()
            return nil
        }
        if let overlayView = contentView as? SelectionOverlayView,
           overlayView.handleKeyDown(event) {
            return nil
        }
        guard event.keyCode == 53 else {
            return event
        }
        performBaseEscape()
        return nil
    }

    private func ownsMonitoredKeyEvent(_ event: NSEvent) -> Bool {
        if let eventWindow = event.window {
            return eventWindow === self
        }
        return isKeyWindow
    }

    override func cancelOperation(_ sender: Any?) {
        if scrollCaptureOverlayState != .inactive {
            requestScrollCaptureCancel()
            return
        }
        completeSelection(with: nil)
    }

    var scrollCaptureToolbarScreenFrame: NSRect? {
        guard let overlayView = contentView as? SelectionOverlayView,
              let frame = overlayView.scrollCaptureToolbarFrame else { return nil }
        return convertToScreen(frame)
    }

    var scrollCaptureControlGeometry: ScrollCaptureControlGeometry? {
        guard let overlayView = contentView as? SelectionOverlayView,
              let geometry = overlayView.scrollCaptureControlGeometry else { return nil }
        return ScrollCaptureControlGeometry(
            toolbarFrame: convertToScreen(geometry.toolbarFrame),
            finishButtonFrame: convertToScreen(geometry.finishButtonFrame),
            cancelButtonFrame: convertToScreen(geometry.cancelButtonFrame)
        )
    }

    func setScrollCapturePaused(message: String) {
        guard scrollCaptureOverlayState != .inactive else { return }
        scrollCaptureOverlayState = .paused(message: message)
        (contentView as? SelectionOverlayView)?.scrollCaptureOverlayState = scrollCaptureOverlayState
    }

    func setScrollCaptureCapturing() {
        scrollCaptureTerminalActionTriggered = false
        scrollCaptureOverlayState = .capturing
        ignoresMouseEvents = true
        (contentView as? SelectionOverlayView)?.scrollCaptureOverlayState = .capturing
    }

    func resetScrollCaptureTerminalActionsForRetry() {
        guard scrollCaptureOverlayState != .inactive else { return }
        scrollCaptureTerminalActionTriggered = false
    }

    func endScrollCapturePassiveMode() {
        guard scrollCaptureOverlayState != .inactive else { return }
        scrollCaptureOverlayState = .inactive
        ignoresMouseEvents = false
        (contentView as? SelectionOverlayView)?.endScrollCapturePassiveMode()
    }

    func restoreAfterScrollCaptureCancellation() {
        endScrollCapturePassiveMode()
    }

    func finishScrollCaptureAndDismiss() {
        endScrollCapturePassiveMode()
        onScrollCaptureRequested = nil
        onScrollCaptureFinishRequested = nil
        onScrollCaptureCancelRequested = nil
        orderOut(nil)
    }

    private func requestScrollCaptureCancel() {
        guard scrollCaptureOverlayState != .inactive, !scrollCaptureTerminalActionTriggered else { return }
        scrollCaptureTerminalActionTriggered = true
        endScrollCapturePassiveMode()
        onScrollCaptureCancelRequested?()
    }

    private func requestScrollCaptureFinish() {
        guard scrollCaptureOverlayState != .inactive, !scrollCaptureTerminalActionTriggered else { return }
        scrollCaptureTerminalActionTriggered = true
        onScrollCaptureFinishRequested?()
    }

    private static func isScrollCaptureFinishKey(_ keyCode: UInt16) -> Bool {
        keyCode == 36 || keyCode == 76
    }

    private func performBaseEscape() {
        if let overlayView = contentView as? SelectionOverlayView,
           overlayView.finishPinnedImageEditingForEscape() {
            return
        }
        cancelOperation(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, scrollCaptureOverlayState != .inactive {
            requestScrollCaptureCancel()
            return
        }
        if Self.isScrollCaptureFinishKey(event.keyCode), scrollCaptureOverlayState != .inactive {
            requestScrollCaptureFinish()
            return
        }
        if let overlayView = contentView as? SelectionOverlayView,
           overlayView.handleKeyDown(event) {
            return
        }

        if event.keyCode == 53 {
            performBaseEscape()
            return
        }

        super.keyDown(with: event)
    }

#if DEBUG
    func test_beginScrollCapture() {
        (contentView as? SelectionOverlayView)?.beginScrollCapture()
    }

    func test_toolbarButtonIsEnabled(_ button: TestToolbarButton) -> Bool {
        (contentView as? SelectionOverlayView)?.test_toolbarButtonIsEnabled(button) ?? false
    }

    func test_tooltipText(for button: TestToolbarButton) -> String? {
        (contentView as? SelectionOverlayView)?.test_tooltipText(for: button)
    }
    func test_setLockedSelectionRect(_ rect: NSRect) {
        (contentView as? SelectionOverlayView)?.test_setLockedSelectionRect(rect)
    }

    func test_activateShapeTool(_ shape: CaptureAnnotationKind) {
        (contentView as? SelectionOverlayView)?.test_activateShapeTool(shape)
    }

    func test_activateTextTool() {
        (contentView as? SelectionOverlayView)?.test_activateTextTool()
    }

    func test_openTextFontDropdown() {
        (contentView as? SelectionOverlayView)?.test_openTextFontDropdown()
    }

    func test_toggleShapeTool(_ shape: CaptureAnnotationKind) {
        (contentView as? SelectionOverlayView)?.test_toggleShapeTool(shape)
    }

    func test_setCurrentStrokePattern(_ pattern: CaptureStrokePattern) {
        (contentView as? SelectionOverlayView)?.test_setCurrentStrokePattern(pattern)
    }

    func test_setCurrentStrokeWidth(_ width: CGFloat) {
        (contentView as? SelectionOverlayView)?.test_setCurrentStrokeWidth(width)
    }

    func test_setAnnotations(_ annotations: [CaptureAnnotation]) {
        (contentView as? SelectionOverlayView)?.test_setAnnotations(annotations)
    }

    func test_setEraserMasks(_ masks: [EraserMask]) {
        (contentView as? SelectionOverlayView)?.test_setEraserMasks(masks)
    }

    func test_addEraserMask(_ mask: EraserMask) {
        (contentView as? SelectionOverlayView)?.test_addEraserMask(mask)
    }

    @discardableResult
    func test_deleteAnnotations(at indexes: [Int]) -> Bool {
        (contentView as? SelectionOverlayView)?.test_deleteAnnotations(at: indexes) ?? false
    }

    func test_selectAnnotation(at index: Int) {
        (contentView as? SelectionOverlayView)?.test_selectAnnotation(at: index)
    }

    func test_setWindowSelectionCandidates(_ candidates: [WindowSelectionCandidate]) {
        (contentView as? SelectionOverlayView)?.test_setWindowSelectionCandidates(candidates)
    }

    func test_clearClipboard() {
        NSPasteboard.general.clearContents()
    }

    func test_setStrokeStyleMenuVisible(_ isVisible: Bool) {
        (contentView as? SelectionOverlayView)?.test_setStrokeStyleMenuVisible(isVisible)
    }

    func test_setArrowTypeMenusVisible(start: Bool, end: Bool) {
        (contentView as? SelectionOverlayView)?.test_setArrowTypeMenusVisible(start: start, end: end)
    }

    func test_beginAnnotatingMouseDown(at point: NSPoint) {
        (contentView as? SelectionOverlayView)?.test_beginAnnotatingMouseDown(at: point)
    }

    func test_dragMouse(to point: NSPoint) {
        (contentView as? SelectionOverlayView)?.test_dragMouse(to: point)
    }

    func test_mouseDown(at point: NSPoint, modifierFlags: NSEvent.ModifierFlags = []) {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return
        }
        overlayView.mouseDown(with: test_mouseEvent(type: .leftMouseDown, at: point, modifierFlags: modifierFlags))
    }

    func test_doubleClick(at point: NSPoint) {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return
        }
        overlayView.mouseDown(with: test_mouseEvent(type: .leftMouseDown, at: point, clickCount: 2))
    }

    func test_mouseMoved(to point: NSPoint, modifierFlags: NSEvent.ModifierFlags = []) {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return
        }
        overlayView.mouseMoved(with: test_mouseEvent(type: .mouseMoved, at: point, modifierFlags: modifierFlags))
    }

    func test_updateColorSampler(at point: NSPoint) {
        (contentView as? SelectionOverlayView)?.test_updateColorSampler(at: point)
    }

    func test_scrollWheel(at point: NSPoint, deltaY: CGFloat) {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return
        }
        if overlayView.test_handleTextDropdownScroll(at: point, deltaY: deltaY) {
            return
        }
        if let handler = configuration.longImageScrollHandler {
            handler(deltaY)
            return
        }
        _ = overlayView.test_handleScrollWheel(at: point, deltaY: deltaY)
    }

    func test_handleScrollWheel(at point: NSPoint, deltaY: CGFloat) -> Bool {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return false
        }
        return overlayView.test_handleScrollWheel(at: point, deltaY: deltaY)
    }

    func test_handleMagnify(at point: NSPoint, magnification: CGFloat) -> Bool {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return false
        }
        return overlayView.test_handleMagnify(at: point, magnification: magnification)
    }

    func test_completeSelectionWheelAnimation() {
        (contentView as? SelectionOverlayView)?.test_completeSelectionWheelAnimation()
    }

    func test_mouseDragged(to point: NSPoint, modifierFlags: NSEvent.ModifierFlags = []) {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return
        }
        overlayView.mouseDragged(with: test_mouseEvent(type: .leftMouseDragged, at: point, modifierFlags: modifierFlags))
    }

    func test_mouseUp(at point: NSPoint, modifierFlags: NSEvent.ModifierFlags = []) {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return
        }
        overlayView.mouseUp(with: test_mouseEvent(type: .leftMouseUp, at: point, modifierFlags: modifierFlags))
    }

    func test_rightMouseDown(at point: NSPoint) {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return
        }
        overlayView.rightMouseDown(with: test_mouseEvent(type: .rightMouseDown, at: point))
    }

    func test_drag(from start: NSPoint, to end: NSPoint, modifiers: NSEvent.ModifierFlags = []) {
        test_mouseDown(at: start, modifierFlags: modifiers)
        test_mouseDragged(to: end, modifierFlags: modifiers)
        test_mouseUp(at: end, modifierFlags: modifiers)
    }

    func test_keyDown(
        keyCode: UInt16,
        charactersIgnoringModifiers: String = "",
        modifierFlags: NSEvent.ModifierFlags = []
    ) {
        keyDown(with: test_keyEvent(
            keyCode: keyCode,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags
        ))
    }

    func test_flagsChanged(modifierFlags: NSEvent.ModifierFlags) {
        guard let event = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 56
        ) else {
            return
        }
        contentView?.flagsChanged(with: event)
    }

    func test_handleKeyDown(
        keyCode: UInt16,
        charactersIgnoringModifiers: String = "",
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> Bool {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return false
        }
        return overlayView.handleKeyDown(test_keyEvent(
            keyCode: keyCode,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags
        ))
    }

    func test_ownsMonitoredKeyEvent(_ event: NSEvent) -> Bool {
        ownsMonitoredKeyEvent(event)
    }

    func test_handleMonitoredKeyDown(
        _ event: NSEvent,
        treatingWindowlessEventAsKey: Bool? = nil
    ) -> NSEvent? {
        guard event.window == nil, let treatingWindowlessEventAsKey else {
            return handleMonitoredKeyDown(event)
        }
        return processMonitoredKeyDown(event, isOwned: treatingWindowlessEventAsKey)
    }

    func test_handleInstalledKeyMonitorEvent(_ event: NSEvent) -> NSEvent? {
        makeKeyDownMonitorHandler()(event)
    }

    func test_cursorStyle(at point: NSPoint) -> SelectionToolbarState.OverlayCursorStyle? {
        (contentView as? SelectionOverlayView)?.test_cursorStyle(at: point)
    }

    func test_mainToolbarDragPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_mainToolbarDragPoint()
    }

    func test_mainToolbarLeadingDragPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_mainToolbarLeadingDragPoint()
    }

    func test_mainToolbarTrailingDragPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_mainToolbarTrailingDragPoint()
    }

    func test_mainToolbarButtonRects() -> [NSRect] {
        (contentView as? SelectionOverlayView)?.test_mainToolbarButtonRects() ?? []
    }

    func test_mainToolbarRect() -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_mainToolbarRect()
    }

    func test_mainToolbarButtonRect(for button: TestToolbarButton) -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_mainToolbarButtonRect(for: button)
    }

    func test_mainToolbarButtonPoint(for button: TestToolbarButton) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_mainToolbarButtonPoint(for: button)
    }

    func test_toolbarButtonIsSelected(_ button: TestToolbarButton) -> Bool {
        (contentView as? SelectionOverlayView)?.test_toolbarButtonIsSelected(button) ?? false
    }

    var test_isPinnedImageDragInProgress: Bool {
        (contentView as? SelectionOverlayView)?.test_isPinnedImageDragInProgress ?? false
    }

    func test_symbolName(for button: TestToolbarButton) -> String? {
        (contentView as? SelectionOverlayView)?.test_symbolName(for: button)
    }

    func test_annotationRect(at index: Int) -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_annotationRect(at: index)
    }

    func test_annotationOverlayRect(at index: Int) -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_annotationOverlayRect(at: index)
    }

    func test_textEditorContentOrigin() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_textEditorContentOrigin()
    }

    func test_textEditorInsertionRect() -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_textEditorInsertionRect()
    }

    func test_editingTextCaretDrawRect() -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_editingTextCaretDrawRect()
    }

    func test_editingTextCaretColor() -> NSColor? {
        (contentView as? SelectionOverlayView)?.test_editingTextCaretColor()
    }

    func test_textEditorOverlayPointForInsertion(at characterIndex: Int) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_textEditorOverlayPointForInsertion(at: characterIndex)
    }

    func test_textEditorSelectedRange() -> NSRange? {
        (contentView as? SelectionOverlayView)?.test_textEditorSelectedRange()
    }

    func test_textEditorFrameCenterRotation() -> CGFloat? {
        (contentView as? SelectionOverlayView)?.test_textEditorFrameCenterRotation()
    }

    func test_annotationText(at index: Int) -> String? {
        (contentView as? SelectionOverlayView)?.test_annotationText(at: index)
    }

    func test_arrowLine(at index: Int) -> CaptureArrowLine? {
        (contentView as? SelectionOverlayView)?.test_arrowLine(at: index)
    }

    func test_brushPath(at index: Int) -> CaptureBrushPath? {
        (contentView as? SelectionOverlayView)?.test_brushPath(at: index)
    }

    func test_markerLine(at index: Int) -> CaptureMarkerLine? {
        (contentView as? SelectionOverlayView)?.test_markerLine(at: index)
    }

    func test_textAnnotation(at index: Int) -> CaptureAnnotation? {
        (contentView as? SelectionOverlayView)?.test_textAnnotation(at: index)
    }

    func test_markerToolbarButtonPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_markerToolbarButtonPoint()
    }

    func test_measurementControlPoint(_ control: SelectionToolbarState.MeasurementControl) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_measurementControlPoint(control)
    }

    func test_optionsStrokeWidthPoint(at index: Int) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_optionsStrokeWidthPoint(at: index)
    }

    func test_optionsPaletteColorPoint(at index: Int) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_optionsPaletteColorPoint(at: index)
    }

    var test_textSizeOptions: [CGFloat] {
        (contentView as? SelectionOverlayView)?.test_textSizeOptions ?? []
    }

    var test_textSizeOptionsCount: Int {
        (contentView as? SelectionOverlayView)?.test_textSizeOptionsCount ?? 0
    }

    func test_optionsTextSizePoint(at index: Int) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_optionsTextSizePoint(at: index)
    }

    func test_optionsTextSizePoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_optionsTextSizePoint()
    }

    func test_optionsTextFontPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_optionsTextFontPoint()
    }

    var test_textFontOptions: [String] {
        (contentView as? SelectionOverlayView)?.test_textFontOptions ?? []
    }

    var test_textDropdownRect: NSRect? {
        (contentView as? SelectionOverlayView)?.test_textDropdownRect
    }

    var test_isTextFontDropdownVisible: Bool {
        (contentView as? SelectionOverlayView)?.test_isTextFontDropdownVisible ?? false
    }

    var test_isTextSizeDropdownVisible: Bool {
        (contentView as? SelectionOverlayView)?.test_isTextSizeDropdownVisible ?? false
    }

    var test_isMagnifierZoomDropdownVisible: Bool {
        (contentView as? SelectionOverlayView)?.test_isMagnifierZoomDropdownVisible ?? false
    }

    var test_textDropdownScrollOffset: Int {
        (contentView as? SelectionOverlayView)?.test_textDropdownScrollOffset ?? 0
    }

    var test_backgroundImage: NSImage? {
        (contentView as? SelectionOverlayView)?.test_backgroundImage
    }

    var test_suppressedAnnotationIDs: Set<AnnotationID> {
        (contentView as? SelectionOverlayView)?.test_suppressedAnnotationIDs ?? []
    }

    func test_optionsTextBoldPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_optionsTextBoldPoint()
    }

    func test_optionsTextItalicPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_optionsTextItalicPoint()
    }

    func test_optionsTextOutlinePoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_optionsTextOutlinePoint()
    }

    func test_selectTextSize(_ size: CGFloat) {
        (contentView as? SelectionOverlayView)?.test_selectTextSize(size)
    }

    func test_selectTextFont(_ family: String) {
        (contentView as? SelectionOverlayView)?.test_selectTextFont(family)
    }

    func test_annotation(at index: Int) -> CaptureAnnotation? {
        (contentView as? SelectionOverlayView)?.test_annotation(at: index)
    }

    func test_activateNumberTool() {
        (contentView as? SelectionOverlayView)?.test_activateNumberTool()
    }

    func test_activateMagnifierTool() {
        (contentView as? SelectionOverlayView)?.test_activateMagnifierTool()
    }

    func test_activateEraserTool() {
        (contentView as? SelectionOverlayView)?.test_activateEraserTool()
    }

    func test_eraserPointOptionPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_eraserPointOptionPoint()
    }

    func test_eraserRectangleOptionPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_eraserRectangleOptionPoint()
    }

    func test_eraserClearAllOptionPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_eraserClearAllOptionPoint()
    }

    var test_eraserPointOptionRect: NSRect? {
        (contentView as? SelectionOverlayView)?.test_eraserPointOptionRect
    }

    var test_eraserRectangleOptionRect: NSRect? {
        (contentView as? SelectionOverlayView)?.test_eraserRectangleOptionRect
    }

    var test_eraserClearAllSeparatorRect: NSRect? {
        (contentView as? SelectionOverlayView)?.test_eraserClearAllSeparatorRect
    }

    var test_eraserClearAllOptionRect: NSRect? {
        (contentView as? SelectionOverlayView)?.test_eraserClearAllOptionRect
    }

    var test_numberMarkType: CaptureNumberMarkType {
        (contentView as? SelectionOverlayView)?.test_numberMarkType ?? .number
    }

    var test_isMagnifierToolActive: Bool {
        (contentView as? SelectionOverlayView)?.test_isMagnifierToolActive ?? false
    }

    var test_isEraserToolActive: Bool {
        (contentView as? SelectionOverlayView)?.test_isEraserToolActive ?? false
    }

    var test_isEraserRectangleModeActive: Bool {
        (contentView as? SelectionOverlayView)?.test_isEraserRectangleModeActive ?? false
    }

    var test_eraserRectanglePreviewRect: NSRect? {
        (contentView as? SelectionOverlayView)?.test_eraserRectanglePreviewRect
    }

    var test_eraserToolbarButtonIsSelected: Bool {
        (contentView as? SelectionOverlayView)?.test_eraserToolbarButtonIsSelected ?? false
    }

    var test_currentMagnifierShape: CaptureMagnifierShape {
        (contentView as? SelectionOverlayView)?.test_currentMagnifierShape ?? .rectangle
    }

    var test_currentMagnifierZoom: CGFloat {
        (contentView as? SelectionOverlayView)?.test_currentMagnifierZoom ?? 2
    }

    func test_setMagnifierShape(_ shape: CaptureMagnifierShape) {
        (contentView as? SelectionOverlayView)?.test_setMagnifierShape(shape)
    }

    func test_setMagnifierZoom(_ zoom: CGFloat) {
        (contentView as? SelectionOverlayView)?.test_setMagnifierZoom(zoom)
    }

    func test_numberMarkTypePoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_numberMarkTypePoint()
    }

    func test_numberSizePoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_numberSizePoint()
    }

    func test_numberMarkTypeMenuPoint(_ type: CaptureNumberMarkType) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_numberMarkTypeMenuPoint(type)
    }

    func test_magnifierZoomMenuPoint(_ zoom: CGFloat) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_magnifierZoomMenuPoint(zoom)
    }

    func test_numberMarkTypeIconInteriorPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_numberMarkTypeIconInteriorPoint()
    }

    func test_numberCursorImage(for type: CaptureNumberMarkType) -> NSImage? {
        (contentView as? SelectionOverlayView)?.test_numberCursorImage(for: type)
    }

    func test_numberCursorHotSpot(for type: CaptureNumberMarkType) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_numberCursorHotSpot(for: type)
    }

    func test_numberCursorText(for type: CaptureNumberMarkType) -> String? {
        (contentView as? SelectionOverlayView)?.test_numberCursorText(for: type)
    }

    func test_selectNumberSize(_ size: CGFloat) {
        (contentView as? SelectionOverlayView)?.test_selectNumberSize(size)
    }

    func test_numberSequenceIndex(at index: Int) -> Int? {
        (contentView as? SelectionOverlayView)?.test_numberSequenceIndex(at: index)
    }

    func test_setNumberMarkType(_ type: CaptureNumberMarkType) {
        (contentView as? SelectionOverlayView)?.test_setNumberMarkType(type)
    }

    func test_mosaicRectangleOptionPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_mosaicRectangleOptionPoint()
    }

    func test_mosaicRedactionTypePoint(_ type: CaptureMosaicRedactionType) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_mosaicRedactionTypePoint(type)
    }

    func test_mosaicValueIncrementPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_mosaicValueIncrementPoint()
    }

    func test_mosaicValueDecrementPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_mosaicValueDecrementPoint()
    }

    func test_mosaicValueInputPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_mosaicValueInputPoint()
    }

    func test_shapeResizeHandlePoint(_ handle: SelectionToolbarState.OverlayResizeHandle) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_shapeResizeHandlePoint(handle)
    }

    func test_numberDeleteHandlePoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_numberDeleteHandlePoint()
    }

    func test_numberResizeHandlePoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_numberResizeHandlePoint()
    }

    func test_numberIncrementHandlePoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_numberIncrementHandlePoint()
    }

    func test_numberDecrementHandlePoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_numberDecrementHandlePoint()
    }

    func test_numberIncrementHandleIsHitTarget() -> Bool {
        (contentView as? SelectionOverlayView)?.test_numberIncrementHandleIsHitTarget() ?? false
    }

    func test_numberDecrementHandleIsHitTarget() -> Bool {
        (contentView as? SelectionOverlayView)?.test_numberDecrementHandleIsHitTarget() ?? false
    }

    func test_numberResetHandlePoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_numberResetHandlePoint()
    }

    func test_numberDeleteHandleRect() -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_numberDeleteHandleRect()
    }

    func test_numberResizeHandleRect() -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_numberResizeHandleRect()
    }

    func test_numberIncrementHandleRect() -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_numberIncrementHandleRect()
    }

    func test_numberDecrementHandleRect() -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_numberDecrementHandleRect()
    }

    func test_numberResetHandleRect() -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_numberResetHandleRect()
    }

    func test_numberOutlineRect() -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_numberOutlineRect()
    }

    var test_numberControlsVisible: Bool {
        (contentView as? SelectionOverlayView)?.test_numberControlsVisible ?? false
    }

    func test_mosaicRectangleRotationHandlePoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_mosaicRectangleRotationHandlePoint()
    }

    func test_mosaicRectangleRotationHandleGlyph() -> TestMosaicRectangleRotationHandleGlyph? {
        (contentView as? SelectionOverlayView)?.test_mosaicRectangleRotationHandleGlyph()
    }

    var test_sampledColorHex: String? {
        (contentView as? SelectionOverlayView)?.test_sampledColorHex
    }

    var test_sampledPointerPoint: NSPoint? {
        (contentView as? SelectionOverlayView)?.test_sampledPointerPoint
    }

    var test_eyedropperMeasurementLine: (start: NSPoint, end: NSPoint)? {
        (contentView as? SelectionOverlayView)?.test_eyedropperMeasurementLine
    }

    var test_eyedropperMeasurementLabel: String? {
        (contentView as? SelectionOverlayView)?.test_eyedropperMeasurementLabel
    }

    var test_eyedropperMeasurementInvalidationRect: NSRect? {
        (contentView as? SelectionOverlayView)?.test_eyedropperMeasurementInvalidationRect
    }

    var test_visibleSelectionCompositeLookupCount: Int {
        (contentView as? SelectionOverlayView)?.test_visibleSelectionCompositeLookupCount ?? 0
    }

    func test_magnifierSampleColorHex(at point: NSPoint) -> String? {
        (contentView as? SelectionOverlayView)?.test_magnifierSampleColorHex(at: point)
    }

    func test_magnifierSampleColorHex(at point: NSPoint, columnOffset: Int, rowOffset: Int) -> String? {
        (contentView as? SelectionOverlayView)?.test_magnifierSampleColorHex(
            at: point,
            columnOffset: columnOffset,
            rowOffset: rowOffset
        )
    }

    var test_isColorSamplerVisible: Bool {
        (contentView as? SelectionOverlayView)?.test_isColorSamplerVisible ?? false
    }

    var test_mosaicStrokeDraftUsesLiveCompositePreviewPath: Bool {
        (contentView as? SelectionOverlayView)?.test_mosaicStrokeDraftUsesLiveCompositePreviewPath ?? false
    }

    var test_mosaicRectangleDraftUsesLivePreviewPath: Bool {
        (contentView as? SelectionOverlayView)?.test_mosaicRectangleDraftUsesLivePreviewPath ?? false
    }

    func test_annotationRotationAngle(at index: Int) -> CGFloat? {
        (contentView as? SelectionOverlayView)?.test_annotationRotationAngle(at: index)
    }

    func test_annotationStyle(at index: Int) -> CaptureAnnotationStyle? {
        (contentView as? SelectionOverlayView)?.test_annotationStyle(at: index)
    }

    var test_selectedAnnotationKind: CaptureAnnotationKind? {
        (contentView as? SelectionOverlayView)?.test_selectedAnnotationKind
    }

    var test_selectedAnnotationIndex: Int? {
        (contentView as? SelectionOverlayView)?.test_selectedAnnotationIndex
    }

    var test_selectedAnnotationShowsOutline: Bool {
        (contentView as? SelectionOverlayView)?.test_selectedAnnotationShowsOutline ?? false
    }

    var test_annotationCount: Int {
        (contentView as? SelectionOverlayView)?.test_annotationCount ?? 0
    }

    var test_eraserMaskCount: Int {
        (contentView as? SelectionOverlayView)?.test_eraserMaskCount ?? 0
    }

    func test_eraserMask(at index: Int) -> EraserMask? {
        (contentView as? SelectionOverlayView)?.test_eraserMask(at: index)
    }

    var test_damagedAnnotationIDs: Set<AnnotationID> {
        (contentView as? SelectionOverlayView)?.test_damagedAnnotationIDs ?? []
    }

    var test_damagedAnnotationCount: Int {
        (contentView as? SelectionOverlayView)?.test_damagedAnnotationCount ?? 0
    }

    var test_lockedSelectionRect: NSRect? {
        (contentView as? SelectionOverlayView)?.test_lockedSelectionRect
    }

    var test_currentSelectionRect: NSRect? {
        (contentView as? SelectionOverlayView)?.test_currentSelectionRect
    }

    var test_overlayBounds: NSRect {
        (contentView as? SelectionOverlayView)?.test_overlayBounds ?? .zero
    }

    var test_selectionCornerRadius: CGFloat {
        (contentView as? SelectionOverlayView)?.test_selectionCornerRadius ?? 0
    }

    var test_isSelectionAspectRatioLocked: Bool {
        (contentView as? SelectionOverlayView)?.test_isSelectionAspectRatioLocked ?? false
    }

    var test_currentStrokePattern: CaptureStrokePattern? {
        (contentView as? SelectionOverlayView)?.test_currentStrokePattern
    }

    var test_currentStyle: CaptureAnnotationStyle? {
        (contentView as? SelectionOverlayView)?.test_currentStyle
    }

    var test_optionsToolbarMode: SelectionToolbarState.OptionsToolbarMode? {
        (contentView as? SelectionOverlayView)?.test_optionsToolbarMode
    }

    var test_optionsToolbarRect: NSRect? {
        (contentView as? SelectionOverlayView)?.test_optionsToolbarRect
    }

    var test_currentShapeKind: CaptureAnnotationKind? {
        (contentView as? SelectionOverlayView)?.test_currentShapeKind
    }

    var test_mosaicRedactionType: CaptureMosaicRedactionType? {
        (contentView as? SelectionOverlayView)?.test_mosaicRedactionType
    }

    var test_hoveredTooltipText: String? {
        (contentView as? SelectionOverlayView)?.test_hoveredTooltipText
    }

    func test_mosaicRedactionValue(for type: CaptureMosaicRedactionType) -> Int? {
        (contentView as? SelectionOverlayView)?.test_mosaicRedactionValue(for: type)
    }

    func test_mosaicStroke(at index: Int) -> CaptureMosaicStroke? {
        (contentView as? SelectionOverlayView)?.test_mosaicStroke(at: index)
    }

    func test_mosaicRedaction(at index: Int) -> CaptureMosaicRedaction? {
        (contentView as? SelectionOverlayView)?.test_mosaicRedaction(at: index)
    }

    func test_mosaicPreviewComposite(for annotations: [CaptureAnnotation]) -> (size: NSSize, drawRect: NSRect)? {
        (contentView as? SelectionOverlayView)?.test_mosaicPreviewComposite(for: annotations)
    }

    var test_hasMosaicCompositeCache: Bool {
        (contentView as? SelectionOverlayView)?.test_hasMosaicCompositeCache ?? false
    }

    var test_mosaicCompositeRenderCount: Int {
        (contentView as? SelectionOverlayView)?.test_mosaicCompositeRenderCount ?? 0
    }

    var test_mosaicFullCompositeRenderCount: Int {
        (contentView as? SelectionOverlayView)?.test_mosaicFullCompositeRenderCount ?? 0
    }

    var test_mosaicCompositeDrawCount: Int {
        (contentView as? SelectionOverlayView)?.test_mosaicCompositeDrawCount ?? 0
    }

    var test_mosaicDraftRedactedBaseRenderCount: Int {
        (contentView as? SelectionOverlayView)?.test_mosaicDraftRedactedBaseRenderCount ?? 0
    }

    var test_mosaicDraftPreviewImageRenderCount: Int {
        (contentView as? SelectionOverlayView)?.test_mosaicDraftPreviewImageRenderCount ?? 0
    }

    var test_eraserMaskedCompositeRenderCount: Int {
        (contentView as? SelectionOverlayView)?.test_eraserMaskedCompositeRenderCount ?? 0
    }

    var test_eraserMaskedCompositeCacheHitCount: Int {
        (contentView as? SelectionOverlayView)?.test_eraserMaskedCompositeCacheHitCount ?? 0
    }

    var test_eraserMaskedCompositeDrawRect: NSRect? {
        (contentView as? SelectionOverlayView)?.test_eraserMaskedCompositeDrawRect
    }

    var test_eraserMaskedCompositePixelRect: CGRect? {
        (contentView as? SelectionOverlayView)?.test_eraserMaskedCompositePixelRect
    }

    var test_outsideMaskedAnnotationRenderCount: Int {
        (contentView as? SelectionOverlayView)?.test_outsideMaskedAnnotationRenderCount ?? 0
    }

    var test_outsideMaskedAnnotationCacheHitCount: Int {
        (contentView as? SelectionOverlayView)?.test_outsideMaskedAnnotationCacheHitCount ?? 0
    }

    func test_mosaicPreviewClipBounds(for annotations: [CaptureAnnotation]) -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_mosaicPreviewClipBounds(for: annotations)
    }

    func test_mosaicPreviewClipContains(_ point: NSPoint, for annotations: [CaptureAnnotation]) -> Bool {
        (contentView as? SelectionOverlayView)?.test_mosaicPreviewClipContains(point, for: annotations) ?? false
    }

    func test_mosaicDraftPreviewAnnotationCount(for draft: CaptureAnnotation) -> Int? {
        (contentView as? SelectionOverlayView)?.test_mosaicDraftPreviewAnnotationCount(for: draft)
    }

    func test_mosaicDraftPreviewDrawRect(for draft: CaptureAnnotation) -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_mosaicDraftPreviewDrawRect(for: draft)
    }

    func test_mosaicDraftPreview(for draft: CaptureAnnotation) -> (image: NSImage, drawRect: NSRect)? {
        (contentView as? SelectionOverlayView)?.test_mosaicDraftPreview(for: draft)
    }

    func test_renderedOverlayImage() -> NSImage? {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return nil
        }
        let image = NSImage(size: overlayView.bounds.size)
        image.lockFocus()
        overlayView.draw(overlayView.bounds)
        image.unlockFocus()
        return image
    }

    var test_showsStrokeStyleMenu: Bool {
        (contentView as? SelectionOverlayView)?.test_showsStrokeStyleMenu ?? false
    }

    var test_showsStartArrowTypeMenu: Bool {
        (contentView as? SelectionOverlayView)?.test_showsStartArrowTypeMenu ?? false
    }

    var test_showsEndArrowTypeMenu: Bool {
        (contentView as? SelectionOverlayView)?.test_showsEndArrowTypeMenu ?? false
    }

    var test_selectedBrushEndpointMarkers: [NSPoint] {
        (contentView as? SelectionOverlayView)?.test_selectedBrushEndpointMarkers ?? []
    }

    var test_markerToolbarButtonIsSelected: Bool {
        (contentView as? SelectionOverlayView)?.test_markerToolbarButtonIsSelected ?? false
    }

    var test_isEyedropperToolActive: Bool {
        (contentView as? SelectionOverlayView)?.test_isEyedropperToolActive ?? false
    }

    var test_eyedropperToolbarButtonIsSelected: Bool {
        (contentView as? SelectionOverlayView)?.test_eyedropperToolbarButtonIsSelected ?? false
    }

    var test_isTextToolActive: Bool {
        (contentView as? SelectionOverlayView)?.test_isTextToolActive ?? false
    }

    var test_isNumberToolActive: Bool {
        (contentView as? SelectionOverlayView)?.test_isNumberToolActive ?? false
    }

    var test_textToolbarButtonIsSelected: Bool {
        (contentView as? SelectionOverlayView)?.test_textToolbarButtonIsSelected ?? false
    }

    var test_numberToolbarIconUsesTemplateBlack: Bool {
        (contentView as? SelectionOverlayView)?.test_numberToolbarIconUsesTemplateBlack ?? false
    }

    var test_isEditingTextAnnotation: Bool {
        (contentView as? SelectionOverlayView)?.test_isEditingTextAnnotation ?? false
    }

    var test_textEditorIsFirstResponder: Bool {
        (contentView as? SelectionOverlayView)?.test_textEditorIsFirstResponder ?? false
    }

    var test_textEditorUsesTransparentText: Bool {
        (contentView as? SelectionOverlayView)?.test_textEditorUsesTransparentText ?? false
    }

    func test_commitTextEditing() {
        (contentView as? SelectionOverlayView)?.test_commitTextEditing()
    }

    func test_textEditorMouseDown(at point: NSPoint) {
        (contentView as? SelectionOverlayView)?.test_textEditorMouseDown(at: point)
    }

    func test_textEditorMouseDragged(to point: NSPoint) {
        (contentView as? SelectionOverlayView)?.test_textEditorMouseDragged(to: point)
    }

    func test_textEditorMouseDownAndDragged(from start: NSPoint, to end: NSPoint) {
        (contentView as? SelectionOverlayView)?.test_textEditorMouseDownAndDragged(from: start, to: end)
    }

    func test_textEditorDragSequence(from start: NSPoint, to end: NSPoint) {
        (contentView as? SelectionOverlayView)?.test_textEditorDragSequence(from: start, to: end)
    }

    private func test_mouseEvent(
        type: NSEvent.EventType,
        at point: NSPoint,
        modifierFlags: NSEvent.ModifierFlags = [],
        clickCount: Int = 1
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        )!
    }

    private func test_keyEvent(
        keyCode: UInt16,
        charactersIgnoringModifiers: String,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: charactersIgnoringModifiers,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
#endif

    private func completeSelection(with result: CaptureSelectionResult?) {
        guard !didCompleteSelection else {
            return
        }
        didCompleteSelection = true
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }
        (contentView as? SelectionOverlayView)?.prepareForCompletion()
        makeFirstResponder(nil)
        if configuration.completesBeforeOrderingOut {
            selectionHandler(result)
            orderOut(nil)
        } else {
            orderOut(nil)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.selectionHandler(result)
            }
        }
    }

    private static func desktopFrame() -> NSRect {
        var iterator = NSScreen.screens.makeIterator()
        guard var frame = iterator.next()?.frame else {
            return .zero
        }

        while let nextFrame = iterator.next()?.frame {
            frame = frame.union(nextFrame)
        }

        return frame
    }

    static func visibleDesktopFrame() -> NSRect {
        var iterator = NSScreen.screens.makeIterator()
        guard var frame = iterator.next()?.visibleFrame else {
            return desktopFrame()
        }

        while let nextFrame = iterator.next()?.visibleFrame {
            frame = frame.union(nextFrame)
        }

        return frame
    }

    private static func paletteColor(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private final class SelectionTextEditor: NSTextView {
    var textInputDidChange: (() -> Void)?
    var overlayMouseDown: ((NSEvent) -> Bool)?
    var overlayMouseDragged: ((NSEvent) -> Bool)?
    var overlayMouseUp: ((NSEvent) -> Bool)?
    private var isForwardingMouseEventsToOverlay = false

    override func insertText(_ insertString: Any) {
        insertCommittedText(insertString, source: "direct")
    }

    func insertCommittedText(_ insertString: Any, source: String = "forwarded") {
        let replacementRange = currentTextInputReplacementRange()
        NSLog(
            "xxsnap text editor insertText %@ replacement=(%ld,%ld) selected=(%ld,%ld) marked=(%ld,%ld) length=%ld payload=%@",
            source,
            replacementRange.location,
            replacementRange.length,
            selectedRange().location,
            selectedRange().length,
            markedRange().location,
            markedRange().length,
            (string as NSString).length,
            String(describing: type(of: insertString))
        )
        super.insertText(insertString, replacementRange: replacementRange)
        makeTextStorageTransparent()
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        NSLog(
            "xxsnap text editor insertText replacement=(%ld,%ld) selected=(%ld,%ld) marked=(%ld,%ld) length=%ld payload=%@",
            replacementRange.location,
            replacementRange.length,
            selectedRange().location,
            selectedRange().length,
            markedRange().location,
            markedRange().length,
            (string as NSString).length,
            String(describing: type(of: insertString))
        )
        super.insertText(insertString, replacementRange: replacementRange)
        makeTextStorageTransparent()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        NSLog(
            "xxsnap text editor setMarkedText selected=(%ld,%ld) replacement=(%ld,%ld) currentMarked=(%ld,%ld) length=%ld payload=%@",
            selectedRange.location,
            selectedRange.length,
            replacementRange.location,
            replacementRange.length,
            markedRange().location,
            markedRange().length,
            (self.string as NSString).length,
            String(describing: type(of: string))
        )
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        makeTextStorageTransparent()
        textInputDidChange?()
    }

    override func unmarkText() {
        NSLog(
            "xxsnap text editor unmarkText marked=(%ld,%ld) length=%ld",
            markedRange().location,
            markedRange().length,
            (string as NSString).length
        )
        super.unmarkText()
    }

    override func mouseDown(with event: NSEvent) {
        NSLog(
            "xxsnap text editor mouseDown point=(%.0f, %.0f) selected=(%ld,%ld) marked=(%ld,%ld) length=%ld",
            event.locationInWindow.x,
            event.locationInWindow.y,
            selectedRange().location,
            selectedRange().length,
            markedRange().location,
            markedRange().length,
            (string as NSString).length
        )
        if overlayMouseDown?(event) == true {
            isForwardingMouseEventsToOverlay = true
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isForwardingMouseEventsToOverlay {
            NSLog(
                "xxsnap text editor mouseDragged forwarded point=(%.0f, %.0f)",
                event.locationInWindow.x,
                event.locationInWindow.y
            )
            if overlayMouseDragged?(event) == true {
                return
            }
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if isForwardingMouseEventsToOverlay {
            NSLog(
                "xxsnap text editor mouseUp forwarded point=(%.0f, %.0f)",
                event.locationInWindow.x,
                event.locationInWindow.y
            )
            _ = overlayMouseUp?(event)
            isForwardingMouseEventsToOverlay = false
            return
        }
        super.mouseUp(with: event)
    }

    func moveInsertionPointToEnd() {
        setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
    }

    private func currentTextInputReplacementRange() -> NSRange {
        let marked = markedRange()
        let textLength = (string as NSString).length
        if marked.location != NSNotFound,
           marked.length > 0,
           NSMaxRange(marked) <= textLength {
            return marked
        }
        return selectedRange()
    }

    func makeTextStorageTransparent() {
        guard let textStorage, textStorage.length > 0 else {
            return
        }
        textStorage.addAttributes([
            .foregroundColor: NSColor.clear,
            .strokeColor: NSColor.clear,
            .strokeWidth: 0,
            .backgroundColor: NSColor.clear,
        ], range: NSRange(location: 0, length: textStorage.length))
    }
}

private final class SelectionOverlayView: NSView, NSTextViewDelegate {
    private enum NumberHandleKind {
        case delete
        case resize
        case increment
        case decrement
        case reset
    }

    private struct NumberHandleHit {
        var index: Int
        var kind: NumberHandleKind
    }

    private struct ColorSamplerPixelSource {
        var imageSize: NSSize
        var bitmap: NSBitmapImageRep?
        var cgImage: CGImage?
    }

    private struct PixelAlignedCrop {
        var image: NSImage
        var pixelRect: CGRect
        var drawRect: NSRect
    }

    private struct EraserMaskedCompositeCacheEntry {
        var revision: UInt64
        var image: NSImage
        var pixelRect: CGRect
        var drawRect: NSRect
        var drawClipPath: NSBezierPath
    }

    private struct OutsideMaskedAnnotationCacheEntry {
        var revision: UInt64
        var image: NSImage
        var rect: NSRect
    }

    var selectionDidFinish: ((CaptureSelectionResult?) -> Void)?
    var scrollCaptureDidRequest: ((ScrollCaptureSeed) -> Void)?
    var scrollCaptureCancelDidRequest: (() -> Void)?
    var scrollCaptureFinishDidRequest: (() -> Void)?
    var scrollCaptureOverlayState: ScrollCaptureOverlayState = .inactive {
        didSet {
            if scrollCaptureOverlayState != .inactive {
                clearColorSampler()
                eyedropperMeasurementStartPoint = nil
                eyedropperMeasurementEndPoint = nil
                colorSamplerCopySuccessTimer?.invalidate()
                colorSamplerCopySuccessTimer = nil
                colorSamplerCopySuccessUntil = nil
            }
            needsDisplay = true
        }
    }
    private var backgroundImage: NSImage? {
        didSet { invalidateEraserMaskedComposite() }
    }
    private var backgroundBitmap: NSBitmapImageRep?
    private var suppressedAnnotationIDs: Set<AnnotationID>
    private var backgroundLuminanceCache: [String: CGFloat] = [:]
    private let settings: AppSettings
    private let featureGate: FeatureGate
    private let configuration: SelectionOverlayConfiguration
    private let refreshHandler: (() async throws -> NSImage?)?
    private let colorSamplerSize = NSSize(width: 184, height: 188)
    private let mainToolbarButtonStep: CGFloat = 28
    private let mainToolbarHorizontalPadding: CGFloat = 4
    private static let defaultTextSize: CGFloat = 8
    private var strokePatternOptions: [SelectionToolbarState.StrokePatternOption] {
        SelectionToolbarState.strokePatternOptions(
            canUsePremiumStrokePatterns: featureGate.isEnabled(.sketchStrokePatterns),
            mode: optionsToolbarMode
        )
    }

    init(
        frame frameRect: NSRect,
        backgroundImage: NSImage?,
        settings: AppSettings,
        featureGate: FeatureGate,
        configuration: SelectionOverlayConfiguration,
        refreshHandler: (() async throws -> NSImage?)?
    ) {
        self.backgroundImage = backgroundImage
        self.settings = settings
        self.featureGate = featureGate
        self.configuration = configuration
        self.suppressedAnnotationIDs = configuration.suppressedAnnotationIDs
        self.refreshHandler = refreshHandler
        if let cgImage = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            self.backgroundBitmap = NSBitmapImageRep(cgImage: cgImage)
        } else {
            self.backgroundBitmap = nil
        }
        super.init(frame: frameRect)
        annotations = configuration.initialAnnotations
        eraserMasks = configuration.initialEraserMasks
        if let initialLockedSelectionRect = configuration.initialLockedSelectionRect {
            setLockedSelectionRect(initialLockedSelectionRect)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private enum InteractionMode {
        case selecting
        case annotating
        case drawingShape
        case draggingToolbar
        case draggingCornerRadius
        case draggingMosaicValue
        case movingShape
        case movingSelection
        case resizingShape
        case resizingArrowLine
        case resizingMarkerLine
        case rotatingBrush
        case rotatingMosaicRectangle
        case resizingSelection
        case placingNumberMark
        case erasingAnnotation
        case drawingEraserRectangle
    }

    private enum EraserMode {
        case point
        case rectangle
    }

    private enum ToolbarButton {
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
        case undo
        case redo
        case cancel
        case pin
        case save
        case copy
        case scroll
        case finishEditing
    }

    private enum TextDropdownKind {
        case font
        case size
    }

    private enum ShapeResizeHandle: CaseIterable {
        case topLeft
        case top
        case topRight
        case left
        case right
        case bottomLeft
        case bottom
        case bottomRight

        var toolbarStateHandle: SelectionToolbarState.OverlayResizeHandle {
            switch self {
            case .topLeft:
                return .topLeft
            case .top:
                return .top
            case .topRight:
                return .topRight
            case .left:
                return .left
            case .right:
                return .right
            case .bottomLeft:
                return .bottomLeft
            case .bottom:
                return .bottom
            case .bottomRight:
                return .bottomRight
            }
        }

        init(toolbarStateHandle: SelectionToolbarState.OverlayResizeHandle) {
            switch toolbarStateHandle {
            case .topLeft:
                self = .topLeft
            case .top:
                self = .top
            case .topRight:
                self = .topRight
            case .left:
                self = .left
            case .right:
                self = .right
            case .bottomLeft:
                self = .bottomLeft
            case .bottom:
                self = .bottom
            case .bottomRight:
                self = .bottomRight
            }
        }
    }

    private enum ArrowTypeField {
        case start
        case end
    }

    private let colors = SelectionOverlayWindow.defaultPaletteColors
    private var visiblePaletteCount: Int {
        min(colors.count, settings.paletteVisibleCount)
    }
    private var windowCandidates: [WindowSelectionCandidate] = []
    private var hoveredWindowRect: NSRect?
    private var displayedWindowRect: NSRect?
    private var pendingWindowSelectionRect: NSRect?
    private var hoverAnimationTimer: Timer?
    private var hoveredTooltip: (identifier: String, text: String, anchor: NSRect)?
    private var interactionMode = InteractionMode.selecting
    private var isPinnedImageDragInProgress = false
    private var selectionStartPoint: NSPoint?
    private var selectionCurrentPoint: NSPoint?
    private var lockedSelectionRect: NSRect? {
        didSet { invalidateEraserMaskedComposite() }
    }
    private var shapeStartPoint: NSPoint?
    private var shapeCurrentPoint: NSPoint?
    private var eraserRectangleStartPoint: NSPoint?
    private var eraserRectangleCurrentPoint: NSPoint?
    private var brushDraftPoints: [NSPoint] = []
    private var mosaicDraftPoints: [NSPoint] = []
    private var annotations: [CaptureAnnotation] = [] {
        didSet { invalidateEraserMaskedComposite() }
    }
    private var editorDocumentRevision: UInt64 = 0
    private enum AnnotationHistoryEntry {
        case add(annotation: CaptureAnnotation, index: Int)
        case delete(annotation: CaptureAnnotation, index: Int, masks: [EraserMask])
        case deleteMany(entries: [DeletedAnnotationEntry], masks: [EraserMask])
        case addEraserMask(mask: EraserMask)
    }

    private struct DeletedAnnotationEntry {
        var annotation: CaptureAnnotation
        var index: Int
    }

    private var undoAnnotationEntries: [AnnotationHistoryEntry] = []
    private var redoAnnotationEntries: [AnnotationHistoryEntry] = []
    private var eraserMasks: [EraserMask] = [] {
        didSet { invalidateEraserMaskedComposite() }
    }
    private var eraserMaskedCompositeRevision: UInt64 = 0
    private var eraserMaskedCompositeCache: EraserMaskedCompositeCacheEntry?
    private var outsideMaskedAnnotationCache: [AnnotationID: OutsideMaskedAnnotationCacheEntry] = [:]
#if DEBUG
    private var eraserMaskedCompositeRenderCount = 0
    private var eraserMaskedCompositeCacheHitCount = 0
    private var eraserMaskedCompositeDrawRect: NSRect?
    private var eraserMaskedCompositePixelRect: CGRect?
    private var outsideMaskedAnnotationRenderCount = 0
    private var outsideMaskedAnnotationCacheHitCount = 0
#endif
    private var damagedAnnotationIDs: Set<AnnotationID> {
        Set(eraserMasks.flatMap(\.affectedAnnotationIDs))
    }
    private func isDamagedAnnotation(_ annotation: CaptureAnnotation) -> Bool {
        damagedAnnotationIDs.contains(annotation.id)
    }
    private func annotationIsEditable(at index: Int) -> Bool {
        annotations.indices.contains(index) && !isDamagedAnnotation(annotations[index])
    }
    private var hasDamagedAnnotations: Bool {
        annotations.contains { isDamagedAnnotation($0) }
    }
    private var selectedAnnotationIndex: Int?
    private var selectedNumberAnnotationCanFollowTypeDropdown = false
    private var revealedNumberControlsIndex: Int?
    private var editingNumberAnnotationIndex: Int?
    private var editingNumberDraft: String = ""
    private var editingNumberHasDraft = false
    private var editingNumberDraftWasEdited = false
    private var editingNumberCaretIndex = 0
    private var numberCaretBlinkTimer: Timer?
    private var numberCaretVisible = false
    private var movingAnnotationStartRect: NSRect?
    private var movingAnnotationStartArrowLine: CaptureArrowLine?
    private var movingAnnotationStartBrushPath: CaptureBrushPath?
    private var movingAnnotationStartMarkerLine: CaptureMarkerLine?
    private var movingAnnotationStartMosaicStroke: CaptureMosaicStroke?
    private var mosaicGeometryEditingStartAnnotations: [CaptureAnnotation] = []
    private var mosaicGeometryEditingStartComposite: (image: NSImage, drawRect: NSRect)?
    private var mosaicGeometryEditingStartCompositeKey: String?
    private var movingAnnotationOffset = NSPoint.zero
    private var rotatingMosaicRectangleStartPointerAngle: CGFloat?
    private var rotatingMosaicRectangleStartAnnotationAngle: CGFloat = 0
    private var movingSelectionStartRect: NSRect?
    private var movingSelectionPointerOffset = NSPoint.zero
    private var movingSelectionBounds: NSRect?
    private var movingSelectionStartAnnotationRects: [NSRect] = []
    private var movingSelectionStartAnnotations: [CaptureAnnotation] = []
    private var mainToolbarOffset = NSSize.zero
    private var toolbarDragStartPoint: NSPoint?
    private var toolbarDragStartOffset = NSSize.zero
    private var activeResizeHandle: ShapeResizeHandle?
    private var resizingAnnotationStartRect: NSRect?
    private var resizingAnnotationStartStyle: CaptureAnnotationStyle?
    private var activeArrowLineHandle: SelectionToolbarState.ArrowLineHitTarget?
    private var resizingArrowLineStart: CaptureArrowLine?
    private var activeMarkerLineHandle: SelectionToolbarState.BrushRotationHitTarget?
    private var resizingMarkerLineStart: CaptureMarkerLine?
    private var activeBrushRotationHandle: SelectionToolbarState.BrushRotationHitTarget?
    private var rotatingBrushStartPath: CaptureBrushPath?
    private var activeSelectionResizeHandle: SelectionToolbarState.OverlayResizeHandle?
    private var resizingSelectionStartRect: NSRect?
    private var resizingSelectionStartAnnotationRects: [NSRect] = []
    private var resizingSelectionStartAnnotations: [CaptureAnnotation] = []
    private var selectionWheelAnimationTimer: Timer?
    private var selectionWheelAnimationStartTime: CFTimeInterval?
    private var selectionWheelAnimationStartRect: NSRect?
    private var selectionWheelAnimationTargetRect: NSRect?
    private var selectionWheelAnimationStartAnnotationRects: [NSRect] = []
    private var selectionWheelAnimationStartAnnotations: [CaptureAnnotation] = []
    private let defaultSelectionCornerRadius: CGFloat = 10
    private var selectionCornerRadius: CGFloat = 10
    private var isSelectionAspectRatioLocked = false
    private var isRefreshingSelectionBackground = false
    private var refreshAnimationStartDate: Date?
    private var refreshAnimationTimer: Timer?
    private var currentShapeKind = CaptureAnnotationKind.rectangle
    private var activeShapeKind: CaptureAnnotationKind?
    private var isShapeToolActive = false
    private var isEyedropperToolActive = false
    private var isTextToolActive = false
    private var isNumberToolActive = false
    private var isMagnifierToolActive = false
    private var isEraserToolActive = false
    private var eraserMode: EraserMode = .point
    private var currentMagnifierShape: CaptureMagnifierShape = .rectangle
    private var currentMagnifierZoom: CGFloat = 2
    private var currentNumberMarkType: CaptureNumberMarkType = .number
    private var currentNumberSequenceGroupID: UUID?
    private var nextNumberSequenceIndexAfterReset: Int?
    private var editingTextAnnotationIndex: Int?
    private var textDraftCreatedDuringCurrentEdit = false
    private var pendingTextEditAnnotationIndex: Int?
    private var pendingTextEditStartPoint: NSPoint?
    private var pendingTextEditResizeHandle: ShapeResizeHandle?
    private var pendingTextEditShouldBeginEditing = true
    private var shouldRestoreWindowLevelAfterForwardedTextDrag = false
    private var textEditor: NSTextView?
    private let textCaretAnnotationWidth: CGFloat = 1
    private let textDeleteHandleIconSize: CGFloat = 14
    private var currentStyle = CaptureAnnotationStyle()
    private var nonMarkerStyle = CaptureAnnotationStyle()
    private var markerStyle = SelectionToolbarState.markerActivationStyle(currentStyle: CaptureAnnotationStyle())
    private var textStyle = SelectionOverlayView.defaultTextStyle()
    private var numberStyle = SelectionOverlayView.defaultNumberStyle()
    private var magnifierStyle = SelectionOverlayView.defaultMagnifierStyle()
    private var mosaicRedactionType: CaptureMosaicRedactionType = .pixelMosaic
    private var mosaicRedactionValues: [CaptureMosaicRedactionType: Int] = [
        .gaussianBlur: SelectionToolbarState.mosaicDefaultRedactionValue(for: .gaussianBlur),
        .pixelMosaic: SelectionToolbarState.mosaicDefaultRedactionValue(for: .pixelMosaic),
    ]
    private var mosaicValueEditingText: String?
    private var mosaicDotIndex: Int = 0
    private var mosaicCompositeCache: [String: (image: NSImage, drawRect: NSRect)] = [:]
    private var mosaicDraftPreviewCache: [String: NSImage] = [:]
    private var mosaicDraftRedactedBaseCache: [String: NSImage] = [:]
    private var mosaicRectangleIconCache: [String: NSImage] = [:]
    private var mosaicCompositeRenderCount = 0
    private var mosaicFullCompositeRenderCount = 0
    private var mosaicCompositeDrawCount = 0
    private var mosaicDraftRedactedBaseRenderCount = 0
    private var mosaicDraftPreviewImageRenderCount = 0
    private var mosaicPerformanceFrameIndex = 0
    private var mosaicPerformanceLastFrameLogTime: TimeInterval = 0
    private var mosaicPerformanceLastCacheLogTime: TimeInterval = 0
#if DEBUG
    private var mosaicTextBaseLastLogTime: TimeInterval = 0
#endif
    private var currentStartArrowType = CaptureArrowType.none
    private var currentEndArrowType = CaptureArrowType.normal
    private var customColor: NSColor?
    private var isCustomColorSwatchActive = false
    private var showsCornerRadiusPanel = false
    private var showsStrokeStyleMenu = false
    private var showsStartArrowTypeMenu = false
    private var showsEndArrowTypeMenu = false
    private var activeNumberDropdown = false
    private var activeMagnifierZoomDropdown = false
    private var activeTextDropdown: TextDropdownKind?
    private var textFontDropdownScrollOffset = 0
    private var textSizeDropdownScrollOffset = 0
    private var textDropdownScrollRemainderY: CGFloat = 0
    private var sampledPointerPoint: NSPoint?
    private var sampledColor: NSColor?
    private var eyedropperMeasurementStartPoint: NSPoint?
    private var eyedropperMeasurementEndPoint: NSPoint?
    private var isEyedropperMeasurementInProgress = false
#if DEBUG
    private var eyedropperMeasurementInvalidationRectForTesting: NSRect?
    private var visibleSelectionCompositeLookupCountForTesting = 0
#endif
    private var colorSamplerCopyMode: SelectionToolbarState.ColorSamplerCopyMode = .hex
    private var colorSamplerCopySuccessUntil: Date?
    private var colorSamplerCopySuccessTimer: Timer?
    private var wasShiftDown = false
    private var pinnedImageToolbarShiftShortcutCandidate = false

    override var acceptsFirstResponder: Bool {
        true
    }

    override func insertText(_ insertString: Any) {
        NSLog(
            "xxsnap text insertText editing=%@ payloadType=%@",
            isEditingTextAnnotation ? "yes" : "no",
            "\(type(of: insertString))"
        )
        if let textEditor, window?.firstResponder === textEditor {
            if let selectionTextEditor = textEditor as? SelectionTextEditor {
                selectionTextEditor.insertCommittedText(insertString)
            } else {
                textEditor.insertText(insertString, replacementRange: textEditor.selectedRange())
            }
            return
        }
        guard insertTextIntoCurrentAnnotation(insertString) else {
            super.insertText(insertString)
            return
        }
    }

    override func doCommand(by selector: Selector) {
        guard isEditingTextAnnotation else {
            super.doCommand(by: selector)
            return
        }

        NSLog("xxsnap text doCommand selector=%@", NSStringFromSelector(selector))
        switch selector {
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertLineBreak(_:)):
            _ = insertTextIntoCurrentAnnotation("\n")
        case #selector(NSResponder.deleteBackward(_:)),
             #selector(NSResponder.deleteForward(_:)):
            deleteBackwardInCurrentTextAnnotation()
        case #selector(NSResponder.cancelOperation(_:)):
            cancelCurrentTextEdit()
        default:
            super.doCommand(by: selector)
        }
    }

    func textDidChange(_ notification: Notification) {
        guard let editor = notification.object as? NSTextView, editor === textEditor else {
            return
        }
        syncEditingTextFromEditor()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let editor = notification.object as? NSTextView, editor === textEditor else {
            return
        }
        needsDisplay = true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard textView === textEditor else {
            return false
        }

        NSLog("xxsnap text editor command selector=%@", NSStringFromSelector(commandSelector))
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertLineBreak(_:)):
            return false
        case #selector(NSResponder.cancelOperation(_:)):
            cancelCurrentTextEdit()
            return true
        default:
            return false
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseExited(with event: NSEvent) {
        commitNumberEditingIfNeeded()
        hoveredWindowRect = nil
        displayedWindowRect = nil
        hoverAnimationTimer?.invalidate()
        hoverAnimationTimer = nil
        hoveredTooltip = nil
        revealedNumberControlsIndex = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    deinit {
        hoverAnimationTimer?.invalidate()
        refreshAnimationTimer?.invalidate()
        colorSamplerCopySuccessTimer?.invalidate()
        selectionWheelAnimationTimer?.invalidate()
        numberCaretBlinkTimer?.invalidate()
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
    }

    func prepareForCompletion() {
        closeCustomColorPanel()
        refreshAnimationTimer?.invalidate()
        refreshAnimationTimer = nil
        refreshAnimationStartDate = nil
        colorSamplerCopySuccessTimer?.invalidate()
        selectionWheelAnimationTimer?.invalidate()
        selectionWheelAnimationTimer = nil
        selectionWheelAnimationStartTime = nil
        stopNumberCaretBlink()
        eraserMaskedCompositeCache = nil
        outsideMaskedAnnotationCache.removeAll()
        selectionDidFinish = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let frameStart = CFAbsoluteTimeGetCurrent()
        let compositeRenderCountBeforeFrame = mosaicCompositeRenderCount
        let compositeDrawCountBeforeFrame = mosaicCompositeDrawCount
        let redactedBaseRenderCountBeforeFrame = mosaicDraftRedactedBaseRenderCount
        let previewImageRenderCountBeforeFrame = mosaicDraftPreviewImageRenderCount
        defer {
            logMosaicDrawFrameIfNeeded(
                startTime: frameStart,
                dirtyRect: dirtyRect,
                compositeRenderCountBeforeFrame: compositeRenderCountBeforeFrame,
                compositeDrawCountBeforeFrame: compositeDrawCountBeforeFrame,
                redactedBaseRenderCountBeforeFrame: redactedBaseRenderCountBeforeFrame,
                previewImageRenderCountBeforeFrame: previewImageRenderCountBeforeFrame
            )
        }

        drawOverlay()

        guard let selectionRect else {
            return
        }

        let drawsMaskedAnnotationsBeforeChrome = lockedSelectionRect != nil && hasEraserMasksForDrawing
        if drawsMaskedAnnotationsBeforeChrome {
            drawAnnotations()
            drawMosaicDraftPreviewIfNeeded()
        }

        if configuration.showsSelectionBorder {
            drawSelectionBorder(selectionRect)
        }
        drawSelectionHandles(selectionRect)
        if configuration.showsSelectionMeasurementControl {
            drawMeasurementLabel(selectionRect)
        }

        guard lockedSelectionRect != nil else {
            drawColorSamplerIfNeeded()
            return
        }

        if !drawsMaskedAnnotationsBeforeChrome {
            drawAnnotations()
        }
        drawEditingTextCaretIfNeeded()
        drawDraftAnnotation()
        drawEraserRectanglePreview()
        if !isPinnedImageDragInProgress {
            drawMainToolbar(for: selectionRect)
            drawOptionsToolbar(for: selectionRect)
        }

        if showsCornerRadiusPanel {
            drawCornerRadiusPanel(for: selectionRect)
        }
        if showsStrokeStyleMenu, SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode) {
            drawStrokeStyleMenu(for: selectionRect)
        }
        if showsStartArrowTypeMenu {
            drawArrowTypeMenu(field: .start)
        }
        if showsEndArrowTypeMenu {
            drawArrowTypeMenu(field: .end)
        }
        drawNumberMarkTypeMenuIfNeeded()
        drawMagnifierZoomMenuIfNeeded()
        drawTextDropdownIfNeeded()
        drawTooltipIfNeeded()
        drawEyedropperMeasurementIfNeeded()
        drawColorSamplerIfNeeded()
    }

    private func logMosaicDrawFrameIfNeeded(
        startTime: TimeInterval,
        dirtyRect: NSRect,
        compositeRenderCountBeforeFrame: Int,
        compositeDrawCountBeforeFrame: Int,
        redactedBaseRenderCountBeforeFrame: Int,
        previewImageRenderCountBeforeFrame: Int
    ) {
        let hasMosaicWork = hasMosaicPerformanceWork
        guard hasMosaicWork else {
            return
        }

        mosaicPerformanceFrameIndex += 1
        let now = CFAbsoluteTimeGetCurrent()
        let elapsedMs = (now - startTime) * 1000
        let compositeRenderDelta = mosaicCompositeRenderCount - compositeRenderCountBeforeFrame
        let compositeDrawDelta = mosaicCompositeDrawCount - compositeDrawCountBeforeFrame
        let redactedBaseRenderDelta = mosaicDraftRedactedBaseRenderCount - redactedBaseRenderCountBeforeFrame
        let previewImageRenderDelta = mosaicDraftPreviewImageRenderCount - previewImageRenderCountBeforeFrame
        let shouldLogSlowFrame = elapsedMs >= 12
        let shouldLogPeriodicEditingFrame = mosaicGeometryEditingShouldUseCachedComposite
            && now - mosaicPerformanceLastFrameLogTime >= 1.0
        let shouldLogUnexpectedRender = mosaicGeometryEditingShouldUseCachedComposite
            && (compositeRenderDelta > 0 || redactedBaseRenderDelta > 0 || previewImageRenderDelta > 0)

        guard shouldLogSlowFrame || shouldLogPeriodicEditingFrame || shouldLogUnexpectedRender else {
            return
        }

        mosaicPerformanceLastFrameLogTime = now
        NSLog(
            "xxsnap mosaic-perf frame index=%ld elapsedMs=%.2f mode=%@ annotations=%ld mosaic=%ld selected=%@ dirty=%@ cache(composite=%ld,draft=%ld,redacted=%ld) delta(compositeRender=%ld,compositeDraw=%ld,redactedRender=%ld,previewRender=%ld) total(compositeRender=%ld,compositeDraw=%ld,redactedRender=%ld,previewRender=%ld)",
            mosaicPerformanceFrameIndex,
            elapsedMs,
            "\(interactionMode)",
            annotations.count,
            mosaicAnnotationCount,
            selectedMosaicAnnotationLogDescription,
            mosaicRectLogDescription(dirtyRect),
            mosaicCompositeCache.count,
            mosaicDraftPreviewCache.count,
            mosaicDraftRedactedBaseCache.count,
            compositeRenderDelta,
            compositeDrawDelta,
            redactedBaseRenderDelta,
            previewImageRenderDelta,
            mosaicCompositeRenderCount,
            mosaicCompositeDrawCount,
            mosaicDraftRedactedBaseRenderCount,
            mosaicDraftPreviewImageRenderCount
        )
    }

    private var hasMosaicPerformanceWork: Bool {
        mosaicAnnotationCount > 0
            || draftAnnotation.map { isMosaicAnnotation($0) } == true
            || isMosaicDrawingToolActive
    }

    private var mosaicAnnotationCount: Int {
        annotations.reduce(0) { count, annotation in
            count + (isMosaicAnnotation(annotation) ? 1 : 0)
        }
    }

    private var selectedMosaicAnnotationLogDescription: String {
        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else {
            return "none"
        }
        let annotation = annotations[selectedAnnotationIndex]
        return "\(selectedAnnotationIndex):\(annotation.kind):\(mosaicRectLogDescription(overlayRect(fromLocalAnnotationRect: annotation.rect)))"
    }

    private func logMosaicPerformanceEvent(_ name: String, startTime: TimeInterval? = nil, details: String = "") {
        let elapsed = startTime.map { String(format: " elapsedMs=%.2f", (CFAbsoluteTimeGetCurrent() - $0) * 1000) } ?? ""
        let suffix = details.isEmpty ? "" : " \(details)"
        NSLog(
            "xxsnap mosaic-perf event=%@%@ mode=%@ annotations=%ld mosaic=%ld selected=%@ cache(composite=%ld,draft=%ld,redacted=%ld) total(compositeRender=%ld,compositeDraw=%ld,redactedRender=%ld,previewRender=%ld)%@",
            name,
            elapsed,
            "\(interactionMode)",
            annotations.count,
            mosaicAnnotationCount,
            selectedMosaicAnnotationLogDescription,
            mosaicCompositeCache.count,
            mosaicDraftPreviewCache.count,
            mosaicDraftRedactedBaseCache.count,
            mosaicCompositeRenderCount,
            mosaicCompositeDrawCount,
            mosaicDraftRedactedBaseRenderCount,
            mosaicDraftPreviewImageRenderCount,
            suffix
        )
    }

    private func logMosaicCacheEventIfNeeded(
        _ name: String,
        startTime: TimeInterval,
        force: Bool = false,
        details: String = ""
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsedMs = (now - startTime) * 1000
        guard force || elapsedMs >= 4 || now - mosaicPerformanceLastCacheLogTime >= 1.0 else {
            return
        }

        mosaicPerformanceLastCacheLogTime = now
        logMosaicPerformanceEvent(name, startTime: startTime, details: details)
    }

    private func mosaicRectLogDescription(_ rect: NSRect) -> String {
        String(
            format: "(%.0f,%.0f %.0fx%.0f)",
            rect.minX,
            rect.minY,
            rect.width,
            rect.height
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard scrollCaptureOverlayState == .inactive else { return }
        cancelPinnedImageToolbarShiftShortcut()
        let point = convert(event.locationInWindow, from: nil)
        let startsNewContent = isShapeToolActive
            || isTextToolActive
            || isNumberToolActive
            || isMagnifierToolActive
            || isEraserToolActive
        let targetID = startsNewContent ? nil : annotationIndexForBorder(at: point).map { annotations[$0].id }
        configuration.annotationInteractionTargetBegan?(targetID)
        configuration.annotationInteractionBegan?()
        NSLog("xxsnap overlay mouseDown mode=%@ point=(%.0f, %.0f)", "\(interactionMode)", point.x, point.y)

        cancelSelectionWheelAnimation()

        if isEyedropperToolActive, !isToolbarOrPanelPoint(point) {
            handleEyedropperMeasurementClick(at: point, modifierFlags: event.modifierFlags)
            updateColorSampler(at: point)
            needsDisplay = true
            return
        }

        switch interactionMode {
        case .selecting:
            if let hoverRect = (hoveredWindowRect ?? displayedWindowRect)?.standardized,
               hoverRect.contains(point),
               hoverRect.width >= 8,
               hoverRect.height >= 8 {
                pendingWindowSelectionRect = hoverRect
                selectionStartPoint = point
                selectionCurrentPoint = nil
                updateColorSampler(at: point)
                NSLog("xxsnap overlay window selection pending rect=(%.0f, %.0f, %.0f, %.0f)", hoverRect.minX, hoverRect.minY, hoverRect.width, hoverRect.height)
                invalidateCursorRectsAndRefresh(at: point)
                needsDisplay = true
                return
            }
            pendingWindowSelectionRect = nil
            selectionStartPoint = point
            selectionCurrentPoint = point
            updateColorSampler(at: point)
        case .annotating, .drawingShape, .drawingEraserRectangle, .draggingToolbar, .draggingCornerRadius, .draggingMosaicValue, .movingShape, .movingSelection, .resizingShape, .resizingArrowLine, .resizingMarkerLine, .rotatingBrush, .rotatingMosaicRectangle, .resizingSelection, .placingNumberMark, .erasingAnnotation:
            if beginPinnedImageDragIfPossible(at: point) {
                needsDisplay = true
                return
            }
            handleAnnotatingMouseDown(at: point, clickCount: event.clickCount)
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard scrollCaptureOverlayState == .inactive else { return }
        let point = convert(event.locationInWindow, from: nil)

        if isPinnedImageDragInProgress {
            configuration.pinnedImageDragChanged?(screenPoint(from: point))
            needsDisplay = true
            return
        }

        if isEyedropperToolActive, interactionMode == .annotating {
            updateEyedropperMeasurement(to: point, modifierFlags: event.modifierFlags)
            updateColorSampler(at: point)
            return
        }

        switch interactionMode {
        case .selecting:
            if let selectionStartPoint, hypot(point.x - selectionStartPoint.x, point.y - selectionStartPoint.y) > 3 {
                pendingWindowSelectionRect = nil
            }
            hoveredWindowRect = nil
            selectionCurrentPoint = point
            updateColorSampler(at: point)
        case .drawingShape:
            let clampedPoint = clamp(point, to: bounds)
            shapeCurrentPoint = draftEndPoint(rawEnd: clampedPoint, modifierFlags: event.modifierFlags)
            let draftPoint = shapeCurrentPoint ?? clampedPoint
            appendBrushDraftPointIfNeeded(clampedPoint, modifierFlags: event.modifierFlags)
            appendMosaicDraftPointIfNeeded(draftPoint, modifierFlags: event.modifierFlags)
        case .drawingEraserRectangle:
            eraserRectangleCurrentPoint = clamp(point, to: bounds)
        case .draggingToolbar:
            updateDraggingToolbar(to: point)
        case .annotating:
            if isShapeToolActive || isMagnifierToolActive {
                let clampedPoint = clamp(point, to: bounds)
                shapeStartPoint = shapeStartPoint ?? clampedPoint
                shapeCurrentPoint = draftEndPoint(rawEnd: clampedPoint, modifierFlags: event.modifierFlags)
                if currentShapeKind == .brush, brushDraftPoints.isEmpty {
                    brushDraftPoints = [shapeStartPoint ?? clampedPoint, clampedPoint]
                }
                if currentShapeKind == .mosaicStroke, mosaicDraftPoints.isEmpty {
                    mosaicDraftPoints = [shapeStartPoint ?? clampedPoint, clampedPoint]
                }
                let draftPoint = shapeCurrentPoint ?? clampedPoint
                appendBrushDraftPointIfNeeded(clampedPoint, modifierFlags: event.modifierFlags)
                appendMosaicDraftPointIfNeeded(draftPoint, modifierFlags: event.modifierFlags)
                interactionMode = .drawingShape
                NSLog("xxsnap overlay recovered drawing from drag point=(%.0f, %.0f)", point.x, point.y)
            } else if let pendingTextEditAnnotationIndex,
                      let pendingTextEditStartPoint,
                      annotations.indices.contains(pendingTextEditAnnotationIndex) {
                let distance = hypot(point.x - pendingTextEditStartPoint.x, point.y - pendingTextEditStartPoint.y)
                guard distance > 3 else {
                    NSLog(
                        "xxsnap text drag pending below threshold index=%ld point=(%.0f, %.0f) start=(%.0f, %.0f) distance=%.2f",
                        pendingTextEditAnnotationIndex,
                        point.x,
                        point.y,
                        pendingTextEditStartPoint.x,
                        pendingTextEditStartPoint.y,
                        distance
                    )
                    return
                }

                let pendingTextEditResizeHandle = self.pendingTextEditResizeHandle
                if editingTextAnnotationIndex == pendingTextEditAnnotationIndex {
                    guard prepareEditingTextForForwardedDrag(at: pendingTextEditAnnotationIndex) else {
                        shouldRestoreWindowLevelAfterForwardedTextDrag = false
                        return
                    }
                }
                self.pendingTextEditAnnotationIndex = nil
                self.pendingTextEditStartPoint = nil
                self.pendingTextEditResizeHandle = nil
                self.pendingTextEditShouldBeginEditing = true
                if let pendingTextEditResizeHandle {
                    beginAnnotationResize(with: pendingTextEditResizeHandle)
                    updateResizingShape(to: point)
                } else {
                    beginAnnotationMove(at: pendingTextEditAnnotationIndex, point: pendingTextEditStartPoint)
                    updateMovingShape(to: point)
                }
            } else {
                startSelectionMoveIfPossible(at: point)
                if interactionMode == .movingSelection {
                    updateMovingSelection(to: point)
                }
            }
        case .draggingCornerRadius:
            updateCornerRadius(from: point)
        case .draggingMosaicValue:
            updateMosaicValue(from: point)
        case .movingShape:
            updateMovingShape(to: point)
        case .movingSelection:
            updateMovingSelection(to: point)
        case .resizingShape:
            updateResizingShape(to: point)
        case .resizingArrowLine:
            updateResizingArrowLine(to: point, modifierFlags: event.modifierFlags)
        case .resizingMarkerLine:
            updateResizingMarkerLine(to: point)
        case .rotatingBrush:
            updateRotatingBrush(to: point)
        case .rotatingMosaicRectangle:
            updateRotatingMosaicRectangle(to: point)
        case .resizingSelection:
            updateResizingSelection(to: point)
        case .placingNumberMark, .erasingAnnotation:
            break
        }

        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelPinnedImageToolbarShiftShortcut()
        let point = convert(event.locationInWindow, from: nil)
        if let pinnedImageContextMenuHandler = configuration.pinnedImageContextMenuHandler {
            pinnedImageContextMenuHandler(screenPoint(from: point))
            return
        }

        super.rightMouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        commitNumberEditingIfPointerLeaves(at: point)
        updateRevealedNumberControls(at: point)
        if isEyedropperToolActive, isEyedropperMeasurementInProgress {
            updateEyedropperMeasurement(to: point, modifierFlags: event.modifierFlags)
        }
        updateHoverState(at: point)
        updateColorSampler(at: point)
        refreshCursor(at: point)
    }

    private func cursorStyle(at point: NSPoint) -> SelectionToolbarState.OverlayCursorStyle {
        let isInsideSelection = cursorSelectionRect?.standardized.contains(point) == true

        if interactionMode == .movingSelection {
            return backgroundAwareCursorStyle(.move, at: point)
        }

        if isEyedropperToolActive {
            if isToolbarOrPanelPoint(point) || !isInsideSelection {
                return .arrow
            }
            return backgroundAwareCursorStyle(.eyedropper, at: point)
        }

        if isEraserToolActive {
            if isToolbarOrPanelPoint(point) {
                return .arrow
            }
            return eraserMode == .rectangle ? .crosshair : .eraser
        }

        if isMagnifierToolActive {
            if isToolbarOrPanelPoint(point) {
                return .arrow
            }
            if interactionMode == .movingShape {
                return backgroundAwareCursorStyle(.move, at: point)
            }
            if interactionMode == .annotating,
               let handle = textAwareResizeHandle(at: point)?.toolbarStateHandle {
                return backgroundAwareCursorStyle(
                    SelectionToolbarState.overlayCursorStyle(for: handle),
                    at: point
                )
            }
            if interactionMode == .annotating,
               let selectedAnnotation,
               selectedAnnotation.kind == .magnifier,
               annotationBorderContains(point, for: selectedAnnotation) {
                return backgroundAwareCursorStyle(.move, at: point)
            }
            return .crosshair
        }

        if configuration.usesArrowCursorWhenIdle,
           interactionMode == .annotating,
           !isShapeToolActive,
           !isTextToolActive,
           !isNumberToolActive,
           !isMagnifierToolActive,
           !isEraserToolActive,
           !isEyedropperToolActive {
            if let lockedSelectionRect,
               !isToolbarOrPanelPoint(point),
               lockedSelectionRect.standardized.contains(point) {
                return backgroundAwareCursorStyle(.move, at: point)
            }
            return .arrow
        }

        let selectionResizeHandle = interactionMode == .annotating && !shouldPreferMosaicDrawingOutsideSelection(at: point)
            ? selectionResizeHandle(at: point)
            : nil
        let shapeResizeHandle = interactionMode == .annotating ? textAwareResizeHandle(at: point)?.toolbarStateHandle : nil
        let isAnnotationBorder = interactionMode == .annotating && annotationIndexForBorder(at: point) != nil
        let textAnnotationBorderIndex = interactionMode == .annotating ? textAnnotationBorderIndex(at: point) : nil

        if isNumberToolActive {
            if isToolbarOrPanelPoint(point) {
                return .arrow
            }
            if let hit = numberHandleHitTarget(at: point) {
                switch hit.kind {
                case .resize:
                    return backgroundAwareCursorStyle(.resizeBottomRight, at: point)
                case .delete, .increment, .decrement, .reset:
                    return .arrow
                }
            }
            if interactionMode == .movingShape {
                return backgroundAwareCursorStyle(.move, at: point)
            }
            if interactionMode == .annotating, numberAnnotationIndex(at: point) != nil {
                return backgroundAwareCursorStyle(.move, at: point)
            }
            switch currentNumberMarkType {
            case .number:
                return .numberMark
            case .check:
                return .numberCheck
            case .cross:
                return .numberCross
            }
        }

        if textDeleteHandleHitTarget(at: point) != nil {
            return .arrow
        }

        if isTextToolActive,
           interactionMode == .annotating,
           selectedAnnotation?.kind == .text {
            if let shapeResizeHandle {
                return backgroundAwareCursorStyle(SelectionToolbarState.overlayCursorStyle(for: shapeResizeHandle), at: point)
            }
            if textAnnotationBorderIndex != nil {
                return backgroundAwareCursorStyle(.move, at: point)
            }
        }

        if isTextToolActive,
           interactionMode == .annotating,
           mosaicRectangleRotationHitTarget(at: point) != nil {
            return .rotationHandle
        }

        if isTextToolActive,
           interactionMode == .annotating,
           let selectionResizeHandle,
           shapeResizeHandle == nil,
           !isAnnotationBorder,
           textAnnotationIndex(at: point) == nil {
            return backgroundAwareCursorStyle(SelectionToolbarState.overlayCursorStyle(for: selectionResizeHandle), at: point)
        }

        if isTextToolActive, !isToolbarOrPanelPoint(point) {
            return .textInput
        }

        if interactionMode == .movingShape {
            return backgroundAwareCursorStyle(.move, at: point)
        }

        if interactionMode == .annotating, mosaicRectangleRotationHitTarget(at: point) != nil {
            return .rotationHandle
        }

        if interactionMode == .annotating, shouldPreferMosaicDrawingBeforeAnnotationHitTesting(at: point) {
            let style = SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: isInsideSelection,
                isShapeToolActive: isShapeToolActive,
                currentShapeKind: currentShapeKind
            )
            return backgroundAwareCursorStyle(style, at: point)
        }

        if interactionMode == .annotating, let arrowHit = arrowLineHitTarget(at: point) {
            switch arrowHit.target {
            case .start, .end:
                return backgroundAwareCursorStyle(.resizeUpDown, at: point)
            case .control, .body:
                return backgroundAwareCursorStyle(.move, at: point)
            case .none:
                break
            }
        }

        if interactionMode == .rotatingMosaicRectangle {
            return .rotationHandle
        }

        if interactionMode == .rotatingBrush {
            return backgroundAwareCursorStyle(.resizeUpDown, at: point)
        }

        if interactionMode == .resizingMarkerLine {
            return backgroundAwareCursorStyle(.resizeUpDown, at: point)
        }

        if interactionMode == .annotating, markerRotationHitTarget(at: point) != nil {
            return backgroundAwareCursorStyle(.resizeUpDown, at: point)
        }

        if interactionMode == .annotating, brushRotationHitTarget(at: point) != nil {
            return backgroundAwareCursorStyle(.resizeUpDown, at: point)
        }

        if let shapeResizeHandle {
            return backgroundAwareCursorStyle(SelectionToolbarState.overlayCursorStyle(for: shapeResizeHandle), at: point)
        }

        if isAnnotationBorder {
            return backgroundAwareCursorStyle(.move, at: point)
        }

        if let selectionResizeHandle {
            return backgroundAwareCursorStyle(SelectionToolbarState.overlayCursorStyle(for: selectionResizeHandle), at: point)
        }

        if !isShapeToolActive, isMainToolbarDragPoint(point) {
            return backgroundAwareCursorStyle(.move, at: point)
        }

        let style = SelectionToolbarState.overlayCursorStyle(
            isSelecting: interactionMode == .selecting,
            isToolbarOrPanelPoint: isToolbarOrPanelPoint(point),
            resizeHandle: nil,
            selectionResizeHandle: nil,
            isAnnotationBorder: false,
            isInsideSelection: isInsideSelection,
            isShapeToolActive: isShapeToolActive,
            currentShapeKind: currentShapeKind
        )
        return backgroundAwareCursorStyle(style, at: point)
    }

    private func backgroundAwareCursorStyle(
        _ style: SelectionToolbarState.OverlayCursorStyle,
        at point: NSPoint
    ) -> SelectionToolbarState.OverlayCursorStyle {
        guard shouldUseLightCursor(at: point) else {
            return style
        }

        switch style {
        case .move:
            return .moveLight
        case .resizeLeftRight:
            return .resizeLeftRightLight
        case .resizeUpDown:
            return .resizeUpDownLight
        case .resizeTopLeft:
            return .resizeTopLeftLight
        case .resizeTopRight:
            return .resizeTopRightLight
        case .resizeBottomLeft:
            return .resizeBottomLeftLight
        case .resizeBottomRight:
            return .resizeBottomRightLight
        case .brush:
            return .brushLight
        case .marker:
            return .markerLight
        case .eyedropper:
            return .eyedropperLight
        default:
            return style
        }
    }

    private func refreshCursor(at point: NSPoint) {
        let style = cursorStyle(at: point)
        if currentShapeKind == .mosaicStroke, isShapeToolActive {
            if style == .crosshair {
                NSCursor.xxsnapMosaicDot(diameter: SelectionToolbarState.mosaicCursorDotDiameter(for: currentStyle.strokeWidth)).set()
            } else {
                setCursor(style)
            }
            return
        }
        if currentShapeKind == .mosaicRectangle, isShapeToolActive {
            if style != .crosshair {
                if style == .rotationHandle {
                    NSCursor.xxsnapMosaicRectangleRotationHandle.set()
                } else {
                    setCursor(style)
                }
                return
            }
            NSCursor.crosshair.set()
            return
        }
        setCursor(style)
    }

    private func refreshCursorForCurrentMouseLocation() {
        guard let window else {
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(point) {
            refreshCursor(at: point)
        } else {
            NSCursor.arrow.set()
        }
    }

    private func invalidateCursorRectsAndRefresh(at point: NSPoint? = nil) {
        window?.invalidateCursorRects(for: self)
        if let point {
            refreshCursor(at: point)
        } else {
            refreshCursorForCurrentMouseLocation()
        }
    }

    private func screenPoint(from point: NSPoint) -> NSPoint {
        window?.convertPoint(toScreen: point) ?? NSEvent.mouseLocation
    }

    private var isAnyAnnotationToolActive: Bool {
        isShapeToolActive
            || isTextToolActive
            || isNumberToolActive
            || isMagnifierToolActive
            || isEraserToolActive
            || isEyedropperToolActive
    }

    private func beginPinnedImageDragIfPossible(at point: NSPoint) -> Bool {
        guard configuration.pinnedImageDragBegan != nil,
              interactionMode == .annotating,
              !isAnyAnnotationToolActive,
              !isToolbarOrPanelPoint(point),
              let lockedSelectionRect,
              lockedSelectionRect.standardized.contains(point)
        else {
            return false
        }

        isPinnedImageDragInProgress = true
        hoveredTooltip = nil
        configuration.pinnedImageDragBegan?(screenPoint(from: point))
        return true
    }

    override func mouseUp(with event: NSEvent) {
        defer { configuration.annotationInteractionEnded?() }
        let point = convert(event.locationInWindow, from: nil)
        NSLog("xxsnap overlay mouseUp mode=%@ point=(%.0f, %.0f)", "\(interactionMode)", point.x, point.y)

        if isPinnedImageDragInProgress {
            isPinnedImageDragInProgress = false
            configuration.pinnedImageDragEnded?()
            invalidateCursorRectsAndRefresh(at: point)
            needsDisplay = true
            return
        }

        if isEyedropperToolActive, interactionMode == .annotating {
            updateColorSampler(at: point)
            invalidateCursorRectsAndRefresh(at: point)
            return
        }

        switch interactionMode {
        case .selecting:
            hoveredWindowRect = nil
            selectionCurrentPoint = point
            if
                let pendingWindowSelectionRect,
                let selectionStartPoint,
                hypot(point.x - selectionStartPoint.x, point.y - selectionStartPoint.y) <= 3
            {
                self.pendingWindowSelectionRect = nil
                self.selectionStartPoint = nil
                selectionCurrentPoint = nil
                lockedSelectionRect = pendingWindowSelectionRect
                interactionMode = .annotating
                window?.makeFirstResponder(self)
                updateColorSampler(at: point)
                NSLog("xxsnap overlay window selection locked rect=(%.0f, %.0f, %.0f, %.0f)", pendingWindowSelectionRect.minX, pendingWindowSelectionRect.minY, pendingWindowSelectionRect.width, pendingWindowSelectionRect.height)
                invalidateCursorRectsAndRefresh(at: point)
                needsDisplay = true
                return
            }
            pendingWindowSelectionRect = nil
            guard let selectionRect, selectionRect.width >= 8, selectionRect.height >= 8 else {
                selectionDidFinish?(nil)
                return
            }
            lockedSelectionRect = selectionRect
            interactionMode = .annotating
            window?.makeFirstResponder(self)
            updateColorSampler(at: point)
            NSLog("xxsnap overlay selection locked rect=(%.0f, %.0f, %.0f, %.0f)", selectionRect.minX, selectionRect.minY, selectionRect.width, selectionRect.height)
        case .drawingShape:
            let clampedPoint = clamp(point, to: bounds)
            shapeCurrentPoint = draftEndPoint(rawEnd: clampedPoint, modifierFlags: event.modifierFlags)
            let draftPoint = shapeCurrentPoint ?? clampedPoint
            appendBrushDraftPointIfNeeded(clampedPoint, modifierFlags: event.modifierFlags)
            appendMosaicDraftPointIfNeeded(draftPoint, modifierFlags: event.modifierFlags)
            if let draft = draftAnnotation, isUsableDraftAnnotation(draft) {
                annotations.append(draft)
                recordAnnotationAdd(at: annotations.index(before: annotations.endIndex))
                selectedAnnotationIndex = draft.kind == .brush || draft.kind == .mosaicStroke ? nil : annotations.indices.last
                currentStyle = draft.style
                if draft.kind == .magnifier {
                    magnifierStyle = draft.style
                } else {
                    currentShapeKind = draft.kind
                    activeShapeKind = draft.kind
                }
                rememberCurrentStyleForActiveTool()
                clearRedoAnnotationHistory()
                if draft.kind == .mosaicStroke || draft.kind == .mosaicRectangle {
                    resetMosaicRedactionPreviewCaches()
                }
                NSLog("xxsnap overlay added annotation count=%ld rect=(%.0f, %.0f, %.0f, %.0f)", annotations.count, draft.rect.minX, draft.rect.minY, draft.rect.width, draft.rect.height)
            }
            shapeStartPoint = nil
            shapeCurrentPoint = nil
            brushDraftPoints.removeAll()
            mosaicDraftPoints.removeAll()
            interactionMode = .annotating
        case .drawingEraserRectangle:
            eraserRectangleCurrentPoint = clamp(point, to: bounds)
            commitEraserRectangle()
            eraserRectangleStartPoint = nil
            eraserRectangleCurrentPoint = nil
            interactionMode = .annotating
        case .draggingToolbar:
            updateDraggingToolbar(to: point)
            commitToolbarDrag()
            interactionMode = .annotating
        case .draggingCornerRadius:
            updateCornerRadius(from: point)
            interactionMode = .annotating
        case .draggingMosaicValue:
            updateMosaicValue(from: point)
            interactionMode = .annotating
        case .movingShape:
            commitSelectedShapePreview()
            finishForwardedTextDragIfNeeded()
            interactionMode = .annotating
        case .movingSelection:
            commitSelectionMove()
            interactionMode = .annotating
            updateColorSampler(at: point)
        case .resizingShape:
            commitSelectedShapePreview()
            activeResizeHandle = nil
            interactionMode = .annotating
        case .resizingArrowLine:
            commitSelectedShapePreview()
            activeArrowLineHandle = nil
            resizingArrowLineStart = nil
            interactionMode = .annotating
        case .resizingMarkerLine:
            commitSelectedShapePreview()
            activeMarkerLineHandle = nil
            resizingMarkerLineStart = nil
            interactionMode = .annotating
        case .rotatingBrush:
            commitSelectedShapePreview()
            activeBrushRotationHandle = nil
            rotatingBrushStartPath = nil
            interactionMode = .annotating
        case .rotatingMosaicRectangle:
            commitSelectedShapePreview()
            rotatingMosaicRectangleStartPointerAngle = nil
            rotatingMosaicRectangleStartAnnotationAngle = 0
            interactionMode = .annotating
        case .resizingSelection:
            commitSelectionResize()
            interactionMode = .annotating
        case .placingNumberMark, .erasingAnnotation:
            interactionMode = .annotating
        case .annotating:
            if let pendingTextEditAnnotationIndex {
                let editPoint = pendingTextEditStartPoint ?? point
                let shouldBeginEditing = pendingTextEditShouldBeginEditing
                self.pendingTextEditAnnotationIndex = nil
                self.pendingTextEditStartPoint = nil
                self.pendingTextEditResizeHandle = nil
                self.pendingTextEditShouldBeginEditing = true
                guard shouldBeginEditing else {
                    if editingTextAnnotationIndex == pendingTextEditAnnotationIndex {
                        commitCurrentTextEdit(restoreWindowLevel: false)
                    } else {
                        editingTextAnnotationIndex = nil
                        removeTextEditor(restoreWindowLevel: false)
                    }
                    selectedAnnotationIndex = pendingTextEditAnnotationIndex
                    shouldRestoreWindowLevelAfterForwardedTextDrag = false
                    invalidateCursorRectsAndRefresh(at: point)
                    needsDisplay = true
                    return
                }
                if editingTextAnnotationIndex == pendingTextEditAnnotationIndex, textEditor != nil {
                    setTextEditorInsertionPoint(at: editPoint)
                    shouldRestoreWindowLevelAfterForwardedTextDrag = false
                    invalidateCursorRectsAndRefresh(at: point)
                    needsDisplay = true
                    return
                }
                beginTextEditing(at: pendingTextEditAnnotationIndex, draftCreated: false, insertionPoint: editPoint)
                invalidateCursorRectsAndRefresh(at: point)
                needsDisplay = true
                return
            }
            break
        }

        invalidateCursorRectsAndRefresh(at: point)
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        cancelPinnedImageToolbarShiftShortcut()
        let point = convert(event.locationInWindow, from: nil)
        if handleTextDropdownScroll(at: point, deltaY: event.scrollingDeltaY) {
            return
        }
        if let longImageScrollHandler = configuration.longImageScrollHandler {
            longImageScrollHandler(event.scrollingDeltaY)
            return
        }
        guard handleScrollWheel(at: point, deltaY: event.scrollingDeltaY) else {
            super.scrollWheel(with: event)
            return
        }
    }

    override func magnify(with event: NSEvent) {
        cancelPinnedImageToolbarShiftShortcut()
        let point = convert(event.locationInWindow, from: nil)
        guard handleMagnify(at: point, magnification: event.magnification) else {
            super.magnify(with: event)
            return
        }
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyDown(event) {
            return
        }

        super.keyDown(with: event)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if scrollCaptureOverlayState != .inactive {
            if event.keyCode == 53 {
                scrollCaptureCancelDidRequest?()
            } else if event.keyCode == 36 || event.keyCode == 76 {
                scrollCaptureFinishDidRequest?()
            }
            return true
        }
        cancelPinnedImageToolbarShiftShortcut()
        if shouldPassKeyDownToTextEditor(event) {
            NSLog(
                "xxsnap text keyDown passThrough keyCode=%hu charsLength=%ld",
                event.keyCode,
                event.characters?.count ?? 0
            )
            return false
        }

        if event.keyCode == 53 {
            return cancelActiveToolForEscape()
        }

        if let command = PinnedImageWindowCommand(event: event),
           let handler = configuration.pinnedImageWindowCommandHandler {
            handler(command)
            return true
        }

        if handleNumberEditingKeyDown(event) {
            return true
        }

        if handleTextEditingKeyDown(event) {
            return true
        }

        if handleMosaicValueEditingKeyDown(event) {
            return true
        }

        if Self.isAnnotationDeleteKey(event.keyCode), deleteSelectedAnnotation() {
            return true
        }

        if let button = mainToolbarButtons().first(where: { button in
            SelectionToolbarState.toolbarShortcut(for: tooltipIdentifier(for: button))?.matches(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                modifierFlags: event.modifierFlags
            ) == true
        }) {
            if isToolbarButtonEnabled(button) {
                perform(button)
            }
            return true
        }

        if SelectionToolbarState.isColorSamplerCopyShortcut(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        ),
           copySampledColorToPasteboard() {
            return true
        }

        return false
    }

    func finishPinnedImageEditingForEscape() -> Bool {
        guard configuration.showsFinishEditingButton else {
            return false
        }
        finish(action: .finishEditing)
        return true
    }

    private func cancelActiveToolForEscape() -> Bool {
        let hasActiveTool = isShapeToolActive
            || isEyedropperToolActive
            || isTextToolActive
            || isNumberToolActive
            || isMagnifierToolActive
            || isEraserToolActive
        let hasTransientToolState = isEditingTextAnnotation
            || editingNumberAnnotationIndex != nil
            || mosaicValueEditingText != nil
            || activeTextDropdown != nil
            || activeNumberDropdown
            || activeMagnifierZoomDropdown
            || showsStrokeStyleMenu
            || showsCornerRadiusPanel
            || showsStartArrowTypeMenu
            || showsEndArrowTypeMenu
        guard hasActiveTool || hasTransientToolState else {
            return false
        }

        commitCurrentTextEdit()
        commitNumberEditingIfNeeded()
        mosaicValueEditingText = nil
        clearPendingTextEdit()
        closeTextDropdown()
        closeMagnifierZoomDropdown()
        rememberCurrentStyleForActiveTool()

        isShapeToolActive = false
        activeShapeKind = nil
        isEyedropperToolActive = false
        isTextToolActive = false
        isNumberToolActive = false
        isMagnifierToolActive = false
        isEraserToolActive = false
        activeNumberDropdown = false
        clearEyedropperMeasurement()
        clearColorSampler()
        clearEraserRectangleState()

        shapeStartPoint = nil
        shapeCurrentPoint = nil
        brushDraftPoints.removeAll()
        mosaicDraftPoints.removeAll()
        selectedAnnotationIndex = nil
        revealedNumberControlsIndex = nil
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        interactionMode = lockedSelectionRect == nil ? .selecting : .annotating
        resetMosaicRedactionPreviewCaches()
        invalidateCursorRectsAndRefresh()
        needsDisplay = true
        return true
    }

    private func shouldPassKeyDownToTextEditor(_ event: NSEvent) -> Bool {
        guard
            let textEditor,
            window?.firstResponder === textEditor,
            isEditingTextAnnotation
        else {
            return false
        }

        if event.keyCode == 53 {
            return false
        }

        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            return false
        }

        return true
    }

    override func flagsChanged(with event: NSEvent) {
        let relevantModifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let colorSamplerOwnsShift = sampledColor != nil || sampledPointerPoint != nil
        if relevantModifiers == [.shift],
           !isPinnedImageDragInProgress,
           !colorSamplerOwnsShift,
           configuration.pinnedImageToolbarToggleHandler != nil {
            pinnedImageToolbarShiftShortcutCandidate = true
        } else if relevantModifiers.isEmpty, pinnedImageToolbarShiftShortcutCandidate {
            pinnedImageToolbarShiftShortcutCandidate = false
            configuration.pinnedImageToolbarToggleHandler?()
        } else {
            pinnedImageToolbarShiftShortcutCandidate = false
        }

        let isShiftDown = event.modifierFlags.contains(.shift)
        if isShiftDown, !wasShiftDown, sampledColor != nil || sampledPointerPoint != nil {
            colorSamplerCopyMode = SelectionToolbarState.toggledColorSamplerCopyMode(from: colorSamplerCopyMode)
            needsDisplay = true
        }
        wasShiftDown = isShiftDown
        super.flagsChanged(with: event)
    }

    private func cancelPinnedImageToolbarShiftShortcut() {
        pinnedImageToolbarShiftShortcutCandidate = false
    }

    override func resetCursorRects() {
        let defaultCursor = interactionMode == .selecting ? NSCursor.crosshair : .arrow
        addCursorRect(bounds, cursor: defaultCursor)
        if isEyedropperToolActive, let lockedSelectionRect {
            addCursorRect(
                lockedSelectionRect.standardized,
                cursor: selectionPrefersLightCursor(lockedSelectionRect.standardized) ? NSCursor.xxsnapEyedropperLight : NSCursor.xxsnapEyedropper
            )
        }
        if isTextToolActive, let lockedSelectionRect {
            let textInputRect = lockedSelectionRect.standardized.insetBy(dx: 12, dy: 12)
            if textInputRect.width > 0, textInputRect.height > 0 {
                addCursorRect(textInputRect, cursor: NSCursor.iBeam)
            }
        }
        if let lockedSelectionRect, isShapeToolActive {
            let drawingRect = lockedSelectionRect.standardized.insetBy(dx: 12, dy: 12)
            if drawingRect.width > 0, drawingRect.height > 0 {
                addCursorRect(drawingRect, cursor: cursorRectCursorForActiveShapeTool())
            }
        }
        if let lockedSelectionRect, interactionMode == .annotating, !isEyedropperToolActive {
            addSelectionResizeCursorRects(for: lockedSelectionRect.standardized)
        }
    }

    private func cursorRectCursorForActiveShapeTool() -> NSCursor {
        if currentShapeKind == .brush {
            return selectionPrefersLightCursor(lockedSelectionRect?.standardized) ? NSCursor.xxsnapBrushLight : NSCursor.xxsnapBrush
        }
        if currentShapeKind == .marker {
            let color = selectionPrefersLightCursor(lockedSelectionRect?.standardized) ? NSColor.white : currentStyle.strokeColor
            return NSCursor.xxsnapMarker(color: color, strokeWidth: currentStyle.strokeWidth)
        }
        if currentShapeKind == .mosaicStroke {
            return NSCursor.xxsnapMosaicDot(diameter: SelectionToolbarState.mosaicCursorDotDiameter(for: currentStyle.strokeWidth))
        }
        return NSCursor.crosshair
    }

    private func addSelectionResizeCursorRects(for rect: NSRect) {
        let outset: CGFloat = 12
        let cornerLength = min(max(outset * 2, 18), min(rect.width, rect.height) / 2)
        let useLightCursor = selectionPrefersLightCursor(rect)
        addCursorRectClipped(
            NSRect(x: rect.minX - outset, y: rect.maxY - cornerLength, width: cornerLength + outset, height: cornerLength + outset),
            cursor: nsCursor(for: useLightCursor ? .resizeTopLeftLight : .resizeTopLeft)
        )
        addCursorRectClipped(
            NSRect(x: rect.maxX - cornerLength, y: rect.maxY - cornerLength, width: cornerLength + outset, height: cornerLength + outset),
            cursor: nsCursor(for: useLightCursor ? .resizeTopRightLight : .resizeTopRight)
        )
        addCursorRectClipped(
            NSRect(x: rect.minX - outset, y: rect.minY - outset, width: cornerLength + outset, height: cornerLength + outset),
            cursor: nsCursor(for: useLightCursor ? .resizeBottomLeftLight : .resizeBottomLeft)
        )
        addCursorRectClipped(
            NSRect(x: rect.maxX - cornerLength, y: rect.minY - outset, width: cornerLength + outset, height: cornerLength + outset),
            cursor: nsCursor(for: useLightCursor ? .resizeBottomRightLight : .resizeBottomRight)
        )

        if rect.width > cornerLength * 2 {
            addCursorRectClipped(
                NSRect(x: rect.minX + cornerLength, y: rect.maxY - outset, width: rect.width - cornerLength * 2, height: outset * 2),
                cursor: nsCursor(for: useLightCursor ? .resizeUpDownLight : .resizeUpDown)
            )
            addCursorRectClipped(
                NSRect(x: rect.minX + cornerLength, y: rect.minY - outset, width: rect.width - cornerLength * 2, height: outset * 2),
                cursor: nsCursor(for: useLightCursor ? .resizeUpDownLight : .resizeUpDown)
            )
        }

        if rect.height > cornerLength * 2 {
            addCursorRectClipped(
                NSRect(x: rect.minX - outset, y: rect.minY + cornerLength, width: outset * 2, height: rect.height - cornerLength * 2),
                cursor: nsCursor(for: useLightCursor ? .resizeLeftRightLight : .resizeLeftRight)
            )
            addCursorRectClipped(
                NSRect(x: rect.maxX - outset, y: rect.minY + cornerLength, width: outset * 2, height: rect.height - cornerLength * 2),
                cursor: nsCursor(for: useLightCursor ? .resizeLeftRightLight : .resizeLeftRight)
            )
        }
    }

    private func addCursorRectClipped(_ rect: NSRect, cursor: NSCursor) {
        let clipped = rect.intersection(bounds)
        if !clipped.isNull, clipped.width > 0, clipped.height > 0 {
            addCursorRect(clipped, cursor: cursor)
        }
    }

    private func numberCursorText(for type: CaptureNumberMarkType) -> String {
        switch type {
        case .number:
            return "\(nextNumberSequenceIndex())"
        case .check:
            return "✓"
        case .cross:
            return "×"
        }
    }

    private func numberCreationCursor(for type: CaptureNumberMarkType) -> NSCursor {
        let size = NSSize(width: 30, height: 30)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
        drawNumberMarkIcon(type, in: rect, color: currentStyle.strokeColor, toolbar: false, numberText: numberCursorText(for: type))
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }

    private func nsCursor(for style: SelectionToolbarState.OverlayCursorStyle) -> NSCursor {
        switch style {
        case .arrow:
            return NSCursor.arrow
        case .crosshair:
            return NSCursor.crosshair
        case .textInput:
            return NSCursor.iBeam
        case .move:
            return NSCursor.xxsnapMove
        case .moveLight:
            return NSCursor.xxsnapMoveLight
        case .resizeLeftRight:
            return NSCursor.resizeLeftRight
        case .resizeLeftRightLight:
            return NSCursor.xxsnapResizeLeftRightLight
        case .resizeUpDown:
            return NSCursor.resizeUpDown
        case .resizeUpDownLight:
            return NSCursor.xxsnapResizeUpDownLight
        case .resizeTopLeft:
            return NSCursor.frameResize(position: .topLeft, directions: .all)
        case .resizeTopLeftLight:
            return NSCursor.xxsnapResizeTopLeftLight
        case .resizeTopRight:
            return NSCursor.frameResize(position: .topRight, directions: .all)
        case .resizeTopRightLight:
            return NSCursor.xxsnapResizeTopRightLight
        case .resizeBottomLeft:
            return NSCursor.frameResize(position: .bottomLeft, directions: .all)
        case .resizeBottomLeftLight:
            return NSCursor.xxsnapResizeBottomLeftLight
        case .resizeBottomRight:
            return NSCursor.frameResize(position: .bottomRight, directions: .all)
        case .resizeBottomRightLight:
            return NSCursor.xxsnapResizeBottomRightLight
        case .rotationHandle:
            return NSCursor.xxsnapMosaicRectangleRotationHandle
        case .eraser:
            return NSCursor.xxsnapEraser
        case .brush:
            return NSCursor.xxsnapBrush
        case .brushLight:
            return NSCursor.xxsnapBrushLight
        case .eyedropper:
            return NSCursor.xxsnapEyedropper
        case .eyedropperLight:
            return NSCursor.xxsnapEyedropperLight
        case .marker:
            return NSCursor.xxsnapMarker(color: currentStyle.strokeColor, strokeWidth: currentStyle.strokeWidth)
        case .markerLight:
            return NSCursor.xxsnapMarker(color: .white, strokeWidth: currentStyle.strokeWidth)
        case .numberMark:
            return numberCreationCursor(for: .number)
        case .numberCheck:
            return numberCreationCursor(for: .check)
        case .numberCross:
            return numberCreationCursor(for: .cross)
        }
    }

    private func setCursor(_ style: SelectionToolbarState.OverlayCursorStyle) {
        nsCursor(for: style).set()
    }

    private var selectionRect: NSRect? {
        if let lockedSelectionRect {
            return lockedSelectionRect
        }

        if let selectionStartPoint, let selectionCurrentPoint {
            return NSRect(
                x: min(selectionStartPoint.x, selectionCurrentPoint.x),
                y: min(selectionStartPoint.y, selectionCurrentPoint.y),
                width: abs(selectionCurrentPoint.x - selectionStartPoint.x),
                height: abs(selectionCurrentPoint.y - selectionStartPoint.y)
            )
        }

        return displayedWindowRect ?? hoveredWindowRect
    }

    private var colorSamplerSelectionRect: NSRect? {
        lockedSelectionRect
    }

    private var cursorSelectionRect: NSRect? {
        lockedSelectionRect ?? selectionRect
    }

    private var draftAnnotation: CaptureAnnotation? {
        guard let shapeStartPoint, let shapeCurrentPoint, lockedSelectionRect != nil else {
            return nil
        }

        if isMagnifierToolActive {
            let rect = NSRect(
                x: min(shapeStartPoint.x, shapeCurrentPoint.x),
                y: min(shapeStartPoint.y, shapeCurrentPoint.y),
                width: abs(shapeCurrentPoint.x - shapeStartPoint.x),
                height: abs(shapeCurrentPoint.y - shapeStartPoint.y)
            )
            return CaptureAnnotation(
                kind: .magnifier,
                rect: localAnnotationRect(from: rect),
                style: currentStyle,
                magnifierShape: currentMagnifierShape,
                magnifierZoom: currentMagnifierZoom
            )
        }

        if currentShapeKind == .brush {
            let overlayPath = CaptureBrushPath(points: brushDraftPoints.isEmpty ? [shapeStartPoint, shapeCurrentPoint] : brushDraftPoints)
            let localPath = localBrushPath(fromOverlayBrushPath: overlayPath)
            return CaptureAnnotation(
                kind: .brush,
                rect: localPath.boundingRect,
                style: currentStyle,
                brushPath: localPath
            )
        }

        if currentShapeKind == .arrowLine {
            let overlayLine = CaptureArrowLine(
                start: shapeStartPoint,
                end: shapeCurrentPoint,
                control: NSPoint(
                    x: (shapeStartPoint.x + shapeCurrentPoint.x) / 2,
                    y: (shapeStartPoint.y + shapeCurrentPoint.y) / 2
                ),
                startArrowType: currentStartArrowType,
                endArrowType: currentEndArrowType
            )
            let localLine = localArrowLine(fromOverlayArrowLine: overlayLine)
            return CaptureAnnotation(
                kind: .arrowLine,
                rect: localLine.boundingRect,
                style: currentStyle,
                arrowLine: localLine
            )
        }

        if currentShapeKind == .marker {
            let overlayLine = CaptureMarkerLine(start: shapeStartPoint, end: shapeCurrentPoint)
            let localLine = localMarkerLine(fromOverlayMarkerLine: overlayLine)
            return CaptureAnnotation(
                kind: .marker,
                rect: localLine.boundingRect,
                style: currentStyle,
                markerLine: localLine
            )
        }

        if currentShapeKind == .mosaicStroke {
            let overlayStroke = CaptureMosaicStroke(
                points: mosaicDraftPoints.isEmpty ? [shapeStartPoint, shapeCurrentPoint] : mosaicDraftPoints
            )
            let localStroke = localMosaicStroke(fromOverlayStroke: overlayStroke)
            return CaptureAnnotation(
                kind: .mosaicStroke,
                rect: localStroke.boundingRect,
                style: currentStyle,
                mosaicStroke: localStroke,
                mosaicRedaction: mosaicRedaction(for: .mosaicStroke)
            )
        }

        if currentShapeKind == .mosaicRectangle {
            let rect = NSRect(
                x: min(shapeStartPoint.x, shapeCurrentPoint.x),
                y: min(shapeStartPoint.y, shapeCurrentPoint.y),
                width: abs(shapeCurrentPoint.x - shapeStartPoint.x),
                height: abs(shapeCurrentPoint.y - shapeStartPoint.y)
            )
            return CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: localAnnotationRect(from: rect),
                style: currentStyle,
                mosaicRedaction: mosaicRedaction(for: .mosaicRectangle)
            )
        }

        let rect = NSRect(
            x: min(shapeStartPoint.x, shapeCurrentPoint.x),
            y: min(shapeStartPoint.y, shapeCurrentPoint.y),
            width: abs(shapeCurrentPoint.x - shapeStartPoint.x),
            height: abs(shapeCurrentPoint.y - shapeStartPoint.y)
        )

        return CaptureAnnotation(kind: currentShapeKind, rect: localAnnotationRect(from: rect), style: currentStyle)
    }

    private func isUsableDraftAnnotation(_ annotation: CaptureAnnotation) -> Bool {
        if annotation.kind == .arrowLine, let arrowLine = annotation.arrowLine {
            return hypot(arrowLine.end.x - arrowLine.start.x, arrowLine.end.y - arrowLine.start.y) >= 8
        }
        if annotation.kind == .marker, let markerLine = annotation.markerLine {
            let length = hypot(markerLine.end.x - markerLine.start.x, markerLine.end.y - markerLine.start.y)
            return length == 0 || length >= 8
        }
        if annotation.kind == .brush {
            return (annotation.brushPath?.points.count ?? 0) >= 2
        }
        if annotation.kind == .mosaicStroke, let mosaicStroke = annotation.mosaicStroke {
            guard !mosaicStroke.points.isEmpty else {
                return false
            }
            if mosaicStroke.points.count == 1 {
                return true
            }
            let totalLength = zip(mosaicStroke.points, mosaicStroke.points.dropFirst()).reduce(CGFloat.zero) { partial, segment in
                partial + hypot(segment.1.x - segment.0.x, segment.1.y - segment.0.y)
            }
            return totalLength >= 2
        }

        return annotation.rect.width >= 8 && annotation.rect.height >= 8
    }

    private func updateHoverState(at point: NSPoint) {
        let previousWindowRect = hoveredWindowRect
        let previousTooltipText = hoveredTooltip?.text
        hoveredTooltip = tooltipTarget(at: point)

        if interactionMode == .selecting, selectionStartPoint == nil {
            if windowCandidates.isEmpty, let window {
                windowCandidates = WindowSelectionState.currentCandidates(desktopFrame: window.frame)
            }
            let targetRect = WindowSelectionState.bestHoverRect(
                at: point,
                candidates: windowCandidates,
                desktopFrame: bounds,
                currentProcessID: pid_t(NSRunningApplication.current.processIdentifier)
            )
            updateHoveredWindowRect(targetRect)
        } else if interactionMode != .selecting {
            updateHoveredWindowRect(nil)
        }

        if previousWindowRect != hoveredWindowRect || previousTooltipText != hoveredTooltip?.text {
            needsDisplay = true
        }
    }

    private func updateColorSampler(at point: NSPoint) {
        guard scrollCaptureOverlayState == .inactive else {
            clearColorSampler()
            return
        }
        if isEyedropperToolActive {
            let samplePoint = eyedropperSamplePoint(forMousePoint: point)
            guard SelectionToolbarState.shouldShowExplicitColorSampler(
                pointer: samplePoint,
                selectionRect: lockedSelectionRect
            ), !isToolbarOrPanelPoint(samplePoint) else {
                clearColorSampler()
                return
            }

            guard let color = sampleCurrentColor(at: samplePoint) else {
                clearColorSampler()
                return
            }

            let previousPoint = sampledPointerPoint
            sampledPointerPoint = samplePoint
            sampledColor = color
            invalidateColorSampler(from: previousPoint, to: samplePoint)
            return
        }

        if isEraserToolActive {
            clearColorSampler()
            return
        }

        guard configuration.allowsPassiveColorSampler else {
            clearColorSampler()
            return
        }

        guard SelectionToolbarState.shouldShowColorSampler(
            isShapeToolActive: isShapeToolActive,
            hasAnnotations: !annotations.isEmpty,
            pointer: point,
            selectionRect: colorSamplerSelectionRect
        ) else {
            clearColorSampler()
            return
        }

        guard let color = sampleColor(at: point) else {
            clearColorSampler()
            return
        }

        let previousPoint = sampledPointerPoint
        sampledPointerPoint = point
        sampledColor = color
        invalidateColorSampler(from: previousPoint, to: point)
    }

    private func clearColorSampler() {
        if sampledPointerPoint != nil || sampledColor != nil {
            let previousPoint = sampledPointerPoint
            sampledPointerPoint = nil
            sampledColor = nil
            invalidateColorSampler(from: previousPoint, to: nil)
        }
    }

    private func invalidateColorSampler(from previousPoint: NSPoint?, to nextPoint: NSPoint?) {
        if let previousPoint {
            setNeedsDisplay(colorSamplerInvalidationRect(at: previousPoint))
        }
        if let nextPoint {
            setNeedsDisplay(colorSamplerInvalidationRect(at: nextPoint))
        }
    }

    private func colorSamplerInvalidationRect(at point: NSPoint) -> NSRect {
        SelectionToolbarState.colorSamplerRect(
            size: colorSamplerSize,
            pointer: point,
            inside: safeLayoutBounds
        ).insetBy(dx: -8, dy: -8)
    }

    private func eyedropperSamplePoint(forMousePoint point: NSPoint) -> NSPoint {
        NSPoint(
            x: point.x + SelectionToolbarState.eyedropperSampleOffset.width,
            y: point.y + SelectionToolbarState.eyedropperSampleOffset.height
        )
    }

    private var eyedropperMeasurementLine: (start: NSPoint, end: NSPoint)? {
        guard let start = eyedropperMeasurementStartPoint,
              let end = eyedropperMeasurementEndPoint,
              eyedropperMeasurementPixelLength(from: start, to: end) > 0
        else {
            return nil
        }
        return (start, end)
    }

    private var eyedropperMeasurementLabel: String? {
        guard let line = eyedropperMeasurementLine else {
            return nil
        }
        return "\(eyedropperMeasurementPixelLength(from: line.start, to: line.end)) px"
    }

    private func handleEyedropperMeasurementClick(at point: NSPoint, modifierFlags: NSEvent.ModifierFlags) {
        if isEyedropperMeasurementInProgress, eyedropperMeasurementStartPoint != nil {
            finishEyedropperMeasurement(at: point, modifierFlags: modifierFlags)
        } else {
            beginEyedropperMeasurement(at: point)
        }
    }

    private func beginEyedropperMeasurement(at point: NSPoint) {
        guard isValidEyedropperMeasurementPoint(point) else {
            clearEyedropperMeasurement()
            return
        }
        let previousLine = eyedropperMeasurementLine
        eyedropperMeasurementStartPoint = point
        eyedropperMeasurementEndPoint = point
        isEyedropperMeasurementInProgress = true
        invalidateEyedropperMeasurement(from: previousLine, to: eyedropperMeasurementLine)
    }

    private func updateEyedropperMeasurement(to point: NSPoint, modifierFlags: NSEvent.ModifierFlags) {
        guard eyedropperMeasurementStartPoint != nil else {
            return
        }
        let previousLine = eyedropperMeasurementLine
        eyedropperMeasurementEndPoint = snappedEyedropperMeasurementEndPoint(rawEnd: point, modifierFlags: modifierFlags)
        invalidateEyedropperMeasurement(from: previousLine, to: eyedropperMeasurementLine)
    }

    private func finishEyedropperMeasurement(at point: NSPoint, modifierFlags: NSEvent.ModifierFlags) {
        guard let start = eyedropperMeasurementStartPoint else {
            return
        }
        let previousLine = eyedropperMeasurementLine
        let end = snappedEyedropperMeasurementEndPoint(rawEnd: point, modifierFlags: modifierFlags)
        eyedropperMeasurementEndPoint = end
        if eyedropperMeasurementPixelLength(from: start, to: end) == 0 {
            clearEyedropperMeasurement()
        } else {
            isEyedropperMeasurementInProgress = false
            invalidateEyedropperMeasurement(from: previousLine, to: eyedropperMeasurementLine)
        }
    }

    private func snappedEyedropperMeasurementEndPoint(
        rawEnd: NSPoint,
        modifierFlags: NSEvent.ModifierFlags
    ) -> NSPoint {
        guard let start = eyedropperMeasurementStartPoint else {
            return rawEnd
        }
        return SelectionToolbarState.snappedMarkerEndPoint(
            start: start,
            rawEnd: rawEnd,
            isShiftPressed: modifierFlags.contains(.shift)
        )
    }

    private func clearEyedropperMeasurement() {
        let previousLine = eyedropperMeasurementLine
        eyedropperMeasurementStartPoint = nil
        eyedropperMeasurementEndPoint = nil
        isEyedropperMeasurementInProgress = false
        invalidateEyedropperMeasurement(from: previousLine, to: nil)
    }

    private func invalidateEyedropperMeasurement(
        from previousLine: (start: NSPoint, end: NSPoint)?,
        to nextLine: (start: NSPoint, end: NSPoint)?
    ) {
        let rects = [previousLine, nextLine]
            .compactMap { $0 }
            .map(eyedropperMeasurementDrawingRect)
        guard let first = rects.first else {
            return
        }
        let invalidationRect = rects.dropFirst().reduce(first) { $0.union($1) }
#if DEBUG
        eyedropperMeasurementInvalidationRectForTesting = invalidationRect
#endif
        setNeedsDisplay(invalidationRect)
    }

    private func eyedropperMeasurementDrawingRect(
        for line: (start: NSPoint, end: NSPoint)
    ) -> NSRect {
        let lineRect = NSRect(
            x: min(line.start.x, line.end.x),
            y: min(line.start.y, line.end.y),
            width: abs(line.end.x - line.start.x),
            height: abs(line.end.y - line.start.y)
        ).insetBy(dx: -5, dy: -5)
        let label = "\(eyedropperMeasurementPixelLength(from: line.start, to: line.end)) px"
        return lineRect.union(eyedropperMeasurementLabelRect(for: line, label: label).insetBy(dx: -2, dy: -2))
    }

    private func isValidEyedropperMeasurementPoint(_ point: NSPoint) -> Bool {
        let samplePoint = eyedropperSamplePoint(forMousePoint: point)
        return SelectionToolbarState.shouldShowExplicitColorSampler(
            pointer: samplePoint,
            selectionRect: lockedSelectionRect
        ) && !isToolbarOrPanelPoint(samplePoint)
    }

    private func eyedropperMeasurementPixelLength(from start: NSPoint, to end: NSPoint) -> Int {
        Int(hypot(end.x - start.x, end.y - start.y).rounded())
    }

    private func updateHoveredWindowRect(_ targetRect: NSRect?) {
        guard hoveredWindowRect != targetRect else {
            return
        }

        let startRect = displayedWindowRect ?? hoveredWindowRect ?? targetRect
        hoveredWindowRect = targetRect
        hoverAnimationTimer?.invalidate()

        guard let startRect, let targetRect else {
            displayedWindowRect = targetRect
            needsDisplay = true
            return
        }

        let startTime = CACurrentMediaTime()
        let duration: TimeInterval = 0.14
        hoverAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(1, elapsed / duration)
            let eased = 1 - pow(1 - CGFloat(progress), 3)
            self.displayedWindowRect = self.interpolate(from: startRect, to: targetRect, progress: eased)
            self.needsDisplay = true

            if progress >= 1 {
                timer.invalidate()
                self.hoverAnimationTimer = nil
                self.displayedWindowRect = targetRect
            }
        }
        RunLoop.main.add(hoverAnimationTimer!, forMode: .common)
    }

    private func interpolate(from start: NSRect, to end: NSRect, progress: CGFloat) -> NSRect {
        NSRect(
            x: start.minX + (end.minX - start.minX) * progress,
            y: start.minY + (end.minY - start.minY) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }

    private func tooltipTarget(at point: NSPoint) -> (identifier: String, text: String, anchor: NSRect)? {
        guard lockedSelectionRect != nil, let selectionRect else {
            return nil
        }

        if let toolbar = mainToolbarRect(for: selectionRect) {
            for (button, rect) in toolbarButtonRects(in: toolbar) where rect.contains(point) {
                let identifier = tooltipIdentifier(for: button)
                if button == .scroll, scrollCaptureOverlayState != .inactive {
                    return (identifier, L10n(language: settings.language).text(.finishScrollCapture), rect)
                }
                guard let title = SelectionToolbarState.tooltipTitle(for: identifier) else {
                    return nil
                }
                return (identifier, title, rect)
            }
        }

        if configuration.showsSelectionMeasurementControl {
            let measurementLayout = measurementControlLayout(for: selectionRect)
            if measurementLayout.cornerStyle.contains(point),
               let title = SelectionToolbarState.tooltipTitle(for: "cornerStyle") {
                return ("cornerStyle", title, measurementLayout.cornerStyle)
            }
            if measurementLayout.aspectRatio.contains(point) {
                let identifier = isSelectionAspectRatioLocked ? "aspectRatioLockedOn" : "aspectRatioLockedOff"
                if let title = SelectionToolbarState.tooltipTitle(for: identifier) {
                    return (identifier, title, measurementLayout.aspectRatio)
                }
            }
            if measurementLayout.refresh.contains(point),
               let title = SelectionToolbarState.tooltipTitle(for: "refreshCapture") {
                return ("refreshCapture", title, measurementLayout.refresh)
            }
        }

        guard let optionsRect = optionsToolbarRect else {
            return nil
        }
        let layout = optionsToolbarLayout(in: optionsRect)

        for (index, rect) in layout.strokeWidths.enumerated() where rect.contains(point) {
            let identifiers = ["strokeWidthThin", "strokeWidthMedium", "strokeWidthThick"]
            let identifier = identifiers[index]
            return (identifier, SelectionToolbarState.tooltipTitle(for: identifier) ?? "线条粗细", rect)
        }

        if let fillRect = layout.fillToggle,
           fillRect.contains(point),
           let title = SelectionToolbarState.tooltipTitle(for: "fill") {
            return ("fill", title, fillRect)
        }

        if let rectangleMode = layout.rectangleMode {
            let rectangleButton = shapeModeBackgroundRect(for: rectangleMode)
            let identifier = optionsToolbarMode == .mosaic ? "mosaicRectangle" : "shapeRectangle"
            if rectangleButton.contains(point), let title = SelectionToolbarState.tooltipTitle(for: identifier) {
                return (identifier, title, rectangleButton)
            }
        }

        if let ellipseButton = layout.ellipseMode,
           ellipseButton.contains(point),
           let title = SelectionToolbarState.tooltipTitle(for: "shapeEllipse") {
            return ("shapeEllipse", title, ellipseButton)
        }

        if optionsToolbarMode == .mosaic {
            let redactionTypeRect = optionButtonBackgroundRect(for: SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsRect))
            if redactionTypeRect.contains(point) {
                let identifier = mosaicRedactionType == .gaussianBlur ? "mosaicBlur" : "mosaicPixel"
                if let title = SelectionToolbarState.tooltipTitle(for: identifier) {
                    return (identifier, title, redactionTypeRect)
                }
            }
        }

        if optionsToolbarMode == .eraser {
            let eraserTargets: [(NSRect?, String)] = [
                (layout.eraserPointMode, "eraserPoint"),
                (layout.eraserRectangleMode, "eraserRectangle"),
                (layout.eraserClearAll, "eraserClearAll"),
            ]
            for (rect, identifier) in eraserTargets {
                guard let rect else {
                    continue
                }
                let button = optionButtonBackgroundRect(for: rect)
                if button.contains(point), let title = SelectionToolbarState.tooltipTitle(for: identifier) {
                    return (identifier, title, button)
                }
            }
        }

        if optionsToolbarMode == .text {
            if layout.textBold.contains(point), let title = SelectionToolbarState.tooltipTitle(for: "textBold") {
                return ("textBold", title, layout.textBold)
            }
            if layout.textItalic.contains(point), let title = SelectionToolbarState.tooltipTitle(for: "textItalic") {
                return ("textItalic", title, layout.textItalic)
            }
            if layout.textOutline.contains(point), let title = SelectionToolbarState.tooltipTitle(for: "textOutline") {
                return ("textOutline", title, layout.textOutline)
            }
        }

        if SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode),
           layout.strokeStyle.contains(point),
           let title = SelectionToolbarState.tooltipTitle(for: "strokeStyle") {
            return ("strokeStyle", title, layout.strokeStyle)
        }

        if let startArrowType = layout.startArrowType, startArrowType.contains(point) {
            return ("startArrowType", SelectionToolbarState.tooltipTitle(for: "startArrowType") ?? "开始箭头", startArrowType)
        }

        if let endArrowType = layout.endArrowType, endArrowType.contains(point) {
            return ("endArrowType", SelectionToolbarState.tooltipTitle(for: "endArrowType") ?? "结束箭头", endArrowType)
        }

        for (index, rect) in layout.colorSwatches.enumerated() where rect.insetBy(dx: -4, dy: -4).contains(point) {
            if index == visiblePaletteCount, let title = SelectionToolbarState.tooltipTitle(for: "customColor") {
                return ("customColor", title, rect)
            }
            return nil
        }

        return nil
    }

    private func tooltipIdentifier(for button: ToolbarButton) -> String {
        switch button {
        case .rectangle:
            return "rectangle"
        case .polyline:
            return "polyline"
        case .pen:
            return "pen"
        case .marker:
            return "marker"
        case .eyedropper:
            return "eyedropper"
        case .mosaic:
            return "mosaic"
        case .text:
            return "text"
        case .number:
            return "number"
        case .magnifier:
            return "magnifier"
        case .eraser:
            return "eraser"
        case .undo:
            return "undo"
        case .redo:
            return "redo"
        case .cancel:
            return "cancel"
        case .pin:
            return "pin"
        case .save:
            return "save"
        case .copy:
            return "copy"
        case .scroll:
            return "scroll"
        case .finishEditing:
            return "finishEditing"
        }
    }

    private func handleAnnotatingMouseDown(at point: NSPoint, clickCount: Int = 1) {
        if activeTextDropdown != nil, handleTextDropdownClick(at: point) {
            return
        }
        if activeNumberDropdown, handleOptionsClick(at: point) {
            return
        }
        if activeMagnifierZoomDropdown, handleOptionsClick(at: point) {
            return
        }

        if startToolbarDragIfPossible(at: point) {
            return
        }

        if handleMeasurementControlClick(at: point) {
            return
        }

        if let button = toolbarButton(at: point) {
            guard isToolbarButtonEnabled(button) else {
                return
            }
            perform(button)
            return
        }

        if handleCornerRadiusPanelClick(at: point)
            || handleStrokeStyleMenuClick(at: point)
            || handleArrowTypeMenuClick(at: point)
            || handleOptionsClick(at: point) {
            return
        }

        guard let lockedSelectionRect else {
            return
        }

        if handleEraserMouseDown(at: point) {
            return
        }

        if isNumberToolActive, handleNumberToolMouseDown(at: point, clickCount: clickCount) {
            return
        }

        if textDeleteHandleHitTarget(at: point) != nil {
            _ = deleteSelectedAnnotation()
            needsDisplay = true
            return
        }

        if let mosaicHit = mosaicRectangleRotationHitTarget(at: point) {
            NSCursor.xxsnapMosaicRectangleRotationHandle.set()
            selectAnnotation(at: mosaicHit)
            rotatingMosaicRectangleStartPointerAngle = angle(from: mosaicRectangleCenter(for: annotations[mosaicHit]), to: point)
            rotatingMosaicRectangleStartAnnotationAngle = annotations[mosaicHit].rotationAngle
            captureMosaicGeometryEditingStartState()
            interactionMode = .rotatingMosaicRectangle
            NSLog(
                "xxsnap annotation rotate begin index=%ld kind=%@ point=(%.0f, %.0f) angle=%.3f",
                mosaicHit,
                String(describing: annotations[mosaicHit].kind),
                point.x,
                point.y,
                annotations[mosaicHit].rotationAngle
            )
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
            needsDisplay = true
            return
        }

        if isTextToolActive,
           textAwareResizeHandle(at: point) == nil,
           textAnnotationIndex(at: point) == nil,
           let selectionResizeHandle = selectionResizeHandle(at: point) {
            beginSelectionResize(handle: selectionResizeHandle)
            return
        }

        if isTextToolActive {
            if handleTextToolMouseDown(at: point, selectionRect: lockedSelectionRect.standardized) {
                return
            }
        }

        if shouldPreferMosaicDrawingBeforeAnnotationHitTesting(at: point) {
            beginShapeDrawing(at: point)
            return
        }

        if shouldPreferMosaicDrawingOutsideSelection(at: point) {
            beginShapeDrawing(at: point)
            return
        }

        if let markerHit = markerRotationHitTarget(at: point) {
            NSCursor.resizeUpDown.set()
            selectAnnotation(at: markerHit.index)
            activeMarkerLineHandle = markerHit.target
            resizingMarkerLineStart = overlayMarkerLine(fromLocalMarkerLine: annotations[markerHit.index].markerLine)
            interactionMode = .resizingMarkerLine
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
            needsDisplay = true
            return
        }

        if let brushHit = brushRotationHitTarget(at: point) {
            NSCursor.resizeUpDown.set()
            selectAnnotation(at: brushHit.index)
            activeBrushRotationHandle = brushHit.target
            rotatingBrushStartPath = overlayBrushPath(fromLocalBrushPath: annotations[brushHit.index].brushPath)
            interactionMode = .rotatingBrush
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
            needsDisplay = true
            return
        }

        if let arrowHit = arrowLineHitTarget(at: point) {
            NSCursor.xxsnapMove.set()
            let canEditArrowGeometry = activeToolCanEdit(annotationKind: annotations[arrowHit.index].kind)
            selectAnnotation(at: arrowHit.index)
            switch arrowHit.target {
            case .start, .end, .control:
                if canEditArrowGeometry {
                    activeArrowLineHandle = arrowHit.target
                    resizingArrowLineStart = overlayArrowLine(fromLocalArrowLine: annotations[arrowHit.index].arrowLine)
                    interactionMode = .resizingArrowLine
                } else {
                    beginAnnotationMove(at: arrowHit.index, point: point)
                }
            case .body:
                beginAnnotationMove(at: arrowHit.index, point: point)
            case .none:
                break
            }
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
            needsDisplay = true
            return
        }

        if isMagnifierToolActive,
           textAwareResizeHandle(at: point) == nil,
           annotationIndexForBorder(at: point) == nil,
           selectionResizeHandle(at: point) == nil {
            beginShapeDrawing(at: point)
            return
        }

        switch SelectionToolbarState.annotatingMouseDownTarget(
            shapeResizeHandle: textAwareResizeHandle(at: point)?.toolbarStateHandle,
            isAnnotationBorder: annotationIndexForBorder(at: point) != nil,
            selectionResizeHandle: selectionResizeHandle(at: point),
            selectionMoveEligible: shouldStartSelectionMove(at: point)
        ) {
        case .shapeResize(let handle):
            beginAnnotationResize(with: ShapeResizeHandle(toolbarStateHandle: handle))
            return
        case .annotationMove:
            guard let hitIndex = annotationIndexForBorder(at: point) else {
                break
            }
            NSCursor.xxsnapMove.set()
            selectAnnotation(at: hitIndex)
            beginAnnotationMove(at: hitIndex, point: point)
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            needsDisplay = true
            return
        case .selectionResize(let handle):
            beginSelectionResize(handle: handle)
            return
        case .selectionMove:
            startSelectionMoveIfPossible(at: point)
            needsDisplay = true
            return
        case .none:
            break
        }

        if isShapeToolActive || isMagnifierToolActive {
            beginShapeDrawing(at: point)
            return
        }

        selectedAnnotationIndex = nil
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        needsDisplay = true
    }

    private func handleEraserMouseDown(at point: NSPoint) -> Bool {
        guard isEraserToolActive, !isToolbarOrPanelPoint(point) else {
            return false
        }

        commitCurrentTextEdit()
        commitNumberEditingIfNeeded()
        if eraserMode == .rectangle {
            let clampedPoint = clamp(point, to: bounds)
            eraserRectangleStartPoint = clampedPoint
            eraserRectangleCurrentPoint = clampedPoint
            interactionMode = .drawingEraserRectangle
            selectedAnnotationIndex = nil
            needsDisplay = true
            return true
        }

        if let index = eraserAnnotationIndex(at: point) {
            _ = deleteAnnotation(at: index)
        }
        interactionMode = .erasingAnnotation
        needsDisplay = true
        return true
    }

    private func handleNumberToolMouseDown(at point: NSPoint, clickCount: Int) -> Bool {
        guard lockedSelectionRect != nil, !isToolbarOrPanelPoint(point) else {
            return false
        }

        if let hit = numberHandleHitTarget(at: point) {
            handleNumberHandleMouseDown(hit)
            return true
        }
        if disabledNumberAdjustmentHandleContains(point) {
            return true
        }

        if let index = numberAnnotationIndex(at: point) {
            selectAnnotation(at: index)
            if clickCount >= 2 {
                beginNumberEditing(at: index)
                return true
            }
            beginAnnotationMove(at: index, point: point)
            return true
        }

        createNumberMark(at: point)
        return true
    }

    private func handleNumberHandleMouseDown(_ hit: NumberHandleHit) {
        selectAnnotation(at: hit.index)
        switch hit.kind {
        case .delete:
            _ = deleteSelectedAnnotation()
        case .resize:
            beginAnnotationResize(with: .bottomRight)
        case .increment:
            adjustNumberAnnotation(at: hit.index, delta: 1)
        case .decrement:
            adjustNumberAnnotation(at: hit.index, delta: -1)
        case .reset:
            resetNumberAnnotation(at: hit.index)
        }
    }

    private func createNumberMark(at point: NSPoint) {
        var style = currentStyle
        style.textSize = clampedNumberSize(style.textSize)
        let rect = CaptureAnnotationRenderer.numberMarkRect(centeredAt: point, fontSize: style.textSize)
        var annotation = CaptureAnnotation(
            kind: .numberSequence,
            rect: localAnnotationRect(from: rect),
            style: style,
            numberMarkType: currentNumberMarkType
        )
        let assignedNumberSequenceIndex = currentNumberMarkType == .number ? nextNumberSequenceIndex() : nil
        annotation.numberSequenceIndex = assignedNumberSequenceIndex
        annotation.numberSequenceIsManual = currentNumberMarkType == .number &&
            isNumberSequenceManualModeActive(in: currentNumberSequenceGroupID)
        annotation.numberSequenceGroupID = currentNumberMarkType == .number ? currentNumberSequenceGroupID : nil
        annotations.append(annotation)
        if currentNumberMarkType == .number,
           let assignedNumberSequenceIndex,
           nextNumberSequenceIndexAfterReset != nil {
            nextNumberSequenceIndexAfterReset = min(999, assignedNumberSequenceIndex + 1)
        }
        recordAnnotationAdd(at: annotations.index(before: annotations.endIndex))
        selectedAnnotationIndex = annotations.indices.last
        interactionMode = .placingNumberMark
        revealedNumberControlsIndex = nil
        selectedNumberAnnotationCanFollowTypeDropdown = true
        numberStyle = style
        clearRedoAnnotationHistory()
        invalidateCursorRectsAndRefresh(at: point)
        needsDisplay = true
    }

    private func nextNumberSequenceIndex(excluding excludedIndex: Int? = nil) -> Int {
        if excludedIndex == nil, let nextNumberSequenceIndexAfterReset {
            return nextNumberSequenceIndexAfterReset
        }
        return numericNumberAnnotationIndices()
            .filter { $0 != excludedIndex }
            .filter { annotations[$0].numberSequenceGroupID == currentNumberSequenceGroupID }
            .compactMap { annotations[$0].numberSequenceIndex }
            .max()
            .map { min(999, $0 + 1) } ?? 1
    }

    private func renumberNumberSequenceAnnotations(in groupID: UUID? = nil) {
        var next = 1
        for index in annotations.indices where annotations[index].kind == .numberSequence {
            if (annotations[index].numberMarkType == .number || annotations[index].numberMarkType == nil) &&
                annotations[index].numberSequenceGroupID == groupID {
                annotations[index].numberSequenceIndex = next
                annotations[index].numberSequenceIsManual = false
                next += 1
            } else if annotations[index].numberMarkType != .number && annotations[index].numberMarkType != nil {
                annotations[index].numberSequenceIndex = nil
                annotations[index].numberSequenceIsManual = false
            }
        }
    }

    private func numberSequenceGroupIDs(in annotations: [CaptureAnnotation]) -> Set<UUID?> {
        var groupIDs = Set<UUID?>()
        for annotation in annotations
            where annotation.kind == .numberSequence &&
            (annotation.numberMarkType == .number || annotation.numberMarkType == nil) {
            groupIDs.insert(annotation.numberSequenceGroupID)
        }
        return groupIDs
    }

    private func isNumberSequenceManualModeActive(in groupID: UUID?) -> Bool {
        annotations.contains {
            $0.kind == .numberSequence &&
                ($0.numberMarkType == .number || $0.numberMarkType == nil) &&
                $0.numberSequenceGroupID == groupID &&
                $0.numberSequenceIsManual
        }
    }

    private func markNumberSequenceManualMode(in groupID: UUID?) {
        for index in annotations.indices where annotations[index].kind == .numberSequence {
            if (annotations[index].numberMarkType == .number || annotations[index].numberMarkType == nil) &&
                annotations[index].numberSequenceGroupID == groupID {
                annotations[index].numberSequenceIsManual = true
            }
        }
    }

    private func numericNumberAnnotationIndices() -> [Int] {
        annotations.indices.filter {
            annotations[$0].kind == .numberSequence &&
                (annotations[$0].numberMarkType == .number || annotations[$0].numberMarkType == nil)
        }.sorted {
            (annotations[$0].numberSequenceIndex ?? Int.max) < (annotations[$1].numberSequenceIndex ?? Int.max)
        }
    }

    private func canAdjustNumberAnnotation(delta: Int) -> Bool {
        guard let selectedAnnotationIndex,
              annotations.indices.contains(selectedAnnotationIndex),
              annotations[selectedAnnotationIndex].kind == .numberSequence,
              annotations[selectedAnnotationIndex].numberMarkType == .number || annotations[selectedAnnotationIndex].numberMarkType == nil
        else {
            return false
        }
        let value = annotations[selectedAnnotationIndex].numberSequenceIndex ?? 1
        if !isNumberSequenceManualModeActive(in: annotations[selectedAnnotationIndex].numberSequenceGroupID) {
            return numberAnnotationIndex(
                with: value + delta,
                in: annotations[selectedAnnotationIndex].numberSequenceGroupID,
                excluding: selectedAnnotationIndex
            ) != nil
        }
        return (1...999).contains(value + delta)
    }

    private func adjustNumberAnnotation(at index: Int, delta: Int) {
        guard annotations.indices.contains(index),
              annotations[index].kind == .numberSequence,
              annotations[index].numberMarkType == .number || annotations[index].numberMarkType == nil
        else {
            return
        }

        let value = annotations[index].numberSequenceIndex ?? 1
        let nextValue = min(999, max(1, value + delta))
        let isManualSequence = isNumberSequenceManualModeActive(in: annotations[index].numberSequenceGroupID)
        if let adjacentIndex = numberAnnotationIndex(with: nextValue, in: annotations[index].numberSequenceGroupID, excluding: index) {
            annotations[adjacentIndex].numberSequenceIndex = value
        } else if !isManualSequence {
            return
        }
        annotations[index].numberSequenceIndex = nextValue
        selectedAnnotationIndex = index
        clearRedoAnnotationHistory()
        needsDisplay = true
    }

    private func numberAnnotationIndex(with value: Int, in groupID: UUID?, excluding excludedIndex: Int) -> Int? {
        annotations.indices.first { index in
            index != excludedIndex &&
                annotations[index].kind == .numberSequence &&
                (annotations[index].numberMarkType == .number || annotations[index].numberMarkType == nil) &&
                annotations[index].numberSequenceGroupID == groupID &&
                annotations[index].numberSequenceIndex == value
        }
    }

    private func resetNumberAnnotation(at index: Int) {
        guard annotations.indices.contains(index),
              annotations[index].kind == .numberSequence,
              (annotations[index].numberSequenceIndex ?? 1) > 1
        else {
            return
        }
        let newGroupID = UUID()
        annotations[index].numberSequenceIndex = 1
        annotations[index].numberSequenceIsManual = false
        annotations[index].numberSequenceGroupID = newGroupID
        currentNumberSequenceGroupID = newGroupID
        nextNumberSequenceIndexAfterReset = 2
        selectedAnnotationIndex = index
        clearRedoAnnotationHistory()
        needsDisplay = true
    }

    private func beginNumberEditing(at index: Int) {
        guard annotations.indices.contains(index),
              annotations[index].kind == .numberSequence,
              annotations[index].numberMarkType == .number || annotations[index].numberMarkType == nil
        else {
            return
        }
        editingNumberAnnotationIndex = index
        let value = min(999, max(1, annotations[index].numberSequenceIndex ?? 1))
        editingNumberDraft = "\(value)"
        editingNumberHasDraft = true
        editingNumberDraftWasEdited = false
        editingNumberCaretIndex = editingNumberDraft.count
        selectedAnnotationIndex = index
        revealedNumberControlsIndex = index
        startNumberCaretBlink()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func commitNumberEditing() {
        guard let editingNumberAnnotationIndex,
              annotations.indices.contains(editingNumberAnnotationIndex),
              annotations[editingNumberAnnotationIndex].kind == .numberSequence
        else {
            clearNumberEditing()
            return
        }
        if editingNumberDraftWasEdited {
            markNumberSequenceManualMode(in: annotations[editingNumberAnnotationIndex].numberSequenceGroupID)
            if let value = Int(editingNumberDraft), value > 0 {
                annotations[editingNumberAnnotationIndex].numberSequenceIndex = min(999, max(1, value))
            } else if editingNumberDraft.isEmpty {
                annotations[editingNumberAnnotationIndex].numberSequenceIndex = 1
            }
        }
        clearNumberEditing()
        clearRedoAnnotationHistory()
        needsDisplay = true
    }

    private func clearNumberEditing() {
        editingNumberAnnotationIndex = nil
        editingNumberDraft = ""
        editingNumberHasDraft = false
        editingNumberDraftWasEdited = false
        editingNumberCaretIndex = 0
        stopNumberCaretBlink()
    }

    private func commitNumberEditingIfNeeded() {
        guard editingNumberAnnotationIndex != nil else {
            return
        }
        commitNumberEditing()
    }

    private func commitNumberEditingIfPointerLeaves(at point: NSPoint) {
        guard let editingNumberAnnotationIndex,
              annotations.indices.contains(editingNumberAnnotationIndex),
              annotations[editingNumberAnnotationIndex].kind == .numberSequence
        else {
            return
        }
        if numberControlsRegionContains(point, for: annotations[editingNumberAnnotationIndex]) {
            return
        }
        commitNumberEditing()
    }

    private func startNumberCaretBlink() {
        numberCaretBlinkTimer?.invalidate()
        numberCaretVisible = true
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.editingNumberAnnotationIndex != nil else {
                return
            }
            self.numberCaretVisible.toggle()
            self.needsDisplay = true
        }
        numberCaretBlinkTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopNumberCaretBlink() {
        numberCaretBlinkTimer?.invalidate()
        numberCaretBlinkTimer = nil
        numberCaretVisible = false
    }

    private func showNumberCaretNow() {
        numberCaretVisible = true
        needsDisplay = true
    }

    private func handleNumberEditingKeyDown(_ event: NSEvent) -> Bool {
        guard let editingNumberAnnotationIndex,
              annotations.indices.contains(editingNumberAnnotationIndex),
              annotations[editingNumberAnnotationIndex].kind == .numberSequence
        else {
            return false
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            commitNumberEditing()
            return true
        }
        if event.keyCode == 53 {
            clearNumberEditing()
            needsDisplay = true
            return true
        }
        if event.keyCode == 123 {
            editingNumberCaretIndex = max(0, editingNumberCaretIndex - 1)
            showNumberCaretNow()
            return true
        }
        if event.keyCode == 124 {
            editingNumberCaretIndex = min(editingNumberDraft.count, editingNumberCaretIndex + 1)
            showNumberCaretNow()
            return true
        }
        if event.keyCode == 51 {
            editingNumberHasDraft = true
            editingNumberDraftWasEdited = true
            if editingNumberCaretIndex > 0 {
                let removeIndex = editingNumberDraft.index(editingNumberDraft.startIndex, offsetBy: editingNumberCaretIndex - 1)
                editingNumberDraft.remove(at: removeIndex)
                editingNumberCaretIndex -= 1
            }
            markNumberSequenceManualMode(in: annotations[editingNumberAnnotationIndex].numberSequenceGroupID)
            showNumberCaretNow()
            return true
        }
        guard let characters = event.charactersIgnoringModifiers, characters.allSatisfy({ $0.isNumber }) else {
            return true
        }
        var nextDraft = editingNumberDraft
        let insertIndex = nextDraft.index(nextDraft.startIndex, offsetBy: min(editingNumberCaretIndex, nextDraft.count))
        nextDraft.insert(contentsOf: characters, at: insertIndex)
        if nextDraft.count > 3 {
            showNumberCaretNow()
            return true
        }
        if let value = Int(nextDraft) {
            let clamped = min(999, max(1, value))
            let clampedText = "\(clamped)"
            editingNumberHasDraft = true
            editingNumberDraftWasEdited = true
            editingNumberDraft = clampedText
            editingNumberCaretIndex = clampedText == nextDraft
                ? min(clampedText.count, editingNumberCaretIndex + characters.count)
                : clampedText.count
            markNumberSequenceManualMode(in: annotations[editingNumberAnnotationIndex].numberSequenceGroupID)
            annotations[editingNumberAnnotationIndex].numberSequenceIndex = clamped
            clearRedoAnnotationHistory()
            showNumberCaretNow()
        }
        return true
    }

    private func beginShapeDrawing(at point: NSPoint) {
        clearPendingTextEdit()
        selectedAnnotationIndex = nil
        shapeStartPoint = point
        shapeCurrentPoint = point
        brushDraftPoints = currentShapeKind == .brush ? [point] : []
        mosaicDraftPoints = currentShapeKind == .mosaicStroke ? [point] : []
        interactionMode = .drawingShape
        NSLog("xxsnap overlay drawing started point=(%.0f, %.0f)", point.x, point.y)
    }

    private func beginAnnotationResize(with handle: ShapeResizeHandle) {
        activeResizeHandle = handle
        resizingAnnotationStartRect = selectedAnnotation.map { overlayRect(fromLocalAnnotationRect: $0.rect) }
        resizingAnnotationStartStyle = selectedAnnotation?.style
        captureMosaicGeometryEditingStartState()
        interactionMode = .resizingShape
        NSLog(
            "xxsnap annotation resize begin handle=%@ selected=%@ rect=%@",
            String(describing: handle.toolbarStateHandle),
            selectedAnnotationIndex.map { "\($0)" } ?? "none",
            resizingAnnotationStartRect.map { NSStringFromRect($0) } ?? "nil"
        )
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
    }

    private func shouldPreferMosaicDrawingOutsideSelection(at point: NSPoint) -> Bool {
        guard
            isMosaicDrawingToolActive,
            let lockedSelectionRect = lockedSelectionRect?.standardized
        else {
            return false
        }

        guard !isToolbarOrPanelPoint(point) else {
            return false
        }

        if SelectionToolbarState.selectionResizeHandle(at: point, in: lockedSelectionRect) != nil {
            return false
        }

        return !lockedSelectionRect.contains(point)
    }

    private var isMosaicDrawingToolActive: Bool {
        isShapeToolActive && (currentShapeKind == .mosaicStroke || currentShapeKind == .mosaicRectangle)
    }

    private func shouldPreferMosaicDrawingBeforeAnnotationHitTesting(at point: NSPoint) -> Bool {
        guard isMosaicDrawingToolActive else {
            return false
        }

        guard !isToolbarOrPanelPoint(point) else {
            return false
        }

        if let lockedSelectionRect = lockedSelectionRect?.standardized,
           SelectionToolbarState.selectionResizeHandle(at: point, in: lockedSelectionRect) != nil {
            return false
        }

        if textAwareResizeHandle(at: point) != nil {
            return false
        }

        if let hitIndex = annotationIndexForBorder(at: point),
           annotations.indices.contains(hitIndex),
           isMosaicAnnotation(annotations[hitIndex]) {
            return false
        }

        return true
    }

    private func handleMeasurementControlClick(at point: NSPoint) -> Bool {
        guard configuration.showsSelectionMeasurementControl else {
            return false
        }
        guard let lockedSelectionRect else {
            return false
        }

        let layout = measurementControlLayout(for: lockedSelectionRect)
        guard let control = SelectionToolbarState.measurementControl(at: point, in: layout) else {
            return false
        }

        switch control {
        case .cornerStyle:
            selectionCornerRadius = selectionCornerRadius > 0 ? 0 : defaultSelectionCornerRadius
        case .aspectRatioLock:
            isSelectionAspectRatioLocked.toggle()
        case .refresh:
            refreshSelectionBackground()
        }
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        hoveredTooltip = tooltipTarget(at: point)
        needsDisplay = true
        return true
    }

    private func handleTextToolMouseDown(at point: NSPoint, selectionRect: NSRect) -> Bool {
        commitCurrentTextEdit()
        NSLog(
            "xxsnap text mouseDown point=(%.0f, %.0f) insideSelection=%@ existingTextHit=%@",
            point.x,
            point.y,
            selectionRect.contains(point) ? "yes" : "no",
            textAnnotationIndex(at: point).map { "\($0)" } ?? "none"
        )

        if let textHit = textAnnotationIndex(at: point) {
            selectAnnotation(at: textHit)
            pendingTextEditAnnotationIndex = textHit
            pendingTextEditStartPoint = point
            pendingTextEditResizeHandle = textResizeHandle(at: point, annotation: annotations[textHit])
            pendingTextEditShouldBeginEditing = shouldBeginTextEditingFromClick(at: point, annotation: annotations[textHit])
            NSLog(
                "xxsnap text existing selected index=%ld rect=%@ pendingDrag=yes pendingResize=%@ beginEditing=%@",
                textHit,
                NSStringFromRect(overlayRect(fromLocalAnnotationRect: annotations[textHit].rect)),
                pendingTextEditResizeHandle.map { String(describing: $0.toolbarStateHandle) } ?? "none",
                pendingTextEditShouldBeginEditing ? "yes" : "no"
            )
            needsDisplay = true
            return true
        }

        let textRect = textAnnotationRect(anchoredAt: point, inside: selectionRect)
        var style = currentStyle
        style.strokeWidth = 0
        style.strokePattern = .solid
        style.fillEnabled = false
        style.textSize = style.textSize > 0 ? style.textSize : Self.defaultTextSize
        currentStyle = style
        let annotation = CaptureAnnotation(
            kind: .text,
            rect: localAnnotationRect(from: textRect),
            style: style,
            text: ""
        )
        annotations.append(annotation)
        recordAnnotationAdd(at: annotations.index(before: annotations.endIndex))
        clearRedoAnnotationHistory()
        beginTextEditing(at: annotations.index(before: annotations.endIndex), draftCreated: true)
        NSLog(
            "xxsnap text draft created index=%ld rect=(%.0f, %.0f, %.0f, %.0f)",
            annotations.index(before: annotations.endIndex),
            textRect.minX,
            textRect.minY,
            textRect.width,
            textRect.height
        )
        needsDisplay = true
        return true
    }

    private func beginTextEditing(at index: Int, draftCreated: Bool, insertionPoint: NSPoint? = nil) {
        guard annotations.indices.contains(index), annotations[index].kind == .text else {
            editingTextAnnotationIndex = nil
            textDraftCreatedDuringCurrentEdit = false
            clearPendingTextEdit()
            return
        }

        clearPendingTextEdit()
        shouldRestoreWindowLevelAfterForwardedTextDrag = false
        selectedAnnotationIndex = index
        editingTextAnnotationIndex = index
        textDraftCreatedDuringCurrentEdit = draftCreated
        isTextToolActive = true
        isEyedropperToolActive = false
        clearEyedropperMeasurement()
        isShapeToolActive = false
        activeShapeKind = nil
        showsCornerRadiusPanel = false
        showsStrokeStyleMenu = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        currentStyle = annotations[index].style
        installTextEditor(for: index)
        window?.level = .floating
        if window?.isKeyWindow != true {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
        let acceptedFirstResponder = window?.makeFirstResponder(textEditor ?? self) ?? false
        NSLog(
            "xxsnap text beginEditing index=%ld draft=%@ appActive=%@ keyWindow=%@ firstResponderAccepted=%@ firstResponder=%@",
            index,
            draftCreated ? "yes" : "no",
            NSApp.isActive ? "yes" : "no",
            window?.isKeyWindow == true ? "yes" : "no",
            acceptedFirstResponder ? "yes" : "no",
            window?.firstResponder === textEditor ? "textEditor" : (window?.firstResponder === self ? "overlay" : "\(String(describing: window?.firstResponder))")
        )
        if let insertionPoint {
            setTextEditorInsertionPoint(at: insertionPoint)
        }
    }

    private func installTextEditor(for index: Int) {
        removeTextEditor()
        guard annotations.indices.contains(index), annotations[index].kind == .text else {
            return
        }

        let editor = SelectionTextEditor(frame: .zero)
        editor.delegate = self
        editor.textInputDidChange = { [weak self] in
            self?.syncEditingTextFromEditor()
        }
        editor.overlayMouseDown = { [weak self] event in
            self?.forwardTextEditorMouseDown(event) ?? false
        }
        editor.overlayMouseDragged = { [weak self] event in
            self?.forwardTextEditorMouseDragged(event) ?? false
        }
        editor.overlayMouseUp = { [weak self] event in
            self?.forwardTextEditorMouseUp(event) ?? false
        }
        editor.string = annotations[index].text ?? ""
        editor.isEditable = true
        editor.isSelectable = true
        editor.isRichText = false
        editor.importsGraphics = false
        editor.drawsBackground = false
        editor.backgroundColor = .clear
        editor.alphaValue = 1
        editor.insertionPointColor = .clear
        editor.textContainerInset = NSSize(width: CaptureAnnotationRenderer.textHorizontalPadding, height: 0)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.minSize = NSSize(
            width: CaptureAnnotationRenderer.textHorizontalPadding * 2 + textCaretAnnotationWidth,
            height: 16
        )
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        applyTextEditorStyle(editor, style: annotations[index].style)
        applyTextEditorFrame(editor, for: annotations[index])
        addSubview(editor)
        textEditor = editor
        editor.moveInsertionPointToEnd()
    }

    private func setTextEditorInsertionPoint(at overlayPoint: NSPoint) {
        guard
            let textEditor,
            let editingTextAnnotationIndex,
            annotations.indices.contains(editingTextAnnotationIndex)
        else {
            return
        }

        let editorPoint = textEditorPoint(for: overlayPoint, annotation: annotations[editingTextAnnotationIndex])
        let insertionIndex = textEditorInsertionIndex(at: editorPoint, in: textEditor)
        textEditor.setSelectedRange(NSRange(location: insertionIndex, length: 0))
        NSLog(
            "xxsnap text editor caret setFromClick point=(%.0f, %.0f) editorPoint=(%.0f, %.0f) location=%ld",
            overlayPoint.x,
            overlayPoint.y,
            editorPoint.x,
            editorPoint.y,
            insertionIndex
        )
    }

    private func textEditorInsertionIndex(at editorPoint: NSPoint, in textEditor: NSTextView) -> Int {
        let textLength = (textEditor.string as NSString).length
        guard textLength > 0,
              let textContainer = textEditor.textContainer,
              let layoutManager = textEditor.layoutManager
        else {
            return 0
        }

        layoutManager.ensureLayout(for: textContainer)
        guard layoutManager.numberOfGlyphs > 0 else {
            return 0
        }

        let containerOrigin = textEditor.textContainerOrigin
        let containerPoint = NSPoint(
            x: editorPoint.x - containerOrigin.x,
            y: editorPoint.y - containerOrigin.y
        )
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: &fraction
        )
        let clampedGlyphIndex = min(max(0, glyphIndex), layoutManager.numberOfGlyphs - 1)
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: clampedGlyphIndex, length: 1),
            in: textContainer
        )
        let characterIndex = layoutManager.characterIndexForGlyph(at: clampedGlyphIndex)
        if containerPoint.x >= glyphRect.midX || fraction >= 0.5 {
            return min(textLength, characterIndex + 1)
        }
        return max(0, characterIndex)
    }

    private func removeTextEditor() {
        removeTextEditor(restoreWindowLevel: true)
    }

    private func removeTextEditor(restoreWindowLevel: Bool) {
        textEditor?.delegate = nil
        if let textEditor = textEditor as? SelectionTextEditor {
            textEditor.textInputDidChange = nil
        }
        textEditor?.removeFromSuperview()
        textEditor = nil
        _ = restoreWindowLevel
    }

    private func finishForwardedTextDragIfNeeded() {
        guard shouldRestoreWindowLevelAfterForwardedTextDrag else {
            return
        }

        let previousLevel = window?.level.rawValue ?? -1
        shouldRestoreWindowLevelAfterForwardedTextDrag = false
        if !isEditingTextAnnotation, textEditor != nil {
            removeTextEditor(restoreWindowLevel: false)
        }
        NSLog(
            "xxsnap text drag finishForwarded previousLevel=%ld currentLevel=%ld editing=%@",
            previousLevel,
            window?.level.rawValue ?? -1,
            isEditingTextAnnotation ? "yes" : "no"
        )
    }

    private func forwardTextEditorMouseDown(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        NSLog(
            "xxsnap text editor forwarding mouseDown point=(%.0f, %.0f) mode=%@ textTool=%@ editing=%@ hit=%@ selectionRect=%@",
            point.x,
            point.y,
            String(describing: interactionMode),
            isTextToolActive ? "yes" : "no",
            editingTextAnnotationIndex.map { "\($0)" } ?? "none",
            textAnnotationIndex(at: point).map { "\($0)" } ?? "none",
            lockedSelectionRect.map { NSStringFromRect($0.standardized) } ?? "nil"
        )
        guard interactionMode == .annotating, isTextToolActive else {
            return false
        }

        syncEditingTextFromEditor()
        if let textHit = textAnnotationIndex(at: point) {
            selectedAnnotationIndex = textHit
            currentStyle = annotations[textHit].style
            rememberCurrentStyleForActiveTool()
            pendingTextEditAnnotationIndex = textHit
            pendingTextEditStartPoint = point
            pendingTextEditResizeHandle = textResizeHandle(at: point, annotation: annotations[textHit])
            pendingTextEditShouldBeginEditing = shouldBeginTextEditingFromClick(at: point, annotation: annotations[textHit])
            shouldRestoreWindowLevelAfterForwardedTextDrag = textEditor != nil
            NSLog(
                "xxsnap text editor prepared existing drag index=%ld rect=%@ pendingResize=%@ beginEditing=%@ editorAlive=%@",
                textHit,
                NSStringFromRect(overlayRect(fromLocalAnnotationRect: annotations[textHit].rect)),
                pendingTextEditResizeHandle.map { String(describing: $0.toolbarStateHandle) } ?? "none",
                pendingTextEditShouldBeginEditing ? "yes" : "no",
                textEditor != nil ? "yes" : "no"
            )
            needsDisplay = true
            return true
        }

        commitCurrentTextEdit(restoreWindowLevel: false)
        handleAnnotatingMouseDown(at: point)
        needsDisplay = true
        return true
    }

    private func forwardTextEditorMouseDragged(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        NSLog(
            "xxsnap text editor forwarding mouseDragged point=(%.0f, %.0f) mode=%@ pendingText=%@",
            point.x,
            point.y,
            String(describing: interactionMode),
            pendingTextEditAnnotationIndex.map { "\($0)" } ?? "none"
        )
        mouseDragged(with: event)
        return true
    }

    private func forwardTextEditorMouseUp(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        NSLog(
            "xxsnap text editor forwarding mouseUp point=(%.0f, %.0f) mode=%@",
            point.x,
            point.y,
            String(describing: interactionMode)
        )
        mouseUp(with: event)
        return true
    }

    private func applyTextEditorStyle(_ editor: NSTextView, style: CaptureAnnotationStyle) {
        var attributes = CaptureAnnotationRenderer.textAttributes(style: style)
        let clearColor = NSColor.clear
        editor.font = attributes[.font] as? NSFont
        editor.textColor = clearColor
        editor.insertionPointColor = clearColor
        attributes[.foregroundColor] = clearColor
        attributes[.strokeColor] = clearColor
        attributes[.strokeWidth] = 0
        editor.typingAttributes = attributes
        if let textStorage = editor.textStorage, textStorage.length > 0 {
            textStorage.setAttributes(attributes, range: NSRange(location: 0, length: textStorage.length))
        }
        (editor as? SelectionTextEditor)?.makeTextStorageTransparent()
        NSLog(
            "xxsnap text editor style applied color=%@ outline=%@ size=%.0f font=%@",
            SelectionToolbarState.colorSamplerHexString(for: style.strokeColor),
            style.textOutlineEnabled ? "yes" : "no",
            style.textSize,
            style.textFontFamily ?? "system"
        )
    }

    private func layoutTextEditorForCurrentAnnotation() {
        guard let textEditor,
              let editingTextAnnotationIndex,
              annotations.indices.contains(editingTextAnnotationIndex)
        else {
            return
        }

        applyTextEditorFrame(textEditor, for: annotations[editingTextAnnotationIndex])
    }

    private func applyTextEditorFrame(_ textEditor: NSTextView, for annotation: CaptureAnnotation) {
        textEditor.frameCenterRotation = 0
        textEditor.frame = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
        textEditor.frameCenterRotation = annotation.rotationAngle * 180 / .pi
    }

    private func textEditorPoint(for overlayPoint: NSPoint, annotation: CaptureAnnotation) -> NSPoint {
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let unrotatedPoint = rotatedPoint(overlayPoint, around: center, angle: -annotation.rotationAngle)
        return NSPoint(
            x: unrotatedPoint.x - rect.minX,
            y: rect.height - (unrotatedPoint.y - rect.minY)
        )
    }

    private func syncEditingTextFromEditor() {
        guard let textEditor,
              let editingTextAnnotationIndex = validEditingTextAnnotationIndex()
        else {
            return
        }

        let text = textEditor.string
        if annotations[editingTextAnnotationIndex].text != text {
            updateEditingText(text)
        } else {
            layoutTextEditorForCurrentAnnotation()
        }
        NSLog(
            "xxsnap text editor synced characters=%ld totalLength=%ld caret=%ld marked=(%ld,%ld)",
            text.count,
            annotations[editingTextAnnotationIndex].text?.count ?? 0,
            textEditor.selectedRange().location,
            textEditor.markedRange().location,
            textEditor.markedRange().length
        )
    }

    private func handleTextEditingKeyDown(_ event: NSEvent) -> Bool {
        guard let editingTextAnnotationIndex = validEditingTextAnnotationIndex() else {
            return false
        }

        NSLog(
            "xxsnap text keyDown keyCode=%hu charsLength=%ld command=%@ control=%@ editingIndex=%ld",
            event.keyCode,
            event.characters?.count ?? 0,
            event.modifierFlags.contains(.command) ? "yes" : "no",
            event.modifierFlags.contains(.control) ? "yes" : "no",
            editingTextAnnotationIndex
        )

        guard !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control)
        else {
            return false
        }

        if event.keyCode == 53 {
            cancelCurrentTextEdit()
            return true
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            return insertTextIntoCurrentAnnotation("\n")
        }

        if event.keyCode == 51 {
            deleteBackwardInCurrentTextAnnotation()
            return true
        }

        if handleTextNavigationKeyDown(event) {
            return true
        }

        let previousText = annotations[editingTextAnnotationIndex].text ?? ""
        interpretKeyEvents([event])
        if !isEditingTextAnnotation {
            return true
        }
        let currentText = annotations.indices.contains(editingTextAnnotationIndex)
            ? (annotations[editingTextAnnotationIndex].text ?? "")
            : ""
        if currentText != previousText {
            return true
        }

        if let characters = event.characters, !characters.isEmpty {
            return insertTextIntoCurrentAnnotation(characters)
        }
        return true
    }

    private func handleTextNavigationKeyDown(_ event: NSEvent) -> Bool {
        guard let textEditor else {
            return false
        }

        let command: ((Any?) -> Void)?
        switch event.keyCode {
        case 123:
            command = textEditor.moveLeft(_:)
        case 124:
            command = textEditor.moveRight(_:)
        case 125:
            command = textEditor.moveDown(_:)
        case 126:
            command = textEditor.moveUp(_:)
        default:
            command = nil
        }
        guard let command else {
            return false
        }

        _ = window?.makeFirstResponder(textEditor)
        command(nil)
        needsDisplay = true
        return true
    }

    private var isEditingTextAnnotation: Bool {
        validEditingTextAnnotationIndex() != nil
    }

    private func validEditingTextAnnotationIndex() -> Int? {
        guard let editingTextAnnotationIndex,
              annotations.indices.contains(editingTextAnnotationIndex),
              annotations[editingTextAnnotationIndex].kind == .text
        else {
            self.editingTextAnnotationIndex = nil
            textDraftCreatedDuringCurrentEdit = false
            return nil
        }
        return editingTextAnnotationIndex
    }

    @discardableResult
    private func insertTextIntoCurrentAnnotation(_ insertString: Any) -> Bool {
        guard let editingTextAnnotationIndex = validEditingTextAnnotationIndex() else {
            return false
        }

        let rawText: String
        if let attributedString = insertString as? NSAttributedString {
            rawText = attributedString.string
        } else if let string = insertString as? String {
            rawText = string
        } else {
            rawText = String(describing: insertString)
        }

        var printableCharacters = ""
        for character in rawText {
            if character.isNewline {
                printableCharacters.append("\n")
            } else if String(character).rangeOfCharacter(from: .controlCharacters) == nil {
                printableCharacters.append(character)
            }
        }
        guard !printableCharacters.isEmpty else {
            return true
        }

        if let textEditor {
            if let textEditor = textEditor as? SelectionTextEditor {
                textEditor.insertCommittedText(printableCharacters, source: "overlay")
            } else {
                let textLength = (textEditor.string as NSString).length
                let selectedRange = textEditor.selectedRange()
                let replacementRange = NSMaxRange(selectedRange) <= textLength
                    ? selectedRange
                    : NSRange(location: textLength, length: 0)
                textEditor.insertText(printableCharacters, replacementRange: replacementRange)
            }
            syncEditingTextFromEditor()
            return true
        }

        updateEditingText((annotations[editingTextAnnotationIndex].text ?? "") + printableCharacters)
        NSLog(
            "xxsnap text inserted characters=%ld totalLength=%ld",
            printableCharacters.count,
            annotations[editingTextAnnotationIndex].text?.count ?? 0
        )
        return true
    }

    private func deleteBackwardInCurrentTextAnnotation() {
        guard let editingTextAnnotationIndex = validEditingTextAnnotationIndex() else {
            return
        }

        if let textEditor {
            let textLength = (textEditor.string as NSString).length
            let selectedRange = textEditor.selectedRange()
            let replacementRange: NSRange
            if selectedRange.length > 0, NSMaxRange(selectedRange) <= textLength {
                replacementRange = selectedRange
            } else if selectedRange.location > 0, selectedRange.location <= textLength {
                replacementRange = NSRange(location: selectedRange.location - 1, length: 1)
            } else {
                replacementRange = NSRange(location: 0, length: 0)
            }

            guard replacementRange.length > 0 else {
                if textLength == 0, textDraftCreatedDuringCurrentEdit {
                    discardEditingTextAnnotation()
                }
                return
            }

            textEditor.textStorage?.replaceCharacters(in: replacementRange, with: "")
            (textEditor as? SelectionTextEditor)?.makeTextStorageTransparent()
            textEditor.setSelectedRange(NSRange(location: replacementRange.location, length: 0))
            syncEditingTextFromEditor()
            if textEditor.string.isEmpty, textDraftCreatedDuringCurrentEdit {
                discardEditingTextAnnotation()
            }
            needsDisplay = true
            return
        }

        var text = annotations[editingTextAnnotationIndex].text ?? ""
        if text.isEmpty {
            discardEditingTextAnnotation()
            return
        }

        text.removeLast()
        updateEditingText(text)
        if text.isEmpty, textDraftCreatedDuringCurrentEdit {
            discardEditingTextAnnotation()
        }
        needsDisplay = true
    }

    private func cancelCurrentTextEdit() {
        guard let editingTextAnnotationIndex = validEditingTextAnnotationIndex() else {
            return
        }

        if (annotations[editingTextAnnotationIndex].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            discardEditingTextAnnotation()
        } else {
            self.editingTextAnnotationIndex = nil
            textDraftCreatedDuringCurrentEdit = false
        }
        needsDisplay = true
    }

    private static func isAnnotationDeleteKey(_ keyCode: UInt16) -> Bool {
        keyCode == 51 || keyCode == 117
    }

    private func updateEditingText(_ text: String) {
        guard let editingTextAnnotationIndex,
              annotations.indices.contains(editingTextAnnotationIndex),
              annotations[editingTextAnnotationIndex].kind == .text
        else {
            return
        }

        let updatedSize = textAnnotationSize(
            text: text,
            style: annotations[editingTextAnnotationIndex].style
        )

        annotations[editingTextAnnotationIndex].text = text
        annotations[editingTextAnnotationIndex].rect.size = updatedSize
        clearRedoAnnotationHistory()
        layoutTextEditorForCurrentAnnotation()
        needsDisplay = true
    }

    private func prepareEditingTextForForwardedDrag(at index: Int) -> Bool {
        syncEditingTextFromEditor()
        guard editingTextAnnotationIndex == index,
              annotations.indices.contains(index),
              annotations[index].kind == .text
        else {
            return annotations.indices.contains(index)
        }

        let text = annotations[index].text ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            discardEditingTextAnnotation()
            return false
        }

        selectedAnnotationIndex = index
        editingTextAnnotationIndex = nil
        textDraftCreatedDuringCurrentEdit = false
        textEditor?.alphaValue = 0
        textEditor?.isEditable = false
        clearRedoAnnotationHistory()
        needsDisplay = true
        return true
    }

    private func commitCurrentTextEdit(restoreWindowLevel: Bool = true) {
        syncEditingTextFromEditor()
        guard let editingTextAnnotationIndex,
              annotations.indices.contains(editingTextAnnotationIndex),
              annotations[editingTextAnnotationIndex].kind == .text
        else {
            self.editingTextAnnotationIndex = nil
            textDraftCreatedDuringCurrentEdit = false
            removeTextEditor(restoreWindowLevel: restoreWindowLevel)
            return
        }

#if DEBUG
        NSLog(
            "xxsnap text commit index=%ld rect=%@ characters=%ld",
            editingTextAnnotationIndex,
            NSStringFromRect(overlayRect(fromLocalAnnotationRect: annotations[editingTextAnnotationIndex].rect)),
            annotations[editingTextAnnotationIndex].text?.count ?? 0
        )
#endif

        let text = annotations[editingTextAnnotationIndex].text ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            discardEditingTextAnnotation()
            return
        }

        selectedAnnotationIndex = editingTextAnnotationIndex
        self.editingTextAnnotationIndex = nil
        textDraftCreatedDuringCurrentEdit = false
        clearPendingTextEdit()
        removeTextEditor(restoreWindowLevel: restoreWindowLevel)
        clearRedoAnnotationHistory()
        needsDisplay = true
    }

    private func discardEditingTextAnnotation() {
        guard let editingTextAnnotationIndex else {
            return
        }

        if annotations.indices.contains(editingTextAnnotationIndex),
           textDraftCreatedDuringCurrentEdit
                || (annotations[editingTextAnnotationIndex].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotations.remove(at: editingTextAnnotationIndex)
        }
        self.editingTextAnnotationIndex = nil
        textDraftCreatedDuringCurrentEdit = false
        clearPendingTextEdit()
        removeTextEditor()
        selectedAnnotationIndex = nil
        clearRedoAnnotationHistory()
    }

    private func clearPendingTextEdit() {
        pendingTextEditAnnotationIndex = nil
        pendingTextEditStartPoint = nil
        pendingTextEditResizeHandle = nil
        pendingTextEditShouldBeginEditing = true
    }

    private func textAnnotationRect(anchoredAt point: NSPoint, inside _: NSRect) -> NSRect {
        let horizontalPadding = CaptureAnnotationRenderer.textHorizontalPadding
        let size = textAnnotationSize(text: "", style: currentStyle)
        let verticalOffset = size.height / 2
        return NSRect(
            x: point.x - horizontalPadding,
            y: point.y - verticalOffset,
            width: size.width,
            height: size.height
        )
    }

    private func textAnnotationSize(text: String, style: CaptureAnnotationStyle) -> NSSize {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lineHeight = CaptureAnnotationRenderer.textLineHeight(style: style)
        let horizontalPadding = CaptureAnnotationRenderer.textHorizontalPadding * 2
        guard !trimmedText.isEmpty else {
            return NSSize(width: horizontalPadding + textCaretAnnotationWidth, height: lineHeight)
        }

        let attributedText = NSAttributedString(
            string: text,
            attributes: CaptureAnnotationRenderer.textAttributes(style: style)
        )
        let measured = attributedText.boundingRect(
            with: NSSize(width: 10_000, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return NSSize(
            width: horizontalPadding + max(textCaretAnnotationWidth, ceil(measured.width)),
            height: max(lineHeight, ceil(measured.height))
        )
    }

    private func refreshSelectionBackground() {
        guard !isRefreshingSelectionBackground, let refreshHandler else {
            return
        }

        isRefreshingSelectionBackground = true
        startRefreshAnimation()
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.isRefreshingSelectionBackground = false
                self.finishRefreshAnimation()
                self.needsDisplay = true
            }

            do {
                if let image = try await refreshHandler() {
                    self.updateBackgroundImage(image)
                }
            } catch {
                NSLog("xxsnap refresh background failed: \(error.localizedDescription)")
            }
        }
    }

    private func startRefreshAnimation() {
        refreshAnimationStartDate = Date()
        refreshAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.needsDisplay = true
        }
        refreshAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        needsDisplay = true
    }

    private func finishRefreshAnimation() {
        refreshAnimationTimer?.invalidate()
        refreshAnimationTimer = nil
        refreshAnimationStartDate = nil
        needsDisplay = true
    }

    private var refreshAnimationDegrees: CGFloat {
        guard let refreshAnimationStartDate else {
            return 0
        }
        let elapsed = Date().timeIntervalSince(refreshAnimationStartDate)
        return CGFloat(elapsed / 1.4).truncatingRemainder(dividingBy: 1) * 360
    }

    private func updateBackgroundImage(_ image: NSImage?) {
        backgroundImage = image
        if let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            backgroundBitmap = NSBitmapImageRep(cgImage: cgImage)
        } else {
            backgroundBitmap = nil
        }
        backgroundLuminanceCache.removeAll()
        resetMosaicPreviewCaches()
    }

    private func draftEndPoint(rawEnd: NSPoint, modifierFlags: NSEvent.ModifierFlags) -> NSPoint {
        guard let shapeStartPoint else {
            return rawEnd
        }

        if isMagnifierToolActive, modifierFlags.contains(.shift) {
            return equalSidePoint(start: shapeStartPoint, rawEnd: rawEnd)
        }

        if currentShapeKind == .marker {
            return SelectionToolbarState.snappedMarkerEndPoint(
                start: shapeStartPoint,
                rawEnd: rawEnd,
                isShiftPressed: modifierFlags.contains(.shift)
            )
        }

        if currentShapeKind == .mosaicStroke, modifierFlags.contains(.shift) {
            return axisLockedPoint(start: shapeStartPoint, rawEnd: rawEnd)
        }

        if (currentShapeKind == .rectangle || currentShapeKind == .ellipse), modifierFlags.contains(.shift) {
            return equalSidePoint(start: shapeStartPoint, rawEnd: rawEnd)
        }

        return rawEnd
    }

    private func equalSidePoint(start: NSPoint, rawEnd: NSPoint) -> NSPoint {
        let deltaX = rawEnd.x - start.x
        let deltaY = rawEnd.y - start.y
        let side = max(abs(deltaX), abs(deltaY))
        return NSPoint(
            x: start.x + signedDistance(side, matching: deltaX),
            y: start.y + signedDistance(side, matching: deltaY)
        )
    }

    private func signedDistance(_ distance: CGFloat, matching delta: CGFloat) -> CGFloat {
        if delta < 0 {
            return -distance
        }
        return distance
    }

    private func mosaicRedaction(for kind: CaptureAnnotationKind) -> CaptureMosaicRedaction {
        _ = kind
        return CaptureMosaicRedaction(
            type: mosaicRedactionType,
            value: mosaicRedactionValues[mosaicRedactionType] ?? SelectionToolbarState.mosaicDefaultRedactionValue(for: mosaicRedactionType)
        )
    }

    private func localMosaicStroke(fromOverlayStroke stroke: CaptureMosaicStroke) -> CaptureMosaicStroke {
        guard let lockedSelectionRect else {
            return stroke
        }
        return localMosaicStroke(fromOverlayStroke: stroke, selectionRect: lockedSelectionRect)
    }

    private func localMosaicStroke(fromOverlayStroke stroke: CaptureMosaicStroke, selectionRect: NSRect) -> CaptureMosaicStroke {
        CaptureMosaicStroke(points: stroke.points.map { localPoint(fromOverlayPoint: $0, selectionRect: selectionRect) })
    }

    private func beginSelectionResize(handle: SelectionToolbarState.OverlayResizeHandle) {
        guard !hasDamagedAnnotations else {
            return
        }
        activeSelectionResizeHandle = handle
        resizingSelectionStartRect = lockedSelectionRect?.standardized
        resizingSelectionStartAnnotationRects = annotations.map { overlayRect(fromLocalAnnotationRect: $0.rect) }
        resizingSelectionStartAnnotations = annotations
        interactionMode = .resizingSelection
        selectedAnnotationIndex = nil
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        needsDisplay = true
    }

    private func beginAnnotationMove(at index: Int, point: NSPoint) {
        clearPendingTextEdit()
        movingAnnotationStartRect = overlayRect(fromLocalAnnotationRect: annotations[index].rect)
        movingAnnotationStartArrowLine = overlayArrowLine(fromLocalArrowLine: annotations[index].arrowLine)
        movingAnnotationStartBrushPath = overlayBrushPath(fromLocalBrushPath: annotations[index].brushPath)
        movingAnnotationStartMarkerLine = overlayMarkerLine(fromLocalMarkerLine: annotations[index].markerLine)
        movingAnnotationStartMosaicStroke = overlayMosaicStroke(fromLocalMosaicStroke: annotations[index].mosaicStroke)
        captureMosaicGeometryEditingStartState()
        movingAnnotationOffset = NSPoint(
            x: point.x - (movingAnnotationStartRect?.minX ?? point.x),
            y: point.y - (movingAnnotationStartRect?.minY ?? point.y)
        )
        interactionMode = .movingShape
        NSLog(
            "xxsnap annotation move begin index=%ld kind=%@ point=(%.0f, %.0f) rect=%@ offset=(%.0f, %.0f)",
            index,
            String(describing: annotations[index].kind),
            point.x,
            point.y,
            movingAnnotationStartRect.map { NSStringFromRect($0) } ?? "nil",
            movingAnnotationOffset.x,
            movingAnnotationOffset.y
        )
    }

    private func perform(_ button: ToolbarButton) {
        NSLog(
            "xxsnap toolbar perform button=%@ before text=%@ eyedropper=%@ shape=%@ activeShape=%@",
            String(describing: button),
            isTextToolActive ? "yes" : "no",
            isEyedropperToolActive ? "yes" : "no",
            isShapeToolActive ? "yes" : "no",
            activeShapeKind.map { String(describing: $0) } ?? "nil"
        )
        switch button {
        case .rectangle:
            toggleShapeTool(.rectangle)
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
        case .polyline:
            toggleShapeTool(.arrowLine)
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
        case .pen:
            toggleShapeTool(.brush)
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
        case .marker:
            toggleShapeTool(.marker)
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
        case .eyedropper:
            toggleEyedropperTool()
        case .mosaic:
            toggleShapeTool(.mosaicStroke)
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
        case .text:
            toggleTextTool()
        case .number:
            toggleNumberTool()
        case .magnifier:
            toggleMagnifierTool()
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
        case .eraser:
            toggleEraserTool()
        case .undo:
            undoLastAnnotation()
        case .redo:
            redoLastAnnotation()
        case .copy:
            finish(action: .copy)
        case .save:
            finish(action: .save)
        case .cancel:
            selectionDidFinish?(nil)
        case .pin:
            finish(action: .pin)
        case .scroll:
            beginScrollCapture()
        case .finishEditing:
            finish(action: .finishEditing)
        }

        NSLog(
            "xxsnap toolbar performed button=%@ after text=%@ eyedropper=%@ shape=%@ activeShape=%@ cursor=%@",
            String(describing: button),
            isTextToolActive ? "yes" : "no",
            isEyedropperToolActive ? "yes" : "no",
            isShapeToolActive ? "yes" : "no",
            activeShapeKind.map { String(describing: $0) } ?? "nil",
            String(describing: cursorStyle(at: currentMousePointForLogging()))
        )
        needsDisplay = true
    }

    private func currentMousePointForLogging() -> NSPoint {
        guard let window else {
            return .zero
        }
        return convert(window.mouseLocationOutsideOfEventStream, from: nil)
    }

    private func clearEraserRectangleState() {
        eraserRectangleStartPoint = nil
        eraserRectangleCurrentPoint = nil
        if interactionMode == .drawingEraserRectangle {
            interactionMode = .annotating
        }
    }

    private func toggleEyedropperTool() {
        commitCurrentTextEdit()
        clearPendingTextEdit()
        closeTextDropdown()
        closeMagnifierZoomDropdown()
        if isEyedropperToolActive {
            isEyedropperToolActive = false
            activeNumberDropdown = false
            clearEyedropperMeasurement()
            invalidateCursorRectsAndRefresh()
            return
        }

        rememberCurrentStyleForActiveTool()
        isEyedropperToolActive = true
        isEraserToolActive = false
        clearEraserRectangleState()
        clearEyedropperMeasurement()
        isTextToolActive = false
        isNumberToolActive = false
        isMagnifierToolActive = false
        activeNumberDropdown = false
        isShapeToolActive = false
        activeShapeKind = nil
        selectedAnnotationIndex = nil
        showsCornerRadiusPanel = false
        showsStrokeStyleMenu = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        shapeStartPoint = nil
        shapeCurrentPoint = nil
        brushDraftPoints.removeAll()
        mosaicDraftPoints.removeAll()
        invalidateCursorRectsAndRefresh()
    }

    private func toggleEraserTool() {
        commitCurrentTextEdit()
        clearPendingTextEdit()
        closeTextDropdown()
        closeMagnifierZoomDropdown()
        if isEraserToolActive {
            isEraserToolActive = false
            clearEraserRectangleState()
            selectedAnnotationIndex = nil
            invalidateCursorRectsAndRefresh()
            needsDisplay = true
            return
        }

        activateEraserTool()
    }

    private func activateEraserTool() {
        commitCurrentTextEdit()
        clearPendingTextEdit()
        closeTextDropdown()
        closeMagnifierZoomDropdown()
        rememberCurrentStyleForActiveTool()
        isEraserToolActive = true
        eraserMode = .point
        clearEraserRectangleState()
        isShapeToolActive = false
        activeShapeKind = nil
        isTextToolActive = false
        isNumberToolActive = false
        isMagnifierToolActive = false
        isEyedropperToolActive = false
        activeNumberDropdown = false
        clearEyedropperMeasurement()
        clearColorSampler()
        selectedAnnotationIndex = nil
        showsCornerRadiusPanel = false
        showsStrokeStyleMenu = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        shapeStartPoint = nil
        shapeCurrentPoint = nil
        brushDraftPoints.removeAll()
        mosaicDraftPoints.removeAll()
        invalidateCursorRectsAndRefresh()
        needsDisplay = true
    }

    private func toggleTextTool() {
        commitCurrentTextEdit()
        clearPendingTextEdit()
        if isTextToolActive {
            closeTextDropdown()
            closeMagnifierZoomDropdown()
            isTextToolActive = false
            activeNumberDropdown = false
            selectedAnnotationIndex = nil
            invalidateCursorRectsAndRefresh()
            return
        }

        activateTextTool()
    }

    private func activateTextTool() {
        commitCurrentTextEdit()
        clearPendingTextEdit()
        closeTextDropdown()
        closeMagnifierZoomDropdown()
        rememberCurrentStyleForActiveTool()
        isTextToolActive = true
        isEraserToolActive = false
        clearEraserRectangleState()
        isEyedropperToolActive = false
        clearEyedropperMeasurement()
        isNumberToolActive = false
        isMagnifierToolActive = false
        activeNumberDropdown = false
        isShapeToolActive = false
        activeShapeKind = nil
        selectedAnnotationIndex = nil
        showsCornerRadiusPanel = false
        showsStrokeStyleMenu = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        shapeStartPoint = nil
        shapeCurrentPoint = nil
        brushDraftPoints.removeAll()
        mosaicDraftPoints.removeAll()
        if textStyle.textSize > 0 {
            currentStyle = textStyle
        }
        currentStyle.textSize = currentStyle.textSize > 0 ? currentStyle.textSize : Self.defaultTextSize
        currentStyle.textOutlineEnabled = true
        rememberCurrentStyleForActiveTool()
        NSLog(
            "xxsnap text tool activated size=%.0f outline=%@ font=%@",
            currentStyle.textSize,
            currentStyle.textOutlineEnabled ? "yes" : "no",
            currentStyle.textFontFamily ?? "system"
        )
        invalidateCursorRectsAndRefresh()
        needsDisplay = true
    }

    private func toggleNumberTool() {
        commitCurrentTextEdit()
        clearPendingTextEdit()
        closeTextDropdown()
        closeMagnifierZoomDropdown()
        if isNumberToolActive {
            isNumberToolActive = false
            activeNumberDropdown = false
            selectedAnnotationIndex = nil
            invalidateCursorRectsAndRefresh()
            needsDisplay = true
            return
        }

        activateNumberTool()
    }

    private func activateNumberTool() {
        commitCurrentTextEdit()
        clearPendingTextEdit()
        closeTextDropdown()
        closeMagnifierZoomDropdown()
        rememberCurrentStyleForActiveTool()
        isNumberToolActive = true
        isEraserToolActive = false
        clearEraserRectangleState()
        isTextToolActive = false
        isEyedropperToolActive = false
        clearEyedropperMeasurement()
        isMagnifierToolActive = false
        isShapeToolActive = false
        activeShapeKind = nil
        selectedAnnotationIndex = nil
        currentStyle = numberStyle
        currentStyle.textSize = clampedNumberSize(currentStyle.textSize)
        showsCornerRadiusPanel = false
        showsStrokeStyleMenu = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        shapeStartPoint = nil
        shapeCurrentPoint = nil
        brushDraftPoints.removeAll()
        mosaicDraftPoints.removeAll()
        invalidateCursorRectsAndRefresh()
        needsDisplay = true
    }

    private func clampedNumberSize(_ size: CGFloat) -> CGFloat {
        let minimum = SelectionToolbarState.numberSizeValues.first ?? 3
        let maximum = SelectionToolbarState.numberSizeValues.last ?? 72
        return max(minimum, min(maximum, size))
    }

    private func toggleMagnifierTool() {
        commitCurrentTextEdit()
        clearPendingTextEdit()
        closeTextDropdown()
        if isMagnifierToolActive {
            closeMagnifierZoomDropdown()
            isMagnifierToolActive = false
            selectedAnnotationIndex = nil
            invalidateCursorRectsAndRefresh()
            needsDisplay = true
            return
        }

        activateMagnifierTool()
    }

    private func activateMagnifierTool() {
        commitCurrentTextEdit()
        clearPendingTextEdit()
        closeTextDropdown()
        closeMagnifierZoomDropdown()
        rememberCurrentStyleForActiveTool()
        isMagnifierToolActive = true
        isEraserToolActive = false
        clearEraserRectangleState()
        isTextToolActive = false
        isNumberToolActive = false
        isEyedropperToolActive = false
        clearEyedropperMeasurement()
        activeNumberDropdown = false
        isShapeToolActive = false
        activeShapeKind = nil
        selectedAnnotationIndex = nil
        currentStyle = magnifierStyle
        currentStyle.strokePattern = .solid
        showsCornerRadiusPanel = false
        showsStrokeStyleMenu = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        shapeStartPoint = nil
        shapeCurrentPoint = nil
        brushDraftPoints.removeAll()
        mosaicDraftPoints.removeAll()
        invalidateCursorRectsAndRefresh()
        needsDisplay = true
    }

    private func toggleShapeTool(_ shape: CaptureAnnotationKind) {
        commitCurrentTextEdit()
        clearPendingTextEdit()
        closeTextDropdown()
        closeMagnifierZoomDropdown()
        rememberCurrentStyleForActiveTool()
        isEraserToolActive = false
        clearEraserRectangleState()
        isEyedropperToolActive = false
        clearEyedropperMeasurement()
        isTextToolActive = false
        isNumberToolActive = false
        isMagnifierToolActive = false
        activeNumberDropdown = false
        activeShapeKind = activeShapeKind == shape ? nil : shape
        isShapeToolActive = activeShapeKind != nil
        if let activeShapeKind {
            currentShapeKind = activeShapeKind
            if activeShapeKind == .arrowLine {
                let activation = SelectionToolbarState.arrowLineActivationState(
                    currentStyle: nonMarkerStyle,
                    paletteColors: colors
                )
                currentStyle = activation.style
                currentStartArrowType = activation.startArrowType
                currentEndArrowType = activation.endArrowType
                showsCornerRadiusPanel = false
            } else if activeShapeKind == .brush {
                currentStyle = SelectionToolbarState.brushActivationStyle(
                    currentStyle: nonMarkerStyle,
                    paletteColors: colors
                )
                showsCornerRadiusPanel = false
            } else if activeShapeKind == .marker {
                currentStyle = markerStyle
                showsCornerRadiusPanel = false
            } else if activeShapeKind == .mosaicStroke || activeShapeKind == .mosaicRectangle {
                mosaicRedactionType = .pixelMosaic
                currentStyle = SelectionToolbarState.mosaicActivationStyle(
                    currentStyle: nonMarkerStyle,
                    paletteColors: colors,
                    strokeWidth: SelectionToolbarState.strokeWidthValues(for: .mosaic)[mosaicDotIndex]
                )
                showsCornerRadiusPanel = false
            } else {
                currentStyle = SelectionToolbarState.styleForPrimaryShapeToolActivation(
                    currentStyle: nonMarkerStyle,
                    paletteColors: colors
                )
            }
            rememberCurrentStyleForActiveTool()
            if activeShapeKind != .arrowLine {
                showsStartArrowTypeMenu = false
                showsEndArrowTypeMenu = false
            }
            if !SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode) {
                showsStrokeStyleMenu = false
            }
            currentStyle.strokePattern = .solid
            rememberCurrentStyleForActiveTool()
        } else {
            selectedAnnotationIndex = nil
            showsCornerRadiusPanel = false
            showsStrokeStyleMenu = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
        }
        clearSelectedAnnotationIfNeededForActiveTool()
        shapeStartPoint = nil
        shapeCurrentPoint = nil
        brushDraftPoints.removeAll()
        mosaicDraftPoints.removeAll()
        invalidateCursorRectsAndRefresh()
    }

    private func activateShapeTool(_ shape: CaptureAnnotationKind) {
        commitCurrentTextEdit()
        clearPendingTextEdit()
        closeTextDropdown()
        closeMagnifierZoomDropdown()
        rememberCurrentStyleForActiveTool()
        isEraserToolActive = false
        clearEraserRectangleState()
        isEyedropperToolActive = false
        clearEyedropperMeasurement()
        isTextToolActive = false
        isNumberToolActive = false
        isMagnifierToolActive = false
        activeNumberDropdown = false
        activeShapeKind = shape
        currentShapeKind = shape
        isShapeToolActive = true
        if shape == .arrowLine {
            let activation = SelectionToolbarState.arrowLineActivationState(
                currentStyle: nonMarkerStyle,
                paletteColors: colors
            )
            currentStyle = activation.style
            currentStartArrowType = activation.startArrowType
            currentEndArrowType = activation.endArrowType
            showsCornerRadiusPanel = false
        } else if shape == .brush {
            currentStyle = SelectionToolbarState.brushActivationStyle(
                currentStyle: nonMarkerStyle,
                paletteColors: colors
            )
            showsCornerRadiusPanel = false
        } else if shape == .marker {
            currentStyle = markerStyle
            showsCornerRadiusPanel = false
        } else if shape == .mosaicStroke || shape == .mosaicRectangle {
            currentStyle = SelectionToolbarState.mosaicActivationStyle(
                currentStyle: nonMarkerStyle,
                paletteColors: colors,
                strokeWidth: SelectionToolbarState.strokeWidthValues(for: .mosaic)[mosaicDotIndex]
            )
            showsCornerRadiusPanel = false
        } else {
            currentStyle = SelectionToolbarState.styleForPrimaryShapeToolActivation(
                currentStyle: nonMarkerStyle,
                paletteColors: colors
            )
        }
        rememberCurrentStyleForActiveTool()
        if shape != .arrowLine {
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
        }
        if !SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode) {
            showsStrokeStyleMenu = false
        }
        currentStyle.strokePattern = .solid
        rememberCurrentStyleForActiveTool()
        clearSelectedAnnotationIfNeededForActiveTool()
        shapeStartPoint = nil
        shapeCurrentPoint = nil
        brushDraftPoints.removeAll()
        mosaicDraftPoints.removeAll()
        invalidateCursorRectsAndRefresh()
    }

    private func rememberCurrentStyleForActiveTool() {
        if isTextToolActive {
            textStyle = currentStyle
            return
        }

        if isNumberToolActive {
            numberStyle = currentStyle
            numberStyle.textSize = clampedNumberSize(numberStyle.textSize)
            return
        }

        if isMagnifierToolActive {
            magnifierStyle = currentStyle
            magnifierStyle.strokePattern = .solid
            return
        }

        guard isShapeToolActive else {
            return
        }

        if currentShapeKind == .marker {
            markerStyle = currentStyle
        } else if currentShapeKind == .mosaicStroke || currentShapeKind == .mosaicRectangle {
            nonMarkerStyle = currentStyle
        } else {
            nonMarkerStyle = currentStyle
        }
    }

    private func setLockedSelectionRect(_ rect: NSRect) {
        cancelSelectionWheelAnimation()
        let rect = rect.standardized
        lockedSelectionRect = rect
        selectionStartPoint = rect.origin
        selectionCurrentPoint = NSPoint(x: rect.maxX, y: rect.maxY)
        interactionMode = .annotating
    }

    func updatePinnedImageEditor(backgroundImage: NSImage?, selectionRect: NSRect) {
        let previousSelectionRect = lockedSelectionRect?.standardized
        let startAnnotationRects = annotations.map { overlayRect(fromLocalAnnotationRect: $0.rect) }
        let startAnnotations = annotations
        let startEraserMaskRects = eraserMasks.map { overlayRect(fromLocalAnnotationRect: $0.rect) }
        self.backgroundImage = backgroundImage
        if let cgImage = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            backgroundBitmap = NSBitmapImageRep(cgImage: cgImage)
        } else {
            backgroundBitmap = nil
        }
        backgroundLuminanceCache.removeAll()

        let nextSelectionRect = selectionRect.standardized
        if let previousSelectionRect {
            applySelectionWheelResize(
                from: previousSelectionRect,
                to: nextSelectionRect,
                startAnnotationRects: startAnnotationRects,
                startAnnotations: startAnnotations
            )
            let remappedMaskRects = SelectionToolbarState.localAnnotationRectsPreservingOverlayPositions(
                startEraserMaskRects,
                selectionRect: nextSelectionRect
            )
            for index in eraserMasks.indices where remappedMaskRects.indices.contains(index) {
                eraserMasks[index].rect = remappedMaskRects[index]
            }
        } else {
            setLockedSelectionRect(nextSelectionRect)
        }
        selectionStartPoint = nextSelectionRect.origin
        selectionCurrentPoint = NSPoint(x: nextSelectionRect.maxX, y: nextSelectionRect.maxY)
        clearColorSampler()
        needsDisplay = true
    }

    var editorSnapshot: SelectionOverlayEditorSnapshot {
        commitCurrentTextEdit()
        return SelectionOverlayEditorSnapshot(
            annotations: annotations,
            eraserMasks: eraserMasks,
            revision: editorDocumentRevision
        )
    }

    func test_handleTextDropdownScroll(at point: NSPoint, deltaY: CGFloat) -> Bool {
        handleTextDropdownScroll(at: point, deltaY: deltaY)
    }

    func updateLongImageEditor(
        backgroundImage: NSImage?,
        selectionRect: NSRect,
        annotations: [CaptureAnnotation],
        eraserMasks: [EraserMask],
        suppressedAnnotationIDs: Set<AnnotationID>
    ) {
        commitCurrentTextEdit()
        self.backgroundImage = backgroundImage
        if let cgImage = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            backgroundBitmap = NSBitmapImageRep(cgImage: cgImage)
        } else {
            backgroundBitmap = nil
        }
        backgroundLuminanceCache.removeAll()
        self.annotations = annotations
        self.eraserMasks = eraserMasks
        self.suppressedAnnotationIDs = suppressedAnnotationIDs
        selectedAnnotationIndex = nil
        setLockedSelectionRect(selectionRect.standardized)
        resetMosaicPreviewCaches()
        clearColorSampler()
        needsDisplay = true
    }

    func updateLongImageEditorPresentation(
        backgroundImage: NSImage?,
        suppressedAnnotationIDs: Set<AnnotationID>
    ) {
        self.backgroundImage = backgroundImage
        if let cgImage = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            backgroundBitmap = NSBitmapImageRep(cgImage: cgImage)
        } else {
            backgroundBitmap = nil
        }
        backgroundLuminanceCache.removeAll()
        self.suppressedAnnotationIDs = suppressedAnnotationIDs
        resetMosaicPreviewCaches()
        needsDisplay = true
    }

#if DEBUG
    func test_setLockedSelectionRect(_ rect: NSRect) {
        setLockedSelectionRect(rect)
    }

    func test_activateShapeTool(_ shape: CaptureAnnotationKind) {
        activateShapeTool(shape)
    }

    func test_activateTextTool() {
        activateTextTool()
    }

    func test_openTextFontDropdown() {
        toggleTextDropdown(.font)
    }

    func test_activateNumberTool() {
        activateNumberTool()
    }

    func test_activateMagnifierTool() {
        activateMagnifierTool()
    }

    func test_activateEraserTool() {
        activateEraserTool()
    }

    func test_toggleShapeTool(_ shape: CaptureAnnotationKind) {
        toggleShapeTool(shape)
    }

    func test_setCurrentStrokePattern(_ pattern: CaptureStrokePattern) {
        currentStyle.strokePattern = pattern
        rememberCurrentStyleForActiveTool()
    }

    func test_setCurrentStrokeWidth(_ width: CGFloat) {
        currentStyle.strokeWidth = width
        rememberCurrentStyleForActiveTool()
    }

    func test_setAnnotations(_ newAnnotations: [CaptureAnnotation]) {
        annotations = newAnnotations
        clearRedoAnnotationHistory()
        selectedAnnotationIndex = nil
        resetMosaicPreviewCaches()
        needsDisplay = true
    }

    func test_setEraserMasks(_ masks: [EraserMask]) {
        eraserMasks = masks
        clearRedoAnnotationHistory()
        needsDisplay = true
    }

    func test_addEraserMask(_ mask: EraserMask) {
        eraserMasks.append(mask)
        needsDisplay = true
    }

    var test_eraserMaskedCompositeRenderCount: Int {
        eraserMaskedCompositeRenderCount
    }

    var test_eraserMaskedCompositeCacheHitCount: Int {
        eraserMaskedCompositeCacheHitCount
    }

    var test_eraserMaskedCompositeDrawRect: NSRect? {
        eraserMaskedCompositeDrawRect
    }

    var test_eraserMaskedCompositePixelRect: CGRect? {
        eraserMaskedCompositePixelRect
    }

    var test_outsideMaskedAnnotationRenderCount: Int {
        outsideMaskedAnnotationRenderCount
    }

    var test_outsideMaskedAnnotationCacheHitCount: Int {
        outsideMaskedAnnotationCacheHitCount
    }

    @discardableResult
    func test_deleteAnnotations(at indexes: [Int]) -> Bool {
        deleteAnnotations(at: indexes)
    }

    func test_selectAnnotation(at index: Int) {
        guard annotations.indices.contains(index) else {
            selectedAnnotationIndex = nil
            selectedNumberAnnotationCanFollowTypeDropdown = false
            return
        }
        selectedAnnotationIndex = index
        selectedNumberAnnotationCanFollowTypeDropdown = annotations[index].kind == .numberSequence
        if annotations[index].kind == .numberSequence {
            selectNumberSequenceGroup(for: annotations[index])
        }
        needsDisplay = true
    }

    func test_setWindowSelectionCandidates(_ candidates: [WindowSelectionCandidate]) {
        windowCandidates = candidates
    }

    func test_setStrokeStyleMenuVisible(_ isVisible: Bool) {
        showsStrokeStyleMenu = isVisible
    }

    func test_setArrowTypeMenusVisible(start: Bool, end: Bool) {
        showsStartArrowTypeMenu = start
        showsEndArrowTypeMenu = end
    }

    func test_beginAnnotatingMouseDown(at point: NSPoint) {
        handleAnnotatingMouseDown(at: point)
    }

    func test_dragMouse(to point: NSPoint) {
        switch interactionMode {
        case .resizingSelection:
            updateResizingSelection(to: point)
        case .movingSelection:
            updateMovingSelection(to: point)
        case .drawingShape:
            shapeCurrentPoint = point
            appendBrushDraftPointIfNeeded(point)
        default:
            break
        }
    }

    func test_updateColorSampler(at point: NSPoint) {
        updateColorSampler(at: point)
    }

    func test_handleScrollWheel(at point: NSPoint, deltaY: CGFloat) -> Bool {
        if handleTextDropdownScroll(at: point, deltaY: deltaY) {
            return true
        }
        return handleScrollWheel(at: point, deltaY: deltaY)
    }

    func test_handleMagnify(at point: NSPoint, magnification: CGFloat) -> Bool {
        handleMagnify(at: point, magnification: magnification)
    }

    func test_completeSelectionWheelAnimation() {
        completeSelectionWheelAnimation()
    }

    func test_cursorStyle(at point: NSPoint) -> SelectionToolbarState.OverlayCursorStyle {
        cursorStyle(at: point)
    }

    func test_mainToolbarDragPoint() -> NSPoint? {
        guard let selectionRect, let toolbar = mainToolbarRect(for: selectionRect) else {
            return nil
        }
        let dragRect = mainToolbarDragHandleRect(in: toolbar)
        return NSPoint(x: dragRect.midX, y: dragRect.midY)
    }

    func test_mainToolbarLeadingDragPoint() -> NSPoint? {
        guard let selectionRect, let toolbar = mainToolbarRect(for: selectionRect) else {
            return nil
        }
        let dragRect = mainToolbarLeadingDragHandleRect(in: toolbar)
        return NSPoint(x: dragRect.midX, y: dragRect.midY)
    }

    func test_mainToolbarTrailingDragPoint() -> NSPoint? {
        test_mainToolbarDragPoint()
    }

    func test_mainToolbarButtonRects() -> [NSRect] {
        guard let selectionRect, let toolbar = mainToolbarRect(for: selectionRect) else {
            return []
        }
        return toolbarButtonRects(in: toolbar).map(\.1)
    }

    func test_mainToolbarRect() -> NSRect? {
        guard let selectionRect else {
            return nil
        }
        return mainToolbarRect(for: selectionRect)
    }

    func test_mainToolbarButtonRect(for button: TestToolbarButton) -> NSRect? {
        guard let selectionRect, let toolbar = mainToolbarRect(for: selectionRect) else {
            return nil
        }
        let toolbarButton: ToolbarButton
        switch button {
        case .rectangle:
            toolbarButton = .rectangle
        case .arrow:
            toolbarButton = .polyline
        case .pen:
            toolbarButton = .pen
        case .marker:
            toolbarButton = .marker
        case .eyedropper:
            toolbarButton = .eyedropper
        case .mosaic:
            toolbarButton = .mosaic
        case .text:
            toolbarButton = .text
        case .number:
            toolbarButton = .number
        case .magnifier:
            toolbarButton = .magnifier
        case .eraser:
            toolbarButton = .eraser
        case .undo:
            toolbarButton = .undo
        case .redo:
            toolbarButton = .redo
        case .cancel:
            toolbarButton = .cancel
        case .pin:
            toolbarButton = .pin
        case .save:
            toolbarButton = .save
        case .copy:
            toolbarButton = .copy
        case .scroll:
            toolbarButton = .scroll
        case .finishEditing:
            toolbarButton = .finishEditing
        }
        return toolbarButtonRects(in: toolbar).first(where: { $0.0 == toolbarButton })?.1
    }

    func test_symbolName(for button: TestToolbarButton) -> String {
        let toolbarButton: ToolbarButton
        switch button {
        case .rectangle:
            toolbarButton = .rectangle
        case .arrow:
            toolbarButton = .polyline
        case .pen:
            toolbarButton = .pen
        case .marker:
            toolbarButton = .marker
        case .eyedropper:
            toolbarButton = .eyedropper
        case .mosaic:
            toolbarButton = .mosaic
        case .text:
            toolbarButton = .text
        case .number:
            toolbarButton = .number
        case .magnifier:
            toolbarButton = .magnifier
        case .eraser:
            toolbarButton = .eraser
        case .undo:
            toolbarButton = .undo
        case .redo:
            toolbarButton = .redo
        case .cancel:
            toolbarButton = .cancel
        case .pin:
            toolbarButton = .pin
        case .save:
            toolbarButton = .save
        case .copy:
            toolbarButton = .copy
        case .scroll:
            toolbarButton = .scroll
        case .finishEditing:
            toolbarButton = .finishEditing
        }
        return symbolName(for: toolbarButton)
    }

    func test_mainToolbarButtonPoint(for button: TestToolbarButton) -> NSPoint? {
        guard let rect = test_mainToolbarButtonRect(for: button) else {
            return nil
        }
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_toolbarButtonIsSelected(_ button: TestToolbarButton) -> Bool {
        let toolbarButton: ToolbarButton
        switch button {
        case .rectangle:
            toolbarButton = .rectangle
        case .arrow:
            toolbarButton = .polyline
        case .pen:
            toolbarButton = .pen
        case .marker:
            toolbarButton = .marker
        case .eyedropper:
            toolbarButton = .eyedropper
        case .mosaic:
            toolbarButton = .mosaic
        case .text:
            toolbarButton = .text
        case .number:
            toolbarButton = .number
        case .magnifier:
            toolbarButton = .magnifier
        case .eraser:
            toolbarButton = .eraser
        case .undo:
            toolbarButton = .undo
        case .redo:
            toolbarButton = .redo
        case .cancel:
            toolbarButton = .cancel
        case .pin:
            toolbarButton = .pin
        case .save:
            toolbarButton = .save
        case .copy:
            toolbarButton = .copy
        case .scroll:
            toolbarButton = .scroll
        case .finishEditing:
            toolbarButton = .finishEditing
        }
        return buttonMatchesCurrentTool(toolbarButton)
    }

    func test_toolbarButtonIsEnabled(_ button: TestToolbarButton) -> Bool {
        guard let point = test_mainToolbarButtonPoint(for: button),
              let toolbarButton = toolbarButton(at: point) else { return false }
        return isToolbarButtonEnabled(toolbarButton)
    }

    func test_tooltipText(for button: TestToolbarButton) -> String? {
        guard let point = test_mainToolbarButtonPoint(for: button) else { return nil }
        return tooltipTarget(at: point)?.text
    }

    var test_isPinnedImageDragInProgress: Bool {
        isPinnedImageDragInProgress
    }

    func test_annotationRect(at index: Int) -> NSRect? {
        guard annotations.indices.contains(index) else {
            return nil
        }
        return annotations[index].rect
    }

    func test_annotationOverlayRect(at index: Int) -> NSRect? {
        guard annotations.indices.contains(index) else {
            return nil
        }
        return overlayRect(fromLocalAnnotationRect: annotations[index].rect)
    }

    func test_annotationText(at index: Int) -> String? {
        guard annotations.indices.contains(index) else {
            return nil
        }
        syncEditingTextFromEditor()
        return annotations[index].text
    }

    func test_arrowLine(at index: Int) -> CaptureArrowLine? {
        guard annotations.indices.contains(index) else {
            return nil
        }
        return annotations[index].arrowLine
    }

    func test_brushPath(at index: Int) -> CaptureBrushPath? {
        guard annotations.indices.contains(index) else {
            return nil
        }
        return annotations[index].brushPath
    }

    func test_markerLine(at index: Int) -> CaptureMarkerLine? {
        guard annotations.indices.contains(index) else {
            return nil
        }
        return annotations[index].markerLine
    }

    func test_textAnnotation(at index: Int) -> CaptureAnnotation? {
        guard annotations.indices.contains(index), annotations[index].kind == .text else {
            return nil
        }
        return annotations[index]
    }

    func test_markerToolbarButtonPoint() -> NSPoint? {
        guard let selectionRect, let toolbar = mainToolbarRect(for: selectionRect) else {
            return nil
        }
        guard let rect = toolbarButtonRects(in: toolbar).first(where: { $0.0 == .marker })?.1 else {
            return nil
        }
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_measurementControlPoint(_ control: SelectionToolbarState.MeasurementControl) -> NSPoint? {
        guard configuration.showsSelectionMeasurementControl else {
            return nil
        }
        guard scrollCaptureOverlayState == .inactive else {
            return nil
        }
        guard let selectionRect else {
            return nil
        }
        let layout = measurementControlLayout(for: selectionRect)
        let rect: NSRect
        switch control {
        case .cornerStyle:
            rect = layout.cornerStyle
        case .aspectRatioLock:
            rect = layout.aspectRatio
        case .refresh:
            rect = layout.refresh
        }
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_optionsStrokeWidthPoint(at index: Int) -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let layout = optionsToolbarLayout(in: optionsToolbarRect)
        guard layout.strokeWidths.indices.contains(index) else {
            return nil
        }
        let rect = layout.strokeWidths[index]
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_optionsPaletteColorPoint(at index: Int) -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let rects = colorSwatchRects(in: optionsToolbarRect)
        guard rects.indices.contains(index) else {
            return nil
        }
        let rect = rects[index]
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    var test_textSizeOptions: [CGFloat] {
        SelectionToolbarState.textSizeValues
    }

    var test_textSizeOptionsCount: Int {
        SelectionToolbarState.textSizeValues.count
    }

    var test_textFontOptions: [String] {
        SelectionToolbarState.installedTextFontFamilies()
    }

    func test_optionsTextSizePoint(at index: Int) -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let rects = optionsToolbarLayout(in: optionsToolbarRect).textSizes
        guard rects.indices.contains(index) else {
            return nil
        }
        let rect = rects[index]
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_optionsTextSizePoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let rect = optionsToolbarLayout(in: optionsToolbarRect).textSize
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_optionsTextFontPoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let rect = optionsToolbarLayout(in: optionsToolbarRect).textFont
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    var test_textDropdownRect: NSRect? {
        guard let activeTextDropdown else {
            return nil
        }
        return textDropdownRect(for: activeTextDropdown)
    }

    var test_isTextFontDropdownVisible: Bool {
        activeTextDropdown == .font
    }

    var test_isTextSizeDropdownVisible: Bool {
        activeTextDropdown == .size
    }

    var test_isMagnifierZoomDropdownVisible: Bool {
        activeMagnifierZoomDropdown
    }

    var test_textDropdownScrollOffset: Int {
        guard let activeTextDropdown else {
            return 0
        }
        return textDropdownScrollOffset(for: activeTextDropdown)
    }

    var test_backgroundImage: NSImage? { backgroundImage }
    var test_suppressedAnnotationIDs: Set<AnnotationID> { suppressedAnnotationIDs }

    func test_optionsTextBoldPoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let rect = optionsToolbarLayout(in: optionsToolbarRect).textBold
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_optionsTextItalicPoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let rect = optionsToolbarLayout(in: optionsToolbarRect).textItalic
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_optionsTextOutlinePoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let rect = optionsToolbarLayout(in: optionsToolbarRect).textOutline
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_selectTextSize(_ size: CGFloat) {
        applyTextSize(size)
    }

    func test_selectTextFont(_ family: String) {
        applyTextFontFamily(family)
    }

    func test_annotation(at index: Int) -> CaptureAnnotation? {
        annotations.indices.contains(index) ? annotations[index] : nil
    }

    var test_numberMarkType: CaptureNumberMarkType {
        currentNumberMarkType
    }

    func test_numberMarkTypePoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let rect = optionsToolbarLayout(in: optionsToolbarRect).numberMarkType
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_numberSizePoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let rect = optionsToolbarLayout(in: optionsToolbarRect).numberSize
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_numberMarkTypeMenuPoint(_ type: CaptureNumberMarkType) -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let itemRects = numberMarkTypeMenuItemRects(in: numberMarkTypeMenuRect(in: optionsToolbarRect))
        guard let index = CaptureNumberMarkType.allCases.firstIndex(of: type), itemRects.indices.contains(index) else {
            return nil
        }
        let rect = itemRects[index]
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_magnifierZoomMenuPoint(_ zoom: CGFloat) -> NSPoint? {
        guard let optionsToolbarRect,
              let index = SelectionToolbarState.magnifierZoomValues.firstIndex(where: { abs($0 - zoom) < 0.001 })
        else {
            return nil
        }
        let itemRects = magnifierZoomMenuItemRects(in: magnifierZoomMenuRect(in: optionsToolbarRect))
        guard itemRects.indices.contains(index) else {
            return nil
        }
        let rect = itemRects[index]
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_numberMarkTypeIconInteriorPoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let field = optionsToolbarLayout(in: optionsToolbarRect).numberMarkType
        let iconRect = NSRect(x: field.minX + 8, y: field.midY - 7, width: 14, height: 14)
        return NSPoint(x: iconRect.minX + 4, y: iconRect.midY)
    }

    func test_numberCursorImage(for type: CaptureNumberMarkType) -> NSImage? {
        numberCreationCursor(for: type).image
    }

    func test_numberCursorHotSpot(for type: CaptureNumberMarkType) -> NSPoint? {
        numberCreationCursor(for: type).hotSpot
    }

    func test_numberCursorText(for type: CaptureNumberMarkType) -> String? {
        numberCursorText(for: type)
    }

    func test_selectNumberSize(_ size: CGFloat) {
        applyTextSize(size)
    }

    func test_numberSequenceIndex(at index: Int) -> Int? {
        annotations.indices.contains(index) ? annotations[index].numberSequenceIndex : nil
    }

    func test_setNumberMarkType(_ type: CaptureNumberMarkType) {
        setNumberMarkType(type)
    }

    func test_mosaicRectangleOptionPoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        guard let rect = optionsToolbarLayout(in: optionsToolbarRect).rectangleMode else {
            return nil
        }
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_eraserPointOptionPoint() -> NSPoint? {
        guard let optionsToolbarRect,
              let rect = optionsToolbarLayout(in: optionsToolbarRect).eraserPointMode
        else {
            return nil
        }
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    var test_eraserPointOptionRect: NSRect? {
        guard let optionsToolbarRect else {
            return nil
        }
        return optionsToolbarLayout(in: optionsToolbarRect).eraserPointMode
    }

    var test_eraserRectangleOptionRect: NSRect? {
        guard let optionsToolbarRect else {
            return nil
        }
        return optionsToolbarLayout(in: optionsToolbarRect).eraserRectangleMode
    }

    func test_eraserRectangleOptionPoint() -> NSPoint? {
        guard let optionsToolbarRect,
              let rect = optionsToolbarLayout(in: optionsToolbarRect).eraserRectangleMode
        else {
            return nil
        }
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_eraserClearAllOptionPoint() -> NSPoint? {
        guard let optionsToolbarRect,
              let rect = optionsToolbarLayout(in: optionsToolbarRect).eraserClearAll
        else {
            return nil
        }
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    var test_eraserClearAllSeparatorRect: NSRect? {
        guard let optionsToolbarRect else {
            return nil
        }
        return optionsToolbarLayout(in: optionsToolbarRect).eraserClearAllSeparator
    }

    var test_eraserClearAllOptionRect: NSRect? {
        guard let optionsToolbarRect else {
            return nil
        }
        return optionsToolbarLayout(in: optionsToolbarRect).eraserClearAll
    }

    func test_mosaicRedactionTypePoint(_ type: CaptureMosaicRedactionType) -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let rect: NSRect
        switch type {
        case .gaussianBlur:
            rect = SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsToolbarRect)
        case .pixelMosaic:
            rect = SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsToolbarRect)
        }
        guard !rect.isEmpty else {
            return nil
        }
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_mosaicValueIncrementPoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let valueRect = SelectionToolbarState.mosaicRedactionValueRect(in: optionsToolbarRect)
        let rect = mosaicValueIncrementRect(in: valueRect)
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_mosaicValueDecrementPoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let valueRect = SelectionToolbarState.mosaicRedactionValueRect(in: optionsToolbarRect)
        let rect = mosaicValueDecrementRect(in: valueRect)
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_mosaicValueInputPoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        let valueRect = SelectionToolbarState.mosaicRedactionValueRect(in: optionsToolbarRect)
        let rect = mosaicValueInputRect(in: valueRect)
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_shapeResizeHandlePoint(_ handle: SelectionToolbarState.OverlayResizeHandle) -> NSPoint? {
        guard let annotation = selectedAnnotation else {
            return nil
        }
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect)
        let localHandle = ShapeResizeHandle(toolbarStateHandle: handle)
        let rectForHandle = handleRect(
            for: rect,
            handle: localHandle,
            kind: annotation.kind,
            rotationAngle: annotationKindSupportsRotationHandle(annotation.kind) ? annotation.rotationAngle : 0
        )
        return NSPoint(x: rectForHandle.midX, y: rectForHandle.midY)
    }

    func test_numberDeleteHandlePoint() -> NSPoint? {
        test_numberHandlePoint(.delete)
    }

    func test_numberResizeHandlePoint() -> NSPoint? {
        test_numberHandlePoint(.resize)
    }

    func test_numberIncrementHandlePoint() -> NSPoint? {
        test_numberHandlePoint(.increment)
    }

    func test_numberDecrementHandlePoint() -> NSPoint? {
        test_numberHandlePoint(.decrement)
    }

    func test_numberIncrementHandleIsHitTarget() -> Bool {
        guard let point = test_numberIncrementHandlePoint() else {
            return false
        }
        return numberHandleHitTarget(at: point)?.kind == .increment
    }

    func test_numberDecrementHandleIsHitTarget() -> Bool {
        guard let point = test_numberDecrementHandlePoint() else {
            return false
        }
        return numberHandleHitTarget(at: point)?.kind == .decrement
    }

    func test_numberResetHandlePoint() -> NSPoint? {
        test_numberHandlePoint(.reset)
    }

    func test_numberDeleteHandleRect() -> NSRect? {
        test_numberHandleRect(.delete)
    }

    func test_numberResizeHandleRect() -> NSRect? {
        test_numberHandleRect(.resize)
    }

    func test_numberIncrementHandleRect() -> NSRect? {
        test_numberHandleRect(.increment)
    }

    func test_numberDecrementHandleRect() -> NSRect? {
        test_numberHandleRect(.decrement)
    }

    func test_numberResetHandleRect() -> NSRect? {
        test_numberHandleRect(.reset)
    }

    func test_numberOutlineRect() -> NSRect? {
        guard let selectedAnnotation else {
            return nil
        }
        return numberEditingOutlineRect(for: selectedAnnotation)
    }

    var test_numberControlsVisible: Bool {
        shouldShowSelectedNumberControls()
    }

    private func test_numberHandlePoint(_ kind: NumberHandleKind) -> NSPoint? {
        guard let rect = test_numberHandleRect(kind) else {
            return nil
        }
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    private func test_numberHandleRect(_ kind: NumberHandleKind) -> NSRect? {
        guard let selectedAnnotation,
              let rect = numberHandleRect(for: selectedAnnotation, kind: kind)
        else {
            return nil
        }
        return rect
    }

    func test_mosaicRectangleRotationHandlePoint() -> NSPoint? {
        guard let selectedAnnotation, annotationKindSupportsRotationHandle(selectedAnnotation.kind) else {
            return nil
        }
        return mosaicRectangleRotationHandlePoint(for: selectedAnnotation)
    }

    func test_mosaicRectangleRotationHandleGlyph() -> TestMosaicRectangleRotationHandleGlyph? {
        guard let selectedAnnotation, annotationKindSupportsRotationHandle(selectedAnnotation.kind) else {
            return nil
        }
        return .refreshDot
    }

    var test_mosaicStrokeDraftUsesLiveCompositePreviewPath: Bool {
        guard let draftAnnotation else {
            return false
        }
        return draftAnnotation.kind == .mosaicStroke
            && mosaicDraftPreviewImage(for: draftAnnotation) != nil
    }

    var test_mosaicRectangleDraftUsesLivePreviewPath: Bool {
        guard let draftAnnotation else {
            return false
        }
        return draftAnnotation.kind == .mosaicRectangle
            && mosaicDraftPreviewImage(for: draftAnnotation) != nil
    }

    func test_annotationRotationAngle(at index: Int) -> CGFloat? {
        guard annotations.indices.contains(index) else {
            return nil
        }
        return annotations[index].rotationAngle
    }

    func test_annotationStyle(at index: Int) -> CaptureAnnotationStyle? {
        guard annotations.indices.contains(index) else {
            return nil
        }
        return annotations[index].style
    }

    func test_mosaicStroke(at index: Int) -> CaptureMosaicStroke? {
        guard annotations.indices.contains(index) else {
            return nil
        }
        return annotations[index].mosaicStroke
    }

    func test_mosaicRedaction(at index: Int) -> CaptureMosaicRedaction? {
        guard annotations.indices.contains(index) else {
            return nil
        }
        return annotations[index].mosaicRedaction
    }

    func test_mosaicPreviewComposite(for annotations: [CaptureAnnotation]) -> (size: NSSize, drawRect: NSRect)? {
        guard let composite = mosaicPreviewComposite(for: annotations) else {
            return nil
        }
        return (composite.image.size, composite.drawRect)
    }

    var test_hasMosaicCompositeCache: Bool {
        !mosaicCompositeCache.isEmpty
    }

    var test_mosaicCompositeRenderCount: Int {
        mosaicCompositeRenderCount
    }

    var test_mosaicFullCompositeRenderCount: Int {
        mosaicFullCompositeRenderCount
    }

    var test_mosaicCompositeDrawCount: Int {
        mosaicCompositeDrawCount
    }

    var test_mosaicDraftRedactedBaseRenderCount: Int {
        mosaicDraftRedactedBaseRenderCount
    }

    var test_mosaicDraftPreviewImageRenderCount: Int {
        mosaicDraftPreviewImageRenderCount
    }

    func test_mosaicPreviewClipBounds(for annotations: [CaptureAnnotation]) -> NSRect? {
        let clipPath = NSBezierPath()
        annotations.compactMap(mosaicDraftClipPath).forEach { clipPath.append($0) }
        guard clipPath.elementCount > 0 else {
            return nil
        }
        return clipPath.bounds
    }

    func test_mosaicPreviewClipContains(_ point: NSPoint, for annotations: [CaptureAnnotation]) -> Bool {
        let clipPath = NSBezierPath()
        annotations.compactMap(mosaicDraftClipPath).forEach { clipPath.append($0) }
        guard clipPath.elementCount > 0 else {
            return false
        }
        return clipPath.contains(point)
    }

    func test_mosaicDraftPreviewAnnotationCount(for draft: CaptureAnnotation) -> Int {
        mosaicPreviewAnnotations(including: draft).count
    }

    func test_mosaicDraftPreviewDrawRect(for draft: CaptureAnnotation) -> NSRect? {
        guard let redaction = draft.mosaicRedaction else {
            return nil
        }
        return mosaicDraftPreviewDrawRect(for: draft, redaction: redaction)
    }

    func test_mosaicDraftPreview(for draft: CaptureAnnotation) -> (image: NSImage, drawRect: NSRect)? {
        mosaicDraftPreview(for: draft)
    }

    var test_selectedAnnotationKind: CaptureAnnotationKind? {
        selectedAnnotation?.kind
    }

    var test_selectedAnnotationIndex: Int? {
        selectedAnnotationIndex
    }

    var test_selectedAnnotationShowsOutline: Bool {
        guard let selectedAnnotation else {
            return false
        }
        return shouldDrawSelectedAnnotationOutline(selectedAnnotation)
    }

    var test_annotationCount: Int {
        annotations.count
    }

    var test_eraserMaskCount: Int {
        eraserMasks.count
    }

    func test_eraserMask(at index: Int) -> EraserMask? {
        eraserMasks.indices.contains(index) ? eraserMasks[index] : nil
    }

    var test_damagedAnnotationIDs: Set<AnnotationID> {
        damagedAnnotationIDs
    }

    var test_damagedAnnotationCount: Int {
        damagedAnnotationIDs.count
    }

    var test_lockedSelectionRect: NSRect? {
        lockedSelectionRect?.standardized
    }

    var test_currentSelectionRect: NSRect? {
        selectionRect?.standardized
    }

    var test_overlayBounds: NSRect {
        bounds
    }

    var test_selectionCornerRadius: CGFloat {
        selectionCornerRadius
    }

    var test_isSelectionAspectRatioLocked: Bool {
        isSelectionAspectRatioLocked
    }

    var test_currentStrokePattern: CaptureStrokePattern {
        currentStyle.strokePattern
    }

    var test_currentStyle: CaptureAnnotationStyle {
        currentStyle
    }

    var test_isMagnifierToolActive: Bool {
        isMagnifierToolActive
    }

    var test_isEraserToolActive: Bool {
        isEraserToolActive
    }

    var test_eraserToolbarButtonIsSelected: Bool {
        buttonMatchesCurrentTool(.eraser)
    }

    var test_isEraserRectangleModeActive: Bool {
        eraserMode == .rectangle
    }

    var test_eraserRectanglePreviewRect: NSRect? {
        eraserRectanglePreviewRect
    }

    var test_currentMagnifierShape: CaptureMagnifierShape {
        currentMagnifierShape
    }

    var test_currentMagnifierZoom: CGFloat {
        currentMagnifierZoom
    }

    func test_setMagnifierShape(_ shape: CaptureMagnifierShape) {
        currentMagnifierShape = shape
        applyCurrentMagnifierSettingsToSelectedAnnotation()
    }

    func test_setMagnifierZoom(_ zoom: CGFloat) {
        currentMagnifierZoom = zoom
        applyCurrentMagnifierSettingsToSelectedAnnotation()
    }

    var test_optionsToolbarMode: SelectionToolbarState.OptionsToolbarMode? {
        guard isShapeToolActive || isTextToolActive || isNumberToolActive || isMagnifierToolActive || isEraserToolActive else {
            return nil
        }
        return optionsToolbarMode
    }

    var test_optionsToolbarRect: NSRect? {
        optionsToolbarRect
    }

    var test_currentShapeKind: CaptureAnnotationKind? {
        guard isShapeToolActive else {
            return nil
        }
        return currentShapeKind
    }

    var test_mosaicRedactionType: CaptureMosaicRedactionType {
        mosaicRedactionType
    }

    var test_hoveredTooltipText: String? {
        hoveredTooltip?.text
    }

    func test_mosaicRedactionValue(for type: CaptureMosaicRedactionType) -> Int {
        mosaicRedactionValues[type] ?? SelectionToolbarState.mosaicDefaultRedactionValue(for: type)
    }

    var test_showsStrokeStyleMenu: Bool {
        showsStrokeStyleMenu
    }

    var test_showsStartArrowTypeMenu: Bool {
        showsStartArrowTypeMenu
    }

    var test_showsEndArrowTypeMenu: Bool {
        showsEndArrowTypeMenu
    }

    var test_selectedBrushEndpointMarkers: [NSPoint] {
        guard let selectedAnnotation else {
            return []
        }
        return selectedBrushEndpointMarkers(for: selectedAnnotation)
    }

    var test_markerToolbarButtonIsSelected: Bool {
        buttonMatchesCurrentTool(.marker)
    }

    var test_isEyedropperToolActive: Bool {
        isEyedropperToolActive
    }

    var test_eyedropperToolbarButtonIsSelected: Bool {
        buttonMatchesCurrentTool(.eyedropper)
    }

    var test_isTextToolActive: Bool {
        isTextToolActive
    }

    var test_isNumberToolActive: Bool {
        isNumberToolActive
    }

    var test_textToolbarButtonIsSelected: Bool {
        buttonMatchesCurrentTool(.text)
    }

    var test_numberToolbarIconUsesTemplateBlack: Bool {
        true
    }

    var test_isEditingTextAnnotation: Bool {
        guard let editingTextAnnotationIndex else {
            return false
        }
        return annotations.indices.contains(editingTextAnnotationIndex)
    }

    var test_textEditorIsFirstResponder: Bool {
        guard let textEditor else {
            return false
        }
        return window?.firstResponder === textEditor
    }

    var test_textEditorUsesTransparentText: Bool {
        guard let textEditor else {
            return false
        }
        let textAlpha = textEditor.textColor?.alphaComponent ?? 1
        let typingColor = textEditor.typingAttributes[.foregroundColor] as? NSColor
        return textAlpha == 0 && (typingColor?.alphaComponent ?? 1) == 0
    }

    func test_textEditorContentOrigin() -> NSPoint? {
        guard let textEditor else {
            return nil
        }

        return NSPoint(
            x: textEditor.frame.minX + textEditor.textContainerInset.width,
            y: textEditor.frame.minY + textEditor.textContainerInset.height
        )
    }

    func test_textEditorInsertionRect() -> NSRect? {
        guard let textEditor,
              let textContainer = textEditor.textContainer,
              let layoutManager = textEditor.layoutManager
        else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let textLength = (textEditor.string as NSString).length
        let selectedLocation = min(textEditor.selectedRange().location, textLength)
        let rectInContainer: NSRect
        if textLength == 0 || layoutManager.numberOfGlyphs == 0 {
            rectInContainer = layoutManager.extraLineFragmentRect
        } else if selectedLocation >= textLength {
            let glyphRange = NSRange(location: max(0, layoutManager.numberOfGlyphs - 1), length: 1)
            var lastGlyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            lastGlyphRect.origin.x = lastGlyphRect.maxX
            lastGlyphRect.size.width = 1
            rectInContainer = lastGlyphRect
        } else {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: selectedLocation)
            var glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            glyphRect.size.width = 1
            rectInContainer = glyphRect
        }

        let containerOrigin = textEditor.textContainerOrigin
        let editorCaretRect = NSRect(
            x: textEditor.frame.minX + containerOrigin.x + rectInContainer.minX,
            y: textEditor.frame.minY + textEditor.bounds.height - containerOrigin.y - rectInContainer.maxY,
            width: max(1, rectInContainer.width),
            height: rectInContainer.height
        )
        return editorCaretRect
    }

    func test_editingTextCaretDrawRect() -> NSRect? {
        guard let textEditor,
              let editingTextAnnotationIndex,
              annotations.indices.contains(editingTextAnnotationIndex)
        else {
            return nil
        }

        return editingTextCaretDrawInfo(
            for: textEditor,
            annotation: annotations[editingTextAnnotationIndex]
        )?.drawRect
    }

    func test_editingTextCaretColor() -> NSColor? {
        guard let textEditor,
              let editingTextAnnotationIndex,
              annotations.indices.contains(editingTextAnnotationIndex),
              let caretInfo = editingTextCaretDrawInfo(
                for: textEditor,
                annotation: annotations[editingTextAnnotationIndex]
              )
        else {
            return nil
        }

        return editingTextCaretColor(at: caretInfo.samplePoint)
    }

    func test_textEditorOverlayPointForInsertion(at characterIndex: Int) -> NSPoint? {
        guard
            let textEditor,
            let editingTextAnnotationIndex,
            annotations.indices.contains(editingTextAnnotationIndex),
            let caretRect = textEditorCaretRectInEditorBounds(textEditor, selectedLocation: characterIndex)
        else {
            return nil
        }

        let annotation = annotations[editingTextAnnotationIndex]
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
        let unrotatedPoint = NSPoint(
            x: rect.minX + caretRect.minX,
            y: rect.minY + rect.height - caretRect.midY
        )
        return rotatedPoint(
            unrotatedPoint,
            around: NSPoint(x: rect.midX, y: rect.midY),
            angle: annotation.rotationAngle
        )
    }

    func test_textEditorSelectedRange() -> NSRange? {
        textEditor?.selectedRange()
    }

    func test_textEditorFrameCenterRotation() -> CGFloat? {
        textEditor?.frameCenterRotation
    }

    func test_commitTextEditing() {
        commitCurrentTextEdit()
    }

    func test_textEditorMouseDown(at point: NSPoint) {
        guard let textEditor,
              let event = test_mouseEvent(type: .leftMouseDown, at: point)
        else {
            return
        }
        textEditor.mouseDown(with: event)
    }

    func test_textEditorMouseDragged(to point: NSPoint) {
        guard let textEditor,
              let event = test_mouseEvent(type: .leftMouseDragged, at: point)
        else {
            return
        }
        textEditor.mouseDragged(with: event)
    }

    func test_textEditorMouseDownAndDragged(from start: NSPoint, to end: NSPoint) {
        guard let textEditor,
              let mouseDown = test_mouseEvent(type: .leftMouseDown, at: start),
              let mouseDragged = test_mouseEvent(type: .leftMouseDragged, at: end)
        else {
            return
        }

        textEditor.mouseDown(with: mouseDown)
        textEditor.mouseDragged(with: mouseDragged)
    }

    func test_textEditorDragSequence(from start: NSPoint, to end: NSPoint) {
        guard let textEditor,
              let mouseDown = test_mouseEvent(type: .leftMouseDown, at: start),
              let mouseDragged = test_mouseEvent(type: .leftMouseDragged, at: end),
              let mouseUp = test_mouseEvent(type: .leftMouseUp, at: end)
        else {
            return
        }

        textEditor.mouseDown(with: mouseDown)
        textEditor.mouseDragged(with: mouseDragged)
        textEditor.mouseUp(with: mouseUp)
    }

    private func test_mouseEvent(type: NSEvent.EventType, at point: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    var test_isColorSamplerVisible: Bool {
        sampledPointerPoint != nil && sampledColor != nil
    }

    var test_sampledColorHex: String? {
        sampledColor.map { SelectionToolbarState.colorSamplerHexString(for: $0) }
    }

    var test_sampledPointerPoint: NSPoint? {
        sampledPointerPoint
    }

    var test_eyedropperMeasurementLine: (start: NSPoint, end: NSPoint)? {
        eyedropperMeasurementLine
    }

    var test_eyedropperMeasurementLabel: String? {
        eyedropperMeasurementLabel
    }

    var test_eyedropperMeasurementInvalidationRect: NSRect? {
        eyedropperMeasurementInvalidationRectForTesting
    }

    var test_visibleSelectionCompositeLookupCount: Int {
        visibleSelectionCompositeLookupCountForTesting
    }

    func test_magnifierSampleColorHex(at point: NSPoint) -> String? {
        magnifierSampleColor(at: point).map { SelectionToolbarState.colorSamplerHexString(for: $0) }
    }

    func test_magnifierSampleColorHex(at point: NSPoint, columnOffset: Int, rowOffset: Int) -> String? {
        magnifierSampleColor(
            centeredAt: point,
            columnOffset: columnOffset,
            rowOffset: rowOffset
        ).map { SelectionToolbarState.colorSamplerHexString(for: $0) }
    }
#endif

    private func showPlaceholder(for button: ToolbarButton) {
        let label: String
        switch button {
        case .pin:
            label = "贴图"
        case .polyline:
            label = "箭头线"
        case .pen:
            label = "画笔"
        case .marker:
            label = "标记"
        case .eyedropper:
            label = "取色"
        case .mosaic:
            label = "马赛克"
        case .text:
            label = "文字"
        case .number:
            label = "序号"
        case .magnifier:
            label = "放大镜"
        case .eraser:
            label = "橡皮擦"
        case .scroll:
            label = "滚动截图"
        case .undo:
            label = "撤销"
        case .redo:
            label = "重做"
        case .copy:
            label = "复制"
        case .save:
            label = "保存"
        case .cancel:
            label = "退出"
        case .rectangle:
            label = "矩形"
        case .finishEditing:
            label = "完成编辑"
        }

        NSAlert.showTransient(message: "\(label)功能开发中。", in: window)
    }

    private func finish(action: CaptureCompletionAction) {
        guard let lockedSelectionRect, let window else {
            selectionDidFinish?(nil)
            return
        }

        commitCurrentTextEdit()

        selectionDidFinish?(
            CaptureSelectionResult(
                screenRect: window.convertToScreen(lockedSelectionRect).standardized,
                snapshotRect: lockedSelectionRect.standardized,
                annotations: annotations,
                eraserMasks: eraserMasks,
                action: action
            )
        )
    }

    private func undoLastAnnotation() {
        if let entry = undoAnnotationEntries.popLast() {
            applyUndo(entry)
            redoAnnotationEntries.append(entry)
        } else {
            guard let removed = annotations.popLast() else {
                return
            }
            redoAnnotationEntries.append(.add(annotation: removed, index: annotations.count))
            selectedAnnotationIndex = annotations.indices.last
            if removed.kind == .mosaicStroke || removed.kind == .mosaicRectangle {
                resetMosaicPreviewCaches()
            }
        }
        needsDisplay = true
    }

    private func redoLastAnnotation() {
        guard let entry = redoAnnotationEntries.popLast() else {
            return
        }
        applyRedo(entry)
        undoAnnotationEntries.append(entry)
        needsDisplay = true
    }

    private func recordAnnotationAdd(at index: Int) {
        guard annotations.indices.contains(index) else {
            return
        }
        undoAnnotationEntries.append(.add(annotation: annotations[index], index: index))
        redoAnnotationEntries.removeAll()
        editorDocumentRevision &+= 1
    }

    private func clearRedoAnnotationHistory() {
        redoAnnotationEntries.removeAll()
        editorDocumentRevision &+= 1
    }

    private func applyUndo(_ entry: AnnotationHistoryEntry) {
        switch entry {
        case .add(let annotation, let index):
            let removalIndex: Int? = annotations.indices.contains(index) ? index : annotations.indices.last
            if let removalIndex {
                annotations.remove(at: removalIndex)
            }
            selectedAnnotationIndex = annotations.indices.last
            finishAnnotationHistoryMutation(
                affectedKind: annotation.kind,
                selectedIndex: selectedAnnotationIndex,
                numberSequenceGroupIDs: numberSequenceGroupIDs(in: [annotation])
            )
        case .delete(let annotation, let index, let masks):
            let insertionIndex = min(max(index, 0), annotations.count)
            annotations.insert(annotation, at: insertionIndex)
            restoreEraserMasks(masks)
            selectedAnnotationIndex = insertionIndex
            finishAnnotationHistoryMutation(
                affectedKind: annotation.kind,
                selectedIndex: insertionIndex,
                numberSequenceGroupIDs: numberSequenceGroupIDs(in: [annotation])
            )
        case .deleteMany(let entries, let masks):
            let sorted = entries.sorted { $0.index < $1.index }
            for entry in sorted {
                let insertionIndex = min(max(entry.index, 0), annotations.count)
                annotations.insert(entry.annotation, at: insertionIndex)
            }
            restoreEraserMasks(masks)
            finishAnnotationHistoryMutation(
                affectedKinds: sorted.map(\.annotation.kind),
                selectedIndex: nil,
                numberSequenceGroupIDs: numberSequenceGroupIDs(in: sorted.map(\.annotation))
            )
        case .addEraserMask(let mask):
            eraserMasks.removeAll { $0.id == mask.id }
            finishAnnotationHistoryMutation(affectedKinds: annotations.filter { mask.affectedAnnotationIDs.contains($0.id) }.map(\.kind), selectedIndex: nil)
        }
    }

    private func applyRedo(_ entry: AnnotationHistoryEntry) {
        switch entry {
        case .add(let annotation, let index):
            let insertionIndex = min(max(index, 0), annotations.count)
            annotations.insert(annotation, at: insertionIndex)
            selectedAnnotationIndex = insertionIndex
            finishAnnotationHistoryMutation(
                affectedKind: annotation.kind,
                selectedIndex: insertionIndex,
                numberSequenceGroupIDs: numberSequenceGroupIDs(in: [annotation])
            )
        case .delete(let annotation, let index, let masks):
            let removalIndex: Int? = annotations.indices.contains(index) ? index : nil
            if let removalIndex {
                annotations.remove(at: removalIndex)
            }
            reapplyEraserMaskPruning(originalMasks: masks, removing: Set([annotation.id]))
            selectedAnnotationIndex = nil
            finishAnnotationHistoryMutation(
                affectedKind: annotation.kind,
                selectedIndex: nil,
                numberSequenceGroupIDs: numberSequenceGroupIDs(in: [annotation])
            )
        case .deleteMany(let entries, let masks):
            for entry in entries.sorted(by: { $0.index > $1.index }) where annotations.indices.contains(entry.index) {
                annotations.remove(at: entry.index)
            }
            let deletedIDs = Set(entries.map(\.annotation.id))
            if annotations.isEmpty {
                let maskIDs = Set(masks.map(\.id))
                eraserMasks.removeAll { maskIDs.contains($0.id) }
            } else {
                reapplyEraserMaskPruning(originalMasks: masks, removing: deletedIDs)
            }
            finishAnnotationHistoryMutation(
                affectedKinds: entries.map(\.annotation.kind),
                selectedIndex: nil,
                numberSequenceGroupIDs: numberSequenceGroupIDs(in: entries.map(\.annotation))
            )
        case .addEraserMask(let mask):
            eraserMasks.append(mask)
            finishAnnotationHistoryMutation(affectedKinds: annotations.filter { mask.affectedAnnotationIDs.contains($0.id) }.map(\.kind), selectedIndex: nil)
        }
    }

    private func finishAnnotationHistoryMutation(
        affectedKind: CaptureAnnotationKind,
        selectedIndex: Int?,
        numberSequenceGroupIDs: Set<UUID?>? = nil
    ) {
        finishAnnotationHistoryMutation(
            affectedKinds: [affectedKind],
            selectedIndex: selectedIndex,
            numberSequenceGroupIDs: numberSequenceGroupIDs
        )
    }

    private func finishAnnotationHistoryMutation(
        affectedKinds: [CaptureAnnotationKind],
        selectedIndex: Int?,
        numberSequenceGroupIDs: Set<UUID?>? = nil
    ) {
        editorDocumentRevision &+= 1
        editingTextAnnotationIndex = nil
        clearNumberEditing()
        clearPendingTextEdit()
        removeTextEditor()
        if affectedKinds.contains(.numberSequence) {
            if let numberSequenceGroupIDs, !numberSequenceGroupIDs.isEmpty {
                for groupID in numberSequenceGroupIDs where !isNumberSequenceManualModeActive(in: groupID) {
                    renumberNumberSequenceAnnotations(in: groupID)
                }
            } else if !isNumberSequenceManualModeActive(in: nil) {
                renumberNumberSequenceAnnotations()
            }
        }
        if affectedKinds.contains(.numberSequence) {
            revealedNumberControlsIndex = nil
            invalidateCursorRectsAndRefresh()
        }
        if affectedKinds.contains(.mosaicStroke) || affectedKinds.contains(.mosaicRectangle) {
            resetMosaicPreviewCaches()
        }
        selectedAnnotationIndex = selectedIndex.flatMap { annotationIsEditable(at: $0) ? $0 : nil }
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
    }

    private func deleteSelectedAnnotation() -> Bool {
        let deletionIndex: Int?
        if let selectedAnnotationIndex, annotationIsEditable(at: selectedAnnotationIndex) {
            deletionIndex = selectedAnnotationIndex
        } else if let revealedNumberControlsIndex,
                  annotationIsEditable(at: revealedNumberControlsIndex),
                  annotations[revealedNumberControlsIndex].kind == .numberSequence {
            deletionIndex = revealedNumberControlsIndex
        } else {
            deletionIndex = nil
        }

        guard let deletionIndex else {
            return false
        }

        return deleteAnnotation(at: deletionIndex)
    }

    private func deleteAnnotations(at indexes: [Int]) -> Bool {
        let uniqueIndexes = Array(Set(indexes)).filter { annotations.indices.contains($0) }.sorted()
        guard !uniqueIndexes.isEmpty else {
            needsDisplay = true
            return false
        }

        let entries = uniqueIndexes.map { DeletedAnnotationEntry(annotation: annotations[$0], index: $0) }
        for index in uniqueIndexes.reversed() {
            annotations.remove(at: index)
        }

        let removedAnnotationIDs = Set(entries.map(\.annotation.id))
        let removedMasks = pruneEraserMasks(removing: removedAnnotationIDs)
        undoAnnotationEntries.append(.deleteMany(entries: entries, masks: removedMasks))
        selectedAnnotationIndex = nil
        editingTextAnnotationIndex = nil
        clearNumberEditing()
        clearPendingTextEdit()
        removeTextEditor()
        clearRedoAnnotationHistory()
        finishAnnotationHistoryMutation(
            affectedKinds: entries.map(\.annotation.kind),
            selectedIndex: nil,
            numberSequenceGroupIDs: numberSequenceGroupIDs(in: entries.map(\.annotation))
        )
        needsDisplay = true
        return true
    }

    private func clearAllAnnotationsAndMasks() -> Bool {
        let entries = annotations.indices.map { DeletedAnnotationEntry(annotation: annotations[$0], index: $0) }
        let masks = eraserMasks
        guard !entries.isEmpty || !masks.isEmpty else {
            needsDisplay = true
            return false
        }
        annotations.removeAll()
        eraserMasks.removeAll()
        undoAnnotationEntries.append(.deleteMany(entries: entries, masks: masks))
        clearRedoAnnotationHistory()
        finishAnnotationHistoryMutation(
            affectedKinds: entries.map(\.annotation.kind),
            selectedIndex: nil,
            numberSequenceGroupIDs: numberSequenceGroupIDs(in: entries.map(\.annotation))
        )
        needsDisplay = true
        return true
    }

    private func pruneEraserMasks(removing annotationIDs: Set<AnnotationID>) -> [EraserMask] {
        guard !annotationIDs.isEmpty else {
            return []
        }
        let originalMasks = eraserMasks.filter { !$0.affectedAnnotationIDs.isDisjoint(with: annotationIDs) }
        eraserMasks = eraserMasks.compactMap { mask in
            guard !mask.affectedAnnotationIDs.isDisjoint(with: annotationIDs) else {
                return mask
            }
            var prunedMask = mask
            prunedMask.affectedAnnotationIDs.subtract(annotationIDs)
            return prunedMask.affectedAnnotationIDs.isEmpty ? nil : prunedMask
        }
        return originalMasks
    }

    private func restoreEraserMasks(_ masks: [EraserMask]) {
        guard !masks.isEmpty else {
            return
        }
        var replacementsByID = Dictionary(uniqueKeysWithValues: masks.map { ($0.id, $0) })
        eraserMasks = eraserMasks.map { mask in
            replacementsByID.removeValue(forKey: mask.id) ?? mask
        }
        let remainingIDs = Set(replacementsByID.keys)
        eraserMasks.append(contentsOf: masks.filter { remainingIDs.contains($0.id) })
    }

    private func reapplyEraserMaskPruning(originalMasks masks: [EraserMask], removing annotationIDs: Set<AnnotationID>) {
        guard !masks.isEmpty else {
            return
        }
        let maskIDs = Set(masks.map(\.id))
        let prunedMasks = masks.compactMap { mask -> EraserMask? in
            var prunedMask = mask
            prunedMask.affectedAnnotationIDs.subtract(annotationIDs)
            return prunedMask.affectedAnnotationIDs.isEmpty ? nil : prunedMask
        }
        let prunedMasksByID = Dictionary(uniqueKeysWithValues: prunedMasks.map { ($0.id, $0) })
        var replacedIDs = Set<UUID>()
        eraserMasks = eraserMasks.compactMap { mask in
            guard maskIDs.contains(mask.id) else {
                return mask
            }
            guard let prunedMask = prunedMasksByID[mask.id] else {
                return nil
            }
            replacedIDs.insert(mask.id)
            return prunedMask
        }
        eraserMasks.append(contentsOf: prunedMasks.filter { !replacedIDs.contains($0.id) })
    }

    private func deleteAnnotation(at deletionIndex: Int) -> Bool {
        guard annotations.indices.contains(deletionIndex) else {
            return false
        }

        let removed = annotations[deletionIndex]
        let removedNumberSequenceGroupID = removed.numberSequenceGroupID
        let shouldRenumberNumberSequence = removed.kind == .numberSequence &&
            !isNumberSequenceManualModeActive(in: removedNumberSequenceGroupID)
        if removed.kind == .numberSequence,
           removed.numberMarkType == .number || removed.numberMarkType == nil {
            currentNumberSequenceGroupID = removedNumberSequenceGroupID
            nextNumberSequenceIndexAfterReset = nil
        }
        annotations.remove(at: deletionIndex)
        let removedMasks = pruneEraserMasks(removing: Set([removed.id]))
        undoAnnotationEntries.append(.delete(annotation: removed, index: deletionIndex, masks: removedMasks))
        self.selectedAnnotationIndex = nil
        editingTextAnnotationIndex = nil
        clearNumberEditing()
        clearPendingTextEdit()
        removeTextEditor()
        clearRedoAnnotationHistory()
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        if removed.kind == .numberSequence {
            if shouldRenumberNumberSequence {
                renumberNumberSequenceAnnotations(in: removedNumberSequenceGroupID)
            }
            revealedNumberControlsIndex = nil
            invalidateCursorRectsAndRefresh()
        }
        if removed.kind == .mosaicStroke || removed.kind == .mosaicRectangle {
            resetMosaicPreviewCaches()
        }
        needsDisplay = true
        return true
    }

    private func handleOptionsClick(at point: NSPoint) -> Bool {
        guard let optionsRect = optionsToolbarRect else {
            return false
        }
        if handleTextDropdownClick(at: point) {
            return true
        }
        if optionsToolbarMode == .mosaic {
            closeTextDropdown()
            return handleMosaicOptionsClick(at: point, optionsRect: optionsRect)
        }
        if optionsToolbarMode == .numberSequence {
            return handleNumberOptionsClick(at: point, optionsRect: optionsRect)
        }
        if optionsToolbarMode == .magnifier {
            return handleMagnifierOptionsClick(at: point, optionsRect: optionsRect)
        }
        if optionsToolbarMode == .eraser {
            return handleEraserOptionsClick(at: point, optionsRect: optionsRect)
        }
        let layout = optionsToolbarLayout(in: optionsRect)
        let strokeWidths = SelectionToolbarState.strokeWidthValues(for: optionsToolbarMode)

        if optionsToolbarMode == .text {
            if layout.textBold.contains(point) {
                closeTextDropdown()
                currentStyle.textBold.toggle()
                rememberCurrentStyleForActiveTool()
                applyCurrentStyleToSelectedAnnotation()
                return true
            }
            if layout.textItalic.contains(point) {
                closeTextDropdown()
                currentStyle.textItalic.toggle()
                rememberCurrentStyleForActiveTool()
                applyCurrentStyleToSelectedAnnotation()
                return true
            }
            if layout.textOutline.contains(point) {
                closeTextDropdown()
                currentStyle.textOutlineEnabled.toggle()
                rememberCurrentStyleForActiveTool()
                applyCurrentStyleToSelectedAnnotation()
                return true
            }
            if layout.textFont.contains(point) {
                toggleTextDropdown(.font)
                return true
            }
            if layout.textSize.contains(point) {
                toggleTextDropdown(.size)
                return true
            }
        }

        for (index, rect) in layout.strokeWidths.enumerated() where rect.contains(point) {
            closeTextDropdown()
            currentStyle.strokeWidth = strokeWidths[index]
            rememberCurrentStyleForActiveTool()
            applyCurrentStyleToSelectedAnnotation()
            return true
        }

        if let fillRect = layout.fillToggle, fillRect.contains(point) {
            closeTextDropdown()
            currentStyle.fillEnabled.toggle()
            rememberCurrentStyleForActiveTool()
            applyCurrentStyleToSelectedAnnotation()
            return true
        }

        if let rectangleButton = layout.rectangleMode {
            let rectangleDisclosureRect = rectangleDisclosureHitRect(in: rectangleButton)
            if rectangleDisclosureRect.contains(point) {
                closeTextDropdown()
                activateShapeTool(.rectangle)
                applyCurrentStyleToSelectedAnnotation()
                showsCornerRadiusPanel.toggle()
                showsStrokeStyleMenu = false
                showsStartArrowTypeMenu = false
                showsEndArrowTypeMenu = false
                return true
            }

            if rectangleButton.contains(point) {
                closeTextDropdown()
                activateShapeTool(.rectangle)
                applyCurrentStyleToSelectedAnnotation()
                return true
            }
        }

        if let ellipseButton = layout.ellipseMode, ellipseButton.contains(point) {
            closeTextDropdown()
            activateShapeTool(.ellipse)
            showsCornerRadiusPanel = false
            applyCurrentStyleToSelectedAnnotation()
            return true
        }

        if SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode),
           layout.strokeStyle.contains(point) {
            closeTextDropdown()
            showsStrokeStyleMenu.toggle()
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
            return true
        }

        if let startArrowType = layout.startArrowType, startArrowType.contains(point) {
            closeTextDropdown()
            showsStartArrowTypeMenu.toggle()
            showsEndArrowTypeMenu = false
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            return true
        }

        if let endArrowType = layout.endArrowType, endArrowType.contains(point) {
            closeTextDropdown()
            showsEndArrowTypeMenu.toggle()
            showsStartArrowTypeMenu = false
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            return true
        }

        if handleColorSwatchClick(at: point, optionsRect: optionsRect) {
            return true
        }

        if !optionsRect.contains(point) {
            closeTextDropdown()
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
            return false
        }

        return true
    }

    private func handleEraserOptionsClick(at point: NSPoint, optionsRect: NSRect) -> Bool {
        let layout = optionsToolbarLayout(in: optionsRect)
        if let eraserButton = layout.eraserPointMode,
           optionButtonBackgroundRect(for: eraserButton).contains(point) {
            eraserMode = .point
            eraserRectangleStartPoint = nil
            eraserRectangleCurrentPoint = nil
            invalidateCursorRectsAndRefresh(at: point)
            needsDisplay = true
            return true
        }
        if let rectangleButton = layout.eraserRectangleMode,
           optionButtonBackgroundRect(for: rectangleButton).contains(point) {
            eraserMode = .rectangle
            eraserRectangleStartPoint = nil
            eraserRectangleCurrentPoint = nil
            invalidateCursorRectsAndRefresh(at: point)
            needsDisplay = true
            return true
        }
        if let clearAllButton = layout.eraserClearAll,
           optionButtonBackgroundRect(for: clearAllButton).contains(point) {
            eraserRectangleStartPoint = nil
            eraserRectangleCurrentPoint = nil
            _ = clearAllAnnotationsAndMasks()
            invalidateCursorRectsAndRefresh(at: point)
            needsDisplay = true
            return true
        }
        return optionsRect.contains(point)
    }

    private func handleNumberOptionsClick(at point: NSPoint, optionsRect: NSRect) -> Bool {
        if let selectedType = numberMarkTypeMenuHitTarget(at: point) {
            setNumberMarkType(selectedType)
            activeNumberDropdown = false
            needsDisplay = true
            return true
        }

        let layout = optionsToolbarLayout(in: optionsRect)
        if layout.numberMarkType.contains(point) {
            closeTextDropdown()
            closeMagnifierZoomDropdown()
            activeNumberDropdown.toggle()
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
            needsDisplay = true
            return true
        }

        if layout.numberSize.contains(point) {
            activeNumberDropdown = false
            toggleTextDropdown(.size)
            return true
        }

        if handleColorSwatchClick(at: point, optionsRect: optionsRect) {
            activeNumberDropdown = false
            return true
        }

        if !optionsRect.contains(point) {
            activeNumberDropdown = false
            closeTextDropdown()
            return false
        }

        return true
    }

    private func handleMagnifierOptionsClick(at point: NSPoint, optionsRect: NSRect) -> Bool {
        let layout = optionsToolbarLayout(in: optionsRect)
        if activeMagnifierZoomDropdown {
            let menu = magnifierZoomMenuRect(in: optionsRect)
            if menu.contains(point) {
                for (index, rect) in magnifierZoomMenuItemRects(in: menu).enumerated() where rect.contains(point) {
                    applyMagnifierZoom(SelectionToolbarState.magnifierZoomValues[index])
                    return true
                }
                return true
            }
            if !layout.magnifierZoom.contains(point) {
                closeMagnifierZoomDropdown()
            }
        }

        if let rectangleButton = layout.rectangleMode, rectangleButton.contains(point) {
            closeMagnifierZoomDropdown()
            currentMagnifierShape = .rectangle
            applyCurrentMagnifierSettingsToSelectedAnnotation()
            needsDisplay = true
            return true
        }
        if let circleButton = layout.ellipseMode, circleButton.contains(point) {
            closeMagnifierZoomDropdown()
            currentMagnifierShape = .circle
            applyCurrentMagnifierSettingsToSelectedAnnotation()
            needsDisplay = true
            return true
        }
        if layout.magnifierZoom.contains(point) {
            toggleMagnifierZoomDropdown()
            return true
        }
        let strokeWidths = SelectionToolbarState.strokeWidthValues(for: .magnifier)
        for (index, rect) in layout.strokeWidths.enumerated() where rect.contains(point) {
            closeMagnifierZoomDropdown()
            currentStyle.strokeWidth = strokeWidths[index]
            rememberCurrentStyleForActiveTool()
            applyCurrentStyleToSelectedAnnotation()
            return true
        }
        if let swatch = SelectionToolbarState.swatchHitTarget(at: point, in: optionsRect, paletteCount: visiblePaletteCount, mode: optionsToolbarMode) {
            closeMagnifierZoomDropdown()
            switch swatch {
            case .custom:
                return handleColorSwatchClick(at: point, optionsRect: optionsRect)
            case let .palette(index):
                guard colors.indices.contains(index) else {
                    return true
                }
                let color = colors[index]
                currentStyle.strokeColor = color
                currentStyle.fillColor = color
                rememberCurrentStyleForActiveTool()
                customColor = nil
                isCustomColorSwatchActive = false
                closeCustomColorPanel()
                applyCurrentStyleToSelectedAnnotation()
                return true
            }
        }
        if !optionsRect.contains(point) {
            closeMagnifierZoomDropdown()
            return false
        }
        return optionsRect.contains(point)
    }

    private func handleColorSwatchClick(at point: NSPoint, optionsRect: NSRect) -> Bool {
        guard let swatch = SelectionToolbarState.swatchHitTarget(at: point, in: optionsRect, paletteCount: visiblePaletteCount, mode: optionsToolbarMode) else {
            return false
        }

        closeTextDropdown()
        switch swatch {
        case .custom:
            NSLog("xxsnap overlay custom color swatch clicked")
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
            isCustomColorSwatchActive = true
            toggleCustomColorPanel()
        case let .palette(index):
            guard colors.indices.contains(index) else {
                return true
            }
            let color = opaqueColor(colors[index])
            currentStyle.strokeColor = color
            currentStyle.fillColor = color
            rememberCurrentStyleForActiveTool()
            customColor = nil
            isCustomColorSwatchActive = false
            closeCustomColorPanel()
            applyCurrentStyleToSelectedAnnotation()
            invalidateMarkerCursorIfNeeded()
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
        }
        return true
    }

    private func numberMarkTypeMenuHitTarget(at point: NSPoint) -> CaptureNumberMarkType? {
        guard activeNumberDropdown, let optionsToolbarRect else {
            return nil
        }
        let menu = numberMarkTypeMenuRect(in: optionsToolbarRect)
        guard menu.contains(point) else {
            return nil
        }
        return CaptureNumberMarkType.allCases.enumerated().first { index, _ in
            numberMarkTypeMenuItemRects(in: menu)[index].contains(point)
        }?.element
    }

    private func setNumberMarkType(_ type: CaptureNumberMarkType) {
        let previousType = currentNumberMarkType
        currentNumberMarkType = type
        switch type {
        case .number:
            if previousType != .number {
                let defaultColor = Self.defaultNumberStyle().strokeColor
                currentStyle.strokeColor = defaultColor
                currentStyle.fillColor = defaultColor
                customColor = nil
                isCustomColorSwatchActive = false
            }
        case .check:
            currentStyle.strokeColor = NSColor.systemGreen
            currentStyle.fillColor = NSColor.systemGreen
            customColor = nil
            isCustomColorSwatchActive = false
        case .cross:
            currentStyle.strokeColor = NSColor.systemRed
            currentStyle.fillColor = NSColor.systemRed
            customColor = nil
            isCustomColorSwatchActive = false
        }
        rememberCurrentStyleForActiveTool()
        applyCurrentStyleToSelectedAnnotation()
        applyCurrentNumberMarkTypeToSelectedAnnotation(type)
        invalidateCursorRectsAndRefresh()
    }

    private func applyCurrentNumberMarkTypeToSelectedAnnotation(_ type: CaptureNumberMarkType) {
        guard let selectedAnnotationIndex,
              annotationIsEditable(at: selectedAnnotationIndex),
              annotations[selectedAnnotationIndex].kind == .numberSequence,
              selectedNumberAnnotationCanFollowTypeDropdown
        else {
            return
        }

        annotations[selectedAnnotationIndex].numberMarkType = type
        switch type {
        case .number:
            if annotations[selectedAnnotationIndex].numberSequenceIndex == nil {
                annotations[selectedAnnotationIndex].numberSequenceIndex = nextNumberSequenceIndex(excluding: selectedAnnotationIndex)
                annotations[selectedAnnotationIndex].numberSequenceIsManual = false
            }
        case .check, .cross:
            annotations[selectedAnnotationIndex].numberSequenceIndex = nil
            annotations[selectedAnnotationIndex].numberSequenceIsManual = false
        }
        clearRedoAnnotationHistory()
        needsDisplay = true
    }

    private func applyTextSize(_ size: CGFloat) {
        currentStyle.textSize = isNumberToolActive ? clampedNumberSize(size) : max(3, min(72, size))
        rememberCurrentStyleForActiveTool()
        applyCurrentStyleToSelectedAnnotation()
        needsDisplay = true
    }

    private func applyTextFontFamily(_ family: String) {
        currentStyle.textFontFamily = family
        rememberCurrentStyleForActiveTool()
        applyCurrentStyleToSelectedAnnotation()
        needsDisplay = true
    }

    private func currentTextFontFamily() -> String {
        currentStyle.textFontFamily ?? NSFont.systemFont(ofSize: 12).familyName ?? "System"
    }

    private func toggleTextDropdown(_ kind: TextDropdownKind) {
        if activeTextDropdown == kind {
            closeTextDropdown()
            return
        }
        activeTextDropdown = kind
        closeMagnifierZoomDropdown()
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        scrollTextDropdownSelectionIntoView(kind)
        needsDisplay = true
    }

    private func closeTextDropdown() {
        guard activeTextDropdown != nil else {
            return
        }
        activeTextDropdown = nil
        textDropdownScrollRemainderY = 0
        needsDisplay = true
    }

    private func toggleMagnifierZoomDropdown() {
        activeMagnifierZoomDropdown.toggle()
        activeNumberDropdown = false
        closeTextDropdown()
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        needsDisplay = true
    }

    private func closeMagnifierZoomDropdown() {
        guard activeMagnifierZoomDropdown else {
            return
        }
        activeMagnifierZoomDropdown = false
        needsDisplay = true
    }

    private func applyMagnifierZoom(_ zoom: CGFloat) {
        currentMagnifierZoom = zoom
        applyCurrentMagnifierSettingsToSelectedAnnotation()
        closeMagnifierZoomDropdown()
        needsDisplay = true
    }

    private func handleTextDropdownClick(at point: NSPoint) -> Bool {
        guard let kind = activeTextDropdown, let menu = textDropdownRect(for: kind) else {
            return false
        }
        if menu.contains(point) {
            let startIndex = textDropdownScrollOffset(for: kind)
            for (visibleIndex, rect) in textDropdownItemRects(in: menu, kind: kind).enumerated() where rect.contains(point) {
                applyTextDropdownSelection(kind, at: startIndex + visibleIndex)
                closeTextDropdown()
                return true
            }
            return true
        }
        if let optionsRect = optionsToolbarRect {
            let layout = optionsToolbarLayout(in: optionsRect)
            let activeField = textDropdownAnchorField(for: kind, in: layout)
            if activeField.contains(point) {
                return false
            }
        }
        closeTextDropdown()
        return false
    }

    private func handleTextDropdownScroll(at point: NSPoint, deltaY: CGFloat) -> Bool {
        guard let kind = activeTextDropdown, let menu = textDropdownRect(for: kind), menu.contains(point) else {
            return false
        }
        textDropdownScrollRemainderY += deltaY
        let stepDelta: CGFloat = 8
        let steps = Int(abs(textDropdownScrollRemainderY) / stepDelta)
        guard steps > 0 else {
            return true
        }

        let direction = textDropdownScrollRemainderY < 0 ? 1 : -1
        setTextDropdownScrollOffset(textDropdownScrollOffset(for: kind) + direction * steps, for: kind)
        textDropdownScrollRemainderY = textDropdownScrollRemainderY.truncatingRemainder(dividingBy: stepDelta)
        needsDisplay = true
        return true
    }

    private func applyTextDropdownSelection(_ kind: TextDropdownKind, at index: Int) {
        switch kind {
        case .font:
            guard !isNumberToolActive else {
                return
            }
            let families = SelectionToolbarState.installedTextFontFamilies()
            guard families.indices.contains(index) else {
                return
            }
            applyTextFontFamily(families[index])
        case .size:
            let sizes = textSizeValuesForActiveTool()
            guard sizes.indices.contains(index) else {
                return
            }
            applyTextSize(sizes[index])
        }
    }

    private func scrollTextDropdownSelectionIntoView(_ kind: TextDropdownKind) {
        let selectedIndex: Int
        switch kind {
        case .font:
            if isNumberToolActive {
                selectedIndex = 0
                break
            }
            let families = SelectionToolbarState.installedTextFontFamilies()
            selectedIndex = families.firstIndex(of: currentTextFontFamily()) ?? 0
        case .size:
            selectedIndex = textSizeValuesForActiveTool().firstIndex { Int($0.rounded()) == Int(currentStyle.textSize.rounded()) } ?? 0
        }
        let visibleCount = textDropdownVisibleItemCount(for: kind)
        let currentOffset = textDropdownScrollOffset(for: kind)
        if selectedIndex < currentOffset {
            setTextDropdownScrollOffset(selectedIndex, for: kind)
        } else if selectedIndex >= currentOffset + visibleCount {
            setTextDropdownScrollOffset(selectedIndex - visibleCount + 1, for: kind)
        } else {
            setTextDropdownScrollOffset(currentOffset, for: kind)
        }
    }

    private func textDropdownRect(for kind: TextDropdownKind) -> NSRect? {
        guard (optionsToolbarMode == .text || (optionsToolbarMode == .numberSequence && kind == .size)),
              let optionsRect = optionsToolbarRect else {
            return nil
        }
        let layout = optionsToolbarLayout(in: optionsRect)
        let field = textDropdownAnchorField(for: kind, in: layout)
        let height = CGFloat(textDropdownVisibleItemCount(for: kind)) * textDropdownItemHeight + 8
        return SelectionToolbarState.popoverRect(
            size: NSSize(width: max(field.width, kind == .font ? 154 : 48), height: height),
            anchoredTo: field,
            inside: safeLayoutBounds
        )
    }

    private func textDropdownAnchorField(for kind: TextDropdownKind, in layout: SelectionToolbarState.OptionsToolbarLayout) -> NSRect {
        if optionsToolbarMode == .numberSequence, kind == .size {
            return layout.numberSize
        }
        return kind == .font ? layout.textFont : layout.textSize
    }

    private func textSizeValuesForActiveTool() -> [CGFloat] {
        isNumberToolActive ? SelectionToolbarState.numberSizeValues : SelectionToolbarState.textSizeValues
    }

    private var textDropdownItemHeight: CGFloat {
        22
    }

    private func textDropdownVisibleItemCount(for kind: TextDropdownKind) -> Int {
        min(8, max(1, textDropdownItemCount(for: kind)))
    }

    private func textDropdownItemCount(for kind: TextDropdownKind) -> Int {
        switch kind {
        case .font:
            return SelectionToolbarState.installedTextFontFamilies().count
        case .size:
            return textSizeValuesForActiveTool().count
        }
    }

    private func textDropdownScrollOffset(for kind: TextDropdownKind) -> Int {
        switch kind {
        case .font:
            return textFontDropdownScrollOffset
        case .size:
            return textSizeDropdownScrollOffset
        }
    }

    private func setTextDropdownScrollOffset(_ offset: Int, for kind: TextDropdownKind) {
        let maxOffset = max(0, textDropdownItemCount(for: kind) - textDropdownVisibleItemCount(for: kind))
        let clamped = max(0, min(maxOffset, offset))
        switch kind {
        case .font:
            textFontDropdownScrollOffset = clamped
        case .size:
            textSizeDropdownScrollOffset = clamped
        }
    }

    private func textDropdownItemRects(in menu: NSRect, kind: TextDropdownKind) -> [NSRect] {
        let visibleCount = textDropdownVisibleItemCount(for: kind)
        return (0..<visibleCount).map { index in
            NSRect(
                x: menu.minX + 4,
                y: menu.maxY - 4 - textDropdownItemHeight * CGFloat(index + 1),
                width: menu.width - (textDropdownItemCount(for: kind) > visibleCount ? 12 : 8),
                height: textDropdownItemHeight
            )
        }
    }

    private func handleMosaicOptionsClick(at point: NSPoint, optionsRect: NSRect) -> Bool {
        let dotRects = SelectionToolbarState.strokeWidthRects(in: optionsRect)
        let dotValues = SelectionToolbarState.strokeWidthValues(for: .mosaic)
        for (index, rect) in dotRects.enumerated() where rect.contains(point) {
            commitMosaicValueEditing()
            mosaicDotIndex = index
            currentStyle.strokeWidth = dotValues[index]
            if currentShapeKind != .mosaicStroke {
                selectedAnnotationIndex = nil
                activateShapeTool(.mosaicStroke)
            }
            rememberCurrentStyleForActiveTool()
            if selectedAnnotation?.kind == .mosaicStroke {
                applyCurrentStyleToSelectedAnnotation()
            }
            invalidateCursorRectsAndRefresh()
            return true
        }

        let valueRect = SelectionToolbarState.mosaicRedactionValueRect(in: optionsRect)
        if valueRect.contains(point) {
            beginMosaicValueEditing()
            updateMosaicValue(from: point)
            interactionMode = .draggingMosaicValue
            return true
        }

        let layout = optionsToolbarLayout(in: optionsRect)
        if let rectangleRect = layout.rectangleMode, rectangleRect.contains(point) {
            commitMosaicValueEditing()
            if currentShapeKind != .mosaicRectangle {
                selectedAnnotationIndex = nil
            }
            activateShapeTool(.mosaicRectangle)
            return true
        }

        let pixelRect = SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsRect)
        if pixelRect.contains(point) {
            commitMosaicValueEditing()
            mosaicRedactionType = mosaicRedactionType == .pixelMosaic ? .gaussianBlur : .pixelMosaic
            applyCurrentMosaicRedactionToSelectedAnnotation()
            hoveredTooltip = tooltipTarget(at: point)
            needsDisplay = true
            return true
        }

        return optionsRect.contains(point)
    }

    private func beginMosaicValueEditing() {
        mosaicValueEditingText = nil
        needsDisplay = true
    }

    private func commitMosaicValueEditing() {
        guard let text = mosaicValueEditingText else {
            return
        }
        if let value = Int(text) {
            setCurrentMosaicValue(value)
        }
        mosaicValueEditingText = nil
        needsDisplay = true
    }

    private func handleMosaicValueEditingKeyDown(_ event: NSEvent) -> Bool {
        guard mosaicValueEditingText != nil else {
            return false
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            commitMosaicValueEditing()
            return true
        }

        if event.keyCode == 51 {
            mosaicValueEditingText = String((mosaicValueEditingText ?? "").dropLast())
            needsDisplay = true
            return true
        }

        guard let characters = event.charactersIgnoringModifiers, characters.allSatisfy(\.isNumber) else {
            return true
        }
        let next = String(((mosaicValueEditingText ?? "") + characters).prefix(2))
        mosaicValueEditingText = next
        if let value = Int(next) {
            setCurrentMosaicValue(value)
        }
        needsDisplay = true
        return true
    }

    private func adjustCurrentMosaicValue(by delta: Int) {
        let current = mosaicRedactionValues[mosaicRedactionType] ?? SelectionToolbarState.mosaicDefaultRedactionValue(for: mosaicRedactionType)
        setCurrentMosaicValue(current + delta)
    }

    private func updateMosaicValue(from point: NSPoint) {
        guard let optionsRect = optionsToolbarRect else {
            return
        }
        let valueRect = SelectionToolbarState.mosaicRedactionValueRect(in: optionsRect)
        let track = mosaicValueSliderTrackRect(in: valueRect)
        let progress = min(1, max(0, (point.x - track.minX) / max(track.width, 1)))
        let value = Int((5 + progress * 15).rounded())
        setCurrentMosaicValue(value)
    }

    private func setCurrentMosaicValue(_ value: Int) {
        let clampedValue = min(20, max(5, value))
        if mosaicRedactionValues[mosaicRedactionType] == clampedValue {
            return
        }

        mosaicRedactionValues[mosaicRedactionType] = clampedValue
        applyCurrentMosaicRedactionToSelectedAnnotation()
        needsDisplay = true
    }

    private func applyCurrentMosaicRedactionToSelectedAnnotation() {
        guard let selectedAnnotationIndex, annotationIsEditable(at: selectedAnnotationIndex) else {
            return
        }
        guard annotations[selectedAnnotationIndex].kind == .mosaicStroke || annotations[selectedAnnotationIndex].kind == .mosaicRectangle else {
            return
        }
        let nextRedaction = mosaicRedaction(for: annotations[selectedAnnotationIndex].kind)
        if annotations[selectedAnnotationIndex].mosaicRedaction == nextRedaction {
            return
        }

        annotations[selectedAnnotationIndex].mosaicRedaction = nextRedaction
        resetMosaicRedactionPreviewCaches()
        needsDisplay = true
    }

    private func updateTextAnnotationRect(at index: Int) {
        guard annotations.indices.contains(index), annotations[index].kind == .text else {
            return
        }

        let origin = annotations[index].rect.origin
        annotations[index].rect.size = textAnnotationSize(
            text: annotations[index].text ?? "",
            style: annotations[index].style
        )
        annotations[index].rect.origin = origin
        if let lockedSelectionRect {
            let overlayRect = overlayRect(fromLocalAnnotationRect: annotations[index].rect)
            annotations[index].rect = localAnnotationRect(
                from: clamp(rect: overlayRect, inside: lockedSelectionRect.standardized)
            )
        }
    }

    private func handleStrokeStyleMenuClick(at point: NSPoint) -> Bool {
        guard
            showsStrokeStyleMenu,
            SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode),
            let optionsRect = optionsToolbarRect
        else {
            return false
        }

        let menu = strokeStyleMenuRect(in: optionsRect)
        let options = strokePatternOptions
        switch SelectionToolbarState.strokeMenuHitTarget(at: point, in: menu, itemCount: options.count) {
        case let .item(index):
            guard options.indices.contains(index) else {
                return true
            }
            let option = options[index]
            guard option.isEnabled else {
                return true
            }
            currentStyle.strokePattern = option.pattern
            rememberCurrentStyleForActiveTool()
            applyCurrentStyleToSelectedAnnotation()
            showsStrokeStyleMenu = false
            needsDisplay = true
            NSLog("xxsnap overlay selected stroke pattern=%ld", option.pattern.rawValue)
            return true
        case .menuBackground:
            return true
        case .outside:
            return false
        }
    }

    private func handleArrowTypeMenuClick(at point: NSPoint) -> Bool {
        guard showsStartArrowTypeMenu || showsEndArrowTypeMenu, let optionsRect = optionsToolbarRect else {
            return false
        }

        if showsStartArrowTypeMenu, handleArrowTypeMenuClick(at: point, field: .start, optionsRect: optionsRect) {
            return true
        }

        if showsEndArrowTypeMenu, handleArrowTypeMenuClick(at: point, field: .end, optionsRect: optionsRect) {
            return true
        }

        return false
    }

    private func handleArrowTypeMenuClick(at point: NSPoint, field: ArrowTypeField, optionsRect: NSRect) -> Bool {
        let menu = arrowTypeMenuRect(in: optionsRect, field: field)
        let options = CaptureArrowType.allCases
        switch SelectionToolbarState.arrowTypeMenuHitTarget(at: point, in: menu, itemCount: options.count) {
        case let .item(index):
            guard options.indices.contains(index) else {
                return true
            }
            switch field {
            case .start:
                let pair = SelectionToolbarState.arrowTypesAfterSelection(
                    currentStart: currentStartArrowType,
                    currentEnd: currentEndArrowType,
                    selectedType: options[index],
                    endpoint: .start
                )
                currentStartArrowType = pair.start
                currentEndArrowType = pair.end
                showsStartArrowTypeMenu = false
            case .end:
                let pair = SelectionToolbarState.arrowTypesAfterSelection(
                    currentStart: currentStartArrowType,
                    currentEnd: currentEndArrowType,
                    selectedType: options[index],
                    endpoint: .end
                )
                currentStartArrowType = pair.start
                currentEndArrowType = pair.end
                showsEndArrowTypeMenu = false
            }
            applyCurrentStyleToSelectedAnnotation()
            needsDisplay = true
            return true
        case .menuBackground:
            return true
        case .outside:
            return false
        }
    }

    private func handleCornerRadiusPanelClick(at point: NSPoint) -> Bool {
        guard showsCornerRadiusPanel, let panel = cornerRadiusPanelRect else {
            return false
        }

        let valueRect = cornerRadiusValueRect(in: panel)
        if cornerRadiusUpRect(in: valueRect).contains(point) {
            currentStyle.cornerRadius = min(30, currentStyle.cornerRadius + 1)
            rememberCurrentStyleForActiveTool()
            applyCurrentStyleToSelectedAnnotation()
            return true
        }
        if cornerRadiusDownRect(in: valueRect).contains(point) {
            currentStyle.cornerRadius = max(0, currentStyle.cornerRadius - 1)
            rememberCurrentStyleForActiveTool()
            applyCurrentStyleToSelectedAnnotation()
            return true
        }
        if cornerRadiusSliderTrackRect(in: panel, valueRect: valueRect).insetBy(dx: -8, dy: -8).contains(point) {
            interactionMode = .draggingCornerRadius
            updateCornerRadius(from: point)
            return true
        }

        return panel.contains(point)
    }

    private func updateCornerRadius(from point: NSPoint) {
        guard let panel = cornerRadiusPanelRect else {
            return
        }

        let valueRect = cornerRadiusValueRect(in: panel)
        let track = cornerRadiusSliderTrackRect(in: panel, valueRect: valueRect)
        let ratio = min(1, max(0, (point.x - track.minX) / max(1, track.width)))
        currentStyle.cornerRadius = round(ratio * 30)
        rememberCurrentStyleForActiveTool()
        applyCurrentStyleToSelectedAnnotation()
    }

    private func appendBrushDraftPointIfNeeded(
        _ point: NSPoint,
        modifierFlags: NSEvent.ModifierFlags = []
    ) {
        guard currentShapeKind == .brush else {
            return
        }

        if modifierFlags.contains(.shift), let shapeStartPoint {
            brushDraftPoints = [shapeStartPoint, point]
            return
        }

        if let last = brushDraftPoints.last, hypot(point.x - last.x, point.y - last.y) < 1.5 {
            return
        }
        brushDraftPoints.append(point)
    }

    private func appendMosaicDraftPointIfNeeded(
        _ point: NSPoint,
        modifierFlags: NSEvent.ModifierFlags = []
    ) {
        guard currentShapeKind == .mosaicStroke else {
            return
        }

        if modifierFlags.contains(.shift), let shapeStartPoint {
            mosaicDraftPoints = [shapeStartPoint, point]
            return
        }

        if let last = mosaicDraftPoints.last, hypot(point.x - last.x, point.y - last.y) < 1.5 {
            return
        }
        mosaicDraftPoints.append(point)
    }

    private func axisLockedPoint(start: NSPoint, rawEnd: NSPoint) -> NSPoint {
        let dx = rawEnd.x - start.x
        let dy = rawEnd.y - start.y
        if abs(dx) >= abs(dy) {
            return NSPoint(x: rawEnd.x, y: start.y)
        }
        return NSPoint(x: start.x, y: rawEnd.y)
    }

    private var selectedAnnotation: CaptureAnnotation? {
        guard let selectedAnnotationIndex,
              annotationIsEditable(at: selectedAnnotationIndex) else {
            return nil
        }

        return annotations[selectedAnnotationIndex]
    }

    private func clearSelectedAnnotationIfNeededForActiveTool() {
        guard let selectedAnnotation, !activeToolCanEdit(annotationKind: selectedAnnotation.kind) else {
            return
        }

        selectedAnnotationIndex = nil
        showsCornerRadiusPanel = false
        showsStrokeStyleMenu = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
    }

    private func activeToolCanEdit(annotationKind kind: CaptureAnnotationKind) -> Bool {
        if isTextToolActive {
            return kind == .text
        }

        if isMagnifierToolActive {
            return kind == .magnifier
        }

        guard isShapeToolActive else {
            return true
        }

        switch currentShapeKind {
        case .arrowLine:
            return kind == .arrowLine
        case .brush:
            return false
        case .marker:
            return kind == .marker
        case .magnifier:
            return kind == .magnifier
        case .mosaicStroke, .mosaicRectangle:
            return kind == .mosaicStroke || kind == .mosaicRectangle
        case .rectangle, .ellipse:
            return kind == .rectangle || kind == .ellipse
        case .text:
            return kind == .text
        case .numberSequence:
            return kind == .numberSequence
        }
    }

    private func selectAnnotation(at index: Int) {
        guard annotationIsEditable(at: index) else {
            selectedAnnotationIndex = nil
            return
        }

        selectedAnnotationIndex = index
        let annotation = annotations[index]
        if annotation.kind == .text {
            activateTextTool()
            selectedAnnotationIndex = index
            currentStyle = annotation.style
            rememberCurrentStyleForActiveTool()
            return
        }
        if annotation.kind == .numberSequence {
            activateNumberTool()
            selectedAnnotationIndex = index
            selectNumberSequenceGroup(for: annotation)
            selectedNumberAnnotationCanFollowTypeDropdown = true
            currentNumberMarkType = annotation.numberMarkType ?? .number
            currentStyle = annotation.style
            rememberCurrentStyleForActiveTool()
            return
        }
        if annotation.kind == .magnifier {
            activateMagnifierTool()
            selectedAnnotationIndex = index
            currentStyle = annotation.style
            magnifierStyle = annotation.style
            currentMagnifierShape = annotation.effectiveMagnifierShape
            currentMagnifierZoom = annotation.effectiveMagnifierZoom
            rememberCurrentStyleForActiveTool()
            return
        }
        activateShapeTool(annotation.kind)
        currentStyle = annotation.style
        rememberCurrentStyleForActiveTool()
        if let arrowLine = annotation.arrowLine {
            currentStartArrowType = arrowLine.startArrowType
            currentEndArrowType = arrowLine.endArrowType
        }
        if let mosaicRedaction = annotation.mosaicRedaction {
            mosaicRedactionType = mosaicRedaction.type
            mosaicRedactionValues[mosaicRedaction.type] = mosaicRedaction.value
        }
        if annotation.kind == .mosaicStroke {
            let widths = SelectionToolbarState.strokeWidthValues(for: .mosaic)
            if let index = widths.enumerated().min(by: { abs($0.element - annotation.style.strokeWidth) < abs($1.element - annotation.style.strokeWidth) })?.offset {
                mosaicDotIndex = index
            }
        }
        if annotation.kind == .marker {
            invalidateCursorRectsAndRefresh()
        }
    }

    private func selectNumberSequenceGroup(for annotation: CaptureAnnotation) {
        guard annotation.kind == .numberSequence,
              annotation.numberMarkType == .number || annotation.numberMarkType == nil
        else {
            return
        }

        currentNumberSequenceGroupID = annotation.numberSequenceGroupID
        nextNumberSequenceIndexAfterReset = nil
    }

    private func applyCurrentStyleToSelectedAnnotation() {
        guard let selectedAnnotationIndex, annotationIsEditable(at: selectedAnnotationIndex) else {
            return
        }

        annotations[selectedAnnotationIndex].style = SelectionToolbarState.updatedSelectedAnnotationStyle(
            kind: annotations[selectedAnnotationIndex].kind,
            existingStyle: annotations[selectedAnnotationIndex].style,
            currentStyle: currentStyle
        )
        if annotations[selectedAnnotationIndex].kind == .mosaicStroke || annotations[selectedAnnotationIndex].kind == .mosaicRectangle {
            annotations[selectedAnnotationIndex].mosaicRedaction = mosaicRedaction(for: annotations[selectedAnnotationIndex].kind)
            resetMosaicPreviewCaches()
        }
        if annotations[selectedAnnotationIndex].kind == .text {
            updateTextAnnotationRect(at: selectedAnnotationIndex)
            if selectedAnnotationIndex == editingTextAnnotationIndex, let textEditor {
                applyTextEditorStyle(textEditor, style: annotations[selectedAnnotationIndex].style)
                layoutTextEditorForCurrentAnnotation()
                window?.makeFirstResponder(textEditor)
            }
        } else if annotations[selectedAnnotationIndex].kind == .arrowLine {
            if var arrowLine = annotations[selectedAnnotationIndex].arrowLine {
                arrowLine.startArrowType = currentStartArrowType
                arrowLine.endArrowType = currentEndArrowType
                annotations[selectedAnnotationIndex].arrowLine = arrowLine
                annotations[selectedAnnotationIndex].rect = arrowLine.boundingRect
            }
        } else if annotations[selectedAnnotationIndex].kind == .numberSequence {
            annotations[selectedAnnotationIndex].style.textSize = clampedNumberSize(annotations[selectedAnnotationIndex].style.textSize)
            if annotations[selectedAnnotationIndex].numberSequenceIndex != nil {
                annotations[selectedAnnotationIndex].numberSequenceIndex = min(999, max(1, annotations[selectedAnnotationIndex].numberSequenceIndex ?? 1))
            }
            let overlayRect = overlayRect(fromLocalAnnotationRect: annotations[selectedAnnotationIndex].rect).standardized
            let center = NSPoint(x: overlayRect.midX, y: overlayRect.midY)
            let resizedRect = CaptureAnnotationRenderer.numberMarkRect(
                centeredAt: center,
                fontSize: annotations[selectedAnnotationIndex].style.textSize
            )
            annotations[selectedAnnotationIndex].rect = localAnnotationRect(from: resizedRect)
        } else if annotations[selectedAnnotationIndex].kind == .magnifier {
            annotations[selectedAnnotationIndex].magnifierShape = currentMagnifierShape
            annotations[selectedAnnotationIndex].magnifierZoom = currentMagnifierZoom
        } else if SelectionToolbarState.annotationKindSupportsPostDrawEditing(annotations[selectedAnnotationIndex].kind) {
            annotations[selectedAnnotationIndex].kind = currentShapeKind
        }
        clearRedoAnnotationHistory()
        needsDisplay = true
    }

    private func applyCurrentMagnifierSettingsToSelectedAnnotation() {
        guard let selectedAnnotationIndex,
              annotationIsEditable(at: selectedAnnotationIndex),
              annotations[selectedAnnotationIndex].kind == .magnifier
        else {
            rememberCurrentStyleForActiveTool()
            return
        }
        annotations[selectedAnnotationIndex].magnifierShape = currentMagnifierShape
        annotations[selectedAnnotationIndex].magnifierZoom = currentMagnifierZoom
        clearRedoAnnotationHistory()
        rememberCurrentStyleForActiveTool()
    }

    private func opaqueColor(_ color: NSColor) -> NSColor {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        return converted.withAlphaComponent(1)
    }

    private func toggleCustomColorPanel() {
        if NSColorPanel.shared.isVisible {
            closeCustomColorPanel()
            return
        }

        window?.level = .floating
        window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSColorPanel.shared
        panel.level = .modalPanel
        panel.showsAlpha = false
        panel.color = customColor ?? currentStyle.strokeColor
        panel.setTarget(self)
        panel.setAction(#selector(customColorChanged(_:)))
        positionCustomColorPanel(panel)
        panel.orderFrontRegardless()
        NSLog("xxsnap overlay opened custom color panel")
    }

    @objc private func customColorChanged(_ sender: NSColorPanel) {
        let color = opaqueColor(sender.color)
        customColor = color
        isCustomColorSwatchActive = true
        currentStyle.strokeColor = color
        currentStyle.fillColor = color
        rememberCurrentStyleForActiveTool()
        applyCurrentStyleToSelectedAnnotation()
        invalidateMarkerCursorIfNeeded()
        needsDisplay = true
    }

    private func invalidateMarkerCursorIfNeeded() {
        guard isShapeToolActive, currentShapeKind == .marker else {
            return
        }

        invalidateCursorRectsAndRefresh()
    }

    private func closeCustomColorPanel() {
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderOut(nil)
    }

    private func positionCustomColorPanel(_ panel: NSColorPanel) {
        guard
            let optionsRect = optionsToolbarRect,
            let customSwatchRect = colorSwatchRects(in: optionsRect).last,
            let window
        else {
            return
        }

        let panelSize = panel.frame.size
        let overlayPanelRect = SelectionToolbarState.popoverRect(
            size: panelSize,
            anchoredTo: customSwatchRect,
            inside: safeLayoutBounds
        )
        let screenRect = window.convertToScreen(overlayPanelRect)
        panel.setFrameOrigin(screenRect.origin)
    }

    private func commitSelectedShapePreview() {
        movingAnnotationStartRect = nil
        movingAnnotationStartArrowLine = nil
        movingAnnotationStartBrushPath = nil
        movingAnnotationStartMarkerLine = nil
        movingAnnotationStartMosaicStroke = nil
        resizingAnnotationStartRect = nil
        resizingAnnotationStartStyle = nil
        resizingArrowLineStart = nil
        activeArrowLineHandle = nil
        resizingMarkerLineStart = nil
        activeMarkerLineHandle = nil
        rotatingBrushStartPath = nil
        activeBrushRotationHandle = nil
        mosaicGeometryEditingStartAnnotations.removeAll()
        mosaicGeometryEditingStartComposite = nil
        mosaicGeometryEditingStartCompositeKey = nil
        clearRedoAnnotationHistory()
        needsDisplay = true
    }

    private func captureMosaicGeometryEditingStartState() {
        let start = CFAbsoluteTimeGetCurrent()
        mosaicGeometryEditingStartAnnotations = annotations
        mosaicGeometryEditingStartComposite = cachedFullMosaicPreviewComposite(for: annotations)
        if let backgroundImage {
            mosaicGeometryEditingStartCompositeKey = mosaicCompositeKey(for: annotations, backgroundImage: backgroundImage)
        } else {
            mosaicGeometryEditingStartCompositeKey = nil
        }
        if hasMosaicPerformanceWork {
            logMosaicPerformanceEvent(
                "geometry-start",
                startTime: start,
                details: "startComposite=\(mosaicGeometryEditingStartComposite == nil ? "miss" : "hit") startKey=\(mosaicGeometryEditingStartCompositeKey == nil ? "nil" : "set")"
            )
        }
    }

    private func commitSelectionResize() {
        if let lockedSelectionRect {
            let rect = lockedSelectionRect.standardized
            self.lockedSelectionRect = rect
        }
        activeSelectionResizeHandle = nil
        resizingSelectionStartRect = nil
        resizingSelectionStartAnnotationRects.removeAll()
        resizingSelectionStartAnnotations.removeAll()
        clearRedoAnnotationHistory()
        needsDisplay = true
    }

    private func commitSelectionMove() {
        movingSelectionStartRect = nil
        movingSelectionBounds = nil
        movingSelectionPointerOffset = .zero
        movingSelectionStartAnnotationRects.removeAll()
        movingSelectionStartAnnotations.removeAll()
        needsDisplay = true
    }

    private func startToolbarDragIfPossible(at point: NSPoint) -> Bool {
        guard isMainToolbarDragPoint(point) else {
            return false
        }

        NSCursor.xxsnapMove.set()
        toolbarDragStartPoint = point
        toolbarDragStartOffset = mainToolbarOffset
        interactionMode = .draggingToolbar
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        return true
    }

    private func updateDraggingToolbar(to point: NSPoint) {
        guard
            let selectionRect,
            let toolbarDragStartPoint,
            let baseToolbar = baseMainToolbarRect(for: selectionRect)
        else {
            return
        }

        let requestedOffset = NSSize(
            width: toolbarDragStartOffset.width + point.x - toolbarDragStartPoint.x,
            height: toolbarDragStartOffset.height + point.y - toolbarDragStartPoint.y
        )
        let layoutBounds = mainToolbarLayoutBounds(for: selectionRect)
        let dragged = SelectionToolbarState.draggedToolbarRect(
            baseRect: baseToolbar,
            offset: requestedOffset,
            inside: layoutBounds
        )
        mainToolbarOffset = NSSize(width: dragged.minX - baseToolbar.minX, height: dragged.minY - baseToolbar.minY)
    }

    private func commitToolbarDrag() {
        toolbarDragStartPoint = nil
        toolbarDragStartOffset = .zero
        needsDisplay = true
    }

    private func annotationIndexForBorder(at point: NSPoint) -> Int? {
        for index in annotations.indices.reversed() where annotationIsEditable(at: index) {
            if annotationBorderContains(point, for: annotations[index]) {
                return index
            }
        }
        return nil
    }

    private func numberAnnotationIndex(at point: NSPoint) -> Int? {
        for index in annotations.indices.reversed() where annotationIsEditable(at: index) && annotations[index].kind == .numberSequence {
            let rect = overlayRect(fromLocalAnnotationRect: annotations[index].rect).standardized.insetBy(dx: -6, dy: -6)
            if rect.contains(point) {
                return index
            }
        }
        return nil
    }

    private func updateRevealedNumberControls(at point: NSPoint) {
        let previous = revealedNumberControlsIndex
        if let index = numberAnnotationIndex(at: point) {
            revealedNumberControlsIndex = index
        } else if let index = revealedNumberControlsIndex,
                  annotations.indices.contains(index),
                  numberControlsRegionContains(point, for: annotations[index]) {
            revealedNumberControlsIndex = index
        } else {
            revealedNumberControlsIndex = nil
        }

        if previous != revealedNumberControlsIndex {
            needsDisplay = true
        }
    }

    private func numberControlsRegionContains(_ point: NSPoint, for annotation: CaptureAnnotation) -> Bool {
        guard annotation.kind == .numberSequence else {
            return false
        }
        let outlineRect = numberEditingOutlineRect(for: annotation)
        if outlineRect.insetBy(dx: -16, dy: -16).contains(point) {
            return true
        }
        return [.delete, .resize, .increment, .decrement, .reset].contains { kind in
            numberHandleRect(for: annotation, kind: kind)?.insetBy(dx: -8, dy: -8).contains(point) == true
        }
    }

    private func numberEditingOutlineRect(for annotation: CaptureAnnotation) -> NSRect {
        overlayRect(fromLocalAnnotationRect: annotation.rect).standardized.insetBy(dx: -4, dy: -4)
    }

    private func shouldShowSelectedNumberControls() -> Bool {
        guard let selectedAnnotationIndex,
              annotations.indices.contains(selectedAnnotationIndex),
              annotationIsEditable(at: selectedAnnotationIndex),
              annotations[selectedAnnotationIndex].kind == .numberSequence
        else {
            return false
        }
        return true
    }

    private func numberHandleRect(for annotation: CaptureAnnotation, kind: NumberHandleKind) -> NSRect? {
        guard annotation.kind == .numberSequence else {
            return nil
        }
        let rect = numberEditingOutlineRect(for: annotation)
        let size: CGFloat
        switch kind {
        case .resize:
            size = 7.5
        case .increment, .decrement, .reset:
            size = 12
        case .delete:
            size = 15
        }
        let outsideLeftCenterX = rect.minX - size / 2 - 2
        let center: NSPoint
        switch kind {
        case .delete:
            center = NSPoint(x: rect.maxX, y: rect.maxY)
        case .resize:
            center = NSPoint(x: rect.maxX, y: rect.minY)
        case .increment:
            guard annotation.numberMarkType == .number || annotation.numberMarkType == nil else {
                return nil
            }
            center = NSPoint(x: outsideLeftCenterX, y: rect.maxY)
        case .decrement:
            guard annotation.numberMarkType == .number || annotation.numberMarkType == nil else {
                return nil
            }
            center = NSPoint(x: outsideLeftCenterX, y: rect.maxY - size)
        case .reset:
            guard (annotation.numberMarkType == .number || annotation.numberMarkType == nil),
                  (annotation.numberSequenceIndex ?? 1) > 1
            else {
                return nil
            }
            center = NSPoint(x: outsideLeftCenterX, y: rect.minY)
        }
        return NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    }

    private func numberHandleHitTarget(at point: NSPoint) -> NumberHandleHit? {
        guard interactionMode == .annotating,
              let selectedAnnotationIndex,
              annotations.indices.contains(selectedAnnotationIndex),
              annotations[selectedAnnotationIndex].kind == .numberSequence,
              activeToolCanEdit(annotationKind: .numberSequence),
              shouldShowSelectedNumberControls()
        else {
            return nil
        }

        let kinds: [NumberHandleKind] = [.delete, .resize, .increment, .decrement, .reset]
        for kind in kinds {
            if kind == .increment, !canAdjustNumberAnnotation(delta: 1) {
                continue
            }
            if kind == .decrement, !canAdjustNumberAnnotation(delta: -1) {
                continue
            }
            if let rect = numberHandleRect(for: annotations[selectedAnnotationIndex], kind: kind),
               rect.insetBy(dx: -3, dy: -3).contains(point) {
                return NumberHandleHit(index: selectedAnnotationIndex, kind: kind)
            }
        }
        return nil
    }

    private func disabledNumberAdjustmentHandleContains(_ point: NSPoint) -> Bool {
        guard interactionMode == .annotating,
              let selectedAnnotationIndex,
              annotations.indices.contains(selectedAnnotationIndex),
              annotations[selectedAnnotationIndex].kind == .numberSequence,
              activeToolCanEdit(annotationKind: .numberSequence),
              shouldShowSelectedNumberControls()
        else {
            return false
        }

        let disabledHandles: [(kind: NumberHandleKind, delta: Int)] = [
            (.increment, 1),
            (.decrement, -1),
        ]
        for disabledHandle in disabledHandles where !canAdjustNumberAnnotation(delta: disabledHandle.delta) {
            if let rect = numberHandleRect(for: annotations[selectedAnnotationIndex], kind: disabledHandle.kind),
               rect.insetBy(dx: -3, dy: -3).contains(point) {
                return true
            }
        }
        return false
    }

    private func textAnnotationIndex(at point: NSPoint) -> Int? {
        for index in annotations.indices.reversed() where annotationIsEditable(at: index) && annotations[index].kind == .text {
            if textAnnotationHitContains(point: point, annotation: annotations[index]) {
                return index
            }
        }
        return nil
    }

    private func textAnnotationBorderIndex(at point: NSPoint) -> Int? {
        for index in annotations.indices.reversed() where annotationIsEditable(at: index) && annotations[index].kind == .text {
            if textAnnotationBorderContains(point: point, annotation: annotations[index]) {
                return index
            }
        }
        return nil
    }

    private func eraserAnnotationIndex(at point: NSPoint) -> Int? {
        for index in annotations.indices.reversed() where eraserContains(point, annotation: annotations[index], index: index) {
            return index
        }
        return nil
    }

    private func eraserContains(_ point: NSPoint, annotation: CaptureAnnotation, index: Int) -> Bool {
        switch annotation.kind {
        case .rectangle, .ellipse:
            let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
            return rect.insetBy(dx: -4, dy: -4).contains(point)
        case .arrowLine:
            guard let arrowLine = overlayArrowLine(fromLocalArrowLine: annotation.arrowLine) else {
                return false
            }
            return SelectionToolbarState.arrowLineHitTarget(at: point, line: arrowLine) != .none
        case .brush:
            guard let path = overlayBrushPath(fromLocalBrushPath: annotation.brushPath) else {
                return false
            }
            return brushPathContains(point, path: path, hitOutset: max(8, annotation.style.strokeWidth / 2 + 4))
        case .marker:
            guard let line = overlayMarkerLine(fromLocalMarkerLine: annotation.markerLine) else {
                return false
            }
            return SelectionToolbarState.markerLineContains(
                point: point,
                line: line,
                hitOutset: max(8, annotation.style.strokeWidth / 2 + 4)
            )
        case .text, .magnifier, .mosaicRectangle:
            return rotatedAnnotationRectContains(point, annotation: annotation, hitOutset: 6)
        case .numberSequence:
            let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized.insetBy(dx: -6, dy: -6)
            return rect.contains(point)
        case .mosaicStroke:
            guard let stroke = overlayMosaicStroke(fromLocalMosaicStroke: annotation.mosaicStroke) else {
                return false
            }
            return mosaicStrokeContains(point, stroke: stroke, hitOutset: max(8, annotation.style.strokeWidth / 2 + 4))
        }
    }

    private func damagedAnnotationIndex(at point: NSPoint) -> Int? {
        for index in annotations.indices.reversed() where !annotationIsEditable(at: index) {
            if eraserContains(point, annotation: annotations[index], index: index) {
                return index
            }
        }
        return nil
    }

    private var eraserRectanglePreviewRect: NSRect? {
        guard let start = eraserRectangleStartPoint, let current = eraserRectangleCurrentPoint else {
            return nil
        }
        return NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        ).standardized
    }

    private var hasEraserMasksForDrawing: Bool {
        eraserMasks.contains { !$0.affectedAnnotationIDs.subtracting(suppressedAnnotationIDs).isEmpty }
    }

    private func commitEraserRectangle() {
        guard let overlayRect = eraserRectanglePreviewRect, overlayRect.width >= 3, overlayRect.height >= 3 else {
            needsDisplay = true
            return
        }
        guard let effectiveOverlayRect = effectiveOverlayEraserRect(from: overlayRect) else {
            needsDisplay = true
            return
        }

        let affectedIDs = Set(
            annotations.compactMap { annotation in
                eraserRectangleIntersects(effectiveOverlayRect, annotation: annotation) ? annotation.id : nil
            }
        )
        guard !affectedIDs.isEmpty,
              let localRect = localRectFromOverlayEraserRect(effectiveOverlayRect)
        else {
            needsDisplay = true
            return
        }

        let mask = EraserMask(rect: localRect, affectedAnnotationIDs: affectedIDs)
        eraserMasks.append(mask)
        undoAnnotationEntries.append(.addEraserMask(mask: mask))
        clearRedoAnnotationHistory()
        selectedAnnotationIndex = nil
        editingTextAnnotationIndex = nil
        clearNumberEditing()
        clearPendingTextEdit()
        removeTextEditor()
        resetMosaicPreviewCaches()
        needsDisplay = true
    }

    private func effectiveOverlayEraserRect(from rect: NSRect) -> NSRect? {
        guard lockedSelectionRect != nil else {
            return nil
        }
        let effectiveRect = rect.standardized
        guard effectiveRect.width > 0, effectiveRect.height > 0 else {
            return nil
        }
        return effectiveRect
    }

    private func localRectFromOverlayEraserRect(_ rect: NSRect) -> NSRect? {
        guard let lockedSelectionRect else {
            return nil
        }
        let localRect = NSRect(
            x: rect.minX - lockedSelectionRect.minX,
            y: rect.minY - lockedSelectionRect.minY,
            width: rect.width,
            height: rect.height
        ).standardized
        guard localRect.width > 0, localRect.height > 0 else {
            return nil
        }
        return localRect
    }

    private func eraserRectangleIntersects(_ rect: NSRect, annotation: CaptureAnnotation) -> Bool {
        if annotationKindSupportsRotationHandle(annotation.kind),
           abs(annotation.rotationAngle) >= 0.001 {
            return eraserRectangleIntersectsRotatedAnnotationRect(rect, annotation: annotation)
        }
        guard let bounds = eraserRectangleVisualBounds(for: annotation) else {
            return false
        }
        return rect.intersects(bounds)
    }

    private func eraserRectangleIntersectsRotatedAnnotationRect(_ eraserRect: NSRect, annotation: CaptureAnnotation) -> Bool {
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
        let eraserRect = eraserRect.standardized
        guard rect.width > 0, rect.height > 0, eraserRect.width > 0, eraserRect.height > 0 else {
            return false
        }
        let polygon = rotatedRectangleCorners(for: rect, angle: annotation.rotationAngle)
        let eraserCorners = rectangleCorners(for: eraserRect)
        if polygon.contains(where: { eraserRect.contains($0) }) {
            return true
        }
        if eraserCorners.contains(where: { point($0, isInsideConvexPolygon: polygon) }) {
            return true
        }
        let polygonEdges = edges(for: polygon)
        let eraserEdges = edges(for: eraserCorners)
        return polygonEdges.contains { polygonEdge in
            eraserEdges.contains { eraserEdge in
                segmentsIntersect(polygonEdge.0, polygonEdge.1, eraserEdge.0, eraserEdge.1)
            }
        }
    }

    private func eraserRectangleVisualBounds(for annotation: CaptureAnnotation) -> NSRect? {
        switch annotation.kind {
        case .rectangle, .ellipse, .text, .numberSequence, .magnifier, .mosaicRectangle:
            return overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
        case .arrowLine:
            let fallback = eraserFallbackVisualBounds(for: annotation)
            guard let line = overlayArrowLine(fromLocalArrowLine: annotation.arrowLine) else {
                return fallback
            }
            return eraserStrokeVisualBounds(line.boundingRect, annotation: annotation, fallback: fallback)
        case .brush:
            let fallback = eraserFallbackVisualBounds(for: annotation)
            guard let path = overlayBrushPath(fromLocalBrushPath: annotation.brushPath) else {
                return fallback
            }
            return eraserStrokeVisualBounds(path.boundingRect, annotation: annotation, fallback: fallback)
        case .marker:
            let fallback = eraserFallbackVisualBounds(for: annotation)
            guard let line = overlayMarkerLine(fromLocalMarkerLine: annotation.markerLine) else {
                return fallback
            }
            return eraserStrokeVisualBounds(line.boundingRect, annotation: annotation, fallback: fallback)
        case .mosaicStroke:
            let fallback = eraserFallbackVisualBounds(for: annotation)
            guard let stroke = overlayMosaicStroke(fromLocalMosaicStroke: annotation.mosaicStroke) else {
                return fallback
            }
            return eraserStrokeVisualBounds(stroke.boundingRect, annotation: annotation, fallback: fallback)
        }
    }

    private func eraserFallbackVisualBounds(for annotation: CaptureAnnotation) -> NSRect {
        let padding = max(0, annotation.style.strokeWidth / 2)
        return overlayRect(fromLocalAnnotationRect: annotation.rect)
            .standardized
            .insetBy(dx: -padding, dy: -padding)
    }

    private func eraserStrokeVisualBounds(_ rect: NSRect, annotation: CaptureAnnotation, fallback: NSRect) -> NSRect {
        let bounds = rect.standardized
        if bounds.isEmpty {
            return fallback
        }
        let padding = max(0, annotation.style.strokeWidth / 2)
        return bounds.insetBy(dx: -padding, dy: -padding)
    }

    private func rotatedRectangleCorners(for rect: NSRect, angle: CGFloat) -> [NSPoint] {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return rectangleCorners(for: rect).map { rotatedPoint($0, around: center, angle: angle) }
    }

    private func rectangleCorners(for rect: NSRect) -> [NSPoint] {
        [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.maxY),
        ]
    }

    private func edges(for points: [NSPoint]) -> [(NSPoint, NSPoint)] {
        guard points.count >= 2 else {
            return []
        }
        return points.indices.map { index in
            (points[index], points[(index + 1) % points.count])
        }
    }

    private func point(_ point: NSPoint, isInsideConvexPolygon polygon: [NSPoint]) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }
        let epsilon: CGFloat = 0.0001
        var hasPositive = false
        var hasNegative = false
        for (start, end) in edges(for: polygon) {
            let cross = crossProduct(start, end, point)
            if cross > epsilon {
                hasPositive = true
            } else if cross < -epsilon {
                hasNegative = true
            }
            if hasPositive && hasNegative {
                return false
            }
        }
        return true
    }

    private func segmentsIntersect(_ a: NSPoint, _ b: NSPoint, _ c: NSPoint, _ d: NSPoint) -> Bool {
        let epsilon: CGFloat = 0.0001
        let abC = crossProduct(a, b, c)
        let abD = crossProduct(a, b, d)
        let cdA = crossProduct(c, d, a)
        let cdB = crossProduct(c, d, b)
        if abs(abC) <= epsilon, point(c, isOnSegmentFrom: a, to: b) {
            return true
        }
        if abs(abD) <= epsilon, point(d, isOnSegmentFrom: a, to: b) {
            return true
        }
        if abs(cdA) <= epsilon, point(a, isOnSegmentFrom: c, to: d) {
            return true
        }
        if abs(cdB) <= epsilon, point(b, isOnSegmentFrom: c, to: d) {
            return true
        }
        return (abC > 0) != (abD > 0) && (cdA > 0) != (cdB > 0)
    }

    private func point(_ point: NSPoint, isOnSegmentFrom start: NSPoint, to end: NSPoint) -> Bool {
        let epsilon: CGFloat = 0.0001
        return point.x >= min(start.x, end.x) - epsilon &&
            point.x <= max(start.x, end.x) + epsilon &&
            point.y >= min(start.y, end.y) - epsilon &&
            point.y <= max(start.y, end.y) + epsilon
    }

    private func crossProduct(_ start: NSPoint, _ end: NSPoint, _ point: NSPoint) -> CGFloat {
        (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x)
    }

    private func annotationBorderContains(_ point: NSPoint, for annotation: CaptureAnnotation) -> Bool {
        if annotation.kind == .arrowLine {
            guard let arrowLine = overlayArrowLine(fromLocalArrowLine: annotation.arrowLine) else {
                return false
            }
            return SelectionToolbarState.arrowLineHitTarget(at: point, line: arrowLine) == .body
        }
        if annotation.kind == .brush {
            return false
        }
        if annotation.kind == .mosaicStroke {
            return false
        }
        if annotation.kind == .mosaicRectangle {
            return rotatedAnnotationRectContains(point, annotation: annotation, hitOutset: 4)
        }
        if annotation.kind == .marker {
            guard let markerLine = overlayMarkerLine(fromLocalMarkerLine: annotation.markerLine) else {
                return false
            }
            let hitOutset = max(8, annotation.style.strokeWidth / 2 + 4)
            if isZeroLengthMarkerLine(markerLine) {
                return SelectionToolbarState.markerLineContains(point: point, line: markerLine, hitOutset: hitOutset)
            }
            if hypot(point.x - markerLine.start.x, point.y - markerLine.start.y) <= hitOutset
                || hypot(point.x - markerLine.end.x, point.y - markerLine.end.y) <= hitOutset {
                return false
            }
            return SelectionToolbarState.markerLineContains(point: point, line: markerLine, hitOutset: hitOutset)
        }
        if annotation.kind == .text {
            return textAnnotationHitContains(point: point, annotation: annotation)
        }
        if annotation.kind == .numberSequence {
            return false
        }
        if annotation.kind == .magnifier {
            return rotatedAnnotationRectContains(point, annotation: annotation, hitOutset: 4)
        }

        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
        return SelectionToolbarState.shapeBorderContains(
            point: point,
            rect: rect,
            kind: annotation.kind,
            cornerRadius: annotation.style.cornerRadius
        )
    }

    private func textAnnotationHitContains(point: NSPoint, annotation: CaptureAnnotation) -> Bool {
        rotatedAnnotationRectContains(point, annotation: annotation, hitOutset: 6)
    }

    private func textAnnotationBorderContains(point: NSPoint, annotation: CaptureAnnotation) -> Bool {
        rotatedAnnotationBorderContains(point, annotation: annotation, hitOutset: 6)
    }

    private func shouldBeginTextEditingFromClick(at point: NSPoint, annotation: CaptureAnnotation) -> Bool {
        guard textAnnotationBorderContains(point: point, annotation: annotation) else {
            return true
        }

        if let handle = textResizeHandle(at: point, annotation: annotation) {
            return handle == .left || handle == .right
        }
        return false
    }

    private func textAwareResizeHandle(at point: NSPoint) -> ShapeResizeHandle? {
        if let handle = resizeHandle(at: point) {
            return handle
        }
        guard
            let selectedAnnotation,
            selectedAnnotation.kind == .text
        else {
            return nil
        }
        return fullscreenTextEdgeResizeHandle(at: point, annotation: selectedAnnotation)
    }

    private func textResizeHandle(at point: NSPoint, annotation: CaptureAnnotation) -> ShapeResizeHandle? {
        resizeHandle(at: point) ?? fullscreenTextEdgeResizeHandle(at: point, annotation: annotation)
    }

    private func fullscreenTextEdgeResizeHandle(at point: NSPoint, annotation: CaptureAnnotation) -> ShapeResizeHandle? {
        guard
            annotation.kind == .text,
            abs(annotation.rotationAngle) < 0.001,
            let lockedSelectionRect
        else {
            return nil
        }

        let selectionRect = lockedSelectionRect.standardized
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
        let tolerance: CGFloat = 6
        guard
            abs(rect.minX - selectionRect.minX) <= tolerance,
            abs(rect.maxX - selectionRect.maxX) <= tolerance,
            abs(rect.minY - selectionRect.minY) <= tolerance,
            abs(rect.maxY - selectionRect.maxY) <= tolerance,
            textAnnotationBorderContains(point: point, annotation: annotation)
        else {
            return nil
        }

        let distances: [(handle: ShapeResizeHandle, distance: CGFloat)] = [
            (.top, abs(point.y - rect.maxY)),
            (.right, abs(point.x - rect.maxX)),
            (.bottom, abs(point.y - rect.minY)),
            (.left, abs(point.x - rect.minX)),
        ]
        return distances
            .filter { $0.distance <= tolerance }
            .min { $0.distance < $1.distance }?
            .handle
    }

    private func textDeleteHandleHitTarget(at point: NSPoint) -> Int? {
        guard interactionMode == .annotating,
              let selectedAnnotationIndex,
              annotations.indices.contains(selectedAnnotationIndex),
              annotationIsEditable(at: selectedAnnotationIndex),
              annotations[selectedAnnotationIndex].kind == .text,
              activeToolCanEdit(annotationKind: .text),
              let rect = textDeleteHandleRect(for: annotations[selectedAnnotationIndex])
        else {
            return nil
        }

        return rect.insetBy(dx: -3, dy: -3).contains(point) ? selectedAnnotationIndex : nil
    }

    private func textDeleteHandleRect(for annotation: CaptureAnnotation) -> NSRect? {
        guard annotation.kind == .text else {
            return nil
        }

        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect)
        let handle = handleRect(
            for: rect,
            handle: .topRight,
            kind: annotation.kind,
            rotationAngle: annotation.rotationAngle
        )
        return NSRect(
            x: handle.midX - textDeleteHandleIconSize / 2,
            y: handle.midY - textDeleteHandleIconSize / 2,
            width: textDeleteHandleIconSize,
            height: textDeleteHandleIconSize
        )
    }

    private func resizeHandle(at point: NSPoint) -> ShapeResizeHandle? {
        guard let annotation = selectedAnnotation else {
            return nil
        }
        guard activeToolCanEdit(annotationKind: annotation.kind) else {
            return nil
        }
        guard SelectionToolbarState.annotationKindSupportsGeometryEditing(annotation.kind) else {
            return nil
        }

        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect)
        let rotationAngle = annotationKindSupportsRotationHandle(annotation.kind) ? annotation.rotationAngle : 0
        for handle in ShapeResizeHandle.allCases where handleRect(
            for: rect,
            handle: handle,
            kind: annotation.kind,
            rotationAngle: rotationAngle
        ).insetBy(dx: -3, dy: -3).contains(point) {
            return handle
        }
        return nil
    }

    private func arrowLineHitTarget(at point: NSPoint) -> (index: Int, target: SelectionToolbarState.ArrowLineHitTarget)? {
        for index in annotations.indices.reversed() where annotationIsEditable(at: index) && annotations[index].kind == .arrowLine {
            guard let arrowLine = overlayArrowLine(fromLocalArrowLine: annotations[index].arrowLine) else {
                continue
            }
            let target = SelectionToolbarState.arrowLineHitTarget(at: point, line: arrowLine)
            if target != .none {
                return (index, target)
            }
        }
        return nil
    }

    private func brushRotationHitTarget(at point: NSPoint) -> (index: Int, target: SelectionToolbarState.BrushRotationHitTarget)? {
        guard let selectedAnnotationIndex,
              annotationIsEditable(at: selectedAnnotationIndex),
              annotations[selectedAnnotationIndex].kind == .brush,
              activeToolCanEdit(annotationKind: annotations[selectedAnnotationIndex].kind),
              let brushPath = overlayBrushPath(fromLocalBrushPath: annotations[selectedAnnotationIndex].brushPath)
        else {
            return nil
        }

        let target = SelectionToolbarState.brushRotationHitTarget(at: point, path: brushPath)
        if target != .none {
            return (selectedAnnotationIndex, target)
        }
        return nil
    }

    private func markerRotationHitTarget(at point: NSPoint) -> (index: Int, target: SelectionToolbarState.BrushRotationHitTarget)? {
        for index in annotations.indices.reversed() where annotationIsEditable(at: index) && annotations[index].kind == .marker {
            guard activeToolCanEdit(annotationKind: annotations[index].kind) else {
                continue
            }
            guard let markerLine = overlayMarkerLine(fromLocalMarkerLine: annotations[index].markerLine) else {
                continue
            }
            guard !isZeroLengthMarkerLine(markerLine) else {
                continue
            }
            let target = SelectionToolbarState.markerRotationHitTarget(at: point, line: markerLine)
            if target != .none {
                return (index, target)
            }
        }
        return nil
    }

    private func isZeroLengthMarkerLine(_ markerLine: CaptureMarkerLine) -> Bool {
        hypot(markerLine.end.x - markerLine.start.x, markerLine.end.y - markerLine.start.y) < 0.5
    }

    private func selectionResizeHandle(at point: NSPoint) -> SelectionToolbarState.OverlayResizeHandle? {
        guard configuration.allowsSelectionGeometryEditing else {
            return nil
        }
        guard let lockedSelectionRect else {
            return nil
        }

        return SelectionToolbarState.selectionResizeHandle(at: point, in: lockedSelectionRect)
    }

    private func shouldStartSelectionMove(at point: NSPoint) -> Bool {
        guard configuration.allowsSelectionGeometryEditing else {
            return false
        }
        guard let lockedSelectionRect else {
            return false
        }

        if isTextToolActive {
            NSLog(
                "xxsnap selection move blocked textTool=yes point=(%.0f, %.0f) mode=%@ editing=%@ pendingText=%@ selected=%@",
                point.x,
                point.y,
                String(describing: interactionMode),
                editingTextAnnotationIndex.map { "\($0)" } ?? "none",
                pendingTextEditAnnotationIndex.map { "\($0)" } ?? "none",
                selectedAnnotationIndex.map { "\($0)" } ?? "none"
            )
            return false
        }

        if hasDamagedAnnotations {
            return false
        }

        return SelectionToolbarState.shouldStartSelectionMove(
            isShapeToolActive: isShapeToolActive,
            pointer: point,
            selectionRect: lockedSelectionRect,
            screenBounds: screenBounds(containing: lockedSelectionRect),
            selectionResizeHandle: selectionResizeHandle(at: point)
        )
    }

    private func startSelectionMoveIfPossible(at point: NSPoint) {
        guard shouldStartSelectionMove(at: point), let lockedSelectionRect else {
            return
        }

        NSCursor.xxsnapMove.set()
        movingSelectionStartRect = lockedSelectionRect.standardized
        movingSelectionStartAnnotationRects = annotations.map { overlayRect(fromLocalAnnotationRect: $0.rect) }
        movingSelectionStartAnnotations = annotations
        movingSelectionPointerOffset = NSPoint(
            x: point.x - lockedSelectionRect.minX,
            y: point.y - lockedSelectionRect.minY
        )
        movingSelectionBounds = screenBounds(containing: lockedSelectionRect)
        NSLog(
            "xxsnap selection move begin point=(%.0f, %.0f) rect=%@ offset=(%.0f, %.0f) selected=%@ textTool=%@",
            point.x,
            point.y,
            NSStringFromRect(lockedSelectionRect.standardized),
            movingSelectionPointerOffset.x,
            movingSelectionPointerOffset.y,
            selectedAnnotationIndex.map { "\($0)" } ?? "none",
            isTextToolActive ? "yes" : "no"
        )
        sampledPointerPoint = nil
        sampledColor = nil
        interactionMode = .movingSelection
        selectedAnnotationIndex = nil
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
    }

    private func updateMovingShape(to point: NSPoint) {
        guard
            let selectedAnnotationIndex,
            annotationIsEditable(at: selectedAnnotationIndex),
            let movingAnnotationStartRect
        else {
            return
        }

        NSCursor.xxsnapMove.set()
        let requested = NSRect(
            x: point.x - movingAnnotationOffset.x,
            y: point.y - movingAnnotationOffset.y,
            width: movingAnnotationStartRect.width,
            height: movingAnnotationStartRect.height
        )
        if let movingAnnotationStartArrowLine {
            let dx = requested.minX - movingAnnotationStartRect.minX
            let dy = requested.minY - movingAnnotationStartRect.minY
            let movedOverlayLine = offsetArrowLine(movingAnnotationStartArrowLine, dx: dx, dy: dy)
            let localLine = localArrowLine(fromOverlayArrowLine: movedOverlayLine)
            annotations[selectedAnnotationIndex].arrowLine = localLine
            annotations[selectedAnnotationIndex].rect = localLine.boundingRect
            return
        }
        if let movingAnnotationStartBrushPath {
            let dx = requested.minX - movingAnnotationStartRect.minX
            let dy = requested.minY - movingAnnotationStartRect.minY
            let movedOverlayPath = offsetBrushPath(movingAnnotationStartBrushPath, dx: dx, dy: dy)
            let localPath = localBrushPath(fromOverlayBrushPath: movedOverlayPath)
            annotations[selectedAnnotationIndex].brushPath = localPath
            annotations[selectedAnnotationIndex].rect = localPath.boundingRect
            return
        }
        if let movingAnnotationStartMarkerLine {
            let dx = requested.minX - movingAnnotationStartRect.minX
            let dy = requested.minY - movingAnnotationStartRect.minY
            let movedOverlayLine = offsetMarkerLine(movingAnnotationStartMarkerLine, dx: dx, dy: dy)
            let localLine = localMarkerLine(fromOverlayMarkerLine: movedOverlayLine)
            annotations[selectedAnnotationIndex].markerLine = localLine
            annotations[selectedAnnotationIndex].rect = localLine.boundingRect
            return
        }
        if let movingAnnotationStartMosaicStroke {
            let dx = requested.minX - movingAnnotationStartRect.minX
            let dy = requested.minY - movingAnnotationStartRect.minY
            let movedOverlayStroke = offsetMosaicStroke(movingAnnotationStartMosaicStroke, dx: dx, dy: dy)
            let localStroke = localMosaicStroke(fromOverlayStroke: movedOverlayStroke)
            annotations[selectedAnnotationIndex].mosaicStroke = localStroke
            annotations[selectedAnnotationIndex].rect = localStroke.boundingRect
            return
        }

        annotations[selectedAnnotationIndex].rect = localAnnotationRect(from: requested)
    }

    private func updateMovingSelection(to point: NSPoint) {
        guard
            let movingSelectionStartRect,
            let movingSelectionBounds
        else {
            return
        }

        lockedSelectionRect = SelectionToolbarState.movedSelectionRect(
            startRect: movingSelectionStartRect,
            pointer: point,
            pointerOffset: movingSelectionPointerOffset,
            inside: movingSelectionBounds
        )

        if let lockedSelectionRect {
            let preservedRects = SelectionToolbarState.localAnnotationRectsPreservingOverlayPositions(
                movingSelectionStartAnnotationRects,
                selectionRect: lockedSelectionRect
            )
            for index in annotations.indices where preservedRects.indices.contains(index) {
                if movingSelectionStartAnnotations.indices.contains(index),
                   let arrowLine = movingSelectionStartAnnotations[index].arrowLine {
                    let overlayLine = overlayArrowLine(fromLocalArrowLine: arrowLine, selectionRect: movingSelectionStartRect)
                    let localLine = localArrowLine(fromOverlayArrowLine: overlayLine, selectionRect: lockedSelectionRect)
                    annotations[index].arrowLine = localLine
                    annotations[index].rect = localLine.boundingRect
                } else if movingSelectionStartAnnotations.indices.contains(index),
                          let markerLine = movingSelectionStartAnnotations[index].markerLine {
                    let overlayLine = overlayMarkerLine(fromLocalMarkerLine: markerLine, selectionRect: movingSelectionStartRect)
                    let localLine = localMarkerLine(fromOverlayMarkerLine: overlayLine, selectionRect: lockedSelectionRect)
                    annotations[index].markerLine = localLine
                    annotations[index].rect = localLine.boundingRect
                } else if movingSelectionStartAnnotations.indices.contains(index),
                          let brushPath = movingSelectionStartAnnotations[index].brushPath {
                    let overlayPath = overlayBrushPath(fromLocalBrushPath: brushPath, selectionRect: movingSelectionStartRect)
                    let localPath = localBrushPath(fromOverlayBrushPath: overlayPath, selectionRect: lockedSelectionRect)
                    annotations[index].brushPath = localPath
                    annotations[index].rect = localPath.boundingRect
                } else if movingSelectionStartAnnotations.indices.contains(index),
                          let mosaicStroke = movingSelectionStartAnnotations[index].mosaicStroke {
                    let overlayStroke = overlayMosaicStroke(fromLocalMosaicStroke: mosaicStroke, selectionRect: movingSelectionStartRect)
                    let localStroke = localMosaicStroke(fromOverlayStroke: overlayStroke, selectionRect: lockedSelectionRect)
                    annotations[index].mosaicStroke = localStroke
                    annotations[index].rect = localStroke.boundingRect
                } else {
                    annotations[index].rect = preservedRects[index]
                }
            }
        }
    }

    private func updateResizingShape(to point: NSPoint) {
        guard
            let selectedAnnotationIndex,
            annotationIsEditable(at: selectedAnnotationIndex),
            let activeResizeHandle,
            let resizingAnnotationStartRect
        else {
            return
        }

        if annotations[selectedAnnotationIndex].kind == .numberSequence {
            updateNumberAnnotationResize(
                at: selectedAnnotationIndex,
                to: point,
                startRect: resizingAnnotationStartRect,
                startStyle: resizingAnnotationStartStyle ?? annotations[selectedAnnotationIndex].style
            )
            return
        }

        if annotations[selectedAnnotationIndex].kind == .text {
            updateTextAnnotationResize(
                at: selectedAnnotationIndex,
                to: point,
                handle: activeResizeHandle,
                startRect: resizingAnnotationStartRect,
                startStyle: resizingAnnotationStartStyle ?? annotations[selectedAnnotationIndex].style
            )
            return
        }

        if annotations[selectedAnnotationIndex].kind == .mosaicRectangle,
           abs(annotations[selectedAnnotationIndex].rotationAngle) >= 0.001 {
            updateRotatedMosaicRectangleResize(
                at: selectedAnnotationIndex,
                to: point,
                handle: activeResizeHandle,
                startRect: resizingAnnotationStartRect
            )
            return
        }

        let clampedPoint = clamp(point, to: bounds)
        var minX = resizingAnnotationStartRect.minX
        var maxX = resizingAnnotationStartRect.maxX
        var minY = resizingAnnotationStartRect.minY
        var maxY = resizingAnnotationStartRect.maxY

        switch activeResizeHandle {
        case .topLeft:
            minX = clampedPoint.x
            maxY = clampedPoint.y
        case .top:
            maxY = clampedPoint.y
        case .topRight:
            maxX = clampedPoint.x
            maxY = clampedPoint.y
        case .left:
            minX = clampedPoint.x
        case .right:
            maxX = clampedPoint.x
        case .bottomLeft:
            minX = clampedPoint.x
            minY = clampedPoint.y
        case .bottom:
            minY = clampedPoint.y
        case .bottomRight:
            maxX = clampedPoint.x
            minY = clampedPoint.y
        }

        let resized = NSRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )

        if resized.width >= 8, resized.height >= 8 {
            annotations[selectedAnnotationIndex].rect = localAnnotationRect(from: resized)
        }
    }

    private func updateNumberAnnotationResize(
        at index: Int,
        to point: NSPoint,
        startRect: NSRect,
        startStyle: CaptureAnnotationStyle
    ) {
        let center = NSPoint(x: startRect.midX, y: startRect.midY)
        let startDistance = max(1, hypot(startRect.maxX - center.x, startRect.minY - center.y))
        let currentDistance = max(1, hypot(point.x - center.x, point.y - center.y))
        var style = startStyle
        style.textSize = clampedNumberSize(startStyle.textSize * currentDistance / startDistance)
        let nextRect = CaptureAnnotationRenderer.numberMarkRect(centeredAt: center, fontSize: style.textSize)
        annotations[index].style = style
        annotations[index].rect = localAnnotationRect(from: nextRect)
        currentStyle = style
        numberStyle = style
    }

    private func updateTextAnnotationResize(
        at selectedAnnotationIndex: Int,
        to point: NSPoint,
        handle: ShapeResizeHandle,
        startRect: NSRect,
        startStyle: CaptureAnnotationStyle
    ) {
        guard startRect.width > 0, startRect.height > 0 else {
            return
        }

        let angle = annotations[selectedAnnotationIndex].rotationAngle
        let center = NSPoint(x: startRect.midX, y: startRect.midY)
        let xAxis = NSPoint(x: cos(angle), y: sin(angle))
        let yAxis = NSPoint(x: -sin(angle), y: cos(angle))
        let pointer = clamp(point, to: bounds)
        let localPointer = localPoint(pointer, center: center, xAxis: xAxis, yAxis: yAxis)
        let halfWidth = startRect.width / 2
        let halfHeight = startRect.height / 2

        let isCornerResize: Bool
        let requestedScale: CGFloat
        switch handle {
        case .top:
            isCornerResize = false
            requestedScale = centeredEdgeTextScale(distanceFromCenter: localPointer.y, halfLength: halfHeight)
        case .left:
            isCornerResize = false
            requestedScale = centeredEdgeTextScale(distanceFromCenter: localPointer.x, halfLength: halfWidth)
        case .right:
            isCornerResize = false
            requestedScale = centeredEdgeTextScale(distanceFromCenter: localPointer.x, halfLength: halfWidth)
        case .bottom:
            isCornerResize = false
            requestedScale = centeredEdgeTextScale(distanceFromCenter: localPointer.y, halfLength: halfHeight)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            isCornerResize = true
            requestedScale = max(
                centeredEdgeTextScale(distanceFromCenter: localPointer.x, halfLength: halfWidth),
                centeredEdgeTextScale(distanceFromCenter: localPointer.y, halfLength: halfHeight)
            )
        }

        var newStyle = startStyle
        newStyle.textSize = clampedTextSize(startStyle.textSize * requestedScale)
        let effectiveScale = startStyle.textSize > 0 ? newStyle.textSize / startStyle.textSize : requestedScale
        let newSize = isCornerResize
            ? textAnnotationSize(text: annotations[selectedAnnotationIndex].text ?? "", style: newStyle)
            : NSSize(width: startRect.width * effectiveScale, height: startRect.height * effectiveScale)
        guard newSize.width >= 8, newSize.height >= 8 else {
            return
        }

        annotations[selectedAnnotationIndex].rect = localAnnotationRect(from: NSRect(
            x: center.x - newSize.width / 2,
            y: center.y - newSize.height / 2,
            width: newSize.width,
            height: newSize.height
        ))
        annotations[selectedAnnotationIndex].style = newStyle
        currentStyle = annotations[selectedAnnotationIndex].style
        textStyle = currentStyle
    }

    private func centeredEdgeTextScale(distanceFromCenter: CGFloat, halfLength: CGFloat) -> CGFloat {
        max(0.2, abs(distanceFromCenter) / max(1, halfLength))
    }

    private func clampedTextSize(_ size: CGFloat) -> CGFloat {
        let minimum = SelectionToolbarState.textSizeValues.first ?? 3
        let maximum = SelectionToolbarState.textSizeValues.last ?? 72
        return max(minimum, min(maximum, size))
    }

    private func localPoint(_ point: NSPoint, center: NSPoint, xAxis: NSPoint, yAxis: NSPoint) -> NSPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return NSPoint(
            x: dx * xAxis.x + dy * xAxis.y,
            y: dx * yAxis.x + dy * yAxis.y
        )
    }

    private func updateRotatedMosaicRectangleResize(
        at selectedAnnotationIndex: Int,
        to point: NSPoint,
        handle: ShapeResizeHandle,
        startRect: NSRect
    ) {
        let angle = annotations[selectedAnnotationIndex].rotationAngle
        let center = NSPoint(x: startRect.midX, y: startRect.midY)
        let xAxis = NSPoint(x: cos(angle), y: sin(angle))
        let yAxis = NSPoint(x: -sin(angle), y: cos(angle))
        let centerX = projectedDistance(center, onto: xAxis)
        let centerY = projectedDistance(center, onto: yAxis)
        let pointer = clamp(point, to: bounds)
        let pointerX = projectedDistance(pointer, onto: xAxis)
        let pointerY = projectedDistance(pointer, onto: yAxis)

        var minX = centerX - startRect.width / 2
        var maxX = centerX + startRect.width / 2
        var minY = centerY - startRect.height / 2
        var maxY = centerY + startRect.height / 2

        switch handle {
        case .topLeft:
            minX = pointerX
            maxY = pointerY
        case .top:
            maxY = pointerY
        case .topRight:
            maxX = pointerX
            maxY = pointerY
        case .left:
            minX = pointerX
        case .right:
            maxX = pointerX
        case .bottomLeft:
            minX = pointerX
            minY = pointerY
        case .bottom:
            minY = pointerY
        case .bottomRight:
            maxX = pointerX
            minY = pointerY
        }

        let width = abs(maxX - minX)
        let height = abs(maxY - minY)
        let resizedCenterX = (minX + maxX) / 2
        let resizedCenterY = (minY + maxY) / 2
        let resizedCenter = NSPoint(
            x: xAxis.x * resizedCenterX + yAxis.x * resizedCenterY,
            y: xAxis.y * resizedCenterX + yAxis.y * resizedCenterY
        )
        let resized = NSRect(
            x: resizedCenter.x - width / 2,
            y: resizedCenter.y - height / 2,
            width: width,
            height: height
        )

        if resized.width >= 8, resized.height >= 8 {
            annotations[selectedAnnotationIndex].rect = localAnnotationRect(from: resized)
        }
    }

    private func updateResizingArrowLine(to point: NSPoint, modifierFlags: NSEvent.ModifierFlags = []) {
        guard
            let selectedAnnotationIndex,
            annotationIsEditable(at: selectedAnnotationIndex),
            let originalLine = resizingArrowLineStart,
            let activeArrowLineHandle
        else {
            return
        }

        _ = modifierFlags
        let clampedPoint = clamp(point, to: bounds)
        var updatedLine = originalLine
        switch activeArrowLineHandle {
        case .start:
            let delta = NSPoint(
                x: clampedPoint.x - originalLine.start.x,
                y: clampedPoint.y - originalLine.start.y
            )
            updatedLine.start = clampedPoint
            updatedLine.control = NSPoint(
                x: originalLine.control.x + delta.x / 2,
                y: originalLine.control.y + delta.y / 2
            )
        case .end:
            let delta = NSPoint(
                x: clampedPoint.x - originalLine.end.x,
                y: clampedPoint.y - originalLine.end.y
            )
            updatedLine.end = clampedPoint
            updatedLine.control = NSPoint(
                x: originalLine.control.x + delta.x / 2,
                y: originalLine.control.y + delta.y / 2
            )
        case .control:
            updatedLine.control = clampedPoint
        case .body, .none:
            return
        }

        guard hypot(updatedLine.end.x - updatedLine.start.x, updatedLine.end.y - updatedLine.start.y) >= 4 else {
            return
        }

        let localLine = localArrowLine(fromOverlayArrowLine: updatedLine)
        annotations[selectedAnnotationIndex].arrowLine = localLine
        annotations[selectedAnnotationIndex].rect = localLine.boundingRect
    }

    private func updateResizingMarkerLine(to point: NSPoint) {
        guard
            let selectedAnnotationIndex,
            annotationIsEditable(at: selectedAnnotationIndex),
            let originalLine = resizingMarkerLineStart,
            let activeMarkerLineHandle
        else {
            return
        }

        let updatedLine = SelectionToolbarState.resizedMarkerLine(
            originalLine,
            dragging: activeMarkerLineHandle,
            to: clamp(point, to: bounds)
        )
        guard hypot(updatedLine.end.x - updatedLine.start.x, updatedLine.end.y - updatedLine.start.y) >= 8 else {
            return
        }

        let localLine = localMarkerLine(fromOverlayMarkerLine: updatedLine)
        annotations[selectedAnnotationIndex].markerLine = localLine
        annotations[selectedAnnotationIndex].rect = localLine.boundingRect
        NSCursor.resizeUpDown.set()
    }

    private func updateRotatingBrush(to point: NSPoint) {
        guard
            let selectedAnnotationIndex,
            annotationIsEditable(at: selectedAnnotationIndex),
            let rotatingBrushStartPath,
            let activeBrushRotationHandle
        else {
            return
        }

        let rotatedPath = SelectionToolbarState.rotatedBrushPath(
            rotatingBrushStartPath,
            dragging: activeBrushRotationHandle,
            to: clamp(point, to: bounds)
        )
        let localPath = localBrushPath(fromOverlayBrushPath: rotatedPath)
        annotations[selectedAnnotationIndex].brushPath = localPath
        annotations[selectedAnnotationIndex].rect = localPath.boundingRect
        NSCursor.resizeUpDown.set()
    }

    private func updateRotatingMosaicRectangle(to point: NSPoint) {
        guard
            let selectedAnnotationIndex,
            annotationIsEditable(at: selectedAnnotationIndex),
            annotationKindSupportsRotationHandle(annotations[selectedAnnotationIndex].kind),
            let startPointerAngle = rotatingMosaicRectangleStartPointerAngle
        else {
            return
        }

        let center = mosaicRectangleCenter(for: annotations[selectedAnnotationIndex])
        let currentPointerAngle = angle(from: center, to: clamp(point, to: bounds))
        annotations[selectedAnnotationIndex].rotationAngle = rotatingMosaicRectangleStartAnnotationAngle + currentPointerAngle - startPointerAngle
        needsDisplay = true
    }

    private func updateResizingSelection(to point: NSPoint) {
        guard
            let activeSelectionResizeHandle,
            let resizingSelectionStartRect
        else {
            return
        }

        let resized = SelectionToolbarState.resizedSelectionRect(
            from: resizingSelectionStartRect,
            handle: activeSelectionResizeHandle,
            point: clamp(point, to: bounds),
            lockAspectRatio: isSelectionAspectRatioLocked
        )

        guard resized.width >= 8, resized.height >= 8 else {
            return
        }

        lockedSelectionRect = resized
        for index in annotations.indices where resizingSelectionStartAnnotationRects.indices.contains(index) {
            if resizingSelectionStartAnnotations.indices.contains(index),
               let arrowLine = resizingSelectionStartAnnotations[index].arrowLine {
                let overlayLine = overlayArrowLine(fromLocalArrowLine: arrowLine, selectionRect: resizingSelectionStartRect)
                let localLine = localArrowLine(fromOverlayArrowLine: overlayLine, selectionRect: resized)
                annotations[index].arrowLine = localLine
                annotations[index].rect = localLine.boundingRect
            } else if resizingSelectionStartAnnotations.indices.contains(index),
                      let markerLine = resizingSelectionStartAnnotations[index].markerLine {
                let overlayLine = overlayMarkerLine(fromLocalMarkerLine: markerLine, selectionRect: resizingSelectionStartRect)
                let localLine = localMarkerLine(fromOverlayMarkerLine: overlayLine, selectionRect: resized)
                annotations[index].markerLine = localLine
                annotations[index].rect = localLine.boundingRect
            } else if resizingSelectionStartAnnotations.indices.contains(index),
                      let brushPath = resizingSelectionStartAnnotations[index].brushPath {
                let overlayPath = overlayBrushPath(fromLocalBrushPath: brushPath, selectionRect: resizingSelectionStartRect)
                let localPath = localBrushPath(fromOverlayBrushPath: overlayPath, selectionRect: resized)
                annotations[index].brushPath = localPath
                annotations[index].rect = localPath.boundingRect
            } else if resizingSelectionStartAnnotations.indices.contains(index),
                      let mosaicStroke = resizingSelectionStartAnnotations[index].mosaicStroke {
                let overlayStroke = overlayMosaicStroke(fromLocalMosaicStroke: mosaicStroke, selectionRect: resizingSelectionStartRect)
                let localStroke = localMosaicStroke(fromOverlayStroke: overlayStroke, selectionRect: resized)
                annotations[index].mosaicStroke = localStroke
                annotations[index].rect = localStroke.boundingRect
            } else {
                annotations[index].rect = SelectionToolbarState.localAnnotationRect(
                    fromOverlayRect: resizingSelectionStartAnnotationRects[index],
                    selectionRect: resized
                )
            }
        }
    }

    private func handleScrollWheel(at point: NSPoint, deltaY: CGFloat) -> Bool {
        if let pinnedImageScaleHandler = configuration.pinnedImageScaleHandler, deltaY != 0 {
            let factor = deltaY > 0 ? 1.08 : 0.92
            pinnedImageScaleHandler(factor, window?.convertPoint(toScreen: point) ?? NSEvent.mouseLocation)
            return true
        }
        return handleSelectionZoom(at: point, deltaY: deltaY)
    }

    private func handleMagnify(at point: NSPoint, magnification: CGFloat) -> Bool {
        handleSelectionZoom(at: point, deltaY: magnification * 60)
    }

    private func handleSelectionZoom(at point: NSPoint, deltaY: CGFloat) -> Bool {
        guard let lockedSelectionRect else {
            return false
        }
        guard !hasDamagedAnnotations else {
            return false
        }
        guard !isToolbarOrPanelPoint(point) else {
            return false
        }
        guard interactionMode != .selecting else {
            return false
        }
        guard activeDragIsInProgress == false else {
            return false
        }

        let selectionRect = lockedSelectionRect.standardized
        let anchor = selectionRect.contains(point) ? point : NSPoint(x: selectionRect.midX, y: selectionRect.midY)
        let screenBounds = screenBounds(containing: lockedSelectionRect)
        let resized = SelectionToolbarState.wheelZoomedSelectionRect(
            from: selectionRect,
            anchor: anchor,
            deltaY: deltaY,
            inside: screenBounds,
            minimumSize: 64
        )
        guard resized != selectionRect else {
            return true
        }

        startSelectionWheelAnimation(from: selectionRect, to: resized)
        needsDisplay = true
        invalidateCursorRectsAndRefresh(at: point)
        return true
    }

    private var activeDragIsInProgress: Bool {
        switch interactionMode {
        case .selecting, .annotating:
            return false
        default:
            return true
        }
    }

    private func startSelectionWheelAnimation(from startRect: NSRect, to targetRect: NSRect) {
        selectionWheelAnimationTimer?.invalidate()
        selectionWheelAnimationStartTime = CACurrentMediaTime()
        selectionWheelAnimationStartRect = startRect
        selectionWheelAnimationTargetRect = targetRect
        selectionWheelAnimationStartAnnotationRects = annotations.map { overlayRect(fromLocalAnnotationRect: $0.rect) }
        selectionWheelAnimationStartAnnotations = annotations

        updateSelectionWheelAnimation(progress: 0.35)

        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard let startTime = self.selectionWheelAnimationStartTime else {
                timer.invalidate()
                return
            }

            let duration: CFTimeInterval = 0.16
            let rawProgress = min(1, (CACurrentMediaTime() - startTime) / duration)
            let eased = 1 - pow(1 - CGFloat(rawProgress), 3)
            self.updateSelectionWheelAnimation(progress: max(0.35, eased))

            if rawProgress >= 1 {
                timer.invalidate()
                self.clearSelectionWheelAnimationState()
            }
        }
        selectionWheelAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateSelectionWheelAnimation(progress: CGFloat) {
        guard
            let startRect = selectionWheelAnimationStartRect,
            let targetRect = selectionWheelAnimationTargetRect
        else {
            return
        }

        let clampedProgress = min(1, max(0, progress))
        let animatedRect = interpolate(from: startRect, to: targetRect, progress: clampedProgress)
        applySelectionWheelResize(
            from: startRect,
            to: animatedRect,
            startAnnotationRects: selectionWheelAnimationStartAnnotationRects,
            startAnnotations: selectionWheelAnimationStartAnnotations
        )
        needsDisplay = true
    }

    private func completeSelectionWheelAnimation() {
        selectionWheelAnimationTimer?.invalidate()
        selectionWheelAnimationTimer = nil
        updateSelectionWheelAnimation(progress: 1)
        clearSelectionWheelAnimationState()
    }

    private func cancelSelectionWheelAnimation() {
        selectionWheelAnimationTimer?.invalidate()
        clearSelectionWheelAnimationState()
    }

    private func clearSelectionWheelAnimationState() {
        selectionWheelAnimationTimer = nil
        selectionWheelAnimationStartTime = nil
        selectionWheelAnimationStartRect = nil
        selectionWheelAnimationTargetRect = nil
        selectionWheelAnimationStartAnnotationRects.removeAll()
        selectionWheelAnimationStartAnnotations.removeAll()
    }

    private func applySelectionWheelResize(from startRect: NSRect, to resized: NSRect) {
        applySelectionWheelResize(
            from: startRect,
            to: resized,
            startAnnotationRects: annotations.map { overlayRect(fromLocalAnnotationRect: $0.rect) },
            startAnnotations: annotations
        )
    }

    private func applySelectionWheelResize(
        from startRect: NSRect,
        to resized: NSRect,
        startAnnotationRects: [NSRect],
        startAnnotations: [CaptureAnnotation]
    ) {
        resizingSelectionStartRect = startRect
        resizingSelectionStartAnnotationRects = startAnnotationRects
        resizingSelectionStartAnnotations = startAnnotations
        lockedSelectionRect = resized

        if let lockedSelectionRect {
            let preservedRects = SelectionToolbarState.localAnnotationRectsPreservingOverlayPositions(
                resizingSelectionStartAnnotationRects,
                selectionRect: lockedSelectionRect
            )
            for index in annotations.indices where preservedRects.indices.contains(index) {
                if resizingSelectionStartAnnotations.indices.contains(index),
                   let arrowLine = resizingSelectionStartAnnotations[index].arrowLine {
                    let overlayLine = overlayArrowLine(fromLocalArrowLine: arrowLine, selectionRect: startRect)
                    let localLine = localArrowLine(fromOverlayArrowLine: overlayLine, selectionRect: lockedSelectionRect)
                    annotations[index].arrowLine = localLine
                    annotations[index].rect = localLine.boundingRect
                } else if resizingSelectionStartAnnotations.indices.contains(index),
                          let markerLine = resizingSelectionStartAnnotations[index].markerLine {
                    let overlayLine = overlayMarkerLine(fromLocalMarkerLine: markerLine, selectionRect: startRect)
                    let localLine = localMarkerLine(fromOverlayMarkerLine: overlayLine, selectionRect: lockedSelectionRect)
                    annotations[index].markerLine = localLine
                    annotations[index].rect = localLine.boundingRect
                } else if resizingSelectionStartAnnotations.indices.contains(index),
                          let brushPath = resizingSelectionStartAnnotations[index].brushPath {
                    let overlayPath = overlayBrushPath(fromLocalBrushPath: brushPath, selectionRect: startRect)
                    let localPath = localBrushPath(fromOverlayBrushPath: overlayPath, selectionRect: lockedSelectionRect)
                    annotations[index].brushPath = localPath
                    annotations[index].rect = localPath.boundingRect
                } else if resizingSelectionStartAnnotations.indices.contains(index),
                          let mosaicStroke = resizingSelectionStartAnnotations[index].mosaicStroke {
                    let overlayStroke = overlayMosaicStroke(fromLocalMosaicStroke: mosaicStroke, selectionRect: startRect)
                    let localStroke = localMosaicStroke(fromOverlayStroke: overlayStroke, selectionRect: lockedSelectionRect)
                    annotations[index].mosaicStroke = localStroke
                    annotations[index].rect = localStroke.boundingRect
                } else {
                    annotations[index].rect = preservedRects[index]
                }
            }
        }
    }

    private func drawOverlay() {
        if scrollCaptureOverlayState == .inactive, let backgroundImage {
            backgroundImage.draw(in: bounds, from: NSRect(origin: .zero, size: backgroundImage.size), operation: .copy, fraction: 1)
            if !hasEraserMasksForDrawing {
                let usesSequentialMosaicOrdering = shouldRenderAnnotationsWithMosaicOrdering
                if let rotatingIndex = rotatingMosaicRectangleAnnotationIndex(),
                   !usesSequentialMosaicOrdering,
                   rotatingIndex == annotations.indices.last,
                   drawRotatingMosaicRectanglePreview(at: rotatingIndex) {
                    // Rotation changes only the clip path; reuse the filtered base image.
                } else if usesSequentialMosaicOrdering {
                    drawAnnotationsRespectingMosaicOrder()
                } else {
                    let liveValueIndex = selectedMosaicValuePreviewIndex()
                    let mosaicAnnotations = annotations.enumerated().compactMap { index, annotation in
                        isMosaicAnnotation(annotation)
                            && !suppressedAnnotationIDs.contains(annotation.id)
                            && index != liveValueIndex ? annotation : nil
                    }
                    if let composite = mosaicPreviewComposite(for: mosaicAnnotations) {
                        drawMosaicComposite(composite, clippedTo: mosaicAnnotations)
                    }
                    if let liveValueIndex {
                        drawLiveMosaicValuePreview(at: liveValueIndex)
                    }
                }
            }
            if !hasEraserMasksForDrawing {
                drawMosaicDraftPreviewIfNeeded()
            }
            for (index, annotation) in annotations.enumerated()
                where annotation.kind == .mosaicRectangle
                && selectedAnnotationIndex == index
                && annotationIsEditable(at: index)
                && shouldDrawSelectedAnnotationOutline(annotation) {
                drawSelectedAnnotationOutline(annotation)
            }
        }

        guard let selectionRect else {
            if configuration.outsideSelectionDimAlpha > 0 {
                NSColor.black.withAlphaComponent(configuration.outsideSelectionDimAlpha).setFill()
                bounds.fill()
            }
            return
        }

        let path = NSBezierPath(rect: bounds)
        path.append(selectionPath(in: selectionRect))
        path.windingRule = .evenOdd

        if configuration.outsideSelectionDimAlpha > 0 {
            NSColor.black.withAlphaComponent(configuration.outsideSelectionDimAlpha).setFill()
            path.fill()
        }
    }

    private func drawMosaicDraftPreviewIfNeeded() {
        if let draftAnnotation,
           isMosaicAnnotation(draftAnnotation),
           isUsableDraftAnnotation(draftAnnotation) {
            drawMosaicDraftPreview(draftAnnotation)
        }
    }

    private func drawSelectionBorder(_ rect: NSRect) {
        NSColor(calibratedRed: 83 / 255, green: 120 / 255, blue: 232 / 255, alpha: 1).setStroke()
        let border = selectionPath(in: rect)
        border.lineWidth = 2
        border.stroke()
    }

    private func selectionPath(in rect: NSRect) -> NSBezierPath {
        guard selectionCornerRadius > 0 else {
            return NSBezierPath(rect: rect)
        }
        let radius = min(selectionCornerRadius, rect.width / 2, rect.height / 2)
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    private func drawSelectionHandles(_ rect: NSRect) {
        guard configuration.allowsSelectionGeometryEditing else {
            return
        }
        let handles = SelectionToolbarState.selectionHandlePoints(in: rect, cornerRadius: selectionCornerRadius)

        NSColor(calibratedRed: 83 / 255, green: 120 / 255, blue: 232 / 255, alpha: 1).setFill()
        NSColor(calibratedWhite: 1, alpha: 0.95).setStroke()
        for handle in handles {
            let handleRect = NSRect(x: handle.x - 5, y: handle.y - 5, width: 10, height: 10)
            let path = NSBezierPath(ovalIn: handleRect)
            path.fill()
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func drawMeasurementLabel(_ rect: NSRect) {
        let label = "\(Int(rect.width)) x \(Int(rect.height))  px"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: samplerInfoFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let layout = measurementControlLayout(for: rect)

        NSColor(calibratedWhite: 0.12, alpha: 0.86).setFill()
        NSBezierPath(roundedRect: layout.panel, xRadius: 5, yRadius: 5).fill()
        NSString(string: label).draw(in: layout.label.insetBy(dx: 9, dy: 4), withAttributes: attributes)
        guard scrollCaptureOverlayState == .inactive else { return }
        drawMeasurementSeparator(layout.labelSeparator)
        drawMeasurementSeparator(layout.refreshSeparator)

        drawMeasurementControlButton(layout.cornerStyle, selected: selectionCornerRadius > 0)
        drawMeasurementIcon(
            named: selectionCornerRadius > 0 ? "border-corner-rounded" : "border-corner-square",
            in: layout.cornerStyle.insetBy(dx: 2, dy: 2)
        ) {
            drawCornerStyleIcon(in: layout.cornerStyle.insetBy(dx: 2, dy: 2), rounded: selectionCornerRadius > 0)
        }
        drawMeasurementControlButton(layout.aspectRatio, selected: isSelectionAspectRatioLocked)
        drawMeasurementIcon(
            named: isSelectionAspectRatioLocked ? "aspect-ratio-fill" : "aspect-ratio",
            in: layout.aspectRatio.insetBy(dx: 3, dy: 3)
        ) {
            drawAspectRatioIcon(in: layout.aspectRatio.insetBy(dx: 3, dy: 3), locked: isSelectionAspectRatioLocked)
        }
        drawMeasurementControlButton(layout.refresh, selected: isRefreshingSelectionBackground)
        drawRotatingMeasurementIcon(in: layout.refresh.insetBy(dx: 2, dy: 2), degrees: refreshAnimationDegrees) {
            drawMeasurementIcon(named: "refresh", in: layout.refresh.insetBy(dx: 2, dy: 2)) {
                drawRefreshIcon(in: layout.refresh.insetBy(dx: 2, dy: 2))
            }
        }
    }

    private func measurementControlLayout(for rect: NSRect) -> SelectionToolbarState.MeasurementControlLayout {
        let label = "\(Int(rect.width)) x \(Int(rect.height))  px"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: samplerInfoFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        var layout = SelectionToolbarState.measurementControlLayout(
            anchoredTo: rect,
            textSize: NSString(string: label).size(withAttributes: attributes),
            inside: safeLayoutBounds
        )
        if scrollCaptureOverlayState != .inactive {
            layout.panel.size.width = layout.label.width
            layout.labelSeparator = .zero
            layout.cornerStyle = .zero
            layout.aspectRatio = .zero
            layout.refreshSeparator = .zero
            layout.refresh = .zero
        }
        return layout
    }

    private func drawMeasurementControlButton(_ rect: NSRect, selected: Bool) {
        (
            selected
                ? NSColor.white.withAlphaComponent(SelectionToolbarState.measurementControlSelectedBackgroundAlpha)
                : NSColor.white.withAlphaComponent(0.06)
        ).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
    }

    private func drawMeasurementSeparator(_ rect: NSRect) {
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 0.5, yRadius: 0.5).fill()
    }

    private func drawRotatingMeasurementIcon(in rect: NSRect, degrees: CGFloat, draw: () -> Void) {
        guard degrees != 0 else {
            draw()
            return
        }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: degrees)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)

        NSGraphicsContext.saveGraphicsState()
        transform.concat()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawMeasurementIcon(named name: String, in rect: NSRect, fallback: () -> Void) {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "svg"),
            let image = NSImage(contentsOf: url)
        else {
            fallback()
            return
        }

        image.isTemplate = false
        image.draw(in: rect)
    }

    private func drawCornerStyleIcon(in rect: NSRect, rounded: Bool) {
        let path = NSBezierPath()
        if rounded {
            let inset: CGFloat = 2
            let radius = min(rect.width, rect.height) * 0.34
            let start = NSPoint(x: rect.minX + inset, y: rect.minY + inset)
            let verticalEnd = NSPoint(x: rect.minX + inset, y: rect.maxY - inset - radius)
            let curveEnd = NSPoint(x: rect.minX + inset + radius, y: rect.maxY - inset)
            path.move(to: start)
            path.line(to: verticalEnd)
            path.curve(
                to: curveEnd,
                controlPoint1: NSPoint(x: verticalEnd.x, y: curveEnd.y),
                controlPoint2: NSPoint(x: verticalEnd.x, y: curveEnd.y)
            )
            path.line(to: NSPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        } else {
            path.move(to: NSPoint(x: rect.minX + 1, y: rect.minY + 1))
            path.line(to: NSPoint(x: rect.minX + 1, y: rect.maxY - 1))
            path.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 1))
        }
        NSColor.white.setStroke()
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawAspectRatioIcon(in rect: NSRect, locked: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        NSColor.white.setStroke()
        path.lineWidth = 1.2
        path.stroke()

        let cornerPath = NSBezierPath()
        cornerPath.move(to: NSPoint(x: rect.minX + 3, y: rect.midY))
        cornerPath.line(to: NSPoint(x: rect.minX + 3, y: rect.maxY - 3))
        cornerPath.line(to: NSPoint(x: rect.midX, y: rect.maxY - 3))
        cornerPath.move(to: NSPoint(x: rect.maxX - 3, y: rect.midY))
        cornerPath.line(to: NSPoint(x: rect.maxX - 3, y: rect.minY + 3))
        cornerPath.line(to: NSPoint(x: rect.midX, y: rect.minY + 3))
        cornerPath.lineWidth = 1.6
        cornerPath.lineCapStyle = .round
        cornerPath.lineJoinStyle = .round
        cornerPath.stroke()

        if locked {
            NSColor.white.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }

    private func drawRefreshIcon(in rect: NSRect) {
        let path = NSBezierPath()
        path.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width * 0.34, startAngle: 100, endAngle: 190)
        path.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width * 0.34, startAngle: 280, endAngle: 10)

        NSColor.white.setStroke()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        let topArrow = NSBezierPath()
        topArrow.move(to: NSPoint(x: rect.minX + 3, y: rect.midY + 3))
        topArrow.line(to: NSPoint(x: rect.minX + 3, y: rect.midY + 7))
        topArrow.line(to: NSPoint(x: rect.minX + 7, y: rect.midY + 7))
        topArrow.lineWidth = 1.6
        topArrow.lineCapStyle = .round
        topArrow.lineJoinStyle = .round
        topArrow.stroke()

        let bottomArrow = NSBezierPath()
        bottomArrow.move(to: NSPoint(x: rect.maxX - 3, y: rect.midY - 3))
        bottomArrow.line(to: NSPoint(x: rect.maxX - 3, y: rect.midY - 7))
        bottomArrow.line(to: NSPoint(x: rect.maxX - 7, y: rect.midY - 7))
        bottomArrow.lineWidth = 1.6
        bottomArrow.lineCapStyle = .round
        bottomArrow.lineJoinStyle = .round
        bottomArrow.stroke()
    }

    private func drawAnnotations() {
        guard !eraserMasks.isEmpty else {
            drawAnnotationsWithoutEraserMasks()
            return
        }
        drawAnnotationsWithEraserMasks(eraserMasks)
    }

    private func drawAnnotationsWithoutEraserMasks() {
        let alreadyRenderedWithMosaicOrdering = shouldRenderAnnotationsWithMosaicOrdering
        let selectedIndex = selectedAnnotationIndex
        for (index, annotation) in annotations.enumerated() {
            if suppressedAnnotationIDs.contains(annotation.id)
                || isMosaicAnnotation(annotation)
                || index == selectedIndex {
                continue
            }
            if !alreadyRenderedWithMosaicOrdering {
                drawAnnotation(annotation, inOverlay: true)
            }
        }

        guard let selectedIndex,
              annotationIsEditable(at: selectedIndex)
        else {
            return
        }

        let selectedAnnotation = annotations[selectedIndex]
        guard !isMosaicAnnotation(selectedAnnotation) else {
            return
        }

        if !alreadyRenderedWithMosaicOrdering && !suppressedAnnotationIDs.contains(selectedAnnotation.id) {
            drawAnnotation(selectedAnnotation, inOverlay: true)
        }
        if shouldDrawSelectedAnnotationOutline(selectedAnnotation) {
            drawSelectedAnnotationOutline(selectedAnnotation)
        }
    }

    private func drawAnnotationsWithEraserMasks(_ masks: [EraserMask]) {
        guard let lockedSelectionRect,
              let composite = eraserMaskedComposite(for: masks, in: lockedSelectionRect)
        else {
            drawAnnotationsWithoutEraserMasks()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: lockedSelectionRect.standardized).addClip()
        composite.drawClipPath.addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        composite.image.draw(
            in: composite.drawRect,
            from: NSRect(origin: .zero, size: composite.image.size),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        drawAnnotationsOutsideLockedSelection(lockedSelectionRect, masks: masks)

        if let selectedIndex = selectedAnnotationIndex,
           annotations.indices.contains(selectedIndex),
           annotationIsEditable(at: selectedIndex),
           shouldDrawSelectedAnnotationOutline(annotations[selectedIndex]) {
            drawSelectedAnnotationOutline(annotations[selectedIndex])
        }
    }

    private func eraserMaskedComposite(
        for masks: [EraserMask],
        in lockedSelectionRect: NSRect
    ) -> EraserMaskedCompositeCacheEntry? {
        if let cached = eraserMaskedCompositeCache,
           cached.revision == eraserMaskedCompositeRevision {
#if DEBUG
            eraserMaskedCompositeCacheHitCount += 1
            eraserMaskedCompositeDrawRect = cached.drawRect
            eraserMaskedCompositePixelRect = cached.pixelRect
#endif
            return cached
        }

        guard let backgroundImage,
              let crop = pixelAlignedCrop(image: backgroundImage, to: lockedSelectionRect)
        else {
            return nil
        }

        let shiftedAnnotations = annotations.map {
            shiftedOverlayAnnotation($0, by: crop.drawRect.origin)
        }
        let shiftedMasks = masks.map { mask in
            var shifted = mask
            let overlayRect = NSRect(
                x: lockedSelectionRect.minX + mask.rect.minX,
                y: lockedSelectionRect.minY + mask.rect.minY,
                width: mask.rect.width,
                height: mask.rect.height
            )
            shifted.rect = overlayRect.offsetBy(
                dx: -crop.drawRect.minX,
                dy: -crop.drawRect.minY
            )
            return shifted
        }
        let rendered = CaptureAnnotationRenderer.render(
            image: crop.image,
            annotations: shiftedAnnotations,
            eraserMasks: shiftedMasks
        )
        let drawClipPath = NSBezierPath()
        for annotation in annotations {
            guard var visualBounds = eraserRectangleVisualBounds(for: annotation)?.standardized,
                  !visualBounds.isEmpty else {
                continue
            }
            if abs(annotation.rotationAngle) >= 0.001,
               annotation.kind == .text || annotation.kind == .mosaicRectangle {
                let corners = rotatedRectangleCorners(for: visualBounds, angle: annotation.rotationAngle)
                if let first = corners.first {
                    visualBounds = corners.dropFirst().reduce(
                        NSRect(origin: first, size: .zero)
                    ) { partial, point in
                        partial.union(NSRect(origin: point, size: .zero))
                    }
                }
            }
            let padding: CGFloat
            if annotation.kind == .arrowLine {
                padding = max(28, annotation.style.strokeWidth * 6)
            } else if annotation.kind == .text {
                padding = max(8, annotation.style.strokeWidth * 2)
            } else {
                padding = max(6, annotation.style.strokeWidth * 2)
            }
            drawClipPath.appendRect(visualBounds.insetBy(dx: -padding, dy: -padding))
        }
        let entry = EraserMaskedCompositeCacheEntry(
            revision: eraserMaskedCompositeRevision,
            image: rendered,
            pixelRect: crop.pixelRect,
            drawRect: crop.drawRect,
            drawClipPath: drawClipPath
        )
        eraserMaskedCompositeCache = entry
#if DEBUG
        eraserMaskedCompositeRenderCount += 1
        eraserMaskedCompositeDrawRect = crop.drawRect
        eraserMaskedCompositePixelRect = crop.pixelRect
#endif
        return entry
    }

    private func invalidateEraserMaskedComposite() {
        eraserMaskedCompositeRevision &+= 1
        eraserMaskedCompositeCache = nil
        outsideMaskedAnnotationCache.removeAll()
#if DEBUG
        eraserMaskedCompositeDrawRect = nil
        eraserMaskedCompositePixelRect = nil
#endif
    }

    private func drawAnnotationsOutsideLockedSelection(_ lockedSelectionRect: NSRect, masks: [EraserMask]) {
        let clippedSelectionRect = lockedSelectionRect.standardized
        let selectedIndex = selectedAnnotationIndex
        for (index, annotation) in annotations.enumerated() {
            if index == selectedIndex || isMosaicAnnotation(annotation) || !annotationHasVisibleAreaOutsideLockedSelection(annotation, clippedSelectionRect) {
                continue
            }
            drawAnnotationOutsideLockedSelection(annotation, clippedSelectionRect, masks: masks)
        }

        if let selectedIndex,
           annotations.indices.contains(selectedIndex),
           annotationIsEditable(at: selectedIndex) {
            let selectedAnnotation = annotations[selectedIndex]
            if !isMosaicAnnotation(selectedAnnotation),
               annotationHasVisibleAreaOutsideLockedSelection(selectedAnnotation, clippedSelectionRect) {
                drawAnnotationOutsideLockedSelection(selectedAnnotation, clippedSelectionRect, masks: masks)
                if shouldDrawSelectedAnnotationOutline(selectedAnnotation) {
                    drawSelectedAnnotationOutline(selectedAnnotation)
                }
            }
        }
    }

    private func drawAnnotationOutsideLockedSelection(_ annotation: CaptureAnnotation, _ lockedSelectionRect: NSRect, masks: [EraserMask]) {
        let masksForAnnotation = masks.filter { $0.affectedAnnotationIDs.contains(annotation.id) }

        NSGraphicsContext.saveGraphicsState()
        outsideLockedSelectionClipPath(lockedSelectionRect).addClip()
        if masksForAnnotation.isEmpty {
            drawAnnotation(annotation, inOverlay: true)
        } else if let maskedAnnotation = outsideMaskedAnnotationImage(for: annotation, masks: masksForAnnotation) {
            maskedAnnotation.image.draw(
                in: maskedAnnotation.rect,
                from: NSRect(origin: .zero, size: maskedAnnotation.image.size),
                operation: .sourceOver,
                fraction: 1
            )
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func outsideLockedSelectionClipPath(_ lockedSelectionRect: NSRect) -> NSBezierPath {
        let clipPath = NSBezierPath(rect: bounds)
        clipPath.append(selectionPath(in: lockedSelectionRect))
        clipPath.windingRule = .evenOdd
        return clipPath
    }

    private func outsideMaskedAnnotationImage(for annotation: CaptureAnnotation, masks: [EraserMask]) -> (image: NSImage, rect: NSRect)? {
        if let cached = outsideMaskedAnnotationCache[annotation.id],
           cached.revision == eraserMaskedCompositeRevision {
#if DEBUG
            outsideMaskedAnnotationCacheHitCount += 1
#endif
            return (cached.image, cached.rect)
        }

        guard let visualBounds = eraserRectangleVisualBounds(for: annotation)?.standardized else {
            return nil
        }
        let imageRect = visualBounds.insetBy(dx: -2, dy: -2).intersection(bounds).standardized
        guard imageRect.width > 0, imageRect.height > 0 else {
            return nil
        }

        let image = NSImage(size: imageRect.size)

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageRect.size).fill()
        let transform = NSAffineTransform()
        transform.translateX(by: -imageRect.minX, yBy: -imageRect.minY)
        transform.concat()
        drawAnnotation(annotation, inOverlay: true)
        for mask in masks {
            NSColor.black.setFill()
            overlayRect(fromLocalEraserMaskRect: mask.rect).insetBy(dx: -1, dy: -1).fill(using: .destinationOut)
        }
        image.unlockFocus()
        outsideMaskedAnnotationCache[annotation.id] = OutsideMaskedAnnotationCacheEntry(
            revision: eraserMaskedCompositeRevision,
            image: image,
            rect: imageRect
        )
#if DEBUG
        outsideMaskedAnnotationRenderCount += 1
#endif
        return (image, imageRect)
    }

    private func overlayRect(fromLocalEraserMaskRect rect: NSRect) -> NSRect {
        guard let lockedSelectionRect else {
            return rect
        }
        return NSRect(
            x: lockedSelectionRect.minX + rect.minX,
            y: lockedSelectionRect.minY + rect.minY,
            width: rect.width,
            height: rect.height
        ).standardized
    }

    private func annotationHasVisibleAreaOutsideLockedSelection(_ annotation: CaptureAnnotation, _ lockedSelectionRect: NSRect) -> Bool {
        guard let visualBounds = eraserRectangleVisualBounds(for: annotation)?.standardized,
              visualBounds.width > 0,
              visualBounds.height > 0
        else {
            return false
        }
        return !lockedSelectionRect.contains(visualBounds)
    }

    private var shouldRenderAnnotationsWithMosaicOrdering: Bool {
        guard backgroundImage != nil else {
            return false
        }

        let drawableAnnotations = annotations.filter { !suppressedAnnotationIDs.contains($0.id) }
        let orderedAnnotations = draftAnnotation.map { drawableAnnotations + [$0] } ?? drawableAnnotations
        return needsSequentialMosaicComposite(for: orderedAnnotations)
    }

    private func isMosaicAnnotation(_ annotation: CaptureAnnotation) -> Bool {
        annotation.kind == .mosaicStroke || annotation.kind == .mosaicRectangle
    }

    private func needsSequentialMosaicComposite(for annotations: [CaptureAnnotation]) -> Bool {
        var mosaicCount = 0
        var hasEarlierNonMosaicAnnotation = false
        for annotation in annotations {
            if isMosaicAnnotation(annotation) {
                mosaicCount += 1
                if mosaicCount > 1 {
                    return true
                }
                if hasEarlierNonMosaicAnnotation {
                    return true
                }
            } else {
                hasEarlierNonMosaicAnnotation = true
            }
        }
        return false
    }

    private func drawAnnotationsRespectingMosaicOrder() {
        let rotatingIndex = rotatingMosaicRectangleAnnotationIndex()
        let liveValueIndex = selectedMosaicValuePreviewIndex()
        if let liveGeometryIndex = selectedMosaicGeometryPreviewIndex(),
           drawCachedMosaicCompositeWhileEditingLargeGeometry(at: liveGeometryIndex) {
            return
        }
        if let liveGeometryIndex = selectedMosaicGeometryPreviewIndex(),
           drawAnnotationsRespectingMosaicOrderWhileEditingSelectedMosaic(at: liveGeometryIndex) {
            return
        }
        if drawSingleMosaicCompositeWhenOrderAllows(rotatingIndex: rotatingIndex, liveValueIndex: liveValueIndex) {
            return
        }

        for (index, annotation) in annotations.enumerated() {
            if suppressedAnnotationIDs.contains(annotation.id) {
                continue
            }
            if isMosaicAnnotation(annotation) {
                if rotatingIndex == index,
                   drawRotatingMosaicRectanglePreview(at: index, drawBaseAnnotations: false) {
                    continue
                }
                if liveValueIndex == index,
                   drawLiveMosaicValuePreview(at: index, baseAnnotations: Array(annotations.prefix(index))) {
                    continue
                }
                let annotationsThroughCurrent = Array(annotations.prefix(index + 1))
                if let composite = mosaicPreviewComposite(for: annotationsThroughCurrent) {
                    drawMosaicComposite(composite, clippedTo: [annotation])
                }
            } else {
                drawAnnotation(annotation, inOverlay: true)
            }
        }
    }

    private func drawSingleMosaicCompositeWhenOrderAllows(rotatingIndex: Int?, liveValueIndex: Int?) -> Bool {
        guard rotatingIndex == nil, liveValueIndex == nil else {
            return false
        }

        var mosaicAnnotations: [CaptureAnnotation] = []
        var nonMosaicPrefixAnnotations: [CaptureAnnotation] = []
        var hasSeenMosaic = false
        for annotation in annotations {
            if isMosaicAnnotation(annotation) {
                hasSeenMosaic = true
                mosaicAnnotations.append(annotation)
            } else if hasSeenMosaic {
                return false
            } else {
                nonMosaicPrefixAnnotations.append(annotation)
            }
        }

        guard !mosaicAnnotations.isEmpty else {
            return false
        }

        for annotation in nonMosaicPrefixAnnotations {
            drawAnnotation(annotation, inOverlay: true)
        }
        if let composite = mosaicPreviewComposite(for: annotations) {
            drawMosaicCompositeUnclipped(composite)
        }
        return true
    }

    private func drawAnnotationsRespectingMosaicOrderWhileEditingSelectedMosaic(at selectedIndex: Int) -> Bool {
        guard annotations.indices.contains(selectedIndex),
              isMosaicAnnotation(annotations[selectedIndex]) else {
            return false
        }

        let baseAnnotations = annotations.enumerated().compactMap { index, annotation in
            index == selectedIndex ? nil : annotation
        }
        guard let backgroundImage else {
            return false
        }

        if let baseComposite = mosaicPreviewComposite(for: baseAnnotations) {
            drawMosaicCompositeUnclipped(baseComposite)
        }

        guard let preview = mosaicLocalPreview(
            for: annotations[selectedIndex],
            existingAnnotations: baseAnnotations,
            backgroundImage: backgroundImage
        ) else {
            return false
        }

        NSGraphicsContext.saveGraphicsState()
        mosaicDraftClipPath(for: annotations[selectedIndex])?.addClip()
        preview.image.draw(
            in: preview.drawRect,
            from: NSRect(origin: .zero, size: preview.image.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return true
    }

    private func drawCachedMosaicCompositeWhileEditingLargeGeometry(at selectedIndex: Int) -> Bool {
        let start = CFAbsoluteTimeGetCurrent()
        guard
            annotations.indices.contains(selectedIndex),
            isMosaicAnnotation(annotations[selectedIndex]),
            mosaicGeometryEditingShouldUseCachedComposite,
            !mosaicGeometryEditingStartAnnotations.isEmpty,
            let composite = mosaicGeometryEditingStartComposite,
            let baseKey = mosaicGeometryEditingStartCompositeKey
        else {
            return false
        }

        drawMosaicCompositeUnclipped(composite)
        let geometryChanged = selectedMosaicGeometryHasChanged(at: selectedIndex)
        guard geometryChanged else {
            logMosaicCacheEventIfNeeded(
                "draw-cached-editing-composite",
                startTime: start,
                details: "selectedIndex=\(selectedIndex) geometryChanged=false localPreview=skipped compositeRect=\(mosaicRectLogDescription(composite.drawRect)) annotationRect=\(mosaicRectLogDescription(overlayRect(fromLocalAnnotationRect: annotations[selectedIndex].rect)))"
            )
            return true
        }

        let drewLocalPreview = drawSelectedMosaicAnnotationLocalPreview(
            at: selectedIndex,
            baseImage: composite.image,
            baseKey: baseKey
        )
        logMosaicCacheEventIfNeeded(
            "draw-cached-editing-composite",
            startTime: start,
            force: !drewLocalPreview,
            details: "selectedIndex=\(selectedIndex) localPreview=\(drewLocalPreview ? "hit" : "miss") compositeRect=\(mosaicRectLogDescription(composite.drawRect)) annotationRect=\(mosaicRectLogDescription(overlayRect(fromLocalAnnotationRect: annotations[selectedIndex].rect)))"
        )
        return true
    }

    private var mosaicGeometryEditingShouldUseCachedComposite: Bool {
        switch interactionMode {
        case .movingShape, .resizingShape, .rotatingMosaicRectangle:
            return true
        default:
            return false
        }
    }

    private func shouldDrawSelectedAnnotationOutline(_ annotation: CaptureAnnotation) -> Bool {
        if annotation.kind == .mosaicRectangle, !configuration.showsMosaicRectangleSelectionOutline {
            return false
        }
        return activeToolCanEdit(annotationKind: annotation.kind)
            && (annotation.kind == .arrowLine
                || annotation.kind == .brush
                || SelectionToolbarState.annotationKindSupportsGeometryEditing(annotation.kind))
    }

    private func drawDraftAnnotation() {
        guard let draftAnnotation else {
            return
        }

        if draftAnnotation.kind == .mosaicStroke || draftAnnotation.kind == .mosaicRectangle {
            if draftAnnotation.kind == .mosaicRectangle {
                drawMosaicRectangleDraftBorder(draftAnnotation)
            }
            return
        }
        drawAnnotation(draftAnnotation, inOverlay: true)
        if draftAnnotation.kind == .arrowLine {
            drawSelectedAnnotationOutline(draftAnnotation)
        } else if SelectionToolbarState.annotationKindSupportsGeometryEditing(draftAnnotation.kind) {
            drawResizeHandles(for: overlayRect(fromLocalAnnotationRect: draftAnnotation.rect), kind: draftAnnotation.kind)
        }
    }

    private func drawEraserRectanglePreview() {
        guard eraserMode == .rectangle,
              interactionMode == .drawingEraserRectangle,
              let rect = eraserRectanglePreviewRect,
              rect.width >= 1,
              rect.height >= 1
        else {
            return
        }

        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
    }

    private func drawMosaicRectangleDraftBorder(_ annotation: CaptureAnnotation) {
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect)
        let path = rotatedRectanglePath(for: rect, angle: annotation.rotationAngle)
        NSColor.systemBlue.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 0.6
        path.stroke()
    }

    private func drawMosaicDraftPreview(_ annotation: CaptureAnnotation) {
        if drawMosaicRectangleDraftPreviewDirectly(annotation) {
            return
        }

        guard let preview = mosaicDraftPreview(for: annotation) else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        mosaicDraftClipPath(for: annotation)?.addClip()
        preview.image.draw(
            in: preview.drawRect,
            from: NSRect(origin: .zero, size: preview.image.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawMosaicRectangleDraftPreviewDirectly(_ annotation: CaptureAnnotation) -> Bool {
        let start = CFAbsoluteTimeGetCurrent()
        guard annotation.kind == .mosaicRectangle,
              let backgroundImage,
              let redaction = annotation.mosaicRedaction,
              annotations.isEmpty,
              let clip = mosaicDraftClipPath(for: annotation) else {
            return false
        }

        let redactedBase = mosaicDraftRedactedBaseImage(
            redaction: redaction,
            existingAnnotations: annotations,
            backgroundImage: backgroundImage
        )
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        redactedBase.draw(
            in: bounds,
            from: NSRect(origin: .zero, size: redactedBase.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        logMosaicCacheEventIfNeeded(
            "draw-rectangle-draft-direct",
            startTime: start,
            details: "redaction=\(redaction.type):\(redaction.value) clip=\(mosaicRectLogDescription(clip.bounds))"
        )
        return true
    }

    private func drawMosaicComposite(
        _ composite: (image: NSImage, drawRect: NSRect),
        clippedTo annotations: [CaptureAnnotation]
    ) {
        for clipPath in annotations.compactMap(mosaicDraftClipPath) {
            mosaicCompositeDrawCount += 1
            NSGraphicsContext.saveGraphicsState()
            clipPath.addClip()
            composite.image.draw(
                in: composite.drawRect,
                from: NSRect(origin: .zero, size: composite.image.size),
                operation: .copy,
                fraction: 1
            )
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawMosaicCompositeUnclipped(_ composite: (image: NSImage, drawRect: NSRect)) {
        mosaicCompositeDrawCount += 1
        composite.image.draw(
            in: composite.drawRect,
            from: NSRect(origin: .zero, size: composite.image.size),
            operation: .copy,
            fraction: 1
        )
    }

    private func drawRotatingMosaicRectanglePreview(
        at selectedIndex: Int,
        drawBaseAnnotations: Bool = true
    ) -> Bool {
        guard
            let backgroundImage,
            annotations.indices.contains(selectedIndex),
            annotations[selectedIndex].kind == .mosaicRectangle,
            let redaction = annotations[selectedIndex].mosaicRedaction,
            let clipPath = mosaicDraftClipPath(for: annotations[selectedIndex])
        else {
            return false
        }

        let earlierAnnotations = Array(annotations[..<selectedIndex])
        let baseImage: NSImage
        let baseKey: String
        if let baseComposite = fullMosaicPreviewComposite(for: earlierAnnotations) {
            if drawBaseAnnotations {
                drawMosaicComposite(baseComposite, clippedTo: earlierAnnotations)
            }
            baseImage = baseComposite.image
            baseKey = mosaicCompositeKey(for: earlierAnnotations, backgroundImage: backgroundImage)
        } else {
            baseImage = backgroundImage
            baseKey = mosaicBackgroundKey(for: backgroundImage)
        }

        let redactedImage = mosaicRedactedBaseImage(
            baseImage: baseImage,
            baseKey: baseKey,
            redaction: redaction
        )
        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        redactedImage.draw(
            in: bounds,
            from: NSRect(origin: .zero, size: redactedImage.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return true
    }

    private func drawSelectedMosaicAnnotationPreview(
        at selectedIndex: Int,
        baseImage: NSImage,
        baseKey: String
    ) -> Bool {
        guard
            annotations.indices.contains(selectedIndex),
            isMosaicAnnotation(annotations[selectedIndex]),
            let redaction = annotations[selectedIndex].mosaicRedaction,
            let clipPath = mosaicDraftClipPath(for: annotations[selectedIndex])
        else {
            return false
        }

        let redactedImage = mosaicRedactedBaseImage(
            baseImage: baseImage,
            baseKey: baseKey,
            redaction: redaction
        )
        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        redactedImage.draw(
            in: bounds,
            from: NSRect(origin: .zero, size: redactedImage.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return true
    }

    private func drawSelectedMosaicAnnotationLocalPreview(
        at selectedIndex: Int,
        baseImage: NSImage,
        baseKey: String
    ) -> Bool {
        let start = CFAbsoluteTimeGetCurrent()
        guard
            annotations.indices.contains(selectedIndex),
            isMosaicAnnotation(annotations[selectedIndex]),
            let preview = mosaicLocalPreview(
                for: annotations[selectedIndex],
                baseImage: baseImage,
                baseKey: baseKey
            )
        else {
            logMosaicCacheEventIfNeeded(
                "draw-selected-local-preview-miss",
                startTime: start,
                force: true,
                details: "selectedIndex=\(selectedIndex)"
            )
            return false
        }

        NSGraphicsContext.saveGraphicsState()
        mosaicDraftClipPath(for: annotations[selectedIndex])?.addClip()
        preview.image.draw(
            in: preview.drawRect,
            from: NSRect(origin: .zero, size: preview.image.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        logMosaicCacheEventIfNeeded(
            "draw-selected-local-preview",
            startTime: start,
            details: "selectedIndex=\(selectedIndex) drawRect=\(mosaicRectLogDescription(preview.drawRect))"
        )
        return true
    }

    private func rotatingMosaicRectangleAnnotationIndex() -> Int? {
        guard
            interactionMode == .rotatingMosaicRectangle,
            let selectedAnnotationIndex,
            annotations.indices.contains(selectedAnnotationIndex),
            annotations[selectedAnnotationIndex].kind == .mosaicRectangle
        else {
            return nil
        }
        return selectedAnnotationIndex
    }

    private func selectedMosaicGeometryPreviewIndex() -> Int? {
        guard
            let selectedAnnotationIndex,
            annotations.indices.contains(selectedAnnotationIndex),
            isMosaicAnnotation(annotations[selectedAnnotationIndex])
        else {
            return nil
        }

        switch interactionMode {
        case .movingShape, .resizingShape, .rotatingMosaicRectangle:
            return selectedAnnotationIndex
        default:
            return nil
        }
    }

    private func selectedMosaicGeometryHasChanged(at index: Int) -> Bool {
        guard annotations.indices.contains(index) else {
            return false
        }

        switch interactionMode {
        case .movingShape:
            guard let movingAnnotationStartRect else {
                return true
            }
            let currentRect = overlayRect(fromLocalAnnotationRect: annotations[index].rect)
            if !rectsApproximatelyEqual(currentRect, movingAnnotationStartRect) {
                return true
            }
            guard let movingAnnotationStartMosaicStroke else {
                return false
            }
            guard let currentStroke = overlayMosaicStroke(fromLocalMosaicStroke: annotations[index].mosaicStroke) else {
                return true
            }
            return !pointsApproximatelyEqual(currentStroke.points, movingAnnotationStartMosaicStroke.points)
        case .resizingShape:
            guard let resizingAnnotationStartRect else {
                return true
            }
            return !rectsApproximatelyEqual(
                overlayRect(fromLocalAnnotationRect: annotations[index].rect),
                resizingAnnotationStartRect
            )
        case .rotatingMosaicRectangle:
            return abs(annotations[index].rotationAngle - rotatingMosaicRectangleStartAnnotationAngle) > 0.001
        default:
            return false
        }
    }

    private func rectsApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 0.001
            && abs(lhs.minY - rhs.minY) <= 0.001
            && abs(lhs.width - rhs.width) <= 0.001
            && abs(lhs.height - rhs.height) <= 0.001
    }

    private func pointsApproximatelyEqual(_ lhs: [NSPoint], _ rhs: [NSPoint]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy { left, right in
            abs(left.x - right.x) <= 0.001 && abs(left.y - right.y) <= 0.001
        }
    }

    private func selectedMosaicValuePreviewIndex() -> Int? {
        guard interactionMode == .draggingMosaicValue,
              let selectedAnnotationIndex,
              annotations.indices.contains(selectedAnnotationIndex),
              isMosaicAnnotation(annotations[selectedAnnotationIndex]) else {
            return nil
        }
        return selectedAnnotationIndex
    }

    @discardableResult
    private func drawLiveMosaicValuePreview(
        at selectedIndex: Int,
        baseAnnotations: [CaptureAnnotation]? = nil
    ) -> Bool {
        guard let backgroundImage, annotations.indices.contains(selectedIndex) else {
            return false
        }

        let resolvedBaseAnnotations = baseAnnotations ?? annotations.enumerated().compactMap { index, annotation in
            isMosaicAnnotation(annotation) && index != selectedIndex ? annotation : nil
        }

        guard let preview = mosaicLocalPreview(
            for: annotations[selectedIndex],
            existingAnnotations: resolvedBaseAnnotations,
            backgroundImage: backgroundImage
        ) else {
            return false
        }

        NSGraphicsContext.saveGraphicsState()
        mosaicDraftClipPath(for: annotations[selectedIndex])?.addClip()
        preview.image.draw(
            in: preview.drawRect,
            from: NSRect(origin: .zero, size: preview.image.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return true
    }

    private func drawAnnotation(_ annotation: CaptureAnnotation, inOverlay: Bool) {
        if inOverlay, shouldSuppressEditingTextAnnotation(annotation) {
            return
        }
        if annotation.kind == .text {
            drawTextAnnotation(annotation, inOverlay: inOverlay)
            return
        }
        if annotation.kind == .numberSequence {
            drawNumberSequenceAnnotation(annotation, inOverlay: inOverlay)
            return
        }
        if annotation.kind == .mosaicStroke || annotation.kind == .mosaicRectangle {
            guard let composite = mosaicPreviewComposite(for: [annotation]) else {
                return
            }
            composite.image.draw(
                in: composite.drawRect,
                from: NSRect(origin: .zero, size: composite.image.size),
                operation: .copy,
                fraction: 1
            )
            return
        }
        if annotation.kind == .arrowLine {
            drawArrowLineAnnotation(annotation, inOverlay: inOverlay)
            return
        }
        if annotation.kind == .brush {
            drawBrushPathAnnotation(annotation, inOverlay: inOverlay)
            return
        }
        if annotation.kind == .marker {
            drawMarkerLineAnnotation(annotation, inOverlay: inOverlay)
            return
        }
        if annotation.kind == .magnifier {
            drawMagnifierAnnotation(annotation, inOverlay: inOverlay)
            return
        }

        let rect = inOverlay ? overlayRect(fromLocalAnnotationRect: annotation.rect) : annotation.rect
        let insetRect = rect.standardized.insetBy(dx: annotation.style.strokeWidth / 2, dy: annotation.style.strokeWidth / 2)
        let path: NSBezierPath

        switch annotation.kind {
        case .rectangle where annotation.style.cornerRadius > 0:
            path = NSBezierPath(
                roundedRect: insetRect,
                xRadius: annotation.style.cornerRadius,
                yRadius: annotation.style.cornerRadius
            )
        case .rectangle:
            path = NSBezierPath(rect: insetRect)
        case .ellipse:
            path = NSBezierPath(ovalIn: insetRect)
        case .arrowLine, .brush, .marker, .text, .numberSequence, .magnifier, .mosaicStroke, .mosaicRectangle:
            return
        }

        if annotation.style.fillEnabled {
            annotation.style.fillColor.setFill()
            path.fill()
        }

        let strokePath = annotation.style.strokePattern.isSketch
            ? CaptureSketchStrokePath.bezierPath(
                kind: annotation.kind,
                rect: insetRect,
                cornerRadius: annotation.style.cornerRadius,
                lineWidth: annotation.style.strokeWidth
            )
            : path
        annotation.style.strokeColor.setStroke()
        strokePath.lineWidth = annotation.style.strokeWidth
        strokePath.lineJoinStyle = .round
        strokePath.lineCapStyle = .round
        let dashPattern = annotation.style.strokePattern.dashPattern(strokeWidth: annotation.style.strokeWidth)
        strokePath.setLineDash(
            dashPattern,
            count: dashPattern.count,
            phase: 0
        )
        strokePath.stroke()
    }

    private func drawMagnifierAnnotation(_ annotation: CaptureAnnotation, inOverlay: Bool) {
        let destination = (inOverlay ? overlayRect(fromLocalAnnotationRect: annotation.rect) : annotation.rect).standardized
        guard destination.width > 0, destination.height > 0 else {
            return
        }

        if let backgroundImage, bounds.width > 0, bounds.height > 0 {
            let sourceDestination = inOverlay
                ? destination
                : overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
            let scaleX = backgroundImage.size.width / bounds.width
            let scaleY = backgroundImage.size.height / bounds.height
            let destinationInImage = CGRect(
                x: sourceDestination.minX * scaleX,
                y: sourceDestination.minY * scaleY,
                width: sourceDestination.width * scaleX,
                height: sourceDestination.height * scaleY
            )
            let sourceBounds = CGRect(origin: .zero, size: backgroundImage.size)
            if let geometry = CaptureAnnotationRenderer.magnifierDrawGeometry(
                destination: destinationInImage,
                sourceBounds: sourceBounds,
                zoom: annotation.effectiveMagnifierZoom,
                contentXOffset: CaptureAnnotationRenderer.magnifierContentXOffset * scaleX,
                contentYOffset: CaptureAnnotationRenderer.magnifierContentYOffset * scaleY
            ) {
                let overlayDrawRect = NSRect(
                    x: geometry.drawRect.minX / scaleX,
                    y: geometry.drawRect.minY / scaleY,
                    width: geometry.drawRect.width / scaleX,
                    height: geometry.drawRect.height / scaleY
                )
                let drawRect = inOverlay ? overlayDrawRect : localAnnotationRect(from: overlayDrawRect)
                let sourceRect = NSRect(
                    x: geometry.integralSource.minX,
                    y: geometry.integralSource.minY,
                    width: geometry.integralSource.width,
                    height: geometry.integralSource.height
                )

                NSGraphicsContext.saveGraphicsState()
                magnifierClipPath(shape: annotation.effectiveMagnifierShape, rect: destination).addClip()
                NSGraphicsContext.current?.imageInterpolation = .none
                backgroundImage.draw(in: drawRect, from: sourceRect, operation: .copy, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        drawMagnifierBorder(annotation, rect: destination)
    }

    private func drawMagnifierBorder(_ annotation: CaptureAnnotation, rect: NSRect) {
        let lineWidth = annotation.style.strokeWidth
        guard lineWidth > 0 else {
            return
        }

        let insetRect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        guard insetRect.width > 0, insetRect.height > 0 else {
            return
        }

        let path = magnifierClipPath(shape: annotation.effectiveMagnifierShape, rect: insetRect)
        annotation.style.strokeColor.setStroke()
        path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
    }

    private func magnifierClipPath(shape: CaptureMagnifierShape, rect: NSRect) -> NSBezierPath {
        switch shape {
        case .circle:
            return NSBezierPath(ovalIn: rect)
        case .rectangle:
            return NSBezierPath(rect: rect)
        }
    }

    private func drawNumberSequenceAnnotation(_ annotation: CaptureAnnotation, inOverlay: Bool) {
        let rect = (inOverlay ? overlayRect(fromLocalAnnotationRect: annotation.rect) : annotation.rect).standardized
        switch annotation.numberMarkType ?? .number {
        case .number:
            annotation.style.strokeColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let value = min(999, max(1, annotation.numberSequenceIndex ?? 1))
            let text = "\(value)"
            let displayedText: String
            let isEditingNumber: Bool
            if let editingNumberAnnotationIndex,
               annotations.indices.contains(editingNumberAnnotationIndex),
               annotations[editingNumberAnnotationIndex].rect == annotation.rect {
                isEditingNumber = true
                displayedText = editingNumberHasDraft ? editingNumberDraft : text
            } else {
                isEditingNumber = false
                displayedText = text
            }
            let font = NSFont.monospacedDigitSystemFont(
                ofSize: CaptureAnnotationRenderer.numberMarkTextFontSize(for: annotation.style.textSize, text: displayedText),
                weight: .bold
            )
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: readableNumberForegroundColor(on: annotation.style.strokeColor),
            ]
            let size = NSString(string: displayedText).size(withAttributes: attributes)
            let textOrigin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
            NSString(string: displayedText).draw(
                at: textOrigin,
                withAttributes: attributes
            )
            if isEditingNumber, numberCaretVisible {
                drawNumberEditingCaret(
                    inText: displayedText,
                    caretIndex: editingNumberCaretIndex,
                    textOrigin: textOrigin,
                    textSize: size,
                    attributes: attributes,
                    font: font,
                    in: rect
                )
            }
        case .check:
            drawNumberSymbol("✓", in: rect, color: annotation.style.strokeColor)
        case .cross:
            drawNumberSymbol("×", in: rect, color: annotation.style.strokeColor)
        }
    }

    private func drawNumberEditingCaret(
        inText text: String,
        caretIndex: Int,
        textOrigin: NSPoint,
        textSize: NSSize,
        attributes: [NSAttributedString.Key: Any],
        font: NSFont,
        in rect: NSRect
    ) {
        let caretWidth = max(1.2, min(2.2, font.pointSize / 14))
        let caretHeight = min(max(8, textSize.height * 0.88), rect.height * 0.82)
        let horizontalPadding = max(2, rect.width * 0.07)
        let clampedCaretIndex = min(max(0, caretIndex), text.count)
        let prefix = String(text.prefix(clampedCaretIndex))
        let prefixWidth = NSString(string: prefix).size(withAttributes: attributes).width
        let requestedX = textOrigin.x + prefixWidth + max(1, caretWidth / 2)
        let caretX = min(requestedX, rect.maxX - horizontalPadding - caretWidth)
        let caretRect = NSRect(
            x: max(rect.minX + horizontalPadding, caretX),
            y: rect.midY - caretHeight / 2,
            width: caretWidth,
            height: caretHeight
        )
        NSColor.black.setFill()
        NSBezierPath(rect: caretRect).fill()
    }

    private func readableNumberForegroundColor(on color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.68 ? NSColor.black.withAlphaComponent(0.86) : .white
    }

    private func drawTextAnnotation(_ annotation: CaptureAnnotation, inOverlay: Bool) {
        guard
            let text = annotation.text,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        let rect = (inOverlay ? overlayRect(fromLocalAnnotationRect: annotation.rect) : annotation.rect).standardized
        NSGraphicsContext.saveGraphicsState()
        if abs(annotation.rotationAngle) >= 0.001 {
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byRadians: annotation.rotationAngle)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
        }
        CaptureAnnotationRenderer.drawText(text, in: rect, style: annotation.style)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawEditingTextCaretIfNeeded() {
        guard
            let textEditor,
            window?.firstResponder === textEditor,
            let editingTextAnnotationIndex,
            annotations.indices.contains(editingTextAnnotationIndex),
            annotations[editingTextAnnotationIndex].kind == .text,
            textEditor.selectedRange().length == 0
        else {
            return
        }

        let annotation = annotations[editingTextAnnotationIndex]
        guard let caretInfo = editingTextCaretDrawInfo(for: textEditor, annotation: annotation) else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        if abs(annotation.rotationAngle) >= 0.001 {
            let transform = NSAffineTransform()
            transform.translateX(by: caretInfo.annotationRect.midX, yBy: caretInfo.annotationRect.midY)
            transform.rotate(byRadians: annotation.rotationAngle)
            transform.translateX(by: -caretInfo.annotationRect.midX, yBy: -caretInfo.annotationRect.midY)
            transform.concat()
        }
        editingTextCaretColor(at: caretInfo.samplePoint).setFill()
        NSBezierPath(rect: caretInfo.drawRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private struct EditingTextCaretDrawInfo {
        let annotationRect: NSRect
        let drawRect: NSRect
        let samplePoint: NSPoint
    }

    private func editingTextCaretDrawInfo(
        for textEditor: NSTextView,
        annotation: CaptureAnnotation
    ) -> EditingTextCaretDrawInfo? {
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
        guard rect.width > 0, rect.height > 0,
              let caretRect = textEditorCaretRectInEditorBounds(textEditor)
        else {
            return nil
        }

        let caretWidth = max(1.5, min(3, annotation.style.textSize / 12))
        let caretHeight = min(max(1, caretRect.height), rect.height)
        let clampedX = min(max(caretRect.midX, 0), rect.width)
        let clampedY = min(max(rect.height - caretRect.maxY, 0), max(0, rect.height - caretHeight))
        let localCaretRect = NSRect(
            x: clampedX - caretWidth / 2,
            y: clampedY,
            width: caretWidth,
            height: caretHeight
        )
        let drawRect = NSRect(
            x: rect.minX + localCaretRect.minX,
            y: rect.minY + localCaretRect.minY,
            width: localCaretRect.width,
            height: localCaretRect.height
        )
        let samplePoint = rotatedPoint(
            NSPoint(x: drawRect.midX, y: drawRect.midY),
            around: NSPoint(x: rect.midX, y: rect.midY),
            angle: annotation.rotationAngle
        )

        return EditingTextCaretDrawInfo(annotationRect: rect, drawRect: drawRect, samplePoint: samplePoint)
    }

    private func editingTextCaretColor(at point: NSPoint) -> NSColor {
        if let selectionRect = lockedSelectionRect?.standardized,
           let luminance = averageBackgroundLuminance(in: selectionRect) {
            return luminance < 0.5 ? .white : .black
        }

        guard let color = sampleColor(at: point),
              perceivedLuminance(of: color) < 0.18
        else {
            return .black
        }

        return .white
    }

    private func textEditorCaretRectInEditorBounds(
        _ textEditor: NSTextView,
        selectedLocation explicitSelectedLocation: Int? = nil
    ) -> NSRect? {
        guard let textContainer = textEditor.textContainer,
              let layoutManager = textEditor.layoutManager
        else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let textLength = (textEditor.string as NSString).length
        let selectedLocation = min(explicitSelectedLocation ?? textEditor.selectedRange().location, textLength)
        let rectInContainer: NSRect
        if textLength == 0 || layoutManager.numberOfGlyphs == 0 {
            rectInContainer = layoutManager.extraLineFragmentRect
        } else if selectedLocation >= textLength {
            let glyphRange = NSRange(location: max(0, layoutManager.numberOfGlyphs - 1), length: 1)
            var lastGlyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            lastGlyphRect.origin.x = lastGlyphRect.maxX
            lastGlyphRect.size.width = 1
            rectInContainer = lastGlyphRect
        } else {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: selectedLocation)
            var glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            glyphRect.size.width = 1
            rectInContainer = glyphRect
        }

        let containerOrigin = textEditor.textContainerOrigin
        return NSRect(
            x: containerOrigin.x + rectInContainer.minX,
            y: containerOrigin.y + rectInContainer.minY,
            width: max(1, rectInContainer.width),
            height: rectInContainer.height
        )
    }

    private func drawBrushPathAnnotation(_ annotation: CaptureAnnotation, inOverlay: Bool) {
        guard let brushPath = inOverlay
            ? overlayBrushPath(fromLocalBrushPath: annotation.brushPath)
            : annotation.brushPath,
            !brushPath.points.isEmpty
        else {
            return
        }

        let path = NSBezierPath()
        path.move(to: brushPath.points[0])
        if brushPath.points.count == 1 {
            path.line(to: NSPoint(x: brushPath.points[0].x + 0.01, y: brushPath.points[0].y + 0.01))
        } else {
            brushPath.points.dropFirst().forEach { path.line(to: $0) }
        }

        annotation.style.strokeColor.setStroke()
        path.lineWidth = annotation.style.strokeWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        let dashPattern = annotation.style.strokePattern.dashPattern(strokeWidth: annotation.style.strokeWidth)
        path.setLineDash(
            dashPattern,
            count: dashPattern.count,
            phase: 0
        )
        path.stroke()
    }

    private func drawMarkerLineAnnotation(_ annotation: CaptureAnnotation, inOverlay: Bool) {
        guard let markerLine = inOverlay
            ? overlayMarkerLine(fromLocalMarkerLine: annotation.markerLine)
            : annotation.markerLine
        else {
            return
        }

        let path = NSBezierPath()
        path.move(to: markerLine.start)
        path.line(to: markerLine.end)

        NSGraphicsContext.saveGraphicsState()
        let samplingLine = inOverlay
            ? markerLine
            : (overlayMarkerLine(fromLocalMarkerLine: annotation.markerLine) ?? markerLine)
        let prefersNormalBlend = markerLinePrefersNormalBlend(samplingLine)
        NSGraphicsContext.current?.cgContext.setBlendMode(prefersNormalBlend ? .normal : .multiply)
        let strokeColor = visibleMarkerColor(annotation.style.strokeColor, onDarkBackground: prefersNormalBlend)
        let markerColor = strokeColor.withAlphaComponent(CaptureAnnotationRenderer.markerOpacity)
        if isZeroLengthMarkerLine(markerLine) {
            markerColor.setFill()
            let radius = annotation.style.strokeWidth / 2
            NSBezierPath(
                ovalIn: NSRect(
                    x: markerLine.start.x - radius,
                    y: markerLine.start.y - radius,
                    width: annotation.style.strokeWidth,
                    height: annotation.style.strokeWidth
                )
            ).fill()
        } else {
            markerColor.setStroke()
            path.lineWidth = annotation.style.strokeWidth
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func markerLinePrefersNormalBlend(_ markerLine: CaptureMarkerLine) -> Bool {
        let sampleCount = 17
        var darkSamples = 0
        var validSamples = 0
        for index in 0..<sampleCount {
            let t = CGFloat(index) / CGFloat(sampleCount - 1)
            let point = NSPoint(
                x: markerLine.start.x + (markerLine.end.x - markerLine.start.x) * t,
                y: markerLine.start.y + (markerLine.end.y - markerLine.start.y) * t
            )
            guard let color = sampleColor(at: point) else {
                continue
            }
            validSamples += 1
            if perceivedLuminance(of: color) < 0.12 {
                darkSamples += 1
            }
        }
        return validSamples > 0 && darkSamples >= max(1, validSamples * 3 / 4)
    }

    private func visibleMarkerColor(_ color: NSColor, onDarkBackground: Bool) -> NSColor {
        guard onDarkBackground, perceivedLuminance(of: color) < 0.18 else {
            return color
        }
        return .white
    }

    private func drawArrowLineAnnotation(_ annotation: CaptureAnnotation, inOverlay: Bool) {
        guard let arrowLine = inOverlay
            ? overlayArrowLine(fromLocalArrowLine: annotation.arrowLine)
            : annotation.arrowLine
        else {
            return
        }

        let startDirection = direction(
            from: arrowLine.control,
            to: arrowLine.start,
            fallbackFrom: arrowLine.end,
            fallbackTo: arrowLine.start
        )
        let endDirection = direction(
            from: arrowLine.control,
            to: arrowLine.end,
            fallbackFrom: arrowLine.start,
            fallbackTo: arrowLine.end
        )

        let usesVectorBody = CaptureArrowVectorGeometry.isVectorArrow(arrowLine.startArrowType)
            || CaptureArrowVectorGeometry.isVectorArrow(arrowLine.endArrowType)

        if CaptureArrowVectorGeometry.isVectorArrow(arrowLine.endArrowType) {
            annotation.style.strokeColor.setFill()
            if let vectorPath = CaptureArrowVectorGeometry.bezierPathAlongCurve(
                for: arrowLine.endArrowType,
                start: arrowLine.start,
                control: arrowLine.control,
                end: arrowLine.end,
                strokeWidth: annotation.style.strokeWidth
            ) {
                vectorPath.path.fill()
            }
        }

        if !usesVectorBody {
            let bodyStart = arrowLine.startArrowType == .normal
                ? CaptureArrowVectorGeometry.pointAlongCurve(
                    start: arrowLine.end,
                    control: arrowLine.control,
                    end: arrowLine.start,
                    distanceFromEnd: CaptureArrowVectorGeometry.normalArrowHeadInset(for: annotation.style.strokeWidth)
                )
                : arrowLine.start
            let bodyEnd = arrowLine.endArrowType == .normal
                ? CaptureArrowVectorGeometry.pointAlongCurve(
                    start: arrowLine.start,
                    control: arrowLine.control,
                    end: arrowLine.end,
                    distanceFromEnd: CaptureArrowVectorGeometry.normalArrowHeadInset(for: annotation.style.strokeWidth)
                )
                : arrowLine.end
            let path = annotation.style.strokePattern.isSketch
                ? CaptureSketchStrokePath.sampleQuadraticCurve(
                    from: bodyStart,
                    control: arrowLine.control,
                    to: bodyEnd,
                    lineWidth: annotation.style.strokeWidth
                )
                : NSBezierPath()
            if !annotation.style.strokePattern.isSketch {
                path.move(to: bodyStart)
                appendQuadraticCurve(to: path, start: bodyStart, control: arrowLine.control, end: bodyEnd)
            }

            annotation.style.strokeColor.setStroke()
            path.lineWidth = annotation.style.strokeWidth
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            let dashPattern = annotation.style.strokePattern.dashPattern(strokeWidth: annotation.style.strokeWidth)
            path.setLineDash(
                dashPattern,
                count: dashPattern.count,
                phase: 0
            )
            path.stroke()
        }

        if CaptureArrowVectorGeometry.isVectorArrow(arrowLine.startArrowType) {
            annotation.style.strokeColor.setFill()
            if let vectorPath = CaptureArrowVectorGeometry.bezierPathAlongCurve(
                for: arrowLine.startArrowType,
                start: arrowLine.end,
                control: arrowLine.control,
                end: arrowLine.start,
                strokeWidth: annotation.style.strokeWidth
            ) {
                vectorPath.path.fill()
            }
        }
        if !CaptureArrowVectorGeometry.isVectorArrow(arrowLine.startArrowType) {
            drawArrowHead(
                type: arrowLine.startArrowType,
                tip: arrowLine.start,
                direction: startDirection,
                color: annotation.style.strokeColor,
                lineWidth: annotation.style.strokeWidth
            )
        }

        if !CaptureArrowVectorGeometry.isVectorArrow(arrowLine.endArrowType) {
            drawArrowHead(
                type: arrowLine.endArrowType,
                tip: arrowLine.end,
                direction: endDirection,
                color: annotation.style.strokeColor,
                lineWidth: annotation.style.strokeWidth
            )
        }
    }

    private static func defaultTextStyle() -> CaptureAnnotationStyle {
        var style = CaptureAnnotationStyle()
        let defaultColor = SelectionOverlayWindow.defaultPaletteColors.first ?? style.strokeColor
        style.strokeColor = defaultColor
        style.fillColor = defaultColor
        style.textSize = defaultTextSize
        style.textOutlineEnabled = true
        return style
    }

    private static func defaultNumberStyle() -> CaptureAnnotationStyle {
        var style = CaptureAnnotationStyle()
        let defaultColor = SelectionOverlayWindow.defaultPaletteColors.first ?? style.strokeColor
        style.strokeColor = defaultColor
        style.fillColor = defaultColor
        style.textSize = 3
        return style
    }

    private static func defaultMagnifierStyle() -> CaptureAnnotationStyle {
        var style = CaptureAnnotationStyle()
        style.strokeColor = NSColor.systemBlue
        style.fillColor = NSColor.systemBlue
        style.strokeWidth = SelectionToolbarState.strokeWidthValues(for: .magnifier)[0]
        style.strokePattern = .solid
        style.fillEnabled = false
        return style
    }

    private func shouldSuppressEditingTextAnnotation(_ annotation: CaptureAnnotation) -> Bool {
        guard
            let editingTextAnnotationIndex,
            textEditorDrawsVisibleText,
            annotations.indices.contains(editingTextAnnotationIndex),
            annotations[editingTextAnnotationIndex].kind == .text,
            annotation.kind == .text
        else {
            return false
        }

        let editingAnnotation = annotations[editingTextAnnotationIndex]
        return annotation.rect == editingAnnotation.rect
            && annotation.text == editingAnnotation.text
    }

    private var textEditorDrawsVisibleText: Bool {
        guard let textEditor else {
            return false
        }
        let textAlpha = textEditor.textColor?.alphaComponent ?? 1
        let typingColor = textEditor.typingAttributes[.foregroundColor] as? NSColor
        return textAlpha > 0 || (typingColor?.alphaComponent ?? 0) > 0
    }

    private func drawSelectedAnnotationOutline(_ annotation: CaptureAnnotation) {
        if annotation.kind == .numberSequence {
            drawSelectedNumberMarkOutline(annotation)
            return
        }
        if annotation.kind == .arrowLine {
            drawSelectedArrowLineOutline(annotation)
            return
        }
        if annotation.kind == .brush {
            drawSelectedBrushPathOutline(annotation)
            return
        }
        if annotation.kind == .marker {
            drawSelectedMarkerLineOutline(annotation)
            return
        }

        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect)
        NSColor.systemBlue.setStroke()
        let outline: NSBezierPath
        if annotationKindSupportsRotationHandle(annotation.kind) {
            outline = rotatedRectanglePath(for: rect, angle: annotation.rotationAngle)
        } else {
            outline = annotation.kind == .ellipse ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
        }
        if annotation.kind == .mosaicRectangle {
            outline.lineWidth = 0.6
            outline.setLineDash([3, 2], count: 2, phase: 0)
        } else {
            outline.lineWidth = 1.5
            outline.setLineDash([4, 3], count: 2, phase: 0)
        }
        outline.stroke()
        if SelectionToolbarState.annotationKindSupportsGeometryEditing(annotation.kind) {
            drawResizeHandles(
                for: rect,
                kind: annotation.kind,
                rotationAngle: annotationKindSupportsRotationHandle(annotation.kind) ? annotation.rotationAngle : 0
            )
        }
        if annotationKindSupportsRotationHandle(annotation.kind), let point = mosaicRectangleRotationHandlePoint(for: annotation) {
            drawMosaicRectangleRotationHandle(at: point)
        }
    }

    private func drawSelectedNumberMarkOutline(_ annotation: CaptureAnnotation) {
        let rect = numberEditingOutlineRect(for: annotation)
        NSColor.systemBlue.setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 1.5
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.stroke()

        guard shouldShowSelectedNumberControls() else {
            return
        }

        drawNumberHandle(.delete, for: annotation, enabled: true)
        drawNumberHandle(.resize, for: annotation, enabled: true)
        if annotation.numberMarkType == .number || annotation.numberMarkType == nil {
            drawNumberHandle(.increment, for: annotation, enabled: canAdjustNumberAnnotation(delta: 1))
            drawNumberHandle(.decrement, for: annotation, enabled: canAdjustNumberAnnotation(delta: -1))
            if (annotation.numberSequenceIndex ?? 1) > 1 {
                drawNumberHandle(.reset, for: annotation, enabled: true)
            }
        }
    }

    private func drawNumberHandle(_ kind: NumberHandleKind, for annotation: CaptureAnnotation, enabled: Bool) {
        guard let rect = numberHandleRect(for: annotation, kind: kind) else {
            return
        }

        switch kind {
        case .delete:
            drawNumberDeleteHandle(in: rect, enabled: enabled)
        case .resize:
            drawNumberCircleHandle(in: rect, enabled: enabled)
        case .increment, .decrement:
            drawNumberSquareHandle(kind, in: rect, enabled: enabled)
        case .reset:
            drawNumberResetHandle(in: rect, enabled: enabled)
        }
    }

    private func drawNumberCircleHandle(in rect: NSRect, enabled: Bool) {
        let color = enabled ? NSColor.systemBlue : NSColor.disabledControlTextColor
        NSColor.white.setFill()
        NSBezierPath(ovalIn: rect).fill()
        color.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1.2, dy: 1.2)).fill()
    }

    private func drawNumberSquareHandle(_ kind: NumberHandleKind, in rect: NSRect, enabled: Bool) {
        let color = enabled ? NSColor.systemBlue : NSColor.disabledControlTextColor
        NSColor.white.setFill()
        NSBezierPath(rect: rect).fill()
        color.setStroke()
        let outline = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
        outline.lineWidth = 1.2
        outline.stroke()

        let path = NSBezierPath()
        let inset = rect.insetBy(dx: 4.5, dy: 4.5)
        path.move(to: NSPoint(x: inset.minX, y: rect.midY))
        path.line(to: NSPoint(x: inset.maxX, y: rect.midY))
        if kind == .increment {
            path.move(to: NSPoint(x: rect.midX, y: inset.minY))
            path.line(to: NSPoint(x: rect.midX, y: inset.maxY))
        }
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func drawNumberDeleteHandle(in rect: NSRect, enabled: Bool) {
        NSColor.white.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: -1, dy: -1)).fill()

        if let image = Bundle.main.url(forResource: "close", withExtension: "svg")
            .flatMap(NSImage.init(contentsOf:)) {
            image.draw(in: rect)
            return
        }

        (enabled ? NSColor.systemBlue : NSColor.disabledControlTextColor).setFill()
        NSBezierPath(ovalIn: rect).fill()
        drawNumberSymbol("×", in: rect.insetBy(dx: 2, dy: 2), color: .white)
    }

    private func drawNumberResetHandle(in rect: NSRect, enabled: Bool) {
        let color = enabled ? NSColor.systemBlue : NSColor.disabledControlTextColor

        NSColor.white.setFill()
        NSBezierPath(ovalIn: rect).fill()
        color.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1.2, dy: 1.2)).fill()
        drawNumberResetFallback(in: rect, color: .white, lineWidth: 1.7)
    }

    private func drawNumberResetFallback(in rect: NSRect, color: NSColor, lineWidth: CGFloat = 1.25) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let iconRect = rect.insetBy(dx: 2.5, dy: 2.5)
        func svgPoint(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(
                x: iconRect.minX + x / 16 * iconRect.width,
                y: iconRect.maxY - y / 16 * iconRect.height
            )
        }

        context.saveGState()

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: svgPoint(8, 8),
            radius: iconRect.width * 5 / 16,
            startAngle: 48,
            endAngle: 334,
            clockwise: false
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()

        let arrow = NSBezierPath()
        arrow.move(to: svgPoint(8, 4.466))
        arrow.line(to: svgPoint(8, 0.534))
        arrow.line(to: svgPoint(10.77, 2.5))
        arrow.line(to: svgPoint(8.41, 4.658))
        arrow.close()
        color.setFill()
        arrow.fill()
        context.restoreGState()
    }

    private func drawSelectedArrowLineOutline(_ annotation: CaptureAnnotation) {
        guard let arrowLine = overlayArrowLine(fromLocalArrowLine: annotation.arrowLine) else {
            return
        }

        let outline = NSBezierPath()
        outline.move(to: arrowLine.start)
        appendQuadraticCurve(to: outline, start: arrowLine.start, control: arrowLine.control, end: arrowLine.end)
        NSColor.systemBlue.setStroke()
        outline.lineWidth = 1.2
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.stroke()

        drawArrowLineHandle(at: arrowLine.start, radius: 4)
        drawArrowLineHandle(at: arrowLine.end, radius: 4)
        drawArrowLineHandle(at: arrowLine.control, radius: 3.5)
    }

    private func drawSelectedBrushPathOutline(_ annotation: CaptureAnnotation) {
        selectedBrushEndpointMarkers(for: annotation).forEach { point in
            drawBrushEndpointHandle(at: point)
        }
    }

    private func drawSelectedMarkerLineOutline(_ annotation: CaptureAnnotation) {
        guard let markerLine = overlayMarkerLine(fromLocalMarkerLine: annotation.markerLine) else {
            return
        }
        guard !isZeroLengthMarkerLine(markerLine) else {
            return
        }

        [
            SelectionToolbarState.markerRotationHandlePoint(for: .start, line: markerLine),
            SelectionToolbarState.markerRotationHandlePoint(for: .end, line: markerLine),
        ].compactMap { $0 }.forEach { point in
            drawBrushEndpointHandle(at: point)
        }
    }

    private func appendQuadraticCurve(to path: NSBezierPath, start: NSPoint, control: NSPoint, end: NSPoint) {
        let firstControl = NSPoint(
            x: start.x + (control.x - start.x) * 2 / 3,
            y: start.y + (control.y - start.y) * 2 / 3
        )
        let secondControl = NSPoint(
            x: end.x + (control.x - end.x) * 2 / 3,
            y: end.y + (control.y - end.y) * 2 / 3
        )
        path.curve(to: end, controlPoint1: firstControl, controlPoint2: secondControl)
    }

    private func drawArrowLineHandle(at point: NSPoint, radius: CGFloat) {
        let rect = NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        NSColor.systemBlue.setFill()
        NSColor.white.setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.fill()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawBrushEndpointHandle(at point: NSPoint) {
        drawArrowLineHandle(at: point, radius: 3)
    }

    private func drawMosaicRectangleRotationHandle(at point: NSPoint) {
        guard let image = NSCursor.svgImage(named: "refresh-svgrepo-com3") else {
            return
        }
        let size: CGFloat = 12
        image.draw(in: NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
    }

    private func drawTextDeleteHandle(at point: NSPoint) {
        let size = textDeleteHandleIconSize
        let rect = NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        guard let image = NSCursor.svgImage(named: "x-circle-fill") else {
            NSColor.systemBlue.setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSColor.white.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: rect.minX + 4, y: rect.minY + 4))
            path.line(to: NSPoint(x: rect.maxX - 4, y: rect.maxY - 4))
            path.move(to: NSPoint(x: rect.minX + 4, y: rect.maxY - 4))
            path.line(to: NSPoint(x: rect.maxX - 4, y: rect.minY + 4))
            path.stroke()
            return
        }

        image.draw(in: rect)
    }

    private func selectedBrushEndpointMarkers(for annotation: CaptureAnnotation) -> [NSPoint] {
        guard annotation.kind == .brush,
              let brushPath = overlayBrushPath(fromLocalBrushPath: annotation.brushPath),
              brushPath.points.count >= 2 else {
            return []
        }

        return [
            SelectionToolbarState.brushRotationHandlePoint(for: .start, path: brushPath),
            SelectionToolbarState.brushRotationHandlePoint(for: .end, path: brushPath),
        ].compactMap { $0 }
    }

    private func drawResizeHandles(for rect: NSRect, kind: CaptureAnnotationKind, rotationAngle: CGFloat = 0) {
        let handles = resizeHandleCenters(for: rect, kind: kind, rotationAngle: rotationAngle)
        NSColor.systemBlue.setFill()
        NSColor.white.setStroke()
        for (index, center) in handles.enumerated() {
            let handle = ShapeResizeHandle.allCases[index]
            if kind == .text, handle == .topRight {
                drawTextDeleteHandle(at: center)
                continue
            }

            let handleRect = NSRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
            let path = NSBezierPath(ovalIn: handleRect)
            path.fill()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func handleRect(
        for rect: NSRect,
        handle: ShapeResizeHandle,
        kind: CaptureAnnotationKind,
        rotationAngle: CGFloat = 0
    ) -> NSRect {
        let centers = resizeHandleCenters(for: rect, kind: kind, rotationAngle: rotationAngle)
        let index = ShapeResizeHandle.allCases.firstIndex(of: handle) ?? 0
        let center = centers[index]
        return NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
    }

    private func drawMainToolbar(for selectionRect: NSRect) {
        guard let toolbar = mainToolbarRect(for: selectionRect) else {
            return
        }

        drawPanel(toolbar, opaque: true, alpha: 0.9)
        drawMainToolbarDragHandle(mainToolbarLeadingDragHandleRect(in: toolbar), enabled: true)
        drawMainToolbarSeparators(in: toolbar)

        for (button, rect) in toolbarButtonRects(in: toolbar) {
            let enabled = isToolbarButtonEnabled(button)
            if button == .finishEditing {
                drawToolbarButton(rect, symbol: nil, selected: false, enabled: enabled)
                if !drawToolbarImage(
                    named: "done",
                    in: rect,
                    template: true,
                    enabled: enabled,
                    inset: 0,
                    tintColor: button == .scroll ? .systemBlue : .black
                ) {
                    drawNumberMarkIcon(
                        .check,
                        in: rect.insetBy(dx: 3, dy: 3),
                        color: button == .scroll ? .systemBlue : .black,
                        toolbar: true
                    )
                }
            } else {
                drawToolbarButton(rect, symbol: symbolName(for: button, enabled: enabled), selected: buttonMatchesCurrentTool(button), enabled: enabled)
            }
        }
        drawMainToolbarDragHandle(mainToolbarDragHandleRect(in: toolbar), enabled: true)
    }

    private func drawMainToolbarDragHandle(_ rect: NSRect, enabled: Bool) {
        drawToolbarButton(rect, symbol: nil, selected: false, enabled: enabled)
        let color = SelectionToolbarState.mainToolbarDragHandleIconColor(enabled: enabled)
        let imageInset = toolbarIconInset(for: "settings-more")
        if drawToolbarImage(
            named: "settings-more",
            in: rect,
            template: true,
            enabled: enabled,
            selected: false,
            inset: imageInset,
            tintColor: color
        ) || drawToolbarImage(
            named: "toolbar-settings-more",
            in: rect,
            template: true,
            enabled: enabled,
            selected: false,
            inset: imageInset,
            tintColor: color
        ) {
            return
        }
    }

    private func drawMainToolbarSeparators(in toolbar: NSRect) {
        let buttonRects = Dictionary(uniqueKeysWithValues: toolbarButtonRects(in: toolbar))
        var separators: [(ToolbarButton, ToolbarButton)] = [
            (.redo, .cancel),
        ]
        if featureGate.isEnabled(.scrollCapture) {
            separators.insert(contentsOf: [(.eraser, .scroll), (.scroll, .undo)], at: 0)
        } else {
            separators.insert((.eraser, .undo), at: 0)
        }

        NSColor.tertiaryLabelColor.withAlphaComponent(0.5).setFill()

        for (leftButton, rightButton) in separators {
            guard let left = buttonRects[leftButton], let right = buttonRects[rightButton] else {
                continue
            }
            let x = left.maxX + (right.minX - left.maxX) / 2
            let separatorRect = NSRect(
                x: floor(x) + 0.25,
                y: toolbar.midY - 6,
                width: 1.5,
                height: 12
            )
            NSBezierPath(roundedRect: separatorRect, xRadius: 0.75, yRadius: 0.75).fill()
        }
    }

    private func isToolbarButtonEnabled(_ button: ToolbarButton) -> Bool {
        if scrollCaptureOverlayState != .inactive {
            return button == .scroll || button == .cancel
        }
        switch button {
        case .undo:
            return !undoAnnotationEntries.isEmpty || !annotations.isEmpty
        case .redo:
            return !redoAnnotationEntries.isEmpty
        default:
            return true
        }
    }

    private func drawTooltipIfNeeded() {
        guard let hoveredTooltip else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: samplerInfoFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let shortcut = SelectionToolbarState.toolbarShortcut(for: hoveredTooltip.identifier)
        let hasShortcutIcon = shortcut?.iconName != nil
        let iconSize: CGFloat = hasShortcutIcon ? 12 : 0
        let iconSpacing: CGFloat = hasShortcutIcon ? 3 : 0
        let titleText = hoveredTooltip.text + (shortcut == nil ? "" : " (")
        let titleSize = NSString(string: titleText).size(withAttributes: attributes)
        let keyText = shortcut.map { $0.displayText + ")" } ?? ""
        let keySize = NSString(string: keyText).size(withAttributes: attributes)
        let textSize = NSSize(
            width: titleSize.width + iconSize + iconSpacing + keySize.width,
            height: max(titleSize.height, iconSize)
        )
        let rect = SelectionToolbarState.tooltipRect(textSize: textSize, anchoredTo: hoveredTooltip.anchor, inside: safeLayoutBounds)
        NSColor(calibratedWhite: 0.08, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        let contentRect = rect.insetBy(dx: 8, dy: 5)
        NSString(string: titleText).draw(in: contentRect, withAttributes: attributes)
        guard let shortcut else {
            return
        }

        var keyTextX = contentRect.minX + titleSize.width
        if let iconName = shortcut.iconName {
            let iconRect = NSRect(
                x: keyTextX,
                y: contentRect.midY - iconSize / 2,
                width: iconSize,
                height: iconSize
            )
            if let image = SelectionToolbarState.tooltipShortcutIconImage(named: iconName, tint: .white, size: iconSize) {
                image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            keyTextX = iconRect.maxX + iconSpacing
        }
        NSString(string: keyText).draw(
            in: NSRect(
                x: keyTextX,
                y: contentRect.minY,
                width: keySize.width,
                height: contentRect.height
            ),
            withAttributes: attributes
        )
    }

    private func drawEyedropperMeasurementIfNeeded() {
        guard scrollCaptureOverlayState == .inactive,
              isEyedropperToolActive,
              let line = eyedropperMeasurementLine,
              let label = eyedropperMeasurementLabel
        else {
            return
        }

        let path = NSBezierPath()
        path.move(to: line.start)
        path.line(to: line.end)
        let dash: [CGFloat] = [6, 4]
        path.setLineDash(dash, count: dash.count, phase: 0)
        path.lineCapStyle = .round
        path.lineWidth = 3
        NSColor.white.withAlphaComponent(0.95).setStroke()
        path.stroke()
        path.lineWidth = 1.5
        NSColor.systemBlue.setStroke()
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: samplerInfoFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let labelRect = eyedropperMeasurementLabelRect(for: line, label: label)
        NSColor(calibratedWhite: 0.08, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        NSString(string: label).draw(in: labelRect.insetBy(dx: 7, dy: 4), withAttributes: attributes)
    }

    private func eyedropperMeasurementLabelRect(
        for line: (start: NSPoint, end: NSPoint),
        label: String
    ) -> NSRect {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: samplerInfoFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = NSString(string: label).size(withAttributes: attributes)
        var labelRect = NSRect(
            x: (line.start.x + line.end.x) / 2 - textSize.width / 2 - 7,
            y: max(line.start.y, line.end.y) + 8,
            width: textSize.width + 14,
            height: textSize.height + 8
        )
        labelRect.origin.x = max(safeLayoutBounds.minX + 4, min(labelRect.minX, safeLayoutBounds.maxX - labelRect.width - 4))
        labelRect.origin.y = max(safeLayoutBounds.minY + 4, min(labelRect.minY, safeLayoutBounds.maxY - labelRect.height - 4))
        return labelRect
    }

    private func drawColorSamplerIfNeeded() {
        guard scrollCaptureOverlayState == .inactive else { return }
        if isEyedropperToolActive {
            guard
                let point = sampledPointerPoint,
                let color = sampledColor,
                SelectionToolbarState.shouldShowExplicitColorSampler(
                    pointer: point,
                    selectionRect: lockedSelectionRect
                ),
                !isToolbarOrPanelPoint(point)
            else {
                return
            }

            let rect = SelectionToolbarState.colorSamplerRect(
                size: colorSamplerSize,
                pointer: point,
                inside: safeLayoutBounds
            )
            drawColorSamplerPanel(rect, point: point, color: color)
            return
        }

        guard
            let point = sampledPointerPoint,
            let color = sampledColor,
            let selectionRect = colorSamplerSelectionRect,
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: isShapeToolActive,
                hasAnnotations: !annotations.isEmpty,
                pointer: point,
                selectionRect: selectionRect
            )
        else {
            return
        }

        let rect = SelectionToolbarState.colorSamplerRect(
            size: colorSamplerSize,
            pointer: point,
            inside: safeLayoutBounds
        )
        drawColorSamplerPanel(rect, point: point, color: color)
    }

    private func drawColorSamplerPanel(_ rect: NSRect, point: NSPoint, color: NSColor) {
        let magnifierHeight: CGFloat = 96
        let infoRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - magnifierHeight)
        let magnifierRect = NSRect(x: rect.minX, y: rect.maxY - magnifierHeight, width: rect.width, height: magnifierHeight)

        let outline = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.white.setFill()
        outline.fill()
        NSColor(calibratedWhite: 0.72, alpha: 1).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).addClip()
        drawSamplerMagnifier(in: magnifierRect, centeredAt: point)
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor(calibratedWhite: 0.33, alpha: 0.98).setFill()
        NSBezierPath(rect: infoRect).fill()

        let coordinateAttributes: [NSAttributedString.Key: Any] = [
            .font: samplerInfoFont(ofSize: 12, weight: .medium),
            .foregroundColor: SelectionToolbarState.colorSamplerCoordinateTextColor,
        ]
        let coordinates = "(\(Int(point.x)) , \(Int(bounds.height - point.y)))"
        let coordinateSize = NSString(string: coordinates).size(withAttributes: coordinateAttributes)
        NSString(string: coordinates).draw(
            in: NSRect(
                x: infoRect.midX - coordinateSize.width / 2,
                y: infoRect.maxY - 23,
                width: coordinateSize.width,
                height: 16
            ),
            withAttributes: coordinateAttributes
        )

        let valueText = colorSamplerDisplayValue(for: color)
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: samplerInfoFont(ofSize: 13, weight: .semibold),
            .foregroundColor: SelectionToolbarState.colorSamplerValueTextColor,
        ]
        let valueSize = NSString(string: valueText).size(withAttributes: valueAttributes)
        let rowSpacing: CGFloat = 7
        let swatchRect = NSRect(
            x: infoRect.midX - (18 + rowSpacing + valueSize.width) / 2,
            y: infoRect.minY + 47,
            width: 18,
            height: 18
        )
        color.setFill()
        NSBezierPath(roundedRect: swatchRect, xRadius: 3, yRadius: 3).fill()
        NSColor.white.setStroke()
        let swatchBorder = NSBezierPath(roundedRect: swatchRect, xRadius: 3, yRadius: 3)
        swatchBorder.lineWidth = 1.2
        swatchBorder.stroke()

        NSString(string: valueText).draw(
            in: NSRect(
                x: swatchRect.maxX + rowSpacing,
                y: infoRect.minY + 48,
                width: valueSize.width,
                height: 18
            ),
            withAttributes: valueAttributes
        )

        let isShowingCopySuccess = colorSamplerCopySuccessUntil.map { Date() < $0 } ?? false
        let copyHintAttributes: [NSAttributedString.Key: Any] = [
            .font: samplerInfoFont(ofSize: 12, weight: .medium),
            .foregroundColor: isShowingCopySuccess
                ? SelectionToolbarState.colorSamplerCopySuccessTextColor
                : SelectionToolbarState.colorSamplerCopyHintTextColor,
        ]
        let copyText = NSMutableAttributedString(
            string: isShowingCopySuccess
                ? SelectionToolbarState.colorSamplerCopySuccessText
                : SelectionToolbarState.colorSamplerCopyHintText(
                    for: colorSamplerCopyMode,
                    l10n: L10n(language: settings.language)
                ),
            attributes: copyHintAttributes
        )
        if !isShowingCopySuccess {
            copyText.addAttributes(
                [.font: samplerInfoFont(ofSize: 12, weight: .bold)],
                range: NSRange(location: 1, length: 1)
            )
        }
        let copyBounds = copyText.boundingRect(
            with: NSSize(width: infoRect.width - 24, height: 20),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let copyRect = SelectionToolbarState.colorSamplerCopyHintRect(
            textSize: copyBounds.size,
            infoRect: infoRect,
            swatchRect: swatchRect
        )
        copyText.draw(
            in: copyRect
        )

        let switchHintAttributes: [NSAttributedString.Key: Any] = [
            .font: samplerInfoFont(ofSize: 12, weight: .regular),
            .foregroundColor: SelectionToolbarState.colorSamplerSwitchHintTextColor,
        ]
        let switchText = NSMutableAttributedString(
            string: "按 Shift 切换 RGB/HEX",
            attributes: switchHintAttributes
        )
        switchText.addAttributes(
            [.font: samplerInfoFont(ofSize: 12, weight: .semibold)],
            range: NSRange(location: 2, length: 5)
        )
        let switchBounds = switchText.boundingRect(
            with: NSSize(width: infoRect.width - 20, height: 20),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let switchRect = SelectionToolbarState.colorSamplerSwitchHintRect(
            textSize: switchBounds.size,
            infoRect: infoRect,
            copyHintRect: copyRect
        )
        switchText.draw(
            in: switchRect
        )
    }

    private func samplerInfoFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let fontName = weight.rawValue >= NSFont.Weight.semibold.rawValue ? "Arial-BoldMT" : "Arial"
        return NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    private func drawSamplerMagnifier(in rect: NSRect, centeredAt point: NSPoint) {
        let gridSize = 9
        let cellWidth = rect.width / CGFloat(gridSize)
        let cellHeight = rect.height / CGFloat(gridSize)
        let contentRect = rect
        let centerIndex = gridSize / 2
        let samplingSource = colorSamplerPixelSource()

        NSColor.white.setFill()
        NSBezierPath(rect: contentRect).fill()

        for row in 0..<gridSize {
            for column in 0..<gridSize {
                let cellRect = NSRect(
                    x: contentRect.minX + CGFloat(column) * cellWidth,
                    y: contentRect.minY + CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )
                (magnifierSampleColor(
                    centeredAt: point,
                    columnOffset: column - centerIndex,
                    rowOffset: centerIndex - row,
                    source: samplingSource
                ) ?? .white).setFill()
                NSBezierPath(rect: cellRect).fill()
            }
        }

        NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
        for step in 0...gridSize {
            let x = contentRect.minX + CGFloat(step) * cellWidth
            let y = contentRect.minY + CGFloat(step) * cellHeight
            let vertical = NSBezierPath()
            vertical.move(to: NSPoint(x: x, y: contentRect.minY))
            vertical.line(to: NSPoint(x: x, y: contentRect.maxY))
            vertical.lineWidth = 0.8
            vertical.stroke()

            let horizontal = NSBezierPath()
            horizontal.move(to: NSPoint(x: contentRect.minX, y: y))
            horizontal.line(to: NSPoint(x: contentRect.maxX, y: y))
            horizontal.lineWidth = 0.8
            horizontal.stroke()
        }

        let centerRect = NSRect(
            x: contentRect.midX - cellWidth / 2,
            y: contentRect.midY - cellHeight / 2,
            width: cellWidth,
            height: cellHeight
        )
        NSColor.black.setStroke()
        let centerBorder = NSBezierPath(rect: centerRect)
        centerBorder.lineWidth = 1.6
        centerBorder.stroke()
    }

    private func colorSamplerDisplayValue(for color: NSColor) -> String {
        switch colorSamplerCopyMode {
        case .hex:
            return hexString(for: color)
        case .rgb:
            return rgbString(for: color)
        }
    }

    private func drawOptionsToolbar(for selectionRect: NSRect) {
        guard let optionsRect = optionsToolbarRect else {
            return
        }

        let layout = optionsToolbarLayout(in: optionsRect)
        drawPanel(optionsRect, opaque: true, alpha: 0.9)
        drawOptionsToolbarSeparators(in: optionsRect)

        if optionsToolbarMode != .mosaic {
            let strokeWidths = SelectionToolbarState.strokeWidthValues(for: optionsToolbarMode)
            for (index, rect) in layout.strokeWidths.enumerated() {
                let width = strokeWidths[index]
                drawToolbarButton(optionButtonBackgroundRect(for: rect), symbol: nil, selected: currentStyle.strokeWidth == width, enabled: true)
                (currentStyle.strokeWidth == width ? NSColor.controlAccentColor : NSColor.labelColor).setStroke()
                let line = NSBezierPath()
                line.move(to: NSPoint(x: rect.minX + 4, y: rect.midY))
                line.line(to: NSPoint(x: rect.maxX - 4, y: rect.midY))
                line.lineWidth = SelectionToolbarState.strokeWidthPreviewLineWidth(for: width, mode: optionsToolbarMode)
                line.lineCapStyle = .round
                line.stroke()
            }
        }

        switch optionsToolbarMode {
        case .shape:
            drawFillToggle(in: optionsRect)
            drawShapeModeButtons(in: optionsRect)
        case .arrowLine:
            drawArrowTypeFields(in: optionsRect)
        case .brush, .marker:
            break
        case .mosaic:
            drawMosaicModeControls(in: optionsRect)
        case .text:
            drawTextOptions(in: optionsRect)
        case .numberSequence:
            drawNumberOptions(in: optionsRect)
        case .magnifier:
            drawMagnifierOptions(in: optionsRect)
        case .eraser:
            drawEraserOptions(in: optionsRect)
        }
        if SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode) {
            drawStrokeStyleField(in: optionsRect)
        }
        if optionsToolbarMode != .mosaic && optionsToolbarMode != .eraser {
            drawColorSwatches(in: optionsRect)
        }
    }

    private func drawEraserOptions(in optionsRect: NSRect) {
        let layout = optionsToolbarLayout(in: optionsRect)
        if let eraserButton = layout.eraserPointMode {
            drawToolbarButton(
                eraserButton,
                symbol: "toolbar-eraser-tool",
                selected: eraserMode == .point,
                enabled: true
            )
        }
        if let rectangleButton = layout.eraserRectangleMode {
            drawToolbarButton(
                rectangleButton,
                symbol: "toolbar-screenshot",
                selected: eraserMode == .rectangle,
                enabled: true
            )
        }
        if let clearAllButton = layout.eraserClearAll {
            drawToolbarButton(
                clearAllButton,
                symbol: "toolbar-trash",
                selected: false,
                enabled: true
            )
        }
    }

    private func drawMagnifierOptions(in optionsRect: NSRect) {
        let layout = optionsToolbarLayout(in: optionsRect)
        drawMagnifierShapeButtons(in: optionsRect)
        drawTextPopupField(magnifierZoomLabel(currentMagnifierZoom), in: layout.magnifierZoom, compact: true)
    }

    private func drawMagnifierShapeButtons(in optionsRect: NSRect) {
        let layout = optionsToolbarLayout(in: optionsRect)
        if let rectangleButton = layout.rectangleMode {
            drawToolbarButton(shapeModeBackgroundRect(for: rectangleButton), symbol: nil, selected: currentMagnifierShape == .rectangle, enabled: true)
            (currentMagnifierShape == .rectangle ? NSColor.controlAccentColor : NSColor.labelColor).setStroke()
            let path = NSBezierPath(roundedRect: rectangleIconRect(in: rectangleButton), xRadius: 1.5, yRadius: 1.5)
            path.lineWidth = 1.6
            path.stroke()
        }
        if let circleButton = layout.ellipseMode {
            drawToolbarButton(optionButtonBackgroundRect(for: circleButton), symbol: nil, selected: currentMagnifierShape == .circle, enabled: true)
            (currentMagnifierShape == .circle ? NSColor.controlAccentColor : NSColor.labelColor).setStroke()
            let path = NSBezierPath(ovalIn: circleIconRect(in: circleButton))
            path.lineWidth = 1.6
            path.stroke()
        }
    }

    private func magnifierZoomLabel(_ zoom: CGFloat) -> String {
        let normalized = SelectionToolbarState.magnifierZoomValues.first(where: { abs($0 - zoom) < 0.001 }) ?? zoom
        return normalized == floor(normalized) ? "\(Int(normalized))x" : "\(normalized)x"
    }

    private func drawOptionsToolbarSeparators(in optionsRect: NSRect) {
        let layout = optionsToolbarLayout(in: optionsRect)
        let firstSwatchMinX = layout.colorSwatches.map { $0.minX }.min()
        var separatorXs: [CGFloat] = []

        switch optionsToolbarMode {
        case .shape:
            if let fill = layout.fillToggle, let rectangle = layout.rectangleMode, let ellipse = layout.ellipseMode {
                separatorXs.append(optionButtonBackgroundRect(for: fill).maxX + (shapeModeBackgroundRect(for: rectangle).minX - optionButtonBackgroundRect(for: fill).maxX) / 2)
                separatorXs.append(optionButtonBackgroundRect(for: ellipse).maxX + (layout.strokeStyle.minX - optionButtonBackgroundRect(for: ellipse).maxX) / 2)
            }
            if let firstSwatchMinX {
                separatorXs.append(layout.strokeStyle.maxX + (firstSwatchMinX - layout.strokeStyle.maxX) / 2)
            }
        case .arrowLine:
            if let lastStrokeWidth = layout.strokeWidths.last {
                separatorXs.append(lastStrokeWidth.maxX + (layout.strokeStyle.minX - lastStrokeWidth.maxX) / 2)
            }
            if let startArrowType = layout.startArrowType {
                separatorXs.append(layout.strokeStyle.maxX + (startArrowType.minX - layout.strokeStyle.maxX) / 2)
            }
            if let endArrowType = layout.endArrowType, let firstSwatchMinX {
                separatorXs.append(endArrowType.maxX + (firstSwatchMinX - endArrowType.maxX) / 2)
            }
        case .brush:
            if let lastStrokeWidth = layout.strokeWidths.last {
                separatorXs.append(lastStrokeWidth.maxX + (layout.strokeStyle.minX - lastStrokeWidth.maxX) / 2)
            }
            if let firstSwatchMinX {
                separatorXs.append(layout.strokeStyle.maxX + (firstSwatchMinX - layout.strokeStyle.maxX) / 2)
            }
        case .marker:
            if let lastStrokeWidth = layout.strokeWidths.last, let firstSwatchMinX {
                separatorXs.append(lastStrokeWidth.maxX + (firstSwatchMinX - lastStrokeWidth.maxX) / 2)
            }
        case .eraser:
            if let separator = layout.eraserClearAllSeparator {
                separatorXs.append(separator.minX)
            }
        case .mosaic:
            break
        case .magnifier:
            if let lastStrokeWidth = layout.strokeWidths.last,
               let rectangle = layout.rectangleMode,
               let ellipse = layout.ellipseMode {
                separatorXs.append(lastStrokeWidth.maxX + (shapeModeBackgroundRect(for: rectangle).minX - lastStrokeWidth.maxX) / 2)
                separatorXs.append(optionButtonBackgroundRect(for: ellipse).maxX + (layout.magnifierZoom.minX - optionButtonBackgroundRect(for: ellipse).maxX) / 2)
            }
            if let firstSwatchMinX {
                separatorXs.append(layout.magnifierZoom.maxX + (firstSwatchMinX - layout.magnifierZoom.maxX) / 2)
            }
        case .text:
            if let firstSwatchMinX {
                separatorXs.append(layout.textOutline.maxX + (layout.textFont.minX - layout.textOutline.maxX) / 2)
                separatorXs.append(layout.textFont.maxX + (layout.textSize.minX - layout.textFont.maxX) / 2)
                separatorXs.append(layout.textSize.maxX + (firstSwatchMinX - layout.textSize.maxX) / 2)
            }
        case .numberSequence:
            if let firstSwatchMinX {
                separatorXs.append(layout.numberMarkType.maxX + (layout.numberSize.minX - layout.numberMarkType.maxX) / 2)
                separatorXs.append(layout.numberSize.maxX + (firstSwatchMinX - layout.numberSize.maxX) / 2)
            }
        }

        NSColor.tertiaryLabelColor.withAlphaComponent(0.5).setFill()
        for x in separatorXs {
            let separatorRect = NSRect(
                x: floor(x) + 0.25,
                y: optionsRect.midY - 6,
                width: 1.5,
                height: 12
            )
            NSBezierPath(roundedRect: separatorRect, xRadius: 0.75, yRadius: 0.75).fill()
        }
    }

    private func drawStrokeStyleField(in optionsRect: NSRect) {
        let field = strokeStyleFieldRect(in: optionsRect)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: field, xRadius: 4, yRadius: 4).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: field, xRadius: 4, yRadius: 4).stroke()

        drawStrokePatternSample(
            currentStyle.strokePattern,
            from: NSPoint(x: field.minX + 10, y: field.midY),
            to: NSPoint(x: field.maxX - 22, y: field.midY),
            color: .labelColor
        )
        drawTriangle(in: NSRect(x: field.maxX - 16, y: field.midY - 3, width: 7, height: 5), color: .labelColor)
    }

    private func drawArrowTypeFields(in optionsRect: NSRect) {
        guard
            let startField = optionsToolbarLayout(in: optionsRect).startArrowType,
            let endField = optionsToolbarLayout(in: optionsRect).endArrowType
        else {
            return
        }

        drawArrowTypeField(currentStartArrowType, in: startField, pointsRight: false)
        drawArrowTypeField(currentEndArrowType, in: endField, pointsRight: true)
    }

    private func drawArrowTypeField(_ type: CaptureArrowType, in field: NSRect, pointsRight: Bool) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: field, xRadius: 4, yRadius: 4).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: field, xRadius: 4, yRadius: 4).stroke()

        drawArrowTypeSample(
            type,
            in: SelectionToolbarState.arrowTypeSampleRect(in: field, pointsRight: pointsRight),
            pointsRight: pointsRight,
            color: .labelColor,
            lineWidth: 1.6
        )
        drawTriangle(in: SelectionToolbarState.arrowTypeDisclosureRect(in: field), color: .labelColor)
    }

    private func drawStrokeStyleMenu(for selectionRect: NSRect) {
        guard let options = optionsToolbarRect else {
            return
        }

        let menu = strokeStyleMenuRect(in: options)
        drawPanel(menu)

        for (index, option) in strokePatternOptions.enumerated() {
            let pattern = option.pattern
            let item = strokeStyleMenuItemRects(in: menu)[index]
            let selected = pattern == currentStyle.strokePattern
            drawToolbarButton(item, symbol: nil, selected: selected, enabled: option.isEnabled)

            let strokeColor = selected ? NSColor.controlAccentColor : NSColor.labelColor
            drawStrokePatternSample(
                pattern,
                from: NSPoint(x: item.minX + 10, y: item.midY),
                to: NSPoint(x: item.maxX - 10, y: item.midY),
                color: option.isEnabled ? strokeColor : NSColor.disabledControlTextColor
            )
        }
    }

    private func drawArrowTypeMenu(field: ArrowTypeField) {
        guard let options = optionsToolbarRect else {
            return
        }

        let menu = arrowTypeMenuRect(in: options, field: field)
        drawPanel(menu)
        let selectedType = field == .start ? currentStartArrowType : currentEndArrowType
        let pointsRight = field == .end

        for (index, type) in CaptureArrowType.allCases.enumerated() {
            let item = arrowTypeMenuItemRects(in: menu)[index]
            let selected = type == selectedType
            drawToolbarButton(item, symbol: nil, selected: selected, enabled: true)

            let color = selected ? NSColor.controlAccentColor : NSColor.labelColor
            drawArrowTypeSample(
                type,
                in: SelectionToolbarState.arrowTypeSampleRect(in: item.insetBy(dx: 8, dy: 4), pointsRight: pointsRight),
                pointsRight: pointsRight,
                color: color,
                lineWidth: 1.8
            )
        }
    }

    private func drawArrowTypeSample(
        _ type: CaptureArrowType,
        in rect: NSRect,
        pointsRight: Bool,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        if type == .normal || type == .solidArrow || type == .hollowArrow {
            let scale = max(0.6, min((rect.width - 2) / 16, (rect.height - 2) / 8))
            let direction: CGFloat = pointsRight ? 1 : -1
            let tip = NSPoint(x: rect.midX + direction * 8 * scale, y: rect.midY)
            color.setFill()
            guard
                let vectorPath = CaptureArrowVectorGeometry.bezierPath(
                    for: type,
                    tip: tip,
                    direction: CGVector(dx: direction, dy: 0),
                    scale: scale
                )
            else {
                return
            }
            vectorPath.path.fill()
            return
        }

        let start = pointsRight
            ? NSPoint(x: rect.minX, y: rect.midY)
            : NSPoint(x: rect.maxX, y: rect.midY)
        let end = pointsRight
            ? NSPoint(x: rect.maxX - 5, y: rect.midY)
            : NSPoint(x: rect.minX + 5, y: rect.midY)
        let body = NSBezierPath()
        body.move(to: start)
        body.line(to: end)

        color.setStroke()
        body.lineWidth = lineWidth
        body.lineCapStyle = .round
        body.lineJoinStyle = .round
        body.stroke()
        drawArrowHead(type: type, tip: end, pointsRight: pointsRight, color: color, lineWidth: lineWidth)
    }

    private func drawArrowHead(type: CaptureArrowType, tip: NSPoint, pointsRight: Bool, color: NSColor, lineWidth: CGFloat) {
        guard type != .none else {
            return
        }

        let direction: CGFloat = pointsRight ? 1 : -1
        color.setStroke()
        color.setFill()
        switch type {
        case .none:
            return
        case .bar:
            let capHalfWidth = max(4, lineWidth * 2.1)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: tip.x, y: tip.y + capHalfWidth))
            path.line(to: NSPoint(x: tip.x, y: tip.y - capHalfWidth))
            path.lineWidth = max(1.5, lineWidth)
            path.lineCapStyle = .butt
            path.stroke()
        case .dot:
            let radius = max(3, lineWidth * 1.45)
            NSBezierPath(ovalIn: NSRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2)).fill()
        case .diamond:
            let diamondLength = max(8, lineWidth * 3.4)
            let diamondHalfWidth = max(3.5, lineWidth * 1.6)
            let center = NSPoint(x: tip.x - direction * diamondLength * 0.5, y: tip.y)
            let back = NSPoint(x: tip.x - direction * diamondLength, y: tip.y)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: NSPoint(x: center.x, y: center.y + diamondHalfWidth))
            path.line(to: back)
            path.line(to: NSPoint(x: center.x, y: center.y - diamondHalfWidth))
            path.close()
            path.fill()
        case .normal, .solidArrow, .hollowArrow:
            return
        }
    }

    private func drawArrowHead(
        type: CaptureArrowType,
        tip: NSPoint,
        direction: CGVector,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        guard type != .none else {
            return
        }

        let perp = CGVector(dx: -direction.dy, dy: direction.dx)
        color.setStroke()
        color.setFill()
        switch type {
        case .none:
            return
        case .bar:
            let capHalfWidth = max(5, lineWidth * 2.1)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: tip.x + perp.dx * capHalfWidth, y: tip.y + perp.dy * capHalfWidth))
            path.line(to: NSPoint(x: tip.x - perp.dx * capHalfWidth, y: tip.y - perp.dy * capHalfWidth))
            path.lineWidth = max(1.5, lineWidth)
            path.lineCapStyle = .butt
            path.stroke()
        case .dot:
            let radius = max(3.5, lineWidth * 1.45)
            NSBezierPath(ovalIn: NSRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2)).fill()
        case .diamond:
            let diamondLength = max(10, lineWidth * 3.3)
            let diamondHalfWidth = max(4, lineWidth * 1.5)
            let center = NSPoint(x: tip.x - direction.dx * diamondLength * 0.5, y: tip.y - direction.dy * diamondLength * 0.5)
            let back = NSPoint(x: tip.x - direction.dx * diamondLength, y: tip.y - direction.dy * diamondLength)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: NSPoint(x: center.x + perp.dx * diamondHalfWidth, y: center.y + perp.dy * diamondHalfWidth))
            path.line(to: back)
            path.line(to: NSPoint(x: center.x - perp.dx * diamondHalfWidth, y: center.y - perp.dy * diamondHalfWidth))
            path.close()
            path.fill()
        case .normal, .solidArrow, .hollowArrow:
            guard
                let vectorPath = CaptureArrowVectorGeometry.bezierPath(
                    for: type,
                    tip: tip,
                    direction: direction,
                    scale: max(0.8, lineWidth / 2),
                    minimumTemplateX: 11.45
                )
            else {
                return
            }
            vectorPath.path.fill()
        }
    }

    private func direction(from point: NSPoint, to tip: NSPoint, fallbackFrom: NSPoint, fallbackTo: NSPoint) -> CGVector {
        let dx = tip.x - point.x
        let dy = tip.y - point.y
        let length = hypot(dx, dy)
        if length > 0.001 {
            return CGVector(dx: dx / length, dy: dy / length)
        }

        let fallbackDx = fallbackTo.x - fallbackFrom.x
        let fallbackDy = fallbackTo.y - fallbackFrom.y
        let fallbackLength = hypot(fallbackDx, fallbackDy)
        guard fallbackLength > 0.001 else {
            return CGVector(dx: 1, dy: 0)
        }
        return CGVector(dx: fallbackDx / fallbackLength, dy: fallbackDy / fallbackLength)
    }

    private func trimmedPoint(_ point: NSPoint, direction: CGVector, inset: CGFloat) -> NSPoint {
        guard inset > 0 else {
            return point
        }
        return NSPoint(x: point.x - direction.dx * inset, y: point.y - direction.dy * inset)
    }

    private func drawStrokePatternSample(
        _ pattern: CaptureStrokePattern,
        from start: NSPoint,
        to end: NSPoint,
        color: NSColor
    ) {
        let sampleLineWidth: CGFloat = 2
        let sample = pattern.isSketch
            ? CaptureSketchStrokePath.sampleLine(from: start, to: end, lineWidth: sampleLineWidth)
            : NSBezierPath()
        if !pattern.isSketch {
            sample.move(to: start)
            sample.line(to: end)
        }

        color.setStroke()
        sample.lineWidth = sampleLineWidth
        sample.lineCapStyle = .round
        sample.lineJoinStyle = .round
        let dashPattern = pattern.dashPattern(strokeWidth: sampleLineWidth)
        sample.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        sample.stroke()
    }

    private func drawCornerRadiusPanel(for selectionRect: NSRect) {
        guard let panel = cornerRadiusPanelRect else {
            return
        }

        drawPanel(panel, opaque: true, alpha: 0.9)

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
        ]
        NSString(string: "圆角半径").draw(at: NSPoint(x: panel.minX + 8, y: panel.minY + 8), withAttributes: labelAttributes)

        let valueRect = cornerRadiusValueRect(in: panel)
        let track = cornerRadiusSliderTrackRect(in: panel, valueRect: valueRect)
        drawSlider(track: track, value: currentStyle.cornerRadius, maximum: 30)
        drawCornerRadiusValue(valueRect)
    }

    private func drawFillToggle(in optionsRect: NSRect) {
        let rect = fillToggleRect(in: optionsRect)
        drawToolbarButton(optionButtonBackgroundRect(for: rect), symbol: nil, selected: currentStyle.fillEnabled, enabled: true)
        let sample = rect.insetBy(dx: 4, dy: 4)
        let preview = SelectionToolbarState.fillPreviewStyle(currentShapeKind: currentShapeKind, currentStyle: currentStyle)
        preview.color.setFill()
        let path: NSBezierPath
        switch preview.shape {
        case .rectangle:
            path = NSBezierPath(roundedRect: sample, xRadius: 2, yRadius: 2)
        case .ellipse:
            path = NSBezierPath(ovalIn: sample)
        }
        path.fill()
        if preview.showsStrokeOutline {
            currentStyle.strokeColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawShapeModeButtons(in optionsRect: NSRect) {
        let rectangleButton = rectangleModeButtonRect(in: optionsRect)
        let ellipseButton = ellipseModeButtonRect(in: optionsRect)
        let rectangleSelected = currentShapeKind == .rectangle

        drawToolbarButton(shapeModeBackgroundRect(for: rectangleButton), symbol: nil, selected: rectangleSelected, enabled: true)
        (rectangleSelected ? NSColor.controlAccentColor : NSColor.labelColor).setStroke()
        let rectIcon = rectangleIconRect(in: rectangleButton)
        let rectIconPath = NSBezierPath(roundedRect: rectIcon, xRadius: 1.5, yRadius: 1.5)
        rectIconPath.lineWidth = 1.5
        rectIconPath.stroke()
        drawDisclosureCorner(in: shapeModeBackgroundRect(for: rectangleButton), enabled: true)

        let ellipseSelected = currentShapeKind == .ellipse
        drawToolbarButton(optionButtonBackgroundRect(for: ellipseButton), symbol: nil, selected: ellipseSelected, enabled: true)
        (ellipseSelected ? NSColor.controlAccentColor : NSColor.labelColor).setStroke()
        let circlePath = NSBezierPath(ovalIn: circleIconRect(in: ellipseButton))
        circlePath.lineWidth = 1.6
        circlePath.stroke()
    }

    private func drawTextOptions(in optionsRect: NSRect) {
        let layout = optionsToolbarLayout(in: optionsRect)
        drawTextIconToggle(named: "bold", in: layout.textBold, selected: currentStyle.textBold)
        drawTextIconToggle(named: "italic", in: layout.textItalic, selected: currentStyle.textItalic)
        drawTextIconToggle(named: "stroke", in: layout.textOutline, selected: currentStyle.textOutlineEnabled)
        drawTextPopupField(
            SelectionToolbarState.textFontDisplayName(for: currentTextFontFamily()),
            in: layout.textFont,
            compact: false
        )
        drawTextPopupField("\(Int(currentStyle.textSize.rounded()))", in: layout.textSize, compact: true)
    }

    private func drawNumberOptions(in optionsRect: NSRect) {
        let layout = optionsToolbarLayout(in: optionsRect)
        drawNumberMarkTypeField(in: layout.numberMarkType)
        drawTextPopupField("\(Int(currentStyle.textSize.rounded()))", in: layout.numberSize, compact: true)
    }

    private func drawNumberMarkTypeField(in field: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: field, xRadius: 4, yRadius: 4).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: field, xRadius: 4, yRadius: 4).stroke()

        drawNumberMarkIcon(
            currentNumberMarkType,
            in: NSRect(x: field.minX + 8, y: field.midY - 7, width: 14, height: 14),
            color: .labelColor,
            toolbar: true
        )
        drawTriangle(in: NSRect(x: field.maxX - 14, y: field.midY - 3, width: 7, height: 5), color: .labelColor)
    }

    private func drawNumberMarkTypeMenuIfNeeded() {
        guard activeNumberDropdown, let optionsToolbarRect else {
            return
        }

        let menu = numberMarkTypeMenuRect(in: optionsToolbarRect)
        drawPanel(menu)
        for (index, type) in CaptureNumberMarkType.allCases.enumerated() {
            let item = numberMarkTypeMenuItemRects(in: menu)[index]
            let selected = type == currentNumberMarkType
            drawToolbarButton(item, symbol: nil, selected: selected, enabled: true)
            drawNumberMarkIcon(
                type,
                in: NSRect(x: item.midX - 8, y: item.midY - 8, width: 16, height: 16),
                color: selected && type == .number ? NSColor.systemBlue : defaultNumberMenuColor(for: type),
                toolbar: true
            )
        }
    }

    private func drawMagnifierZoomMenuIfNeeded() {
        guard activeMagnifierZoomDropdown, let optionsToolbarRect else {
            return
        }

        let menu = magnifierZoomMenuRect(in: optionsToolbarRect)
        drawTextDropdownPanel(menu)
        for (index, value) in SelectionToolbarState.magnifierZoomValues.enumerated() {
            let item = magnifierZoomMenuItemRects(in: menu)[index]
            let selected = abs(currentMagnifierZoom - value) < 0.001
            if selected {
                NSColor.systemBlue.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: item.insetBy(dx: 4, dy: 2), xRadius: 5, yRadius: 5).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: selected ? .semibold : .medium),
                .foregroundColor: selected ? NSColor.systemBlue : NSColor.labelColor,
            ]
            let text = magnifierZoomLabel(value)
            let size = NSString(string: text).size(withAttributes: attributes)
            NSString(string: text).draw(
                at: NSPoint(x: item.midX - size.width / 2, y: item.midY - size.height / 2),
                withAttributes: attributes
            )
        }
    }

    private func defaultNumberMenuColor(for type: CaptureNumberMarkType) -> NSColor {
        switch type {
        case .number:
            return .labelColor
        case .check:
            return .systemGreen
        case .cross:
            return .systemRed
        }
    }

    private func drawNumberMarkIcon(
        _ type: CaptureNumberMarkType,
        in rect: NSRect,
        color: NSColor,
        toolbar: Bool,
        numberText: String = "1"
    ) {
        switch type {
        case .number:
            color.setFill()
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            circle.fill()
            let foregroundColor = readableNumberForegroundColor(on: color)
            let text = numberText
            let fontSize: CGFloat = toolbar ? 9 : (text.count >= 3 ? 8 : 12)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: foregroundColor,
            ]
            let size = NSString(string: text).size(withAttributes: attributes)
            NSString(string: text).draw(
                at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                withAttributes: attributes
            )
        case .check:
            drawNumberSymbol("✓", in: rect, color: color)
        case .cross:
            drawNumberSymbol("×", in: rect, color: color)
        }
    }

    private func drawNumberSymbol(_ symbol: String, in rect: NSRect, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: rect.height, weight: .bold),
            .foregroundColor: color,
        ]
        let size = NSString(string: symbol).size(withAttributes: attributes)
        NSString(string: symbol).draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawTextIconToggle(named name: String, in rect: NSRect, selected: Bool) {
        drawToolbarButton(optionButtonBackgroundRect(for: rect), symbol: nil, selected: selected, enabled: true)
        let iconSize = (name == "bold" || name == "italic")
            ? SelectionToolbarState.textEmphasisIconSize
            : SelectionToolbarState.textOptionIconSize
        let iconRect = NSRect(
            x: rect.midX - iconSize / 2,
            y: rect.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        _ = drawToolbarImage(
            named: name,
            in: iconRect,
            template: true,
            enabled: true,
            selected: selected,
            inset: 0
        )
    }

    private func drawTextPopupField(_ value: String, in field: NSRect, compact: Bool) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: field, xRadius: 4, yRadius: 4).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: field, xRadius: 4, yRadius: 4).stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: compact ? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium) : NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
        ]
        let availableWidth = max(0, field.width - 20)
        let clippedValue = clippedLabel(value, attributes: attributes, maxWidth: availableWidth)
        let labelSize = NSString(string: clippedValue).size(withAttributes: attributes)
        NSString(string: clippedValue).draw(
            at: NSPoint(x: field.minX + 7, y: field.midY - labelSize.height / 2),
            withAttributes: attributes
        )
        drawTriangle(in: NSRect(x: field.maxX - 14, y: field.midY - 3, width: 7, height: 5), color: .labelColor)
    }

    private func drawTextDropdownIfNeeded() {
        guard let kind = activeTextDropdown, let menu = textDropdownRect(for: kind) else {
            return
        }

        drawTextDropdownPanel(menu)
        let labels: [String]
        let selectedIndex: Int?
        switch kind {
        case .font:
            let families = SelectionToolbarState.installedTextFontFamilies()
            labels = families.map { SelectionToolbarState.textFontDisplayName(for: $0) }
            selectedIndex = families.firstIndex(of: currentTextFontFamily())
        case .size:
            let sizes = textSizeValuesForActiveTool()
            labels = sizes.map { "\(Int($0.rounded()))" }
            selectedIndex = sizes.firstIndex { Int($0.rounded()) == Int(currentStyle.textSize.rounded()) }
        }

        let startIndex = textDropdownScrollOffset(for: kind)
        let itemRects = textDropdownItemRects(in: menu, kind: kind)
        for (visibleIndex, rect) in itemRects.enumerated() {
            let index = startIndex + visibleIndex
            guard labels.indices.contains(index) else {
                continue
            }
            let selected = index == selectedIndex
            if selected {
                NSColor.systemBlue.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 2), xRadius: 5, yRadius: 5).fill()
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: kind == .size
                    ? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: selected ? .semibold : .medium)
                    : NSFont.systemFont(ofSize: 11, weight: selected ? .semibold : .regular),
                .foregroundColor: selected ? NSColor.systemBlue : NSColor.labelColor,
            ]
            let label = clippedLabel(labels[index], attributes: attributes, maxWidth: rect.width - 12)
            let labelSize = NSString(string: label).size(withAttributes: attributes)
            NSString(string: label).draw(
                at: NSPoint(x: rect.minX + 6, y: rect.midY - labelSize.height / 2),
                withAttributes: attributes
            )
        }

        drawTextDropdownScrollbar(in: menu, kind: kind)
    }

    private func drawTextDropdownPanel(_ rect: NSRect) {
        SelectionToolbarState.textDropdownBackgroundColor.setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        path.fill()
        NSColor.black.withAlphaComponent(0.10).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawTextDropdownScrollbar(in menu: NSRect, kind: TextDropdownKind) {
        let totalCount = textDropdownItemCount(for: kind)
        let visibleCount = textDropdownVisibleItemCount(for: kind)
        guard totalCount > visibleCount else {
            return
        }

        let track = NSRect(x: menu.maxX - 8, y: menu.minY + 6, width: 4, height: menu.height - 12)
        SelectionToolbarState.textDropdownScrollbarTrackColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()

        let thumbHeight = max(18, track.height * CGFloat(visibleCount) / CGFloat(totalCount))
        let maxOffset = max(1, totalCount - visibleCount)
        let progress = CGFloat(textDropdownScrollOffset(for: kind)) / CGFloat(maxOffset)
        let thumbY = track.maxY - thumbHeight - (track.height - thumbHeight) * progress
        let thumb = NSRect(x: track.minX, y: thumbY, width: track.width, height: thumbHeight)
        SelectionToolbarState.textDropdownScrollbarThumbColor.setFill()
        NSBezierPath(roundedRect: thumb, xRadius: 2, yRadius: 2).fill()
    }

    private func clippedLabel(_ value: String, attributes: [NSAttributedString.Key: Any], maxWidth: CGFloat) -> String {
        if NSString(string: value).size(withAttributes: attributes).width <= maxWidth {
            return value
        }
        var label = value
        while label.count > 1 {
            label.removeLast()
            let candidate = label + "..."
            if NSString(string: candidate).size(withAttributes: attributes).width <= maxWidth {
                return candidate
            }
        }
        return "..."
    }

    private func drawColorSwatches(in optionsRect: NSRect) {
        for (index, rect) in colorSwatchRects(in: optionsRect).enumerated() {
            let isCustomSlot = index == visiblePaletteCount
            let color = isCustomSlot ? nil : colors[index]
            let selected: Bool
            if let color {
                selected = !isCustomColorSwatchActive && colorsMatch(color, currentStyle.strokeColor)
            } else {
                selected = isCustomColorSwatchActive
            }
            let fillRect = selected && !isCustomSlot ? rect.insetBy(dx: -3, dy: -3) : rect

            if let color {
                color.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2).fill()
            } else {
                drawCustomColorPaletteIcon(in: fillRect)
            }
            if isCustomSlot {
                continue
            }
            let strokeColor = selected ? NSColor.systemBlue : (isCustomSlot ? NSColor.separatorColor : NSColor.separatorColor)
            strokeColor.setStroke()
            let border = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
            border.lineWidth = selected ? 1.5 : 1
            border.stroke()
        }
    }

    private func drawMosaicModeControls(in optionsRect: NSRect) {
        let strokeWidths = SelectionToolbarState.strokeWidthValues(for: .mosaic)
        for (index, rect) in SelectionToolbarState.strokeWidthRects(in: optionsRect).enumerated() {
            let width = strokeWidths[index]
            let isSelected = currentShapeKind == .mosaicStroke && currentStyle.strokeWidth == width
            drawToolbarButton(optionButtonBackgroundRect(for: rect), symbol: nil, selected: isSelected, enabled: true)
            let diameter = SelectionToolbarState.mosaicPreviewDotDiameter(for: width)
            (isSelected ? NSColor.controlAccentColor : NSColor.labelColor).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)).fill()
        }

        let rectangleRect = optionsToolbarLayout(in: optionsRect).rectangleMode ?? .zero
        drawToolbarButton(optionButtonBackgroundRect(for: rectangleRect), symbol: nil, selected: currentShapeKind == .mosaicRectangle, enabled: true)
        drawMosaicRectangleGlyph(in: rectangleRect, selected: currentShapeKind == .mosaicRectangle)

        let redactionTypeRect = SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsRect)
        drawToolbarButton(optionButtonBackgroundRect(for: redactionTypeRect), symbol: nil, selected: true, enabled: true)
        if mosaicRedactionType == .gaussianBlur {
            drawMosaicGaussianGlyph(
                in: redactionTypeRect.insetBy(dx: 2, dy: 2),
                value: mosaicPreviewValue(for: .gaussianBlur),
                selected: true
            )
        } else {
            drawMosaicPixelGlyph(
                in: redactionTypeRect.insetBy(dx: 2, dy: 2),
                value: mosaicPreviewValue(for: .pixelMosaic),
                selected: true
            )
        }

        let valueRect = SelectionToolbarState.mosaicRedactionValueRect(in: optionsRect)
        drawToolbarButton(valueRect, symbol: nil, selected: false, enabled: true)
        drawMosaicValueControl(in: valueRect)
    }

    private func mosaicShapeGlyphColor(selected: Bool = false) -> NSColor {
        selected ? NSColor.systemBlue : NSColor.labelColor
    }

    private func drawMosaicCircleModeGlyph(in rect: NSRect) {
        mosaicShapeGlyphColor().setFill()
        let side: CGFloat = 15
        NSBezierPath(ovalIn: NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)).fill()
    }

    private func drawMosaicGaussianGlyph(in rect: NSRect, value: Int, selected: Bool = false) {
        let progress = SelectionToolbarState.mosaicPreviewProgress(for: value)
        let circleRect = rect.insetBy(dx: 1, dy: 1)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let baseDiameter: CGFloat = 7.5 + progress * 3
        let blurExpansion: CGFloat = 2.5 + progress * 3
        let glyphColor = selected ? NSColor.systemBlue : NSColor(calibratedWhite: 0.30, alpha: 0.82)

        SelectionToolbarState.mosaicPreviewBackgroundColor(for: value).setFill()
        let circlePath = NSBezierPath(ovalIn: circleRect)
        circlePath.fill()

        (selected ? NSColor.systemBlue : NSColor(calibratedWhite: 0.42, alpha: 1)).setStroke()
        circlePath.lineWidth = 1.4
        circlePath.stroke()

        (selected ? glyphColor.withAlphaComponent(0.16 + progress * 0.14) : NSColor(calibratedWhite: 0.38, alpha: 0.18 + progress * 0.18)).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - (baseDiameter + blurExpansion) / 2,
                y: center.y - (baseDiameter + blurExpansion) / 2,
                width: baseDiameter + blurExpansion,
                height: baseDiameter + blurExpansion
            )
        ).fill()

        (selected ? glyphColor.withAlphaComponent(0.28 + progress * 0.18) : NSColor(calibratedWhite: 0.34, alpha: 0.32 + progress * 0.22)).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - (baseDiameter + blurExpansion * 0.55) / 2,
                y: center.y - (baseDiameter + blurExpansion * 0.55) / 2,
                width: baseDiameter + blurExpansion * 0.55,
                height: baseDiameter + blurExpansion * 0.55
            )
        ).fill()

        glyphColor.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - baseDiameter / 2,
                y: center.y - baseDiameter / 2,
                width: baseDiameter,
                height: baseDiameter
            )
        ).fill()
    }

    private func drawMosaicPixelGlyph(in rect: NSRect, value: Int, selected: Bool = false) {
        let progress = SelectionToolbarState.mosaicPreviewProgress(for: value)
        let size: CGFloat = 4.8 + progress * 2.4
        let spacing: CGFloat = 5.8 + progress * 2.4
        let centers = [
            NSPoint(x: rect.midX, y: rect.midY),
            NSPoint(x: rect.midX, y: rect.midY + spacing),
            NSPoint(x: rect.midX, y: rect.midY - spacing),
            NSPoint(x: rect.midX - spacing, y: rect.midY),
            NSPoint(x: rect.midX + spacing, y: rect.midY),
        ]
        let colors = selected
            ? [
                NSColor.white.withAlphaComponent(0.94),
                NSColor.systemBlue.withAlphaComponent(0.82),
                NSColor.systemBlue.withAlphaComponent(0.82),
                NSColor.systemBlue.withAlphaComponent(0.82),
                NSColor.systemBlue.withAlphaComponent(0.82),
            ]
            : [
                NSColor.white.withAlphaComponent(0.94),
                NSColor(calibratedWhite: 0.28, alpha: 0.94),
                NSColor(calibratedWhite: 0.28, alpha: 0.94),
                NSColor(calibratedWhite: 0.28, alpha: 0.94),
                NSColor(calibratedWhite: 0.28, alpha: 0.94),
            ]
        for (index, center) in centers.enumerated() {
            colors[index].setFill()
            NSBezierPath(
                roundedRect: NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
                xRadius: 1.2,
                yRadius: 1.2
            ).fill()
        }
    }

    private func drawMosaicRectangleGlyph(in rect: NSRect, selected: Bool = false) {
        if let image = mosaicRectangleIcon(selected: selected) {
            image.draw(in: rect)
            return
        }

        mosaicShapeGlyphColor(selected: selected).setFill()
        let side: CGFloat = 15
        NSBezierPath(roundedRect: NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side), xRadius: 1.5, yRadius: 1.5).fill()
    }

    private func mosaicRectangleIcon(selected: Bool) -> NSImage? {
        let replacementColor = selected ? svgHexColor(for: NSColor.systemBlue) : "#000000"
        if let cached = mosaicRectangleIconCache[replacementColor] {
            return cached
        }

        guard
            let url = Bundle.main.url(forResource: "square_masaike", withExtension: "svg"),
            let data = try? Data(contentsOf: url),
            var svg = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        svg = svg.replacingOccurrences(of: "fill=\"#000000\"", with: "fill=\"\(replacementColor)\"")
        guard let imageData = svg.data(using: .utf8),
              let image = NSImage(data: imageData) else {
            return nil
        }
        mosaicRectangleIconCache[replacementColor] = image
        return image
    }

    private func svgHexColor(for color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? color
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }

    private func mosaicPreviewValue(for type: CaptureMosaicRedactionType) -> Int {
        mosaicRedactionValues[type] ?? SelectionToolbarState.mosaicDefaultRedactionValue(for: type)
    }

    private func drawMosaicValueControl(in rect: NSRect) {
        let value = mosaicRedactionValues[mosaicRedactionType] ?? SelectionToolbarState.mosaicDefaultRedactionValue(for: mosaicRedactionType)
        let track = mosaicValueSliderTrackRect(in: rect)
        let valueRect = mosaicValueSliderLabelRect(in: rect)
        let progress = CGFloat(value - 5) / 15
        let thumbCenterX = track.minX + track.width * min(1, max(0, progress))

        NSColor.separatorColor.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()

        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: max(0, thumbCenterX - track.minX), height: track.height), xRadius: 2, yRadius: 2).fill()

        NSColor.controlBackgroundColor.setFill()
        let thumbRect = NSRect(x: thumbCenterX - 6, y: rect.midY - 7, width: 12, height: 14)
        NSBezierPath(roundedRect: thumbRect, xRadius: 2, yRadius: 2).fill()
        NSColor.controlAccentColor.setStroke()
        let thumbBorder = NSBezierPath(roundedRect: thumbRect, xRadius: 2, yRadius: 2)
        thumbBorder.lineWidth = 1.6
        thumbBorder.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let displayText = "\(value)"
        let textSize = NSString(string: displayText).size(withAttributes: attributes)
        NSString(string: displayText).draw(
            in: NSRect(x: valueRect.midX - textSize.width / 2, y: valueRect.minY + 4, width: textSize.width, height: 12),
            withAttributes: attributes
        )
    }

    private func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let left = opaqueColor(lhs)
        let right = opaqueColor(rhs)
        return abs(left.redComponent - right.redComponent) < 0.001
            && abs(left.greenComponent - right.greenComponent) < 0.001
            && abs(left.blueComponent - right.blueComponent) < 0.001
    }

    private func drawCustomColorPaletteIcon(in rect: NSRect) {
        drawToolbarImage(named: "palette-tool", in: rect, template: false, enabled: true, inset: 0)
    }

    private func drawPanel(_ rect: NSRect, opaque: Bool = false, alpha: CGFloat? = nil) {
        let fillAlpha = alpha ?? (opaque ? 1 : 0.96)
        NSColor.windowBackgroundColor.withAlphaComponent(fillAlpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        border.lineWidth = 1
        border.stroke()
    }

    private func copySampledColorToPasteboard() -> Bool {
        guard let color = sampledColor ?? sampledPointerPoint.flatMap(sampleCurrentColor(at:)) else {
            return false
        }

        sampledColor = color
        if let sampledPointerPoint {
            logColorSamplerDebug(at: sampledPointerPoint, color: color)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(colorSamplerDisplayValue(for: color), forType: .string)
        showColorSamplerCopySuccess()
        return true
    }

    private func showColorSamplerCopySuccess() {
        colorSamplerCopySuccessTimer?.invalidate()
        colorSamplerCopySuccessUntil = Date(timeIntervalSinceNow: SelectionToolbarState.colorSamplerCopySuccessDuration)
        needsDisplay = true

        colorSamplerCopySuccessTimer = Timer.scheduledTimer(withTimeInterval: SelectionToolbarState.colorSamplerCopySuccessDuration, repeats: false) { [weak self] _ in
            self?.colorSamplerCopySuccessUntil = nil
            self?.colorSamplerCopySuccessTimer = nil
            self?.needsDisplay = true
        }
        if let colorSamplerCopySuccessTimer {
            RunLoop.main.add(colorSamplerCopySuccessTimer, forMode: .common)
        }
    }

    private func hexString(for color: NSColor) -> String {
        SelectionToolbarState.colorSamplerHexString(for: color)
    }

    private func sampleColor(at point: NSPoint) -> NSColor? {
        guard let backgroundBitmap else {
            return nil
        }

        let pixel = bitmapPixelPoint(for: point, in: backgroundBitmap)
        return sampleColor(atPixelX: pixel.x, y: pixel.y, in: backgroundBitmap)
    }

    private func shouldUseLightCursor(at point: NSPoint) -> Bool {
        guard let selectionRect = cursorSelectionRect?.standardized else {
            return false
        }

        let hitRect = selectionRect.insetBy(dx: -16, dy: -16)
        guard hitRect.contains(point) else {
            return false
        }

        return selectionPrefersLightCursor(selectionRect)
    }

    private func selectionPrefersLightCursor(_ rect: NSRect?) -> Bool {
        guard let rect,
              let luminance = averageBackgroundLuminance(in: rect.standardized)
        else {
            return false
        }
        return luminance < 0.5
    }

    private func averageBackgroundLuminance(in rect: NSRect) -> CGFloat? {
        guard backgroundBitmap != nil else {
            return nil
        }

        let imageSize = backgroundImage?.size ?? bounds.size
        let imageRect = NSRect(origin: .zero, size: imageSize)
        let sampleRect = rect.standardized.intersection(imageRect)
        guard sampleRect.width > 0, sampleRect.height > 0 else {
            return nil
        }
        let cacheKey = backgroundLuminanceCacheKey(for: sampleRect)
        if let cached = backgroundLuminanceCache[cacheKey] {
            return cached
        }

        let maxSamplesPerAxis = 24
        let columns = max(1, min(maxSamplesPerAxis, Int(ceil(sampleRect.width))))
        let rows = max(1, min(maxSamplesPerAxis, Int(ceil(sampleRect.height))))
        var total: CGFloat = 0
        var count: CGFloat = 0

        for row in 0..<rows {
            for column in 0..<columns {
                let point = NSPoint(
                    x: sampleRect.minX + (CGFloat(column) + 0.5) * sampleRect.width / CGFloat(columns),
                    y: sampleRect.minY + (CGFloat(row) + 0.5) * sampleRect.height / CGFloat(rows)
                )
                guard let color = sampleColor(at: point) else {
                    continue
                }
                total += perceivedLuminance(of: color)
                count += 1
            }
        }

        guard count > 0 else {
            return nil
        }
        let luminance = total / count
        backgroundLuminanceCache[cacheKey] = luminance
        return luminance
    }

    private func backgroundLuminanceCacheKey(for rect: NSRect) -> String {
        [
            Int(rect.minX.rounded(.down)),
            Int(rect.minY.rounded(.down)),
            Int(rect.width.rounded(.up)),
            Int(rect.height.rounded(.up)),
        ].map(String.init).joined(separator: ":")
    }

    private func perceivedLuminance(of color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }

    private func sampleCurrentColor(at point: NSPoint) -> NSColor? {
        if isEyedropperToolActive {
            return sampleVisibleSelectionColor(at: point)
        }
        return sampleColor(at: point)
    }

    private func magnifierSampleColor(at point: NSPoint) -> NSColor? {
        sampleCurrentColor(at: point)
    }

    private func magnifierSampleColor(centeredAt point: NSPoint, columnOffset: Int, rowOffset: Int) -> NSColor? {
        let samplePoint = magnifierSamplePoint(
            centeredAt: point,
            columnOffset: columnOffset,
            rowOffset: rowOffset
        )
        return sampleCurrentColor(at: samplePoint)
    }

    private func magnifierSampleColor(
        centeredAt point: NSPoint,
        columnOffset: Int,
        rowOffset: Int,
        source: ColorSamplerPixelSource?
    ) -> NSColor? {
        let samplePoint = magnifierSamplePoint(
            centeredAt: point,
            columnOffset: columnOffset,
            rowOffset: rowOffset
        )
        if isEyedropperToolActive, let markerColor = visibleDarkMarkerLineColor(at: samplePoint) {
            return markerColor
        }
        guard let source else {
            return sampleCurrentColor(at: samplePoint)
        }
        let pixel = bitmapPixelPoint(
            for: samplePoint,
            imageSize: source.imageSize,
            pixelsWide: source.bitmap?.pixelsWide ?? source.cgImage?.width ?? 1,
            pixelsHigh: source.bitmap?.pixelsHigh ?? source.cgImage?.height ?? 1
        )
        if let bitmap = source.bitmap {
            return sampleColor(atPixelX: pixel.x, y: pixel.y, in: bitmap)
        }
        if let cgImage = source.cgImage {
            return SelectionToolbarState.sampleColor(atPixelX: pixel.x, y: pixel.y, in: cgImage)
        }
        return nil
    }

    private func colorSamplerPixelSource() -> ColorSamplerPixelSource? {
        if isEyedropperToolActive,
           let composite = visibleSelectionCompositeForSampling(),
           let cgImage = composite.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return ColorSamplerPixelSource(imageSize: composite.image.size, bitmap: nil, cgImage: cgImage)
        }
        guard let backgroundBitmap else {
            return nil
        }
        return ColorSamplerPixelSource(
            imageSize: backgroundImage?.size ?? bounds.size,
            bitmap: backgroundBitmap,
            cgImage: nil
        )
    }

    private func magnifierSamplePoint(centeredAt point: NSPoint, columnOffset: Int, rowOffset: Int) -> NSPoint {
        let step = magnifierPointStep()
        return NSPoint(
            x: point.x + CGFloat(columnOffset) * step.width,
            y: point.y - CGFloat(rowOffset) * step.height
        )
    }

    private func magnifierPointStep() -> NSSize {
        if let backgroundImage, let cgImage = backgroundImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return NSSize(
                width: backgroundImage.size.width / CGFloat(max(cgImage.width, 1)),
                height: backgroundImage.size.height / CGFloat(max(cgImage.height, 1))
            )
        }
        if let backgroundBitmap {
            let imageSize = backgroundImage?.size ?? bounds.size
            return NSSize(
                width: imageSize.width / CGFloat(max(backgroundBitmap.pixelsWide, 1)),
                height: imageSize.height / CGFloat(max(backgroundBitmap.pixelsHigh, 1))
            )
        }
        return NSSize(width: 1, height: 1)
    }

    private func sampleVisibleSelectionColor(at point: NSPoint) -> NSColor? {
        guard
            let selectionRect = lockedSelectionRect?.standardized,
            selectionRect.contains(point)
        else {
            return nil
        }

        if let markerColor = visibleDarkMarkerLineColor(at: point) {
            return markerColor
        }

        guard let composite = visibleSelectionCompositeForSampling() else {
            return sampleColor(at: point)
        }

        return sampleColor(at: point, in: composite.image)
    }

    private func visibleSelectionCompositeForSampling() -> (image: NSImage, drawRect: NSRect)? {
#if DEBUG
        visibleSelectionCompositeLookupCountForTesting += 1
#endif
        return fullMosaicPreviewComposite(for: annotations)
    }

    private func visibleDarkMarkerLineColor(at point: NSPoint) -> NSColor? {
        for annotation in annotations.reversed() where annotation.kind == .marker {
            guard let markerLine = overlayMarkerLine(fromLocalMarkerLine: annotation.markerLine) else {
                continue
            }
            let hitOutset = max(1, annotation.style.strokeWidth / 2 + 1)
            guard SelectionToolbarState.markerLineContains(point: point, line: markerLine, hitOutset: hitOutset) else {
                continue
            }
            guard markerLinePrefersNormalBlend(markerLine) else {
                return nil
            }
            return visibleMarkerColor(annotation.style.strokeColor, onDarkBackground: true)
        }
        return nil
    }

    private func sampleColor(at point: NSPoint, in image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let pixel = bitmapPixelPoint(
            for: point,
            imageSize: image.size,
            pixelsWide: cgImage.width,
            pixelsHigh: cgImage.height
        )
        return SelectionToolbarState.sampleColor(atPixelX: pixel.x, y: pixel.y, in: cgImage)
    }

    private func logColorSamplerDebug(at point: NSPoint, color: NSColor) {
        guard let backgroundBitmap else {
            return
        }

        let pixel = bitmapPixelPoint(for: point, in: backgroundBitmap)
        NSLog(
            "xxsnap color sampler %@",
            SelectionToolbarState.colorSamplerDebugDescription(
                atPixelX: pixel.x,
                y: pixel.y,
                in: backgroundBitmap,
                color: color
            )
        )
    }

    private func bitmapPixelPoint(for point: NSPoint, in bitmap: NSBitmapImageRep) -> (x: Int, y: Int) {
        bitmapPixelPoint(
            for: point,
            imageSize: backgroundImage?.size ?? bounds.size,
            pixelsWide: bitmap.pixelsWide,
            pixelsHigh: bitmap.pixelsHigh
        )
    }

    private func bitmapPixelPoint(
        for point: NSPoint,
        imageSize: NSSize,
        pixelsWide: Int,
        pixelsHigh: Int
    ) -> (x: Int, y: Int) {
        let scaleX = CGFloat(pixelsWide) / max(imageSize.width, 1)
        let scaleY = CGFloat(pixelsHigh) / max(imageSize.height, 1)
        let x = max(0, min(pixelsWide - 1, Int(point.x * scaleX)))
        let y = max(0, min(pixelsHigh - 1, Int((imageSize.height - point.y) * scaleY)))
        return (x, y)
    }

    private func sampleColor(atPixelX x: Int, y: Int, in bitmap: NSBitmapImageRep) -> NSColor? {
        SelectionToolbarState.sampleColor(atPixelX: x, y: y, in: bitmap)
    }

    private func rgbString(for color: NSColor) -> String {
        SelectionToolbarState.colorSamplerRgbString(for: color)
    }

    private func drawToolbarButton(_ rect: NSRect, symbol: String?, selected: Bool, enabled: Bool) {
        (selected ? NSColor.controlAccentColor.withAlphaComponent(SelectionToolbarState.toolbarSelectedBackgroundAlpha) : NSColor.clear).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()

        guard let symbol else {
            return
        }

        drawToolbarIcon(named: symbol, in: rect, enabled: enabled, selected: selected)
    }

    private func drawToolbarIcon(named name: String, in rect: NSRect, enabled: Bool, selected: Bool) {
        let color: NSColor
        if name == "toolbar-scroll-screen2", enabled, !selected {
            color = .black
        } else {
            color = toolbarIconColor(enabled: enabled, selected: selected)
        }
        color.set()

        let resourceName = name.replacingOccurrences(of: "toolbar-", with: "")
        let imageInset = toolbarIconInset(for: resourceName)
        let usesFixedColorResource = SelectionToolbarState.usesFixedColorToolbarIconResource(resourceName)
        if drawToolbarImage(named: resourceName, in: rect, template: !usesFixedColorResource, enabled: enabled, selected: selected, inset: imageInset, tintColor: color)
            || drawToolbarImage(named: name, in: rect, template: !usesFixedColorResource, enabled: enabled, selected: selected, inset: imageInset, tintColor: color) {
            return
        }

        let systemPointSize: CGFloat = name == "toolbar-text-tool" ? 15 : 13
        let systemInset: CGFloat = name == "toolbar-text-tool" ? 0 : 4
        let configuration = NSImage.SymbolConfiguration(pointSize: systemPointSize, weight: .medium)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            image.isTemplate = true
            image.draw(in: rect.insetBy(dx: systemInset, dy: systemInset))
        }
    }

    private func toolbarIconInset(for resourceName: String) -> CGFloat {
        SelectionToolbarState.toolbarIconInset(for: resourceName)
    }

    @discardableResult
    private func drawToolbarImage(
        named name: String,
        in rect: NSRect,
        template: Bool,
        enabled: Bool,
        selected: Bool = false,
        inset: CGFloat = 3,
        tintColor: NSColor? = nil
    ) -> Bool {
        let resource = NSImage(named: name)
            ?? Bundle.main.url(forResource: name, withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? Bundle.main.url(forResource: name, withExtension: "png").flatMap(NSImage.init(contentsOf:))
        if let image = resource {
            image.isTemplate = template
            let targetRect = rect.insetBy(dx: inset, dy: inset)
            if template {
                drawTintedToolbarImage(
                    image,
                    in: targetRect,
                    color: tintColor ?? toolbarIconColor(enabled: enabled, selected: selected)
                )
            } else {
                image.draw(in: targetRect)
            }
            return true
        }

        return false
    }

    private func drawTintedToolbarImage(_ image: NSImage, in rect: NSRect, color: NSColor) {
        let imageSize = image.size.width > 0 && image.size.height > 0 ? image.size : rect.size
        let imageRect = NSRect(origin: .zero, size: imageSize)
        let tintedImage = NSImage(size: imageSize)
        tintedImage.lockFocus()
        color.setFill()
        imageRect.fill()
        image.draw(in: imageRect, from: imageRect, operation: .destinationIn, fraction: 1)
        tintedImage.unlockFocus()
        tintedImage.draw(in: rect)
    }

    private func toolbarIconColor(enabled: Bool, selected: Bool) -> NSColor {
        if !enabled {
            return .disabledControlTextColor
        }
        return selected ? .systemBlue : .labelColor
    }

    private func drawShapeToolButton(_ rect: NSRect, selected: Bool, enabled: Bool) {
        drawToolbarButton(rect, symbol: nil, selected: selected, enabled: enabled)

        let color = enabled ? NSColor.labelColor : NSColor.disabledControlTextColor
        color.setStroke()
        let circleSize: CGFloat = 12
        let circle = NSRect(x: rect.minX + 8, y: rect.minY + 5, width: circleSize, height: circleSize)
        let rectangle = NSRect(x: rect.minX + 2, y: rect.minY + 5, width: circleSize, height: circleSize)

        let rectanglePath = NSBezierPath()
        rectanglePath.move(to: NSPoint(x: rectangle.minX, y: rectangle.maxY))
        rectanglePath.line(to: NSPoint(x: circle.minX + 2, y: rectangle.maxY))
        rectanglePath.move(to: NSPoint(x: rectangle.minX, y: rectangle.maxY))
        rectanglePath.line(to: NSPoint(x: rectangle.minX, y: rectangle.minY))
        rectanglePath.line(to: NSPoint(x: rectangle.maxX, y: rectangle.minY))
        rectanglePath.line(to: NSPoint(x: rectangle.maxX, y: circle.minY + 2))
        rectanglePath.lineWidth = 1.5
        rectanglePath.stroke()

        color.setStroke()
        let circlePath = NSBezierPath(ovalIn: circle)
        circlePath.lineWidth = 1.5
        circlePath.stroke()
    }

    private func drawTriangle(in rect: NSRect, color: NSColor, pointsUp: Bool = false) {
        color.setFill()
        let path = NSBezierPath()
        if pointsUp {
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.line(to: NSPoint(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.midX, y: rect.minY))
        }
        path.close()
        path.fill()
    }

    private func drawDisclosureCorner(in rect: NSRect, enabled: Bool) {
        let size: CGFloat = 6
        (enabled ? NSColor.black : NSColor.disabledControlTextColor).setFill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - size, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + size))
        path.close()
        path.fill()
    }

    private func drawSlider(track: NSRect, value: CGFloat, maximum: CGFloat) {
        NSColor.separatorColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()

        let ratio = min(1, max(0, value / max(1, maximum)))
        let thumbX = track.minX + ratio * track.width
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: thumbX - 7, y: track.midY - 7, width: 14, height: 14)).fill()
    }

    private func drawCornerRadiusValue(_ valueRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        NSBezierPath(roundedRect: valueRect, xRadius: 4, yRadius: 4).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: valueRect, xRadius: 4, yRadius: 4).stroke()

        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        NSString(string: "\(Int(currentStyle.cornerRadius))").draw(
            in: NSRect(x: valueRect.minX + 6, y: valueRect.minY + 5, width: 24, height: 14),
            withAttributes: valueAttributes
        )

        drawValueArrow(in: cornerRadiusUpRect(in: valueRect), up: true, enabled: currentStyle.cornerRadius < 30)
        drawValueArrow(in: cornerRadiusDownRect(in: valueRect), up: false, enabled: currentStyle.cornerRadius > 0)
    }

    private func drawValueArrow(in rect: NSRect, up: Bool, enabled: Bool) {
        (enabled ? NSColor.secondaryLabelColor : NSColor.disabledControlTextColor).setFill()
        let inset = rect.insetBy(dx: 5, dy: 3)
        let path = NSBezierPath()
        if up {
            path.move(to: NSPoint(x: inset.midX, y: inset.maxY))
            path.line(to: NSPoint(x: inset.minX, y: inset.minY))
            path.line(to: NSPoint(x: inset.maxX, y: inset.minY))
        } else {
            path.move(to: NSPoint(x: inset.minX, y: inset.maxY))
            path.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
            path.line(to: NSPoint(x: inset.midX, y: inset.minY))
        }
        path.close()
        path.fill()
    }

    private func toolbarButton(at point: NSPoint) -> ToolbarButton? {
        guard let selectionRect, let toolbar = mainToolbarRect(for: selectionRect) else {
            return nil
        }

        return toolbarButtonRects(in: toolbar)
            .first(where: { $0.1.contains(point) })?
            .0
    }

    private func isMainToolbarDragPoint(_ point: NSPoint) -> Bool {
        guard
            let selectionRect,
            let toolbar = mainToolbarRect(for: selectionRect),
            toolbar.contains(point)
        else {
            return false
        }

        if mainToolbarLeadingDragHandleRect(in: toolbar).contains(point)
            || mainToolbarDragHandleRect(in: toolbar).contains(point) {
            return true
        }

        return toolbarButtonRects(in: toolbar)
            .allSatisfy { !$0.1.insetBy(dx: -2, dy: -2).contains(point) }
    }

    private func mainToolbarDragHandleRect(in toolbar: NSRect) -> NSRect {
        var x = toolbar.minX + mainToolbarHorizontalPadding + mainToolbarButtonStep
        for button in mainToolbarButtons() {
            x += mainToolbarButtonStep + mainToolbarExtraGap(after: button)
        }
        return NSRect(x: x, y: toolbar.minY + 4, width: 20, height: 20)
    }

    private func mainToolbarLeadingDragHandleRect(in toolbar: NSRect) -> NSRect {
        NSRect(x: toolbar.minX + mainToolbarHorizontalPadding, y: toolbar.minY + 4, width: 20, height: 20)
    }

    private func toolbarButtonRects(in toolbar: NSRect) -> [(ToolbarButton, NSRect)] {
        var x = toolbar.minX + mainToolbarHorizontalPadding + mainToolbarButtonStep
        return mainToolbarButtons().map { button in
            let rect = NSRect(x: x, y: toolbar.minY + 4, width: 20, height: 20)
            x += mainToolbarButtonStep + mainToolbarExtraGap(after: button)
            return (button, rect)
        }
    }

    private func mainToolbarButtons() -> [ToolbarButton] {
        var buttons: [ToolbarButton] = [
            .rectangle,
            .polyline,
            .pen,
            .marker,
            .eyedropper,
            .mosaic,
            .text,
            .number,
            .magnifier,
            .eraser,
        ]
        if featureGate.isEnabled(.scrollCapture) {
            buttons.append(.scroll)
        }
        buttons.append(contentsOf: [
            .undo,
            .redo,
            .cancel,
            .pin,
            .save,
            .copy,
        ])
        buttons = buttons.filter { !isMainToolbarButtonHidden($0) }
        if configuration.showsFinishEditingButton {
            buttons.append(.finishEditing)
        }
        return buttons
    }

    private func isMainToolbarButtonHidden(_ button: ToolbarButton) -> Bool {
        switch button {
        case .scroll:
            return configuration.hiddenMainToolbarButtons.contains(.scroll)
        case .cancel:
            return configuration.hiddenMainToolbarButtons.contains(.cancel)
        case .pin:
            return configuration.hiddenMainToolbarButtons.contains(.pin)
        default:
            return false
        }
    }

    private func mainToolbarExtraGap(after button: ToolbarButton) -> CGFloat {
        switch button {
        case .eraser, .scroll, .redo:
            return 8
        default:
            return 0
        }
    }

    private func mainToolbarWidth() -> CGFloat {
        return mainToolbarHorizontalPadding + mainToolbarButtonStep + mainToolbarButtons().reduce(CGFloat(0)) { width, button in
            width + mainToolbarButtonStep + mainToolbarExtraGap(after: button)
        } + mainToolbarButtonStep
    }

    private func symbolName(for button: ToolbarButton, enabled: Bool = true) -> String {
        switch button {
        case .rectangle:
            return "toolbar-screenshot"
        case .polyline:
            return "toolbar-arrow"
        case .pen:
            return "toolbar-pencil-tool"
        case .marker:
            return "toolbar-highlighter-tool"
        case .eyedropper:
            return "toolbar-straw-ranging"
        case .mosaic:
            return "toolbar-masaike2"
        case .text:
            return "toolbar-text-tool"
        case .number:
            return "toolbar-number-sequence"
        case .magnifier:
            return "toolbar-zoom-in-tool"
        case .eraser:
            return "toolbar-eraser-tool"
        case .undo:
            return enabled ? "toolbar-undo-enabled" : "toolbar-undo-disabled"
        case .redo:
            return enabled ? "toolbar-redo-enabled" : "toolbar-redo-disabled"
        case .copy:
            return "toolbar-copy-to-clipboard"
        case .save:
            return "toolbar-save-to-file"
        case .cancel:
            return "toolbar-cancel-capture"
        case .pin:
            return "toolbar-pin-to-screen"
        case .scroll:
            return "toolbar-scroll-screen2"
        case .finishEditing:
            return "checkmark"
        }
    }

    private func buttonMatchesCurrentTool(_ button: ToolbarButton) -> Bool {
        if button == .scroll, scrollCaptureOverlayState != .inactive {
            return true
        }
        switch button {
        case .rectangle:
            return isShapeToolActive && (currentShapeKind == .rectangle || currentShapeKind == .ellipse)
        case .polyline:
            return isShapeToolActive && currentShapeKind == .arrowLine
        case .pen:
            return isShapeToolActive && currentShapeKind == .brush
        case .marker:
            return isShapeToolActive && currentShapeKind == .marker
        case .eyedropper:
            return isEyedropperToolActive
        case .mosaic:
            return isShapeToolActive && (currentShapeKind == .mosaicStroke || currentShapeKind == .mosaicRectangle)
        case .text:
            return isTextToolActive
        case .number:
            return isNumberToolActive
        case .magnifier:
            return isMagnifierToolActive
        case .finishEditing:
            return false
        case .eraser:
            return isEraserToolActive
        default:
            return false
        }
    }

    private func mainToolbarRect(for selectionRect: NSRect) -> NSRect? {
        guard let base = baseMainToolbarRect(for: selectionRect) else {
            return nil
        }

        return SelectionToolbarState.draggedToolbarRect(
            baseRect: base,
            offset: mainToolbarOffset,
            inside: mainToolbarLayoutBounds(for: selectionRect)
        )
    }

    var scrollCaptureToolbarFrame: NSRect? {
        guard let selectionRect else { return nil }
        return mainToolbarRect(for: selectionRect)
    }

    var scrollCaptureControlGeometry: ScrollCaptureControlGeometry? {
        guard let selectionRect,
              let toolbarFrame = mainToolbarRect(for: selectionRect) else { return nil }
        let frames = Dictionary(uniqueKeysWithValues: toolbarButtonRects(in: toolbarFrame))
        guard let finishButtonFrame = frames[.scroll],
              let cancelButtonFrame = frames[.cancel] else { return nil }
        return ScrollCaptureControlGeometry(
            toolbarFrame: toolbarFrame,
            finishButtonFrame: finishButtonFrame,
            cancelButtonFrame: cancelButtonFrame
        )
    }

    func beginScrollCapture() {
        guard scrollCaptureOverlayState == .inactive,
              let lockedSelectionRect,
              let window,
              let backgroundImage else { return }
        commitCurrentTextEdit()
        commitNumberEditingIfNeeded()
        let snapshotRect = lockedSelectionRect.standardized
        guard let crop = pixelAlignedCrop(image: backgroundImage, to: snapshotRect) else { return }
        closeTextDropdown()
        closeMagnifierZoomDropdown()
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        activeNumberDropdown = false
        scrollCaptureOverlayState = .capturing
        scrollCaptureDidRequest?(ScrollCaptureSeed(
            screenRect: window.convertToScreen(crop.drawRect).standardized,
            snapshotRect: snapshotRect,
            frozenImage: crop.image,
            annotations: annotations,
            eraserMasks: eraserMasks
        ))
    }

    func endScrollCapturePassiveMode() {
        scrollCaptureOverlayState = .inactive
        invalidateCursorRectsAndRefresh()
        needsDisplay = true
    }

    private func baseMainToolbarRect(for selectionRect: NSRect) -> NSRect? {
        let visibleSelectionRect = selectionRect.intersection(safeLayoutBounds)
        let anchor = visibleSelectionRect.isNull || visibleSelectionRect.isEmpty ? selectionRect : visibleSelectionRect
        let layoutBounds = mainToolbarLayoutBounds(for: selectionRect)
        return SelectionToolbarState.toolbarRect(
            size: NSSize(width: mainToolbarWidth(), height: 28),
            anchoredTo: anchor,
            inside: layoutBounds,
            allowsInsidePlacement: isFullScreenSelection(selectionRect)
        )
    }

    private func mainToolbarLayoutBounds(for selectionRect: NSRect) -> NSRect {
        isFullScreenSelection(selectionRect) ? safeLayoutBounds : screenBounds(containing: selectionRect)
    }

    private func isFullScreenSelection(_ selectionRect: NSRect) -> Bool {
        SelectionToolbarState.isFullScreenSelection(selectionRect, in: screenBounds(containing: selectionRect))
    }

    private func isToolbarOrPanelPoint(_ point: NSPoint) -> Bool {
        if let selectionRect, let toolbar = mainToolbarRect(for: selectionRect), toolbar.contains(point) {
            return true
        }

        if let lockedSelectionRect,
           measurementControlLayout(for: lockedSelectionRect).panel.contains(point) {
            return true
        }

        if let optionsToolbarRect, optionsToolbarRect.contains(point) {
            return true
        }

        if let activeTextDropdown, let menu = textDropdownRect(for: activeTextDropdown), menu.contains(point) {
            return true
        }

        if activeNumberDropdown,
           let optionsToolbarRect,
           numberMarkTypeMenuRect(in: optionsToolbarRect).contains(point) {
            return true
        }

        if activeMagnifierZoomDropdown,
           let optionsToolbarRect,
           magnifierZoomMenuRect(in: optionsToolbarRect).contains(point) {
            return true
        }

        if showsCornerRadiusPanel, let cornerRadiusPanelRect, cornerRadiusPanelRect.contains(point) {
            return true
        }

        if showsStrokeStyleMenu,
           SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode),
           let optionsToolbarRect,
           strokeStyleMenuRect(in: optionsToolbarRect).contains(point) {
            return true
        }

        if showsStartArrowTypeMenu, let optionsToolbarRect, arrowTypeMenuRect(in: optionsToolbarRect, field: .start).contains(point) {
            return true
        }

        if showsEndArrowTypeMenu, let optionsToolbarRect, arrowTypeMenuRect(in: optionsToolbarRect, field: .end).contains(point) {
            return true
        }

        return false
    }

    private var optionsToolbarMode: SelectionToolbarState.OptionsToolbarMode {
        if isEraserToolActive {
            return .eraser
        }

        if isTextToolActive {
            return .text
        }

        if isNumberToolActive {
            return .numberSequence
        }

        if isMagnifierToolActive {
            return .magnifier
        }

        switch currentShapeKind {
        case .arrowLine:
            return .arrowLine
        case .brush:
            return .brush
        case .marker:
            return .marker
        case .mosaicStroke, .mosaicRectangle:
            return .mosaic
        case .magnifier:
            return .magnifier
        case .rectangle, .ellipse, .text, .numberSequence:
            return .shape
        }
    }

    private func optionsToolbarLayout(in optionsRect: NSRect) -> SelectionToolbarState.OptionsToolbarLayout {
        SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: visiblePaletteCount,
            mode: optionsToolbarMode
        )
    }

    private var optionsToolbarRect: NSRect? {
        guard
            SelectionToolbarState.shouldShowOptionsToolbar(isPrimaryShapeToolActive: isShapeToolActive || isTextToolActive || isNumberToolActive || isMagnifierToolActive || isEraserToolActive),
            let selectionRect,
            let toolbar = mainToolbarRect(for: selectionRect)
        else {
            return nil
        }

        let optionsSize = NSSize(
            width: SelectionToolbarState.optionsToolbarWidth(paletteCount: visiblePaletteCount, mode: optionsToolbarMode),
            height: SelectionToolbarState.optionsToolbarHeight(paletteCount: visiblePaletteCount, mode: optionsToolbarMode)
        )
        if shouldLeftAlignOptionsToolbarWithMainToolbar(optionsToolbarMode) {
            return leftAlignedOptionsToolbarRect(size: optionsSize, alignedWith: toolbar)
        }
        if let anchorButton = optionsToolbarAnchorButton(for: optionsToolbarMode),
           let anchorRect = toolbarButtonRects(in: toolbar).first(where: { $0.0 == anchorButton })?.1 {
            return anchoredOptionsToolbarRect(size: optionsSize, anchoredTo: anchorRect, within: toolbar)
        }

        return toolbarRect(size: optionsSize, anchoredTo: toolbar)
    }

    private func shouldLeftAlignOptionsToolbarWithMainToolbar(_ mode: SelectionToolbarState.OptionsToolbarMode) -> Bool {
        switch mode {
        case .shape, .arrowLine, .text:
            return true
        case .brush, .marker, .mosaic, .numberSequence, .magnifier, .eraser:
            return false
        }
    }

    private func optionsToolbarAnchorButton(for mode: SelectionToolbarState.OptionsToolbarMode) -> ToolbarButton? {
        switch mode {
        case .brush:
            return .pen
        case .marker:
            return .marker
        case .mosaic:
            return .mosaic
        case .eraser:
            return .eraser
        case .shape, .arrowLine, .text, .numberSequence, .magnifier:
            return nil
        }
    }

    private func leftAlignedOptionsToolbarRect(size: NSSize, alignedWith toolbar: NSRect) -> NSRect {
        let gap: CGFloat = 8
        let safeBounds = safeLayoutBounds.insetBy(dx: gap, dy: gap)
        let x = min(
            max(toolbar.minX, safeBounds.minX),
            max(safeBounds.minX, safeBounds.maxX - size.width)
        )
        let below = NSRect(
            x: x,
            y: toolbar.minY - gap - size.height,
            width: size.width,
            height: size.height
        )
        if safeBounds.contains(below) {
            return below
        }

        let above = NSRect(
            x: x,
            y: toolbar.maxY + gap,
            width: size.width,
            height: size.height
        )
        if safeBounds.contains(above) {
            return above
        }

        return clamp(rect: below, inside: safeBounds)
    }

    private func anchoredOptionsToolbarRect(size: NSSize, anchoredTo anchor: NSRect, within toolbar: NSRect) -> NSRect {
        let gap: CGFloat = 8
        let safeBounds = safeLayoutBounds.insetBy(dx: gap, dy: gap)
        let centeredX = anchor.midX - size.width / 2
        let x: CGFloat
        if size.width <= toolbar.width {
            x = min(max(centeredX, toolbar.minX), toolbar.maxX - size.width)
        } else {
            x = min(
                max(centeredX, safeBounds.minX),
                max(safeBounds.minX, safeBounds.maxX - size.width)
            )
        }
        let below = NSRect(
            x: x,
            y: anchor.minY - gap - size.height,
            width: size.width,
            height: size.height
        )
        if safeBounds.contains(below) {
            return below
        }

        let above = NSRect(
            x: x,
            y: anchor.maxY + gap,
            width: size.width,
            height: size.height
        )
        if safeBounds.contains(above) {
            return above
        }

        return clamp(rect: below, inside: safeBounds)
    }

    private var cornerRadiusPanelRect: NSRect? {
        guard optionsToolbarMode == .shape, let options = optionsToolbarRect else {
            return nil
        }

        let rectangleButton = rectangleModeButtonRect(in: options)
        var rect = NSRect(x: rectangleButton.minX - 6, y: options.minY - 38, width: 260, height: 30)
        if rect.minY < safeLayoutBounds.minY + 8 {
            rect.origin.y = options.maxY + 8
        }
        return clamp(rect: rect, inside: safeLayoutBounds.insetBy(dx: 8, dy: 8))
    }

    private func toolbarRect(size: NSSize, anchoredTo anchor: NSRect) -> NSRect {
        SelectionToolbarState.toolbarRect(size: size, anchoredTo: anchor, inside: safeLayoutBounds)
    }

    private func strokeWidthRects(in optionsRect: NSRect) -> [NSRect] {
        SelectionToolbarState.strokeWidthRects(in: optionsRect)
    }

    private func optionButtonBackgroundRect(for rect: NSRect) -> NSRect {
        rect.insetBy(dx: -3, dy: -5)
    }

    private func fillToggleRect(in optionsRect: NSRect) -> NSRect {
        SelectionToolbarState.fillToggleRect(in: optionsRect)
    }

    private func rectangleModeButtonRect(in optionsRect: NSRect) -> NSRect {
        SelectionToolbarState.rectangleModeButtonRect(in: optionsRect)
    }

    private func ellipseModeButtonRect(in optionsRect: NSRect) -> NSRect {
        SelectionToolbarState.ellipseModeButtonRect(in: optionsRect)
    }

    private func strokeStyleFieldRect(in optionsRect: NSRect) -> NSRect {
        optionsToolbarLayout(in: optionsRect).strokeStyle
    }

    private func optionControlY(in optionsRect: NSRect) -> CGFloat {
        optionsRect.midY - 10
    }

    private func strokeStyleMenuRect(in optionsRect: NSRect) -> NSRect {
        let field = strokeStyleFieldRect(in: optionsRect)
        let itemCount = max(1, strokePatternOptions.count)
        let height = CGFloat(itemCount) * 24 + 8
        return SelectionToolbarState.popoverRect(
            size: NSSize(width: field.width, height: height),
            anchoredTo: field,
            inside: safeLayoutBounds
        )
    }

    private func strokeStyleMenuItemRects(in menu: NSRect) -> [NSRect] {
        SelectionToolbarState.strokeStyleMenuItemRects(in: menu, itemCount: strokePatternOptions.count)
    }

    private func arrowTypeMenuRect(in optionsRect: NSRect, field: ArrowTypeField) -> NSRect {
        let layout = optionsToolbarLayout(in: optionsRect)
        let anchor: NSRect
        switch field {
        case .start:
            anchor = layout.startArrowType ?? .zero
        case .end:
            anchor = layout.endArrowType ?? .zero
        }
        let itemCount = CaptureArrowType.allCases.count
        return SelectionToolbarState.popoverRect(
            size: NSSize(width: 58, height: CGFloat(itemCount) * 24 + 8),
            anchoredTo: anchor,
            inside: safeLayoutBounds
        )
    }

    private func arrowTypeMenuItemRects(in menu: NSRect) -> [NSRect] {
        SelectionToolbarState.arrowTypeMenuItemRects(in: menu, itemCount: CaptureArrowType.allCases.count)
    }

    private func numberMarkTypeMenuRect(in optionsRect: NSRect) -> NSRect {
        let field = optionsToolbarLayout(in: optionsRect).numberMarkType
        return SelectionToolbarState.popoverRect(
            size: NSSize(width: 56, height: CGFloat(CaptureNumberMarkType.allCases.count) * 26 + 8),
            anchoredTo: field,
            inside: safeLayoutBounds
        )
    }

    private func numberMarkTypeMenuItemRects(in menu: NSRect) -> [NSRect] {
        CaptureNumberMarkType.allCases.indices.map { index in
            NSRect(
                x: menu.minX + 4,
                y: menu.maxY - 4 - 26 * CGFloat(index + 1),
                width: menu.width - 8,
                height: 26
            )
        }
    }

    private func magnifierZoomMenuRect(in optionsRect: NSRect) -> NSRect {
        let field = optionsToolbarLayout(in: optionsRect).magnifierZoom
        return SelectionToolbarState.popoverRect(
            size: NSSize(width: field.width, height: CGFloat(SelectionToolbarState.magnifierZoomValues.count) * 24 + 8),
            anchoredTo: field,
            inside: safeLayoutBounds
        )
    }

    private func magnifierZoomMenuItemRects(in menu: NSRect) -> [NSRect] {
        SelectionToolbarState.magnifierZoomValues.indices.map { index in
            NSRect(
                x: menu.minX + 4,
                y: menu.maxY - 4 - 24 * CGFloat(index + 1),
                width: menu.width - 8,
                height: 24
            )
        }
    }

    private func shapeModeBackgroundRect(for button: NSRect) -> NSRect {
        button.insetBy(dx: -3, dy: -4)
    }

    private func rectangleIconRect(in button: NSRect) -> NSRect {
        let side: CGFloat = 13
        return NSRect(x: button.minX + 4, y: button.midY - side / 2, width: side, height: side)
    }

    private func circleIconRect(in button: NSRect) -> NSRect {
        let side: CGFloat = 13
        return NSRect(x: button.midX - side / 2, y: button.midY - side / 2, width: side, height: side)
    }

    private func rectangleDisclosureHitRect(in button: NSRect) -> NSRect {
        let background = shapeModeBackgroundRect(for: button)
        return NSRect(x: background.maxX - 12, y: background.minY, width: 12, height: 12)
    }

    private func colorSwatchRects(in optionsRect: NSRect) -> [NSRect] {
        SelectionToolbarState.colorSwatchRects(in: optionsRect, paletteCount: visiblePaletteCount, mode: optionsToolbarMode)
    }

    private func cornerRadiusValueRect(in panel: NSRect) -> NSRect {
        NSRect(x: panel.maxX - 55, y: panel.minY + 3, width: 52, height: 24)
    }

    private func mosaicValueDecrementRect(in rect: NSRect) -> NSRect {
        let track = mosaicValueSliderTrackRect(in: rect)
        return NSRect(x: track.minX - 4, y: rect.minY, width: 8, height: rect.height)
    }

    private func mosaicValueIncrementRect(in rect: NSRect) -> NSRect {
        let track = mosaicValueSliderTrackRect(in: rect)
        return NSRect(x: track.maxX - 4, y: rect.minY, width: 8, height: rect.height)
    }

    private func mosaicValueInputRect(in rect: NSRect) -> NSRect {
        mosaicValueSliderTrackRect(in: rect)
    }

    private func mosaicValueSliderTrackRect(in rect: NSRect) -> NSRect {
        NSRect(x: rect.minX + 8, y: rect.midY - 2, width: max(24, rect.width - 40), height: 4)
    }

    private func mosaicValueSliderLabelRect(in rect: NSRect) -> NSRect {
        NSRect(x: rect.maxX - 24, y: rect.minY, width: 24, height: rect.height)
    }

    private func cornerRadiusSliderTrackRect(in panel: NSRect, valueRect: NSRect) -> NSRect {
        NSRect(x: panel.minX + 78, y: panel.minY + 13, width: valueRect.minX - panel.minX - 86, height: 4)
    }

    private func cornerRadiusUpRect(in valueRect: NSRect) -> NSRect {
        NSRect(x: valueRect.maxX - 17, y: valueRect.midY, width: 18, height: valueRect.height / 2)
    }

    private func cornerRadiusDownRect(in valueRect: NSRect) -> NSRect {
        NSRect(x: valueRect.maxX - 17, y: valueRect.minY, width: 18, height: valueRect.height / 2)
    }

    private func localAnnotationRect(from overlayRect: NSRect) -> NSRect {
        guard let lockedSelectionRect else {
            return overlayRect
        }

        return SelectionToolbarState.localAnnotationRect(fromOverlayRect: overlayRect, selectionRect: lockedSelectionRect)
    }

    private func localArrowLine(fromOverlayArrowLine arrowLine: CaptureArrowLine) -> CaptureArrowLine {
        guard let lockedSelectionRect else {
            return arrowLine
        }

        return localArrowLine(fromOverlayArrowLine: arrowLine, selectionRect: lockedSelectionRect)
    }

    private func localArrowLine(fromOverlayArrowLine arrowLine: CaptureArrowLine, selectionRect: NSRect) -> CaptureArrowLine {
        CaptureArrowLine(
            start: localPoint(fromOverlayPoint: arrowLine.start, selectionRect: selectionRect),
            end: localPoint(fromOverlayPoint: arrowLine.end, selectionRect: selectionRect),
            control: localPoint(fromOverlayPoint: arrowLine.control, selectionRect: selectionRect),
            startArrowType: arrowLine.startArrowType,
            endArrowType: arrowLine.endArrowType
        )
    }

    private func localMarkerLine(fromOverlayMarkerLine markerLine: CaptureMarkerLine) -> CaptureMarkerLine {
        guard let lockedSelectionRect else {
            return markerLine
        }

        return localMarkerLine(fromOverlayMarkerLine: markerLine, selectionRect: lockedSelectionRect)
    }

    private func localMarkerLine(fromOverlayMarkerLine markerLine: CaptureMarkerLine, selectionRect: NSRect) -> CaptureMarkerLine {
        CaptureMarkerLine(
            start: localPoint(fromOverlayPoint: markerLine.start, selectionRect: selectionRect),
            end: localPoint(fromOverlayPoint: markerLine.end, selectionRect: selectionRect)
        )
    }

    private func localBrushPath(fromOverlayBrushPath brushPath: CaptureBrushPath) -> CaptureBrushPath {
        guard let lockedSelectionRect else {
            return brushPath
        }

        return localBrushPath(fromOverlayBrushPath: brushPath, selectionRect: lockedSelectionRect)
    }

    private func localBrushPath(fromOverlayBrushPath brushPath: CaptureBrushPath, selectionRect: NSRect) -> CaptureBrushPath {
        CaptureBrushPath(
            points: brushPath.points.map { localPoint(fromOverlayPoint: $0, selectionRect: selectionRect) }
        )
    }

    private func overlayRect(fromLocalAnnotationRect localRect: NSRect) -> NSRect {
        guard let lockedSelectionRect else {
            return localRect
        }

        return NSRect(
            x: lockedSelectionRect.minX + localRect.minX,
            y: lockedSelectionRect.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        )
    }

    private func overlayArrowLine(fromLocalArrowLine arrowLine: CaptureArrowLine?) -> CaptureArrowLine? {
        guard let arrowLine, let lockedSelectionRect else {
            return arrowLine
        }

        return overlayArrowLine(fromLocalArrowLine: arrowLine, selectionRect: lockedSelectionRect)
    }

    private func overlayArrowLine(fromLocalArrowLine arrowLine: CaptureArrowLine, selectionRect: NSRect) -> CaptureArrowLine {
        CaptureArrowLine(
            start: overlayPoint(fromLocalPoint: arrowLine.start, selectionRect: selectionRect),
            end: overlayPoint(fromLocalPoint: arrowLine.end, selectionRect: selectionRect),
            control: overlayPoint(fromLocalPoint: arrowLine.control, selectionRect: selectionRect),
            startArrowType: arrowLine.startArrowType,
            endArrowType: arrowLine.endArrowType
        )
    }

    private func overlayMarkerLine(fromLocalMarkerLine markerLine: CaptureMarkerLine?) -> CaptureMarkerLine? {
        guard let markerLine, let lockedSelectionRect else {
            return markerLine
        }

        return overlayMarkerLine(fromLocalMarkerLine: markerLine, selectionRect: lockedSelectionRect)
    }

    private func overlayMarkerLine(fromLocalMarkerLine markerLine: CaptureMarkerLine, selectionRect: NSRect) -> CaptureMarkerLine {
        CaptureMarkerLine(
            start: overlayPoint(fromLocalPoint: markerLine.start, selectionRect: selectionRect),
            end: overlayPoint(fromLocalPoint: markerLine.end, selectionRect: selectionRect)
        )
    }

    private func overlayBrushPath(fromLocalBrushPath brushPath: CaptureBrushPath?) -> CaptureBrushPath? {
        guard let brushPath, let lockedSelectionRect else {
            return brushPath
        }

        return overlayBrushPath(fromLocalBrushPath: brushPath, selectionRect: lockedSelectionRect)
    }

    private func overlayBrushPath(fromLocalBrushPath brushPath: CaptureBrushPath, selectionRect: NSRect) -> CaptureBrushPath {
        CaptureBrushPath(
            points: brushPath.points.map { overlayPoint(fromLocalPoint: $0, selectionRect: selectionRect) }
        )
    }

    private func overlayMosaicStroke(fromLocalMosaicStroke stroke: CaptureMosaicStroke?) -> CaptureMosaicStroke? {
        guard let stroke, let lockedSelectionRect else {
            return stroke
        }

        return overlayMosaicStroke(fromLocalMosaicStroke: stroke, selectionRect: lockedSelectionRect)
    }

    private func overlayMosaicStroke(fromLocalMosaicStroke stroke: CaptureMosaicStroke, selectionRect: NSRect) -> CaptureMosaicStroke {
        return CaptureMosaicStroke(
            points: stroke.points.map { overlayPoint(fromLocalPoint: $0, selectionRect: selectionRect) }
        )
    }

    private func mosaicPreviewComposite(for annotations: [CaptureAnnotation]) -> (image: NSImage, drawRect: NSRect)? {
        mosaicPreviewComposite(for: annotations, allowLocal: true)
    }

    private func fullMosaicPreviewComposite(for annotations: [CaptureAnnotation]) -> (image: NSImage, drawRect: NSRect)? {
        mosaicPreviewComposite(for: annotations, allowLocal: false)
    }

    private func cachedFullMosaicPreviewComposite(for annotations: [CaptureAnnotation]) -> (image: NSImage, drawRect: NSRect)? {
        guard let backgroundImage, !annotations.isEmpty else {
            return nil
        }
        let start = CFAbsoluteTimeGetCurrent()
        let key = mosaicCompositeKey(for: annotations, backgroundImage: backgroundImage)
        let cacheKey = [
            "full",
            key,
        ].joined(separator: "|")
        let cached = mosaicCompositeCache[cacheKey]
        logMosaicCacheEventIfNeeded(
            "cached-full-composite-lookup",
            startTime: start,
            details: "result=\(cached == nil ? "miss" : "hit") requested=\(annotations.count)"
        )
        return cached
    }

    private func mosaicPreviewComposite(
        for annotations: [CaptureAnnotation],
        allowLocal: Bool
    ) -> (image: NSImage, drawRect: NSRect)? {
        guard let backgroundImage, !annotations.isEmpty else {
            return nil
        }
        let start = CFAbsoluteTimeGetCurrent()
        let keyStart = CFAbsoluteTimeGetCurrent()
        let annotationKey = mosaicCompositeKey(for: annotations, backgroundImage: backgroundImage)
        let keyElapsedMs = (CFAbsoluteTimeGetCurrent() - keyStart) * 1000
        let cacheKey = [
            allowLocal ? "local" : "full",
            annotationKey,
        ].joined(separator: "|")
        if let composite = mosaicCompositeCache[cacheKey] {
            logMosaicCacheEventIfNeeded(
                "mosaic-preview-composite-cache-hit",
                startTime: start,
                details: "allowLocal=\(allowLocal) requested=\(annotations.count) drawRect=\(mosaicRectLogDescription(composite.drawRect)) keyMs=\(String(format: "%.2f", keyElapsedMs))"
            )
            return composite
        }

        let renderStart = CFAbsoluteTimeGetCurrent()
        let composite: (image: NSImage, drawRect: NSRect)
        let renderedFullComposite: Bool
        if allowLocal,
           canUseLocalMosaicComposite(for: annotations),
           let localComposite = localMosaicComposite(for: annotations, backgroundImage: backgroundImage) {
            composite = localComposite
            renderedFullComposite = false
        } else {
            composite = fullMosaicPreviewCompositeRenderingCacheMiss(
                for: annotations,
                backgroundImage: backgroundImage
            )
            renderedFullComposite = true
        }
        mosaicCompositeRenderCount += 1
        mosaicCompositeCache[cacheKey] = composite
        if renderedFullComposite {
            let fullCacheKey = [
                "full",
                annotationKey,
            ].joined(separator: "|")
            mosaicCompositeCache[fullCacheKey] = composite
        }
        logMosaicPerformanceEvent(
            "mosaic-preview-composite-cache-miss",
            startTime: start,
            details: "allowLocal=\(allowLocal) rendered=\(renderedFullComposite ? "full" : "local") requested=\(annotations.count) drawRect=\(mosaicRectLogDescription(composite.drawRect)) keyMs=\(String(format: "%.2f", keyElapsedMs)) renderMs=\(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - renderStart) * 1000))"
        )
        return composite
    }

    private func canUseLocalMosaicComposite(for annotations: [CaptureAnnotation]) -> Bool {
        annotations.contains(where: isMosaicAnnotation)
    }

    private func fullMosaicPreviewCompositeRenderingCacheMiss(
        for annotations: [CaptureAnnotation],
        backgroundImage: NSImage
    ) -> (image: NSImage, drawRect: NSRect) {
        let start = CFAbsoluteTimeGetCurrent()
        mosaicFullCompositeRenderCount += 1
        if let prefix = longestCachedFullMosaicPrefix(for: annotations, backgroundImage: backgroundImage),
           prefix.count < annotations.count {
            let suffix = annotations[prefix.count...].map(overlayAnnotation)
            let rendered = CaptureAnnotationRenderer.render(image: prefix.composite.image, annotations: suffix)
            logMosaicPerformanceEvent(
                "full-composite-render",
                startTime: start,
                details: "source=prefix prefix=\(prefix.count) suffix=\(suffix.count) requested=\(annotations.count)"
            )
            return (rendered, bounds)
        }

        let rendered = CaptureAnnotationRenderer.render(
            image: backgroundImage,
            annotations: annotations.map(overlayAnnotation)
        )
        logMosaicPerformanceEvent(
            "full-composite-render",
            startTime: start,
            details: "source=background requested=\(annotations.count) image=\(mosaicRectLogDescription(NSRect(origin: .zero, size: backgroundImage.size)))"
        )
        return (rendered, bounds)
    }

    private func longestCachedFullMosaicPrefix(
        for annotations: [CaptureAnnotation],
        backgroundImage: NSImage
    ) -> (count: Int, composite: (image: NSImage, drawRect: NSRect))? {
        guard annotations.count > 1 else {
            return nil
        }

        for count in stride(from: annotations.count - 1, through: 1, by: -1) {
            let prefix = Array(annotations.prefix(count))
            let key = [
                "full",
                mosaicCompositeKey(for: prefix, backgroundImage: backgroundImage),
            ].joined(separator: "|")
            if let composite = mosaicCompositeCache[key] {
                return (count, composite)
            }
        }
        return nil
    }

    private func localMosaicComposite(
        for annotations: [CaptureAnnotation],
        backgroundImage: NSImage
    ) -> (image: NSImage, drawRect: NSRect)? {
        let start = CFAbsoluteTimeGetCurrent()
        guard let drawRect = mosaicCompositeDrawRect(for: annotations),
              let backgroundCrop = crop(image: backgroundImage, to: drawRect) else {
            logMosaicCacheEventIfNeeded(
                "local-composite-failed",
                startTime: start,
                force: true,
                details: "requested=\(annotations.count)"
            )
            return nil
        }

        let shiftedAnnotations = annotations.map { shiftedOverlayAnnotation($0, by: drawRect.origin) }
        let rendered = CaptureAnnotationRenderer.render(
            image: backgroundCrop,
            annotations: shiftedAnnotations
        )
        logMosaicCacheEventIfNeeded(
            "local-composite-render",
            startTime: start,
            details: "requested=\(annotations.count) drawRect=\(mosaicRectLogDescription(drawRect)) cropSize=\(mosaicRectLogDescription(NSRect(origin: .zero, size: backgroundCrop.size)))"
        )
        return (rendered, drawRect)
    }

    private func mosaicCompositeDrawRect(for annotations: [CaptureAnnotation]) -> NSRect? {
        let imageBounds = backgroundImage.map { NSRect(origin: .zero, size: $0.size) } ?? bounds
        var unionRect: NSRect?
        var pixelBlock: CGFloat?
        for annotation in annotations where isMosaicAnnotation(annotation) {
            guard let clipBounds = mosaicDraftClipPath(for: annotation)?.bounds else {
                continue
            }
            let value = CGFloat(max(1, annotation.mosaicRedaction?.value ?? 1))
            let padding: CGFloat
            switch annotation.mosaicRedaction?.type {
            case .gaussianBlur:
                padding = value * 3
            case .pixelMosaic:
                padding = value
                pixelBlock = max(pixelBlock ?? value, value)
            case .none:
                padding = 1
            }
            let padded = clipBounds.insetBy(dx: -padding, dy: -padding)
            unionRect = unionRect.map { $0.union(padded) } ?? padded
        }

        guard let unionRect else {
            return nil
        }
        var clipped = unionRect.intersection(imageBounds)
        if let pixelBlock, pixelBlock > 1 {
            clipped = alignedPixelMosaicRect(clipped, block: pixelBlock, imageBounds: imageBounds)
        }
        return clipped.isEmpty ? nil : clipped
    }

    private func alignedPixelMosaicRect(_ rect: NSRect, block: CGFloat, imageBounds: NSRect) -> NSRect {
        let minX = floor(rect.minX / block) * block
        let maxX = ceil(rect.maxX / block) * block
        let top = imageBounds.maxY - rect.maxY
        let bottom = imageBounds.maxY - rect.minY
        let alignedTop = floor(top / block) * block
        let alignedBottom = ceil(bottom / block) * block
        let minY = imageBounds.maxY - alignedBottom
        let maxY = imageBounds.maxY - alignedTop
        let aligned = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return aligned.intersection(imageBounds)
    }

    private func overlayAnnotation(_ annotation: CaptureAnnotation) -> CaptureAnnotation {
        var overlayAnnotation = annotation
        overlayAnnotation.rect = overlayRect(fromLocalAnnotationRect: annotation.rect)
        if let arrowLine = annotation.arrowLine {
            overlayAnnotation.arrowLine = overlayArrowLine(fromLocalArrowLine: arrowLine)
        }
        if let markerLine = annotation.markerLine {
            overlayAnnotation.markerLine = overlayMarkerLine(fromLocalMarkerLine: markerLine)
        }
        if let brushPath = annotation.brushPath {
            overlayAnnotation.brushPath = overlayBrushPath(fromLocalBrushPath: brushPath)
        }
        if let mosaicStroke = annotation.mosaicStroke {
            overlayAnnotation.mosaicStroke = overlayMosaicStroke(fromLocalMosaicStroke: mosaicStroke)
        }
        return overlayAnnotation
    }

    private func shiftedOverlayAnnotation(_ annotation: CaptureAnnotation, by origin: NSPoint) -> CaptureAnnotation {
        var shifted = overlayAnnotation(annotation)
        shifted.rect.origin.x -= origin.x
        shifted.rect.origin.y -= origin.y
        if let arrowLine = shifted.arrowLine {
            shifted.arrowLine = CaptureArrowLine(
                start: shiftedPoint(arrowLine.start, by: origin),
                end: shiftedPoint(arrowLine.end, by: origin),
                control: shiftedPoint(arrowLine.control, by: origin),
                startArrowType: arrowLine.startArrowType,
                endArrowType: arrowLine.endArrowType
            )
        }
        if let markerLine = shifted.markerLine {
            shifted.markerLine = CaptureMarkerLine(
                start: shiftedPoint(markerLine.start, by: origin),
                end: shiftedPoint(markerLine.end, by: origin)
            )
        }
        if let brushPath = shifted.brushPath {
            shifted.brushPath = CaptureBrushPath(
                points: brushPath.points.map { shiftedPoint($0, by: origin) }
            )
        }
        if let mosaicStroke = shifted.mosaicStroke {
            shifted.mosaicStroke = CaptureMosaicStroke(
                points: mosaicStroke.points.map { shiftedPoint($0, by: origin) }
            )
        }
        return shifted
    }

    private func shiftedPoint(_ point: NSPoint, by origin: NSPoint) -> NSPoint {
        NSPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private func mosaicCompositeKey(for annotations: [CaptureAnnotation], backgroundImage: NSImage) -> String {
        var parts: [String] = [
            mosaicBackgroundKey(for: backgroundImage),
        ]
        parts.reserveCapacity(annotations.count + (eraserMasks.isEmpty ? 1 : 2))
        annotations.forEach { parts.append(annotationCompositeKey(overlayAnnotation($0))) }
        if !eraserMasks.isEmpty {
            parts.append(eraserMaskCacheSignature(for: annotations))
        }
        return parts.joined(separator: "|")
    }

    private func eraserMaskCacheSignature(for annotations: [CaptureAnnotation]) -> String {
        guard !eraserMasks.isEmpty else {
            return "no-mask"
        }
        let annotationIDs = Set(annotations.map(\.id))
        let maskParts = eraserMasks
            .filter { !$0.affectedAnnotationIDs.isDisjoint(with: annotationIDs) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { mask in
                let rect = mask.rect.standardized
                let affectedIDs = mask.affectedAnnotationIDs
                    .map(\.uuidString)
                    .sorted()
                    .joined(separator: ",")
                return [
                    mask.id.uuidString,
                    mosaicKey(rect),
                    affectedIDs,
                ].joined(separator: ":")
            }
        return "masks:" + maskParts.joined(separator: ";")
    }

    private func annotationCompositeKey(_ annotation: CaptureAnnotation) -> String {
        var item = [
            "\(annotation.kind)",
            mosaicKey(annotation.rect),
            "\(Int((annotation.rotationAngle * 1000).rounded()))",
            styleKey(annotation.style),
        ].joined(separator: ":")
        if let redaction = annotation.mosaicRedaction {
            item += ":\(redaction.type):\(redaction.value)"
        }
        if let arrowLine = annotation.arrowLine {
            item += ":arrow:\(pointKey(arrowLine.start))>\(pointKey(arrowLine.control))>\(pointKey(arrowLine.end)):\(arrowLine.startArrowType.rawValue)-\(arrowLine.endArrowType.rawValue)"
        }
        if let brushPath = annotation.brushPath {
            item += ":brush:" + brushPath.points.map(pointKey).joined(separator: ",")
        }
        if let markerLine = annotation.markerLine {
            item += ":marker:\(pointKey(markerLine.start))>\(pointKey(markerLine.end))"
        }
        if annotation.kind == .magnifier {
            item += ":magnifier:\(annotation.effectiveMagnifierShape):\(Int((annotation.effectiveMagnifierZoom * 100).rounded()))"
        }
        if let stroke = annotation.mosaicStroke {
            item += ":mosaic:" + stroke.points.map(pointKey).joined(separator: ",")
        }
        return item
    }

    private func styleKey(_ style: CaptureAnnotationStyle) -> String {
        [
            colorKey(style.strokeColor),
            "\(Int((style.strokeWidth * 100).rounded()))",
            "\(style.strokePattern.rawValue)",
            style.fillEnabled ? "fill" : "nofill",
            colorKey(style.fillColor),
            "\(Int((style.cornerRadius * 100).rounded()))",
            "\(Int((style.textSize * 100).rounded()))",
            style.textFontFamily ?? "",
            style.textBold ? "bold" : "regular",
            style.textItalic ? "italic" : "roman",
            style.textOutlineEnabled ? "outline" : "plain",
            colorKey(style.textOutlineColor),
        ].joined(separator: "/")
    }

    private func colorKey(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? color
        return [
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded()),
            Int((rgb.alphaComponent * 255).rounded()),
        ].map(String.init).joined(separator: ",")
    }

    private func pointKey(_ point: NSPoint) -> String {
        "\(Int(point.x.rounded()))x\(Int(point.y.rounded()))"
    }

    private func mosaicBackgroundKey(for backgroundImage: NSImage) -> String {
        "bg:\(Int(backgroundImage.size.width))x\(Int(backgroundImage.size.height))"
    }

    private func mosaicKey(_ rect: NSRect) -> String {
        "\(Int(rect.minX.rounded())),\(Int(rect.minY.rounded())),\(Int(rect.width.rounded())),\(Int(rect.height.rounded()))"
    }

    private func mosaicPreviewAnnotations(including draft: CaptureAnnotation) -> [CaptureAnnotation] {
        annotations + [draft]
    }

    private func mosaicDraftPreviewImage(for annotation: CaptureAnnotation) -> NSImage? {
        mosaicDraftPreview(for: annotation)?.image
    }

    private func mosaicDraftPreview(for annotation: CaptureAnnotation) -> (image: NSImage, drawRect: NSRect)? {
        guard let backgroundImage, let redaction = annotation.mosaicRedaction else {
            return nil
        }

        let existingAnnotations = annotations
        if existingAnnotations.isEmpty,
           annotation.kind == .mosaicRectangle,
           redaction.type == .gaussianBlur {
            return mosaicFullImageDraftPreview(for: annotation, redaction: redaction, backgroundImage: backgroundImage)
        }

        if !existingAnnotations.isEmpty,
           let preview = mosaicLocalPreview(
            for: annotation,
            existingAnnotations: existingAnnotations,
            backgroundImage: backgroundImage
           ) {
            return preview
        }

        let baseImage: NSImage
        let baseKey: String
        if let baseComposite = fullMosaicPreviewComposite(for: existingAnnotations) {
            baseImage = baseComposite.image
            baseKey = mosaicCompositeKey(for: existingAnnotations, backgroundImage: backgroundImage)
        } else {
            baseImage = backgroundImage
            baseKey = mosaicBackgroundKey(for: backgroundImage)
        }

        return mosaicLocalPreview(
            for: annotation,
            baseImage: baseImage,
            baseKey: baseKey
        )
    }

    private func mosaicFullImageDraftPreview(
        for annotation: CaptureAnnotation,
        redaction: CaptureMosaicRedaction,
        backgroundImage: NSImage
    ) -> (image: NSImage, drawRect: NSRect)? {
        let start = CFAbsoluteTimeGetCurrent()
        let drawRect = mosaicDraftPreviewDrawRect(for: annotation, redaction: redaction)
        let existingAnnotations = annotations
        let cacheKey = [
            "\(Int(backgroundImage.size.width.rounded()))x\(Int(backgroundImage.size.height.rounded()))",
            mosaicKey(lockedSelectionRect ?? .zero),
            "\(redaction.type)",
            "\(redaction.value)",
            mosaicKey(drawRect),
            mosaicCompositeKey(for: existingAnnotations, backgroundImage: backgroundImage),
            mosaicCompositeKey(for: [annotation], backgroundImage: backgroundImage),
        ].joined(separator: "|")
        if let cached = mosaicDraftPreviewCache[cacheKey] {
            logMosaicCacheEventIfNeeded(
                "full-image-draft-preview-cache-hit",
                startTime: start,
                details: "kind=\(annotation.kind) existing=\(existingAnnotations.count) redaction=\(redaction.type):\(redaction.value) drawRect=\(mosaicRectLogDescription(drawRect))"
            )
            return (cached, drawRect)
        }

        let rendered = mosaicDraftRedactedBaseImage(
            redaction: redaction,
            existingAnnotations: existingAnnotations,
            backgroundImage: backgroundImage
        )
        guard
            let baseCrop = crop(image: mosaicDraftPreviewBaseImage(), to: drawRect),
            let redactedCrop = crop(image: rendered, to: drawRect),
            let preview = mosaicMaskedPreview(
                baseCrop: baseCrop,
                redactedCrop: redactedCrop,
                annotation: annotation,
                drawRect: drawRect
            )
        else {
            logMosaicCacheEventIfNeeded(
                "full-image-draft-preview-failed",
                startTime: start,
                force: true,
                details: "kind=\(annotation.kind) existing=\(existingAnnotations.count) redaction=\(redaction.type):\(redaction.value) drawRect=\(mosaicRectLogDescription(drawRect))"
            )
            return nil
        }
        mosaicDraftPreviewCache[cacheKey] = preview
        logMosaicCacheEventIfNeeded(
            "full-image-draft-preview-render",
            startTime: start,
            force: true,
            details: "kind=\(annotation.kind) existing=\(existingAnnotations.count) redaction=\(redaction.type):\(redaction.value) drawRect=\(mosaicRectLogDescription(drawRect))"
        )
        return (preview, drawRect)
    }

    private func mosaicLocalPreview(
        for annotation: CaptureAnnotation,
        baseImage: NSImage,
        baseKey: String
    ) -> (image: NSImage, drawRect: NSRect)? {
        let start = CFAbsoluteTimeGetCurrent()
        guard let redaction = annotation.mosaicRedaction else {
            return nil
        }

        let drawRect = mosaicDraftPreviewDrawRect(for: annotation, redaction: redaction)
        let cacheKey = [
            "local",
            baseKey,
            annotationCompositeKey(annotation),
            mosaicKey(drawRect),
        ].joined(separator: "|")
        if let cached = mosaicDraftPreviewCache[cacheKey] {
            logMosaicCacheEventIfNeeded(
                "local-preview-cache-hit",
                startTime: start,
                details: "kind=\(annotation.kind) redaction=\(redaction.type):\(redaction.value) drawRect=\(mosaicRectLogDescription(drawRect))"
            )
            return (cached, drawRect)
        }

        let processingRect = mosaicLocalPreviewProcessingRect(
            for: drawRect,
            redaction: redaction,
            imageSize: baseImage.size
        )
        guard let processingBaseCrop = crop(image: baseImage, to: processingRect) else {
            logMosaicCacheEventIfNeeded(
                "local-preview-crop-failed",
                startTime: start,
                force: true,
                details: "kind=\(annotation.kind) drawRect=\(mosaicRectLogDescription(drawRect)) processingRect=\(mosaicRectLogDescription(processingRect))"
            )
            return nil
        }

        if redaction.type == .pixelMosaic {
            guard let preview = renderedLocalMosaicPreview(
                annotation: annotation,
                processingBaseCrop: processingBaseCrop,
                processingRect: processingRect,
                drawRect: drawRect
            ) else {
                logMosaicCacheEventIfNeeded(
                    "local-preview-renderer-failed",
                    startTime: start,
                    force: true,
                    details: "kind=\(annotation.kind) drawRect=\(mosaicRectLogDescription(drawRect)) processingRect=\(mosaicRectLogDescription(processingRect))"
                )
                return nil
            }
            mosaicDraftPreviewCache[cacheKey] = preview
            logMosaicCacheEventIfNeeded(
                "local-preview-renderer-render",
                startTime: start,
                force: true,
                details: "kind=\(annotation.kind) redaction=\(redaction.type):\(redaction.value) drawRect=\(mosaicRectLogDescription(drawRect)) processingRect=\(mosaicRectLogDescription(processingRect))"
            )
            return (preview, drawRect)
        }

        let redactedCropKey = [
            "crop",
            baseKey,
            "\(redaction.type)",
            "\(redaction.value)",
            mosaicKey(processingRect),
        ].joined(separator: "|")
        let redactedProcessingCrop: NSImage
        let redactedCacheHit: Bool
        if let cached = mosaicDraftRedactedBaseCache[redactedCropKey] {
            redactedProcessingCrop = cached
            redactedCacheHit = true
        } else {
            let redactedStart = CFAbsoluteTimeGetCurrent()
            mosaicDraftRedactedBaseRenderCount += 1
            redactedProcessingCrop = CaptureAnnotationRenderer.redactedPreview(image: processingBaseCrop, redaction: redaction)
            mosaicDraftRedactedBaseCache[redactedCropKey] = redactedProcessingCrop
            redactedCacheHit = false
            logMosaicCacheEventIfNeeded(
                "local-preview-redacted-crop-render",
                startTime: redactedStart,
                force: true,
                details: "redaction=\(redaction.type):\(redaction.value) processingRect=\(mosaicRectLogDescription(processingRect))"
            )
        }

        let localDrawRect = NSRect(
            x: drawRect.minX - processingRect.minX,
            y: drawRect.minY - processingRect.minY,
            width: drawRect.width,
            height: drawRect.height
        )
        guard
            let baseCrop = crop(image: processingBaseCrop, to: localDrawRect),
            let redactedCrop = crop(image: redactedProcessingCrop, to: localDrawRect)
        else {
            logMosaicCacheEventIfNeeded(
                "local-preview-local-crop-failed",
                startTime: start,
                force: true,
                details: "kind=\(annotation.kind) localDrawRect=\(mosaicRectLogDescription(localDrawRect)) processingRect=\(mosaicRectLogDescription(processingRect))"
            )
            return nil
        }

        guard let preview = mosaicMaskedPreview(
            baseCrop: baseCrop,
            redactedCrop: redactedCrop,
            annotation: annotation,
            drawRect: drawRect
        ) else {
            logMosaicCacheEventIfNeeded(
                "local-preview-mask-failed",
                startTime: start,
                force: true,
                details: "kind=\(annotation.kind) drawRect=\(mosaicRectLogDescription(drawRect))"
            )
            return nil
        }
        mosaicDraftPreviewCache[cacheKey] = preview
        logMosaicCacheEventIfNeeded(
            "local-preview-render",
            startTime: start,
            force: !redactedCacheHit,
            details: "kind=\(annotation.kind) redaction=\(redaction.type):\(redaction.value) redactedCache=\(redactedCacheHit ? "hit" : "miss") drawRect=\(mosaicRectLogDescription(drawRect)) processingRect=\(mosaicRectLogDescription(processingRect))"
        )
        return (preview, drawRect)
    }

    private func mosaicLocalPreview(
        for annotation: CaptureAnnotation,
        existingAnnotations: [CaptureAnnotation],
        backgroundImage: NSImage
    ) -> (image: NSImage, drawRect: NSRect)? {
        let start = CFAbsoluteTimeGetCurrent()
        guard let redaction = annotation.mosaicRedaction else {
            return nil
        }

        let drawRect = mosaicDraftPreviewDrawRect(for: annotation, redaction: redaction)
        let processingRect = mosaicLocalPreviewProcessingRect(
            for: drawRect,
            redaction: redaction,
            existingAnnotations: existingAnnotations,
            imageSize: backgroundImage.size
        )
        let baseKey = [
            "local-base",
            mosaicCompositeKey(for: existingAnnotations, backgroundImage: backgroundImage),
            mosaicKey(processingRect),
        ].joined(separator: "|")
        let cacheKey = [
            baseKey,
            annotationCompositeKey(annotation),
            mosaicKey(drawRect),
        ].joined(separator: "|")
        if let cached = mosaicDraftPreviewCache[cacheKey] {
            logMosaicCacheEventIfNeeded(
                "local-preview-with-base-cache-hit",
                startTime: start,
                details: "kind=\(annotation.kind) existing=\(existingAnnotations.count) redaction=\(redaction.type):\(redaction.value) drawRect=\(mosaicRectLogDescription(drawRect))"
            )
            return (cached, drawRect)
        }

        guard let processingBaseCrop = localMosaicBaseCrop(
            existingAnnotations: existingAnnotations,
            backgroundImage: backgroundImage,
            processingRect: processingRect
        ) else {
            logMosaicCacheEventIfNeeded(
                "local-preview-with-base-crop-failed",
                startTime: start,
                force: true,
                details: "kind=\(annotation.kind) existing=\(existingAnnotations.count) processingRect=\(mosaicRectLogDescription(processingRect))"
            )
            return nil
        }

        if redaction.type == .pixelMosaic {
            guard let preview = renderedLocalMosaicPreview(
                annotation: annotation,
                processingBaseCrop: processingBaseCrop,
                processingRect: processingRect,
                drawRect: drawRect
            ) else {
                logMosaicCacheEventIfNeeded(
                    "local-preview-with-base-renderer-failed",
                    startTime: start,
                    force: true,
                    details: "kind=\(annotation.kind) existing=\(existingAnnotations.count) localDrawRect=\(mosaicRectLogDescription(drawRect))"
                )
                return nil
            }

            mosaicDraftPreviewCache[cacheKey] = preview
            logMosaicCacheEventIfNeeded(
                "local-preview-with-base-renderer-render",
                startTime: start,
                force: true,
                details: "kind=\(annotation.kind) existing=\(existingAnnotations.count) redaction=\(redaction.type):\(redaction.value) drawRect=\(mosaicRectLogDescription(drawRect)) processingRect=\(mosaicRectLogDescription(processingRect))"
            )
            return (preview, drawRect)
        }

        let redactedCropKey = [
            "crop",
            baseKey,
            "\(redaction.type)",
            "\(redaction.value)",
        ].joined(separator: "|")
        let redactedProcessingCrop: NSImage
        let redactedCacheHit: Bool
        if let cached = mosaicDraftRedactedBaseCache[redactedCropKey] {
            redactedProcessingCrop = cached
            redactedCacheHit = true
        } else {
            let redactedStart = CFAbsoluteTimeGetCurrent()
            mosaicDraftRedactedBaseRenderCount += 1
            redactedProcessingCrop = CaptureAnnotationRenderer.redactedPreview(image: processingBaseCrop, redaction: redaction)
            mosaicDraftRedactedBaseCache[redactedCropKey] = redactedProcessingCrop
            redactedCacheHit = false
            logMosaicCacheEventIfNeeded(
                "local-preview-with-base-redacted-crop-render",
                startTime: redactedStart,
                force: true,
                details: "existing=\(existingAnnotations.count) redaction=\(redaction.type):\(redaction.value) processingRect=\(mosaicRectLogDescription(processingRect))"
            )
        }

        let localDrawRect = NSRect(
            x: drawRect.minX - processingRect.minX,
            y: drawRect.minY - processingRect.minY,
            width: drawRect.width,
            height: drawRect.height
        )
        guard
            let baseCrop = crop(image: processingBaseCrop, to: localDrawRect),
            let redactedCrop = crop(image: redactedProcessingCrop, to: localDrawRect),
            let preview = mosaicMaskedPreview(
                baseCrop: baseCrop,
                redactedCrop: redactedCrop,
                annotation: annotation,
                drawRect: drawRect
            )
        else {
            logMosaicCacheEventIfNeeded(
                "local-preview-with-base-mask-failed",
                startTime: start,
                force: true,
                details: "kind=\(annotation.kind) existing=\(existingAnnotations.count) localDrawRect=\(mosaicRectLogDescription(localDrawRect))"
            )
            return nil
        }

        mosaicDraftPreviewCache[cacheKey] = preview
        logMosaicCacheEventIfNeeded(
            "local-preview-with-base-render",
            startTime: start,
            force: !redactedCacheHit,
            details: "kind=\(annotation.kind) existing=\(existingAnnotations.count) redaction=\(redaction.type):\(redaction.value) redactedCache=\(redactedCacheHit ? "hit" : "miss") drawRect=\(mosaicRectLogDescription(drawRect)) processingRect=\(mosaicRectLogDescription(processingRect))"
        )
        return (preview, drawRect)
    }

    private func renderedLocalMosaicPreview(
        annotation: CaptureAnnotation,
        processingBaseCrop: NSImage,
        processingRect: NSRect,
        drawRect: NSRect
    ) -> NSImage? {
        let shiftedAnnotation = shiftedOverlayAnnotation(annotation, by: processingRect.origin)
        let renderedProcessingCrop = CaptureAnnotationRenderer.render(
            image: processingBaseCrop,
            annotations: [shiftedAnnotation]
        )
        let localDrawRect = NSRect(
            x: drawRect.minX - processingRect.minX,
            y: drawRect.minY - processingRect.minY,
            width: drawRect.width,
            height: drawRect.height
        )
        mosaicDraftPreviewImageRenderCount += 1
        return crop(image: renderedProcessingCrop, to: localDrawRect)
    }

    private func localMosaicBaseCrop(
        existingAnnotations: [CaptureAnnotation],
        backgroundImage: NSImage,
        processingRect: NSRect
    ) -> NSImage? {
        let start = CFAbsoluteTimeGetCurrent()
        guard let backgroundCrop = crop(image: backgroundImage, to: processingRect) else {
            logMosaicCacheEventIfNeeded(
                "local-base-crop-failed",
                startTime: start,
                force: true,
                details: "existing=\(existingAnnotations.count) processingRect=\(mosaicRectLogDescription(processingRect))"
            )
            return nil
        }
        let shiftedAnnotations = existingAnnotations.map { shiftedOverlayAnnotation($0, by: processingRect.origin) }
#if DEBUG
        let logTime = ProcessInfo.processInfo.systemUptime
        if logTime - mosaicTextBaseLastLogTime >= 0.5 {
            mosaicTextBaseLastLogTime = logTime
            for (index, annotation) in existingAnnotations.enumerated() where annotation.kind == .text {
                NSLog(
                    "xxsnap mosaic text-base index=%ld overlayRect=%@ processingRect=%@ shiftedRect=%@",
                    index,
                    NSStringFromRect(overlayRect(fromLocalAnnotationRect: annotation.rect)),
                    NSStringFromRect(processingRect),
                    NSStringFromRect(shiftedAnnotations[index].rect)
                )
            }
        }
#endif
        let rendered = CaptureAnnotationRenderer.render(
            image: backgroundCrop,
            annotations: shiftedAnnotations
        )
        logMosaicCacheEventIfNeeded(
            "local-base-render",
            startTime: start,
            details: "existing=\(existingAnnotations.count) processingRect=\(mosaicRectLogDescription(processingRect))"
        )
        return rendered
    }

    private func mosaicLocalPreviewProcessingRect(
        for drawRect: NSRect,
        redaction: CaptureMosaicRedaction,
        existingAnnotations: [CaptureAnnotation],
        imageSize: NSSize
    ) -> NSRect {
        let imageBounds = NSRect(origin: .zero, size: imageSize)
        let baseRect = mosaicLocalPreviewProcessingRect(
            for: drawRect,
            redaction: redaction,
            imageSize: imageSize
        )
        var existingPadding: CGFloat = 0
        for annotation in existingAnnotations where isMosaicAnnotation(annotation) {
            guard
                let existingRedaction = annotation.mosaicRedaction,
                let clipBounds = mosaicDraftClipPath(for: annotation)?.bounds
            else {
                continue
            }

            let padding = mosaicRedactionInfluencePadding(for: existingRedaction)
            let influenceRect = clipBounds.insetBy(dx: -padding, dy: -padding)
            if influenceRect.intersects(drawRect) {
                existingPadding = max(existingPadding, padding)
            }
        }

        guard existingPadding > 0 else {
            return baseRect
        }
        let expanded = baseRect.insetBy(dx: -existingPadding, dy: -existingPadding).intersection(imageBounds)
        return expanded.isEmpty ? baseRect : expanded
    }

    private func mosaicLocalPreviewProcessingRect(
        for drawRect: NSRect,
        redaction: CaptureMosaicRedaction,
        imageSize: NSSize
    ) -> NSRect {
        let imageBounds = NSRect(origin: .zero, size: imageSize)
        guard redaction.type == .pixelMosaic else {
            return drawRect.intersection(imageBounds)
        }

        let block = CGFloat(max(1, redaction.value))
        guard block > 1 else {
            return drawRect.intersection(imageBounds)
        }

        let minX = floor(drawRect.minX / block) * block
        let maxX = ceil(drawRect.maxX / block) * block
        let top = imageSize.height - drawRect.maxY
        let bottom = imageSize.height - drawRect.minY
        let alignedTop = floor(top / block) * block
        let alignedBottom = ceil(bottom / block) * block
        let minY = imageSize.height - alignedBottom
        let maxY = imageSize.height - alignedTop
        let aligned = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let clipped = aligned.intersection(imageBounds)
        return clipped.isEmpty ? drawRect.intersection(imageBounds) : clipped
    }

    private func mosaicRedactionInfluencePadding(for redaction: CaptureMosaicRedaction) -> CGFloat {
        let value = CGFloat(max(1, redaction.value))
        switch redaction.type {
        case .gaussianBlur:
            return value * 3
        case .pixelMosaic:
            return value
        }
    }

    private func mosaicDraftPreviewBaseImage() -> NSImage {
        fullMosaicPreviewComposite(for: annotations)?.image ?? backgroundImage ?? NSImage(size: bounds.size)
    }

    private func mosaicDraftRedactedBaseImage(
        redaction: CaptureMosaicRedaction,
        existingAnnotations: [CaptureAnnotation],
        backgroundImage: NSImage
    ) -> NSImage {
        let source = mosaicRedactionSourceImage(
            existingAnnotations: existingAnnotations,
            fallbackKey: mosaicBackgroundKey(for: backgroundImage)
        )
        return mosaicRedactedBaseImage(
            baseImage: source.image,
            baseKey: source.key,
            redaction: redaction
        )
    }

    private func mosaicRedactionSourceImage(
        existingAnnotations: [CaptureAnnotation],
        fallbackKey: String
    ) -> (image: NSImage, key: String) {
        guard let backgroundImage else {
            return (mosaicDraftPreviewBaseImage(), "display|\(fallbackKey)")
        }

        let key = "display|" + mosaicCompositeKey(for: existingAnnotations, backgroundImage: backgroundImage)
        return (mosaicDraftPreviewBaseImage(), key)
    }

    private func mosaicRedactedBaseImage(
        baseImage: NSImage,
        baseKey: String,
        redaction: CaptureMosaicRedaction
    ) -> NSImage {
        let start = CFAbsoluteTimeGetCurrent()
        let cacheKey = [
            baseKey,
            "\(redaction.type)",
            "\(redaction.value)",
        ].joined(separator: "|")
        if let cached = mosaicDraftRedactedBaseCache[cacheKey] {
            logMosaicCacheEventIfNeeded(
                "redacted-base-cache-hit",
                startTime: start,
                details: "redaction=\(redaction.type):\(redaction.value) image=\(mosaicRectLogDescription(NSRect(origin: .zero, size: baseImage.size)))"
            )
            return cached
        }

        mosaicDraftRedactedBaseRenderCount += 1
        let redacted = CaptureAnnotationRenderer.redactedPreview(image: baseImage, redaction: redaction)
        mosaicDraftRedactedBaseCache[cacheKey] = redacted
        logMosaicCacheEventIfNeeded(
            "redacted-base-render",
            startTime: start,
            force: true,
            details: "redaction=\(redaction.type):\(redaction.value) image=\(mosaicRectLogDescription(NSRect(origin: .zero, size: baseImage.size)))"
        )
        return redacted
    }

    private func mosaicMaskedPreview(
        baseCrop: NSImage,
        redactedCrop: NSImage,
        annotation: CaptureAnnotation,
        drawRect: NSRect
    ) -> NSImage? {
        guard !drawRect.isEmpty else {
            return nil
        }

        mosaicDraftPreviewImageRenderCount += 1
        let image = NSImage(size: drawRect.size)
        image.lockFocus()
        let graphicsContext = NSGraphicsContext.current
        let previousInterpolation = graphicsContext?.imageInterpolation
        graphicsContext?.imageInterpolation = .none
        defer {
            graphicsContext?.imageInterpolation = previousInterpolation ?? .default
            image.unlockFocus()
        }
        let target = NSRect(origin: .zero, size: drawRect.size)
        baseCrop.draw(in: target, from: NSRect(origin: .zero, size: baseCrop.size), operation: .copy, fraction: 1)

        NSGraphicsContext.saveGraphicsState()
        if let clip = mosaicDraftClipPath(for: annotation)?.copy() as? NSBezierPath {
            let transform = AffineTransform(translationByX: -drawRect.minX, byY: -drawRect.minY)
            clip.transform(using: transform)
            clip.addClip()
        }
        redactedCrop.draw(in: target, from: NSRect(origin: .zero, size: redactedCrop.size), operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return image
    }

    private func mosaicDraftPreviewDrawRect(for annotation: CaptureAnnotation, redaction: CaptureMosaicRedaction) -> NSRect {
        guard let clipBounds = mosaicDraftClipPath(for: annotation)?.bounds else {
            return bounds
        }

        let padding: CGFloat
        switch redaction.type {
        case .gaussianBlur:
            padding = CGFloat(max(1, redaction.value)) * 3
        case .pixelMosaic:
            padding = CGFloat(max(1, redaction.value))
        }

        let drawRect = clipBounds.insetBy(dx: -padding, dy: -padding).intersection(bounds)
        guard !drawRect.isEmpty else {
            return bounds
        }
        return pixelAlignedPreviewRect(drawRect)
    }

    private func pixelAlignedPreviewRect(_ rect: NSRect) -> NSRect {
        guard let backgroundImage else {
            return rect.integral.intersection(bounds)
        }

        let scaleX = CGFloat(backgroundBitmap?.pixelsWide ?? Int(backgroundImage.size.width.rounded()))
            / max(backgroundImage.size.width, 1)
        let scaleY = CGFloat(backgroundBitmap?.pixelsHigh ?? Int(backgroundImage.size.height.rounded()))
            / max(backgroundImage.size.height, 1)
        let aligned = NSRect(
            x: floor(rect.minX * scaleX) / scaleX,
            y: floor(rect.minY * scaleY) / scaleY,
            width: (ceil(rect.maxX * scaleX) - floor(rect.minX * scaleX)) / scaleX,
            height: (ceil(rect.maxY * scaleY) - floor(rect.minY * scaleY)) / scaleY
        )
        let clipped = aligned.intersection(bounds)
        return clipped.isEmpty ? rect : clipped
    }

    private func mosaicDraftClipPath(for annotation: CaptureAnnotation) -> NSBezierPath? {
        switch annotation.kind {
        case .mosaicStroke:
            guard let mosaicStroke = overlayMosaicStroke(fromLocalMosaicStroke: annotation.mosaicStroke),
                  let first = mosaicStroke.points.first else {
                return nil
            }

            let width = max(1, annotation.style.strokeWidth)
            if mosaicStroke.points.count == 1 {
                return NSBezierPath(ovalIn: NSRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width))
            }

            let path = CGMutablePath()
            path.move(to: first)
            for point in mosaicStroke.points.dropFirst() {
                path.addLine(to: point)
            }
            let strokePath = path.copy(
                strokingWithWidth: width,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 4
            )
            return NSBezierPath(cgPath: strokePath)
        case .mosaicRectangle:
            let rect = overlayRect(fromLocalAnnotationRect: annotation.rect)
            return rotatedRectanglePath(for: rect, angle: annotation.rotationAngle)
        default:
            return nil
        }
    }

    private func resetMosaicPreviewCaches() {
        if hasMosaicPerformanceWork || !mosaicCompositeCache.isEmpty || !mosaicDraftPreviewCache.isEmpty || !mosaicDraftRedactedBaseCache.isEmpty {
            logMosaicPerformanceEvent(
                "reset-all-caches",
                details: "before(composite=\(mosaicCompositeCache.count),draft=\(mosaicDraftPreviewCache.count),redacted=\(mosaicDraftRedactedBaseCache.count))"
            )
        }
        mosaicCompositeCache.removeAll()
        resetMosaicRedactionPreviewCaches()
    }

    private func resetMosaicRedactionPreviewCaches() {
        if hasMosaicPerformanceWork || !mosaicDraftPreviewCache.isEmpty || !mosaicDraftRedactedBaseCache.isEmpty {
            logMosaicPerformanceEvent(
                "reset-redaction-caches",
                details: "before(draft=\(mosaicDraftPreviewCache.count),redacted=\(mosaicDraftRedactedBaseCache.count))"
            )
        }
        mosaicDraftPreviewCache.removeAll()
        mosaicDraftRedactedBaseCache.removeAll()
    }

    private func crop(image: NSImage, to rect: NSRect) -> NSImage? {
        let normalizedRect = rect.standardized
        let imageBounds = NSRect(origin: .zero, size: image.size)
        let clippedRect = normalizedRect.intersection(imageBounds)
        guard !clippedRect.isEmpty else {
            return nil
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let pixelRect = CGRect(
            x: clippedRect.minX * scaleX,
            y: (image.size.height - clippedRect.maxY) * scaleY,
            width: clippedRect.width * scaleX,
            height: clippedRect.height * scaleY
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard !pixelRect.isEmpty, let croppedImage = cgImage.cropping(to: pixelRect) else {
            return nil
        }

        return NSImage(cgImage: croppedImage, size: clippedRect.size)
    }

    private func pixelAlignedCrop(image: NSImage, to rect: NSRect) -> PixelAlignedCrop? {
        let imageBounds = NSRect(origin: .zero, size: image.size)
        let clippedRect = rect.standardized.intersection(imageBounds)
        guard !clippedRect.isEmpty,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let imagePixelBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let pixelRect = CGRect(
            x: clippedRect.minX * scaleX,
            y: (image.size.height - clippedRect.maxY) * scaleY,
            width: clippedRect.width * scaleX,
            height: clippedRect.height * scaleY
        )
        .integral
        .intersection(imagePixelBounds)
        guard !pixelRect.isEmpty,
              let croppedImage = cgImage.cropping(to: pixelRect)
        else {
            return nil
        }

        let drawRect = NSRect(
            x: pixelRect.minX / scaleX,
            y: image.size.height - pixelRect.maxY / scaleY,
            width: pixelRect.width / scaleX,
            height: pixelRect.height / scaleY
        )
        return PixelAlignedCrop(
            image: NSImage(cgImage: croppedImage, size: drawRect.size),
            pixelRect: pixelRect,
            drawRect: drawRect
        )
    }

    private func localPoint(fromOverlayPoint point: NSPoint, selectionRect: NSRect) -> NSPoint {
        NSPoint(x: point.x - selectionRect.minX, y: point.y - selectionRect.minY)
    }

    private func overlayPoint(fromLocalPoint point: NSPoint, selectionRect: NSRect) -> NSPoint {
        NSPoint(x: selectionRect.minX + point.x, y: selectionRect.minY + point.y)
    }

    private func offsetArrowLine(_ arrowLine: CaptureArrowLine, dx: CGFloat, dy: CGFloat) -> CaptureArrowLine {
        CaptureArrowLine(
            start: NSPoint(x: arrowLine.start.x + dx, y: arrowLine.start.y + dy),
            end: NSPoint(x: arrowLine.end.x + dx, y: arrowLine.end.y + dy),
            control: NSPoint(x: arrowLine.control.x + dx, y: arrowLine.control.y + dy),
            startArrowType: arrowLine.startArrowType,
            endArrowType: arrowLine.endArrowType
        )
    }

    private func offsetBrushPath(_ brushPath: CaptureBrushPath, dx: CGFloat, dy: CGFloat) -> CaptureBrushPath {
        CaptureBrushPath(
            points: brushPath.points.map { NSPoint(x: $0.x + dx, y: $0.y + dy) }
        )
    }

    private func offsetMarkerLine(_ markerLine: CaptureMarkerLine, dx: CGFloat, dy: CGFloat) -> CaptureMarkerLine {
        CaptureMarkerLine(
            start: NSPoint(x: markerLine.start.x + dx, y: markerLine.start.y + dy),
            end: NSPoint(x: markerLine.end.x + dx, y: markerLine.end.y + dy)
        )
    }

    private func offsetMosaicStroke(_ stroke: CaptureMosaicStroke, dx: CGFloat, dy: CGFloat) -> CaptureMosaicStroke {
        CaptureMosaicStroke(
            points: stroke.points.map { NSPoint(x: $0.x + dx, y: $0.y + dy) }
        )
    }

    private func brushPathContains(_ point: NSPoint, path: CaptureBrushPath, hitOutset: CGFloat) -> Bool {
        guard let first = path.points.first else {
            return false
        }
        if path.points.count == 1 {
            return distance(from: point, to: first) <= hitOutset
        }

        for (start, end) in zip(path.points, path.points.dropFirst()) {
            if SelectionToolbarState.distanceFromSegment(point: point, start: start, end: end) <= hitOutset {
                return true
            }
        }
        return false
    }

    private func mosaicStrokeContains(_ point: NSPoint, stroke: CaptureMosaicStroke, hitOutset: CGFloat) -> Bool {
        guard let first = stroke.points.first else {
            return false
        }
        if stroke.points.count == 1 {
            return distance(from: point, to: first) <= hitOutset
        }

        for (start, end) in zip(stroke.points, stroke.points.dropFirst()) {
            if SelectionToolbarState.distanceFromSegment(point: point, start: start, end: end) <= hitOutset {
                return true
            }
        }
        return false
    }

    private func mosaicRectangleRotationHitTarget(at point: NSPoint) -> Int? {
        guard interactionMode == .annotating else {
            return nil
        }
        for index in annotations.indices.reversed() where annotationIsEditable(at: index) && annotationKindSupportsRotationHandle(annotations[index].kind) {
            if annotations[index].kind == .text, selectedAnnotationIndex != index {
                continue
            }
            guard activeToolCanEdit(annotationKind: annotations[index].kind),
                  let handle = mosaicRectangleRotationHandlePoint(for: annotations[index]),
                  distance(from: point, to: handle) <= 10 else {
                continue
            }
            return index
        }
        return nil
    }

    private func mosaicRectangleRotationHandlePoint(for annotation: CaptureAnnotation) -> NSPoint? {
        guard annotationKindSupportsRotationHandle(annotation.kind) else {
            return nil
        }
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
        guard rect.width >= 1, rect.height >= 1 else {
            return nil
        }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let top = rotatedPoint(NSPoint(x: rect.midX, y: rect.maxY), around: center, angle: annotation.rotationAngle)
        let dx = top.x - center.x
        let dy = top.y - center.y
        let length = max(1, hypot(dx, dy))
        let distance: CGFloat = 20
        return NSPoint(x: top.x + dx / length * distance, y: top.y + dy / length * distance)
    }

    private func mosaicRectangleCenter(for annotation: CaptureAnnotation) -> NSPoint {
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    private func annotationKindSupportsRotationHandle(_ kind: CaptureAnnotationKind) -> Bool {
        kind == .mosaicRectangle || kind == .text
    }

    private func rotatedAnnotationRectContains(_ point: NSPoint, annotation: CaptureAnnotation, hitOutset: CGFloat) -> Bool {
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized.insetBy(dx: -hitOutset, dy: -hitOutset)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let unrotatedPoint = rotatedPoint(point, around: center, angle: -annotation.rotationAngle)
        return rect.contains(unrotatedPoint)
    }

    private func rotatedAnnotationBorderContains(_ point: NSPoint, annotation: CaptureAnnotation, hitOutset: CGFloat) -> Bool {
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let unrotatedPoint = rotatedPoint(point, around: center, angle: -annotation.rotationAngle)
        let outerRect = rect.insetBy(dx: -hitOutset, dy: -hitOutset)
        let innerRect = rect.insetBy(dx: hitOutset, dy: hitOutset)
        guard outerRect.contains(unrotatedPoint) else {
            return false
        }
        guard innerRect.width > 0, innerRect.height > 0 else {
            return true
        }
        return !innerRect.contains(unrotatedPoint)
    }

    private func rotatedRectanglePath(for rect: NSRect, angle: CGFloat) -> NSBezierPath {
        guard abs(angle) >= 0.001 else {
            return NSBezierPath(rect: rect)
        }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let points = [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.maxY),
        ].map { rotatedPoint($0, around: center, angle: angle) }
        let path = NSBezierPath()
        guard let first = points.first else {
            return path
        }
        path.move(to: first)
        points.dropFirst().forEach { path.line(to: $0) }
        path.close()
        return path
    }

    private func rotatedPoint(_ point: NSPoint, around center: NSPoint, angle: CGFloat) -> NSPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosine = cos(angle)
        let sine = sin(angle)
        return NSPoint(
            x: center.x + dx * cosine - dy * sine,
            y: center.y + dx * sine + dy * cosine
        )
    }

    private func projectedDistance(_ point: NSPoint, onto axis: NSPoint) -> CGFloat {
        point.x * axis.x + point.y * axis.y
    }

    private func angle(from center: NSPoint, to point: NSPoint) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x)
    }

    private func distance(from first: NSPoint, to second: NSPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func resizeHandleCenters(for rect: NSRect, kind: CaptureAnnotationKind, rotationAngle: CGFloat = 0) -> [NSPoint] {
        let outline = NSRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - 1), height: max(0, rect.height - 1))
        let centers = [
            NSPoint(x: outline.minX, y: outline.maxY),
            NSPoint(x: outline.midX, y: outline.maxY),
            NSPoint(x: outline.maxX, y: outline.maxY),
            NSPoint(x: outline.minX, y: outline.midY),
            NSPoint(x: outline.maxX, y: outline.midY),
            NSPoint(x: outline.minX, y: outline.minY),
            NSPoint(x: outline.midX, y: outline.minY),
            NSPoint(x: outline.maxX, y: outline.minY),
        ]
        guard abs(rotationAngle) >= 0.001 else {
            return centers
        }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return centers.map { rotatedPoint($0, around: center, angle: rotationAngle) }
    }

    private func clamp(_ point: NSPoint, to rect: NSRect) -> NSPoint {
        NSPoint(
            x: min(rect.maxX, max(rect.minX, point.x)),
            y: min(rect.maxY, max(rect.minY, point.y))
        )
    }

    private func clamp(rect: NSRect, inside bounds: NSRect) -> NSRect {
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

    private func screenBounds(containing rect: NSRect) -> NSRect {
        if configuration.usesWindowBoundsForLayout {
            return bounds
        }
        guard let window else {
            return bounds
        }

        let rect = rect.standardized
        let centerInScreen = window.convertToScreen(NSRect(
            x: rect.midX,
            y: rect.midY,
            width: 1,
            height: 1
        )).origin
        let screen = NSScreen.screens.first(where: { $0.frame.contains(centerInScreen) }) ?? window.screen

        guard let screen else {
            return bounds
        }

        return NSRect(
            x: screen.frame.minX - window.frame.minX,
            y: screen.frame.minY - window.frame.minY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    private var safeLayoutBounds: NSRect {
        if configuration.usesWindowBoundsForLayout {
            return bounds
        }
        guard let window else {
            return bounds
        }
        let visibleFrame = SelectionOverlayWindow.visibleDesktopFrame()
        return NSRect(
            x: visibleFrame.minX - window.frame.minX,
            y: visibleFrame.minY - window.frame.minY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }
}
