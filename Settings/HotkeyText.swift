import AppKit

enum HotkeyText {
    private struct Modifier {
        let flag: NSEvent.ModifierFlags
        let name: String
        let symbol: String
    }

    private static let modifiers = [
        Modifier(flag: .control, name: "control", symbol: "⌃"),
        Modifier(flag: .option, name: "option", symbol: "⌥"),
        Modifier(flag: .shift, name: "shift", symbol: "⇧"),
        Modifier(flag: .command, name: "cmd", symbol: "⌘"),
    ]

    private static let modifierAliases = ["ctrl": "control", "alt": "option", "opt": "option", "command": "cmd"]
    private static let keySymbols = ["space": "Space", "return": "↩"]

    static func text(for event: NSEvent) -> String? {
        guard let key = HotkeyCombination.keyName(forKeyCode: Int(event.keyCode)) else { return nil }
        let pressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let names = modifiers.filter { pressed.contains($0.flag) }.map(\.name)
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
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last else { return text }
        let names = Set(parts.dropLast().map { modifierAliases[$0] ?? $0 })
        let modifierSymbols = modifiers.filter { names.contains($0.name) }.map(\.symbol).joined()
        return modifierSymbols + (keySymbols[key] ?? key.uppercased())
    }
}
