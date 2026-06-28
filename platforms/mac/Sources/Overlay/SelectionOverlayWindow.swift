import AppKit

enum TestMosaicRectangleRotationHandleGlyph {
    case refreshDot
}

enum TestToolbarButton {
    case rectangle
    case marker
    case eyedropper
    case mosaic
    case settings
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

private extension NSCursor {
    static func sniporyBrushRotationHandle(angle: CGFloat) -> NSCursor {
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

    static let sniporyMosaicRectangleRotationHandle: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let hotSpot = NSPoint(x: size.width / 2, y: size.height / 2)
        guard let image = svgImage(named: "refresh (1)") else {
            return NSCursor.sniporyBrushRotationHandle(angle: 0)
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

    static let sniporyEyedropper: NSCursor = {
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
        cursorImage.unlockFocus()
        return NSCursor(image: cursorImage, hotSpot: hotSpot)
    }()

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

    static func sniporyMosaicDot(diameter: CGFloat) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
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
    private var escapeKeyMonitor: Any?

    init(
        backgroundImage: NSImage?,
        settings: AppSettings = .default,
        featureGate: FeatureGate = FeatureGate(license: LicenseState()),
        refreshHandler: (() async throws -> NSImage?)? = nil,
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
            featureGate: featureGate,
            refreshHandler: refreshHandler
        )
        overlayView.selectionDidFinish = { [weak self] result in
            self?.completeSelection(with: result)
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

    private func installEscapeKeyMonitor() {
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.didCompleteSelection else {
                return event
            }
            guard event.keyCode == 53 else {
                return event
            }
            self.cancelOperation(nil)
            return nil
        }
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

    func test_setCurrentStrokeWidth(_ width: CGFloat) {
        (contentView as? SelectionOverlayView)?.test_setCurrentStrokeWidth(width)
    }

    func test_setAnnotations(_ annotations: [CaptureAnnotation]) {
        (contentView as? SelectionOverlayView)?.test_setAnnotations(annotations)
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

    func test_mouseDown(at point: NSPoint) {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return
        }
        overlayView.mouseDown(with: test_mouseEvent(type: .leftMouseDown, at: point))
    }

    func test_mouseMoved(to point: NSPoint) {
        guard let overlayView = contentView as? SelectionOverlayView else {
            return
        }
        overlayView.mouseMoved(with: test_mouseEvent(type: .mouseMoved, at: point))
    }

    func test_updateColorSampler(at point: NSPoint) {
        (contentView as? SelectionOverlayView)?.test_updateColorSampler(at: point)
    }

    func test_scrollWheel(at point: NSPoint, deltaY: CGFloat) {
        guard let overlayView = contentView as? SelectionOverlayView else {
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

    func test_mainToolbarButtonRect(for button: TestToolbarButton) -> NSRect? {
        (contentView as? SelectionOverlayView)?.test_mainToolbarButtonRect(for: button)
    }

    func test_mainToolbarButtonPoint(for button: TestToolbarButton) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_mainToolbarButtonPoint(for: button)
    }

    func test_symbolName(for button: TestToolbarButton) -> String? {
        (contentView as? SelectionOverlayView)?.test_symbolName(for: button)
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

    func test_measurementControlPoint(_ control: SelectionToolbarState.MeasurementControl) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_measurementControlPoint(control)
    }

    func test_optionsStrokeWidthPoint(at index: Int) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_optionsStrokeWidthPoint(at: index)
    }

    func test_optionsPaletteColorPoint(at index: Int) -> NSPoint? {
        (contentView as? SelectionOverlayView)?.test_optionsPaletteColorPoint(at: index)
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

    var test_selectedAnnotationShowsOutline: Bool {
        (contentView as? SelectionOverlayView)?.test_selectedAnnotationShowsOutline ?? false
    }

    var test_annotationCount: Int {
        (contentView as? SelectionOverlayView)?.test_annotationCount ?? 0
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
    private var backgroundImage: NSImage?
    private var backgroundBitmap: NSBitmapImageRep?
    private let settings: AppSettings
    private let featureGate: FeatureGate
    private let refreshHandler: (() async throws -> NSImage?)?
    private let colorSamplerSize = NSSize(width: 184, height: 188)
    private let mainToolbarButtonStep: CGFloat = 28
    private let mainToolbarHorizontalPadding: CGFloat = 4
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
        refreshHandler: (() async throws -> NSImage?)?
    ) {
        self.backgroundImage = backgroundImage
        self.settings = settings
        self.featureGate = featureGate
        self.refreshHandler = refreshHandler
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
        case draggingMosaicValue
        case movingShape
        case movingSelection
        case resizingShape
        case resizingArrowLine
        case resizingMarkerLine
        case rotatingBrush
        case rotatingMosaicRectangle
        case resizingSelection
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
    private var lockedSelectionRect: NSRect? {
        didSet {
            if oldValue != lockedSelectionRect {
                resetMosaicPreviewCaches()
            }
        }
    }
    private var shapeStartPoint: NSPoint?
    private var shapeCurrentPoint: NSPoint?
    private var brushDraftPoints: [NSPoint] = []
    private var mosaicDraftPoints: [NSPoint] = []
    private var annotations: [CaptureAnnotation] = []
    private var redoAnnotations: [CaptureAnnotation] = []
    private var selectedAnnotationIndex: Int?
    private var movingAnnotationStartRect: NSRect?
    private var movingAnnotationStartArrowLine: CaptureArrowLine?
    private var movingAnnotationStartBrushPath: CaptureBrushPath?
    private var movingAnnotationStartMarkerLine: CaptureMarkerLine?
    private var movingAnnotationStartMosaicStroke: CaptureMosaicStroke?
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
    private var currentStyle = CaptureAnnotationStyle()
    private var nonMarkerStyle = CaptureAnnotationStyle()
    private var markerStyle = SelectionToolbarState.markerActivationStyle(currentStyle: CaptureAnnotationStyle())
    private var mosaicRedactionType: CaptureMosaicRedactionType = .pixelMosaic
    private var mosaicRedactionValues: [CaptureMosaicRedactionType: Int] = [
        .gaussianBlur: SelectionToolbarState.mosaicDefaultRedactionValue(for: .gaussianBlur),
        .pixelMosaic: SelectionToolbarState.mosaicDefaultRedactionValue(for: .pixelMosaic),
    ]
    private var mosaicValueEditingText: String?
    private var mosaicDotIndex: Int = 1
    private var mosaicCompositeCache: [String: (image: NSImage, drawRect: NSRect)] = [:]
    private var mosaicDraftPreviewCache: [String: NSImage] = [:]
    private var mosaicDraftRedactedBaseCache: [String: NSImage] = [:]
    private var mosaicCompositeRenderCount = 0
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
        refreshAnimationTimer?.invalidate()
        colorSamplerCopySuccessTimer?.invalidate()
        selectionWheelAnimationTimer?.invalidate()
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

        cancelSelectionWheelAnimation()

        if isEyedropperToolActive, !isToolbarOrPanelPoint(point) {
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
                hoveredWindowRect = nil
                displayedWindowRect = nil
                pendingWindowSelectionRect = nil
                selectionStartPoint = nil
                selectionCurrentPoint = nil
                lockedSelectionRect = hoverRect
                interactionMode = .annotating
                window?.makeFirstResponder(self)
                updateColorSampler(at: point)
                NSLog("snipory overlay auto selection locked rect=(%.0f, %.0f, %.0f, %.0f)", hoverRect.minX, hoverRect.minY, hoverRect.width, hoverRect.height)
                invalidateCursorRectsAndRefresh(at: point)
                needsDisplay = true
                return
            }
            pendingWindowSelectionRect = nil
            selectionStartPoint = point
            selectionCurrentPoint = point
            updateColorSampler(at: point)
        case .annotating, .drawingShape, .draggingToolbar, .draggingCornerRadius, .draggingMosaicValue, .movingShape, .movingSelection, .resizingShape, .resizingArrowLine, .resizingMarkerLine, .rotatingBrush, .rotatingMosaicRectangle, .resizingSelection:
            handleAnnotatingMouseDown(at: point)
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isEyedropperToolActive, interactionMode == .annotating {
            updateColorSampler(at: point)
            needsDisplay = true
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
                if currentShapeKind == .mosaicStroke, mosaicDraftPoints.isEmpty {
                    mosaicDraftPoints = [shapeStartPoint ?? clampedPoint, clampedPoint]
                }
                let draftPoint = shapeCurrentPoint ?? clampedPoint
                appendBrushDraftPointIfNeeded(clampedPoint, modifierFlags: event.modifierFlags)
                appendMosaicDraftPointIfNeeded(draftPoint, modifierFlags: event.modifierFlags)
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

        if isEyedropperToolActive {
            if isToolbarOrPanelPoint(point) || !isInsideSelection {
                return .arrow
            }
            return .eyedropper
        }

        let selectionResizeHandle = interactionMode == .annotating && !shouldPreferMosaicDrawingOutsideSelection(at: point)
            ? selectionResizeHandle(at: point)
            : nil
        let shapeResizeHandle = interactionMode == .annotating ? resizeHandle(at: point)?.toolbarStateHandle : nil
        let isAnnotationBorder = interactionMode == .annotating && annotationIndexForBorder(at: point) != nil

        if interactionMode == .movingShape {
            return .move
        }

        if interactionMode == .annotating, mosaicRectangleRotationHitTarget(at: point) != nil {
            return .rotationHandle
        }

        if interactionMode == .annotating, shouldPreferMosaicDrawingBeforeAnnotationHitTesting(at: point) {
            return SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: isInsideSelection,
                isShapeToolActive: isShapeToolActive,
                currentShapeKind: currentShapeKind
            )
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

        if interactionMode == .rotatingMosaicRectangle {
            return .rotationHandle
        }

        if interactionMode == .rotatingBrush {
            return .resizeUpDown
        }

        if interactionMode == .resizingMarkerLine {
            return .resizeUpDown
        }

        if interactionMode == .annotating, markerRotationHitTarget(at: point) != nil {
            return .resizeUpDown
        }

        if interactionMode == .annotating, brushRotationHitTarget(at: point) != nil {
            return .resizeUpDown
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
        let style = cursorStyle(at: point)
        if currentShapeKind == .mosaicStroke, isShapeToolActive {
            if style == .crosshair {
                NSCursor.sniporyMosaicDot(diameter: SelectionToolbarState.mosaicCursorDotDiameter(for: currentStyle.strokeWidth)).set()
            } else {
                setCursor(style)
            }
            return
        }
        if currentShapeKind == .mosaicRectangle, isShapeToolActive {
            if style != .crosshair {
                if style == .rotationHandle {
                    NSCursor.sniporyMosaicRectangleRotationHandle.set()
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

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        NSLog("snipory overlay mouseUp mode=%@ point=(%.0f, %.0f)", "\(interactionMode)", point.x, point.y)

        if isEyedropperToolActive, interactionMode == .annotating {
            updateColorSampler(at: point)
            invalidateCursorRectsAndRefresh(at: point)
            needsDisplay = true
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
            let draftPoint = shapeCurrentPoint ?? clampedPoint
            appendBrushDraftPointIfNeeded(clampedPoint, modifierFlags: event.modifierFlags)
            appendMosaicDraftPointIfNeeded(draftPoint, modifierFlags: event.modifierFlags)
            if let draft = draftAnnotation, isUsableDraftAnnotation(draft) {
                annotations.append(draft)
                selectedAnnotationIndex = draft.kind == .brush || draft.kind == .mosaicStroke ? nil : annotations.indices.last
                currentShapeKind = draft.kind
                currentStyle = draft.style
                rememberCurrentStyleForActiveTool()
                activeShapeKind = draft.kind
                redoAnnotations.removeAll()
                if draft.kind == .mosaicStroke || draft.kind == .mosaicRectangle {
                    resetMosaicPreviewCaches()
                }
                NSLog("snipory overlay added annotation count=%ld rect=(%.0f, %.0f, %.0f, %.0f)", annotations.count, draft.rect.minX, draft.rect.minY, draft.rect.width, draft.rect.height)
            }
            shapeStartPoint = nil
            shapeCurrentPoint = nil
            brushDraftPoints.removeAll()
            mosaicDraftPoints.removeAll()
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
        case .annotating:
            break
        }

        invalidateCursorRectsAndRefresh(at: point)
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard handleScrollWheel(at: point, deltaY: event.scrollingDeltaY) else {
            super.scrollWheel(with: event)
            return
        }
    }

    override func magnify(with event: NSEvent) {
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
        if event.keyCode == 53 {
            selectionDidFinish?(nil)
            return true
        }

        if handleMosaicValueEditingKeyDown(event) {
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
        if isEyedropperToolActive, let lockedSelectionRect {
            addCursorRect(lockedSelectionRect.standardized, cursor: NSCursor.sniporyEyedropper)
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
        case .eyedropper:
            NSCursor.sniporyEyedropper.set()
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
        lockedSelectionRect
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
        if isEyedropperToolActive {
            let samplePoint = eyedropperSamplePoint(forMousePoint: point)
            guard SelectionToolbarState.shouldShowExplicitColorSampler(
                pointer: samplePoint,
                selectionRect: lockedSelectionRect
            ), !isToolbarOrPanelPoint(samplePoint) else {
                if sampledPointerPoint != nil || sampledColor != nil {
                    sampledPointerPoint = nil
                    sampledColor = nil
                    needsDisplay = true
                }
                return
            }

            guard let color = sampleCurrentColor(at: samplePoint) else {
                if sampledPointerPoint != nil || sampledColor != nil {
                    sampledPointerPoint = nil
                    sampledColor = nil
                    needsDisplay = true
                }
                return
            }

            sampledPointerPoint = samplePoint
            sampledColor = color
            needsDisplay = true
            return
        }

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

        guard let color = sampleColor(at: point) else {
            if sampledPointerPoint != nil || sampledColor != nil {
                sampledPointerPoint = nil
                sampledColor = nil
                needsDisplay = true
            }
            return
        }

        sampledPointerPoint = point
        sampledColor = color
        needsDisplay = true
    }

    private func eyedropperSamplePoint(forMousePoint point: NSPoint) -> NSPoint {
        NSPoint(
            x: point.x + SelectionToolbarState.eyedropperSampleOffset.width,
            y: point.y + SelectionToolbarState.eyedropperSampleOffset.height
        )
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
        guard lockedSelectionRect != nil, let selectionRect else {
            return nil
        }

        if let toolbar = mainToolbarRect(for: selectionRect) {
            for (button, rect) in toolbarButtonRects(in: toolbar) where rect.contains(point) {
                guard let title = SelectionToolbarState.tooltipTitle(for: tooltipIdentifier(for: button)) else {
                    return nil
                }
                return (title, rect)
            }
        }

        let measurementLayout = measurementControlLayout(for: selectionRect)
        if measurementLayout.cornerStyle.contains(point),
           let title = SelectionToolbarState.tooltipTitle(for: "cornerStyle") {
            return (title, measurementLayout.cornerStyle)
        }
        if measurementLayout.aspectRatio.contains(point) {
            let identifier = isSelectionAspectRatioLocked ? "aspectRatioLockedOn" : "aspectRatioLockedOff"
            if let title = SelectionToolbarState.tooltipTitle(for: identifier) {
                return (title, measurementLayout.aspectRatio)
            }
        }
        if measurementLayout.refresh.contains(point),
           let title = SelectionToolbarState.tooltipTitle(for: "refreshCapture") {
            return (title, measurementLayout.refresh)
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
            let identifier = optionsToolbarMode == .mosaic ? "mosaicRectangle" : "shapeRectangle"
            if rectangleButton.contains(point), let title = SelectionToolbarState.tooltipTitle(for: identifier) {
                return (title, rectangleButton)
            }
        }

        if let ellipseButton = layout.ellipseMode,
           ellipseButton.contains(point),
           let title = SelectionToolbarState.tooltipTitle(for: "shapeEllipse") {
            return (title, ellipseButton)
        }

        if optionsToolbarMode == .mosaic {
            let redactionTypeRect = optionButtonBackgroundRect(for: SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsRect))
            if redactionTypeRect.contains(point) {
                let identifier = mosaicRedactionType == .gaussianBlur ? "mosaicBlur" : "mosaicPixel"
                if let title = SelectionToolbarState.tooltipTitle(for: identifier) {
                    return (title, redactionTypeRect)
                }
            }
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
        case .settings:
            return "settings"
        }
    }

    private func handleAnnotatingMouseDown(at point: NSPoint) {
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

        guard lockedSelectionRect != nil else {
            return
        }

        if let mosaicHit = mosaicRectangleRotationHitTarget(at: point) {
            NSCursor.sniporyMosaicRectangleRotationHandle.set()
            selectAnnotation(at: mosaicHit)
            rotatingMosaicRectangleStartPointerAngle = angle(from: mosaicRectangleCenter(for: annotations[mosaicHit]), to: point)
            rotatingMosaicRectangleStartAnnotationAngle = annotations[mosaicHit].rotationAngle
            interactionMode = .rotatingMosaicRectangle
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
            needsDisplay = true
            return
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
        mosaicDraftPoints = currentShapeKind == .mosaicStroke ? [point] : []
        interactionMode = .drawingShape
        NSLog("snipory overlay drawing started point=(%.0f, %.0f)", point.x, point.y)
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

        if resizeHandle(at: point) != nil {
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
                NSLog("Snipory refresh background failed: \(error.localizedDescription)")
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
        resetMosaicPreviewCaches()
    }

    private func draftEndPoint(rawEnd: NSPoint, modifierFlags: NSEvent.ModifierFlags) -> NSPoint {
        guard let shapeStartPoint else {
            return rawEnd
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

        return rawEnd
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
        movingAnnotationStartMosaicStroke = overlayMosaicStroke(fromLocalMosaicStroke: annotations[index].mosaicStroke)
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
        case .eyedropper:
            toggleEyedropperTool()
        case .mosaic:
            toggleShapeTool(.mosaicRectangle)
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
        case .pin, .text, .number, .magnifier, .eraser, .scroll, .settings:
            showPlaceholder(for: button)
        }

        needsDisplay = true
    }

    private func toggleEyedropperTool() {
        if isEyedropperToolActive {
            isEyedropperToolActive = false
            invalidateCursorRectsAndRefresh()
            return
        }

        rememberCurrentStyleForActiveTool()
        isEyedropperToolActive = true
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

    private func toggleShapeTool(_ shape: CaptureAnnotationKind) {
        rememberCurrentStyleForActiveTool()
        isEyedropperToolActive = false
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
        rememberCurrentStyleForActiveTool()
        isEyedropperToolActive = false
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

#if DEBUG
    func test_setLockedSelectionRect(_ rect: NSRect) {
        cancelSelectionWheelAnimation()
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
        rememberCurrentStyleForActiveTool()
    }

    func test_setCurrentStrokeWidth(_ width: CGFloat) {
        currentStyle.strokeWidth = width
        rememberCurrentStyleForActiveTool()
    }

    func test_setAnnotations(_ newAnnotations: [CaptureAnnotation]) {
        annotations = newAnnotations
        redoAnnotations.removeAll()
        selectedAnnotationIndex = nil
        resetMosaicPreviewCaches()
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
        handleScrollWheel(at: point, deltaY: deltaY)
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

    func test_mainToolbarButtonRect(for button: TestToolbarButton) -> NSRect? {
        guard let selectionRect, let toolbar = mainToolbarRect(for: selectionRect) else {
            return nil
        }
        let toolbarButton: ToolbarButton
        switch button {
        case .rectangle:
            toolbarButton = .rectangle
        case .marker:
            toolbarButton = .marker
        case .eyedropper:
            toolbarButton = .eyedropper
        case .mosaic:
            toolbarButton = .mosaic
        case .settings:
            toolbarButton = .settings
        }
        return toolbarButtonRects(in: toolbar).first(where: { $0.0 == toolbarButton })?.1
    }

    func test_symbolName(for button: TestToolbarButton) -> String {
        let toolbarButton: ToolbarButton
        switch button {
        case .rectangle:
            toolbarButton = .rectangle
        case .marker:
            toolbarButton = .marker
        case .eyedropper:
            toolbarButton = .eyedropper
        case .mosaic:
            toolbarButton = .mosaic
        case .settings:
            toolbarButton = .settings
        }
        return symbolName(for: toolbarButton)
    }

    func test_mainToolbarButtonPoint(for button: TestToolbarButton) -> NSPoint? {
        guard let rect = test_mainToolbarButtonRect(for: button) else {
            return nil
        }
        return NSPoint(x: rect.midX, y: rect.midY)
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

    func test_measurementControlPoint(_ control: SelectionToolbarState.MeasurementControl) -> NSPoint? {
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

    func test_mosaicRectangleOptionPoint() -> NSPoint? {
        guard let optionsToolbarRect else {
            return nil
        }
        guard let rect = optionsToolbarLayout(in: optionsToolbarRect).rectangleMode else {
            return nil
        }
        return NSPoint(x: rect.midX, y: rect.midY)
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
            rotationAngle: annotation.kind == .mosaicRectangle ? annotation.rotationAngle : 0
        )
        return NSPoint(x: rectForHandle.midX, y: rectForHandle.midY)
    }

    func test_mosaicRectangleRotationHandlePoint() -> NSPoint? {
        guard let selectedAnnotation, selectedAnnotation.kind == .mosaicRectangle else {
            return nil
        }
        return mosaicRectangleRotationHandlePoint(for: selectedAnnotation)
    }

    func test_mosaicRectangleRotationHandleGlyph() -> TestMosaicRectangleRotationHandleGlyph? {
        guard selectedAnnotation?.kind == .mosaicRectangle else {
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

    var test_optionsToolbarMode: SelectionToolbarState.OptionsToolbarMode? {
        guard isShapeToolActive else {
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

    var test_isColorSamplerVisible: Bool {
        sampledPointerPoint != nil && sampledColor != nil
    }

    var test_sampledColorHex: String? {
        sampledColor.map { SelectionToolbarState.colorSamplerHexString(for: $0) }
    }

    var test_sampledPointerPoint: NSPoint? {
        sampledPointerPoint
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
        if removed.kind == .mosaicStroke || removed.kind == .mosaicRectangle {
            resetMosaicPreviewCaches()
        }
        needsDisplay = true
    }

    private func redoLastAnnotation() {
        guard let restored = redoAnnotations.popLast() else {
            return
        }
        annotations.append(restored)
        selectedAnnotationIndex = annotations.indices.last
        if restored.kind == .mosaicStroke || restored.kind == .mosaicRectangle {
            resetMosaicPreviewCaches()
        }
        needsDisplay = true
    }

    private func deleteSelectedAnnotation() -> Bool {
        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else {
            return false
        }

        let removed = annotations[selectedAnnotationIndex]
        annotations.remove(at: selectedAnnotationIndex)
        self.selectedAnnotationIndex = nil
        redoAnnotations.removeAll()
        showsStrokeStyleMenu = false
        showsCornerRadiusPanel = false
        showsStartArrowTypeMenu = false
        showsEndArrowTypeMenu = false
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
        if optionsToolbarMode == .mosaic {
            return handleMosaicOptionsClick(at: point, optionsRect: optionsRect)
        }
        let layout = optionsToolbarLayout(in: optionsRect)
        let strokeWidths = SelectionToolbarState.strokeWidthValues(for: optionsToolbarMode)

        for (index, rect) in layout.strokeWidths.enumerated() where rect.contains(point) {
            currentStyle.strokeWidth = strokeWidths[index]
            rememberCurrentStyleForActiveTool()
            applyCurrentStyleToSelectedAnnotation()
            return true
        }

        if let fillRect = layout.fillToggle, fillRect.contains(point) {
            currentStyle.fillEnabled.toggle()
            rememberCurrentStyleForActiveTool()
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

        if !optionsRect.contains(point) {
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            showsStartArrowTypeMenu = false
            showsEndArrowTypeMenu = false
            return false
        }

        return true
    }

    private func handleMosaicOptionsClick(at point: NSPoint, optionsRect: NSRect) -> Bool {
        /*
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
        */

        let valueRect = SelectionToolbarState.mosaicRedactionValueRect(in: optionsRect)
        if valueRect.contains(point) {
            beginMosaicValueEditing()
            updateMosaicValue(from: point)
            interactionMode = .draggingMosaicValue
            return true
        }

        /*
        if let rectangleRect = layout.rectangleMode, rectangleRect.contains(point) {
            commitMosaicValueEditing()
            if currentShapeKind != .mosaicRectangle {
                selectedAnnotationIndex = nil
            }
            activateShapeTool(.mosaicRectangle)
            return true
        }
        */

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
        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else {
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
        case .mosaicStroke, .mosaicRectangle:
            return kind == .mosaicStroke || kind == .mosaicRectangle
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

    private func applyCurrentStyleToSelectedAnnotation() {
        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else {
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
        let rotationAngle = annotation.kind == .mosaicRectangle ? annotation.rotationAngle : 0
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
        guard let selectedAnnotationIndex,
              annotations.indices.contains(selectedAnnotationIndex),
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
        for index in annotations.indices.reversed() where annotations[index].kind == .marker {
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
        NSCursor.resizeUpDown.set()
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
        NSCursor.resizeUpDown.set()
    }

    private func updateRotatingMosaicRectangle(to point: NSPoint) {
        guard
            let selectedAnnotationIndex,
            annotations.indices.contains(selectedAnnotationIndex),
            annotations[selectedAnnotationIndex].kind == .mosaicRectangle,
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
        handleSelectionZoom(at: point, deltaY: deltaY)
    }

    private func handleMagnify(at point: NSPoint, magnification: CGFloat) -> Bool {
        handleSelectionZoom(at: point, deltaY: magnification * 60)
    }

    private func handleSelectionZoom(at point: NSPoint, deltaY: CGFloat) -> Bool {
        guard let lockedSelectionRect else {
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
        if let backgroundImage {
            backgroundImage.draw(in: bounds, from: NSRect(origin: .zero, size: backgroundImage.size), operation: .copy, fraction: 1)
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
                    isMosaicAnnotation(annotation) && index != liveValueIndex ? annotation : nil
                }
                if let composite = mosaicPreviewComposite(for: mosaicAnnotations) {
                    drawMosaicComposite(composite, clippedTo: mosaicAnnotations)
                }
                if let liveValueIndex {
                    drawLiveMosaicValuePreview(at: liveValueIndex)
                }
            }
            if let draftAnnotation, isMosaicAnnotation(draftAnnotation) {
                drawMosaicDraftPreview(draftAnnotation)
            }
            for (index, annotation) in annotations.enumerated()
                where annotation.kind == .mosaicRectangle
                && selectedAnnotationIndex == index
                && shouldDrawSelectedAnnotationOutline(annotation) {
                drawSelectedAnnotationOutline(annotation)
            }
        }

        guard let selectionRect else {
            NSColor.black.withAlphaComponent(0.34).setFill()
            bounds.fill()
            return
        }

        let path = NSBezierPath(rect: bounds)
        path.append(selectionPath(in: selectionRect))
        path.windingRule = .evenOdd

        NSColor.black.withAlphaComponent(0.34).setFill()
        path.fill()
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
        let textSize = NSString(string: label).size(withAttributes: attributes)
        let layout = SelectionToolbarState.measurementControlLayout(
            anchoredTo: rect,
            textSize: textSize,
            inside: safeLayoutBounds
        )

        NSColor(calibratedWhite: 0.12, alpha: 0.86).setFill()
        NSBezierPath(roundedRect: layout.panel, xRadius: 5, yRadius: 5).fill()
        NSString(string: label).draw(in: layout.label.insetBy(dx: 9, dy: 4), withAttributes: attributes)
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
        return SelectionToolbarState.measurementControlLayout(
            anchoredTo: rect,
            textSize: NSString(string: label).size(withAttributes: attributes),
            inside: safeLayoutBounds
        )
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
        let alreadyRenderedWithMosaicOrdering = shouldRenderAnnotationsWithMosaicOrdering
        for (index, annotation) in annotations.enumerated() {
            if isMosaicAnnotation(annotation) {
                continue
            }
            if !alreadyRenderedWithMosaicOrdering {
                drawAnnotation(annotation, inOverlay: true)
            }
            if selectedAnnotationIndex == index, shouldDrawSelectedAnnotationOutline(annotation) {
                drawSelectedAnnotationOutline(annotation)
            }
        }
    }

    private var shouldRenderAnnotationsWithMosaicOrdering: Bool {
        guard backgroundImage != nil else {
            return false
        }

        let orderedAnnotations = draftAnnotation.map { annotations + [$0] } ?? annotations
        return needsSequentialMosaicComposite(for: orderedAnnotations)
    }

    private func isMosaicAnnotation(_ annotation: CaptureAnnotation) -> Bool {
        annotation.kind == .mosaicStroke || annotation.kind == .mosaicRectangle
    }

    private func needsSequentialMosaicComposite(for annotations: [CaptureAnnotation]) -> Bool {
        var hasEarlierNonMosaicAnnotation = false
        for annotation in annotations {
            if isMosaicAnnotation(annotation) {
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
        for (index, annotation) in annotations.enumerated() {
            if isMosaicAnnotation(annotation) {
                if rotatingIndex == index, drawRotatingMosaicRectanglePreview(at: index) {
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

    private func drawMosaicRectangleDraftBorder(_ annotation: CaptureAnnotation) {
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect)
        let path = rotatedRectanglePath(for: rect, angle: annotation.rotationAngle)
        NSColor.systemBlue.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 0.6
        path.stroke()
    }

    private func drawMosaicDraftPreview(_ annotation: CaptureAnnotation) {
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

    private func drawMosaicComposite(
        _ composite: (image: NSImage, drawRect: NSRect),
        clippedTo annotations: [CaptureAnnotation]
    ) {
        let clipPath = NSBezierPath()
        annotations.compactMap(mosaicDraftClipPath).forEach { clipPath.append($0) }
        guard clipPath.elementCount > 0 else {
            return
        }

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

    private func drawRotatingMosaicRectanglePreview(at selectedIndex: Int) -> Bool {
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
        if let baseComposite = mosaicPreviewComposite(for: earlierAnnotations) {
            drawMosaicComposite(baseComposite, clippedTo: earlierAnnotations)
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
        let baseImage: NSImage
        let baseKey: String
        if let baseComposite = mosaicPreviewComposite(for: resolvedBaseAnnotations) {
            baseImage = baseComposite.image
            baseKey = mosaicCompositeKey(for: resolvedBaseAnnotations, backgroundImage: backgroundImage)
        } else {
            baseImage = backgroundImage
            baseKey = mosaicBackgroundKey(for: backgroundImage)
        }

        guard let preview = mosaicLocalPreview(
            for: annotations[selectedIndex],
            baseImage: baseImage,
            baseKey: baseKey
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
        case .arrowLine, .brush, .marker, .mosaicStroke, .mosaicRectangle:
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

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setBlendMode(.multiply)
        let markerColor = annotation.style.strokeColor.withAlphaComponent(CaptureAnnotationRenderer.markerOpacity)
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
        let outline: NSBezierPath
        if annotation.kind == .mosaicRectangle {
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
        drawResizeHandles(
            for: rect,
            kind: annotation.kind,
            rotationAngle: annotation.kind == .mosaicRectangle ? annotation.rotationAngle : 0
        )
        if annotation.kind == .mosaicRectangle, let point = mosaicRectangleRotationHandlePoint(for: annotation) {
            drawMosaicRectangleRotationHandle(at: point)
        }
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
        for center in handles {
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
            if button == .settings {
                drawMainToolbarDragHandle(rect, enabled: enabled)
                continue
            }
            drawToolbarButton(rect, symbol: symbolName(for: button, enabled: enabled), selected: buttonMatchesCurrentTool(button), enabled: enabled)
            if button == .number {
                drawNumberToolDisclosure(in: rect, enabled: enabled)
            }
        }
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
                    rowOffset: centerIndex - row
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
        }
        if SelectionToolbarState.showsStrokeStyleField(for: optionsToolbarMode) {
            drawStrokeStyleField(in: optionsRect)
        }
        if optionsToolbarMode != .mosaic {
            drawColorSwatches(in: optionsRect)
        }
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
        case .mosaic:
            break
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

    private func drawMosaicModeControls(in optionsRect: NSRect) {
        /*
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
        drawMosaicRectangleGlyph(in: rectangleRect)
        */

        let redactionTypeRect = SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsRect)
        drawToolbarButton(optionButtonBackgroundRect(for: redactionTypeRect), symbol: nil, selected: true, enabled: true)
        if mosaicRedactionType == .gaussianBlur {
            drawMosaicGaussianGlyph(
                in: redactionTypeRect.insetBy(dx: 2, dy: 2),
                value: mosaicPreviewValue(for: .gaussianBlur)
            )
        } else {
            drawMosaicPixelGlyph(
                in: redactionTypeRect.insetBy(dx: 2, dy: 2),
                value: mosaicPreviewValue(for: .pixelMosaic)
            )
        }

        let valueRect = SelectionToolbarState.mosaicRedactionValueRect(in: optionsRect)
        drawToolbarButton(valueRect, symbol: nil, selected: false, enabled: true)
        drawMosaicValueControl(in: valueRect)
    }

    private func mosaicShapeGlyphColor() -> NSColor {
        NSColor(calibratedWhite: 0.46, alpha: 1)
    }

    private func drawMosaicCircleModeGlyph(in rect: NSRect) {
        mosaicShapeGlyphColor().setFill()
        let side: CGFloat = 15
        NSBezierPath(ovalIn: NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)).fill()
    }

    private func drawMosaicGaussianGlyph(in rect: NSRect, value: Int) {
        let progress = SelectionToolbarState.mosaicPreviewProgress(for: value)
        let circleRect = rect.insetBy(dx: 1, dy: 1)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let baseDiameter: CGFloat = 7.5 + progress * 3
        let blurExpansion: CGFloat = 2.5 + progress * 3

        SelectionToolbarState.mosaicPreviewBackgroundColor(for: value).setFill()
        let circlePath = NSBezierPath(ovalIn: circleRect)
        circlePath.fill()

        NSColor(calibratedWhite: 0.42, alpha: 1).setStroke()
        circlePath.lineWidth = 1.4
        circlePath.stroke()

        NSColor(calibratedWhite: 0.38, alpha: 0.18 + progress * 0.18).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - (baseDiameter + blurExpansion) / 2,
                y: center.y - (baseDiameter + blurExpansion) / 2,
                width: baseDiameter + blurExpansion,
                height: baseDiameter + blurExpansion
            )
        ).fill()

        NSColor(calibratedWhite: 0.34, alpha: 0.32 + progress * 0.22).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - (baseDiameter + blurExpansion * 0.55) / 2,
                y: center.y - (baseDiameter + blurExpansion * 0.55) / 2,
                width: baseDiameter + blurExpansion * 0.55,
                height: baseDiameter + blurExpansion * 0.55
            )
        ).fill()

        NSColor(calibratedWhite: 0.30, alpha: 0.82).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - baseDiameter / 2,
                y: center.y - baseDiameter / 2,
                width: baseDiameter,
                height: baseDiameter
            )
        ).fill()
    }

    private func drawMosaicPixelGlyph(in rect: NSRect, value: Int) {
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
        let colors = [
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

    private func drawMosaicRectangleGlyph(in rect: NSRect) {
        mosaicShapeGlyphColor().setFill()
        let side: CGFloat = 15
        NSBezierPath(roundedRect: NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side), xRadius: 1.5, yRadius: 1.5).fill()
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

        guard let composite = mosaicPreviewComposite(for: annotations) else {
            return sampleColor(at: point)
        }

        return sampleColor(at: point, in: composite.image)
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
        let color = toolbarIconColor(enabled: enabled, selected: selected)
        color.set()

        let resourceName = name.replacingOccurrences(of: "toolbar-", with: "")
        let imageInset = toolbarIconInset(for: resourceName)
        let usesFixedColorResource = SelectionToolbarState.usesFixedColorToolbarIconResource(resourceName)
        if drawToolbarImage(named: resourceName, in: rect, template: !usesFixedColorResource, enabled: enabled, selected: selected, inset: imageInset)
            || drawToolbarImage(named: name, in: rect, template: !usesFixedColorResource, enabled: enabled, selected: selected, inset: imageInset) {
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

        if mainToolbarLeadingDragHandleRect(in: toolbar).contains(point)
            || mainToolbarDragHandleRect(in: toolbar).contains(point) {
            return true
        }

        return toolbarButtonRects(in: toolbar)
            .filter { $0.0 != .settings }
            .allSatisfy { !$0.1.insetBy(dx: -2, dy: -2).contains(point) }
    }

    private func mainToolbarDragHandleRect(in toolbar: NSRect) -> NSRect {
        toolbarButtonRects(in: toolbar).first(where: { $0.0 == .settings })?.1 ?? .zero
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
        return mainToolbarHorizontalPadding + mainToolbarButtonStep + mainToolbarButtons().reduce(CGFloat(0)) { width, button in
            width + mainToolbarButtonStep + mainToolbarExtraGap(after: button)
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
        case .eyedropper:
            return "toolbar-eyedropper"
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
        case .eyedropper:
            return isEyedropperToolActive
        case .mosaic:
            return isShapeToolActive && (currentShapeKind == .mosaicStroke || currentShapeKind == .mosaicRectangle)
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

        if let lockedSelectionRect,
           measurementControlLayout(for: lockedSelectionRect).panel.contains(point) {
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
        case .mosaicStroke, .mosaicRectangle:
            return .mosaic
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
                height: SelectionToolbarState.optionsToolbarHeight(paletteCount: visiblePaletteCount, mode: optionsToolbarMode)
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
        guard let backgroundImage, !annotations.isEmpty else {
            return nil
        }
        let cacheKey = mosaicCompositeKey(for: annotations, backgroundImage: backgroundImage)
        if let composite = mosaicCompositeCache[cacheKey] {
            return composite
        }

        let rendered = CaptureAnnotationRenderer.render(
            image: backgroundImage,
            annotations: annotations.map(overlayAnnotation)
        )
        mosaicCompositeRenderCount += 1
        let composite = (rendered, bounds)
        mosaicCompositeCache[cacheKey] = composite
        return composite
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

    private func mosaicCompositeKey(for annotations: [CaptureAnnotation], backgroundImage: NSImage) -> String {
        var parts: [String] = [
            mosaicBackgroundKey(for: backgroundImage),
            "selection:\(mosaicKey(lockedSelectionRect ?? .zero))",
        ]
        parts.reserveCapacity(annotations.count + 2)
        annotations.forEach { parts.append(annotationCompositeKey($0)) }
        return parts.joined(separator: "|")
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
            return nil
        }
        mosaicDraftPreviewCache[cacheKey] = preview
        return (preview, drawRect)
    }

    private func mosaicLocalPreview(
        for annotation: CaptureAnnotation,
        baseImage: NSImage,
        baseKey: String
    ) -> (image: NSImage, drawRect: NSRect)? {
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
            return (cached, drawRect)
        }

        let processingRect = mosaicLocalPreviewProcessingRect(
            for: drawRect,
            redaction: redaction,
            imageSize: baseImage.size
        )
        guard let processingBaseCrop = crop(image: baseImage, to: processingRect) else {
            return nil
        }

        let redactedCropKey = [
            "crop",
            baseKey,
            "\(redaction.type)",
            "\(redaction.value)",
            mosaicKey(processingRect),
        ].joined(separator: "|")
        let redactedProcessingCrop: NSImage
        if let cached = mosaicDraftRedactedBaseCache[redactedCropKey] {
            redactedProcessingCrop = cached
        } else {
            redactedProcessingCrop = CaptureAnnotationRenderer.redactedPreview(image: processingBaseCrop, redaction: redaction)
            mosaicDraftRedactedBaseCache[redactedCropKey] = redactedProcessingCrop
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
            return nil
        }

        guard let preview = mosaicMaskedPreview(
            baseCrop: baseCrop,
            redactedCrop: redactedCrop,
            annotation: annotation,
            drawRect: drawRect
        ) else {
            return nil
        }
        mosaicDraftPreviewCache[cacheKey] = preview
        return (preview, drawRect)
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

    private func mosaicDraftPreviewBaseImage() -> NSImage {
        mosaicPreviewComposite(for: annotations)?.image ?? backgroundImage ?? NSImage(size: bounds.size)
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
        let cacheKey = [
            baseKey,
            "\(redaction.type)",
            "\(redaction.value)",
        ].joined(separator: "|")
        if let cached = mosaicDraftRedactedBaseCache[cacheKey] {
            return cached
        }

        let redacted = CaptureAnnotationRenderer.redactedPreview(image: baseImage, redaction: redaction)
        mosaicDraftRedactedBaseCache[cacheKey] = redacted
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

        let image = NSImage(size: drawRect.size)
        image.lockFocus()
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
        image.unlockFocus()
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
        return drawRect.isEmpty ? bounds : drawRect
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
        mosaicCompositeCache.removeAll()
        resetMosaicRedactionPreviewCaches()
    }

    private func resetMosaicRedactionPreviewCaches() {
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
        for index in annotations.indices.reversed() where annotations[index].kind == .mosaicRectangle {
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
        guard annotation.kind == .mosaicRectangle else {
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

    private func rotatedAnnotationRectContains(_ point: NSPoint, annotation: CaptureAnnotation, hitOutset: CGFloat) -> Bool {
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect).standardized.insetBy(dx: -hitOutset, dy: -hitOutset)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let unrotatedPoint = rotatedPoint(point, around: center, angle: -annotation.rotationAngle)
        return rect.contains(unrotatedPoint)
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
