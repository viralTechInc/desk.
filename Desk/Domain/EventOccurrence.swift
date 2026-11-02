import Foundation

/// Where a concrete occurrence on the timeline comes from.
enum OccurrenceSource: Hashable, Sendable {
    /// A one-off block stored on a specific date.
    case single(blockID: UUID)
    /// One day of a weekly recurrence rule. `originalDate` is the date the rule
    /// generated; the occurrence may be displayed on another date if an override moved it.
    case recurring(ruleID: UUID, originalDate: LocalDate)

    var isRecurring: Bool {
        if case .recurring = self { return true }
        return false
    }
}

/// A concrete, displayable event for one date. Both the Day and Week screens render
/// these; they are produced on demand by `RecurrenceEngine` from stored blocks, rules
/// and overrides and are never persisted.
struct EventOccurrence: Identifiable, Hashable, Sendable {
    let source: OccurrenceSource
    var date: LocalDate
    var title: String
    var startMinutes: Int
    var endMinutes: Int
    var category: BlockCategory
    var note: String
    /// True when a recurring occurrence has an override applied (changed/moved).
    var isException: Bool

    var id: String {
        switch source {
        case .single(let blockID): "single:\(blockID.uuidString)"
        case .recurring(let ruleID, let originalDate): "rule:\(ruleID.uuidString):\(originalDate.key)"
        }
    }

    var durationMinutes: Int { endMinutes - startMinutes }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title
    }

    var isRecurring: Bool { source.isRecurring }
}

/// Value snapshot describing an editable block's fields, independent of whether it
/// is a one-off block, a series, or a single occurrence.
struct BlockDraft: Hashable, Sendable {
    var title: String = ""
    var date: LocalDate
    var startMinutes: Int
    var endMinutes: Int
    var category: BlockCategory = .work
    var note: String = ""
    var weekdays: WeekdaySet = .none   // empty = no recurrence

    var isRecurring: Bool { !weekdays.isEmpty }
    var durationMinutes: Int { endMinutes - startMinutes }

    init(title: String = "", date: LocalDate, startMinutes: Int, endMinutes: Int,
         category: BlockCategory = .work, note: String = "", weekdays: WeekdaySet = .none) {
        self.title = title
        self.date = date
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.category = category
        self.note = note
        self.weekdays = weekdays
    }

    init(from occurrence: EventOccurrence, weekdays: WeekdaySet = .none) {
        self.init(title: occurrence.title, date: occurrence.date,
                  startMinutes: occurrence.startMinutes, endMinutes: occurrence.endMinutes,
                  category: occurrence.category, note: occurrence.note, weekdays: weekdays)
    }
}

/// Timeline constants shared across the app.
enum TimeRules {
    static let snapMinutes = 15
    static let minimumDuration = 15
    static let dayMinutes = 24 * 60

    static func snap(_ minutes: Int) -> Int {
        let s = Int((Double(minutes) / Double(snapMinutes)).rounded()) * snapMinutes
        return min(max(s, 0), dayMinutes)
    }

    static func snapDown(_ minutes: Int) -> Int {
        min(max((minutes / snapMinutes) * snapMinutes, 0), dayMinutes)
    }

    /// Clamps a start/end pair so that start < end, end ≤ 24:00, duration ≥ minimum.
    static func normalized(start: Int, end: Int) -> (start: Int, end: Int) {
        var s = min(max(start, 0), dayMinutes - minimumDuration)
        var e = min(max(end, s + minimumDuration), dayMinutes)
        if e - s < minimumDuration { s = max(0, e - minimumDuration) }
        if e > dayMinutes { e = dayMinutes; s = e - minimumDuration }
        return (s, e)
    }
}
