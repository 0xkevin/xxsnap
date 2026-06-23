import AppKit

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

private extension NSCursor {
    static func sniporyBrushRotationHandle(angle: CGFloat) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let hotSpot = brushRotationHandleCenter
        let image = NSImage(size: size)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.translateBy(x: hotSpot.x, y: hotSpot.y)
            context.rotate(by: angle)
            context.scaleBy(x: 0.5, y: 0.5)
            context.translateBy(x: -hotSpot.x, y: -hotSpot.y)
        }
        drawBrushRotationHandleIcon()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: hotSpot)
    }

    static let brushRotationHandleCenter = NSPoint(x: 11.34, y: 11.6)
    static let brushRotationHandleRadius: CGFloat = 4.9
    static let brushRotationHandleColor = NSColor.systemBlue

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

    static let sniporyMove: NSCursor = {
        let size = NSSize(width: 28, height: 28)
        if let symbol = NSImage(
            systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
            accessibilityDescription: "Move"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .light)) {
            let image = NSImage(size: size)
            image.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            symbol.draw(in: NSRect(x: 3, y: 3, width: 22, height: 22))
            NSColor.black.setFill()
            NSRect(x: 3, y: 3, width: 22, height: 22).fill(using: .sourceAtop)
            image.unlockFocus()
            return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
        }

        let image = NSImage(size: size)
        image.lockFocus()

        let outline = NSBezierPath()
        drawMoveCursor(into: outline, offset: .zero)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        outline.lineWidth = 4
        outline.lineCapStyle = .round
        outline.lineJoinStyle = .round
        outline.stroke()

        let path = NSBezierPath()
        drawMoveCursor(into: path, offset: .zero)
        NSColor.black.setStroke()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()

    static let sniporyBrush: NSCursor = {
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
            image.unlockFocus()
            return NSCursor(image: image, hotSpot: tipHotSpot)
        }

        // Ultimate fallback: standard arrow
        return NSCursor.arrow
    }()

    static func sniporyMarker(color: NSColor, strokeWidth: CGFloat) -> NSCursor {
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
    private var didCompleteSelection = false

    init(
        backgroundImage: NSImage?,
        settings: AppSettings = .default,
        featureGate: FeatureGate = FeatureGate(license: LicenseState()),
        selectionHandler: @escaping (CaptureSelectionResult?) -> Void
    ) {
        let frame = Self.desktopFrame()

        self.selectionHandler = selectionHandler

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
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let overlayView = SelectionOverlayView(
            frame: NSRect(origin: .zero, size: frame.size),
            backgroundImage: backgroundImage,
            settings: settings,
            featureGate: featureGate
        )
        overlayView.selectionDidFinish = { [weak self] result in
            self?.completeSelection(with: result)
        }

        contentView = overlayView
        acceptsMouseMovedEvents = true
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
    }

    override func cancelOperation(_ sender: Any?) {
        completeSelection(with: nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelOperation(nil)
            return
        }

        if let overlayView = contentView as? SelectionOverlayView,
           overlayView.handleKeyDown(event) {
            return
        }

        super.keyDown(with: event)
    }

#if DEBUG
    func test_setLockedSelectionRect(_ rect: NSRect) {
        (contentView as? SelectionOverlayView)?.test_setLockedSelectionRect(rect)
    }

    func test_activateShapeTool(_ shape: CaptureAnnotationKind) {
        (contentView as? SelectionOverlayView)?.test_activateShapeTool(shape)
    }

    func test_toggleShapeTool(_ shape: CaptureAnnotationKind) {
        (contentView as? SelectionOverlayView)?.test_toggleShapeTool(shape)
    }

    func test_setCurrentStrokePattern(_ pattern: CaptureStrokePattern) {
        (contentView as? SelectionOverlayView)?.test_setCurrentStrokePattern(pattern)
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

    func test_mouseDown(at point: NSPoint) {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return
        }
        overlayView.mouseDown(with: test_mouseEvent(type: .leftMouseDown, at: point))
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

    func test_keyDown(keyCode: UInt16, charactersIgnoringModifiers: String = "") {
        keyDown(with: test_keyEvent(keyCode: keyCode, charactersIgnoringModifiers: charactersIgnoringModifiers))
    }

    func test_cursorStyle(at point: NSPoint) -> SelectionToolbarState.OverlayCursorStyle? {
        (contentView as? SelectionOverlayView)?.test_cursorStyle(at: point)
    }

    func test_mainToolbarDragPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_mainToolbarDragPoint()
    }

    func test_annotationRect(at index: Int) -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_annotationRect(at: index)
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

    func test_markerToolbarButtonPoint() -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_markerToolbarButtonPoint()
    }

    func test_optionsStrokeWidthPoint(at index: Int) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_optionsStrokeWidthPoint(at: index)
    }

    func test_optionsPaletteColorPoint(at index: Int) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_optionsPaletteColorPoint(at: index)
    }

    func test_annotationStyle(at index: Int) -> CaptureAnnotationStyle? {
        (contentView as? SelectionOverlayView)?.test_annotationStyle(at: index)
    }

    var test_selectedAnnotationKind: CaptureAnnotationKind? {
        (contentView as? SelectionOverlayView)?.test_selectedAnnotationKind
    }

    var test_selectedAnnotationShowsOutline: Bool {
        (contentView as? SelectionOverlayView)?.test_selectedAnnotationShowsOutline ?? false
    }

    var test_annotationCount: Int {
        (contentView as? SelectionOverlayView)?.test_annotationCount ?? 0
    }

    var test_lockedSelectionRect: NSRect? {
        (contentView as? SelectionOverlayView)?.test_lockedSelectionRect
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

    private func test_mouseEvent(type: NSEvent.EventType, at point: NSPoint, modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func test_keyEvent(keyCode: UInt16, charactersIgnoringModifiers: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
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
        (contentView as? SelectionOverlayView)?.prepareForCompletion()
        makeFirstResponder(nil)
        orderOut(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.selectionHandler(result)
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

private final class SelectionOverlayView: NSView {
    var selectionDidFinish: ((CaptureSelectionResult?) -> Void)?
    private let backgroundImage: NSImage?
    private let backgroundBitmap: NSBitmapImageRep?
    private let settings: AppSettings
    private let featureGate: FeatureGate
    private let colorSamplerSize = NSSize(width: 184, height: 188)
    private var strokePatternOptions: [SelectionToolbarState.StrokePatternOption] {
        SelectionToolbarState.strokePatternOptions(
            canUsePremiumStrokePatterns: featureGate.isEnabled(.sketchStrokePatterns),
            mode: optionsToolbarMode
        )
    }

    init(frame frameRect: NSRect, backgroundImage: NSImage?, settings: AppSettings, featureGate: FeatureGate) {
        self.backgroundImage = backgroundImage
        self.settings = settings
        self.featureGate = featureGate
        if let cgImage = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            self.backgroundBitmap = NSBitmapImageRep(cgImage: cgImage)
        } else {
            self.backgroundBitmap = nil
        }
        super.init(frame: frameRect)
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
        case movingShape
        case movingSelection
        case resizingShape
        case resizingArrowLine
        case resizingMarkerLine
        case rotatingBrush
        case resizingSelection
    }

    private enum ToolbarButton {
        case rectangle
        case polyline
        case pen
        case marker
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
        case settings
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
    private var hoveredTooltip: (text: String, anchor: NSRect)?
    private var interactionMode = InteractionMode.selecting
    private var selectionStartPoint: NSPoint?
    private var selectionCurrentPoint: NSPoint?
    private var lockedSelectionRect: NSRect?
    private var shapeStartPoint: NSPoint?
    private var shapeCurrentPoint: NSPoint?
    private var brushDraftPoints: [NSPoint] = []
    private var annotations: [CaptureAnnotation] = []
    private var redoAnnotations: [CaptureAnnotation] = []
    private var selectedAnnotationIndex: Int?
    private var movingAnnotationStartRect: NSRect?
    private var movingAnnotationStartArrowLine: CaptureArrowLine?
    private var movingAnnotationStartBrushPath: CaptureBrushPath?
    private var movingAnnotationStartMarkerLine: CaptureMarkerLine?
    private var movingAnnotationOffset = NSPoint.zero
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
    private var currentShapeKind = CaptureAnnotationKind.rectangle
    private var activeShapeKind: CaptureAnnotationKind?
    private var isShapeToolActive = false
    private var currentStyle = CaptureAnnotationStyle()
    private var currentStartArrowType = CaptureArrowType.none
    private var currentEndArrowType = CaptureArrowType.normal
    private var customColor: NSColor?
    private var isCustomColorSwatchActive = false
    private var showsCornerRadiusPanel = false
    private var showsStrokeStyleMenu = false
    private var showsStartArrowTypeMenu = false
    private var showsEndArrowTypeMenu = false
    private var sampledPointerPoint: NSPoint?
    private var sampledColor: NSColor?
    private var colorSamplerCopyMode: SelectionToolbarState.ColorSamplerCopyMode = .hex
    private var colorSamplerCopySuccessUntil: Date?
    private var colorSamplerCopySuccessTimer: Timer?
    private var wasShiftDown = false

    override var acceptsFirstResponder: Bool {
        true
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
        hoveredWindowRect = nil
        displayedWindowRect = nil
        hoverAnimationTimer?.invalidate()
        hoverAnimationTimer = nil
        hoveredTooltip = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    deinit {
        hoverAnimationTimer?.invalidate()
        colorSamplerCopySuccessTimer?.invalidate()
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
    }

    func prepareForCompletion() {
        closeCustomColorPanel()
        colorSamplerCopySuccessTimer?.invalidate()
        selectionDidFinish = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        drawOverlay()

        guard let selectionRect else {
            return
        }

        drawSelectionBorder(selectionRect)
        drawSelectionHandles(selectionRect)
        drawMeasurementLabel(selectionRect)
        drawColorSamplerIfNeeded()

        guard lockedSelectionRect != nil else {
            return
        }

        drawAnnotations()
        drawDraftAnnotation()
        drawMainToolbar(for: selectionRect)
        drawOptionsToolbar(for: selectionRect)

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
        drawTooltipIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        NSLog("snipory overlay mouseDown mode=%@ point=(%.0f, %.0f)", "\(interactionMode)", point.x, point.y)

        switch interactionMode {
        case .selecting:
            pendingWindowSelectionRect = hoveredWindowRect?.contains(point) == true ? hoveredWindowRect : nil
            selectionStartPoint = point
            selectionCurrentPoint = point
            updateColorSampler(at: point)
        case .annotating, .drawingShape, .draggingToolbar, .draggingCornerRadius, .movingShape, .movingSelection, .resizingShape, .resizingArrowLine, .resizingMarkerLine, .rotatingBrush, .resizingSelection:
            handleAnnotatingMouseDown(at: point)
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

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
            appendBrushDraftPointIfNeeded(clampedPoint, modifierFlags: event.modifierFlags)
        case .draggingToolbar:
            updateDraggingToolbar(to: point)
        case .annotating:
            if isShapeToolActive {
                let clampedPoint = clamp(point, to: bounds)
                shapeStartPoint = shapeStartPoint ?? clampedPoint
                shapeCurrentPoint = draftEndPoint(rawEnd: clampedPoint, modifierFlags: event.modifierFlags)
                if currentShapeKind == .brush, brushDraftPoints.isEmpty {
                    brushDraftPoints = [shapeStartPoint ?? clampedPoint, clampedPoint]
                }
                appendBrushDraftPointIfNeeded(clampedPoint, modifierFlags: event.modifierFlags)
                interactionMode = .drawingShape
                NSLog("snipory overlay recovered drawing from drag point=(%.0f, %.0f)", point.x, point.y)
            } else {
                startSelectionMoveIfPossible(at: point)
                if interactionMode == .movingSelection {
                    updateMovingSelection(to: point)
                }
            }
        case .draggingCornerRadius:
            updateCornerRadius(from: point)
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
        case .resizingSelection:
            updateResizingSelection(to: point)
        }

        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHoverState(at: point)
        updateColorSampler(at: point)
        refreshCursor(at: point)
    }

    private func cursorStyle(at point: NSPoint) -> SelectionToolbarState.OverlayCursorStyle {
        let isInsideSelection = cursorSelectionRect?.standardized.contains(point) == true
        let selectionResizeHandle = interactionMode == .annotating ? selectionResizeHandle(at: point) : nil
        let shapeResizeHandle = interactionMode == .annotating ? resizeHandle(at: point)?.toolbarStateHandle : nil
        let isAnnotationBorder = interactionMode == .annotating && annotationIndexForBorder(at: point) != nil

        if interactionMode == .movingShape {
            return .move
        }

        if interactionMode == .annotating, let arrowHit = arrowLineHitTarget(at: point) {
            switch arrowHit.target {
            case .start, .end:
                return .resizeUpDown
            case .control, .body:
                return .move
            case .none:
                break
            }
        }

        if interactionMode == .rotatingBrush {
            return .rotationHandle
        }

        if interactionMode == .resizingMarkerLine {
            return .rotationHandle
        }

        if interactionMode == .annotating, markerRotationHitTarget(at: point) != nil {
            return .rotationHandle
        }

        if interactionMode == .annotating, brushRotationHitTarget(at: point) != nil {
            return .rotationHandle
        }

        if let shapeResizeHandle {
            return SelectionToolbarState.overlayCursorStyle(for: shapeResizeHandle)
        }

        if isAnnotationBorder {
            return .move
        }

        if let selectionResizeHandle {
            return SelectionToolbarState.overlayCursorStyle(for: selectionResizeHandle)
        }

        if isShapeToolActive, !isInsideSelection {
            return .arrow
        }

        if !isShapeToolActive, isMainToolbarDragPoint(point) {
            return .move
        }

        return SelectionToolbarState.overlayCursorStyle(
            isSelecting: interactionMode == .selecting,
            isToolbarOrPanelPoint: isToolbarOrPanelPoint(point),
            resizeHandle: nil,
            selectionResizeHandle: nil,
            isAnnotationBorder: false,
            isInsideSelection: isInsideSelection,
            isShapeToolActive: isShapeToolActive,
            currentShapeKind: currentShapeKind
        )
    }

    private func refreshCursor(at point: NSPoint) {
        if let angle = brushRotationCursorAngle(at: point) {
            NSCursor.sniporyBrushRotationHandle(angle: angle).set()
            return
        }
        setCursor(cursorStyle(at: point))
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

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        NSLog("snipory overlay mouseUp mode=%@ point=(%.0f, %.0f)", "\(interactionMode)", point.x, point.y)

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
                NSLog("snipory overlay window selection locked rect=(%.0f, %.0f, %.0f, %.0f)", pendingWindowSelectionRect.minX, pendingWindowSelectionRect.minY, pendingWindowSelectionRect.width, pendingWindowSelectionRect.height)
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
            NSLog("snipory overlay selection locked rect=(%.0f, %.0f, %.0f, %.0f)", selectionRect.minX, selectionRect.minY, selectionRect.width, selectionRect.height)
        case .drawingShape:
            let clampedPoint = clamp(point, to: bounds)
            shapeCurrentPoint = draftEndPoint(rawEnd: clampedPoint, modifierFlags: event.modifierFlags)
            appendBrushDraftPointIfNeeded(clampedPoint, modifierFlags: event.modifierFlags)
            if let draft = draftAnnotation, isUsableDraftAnnotation(draft) {
                annotations.append(draft)
                selectedAnnotationIndex = annotations.indices.last
                currentShapeKind = draft.kind
                currentStyle = draft.style
                activeShapeKind = draft.kind
                redoAnnotations.removeAll()
                NSLog("snipory overlay added annotation count=%ld rect=(%.0f, %.0f, %.0f, %.0f)", annotations.count, draft.rect.minX, draft.rect.minY, draft.rect.width, draft.rect.height)
            }
            shapeStartPoint = nil
            shapeCurrentPoint = nil
            brushDraftPoints.removeAll()
            interactionMode = .annotating
        case .draggingToolbar:
            updateDraggingToolbar(to: point)
            commitToolbarDrag()
            interactionMode = .annotating
        case .draggingCornerRadius:
            updateCornerRadius(from: point)
            interactionMode = .annotating
        case .movingShape:
            commitSelectedShapePreview()
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
            NSCursor.sniporyBrush.set()
            needsDisplay = true
            return
        case .resizingSelection:
            commitSelectionResize()
            interactionMode = .annotating
        case .annotating:
            break
        }

        invalidateCursorRectsAndRefresh(at: point)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyDown(event) {
            return
        }

        super.keyDown(with: event)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            selectionDidFinish?(nil)
            return true
        }

        if event.keyCode == 51, deleteSelectedAnnotation() {
            return true
        }

        if event.charactersIgnoringModifiers == "z", event.modifierFlags.contains(.command), event.modifierFlags.contains(.shift) {
            if isToolbarButtonEnabled(.redo) {
                redoLastAnnotation()
            }
            return true
        }

        if event.charactersIgnoringModifiers == "z", event.modifierFlags.contains(.command) {
            if isToolbarButtonEnabled(.undo) {
                undoLastAnnotation()
            }
            return true
        }

        if event.charactersIgnoringModifiers == "c", event.modifierFlags.contains(.command) {
            finish(action: .copy)
            return true
        }

        if event.charactersIgnoringModifiers == "s", event.modifierFlags.contains(.command) {
            finish(action: .save)
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

    override func flagsChanged(with event: NSEvent) {
        let isShiftDown = event.modifierFlags.contains(.shift)
        if isShiftDown, !wasShiftDown, sampledColor != nil || sampledPointerPoint != nil {
            colorSamplerCopyMode = SelectionToolbarState.toggledColorSamplerCopyMode(from: colorSamplerCopyMode)
            needsDisplay = true
        }
        wasShiftDown = isShiftDown
        super.flagsChanged(with: event)
    }

    override func resetCursorRects() {
        let defaultCursor = interactionMode == .selecting ? NSCursor.crosshair : .arrow
        addCursorRect(bounds, cursor: defaultCursor)
        if let lockedSelectionRect, isShapeToolActive {
            let drawingRect = lockedSelectionRect.standardized.insetBy(dx: 12, dy: 12)
            if drawingRect.width > 0, drawingRect.height > 0 {
                addCursorRect(drawingRect, cursor: cursorRectCursorForActiveShapeTool())
            }
        }
        if let lockedSelectionRect, interactionMode == .annotating {
            addSelectionResizeCursorRects(for: lockedSelectionRect.standardized)
        }
    }

    private func cursorRectCursorForActiveShapeTool() -> NSCursor {
        if currentShapeKind == .brush {
            return NSCursor.sniporyBrush
        }
        if currentShapeKind == .marker {
            return NSCursor.sniporyMarker(color: currentStyle.strokeColor, strokeWidth: currentStyle.strokeWidth)
        }
        return NSCursor.crosshair
    }

    private func addSelectionResizeCursorRects(for rect: NSRect) {
        let outset: CGFloat = 12
        let cornerLength = min(max(outset * 2, 18), min(rect.width, rect.height) / 2)
        addCursorRectClipped(
            NSRect(x: rect.minX - outset, y: rect.maxY - cornerLength, width: cornerLength + outset, height: cornerLength + outset),
            cursor: NSCursor.frameResize(position: .topLeft, directions: .all)
        )
        addCursorRectClipped(
            NSRect(x: rect.maxX - cornerLength, y: rect.maxY - cornerLength, width: cornerLength + outset, height: cornerLength + outset),
            cursor: NSCursor.frameResize(position: .topRight, directions: .all)
        )
        addCursorRectClipped(
            NSRect(x: rect.minX - outset, y: rect.minY - outset, width: cornerLength + outset, height: cornerLength + outset),
            cursor: NSCursor.frameResize(position: .bottomLeft, directions: .all)
        )
        addCursorRectClipped(
            NSRect(x: rect.maxX - cornerLength, y: rect.minY - outset, width: cornerLength + outset, height: cornerLength + outset),
            cursor: NSCursor.frameResize(position: .bottomRight, directions: .all)
        )

        if rect.width > cornerLength * 2 {
            addCursorRectClipped(
                NSRect(x: rect.minX + cornerLength, y: rect.maxY - outset, width: rect.width - cornerLength * 2, height: outset * 2),
                cursor: NSCursor.resizeUpDown
            )
            addCursorRectClipped(
                NSRect(x: rect.minX + cornerLength, y: rect.minY - outset, width: rect.width - cornerLength * 2, height: outset * 2),
                cursor: NSCursor.resizeUpDown
            )
        }

        if rect.height > cornerLength * 2 {
            addCursorRectClipped(
                NSRect(x: rect.minX - outset, y: rect.minY + cornerLength, width: outset * 2, height: rect.height - cornerLength * 2),
                cursor: NSCursor.resizeLeftRight
            )
            addCursorRectClipped(
                NSRect(x: rect.maxX - outset, y: rect.minY + cornerLength, width: outset * 2, height: rect.height - cornerLength * 2),
                cursor: NSCursor.resizeLeftRight
            )
        }
    }

    private func addCursorRectClipped(_ rect: NSRect, cursor: NSCursor) {
        let clipped = rect.intersection(bounds)
        if !clipped.isNull, clipped.width > 0, clipped.height > 0 {
            addCursorRect(clipped, cursor: cursor)
        }
    }

    private func setCursor(_ style: SelectionToolbarState.OverlayCursorStyle) {
        switch style {
        case .arrow:
            NSCursor.arrow.set()
        case .crosshair:
            NSCursor.crosshair.set()
        case .move:
            NSCursor.sniporyMove.set()
        case .resizeLeftRight:
            NSCursor.resizeLeftRight.set()
        case .resizeUpDown:
            NSCursor.resizeUpDown.set()
        case .resizeTopLeft:
            NSCursor.frameResize(position: .topLeft, directions: .all).set()
        case .resizeTopRight:
            NSCursor.frameResize(position: .topRight, directions: .all).set()
        case .resizeBottomLeft:
            NSCursor.frameResize(position: .bottomLeft, directions: .all).set()
        case .resizeBottomRight:
            NSCursor.frameResize(position: .bottomRight, directions: .all).set()
        case .rotationHandle:
            NSCursor.sniporyBrushRotationHandle(angle: 0).set()
        case .brush:
            NSCursor.sniporyBrush.set()
        case .marker:
            NSCursor.sniporyMarker(color: currentStyle.strokeColor, strokeWidth: currentStyle.strokeWidth).set()
        }
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
        lockedSelectionRect ?? selectionRect ?? displayedWindowRect ?? hoveredWindowRect
    }

    private var cursorSelectionRect: NSRect? {
        lockedSelectionRect ?? selectionRect
    }

    private var draftAnnotation: CaptureAnnotation? {
        guard let shapeStartPoint, let shapeCurrentPoint, lockedSelectionRect != nil else {
            return nil
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
            return hypot(markerLine.end.x - markerLine.start.x, markerLine.end.y - markerLine.start.y) >= 8
        }
        if annotation.kind == .brush {
            return (annotation.brushPath?.points.count ?? 0) >= 2
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
            let targetRect = WindowSelectionState.bestWindow(
                at: point,
                candidates: windowCandidates,
                desktopFrame: bounds,
                currentProcessID: pid_t(NSRunningApplication.current.processIdentifier)
            )?.bounds
            updateHoveredWindowRect(targetRect)
        } else if interactionMode != .selecting {
            updateHoveredWindowRect(nil)
        }

        if previousWindowRect != hoveredWindowRect || previousTooltipText != hoveredTooltip?.text {
            needsDisplay = true
        }
    }

    private func updateColorSampler(at point: NSPoint) {
        guard SelectionToolbarState.shouldShowColorSampler(
            isShapeToolActive: isShapeToolActive,
            hasAnnotations: !annotations.isEmpty,
            pointer: point,
            selectionRect: colorSamplerSelectionRect
        ) else {
            if sampledPointerPoint != nil || sampledColor != nil {
                sampledPointerPoint = nil
                sampledColor = nil
                needsDisplay = true
            }
            return
        }

        sampledPointerPoint = point
        sampledColor = sampleColor(at: point)
        needsDisplay = true
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

    private func tooltipTarget(at point: NSPoint) -> (text: String, anchor: NSRect)? {
        guard lockedSelectionRect != nil, let selectionRect, let toolbar = mainToolbarRect(for: selectionRect) else {
            return nil
        }

        for (button, rect) in toolbarButtonRects(in: toolbar) where rect.contains(point) {
            guard let title = SelectionToolbarState.tooltipTitle(for: tooltipIdentifier(for: button)) else {
                return nil
            }
            return (title, rect)
        }

        guard let optionsRect = optionsToolbarRect else {
            return nil
        }
        let layout = optionsToolbarLayout(in: optionsRect)

        for (index, rect) in layout.strokeWidths.enumerated() where rect.contains(point) {
            let identifiers = ["strokeWidthThin", "strokeWidthMedium", "strokeWidthThick"]
            return (SelectionToolbarState.tooltipTitle(for: identifiers[index]) ?? "线条粗细", rect)
        }

        if let fillRect = layout.fillToggle,
           fillRect.contains(point),
           let title = SelectionToolbarState.tooltipTitle(for: "fill") {
            return (title, fillRect)
        }

        if let rectangleMode = layout.rectangleMode {
            let rectangleButton = shapeModeBackgroundRect(for: rectangleMode)
            if rectangleButton.contains(point), let title = SelectionToolbarState.tooltipTitle(for: "shapeRectangle") {
                return (title, rectangleButton)
            }
        }

        if let ellipseButton = layout.ellipseMode,
           ellipseButton.contains(point),
           let title = SelectionToolbarState.tooltipTitle(for: "shapeEllipse") {
            return (title, ellipseButton)
        }

        if SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode),
           layout.strokeStyle.contains(point),
           let title = SelectionToolbarState.tooltipTitle(for: "strokeStyle") {
            return (title, layout.strokeStyle)
        }

        if let startArrowType = layout.startArrowType, startArrowType.contains(point) {
            return (SelectionToolbarState.tooltipTitle(for: "startArrowType") ?? "开始箭头", startArrowType)
        }

        if let endArrowType = layout.endArrowType, endArrowType.contains(point) {
            return (SelectionToolbarState.tooltipTitle(for: "endArrowType") ?? "结束箭头", endArrowType)
        }

        for (index, rect) in layout.colorSwatches.enumerated() where rect.insetBy(dx: -4, dy: -4).contains(point) {
            if index == visiblePaletteCount, let title = SelectionToolbarState.tooltipTitle(for: "customColor") {
                return (title, rect)
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
        case .settings:
            return "settings"
        }
    }

    private func handleAnnotatingMouseDown(at point: NSPoint) {
        if startToolbarDragIfPossible(at: point) {
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

        guard lockedSelectionRect != nil else {
            return
        }

        if let markerHit = markerRotationHitTarget(at: point) {
            if let angle = markerRotationCursorAngle(for: markerHit.index, target: markerHit.target) {
                NSCursor.sniporyBrushRotationHandle(angle: angle).set()
            }
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
            if let angle = brushRotationCursorAngle(for: brushHit.index, target: brushHit.target) {
                NSCursor.sniporyBrushRotationHandle(angle: angle).set()
            }
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
            NSCursor.sniporyMove.set()
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

        switch SelectionToolbarState.annotatingMouseDownTarget(
            shapeResizeHandle: resizeHandle(at: point)?.toolbarStateHandle,
            isAnnotationBorder: annotationIndexForBorder(at: point) != nil,
            selectionResizeHandle: selectionResizeHandle(at: point),
            selectionMoveEligible: shouldStartSelectionMove(at: point)
        ) {
        case .shapeResize(let handle):
            activeResizeHandle = ShapeResizeHandle(toolbarStateHandle: handle)
            resizingAnnotationStartRect = selectedAnnotation.map { overlayRect(fromLocalAnnotationRect: $0.rect) }
            interactionMode = .resizingShape
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            return
        case .annotationMove:
            guard let hitIndex = annotationIndexForBorder(at: point) else {
                break
            }
            NSCursor.sniporyMove.set()
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

        if isShapeToolActive {
            beginShapeDrawing(at: point)
            return
        }

        selectedAnnotationIndex = nil
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        needsDisplay = true
    }

    private func beginShapeDrawing(at point: NSPoint) {
        selectedAnnotationIndex = nil
        shapeStartPoint = point
        shapeCurrentPoint = point
        brushDraftPoints = currentShapeKind == .brush ? [point] : []
        interactionMode = .drawingShape
        NSLog("snipory overlay drawing started point=(%.0f, %.0f)", point.x, point.y)
    }

    private func draftEndPoint(rawEnd: NSPoint, modifierFlags: NSEvent.ModifierFlags) -> NSPoint {
        guard currentShapeKind == .marker, let shapeStartPoint else {
            return rawEnd
        }

        return SelectionToolbarState.snappedMarkerEndPoint(
            start: shapeStartPoint,
            rawEnd: rawEnd,
            isShiftPressed: modifierFlags.contains(.shift)
        )
    }

    private func beginSelectionResize(handle: SelectionToolbarState.OverlayResizeHandle) {
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
        movingAnnotationStartRect = overlayRect(fromLocalAnnotationRect: annotations[index].rect)
        movingAnnotationStartArrowLine = overlayArrowLine(fromLocalArrowLine: annotations[index].arrowLine)
        movingAnnotationStartBrushPath = overlayBrushPath(fromLocalBrushPath: annotations[index].brushPath)
        movingAnnotationStartMarkerLine = overlayMarkerLine(fromLocalMarkerLine: annotations[index].markerLine)
        movingAnnotationOffset = NSPoint(
            x: point.x - (movingAnnotationStartRect?.minX ?? point.x),
            y: point.y - (movingAnnotationStartRect?.minY ?? point.y)
        )
        interactionMode = .movingShape
    }

    private func perform(_ button: ToolbarButton) {
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
        case .pin, .mosaic, .text, .number, .magnifier, .eraser, .scroll, .settings:
            showPlaceholder(for: button)
        }

        needsDisplay = true
    }

    private func toggleShapeTool(_ shape: CaptureAnnotationKind) {
        activeShapeKind = activeShapeKind == shape ? nil : shape
        isShapeToolActive = activeShapeKind != nil
        if let activeShapeKind {
            currentShapeKind = activeShapeKind
            if activeShapeKind == .arrowLine {
                let activation = SelectionToolbarState.arrowLineActivationState(
                    currentStyle: currentStyle,
                    paletteColors: colors
                )
                currentStyle = activation.style
                currentStartArrowType = activation.startArrowType
                currentEndArrowType = activation.endArrowType
                showsCornerRadiusPanel = false
            } else if activeShapeKind == .brush {
                currentStyle = SelectionToolbarState.brushActivationStyle(
                    currentStyle: currentStyle,
                    paletteColors: colors
                )
                showsCornerRadiusPanel = false
            } else if activeShapeKind == .marker {
                currentStyle = SelectionToolbarState.markerActivationStyle(currentStyle: currentStyle)
                showsCornerRadiusPanel = false
            } else {
                currentStyle = SelectionToolbarState.styleForPrimaryShapeToolActivation(
                    currentStyle: currentStyle,
                    paletteColors: colors
                )
            }
            if activeShapeKind != .arrowLine {
                showsStartArrowTypeMenu = false
                showsEndArrowTypeMenu = false
            }
            if !SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode) {
                showsStrokeStyleMenu = false
            }
            currentStyle.strokePattern = .solid
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
        invalidateCursorRectsAndRefresh()
    }

    private func activateShapeTool(_ shape: CaptureAnnotationKind) {
        activeShapeKind = shape
        currentShapeKind = shape
        isShapeToolActive = true
        if shape == .arrowLine || shape == .brush {
            showsCornerRadiusPanel = false
        }
        if shape == .marker {
            currentStyle = SelectionToolbarState.markerActivationStyle(currentStyle: currentStyle)
            showsCornerRadiusPanel = false
        }
        if shape != .arrowLine {
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
        }
        if !SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode) {
            showsStrokeStyleMenu = false
        }
        currentStyle.strokePattern = .solid
        clearSelectedAnnotationIfNeededForActiveTool()
        shapeStartPoint = nil
        shapeCurrentPoint = nil
        brushDraftPoints.removeAll()
        invalidateCursorRectsAndRefresh()
    }

#if DEBUG
    func test_setLockedSelectionRect(_ rect: NSRect) {
        let rect = rect.standardized
        lockedSelectionRect = rect
        selectionStartPoint = rect.origin
        selectionCurrentPoint = NSPoint(x: rect.maxX, y: rect.maxY)
        interactionMode = .annotating
    }

    func test_activateShapeTool(_ shape: CaptureAnnotationKind) {
        activateShapeTool(shape)
    }

    func test_toggleShapeTool(_ shape: CaptureAnnotationKind) {
        toggleShapeTool(shape)
    }

    func test_setCurrentStrokePattern(_ pattern: CaptureStrokePattern) {
        currentStyle.strokePattern = pattern
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

    func test_annotationRect(at index: Int) -> NSRect? {
        guard annotations.indices.contains(index) else {
            return nil
        }
        return annotations[index].rect
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

    func test_markerToolbarButtonPoint() -> NSPoint? {
        guard let selectionRect, let toolbar = mainToolbarRect(for: selectionRect) else {
            return nil
        }
        guard let rect = toolbarButtonRects(in: toolbar).first(where: { $0.0 == .marker })?.1 else {
            return nil
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

    func test_annotationStyle(at index: Int) -> CaptureAnnotationStyle? {
        guard annotations.indices.contains(index) else {
            return nil
        }
        return annotations[index].style
    }

    var test_selectedAnnotationKind: CaptureAnnotationKind? {
        selectedAnnotation?.kind
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

    var test_lockedSelectionRect: NSRect? {
        lockedSelectionRect?.standardized
    }

    var test_currentStrokePattern: CaptureStrokePattern {
        currentStyle.strokePattern
    }

    var test_currentStyle: CaptureAnnotationStyle {
        currentStyle
    }

    var test_optionsToolbarMode: SelectionToolbarState.OptionsToolbarMode {
        optionsToolbarMode
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
        case .settings:
            label = "设置"
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
        }

        NSAlert.showTransient(message: "\(label)功能开发中。", in: window)
    }

    private func finish(action: CaptureCompletionAction) {
        guard let lockedSelectionRect, let window else {
            selectionDidFinish?(nil)
            return
        }

        selectionDidFinish?(
            CaptureSelectionResult(
                screenRect: window.convertToScreen(lockedSelectionRect).standardized,
                snapshotRect: lockedSelectionRect.standardized,
                annotations: annotations,
                action: action
            )
        )
    }

    private func undoLastAnnotation() {
        guard let removed = annotations.popLast() else {
            return
        }
        redoAnnotations.append(removed)
        selectedAnnotationIndex = annotations.indices.last
        needsDisplay = true
    }

    private func redoLastAnnotation() {
        guard let restored = redoAnnotations.popLast() else {
            return
        }
        annotations.append(restored)
        selectedAnnotationIndex = annotations.indices.last
        needsDisplay = true
    }

    private func deleteSelectedAnnotation() -> Bool {
        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else {
            return false
        }

        annotations.remove(at: selectedAnnotationIndex)
        self.selectedAnnotationIndex = nil
        redoAnnotations.removeAll()
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
        needsDisplay = true
        return true
    }

    private func handleOptionsClick(at point: NSPoint) -> Bool {
        guard let optionsRect = optionsToolbarRect else {
            return false
        }
        let layout = optionsToolbarLayout(in: optionsRect)
        let strokeWidths = SelectionToolbarState.strokeWidthValues(for: optionsToolbarMode)

        for (index, rect) in layout.strokeWidths.enumerated() where rect.contains(point) {
            currentStyle.strokeWidth = strokeWidths[index]
            applyCurrentStyleToSelectedAnnotation()
            return true
        }

        if let fillRect = layout.fillToggle, fillRect.contains(point) {
            currentStyle.fillEnabled.toggle()
            applyCurrentStyleToSelectedAnnotation()
            return true
        }

        if let rectangleButton = layout.rectangleMode {
            let rectangleDisclosureRect = rectangleDisclosureHitRect(in: rectangleButton)
            if rectangleDisclosureRect.contains(point) {
                activateShapeTool(.rectangle)
                applyCurrentStyleToSelectedAnnotation()
                showsCornerRadiusPanel.toggle()
                showsStrokeStyleMenu = false
                showsStartArrowTypeMenu = false
                showsEndArrowTypeMenu = false
                return true
            }

            if rectangleButton.contains(point) {
                activateShapeTool(.rectangle)
                applyCurrentStyleToSelectedAnnotation()
                return true
            }
        }

        if let ellipseButton = layout.ellipseMode, ellipseButton.contains(point) {
            activateShapeTool(.ellipse)
            showsCornerRadiusPanel = false
            applyCurrentStyleToSelectedAnnotation()
            return true
        }

        if SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode),
           layout.strokeStyle.contains(point) {
            showsStrokeStyleMenu.toggle()
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
            return true
        }

        if let startArrowType = layout.startArrowType, startArrowType.contains(point) {
            showsStartArrowTypeMenu.toggle()
            showsEndArrowTypeMenu = false
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            return true
        }

        if let endArrowType = layout.endArrowType, endArrowType.contains(point) {
            showsEndArrowTypeMenu.toggle()
            showsStartArrowTypeMenu = false
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            return true
        }

        if let swatch = SelectionToolbarState.swatchHitTarget(at: point, in: optionsRect, paletteCount: visiblePaletteCount, mode: optionsToolbarMode) {
            switch swatch {
            case .custom:
                NSLog("snipory overlay custom color swatch clicked")
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

        if !optionsRect.contains(point) {
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
            return false
        }

        return true
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
            applyCurrentStyleToSelectedAnnotation()
            showsStrokeStyleMenu = false
            needsDisplay = true
            NSLog("snipory overlay selected stroke pattern=%ld", option.pattern.rawValue)
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
            applyCurrentStyleToSelectedAnnotation()
            return true
        }
        if cornerRadiusDownRect(in: valueRect).contains(point) {
            currentStyle.cornerRadius = max(0, currentStyle.cornerRadius - 1)
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

    private var selectedAnnotation: CaptureAnnotation? {
        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else {
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
        guard isShapeToolActive else {
            return true
        }

        switch currentShapeKind {
        case .arrowLine:
            return kind == .arrowLine
        case .brush:
            return kind == .brush
        case .marker:
            return kind == .marker
        case .rectangle, .ellipse:
            return kind == .rectangle || kind == .ellipse
        }
    }

    private func selectAnnotation(at index: Int) {
        guard annotations.indices.contains(index) else {
            selectedAnnotationIndex = nil
            return
        }

        selectedAnnotationIndex = index
        let annotation = annotations[index]
        activateShapeTool(annotation.kind)
        currentStyle = annotation.style
        if let arrowLine = annotation.arrowLine {
            currentStartArrowType = arrowLine.startArrowType
            currentEndArrowType = arrowLine.endArrowType
        }
        if annotation.kind == .marker {
            invalidateCursorRectsAndRefresh()
        }
    }

    private func applyCurrentStyleToSelectedAnnotation() {
        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else {
            return
        }

        annotations[selectedAnnotationIndex].style = SelectionToolbarState.updatedSelectedAnnotationStyle(
            kind: annotations[selectedAnnotationIndex].kind,
            existingStyle: annotations[selectedAnnotationIndex].style,
            currentStyle: currentStyle
        )
        if annotations[selectedAnnotationIndex].kind == .arrowLine {
            if var arrowLine = annotations[selectedAnnotationIndex].arrowLine {
                arrowLine.startArrowType = currentStartArrowType
                arrowLine.endArrowType = currentEndArrowType
                annotations[selectedAnnotationIndex].arrowLine = arrowLine
                annotations[selectedAnnotationIndex].rect = arrowLine.boundingRect
            }
        } else if SelectionToolbarState.annotationKindSupportsPostDrawEditing(annotations[selectedAnnotationIndex].kind) {
            annotations[selectedAnnotationIndex].kind = currentShapeKind
        }
        redoAnnotations.removeAll()
        needsDisplay = true
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
        NSLog("snipory overlay opened custom color panel")
    }

    @objc private func customColorChanged(_ sender: NSColorPanel) {
        let color = opaqueColor(sender.color)
        customColor = color
        isCustomColorSwatchActive = true
        currentStyle.strokeColor = color
        currentStyle.fillColor = color
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
        resizingAnnotationStartRect = nil
        resizingArrowLineStart = nil
        activeArrowLineHandle = nil
        resizingMarkerLineStart = nil
        activeMarkerLineHandle = nil
        rotatingBrushStartPath = nil
        activeBrushRotationHandle = nil
        redoAnnotations.removeAll()
        needsDisplay = true
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
        redoAnnotations.removeAll()
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

        NSCursor.sniporyMove.set()
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
        for index in annotations.indices.reversed() {
            if annotationBorderContains(point, for: annotations[index]) {
                return index
            }
        }
        return nil
    }

    private func annotationBorderContains(_ point: NSPoint, for annotation: CaptureAnnotation) -> Bool {
        if annotation.kind == .arrowLine {
            guard let arrowLine = overlayArrowLine(fromLocalArrowLine: annotation.arrowLine) else {
                return false
            }
            return SelectionToolbarState.arrowLineHitTarget(at: point, line: arrowLine) == .body
        }
        if annotation.kind == .brush {
            guard let brushPath = overlayBrushPath(fromLocalBrushPath: annotation.brushPath) else {
                return false
            }
            let hitOutset = max(6, annotation.style.strokeWidth / 2 + 4)
            if let start = brushPath.points.first, let end = brushPath.points.last,
               hypot(point.x - start.x, point.y - start.y) <= hitOutset
                || hypot(point.x - end.x, point.y - end.y) <= hitOutset {
                return false
            }
            return brushPathContains(point, path: brushPath, hitOutset: hitOutset)
        }
        if annotation.kind == .marker {
            guard let markerLine = overlayMarkerLine(fromLocalMarkerLine: annotation.markerLine) else {
                return false
            }
            let hitOutset = max(8, annotation.style.strokeWidth / 2 + 4)
            if hypot(point.x - markerLine.start.x, point.y - markerLine.start.y) <= hitOutset
                || hypot(point.x - markerLine.end.x, point.y - markerLine.end.y) <= hitOutset {
                return false
            }
            return SelectionToolbarState.markerLineContains(point: point, line: markerLine, hitOutset: hitOutset)
        }

        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized
        return SelectionToolbarState.shapeBorderContains(
            point: point,
            rect: rect,
            kind: annotation.kind,
            cornerRadius: annotation.style.cornerRadius
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
        for handle in ShapeResizeHandle.allCases where handleRect(for: rect, handle: handle, kind: annotation.kind).insetBy(dx: -3, dy: -3).contains(point) {
            return handle
        }
        return nil
    }

    private func arrowLineHitTarget(at point: NSPoint) -> (index: Int, target: SelectionToolbarState.ArrowLineHitTarget)? {
        for index in annotations.indices.reversed() where annotations[index].kind == .arrowLine {
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
        for index in annotations.indices.reversed() where annotations[index].kind == .brush {
            guard activeToolCanEdit(annotationKind: annotations[index].kind) else {
                continue
            }
            guard let brushPath = overlayBrushPath(fromLocalBrushPath: annotations[index].brushPath) else {
                continue
            }
            let target = SelectionToolbarState.brushRotationHitTarget(at: point, path: brushPath)
            if target != .none {
                return (index, target)
            }
        }
        return nil
    }

    private func markerRotationHitTarget(at point: NSPoint) -> (index: Int, target: SelectionToolbarState.BrushRotationHitTarget)? {
        for index in annotations.indices.reversed() where annotations[index].kind == .marker {
            guard activeToolCanEdit(annotationKind: annotations[index].kind) else {
                continue
            }
            guard let markerLine = overlayMarkerLine(fromLocalMarkerLine: annotations[index].markerLine) else {
                continue
            }
            let target = SelectionToolbarState.markerRotationHitTarget(at: point, line: markerLine)
            if target != .none {
                return (index, target)
            }
        }
        return nil
    }

    private func markerRotationCursorAngle(
        for index: Int,
        target: SelectionToolbarState.BrushRotationHitTarget
    ) -> CGFloat? {
        guard annotations.indices.contains(index),
              let markerLine = overlayMarkerLine(fromLocalMarkerLine: annotations[index].markerLine) else {
            return nil
        }

        let from: NSPoint
        let to: NSPoint
        switch target {
        case .start:
            from = markerLine.end
            to = markerLine.start
        case .end:
            from = markerLine.start
            to = markerLine.end
        case .none:
            return nil
        }
        return atan2(to.y - from.y, to.x - from.x)
    }

    private func brushRotationCursorAngle(at point: NSPoint) -> CGFloat? {
        if interactionMode == .rotatingBrush,
           let selectedAnnotationIndex,
           annotations.indices.contains(selectedAnnotationIndex),
           let activeBrushRotationHandle {
            return brushRotationCursorAngle(for: selectedAnnotationIndex, target: activeBrushRotationHandle)
        }

        guard interactionMode == .annotating,
              let hit = brushRotationHitTarget(at: point) else {
            return nil
        }
        return brushRotationCursorAngle(for: hit.index, target: hit.target)
    }

    private func brushRotationCursorAngle(
        for index: Int,
        target: SelectionToolbarState.BrushRotationHitTarget
    ) -> CGFloat? {
        guard annotations.indices.contains(index),
              let brushPath = overlayBrushPath(fromLocalBrushPath: annotations[index].brushPath) else {
            return nil
        }
        return SelectionToolbarState.brushRotationHandleAngle(for: target, path: brushPath)
    }

    private func selectionResizeHandle(at point: NSPoint) -> SelectionToolbarState.OverlayResizeHandle? {
        guard let lockedSelectionRect else {
            return nil
        }

        return SelectionToolbarState.selectionResizeHandle(at: point, in: lockedSelectionRect)
    }

    private func shouldStartSelectionMove(at point: NSPoint) -> Bool {
        guard let lockedSelectionRect else {
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

        NSCursor.sniporyMove.set()
        movingSelectionStartRect = lockedSelectionRect.standardized
        movingSelectionStartAnnotationRects = annotations.map { overlayRect(fromLocalAnnotationRect: $0.rect) }
        movingSelectionStartAnnotations = annotations
        movingSelectionPointerOffset = NSPoint(
            x: point.x - lockedSelectionRect.minX,
            y: point.y - lockedSelectionRect.minY
        )
        movingSelectionBounds = screenBounds(containing: lockedSelectionRect)
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
            annotations.indices.contains(selectedAnnotationIndex),
            let movingAnnotationStartRect
        else {
            return
        }

        NSCursor.sniporyMove.set()
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
                } else {
                    annotations[index].rect = preservedRects[index]
                }
            }
        }
    }

    private func updateResizingShape(to point: NSPoint) {
        guard
            let selectedAnnotationIndex,
            annotations.indices.contains(selectedAnnotationIndex),
            let activeResizeHandle,
            let resizingAnnotationStartRect
        else {
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

    private func updateResizingArrowLine(to point: NSPoint, modifierFlags: NSEvent.ModifierFlags = []) {
        guard
            let selectedAnnotationIndex,
            annotations.indices.contains(selectedAnnotationIndex),
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
            annotations.indices.contains(selectedAnnotationIndex),
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
        if let angle = markerRotationCursorAngle(for: selectedAnnotationIndex, target: activeMarkerLineHandle) {
            NSCursor.sniporyBrushRotationHandle(angle: angle).set()
        }
    }

    private func updateRotatingBrush(to point: NSPoint) {
        guard
            let selectedAnnotationIndex,
            annotations.indices.contains(selectedAnnotationIndex),
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
        if let angle = SelectionToolbarState.brushRotationHandleAngle(for: activeBrushRotationHandle, path: rotatedPath) {
            NSCursor.sniporyBrushRotationHandle(angle: angle).set()
        }
    }

    private func updateResizingSelection(to point: NSPoint) {
        guard
            let activeSelectionResizeHandle,
            let resizingSelectionStartRect
        else {
            return
        }

        let resized = resizedRect(
            from: resizingSelectionStartRect,
            handle: activeSelectionResizeHandle,
            point: clamp(point, to: bounds)
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
            } else {
                annotations[index].rect = SelectionToolbarState.localAnnotationRect(
                    fromOverlayRect: resizingSelectionStartAnnotationRects[index],
                    selectionRect: resized
                )
            }
        }
    }

    private func resizedRect(from startRect: NSRect, handle: SelectionToolbarState.OverlayResizeHandle, point: NSPoint) -> NSRect {
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

    private func drawOverlay() {
        if let backgroundImage {
            backgroundImage.draw(in: bounds, from: NSRect(origin: .zero, size: backgroundImage.size), operation: .copy, fraction: 1)
        }

        guard let selectionRect else {
            NSColor.black.withAlphaComponent(0.34).setFill()
            bounds.fill()
            return
        }

        let path = NSBezierPath(rect: bounds)
        path.appendRect(selectionRect)
        path.windingRule = .evenOdd

        NSColor.black.withAlphaComponent(0.34).setFill()
        path.fill()
    }

    private func drawSelectionBorder(_ rect: NSRect) {
        NSColor(calibratedRed: 83 / 255, green: 120 / 255, blue: 232 / 255, alpha: 1).setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 2
        border.stroke()
    }

    private func drawSelectionHandles(_ rect: NSRect) {
        let handles = [
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.midX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.midY),
            NSPoint(x: rect.maxX, y: rect.midY),
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.midX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
        ]

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
        let textSize = NSString(string: label).size(withAttributes: attributes)
        var labelRect = NSRect(x: rect.minX, y: rect.maxY + 8, width: textSize.width + 18, height: 24)
        let safeBounds = safeLayoutBounds
        if labelRect.maxY > safeBounds.maxY - 8 {
            labelRect.origin.y = rect.minY - 32
        }
        labelRect = clamp(rect: labelRect, inside: safeBounds.insetBy(dx: 8, dy: 8))

        NSColor(calibratedWhite: 0.12, alpha: 0.86).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        NSString(string: label).draw(in: labelRect.insetBy(dx: 9, dy: 4), withAttributes: attributes)
    }

    private func drawAnnotations() {
        for (index, annotation) in annotations.enumerated() {
            drawAnnotation(annotation, inOverlay: true)
            if selectedAnnotationIndex == index, shouldDrawSelectedAnnotationOutline(annotation) {
                drawSelectedAnnotationOutline(annotation)
            }
        }
    }

    private func shouldDrawSelectedAnnotationOutline(_ annotation: CaptureAnnotation) -> Bool {
        activeToolCanEdit(annotationKind: annotation.kind)
            && (annotation.kind == .arrowLine
                || annotation.kind == .brush
                || SelectionToolbarState.annotationKindSupportsGeometryEditing(annotation.kind))
    }

    private func drawDraftAnnotation() {
        guard let draftAnnotation else {
            return
        }

        drawAnnotation(draftAnnotation, inOverlay: true)
        if draftAnnotation.kind == .arrowLine {
            drawSelectedAnnotationOutline(draftAnnotation)
        } else if SelectionToolbarState.annotationKindSupportsGeometryEditing(draftAnnotation.kind) {
            drawResizeHandles(for: overlayRect(fromLocalAnnotationRect: draftAnnotation.rect), kind: draftAnnotation.kind)
        }
    }

    private func drawAnnotation(_ annotation: CaptureAnnotation, inOverlay: Bool) {
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
        case .arrowLine, .brush, .marker:
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

        annotation.style.strokeColor.withAlphaComponent(CaptureAnnotationRenderer.markerOpacity).setStroke()
        path.lineWidth = annotation.style.strokeWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
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

    private func drawSelectedAnnotationOutline(_ annotation: CaptureAnnotation) {
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
        let outline = annotation.kind == .ellipse ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
        outline.lineWidth = 1.5
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.stroke()
        drawResizeHandles(for: rect, kind: annotation.kind)
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

    private func drawResizeHandles(for rect: NSRect, kind: CaptureAnnotationKind) {
        let handles = resizeHandleCenters(for: rect, kind: kind)
        NSColor.systemBlue.setFill()
        NSColor.white.setStroke()
        for center in handles {
            let handleRect = NSRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
            let path = NSBezierPath(ovalIn: handleRect)
            path.fill()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func handleRect(for rect: NSRect, handle: ShapeResizeHandle, kind: CaptureAnnotationKind) -> NSRect {
        let centers = resizeHandleCenters(for: rect, kind: kind)
        let index = ShapeResizeHandle.allCases.firstIndex(of: handle) ?? 0
        let center = centers[index]
        return NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
    }

    private func drawMainToolbar(for selectionRect: NSRect) {
        guard let toolbar = mainToolbarRect(for: selectionRect) else {
            return
        }

        drawPanel(toolbar, opaque: true, alpha: 0.9)
        drawMainToolbarSeparators(in: toolbar)

        for (button, rect) in toolbarButtonRects(in: toolbar) {
            let enabled = isToolbarButtonEnabled(button)
            drawToolbarButton(rect, symbol: symbolName(for: button, enabled: enabled), selected: buttonMatchesCurrentTool(button), enabled: enabled)
            if button == .number {
                drawNumberToolDisclosure(in: rect, enabled: enabled)
            }
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
        switch button {
        case .undo:
            return !annotations.isEmpty
        case .redo:
            return !redoAnnotations.isEmpty
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
        let textSize = NSString(string: hoveredTooltip.text).size(withAttributes: attributes)
        let rect = SelectionToolbarState.tooltipRect(textSize: textSize, anchoredTo: hoveredTooltip.anchor, inside: safeLayoutBounds)
        NSColor(calibratedWhite: 0.08, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        NSString(string: hoveredTooltip.text).draw(in: rect.insetBy(dx: 8, dy: 5), withAttributes: attributes)
    }

    private func drawColorSamplerIfNeeded() {
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
        guard let backgroundBitmap else {
            return
        }

        let gridSize = 9
        let cellWidth = rect.width / CGFloat(gridSize)
        let cellHeight = rect.height / CGFloat(gridSize)
        let contentRect = rect
        let centerPixel = bitmapPixelPoint(for: point, in: backgroundBitmap)
        let pixelX = centerPixel.x
        let pixelY = centerPixel.y
        let centerIndex = gridSize / 2

        NSColor.white.setFill()
        NSBezierPath(rect: contentRect).fill()

        for row in 0..<gridSize {
            for column in 0..<gridSize {
                let sampleX = pixelX + column - centerIndex
                let sampleY = pixelY + centerIndex - row
                let cellRect = NSRect(
                    x: contentRect.minX + CGFloat(column) * cellWidth,
                    y: contentRect.minY + CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )
                (sampleColor(atPixelX: sampleX, y: sampleY, in: backgroundBitmap) ?? .white).setFill()
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

        switch optionsToolbarMode {
        case .shape:
            drawFillToggle(in: optionsRect)
            drawShapeModeButtons(in: optionsRect)
        case .arrowLine:
            drawArrowTypeFields(in: optionsRect)
        case .brush, .marker:
            break
        }
        if SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode) {
            drawStrokeStyleField(in: optionsRect)
        }
        drawColorSwatches(in: optionsRect)
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
        guard let color = sampledColor ?? sampledPointerPoint.flatMap(sampleColor(at:)) else {
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

    private func logColorSamplerDebug(at point: NSPoint, color: NSColor) {
        guard let backgroundBitmap else {
            return
        }

        let pixel = bitmapPixelPoint(for: point, in: backgroundBitmap)
        NSLog(
            "snipory color sampler %@",
            SelectionToolbarState.colorSamplerDebugDescription(
                atPixelX: pixel.x,
                y: pixel.y,
                in: backgroundBitmap,
                color: color
            )
        )
    }

    private func bitmapPixelPoint(for point: NSPoint, in bitmap: NSBitmapImageRep) -> (x: Int, y: Int) {
        let imageSize = backgroundImage?.size ?? bounds.size
        let scaleX = CGFloat(bitmap.pixelsWide) / max(imageSize.width, 1)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(imageSize.height, 1)
        let x = max(0, min(bitmap.pixelsWide - 1, Int(point.x * scaleX)))
        let y = max(0, min(bitmap.pixelsHigh - 1, Int((bounds.height - point.y) * scaleY)))
        return (x, y)
    }

    private func sampleColor(atPixelX x: Int, y: Int, in bitmap: NSBitmapImageRep) -> NSColor? {
        SelectionToolbarState.sampleColor(atPixelX: x, y: y, in: bitmap)
    }

    private func rgbString(for color: NSColor) -> String {
        SelectionToolbarState.colorSamplerRgbString(for: color)
    }

    private func drawToolbarButton(_ rect: NSRect, symbol: String?, selected: Bool, enabled: Bool) {
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.22) : NSColor.clear).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()

        guard let symbol else {
            return
        }

        drawToolbarIcon(named: symbol, in: rect, enabled: enabled)
    }

    private func drawToolbarIcon(named name: String, in rect: NSRect, enabled: Bool) {
        let color = enabled ? NSColor.labelColor : NSColor.disabledControlTextColor
        color.set()

        let resourceName = name.replacingOccurrences(of: "toolbar-", with: "")
        let imageInset = toolbarIconInset(for: resourceName)
        let usesFixedColorResource = SelectionToolbarState.usesFixedColorToolbarIconResource(resourceName)
        if drawToolbarImage(named: resourceName, in: rect, template: !usesFixedColorResource, enabled: enabled, inset: imageInset)
            || drawToolbarImage(named: name, in: rect, template: !usesFixedColorResource, enabled: enabled, inset: imageInset) {
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
    private func drawToolbarImage(named name: String, in rect: NSRect, template: Bool, enabled: Bool, inset: CGFloat = 3) -> Bool {
        let resource = NSImage(named: name)
            ?? Bundle.main.url(forResource: name, withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? Bundle.main.url(forResource: name, withExtension: "png").flatMap(NSImage.init(contentsOf:))
        if let image = resource {
            image.isTemplate = template
            (enabled ? NSColor.labelColor : NSColor.disabledControlTextColor).set()
            image.draw(in: rect.insetBy(dx: inset, dy: inset))
            return true
        }

        return false
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

    private func drawTriangle(in rect: NSRect, color: NSColor) {
        color.setFill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.midX, y: rect.minY))
        path.close()
        path.fill()
    }

    private func drawNumberToolDisclosure(in rect: NSRect, enabled: Bool) {
        drawDisclosureCorner(in: rect, enabled: enabled)
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
            .first(where: { $0.0 != .settings && $0.1.contains(point) })?
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

        if mainToolbarDragHandleRect(in: toolbar).contains(point) {
            return true
        }

        return toolbarButtonRects(in: toolbar)
            .filter { $0.0 != .settings }
            .allSatisfy { !$0.1.insetBy(dx: -2, dy: -2).contains(point) }
    }

    private func mainToolbarDragHandleRect(in toolbar: NSRect) -> NSRect {
        toolbarButtonRects(in: toolbar).first(where: { $0.0 == .settings })?.1 ?? .zero
    }

    private func toolbarButtonRects(in toolbar: NSRect) -> [(ToolbarButton, NSRect)] {
        let buttonStep: CGFloat = 25
        var x = toolbar.minX + 4
        return mainToolbarButtons().map { button in
            let rect = NSRect(x: x, y: toolbar.minY + 4, width: 20, height: 20)
            x += buttonStep + mainToolbarExtraGap(after: button)
            return (button, rect)
        }
    }

    private func mainToolbarButtons() -> [ToolbarButton] {
        var buttons: [ToolbarButton] = [
            .rectangle,
            .polyline,
            .pen,
            .marker,
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
            .settings,
        ])
        return buttons
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
        let buttonStep: CGFloat = 25
        return 4 + mainToolbarButtons().reduce(CGFloat(0)) { width, button in
            width + buttonStep + mainToolbarExtraGap(after: button)
        }
    }

    private func symbolName(for button: ToolbarButton, enabled: Bool = true) -> String {
        switch button {
        case .rectangle:
            return "toolbar-shape-marker"
        case .polyline:
            return "toolbar-arrow-line"
        case .pen:
            return "toolbar-pencil-tool"
        case .marker:
            return "toolbar-highlighter-tool"
        case .mosaic:
            return "toolbar-mosaic-tool"
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
            return "toolbar-scroll-capture"
        case .settings:
            return "toolbar-settings-more"
        }
    }

    private func buttonMatchesCurrentTool(_ button: ToolbarButton) -> Bool {
        switch button {
        case .rectangle:
            return isShapeToolActive && (currentShapeKind == .rectangle || currentShapeKind == .ellipse)
        case .polyline:
            return isShapeToolActive && currentShapeKind == .arrowLine
        case .pen:
            return isShapeToolActive && currentShapeKind == .brush
        case .marker:
            return isShapeToolActive && currentShapeKind == .marker
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

        if let optionsToolbarRect, optionsToolbarRect.contains(point) {
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
        switch currentShapeKind {
        case .arrowLine:
            return .arrowLine
        case .brush:
            return .brush
        case .marker:
            return .marker
        case .rectangle, .ellipse:
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
            SelectionToolbarState.shouldShowOptionsToolbar(isPrimaryShapeToolActive: isShapeToolActive),
            let selectionRect,
            let toolbar = mainToolbarRect(for: selectionRect)
        else {
            return nil
        }

        return toolbarRect(
            size: NSSize(
                width: SelectionToolbarState.optionsToolbarWidth(paletteCount: visiblePaletteCount, mode: optionsToolbarMode),
                height: SelectionToolbarState.optionsToolbarHeight(paletteCount: visiblePaletteCount)
            ),
            anchoredTo: toolbar
        )
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

    private func distance(from first: NSPoint, to second: NSPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func resizeHandleCenters(for rect: NSRect, kind: CaptureAnnotationKind) -> [NSPoint] {
        let outline = NSRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - 1), height: max(0, rect.height - 1))
        return [
            NSPoint(x: outline.minX, y: outline.maxY),
            NSPoint(x: outline.midX, y: outline.maxY),
            NSPoint(x: outline.maxX, y: outline.maxY),
            NSPoint(x: outline.minX, y: outline.midY),
            NSPoint(x: outline.maxX, y: outline.midY),
            NSPoint(x: outline.minX, y: outline.minY),
            NSPoint(x: outline.midX, y: outline.minY),
            NSPoint(x: outline.maxX, y: outline.minY),
        ]
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
