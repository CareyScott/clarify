import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static func isGranted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

enum SelectedText {
    private static let copyKeyCode: CGKeyCode = 8
    private static let copyTimeout: TimeInterval = 0.5
    private static let pollInterval: useconds_t = 20_000

    static func inFrontApp() -> String? {
        guard AccessibilityPermission.isGranted() else { return nil }
        if let selection = accessibilitySelection() { return selection }
        return copiedSelection()
    }

    private static func accessibilitySelection() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func copiedSelection() -> String? {
        let pasteboard = NSPasteboard.general
        let savedItems = snapshot(of: pasteboard)
        let changeCountBeforeCopy = pasteboard.changeCount
        pressCommandC()
        let deadline = Date().addingTimeInterval(copyTimeout)
        while pasteboard.changeCount == changeCountBeforeCopy && Date() < deadline {
            usleep(pollInterval)
        }
        let copied = pasteboard.changeCount == changeCountBeforeCopy ? nil : pasteboard.string(forType: .string)
        pasteboard.clearContents()
        if !savedItems.isEmpty { pasteboard.writeObjects(savedItems) }
        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return copied
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func pressCommandC() {
        let source = CGEventSource(stateID: .privateState)
        for isKeyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: copyKeyCode, keyDown: isKeyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
