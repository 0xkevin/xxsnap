import AppKit

struct PinnedImageWindowGeometry {
    static let maxScreenFraction: CGFloat = 0.8
    static let minLongSide: CGFloat = 96
    static let shadowOutset: CGFloat = 18
    static let toolbarGap: CGFloat = 6
    static let toolbarHeight: CGFloat = 28

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
    var onHide: (() -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    func show()
}

@MainActor
final class PinnedImageWindowController: NSWindowController, PinnedImageWindowPresenting {
    private static let activeControllers = NSHashTable<PinnedImageWindowController>.weakObjects()

    var image: NSImage {
        pinnedImage
    }

    let screenRect: NSRect
    var onHide: (() -> Void)?
    var onClose: (() -> Void)?
    private var pinnedImage: NSImage
    private let initialImageFrame: NSRect
    private let imageAspectRatio: CGFloat
    private var editingOverlayWindow: SelectionOverlayWindow?
    private var editingDragOffsetInScreen: NSPoint?
#if DEBUG
    private var imageActionHandlerForTesting: ((CaptureCompletionAction) -> Void)?
#endif

    init(
        image: NSImage,
        screenRect: NSRect? = nil,
        visibleFrame: NSRect? = nil,
        screenResolver: (NSRect) -> NSRect? = PinnedImageWindowController.visibleFrame(containing:)
    ) {
        self.pinnedImage = image
        let requestedRect = screenRect?.standardized ?? NSRect(origin: .zero, size: image.size)
        self.screenRect = requestedRect.isEmpty ? NSRect(origin: .zero, size: image.size) : requestedRect
        self.imageAspectRatio = image.size.width / max(image.size.height, 1)
        let screenFrame = visibleFrame
            ?? screenResolver(self.screenRect)
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let requestedImageFrame = self.screenRect
        let windowFrame = PinnedImageWindowGeometry.windowFrame(forImageFrame: requestedImageFrame)
        let needsFitting = windowFrame.width > screenFrame.width || windowFrame.height > screenFrame.height
        let fittedSize: NSSize
        if needsFitting {
            // Leave headroom for an immediate zoom while keeping the complete pin on-screen.
            let initialVisibleFrame = NSRect(
                origin: screenFrame.origin,
                size: NSSize(width: screenFrame.width * 0.875, height: screenFrame.height * 0.875)
            )
            fittedSize = PinnedImageWindowGeometry.fittedImageSize(
                imageSize: image.size,
                visibleFrame: initialVisibleFrame
            )
        } else {
            fittedSize = requestedImageFrame.size
        }
        let initialImageFrame = needsFitting
            ? NSRect(
                x: screenFrame.midX - fittedSize.width / 2,
                y: screenFrame.midY - fittedSize.height / 2,
                width: fittedSize.width,
                height: fittedSize.height
            )
            : requestedImageFrame
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

    private static func visibleFrame(containing rect: NSRect) -> NSRect? {
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(rect.origin, $0.frame, false) }) {
            return screen.visibleFrame
        }
        let point = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })?.visibleFrame
            ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.visibleFrame
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
        let currentImageFrame = currentImageFrameInScreen()
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
        applyWindowFrame(forImageFrame: newImageFrame)
    }

    func showEditingToolbar() {
        if let editingOverlayWindow {
            editingOverlayWindow.alphaValue = 1
            editingOverlayWindow.present()
            return
        }
        let imageFrame = currentImageFrameInScreen()
        let overlayGeometry = editingOverlayGeometry(for: imageFrame)
        let backgroundImage = editingOverlayBackgroundImage(
            frameSize: overlayGeometry.windowFrame.size,
            imageRect: overlayGeometry.selectionRect
        )
        let overlayWindow = SelectionOverlayWindow(
            backgroundImage: backgroundImage,
            configuration: .pinnedImageEditor(
                windowFrame: overlayGeometry.windowFrame,
                selectionRect: overlayGeometry.selectionRect,
                pinnedImageScaleHandler: { [weak self] factor, anchor in
                    self?.scaleEditingOverlay(by: factor, around: anchor)
                },
                pinnedImageDragBegan: { [weak self] point in
                    self?.beginEditingOverlayDrag(at: point)
                },
                pinnedImageDragChanged: { [weak self] point in
                    self?.dragEditingOverlay(to: point)
                },
                pinnedImageDragEnded: { [weak self] in
                    self?.endEditingOverlayDrag()
                },
                pinnedImageContextMenuHandler: { [weak self] point in
                    self?.showContextMenu(atScreenPoint: point)
                },
                pinnedImageWindowCommandHandler: { [weak self] command in
                    self?.performWindowCommand(command)
                },
                pinnedImageToolbarToggleHandler: { [weak self] in
                    self?.toggleEditingToolbar()
                }
            )
        ) { [weak self] result in
            self?.completeEditingOverlay(with: result)
        }
        editingOverlayWindow = overlayWindow
        overlayWindow.level = window?.level ?? .floating
        overlayWindow.alphaValue = 1
        overlayWindow.present()
    }

    func hideEditingToolbar() {
        editingDragOffsetInScreen = nil
        editingOverlayWindow?.cancelOperation(nil)
        editingOverlayWindow = nil
    }

    func finishEditing() {
        hideEditingToolbar()
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let toolbarItem = menuItem(title: "显示工具条 (⇧)", action: #selector(toggleEditingToolbarFromMenu))
        toolbarItem.state = editingOverlayWindow == nil ? .off : .on
        menu.addItem(toolbarItem)
        menu.addItem(menuItem(
            title: "复制图片",
            action: #selector(copyImage),
            keyEquivalent: "c",
            modifierMask: [.command]
        ))
        menu.addItem(menuItem(
            title: "保存图片",
            action: #selector(saveImage),
            keyEquivalent: "s",
            modifierMask: [.command]
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: "重置大小",
            action: #selector(resetSize),
            keyEquivalent: "r",
            modifierMask: [.command]
        ))

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

        let topItem = menuItem(
            title: "置顶",
            action: #selector(toggleAlwaysOnTop),
            keyEquivalent: "t",
            modifierMask: [.command]
        )
        topItem.state = window?.level == .floating ? .on : .off
        menu.addItem(topItem)

        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: "关闭",
            action: #selector(closePinnedWindow),
            keyEquivalent: "w",
            modifierMask: [.command]
        ))
        menu.addItem(menuItem(
            title: "关闭全部贴图",
            action: #selector(closeAllPinnedWindows),
            keyEquivalent: "w",
            modifierMask: [.command, .shift]
        ))
        return menu
    }

    func showContextMenu(with event: NSEvent) {
        guard let contentView = window?.contentView else {
            return
        }
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: contentView)
    }

    func showContextMenu(atScreenPoint screenPoint: NSPoint) {
        guard let window, let contentView = window.contentView else {
            return
        }
        let location = NSPoint(x: screenPoint.x - window.frame.minX, y: screenPoint.y - window.frame.minY)
        guard let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            return
        }
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: contentView)
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifierMask
        item.target = self
        return item
    }

    @objc private func toggleEditingToolbarFromMenu() {
        toggleEditingToolbar()
    }

    fileprivate func toggleEditingToolbar() {
        if editingOverlayWindow == nil {
            showEditingToolbar()
        } else {
            hideEditingToolbar()
        }
    }

    @objc fileprivate func copyImage() {
        copyImageToPasteboard(pinnedImage)
    }

    @objc fileprivate func saveImage() {
        writeImageToFile(pinnedImage)
    }

    @objc private func resetSize() {
        applyWindowFrame(forImageFrame: initialImageFrame)
        refreshEditingOverlay()
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let opacity = sender.representedObject as? CGFloat else {
            return
        }
        window?.alphaValue = opacity
    }

    @objc private func toggleAlwaysOnTop() {
        let nextLevel: NSWindow.Level = window?.level == .floating ? .normal : .floating
        window?.level = nextLevel
        editingOverlayWindow?.level = nextLevel
    }

    @objc private func closePinnedWindow() {
        window?.close()
    }

    fileprivate func hidePinnedWindow() {
        guard window?.isVisible == true else {
            return
        }
        window?.orderOut(nil)
        onHide?()
    }

    @objc private func closeAllPinnedWindows() {
        for controller in Self.activeControllers.allObjects {
            controller.window?.close()
        }
    }

    fileprivate func handleKeyDown(_ event: NSEvent) -> Bool {
        if SelectionToolbarState.toolbarShortcut(for: "copy")?.matches(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        ) == true {
            copyImage()
            return true
        }
        if SelectionToolbarState.toolbarShortcut(for: "save")?.matches(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        ) == true {
            saveImage()
            return true
        }
        guard let command = PinnedImageWindowCommand(event: event) else {
            return false
        }
        performWindowCommand(command)
        return true
    }

    private func performWindowCommand(_ command: PinnedImageWindowCommand) {
        switch command {
        case .resetSize:
            resetSize()
        case .toggleAlwaysOnTop:
            toggleAlwaysOnTop()
        case .closeCurrent:
            closePinnedWindow()
        case .closeAll:
            closeAllPinnedWindows()
        }
    }

    private var contentView: PinnedImageContentView? {
        window?.contentView as? PinnedImageContentView
    }

    fileprivate var isEditingToolbarVisible: Bool {
        editingOverlayWindow != nil
    }

    fileprivate func refreshEditingToolbarLayout() {
        applyWindowFrame(forImageFrame: currentImageFrameInScreen())
    }

    private func currentImageFrameInScreen() -> NSRect {
        guard let window, let contentView else {
            return window.map { PinnedImageWindowGeometry.imageFrame(inWindowFrame: $0.frame) } ?? initialImageFrame
        }
        let imageRect = contentView.currentImageRect
        return NSRect(
            x: window.frame.minX + imageRect.minX,
            y: window.frame.minY + imageRect.minY,
            width: imageRect.width,
            height: imageRect.height
        )
    }

    private func applyWindowFrame(forImageFrame imageFrame: NSRect) {
        guard let window, let contentView else {
            return
        }
        let insets = contentView.requiredContentInsets(forImageWidth: imageFrame.width)
        contentView.contentInsets = insets
        let frame = NSRect(
            x: imageFrame.minX - insets.left,
            y: imageFrame.minY - insets.bottom,
            width: imageFrame.width + insets.left + insets.right,
            height: imageFrame.height + insets.top + insets.bottom
        )
        window.setFrame(frame, display: true)
    }

    private func editingOverlayGeometry(for imageFrame: NSRect) -> (windowFrame: NSRect, selectionRect: NSRect) {
        let visibleFrame = window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? imageFrame
        let minimumToolbarWidth: CGFloat = 600
        let bottomReserve: CGFloat = 132
        let topReserve: CGFloat = 24
        var frame = NSRect(
            x: imageFrame.maxX - max(imageFrame.width, minimumToolbarWidth),
            y: imageFrame.minY - bottomReserve,
            width: max(imageFrame.width, minimumToolbarWidth),
            height: imageFrame.height + bottomReserve + topReserve
        )

        if frame.width > visibleFrame.width {
            frame.size.width = visibleFrame.width
            frame.origin.x = visibleFrame.minX
        } else {
            frame.origin.x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - frame.width)
        }

        if frame.height > visibleFrame.height {
            frame.size.height = visibleFrame.height
            frame.origin.y = visibleFrame.minY
        } else {
            frame.origin.y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height)
        }

        let selectionRect = NSRect(
            x: imageFrame.minX - frame.minX,
            y: imageFrame.minY - frame.minY,
            width: imageFrame.width,
            height: imageFrame.height
        )
        return (frame, selectionRect)
    }

    private func scaleEditingOverlay(by factor: CGFloat, around anchorInScreen: NSPoint) {
        scale(by: factor, around: anchorInScreen)
        refreshEditingOverlay()
    }

    private func beginEditingOverlayDrag(at screenPoint: NSPoint) {
        let imageFrame = currentImageFrameInScreen()
        editingDragOffsetInScreen = NSPoint(
            x: screenPoint.x - imageFrame.minX,
            y: screenPoint.y - imageFrame.minY
        )
        editingOverlayWindow?.alphaValue = 0
    }

    private func dragEditingOverlay(to screenPoint: NSPoint) {
        guard let editingDragOffsetInScreen else {
            return
        }
        let imageFrame = currentImageFrameInScreen()
        let movedFrame = NSRect(
            x: screenPoint.x - editingDragOffsetInScreen.x,
            y: screenPoint.y - editingDragOffsetInScreen.y,
            width: imageFrame.width,
            height: imageFrame.height
        )
        applyWindowFrame(forImageFrame: movedFrame)
        refreshEditingOverlay()
    }

    private func endEditingOverlayDrag() {
        editingDragOffsetInScreen = nil
        refreshEditingOverlay()
        editingOverlayWindow?.alphaValue = 1
    }

    private func refreshEditingOverlay() {
        guard let editingOverlayWindow else {
            return
        }
        let imageFrame = currentImageFrameInScreen()
        let overlayGeometry = editingOverlayGeometry(for: imageFrame)
        let backgroundImage = editingOverlayBackgroundImage(
            frameSize: overlayGeometry.windowFrame.size,
            imageRect: overlayGeometry.selectionRect
        )
        editingOverlayWindow.updatePinnedImageEditor(
            windowFrame: overlayGeometry.windowFrame,
            backgroundImage: backgroundImage,
            selectionRect: overlayGeometry.selectionRect
        )
    }

    private func editingOverlayBackgroundImage(frameSize: NSSize, imageRect: NSRect) -> NSImage {
        let image = NSImage(size: frameSize)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: frameSize).fill()
        pinnedImage.draw(
            in: imageRect,
            from: NSRect(origin: .zero, size: pinnedImage.size),
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        return image
    }

    private func completeEditingOverlay(with result: CaptureSelectionResult?) {
        editingDragOffsetInScreen = nil
        editingOverlayWindow = nil
        guard let result else {
            return
        }

        let annotations = scaledAnnotationsForPinnedImage(
            result.annotations,
            from: result.snapshotRect.size
        )
        let eraserMasks = scaledEraserMasksForPinnedImage(
            result.eraserMasks,
            from: result.snapshotRect.size
        )
        let bakedImage = CaptureAnnotationRenderer.render(
            image: pinnedImage,
            annotations: annotations,
            eraserMasks: eraserMasks
        )
        updatePinnedImage(bakedImage)

        switch result.action {
        case .copy:
            copyImageToPasteboard(bakedImage)
        case .save:
            writeImageToFile(bakedImage)
        case .pin, .finishEditing:
            break
        }
    }

    private func updatePinnedImage(_ image: NSImage) {
        pinnedImage = image
        contentView?.image = image
        contentView?.needsDisplay = true
    }

    private func scaledAnnotationsForPinnedImage(
        _ annotations: [CaptureAnnotation],
        from sourceSize: NSSize
    ) -> [CaptureAnnotation] {
        let scale = pinnedImageScale(from: sourceSize)
        guard scale.x != 1 || scale.y != 1 else {
            return annotations
        }
        let strokeScale = (scale.x + scale.y) / 2
        return annotations.map { annotation in
            var annotation = annotation
            annotation.rect = scaledRect(annotation.rect, scale: scale)
            annotation.style.strokeWidth *= strokeScale
            annotation.style.cornerRadius *= strokeScale
            annotation.style.textSize *= strokeScale
            if var arrowLine = annotation.arrowLine {
                arrowLine.start = scaledPoint(arrowLine.start, scale: scale)
                arrowLine.end = scaledPoint(arrowLine.end, scale: scale)
                arrowLine.control = scaledPoint(arrowLine.control, scale: scale)
                annotation.arrowLine = arrowLine
            }
            if var brushPath = annotation.brushPath {
                brushPath.points = brushPath.points.map { scaledPoint($0, scale: scale) }
                annotation.brushPath = brushPath
            }
            if var markerLine = annotation.markerLine {
                markerLine.start = scaledPoint(markerLine.start, scale: scale)
                markerLine.end = scaledPoint(markerLine.end, scale: scale)
                annotation.markerLine = markerLine
            }
            if var mosaicStroke = annotation.mosaicStroke {
                mosaicStroke.points = mosaicStroke.points.map { scaledPoint($0, scale: scale) }
                annotation.mosaicStroke = mosaicStroke
            }
            return annotation
        }
    }

    private func scaledEraserMasksForPinnedImage(
        _ masks: [EraserMask],
        from sourceSize: NSSize
    ) -> [EraserMask] {
        let scale = pinnedImageScale(from: sourceSize)
        guard scale.x != 1 || scale.y != 1 else {
            return masks
        }
        return masks.map { mask in
            EraserMask(
                id: mask.id,
                rect: scaledRect(mask.rect, scale: scale),
                affectedAnnotationIDs: mask.affectedAnnotationIDs
            )
        }
    }

    private func pinnedImageScale(from sourceSize: NSSize) -> NSPoint {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return NSPoint(x: 1, y: 1)
        }
        return NSPoint(
            x: pinnedImage.size.width / sourceSize.width,
            y: pinnedImage.size.height / sourceSize.height
        )
    }

    private func scaledPoint(_ point: NSPoint, scale: NSPoint) -> NSPoint {
        NSPoint(x: point.x * scale.x, y: point.y * scale.y)
    }

    private func scaledRect(_ rect: NSRect, scale: NSPoint) -> NSRect {
        NSRect(
            x: rect.minX * scale.x,
            y: rect.minY * scale.y,
            width: rect.width * scale.x,
            height: rect.height * scale.y
        )
    }

    private func copyImageToPasteboard(_ image: NSImage) {
#if DEBUG
        if let imageActionHandlerForTesting {
            imageActionHandlerForTesting(.copy)
            return
        }
#endif
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func writeImageToFile(_ image: NSImage) {
#if DEBUG
        if let imageActionHandlerForTesting {
            imageActionHandlerForTesting(.save)
            return
        }
#endif
        guard
            let tiffData = image.tiffRepresentation,
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
}

extension PinnedImageWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        editingDragOffsetInScreen = nil
        editingOverlayWindow?.cancelOperation(nil)
        editingOverlayWindow = nil
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
    fileprivate enum HoverCursorStyle: Equatable {
        case arrow
        case move
    }

    var image: NSImage
    weak var controller: PinnedImageWindowController?
    private var dragOffset: NSPoint?
    private var shiftToolbarShortcutCandidate = false
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
    fileprivate var contentInsets = NSEdgeInsets(
        top: PinnedImageWindowGeometry.shadowOutset,
        left: PinnedImageWindowGeometry.shadowOutset,
        bottom: PinnedImageWindowGeometry.shadowOutset,
        right: PinnedImageWindowGeometry.shadowOutset
    ) {
        didSet {
            needsDisplay = true
        }
    }
    private var currentEditingTool: EditingToolbarButton?
    private let pinnedToolbarButtonStep: CGFloat = 28
    private let pinnedToolbarHorizontalPadding: CGFloat = 4
    private let pinnedToolbarHandleWidth: CGFloat = 28

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

    private enum EditingToolbarButton: CaseIterable, Hashable {
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
        case save
        case copy
        case done

        static let pinnedToolbarCases: [EditingToolbarButton] = [
            .rectangle,
            .arrow,
            .pen,
            .marker,
            .eyedropper,
            .mosaic,
            .text,
            .number,
            .magnifier,
            .eraser,
            .undo,
            .redo,
            .save,
            .copy,
            .done,
        ]

        var title: String {
            SelectionToolbarState.tooltipTitle(for: tooltipIdentifier) ?? "完成编辑"
        }

        var kindTitle: String {
            switch self {
            case .rectangle:
                return "矩形"
            case .arrow:
                return "箭头"
            case .marker:
                return "标记"
            default:
                return title
            }
        }

        var tooltipIdentifier: String {
            switch self {
            case .rectangle:
                return "rectangle"
            case .arrow:
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
            case .save:
                return "save"
            case .copy:
                return "copy"
            case .done:
                return "done"
            }
        }

        var iconName: String? {
            switch self {
            case .rectangle:
                return "toolbar-screenshot"
            case .arrow:
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
                return "toolbar-undo-disabled"
            case .redo:
                return "toolbar-redo-disabled"
            case .save:
                return "toolbar-save-to-file"
            case .copy:
                return "toolbar-copy-to-clipboard"
            case .done:
                return nil
            }
        }

        var isAnnotationTool: Bool {
            switch self {
            case .rectangle, .arrow, .pen, .marker:
                return true
            case .eyedropper, .mosaic, .text, .number, .magnifier, .eraser, .undo, .redo, .save, .copy, .done:
                return false
            }
        }

        var isEnabled: Bool {
            switch self {
            case .rectangle, .arrow, .pen, .marker, .eyedropper, .mosaic, .text, .number, .magnifier, .eraser, .save, .copy, .done:
                return true
            case .undo, .redo:
                return false
            }
        }

        func matches(title: String) -> Bool {
            self.title == title || kindTitle == title
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

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(currentImageRect, cursor: NSCursor.xxsnapMove)
    }

    override func draw(_ dirtyRect: NSRect) {
        let imageRect = currentImageRect
        drawBlueOuterShadow(around: imageRect)
        image.draw(in: imageRect)
        drawPendingAnnotations(in: imageRect)
        if showsEditingToolbar {
            if currentEditingTool != nil {
                drawOptionsToolbar(for: imageRect)
            }
            drawEditingToolbar(in: imageRect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        cancelShiftToolbarShortcutCandidate()
        window?.makeFirstResponder(self)
        let point = event.locationInWindow
        if showsEditingToolbar {
            if let button = editingToolbarButton(at: point) {
                performEditingToolbarButton(button)
                return
            }
            guard currentEditingTool != nil, currentImageRect.contains(point) else {
                return
            }
            annotationStartPoint = imagePoint(from: point)
            draftAnnotation = nil
            return
        }
        if window != nil {
            dragOffset = event.locationInWindow
            NSCursor.xxsnapMove.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        cancelShiftToolbarShortcutCandidate()
        if showsEditingToolbar, let annotationStartPoint, let currentEditingTool {
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
        cancelShiftToolbarShortcutCandidate()
        if showsEditingToolbar, let annotationStartPoint, let currentEditingTool {
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
        updateHoverCursor(at: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverCursor(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelShiftToolbarShortcutCandidate()
        controller?.showContextMenu(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        let relevantModifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if relevantModifiers == [.shift],
           dragOffset == nil {
            shiftToolbarShortcutCandidate = true
        } else if relevantModifiers.isEmpty, shiftToolbarShortcutCandidate {
            shiftToolbarShortcutCandidate = false
            controller?.toggleEditingToolbar()
        } else {
            shiftToolbarShortcutCandidate = false
        }
        super.flagsChanged(with: event)
    }

    fileprivate func hoverCursorStyle(at point: NSPoint) -> HoverCursorStyle {
        currentImageRect.contains(point) ? .move : .arrow
    }

    private func updateHoverCursor(at point: NSPoint) {
        switch hoverCursorStyle(at: point) {
        case .move:
            NSCursor.xxsnapMove.set()
        case .arrow:
            NSCursor.arrow.set()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        cancelShiftToolbarShortcutCandidate()
        guard event.deltaY != 0 else {
            return
        }
        let factor = event.deltaY > 0 ? 1.08 : 0.92
        controller?.scale(by: factor, around: NSEvent.mouseLocation)
    }

    override func magnify(with event: NSEvent) {
        cancelShiftToolbarShortcutCandidate()
        controller?.scale(by: 1 + event.magnification, around: NSEvent.mouseLocation)
    }

    override func keyDown(with event: NSEvent) {
        cancelShiftToolbarShortcutCandidate()
        if controller?.handleKeyDown(event) == true {
            return
        }
        if event.keyCode == 53 {
            controller?.hidePinnedWindow()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            window?.close()
            return
        }
        super.keyDown(with: event)
    }

    private func cancelShiftToolbarShortcutCandidate() {
        shiftToolbarShortcutCandidate = false
    }

    fileprivate var currentImageRect: NSRect {
        NSRect(
            x: contentInsets.left,
            y: contentInsets.bottom,
            width: max(1, bounds.width - contentInsets.left - contentInsets.right),
            height: max(1, bounds.height - contentInsets.top - contentInsets.bottom)
        )
    }

    fileprivate var editingToolbarTitles: [String] {
        EditingToolbarButton.pinnedToolbarCases.map(\.title)
    }

    fileprivate var currentEditingToolTitle: String {
        currentEditingTool?.title ?? ""
    }

    fileprivate var pendingAnnotationKindTitles: [String] {
        var titles = pendingAnnotations.map { $0.tool.kindTitle }
        if let draftAnnotation {
            titles.append(draftAnnotation.tool.kindTitle)
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

    fileprivate var editingToolbarIconRectsForTesting: [NSRect] {
        editingToolbarButtonRects().map { button, rect in
            if button == .done {
                return rect.insetBy(dx: 2, dy: 2)
            }
            let resourceName = (button.iconName ?? "").replacingOccurrences(of: "toolbar-", with: "")
            let inset = SelectionToolbarState.toolbarIconInset(for: resourceName)
            return rect.insetBy(dx: inset, dy: inset)
        }
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
        guard let currentEditingTool else {
            return
        }
        let startPoint = imagePoint(from: start)
        let endPoint = imagePoint(from: end)
        let annotation = makeAnnotation(tool: currentEditingTool, from: startPoint, to: endPoint)
        if isDrawableAnnotation(annotation) {
            pendingAnnotations.append(annotation)
            needsDisplay = true
        }
    }

    fileprivate func selectEditingTool(named title: String) {
        guard let tool = EditingToolbarButton.pinnedToolbarCases.first(where: { $0.matches(title: title) && $0.isAnnotationTool }) else {
            return
        }
        currentEditingTool = tool
        controller?.refreshEditingToolbarLayout()
        needsDisplay = true
    }

    fileprivate func beginEditingToolbar() {
        currentEditingTool = nil
        showsEditingToolbar = true
    }

    fileprivate func endEditingToolbar() {
        showsEditingToolbar = false
        currentEditingTool = nil
    }

    fileprivate func requiredContentInsets(forImageWidth imageWidth: CGFloat) -> NSEdgeInsets {
        let shadow = PinnedImageWindowGeometry.shadowOutset
        guard showsEditingToolbar else {
            return NSEdgeInsets(top: shadow, left: shadow, bottom: shadow, right: shadow)
        }

        let optionsHeight = currentEditingTool == nil ? 0 : editingOptionsToolbarHeight()
        let toolbarStackHeight = PinnedImageWindowGeometry.toolbarGap
            + PinnedImageWindowGeometry.toolbarHeight
            + (optionsHeight > 0 ? PinnedImageWindowGeometry.toolbarGap + optionsHeight : 0)
        let requiredToolbarWidth = max(editingToolbarWidth(), currentEditingTool == nil ? 0 : editingOptionsToolbarWidth())
        let extraLeft = max(0, requiredToolbarWidth - max(imageWidth, 1))

        return NSEdgeInsets(
            top: shadow,
            left: shadow + extraLeft,
            bottom: shadow + toolbarStackHeight,
            right: shadow
        )
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
        case .eyedropper, .mosaic, .text, .number, .magnifier, .eraser, .undo, .redo, .save, .copy, .done:
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
        case .eyedropper, .mosaic, .text, .number, .magnifier, .eraser, .undo, .redo, .save, .copy, .done:
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
        case .eyedropper, .mosaic, .text, .number, .magnifier, .eraser, .undo, .redo, .save, .copy, .done:
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

    fileprivate func editingToolbarRect(in imageRect: NSRect) -> NSRect {
        let width = editingToolbarWidth()
        let proposedX = imageRect.maxX - width
        let minX = bounds.minX + 4
        let maxX = bounds.maxX - width - 4
        let x = maxX >= minX ? min(max(proposedX, minX), maxX) : minX
        return NSRect(
            x: x,
            y: imageRect.minY - PinnedImageWindowGeometry.toolbarGap - PinnedImageWindowGeometry.toolbarHeight,
            width: width,
            height: PinnedImageWindowGeometry.toolbarHeight
        )
    }

    private func editingToolbarWidth() -> CGFloat {
        var width = pinnedToolbarHorizontalPadding * 2 + pinnedToolbarHandleWidth * 2
        for button in EditingToolbarButton.pinnedToolbarCases {
            width += pinnedToolbarButtonStep
            width += editingToolbarExtraGap(after: button)
        }
        return width
    }

    private func editingToolbarExtraGap(after button: EditingToolbarButton) -> CGFloat {
        switch button {
        case .eraser, .redo:
            return 8
        default:
            return 0
        }
    }

    private func editingToolbarButtonRects() -> [(EditingToolbarButton, NSRect)] {
        let toolbar = editingToolbarRect(in: currentImageRect)
        var x = toolbar.minX + pinnedToolbarHorizontalPadding + pinnedToolbarHandleWidth
        return EditingToolbarButton.pinnedToolbarCases.map { button in
            let rect = NSRect(x: x, y: toolbar.minY + 4, width: 20, height: 20)
            x += pinnedToolbarButtonStep + editingToolbarExtraGap(after: button)
            return (button, rect)
        }
    }

    private func editingToolbarButton(at point: NSPoint) -> EditingToolbarButton? {
        editingToolbarButtonRects().first { _, rect in rect.insetBy(dx: -4, dy: -4).contains(point) }?.0
    }

    private func performEditingToolbarButton(_ button: EditingToolbarButton) {
        guard button.isEnabled else {
            return
        }
        switch button {
        case .rectangle, .arrow, .pen, .marker:
            currentEditingTool = button
            controller?.refreshEditingToolbarLayout()
            needsDisplay = true
        case .eyedropper, .mosaic, .text, .number, .magnifier, .eraser, .undo, .redo:
            break
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
        drawToolbarPanel(toolbar)
        drawMainToolbarDragHandle(NSRect(
            x: toolbar.minX + pinnedToolbarHorizontalPadding,
            y: toolbar.minY + 4,
            width: 20,
            height: 20
        ))
        drawMainToolbarDragHandle(NSRect(
            x: toolbar.maxX - pinnedToolbarHorizontalPadding - 20,
            y: toolbar.minY + 4,
            width: 20,
            height: 20
        ))
        drawEditingToolbarSeparators(in: toolbar)

        for (button, rect) in editingToolbarButtonRects() {
            let selected = currentEditingTool == button && button.isAnnotationTool
            drawToolbarButton(rect, selected: selected, enabled: button.isEnabled)
            if let iconName = button.iconName {
                drawToolbarIcon(named: iconName, in: rect, enabled: button.isEnabled, selected: selected)
            } else {
                drawDoneCheck(in: rect, enabled: button.isEnabled)
            }
        }
    }

    private func drawEditingToolbarSeparators(in toolbar: NSRect) {
        let buttonRects = Dictionary(uniqueKeysWithValues: editingToolbarButtonRects())
        let separators: [(EditingToolbarButton, EditingToolbarButton)] = [
            (.eraser, .undo),
            (.redo, .save),
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

    private func drawDoneCheck(in rect: NSRect, enabled: Bool) {
        (enabled ? NSColor.black : NSColor.disabledControlTextColor).setStroke()
        let checkRect = rect.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: checkRect.minX + 2.5, y: checkRect.midY - 0.5))
        path.line(to: NSPoint(x: checkRect.midX - 1, y: checkRect.minY + 4))
        path.line(to: NSPoint(x: checkRect.maxX - 2, y: checkRect.maxY - 4))
        path.lineWidth = 2.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawOptionsToolbar(for imageRect: NSRect) {
        guard let optionsRect = editingOptionsToolbarRect(in: imageRect) else {
            return
        }
        let mode = currentOptionsToolbarMode
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: SelectionOverlayWindow.defaultPaletteColors.count,
            mode: mode
        )
        drawToolbarPanel(optionsRect)

        let widths = SelectionToolbarState.strokeWidthValues(for: mode)
        for (index, rect) in layout.strokeWidths.enumerated() {
            let width = widths[index]
            let selected = width == defaultStrokeWidth(for: mode)
            drawToolbarButton(optionButtonBackgroundRect(for: rect), selected: selected, enabled: true)
            (selected ? NSColor.controlAccentColor : NSColor.labelColor).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: rect.minX + 4, y: rect.midY))
            line.line(to: NSPoint(x: rect.maxX - 4, y: rect.midY))
            line.lineWidth = SelectionToolbarState.strokeWidthPreviewLineWidth(for: width, mode: mode)
            line.lineCapStyle = .round
            line.stroke()
        }

        if mode == .shape {
            drawFillPreview(in: layout.fillToggle)
            drawShapePreviewButtons(rectangle: layout.rectangleMode, ellipse: layout.ellipseMode)
        }
        if SelectionToolbarState.showsStrokeStyleField(for: mode) {
            drawStrokeStylePreview(in: layout.strokeStyle)
        }
        drawPinnedColorSwatches(layout.colorSwatches)
    }

    private var currentOptionsToolbarMode: SelectionToolbarState.OptionsToolbarMode {
        switch currentEditingTool {
        case .rectangle:
            return .shape
        case .arrow:
            return .arrowLine
        case .pen:
            return .brush
        case .marker:
            return .marker
        case .eyedropper, .mosaic, .text, .number, .magnifier, .eraser, .undo, .redo, .save, .copy, .done, nil:
            return .shape
        }
    }

    fileprivate func editingOptionsToolbarRect(in imageRect: NSRect) -> NSRect? {
        guard currentEditingTool != nil else {
            return nil
        }
        let size = NSSize(
            width: editingOptionsToolbarWidth(),
            height: editingOptionsToolbarHeight()
        )
        let mainToolbar = editingToolbarRect(in: imageRect)
        let proposedX = imageRect.maxX - size.width
        let minX = bounds.minX + 4
        let maxX = bounds.maxX - size.width - 4
        let x = maxX >= minX ? min(max(proposedX, minX), maxX) : minX
        let proposedY = mainToolbar.minY - size.height - PinnedImageWindowGeometry.toolbarGap
        let y = max(bounds.minY + 4, proposedY)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func editingOptionsToolbarWidth() -> CGFloat {
        SelectionToolbarState.optionsToolbarWidth(
            paletteCount: SelectionOverlayWindow.defaultPaletteColors.count,
            mode: currentOptionsToolbarMode
        )
    }

    private func editingOptionsToolbarHeight() -> CGFloat {
        SelectionToolbarState.optionsToolbarHeight(
            paletteCount: SelectionOverlayWindow.defaultPaletteColors.count,
            mode: currentOptionsToolbarMode
        )
    }

    private func defaultStrokeWidth(for mode: SelectionToolbarState.OptionsToolbarMode) -> CGFloat {
        let widths = SelectionToolbarState.strokeWidthValues(for: mode)
        switch mode {
        case .brush:
            return widths.first ?? 3
        case .marker:
            return widths.dropFirst().first ?? widths.first ?? 10
        default:
            return widths.dropFirst().first ?? widths.first ?? 3
        }
    }

    private func drawToolbarPanel(_ rect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        border.lineWidth = 1
        border.stroke()
    }

    private func drawToolbarButton(_ rect: NSRect, selected: Bool, enabled: Bool) {
        (selected ? NSColor.controlAccentColor.withAlphaComponent(SelectionToolbarState.toolbarSelectedBackgroundAlpha) : NSColor.clear).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        _ = enabled
    }

    private func drawToolbarIcon(named name: String, in rect: NSRect, enabled: Bool, selected: Bool) {
        let resourceName = name.replacingOccurrences(of: "toolbar-", with: "")
        let imageInset = SelectionToolbarState.toolbarIconInset(for: resourceName)
        let usesFixedColorResource = SelectionToolbarState.usesFixedColorToolbarIconResource(resourceName)
        if drawToolbarImage(
            named: resourceName,
            in: rect,
            template: !usesFixedColorResource,
            enabled: enabled,
            selected: selected,
            inset: imageInset
        ) || drawToolbarImage(
            named: name,
            in: rect,
            template: !usesFixedColorResource,
            enabled: enabled,
            selected: selected,
            inset: imageInset
        ) {
            return
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            image.isTemplate = true
            drawTintedToolbarImage(image, in: rect.insetBy(dx: 4, dy: 4), color: toolbarIconColor(enabled: enabled, selected: selected))
        }
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
            ?? Bundle.main.url(forResource: "Icons/\(name)", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? Bundle.main.url(forResource: "Icons/\(name)", withExtension: "png").flatMap(NSImage.init(contentsOf:))
        guard let image = resource else {
            return false
        }

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

    private func drawMainToolbarDragHandle(_ rect: NSRect) {
        drawToolbarButton(rect, selected: false, enabled: true)
        let color = SelectionToolbarState.mainToolbarDragHandleIconColor(enabled: true)
        let imageInset = SelectionToolbarState.toolbarIconInset(for: "settings-more")
        if drawToolbarImage(
            named: "settings-more",
            in: rect,
            template: true,
            enabled: true,
            inset: imageInset,
            tintColor: color
        ) || drawToolbarImage(
            named: "toolbar-settings-more",
            in: rect,
            template: true,
            enabled: true,
            inset: imageInset,
            tintColor: color
        ) {
            return
        }
    }

    private func optionButtonBackgroundRect(for rect: NSRect) -> NSRect {
        NSRect(x: rect.minX - 2, y: rect.minY - 1, width: rect.width + 4, height: rect.height + 2)
    }

    private func drawFillPreview(in rect: NSRect?) {
        guard let rect else {
            return
        }
        drawToolbarButton(optionButtonBackgroundRect(for: rect), selected: false, enabled: true)
        NSColor.systemRed.withAlphaComponent(0.22).setFill()
        NSBezierPath(rect: rect.insetBy(dx: 5, dy: 4)).fill()
        NSColor.systemRed.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 5, dy: 4))
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawShapePreviewButtons(rectangle: NSRect?, ellipse: NSRect?) {
        if let rectangle {
            drawToolbarButton(optionButtonBackgroundRect(for: rectangle), selected: true, enabled: true)
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(roundedRect: rectangle.insetBy(dx: 5, dy: 4), xRadius: 1.5, yRadius: 1.5)
            path.lineWidth = 1.6
            path.stroke()
        }
        if let ellipse {
            drawToolbarButton(optionButtonBackgroundRect(for: ellipse), selected: false, enabled: true)
            NSColor.labelColor.setStroke()
            let path = NSBezierPath(ovalIn: ellipse.insetBy(dx: 5, dy: 4))
            path.lineWidth = 1.6
            path.stroke()
        }
    }

    private func drawStrokeStylePreview(in rect: NSRect) {
        drawToolbarButton(rect, selected: false, enabled: true)
        NSColor.labelColor.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: rect.minX + 5, y: rect.midY))
        line.line(to: NSPoint(x: rect.maxX - 9, y: rect.midY))
        line.lineWidth = 2
        line.lineCapStyle = .round
        line.stroke()
        NSColor.black.setFill()
        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: rect.maxX - 7, y: rect.midY + 2))
        triangle.line(to: NSPoint(x: rect.maxX - 3, y: rect.midY + 2))
        triangle.line(to: NSPoint(x: rect.maxX - 5, y: rect.midY - 2))
        triangle.close()
        triangle.fill()
    }

    private func drawPinnedColorSwatches(_ swatches: [NSRect]) {
        let colors = SelectionOverlayWindow.defaultPaletteColors
        for (index, rect) in swatches.enumerated() {
            let color = colors[index % max(colors.count, 1)]
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSColor.separatorColor.setStroke()
            let border = NSBezierPath(ovalIn: rect)
            border.lineWidth = 1
            border.stroke()
        }
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

    func test_keyDown(
        keyCode: UInt16,
        charactersIgnoringModifiers: String = "",
        modifierFlags: NSEvent.ModifierFlags = []
    ) {
        guard let contentView = window?.contentView else {
            return
        }
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: charactersIgnoringModifiers,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        )
        if let event {
            contentView.keyDown(with: event)
        }
    }

    func test_setImageActionHandler(_ handler: @escaping (CaptureCompletionAction) -> Void) {
        imageActionHandlerForTesting = handler
    }

    func test_editingOverlayKeyDown(
        keyCode: UInt16,
        charactersIgnoringModifiers: String,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        editingOverlayWindow?.test_keyDown(
            keyCode: keyCode,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags
        )
    }

    func test_editingOverlayFlagsChanged(modifierFlags: NSEvent.ModifierFlags) {
        editingOverlayWindow?.test_flagsChanged(modifierFlags: modifierFlags)
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

    var test_contextMenuToolbarItemState: NSControl.StateValue {
        makeContextMenu().items.first { $0.title == "显示工具条 (⇧)" }?.state ?? .off
    }

    var test_isToolbarVisible: Bool {
        editingOverlayWindow != nil
    }

    var test_isEditingOverlayDraggingPinnedImage: Bool {
        editingOverlayWindow?.test_isPinnedImageDragInProgress ?? false
    }

    var test_editingOverlayAlpha: CGFloat? {
        editingOverlayWindow?.alphaValue
    }

    var test_editingOverlayMainToolbarRect: NSRect? {
        editingOverlayWindow?.test_mainToolbarRect()
    }

    func test_editingOverlayToolbarButtonRect(for button: TestToolbarButton) -> NSRect? {
        editingOverlayWindow?.test_mainToolbarButtonRect(for: button)
    }

    func test_setEditingOverlayState(
        annotations: [CaptureAnnotation],
        eraserMasks: [EraserMask]
    ) {
        editingOverlayWindow?.test_setAnnotations(annotations)
        editingOverlayWindow?.test_setEraserMasks(eraserMasks)
    }

    func test_editingOverlayAnnotation(at index: Int) -> CaptureAnnotation? {
        editingOverlayWindow?.test_annotation(at: index)
    }

    func test_editingOverlayEraserMask(at index: Int) -> EraserMask? {
        editingOverlayWindow?.test_eraserMask(at: index)
    }

    var test_imageRectInContent: NSRect {
        contentView?.currentImageRect ?? .zero
    }

    var test_imageFrameInScreen: NSRect {
        currentImageFrameInScreen()
    }

    var test_editingOverlayImageFrameInScreen: NSRect? {
        guard
            let editingOverlayWindow,
            let selectionRect = editingOverlayWindow.test_lockedSelectionRect
        else {
            return nil
        }
        return selectionRect.offsetBy(dx: editingOverlayWindow.frame.minX, dy: editingOverlayWindow.frame.minY)
    }

    var test_windowLevel: NSWindow.Level? {
        window?.level
    }

    var test_editingOverlayWindowLevel: NSWindow.Level? {
        editingOverlayWindow?.level
    }

    func test_flagsChanged(modifierFlags: NSEvent.ModifierFlags) {
        guard
            let contentView,
            let event = NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: 0,
                windowNumber: window?.windowNumber ?? 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 56
            )
        else {
            return
        }
        contentView.flagsChanged(with: event)
    }

    func test_mouseDownForShiftShortcutCancellation() {
        guard
            let contentView,
            let event = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: contentView.currentImageRect.midX, y: contentView.currentImageRect.midY),
                modifierFlags: [.shift],
                timestamp: 0,
                windowNumber: window?.windowNumber ?? 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        else {
            return
        }
        contentView.mouseDown(with: event)
    }

    var test_hoverCursorAtImageCenterIsMove: Bool {
        guard let contentView else {
            return false
        }
        let imageRect = contentView.currentImageRect
        return contentView.hoverCursorStyle(at: NSPoint(x: imageRect.midX, y: imageRect.midY)) == .move
    }

    var test_hoverCursorAtShadowIsArrow: Bool {
        guard let contentView else {
            return false
        }
        return contentView.hoverCursorStyle(at: NSPoint(x: 2, y: 2)) == .arrow
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

    func test_toggleEditingToolbarFromMenu() {
        guard let item = makeContextMenu().items.first(where: { $0.title == "显示工具条 (⇧)" }),
              let action = item.action
        else {
            return
        }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    func test_finishEditing() {
        finishEditing()
    }

    @discardableResult
    func test_dragEditingOverlayBy(dx: CGFloat, dy: CGFloat) -> Bool {
        guard let editingOverlayWindow else {
            return false
        }
        let imageFrame = currentImageFrameInScreen()
        let overlayFrame = editingOverlayWindow.frame
        let startScreen = NSPoint(x: imageFrame.midX, y: imageFrame.midY)
        let start = NSPoint(x: startScreen.x - overlayFrame.minX, y: startScreen.y - overlayFrame.minY)
        let end = NSPoint(x: start.x + dx, y: start.y + dy)
        editingOverlayWindow.test_mouseDown(at: start)
        let wasDragging = editingOverlayWindow.test_isPinnedImageDragInProgress
        let wasHiddenDuringDrag = editingOverlayWindow.alphaValue == 0
        editingOverlayWindow.test_mouseDragged(to: end)
        editingOverlayWindow.test_mouseUp(at: end)
        return wasDragging && wasHiddenDuringDrag
    }

    func test_scrollEditingOverlay(deltaY: CGFloat) {
        let point = editingOverlayWindow?.test_mainToolbarRect().map { NSPoint(x: $0.midX, y: $0.midY + 40) }
            ?? NSPoint(x: currentImageFrameInScreen().midX, y: currentImageFrameInScreen().midY)
        editingOverlayWindow?.test_scrollWheel(at: point, deltaY: deltaY)
    }

    func test_completeEditingOverlay(
        annotations: [CaptureAnnotation],
        eraserMasks: [EraserMask] = [],
        action: CaptureCompletionAction = .finishEditing
    ) {
        completeEditingOverlay(
            with: CaptureSelectionResult(
                screenRect: currentImageFrameInScreen(),
                snapshotRect: NSRect(origin: .zero, size: pinnedImage.size),
                annotations: annotations,
                eraserMasks: eraserMasks,
                action: action
            )
        )
    }

    func test_toolbarContains(_ title: String) -> Bool {
        contentView?.editingToolbarTitles.contains(title) == true
    }

    func test_toolbarTitleIndex(_ title: String) -> Int? {
        contentView?.editingToolbarTitles.firstIndex(of: title)
    }

    var test_editingToolbarIconRects: [NSRect] {
        contentView?.editingToolbarIconRectsForTesting ?? []
    }

    var test_editingToolbarRect: NSRect {
        guard let contentView else {
            return .zero
        }
        return contentView.editingToolbarRect(in: contentView.currentImageRect)
    }

    var test_optionsToolbarRect: NSRect? {
        guard let contentView else {
            return nil
        }
        return contentView.editingOptionsToolbarRect(in: contentView.currentImageRect)
    }

    func test_selectEditingTool(_ title: String) {
        contentView?.selectEditingTool(named: title)
    }

    func test_dragAnnotation(from start: NSPoint, to end: NSPoint) {
        contentView?.addAnnotationByDragging(from: start, to: end)
    }
}
#endif
