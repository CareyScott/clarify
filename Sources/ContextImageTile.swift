import AppKit

final class ContextImageTile: NSView {
    private static let removeButtonSide: CGFloat = 16
    private static let removeButtonInset: CGFloat = 2

    private let onPreview: (ContextImageTile) -> Void
    private let onRemove: () -> Void

    init(image: NSImage, side: CGFloat, onPreview: @escaping (ContextImageTile) -> Void, onRemove: @escaping () -> Void) {
        self.onPreview = onPreview
        self.onRemove = onRemove
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: side).isActive = true
        heightAnchor.constraint(equalToConstant: side).isActive = true

        let thumbnail = NSView(frame: bounds)
        thumbnail.wantsLayer = true
        thumbnail.layer?.contents = image
        thumbnail.layer?.contentsGravity = .resizeAspectFill
        thumbnail.layer?.cornerRadius = 6
        thumbnail.layer?.cornerCurve = .continuous
        thumbnail.layer?.masksToBounds = true
        thumbnail.layer?.borderWidth = 1
        thumbnail.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        thumbnail.toolTip = "Preview"
        thumbnail.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(previewPressed)))
        addSubview(thumbnail)

        let removeButton = PressableButton(frame: NSRect(
            x: side - Self.removeButtonSide - Self.removeButtonInset,
            y: side - Self.removeButtonSide - Self.removeButtonInset,
            width: Self.removeButtonSide,
            height: Self.removeButtonSide
        ))
        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove image")
        removeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white, NSColor.black.withAlphaComponent(0.85)]))
        removeButton.isBordered = false
        removeButton.imageScaling = .scaleProportionallyUpOrDown
        removeButton.toolTip = "Remove"
        removeButton.target = self
        removeButton.action = #selector(removePressed)
        addSubview(removeButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func previewPressed() { onPreview(self) }
    @objc private func removePressed() {
        ButtonMotion.dismiss(self) { [weak self] in self?.onRemove() }
    }
}
