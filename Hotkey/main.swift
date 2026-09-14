import AppKit
import Carbon.HIToolbox

enum ScratchPadLauncher {
    static let clarifyApp = URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
        .appendingPathComponent("Clarify.app")

    static func openScratchPad() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--scratchpad"]
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: clarifyApp, configuration: configuration)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

func register(_ combination: HotkeyCombination) -> EventHotKeyRef? {
    var reference: EventHotKeyRef?
    let identifier = EventHotKeyID(signature: OSType(0x434C_5246), id: 1)
    let status = RegisterEventHotKey(combination.keyCode, combination.carbonModifiers, identifier, GetApplicationEventTarget(), 0, &reference)
    return status == noErr ? reference : nil
}

func parsed(_ text: String) -> HotkeyCombination {
    do {
        return try HotkeyCombination.parse(text)
    } catch {
        fail((error as? HotkeyCombination.ParseError)?.message ?? "\(error)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--check" {
    let text = arguments.dropFirst().joined(separator: " ")
    guard let reference = register(parsed(text)) else { fail("\(text) is already taken by another app. Pick another hotkey.") }
    UnregisterEventHotKey(reference)
    exit(0)
}

guard let hotkey = ClarifySettings.scratchPadHotkey else {
    print("No scratchPadHotkey in \(ClarifySettings.settingsFile.path). Nothing to do.")
    exit(0)
}

var pressedEvent = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
    DispatchQueue.main.async { ScratchPadLauncher.openScratchPad() }
    return noErr
}, 1, &pressedEvent, nil, nil)

guard let registeredHotkey = register(parsed(hotkey)) else { fail("\(hotkey) is already taken by another app.") }

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.run()
