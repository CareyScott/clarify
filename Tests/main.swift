import Carbon.HIToolbox
import Foundation

var failures = 0

func expect(_ name: String, _ condition: Bool) {
    if condition {
        print("pass  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

func originalText(of segments: [DiffSegment]) -> String {
    segments.map { segment in
        switch segment {
        case let .unchanged(text), let .removed(text): return text
        case .added: return ""
        }
    }.joined()
}

func revisedText(of segments: [DiffSegment]) -> String {
    segments.map { segment in
        switch segment {
        case let .unchanged(text), let .added(text): return text
        case .removed: return ""
        }
    }.joined()
}

expect("identical text is one unchanged segment",
       WordDiff.segments(from: "hello there", to: "hello there") == [.unchanged("hello there")])

expect("spelling fix replaces only the word",
       WordDiff.segments(from: "teh cat sat", to: "the cat sat") == [.removed("teh"), .added("the"), .unchanged(" cat sat")])

expect("neighbouring word changes read as one replacement",
       WordDiff.segments(from: "the quick fox", to: "a fast fox") == [.removed("the quick"), .added("a fast"), .unchanged(" fox")])

expect("empty original is all added",
       WordDiff.segments(from: "", to: "new text") == [.added("new text")])

expect("punctuation and word fix across one space read as one replacement",
       WordDiff.segments(from: "ok lets go", to: "ok, let's go") == [.unchanged("ok"), .removed(" lets"), .added(", let's"), .unchanged(" go")])

expect("added word at the end is a lone insertion",
       WordDiff.segments(from: "we shoud ship", to: "we should ship it") == [.unchanged("we "), .removed("shoud"), .added("should"), .unchanged(" ship"), .added(" it")])

let samples: [(String, String)] = [
    ("i think we should maybe ship it tomorow\n\nthoughts?", "we should ship it tomorrow.\n\nthoughts?"),
    ("Grüße aus Köln, bis später", "Viele Grüße aus Köln, bis bald"),
    ("launch 🚀 is on friday", "launch 🚀 is on Friday 👍"),
    ("  leading and trailing  ", "leading and trailing"),
    ("line one\r\nline two", "line one\nline 2"),
    ("", ""),
]

for (index, sample) in samples.enumerated() {
    expect("sample \(index) tokens cover the text", WordDiff.tokens(in: sample.0).joined() == sample.0)
    let segments = WordDiff.segments(from: sample.0, to: sample.1)
    expect("sample \(index) rebuilds the original", originalText(of: segments) == sample.0)
    expect("sample \(index) rebuilds the revision", revisedText(of: segments) == sample.1)
}

let longOriginal = Array(repeating: "word", count: 2500).joined(separator: " ")
let longRevision = longOriginal.replacingOccurrences(of: "word word", with: "word, word")
let longSegments = WordDiff.segments(from: longOriginal, to: longRevision)
expect("text past the table limit still rebuilds both sides",
       originalText(of: longSegments) == longOriginal && revisedText(of: longSegments) == longRevision)

func parseError(_ text: String) -> HotkeyCombination.ParseError? {
    do {
        _ = try HotkeyCombination.parse(text)
        return nil
    } catch {
        return error as? HotkeyCombination.ParseError
    }
}

expect("option+c parses to the c key with option",
       (try? HotkeyCombination.parse("option+c")) == HotkeyCombination(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: UInt32(optionKey)))

expect("spaces and case are ignored",
       (try? HotkeyCombination.parse("Cmd + Shift + Space")) == HotkeyCombination(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | shiftKey)))

expect("alt and ctrl aliases work",
       (try? HotkeyCombination.parse("ctrl+alt+k")) == HotkeyCombination(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(controlKey | optionKey)))

expect("a bare key is refused", parseError("c") == .needsCommandOptionOrControl)
expect("shift alone is refused", parseError("shift+a") == .needsCommandOptionOrControl)
expect("an unknown modifier is named", parseError("hyper+c") == .unknownModifier("hyper"))
expect("an unknown key is named", parseError("option+é") == .unknownKey("é"))
expect("an empty hotkey is refused", parseError("  ") == .empty)

expect("key code maps back to its key name", HotkeyCombination.keyName(forKeyCode: kVK_ANSI_C) == "c")
expect("option+c shows as ⌥C", HotkeyText.symbols(for: "option+c") == "⌥C")
expect("modifiers show in macOS order", HotkeyText.symbols(for: "Cmd + Shift + Space") == "⇧⌘Space")
expect("aliases show the same symbols", HotkeyText.symbols(for: "alt+ctrl+return") == "⌃⌥↩")
expect("recorded text is checked", HotkeyText.problem(with: "shift+a") != nil && HotkeyText.problem(with: "option+c") == nil)

exit(failures == 0 ? 0 : 1)
