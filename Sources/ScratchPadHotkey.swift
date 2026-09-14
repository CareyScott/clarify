import AppKit
import Carbon.HIToolbox

enum HotkeyRegistration {
    private static let identifier = EventHotKeyID(signature: OSType(0x434C_5246), id: 1)
    private static var onPress: (() -> Void)?
    private static var reference: EventHotKeyRef?

    static func isAvailable(_ combination: HotkeyCombination) -> Bool {
        guard let reference = register(combination) else { return false }
        UnregisterEventHotKey(reference)
        return true
    }

    static func listen(for combination: HotkeyCombination, onPress: @escaping () -> Void) -> Bool {
        self.onPress = onPress
        var pressedEvent = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotkeyRegistration.onPress?()
            return noErr
        }, 1, &pressedEvent, nil, nil)
        reference = register(combination)
        return reference != nil
    }

    private static func register(_ combination: HotkeyCombination) -> EventHotKeyRef? {
        var registered: EventHotKeyRef?
        let status = RegisterEventHotKey(combination.keyCode, combination.carbonModifiers, identifier, GetApplicationEventTarget(), 0, &registered)
        return status == noErr ? registered : nil
    }
}

final class ScratchPadHotkeyListener {
    private static let heldModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    private static let modifierReleaseTimeout: TimeInterval = 1.0

    private var controller: ClarifyController?
    private var activationObserver: NSObjectProtocol?

    func start() {
        guard let hotkey = ClarifySettings.scratchPadHotkey else {
            stopListening("No scratchPadHotkey in \(ClarifySettings.settingsFile.path). Nothing to do.")
        }
        guard let combination = try? HotkeyCombination.parse(hotkey) else {
            stopListening("\(hotkey) in settings is not a valid hotkey. Change it in Clarify Settings.")
        }
        guard HotkeyRegistration.listen(for: combination, onPress: { [weak self] in self?.openScratchPad() }) else {
            stopListening("\(hotkey) is already taken by another app. Change it in Clarify Settings.")
        }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.controller == nil else { return }
            self.openScratchPad()
        }
        if !AccessibilityPermission.isGranted() {
            FileHandle.standardError.write(Data("Accessibility is not allowed for Clarify yet, so the hotkey cannot read the selection. Allow it in System Settings > Privacy & Security > Accessibility.\n".utf8))
        }
    }

    private func openScratchPad() {
        if let controller {
            controller.reveal()
            return
        }
        waitForModifierRelease()
        let pasteTarget = NSWorkspace.shared.frontmostApplication
        let selection = SelectedText.inFrontApp() ?? ""
        log("Hotkey pressed in \(pasteTarget?.localizedName ?? "unknown app"): accessibility \(AXIsProcessTrusted() ? "on" : "off"), selection \(selection.count) characters")
        let voiceGuide = ClarifySettings.voiceGuide.trimmingCharacters(in: .whitespacesAndNewlines)
        let controller = ClarifyController(
            source: .scratchpad,
            original: selection,
            pasteTarget: pasteTarget,
            rewriter: ClaudeRewriter(voiceGuide: voiceGuide),
            onFinish: { [weak self] in
                DispatchQueue.main.async { self?.controller = nil }
            }
        )
        self.controller = controller
        controller.start()
    }

    private func waitForModifierRelease() {
        let deadline = Date().addingTimeInterval(Self.modifierReleaseTimeout)
        while Date() < deadline && !CGEventSource.flagsState(.combinedSessionState).intersection(Self.heldModifiers).isEmpty {
            usleep(20_000)
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("\(Date()): \(message)\n".utf8))
    }

    private func stopListening(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(0)
    }
}
