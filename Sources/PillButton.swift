import AppKit

final class PillButton: NSButton {
    private static let height: CGFloat = 26
    private static let horizontalPadding: CGFloat = 12

    private let isPrimary: Bool

    init(isPrimary: Bool, target: AnyObject, action: Selector) {
        self.isPrimary = isPrimary
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = (isPrimary ? NSColor.white : NSColor.white.withAlphaComponent(0.14)).cgColor
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
        let colour: NSColor = isPrimary ? .black : .white
        let title = NSMutableAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
            .foregroundColor: colour,
        ])
        if let shortcut {
            title.append(NSAttributedString(string: "  \(shortcut)", attributes: [
                .font: NSFont.systemFont(ofSize: 12.5),
                .foregroundColor: colour.withAlphaComponent(0.45),
            ]))
        }
        attributedTitle = title
        invalidateIntrinsicContentSize()
    }
}
