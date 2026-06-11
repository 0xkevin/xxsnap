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
    private let selectionHandler: (CaptureSelectionResult?) -> Void
    private var didCompleteSelection = false

    init(backgroundImage: NSImage?, selectionHandler: @escaping (CaptureSelectionResult?) -> Void) {
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

        let overlayView = SelectionOverlayView(frame: NSRect(origin: .zero, size: frame.size), backgroundImage: backgroundImage)
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
}

private final class SelectionOverlayView: NSView {
    var selectionDidFinish: ((CaptureSelectionResult?) -> Void)?
    private let backgroundImage: NSImage?
    private let backgroundBitmap: NSBitmapImageRep?
    private let colorSamplerSize = NSSize(width: 184, height: 188)

    init(frame frameRect: NSRect, backgroundImage: NSImage?) {
        self.backgroundImage = backgroundImage
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
        case ocr
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

    private let colors: [NSColor] = [
        NSColor(calibratedRed: 0 / 255, green: 0 / 255, blue: 0 / 255, alpha: 1),
        NSColor(calibratedRed: 116 / 255, green: 116 / 255, blue: 115 / 255, alpha: 1),
        NSColor(calibratedRed: 112 / 255, green: 25 / 255, blue: 25 / 255, alpha: 1),
        NSColor(calibratedRed: 209 / 255, green: 54 / 255, blue: 41 / 255, alpha: 1),
        NSColor(calibratedRed: 233 / 255, green: 124 / 255, blue: 50 / 255, alpha: 1),
        NSColor(calibratedRed: 250 / 255, green: 241 / 255, blue: 56 / 255, alpha: 1),
        NSColor(calibratedRed: 76 / 255, green: 164 / 255, blue: 74 / 255, alpha: 1),
        NSColor(calibratedRed: 70 / 255, green: 148 / 255, blue: 224 / 255, alpha: 1),
        NSColor(calibratedRed: 62 / 255, green: 62 / 255, blue: 192 / 255, alpha: 1),
        NSColor(calibratedRed: 141 / 255, green: 70 / 255, blue: 151 / 255, alpha: 1),
        NSColor(calibratedRed: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 1),
        NSColor(calibratedRed: 187 / 255, green: 188 / 255, blue: 186 / 255, alpha: 1),
        NSColor(calibratedRed: 164 / 255, green: 114 / 255, blue: 81 / 255, alpha: 1),
        NSColor(calibratedRed: 240 / 255, green: 169 / 255, blue: 193 / 255, alpha: 1),
        NSColor(calibratedRed: 242 / 255, green: 197 / 255, blue: 50 / 255, alpha: 1),
        NSColor(calibratedRed: 234 / 255, green: 225 / 255, blue: 171 / 255, alpha: 1),
        NSColor(calibratedRed: 182 / 255, green: 223 / 255, blue: 56 / 255, alpha: 1),
        NSColor(calibratedRed: 159 / 255, green: 209 / 255, blue: 230 / 255, alpha: 1),
        NSColor(calibratedRed: 109 / 255, green: 133 / 255, blue: 180 / 255, alpha: 1),
        NSColor(calibratedRed: 192 / 255, green: 184 / 255, blue: 225 / 255, alpha: 1),
    ]
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
    private var annotations: [CaptureAnnotation] = []
    private var redoAnnotations: [CaptureAnnotation] = []
    private var selectedAnnotationIndex: Int?
    private var movingAnnotationStartRect: NSRect?
    private var movingAnnotationOffset = NSPoint.zero
    private var movingSelectionStartRect: NSRect?
    private var movingSelectionPointerOffset = NSPoint.zero
    private var movingSelectionBounds: NSRect?
    private var movingSelectionStartAnnotationRects: [NSRect] = []
    private var mainToolbarOffset = NSSize.zero
    private var toolbarDragStartPoint: NSPoint?
    private var toolbarDragStartOffset = NSSize.zero
    private var activeResizeHandle: ShapeResizeHandle?
    private var resizingAnnotationStartRect: NSRect?
    private var activeSelectionResizeHandle: SelectionToolbarState.OverlayResizeHandle?
    private var resizingSelectionStartRect: NSRect?
    private var resizingSelectionStartAnnotationRects: [NSRect] = []
    private var currentShapeKind = CaptureAnnotationKind.rectangle
    private var activeShapeKind: CaptureAnnotationKind?
    private var isShapeToolActive = false
    private var currentStyle = CaptureAnnotationStyle()
    private var customColor: NSColor?
    private var isCustomColorSwatchActive = false
    private var showsCornerRadiusPanel = false
    private var showsStrokeStyleMenu = false
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
        if showsStrokeStyleMenu {
            drawStrokeStyleMenu(for: selectionRect)
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
        case .annotating, .drawingShape, .draggingToolbar, .draggingCornerRadius, .movingShape, .movingSelection, .resizingShape, .resizingSelection:
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
        case .drawingShape:
            shapeCurrentPoint = clamp(point, to: bounds)
        case .draggingToolbar:
            updateDraggingToolbar(to: point)
        case .annotating:
            if isShapeToolActive {
                shapeStartPoint = shapeStartPoint ?? clamp(point, to: bounds)
                shapeCurrentPoint = clamp(point, to: bounds)
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
        case .resizingSelection:
            updateResizingSelection(to: point)
        }

        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHoverState(at: point)
        updateColorSampler(at: point)
        if isMainToolbarDragPoint(point) {
            NSCursor.sniporyMove.set()
            return
        }
        setCursor(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: interactionMode == .selecting,
                isToolbarOrPanelPoint: isToolbarOrPanelPoint(point),
                resizeHandle: interactionMode == .annotating ? resizeHandle(at: point)?.toolbarStateHandle : nil,
                selectionResizeHandle: interactionMode == .annotating ? selectionResizeHandle(at: point) : nil,
                isAnnotationBorder: interactionMode == .annotating && annotationIndexForBorder(at: point) != nil,
                isInsideSelection: colorSamplerSelectionRect?.standardized.contains(point) == true
            )
        )
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
            shapeCurrentPoint = clamp(point, to: bounds)
            if let draft = draftAnnotation, draft.rect.width >= 8, draft.rect.height >= 8 {
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
        case .resizingSelection:
            commitSelectionResize()
            interactionMode = .annotating
        case .annotating:
            break
        }

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
        addCursorRect(bounds, cursor: interactionMode == .selecting ? .crosshair : .arrow)
        if let lockedSelectionRect {
            addCursorRect(lockedSelectionRect, cursor: .crosshair)
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
        lockedSelectionRect ?? displayedWindowRect ?? hoveredWindowRect
    }

    private var draftAnnotation: CaptureAnnotation? {
        guard let shapeStartPoint, let shapeCurrentPoint, lockedSelectionRect != nil else {
            return nil
        }

        let rect = NSRect(
            x: min(shapeStartPoint.x, shapeCurrentPoint.x),
            y: min(shapeStartPoint.y, shapeCurrentPoint.y),
            width: abs(shapeCurrentPoint.x - shapeStartPoint.x),
            height: abs(shapeCurrentPoint.y - shapeStartPoint.y)
        )

        return CaptureAnnotation(kind: currentShapeKind, rect: localAnnotationRect(from: rect), style: currentStyle)
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

        for (index, rect) in strokeWidthRects(in: optionsRect).enumerated() where rect.contains(point) {
            let identifiers = ["strokeWidthThin", "strokeWidthMedium", "strokeWidthThick"]
            return (SelectionToolbarState.tooltipTitle(for: identifiers[index]) ?? "线条粗细", rect)
        }

        let fillRect = fillToggleRect(in: optionsRect)
        if fillRect.contains(point), let title = SelectionToolbarState.tooltipTitle(for: "fill") {
            return (title, fillRect)
        }

        let rectangleButton = shapeModeBackgroundRect(for: rectangleModeButtonRect(in: optionsRect))
        if rectangleButton.contains(point), let title = SelectionToolbarState.tooltipTitle(for: "shapeRectangle") {
            return (title, rectangleButton)
        }

        let ellipseButton = ellipseModeButtonRect(in: optionsRect)
        if ellipseButton.contains(point), let title = SelectionToolbarState.tooltipTitle(for: "shapeEllipse") {
            return (title, ellipseButton)
        }

        let strokeStyle = strokeStyleFieldRect(in: optionsRect)
        if strokeStyle.contains(point), let title = SelectionToolbarState.tooltipTitle(for: "strokeStyle") {
            return (title, strokeStyle)
        }

        for (index, rect) in colorSwatchRects(in: optionsRect).enumerated() where rect.insetBy(dx: -4, dy: -4).contains(point) {
            if index == colors.count, let title = SelectionToolbarState.tooltipTitle(for: "customColor") {
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
        case .ocr:
            return "ocr"
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

        if handleCornerRadiusPanelClick(at: point) || handleStrokeStyleMenuClick(at: point) || handleOptionsClick(at: point) {
            return
        }

        guard lockedSelectionRect != nil else {
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
            movingAnnotationStartRect = overlayRect(fromLocalAnnotationRect: annotations[hitIndex].rect)
            movingAnnotationOffset = NSPoint(
                x: point.x - (movingAnnotationStartRect?.minX ?? point.x),
                y: point.y - (movingAnnotationStartRect?.minY ?? point.y)
            )
            interactionMode = .movingShape
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            needsDisplay = true
            return
        case .selectionResize(let handle):
            activeSelectionResizeHandle = handle
            resizingSelectionStartRect = lockedSelectionRect?.standardized
            resizingSelectionStartAnnotationRects = annotations.map { overlayRect(fromLocalAnnotationRect: $0.rect) }
            interactionMode = .resizingSelection
            selectedAnnotationIndex = nil
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            needsDisplay = true
            return
        case .selectionMove:
            startSelectionMoveIfPossible(at: point)
            needsDisplay = true
            return
        case .none:
            break
        }

        guard isShapeToolActive else {
            selectedAnnotationIndex = nil
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            needsDisplay = true
            return
        }

        selectedAnnotationIndex = nil
        shapeStartPoint = point
        shapeCurrentPoint = point
        interactionMode = .drawingShape
        NSLog("snipory overlay drawing started point=(%.0f, %.0f)", point.x, point.y)
    }

    private func perform(_ button: ToolbarButton) {
        switch button {
        case .rectangle:
            toggleShapeTool(.rectangle)
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
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
        case .pin, .polyline, .pen, .marker, .mosaic, .text, .number, .magnifier, .eraser, .ocr, .scroll, .settings:
            showPlaceholder(for: button)
        }

        needsDisplay = true
    }

    private func toggleShapeTool(_ shape: CaptureAnnotationKind) {
        activeShapeKind = SelectionToolbarState.toggledPrimaryShapeTool(current: activeShapeKind, defaultShape: shape)
        isShapeToolActive = activeShapeKind != nil
        if let activeShapeKind {
            currentShapeKind = activeShapeKind
            currentStyle.strokeWidth = 2
        } else {
            selectedAnnotationIndex = nil
        }
        shapeStartPoint = nil
        shapeCurrentPoint = nil
    }

    private func activateShapeTool(_ shape: CaptureAnnotationKind) {
        activeShapeKind = shape
        currentShapeKind = shape
        isShapeToolActive = true
        shapeStartPoint = nil
        shapeCurrentPoint = nil
    }

    private func showPlaceholder(for button: ToolbarButton) {
        let label: String
        switch button {
        case .pin:
            label = "贴图"
        case .polyline:
            label = "线条"
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
        case .ocr:
            label = "OCR"
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

    private func handleOptionsClick(at point: NSPoint) -> Bool {
        guard let optionsRect = optionsToolbarRect else {
            return false
        }

        for (index, rect) in strokeWidthRects(in: optionsRect).enumerated() where rect.contains(point) {
            currentStyle.strokeWidth = CGFloat([2, 4, 6][index])
            applyCurrentStyleToSelectedAnnotation()
            return true
        }

        let fillRect = fillToggleRect(in: optionsRect)
        if fillRect.contains(point) {
            currentStyle.fillEnabled.toggle()
            applyCurrentStyleToSelectedAnnotation()
            return true
        }

        let rectangleButton = rectangleModeButtonRect(in: optionsRect)
        let rectangleDisclosureRect = rectangleDisclosureHitRect(in: rectangleButton)
        if rectangleDisclosureRect.contains(point) {
            activateShapeTool(.rectangle)
            applyCurrentStyleToSelectedAnnotation()
            showsCornerRadiusPanel.toggle()
            showsStrokeStyleMenu = false
            return true
        }

        if rectangleButton.contains(point) {
            activateShapeTool(.rectangle)
            applyCurrentStyleToSelectedAnnotation()
            return true
        }

        if ellipseModeButtonRect(in: optionsRect).contains(point) {
            activateShapeTool(.ellipse)
            showsCornerRadiusPanel = false
            applyCurrentStyleToSelectedAnnotation()
            return true
        }

        if strokeStyleFieldRect(in: optionsRect).contains(point) {
            showsStrokeStyleMenu.toggle()
            showsCornerRadiusPanel = false
            return true
        }

        if let swatch = SelectionToolbarState.swatchHitTarget(at: point, in: optionsRect, paletteCount: colors.count) {
            switch swatch {
            case .custom:
                NSLog("snipory overlay custom color swatch clicked")
                showsStrokeStyleMenu = false
                showsCornerRadiusPanel = false
                isCustomColorSwatchActive = true
                toggleCustomColorPanel()
            case let .palette(index):
                let color = opaqueColor(colors[index])
                currentStyle.strokeColor = color
                currentStyle.fillColor = color
                customColor = nil
                isCustomColorSwatchActive = false
                closeCustomColorPanel()
                applyCurrentStyleToSelectedAnnotation()
            }
            return true
        }

        if !optionsRect.contains(point) {
            showsStrokeStyleMenu = false
            showsCornerRadiusPanel = false
            return false
        }

        return true
    }

    private func handleStrokeStyleMenuClick(at point: NSPoint) -> Bool {
        guard showsStrokeStyleMenu, let optionsRect = optionsToolbarRect else {
            return false
        }

        let menu = strokeStyleMenuRect(in: optionsRect)
        switch SelectionToolbarState.strokeMenuHitTarget(at: point, in: menu, itemCount: CaptureStrokePattern.allCases.count) {
        case let .item(index):
            let pattern = CaptureStrokePattern.allCases[index]
            currentStyle.strokePattern = pattern
            applyCurrentStyleToSelectedAnnotation()
            showsStrokeStyleMenu = false
            needsDisplay = true
            NSLog("snipory overlay selected stroke pattern=%ld", pattern.rawValue)
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

    private var selectedAnnotation: CaptureAnnotation? {
        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else {
            return nil
        }

        return annotations[selectedAnnotationIndex]
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
    }

    private func applyCurrentStyleToSelectedAnnotation() {
        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else {
            return
        }

        annotations[selectedAnnotationIndex].kind = currentShapeKind
        annotations[selectedAnnotationIndex].style = currentStyle
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
        needsDisplay = true
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
        resizingAnnotationStartRect = nil
        redoAnnotations.removeAll()
        needsDisplay = true
    }

    private func commitSelectionResize() {
        activeSelectionResizeHandle = nil
        resizingSelectionStartRect = nil
        resizingSelectionStartAnnotationRects.removeAll()
        redoAnnotations.removeAll()
        needsDisplay = true
    }

    private func commitSelectionMove() {
        movingSelectionStartRect = nil
        movingSelectionBounds = nil
        movingSelectionPointerOffset = .zero
        movingSelectionStartAnnotationRects.removeAll()
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

        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect)
        for handle in ShapeResizeHandle.allCases where handleRect(for: rect, handle: handle, kind: annotation.kind).insetBy(dx: -3, dy: -3).contains(point) {
            return handle
        }
        return nil
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

        let requested = NSRect(
            x: point.x - movingAnnotationOffset.x,
            y: point.y - movingAnnotationOffset.y,
            width: movingAnnotationStartRect.width,
            height: movingAnnotationStartRect.height
        )
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
                annotations[index].rect = preservedRects[index]
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
            annotations[index].rect = SelectionToolbarState.localAnnotationRect(
                fromOverlayRect: resizingSelectionStartAnnotationRects[index],
                selectionRect: resized
            )
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
            if selectedAnnotationIndex == index {
                drawSelectedAnnotationOutline(annotation)
            }
        }
    }

    private func drawDraftAnnotation() {
        guard let draftAnnotation else {
            return
        }

        drawAnnotation(draftAnnotation, inOverlay: true)
        drawResizeHandles(for: overlayRect(fromLocalAnnotationRect: draftAnnotation.rect), kind: draftAnnotation.kind)
    }

    private func drawAnnotation(_ annotation: CaptureAnnotation, inOverlay: Bool) {
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
        }

        if annotation.style.fillEnabled {
            annotation.style.fillColor.setFill()
            path.fill()
        }

        annotation.style.strokeColor.setStroke()
        path.lineWidth = annotation.style.strokeWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.setLineDash(annotation.style.strokePattern.dashPattern, count: annotation.style.strokePattern.dashPattern.count, phase: 0)
        path.stroke()
    }

    private func drawSelectedAnnotationOutline(_ annotation: CaptureAnnotation) {
        let rect = overlayRect(fromLocalAnnotationRect: annotation.rect)
        NSColor.systemBlue.setStroke()
        let outline = annotation.kind == .ellipse ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
        outline.lineWidth = 1.5
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.stroke()
        drawResizeHandles(for: rect, kind: annotation.kind)
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
        let separators: [(ToolbarButton, ToolbarButton)] = [
            (.eraser, .ocr),
            (.ocr, .undo),
            (.redo, .cancel),
            (.copy, .scroll),
        ]

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
                : SelectionToolbarState.colorSamplerCopyHintText(for: colorSamplerCopyMode),
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

        drawPanel(optionsRect, opaque: true, alpha: 0.9)
        drawOptionsToolbarSeparators(in: optionsRect)

        for (index, rect) in strokeWidthRects(in: optionsRect).enumerated() {
            let width = CGFloat([2, 4, 6][index])
            drawToolbarButton(optionButtonBackgroundRect(for: rect), symbol: nil, selected: currentStyle.strokeWidth == width, enabled: true)
            (currentStyle.strokeWidth == width ? NSColor.controlAccentColor : NSColor.labelColor).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: rect.minX + 4, y: rect.midY))
            line.line(to: NSPoint(x: rect.maxX - 4, y: rect.midY))
            line.lineWidth = width
            line.lineCapStyle = .round
            line.stroke()
        }

        drawFillToggle(in: optionsRect)
        drawShapeModeButtons(in: optionsRect)
        drawStrokeStyleField(in: optionsRect)
        drawColorSwatches(in: optionsRect)
    }

    private func drawOptionsToolbarSeparators(in optionsRect: NSRect) {
        let fill = optionButtonBackgroundRect(for: fillToggleRect(in: optionsRect))
        let rectangle = shapeModeBackgroundRect(for: rectangleModeButtonRect(in: optionsRect))
        let ellipse = optionButtonBackgroundRect(for: ellipseModeButtonRect(in: optionsRect))
        let strokeStyle = strokeStyleFieldRect(in: optionsRect)
        let firstSwatchMinX = colorSwatchRects(in: optionsRect).map { $0.minX }.min()

        var separatorXs: [CGFloat] = [
            fill.maxX + (rectangle.minX - fill.maxX) / 2,
            ellipse.maxX + (strokeStyle.minX - ellipse.maxX) / 2,
        ]
        if let firstSwatchMinX {
            separatorXs.append(strokeStyle.maxX + (firstSwatchMinX - strokeStyle.maxX) / 2)
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

        let sample = NSBezierPath()
        sample.move(to: NSPoint(x: field.minX + 10, y: field.midY))
        sample.line(to: NSPoint(x: field.maxX - 22, y: field.midY))
        NSColor.labelColor.setStroke()
        sample.lineWidth = 2
        sample.lineCapStyle = .round
        sample.setLineDash(currentStyle.strokePattern.dashPattern, count: currentStyle.strokePattern.dashPattern.count, phase: 0)
        sample.stroke()
        drawTriangle(in: NSRect(x: field.maxX - 16, y: field.midY - 3, width: 7, height: 5), color: .labelColor)
    }

    private func drawStrokeStyleMenu(for selectionRect: NSRect) {
        guard let options = optionsToolbarRect else {
            return
        }

        let menu = strokeStyleMenuRect(in: options)
        drawPanel(menu)

        for (index, pattern) in CaptureStrokePattern.allCases.enumerated() {
            let item = strokeStyleMenuItemRects(in: menu)[index]
            let selected = pattern == currentStyle.strokePattern
            drawToolbarButton(item, symbol: nil, selected: selected, enabled: true)

            let sample = NSBezierPath()
            sample.move(to: NSPoint(x: item.minX + 10, y: item.midY))
            sample.line(to: NSPoint(x: item.maxX - 10, y: item.midY))
            let strokeColor = selected ? NSColor.controlAccentColor : NSColor.labelColor
            strokeColor.setStroke()
            sample.lineWidth = 2
            sample.lineCapStyle = .round
            sample.setLineDash(pattern.dashPattern, count: pattern.dashPattern.count, phase: 0)
            sample.stroke()
        }
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
            let isCustomSlot = index == colors.count
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
        let rgb = opaqueColor(color).usingColorSpace(.deviceRGB) ?? opaqueColor(color)
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func sampleColor(at point: NSPoint) -> NSColor? {
        guard let backgroundBitmap else {
            return nil
        }

        let pixel = bitmapPixelPoint(for: point, in: backgroundBitmap)
        return sampleColor(atPixelX: pixel.x, y: pixel.y, in: backgroundBitmap)
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
        let x = max(0, min(bitmap.pixelsWide - 1, x))
        let y = max(0, min(bitmap.pixelsHigh - 1, y))
        guard let color = bitmap.colorAt(x: x, y: y) else {
            return nil
        }

        return color.usingColorSpace(.deviceRGB) ?? color
    }

    private func rgbString(for color: NSColor) -> String {
        let rgb = opaqueColor(color).usingColorSpace(.deviceRGB) ?? opaqueColor(color)
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return "\(red), \(green), \(blue)"
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
        let usesFixedColorResource = fixedColorToolbarIconResources.contains(resourceName)
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
        resourceName == "text-tool" ? 0 : 2
    }

    private var fixedColorToolbarIconResources: Set<String> {
        [
            "undo-enabled",
            "undo-disabled",
            "redo-enabled",
            "redo-disabled",
        ]
    }

    @discardableResult
    private func drawToolbarImage(named name: String, in rect: NSRect, template: Bool, enabled: Bool, inset: CGFloat = 3) -> Bool {
        let resource = NSImage(named: name)
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
        [
            .rectangle,
            .polyline,
            .pen,
            .marker,
            .mosaic,
            .text,
            .number,
            .magnifier,
            .eraser,
            .ocr,
            .undo,
            .redo,
            .cancel,
            .pin,
            .save,
            .copy,
            .scroll,
            .settings,
        ]
    }

    private func mainToolbarExtraGap(after button: ToolbarButton) -> CGFloat {
        switch button {
        case .eraser, .ocr, .redo, .copy:
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
        case .ocr:
            return "toolbar-ocr-recognition"
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
            return isShapeToolActive
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

        if showsStrokeStyleMenu, let optionsToolbarRect, strokeStyleMenuRect(in: optionsToolbarRect).contains(point) {
            return true
        }

        return false
    }

    private var optionsToolbarRect: NSRect? {
        guard
            SelectionToolbarState.shouldShowOptionsToolbar(isPrimaryShapeToolActive: isShapeToolActive),
            let selectionRect,
            let toolbar = mainToolbarRect(for: selectionRect)
        else {
            return nil
        }

        return toolbarRect(size: NSSize(width: 530, height: 40), anchoredTo: toolbar)
    }

    private var cornerRadiusPanelRect: NSRect? {
        guard let options = optionsToolbarRect else {
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
        (0..<3).map { index in
            NSRect(x: optionsRect.minX + 6 + CGFloat(index) * 24, y: optionsRect.minY + 10, width: 20, height: 20)
        }
    }

    private func optionButtonBackgroundRect(for rect: NSRect) -> NSRect {
        rect.insetBy(dx: -3, dy: -5)
    }

    private func fillToggleRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 86, y: optionsRect.minY + 10, width: 20, height: 20)
    }

    private func rectangleModeButtonRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 126, y: optionsRect.minY + 10, width: 26, height: 20)
    }

    private func ellipseModeButtonRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 158, y: optionsRect.minY + 10, width: 22, height: 20)
    }

    private func strokeStyleFieldRect(in optionsRect: NSRect) -> NSRect {
        NSRect(x: optionsRect.minX + 200, y: optionsRect.minY + 10, width: 102, height: 20)
    }

    private func strokeStyleMenuRect(in optionsRect: NSRect) -> NSRect {
        let field = strokeStyleFieldRect(in: optionsRect)
        let itemCount = max(1, CaptureStrokePattern.allCases.count)
        let height = CGFloat(itemCount) * 24 + 8
        return SelectionToolbarState.popoverRect(
            size: NSSize(width: field.width, height: height),
            anchoredTo: field,
            inside: safeLayoutBounds
        )
    }

    private func strokeStyleMenuItemRects(in menu: NSRect) -> [NSRect] {
        SelectionToolbarState.strokeStyleMenuItemRects(in: menu, itemCount: CaptureStrokePattern.allCases.count)
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
        SelectionToolbarState.colorSwatchRects(in: optionsRect, paletteCount: colors.count)
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
