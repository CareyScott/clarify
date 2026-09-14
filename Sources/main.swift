import AppKit

let arguments = CommandLine.arguments.dropFirst()
let piped = arguments.contains("--scratchpad") ? "" : String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
let hasSelection = !piped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

let app = NSApplication.shared
app.setActivationPolicy(hasSelection ? .accessory : .regular)
let voiceGuide = ClarifySettings.voiceGuide.trimmingCharacters(in: .whitespacesAndNewlines)
let controller = ClarifyController(
    source: hasSelection ? .selection : .scratchpad,
    original: hasSelection ? piped : "",
    pasteTarget: NSWorkspace.shared.menuBarOwningApplication,
    rewriter: ClaudeRewriter(voiceGuide: voiceGuide)
)
controller.start()
app.run()
