import AppKit

@MainActor
final class HelpContentView: NSView {
    var onImageSelected: ((NSImage, String, String) -> Void)?
    var imageUnavailableText: String

    private static let thumbnailMaximumDimension: CGFloat = 1_440

    private let imageLoader: (String) -> NSImage?
    private let scrollView = NSScrollView()
    private let documentView = HelpFlippedView()
    private let contentStack = NSStackView()
    private var firstImageButton: HelpImageButton?
    private(set) var appliedAppearanceName: NSAppearance.Name = .aqua

    private(set) var test_visibleTexts: [String] = []
    private(set) var test_visibleImageCount = 0

    var test_backgroundState: (
        helpContentLayerColor: NSColor?,
        scrollViewDrawsBackground: Bool,
        scrollViewBackgroundColor: NSColor,
        clipViewDrawsBackground: Bool,
        clipViewBackgroundColor: NSColor,
        documentViewLayerColor: NSColor?
    ) {
        (
            layer?.backgroundColor.flatMap(NSColor.init(cgColor:)),
            scrollView.drawsBackground,
            scrollView.backgroundColor,
            scrollView.contentView.drawsBackground,
            scrollView.contentView.backgroundColor,
            documentView.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
        )
    }

    init(
        imageUnavailableText: String,
        imageLoader: @escaping (String) -> NSImage?
    ) {
        self.imageUnavailableText = imageUnavailableText
        self.imageLoader = imageLoader
        super.init(frame: .zero)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var scrollOffset: CGFloat {
        get { max(0, scrollView.contentView.bounds.origin.y) }
        set {
            layoutSubtreeIfNeeded()
            scrollView.layoutSubtreeIfNeeded()
            documentView.layoutSubtreeIfNeeded()
            let clipView = scrollView.contentView
            let proposedBounds = NSRect(
                x: clipView.bounds.origin.x,
                y: max(0, newValue),
                width: clipView.bounds.width,
                height: clipView.bounds.height
            )
            let constrainedBounds = clipView.constrainBoundsRect(proposedBounds)
            clipView.scroll(to: constrainedBounds.origin)
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    func render(_ chapter: HelpChapter) {
        resetContent()

        addText(
            chapter.title,
            font: .systemFont(ofSize: 28, weight: .bold),
            color: .labelColor,
            headingLevel: 1
        )
        addText(
            chapter.introduction,
            font: .systemFont(ofSize: 15),
            color: .secondaryLabelColor
        )

        if !chapter.tableOfContents.isEmpty {
            addSectionHeading("目录")
            addArrangedFullWidth(makeBulletList(chapter.tableOfContents))
        }

        if !chapter.shortcuts.isEmpty {
            addSectionHeading("快捷键")
            addArrangedFullWidth(makeShortcutList(chapter.shortcuts))
        }

        for block in chapter.blocks {
            render(block)
        }

        finishRendering()
    }

    func renderError(_ message: String) {
        resetContent()
        addText(
            message,
            font: .systemFont(ofSize: 20, weight: .semibold),
            color: .labelColor
        )
        finishRendering()
    }

    func clear() {
        resetContent()
        needsLayout = true
    }

    func test_clickFirstImage() {
        firstImageButton?.performClick(nil)
    }

    func applySystemAppearance(
        increaseContrast: Bool = NSWorkspace.shared
            .accessibilityDisplayShouldIncreaseContrast
    ) {
        let appearanceName: NSAppearance.Name = increaseContrast
            ? .accessibilityHighContrastAqua
            : .aqua
        appliedAppearanceName = appearanceName
        appearance = NSAppearance(named: appearanceName)
    }

    private func configureLayout() {
        translatesAutoresizingMaskIntoConstraints = false
        applySystemAppearance()
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = .white

        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = NSColor.white.cgColor
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18

        documentView.addSubview(contentStack)
        scrollView.documentView = documentView
        addSubview(scrollView)

        let availableWidthConstraint = contentStack.widthAnchor.constraint(
            equalTo: documentView.widthAnchor,
            constant: -88
        )
        availableWidthConstraint.priority = .defaultHigh
        let readableWidthConstraint = contentStack.widthAnchor.constraint(
            equalToConstant: 760
        )
        readableWidthConstraint.priority = NSLayoutConstraint.Priority(749)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            documentView.widthAnchor.constraint(
                equalTo: scrollView.contentView.widthAnchor
            ),
            contentStack.topAnchor.constraint(
                equalTo: documentView.topAnchor,
                constant: 32
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: documentView.bottomAnchor,
                constant: -64
            ),
            contentStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: documentView.leadingAnchor,
                constant: 44
            ),
            contentStack.trailingAnchor.constraint(
                lessThanOrEqualTo: documentView.trailingAnchor,
                constant: -44
            ),
            contentStack.centerXAnchor.constraint(
                equalTo: documentView.centerXAnchor
            ),
            contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: 760),
            availableWidthConstraint,
            readableWidthConstraint
        ])

    }

    private func resetContent() {
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        firstImageButton = nil
        test_visibleTexts = []
        test_visibleImageCount = 0
        scrollOffset = 0
    }

    private func finishRendering() {
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func render(_ block: HelpContentBlock) {
        switch block {
        case .heading(let level, let text):
            let size: CGFloat = level <= 2 ? 21 : 17
            addText(
                text,
                font: .systemFont(ofSize: size, weight: .semibold),
                color: .labelColor,
                headingLevel: max(2, level)
            )
        case .paragraph(let text):
            addBodyText(text)
        case .steps(let steps):
            addArrangedFullWidth(makeSteps(steps))
        case .bullets(let items):
            addArrangedFullWidth(makeBulletList(items))
        case .shortcuts(let shortcuts):
            addArrangedFullWidth(makeShortcutList(shortcuts))
        case .image(let name, let caption, let accessibilityLabel):
            addArrangedFullWidth(
                makeImage(
                    named: name,
                    caption: caption,
                    accessibilityLabel: accessibilityLabel
                )
            )
        case .note(let title, let text):
            addArrangedFullWidth(
                makeBand(title: title, text: text, color: .systemBlue)
            )
        case .warning(let title, let text):
            addArrangedFullWidth(
                makeBand(title: title, text: text, color: .systemOrange)
            )
        case .faq(let items):
            addArrangedFullWidth(makeFAQ(items))
        }
    }

    private func addSectionHeading(_ text: String) {
        addText(
            text,
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: .labelColor,
            headingLevel: 2
        )
    }

    private func addBodyText(_ text: String) {
        addText(
            text,
            font: .systemFont(ofSize: 14),
            color: .labelColor
        )
    }

    private func addText(
        _ text: String,
        font: NSFont,
        color: NSColor,
        headingLevel: Int? = nil
    ) {
        let label = makeWrappingLabel(
            text,
            font: font,
            color: color,
            headingLevel: headingLevel
        )
        addArrangedFullWidth(label)
        record(text)
    }

    private func addArrangedFullWidth(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func makeWrappingLabel(
        _ text: String,
        font: NSFont = .systemFont(ofSize: 14),
        color: NSColor = .labelColor,
        headingLevel: Int? = nil
    ) -> NSTextField {
        let label: NSTextField
        if let headingLevel {
            label = HelpHeadingTextField(
                string: text,
                headingLevel: headingLevel
            )
        } else {
            label = NSTextField(wrappingLabelWithString: text)
        }
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func makeSteps(_ steps: [HelpStep]) -> NSView {
        let stack = verticalGroup()
        for (index, step) in steps.enumerated() {
            let marker = NSTextField(labelWithString: "\(index + 1).")
            marker.font = .systemFont(ofSize: 14, weight: .semibold)
            marker.alignment = .right
            marker.widthAnchor.constraint(equalToConstant: 26).isActive = true

            let text = makeWrappingLabel(step.text)
            let rowViews: [NSView]
            if let keys = step.keys, !keys.isEmpty {
                rowViews = [marker, text, makeKeycapGroup(keys)]
            } else {
                rowViews = [marker, text]
            }
            let row = horizontalRow(rowViews)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            record(step.text)
            step.keys?.forEach(record)
        }
        return stack
    }

    private func makeBulletList(_ items: [String]) -> NSView {
        let stack = verticalGroup()
        for item in items {
            let marker = NSTextField(labelWithString: "•")
            marker.font = .systemFont(ofSize: 14, weight: .semibold)
            marker.alignment = .center
            marker.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let row = horizontalRow([marker, makeWrappingLabel(item)])
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            record(item)
        }
        return stack
    }

    private func makeShortcutList(_ shortcuts: [HelpShortcut]) -> NSView {
        let stack = verticalGroup()
        for shortcut in shortcuts {
            let action = makeWrappingLabel(shortcut.action)
            let row = horizontalRow([action, makeKeycapGroup(shortcut.keys)])
            row.distribution = .fill
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            record(shortcut.action)
            shortcut.keys.forEach(record)
        }
        return stack
    }

    private func makeKeycapGroup(_ keys: [String]) -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5

        for key in keys {
            let box = NSBox()
            box.boxType = .custom
            box.borderColor = .separatorColor
            box.borderWidth = 1
            box.fillColor = .controlBackgroundColor
            box.cornerRadius = 5
            box.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(labelWithString: key)
            label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(label)

            NSLayoutConstraint.activate([
                box.heightAnchor.constraint(equalToConstant: 26),
                box.widthAnchor.constraint(greaterThanOrEqualToConstant: 26),
                label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 7),
                label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -7),
                label.centerYAnchor.constraint(equalTo: box.centerYAnchor)
            ])
            stack.addArrangedSubview(box)
        }
        return stack
    }

    private func makeImage(
        named name: String,
        caption: String,
        accessibilityLabel: String
    ) -> NSView {
        let stack = verticalGroup(spacing: 8)

        if
            let image = imageLoader(name),
            let thumbnail = makeThumbnail(from: image)
        {
            let button = HelpImageButton(
                thumbnail: thumbnail,
                imageName: name,
                caption: caption,
                accessibilityLabel: accessibilityLabel
            )
            button.onSelect = {
                [weak self] imageName, caption, accessibilityLabel in
                guard
                    let self,
                    let fullImage = self.imageLoader(imageName),
                    fullImage.size.width > 0,
                    fullImage.size.height > 0
                else {
                    return
                }
                self.onImageSelected?(
                    fullImage,
                    caption,
                    accessibilityLabel
                )
            }
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            button.heightAnchor.constraint(
                equalTo: button.widthAnchor,
                multiplier: thumbnail.size.height / thumbnail.size.width
            ).isActive = true
            firstImageButton = firstImageButton ?? button
            test_visibleImageCount += 1
        } else {
            let fallback = makeWrappingLabel(
                imageUnavailableText,
                color: .secondaryLabelColor
            )
            fallback.alignment = .center
            stack.addArrangedSubview(fallback)
            fallback.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            record(imageUnavailableText)
        }

        let captionLabel = makeWrappingLabel(
            caption,
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        captionLabel.alignment = .center
        stack.addArrangedSubview(captionLabel)
        captionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        record(caption)
        return stack
    }

    private func makeThumbnail(from source: NSImage) -> NSImage? {
        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return nil
        }

        let scale = min(
            1,
            Self.thumbnailMaximumDimension / max(
                sourceSize.width,
                sourceSize.height
            )
        )
        let thumbnailSize = NSSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(thumbnailSize.width),
            pixelsHigh: Int(thumbnailSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        representation.size = thumbnailSize

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: thumbnailSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )

        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.addRepresentation(representation)
        return thumbnail
    }

    private func makeBand(
        title: String,
        text: String,
        color: NSColor
    ) -> NSView {
        let band = NSView()
        band.translatesAutoresizingMaskIntoConstraints = false
        band.wantsLayer = true
        band.layer?.backgroundColor = color.withAlphaComponent(0.10).cgColor

        let stripe = NSView()
        stripe.translatesAutoresizingMaskIntoConstraints = false
        stripe.wantsLayer = true
        stripe.layer?.backgroundColor = color.cgColor

        let titleLabel = makeWrappingLabel(
            title,
            font: .systemFont(ofSize: 14, weight: .semibold)
        )
        let bodyLabel = makeWrappingLabel(text)
        let labels = verticalGroup(spacing: 4)
        labels.addArrangedSubview(titleLabel)
        labels.addArrangedSubview(bodyLabel)
        titleLabel.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
        bodyLabel.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true

        band.addSubview(stripe)
        band.addSubview(labels)
        NSLayoutConstraint.activate([
            stripe.leadingAnchor.constraint(equalTo: band.leadingAnchor),
            stripe.topAnchor.constraint(equalTo: band.topAnchor),
            stripe.bottomAnchor.constraint(equalTo: band.bottomAnchor),
            stripe.widthAnchor.constraint(equalToConstant: 3),
            labels.leadingAnchor.constraint(equalTo: stripe.trailingAnchor, constant: 13),
            labels.trailingAnchor.constraint(equalTo: band.trailingAnchor, constant: -16),
            labels.topAnchor.constraint(equalTo: band.topAnchor, constant: 13),
            labels.bottomAnchor.constraint(equalTo: band.bottomAnchor, constant: -13)
        ])
        record(title)
        record(text)
        return band
    }

    private func makeFAQ(_ items: [HelpFAQItem]) -> NSView {
        let stack = verticalGroup(spacing: 14)
        for item in items {
            let question = makeWrappingLabel(
                item.question,
                font: .systemFont(ofSize: 14, weight: .semibold)
            )
            let answer = makeWrappingLabel(item.answer)
            let pair = verticalGroup(spacing: 4)
            pair.addArrangedSubview(question)
            pair.addArrangedSubview(answer)
            question.widthAnchor.constraint(equalTo: pair.widthAnchor).isActive = true
            answer.widthAnchor.constraint(equalTo: pair.widthAnchor).isActive = true
            stack.addArrangedSubview(pair)
            pair.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            record(item.question)
            record(item.answer)
        }
        return stack
    }

    private func verticalGroup(spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    private func horizontalRow(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func record(_ text: String) {
        test_visibleTexts.append(text)
    }

}

private final class HelpFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class HelpHeadingTextField: NSTextField {
    private let headingLevel: Int

    init(string: String, headingLevel: Int) {
        self.headingLevel = headingLevel
        super.init(frame: .zero)
        stringValue = string
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        lineBreakMode = .byWordWrapping
        usesSingleLineMode = false
        cell?.wraps = true
        setAccessibilityRole(
            NSAccessibility.Role(rawValue: "AXHeading")
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityAttributeNames() -> [NSAccessibility.Attribute] {
        let headingLevelAttribute = NSAccessibility.Attribute(
            rawValue: "AXHeadingLevel"
        )
        var attributes = super.accessibilityAttributeNames()
        if !attributes.contains(headingLevelAttribute) {
            attributes.append(headingLevelAttribute)
        }
        return attributes
    }

    override func accessibilityAttributeValue(
        _ attribute: NSAccessibility.Attribute
    ) -> Any? {
        if attribute.rawValue == "AXHeadingLevel" {
            return headingLevel
        }
        return super.accessibilityAttributeValue(attribute)
    }

}

@MainActor
private final class HelpImageButton: NSButton {
    let imageName: String
    let caption: String
    let imageAccessibilityLabel: String
    var onSelect: ((String, String, String) -> Void)?

    init(
        thumbnail: NSImage,
        imageName: String,
        caption: String,
        accessibilityLabel: String
    ) {
        self.imageName = imageName
        self.caption = caption
        imageAccessibilityLabel = accessibilityLabel
        super.init(frame: .zero)
        image = thumbnail
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyUpOrDown
        isBordered = false
        focusRingType = .default
        target = self
        action = #selector(selectImage)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityLabel(accessibilityLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func selectImage() {
        onSelect?(imageName, caption, imageAccessibilityLabel)
    }
}
