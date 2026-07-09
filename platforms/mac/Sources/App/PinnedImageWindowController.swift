import AppKit

struct PinnedImageWindowGeometry {
    static let maxScreenFraction: CGFloat = 0.8
    static let minLongSide: CGFloat = 96
    static let shadowOutset: CGFloat = 18

    static func fittedImageSize(imageSize: NSSize, visibleFrame: NSRect) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: minLongSide, height: minLongSide)
        }

        let maxSize = NSSize(
            width: max(minLongSide, visibleFrame.width * maxScreenFraction),
            height: max(minLongSide, visibleFrame.height * maxScreenFraction)
        )
        let fitFactor = min(1, maxSize.width / imageSize.width, maxSize.height / imageSize.height)
        let minFactor = minLongSide / max(imageSize.width, imageSize.height)
        let factor = max(fitFactor, minFactor)
        return NSSize(width: imageSize.width * factor, height: imageSize.height * factor)
    }

    static func scaledSize(
        currentSize: NSSize,
        aspectRatio: CGFloat,
        scaleFactor: CGFloat,
        visibleFrame: NSRect
    ) -> NSSize {
        guard currentSize.width > 0, currentSize.height > 0, aspectRatio > 0 else {
            return currentSize
        }

        let maxSize = NSSize(
            width: max(minLongSide, visibleFrame.width * maxScreenFraction),
            height: max(minLongSide, visibleFrame.height * maxScreenFraction)
        )
        let proposedWidth = currentSize.width * scaleFactor
        let proposedHeight = proposedWidth / aspectRatio
        let maxFactor = min(maxSize.width / currentSize.width, maxSize.height / currentSize.height)
        let minFactor = minLongSide / max(currentSize.width, currentSize.height)
        let clampedFactor = min(max(scaleFactor, minFactor), maxFactor)

        if proposedHeight <= maxSize.height, proposedWidth <= maxSize.width,
           max(proposedWidth, proposedHeight) >= minLongSide {
            return NSSize(width: proposedWidth, height: proposedHeight)
        }

        return NSSize(width: currentSize.width * clampedFactor, height: currentSize.height * clampedFactor)
    }

    static func movedOrigin(globalMouse: NSPoint, dragOffset: NSPoint) -> NSPoint {
        NSPoint(x: globalMouse.x - dragOffset.x, y: globalMouse.y - dragOffset.y)
    }

    static func windowFrame(forImageFrame imageFrame: NSRect) -> NSRect {
        imageFrame.insetBy(dx: -shadowOutset, dy: -shadowOutset)
    }

    static func imageFrame(inWindowFrame windowFrame: NSRect) -> NSRect {
        windowFrame.insetBy(dx: shadowOutset, dy: shadowOutset)
    }
}

@MainActor
protocol PinnedImageWindowPresenting: AnyObject {
    var image: NSImage { get }
    var screenRect: NSRect { get }
    func show()
}

@MainActor
final class PinnedImageWindowController: NSWindowController, PinnedImageWindowPresenting {
    private static let activeControllers = NSHashTable<PinnedImageWindowController>.weakObjects()

    var image: NSImage {
        pinnedImage
    }

    let screenRect: NSRect
    var onClose: (() -> Void)?
    private var pinnedImage: NSImage
    private let initialImageFrame: NSRect
    private let imageAspectRatio: CGFloat

