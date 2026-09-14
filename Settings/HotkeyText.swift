import AppKit

enum HotkeyText {
    private static let modifierNames: [(flag: NSEvent.ModifierFlags, name: String)] = [
        (.control, "control"), (.option, "option"), (.shift, "shift"), (.command, "cmd"),
    ]

    static func text(for event: NSEvent) -> String? {
        guard let key = HotkeyCombination.keyName(forKeyCode: Int(event.keyCode)) else { return nil }
        let pressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let names = modifierNames.filter { pressed.contains($0.flag) }.map(\.name)
        return (names + [key]).joined(separator: "+")
    }

    static func problem(with text: String) -> String? {
        do {
            _ = try HotkeyCombination.parse(text)
            return nil
        } catch {
            return (error as? HotkeyCombination.ParseError)?.message ?? "\(error)"
        }
    }

    static func symbols(for text: String) -> String {
        HotkeyCombination.symbols(for: text)
    }
}
