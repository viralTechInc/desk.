import Testing
import Foundation
@testable import Desk

@Suite("PlannerStore", .serialized)
@MainActor
struct StoreTests {
    let cal = TestSupport.calendar()
    let monday = TestSupport.d(2026, 11, 2)
    var week: ClosedRange<LocalDate> { monday...TestSupport.d(2026, 11, 8) }

    @Test func notebookRoundTripAndLazyCreation() throws {
        let store = try TestSupport.store()
        #expect(store.pageRecord(for: monday) == nil)
        let editor = store.editor(for: monday)
        #expect(editor.priorities.count == 3)
        editor.setPriority("Ship it", at: 0)
        editor.brainDump = "line one\n\tindented\n\n    four spaces"
        store.flush()
        let saved = try #require(store.pageRecord(for: monday))
        #expect(saved.priorities == ["Ship it"])
        #expect(saved.brainDump == "line one\n\tindented\n\n    four spaces")

        // Reopen through a fresh store on the same container.
        let reopened = PlannerStore(container: store.container, calendar: cal)
        let e2 = reopened.editor(for: monday)
        #expect(e2.priorities == ["Ship it", "", ""])
        #expect(e2.brainDump == saved.brainDump)
    }

    @Test func blankPagesArePruned() throws {
        let store = try TestSupport.store()
        let editor = store.editor(for: monday)
        editor.brainDump = "x"
        store.flush()
        #expect(store.pageRecord(for: monday) != nil)
        editor.brainDump = ""
        store.flush()
        #expect(store.pageRecord(for: monday) == nil)
    }

    @Test func prioritiesGrowAndShrink() throws {
        let store = try TestSupport.store()
        let e = store.editor(for: monday)
        e.setPriority("a", at: 2)
        let idx = e.insertPriority(after: 2)
        #expect(idx == 3 && e.priorities.count == 4)
        e.setPriority("b", at: 3)
        store.flush()
        #expect(store.pageRecord(for: monday)?.priorities == ["", "", "a", "b"])
        #expect(e.removePriorityIfEmpty(at: 3) == false) // not empty
        e.setPriority("", at: 3)
        #expect(e.removePriorityIfEmpty(at: 3) == true)
        #expect(e.priorities.count == 3)
        #expect(e.removePriorityIfEmpty(at: 1) == false) // never below minimum
    }

    @Test func createEditMoveDeleteSingleBlockWithUndo() throws {
        let store = try TestSupport.store()
        let created = try #require(store.createBlock(BlockDraft(title: "Dentist", date: monday, startMinutes: 900, endMinutes: 960, category: .admin)))
        #expect(store.occurrences(on: monday).count == 1)

        store.move(created, toDate: cal.adding(days: 1, to: monday), startMinutes: 600, scope: .thisOccurrence)
        #expect(store.occurrences(on: monday).isEmpty)
        let moved = try #require(store.occurrences(on: cal.adding(days: 1, to: monday)).first)
        #expect(moved.startMinutes == 600 && moved.endMinutes == 660)

        store.resize(moved, endMinutes: 700, scope: .thisOccurrence)
        #expect(store.occurrences(in: week).first?.endMinutes == 700) // exact values are kept; snapping is a UI concern
        store.undoManager.undo()
        #expect(store.occurrences(in: week).first?.endMinutes == 660)
        store.undoManager.redo()
        #expect(store.occurrences(in: week).first?.endMinutes == 700)

        store.delete(moved, scope: .thisOccurrence)
        #expect(store.occurrences(in: week).isEmpty)
        store.undoManager.undo()
        #expect(store.occurrences(in: week).count == 1)
        store.undoManager.undo() // undo resize
        store.undoManager.undo() // undo move
        #expect(store.occurrences(on: monday).first?.startMinutes == 900)
        store.undoManager.undo() // undo create
        #expect(store.occurrences(in: week).isEmpty)
    }

