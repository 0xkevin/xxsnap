import AppKit

/// Top-down image geometry. All public Y coordinates are image points measured
/// from the long document's top edge, independently of AppKit's view flipping.
struct LongImageEditorGeometry: Equatable {
    var imageSize: NSSize
    var viewportSize: NSSize
    var scrollOffset: CGFloat

    var fitWidthScale: CGFloat { imageSize.width > 0 ? viewportSize.width / imageSize.width : 1 }
    var visibleImageRect: NSRect {
        let scale = max(fitWidthScale, 0.0001)
        return NSRect(x: 0, y: clampedOffset, width: imageSize.width,
                      height: max(0, min(imageSize.height - clampedOffset, viewportSize.height / scale)))
    }
    var topVisibleCenter: NSPoint { NSPoint(x: imageSize.width / 2, y: clampedOffset) }
    func imagePoint(forViewportPoint point: NSPoint) -> NSPoint {
        let scale = max(fitWidthScale, 0.0001)
        return NSPoint(x: point.x / scale, y: clampedOffset + point.y / scale)
    }
    func resized(viewportSize: NSSize, preserving anchor: NSPoint) -> Self {
        Self(imageSize: imageSize, viewportSize: viewportSize, scrollOffset: anchor.y)
    }
    private var clampedOffset: CGFloat {
        let visibleHeight = viewportSize.height / max(fitWidthScale, 0.0001)
        return min(max(0, scrollOffset), max(0, imageSize.height - visibleHeight))
    }
}

enum LongImageAnnotationTranslation {
    static func annotation(_ source: CaptureAnnotation, by offset: NSPoint) -> CaptureAnnotation {
        var result = source
        result.rect.origin = point(result.rect.origin, by: offset)
        if var line = result.arrowLine {
            line.start = point(line.start, by: offset); line.end = point(line.end, by: offset)
            line.control = point(line.control, by: offset); result.arrowLine = line
        }
        if var path = result.brushPath { path.points = path.points.map { point($0, by: offset) }; result.brushPath = path }
        if var line = result.markerLine {
            line.start = point(line.start, by: offset); line.end = point(line.end, by: offset); result.markerLine = line
        }
        if var stroke = result.mosaicStroke {
            stroke.points = stroke.points.map { point($0, by: offset) }; result.mosaicStroke = stroke
        }
        return result
    }
    static func mask(_ source: EraserMask, by offset: NSPoint) -> EraserMask {
        var result = source; result.rect.origin = point(result.rect.origin, by: offset); return result
    }
    static func annotation(_ source: CaptureAnnotation, fromImageSliceOrigin origin: NSPoint, displayScale: CGFloat) -> CaptureAnnotation {
        scaled(annotation(source, by: NSPoint(x: -origin.x, y: -origin.y)), by: displayScale)
    }
    static func annotation(_ source: CaptureAnnotation, toImageSliceOrigin origin: NSPoint, displayScale: CGFloat) -> CaptureAnnotation {
        annotation(scaled(source, by: 1 / max(displayScale, 0.0001)), by: origin)
    }
    static func mask(_ source: EraserMask, fromImageSliceOrigin origin: NSPoint, displayScale: CGFloat) -> EraserMask {
        scaled(mask(source, by: NSPoint(x: -origin.x, y: -origin.y)), by: displayScale)
    }
    static func mask(_ source: EraserMask, toImageSliceOrigin origin: NSPoint, displayScale: CGFloat) -> EraserMask {
        mask(scaled(source, by: 1 / max(displayScale, 0.0001)), by: origin)
    }
    private static func scaled(_ source: CaptureAnnotation, by scale: CGFloat) -> CaptureAnnotation {
        var result = source
        result.rect = NSRect(x: result.rect.minX * scale, y: result.rect.minY * scale, width: result.rect.width * scale, height: result.rect.height * scale)
        if var line = result.arrowLine {
            line.start = scalePoint(line.start, scale); line.end = scalePoint(line.end, scale); line.control = scalePoint(line.control, scale); result.arrowLine = line
        }
        if var path = result.brushPath { path.points = path.points.map { scalePoint($0, scale) }; result.brushPath = path }
        if var line = result.markerLine { line.start = scalePoint(line.start, scale); line.end = scalePoint(line.end, scale); result.markerLine = line }
        if var stroke = result.mosaicStroke { stroke.points = stroke.points.map { scalePoint($0, scale) }; result.mosaicStroke = stroke }
        return result
    }
    private static func scaled(_ source: EraserMask, by scale: CGFloat) -> EraserMask {
        var result = source
        result.rect = NSRect(x: result.rect.minX * scale, y: result.rect.minY * scale, width: result.rect.width * scale, height: result.rect.height * scale)
        return result
    }
    private static func scalePoint(_ value: NSPoint, _ scale: CGFloat) -> NSPoint { NSPoint(x: value.x * scale, y: value.y * scale) }
    private static func point(_ value: NSPoint, by offset: NSPoint) -> NSPoint {
        NSPoint(x: value.x + offset.x, y: value.y + offset.y)
    }
}

