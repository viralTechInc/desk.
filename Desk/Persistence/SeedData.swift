import Foundation

/// Opt-in demo content inspired by the owner's paper planner. Never loaded automatically.
enum SeedData {
    static func document(weekContaining date: LocalDate, calendar: DeskCalendar, now: Date = Date()) -> BackupDocument {
        let week = calendar.weekDays(containing: date)
        let monday = week.first { calendar.weekday(of: $0) == .monday } ?? week[0]
        let start = calendar.adding(weeks: -4, to: monday)

        func rule(_ title: String, _ cat: BlockCategory, _ s: Int, _ e: Int, _ days: WeekdaySet, note: String = "") -> RuleRecord {
            RuleRecord(id: UUID(), title: title, category: cat, note: note, startMinutes: s, endMinutes: e,
                       weekdays: days, effectiveStart: start, effectiveEnd: nil, createdAt: now, updatedAt: now)
        }
        let h = { (hour: Int, minute: Int) in hour * 60 + minute }

        let rules: [RuleRecord] = [
            rule("Morning routine", .personal, h(6, 0), h(7, 0), .everyDay),
            rule("Gym", .fitness, h(7, 0), h(8, 0), WeekdaySet([.monday, .wednesday, .friday])),
            rule("EVO deep work", .work, h(8, 0), h(12, 0), .weekdays, note: "Phone away. One problem at a time."),
            rule("Lunch · meditation", .personal, h(12, 0), h(13, 0), .weekdays),
            rule("EVO deep work", .work, h(13, 0), h(17, 0), .weekdays),
            rule("Ops / Dev", .admin, h(17, 0), h(18, 0), WeekdaySet([.tuesday, .thursday])),
            rule("Own projects", .ownProjects, h(19, 0), h(21, 0), WeekdaySet([.monday, .tuesday, .thursday])),
            rule("Family time", .relationships, h(10, 0), h(14, 0), WeekdaySet([.saturday])),
            rule("Date night", .relationships, h(19, 0), h(22, 0), WeekdaySet([.friday])),
            rule("Sauna", .fitness, h(17, 0), h(18, 0), WeekdaySet([.sunday])),
            rule("Sunday reset", .admin, h(19, 0), h(20, 30), WeekdaySet([.sunday]), note: "Plan the week. Clear the desk."),
        ]

        let wednesday = calendar.adding(days: 2, to: monday)
        let blocks: [BlockRecord] = [
            BlockRecord(id: UUID(), date: wednesday, title: "Dentist", startMinutes: h(15, 0), endMinutes: h(16, 0),
                        category: .admin, note: "", createdAt: now, updatedAt: now),
            BlockRecord(id: UUID(), date: calendar.adding(days: 3, to: monday), title: "Coffee with Sam",
                        startMinutes: h(12, 30), endMinutes: h(13, 30), category: .relationships, note: "",
                        createdAt: now, updatedAt: now),
        ]

        // One exception: Wednesday's afternoon deep work shortened for the dentist.
        let afternoon = rules[4]
        let overrides = [
            OverrideRecord(id: UUID(), ruleID: afternoon.id, originalDate: wednesday, isCancelled: false, date: nil,
                           title: nil, startMinutes: nil, endMinutes: h(15, 0), category: nil, note: nil, updatedAt: now),
        ]

        let pages = [
            PageRecord(date: date,
                       priorities: ["Ship the onboarding fix", "Call the accountant", "30 min: outline side project"],
                       brainDump: """
                       Keep the morning clear. No meetings before noon.

                       Ideas
                           - Weekly review template → one page, three questions
                           - Reread the chapter on deep work
                       Remember: book the car service before Friday.
                       """,
                       createdAt: now, updatedAt: now),
        ]
        let weeks = [
            WeekRecord(weekStart: calendar.startOfWeek(containing: date),
                       intentions: ["Protect the mornings", "Be home by six", ""], updatedAt: now),
        ]

        return BackupDocument(exportedAt: now, timeZone: calendar.timeZone.identifier, pages: pages, weeks: weeks,
                              blocks: blocks, rules: rules, overrides: overrides)
    }
}
