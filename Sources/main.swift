import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())

func refuse(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

if arguments.first == "--check-hotkey" {
    let text = arguments.dropFirst().joined(separator: " ")
    do {
        let combination = try HotkeyCombination.parse(text)
        if let conflict = HotkeyConflicts.conflict(for: text, claimedBy: HotkeyConflicts.clarifyScratchPadOwner) {
            refuse(conflict)
        }
        guard HotkeyRegistration.isAvailable(combination) else {
            refuse("\(text) is already taken by another app. Pick another hotkey.")
        }
        exit(0)
    } catch {
        refuse((error as? HotkeyCombination.ParseError)?.message ?? "\(error)")
    }
}

let app = NSApplication.shared

if arguments.contains("--listen") {
    app.setActivationPolicy(.accessory)
    let listener = ScratchPadHotkeyListener()
    listener.start()
    app.run()
    exit(0)
}

let piped = arguments.contains("--scratchpad") ? "" : String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
let hasSelection = !piped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

app.setActivationPolicy(hasSelection ? .accessory : .regular)
let voiceGuide = ClarifySettings.voiceGuide.trimmingCharacters(in: .whitespacesAndNewlines)
let controller = ClarifyController(
    source: hasSelection ? .selection : .scratchpad,
    original: hasSelection ? piped : "",
    pasteTarget: NSWorkspace.shared.menuBarOwningApplication,
    rewriter: ClaudeRewriter(voiceGuide: voiceGuide),
    onFinish: { NSApp.terminate(nil) }
)
controller.start()
app.run()
