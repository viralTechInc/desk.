import Foundation

/// Plain-value inputs for recurrence expansion. The persistence layer maps its models
/// to these so the engine is a pure, fully testable function.
struct RuleInput: Hashable, Sendable {
    var id: UUID
    var title: String
    var category: BlockCategory
    var note: String
    var startMinutes: Int
    var endMinutes: Int
    var weekdays: WeekdaySet
    var effectiveStart: LocalDate
    var effectiveEnd: LocalDate?
}

struct OverrideInput: Hashable, Sendable {
    var ruleID: UUID
    var originalDate: LocalDate
    var isCancelled: Bool
    var date: LocalDate?
    var title: String?
    var startMinutes: Int?
    var endMinutes: Int?
    var category: BlockCategory?
    var note: String?
}

struct SingleBlockInput: Hashable, Sendable {
    var id: UUID
    var date: LocalDate
    var title: String
    var category: BlockCategory
    var note: String
    var startMinutes: Int
    var endMinutes: Int
}

/// Expands rules + overrides + single blocks into concrete occurrences for a date range.
///
/// Semantics (covered by tests):
/// - A rule produces an occurrence on every date in its weekday set, from `effectiveStart`
///   through `effectiveEnd` inclusive (open-ended when nil).
/// - An override keyed by (rule, originalDate) replaces that generated occurrence. If it is
///   cancelled the occurrence disappears. Otherwise only the fields the override sets are
///   changed; unset fields follow the series, so later edits to the series still flow into
///   partially-overridden occurrences.
/// - A moved occurrence (override with a different `date`) is displayed on its new date,
///   even if the new date is outside the rule's weekday set or effective range.
/// - An override whose original date no longer matches the rule (weekday removed or date
///   outside effective range) is ignored; the store deletes such orphans when a series edits.
enum RecurrenceEngine {
    static func occurrences(
        in range: ClosedRange<LocalDate>,
        rules: [RuleInput],
        overrides: [OverrideInput],
        singles: [SingleBlockInput],
        calendar: DeskCalendar
    ) -> [EventOccurrence] {
        var result: [EventOccurrence] = []
        result.reserveCapacity(singles.count + rules.count * 7)

        for s in singles where range.contains(s.date) {
            result.append(EventOccurrence(
                source: .single(blockID: s.id), date: s.date, title: s.title,
                startMinutes: s.startMinutes, endMinutes: s.endMinutes,
                category: s.category, note: s.note, isException: false))
        }

        let overridesByKey: [OverrideKey: OverrideInput] = Dictionary(
            overrides.map { (OverrideKey(ruleID: $0.ruleID, date: $0.originalDate), $0) },
            uniquingKeysWith: { first, _ in first })

        let rulesByID = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let days = calendar.days(in: range)

        for rule in rules {
            guard !rule.weekdays.isEmpty, rule.endMinutes > rule.startMinutes else { continue }
            for day in days {
                guard rule.generates(on: day, calendar: calendar) else { continue }
                if let o = overridesByKey[OverrideKey(ruleID: rule.id, date: day)] {
                    if o.isCancelled { continue }
                    let occ = apply(o, to: rule, originalDate: day)
                    // Moved out of the range → it will be picked up by the second pass only
                    // if its new date is in range; skip here when it isn't.
                    guard range.contains(occ.date) else { continue }
                    result.append(occ)
                } else {
                    result.append(EventOccurrence(
                        source: .recurring(ruleID: rule.id, originalDate: day), date: day,
                        title: rule.title, startMinutes: rule.startMinutes, endMinutes: rule.endMinutes,
                        category: rule.category, note: rule.note, isException: false))
                }
            }
        }

        // Second pass: overrides moved INTO the range from an original date outside it.
        for o in overrides where !o.isCancelled {
            guard let moved = o.date, range.contains(moved), !range.contains(o.originalDate),
                  let rule = rulesByID[o.ruleID],
                  rule.generates(on: o.originalDate, calendar: calendar) else { continue }
            result.append(apply(o, to: rule, originalDate: o.originalDate))
        }

        result.sort { a, b in
            if a.date != b.date { return a.date < b.date }
            if a.startMinutes != b.startMinutes { return a.startMinutes < b.startMinutes }
            if a.endMinutes != b.endMinutes { return a.endMinutes > b.endMinutes }
            return a.id < b.id
        }
        return result
    }

    private struct OverrideKey: Hashable {
        let ruleID: UUID
        let date: LocalDate
    }

    static func apply(_ o: OverrideInput, to rule: RuleInput, originalDate: LocalDate) -> EventOccurrence {
        EventOccurrence(
            source: .recurring(ruleID: rule.id, originalDate: originalDate),
            date: o.date ?? originalDate,
            title: o.title ?? rule.title,
            startMinutes: o.startMinutes ?? rule.startMinutes,
            endMinutes: o.endMinutes ?? rule.endMinutes,
            category: o.category ?? rule.category,
            note: o.note ?? rule.note,
            isException: true)
    }
}

extension RuleInput {
    /// Whether the series itself (ignoring overrides) produces an occurrence on `day`.
    func generates(on day: LocalDate, calendar: DeskCalendar) -> Bool {
        guard day >= effectiveStart else { return false }
        if let end = effectiveEnd, day > end { return false }
        return weekdays.contains(calendar.weekday(of: day))
    }
}
