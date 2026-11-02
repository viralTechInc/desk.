import Testing
import Foundation
@testable import Desk

@Suite("RecurrenceEngine")
struct RecurrenceTests {
    let cal = TestSupport.calendar()
    let ruleID = UUID()

    func rule(weekdays: WeekdaySet = .weekdays, start: LocalDate = TestSupport.d(2026, 10, 5), end: LocalDate? = nil) -> RuleInput {
        RuleInput(id: ruleID, title: "Deep work", category: .work, note: "", startMinutes: 480, endMinutes: 720,
                  weekdays: weekdays, effectiveStart: start, effectiveEnd: end)
    }

    func expand(_ range: ClosedRange<LocalDate>, rules: [RuleInput], overrides: [OverrideInput] = [], singles: [SingleBlockInput] = []) -> [EventOccurrence] {
        RecurrenceEngine.occurrences(in: range, rules: rules, overrides: overrides, singles: singles, calendar: cal)
    }

    @Test func weeklyRuleAppearsOnLaterWeeks() {
        let week = TestSupport.d(2026, 11, 2)...TestSupport.d(2026, 11, 8)
        let occ = expand(week, rules: [rule()])
        #expect(occ.count == 5)
        #expect(occ.map(\.date) == (0..<5).map { cal.adding(days: $0, to: TestSupport.d(2026, 11, 2)) })
        #expect(occ.allSatisfy { $0.isRecurring && !$0.isException })
        let farFuture = TestSupport.d(2027, 6, 7)...TestSupport.d(2027, 6, 13)
        #expect(expand(farFuture, rules: [rule()]).count == 5)
    }

    @Test func effectiveRangeIsRespected() {
        let before = TestSupport.d(2026, 9, 28)...TestSupport.d(2026, 10, 4)
        #expect(expand(before, rules: [rule()]).isEmpty)
        let bounded = rule(end: TestSupport.d(2026, 11, 4))
        let week = TestSupport.d(2026, 11, 2)...TestSupport.d(2026, 11, 8)
        #expect(expand(week, rules: [bounded]).map(\.date.day) == [2, 3, 4])
    }

    @Test func cancelledOverrideRemovesOneOccurrence() {
        let week = TestSupport.d(2026, 11, 2)...TestSupport.d(2026, 11, 8)
        let cancel = OverrideInput(ruleID: ruleID, originalDate: TestSupport.d(2026, 11, 4), isCancelled: true,
                                   date: nil, title: nil, startMinutes: nil, endMinutes: nil, category: nil, note: nil)
        let occ = expand(week, rules: [rule()], overrides: [cancel])
        #expect(occ.count == 4)
        #expect(!occ.contains { $0.date.day == 4 })
    }

    @Test func partialOverrideFollowsSeriesForUnsetFields() {
        let week = TestSupport.d(2026, 11, 2)...TestSupport.d(2026, 11, 8)
        let shorten = OverrideInput(ruleID: ruleID, originalDate: TestSupport.d(2026, 11, 4), isCancelled: false,
                                    date: nil, title: nil, startMinutes: nil, endMinutes: 600, category: nil, note: nil)
        var r = rule()
        r.title = "Renamed series"
        let occ = expand(week, rules: [r], overrides: [shorten])
        let wed = occ.first { $0.date.day == 4 }!
        #expect(wed.endMinutes == 600)
        #expect(wed.startMinutes == 480)
        #expect(wed.title == "Renamed series")
        #expect(wed.isException)
    }

