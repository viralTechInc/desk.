import Foundation
import SwiftUI

/// Anything that occupies a span of minutes on one day of the timeline.
protocol TimelineItem: Identifiable, Hashable where ID == String {
    var startMinutes: Int { get }
    var endMinutes: Int { get }
}

extension EventOccurrence: TimelineItem {}

/// A calendar the system knows about, as shown in Settings → Calendars.
struct CalendarInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let sourceID: String
    let sourceTitle: String
    let sourceKind: String      // "iCloud", "Google", "Exchange", "On My Mac", …
    let color: Color
    let allowsModifications: Bool
}

/// One day's slice of a system calendar event. External events are read-only and are
/// never written to Desk's store; they are re-read from EventKit on demand.
struct ExternalEvent: TimelineItem, Sendable {
    let id: String
    let eventIdentifier: String
    let date: LocalDate
    let title: String
    let startMinutes: Int
    let endMinutes: Int
    let isAllDay: Bool
    /// True when the event continues from the previous day / into the next day.
    let continuesFromPreviousDay: Bool
    let continuesIntoNextDay: Bool
    let calendarID: String
    let calendarTitle: String
    let sourceTitle: String
    let color: Color
    let location: String?
    let isBusy: Bool
    /// Video-call link, when the event carries one (Google Meet, Zoom, Teams…).
    let conference: ConferenceLink?

    var durationMinutes: Int { endMinutes - startMinutes }

    /// Calendars that hide details still report the slot; show it as "Busy".
    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Busy" : t
    }
}

/// Converts a system event's absolute start/end into per-day timeline slices.
/// Pure so it can be tested without EventKit.
enum ExternalEventSplitter {
    struct Source {
        var eventIdentifier: String
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var calendarID: String
        var calendarTitle: String
        var sourceTitle: String
        var color: Color
        var location: String?
        var isBusy: Bool = true
        var url: URL? = nil
        var notes: String? = nil
    }

    static func slices(of event: Source, in range: ClosedRange<LocalDate>, calendar: DeskCalendar) -> [ExternalEvent] {
        guard event.end > event.start || event.isAllDay else { return [] }
        let firstDay = calendar.localDate(from: event.start)
        // An end exactly at midnight belongs to the previous day.
        let endAdjusted = event.isAllDay ? event.end.addingTimeInterval(-1) : event.end
        var lastDay = calendar.localDate(from: endAdjusted)
        if !event.isAllDay, calendar.minutesFromMidnight(event.end) == 0, lastDay > firstDay {
            lastDay = calendar.adding(days: -1, to: lastDay)
        }
        if lastDay < firstDay { lastDay = firstDay }
        let from = max(firstDay, range.lowerBound)
        let to = min(lastDay, range.upperBound)
        guard from <= to else { return [] }
        let conference = ConferenceLinkDetector.detect(url: event.url, location: event.location, notes: event.notes)

        return calendar.days(in: from...to).map { day in
            let startMinutes: Int
            let endMinutes: Int
            if event.isAllDay {
                startMinutes = 0; endMinutes = TimeRules.dayMinutes
            } else {
                startMinutes = day == firstDay ? calendar.minutesFromMidnight(event.start) : 0
                let rawEnd = day == lastDay ? calendar.minutesFromMidnight(event.end) : TimeRules.dayMinutes
                endMinutes = (day == lastDay && rawEnd == 0) ? TimeRules.dayMinutes : max(rawEnd, startMinutes + 1)
            }
            return ExternalEvent(
                id: "ext:\(event.eventIdentifier):\(Int(event.start.timeIntervalSince1970)):\(day.key)",
                eventIdentifier: event.eventIdentifier, date: day, title: event.title,
                startMinutes: startMinutes, endMinutes: endMinutes, isAllDay: event.isAllDay,
                continuesFromPreviousDay: day > firstDay, continuesIntoNextDay: day < lastDay,
                calendarID: event.calendarID, calendarTitle: event.calendarTitle, sourceTitle: event.sourceTitle,
                color: event.color, location: event.location, isBusy: event.isBusy, conference: conference)
        }
    }
}

/// A Desk block or an external calendar event, as rendered on the timeline.
enum ScheduleEntry: TimelineItem, Sendable {
    case block(EventOccurrence)
    case external(ExternalEvent)

    var id: String {
        switch self {
        case .block(let o): o.id
        case .external(let e): e.id
        }
    }
    var startMinutes: Int {
        switch self {
        case .block(let o): o.startMinutes
        case .external(let e): e.startMinutes
        }
    }
    var endMinutes: Int {
        switch self {
        case .block(let o): o.endMinutes
        case .external(let e): e.endMinutes
        }
    }
    var date: LocalDate {
        switch self {
        case .block(let o): o.date
        case .external(let e): e.date
        }
    }
    var title: String {
        switch self {
        case .block(let o): o.displayTitle
        case .external(let e): e.displayTitle
        }
    }
    var color: Color {
        switch self {
        case .block(let o): o.category.color
        case .external(let e): e.color
        }
    }
    var isExternal: Bool {
        if case .external = self { return true }
        return false
    }
    var subtitle: String? {
        switch self {
        case .block: nil
        case .external(let e): e.calendarTitle
        }
    }
    var conference: ConferenceLink? {
        switch self {
        case .block: nil
        case .external(let e): e.conference
        }
    }
}
