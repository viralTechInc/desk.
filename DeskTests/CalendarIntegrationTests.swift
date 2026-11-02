import Testing
import Foundation
import SwiftUI
@testable import Desk

@Suite("External events & schedule merging")
struct CalendarIntegrationTests {
    let cal = TestSupport.calendar()

    func source(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false, calendarID: String = "c1") -> ExternalEventSplitter.Source {
        ExternalEventSplitter.Source(eventIdentifier: "ev-\(title)", title: title, start: start, end: end, isAllDay: allDay,
                                     calendarID: calendarID, calendarTitle: "Work", sourceTitle: "Google", color: .blue, location: nil)
    }

    func at(_ d: LocalDate, _ h: Int, _ m: Int = 0) -> Date { cal.date(d, minutesFromMidnight: h * 60 + m) }

    @Test func timedEventWithinOneDay() {
        let day = TestSupport.d(2026, 11, 3)
        let slices = ExternalEventSplitter.slices(of: source("Standup", at(day, 9, 30), at(day, 10)), in: day...day, calendar: cal)
        #expect(slices.count == 1)
        #expect(slices[0].startMinutes == 570 && slices[0].endMinutes == 600)
        #expect(!slices[0].isAllDay && !slices[0].continuesFromPreviousDay && !slices[0].continuesIntoNextDay)
    }

    @Test func multiDayEventIsSplitPerDayAndClippedToRange() {
        let mon = TestSupport.d(2026, 11, 2), wed = TestSupport.d(2026, 11, 4)
        let s = source("Offsite", at(mon, 14), at(wed, 11))
        let all = ExternalEventSplitter.slices(of: s, in: mon...wed, calendar: cal)
        #expect(all.map(\.date.day) == [2, 3, 4])
        #expect(all[0].startMinutes == 840 && all[0].endMinutes == 1440 && all[0].continuesIntoNextDay)
        #expect(all[1].startMinutes == 0 && all[1].endMinutes == 1440 && all[1].continuesFromPreviousDay && all[1].continuesIntoNextDay)
        #expect(all[2].startMinutes == 0 && all[2].endMinutes == 660 && all[2].continuesFromPreviousDay)
        let onlyTue = ExternalEventSplitter.slices(of: s, in: TestSupport.d(2026, 11, 3)...TestSupport.d(2026, 11, 3), calendar: cal)
        #expect(onlyTue.count == 1 && onlyTue[0].date.day == 3)
        #expect(Set(all.map(\.id)).count == 3, "per-day ids must be unique")
    }

    @Test func eventEndingAtMidnightStaysOnItsDay() {
        let day = TestSupport.d(2026, 11, 3)
        let next = cal.adding(days: 1, to: day)
        let slices = ExternalEventSplitter.slices(of: source("Late", at(day, 22), at(next, 0)), in: day...next, calendar: cal)
        #expect(slices.count == 1)
        #expect(slices[0].date == day && slices[0].endMinutes == 1440)
    }

    @Test func allDayEventsSpanWholeDays() {
        let day = TestSupport.d(2026, 11, 3)
        // EventKit all-day events end at midnight of the following day.
        let slices = ExternalEventSplitter.slices(of: source("Holiday", cal.startOfDay(day), cal.startOfDay(cal.adding(days: 2, to: day)), allDay: true),
                                                  in: day...cal.adding(days: 3, to: day), calendar: cal)
        #expect(slices.map(\.date.day) == [3, 4])
        #expect(slices.allSatisfy { $0.isAllDay && $0.startMinutes == 0 && $0.endMinutes == 1440 })
    }

    @Test func dstFallBackDayKeepsWallClockMinutes() {
        // 2026-11-01 in Toronto has 25 hours; a 9:00–10:00 meeting is still 9:00–10:00.
        let day = TestSupport.d(2026, 11, 1)
        let slices = ExternalEventSplitter.slices(of: source("Brunch", at(day, 9), at(day, 10)), in: day...day, calendar: cal)
        #expect(slices[0].startMinutes == 540 && slices[0].endMinutes == 600)
        let spring = TestSupport.d(2027, 3, 14)
        let s2 = ExternalEventSplitter.slices(of: source("Call", at(spring, 15), at(spring, 16)), in: spring...spring, calendar: cal)
        #expect(s2[0].startMinutes == 900 && s2[0].endMinutes == 960)
    }

