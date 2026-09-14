import AppKit
import ApplicationServices

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum FrontAppPaste {
    private static let commandVKeyCode: CGKeyCode = 9

    static func isAllowed() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func paste(_ text: String, completion: @escaping () -> Void) {
        let previousClipboard = NSPasteboard.general.string(forType: .string)
        Clipboard.copy(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            pressCommandV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let previousClipboard { Clipboard.copy(previousClipboard) }
                completion()
            }
        }
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isKeyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: commandVKeyCode, keyDown: isKeyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
