import Carbon.HIToolbox

struct HotkeyCombination: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    enum ParseError: Error, Equatable {
        case empty
        case needsCommandOptionOrControl
        case unknownModifier(String)
        case unknownKey(String)

        var message: String {
            switch self {
            case .empty: return "No hotkey given. Example: option+c"
            case .needsCommandOptionOrControl: return "A hotkey needs cmd, option or control, so it does not take over normal typing. Example: option+c"
            case let .unknownModifier(name): return "Unknown modifier \"\(name)\". Use cmd, option, control or shift."
            case let .unknownKey(name): return "Unknown key \"\(name)\". Use a letter, a digit, space, return or one of . , / ; ' `"
            }
        }
    }

    private static let modifierMasks: [String: Int] = [
        "cmd": cmdKey, "command": cmdKey,
        "option": optionKey, "opt": optionKey, "alt": optionKey,
        "control": controlKey, "ctrl": controlKey,
        "shift": shiftKey,
    ]

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space, "return": kVK_Return,
        ".": kVK_ANSI_Period, ",": kVK_ANSI_Comma, "/": kVK_ANSI_Slash,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, "`": kVK_ANSI_Grave,
    ]

    static func keyName(forKeyCode keyCode: Int) -> String? {
        keyCodes.first { $0.value == keyCode }?.key
    }

    static func parse(_ text: String) throws -> HotkeyCombination {
        let parts = text.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let key = parts.last else { throw ParseError.empty }
        var modifiers = 0
        for name in parts.dropLast() {
            guard let mask = modifierMasks[name] else { throw ParseError.unknownModifier(name) }
            modifiers |= mask
        }
        guard modifiers & (cmdKey | optionKey | controlKey) != 0 else { throw ParseError.needsCommandOptionOrControl }
        guard let keyCode = keyCodes[key] else { throw ParseError.unknownKey(key) }
        return HotkeyCombination(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers))
    }
}
