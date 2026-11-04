import Foundation

/// One line of a brain dump's task list. Lives inside a daily or weekly page; stored as JSON
/// in the page row so adding it needed no schema migration.
struct TaskItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var text: String
    var isDone: Bool
    var doneAt: Date?
    /// Day (`LocalDate.key`) whose page the task was checked off on. A finished week task
    /// shows only on that day; absent on tasks finished before this existed (see `isVisible`).
    var doneOn: Int?

    init(id: UUID = UUID(), text: String, isDone: Bool = false, doneAt: Date? = nil, doneOn: Int? = nil) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.doneAt = doneAt
        self.doneOn = doneOn
    }

    var isBlankText: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Whether a week task belongs on `day`'s page: open tasks show every day of the week,
    /// finished ones only on the day they were checked off.
    func isVisible(on day: LocalDate, calendar: DeskCalendar) -> Bool {
        guard isDone else { return true }
        if let doneOn { return doneOn == day.key }
        if let doneAt { return calendar.localDate(from: doneAt) == day }
        return true
    }
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

    /// Checks a task off (or back on). `day` is the page it happened on, kept in `doneOn`.
    mutating func toggle(id: UUID, on day: LocalDate? = nil, now: Date = Date()) {
        guard let i = firstIndex(where: { $0.id == id }) else { return }
        self[i].isDone.toggle()
        self[i].doneAt = self[i].isDone ? now : nil
        self[i].doneOn = self[i].isDone ? day?.key : nil
    }

    mutating func remove(id: UUID) {
        removeAll { $0.id == id }
    }

    // MARK: Week lists seen from one day

    /// The week tasks to show on `day`'s page (finished ones only on the day they were done).
    func visible(on day: LocalDate, calendar: DeskCalendar) -> [TaskItem] {
        filter { $0.isVisible(on: day, calendar: calendar) }
    }

    /// The whole week list after `day`'s page edited its `visible` slice: the hidden tasks
    /// (finished on other days) are kept, each near where it was.
    func replacingVisible(_ edited: [TaskItem], on day: LocalDate, calendar: DeskCalendar) -> [TaskItem] {
        let editedIDs = Set(edited.map(\.id))
        var result = edited
        for (i, task) in enumerated() where !task.isVisible(on: day, calendar: calendar) && !editedIDs.contains(task.id) {
            result.insert(task, at: Swift.min(i, result.count))
        }
        return result
    }

    /// Drops lines with no text, keeping the one still being edited.
    mutating func pruneBlank(except keep: UUID? = nil) {
        removeAll { $0.isBlankText && $0.id != keep }
    }
}
