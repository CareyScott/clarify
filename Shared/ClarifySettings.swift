import Foundation

enum ClarifySettings {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/clarify")
    static let settingsFile = directory.appendingPathComponent("settings.json")
    static let voiceFile = directory.appendingPathComponent("voice.md")
    static let defaultModel = "sonnet"

    static var model: String {
        let saved = values()["model"] as? String ?? ""
        return saved.isEmpty ? defaultModel : saved
    }

    static var scratchPadHotkey: String? {
        let saved = (values()["scratchPadHotkey"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        return saved.isEmpty ? nil : saved
    }

    static var voiceGuide: String {
        (try? String(contentsOf: voiceFile, encoding: .utf8)) ?? ""
    }

    static func saveModel(_ model: String) {
        var updated = values()
        updated["model"] = model
        guard let data = try? JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: settingsFile, options: .atomic)
    }

    static func saveVoiceGuide(_ text: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? text.write(to: voiceFile, atomically: true, encoding: .utf8)
    }

    private static func values() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsFile) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