    @Test func emptyTitleShowsBusy() {
        let day = TestSupport.d(2026, 11, 3)
        let slices = ExternalEventSplitter.slices(of: source("", at(day, 9), at(day, 10)), in: day...day, calendar: cal)
        #expect(slices[0].displayTitle == "Busy")
    }

    @Test func calendarFiltering() {
        let day = TestSupport.d(2026, 11, 3)
        let a = ExternalEventSplitter.slices(of: source("A", at(day, 9), at(day, 10), calendarID: "work"), in: day...day, calendar: cal)
        let b = ExternalEventSplitter.slices(of: source("B", at(day, 9), at(day, 10), calendarID: "home"), in: day...day, calendar: cal)
        let filtered = ScheduleMerger.filter(a + b, enabledCalendarIDs: ["home"])
        #expect(filtered.map(\.title) == ["B"])
        #expect(ScheduleMerger.filter(a + b, enabledCalendarIDs: []).isEmpty)
    }

    // MARK: Merging & layout

    func block(_ title: String, _ s: Int, _ e: Int, day: LocalDate = TestSupport.d(2026, 11, 3)) -> EventOccurrence {
        EventOccurrence(source: .single(blockID: UUID()), date: day, title: title, startMinutes: s, endMinutes: e,
                        category: .work, note: "", isException: false)
    }

    func ext(_ title: String, _ s: Int, _ e: Int, day: LocalDate = TestSupport.d(2026, 11, 3), allDay: Bool = false) -> ExternalEvent {
        ExternalEventSplitter.slices(of: source(title, at(day, s / 60, s % 60), at(day, e / 60, e % 60), allDay: allDay), in: day...day, calendar: cal)[0]
    }

    @Test func mergedEntriesSortAndExcludeAllDay() {
        let entries = ScheduleMerger.timedEntries(blocks: [block("Deep work", 480, 720)],
                                                  external: [ext("Standup", 540, 570), ext("Holiday", 0, 60, allDay: true)])
        #expect(entries.map(\.title) == ["Deep work", "Standup"])
        #expect(entries[1].isExternal)
    }

    @Test func mixedOverlapLaysOutSideBySide() {
        let entries = ScheduleMerger.timedEntries(blocks: [block("Deep work", 480, 720)], external: [ext("Standup", 540, 570)])
        let laid = OverlapLayout.layout(entries)
        #expect(laid.allSatisfy { $0.columnCount == 2 })
        #expect(laid.first { $0.item.title == "Deep work" }?.column == 0)
        #expect(laid.first { $0.item.title == "Standup" }?.column == 1)
    }

    @Test func menuBarPrefersMeetingOverOverlappingBlock() {
        let entries = ScheduleMerger.timedEntries(blocks: [block("Deep work", 480, 720)], external: [ext("Standup", 540, 570), ext("Review", 600, 660)])
        let s = ScheduleMerger.status(entries: entries, nowMinutes: 550)
        #expect(s.current?.title == "Standup")
        #expect(s.remainingMinutes == 20)
        #expect(s.upcoming.map(\.title) == ["Review"])
        #expect(s.minutesUntilNext == 50)
        #expect(ScheduleMerger.menuBarTitle(s) == "Standup · 20m")

        // After the meeting, the block is current again.
        let later = ScheduleMerger.status(entries: entries, nowMinutes: 580)
        #expect(later.current?.title == "Deep work")
        #expect(later.remainingMinutes == 140)
        #expect(ScheduleMerger.menuBarTitle(later) == "Deep work · 2h 20m")
    }

    @Test func menuBarUpcomingLimitedToThreeAndCountdown() {
        let entries = ScheduleMerger.timedEntries(blocks: [block("A", 600, 660), block("B", 700, 720), block("C", 800, 820), block("D", 900, 960)], external: [])
        let s = ScheduleMerger.status(entries: entries, nowMinutes: 500)
        #expect(s.current == nil)
        #expect(s.upcoming.map(\.title) == ["A", "B", "C"])
        #expect(ScheduleMerger.menuBarTitle(s) == "A in 1h 40m")
        let far = ScheduleMerger.status(entries: entries, nowMinutes: 300)
        #expect(ScheduleMerger.menuBarTitle(far) == nil, "no countdown more than two hours out")
        let empty = ScheduleMerger.status(entries: [], nowMinutes: 500)
        #expect(empty.current == nil && empty.upcoming.isEmpty && ScheduleMerger.menuBarTitle(empty) == nil)
    }
}