    @Test func recurringSeriesAndThisOccurrenceEdits() throws {
        let store = try TestSupport.store()
        let draft = BlockDraft(title: "Gym", date: monday, startMinutes: 420, endMinutes: 480, category: .fitness,
                               weekdays: WeekdaySet([.monday, .wednesday, .friday]))
        let first = try #require(store.createBlock(draft))
        #expect(first.isRecurring)
        #expect(store.occurrences(in: week).count == 3)
        let nextWeek = cal.adding(weeks: 1, to: monday)...cal.adding(weeks: 1, to: TestSupport.d(2026, 11, 8))
        #expect(store.occurrences(in: nextWeek).count == 3)

        // Edit one occurrence: Wednesday moves to 8:00.
        let wed = try #require(store.occurrences(in: week).first { $0.date.day == 4 })
        store.move(wed, toDate: wed.date, startMinutes: 480, scope: .thisOccurrence)
        let wed2 = try #require(store.occurrences(in: week).first { $0.date.day == 4 })
        #expect(wed2.startMinutes == 480 && wed2.isException)
        #expect(store.occurrences(in: week).filter { $0.startMinutes == 420 }.count == 2)
        #expect(store.occurrences(in: nextWeek).allSatisfy { $0.startMinutes == 420 })

        // Edit series title via Friday: Wednesday keeps its time but gets the new title.
        let fri = try #require(store.occurrences(in: week).first { $0.date.day == 6 })
        var d = BlockDraft(from: fri, weekdays: store.currentWeekdays(for: fri))
        d.title = "Strength"
        store.update(fri, with: d, scope: .entireSeries)
        let all = store.occurrences(in: week)
        #expect(all.allSatisfy { $0.title == "Strength" })
        #expect(all.first { $0.date.day == 4 }?.startMinutes == 480)

        // Series time change via Monday: Wednesday's explicit time override survives.
        let mon = try #require(store.occurrences(in: week).first { $0.date.day == 2 })
        store.move(mon, toDate: mon.date, startMinutes: 360, scope: .entireSeries)
        let after = store.occurrences(in: week)
        #expect(after.first { $0.date.day == 2 }?.startMinutes == 360)
        #expect(after.first { $0.date.day == 6 }?.startMinutes == 360)
        #expect(after.first { $0.date.day == 4 }?.startMinutes == 480)

        // Series edit through the overridden Wednesday clears its time override.
        let wed3 = try #require(store.occurrences(in: week).first { $0.date.day == 4 })
        store.move(wed3, toDate: wed3.date, startMinutes: 300, scope: .entireSeries)
        let after2 = store.occurrences(in: week)
        #expect(after2.allSatisfy { $0.startMinutes == 300 })
        #expect(after2.allSatisfy { !$0.isException })

        // Undo the whole chain back to creation.
        store.undoManager.undo()
        #expect(store.occurrences(in: week).first { $0.date.day == 4 }?.startMinutes == 480)
        store.undoManager.undo(); store.undoManager.undo(); store.undoManager.undo()
        #expect(store.occurrences(in: week).allSatisfy { $0.title == "Gym" && $0.startMinutes == 420 })
    }

    @Test func seriesMoveAcrossDaysRotatesWeekdays() throws {
        let store = try TestSupport.store()
        let draft = BlockDraft(title: "Gym", date: monday, startMinutes: 420, endMinutes: 480, category: .fitness,
                               weekdays: WeekdaySet([.monday, .wednesday]))
        store.createBlock(draft)
        let mon = try #require(store.occurrences(on: monday).first)
        store.move(mon, toDate: cal.adding(days: 1, to: monday), startMinutes: 420, scope: .entireSeries)
        let days = store.occurrences(in: week).map(\.date.day)
        #expect(days == [3, 5]) // Tue, Thu
        if case .recurring(let rid, _) = mon.source {
            #expect(store.rule(withID: rid)?.weekdays == WeekdaySet([.tuesday, .thursday]))
        }
    }

    @Test func deleteOccurrenceVersusSeries() throws {
        let store = try TestSupport.store()
        store.createBlock(BlockDraft(title: "Routine", date: monday, startMinutes: 360, endMinutes: 420, category: .personal, weekdays: .everyDay))
        let tue = try #require(store.occurrences(in: week).first { $0.date.day == 3 })
        store.delete(tue, scope: .thisOccurrence)
        #expect(store.occurrences(in: week).count == 6)
        store.undoManager.undo()
        #expect(store.occurrences(in: week).count == 7)
        store.delete(tue, scope: .entireSeries)
        #expect(store.occurrences(in: week).isEmpty)
        store.undoManager.undo()
        #expect(store.occurrences(in: week).count == 7)
    }

    @Test func stopRepeatingConvertsToSingle() throws {
        let store = try TestSupport.store()
        store.createBlock(BlockDraft(title: "Routine", date: monday, startMinutes: 360, endMinutes: 420, category: .personal, weekdays: .everyDay))
        let wed = try #require(store.occurrences(in: week).first { $0.date.day == 4 })
        var d = BlockDraft(from: wed, weekdays: .everyDay)
        d.weekdays = .none
        store.update(wed, with: d, scope: .entireSeries)
        let remaining = store.occurrences(in: week)
        #expect(remaining.count == 1 && remaining[0].date.day == 4 && !remaining[0].isRecurring)
    }

