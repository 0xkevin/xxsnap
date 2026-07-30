import AppKit
import QuartzCore

@MainActor
final class ShortcutFeedbackPresentationController {
    static let holdDuration: TimeInterval = 3
    static let fadeDuration: TimeInterval = 1

    private static let screenInset: CGFloat = 28
    private static let panelIdentifier = NSUserInterfaceItemIdentifier(
        "xxsnap.shortcut-feedback"
    )

    private let settingsStore: any PreferencesSettingsStoring
    private let visibleFrameProvider: () -> NSRect
    private var fadeWorkItem: DispatchWorkItem?
    private var presentationGeneration: UInt = 0
    private(set) var panel: NSPanel?

    init(
        settingsStore: any PreferencesSettingsStoring,
        visibleFrameProvider: @escaping () -> NSRect = {
            let pointer = NSEvent.mouseLocation
            return NSScreen.screens.first(where: { $0.frame.contains(pointer) })?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1_280, height: 720)
        }
    ) {
        self.settingsStore = settingsStore
        self.visibleFrameProvider = visibleFrameProvider
    }

    func show(_ settings: HotKeySettings) {
        show(settings, isEnabled: settingsStore.load().showsShortcutFeedback)
    }

    func showSystemShortcut(_ settings: HotKeySettings) {
        show(settings, isEnabled: settingsStore.load().showsSystemShortcutFeedback)
    }

    private func show(_ settings: HotKeySettings, isEnabled: Bool) {
        guard isEnabled else {
            hide()
            return
        }

        presentationGeneration &+= 1
        let generation = presentationGeneration
        fadeWorkItem?.cancel()

        let shortcutText = HotKeyFormatter.displayString(settings)
        let bubbleSize = ShortcutFeedbackBubbleView.preferredSize(for: shortcutText)
        let visibleFrame = visibleFrameProvider()
        let frame = NSRect(
            x: visibleFrame.maxX - Self.screenInset - bubbleSize.width,
            y: visibleFrame.minY + Self.screenInset,
            width: bubbleSize.width,
            height: bubbleSize.height
        )

        let panel = panel ?? makePanel(frame: frame)
        let bubble: ShortcutFeedbackBubbleView
        if let existing = panel.contentView as? ShortcutFeedbackBubbleView {
            bubble = existing
        } else {
            bubble = ShortcutFeedbackBubbleView(
                frame: NSRect(origin: .zero, size: bubbleSize),
                shortcutText: shortcutText
            )
            panel.contentView = bubble
        }
        bubble.shortcutText = shortcutText
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        let fadeWorkItem = DispatchWorkItem { [weak self, weak panel] in
            guard let self,
                  let panel,
                  self.presentationGeneration == generation
            else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self, weak panel] in
                Task { @MainActor in
                    guard let self,
                          let panel,
                          self.presentationGeneration == generation
                    else { return }
                    panel.orderOut(nil)
                    self.panel = nil
                }
            }
        }
        self.fadeWorkItem = fadeWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.holdDuration,
            execute: fadeWorkItem
        )
    }

    func hide() {
        presentationGeneration &+= 1
        fadeWorkItem?.cancel()
        fadeWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = Self.panelIdentifier
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        return panel
    }
}

@MainActor
final class ShortcutFeedbackBubbleView: NSView {
    private static let triangleWidth: CGFloat = 14
    private static let bubbleHeight: CGFloat = 58
    private static let minimumBodyWidth: CGFloat = 88
    private static let horizontalTextInset: CGFloat = 22
    private static let font = NSFont.systemFont(ofSize: 26, weight: .semibold)

    var shortcutText: String {
        didSet {
            setAccessibilityLabel(shortcutText)
            needsDisplay = true
        }
    }

    var bubbleBodyRect: NSRect {
        NSRect(
            x: 0,
            y: 0,
            width: bounds.width - Self.triangleWidth,
            height: bounds.height
        )
    }

    var triangleTip: NSPoint {
        NSPoint(x: bounds.maxX, y: bounds.midY)
    }

    init(frame frameRect: NSRect, shortcutText: String) {
        self.shortcutText = shortcutText
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(shortcutText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    static func preferredSize(for shortcutText: String) -> NSSize {
        let textWidth = ceil(
            (shortcutText as NSString).size(withAttributes: textAttributes).width
        )
        let bodyWidth = max(
            minimumBodyWidth,
            textWidth + horizontalTextInset * 2
        )
        return NSSize(
            width: bodyWidth + triangleWidth,
            height: bubbleHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let body = bubbleBodyRect
        let fillColor = NSColor(calibratedWhite: 0.055, alpha: 0.94)
        fillColor.setFill()
        NSBezierPath(
            roundedRect: body,
            xRadius: 17,
            yRadius: 17
        ).fill()

        let triangleHalfHeight: CGFloat = 10
        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: body.maxX - 1, y: body.midY - triangleHalfHeight))
        triangle.line(to: triangleTip)
        triangle.line(to: NSPoint(x: body.maxX - 1, y: body.midY + triangleHalfHeight))
        triangle.close()
        triangle.fill()

        let textSize = (shortcutText as NSString).size(withAttributes: Self.textAttributes)
        let textOrigin = NSPoint(
            x: body.midX - textSize.width / 2,
            y: body.midY - textSize.height / 2
        )
        (shortcutText as NSString).draw(
            at: textOrigin,
            withAttributes: Self.textAttributes
        )
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.white,
            .kern: 0.8
        ]
    }
}
