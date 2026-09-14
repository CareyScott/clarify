import Foundation

struct HotkeyClaim {
    let ownerID: String
    let ownerName: String
    let hotkey: String
}

enum HotkeyConflicts {
    static let clarifyScratchPadOwner = "clarify.scratchPad"

    static func speakOwner(_ commandID: String) -> String {
        "speak.\(commandID)"
    }

    static let claudeCodeShortcuts: [HotkeyClaim] = [
        ("control+c", "interrupt or exit"),
        ("control+d", "exit"),
        ("control+g", "open the prompt in an editor"),
        ("control+l", "redraw the screen"),
        ("control+o", "transcript"),
        ("control+r", "history search"),
        ("control+v", "paste an image"),
        ("control+b", "background commands"),
        ("control+t", "task list"),
        ("control+s", "stash the prompt"),
        ("control+z", "suspend"),
        ("control+x", "editor and subagent key sequences"),
        ("control+a", "start of line"),
        ("control+e", "end of line"),
        ("control+k", "delete to end of line"),
        ("control+u", "delete to start of line"),
        ("control+w", "delete word"),
        ("control+y", "paste deleted text"),
        ("control+p", "previous history"),
        ("control+n", "next history"),
        ("control+j", "new line"),
        ("option+t", "toggle extended thinking"),
        ("option+o", "toggle fast mode"),
        ("option+p", "switch model"),
        ("option+b", "word back"),
        ("option+f", "word forward"),
        ("option+d", "delete word"),
        ("option+y", "paste history"),
        ("option+return", "new line"),
    ].map { HotkeyClaim(ownerID: "claude.code", ownerName: "Claude Code (\($0.1))", hotkey: $0.0) }

    private static let speakCommandTitles = [
        "speak-selection": "Speak Selection",
        "speak-simply": "Speak Simply",
        "speak-translated": "Speak Translated",
        "speak-stop": "Stop Speaking",
    ]

    private static let acceleratorModifiers = [
        "ctrl": "control", "control": "control",
        "alt": "option", "option": "option",
        "cmd": "cmd", "command": "cmd", "commandorcontrol": "cmd", "cmdorctrl": "cmd", "super": "cmd", "meta": "cmd",
        "shift": "shift",
    ]

    static func conflict(for hotkey: String, claimedBy ownerID: String, against claims: [HotkeyClaim] = currentClaims()) -> String? {
        guard let wanted = try? HotkeyCombination.parse(hotkey) else { return nil }
        guard let clash = claims.first(where: { $0.ownerID != ownerID && (try? HotkeyCombination.parse($0.hotkey)) == wanted }) else {
            return nil
        }
        return "\(HotkeyCombination.symbols(for: hotkey)) is already used by \(clash.ownerName). Pick another."
    }

    static func currentClaims() -> [HotkeyClaim] {
        claudeCodeShortcuts + claudeDesktopClaims() + clarifyClaims() + speakClaims()
    }

    static func claudeDesktopHotkey(fromAccelerator accelerator: String) -> String? {
        let parts = accelerator.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, parts.count > 1 else { return nil }
        var modifiers: [String] = []
        for part in parts.dropLast() {
            guard let modifier = acceleratorModifiers[part] else { return nil }
            modifiers.append(modifier)
        }
        return (modifiers + [key == "enter" ? "return" : key]).joined(separator: "+")
    }

    private static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    private static func claudeDesktopClaims() -> [HotkeyClaim] {
        let config = home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        guard let accelerator = values(at: config)["globalShortcut"] as? String,
              let hotkey = claudeDesktopHotkey(fromAccelerator: accelerator) else { return [] }
        return [HotkeyClaim(ownerID: "claude.desktop", ownerName: "Claude desktop (quick entry)", hotkey: hotkey)]
    }

    private static func clarifyClaims() -> [HotkeyClaim] {
        let settings = home.appendingPathComponent(".config/clarify/settings.json")
        guard let hotkey = values(at: settings)["scratchPadHotkey"] as? String, !hotkey.isEmpty else { return [] }
        return [HotkeyClaim(ownerID: clarifyScratchPadOwner, ownerName: "Clarify Scratch Pad", hotkey: hotkey)]
    }

    private static func speakClaims() -> [HotkeyClaim] {
        let directory = ProcessInfo.processInfo.environment["SPEAK_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config/speak")
        let hotkeys = values(at: directory.appendingPathComponent("settings.json"))["hotkeys"] as? [String: String] ?? [:]
        return hotkeys.compactMap { commandID, hotkey in
            hotkey.isEmpty ? nil : HotkeyClaim(
                ownerID: speakOwner(commandID),
                ownerName: "speak \(speakCommandTitles[commandID] ?? commandID)",
                hotkey: hotkey
            )
        }
    }

    private static func values(at file: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