    @Test func promoteSingleToRoutineAndPruneOrphans() throws {
        let store = try TestSupport.store()
        let single = try #require(store.createBlock(BlockDraft(title: "Walk", date: monday, startMinutes: 1080, endMinutes: 1140, category: .personal)))
        var d = BlockDraft(from: single)
        d.weekdays = WeekdaySet([.monday, .tuesday])
        store.update(single, with: d, scope: .thisOccurrence)
        #expect(store.occurrences(in: week).count == 2)
        #expect(store.occurrences(in: week).allSatisfy { $0.isRecurring })

        // Override Tuesday, then remove Tuesday from the series → override is pruned, Tuesday gone.
        let tue = try #require(store.occurrences(in: week).first { $0.date.day == 3 })
        store.resize(tue, endMinutes: 1200, scope: .thisOccurrence)
        let mon = try #require(store.occurrences(in: week).first { $0.date.day == 2 })
        var d2 = BlockDraft(from: mon, weekdays: store.currentWeekdays(for: mon))
        d2.weekdays = WeekdaySet([.monday])
        store.update(mon, with: d2, scope: .entireSeries)
        #expect(store.occurrences(in: week).map(\.date.day) == [2])
        // Re-adding Tuesday does not resurrect the pruned override.
        d2.weekdays = WeekdaySet([.monday, .tuesday])
        let mon2 = try #require(store.occurrences(in: week).first)
        store.update(mon2, with: d2, scope: .entireSeries)
        #expect(store.occurrences(in: week).first { $0.date.day == 3 }?.endMinutes == 1140)
    }

    @Test func duplicateAndOverlapVisible() throws {
        let store = try TestSupport.store()
        let a = try #require(store.createBlock(BlockDraft(title: "A", date: monday, startMinutes: 540, endMinutes: 660)))
        store.duplicate(a)
        let occ = store.occurrences(on: monday)
        #expect(occ.count == 2)
        let laid = OverlapLayout.layout(occ)
        #expect(laid.allSatisfy { $0.columnCount == 2 })
    }

    @Test func backupRoundTrip() throws {
        let store = try TestSupport.store()
        let doc = SeedData.document(weekContaining: monday, calendar: cal)
        store.insert(doc)
        store.flush()
        let data = try store.exportBackup()
        let decoded = try PlannerStore.decodeBackup(data)
        #expect(decoded.rules.count == doc.rules.count)
        #expect(decoded.pages.first?.brainDump == doc.pages.first?.brainDump)

        let fresh = try TestSupport.store()
        try fresh.importBackup(decoded)
        #expect(fresh.occurrences(in: week).count == store.occurrences(in: week).count)
        #expect(fresh.pageRecord(for: monday)?.priorities == doc.pages[0].priorities)
        // The seed's shortened Wednesday afternoon is preserved.
        let wedAfternoon = fresh.occurrences(on: TestSupport.d(2026, 11, 4)).first { $0.title == "EVO deep work" && $0.startMinutes == 780 }
        #expect(wedAfternoon?.endMinutes == 900)
        #expect(wedAfternoon?.isException == true)
    }

