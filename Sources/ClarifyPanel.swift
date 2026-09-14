import AppKit

final class KeyPanel: NSPanel {
    var onCommandReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onPasteImages: (([NSImage]) -> Void)?

    private static let returnKeyCodes: Set<UInt16> = [36, 76]
    private static let editActions: [String: Selector] = [
        "x": #selector(NSText.cut(_:)),
        "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:)),
        "z": Selector(("undo:")),
    ]

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        if Self.returnKeyCodes.contains(event.keyCode) {
            onCommandReturn?()
            return true
        }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), let action = Self.editActions[key] else {
            return super.performKeyEquivalent(with: event)
        }
        if key == "v" {
            let images = ContextImage.images(on: .general)
            if !images.isEmpty {
                onPasteImages?(images)
                return true
            }
        }
        return NSApp.sendAction(action, to: nil, from: self)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

final class ClarifyPanel: NSObject, NSTextFieldDelegate {
    var onSubmit: ((String) -> Void)?
    var onReplaceSelection: (() -> Void)?
    var onCopy: (() -> Void)?
    var onAddScreenshot: (() -> Void)?
    var onPasteImages: (([NSImage]) -> Void)?
    var onRemoveContextImage: ((Int) -> Void)?
    var onCancel: (() -> Void)?

    private static let width: CGFloat = 480
    private static let padding: CGFloat = 14
    private static let contentWidth = width - padding * 2
    private static let maximumDiffHeight: CGFloat = 320
    private static let screenEdgeMargin: CGFloat = 12
    private static let gapAfterRemoved: CGFloat = 4
    private static let thumbnailSide: CGFloat = 44
    private static let maximumPreviewSide: CGFloat = 360

    private let window: KeyPanel
    private let stack = NSStackView()
    private let notesLabel = NSTextField(wrappingLabelWithString: "")
    private let diffView = NSTextView()
    private let diffScroll = NSScrollView()
    private let contextImagesRow = NSStackView()
    private let inputField = NSTextField()
    private let screenshotButton = NSButton()
    private let copyButton = NSButton()
    private let replaceButton = NSButton()
    private let closeButton = NSButton()
    private lazy var diffHeight = diffScroll.heightAnchor.constraint(equalToConstant: 18)
    private var pulseTimer: Timer?

    override init() {
        window = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configureWindow()
        buildLayout()
    }

    func showNearPointer() {
        let pointer = NSEvent.mouseLocation
        let visible = (NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let left = min(max(pointer.x - Self.width / 2, visible.minX + Self.screenEdgeMargin), visible.maxX - Self.width - Self.screenEdgeMargin)
        window.setFrameTopLeftPoint(NSPoint(x: left, y: min(pointer.y - 20, visible.maxY)))
        fitWindowToContent()
        reveal()
    }

    func reveal() {
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(inputField)
        window.invalidateShadow()
    }

    func hide() {
        window.orderOut(nil)
    }

    func showWorking(diff: [DiffSegment]) {
        render(diff)
        notesLabel.stringValue = "Working…"
        notesLabel.isHidden = false
        setDraftActions(enabled: false)
        startPulse()
        fitWindowToContent()
    }

    func showRevision(notes: String, diff: [DiffSegment]) {
        stopPulse()
        notesLabel.stringValue = notes
        notesLabel.isHidden = notes.isEmpty
        render(diff)
        setDraftActions(enabled: true)
        fitWindowToContent()
    }

    func showNote(_ note: String) {
        stopPulse()
        notesLabel.stringValue = note
        notesLabel.isHidden = false
        fitWindowToContent()
    }

    func showContextImages(_ images: [NSImage]) {
        contextImagesRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, image) in images.enumerated() {
            let tile = ContextImageTile(
                image: image,
                side: Self.thumbnailSide,
                onPreview: { [weak self] tile in self?.preview(image, from: tile) },
                onRemove: { [weak self] in self?.onRemoveContextImage?(index) }
            )
            contextImagesRow.addArrangedSubview(tile)
        }
        contextImagesRow.isHidden = images.isEmpty
        fitWindowToContent()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            let instruction = inputField.stringValue
            inputField.stringValue = ""
            onSubmit?(instruction)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }

    private func configureWindow() {
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.appearance = NSAppearance(named: .darkAqua)
        window.onCommandReturn = { [weak self] in self?.onReplaceSelection?() }
        window.onEscape = { [weak self] in self?.onCancel?() }
        window.onPasteImages = { [weak self] images in self?.onPasteImages?(images) }
    }