struct LongImageEditorSlice {
    var image: NSImage
    var imageRect: NSRect
    var annotations: [CaptureAnnotation]
    var eraserMasks: [EraserMask]
}

struct LongImageEditorDocument {
    var image: NSImage
    var annotations: [CaptureAnnotation]
    var eraserMasks: [EraserMask]

    static func visibleSlice(image: NSImage, annotations: [CaptureAnnotation], eraserMasks: [EraserMask], imageRect: NSRect) -> LongImageEditorSlice {
        let rect = imageRect.intersection(NSRect(origin: .zero, size: image.size))
        let visible = annotations.filter { $0.rect.intersects(rect) }
        let visibleIDs = Set(visible.map(\.id))
        let masks = eraserMasks.filter { $0.rect.intersects(rect) && !$0.affectedAnnotationIDs.isDisjoint(with: visibleIDs) }
        let offset = NSPoint(x: -rect.minX, y: -rect.minY)
        return LongImageEditorSlice(
            image: crop(image, rect: rect), imageRect: rect,
            annotations: visible.map { LongImageAnnotationTranslation.annotation($0, by: offset) },
            eraserMasks: masks.map { LongImageAnnotationTranslation.mask($0, by: offset) }
        )
    }

    private static func crop(_ image: NSImage, rect: NSRect) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let sx = CGFloat(source.width) / max(image.size.width, 1), sy = CGFloat(source.height) / max(image.size.height, 1)
        let pixels = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy).integral
            .intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let cropped = source.cropping(to: pixels) else { return image }
        return NSImage(cgImage: cropped, size: rect.size)
    }
}

private final class LongImageFlippedView: NSView { override var isFlipped: Bool { true } }

@MainActor
final class LongImageEditorWindowController: NSWindowController, NSWindowDelegate {
    static let controlStripHeight: CGFloat = 52
    let scrollView = NSScrollView()
    let controlStripView = NSView()
    private let imageView = NSImageView(), documentView = LongImageFlippedView()
    private var documentState: LongImageEditorDocument
    private var boundsObserver: NSObjectProtocol?
    private var overlay: SelectionOverlayWindow?
    private var interactionLocked = false
    private(set) var geometry: LongImageEditorGeometry
    var onFinishEditing: ((NSImage, [CaptureAnnotation], [EraserMask]) -> Void)?

