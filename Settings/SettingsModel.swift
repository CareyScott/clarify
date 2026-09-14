import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ModelChoice: Identifiable {
    let id: String
    let title: String
}

final class SettingsModel: ObservableObject {
    static let modelChoices = [
        ModelChoice(id: "sonnet", title: "Sonnet"),
        ModelChoice(id: "opus", title: "Opus"),
        ModelChoice(id: "haiku", title: "Haiku"),
    ]

    private enum HotkeyCommandResult {
        case succeeded
        case failed(String)
    }

    @Published private(set) var hotkey: String?
    @Published private(set) var hotkeyMessage: String?
    @Published private(set) var isRecordingHotkey = false
    @Published private(set) var isSavingHotkey = false
    @Published var model: String {
        didSet { ClarifySettings.saveModel(model) }
    }
    @Published var voiceGuide: String {
        didSet { ClarifySettings.saveVoiceGuide(voiceGuide) }
    }

    private let hotkeyCommand = Bundle.main.bundleURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("bin/clarify-hotkey")
    private var keyMonitor: Any?

    init() {
        hotkey = ClarifySettings.scratchPadHotkey
        model = ClarifySettings.model
        voiceGuide = ClarifySettings.voiceGuide
    }

    func startRecordingHotkey() {
        guard !isRecordingHotkey, !isSavingHotkey else { return }
        _ = runHotkeyCommand(["pause"])
        isRecordingHotkey = true
        hotkeyMessage = "Press the shortcut you want, or Esc to cancel."
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.record(event)
            return nil
        }
    }

    func cancelRecording() {
        guard isRecordingHotkey else { return }
        stopMonitoringKeys()
        hotkeyMessage = nil
        _ = runHotkeyCommand(["resume"])
    }

    func clearHotkey() {
        saveHotkey(arguments: ["off"]) { [weak self] in
            self?.hotkey = nil
            self?.hotkeyMessage = "No hotkey. Open the pad from Raycast or with clarify-scratchpad."
        }
    }

    private func record(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            cancelRecording()
            return
        }
        guard let text = HotkeyText.text(for: event) else {
            hotkeyMessage = "That key cannot be used. Use a letter, a digit, space or return with cmd, option or control."
            return
        }
        if let problem = HotkeyText.problem(with: text) {
            hotkeyMessage = problem
            return
        }
        stopMonitoringKeys()
        saveHotkey(arguments: [text]) { [weak self] in
            self?.hotkey = text
            self?.hotkeyMessage = "Press \(HotkeyText.symbols(for: text)) in any app to open a scratch pad."
        }
    }

    private func saveHotkey(arguments: [String], onSuccess: @escaping () -> Void) {
        isSavingHotkey = true
        hotkeyMessage = "Saving…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.runHotkeyCommand(arguments)
            DispatchQueue.main.async {
                self.isSavingHotkey = false
                switch result {
                case .succeeded:
                    onSuccess()
                case let .failed(message):
                    self.hotkeyMessage = message
                }
            }
        }
    }

    private func stopMonitoringKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        isRecordingHotkey = false
    }

    private func runHotkeyCommand(_ arguments: [String]) -> HotkeyCommandResult {
        let process = Process()
        process.executableURL = hotkeyCommand
        process.arguments = arguments
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failed("Could not run clarify-hotkey: \(error.localizedDescription)")
        }
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return .succeeded }
        return .failed(message.isEmpty ? "Could not save that hotkey." : message)
    }
}
