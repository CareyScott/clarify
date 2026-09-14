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
            let images = ContextImage.pastedImages(on: .general)
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

final class DropCard: NSView {
    var onDropImages: (([NSImage]) -> Void)?

    private static let restingBorder = NSColor.white.withAlphaComponent(0.1)
    private static let dropTargetBorder = NSColor.white.withAlphaComponent(0.7)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = Self.restingBorder.cgColor
        layer?.masksToBounds = true
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !ContextImage.droppedImages(on: sender.draggingPasteboard).isEmpty else { return [] }
        layer?.borderColor = Self.dropTargetBorder.cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = Self.restingBorder.cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderColor = Self.restingBorder.cgColor
        let images = ContextImage.droppedImages(on: sender.draggingPasteboard)
        guard !images.isEmpty else { return false }
        onDropImages?(images)
        return true
    }
}

final class ClarifyPanel: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
    var onClarifyDraft: ((String) -> Void)?
    var onSendInstruction: ((String) -> Void)?
    var onPrimaryAction: (() -> Void)?
    var onCopy: (() -> Void)?
    var onAddScreenshot: (() -> Void)?
    var onAddImages: (([NSImage]) -> Void)?
    var onRemoveContextImage: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private enum Phase {
        case composing
        case reviewing
    }

    private static let width: CGFloat = 480
    private static let padding: CGFloat = 14
    private static let contentWidth = width - padding * 2
    private static let iconButtonSide: CGFloat = 22
    private static let headerSpacing: CGFloat = 8
    private static let notesWidth = contentWidth - (iconButtonSide + headerSpacing) * 2
    private static let minimumDiffHeight: CGFloat = 18
    private static let minimumDraftHeight: CGFloat = 72
    private static let maximumTextHeight: CGFloat = 320
    private static let screenEdgeMargin: CGFloat = 12
    private static let gapAfterRemoved: CGFloat = 4
    private static let thumbnailSide: CGFloat = 44
    private static let maximumPreviewSide: CGFloat = 360
    private static let bodyFont = NSFont.systemFont(ofSize: 14)
    private static let shortcutHint = "⌘↩"

    private let window: KeyPanel
    private let stack = NSStackView()
    private let notesLabel = NSTextField(wrappingLabelWithString: "")
    private let settingsButton = NSButton()
    private let closeButton = NSButton()
    private let diffView = NSTextView()
    private let diffScroll = NSScrollView()
    private let draftEditor = NSTextView()
    private let draftScroll = NSScrollView()
    private let contextImagesRow = NSStackView()
    private let composeScreenshotButton = NSButton()
    private let chatScreenshotButton = NSButton()
    private let inputField = NSTextField()
    private let sendButton = NSButton()
    private let chatDivider = NSView()
    private let chatRow = NSStackView()
    private lazy var copyButton = PillButton(isPrimary: false, target: self, action: #selector(copyPressed))
    private lazy var primaryButton = PillButton(isPrimary: true, target: self, action: #selector(primaryPressed))
    private lazy var diffHeight = diffScroll.heightAnchor.constraint(equalToConstant: Self.minimumDiffHeight)
    private lazy var draftHeight = draftScroll.heightAnchor.constraint(equalToConstant: Self.minimumDraftHeight)
    private var pulseTimer: Timer?
    private var phase = Phase.reviewing
    private var primaryActionLabel = "Replace"
    private var showsCopyAction = true
    private var hasUnsentImages = false

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
        showPhaseControls()
        updateSendButton()
    }

    func showNearPointer(activatingApp: Bool) {
        let pointer = NSEvent.mouseLocation
        let visible = (NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let left = min(max(pointer.x - Self.width / 2, visible.minX + Self.screenEdgeMargin), visible.maxX - Self.width - Self.screenEdgeMargin)
        window.setFrameTopLeftPoint(NSPoint(x: left, y: min(pointer.y - 20, visible.maxY)))
        fitWindowToContent()
        reveal(activatingApp: activatingApp)
    }

    func reveal(activatingApp: Bool) {
        if activatingApp {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(phase == .composing ? draftEditor : inputField)
        window.invalidateShadow()
    }

    func hide() {
        window.orderOut(nil)
    }

    func showComposer() {
        phase = .composing
        stopPulse()
        notesLabel.stringValue = "Type, paste or dictate a draft, then press \(Self.shortcutHint) to clarify it."
        showPhaseControls()
        fitWindowToContent()
    }

    func setPrimaryAction(label: String, showsCopy: Bool) {
        primaryActionLabel = label
        showsCopyAction = showsCopy
        showPhaseControls()
    }

    func setHasUnsentImages(_ unsent: Bool) {
        hasUnsentImages = unsent
        updateSendButton()
    }

    func showWorking(diff: [DiffSegment]) {
        if phase == .composing {
            phase = .reviewing
            showPhaseControls()
            window.makeFirstResponder(inputField)
        }
        render(diff)
        notesLabel.stringValue = "Working…"
        setResultActions(enabled: false)
        startPulse()
        fitWindowToContent()
    }

    func showRevision(notes: String, diff: [DiffSegment]) {
        stopPulse()
        notesLabel.stringValue = notes
        render(diff)
        setResultActions(enabled: true)
        fitWindowToContent()
    }

    func showNote(_ note: String) {
        stopPulse()
        notesLabel.stringValue = note
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
            sendInstruction()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        updateSendButton()
    }

    func textDidChange(_ notification: Notification) {
        fitWindowToContent()
    }

    private var hasSomethingToSend: Bool {
        hasUnsentImages || !inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendInstruction() {
        guard hasSomethingToSend else { return }
        let instruction = inputField.stringValue
        inputField.stringValue = ""
        updateSendButton()
        window.makeFirstResponder(inputField)
        onSendInstruction?(instruction)
    }

    private func updateSendButton() {
        sendButton.isEnabled = hasSomethingToSend
        sendButton.alphaValue = sendButton.isEnabled ? 1 : 0.3
    }

    private func showPhaseControls() {
        let composing = phase == .composing
        draftScroll.isHidden = !composing
        diffScroll.isHidden = composing
        composeScreenshotButton.isHidden = !composing
        copyButton.isHidden = composing || !showsCopyAction
        chatDivider.isHidden = composing
        chatRow.isHidden = composing
        primaryButton.setLabel(composing ? "Clarify" : primaryActionLabel, shortcut: Self.shortcutHint)
        if composing { primaryButton.isEnabled = true }
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
        window.onCommandReturn = { [weak self] in self?.primaryPressed() }
        window.onEscape = { [weak self] in self?.onCancel?() }
        window.onPasteImages = { [weak self] images in self?.onAddImages?(images) }
    }

    private func buildLayout() {
        let card = DropCard()
        card.onDropImages = { [weak self] images in self?.onAddImages?(images) }
        window.contentView = card

        notesLabel.font = .systemFont(ofSize: 12)
        notesLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        notesLabel.isSelectable = false
        notesLabel.preferredMaxLayoutWidth = Self.notesWidth
        notesLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        styleIconButton(settingsButton, symbol: "gearshape", tooltip: "Clarify Settings", action: #selector(settingsPressed))
        styleIconButton(closeButton, symbol: "xmark", tooltip: "Close without changes (esc)", action: #selector(closePressed))

        let headerRow = NSStackView(views: [notesLabel, settingsButton, closeButton])
        headerRow.orientation = .horizontal
        headerRow.alignment = .top
        headerRow.spacing = Self.headerSpacing

        configureTextView(diffView, in: diffScroll)
        diffView.isEditable = false

        configureTextView(draftEditor, in: draftScroll)
        draftEditor.isEditable = true
        draftEditor.isRichText = false
        draftEditor.allowsUndo = true
        draftEditor.isAutomaticQuoteSubstitutionEnabled = false
        draftEditor.isAutomaticDashSubstitutionEnabled = false
        draftEditor.font = Self.bodyFont
        draftEditor.textColor = .white
        draftEditor.insertionPointColor = .white
        draftEditor.typingAttributes = [.font: Self.bodyFont, .foregroundColor: NSColor.white]
        draftEditor.delegate = self

        contextImagesRow.orientation = .horizontal
        contextImagesRow.alignment = .centerY
        contextImagesRow.spacing = 6
        contextImagesRow.isHidden = true

        styleIconButton(composeScreenshotButton, symbol: "camera", tooltip: "Add a screenshot as context", action: #selector(screenshotPressed))
        copyButton.setLabel("Copy")
        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actionRow = NSStackView(views: [composeScreenshotButton, actionSpacer, copyButton, primaryButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8

        chatDivider.wantsLayer = true
        chatDivider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor

        styleIconButton(chatScreenshotButton, symbol: "camera", tooltip: "Add a screenshot as context", action: #selector(screenshotPressed))
        inputField.isBordered = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.font = .systemFont(ofSize: 13)
        inputField.textColor = .white
        inputField.cell?.isScrollable = true
        inputField.cell?.wraps = false
        inputField.placeholderAttributedString = NSAttributedString(
            string: "Ask Claude for a change, or drop in an image",
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.35), .font: NSFont.systemFont(ofSize: 13)]
        )
        inputField.delegate = self
        inputField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        styleSendButton()

        chatRow.setViews([chatScreenshotButton, inputField, sendButton], in: .leading)
        chatRow.orientation = .horizontal
        chatRow.alignment = .centerY
        chatRow.spacing = 10

        let fullWidthViews = [headerRow, diffScroll, draftScroll, contextImagesRow, actionRow, chatDivider, chatRow]
        fullWidthViews.forEach(stack.addArrangedSubview)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: Self.padding, bottom: 10, right: Self.padding)
        stack.setCustomSpacing(12, after: actionRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate(fullWidthViews.map { $0.widthAnchor.constraint(equalToConstant: Self.contentWidth) } + [
            notesLabel.widthAnchor.constraint(equalToConstant: Self.notesWidth),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            contextImagesRow.heightAnchor.constraint(equalToConstant: Self.thumbnailSide),
            actionRow.heightAnchor.constraint(equalToConstant: 26),
            chatDivider.heightAnchor.constraint(equalToConstant: 1),
            chatRow.heightAnchor.constraint(equalToConstant: 26),
            diffHeight,
            draftHeight,
        ])
    }

    private func configureTextView(_ textView: NSTextView, in scroll: NSScrollView) {
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.frame = NSRect(x: 0, y: 0, width: Self.contentWidth, height: Self.minimumDiffHeight)
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
    }

    private func styleIconButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.image?.isTemplate = true
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        button.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: Self.iconButtonSide).isActive = true
        button.heightAnchor.constraint(equalToConstant: Self.iconButtonSide).isActive = true
    }

    private func styleSendButton() {
        sendButton.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Send to Claude")
        sendButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
        sendButton.isBordered = false
        sendButton.imageScaling = .scaleNone
        sendButton.toolTip = "Send to Claude (return)"
        sendButton.target = self
        sendButton.action = #selector(sendPressed)
        sendButton.wantsLayer = true
        sendButton.layer?.backgroundColor = NSColor.white.cgColor
        sendButton.layer?.cornerRadius = Self.iconButtonSide / 2
        sendButton.widthAnchor.constraint(equalToConstant: Self.iconButtonSide).isActive = true
        sendButton.heightAnchor.constraint(equalToConstant: Self.iconButtonSide).isActive = true
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

    private func setResultActions(enabled: Bool) {
        copyButton.isEnabled = enabled
        primaryButton.isEnabled = enabled
    }

    private func render(_ diff: [DiffSegment]) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let base: [NSAttributedString.Key: Any] = [.font: Self.bodyFont, .paragraphStyle: paragraph]
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

    private func textHeight(of textView: NSTextView, minimum: CGFloat) -> CGFloat {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return minimum }
        layoutManager.ensureLayout(for: container)
        let usedHeight = ceil(layoutManager.usedRect(for: container).height)
        return min(max(usedHeight, minimum), Self.maximumTextHeight)
    }

    private func fitWindowToContent() {
        diffHeight.constant = textHeight(of: diffView, minimum: Self.minimumDiffHeight)
        draftHeight.constant = textHeight(of: draftEditor, minimum: Self.minimumDraftHeight)
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

    @objc private func primaryPressed() {
        switch phase {
        case .composing: onClarifyDraft?(draftEditor.string)
        case .reviewing: if primaryButton.isEnabled { onPrimaryAction?() }
        }
    }

    @objc private func screenshotPressed() { onAddScreenshot?() }
    @objc private func sendPressed() { sendInstruction() }
    @objc private func copyPressed() { onCopy?() }
    @objc private func closePressed() { onCancel?() }
    @objc private func settingsPressed() { onOpenSettings?() }
}
