import AppKit
import QuartzCore

enum ButtonMotion {
    static let pressDuration: TimeInterval = 0.08
    private static let pressedScale: CGFloat = 0.92
    private static let dismissedScale: CGFloat = 0.8
    private static let dismissDuration: TimeInterval = 0.16
    private static let fadeDuration: TimeInterval = 0.15
    private static let crossfadeDuration: TimeInterval = 0.18

    static func press(_ view: NSView) {
        animateScale(of: view, to: pressedScale, springy: false, duration: pressDuration)
    }

    static func release(_ view: NSView) {
        animateScale(of: view, to: 1, springy: true, duration: pressDuration)
    }

    static func dismiss(_ view: NSView, completion: @escaping () -> Void) {
        animateScale(of: view, to: dismissedScale, springy: false, duration: dismissDuration)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = dismissDuration
            view.animator().alphaValue = 0
        }, completionHandler: completion)
    }

    static func crossfade(_ view: NSView) {
        view.wantsLayer = true
        let transition = CATransition()
        transition.type = .fade
        transition.duration = crossfadeDuration
        view.layer?.add(transition, forKey: "crossfade")
    }

    static func fadeBackground(of view: NSView, to colour: NSColor) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        animation.toValue = colour.cgColor
        animation.duration = fadeDuration
        layer.backgroundColor = colour.cgColor
        layer.add(animation, forKey: "background")
    }

    private static func animateScale(of view: NSView, to scale: CGFloat, springy: Bool, duration: TimeInterval) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let centre = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        var target = CATransform3DMakeTranslation(centre.x, centre.y, 0)
        target = CATransform3DScale(target, scale, scale, 1)
        target = CATransform3DTranslate(target, -centre.x, -centre.y, 0)

        let animation: CABasicAnimation
        if springy {
            let spring = CASpringAnimation(keyPath: "transform")
            spring.mass = 1
            spring.stiffness = 420
            spring.damping = 18
            spring.duration = spring.settlingDuration
            animation = spring
        } else {
            animation = CABasicAnimation(keyPath: "transform")
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        }
        animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
        animation.toValue = NSValue(caTransform3D: target)
        layer.transform = target
        layer.add(animation, forKey: "press")
    }
}

class PressableButton: NSButton {
    private var hoverArea: NSTrackingArea?

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            super.mouseDown(with: event)
            return
        }
        ButtonMotion.press(self)
        super.mouseDown(with: event)
        ButtonMotion.release(self)
    }

    func playPress() {
        ButtonMotion.press(self)
        DispatchQueue.main.asyncAfter(deadline: .now() + ButtonMotion.pressDuration) { ButtonMotion.release(self) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        hoverChanged(false)
    }

    func hoverChanged(_ hovering: Bool) {}
}

final class IconButton: PressableButton {
    static let restingTint = NSColor.white.withAlphaComponent(0.8)
    private static let hoverBackground = NSColor.white.withAlphaComponent(0.1)

    override func hoverChanged(_ hovering: Bool) {
        contentTintColor = hovering ? .white : Self.restingTint
        ButtonMotion.fadeBackground(of: self, to: hovering && isEnabled ? Self.hoverBackground : .clear)
    }
}
