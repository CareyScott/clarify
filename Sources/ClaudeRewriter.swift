import Foundation

struct RevisionRequest {
    let original: String
    let draft: String
    let instructions: [String]
    let contextImagesJPEG: [Data]
}

struct Revision: Equatable {
    let notes: String
    let text: String
}

struct RewriteFailure: Error {
    let message: String
}

final class ClaudeRewriter {
    private let voiceGuide: String
    private var running: Process?
    private var requestNumber = 0

    init(voiceGuide: String) {
        self.voiceGuide = voiceGuide
    }

    func revise(_ request: RevisionRequest, completion: @escaping (Result<Revision, RewriteFailure>) -> Void) {
        cancel()
        requestNumber += 1
        let thisRequest = requestNumber
        guard let claude = Self.locateClaude() else {
            completion(.failure(RewriteFailure(message: "Could not find the claude command. Install Claude Code or add it to PATH.")))
            return
        }
        let process = Process()
        process.executableURL = claude
        process.arguments = arguments()
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        running = process
        let message = Self.streamMessage(for: request)
        let original = request.original
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.run(process, sending: message, original: original)
            DispatchQueue.main.async {
                guard thisRequest == self.requestNumber else { return }
                self.running = nil
                completion(result)
            }
        }
    }

    func cancel() {
        running?.terminate()
        running = nil
        requestNumber += 1
    }

    private func arguments() -> [String] {
        [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--tools", "",
            "--setting-sources", "",
            "--strict-mcp-config",
            "--no-session-persistence",
            "--model", ClarifySettings.model,
            "--system-prompt", systemPrompt(),
        ]
    }

    private func systemPrompt() -> String {
        let voice = voiceGuide.isEmpty ? "No voice guide given. Take the voice from the text itself." : voiceGuide
        return """
        You tidy up text someone has already written in their own voice. Return their text, cleaned, not your version of it.

        Keep their words, phrasing and structure wherever they already work. Fix spelling, grammar and punctuation. Make the idea clear: fix sentences that are hard to follow, cut repetition, and bring the main point forward only when it is buried. Do not add facts, ideas, greetings or sign-offs they did not write. Do not make it longer or more formal. Keep the language of the original. Keep line breaks and lists as given unless an instruction says otherwise.

        Code: wrap every inline reference to code in backticks, such as identifiers, function names, commands, file paths, config keys and field names. Put any code that spans more than one line in a fenced code block, with a language tag when the language is clear. Never change what is inside code, only how it is marked. When they describe logic as pseudo code, for example steps with if, else, for each or return, write it as clean pseudo code in a fenced block: one step per line, indentation for nesting, the same keywords throughout, and their names kept as they are. Keep their own sentences around a block, such as the line that introduces it. Do not turn pseudo code into a real programming language unless asked.

        When instructions are given, apply them to the current draft, latest last, keeping earlier ones in force. If the latest instruction is a question, answer it in the notes and leave the draft alone unless the answer calls for a change.

        Attached images are screenshots or pictures they added for context, such as the thread they are replying to. Use them only to understand who the text is for and what it refers to.

        Their voice:
        <voice>
        \(voice)
        </voice>

        Reply in exactly this shape and nothing else:
        <notes>One to three short plain lines in their voice: what you changed, and anything still unclear that only they can fix. If nothing needed changing, say so.</notes>
        <text>The full revised text.</text>
        """
    }

    static func userPrompt(for request: RevisionRequest) -> String {
        var prompt = "<original>\n\(request.original)\n</original>"
        guard !request.instructions.isEmpty else { return prompt }
        prompt += "\n\n<draft>\n\(request.draft)\n</draft>"
        prompt += "\n\n<instructions>\n" + request.instructions.map { "- \($0)" }.joined(separator: "\n") + "\n</instructions>"
        return prompt
    }

    private static func streamMessage(for request: RevisionRequest) -> Data {
        let images: [[String: Any]] = request.contextImagesJPEG.map { jpeg in
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]]
        }
        let content = images + [["type": "text", "text": userPrompt(for: request)]]
        let envelope: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
        let line = (try? JSONSerialization.data(withJSONObject: envelope)) ?? Data()
        return line + Data("\n".utf8)
    }

    private static func run(_ process: Process, sending message: Data, original: String) -> Result<Revision, RewriteFailure> {
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failure(RewriteFailure(message: "Could not start claude: \(error.localizedDescription)"))
        }
        input.fileHandleForWriting.write(message)
        try? input.fileHandleForWriting.close()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let result = finalResult(in: stdout) else {
            return .failure(RewriteFailure(message: "claude stopped without an answer (exit \(process.terminationStatus))."))
        }
        guard !result.isError else { return .failure(RewriteFailure(message: result.text)) }
        return .success(revision(fromReply: result.text, original: original))
    }

    private static func finalResult(in stdout: Data) -> (text: String, isError: Bool)? {
        let lines = String(decoding: stdout, as: UTF8.self).split(separator: "\n")
        for line in lines.reversed() {
            guard let event = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  event["type"] as? String == "result" else { continue }
            let subtype = event["subtype"] as? String ?? ""
            let isError = (event["is_error"] as? Bool ?? false) || subtype != "success"
            return (event["result"] as? String ?? "claude failed: \(subtype)", isError)
        }
        return nil
    }

    static func revision(fromReply reply: String, original: String) -> Revision {
        let notes = contents(ofTag: "notes", in: reply) ?? ""
        let body = contents(ofTag: "text", in: reply) ?? reply
        return Revision(
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            text: body.trimmingCharacters(in: .whitespacesAndNewlines).wrapped(inEdgeWhitespaceOf: original)
        )
    }

    private static func contents(ofTag tag: String, in reply: String) -> String? {
        guard let open = reply.range(of: "<\(tag)>"),
              let close = reply.range(of: "</\(tag)>", options: .backwards, range: open.upperBound..<reply.endIndex) else { return nil }
        return String(reply[open.upperBound..<close.lowerBound])
    }

    private static func locateClaude() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let directories = pathEntries + ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        return directories
            .map { URL(fileURLWithPath: $0).appendingPathComponent("claude") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private extension String {
    func wrapped(inEdgeWhitespaceOf original: String) -> String {
        let leading = original.prefix(while: \.isWhitespace)
        let trailing = String(original.reversed().prefix(while: \.isWhitespace).reversed())
        return leading + self + trailing
    }
}
