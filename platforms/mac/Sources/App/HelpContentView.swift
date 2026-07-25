import AppKit

@MainActor
final class HelpContentView: NSView {
    var onImageSelected: ((NSImage, String) -> Void)?

    private let imageLoader: (String) -> NSImage?
    private let scrollView = NSScrollView()
    private let documentView = HelpFlippedView()
    private let contentStack = NSStackView()
    private var firstImageButton: HelpImageButton?
    private var trackedScrollOffset: CGFloat = 0
    private var isApplyingScrollOffset = false

    private(set) var test_visibleTexts: [String] = []
    private(set) var test_visibleImageCount = 0

    init(imageLoader: @escaping (String) -> NSImage?) {
        self.imageLoader = imageLoader
        super.init(frame: .zero)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var scrollOffset: CGFloat {
        get { trackedScrollOffset }
        set {
            trackedScrollOffset = max(0, newValue)
            isApplyingScrollOffset = true
            scrollView.contentView.scroll(
                to: NSPoint(x: 0, y: trackedScrollOffset)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingScrollOffset = false
        }
    }

    func render(_ chapter: HelpChapter) {
        resetContent()

        addText(
            chapter.title,
            font: .systemFont(ofSize: 28, weight: .bold),
            color: .labelColor
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

    func test_clickFirstImage() {
        firstImageButton?.performClick(nil)
    }

    private func configureLayout() {
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        documentView.translatesAutoresizingMaskIntoConstraints = false
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
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
                color: .labelColor
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
            color: .labelColor
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
        color: NSColor
    ) {
        let label = makeWrappingLabel(text, font: font, color: color)
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
        color: NSColor = .labelColor
    ) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
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

        if let image = imageLoader(name), image.size.width > 0, image.size.height > 0 {
            let button = HelpImageButton(image: image, caption: caption)
            button.onSelect = { [weak self] image, caption in
                self?.onImageSelected?(image, caption)
            }
            button.setAccessibilityLabel(accessibilityLabel)
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            button.heightAnchor.constraint(
                equalTo: button.widthAnchor,
                multiplier: image.size.height / image.size.width
            ).isActive = true
            firstImageButton = firstImageButton ?? button
            test_visibleImageCount += 1
        } else {
            let fallback = makeWrappingLabel(
                "图片暂时无法显示",
                color: .secondaryLabelColor
            )
            fallback.alignment = .center
            stack.addArrangedSubview(fallback)
            fallback.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            record("图片暂时无法显示")
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

    @objc
    private func clipViewBoundsDidChange() {
        guard !isApplyingScrollOffset else { return }
        trackedScrollOffset = max(0, scrollView.contentView.bounds.origin.y)
    }
}

private final class HelpFlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class HelpImageButton: NSButton {
    let previewImage: NSImage
    let caption: String
    var onSelect: ((NSImage, String) -> Void)?

    init(image: NSImage, caption: String) {
        previewImage = image
        self.caption = caption
        super.init(frame: .zero)
        self.image = image
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyUpOrDown
        isBordered = false
        focusRingType = .default
        target = self
        action = #selector(selectImage)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func selectImage() {
        onSelect?(previewImage, caption)
    }
}
