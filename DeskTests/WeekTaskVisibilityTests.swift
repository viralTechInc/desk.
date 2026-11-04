import Testing
import Foundation
@testable import Desk

@Suite("Week tasks seen from a day")
struct WeekTaskVisibilityTests {
    let cal = TestSupport.calendar()
    let monday = TestSupport.d(2026, 11, 2)
    let wednesday = TestSupport.d(2026, 11, 4)
    let thursday = TestSupport.d(2026, 11, 5)

    @Test func finishedTaskStaysOnlyOnItsDay() {
        var tasks: [TaskItem] = []
        let invoice = tasks.addTask("Send invoice")
        tasks.addTask("Book dentist")
        tasks.toggle(id: invoice.id, on: wednesday)

        #expect(tasks.visible(on: wednesday, calendar: cal).map(\.text) == ["Send invoice", "Book dentist"])
        #expect(tasks.visible(on: thursday, calendar: cal).map(\.text) == ["Book dentist"])
        #expect(tasks.visible(on: monday, calendar: cal).map(\.text) == ["Book dentist"])

        // Unchecking brings it back to every day.
        tasks.toggle(id: invoice.id, on: wednesday)
        #expect(tasks.visible(on: thursday, calendar: cal).count == 2)
        #expect(tasks[0].doneOn == nil && tasks[0].doneAt == nil)
    }

    @Test func olderTasksFallBackToDoneAt() {
        let noonWednesday = cal.date(wednesday, minutesFromMidnight: 12 * 60)
        let legacy = TaskItem(text: "Old", isDone: true, doneAt: noonWednesday)
        #expect(legacy.isVisible(on: wednesday, calendar: cal))
        #expect(!legacy.isVisible(on: thursday, calendar: cal))
        #expect(TaskItem(text: "No date", isDone: true).isVisible(on: thursday, calendar: cal))
    }

    @Test func editingADaysSliceKeepsHiddenTasks() {
        var week: [TaskItem] = []
        let a = week.addTask("A")
        week.addTask("B")
        week.addTask("C")
        week.toggle(id: a.id, on: monday)

        // Thursday's page shows B, C; the person adds D and removes C there.
        var slice = week.visible(on: thursday, calendar: cal)
        slice.addTask("D")
        slice.removeAll { $0.text == "C" }
        week = week.replacingVisible(slice, on: thursday, calendar: cal)

        #expect(week.map(\.text) == ["A", "B", "D"])
        #expect(week.visible(on: monday, calendar: cal).map(\.text) == ["A", "B", "D"])
    }

    @Test func doneOnSurvivesStorage() {
        var tasks: [TaskItem] = []
        let t = tasks.addTask("Ship")
        tasks.toggle(id: t.id, on: wednesday)
        let restored = [TaskItem].fromStorage(tasks.storageJSON)
        #expect(restored.first?.doneOn == wednesday.key)
        // Rows written before `doneOn` existed still decode.
        let old = #"[{"id":"\#(UUID().uuidString)","isDone":false,"text":"Legacy"}]"#
        #expect([TaskItem].fromStorage(old).first?.text == "Legacy")
    }
}
