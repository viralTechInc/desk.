import Foundation
import SwiftData
@testable import Desk

enum TestSupport {
    /// Toronto observes DST; several tests cross its transitions on purpose.
    static let toronto = TimeZone(identifier: "America/Toronto")!

    static func calendar(firstWeekday: Weekday = .monday) -> DeskCalendar {
        DeskCalendar(timeZone: toronto, firstWeekday: firstWeekday)
    }

    @MainActor
    static func store(calendar: DeskCalendar = calendar()) throws -> PlannerStore {
        let container = try DeskSchema.container(inMemory: true)
        return PlannerStore(container: container, calendar: calendar, now: { Date(timeIntervalSince1970: 1_762_000_000) })
    }

    static func d(_ y: Int, _ m: Int, _ day: Int) -> LocalDate { LocalDate(year: y, month: m, day: day) }
}
