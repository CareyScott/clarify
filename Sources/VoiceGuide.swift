import Foundation

enum VoiceGuide {
    static let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/clarify/voice.md")

    static func load() -> String {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
