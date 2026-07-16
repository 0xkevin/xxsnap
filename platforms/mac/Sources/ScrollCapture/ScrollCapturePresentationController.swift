import AppKit

private final class ScrollCaptureHitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class ScrollCapturePreviewDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private enum ScrollCapturePreviewVerticalAnchor: Equatable {
    case top
    case bottom
}

enum ScrollCaptureOverlayState: Equatable {
    case inactive
    case capturing
    case paused(message: String)
}

enum ScrollCaptureStepControlState: Equatable {
    case preparing
    case ready(directionLocked: Bool)
    case executing
    case boundary
}

struct ScrollCaptureControlGeometry: Equatable {
    let toolbarFrame: NSRect
    let finishButtonFrame: NSRect
    let cancelButtonFrame: NSRect
}

@MainActor
final class ScrollCapturePresentationController: NSObject {
    private let controlPanel: NSPanel
    private let stepPanel: NSPanel
    private let previewPanel: NSPanel
    private let warningPanel: NSPanel
    private let boundaryPanel: NSPanel
    private let controlFrame: NSRect
    private let stepAnchorButtonFrame: NSRect
    private let captureViewportPointHeight: CGFloat
    private let maximumPreviewContentSize: NSSize
    private let language: AppLanguage
    private let finishButton = NSButton()
    private let cancelButton = NSButton()
    private let directionControl = NSPopUpButton()
    private let startButton = NSButton()
    private let stepProgressIndicator = NSProgressIndicator()
    private let stopButton = NSButton()
    private var startButtonIdleImage: NSImage?
    private let scrollView = NSScrollView()
    private let previewDocumentView = ScrollCapturePreviewDocumentView()
    private let imageView = NSImageView()
    private let viewportIndicatorView = NSView()
    private let warningTextBackground = NSView()
    private let warningAccentView = NSView()
    private let warningIconView = NSImageView()
    private let warningLabel = NSTextField(labelWithString: "")
    private let warningCloseButton = NSButton()
    private let boundaryIconView = NSImageView()
    private let boundaryTextBackground = NSView()
    private let boundaryAccentView = NSView()
    private let boundaryTitleLabel = NSTextField(labelWithString: "")
    private let boundaryDismissButton = NSButton()
    private let onStep: (ScrollCaptureDirection) -> Void
    private let onFinish: () -> Void
    private let onCancel: () -> Void
    private var boundsObserver: NSObjectProtocol?
    private var isProgrammaticScroll = false
    private(set) var isFollowingTail = true
    private var reviewOffset: CGFloat = 0
    private var followEdge: ScrollCapturePreviewEdge = .bottom
    private var currentPreviewViewport: ScrollCapturePreviewViewport?
    private var indicatorPositionIsWheelDriven = false
    private var viewportTopPixel: CGFloat?
    private var previewOutputHeight = 0
    private var lastWheelDirection: ScrollCaptureDirection = .unknown
    private var initialVerticalAnchor: ScrollCapturePreviewVerticalAnchor?
    private var placementSelectionFrame: NSRect
    private var placementVisibleFrame: NSRect
    private var previewGrowthFrame: NSRect
    private var terminalActionTriggered = false
    private var stepControlState: ScrollCaptureStepControlState = .preparing
    private var boundaryWarningVisible = false
    private var boundaryDismissTask: DispatchWorkItem?
    private var hasStarted = false
    private var stopped = false

