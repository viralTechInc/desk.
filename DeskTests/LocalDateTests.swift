import Testing
import Foundation
@testable import Desk

@Suite("LocalDate & DeskCalendar")
struct LocalDateTests {
    let cal = TestSupport.calendar()

    @Test func keyRoundTrip() {
        let d = TestSupport.d(2026, 11, 2)
        #expect(d.key == 20261102)
        #expect(LocalDate(key: 20261102) == d)
        #expect(LocalDate(key: 20261399) == nil)
        #expect(LocalDate(isoString: "2026-11-02") == d)
        #expect(d.isoString == "2026-11-02")
    }

    @Test func yearBoundaryNavigation() {
        let dec31 = TestSupport.d(2026, 12, 31)
        #expect(cal.adding(days: 1, to: dec31) == TestSupport.d(2027, 1, 1))
        #expect(cal.adding(days: -1, to: TestSupport.d(2027, 1, 1)) == dec31)
        #expect(cal.adding(days: 1, to: TestSupport.d(2028, 2, 28)) == TestSupport.d(2028, 2, 29))
        #expect(cal.adding(days: 1, to: TestSupport.d(2027, 2, 28)) == TestSupport.d(2027, 3, 1))
    }

    @Test func dstTransitionsDoNotSkipOrRepeatDays() {
        // Toronto: DST ends 2026-11-01 (clocks back), starts 2027-03-14 (clocks forward).
        let oct31 = TestSupport.d(2026, 10, 31)
        #expect(cal.adding(days: 1, to: oct31) == TestSupport.d(2026, 11, 1))
        #expect(cal.adding(days: 2, to: oct31) == TestSupport.d(2026, 11, 2))
        #expect(cal.days(from: oct31, to: TestSupport.d(2026, 11, 2)) == 2)
        let mar13 = TestSupport.d(2027, 3, 13)
        #expect(cal.adding(days: 1, to: mar13) == TestSupport.d(2027, 3, 14))
        #expect(cal.adding(days: 2, to: mar13) == TestSupport.d(2027, 3, 15))
        #expect(cal.days(from: mar13, to: TestSupport.d(2027, 3, 15)) == 2)
        // A 25-hour day still maps 09:00 to 09:00.
        let nov1 = TestSupport.d(2026, 11, 1)
        let nine = cal.date(nov1, minutesFromMidnight: 9 * 60)
        #expect(cal.minutesFromMidnight(nine) == 9 * 60)
        #expect(cal.localDate(from: nine) == nov1)
    }

    @Test func weekdaysAndWeekStart() {
        let nov2 = TestSupport.d(2026, 11, 2) // a Monday
        #expect(cal.weekday(of: nov2) == .monday)
        #expect(cal.weekday(of: TestSupport.d(2026, 11, 1)) == .sunday)
        #expect(cal.startOfWeek(containing: TestSupport.d(2026, 11, 5)) == nov2)
        #expect(cal.startOfWeek(containing: TestSupport.d(2026, 11, 8)) == nov2) // Sunday belongs to Monday-start week
        let sundayFirst = TestSupport.calendar(firstWeekday: .sunday)
        #expect(sundayFirst.startOfWeek(containing: TestSupport.d(2026, 11, 8)) == TestSupport.d(2026, 11, 8))
        #expect(sundayFirst.startOfWeek(containing: TestSupport.d(2026, 11, 5)) == TestSupport.d(2026, 11, 1))
        let week = cal.weekDays(containing: TestSupport.d(2026, 12, 31))
        #expect(week.first == TestSupport.d(2026, 12, 28))
        #expect(week.last == TestSupport.d(2027, 1, 3))
    }

    @Test func weekdaySetMask() {
        var s = WeekdaySet.weekdays
        #expect(s.contains(.monday) && !s.contains(.sunday))
        s.toggle(.sunday)
        #expect(s.contains(.sunday))
        s.remove(.monday)
        #expect(!s.contains(.monday))
        #expect(WeekdaySet.everyDay.count == 7)
        #expect(WeekdaySet.weekdays.summary() == "Weekdays")
        #expect(WeekdaySet([.monday, .wednesday]).summary() == "Mon, Wed")
        #expect(Weekday.ordered(startingAt: .monday).first == .monday)
        #expect(Weekday.ordered(startingAt: .monday).last == .sunday)
    }

    @Test func timeParsing() {
        #expect(TimeFormat.parse("9") == 540)
        #expect(TimeFormat.parse("9:30") == 570)
        #expect(TimeFormat.parse("930") == 570)
        #expect(TimeFormat.parse("9:30 pm") == 1290)
        #expect(TimeFormat.parse("12 am") == 0)
        #expect(TimeFormat.parse("12pm") == 720)
        #expect(TimeFormat.parse("14h30") == 870)
        #expect(TimeFormat.parse("24:00") == 1440)
        #expect(TimeFormat.parse("25") == nil)
        #expect(TimeFormat.parse("abc") == nil)
    }

    @Test func snappingAndNormalization() {
        #expect(TimeRules.snap(7) == 0)
        #expect(TimeRules.snap(8) == 15)
        #expect(TimeRules.snap(1439) == 1440)
        let n = TimeRules.normalized(start: 600, end: 600)
        #expect(n.start == 600 && n.end == 615)
        let late = TimeRules.normalized(start: 1435, end: 1500)
        #expect(late.end == 1440 && late.start == 1425)
    }
}
