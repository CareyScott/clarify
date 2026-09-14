import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Hotkey") {
                    HStack(spacing: 8) {
                        Button(hotkeyButtonTitle) { settings.startRecordingHotkey() }
                            .disabled(settings.isRecordingHotkey || settings.isSavingHotkey)
                        if settings.hotkey != nil && !settings.isRecordingHotkey && !settings.isSavingHotkey {
                            Button("Clear") { settings.clearHotkey() }
                        }
                    }
                }
            } header: {
                Text("Scratch pad")
            } footer: {
                Text(settings.hotkeyMessage ?? "Optional. Opens a scratch pad from any app.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Model", selection: $settings.model) {
                    ForEach(SettingsModel.modelChoices) { choice in
                        Text(choice.title).tag(choice.id)
                    }
                }
            } header: {
                Text("Claude")
            } footer: {
                Text("Sonnet is the default and usually replies in a few seconds.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $settings.voiceGuide)
                    .font(.system(size: 13))
                    .frame(minHeight: 260)
            } header: {
                Text("Your voice")
            } footer: {
                Text("Sent with every request so the result still sounds like you. Saved as you type.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 660)
    }

    private var hotkeyButtonTitle: String {
        if settings.isRecordingHotkey { return "Press shortcut…" }
        if settings.isSavingHotkey { return "Saving…" }
        return settings.hotkey.map(HotkeyText.symbols(for:)) ?? "Record Shortcut"
    }
}
