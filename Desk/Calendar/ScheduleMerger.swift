import Foundation

/// Pure merging and "what's happening now" logic shared by the planner views and the
/// menu bar. Keeping it free of EventKit and SwiftUI makes it unit-testable.
enum ScheduleMerger {
    /// Timed entries for a date range, sorted; all-day external events are excluded here
    /// (they are rendered in their own strip).
    static func timedEntries(blocks: [EventOccurrence], external: [ExternalEvent]) -> [ScheduleEntry] {
        let b = blocks.map(ScheduleEntry.block)
        let e = external.filter { !$0.isAllDay }.map(ScheduleEntry.external)
        return (b + e).sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            if a.startMinutes != b.startMinutes { return a.startMinutes < b.startMinutes }
            if a.endMinutes != b.endMinutes { return a.endMinutes > b.endMinutes }
            return a.id < b.id
        }
    }

    static func allDay(_ external: [ExternalEvent]) -> [ExternalEvent] {
        external.filter(\.isAllDay).sorted { ($0.calendarTitle, $0.title) < ($1.calendarTitle, $1.title) }
    }

    /// Keeps only events whose calendar is enabled.
    static func filter(_ events: [ExternalEvent], enabledCalendarIDs: Set<String>) -> [ExternalEvent] {
        events.filter { enabledCalendarIDs.contains($0.calendarID) }
    }

    /// Menu bar status for a single day's timed entries at `nowMinutes`.
    struct Status: Equatable {
        var current: ScheduleEntry?
        var upcoming: [ScheduleEntry]
        var remainingMinutes: Int?
        var minutesUntilNext: Int?
    }

    /// Current item: an entry containing `now`. When a meeting (external event) overlaps a
    /// Desk block, the meeting wins — the block itself is untouched. Ties go to the entry
    /// that ends soonest. Upcoming: the next entries starting after `now`, limited to `limit`.
    static func status(entries: [ScheduleEntry], nowMinutes now: Int, limit: Int = 3) -> Status {
        let active = entries.filter { $0.startMinutes <= now && now < $0.endMinutes }
        let current = active.sorted { a, b in
            if a.isExternal != b.isExternal { return a.isExternal }
            if a.endMinutes != b.endMinutes { return a.endMinutes < b.endMinutes }
            return a.startMinutes > b.startMinutes
        }.first
        let upcoming = Array(entries.filter { $0.startMinutes > now }
            .sorted { a, b in
                if a.startMinutes != b.startMinutes { return a.startMinutes < b.startMinutes }
                if a.isExternal != b.isExternal { return a.isExternal }
                return a.endMinutes < b.endMinutes
            }
            .prefix(limit))
        return Status(current: current, upcoming: upcoming,
                      remainingMinutes: current.map { $0.endMinutes - now },
                      minutesUntilNext: upcoming.first.map { $0.startMinutes - now })
    }

    /// Short text for the menu bar itself: "Standup · 25m", "Deep work in 12m", or nil.
    static func menuBarTitle(_ s: Status) -> String? {
        if let c = s.current, let r = s.remainingMinutes {
            return "\(truncate(c.title)) · \(short(r))"
        }
        if let n = s.upcoming.first, let m = s.minutesUntilNext, m <= 120 {
            return "\(truncate(n.title)) in \(short(m))"
        }
        return nil
    }

    static func short(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(minutes, 0))m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private static func truncate(_ s: String, max: Int = 22) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
