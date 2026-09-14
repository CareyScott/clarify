import Foundation

enum DiffSegment: Equatable {
    case unchanged(String)
    case removed(String)
    case added(String)
}

enum WordDiff {
    private static let tokenPattern = try! NSRegularExpression(pattern: "\\s+|[\\p{L}\\p{N}'’]+|[^\\s\\p{L}\\p{N}]")
    private static let tableCellLimit = 4_000_000

    private enum Chunk {
        case unchanged(String)
        case changed(removed: String, added: String)
    }

    static func segments(from original: String, to revised: String) -> [DiffSegment] {
        if original == revised { return original.isEmpty ? [] : [.unchanged(original)] }
        let before = tokens(in: original)
        let after = tokens(in: revised)
        guard (before.count + 1) * (after.count + 1) <= tableCellLimit else {
            return segments(from: [.changed(removed: original, added: revised)])
        }
        return segments(from: mergeWhitespaceBetweenChanges(chunks(from: tokenChanges(before, after))))
    }

    static func tokens(in text: String) -> [String] {
        let matches = tokenPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func tokenChanges(_ before: [String], _ after: [String]) -> [DiffSegment] {
        let columns = after.count + 1
        var commonLength = [Int32](repeating: 0, count: (before.count + 1) * columns)
        for i in stride(from: before.count - 1, through: 0, by: -1) {
            for j in stride(from: after.count - 1, through: 0, by: -1) {
                commonLength[i * columns + j] = before[i] == after[j]
                    ? commonLength[(i + 1) * columns + j + 1] + 1
                    : max(commonLength[(i + 1) * columns + j], commonLength[i * columns + j + 1])
            }
        }
        var changes: [DiffSegment] = []
        var i = 0
        var j = 0
        while i < before.count && j < after.count {
            if before[i] == after[j] {
                changes.append(.unchanged(before[i]))
                i += 1
                j += 1
            } else if commonLength[(i + 1) * columns + j] >= commonLength[i * columns + j + 1] {
                changes.append(.removed(before[i]))
                i += 1
            } else {
                changes.append(.added(after[j]))
                j += 1
            }
        }
        changes += before[i...].map(DiffSegment.removed)
        changes += after[j...].map(DiffSegment.added)
        return changes
    }

    private static func chunks(from tokenChanges: [DiffSegment]) -> [Chunk] {
        var chunks: [Chunk] = []
        for change in tokenChanges {
            switch (change, chunks.last) {
            case let (.unchanged(token), .unchanged(text)?):
                chunks[chunks.count - 1] = .unchanged(text + token)
            case let (.unchanged(token), _):
                chunks.append(.unchanged(token))
            case let (.removed(token), .changed(removed, added)?):
                chunks[chunks.count - 1] = .changed(removed: removed + token, added: added)
            case let (.removed(token), _):
                chunks.append(.changed(removed: token, added: ""))
            case let (.added(token), .changed(removed, added)?):
                chunks[chunks.count - 1] = .changed(removed: removed, added: added + token)
            case let (.added(token), _):
                chunks.append(.changed(removed: "", added: token))
            }
        }
        return chunks
    }

    private static func mergeWhitespaceBetweenChanges(_ chunks: [Chunk]) -> [Chunk] {
        var merged: [Chunk] = []
        var index = 0
        while index < chunks.count {
            if case let .unchanged(gap) = chunks[index], gap.allSatisfy(\.isWhitespace),
               case let .changed(removedBefore, addedBefore)? = merged.last,
               index + 1 < chunks.count,
               case let .changed(removedAfter, addedAfter) = chunks[index + 1] {
                merged[merged.count - 1] = .changed(removed: removedBefore + gap + removedAfter, added: addedBefore + gap + addedAfter)
                index += 2
            } else {
                merged.append(chunks[index])
                index += 1
            }
        }
        return merged
    }

    private static func segments(from chunks: [Chunk]) -> [DiffSegment] {
        chunks.flatMap { chunk -> [DiffSegment] in
            switch chunk {
            case let .unchanged(text):
                return [.unchanged(text)]
            case let .changed(removed, added):
                return (removed.isEmpty ? [] : [.removed(removed)]) + (added.isEmpty ? [] : [.added(added)])
            }
        }
    }
}
