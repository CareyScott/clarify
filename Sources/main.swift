import AppKit

let selection = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
guard !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    FileHandle.standardError.write(Data("Nothing selected.\n".utf8))
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = ClarifyController(original: selection, rewriter: ClaudeRewriter(voiceGuide: VoiceGuide.load()))
controller.start()
app.run()