    init(image: NSImage, screenRect: NSRect? = nil, visibleFrame: NSRect? = NSScreen.main?.visibleFrame) {
        self.pinnedImage = image
        let requestedRect = screenRect?.standardized ?? NSRect(origin: .zero, size: image.size)
        self.screenRect = requestedRect.isEmpty ? NSRect(origin: .zero, size: image.size) : requestedRect
        self.imageAspectRatio = image.size.width / max(image.size.height, 1)
        let screenFrame = visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let initialImageFrame = self.screenRect.isEmpty
            ? NSRect(
                x: screenFrame.midX - image.size.width / 2,
                y: screenFrame.midY - image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            )
            : self.screenRect
        self.initialImageFrame = initialImageFrame
        let initialFrame = PinnedImageWindowGeometry.windowFrame(forImageFrame: initialImageFrame)
        let window = PinnedImageWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = PinnedImageContentView(image: image)
        view.frame = NSRect(origin: .zero, size: initialFrame.size)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        super.init(window: window)
        window.delegate = self
        view.controller = self
        Self.activeControllers.add(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func scale(by factor: CGFloat, around anchorInScreen: NSPoint? = nil) {
        guard let window else {
            return
        }
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let currentImageFrame = PinnedImageWindowGeometry.imageFrame(inWindowFrame: window.frame)
        let newImageSize = PinnedImageWindowGeometry.scaledSize(
            currentSize: currentImageFrame.size,
            aspectRatio: imageAspectRatio,
            scaleFactor: factor,
            visibleFrame: visibleFrame
        )
        guard newImageSize.width > 0, newImageSize.height > 0 else {
            return
        }

        let anchor = anchorInScreen ?? NSPoint(x: currentImageFrame.midX, y: currentImageFrame.midY)
        let xRatio = (anchor.x - currentImageFrame.minX) / max(currentImageFrame.width, 1)
        let yRatio = (anchor.y - currentImageFrame.minY) / max(currentImageFrame.height, 1)
        let newImageOrigin = NSPoint(
            x: anchor.x - newImageSize.width * xRatio,
            y: anchor.y - newImageSize.height * yRatio
        )
        let newImageFrame = NSRect(origin: newImageOrigin, size: newImageSize)
        window.setFrame(PinnedImageWindowGeometry.windowFrame(forImageFrame: newImageFrame), display: true)
    }

    func showEditingToolbar() {
        contentView?.showsEditingToolbar = true
    }

    func hideEditingToolbar() {
        contentView?.showsEditingToolbar = false
    }

    func finishEditing() {
        guard let contentView else {
            return
        }
        if let baked = contentView.bakePendingAnnotations() {
            pinnedImage = baked
        }
        hideEditingToolbar()
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem(title: contentView?.showsEditingToolbar == true ? "隐藏工具条" : "显示工具条", action: #selector(toggleEditingToolbar)))
        menu.addItem(menuItem(title: "复制图片", action: #selector(copyImage)))
        menu.addItem(menuItem(title: "保存图片...", action: #selector(saveImage)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "重置大小", action: #selector(resetSize)))

        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for option in [1.0, 0.8, 0.6, 0.4] as [CGFloat] {
            let item = menuItem(title: "\(Int(option * 100))%", action: #selector(setOpacity(_:)))
            item.representedObject = option
            item.state = abs((window?.alphaValue ?? 1) - option) < 0.01 ? .on : .off
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        let topItem = menuItem(title: "置顶", action: #selector(toggleAlwaysOnTop))
        topItem.state = window?.level == .floating ? .on : .off
        menu.addItem(topItem)

        let clickThroughItem = menuItem(title: "鼠标穿透", action: #selector(toggleMouseClickThrough))
        clickThroughItem.state = window?.ignoresMouseEvents == true ? .on : .off
        menu.addItem(clickThroughItem)

        menu.addItem(.separator())
        menu.addItem(menuItem(title: "关闭", action: #selector(closePinnedWindow)))
        menu.addItem(menuItem(title: "关闭全部贴图", action: #selector(closeAllPinnedWindows)))
        return menu
    }

    func showContextMenu(with event: NSEvent) {
        guard let contentView = window?.contentView else {
            return
        }
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: contentView)
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleEditingToolbar() {
        if contentView?.showsEditingToolbar == true {
            hideEditingToolbar()
        } else {
            showEditingToolbar()
        }
    }

    @objc fileprivate func copyImage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([pinnedImage])
    }

    @objc fileprivate func saveImage() {
        guard
            let tiffData = pinnedImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return
        }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = CaptureCoordinator.defaultCaptureFilename()
        savePanel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            return
        }
        try? pngData.write(to: destinationURL)
    }

    @objc private func resetSize() {
        window?.setFrame(PinnedImageWindowGeometry.windowFrame(forImageFrame: initialImageFrame), display: true)
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let opacity = sender.representedObject as? CGFloat else {
            return
        }
        window?.alphaValue = opacity
    }

    @objc private func toggleAlwaysOnTop() {
        window?.level = window?.level == .floating ? .normal : .floating
    }

    @objc private func toggleMouseClickThrough() {
        window?.ignoresMouseEvents.toggle()
    }

    @objc private func closePinnedWindow() {
        window?.close()
    }

    @objc private func closeAllPinnedWindows() {
        for controller in Self.activeControllers.allObjects {
            controller.window?.close()
        }
    }

    private var contentView: PinnedImageContentView? {
        window?.contentView as? PinnedImageContentView
    }
}

extension PinnedImageWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        Self.activeControllers.remove(self)
        onClose?()
    }
}

private final class PinnedImageWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }
}

private final class PinnedImageContentView: NSView {
    var image: NSImage
    weak var controller: PinnedImageWindowController?
    private var dragOffset: NSPoint?
    fileprivate var showsEditingToolbar = false {
        didSet {
            draftAnnotation = nil
            annotationStartPoint = nil
            needsDisplay = true
        }
    }
    private var annotationStartPoint: NSPoint?
    private var draftAnnotation: PendingAnnotation?
    private var pendingAnnotations: [PendingAnnotation] = []
    private var currentEditingTool: EditingToolbarButton = .rectangle

    private struct PendingAnnotation {
        var tool: EditingToolbarButton
        var points: [NSPoint]

        var boundingRect: NSRect {
            guard let first = points.first else {
                return .zero
            }
            var minX = first.x
            var maxX = first.x
            var minY = first.y
            var maxY = first.y
            for point in points.dropFirst() {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    private enum EditingToolbarButton: CaseIterable {
        case rectangle
        case arrow
        case pen
        case marker
        case save
        case copy
        case done

        var title: String {
            switch self {
            case .rectangle:
                return "矩形"
            case .arrow:
                return "箭头"
            case .pen:
                return "画笔"
            case .marker:
                return "标记"
            case .save:
                return "保存图片"
            case .copy:
                return "复制图片"
            case .done:
                return "完成编辑"
            }
        }

        var iconName: String? {
            switch self {
            case .rectangle:
                return "screenshot"
            case .arrow:
                return "arrow"
            case .pen:
                return "pencil-tool"
            case .marker:
                return "highlighter-tool"
            case .save:
                return "save-to-file"
            case .copy:
                return "copy-to-clipboard"
            case .done:
                return nil
            }
        }

        var isAnnotationTool: Bool {
            switch self {
            case .rectangle, .arrow, .pen, .marker:
                return true
            case .save, .copy, .done:
                return false
            }
        }
    }

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        let imageRect = currentImageRect
        drawBlueOuterShadow(around: imageRect)
        image.draw(in: imageRect)
        drawPendingAnnotations(in: imageRect)
        if showsEditingToolbar {
            drawEditingToolbar(in: imageRect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = event.locationInWindow
        if showsEditingToolbar {
            if let button = editingToolbarButton(at: point) {
                performEditingToolbarButton(button)
                return
            }
            guard currentImageRect.contains(point) else {
                return
            }
            annotationStartPoint = imagePoint(from: point)
            draftAnnotation = nil
            return
        }
        if window != nil {
            dragOffset = event.locationInWindow
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if showsEditingToolbar, let annotationStartPoint {
            draftAnnotation = makeAnnotation(
                tool: currentEditingTool,
                from: annotationStartPoint,
                to: imagePoint(from: event.locationInWindow)
            )
            needsDisplay = true
            return
        }

        guard let dragOffset, let window else {
            return
        }
        let origin = PinnedImageWindowGeometry.movedOrigin(
            globalMouse: NSEvent.mouseLocation,
            dragOffset: dragOffset
        )
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        if showsEditingToolbar, let annotationStartPoint {
            let annotation = makeAnnotation(
                tool: currentEditingTool,
                from: annotationStartPoint,
                to: imagePoint(from: event.locationInWindow)
            )
            if isDrawableAnnotation(annotation) {
                pendingAnnotations.append(annotation)
            }
            self.annotationStartPoint = nil
            draftAnnotation = nil
            needsDisplay = true
            return
        }
        dragOffset = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.showContextMenu(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.deltaY != 0 else {
            return
        }
        let factor = event.deltaY > 0 ? 1.08 : 0.92
        controller?.scale(by: factor, around: NSEvent.mouseLocation)
    }

    override func magnify(with event: NSEvent) {
        controller?.scale(by: 1 + event.magnification, around: NSEvent.mouseLocation)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.keyCode == 51 || event.keyCode == 117 {
            window?.close()
            return
        }
        super.keyDown(with: event)
    }

    fileprivate var currentImageRect: NSRect {
        bounds.insetBy(
            dx: PinnedImageWindowGeometry.shadowOutset,
            dy: PinnedImageWindowGeometry.shadowOutset
        )
    }

    fileprivate var editingToolbarTitles: [String] {
        EditingToolbarButton.allCases.map(\.title)
    }

    fileprivate var currentEditingToolTitle: String {
        currentEditingTool.title
    }

    fileprivate var pendingAnnotationKindTitles: [String] {
        var titles = pendingAnnotations.map { $0.tool.title }
        if let draftAnnotation {
            titles.append(draftAnnotation.tool.title)
        }
        return titles
    }

    fileprivate var pendingRectsForTesting: [NSRect] {
        var rects = pendingAnnotations.map(\.boundingRect)
        if let draftAnnotation {
            rects.append(draftAnnotation.boundingRect)
        }
        return rects
    }

    fileprivate func bakePendingAnnotations() -> NSImage? {
        var annotations = pendingAnnotations
        if let draftAnnotation {
            annotations.append(draftAnnotation)
        }
        guard !annotations.isEmpty else {
            pendingAnnotations.removeAll()
            draftAnnotation = nil
            return nil
        }

        let baked = NSImage(size: image.size)
        baked.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        for annotation in annotations {
            drawAnnotation(annotation)
        }
        baked.unlockFocus()
        image = baked
        pendingAnnotations.removeAll()
        draftAnnotation = nil
        needsDisplay = true
        return baked
    }

    fileprivate func addAnnotationByDragging(from start: NSPoint, to end: NSPoint) {
        showsEditingToolbar = true
        let startPoint = imagePoint(from: start)
        let endPoint = imagePoint(from: end)
        let annotation = makeAnnotation(tool: currentEditingTool, from: startPoint, to: endPoint)
        if isDrawableAnnotation(annotation) {
            pendingAnnotations.append(annotation)
            needsDisplay = true
        }
    }

    fileprivate func selectEditingTool(named title: String) {
        guard let tool = EditingToolbarButton.allCases.first(where: { $0.title == title && $0.isAnnotationTool }) else {
            return
        }
        currentEditingTool = tool
        needsDisplay = true
    }

    private func drawBlueOuterShadow(around imageRect: NSRect) {
        drawShadowLayer(
            around: imageRect,
            color: NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.82, alpha: 0.42),
            blur: 16,
            offset: .zero
        )
        drawShadowLayer(
            around: imageRect,
            color: NSColor(calibratedRed: 0.28, green: 0.64, blue: 1, alpha: 0.34),
            blur: 7,
            offset: NSSize(width: 0, height: -1)
        )
        NSColor(calibratedRed: 0.36, green: 0.65, blue: 0.92, alpha: 0.28).setStroke()
        let edge = NSBezierPath(rect: imageRect.insetBy(dx: 0.5, dy: 0.5))
        edge.lineWidth = 1
        edge.stroke()
    }

    private func drawShadowLayer(around imageRect: NSRect, color: NSColor, blur: CGFloat, offset: NSSize) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = offset
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(rect: imageRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func imagePoint(from viewPoint: NSPoint) -> NSPoint {
        let imageRect = currentImageRect
        let clamped = NSPoint(
            x: min(max(viewPoint.x, imageRect.minX), imageRect.maxX),
            y: min(max(viewPoint.y, imageRect.minY), imageRect.maxY)
        )
        return NSPoint(
            x: (clamped.x - imageRect.minX) / max(imageRect.width, 1) * image.size.width,
            y: (clamped.y - imageRect.minY) / max(imageRect.height, 1) * image.size.height
        )
    }

    private func normalizedRect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }

    private func makeAnnotation(tool: EditingToolbarButton, from start: NSPoint, to end: NSPoint) -> PendingAnnotation {
        switch tool {
        case .rectangle:
            let rect = normalizedRect(from: start, to: end)
            return PendingAnnotation(
                tool: tool,
                points: [
                    rect.origin,
                    NSPoint(x: rect.maxX, y: rect.maxY),
                ]
            )
        case .arrow, .pen, .marker:
            return PendingAnnotation(tool: tool, points: [start, end])
        case .save, .copy, .done:
            return PendingAnnotation(tool: .rectangle, points: [start, end])
        }
    }

    private func isDrawableAnnotation(_ annotation: PendingAnnotation) -> Bool {
        switch annotation.tool {
        case .rectangle:
            return annotation.boundingRect.width >= 2 && annotation.boundingRect.height >= 2
        case .arrow, .pen, .marker:
            guard let start = annotation.points.first, let end = annotation.points.last else {
                return false
            }
            return hypot(end.x - start.x, end.y - start.y) >= 2
        case .save, .copy, .done:
            return false
        }
    }

    private func viewRect(from imageRelativeRect: NSRect, in imageRect: NSRect) -> NSRect {
        NSRect(
            x: imageRect.minX + imageRelativeRect.minX / max(image.size.width, 1) * imageRect.width,
            y: imageRect.minY + imageRelativeRect.minY / max(image.size.height, 1) * imageRect.height,
            width: imageRelativeRect.width / max(image.size.width, 1) * imageRect.width,
            height: imageRelativeRect.height / max(image.size.height, 1) * imageRect.height
        )
    }

    private func viewPoint(from imageRelativePoint: NSPoint, in imageRect: NSRect) -> NSPoint {
        NSPoint(
            x: imageRect.minX + imageRelativePoint.x / max(image.size.width, 1) * imageRect.width,
            y: imageRect.minY + imageRelativePoint.y / max(image.size.height, 1) * imageRect.height
        )
    }

    private func drawPendingAnnotations(in imageRect: NSRect) {
        for annotation in pendingAnnotations {
            drawAnnotation(annotation, in: imageRect)
        }
        if let draftAnnotation {
            drawAnnotation(draftAnnotation, in: imageRect)
        }
    }

    private func drawAnnotation(_ annotation: PendingAnnotation, in imageRect: NSRect? = nil) {
        let points = annotation.points.map { point in
            imageRect.map { viewPoint(from: point, in: $0) } ?? point
        }
        switch annotation.tool {
        case .rectangle:
            let rect = imageRect.map { viewRect(from: annotation.boundingRect, in: $0) } ?? annotation.boundingRect
            drawAnnotationRect(rect)
        case .arrow:
            guard points.count >= 2 else {
                return
            }
            drawLine(points: points, color: .systemRed, lineWidth: 3, alpha: 1)
            drawArrowHead(from: points[0], to: points[1])
        case .pen:
            drawLine(points: points, color: .systemRed, lineWidth: 3, alpha: 1)
        case .marker:
            drawLine(
                points: points,
                color: NSColor(calibratedRed: 1, green: 0.82, blue: 0.04, alpha: 1),
                lineWidth: 10,
                alpha: 0.72
            )
        case .save, .copy, .done:
            break
        }
    }

    private func drawAnnotationRect(_ rect: NSRect) {
        NSColor.systemRed.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 3
        path.stroke()
    }

    private func drawLine(points: [NSPoint], color: NSColor, lineWidth: CGFloat, alpha: CGFloat) {
        guard let first = points.first else {
            return
        }
        let path = NSBezierPath()
        path.move(to: first)
        for point in points.dropFirst() {
            path.line(to: point)
        }
        color.withAlphaComponent(alpha).setStroke()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawArrowHead(from start: NSPoint, to end: NSPoint) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 14
        let headAngle: CGFloat = .pi / 7
        let left = NSPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let right = NSPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )
        let path = NSBezierPath()
        path.move(to: left)
        path.line(to: end)
        path.line(to: right)
        NSColor.systemRed.setStroke()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func editingToolbarRect(in imageRect: NSRect) -> NSRect {
        let buttonCount = CGFloat(EditingToolbarButton.allCases.count)
        let width = buttonCount * 28 + 10
        return NSRect(
            x: imageRect.midX - width / 2,
            y: imageRect.maxY - 34,
            width: width,
            height: 28
        )
    }

    private func editingToolbarButtonRects() -> [(EditingToolbarButton, NSRect)] {
        let toolbar = editingToolbarRect(in: currentImageRect)
        var x = toolbar.minX + 5
        return EditingToolbarButton.allCases.map { button in
            let rect = NSRect(x: x, y: toolbar.minY + 4, width: 20, height: 20)
            x += 28
            return (button, rect)
        }
    }

    private func editingToolbarButton(at point: NSPoint) -> EditingToolbarButton? {
        editingToolbarButtonRects().first { _, rect in rect.insetBy(dx: -4, dy: -4).contains(point) }?.0
    }

    private func performEditingToolbarButton(_ button: EditingToolbarButton) {
        switch button {
        case .rectangle, .arrow, .pen, .marker:
            currentEditingTool = button
            needsDisplay = true
        case .save:
            controller?.saveImage()
        case .copy:
            controller?.copyImage()
        case .done:
            controller?.finishEditing()
        }
    }

    private func drawEditingToolbar(in imageRect: NSRect) {
        let toolbar = editingToolbarRect(in: imageRect)
        NSColor(calibratedWhite: 0.98, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: toolbar, xRadius: 5, yRadius: 5).fill()
        NSColor(calibratedWhite: 0.7, alpha: 0.7).setStroke()
        NSBezierPath(roundedRect: toolbar, xRadius: 5, yRadius: 5).stroke()

        for (button, rect) in editingToolbarButtonRects() {
            NSColor.white.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            let borderColor = button == currentEditingTool && button.isAnnotationTool
                ? NSColor.systemBlue
                : NSColor.black.withAlphaComponent(0.75)
            borderColor.setStroke()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).stroke()
            if button == .done {
                drawDoneCheck(in: rect)
            } else if let iconName = button.iconName,
                      let image = Bundle.main.url(forResource: iconName, withExtension: "svg").flatMap(NSImage.init(contentsOf:)) {
                image.draw(in: rect.insetBy(dx: 3, dy: 3), from: .zero, operation: .sourceOver, fraction: 1)
                NSColor.black.setFill()
                rect.insetBy(dx: 3, dy: 3).fill(using: .sourceAtop)
            }
        }
    }

    private func drawDoneCheck(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + 4.5, y: rect.midY - 0.5))
        path.line(to: NSPoint(x: rect.midX - 1, y: rect.minY + 5))
        path.line(to: NSPoint(x: rect.maxX - 4, y: rect.maxY - 5))
        NSColor.black.setStroke()
        path.lineWidth = 2.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}

#if DEBUG
extension PinnedImageWindowController {
    var test_drawsBlueShadow: Bool {
        true
    }

    var test_drawsCloseButton: Bool {
        false
    }

    func test_keyDown(keyCode: UInt16) {
        guard let contentView = window?.contentView else {
            return
        }
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
        if let event {
            contentView.keyDown(with: event)
        }
    }

    func test_renderedContentImage() -> NSImage {
        let contentBounds = window?.contentView?.bounds ?? NSRect(origin: .zero, size: image.size)
        let rendered = NSImage(size: contentBounds.size)
        rendered.lockFocus()
        window?.contentView?.draw(contentBounds)
        rendered.unlockFocus()
        return rendered
    }

    var test_contextMenuTitles: [String?] {
        makeContextMenu().items.map { item in
            item.isSeparatorItem ? nil : item.title
        }
    }

    var test_isToolbarVisible: Bool {
        contentView?.showsEditingToolbar == true
    }

    var test_imageRectInContent: NSRect {
        contentView?.currentImageRect ?? .zero
    }

    var test_pendingAnnotationCount: Int {
        contentView?.pendingRectsForTesting.count ?? 0
    }

    var test_pendingAnnotationRects: [NSRect] {
        contentView?.pendingRectsForTesting ?? []
    }

    var test_currentEditingToolTitle: String {
        contentView?.currentEditingToolTitle ?? ""
    }

    var test_pendingAnnotationKinds: [String] {
        contentView?.pendingAnnotationKindTitles ?? []
    }

    func test_showEditingToolbar() {
        showEditingToolbar()
    }

    func test_finishEditing() {
        finishEditing()
    }

    func test_toolbarContains(_ title: String) -> Bool {
        contentView?.editingToolbarTitles.contains(title) == true
    }

    func test_selectEditingTool(_ title: String) {
        contentView?.selectEditingTool(named: title)
    }

    func test_dragAnnotation(from start: NSPoint, to end: NSPoint) {
        contentView?.addAnnotationByDragging(from: start, to: end)
    }
}
#endif
