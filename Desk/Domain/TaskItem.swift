import Foundation

/// One line of a brain dump's task list. Lives inside a daily or weekly page; stored as JSON
/// in the page row so adding it needed no schema migration.
struct TaskItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var text: String
    var isDone: Bool
    var doneAt: Date?

    init(id: UUID = UUID(), text: String, isDone: Bool = false, doneAt: Date? = nil) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.doneAt = doneAt
    }

    var isBlankText: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

extension Array where Element == TaskItem {
    /// Stored form: blank lines dropped (the editor may still be showing one being typed).
    var trimmedForStorage: [TaskItem] { filter { !$0.isBlankText } }

    var doneCount: Int { filter(\.isDone).count }

    /// JSON for the page row; `nil` when there is nothing to keep.
    var storageJSON: String? {
        let kept = trimmedForStorage
        guard !kept.isEmpty, let data = try? Self.encoder.encode(kept) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func fromStorage(_ json: String?) -> [TaskItem] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? decoder.decode([TaskItem].self, from: data)) ?? []
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Editing

    /// Appends a task, or inserts it right after `after`. Returns the new task.
    @discardableResult
    mutating func addTask(_ text: String, after: UUID? = nil, now: Date = Date()) -> TaskItem {
        let task = TaskItem(text: text)
        if let after, let i = firstIndex(where: { $0.id == after }) {
            insert(task, at: i + 1)
        } else {
            append(task)
        }
        return task
    }

    mutating func setText(_ text: String, id: UUID) {
        guard let i = firstIndex(where: { $0.id == id }), self[i].text != text else { return }
        self[i].text = text
    }

    mutating func toggle(id: UUID, now: Date = Date()) {
        guard let i = firstIndex(where: { $0.id == id }) else { return }
        self[i].isDone.toggle()
        self[i].doneAt = self[i].isDone ? now : nil
    }

    mutating func remove(id: UUID) {
        removeAll { $0.id == id }
    }

    /// Drops lines with no text, keeping the one still being edited.
    mutating func pruneBlank(except keep: UUID? = nil) {
        removeAll { $0.isBlankText && $0.id != keep }
    }
}