    init(
        toolbarFrame: NSRect,
        finishButtonFrame: NSRect,
        cancelButtonFrame: NSRect,
        selectionFrame: NSRect,
        visibleFrame: NSRect,
        language: AppLanguage,
        onStep: @escaping (ScrollCaptureDirection) -> Void = { _ in },
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onStep = onStep
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.controlFrame = toolbarFrame
        self.stepAnchorButtonFrame = finishButtonFrame
        self.language = language
        self.captureViewportPointHeight = max(1, selectionFrame.height)
        self.placementSelectionFrame = selectionFrame
        self.placementVisibleFrame = visibleFrame
        controlPanel = ScrollCaptureHitPanel(
            contentRect: toolbarFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let stepSize = NSSize(width: 168, height: 32)
        stepPanel = ScrollCaptureHitPanel(
            contentRect: Self.stepToolbarFrame(
                anchoredTo: finishButtonFrame,
                toolbarFrame: toolbarFrame,
                selectionFrame: selectionFrame,
                size: stepSize,
                visibleFrame: visibleFrame
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let previewSize = NSSize(width: 300, height: min(480, max(240, visibleFrame.height * 0.6)))
        self.maximumPreviewContentSize = NSSize(
            width: previewSize.width,
            height: previewSize.height
        )
        let previewFrame = Self.previewFrameAvoidingControls(
            selection: selectionFrame,
            previewSize: previewSize,
            visibleFrame: visibleFrame,
            blockedFrames: [toolbarFrame, stepPanel.frame]
        )
        self.previewGrowthFrame = previewFrame
        previewPanel = NSPanel(
            contentRect: previewFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        warningPanel = ScrollCaptureHitPanel(
            contentRect: Self.warningPanelFrame(
                selection: selectionFrame,
                size: NSSize(width: 252, height: 44),
                visibleFrame: visibleFrame,
                blockedFrames: [toolbarFrame, stepPanel.frame, previewFrame]
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        boundaryPanel = ScrollCaptureHitPanel(
            contentRect: Self.warningPanelFrame(
                selection: selectionFrame,
                size: NSSize(width: 252, height: 44),
                visibleFrame: visibleFrame,
                blockedFrames: []
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        let l10n = L10n(language: language)
        configureControlPanel(
            finishButtonFrame: finishButtonFrame,
            cancelButtonFrame: cancelButtonFrame,
            finishLabel: l10n.text(.finishScrollCapture),
            cancelLabel: l10n.text(.cancel)
        )
        configureStepPanel(language: language)
        configurePreviewPanel()
        configureWarningPanel()
        configureBoundaryPanel()
        installBoundsObserver()
    }

    private func configureControlPanel(
        finishButtonFrame: NSRect,
        cancelButtonFrame: NSRect,
        finishLabel: String,
        cancelLabel: String
    ) {
        controlPanel.level = .screenSaver
        controlPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        controlPanel.isOpaque = false
        controlPanel.backgroundColor = .clear
        controlPanel.hasShadow = false
        controlPanel.ignoresMouseEvents = false
        let content = NSView(frame: NSRect(origin: .zero, size: controlPanel.frame.size))
        configureControlButton(
            cancelButton,
            frame: cancelButtonFrame.offsetBy(dx: -controlFrame.minX, dy: -controlFrame.minY),
            action: #selector(cancelPressed),
            label: cancelLabel
        )
        content.addSubview(cancelButton)
        controlPanel.contentView = content
    }

    private func configureStepPanel(language: AppLanguage) {
        stepPanel.level = .screenSaver
        stepPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        stepPanel.isOpaque = false
        stepPanel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        stepPanel.hasShadow = true
        stepPanel.ignoresMouseEvents = false

        let content = NSView(frame: NSRect(origin: .zero, size: stepPanel.frame.size))
        directionControl.frame = NSRect(x: 6, y: 4, width: 96, height: 24)
        directionControl.removeAllItems()
        directionControl.addItems(withTitles: language == .zhHans
            ? ["向下滚动", "向上滚动"]
            : ["Scroll Down", "Scroll Up"])
        directionControl.selectItem(at: 0)
        directionControl.target = self
        directionControl.action = #selector(directionChanged)

        configureStepButton(
            startButton,
            frame: NSRect(x: 106, y: 2, width: 28, height: 28),
            resourceName: "mouse-point",
            fallbackSymbol: "play.circle",
            action: #selector(startPressed),
            label: language == .zhHans ? "开始单步滚动" : "Start Scroll Step"
        )
        startButtonIdleImage = startButton.image
        stepProgressIndicator.frame = NSRect(
            x: startButton.frame.midX - 9,
            y: startButton.frame.midY - 9,
            width: 18,
            height: 18
        )
        stepProgressIndicator.style = .spinning
        stepProgressIndicator.controlSize = .small
        stepProgressIndicator.isIndeterminate = true
        stepProgressIndicator.isDisplayedWhenStopped = false
        stepProgressIndicator.isHidden = true
        configureStepButton(
            stopButton,
            frame: NSRect(x: 136, y: 2, width: 28, height: 28),
            resourceName: "stop-circle",
            fallbackSymbol: "stop.circle",
            action: #selector(finishPressed),
            label: language == .zhHans ? "结束滚动截图" : "Finish Scroll Capture"
        )
        content.addSubview(directionControl)
        content.addSubview(startButton)
        content.addSubview(stepProgressIndicator)
        content.addSubview(stopButton)
        stepPanel.contentView = content
        directionChanged()
        setStepControlState(.preparing)
    }

    private func configureStepButton(
        _ button: NSButton,
        frame: NSRect,
        resourceName: String,
        fallbackSymbol: String,
        action: Selector,
        label: String
    ) {
        button.frame = frame
        button.title = ""
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        let image = NSImage(named: resourceName)
            ?? Bundle.main.url(forResource: resourceName, withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: label)
        image?.size = NSSize(width: 20, height: 20)
        image?.isTemplate = true
        button.image = image
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.setAccessibilityRole(.button)
        button.target = self
        button.action = action
    }

    private func configureControlButton(_ button: NSButton, frame: NSRect, action: Selector, label: String) {
        button.frame = frame
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.setAccessibilityRole(.button)
        button.target = self
        button.action = action
    }

    private func configurePreviewPanel() {
        previewPanel.level = .screenSaver
        previewPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        previewPanel.isOpaque = false
        previewPanel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        previewPanel.hasShadow = true
        previewPanel.ignoresMouseEvents = true

        let content = NSView(frame: NSRect(origin: .zero, size: previewPanel.frame.size))
        scrollView.frame = content.bounds
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.drawsBackground = false
        imageView.imageScaling = .scaleAxesIndependently
        previewDocumentView.addSubview(imageView)
        viewportIndicatorView.wantsLayer = true
        viewportIndicatorView.layer?.borderColor = NSColor.systemBlue.cgColor
        viewportIndicatorView.layer?.borderWidth = 2
        viewportIndicatorView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.10).cgColor
        viewportIndicatorView.layer?.cornerRadius = 2
        previewDocumentView.addSubview(viewportIndicatorView)
        scrollView.documentView = previewDocumentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        content.addSubview(scrollView)
        previewPanel.contentView = content
    }

    private func configureWarningPanel() {
        warningPanel.level = .screenSaver
        warningPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        warningPanel.isOpaque = false
        warningPanel.backgroundColor = .clear
        warningPanel.hasShadow = false
        warningPanel.ignoresMouseEvents = false

        let content = NSView(frame: NSRect(origin: .zero, size: warningPanel.frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor

        warningTextBackground.frame = content.bounds
        warningTextBackground.wantsLayer = true
        warningTextBackground.layer?.backgroundColor = NSColor.black.cgColor
        warningTextBackground.layer?.cornerRadius = 11
        warningTextBackground.layer?.cornerCurve = .continuous
        warningTextBackground.layer?.shadowColor = NSColor.black.cgColor
        warningTextBackground.layer?.shadowOpacity = 0.22
        warningTextBackground.layer?.shadowRadius = 8
        warningTextBackground.layer?.shadowOffset = NSSize(width: 0, height: -3)

        let warningYellow = NSColor(srgbRed: 1, green: 176 / 255, blue: 32 / 255, alpha: 1)
        warningAccentView.wantsLayer = true
        warningAccentView.layer?.backgroundColor = warningYellow.cgColor
        warningAccentView.layer?.cornerRadius = 2.5

        warningIconView.image = NSImage(
            systemSymbolName: "exclamationmark.circle",
            accessibilityDescription: language == .zhHans ? "提示" : "Notice"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        warningIconView.image?.isTemplate = true
        warningIconView.imageScaling = .scaleProportionallyDown
        warningIconView.contentTintColor = warningYellow

        warningLabel.alignment = .left
        warningLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        warningLabel.textColor = .white
        warningLabel.maximumNumberOfLines = 1
        warningLabel.lineBreakMode = .byTruncatingTail
        warningLabel.cell?.wraps = false
        warningLabel.cell?.usesSingleLineMode = true
        warningLabel.isHidden = true
        warningCloseButton.title = ""
        warningCloseButton.isBordered = false
        warningCloseButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: language == .zhHans ? "关闭提示" : "Dismiss"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        warningCloseButton.image?.isTemplate = true
        warningCloseButton.contentTintColor = NSColor.white.withAlphaComponent(0.72)
        warningCloseButton.toolTip = language == .zhHans ? "关闭提示" : "Dismiss"
        warningCloseButton.setAccessibilityLabel(language == .zhHans ? "关闭提示" : "Dismiss")
        warningCloseButton.setAccessibilityRole(.button)
        warningCloseButton.target = self
        warningCloseButton.action = #selector(dismissWarningPressed)
        warningTextBackground.addSubview(warningAccentView)
        warningTextBackground.addSubview(warningIconView)
        warningTextBackground.addSubview(warningLabel)
        warningTextBackground.addSubview(warningCloseButton)
        content.addSubview(warningTextBackground)
        warningPanel.contentView = content
        layoutWarningContent()
    }

    private func configureBoundaryPanel() {
        boundaryPanel.level = .screenSaver
        boundaryPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        boundaryPanel.isOpaque = false
        boundaryPanel.backgroundColor = .clear
        boundaryPanel.hasShadow = false
        boundaryPanel.ignoresMouseEvents = false
        boundaryPanel.isMovableByWindowBackground = false
        boundaryPanel.isReleasedWhenClosed = false

        let content = NSView(frame: NSRect(origin: .zero, size: boundaryPanel.frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor

        boundaryTextBackground.frame = content.bounds
        boundaryTextBackground.wantsLayer = true
        boundaryTextBackground.layer?.backgroundColor = NSColor.black.cgColor
        boundaryTextBackground.layer?.cornerRadius = 11
        boundaryTextBackground.layer?.cornerCurve = .continuous
        boundaryTextBackground.layer?.shadowColor = NSColor.black.cgColor
        boundaryTextBackground.layer?.shadowOpacity = 0.22
        boundaryTextBackground.layer?.shadowRadius = 8
        boundaryTextBackground.layer?.shadowOffset = NSSize(width: 0, height: -3)

        boundaryAccentView.frame = NSRect(x: 0, y: 0, width: 5, height: 44)
        boundaryAccentView.wantsLayer = true
        let warningYellow = NSColor(srgbRed: 1, green: 176 / 255, blue: 32 / 255, alpha: 1)
        boundaryAccentView.layer?.backgroundColor = warningYellow.cgColor
        boundaryAccentView.layer?.cornerRadius = 2.5

        boundaryIconView.frame = NSRect(x: 22, y: 10, width: 24, height: 24)
        boundaryIconView.imageScaling = .scaleProportionallyDown
        boundaryIconView.contentTintColor = warningYellow

        boundaryTitleLabel.frame = NSRect(x: 60, y: 9, width: 168, height: 24)
        boundaryTitleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        boundaryTitleLabel.textColor = .white
        boundaryTitleLabel.alignment = .left
        boundaryTitleLabel.lineBreakMode = .byTruncatingTail
        boundaryTextBackground.addSubview(boundaryAccentView)
        boundaryTextBackground.addSubview(boundaryIconView)
        boundaryTextBackground.addSubview(boundaryTitleLabel)

        boundaryDismissButton.frame = content.bounds
        boundaryDismissButton.autoresizingMask = [.width, .height]
        boundaryDismissButton.title = ""
        boundaryDismissButton.isBordered = false
        boundaryDismissButton.focusRingType = .none
        boundaryDismissButton.toolTip = language == .zhHans ? "点击关闭提示" : "Click to dismiss"
        boundaryDismissButton.setAccessibilityLabel(language == .zhHans ? "关闭提示" : "Dismiss")
        boundaryDismissButton.target = self
        boundaryDismissButton.action = #selector(dismissBoundaryAlertPressed)
        boundaryDismissButton.setAccessibilityRole(.button)

        content.addSubview(boundaryTextBackground)
        content.addSubview(boundaryDismissButton)
        boundaryPanel.contentView = content
    }

    func start() {
        guard !hasStarted, !stopped else { return }
        hasStarted = true
        controlPanel.orderFrontRegardless()
        stepPanel.orderFrontRegardless()
        previewPanel.orderFrontRegardless()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        cleanup()
    }

    private func cleanup() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        dismissBoundaryAlert()
        [controlPanel, stepPanel, previewPanel, warningPanel, boundaryPanel].forEach { panel in
            panel.orderOut(nil)
            panel.close()
        }
        imageView.image = nil
        stepProgressIndicator.stopAnimation(nil)
        stepProgressIndicator.isHidden = true
        viewportIndicatorView.frame = .zero
        warningLabel.stringValue = ""
        warningLabel.isHidden = true
        warningLabel.toolTip = nil
        scrollView.documentView = nil
        controlPanel.contentView = nil
        stepPanel.contentView = nil
        previewPanel.contentView = nil
        warningPanel.contentView = nil
        boundaryPanel.contentView = nil
    }

    private func installBoundsObserver() {
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrollBoundsChanged() }
        }
    }

    func updatePreview(
        _ image: NSImage,
        following edge: ScrollCapturePreviewEdge,
        viewport: ScrollCapturePreviewViewport
    ) {
        guard !stopped else { return }
        let previousOutputHeight = previewOutputHeight
        followEdge = edge
        currentPreviewViewport = viewport
        imageView.image = image
        let imageWidth = max(image.size.width, 1)
        let imageHeight = max(image.size.height, 1)
        let availableSize = effectivePreviewContentSize
        let requestedScale = min(
            1,
            availableSize.width / imageWidth,
            availableSize.height / imageHeight
        )
        resizePreviewPanel(contentSize: NSSize(
            width: max(1, imageWidth * requestedScale),
            height: max(1, imageHeight * requestedScale)
        ))
        let visibleSize = scrollView.contentSize
        let displayScale = min(
            1,
            visibleSize.width / imageWidth,
            visibleSize.height / imageHeight
        )
        let displayWidth = max(1, imageWidth * displayScale)
        let displayHeight = max(1, imageHeight * displayScale)
        let documentSize = NSSize(
            width: max(1, visibleSize.width),
            height: max(1, visibleSize.height)
        )
        previewDocumentView.frame = NSRect(origin: .zero, size: documentSize)
        let imageOrigin = NSPoint(
            x: max(0, (documentSize.width - displayWidth) / 2),
            y: max(0, (documentSize.height - displayHeight) / 2)
        )
        imageView.frame = NSRect(
            origin: imageOrigin,
            size: NSSize(width: displayWidth, height: displayHeight)
        )
        let outputHeight = max(1, viewport.outputHeight)
        let viewportFraction = min(
            1,
            max(0, CGFloat(viewport.viewportHeight) / CGFloat(outputHeight))
        )
        let indicatorHeight = min(
            displayHeight,
            max(4, min(displayHeight * viewportFraction, max(4, visibleSize.height)))
        )
        let maximumTopPixel = max(
            0,
            CGFloat(outputHeight) * (displayHeight - indicatorHeight) / displayHeight
        )
        let indicatorTopPixel: CGFloat
        if indicatorPositionIsWheelDriven {
            var retainedTopPixel = viewportTopPixel ?? 0
            if previousOutputHeight > 0, outputHeight > previousOutputHeight {
                let growth = CGFloat(outputHeight - previousOutputHeight)
                if edge == .bottom, lastWheelDirection == .down {
                    retainedTopPixel = maximumTopPixel
                } else if edge == .top, lastWheelDirection == .up {
                    retainedTopPixel = 0
                } else if edge == .top {
                    retainedTopPixel += growth
                }
            }
            viewportTopPixel = retainedTopPixel
            indicatorTopPixel = min(max(0, retainedTopPixel), maximumTopPixel)
        } else {
            let anchorsAtBottom = stepControlState == .preparing
                ? initialVerticalAnchor == .bottom
                : edge == .bottom
            indicatorTopPixel = anchorsAtBottom ? maximumTopPixel : 0
            viewportTopPixel = indicatorTopPixel
        }
        let indicatorY = imageOrigin.y
            + indicatorTopPixel * displayHeight / CGFloat(outputHeight)
        viewportIndicatorView.frame = NSRect(
            x: imageOrigin.x,
            y: indicatorY,
            width: displayWidth,
            height: indicatorHeight
        )
        previewOutputHeight = outputHeight
        isFollowingTail = true
        isProgrammaticScroll = true
        reviewOffset = 0
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isProgrammaticScroll = false
        keepViewportIndicatorVisible()
        NSLog(
            "xxsnap scroll-capture preview applied edge=%@ documentHeight=%.2f indicator=%@ visible=%@",
            String(describing: edge),
            displayHeight,
            NSStringFromRect(viewportIndicatorView.frame),
            NSStringFromRect(scrollView.documentVisibleRect)
        )
    }

    func moveViewportIndicator(_ activity: ScrollCaptureScrollActivity) {
        guard !stopped,
              activity.direction != .unknown,
              activity.distance > 0,
              let viewport = currentPreviewViewport,
              imageView.frame.height > 0,
              viewportIndicatorView.frame.height > 0 else { return }
        let resolvedInitialAnchor = initialVerticalAnchor == nil
        if resolvedInitialAnchor {
            initialVerticalAnchor = activity.viewportDirection == .up ? .bottom : .top
            anchorPreviewPanelForInitialDirection()
        }
        let capturePixelsPerPoint = CGFloat(viewport.viewportHeight) / captureViewportPointHeight
        let outputHeight = CGFloat(max(1, viewport.outputHeight))
        let previewPointsPerPixel = imageView.frame.height / outputHeight
        let movement = activity.distance * capturePixelsPerPoint
        let signedMovement = activity.viewportDirection == .down ? movement : -movement
        let minimumY = imageView.frame.minY
        let maximumY = max(minimumY, imageView.frame.maxY - viewportIndicatorView.frame.height)
        var frame = viewportIndicatorView.frame
        let maximumTopPixel = (maximumY - minimumY) / max(previewPointsPerPixel, 0.0001)
        if resolvedInitialAnchor {
            viewportTopPixel = initialVerticalAnchor == .bottom ? maximumTopPixel : 0
        } else if viewportTopPixel == nil {
            viewportTopPixel = (frame.minY - minimumY) / max(previewPointsPerPixel, 0.0001)
        }
        let visibleTopPixel = min(
            max(0, (viewportTopPixel ?? 0) + signedMovement),
            maximumTopPixel
        )
        viewportTopPixel = visibleTopPixel
        lastWheelDirection = activity.direction
        frame.origin.y = minimumY + visibleTopPixel * previewPointsPerPixel
        viewportIndicatorView.frame = frame
        indicatorPositionIsWheelDriven = true
        keepViewportIndicatorVisible()
    }

    private func keepViewportIndicatorVisible() {
        let visible = scrollView.documentVisibleRect
        let indicator = viewportIndicatorView.frame
        let targetOffset: CGFloat?
        if previewDocumentView.frame.height > visible.height,
           stepControlState != .preparing,
           indicator.height < visible.height - 0.5 {
            let trackingFraction: CGFloat = followEdge == .bottom ? 0.65 : 0.35
            let trackingY = visible.minY + visible.height * trackingFraction
            if followEdge == .bottom, indicator.midY > trackingY {
                targetOffset = indicator.midY - visible.height * trackingFraction
            } else if followEdge == .top, indicator.midY < trackingY {
                targetOffset = indicator.midY - visible.height * trackingFraction
            } else {
                targetOffset = nil
            }
        } else if indicator.minY < visible.minY {
            targetOffset = indicator.minY
        } else if indicator.maxY > visible.maxY {
            targetOffset = indicator.maxY - visible.height
        } else {
            targetOffset = nil
        }
        guard let targetOffset else { return }
        let maximumOffset = max(0, previewDocumentView.frame.height - visible.height)
        isProgrammaticScroll = true
        reviewOffset = min(max(0, targetOffset), maximumOffset)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: reviewOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isProgrammaticScroll = false
    }

    func updatePreview(_ image: NSImage, following edge: ScrollCapturePreviewEdge) {
        let imageHeight = max(1, Int(image.size.height.rounded()))
        updatePreview(
            image,
            following: edge,
            viewport: ScrollCapturePreviewViewport(
                viewportHeight: imageHeight,
                outputHeight: imageHeight
            )
        )
    }

    func setWarning(_ text: String) {
        guard !stopped else { return }
        boundaryWarningVisible = false
        dismissBoundaryAlert()
        resizeWarningPanel(for: text)
        updateWarningPanelFrame()
        warningLabel.stringValue = text
        warningLabel.toolTip = text
        warningLabel.isHidden = false
        if hasStarted {
            warningPanel.alphaValue = 0
            warningPanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                warningPanel.animator().alphaValue = 1
            }
        }
    }

    func clearWarning() {
        boundaryWarningVisible = false
        dismissBoundaryAlert()
        warningLabel.stringValue = ""
        warningLabel.toolTip = nil
        warningLabel.isHidden = true
        warningPanel.alphaValue = 1
        warningPanel.orderOut(nil)
    }

    @objc private func dismissWarningPressed() {
        clearWarning()
    }

    private func showBoundaryAlert(isTopBoundary: Bool) {
        dismissBoundaryAlert()
        warningPanel.orderOut(nil)
        warningLabel.stringValue = ""
        warningLabel.toolTip = nil
        warningLabel.isHidden = true

        boundaryTitleLabel.stringValue = language == .zhHans
            ? (isTopBoundary ? "已经到顶" : "已经到底")
            : (isTopBoundary ? "Already at the top" : "Already at the bottom")
        boundaryIconView.image = NSImage(
            systemSymbolName: "exclamationmark.circle",
            accessibilityDescription: boundaryTitleLabel.stringValue
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .medium))
        boundaryIconView.image?.isTemplate = true

        let frame = Self.warningPanelFrame(
            selection: placementSelectionFrame,
            size: boundaryPanel.frame.size,
            visibleFrame: placementVisibleFrame,
            blockedFrames: []
        )
        boundaryPanel.setFrame(frame, display: false)
        if hasStarted {
            boundaryPanel.orderFrontRegardless()
        }
        let dismissTask = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.dismissBoundaryAlert()
            }
        }
        boundaryDismissTask = dismissTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: dismissTask)
    }

    @objc private func dismissBoundaryAlertPressed() {
        dismissBoundaryAlert()
    }

    private func dismissBoundaryAlert() {
        boundaryDismissTask?.cancel()
        boundaryDismissTask = nil
        boundaryPanel.orderOut(nil)
        boundaryTitleLabel.stringValue = ""
        boundaryIconView.image = nil
    }

    private func resizeWarningPanel(for text: String) {
        let font = warningLabel.font ?? .systemFont(ofSize: 13, weight: .semibold)
        let measuredWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let maximumWidth = max(120, min(520, placementVisibleFrame.width - 16))
        let size = NSSize(
            width: min(maximumWidth, max(252, measuredWidth + 96)),
            height: 44
        )
        warningPanel.setFrame(Self.warningPanelFrame(
            selection: placementSelectionFrame,
            size: size,
            visibleFrame: placementVisibleFrame,
            blockedFrames: []
        ), display: false)
        layoutWarningContent()
        warningLabel.maximumNumberOfLines = 1
        warningLabel.lineBreakMode = .byTruncatingTail
        warningLabel.cell?.wraps = false
    }

    private func layoutWarningContent() {
        guard let content = warningPanel.contentView else { return }
        content.frame = NSRect(origin: .zero, size: warningPanel.frame.size)
        warningTextBackground.frame = content.bounds
        warningAccentView.frame = NSRect(x: 0, y: 0, width: 5, height: content.bounds.height)
        warningIconView.frame = NSRect(x: 20, y: 11, width: 22, height: 22)
        warningCloseButton.frame = NSRect(
            x: content.bounds.maxX - 34,
            y: 10,
            width: 24,
            height: 24
        )
        warningLabel.frame = NSRect(
            x: 54,
            y: 8,
            width: max(24, content.bounds.width - 94),
            height: 22
        )
    }

    func updatePlacement(selectionFrame: NSRect, visibleFrame: NSRect) {
        placementSelectionFrame = selectionFrame
        placementVisibleFrame = visibleFrame
        stepPanel.setFrame(Self.stepToolbarFrame(
            anchoredTo: stepAnchorButtonFrame,
            toolbarFrame: controlFrame,
            selectionFrame: selectionFrame,
            size: stepPanel.frame.size,
            visibleFrame: visibleFrame
        ), display: false)
        previewGrowthFrame = Self.previewFrameAvoidingControls(
            selection: selectionFrame,
            previewSize: maximumPreviewContentSize,
            visibleFrame: visibleFrame,
            blockedFrames: [controlFrame, stepPanel.frame]
        )
        if imageView.image == nil {
            previewPanel.setFrame(previewGrowthFrame, display: false)
        } else {
            resizePreviewPanel(contentSize: imageView.frame.size)
        }
        updateWarningPanelFrame()
    }

    private func resizePreviewPanel(contentSize: NSSize) {
        let availableSize = effectivePreviewContentSize
        let size = NSSize(
            width: min(availableSize.width, max(1, contentSize.width)),
            height: min(availableSize.height, max(1, contentSize.height))
        )
        let current = previewPanel.frame
        let keepsRightSide = previewGrowthFrame.minX >= placementSelectionFrame.maxX
        let keepsLeftSide = previewGrowthFrame.maxX <= placementSelectionFrame.minX
        var origin = NSPoint(
            x: keepsRightSide
                ? previewGrowthFrame.minX
                : (keepsLeftSide ? previewGrowthFrame.maxX - size.width : current.midX - size.width / 2),
            y: previewGrowthFrame.minY
        )
        origin.x = min(
            max(origin.x, placementVisibleFrame.minX),
            placementVisibleFrame.maxX - size.width
        )
        origin.y = min(
            max(origin.y, placementVisibleFrame.minY),
            placementVisibleFrame.maxY - size.height
        )
        previewPanel.setFrame(NSRect(origin: origin, size: size), display: false)
        guard let content = previewPanel.contentView else { return }
        content.frame = NSRect(origin: .zero, size: size)
        scrollView.frame = NSRect(origin: .zero, size: size)
        updateWarningPanelFrame()
    }

    private func updateWarningPanelFrame() {
        warningPanel.setFrame(Self.warningPanelFrame(
            selection: placementSelectionFrame,
            size: warningPanel.frame.size,
            visibleFrame: placementVisibleFrame,
            blockedFrames: [controlFrame, stepPanel.frame, previewPanel.frame]
        ), display: false)
    }

    private var effectivePreviewContentSize: NSSize {
        NSSize(
            width: max(1, min(maximumPreviewContentSize.width, previewGrowthFrame.width)),
            height: max(1, min(maximumPreviewContentSize.height, previewGrowthFrame.height))
        )
    }

    private func anchorPreviewPanelForInitialDirection() {
        var frame = previewPanel.frame
        frame.origin.y = previewGrowthFrame.minY
        frame.origin.y = min(
            max(frame.origin.y, placementVisibleFrame.minY),
            placementVisibleFrame.maxY - frame.height
        )
        previewPanel.setFrame(frame, display: false)
    }

    func resetTerminalActionsForRetry() {
        guard !stopped else { return }
        terminalActionTriggered = false
        stopButton.isEnabled = true
        cancelButton.isEnabled = true
        controlPanel.ignoresMouseEvents = false
        stepPanel.ignoresMouseEvents = false
    }

    func setStepControlState(_ state: ScrollCaptureStepControlState) {
        guard !stopped else { return }
        if case .boundary = state {
        } else if boundaryWarningVisible {
            clearWarning()
        }
        stepControlState = state
        setStepLoading(state == .executing)
        switch state {
        case .preparing:
            directionControl.isEnabled = false
            startButton.isEnabled = false
            startButton.contentTintColor = .disabledControlTextColor
        case .ready(let directionLocked):
            directionControl.isEnabled = !directionLocked
            startButton.isEnabled = true
            startButton.contentTintColor = .systemBlue
        case .executing:
            directionControl.isEnabled = false
            startButton.isEnabled = false
            startButton.contentTintColor = .black
        case .boundary:
            directionControl.isEnabled = false
            startButton.isEnabled = false
            startButton.contentTintColor = .disabledControlTextColor
            let isTopBoundary = directionControl.indexOfSelectedItem == 1
            showBoundaryAlert(isTopBoundary: isTopBoundary)
            boundaryWarningVisible = true
        }
        stopButton.isEnabled = !terminalActionTriggered
        stopButton.contentTintColor = .black
    }

    private func setStepLoading(_ loading: Bool) {
        if loading {
            startButton.image = nil
            stepProgressIndicator.isHidden = false
            stepProgressIndicator.startAnimation(nil)
        } else {
            stepProgressIndicator.stopAnimation(nil)
            stepProgressIndicator.isHidden = true
            startButton.image = startButtonIdleImage
        }
    }

    @objc private func startPressed() {
        guard startButton.isEnabled else { return }
        let direction: ScrollCaptureDirection = directionControl.indexOfSelectedItem == 1 ? .up : .down
        onStep(direction)
    }

    @objc private func directionChanged() {
        initialVerticalAnchor = directionControl.indexOfSelectedItem == 1 ? .bottom : .top
        guard imageView.image != nil else { return }
        var frame = viewportIndicatorView.frame
        frame.origin.y = initialVerticalAnchor == .bottom
            ? max(imageView.frame.minY, imageView.frame.maxY - frame.height)
            : imageView.frame.minY
        viewportIndicatorView.frame = frame
        keepViewportIndicatorVisible()
    }

    @objc private func finishPressed() {
        NSLog("xxsnap scroll-capture finish button pressed")
        triggerTerminalAction(onFinish)
    }
    @objc private func cancelPressed() { triggerTerminalAction(onCancel) }

    private func triggerTerminalAction(_ action: () -> Void) {
        guard !terminalActionTriggered else {
            NSLog("xxsnap scroll-capture terminal action ignored: already triggered")
            return
        }
        terminalActionTriggered = true
        startButton.isEnabled = false
        stopButton.isEnabled = false
        cancelButton.isEnabled = false
        controlPanel.ignoresMouseEvents = true
        stepPanel.ignoresMouseEvents = true
        action()
        NSLog("xxsnap scroll-capture terminal action delivered")
    }

    @objc private func scrollBoundsChanged() {
        guard !isProgrammaticScroll else { return }
        let maximumOffset = max(0, previewDocumentView.frame.height - scrollView.contentSize.height)
        let observedOffset = max(0, scrollView.documentVisibleRect.minY)
        reviewOffset = min(observedOffset, maximumOffset)
        if observedOffset != reviewOffset {
            isProgrammaticScroll = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: reviewOffset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isProgrammaticScroll = false
        }
        isFollowingTail = followEdge == .bottom
            ? reviewOffset >= maximumOffset - 2
            : reviewOffset <= 2
    }

    static func stepToolbarFrame(
        anchoredTo buttonFrame: NSRect,
        toolbarFrame: NSRect,
        selectionFrame: NSRect,
        size: NSSize,
        visibleFrame: NSRect,
        spacing: CGFloat = 6
    ) -> NSRect {
        let visible = visibleFrame.standardized
        let toolbar = toolbarFrame.standardized
        let selection = selectionFrame.standardized
        let clampedX = min(
            max(buttonFrame.midX - size.width / 2, visible.minX),
            visible.maxX - size.width
        )
        let below = NSRect(
            x: clampedX,
            y: toolbar.minY - spacing - size.height,
            width: size.width,
            height: size.height
        )
        let above = NSRect(
            x: clampedX,
            y: toolbar.maxY + spacing,
            width: size.width,
            height: size.height
        )
        let verticalCandidates = toolbar.minY >= selection.maxY
            ? [above, below]
            : [below, above]
        let fittingVerticalCandidates = verticalCandidates.filter {
            visible.contains($0) && !$0.intersects(toolbar)
        }
        if let outsideSelection = fittingVerticalCandidates.first(where: { !$0.intersects(selection) }) {
            return outsideSelection
        }
        if let insideFallback = fittingVerticalCandidates.first {
            return insideFallback
        }
        // Keep the step toolbar vertically attached to its anchor. It must not
        // jump to either side when the available space changes.
        return NSRect(
            x: clampedX,
            y: min(max(above.minY, visible.minY), visible.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    static func warningPanelFrame(
        selection: NSRect,
        size: NSSize,
        visibleFrame: NSRect,
        blockedFrames _: [NSRect],
        spacing _: CGFloat = 8
    ) -> NSRect {
        let visible = visibleFrame.standardized
        let selection = selection.standardized
        let size = NSSize(
            width: min(size.width, visible.width),
            height: min(size.height, visible.height)
        )
        let visibleSelection = selection.intersection(visible)
        let anchor = visibleSelection.isNull || visibleSelection.isEmpty ? visible : visibleSelection
        let centeredX = min(
            max(anchor.midX - size.width / 2, visible.minX),
            visible.maxX - size.width
        )
        let centeredY = min(
            max(anchor.midY - size.height / 2, visible.minY),
            visible.maxY - size.height
        )
        return NSRect(x: centeredX, y: centeredY, width: size.width, height: size.height)
    }

    static func previewFrame(
        selection: NSRect,
        previewSize: NSSize,
        visibleFrame: NSRect,
        spacing: CGFloat = 12
    ) -> NSRect {
        let selection = selection.standardized
        let visible = visibleFrame.standardized
        let size = NSSize(
            width: min(previewSize.width, visible.width),
            height: min(previewSize.height, visible.height)
        )
        if let outside = outsidePreviewFrame(
            selection: selection,
            previewSize: size,
            visibleFrame: visible,
            blockedFrames: [],
            spacing: spacing
        ) {
            return outside
        }
        return insidePreviewFrame(
            selection: selection,
            previewSize: size,
            visibleFrame: visible,
            spacing: spacing
        )
    }

    private static func insidePreviewFrame(
        selection: NSRect,
        previewSize: NSSize,
        visibleFrame: NSRect,
        spacing: CGFloat
    ) -> NSRect {
        let size = NSSize(
            width: min(previewSize.width, visibleFrame.width),
            height: min(previewSize.height, visibleFrame.height)
        )
        let insideX = min(
            max(selection.maxX - size.width - spacing, visibleFrame.minX),
            visibleFrame.maxX - size.width
        )
        let insideY = min(
            max(selection.minY, visibleFrame.minY),
            visibleFrame.maxY - size.height
        )
        return NSRect(x: insideX, y: insideY, width: size.width, height: size.height)
    }

    private static func outsidePreviewFrame(
        selection: NSRect,
        previewSize: NSSize,
        visibleFrame: NSRect,
        blockedFrames: [NSRect],
        spacing: CGFloat
    ) -> NSRect? {
        struct Region {
            let frame: NSRect
            let order: Int
        }
        struct Candidate {
            let frame: NSRect
            let isBottomAligned: Bool
            let isFullSize: Bool
            let fittedArea: CGFloat
            let regionArea: CGFloat
            let order: Int
        }

        let regions = [
            Region(
                frame: NSRect(
                    x: selection.maxX + spacing,
                    y: visibleFrame.minY,
                    width: max(0, visibleFrame.maxX - selection.maxX - spacing),
                    height: visibleFrame.height
                ),
                order: 0
            ),
            Region(
                frame: NSRect(
                    x: visibleFrame.minX,
                    y: visibleFrame.minY,
                    width: max(0, selection.minX - visibleFrame.minX - spacing),
                    height: visibleFrame.height
                ),
                order: 1
            ),
        ].filter { !$0.frame.isEmpty }

        let usableRegions = regions.flatMap { region -> [Region] in
            availablePreviewRegions(avoiding: blockedFrames, inside: region.frame, spacing: spacing)
                .map { Region(frame: $0, order: region.order) }
        }
        let minimumWidth = min(1, previewSize.width)
        let minimumHeight = min(120, previewSize.height)
        let candidates = usableRegions.compactMap { region -> Candidate? in
            let size = NSSize(
                width: min(previewSize.width, region.frame.width),
                height: min(previewSize.height, region.frame.height)
            )
            guard size.width >= minimumWidth, size.height >= minimumHeight else { return nil }

            let origin: NSPoint
            switch region.order {
            case 0:
                origin = NSPoint(
                    x: region.frame.minX,
                    y: min(max(selection.minY, region.frame.minY), region.frame.maxY - size.height)
                )
            default:
                origin = NSPoint(
                    x: region.frame.maxX - size.width,
                    y: min(max(selection.minY, region.frame.minY), region.frame.maxY - size.height)
                )
            }
            let frame = NSRect(origin: origin, size: size)
            let bottomAnchorY = min(
                max(selection.minY, visibleFrame.minY),
                visibleFrame.maxY - size.height
            )
            return Candidate(
                frame: frame,
                isBottomAligned: abs(frame.minY - bottomAnchorY) <= 0.5,
                isFullSize: size == previewSize,
                fittedArea: size.width * size.height,
                regionArea: region.frame.width * region.frame.height,
                order: region.order
            )
        }

        return candidates.sorted { left, right in
            if left.isBottomAligned != right.isBottomAligned { return left.isBottomAligned }
            if left.isFullSize != right.isFullSize { return left.isFullSize }
            if left.fittedArea != right.fittedArea { return left.fittedArea > right.fittedArea }
            if left.regionArea != right.regionArea { return left.regionArea > right.regionArea }
            return left.order < right.order
        }.first?.frame
    }

    private static func previewFrameAvoidingControls(
        selection: NSRect,
        previewSize: NSSize,
        visibleFrame: NSRect,
        blockedFrames: [NSRect],
        spacing: CGFloat = 12
    ) -> NSRect {
        let visible = visibleFrame.standardized
        let selectionArea = selection.standardized.intersection(visible)
        let controls = blockedFrames
            .map { $0.standardized.intersection(visible) }
            .filter { !$0.isNull && !$0.isEmpty }
        let desired = NSSize(
            width: min(previewSize.width, visible.width),
            height: min(previewSize.height, visible.height)
        )
        if let outside = outsidePreviewFrame(
            selection: selection.standardized,
            previewSize: desired,
            visibleFrame: visible,
            blockedFrames: controls,
            spacing: spacing
        ) {
            return outside
        }
        let base = insidePreviewFrame(
            selection: selection.standardized,
            previewSize: desired,
            visibleFrame: visible,
            spacing: spacing
        )
        guard controls.contains(where: {
            base.intersects($0.insetBy(dx: -spacing, dy: -spacing))
        }) else { return base }

        let regions = availablePreviewRegions(avoiding: controls, inside: visible, spacing: spacing)
        let bottomRegions = regions.filter { abs($0.minY - visible.minY) <= 0.5 }
        if let bottomRegion = bottomRegions.max(by: { left, right in
            min(desired.width, left.width) * min(desired.height, left.height)
                < min(desired.width, right.width) * min(desired.height, right.height)
        }) {
            return NSRect(
                origin: bottomRegion.origin,
                size: NSSize(
                    width: min(desired.width, bottomRegion.width),
                    height: min(desired.height, bottomRegion.height)
                )
            )
        }
        let preferredRegions = availablePreviewRegions(
            avoiding: controls,
            inside: selectionArea,
            spacing: spacing
        ) + regions

        if let region = preferredRegions.first(where: { $0.width >= desired.width && $0.height >= desired.height }) {
            return NSRect(origin: region.origin, size: desired)
        }
        guard let largest = regions.max(by: { $0.width * $0.height < $1.width * $1.height }),
              largest.width > 0,
              largest.height > 0 else {
            return NSRect(origin: visible.origin, size: .zero)
        }
        return NSRect(
            origin: largest.origin,
            size: NSSize(width: min(desired.width, largest.width), height: min(desired.height, largest.height))
        )
    }

    private static func availablePreviewRegions(
        avoiding blockedFrames: [NSRect],
        inside bounds: NSRect,
        spacing: CGFloat
    ) -> [NSRect] {
        blockedFrames.reduce([bounds]) { regions, blockedFrame in
            regions.flatMap { region in
                let spacingFrame = blockedFrame.insetBy(dx: -spacing, dy: -spacing)
                guard region.intersects(spacingFrame) else { return [region] }
                return availablePreviewRegions(around: blockedFrame, inside: region, spacing: spacing)
            }
        }
    }

    private static func availablePreviewRegions(
        around control: NSRect,
        inside bounds: NSRect,
        spacing: CGFloat
    ) -> [NSRect] {
        guard !bounds.isNull, !bounds.isEmpty else { return [] }
        return [
            NSRect(x: bounds.minX, y: max(bounds.minY, control.maxY + spacing), width: bounds.width, height: max(0, bounds.maxY - max(bounds.minY, control.maxY + spacing))),
            NSRect(x: bounds.minX, y: bounds.minY, width: max(0, min(bounds.maxX, control.minX - spacing) - bounds.minX), height: bounds.height),
            NSRect(x: min(bounds.maxX, control.maxX + spacing), y: bounds.minY, width: max(0, bounds.maxX - min(bounds.maxX, control.maxX + spacing)), height: bounds.height),
            NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, min(bounds.maxY, control.minY - spacing) - bounds.minY)),
        ].filter { $0.width > 0 && $0.height > 0 && !$0.intersects(control) }
    }

#if DEBUG
    var test_controlStyleMask: NSWindow.StyleMask { controlPanel.styleMask }
    var test_controlFrame: NSRect { controlPanel.frame }
    var test_controlCanBecomeKey: Bool { controlPanel.canBecomeKey }
    var test_controlIgnoresMouseEvents: Bool { controlPanel.ignoresMouseEvents }
    var test_terminalHitPanelsCanBecomeKey: Bool { controlPanel.canBecomeKey }
    var test_controlIsOpaque: Bool { controlPanel.isOpaque }
    var test_controlBackgroundColor: NSColor { controlPanel.backgroundColor }
    var test_finishButtonFrame: NSRect { stepPanel.convertToScreen(stopButton.frame) }
    var test_cancelButtonFrame: NSRect { controlPanel.convertToScreen(cancelButton.frame) }
    var test_finishButtonToolTip: String? { stopButton.toolTip }
    var test_cancelButtonToolTip: String? { cancelButton.toolTip }
    var test_finishAccessibilityLabel: String? { stopButton.accessibilityLabel() }
    var test_cancelAccessibilityLabel: String? { cancelButton.accessibilityLabel() }
    var test_accessibilityRoles: [NSAccessibility.Role] {
        [startButton, stopButton, cancelButton].compactMap { $0.accessibilityRole() }
    }
    var test_controlHitTargetCount: Int { [startButton, stopButton, cancelButton].count }
    var test_controlHitTargetsAreTransparent: Bool {
        [startButton, stopButton, cancelButton].allSatisfy { !$0.isBordered }
    }
    var test_interactiveWindowFrames: [NSRect] { [controlPanel.frame, stepPanel.frame] }
    func test_toolbarPointIsInteractive(_ point: NSPoint) -> Bool {
        guard !controlPanel.ignoresMouseEvents, controlPanel.frame.contains(point) else { return false }
        let local = NSPoint(x: point.x - controlFrame.minX, y: point.y - controlFrame.minY)
        return cancelButton.frame.contains(local)
    }
    var test_hasVisiblePanels: Bool {
        controlPanel.isVisible
            || stepPanel.isVisible
            || previewPanel.isVisible
            || warningPanel.isVisible
            || boundaryPanel.isVisible
    }
    var test_panelsAreClosedAndDetached: Bool {
        controlPanel.contentView == nil
            && stepPanel.contentView == nil
            && previewPanel.contentView == nil
            && warningPanel.contentView == nil
            && boundaryPanel.contentView == nil
    }
    var test_stepToolbarFrame: NSRect { stepPanel.frame }
    var test_directionControlIsEnabled: Bool { directionControl.isEnabled }
    var test_startButtonIsEnabled: Bool { startButton.isEnabled }
    var test_startButtonTint: NSColor? { startButton.contentTintColor }
    var test_startButtonImageSize: NSSize? { startButton.image?.size }
    var test_stepProgressIsVisible: Bool { !stepProgressIndicator.isHidden }
    var test_stopButtonImageSize: NSSize? { stopButton.image?.size }
    var test_previewFrame: NSRect { previewPanel.frame }
    var test_previewIgnoresMouseEvents: Bool { previewPanel.ignoresMouseEvents }
    var test_isFollowingTail: Bool { isFollowingTail }
    var test_visibleRect: NSRect { scrollView.documentVisibleRect }
    var test_contentWidth: CGFloat { scrollView.contentSize.width }
    var test_documentHeight: CGFloat { imageView.frame.height }
    var test_previewImageFrame: NSRect { imageView.frame }
    var test_viewportIndicatorFrame: NSRect { viewportIndicatorView.frame }
    var test_reviewOffset: CGFloat { reviewOffset }
    var test_hasBoundsObserver: Bool { boundsObserver != nil }
    var test_warningText: String? { warningLabel.isHidden ? nil : warningLabel.stringValue }
    var test_warningFrame: NSRect { warningPanel.frame }
    var test_warningBackgroundColor: NSColor { warningPanel.backgroundColor }
    var test_warningCornerRadius: CGFloat { warningTextBackground.layer?.cornerRadius ?? 0 }
    var test_warningTextBackgroundColor: NSColor? {
        warningTextBackground.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
    }
    var test_warningIconTintColor: NSColor? { warningIconView.contentTintColor }
    var test_warningAccentColor: NSColor? {
        warningAccentView.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
    }
    var test_warningUsesVisualEffectBackdrop: Bool {
        warningPanel.contentView?.subviews.contains(where: { $0 is NSVisualEffectView }) == true
    }
    var test_warningTextAlignment: NSTextAlignment { warningLabel.alignment }
    var test_warningFontSize: CGFloat { warningLabel.font?.pointSize ?? 0 }
    var test_warningIconFrame: NSRect { warningIconView.frame }
    var test_warningTextFrame: NSRect { warningLabel.frame }
    var test_warningIgnoresMouseEvents: Bool { warningPanel.ignoresMouseEvents }
    var test_warningWraps: Bool { warningLabel.lineBreakMode == .byWordWrapping && warningLabel.maximumNumberOfLines == 2 }
    var test_warningToolTip: String? { warningLabel.toolTip }
    var test_previewImage: NSImage? { imageView.image }
    var test_boundaryAlertMessage: String? {
        boundaryTitleLabel.stringValue.isEmpty ? nil : boundaryTitleLabel.stringValue
    }
    var test_boundaryAlertInformation: String? { nil }
    var test_boundaryAlertButtonTitle: String? { nil }
    var test_boundaryAlertFrame: NSRect? {
        test_boundaryAlertMessage == nil ? nil : boundaryPanel.frame
    }
    var test_boundaryAlertActionButtonCount: Int { 0 }
    var test_boundaryAlertCloseAccessibilityLabel: String? { boundaryDismissButton.accessibilityLabel() }
    var test_boundaryAlertCornerRadius: CGFloat { boundaryTextBackground.layer?.cornerRadius ?? 0 }
    var test_boundaryAlertPanelBackgroundColor: NSColor { boundaryPanel.backgroundColor }
    var test_boundaryAlertTextBackgroundColor: NSColor? {
        boundaryTextBackground.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
    }
    var test_boundaryAlertTextColor: NSColor? { boundaryTitleLabel.textColor }
    var test_boundaryAlertIconTintColor: NSColor? { boundaryIconView.contentTintColor }
    var test_boundaryAlertIconFrame: NSRect { boundaryIconView.frame }
    var test_boundaryAlertTextFrame: NSRect { boundaryTitleLabel.frame }
    var test_boundaryAlertAccentColor: NSColor? {
        boundaryAccentView.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
    }
    var test_boundaryAlertIconDescription: String? { boundaryIconView.image?.accessibilityDescription }
    var test_boundaryAutoDismissScheduled: Bool { boundaryDismissTask != nil }
    func test_triggerWarningClose() { warningCloseButton.performClick(nil) }
    func test_triggerBoundaryAlertClose() { boundaryDismissButton.performClick(nil) }
    func test_triggerStart() { startButton.performClick(nil) }
    func test_selectDirection(_ direction: ScrollCaptureDirection) {
        directionControl.selectItem(at: direction == .up ? 1 : 0)
        directionChanged()
    }
    func test_triggerFinish() { stopButton.performClick(nil) }
    func test_triggerCancel() { cancelButton.performClick(nil) }
    func test_userScroll(to offset: CGFloat) {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        scrollBoundsChanged()
    }
    func test_postBoundsChangeNotification() {
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }
#endif
}