    @Test func movedOccurrenceShowsOnNewDateOnly() {
        let move = OverrideInput(ruleID: ruleID, originalDate: TestSupport.d(2026, 11, 4), isCancelled: false,
                                 date: TestSupport.d(2026, 11, 7), title: nil, startMinutes: 540, endMinutes: 780, category: nil, note: nil)
        let week = TestSupport.d(2026, 11, 2)...TestSupport.d(2026, 11, 8)
        let occ = expand(week, rules: [rule()], overrides: [move])
        #expect(occ.count == 5)
        #expect(!occ.contains { $0.date.day == 4 })
        let sat = occ.first { $0.date.day == 7 }!
        #expect(sat.startMinutes == 540)
        if case .recurring(_, let original) = sat.source { #expect(original == TestSupport.d(2026, 11, 4)) } else { Issue.record("expected recurring") }

        // Querying only the destination day still finds the moved occurrence.
        let satOnly = expand(TestSupport.d(2026, 11, 7)...TestSupport.d(2026, 11, 7), rules: [rule()], overrides: [move])
        #expect(satOnly.count == 1 && satOnly[0].date.day == 7)
        // Querying only the original day finds nothing.
        let wedOnly = expand(TestSupport.d(2026, 11, 4)...TestSupport.d(2026, 11, 4), rules: [rule()], overrides: [move])
        #expect(wedOnly.isEmpty)
    }

    @Test func orphanOverrideIsIgnored() {
        // Wednesday override but rule no longer includes Wednesday.
        let shorten = OverrideInput(ruleID: ruleID, originalDate: TestSupport.d(2026, 11, 4), isCancelled: false,
                                    date: nil, title: "X", startMinutes: nil, endMinutes: nil, category: nil, note: nil)
        let week = TestSupport.d(2026, 11, 2)...TestSupport.d(2026, 11, 8)
        let occ = expand(week, rules: [rule(weekdays: WeekdaySet([.monday, .friday]))], overrides: [shorten])
        #expect(occ.count == 2)
        #expect(!occ.contains { $0.title == "X" })
    }

    @Test func singlesAndRulesMergeSorted() {
        let single = SingleBlockInput(id: UUID(), date: TestSupport.d(2026, 11, 2), title: "Dentist", category: .admin,
                                      note: "", startMinutes: 420, endMinutes: 480)
        let day = TestSupport.d(2026, 11, 2)...TestSupport.d(2026, 11, 2)
        let occ = expand(day, rules: [rule()], singles: [single])
        #expect(occ.map(\.title) == ["Dentist", "Deep work"])
    }

    @Test func dstWeekExpandsSevenDays() {
        // The week containing the fall-back Sunday (Nov 1, 2026).
        let week = TestSupport.d(2026, 10, 26)...TestSupport.d(2026, 11, 1)
        let occ = expand(week, rules: [rule(weekdays: .everyDay)])
        #expect(occ.count == 7)
        #expect(Set(occ.map(\.date)).count == 7)
        let spring = TestSupport.d(2027, 3, 8)...TestSupport.d(2027, 3, 14)
        #expect(expand(spring, rules: [rule(weekdays: .everyDay)]).count == 7)
    }
}

@Suite("OverlapLayout")
struct OverlapLayoutTests {
    func occ(_ id: String, _ s: Int, _ e: Int) -> EventOccurrence {
        EventOccurrence(source: .single(blockID: UUID()), date: TestSupport.d(2026, 11, 2), title: id,
                        startMinutes: s, endMinutes: e, category: .work, note: "", isException: false)
    }

    @Test func nonOverlappingEventsGetFullWidth() {
        let laid = OverlapLayout.layout([occ("a", 480, 540), occ("b", 540, 600)])
        #expect(laid.allSatisfy { $0.columnCount == 1 })
    }

    @Test func overlappingEventsSplitColumns() {
        let laid = OverlapLayout.layout([occ("a", 480, 600), occ("b", 510, 570), occ("c", 600, 660)])
        let byTitle = Dictionary(uniqueKeysWithValues: laid.map { ($0.event.title, $0) })
        #expect(byTitle["a"]!.columnCount == 2 && byTitle["a"]!.column == 0)
        #expect(byTitle["b"]!.columnCount == 2 && byTitle["b"]!.column == 1)
        #expect(byTitle["c"]!.columnCount == 1)
    }

    @Test func threeWayOverlapAndReuse() {
        let laid = OverlapLayout.layout([occ("a", 480, 720), occ("b", 480, 540), occ("c", 540, 600), occ("d", 500, 560)])
        let byTitle = Dictionary(uniqueKeysWithValues: laid.map { ($0.event.title, $0) })
        #expect(byTitle["a"]!.columnCount == 3)
        #expect(byTitle["b"]!.column == 1)
        #expect(byTitle["d"]!.column == 2)
        #expect(byTitle["c"]!.column == 1) // reuses b's column after b ends
    }

    @Test func geometryMapsMinutesToPoints() {
        let g = TimelineGeometry(startHour: 6, endHour: 22, hourHeight: 64)
        #expect(g.y(forMinutes: 6 * 60) == 0)
        #expect(g.y(forMinutes: 7 * 60) == 64)
        #expect(g.minutes(forY: 96) == 7 * 60 + 30)
        #expect(g.snappedMinutes(forY: 100) == 7 * 60 + 30)
        #expect(g.totalHeight == CGFloat(1024))
        let late = occ("late", 23 * 60, 23 * 60 + 30)
        #expect(g.expanded(toInclude: [late]).endHour == 24)
        let early = occ("early", 4 * 60 + 30, 5 * 60)
        #expect(g.expanded(toInclude: [early]).startHour == 4)
    }
}
