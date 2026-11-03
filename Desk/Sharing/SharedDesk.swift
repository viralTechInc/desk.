import Foundation
import SwiftUI

/// What one Desk writes into the shared folder: who it is, plus everything in their planner.
/// The payload is the ordinary backup document, so nothing new has to be kept in sync.
struct SharedDeskFile: Codable, Sendable {
    var app = "Desk"
    var format = 1
    /// Identifies the writing installation so a Desk never reads its own file back as a partner.
    var installID: String
    var name: String
    var updatedAt: Date
    var document: BackupDocument
    /// The writer's calendar events for the weeks around today (absent in files written
    /// before calendar sharing, or when the writer turned it off).
    var events: [SharedEvent]? = nil

    static let fileSuffix = ".desk.json"

    /// "Louis-David" → "louis-david.desk.json"; anything unprintable falls back to "desk".
    static func fileName(for name: String) -> String {
        var slug = ""
        for scalar in name.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) { slug.unicodeScalars.append(scalar) }
            else if !slug.hasSuffix("-") { slug.append("-") }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "desk" }
        return String(slug.prefix(40)) + fileSuffix
    }

    static func isSharedFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasSuffix(fileSuffix) && !name.hasPrefix(".")
    }
}

/// One day's slice of a calendar event as the writer's Mac saw it: just what the timeline
/// needs. The event itself stays in their calendar account and is never editable here.
struct SharedEvent: Codable, Sendable, Identifiable {
    var id: String
    var date: LocalDate
    var title: String
    var startMinutes: Int
    var endMinutes: Int
    var isAllDay: Bool
    var continuesFromPreviousDay: Bool
    var continuesIntoNextDay: Bool
    var calendarTitle: String
    var colorHex: String
    var location: String?
    var conferenceURL: String?
    var isBusy: Bool

    init(_ e: ExternalEvent) {
        id = e.id
        date = e.date
        title = e.title
        startMinutes = e.startMinutes
        endMinutes = e.endMinutes
        isAllDay = e.isAllDay
        continuesFromPreviousDay = e.continuesFromPreviousDay
        continuesIntoNextDay = e.continuesIntoNextDay
        calendarTitle = e.calendarTitle
        colorHex = e.color.sharedHex
        location = e.location
        conferenceURL = e.conference?.url.absoluteString
        isBusy = e.isBusy
    }
}

/// A partner's planner as last read from the shared folder. Everything derived from it is
/// read-only; the partner's own Desk is the only thing that ever changes the file.
struct PartnerDesk: Identifiable, Sendable {
    let id: String
    let name: String
    let updatedAt: Date
    let fileURL: URL
    let document: BackupDocument
    /// Their calendar events, when their Desk shares them.
    let sharedEvents: [SharedEvent]

    init(file: SharedDeskFile, url: URL) {
        id = file.installID
        name = file.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Partner" : file.name
        updatedAt = file.updatedAt
        fileURL = url
        document = file.document
        sharedEvents = file.events ?? []
    }

    var possessive: String { name.hasSuffix("s") ? "\(name)’" : "\(name)’s" }

    func page(for date: LocalDate) -> PageRecord? {
        document.pages.first { $0.date == date }
    }

    func week(for weekStart: LocalDate) -> WeekRecord? {
        document.weeks.first { $0.weekStart == weekStart }
    }

    /// The partner's blocks and routines expanded exactly as their own Desk would show them.
    func occurrences(in range: ClosedRange<LocalDate>, calendar: DeskCalendar) -> [EventOccurrence] {
        RecurrenceEngine.occurrences(
            in: range,
            rules: document.rules.map { r in
                RuleInput(id: r.id, title: r.title, category: r.category, note: r.note, startMinutes: r.startMinutes,
                          endMinutes: r.endMinutes, weekdays: r.weekdays, effectiveStart: r.effectiveStart, effectiveEnd: r.effectiveEnd)
            },
            overrides: document.overrides.map { o in
                OverrideInput(ruleID: o.ruleID, originalDate: o.originalDate, isCancelled: o.isCancelled, date: o.date,
                              title: o.title, startMinutes: o.startMinutes, endMinutes: o.endMinutes, category: o.category, note: o.note)
            },
            singles: document.blocks.map { b in
                SingleBlockInput(id: b.id, date: b.date, title: b.title, category: b.category, note: b.note,
                                 startMinutes: b.startMinutes, endMinutes: b.endMinutes)
            },
            calendar: calendar)
    }

    /// The partner's calendar events in the range, as read-only timeline entries in their
    /// calendar's colour. Shown on their page and, outlined, over my own schedule.
    func calendarEvents(in range: ClosedRange<LocalDate>, calendar: DeskCalendar) -> [ExternalEvent] {
        sharedEvents.filter { range.contains($0.date) }.map { ev in
            ExternalEvent(
                id: "partner:\(id):cal:\(ev.id)", eventIdentifier: ev.id, date: ev.date, title: ev.title,
                startMinutes: ev.startMinutes, endMinutes: ev.endMinutes, isAllDay: ev.isAllDay,
                continuesFromPreviousDay: ev.continuesFromPreviousDay, continuesIntoNextDay: ev.continuesIntoNextDay,
                calendarID: "partner:\(id):calendar", calendarTitle: "\(possessive) \(ev.calendarTitle)",
                sourceTitle: "Shared folder", color: Color(sharedHex: ev.colorHex), location: ev.location, isBusy: ev.isBusy,
                conference: ConferenceLinkDetector.detect(url: ev.conferenceURL.flatMap(URL.init(string:)), location: nil, notes: nil),
                origin: .partnerCalendar(name: name))
        }
    }

    /// The partner's blocks and calendar events as read-only entries laid over my own
    /// schedule, drawn like calendar events (outlined, never editable).
    func events(in range: ClosedRange<LocalDate>, calendar: DeskCalendar) -> [ExternalEvent] {
        let blocks = occurrences(in: range, calendar: calendar).map { occ in
            ExternalEvent(
                id: "partner:\(id):\(occ.id)", eventIdentifier: occ.id, date: occ.date, title: occ.displayTitle,
                startMinutes: occ.startMinutes, endMinutes: occ.endMinutes, isAllDay: false,
                continuesFromPreviousDay: false, continuesIntoNextDay: false,
                calendarID: "partner:\(id)", calendarTitle: possessive + " desk", sourceTitle: "Shared folder",
                color: occ.category.color, location: nil, isBusy: true, conference: nil,
                origin: .partner(name: name, note: occ.note))
        }
        return blocks + calendarEvents(in: range, calendar: calendar)
    }
}

/// Calendar colours cross the folder as "RRGGBB".
extension Color {
    var sharedHex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .systemGray
        return String(format: "%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }

    init(sharedHex hex: String) {
        if hex.count == 6, let value = UInt32(hex, radix: 16) {
            self = Color(nsColor: NSColor(hex: value))
        } else {
            self = Color(nsColor: .systemGray)
        }
    }
}