    var imagePixelSize: NSSize {
        guard let cg = documentState.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .zero }
        return NSSize(width: cg.width, height: cg.height)
    }
    var fitWidthScale: CGFloat { geometry.fitWidthScale }
    var visibleImageRect: NSRect { geometry.visibleImageRect }

    init(image: NSImage, annotations: [CaptureAnnotation] = [], eraserMasks: [EraserMask] = [], visibleFrame: NSRect? = NSScreen.main?.visibleFrame, initialWindowSize: NSSize? = nil) {
        let visible = visibleFrame ?? NSRect(x: 0, y: 0, width: 1_200, height: 900)
        documentState = LongImageEditorDocument(image: image, annotations: annotations, eraserMasks: eraserMasks)
        let requested = initialWindowSize ?? NSSize(width: min(1_000, visible.width), height: min(840, visible.height))
        let size = NSSize(width: min(requested.width, visible.width), height: min(requested.height, visible.height))
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        // `visibleFrame` bounds the complete titled window, not just its content.
        window.setFrame(frame, display: false)
        window.title = "长截图编辑"
        geometry = LongImageEditorGeometry(imageSize: image.size, viewportSize: NSSize(width: size.width, height: size.height - Self.controlStripHeight), scrollOffset: 0)
        super.init(window: window)
        window.delegate = self
        configureViews()
        observeScroll()
        relayout(preserving: geometry.topVisibleCenter)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        overlay?.orderOut(nil)
    }

    func show() { showWindow(nil); window?.makeKeyAndOrderFront(nil); showOverlay() }
    func windowDidResize(_ notification: Notification) {
        let anchor = geometry.topVisibleCenter; commitOverlay(); relayout(preserving: anchor); refreshOverlay()
    }
    func windowWillClose(_ notification: Notification) { commitOverlay(); overlay?.orderOut(nil); overlay = nil }

    private func configureViews() {
        guard let content = window?.contentView else { return }
        controlStripView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true; scrollView.hasHorizontalScroller = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        imageView.image = documentState.image; imageView.imageScaling = .scaleAxesIndependently
        documentView.addSubview(imageView); scrollView.documentView = documentView
        content.addSubview(scrollView); content.addSubview(controlStripView)
        NSLayoutConstraint.activate([
            controlStripView.leadingAnchor.constraint(equalTo: content.leadingAnchor), controlStripView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            controlStripView.topAnchor.constraint(equalTo: content.topAnchor), controlStripView.heightAnchor.constraint(equalToConstant: Self.controlStripHeight),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: controlStripView.bottomAnchor), scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        content.layoutSubtreeIfNeeded()
    }
    private func observeScroll() {
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrolled() }
        }
    }
    private func relayout(preserving anchor: NSPoint) {
        window?.contentView?.layoutSubtreeIfNeeded()
        geometry = geometry.resized(viewportSize: scrollView.contentSize, preserving: anchor)
        let size = NSSize(width: documentState.image.size.width * geometry.fitWidthScale, height: documentState.image.size.height * geometry.fitWidthScale)
        documentView.frame = NSRect(origin: .zero, size: size); imageView.frame = documentView.bounds
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: geometry.scrollOffset * geometry.fitWidthScale))
        scrollView.reflectScrolledClipView(scrollView.contentView); updateOffset()
    }
    private func scrolled() { guard !interactionLocked else { return }; commitOverlay(); updateOffset(); refreshOverlay() }
    private func updateOffset() { geometry.scrollOffset = scrollView.contentView.bounds.minY / max(geometry.fitWidthScale, 0.0001) }
    private func viewportScreenFrame() -> NSRect {
        guard let window else { return .zero }; return window.convertToScreen(scrollView.convert(scrollView.bounds, to: nil))
    }
    private func showOverlay() {
        guard overlay == nil else { refreshOverlay(); return }
        let slice = LongImageEditorDocument.visibleSlice(image: documentState.image, annotations: documentState.annotations, eraserMasks: documentState.eraserMasks, imageRect: visibleImageRect)
        let frame = viewportScreenFrame()
        let config = SelectionOverlayConfiguration.longImageEditor(
            windowFrame: frame, selectionRect: NSRect(origin: .zero, size: frame.size),
            initialAnnotations: slice.annotations.map { LongImageAnnotationTranslation.annotation($0, fromImageSliceOrigin: .zero, displayScale: geometry.fitWidthScale) },
            initialEraserMasks: slice.eraserMasks.map { LongImageAnnotationTranslation.mask($0, fromImageSliceOrigin: .zero, displayScale: geometry.fitWidthScale) },
            interactionBegan: { [weak self] in self?.lock(true) }, interactionEnded: { [weak self] in self?.lock(false) }
        )
        let value = SelectionOverlayWindow(backgroundImage: displayImage(slice.image, size: frame.size), configuration: config) { [weak self] in self?.finish($0) }
        overlay = value; value.present()
    }
    private func refreshOverlay() {
        guard let overlay else { return }
        let slice = LongImageEditorDocument.visibleSlice(image: documentState.image, annotations: documentState.annotations, eraserMasks: documentState.eraserMasks, imageRect: visibleImageRect)
        let frame = viewportScreenFrame()
        overlay.updateLongImageEditor(
            windowFrame: frame, backgroundImage: displayImage(slice.image, size: frame.size),
            selectionRect: NSRect(origin: .zero, size: frame.size),
            annotations: slice.annotations.map { LongImageAnnotationTranslation.annotation($0, fromImageSliceOrigin: .zero, displayScale: geometry.fitWidthScale) },
            eraserMasks: slice.eraserMasks.map { LongImageAnnotationTranslation.mask($0, fromImageSliceOrigin: .zero, displayScale: geometry.fitWidthScale) }
        )
    }
    private func commitOverlay() {
        guard let snapshot = overlay?.editorSnapshot else { return }
        let origin = visibleImageRect.origin, oldVisible = Set(documentState.annotations.filter { $0.rect.intersects(visibleImageRect) }.map(\.id))
        let localIDs = Set(snapshot.annotations.map(\.id)); documentState.annotations.removeAll { oldVisible.contains($0.id) && !localIDs.contains($0.id) }
        for local in snapshot.annotations {
            let full = LongImageAnnotationTranslation.annotation(local, toImageSliceOrigin: origin, displayScale: geometry.fitWidthScale)
            if let index = documentState.annotations.firstIndex(where: { $0.id == full.id }) { documentState.annotations[index] = full } else { documentState.annotations.append(full) }
        }
        let localMaskIDs = Set(snapshot.eraserMasks.map(\.id)); documentState.eraserMasks.removeAll { $0.rect.intersects(visibleImageRect) && !localMaskIDs.contains($0.id) }
        for local in snapshot.eraserMasks {
            let full = LongImageAnnotationTranslation.mask(local, toImageSliceOrigin: origin, displayScale: geometry.fitWidthScale)
            if let index = documentState.eraserMasks.firstIndex(where: { $0.id == full.id }) { documentState.eraserMasks[index] = full } else { documentState.eraserMasks.append(full) }
        }
    }
    private func lock(_ value: Bool) {
        interactionLocked = value; scrollView.verticalScroller?.isEnabled = !value
        if !value { commitOverlay(); refreshOverlay() }
    }
    private func finish(_ result: CaptureSelectionResult?) {
        guard result?.action == .finishEditing else { return }; commitOverlay()
        onFinishEditing?(documentState.image, documentState.annotations, documentState.eraserMasks); close()
    }
    private func displayImage(_ image: NSImage, size: NSSize) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        return NSImage(cgImage: cg, size: size)
    }
}
