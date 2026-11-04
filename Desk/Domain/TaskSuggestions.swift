import Foundation

/// Tidying for the to-dos the on-device model pulls out of brain-dump notes: strips list
/// markers, drops blanks and anything already on the task list, and caps the count.
/// Pure so it can be tested without the model.
enum TaskSuggestions {
    /// Most suggestions shown at once; a brain dump rarely holds more real to-dos than this.
    static let maxCount = 12
    /// Notes beyond this many characters are not sent: the on-device model has a ~4K-token
    /// window shared by the instructions, the existing tasks and the answer.
    static let notesCharacterLimit = 8_000

    /// The notes as sent to the model, cut at a line break near `limit` when too long.
    static func promptNotes(_ notes: String, limit: Int = notesCharacterLimit) -> (text: String, wasTruncated: Bool) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return (trimmed, false) }
        var cut = String(trimmed.prefix(limit))
        if let lastBreak = cut.lastIndex(of: "\n"), cut.distance(from: cut.startIndex, to: lastBreak) > limit / 2 {
            cut = String(cut[..<lastBreak])
        }
        return (cut.trimmingCharacters(in: .whitespacesAndNewlines), true)
    }

    /// Model output → tasks worth offering, in order.
    static func clean(_ raw: [String], existing: [TaskItem]) -> [String] {
        var keys = existing.map { normalized($0.text) }.filter { !$0.isEmpty }
        var result: [String] = []
        for item in raw {
            let text = tidy(item)
            let key = normalized(text)
            guard !key.isEmpty, !keys.contains(where: { overlaps($0, key) }) else { continue }
            keys.append(key)
            result.append(text)
            if result.count == maxCount { break }
        }
        return result
    }

    /// Drops list markers ("- ", "•", "[ ]", "1.") and a trailing full stop; capitalises the first letter.
    static func tidy(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = /^(?:[-*•–·]\s*|\[\s?[xX ]?\s?\]\s*|\d{1,2}[.)]\s+)+/
        if let m = s.prefixMatch(of: marker) { s = String(s[m.range.upperBound...]) }
        while s.hasSuffix(".") && !s.hasSuffix("...") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.first, first.isLowercase { s = first.uppercased() + s.dropFirst() }
        return s
    }

    /// Comparison key: case, accents and punctuation ignored, words single-spaced.
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let words = folded.split { !$0.isLetter && !$0.isNumber }
        return words.joined(separator: " ")
    }

    /// Same task: identical keys, or one is a run of 2+ whole words inside the other
    /// ("call mom" vs "call mom about sunday dinner"). Single words don't count, so an
    /// existing "Email" doesn't swallow "Email Sarah the draft".
    static func overlaps(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (short, long) = a.count < b.count ? (a, b) : (b, a)
        guard short.contains(" ") else { return false }
        return " \(long) ".contains(" \(short) ")
    }
}

extension Array where Element == TaskItem {
    /// Appends each text as a new task (after dropping any blank line still in the list).
    mutating func appendTasks(_ texts: [String]) {
        pruneBlank()
        for text in texts where !text.trimmingCharacters(in: .whitespaces).isEmpty {
            addTask(text)
        }
    }
}