    @Test func weekBrainDumpPersistsAndSurvivesBackup() throws {
        let store = try TestSupport.store()
        let editor = store.weekEditor(for: monday)
        editor.brainDump = "Call the accountant before Friday"
        store.flush()
        #expect(store.weekRecord(for: monday)?.brainDump == "Call the accountant before Friday")

        let data = try store.exportBackup()
        let fresh = try TestSupport.store()
        try fresh.importBackup(try PlannerStore.decodeBackup(data))
        #expect(fresh.weekEditor(for: monday).brainDump == "Call the accountant before Friday")

        // Backups from before the field existed still decode.
        let legacy = Data(#"{"weekStart":"2026-11-02","intentions":["Rest"],"updatedAt":"2026-11-02T12:00:00Z"}"#.utf8)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(WeekRecord.self, from: legacy)
        #expect(record.brainDump == "" && record.intentions == ["Rest"])
    }

    @Test func taskListsPersistToggleAndPrune() throws {
        let store = try TestSupport.store()
        let editor = store.editor(for: monday)
        let call = editor.tasks.addTask("Call mom")
        editor.tasks.addTask("Pay rent")
        editor.tasks.addTask("")                       // a line still being typed is not stored
        store.flush()
        let saved = try #require(store.pageRecord(for: monday))
        #expect(saved.tasks.map(\.text) == ["Call mom", "Pay rent"])
        #expect(saved.tasks.allSatisfy { !$0.isDone })

        editor.tasks.toggle(id: call.id)
        store.flush()
        #expect(store.pageRecord(for: monday)?.tasks.first?.isDone == true)
        #expect(store.pageRecord(for: monday)?.tasks.first?.doneAt != nil)

        // Reopen through a fresh store on the same container: order, state and IDs survive.
        let reopened = PlannerStore(container: store.container, calendar: cal)
        let e2 = reopened.editor(for: monday)
        #expect(e2.tasks.map(\.id) == [call.id, editor.tasks[1].id])
        #expect(e2.tasks.doneCount == 1)

        // Removing every task leaves a blank page, which is pruned.
        e2.tasks.remove(id: call.id)
        e2.tasks.remove(id: e2.tasks[0].id)
        reopened.flush()
        #expect(reopened.pageRecord(for: monday) == nil)

        // Week lists work the same way and ride along in backups.
        let week = store.weekEditor(for: monday)
        week.tasks.addTask("Renew passport")
        store.flush()
        let data = try store.exportBackup()
        let fresh = try TestSupport.store()
        try fresh.importBackup(try PlannerStore.decodeBackup(data))
        #expect(fresh.weekEditor(for: monday).tasks.map(\.text) == ["Renew passport"])

        // Pages written before task lists existed still decode.
        let legacy = Data(#"{"date":"2026-11-02","priorities":[],"brainDump":"x","createdAt":"2026-11-02T12:00:00Z","updatedAt":"2026-11-02T12:00:00Z"}"#.utf8)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(PageRecord.self, from: legacy).tasks.isEmpty)
    }

    @Test func removeDemoDataLeavesUserContent() throws {
        let store = try TestSupport.store()
        store.createBlock(BlockDraft(title: "Untitled", date: monday, startMinutes: 495, endMinutes: 555))
        store.insert(SeedData.document(weekContaining: monday, calendar: cal))
        store.afterBulkChange()
        // The user edits one demo routine; that one must survive as theirs.
        let gym = store.occurrences(on: monday).first { $0.title == "Gym" }!
        store.update(gym, with: BlockDraft(title: "Gym", date: monday, startMinutes: 420, endMinutes: 510, category: .fitness, weekdays: WeekdaySet([.monday, .wednesday, .friday])), scope: .entireSeries)
        let before = store.occurrences(in: week).count

        let removed = store.removeDemoData(weekContaining: monday)
        #expect(removed > 0)
        let left = store.occurrences(in: week)
        #expect(left.count < before)
        #expect(left.contains { $0.title == "Untitled" && $0.startMinutes == 495 })
        #expect(left.contains { $0.title == "Gym" && $0.endMinutes == 510 })
        #expect(!left.contains { $0.title == "Morning routine" || $0.title == "Dentist" })
        #expect(store.pageRecord(for: monday) == nil)
        #expect(store.removeDemoData(weekContaining: monday) == 0)
    }

    @Test func dayAndWeekShareOneSource() throws {
        let store = try TestSupport.store()
        store.createBlock(BlockDraft(title: "Shared", date: TestSupport.d(2026, 11, 5), startMinutes: 600, endMinutes: 660))
        let fromWeek = store.occurrences(in: week).first { $0.title == "Shared" }
        let fromDay = store.occurrences(on: TestSupport.d(2026, 11, 5)).first
        #expect(fromWeek == fromDay)
    }
    @Test func unfinishedTasksRollOverToToday() throws {
        let store = try TestSupport.store()
        let tuesday = TestSupport.d(2026, 11, 3)
        let wednesday = TestSupport.d(2026, 11, 4)

        let mon = store.editor(for: monday)
        let rent = mon.tasks.addTask("Pay rent")
        mon.tasks.addTask("Call mom")
        mon.tasks.toggle(id: rent.id, on: monday)
        store.editor(for: tuesday).tasks.addTask("Book dentist")
        let wed = store.editor(for: wednesday)
        wed.tasks.addTask("Today's own")
        store.editor(for: TestSupport.d(2026, 11, 6)).tasks.addTask("Friday, later")   // future: untouched
        store.flush()

        #expect(store.rollOverTasks(into: wednesday) == 2)
        store.flush()
        #expect(wed.tasks.map(\.text) == ["Call mom", "Book dentist", "Today's own"])
        #expect(store.pageRecord(for: monday)?.tasks.map(\.text) == ["Pay rent"])   // done stays on its day
        #expect(store.pageRecord(for: tuesday) == nil)                               // nothing left: page pruned
        #expect(store.pageRecord(for: TestSupport.d(2026, 11, 6))?.tasks.map(\.text) == ["Friday, later"])

        // Running again (another launch the same day) moves nothing and duplicates nothing.
        #expect(store.rollOverTasks(into: wednesday) == 0)
        let reopened = PlannerStore(container: store.container, calendar: cal)
        #expect(reopened.editor(for: wednesday).tasks.count == 3)
    }
}