    private func buildLayout() {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
        card.layer?.cornerRadius = 16
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        card.layer?.masksToBounds = true
        window.contentView = card

        notesLabel.font = .systemFont(ofSize: 12)
        notesLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        notesLabel.isSelectable = false
        notesLabel.preferredMaxLayoutWidth = Self.contentWidth

        diffView.isEditable = false
        diffView.isSelectable = true
        diffView.drawsBackground = false
        diffView.textContainerInset = .zero
        diffView.textContainer?.lineFragmentPadding = 0
        diffView.textContainer?.widthTracksTextView = true
        diffView.isVerticallyResizable = true
        diffView.autoresizingMask = [.width]
        diffView.frame = NSRect(x: 0, y: 0, width: Self.contentWidth, height: 18)
        diffScroll.documentView = diffView
        diffScroll.drawsBackground = false
        diffScroll.hasVerticalScroller = true
        diffScroll.autohidesScrollers = true
        diffScroll.scrollerStyle = .overlay

        contextImagesRow.orientation = .horizontal
        contextImagesRow.alignment = .centerY
        contextImagesRow.spacing = 6
        contextImagesRow.isHidden = true

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor

        inputField.isBordered = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.font = .systemFont(ofSize: 13)
        inputField.textColor = .white
        inputField.cell?.isScrollable = true
        inputField.cell?.wraps = false
        inputField.placeholderAttributedString = NSAttributedString(
            string: "Add context, paste an image, ask a question",
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.35), .font: NSFont.systemFont(ofSize: 13)]
        )
        inputField.delegate = self
        inputField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        style(screenshotButton, symbol: "camera", tooltip: "Add a screenshot as context", action: #selector(screenshotPressed))
        style(copyButton, symbol: "doc.on.doc", tooltip: "Copy", action: #selector(copyPressed))
        style(replaceButton, symbol: "checkmark", tooltip: "Replace selection (⌘↩)", action: #selector(replacePressed))
        style(closeButton, symbol: "xmark", tooltip: "Close (esc)", action: #selector(closePressed))

        let inputRow = NSStackView(views: [screenshotButton, inputField, copyButton, replaceButton, closeButton])
        inputRow.orientation = .horizontal
        inputRow.alignment = .centerY
        inputRow.spacing = 10

        let fullWidthViews = [notesLabel, diffScroll, contextImagesRow, divider, inputRow]
        fullWidthViews.forEach(stack.addArrangedSubview)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: Self.padding, left: Self.padding, bottom: 10, right: Self.padding)
        stack.setCustomSpacing(12, after: diffScroll)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate(fullWidthViews.map { $0.widthAnchor.constraint(equalToConstant: Self.contentWidth) } + [
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            contextImagesRow.heightAnchor.constraint(equalToConstant: Self.thumbnailSide),
            divider.heightAnchor.constraint(equalToConstant: 1),
            inputRow.heightAnchor.constraint(equalToConstant: 26),
            diffHeight,
        ])
    }

    private func style(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.image?.isTemplate = true
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        button.contentTintColor = .white
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    private func preview(_ image: NSImage, from tile: NSView) {
        let scale = min(1, Self.maximumPreviewSide / max(image.size.width, image.size.height, 1))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let content = NSViewController()
        content.view = imageView
        let popover = NSPopover()
        popover.contentViewController = content
        popover.contentSize = size
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.show(relativeTo: tile.bounds, of: tile, preferredEdge: .maxY)
    }

    private func setDraftActions(enabled: Bool) {
        for button in [copyButton, replaceButton] {
            button.isEnabled = enabled
            button.alphaValue = enabled ? 1 : 0.35
        }
    }

    private func render(_ diff: [DiffSegment]) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .paragraphStyle: paragraph]
        let text = NSMutableAttributedString()
        for segment in diff {
            switch segment {
            case let .unchanged(part):
                text.append(NSAttributedString(string: part, attributes: base.merging([
                    .foregroundColor: NSColor.white.withAlphaComponent(0.85),
                ]) { $1 }))
            case let .removed(part):
                let removed = NSMutableAttributedString(string: part, attributes: base.merging([
                    .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.white.withAlphaComponent(0.35),
                ]) { $1 })
                removed.addAttribute(.kern, value: Self.gapAfterRemoved, range: NSRange(location: removed.length - 1, length: 1))
                text.append(removed)
            case let .added(part):
                text.append(NSAttributedString(string: part, attributes: base.merging([
                    .foregroundColor: NSColor.white,
                    .backgroundColor: NSColor.white.withAlphaComponent(0.18),
                ]) { $1 }))
            }
        }
        diffView.textStorage?.setAttributedString(text)
    }

    private func fitWindowToContent() {
        if let layoutManager = diffView.layoutManager, let container = diffView.textContainer {
            layoutManager.ensureLayout(for: container)
            let textHeight = ceil(layoutManager.usedRect(for: container).height)
            diffHeight.constant = min(max(textHeight, 18), Self.maximumDiffHeight)
        }
        stack.layoutSubtreeIfNeeded()
        let height = ceil(stack.fittingSize.height)
        var frame = window.frame
        frame.origin.y = frame.maxY - height
        frame.size = NSSize(width: Self.width, height: height)
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.y = max(frame.origin.y, visible.minY + Self.screenEdgeMargin)
        }
        window.setFrame(frame, display: true)
        window.invalidateShadow()
    }

    private func startPulse() {
        stopPulse()
        var phase: CGFloat = 0
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            phase += 0.12
            self?.notesLabel.alphaValue = 0.4 + 0.6 * (0.5 + 0.5 * sin(phase))
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        notesLabel.alphaValue = 1
    }

    @objc private func screenshotPressed() { onAddScreenshot?() }
    @objc private func copyPressed() { onCopy?() }
    @objc private func replacePressed() { onReplaceSelection?() }
    @objc private func closePressed() { onCancel?() }}
