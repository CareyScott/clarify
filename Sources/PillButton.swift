import AppKit

final class PillButton: PressableButton {
    private static let height: CGFloat = 26
    private static let horizontalPadding: CGFloat = 12
    private static let confirmationDuration: TimeInterval = 1.2
    private static let layoutDuration: TimeInterval = 0.2

    private let isPrimary: Bool
    private var label = ""
    private var shortcut: String?
    private var pendingRestore: DispatchWorkItem?

    init(isPrimary: Bool, target: AnyObject, action: Selector) {
        self.isPrimary = isPrimary
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = restingBackground.cgColor
        setContentHuggingPriority(.required, for: .horizontal)
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.35 }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: attributedTitle.size().width + Self.horizontalPadding * 2, height: Self.height)
    }

    func setLabel(_ label: String, shortcut: String? = nil) {
        self.label = label
        self.shortcut = shortcut
        pendingRestore?.cancel()
        pendingRestore = nil
        render(label, shortcut: shortcut, withCheckmark: false)
    }

    func showConfirmation(_ text: String) {
        pendingRestore?.cancel()
        transition { self.render(text, shortcut: nil, withCheckmark: true) }
        let restore = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.transition { self.render(self.label, shortcut: self.shortcut, withCheckmark: false) }
        }
        pendingRestore = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmationDuration, execute: restore)
    }

    override func hoverChanged(_ hovering: Bool) {
        ButtonMotion.fadeBackground(of: self, to: hovering && isEnabled ? hoverBackground : restingBackground)
    }

    private var restingBackground: NSColor {
        isPrimary ? .white : NSColor.white.withAlphaComponent(0.14)
    }

    private var hoverBackground: NSColor {
        isPrimary ? NSColor(white: 0.86, alpha: 1) : NSColor.white.withAlphaComponent(0.24)
    }

    private func render(_ text: String, shortcut: String?, withCheckmark: Bool) {
        let colour: NSColor = isPrimary ? .black : .white
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12.5, weight: .medium), .foregroundColor: colour]
        let title = NSMutableAttributedString()
        if withCheckmark, let checkmark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .bold).applying(.init(paletteColors: [colour]))) {
            let attachment = NSTextAttachment()
            attachment.image = checkmark
            attachment.bounds = NSRect(x: 0, y: -1, width: checkmark.size.width, height: checkmark.size.height)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: " ", attributes: labelAttributes))
        }
        title.append(NSAttributedString(string: text, attributes: labelAttributes))
        if let shortcut {
            title.append(NSAttributedString(string: "  \(shortcut)", attributes: [
                .font: NSFont.systemFont(ofSize: 12.5),
                .foregroundColor: colour.withAlphaComponent(0.45),
            ]))
        }
        attributedTitle = title
        invalidateIntrinsicContentSize()
    }

    private func transition(_ change: () -> Void) {
        ButtonMotion.crossfade(self)
        change()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.layoutDuration
            context.allowsImplicitAnimation = true
            self.superview?.layoutSubtreeIfNeeded()
        }
    }
}
