import Testing
import Foundation
@testable import Desk

@Suite("Task suggestions")
struct TaskSuggestionsTests {
    @Test func tidyStripsListMarkersAndTrailingStop() {
        #expect(TaskSuggestions.tidy("- buy coffee.") == "Buy coffee")
        #expect(TaskSuggestions.tidy("• Call mom") == "Call mom")
        #expect(TaskSuggestions.tidy("[ ] send invoice") == "Send invoice")
        #expect(TaskSuggestions.tidy("[x] Send invoice") == "Send invoice")
        #expect(TaskSuggestions.tidy("2. Book dentist") == "Book dentist")
        #expect(TaskSuggestions.tidy("  appeler le garage  ") == "Appeler le garage")
        #expect(TaskSuggestions.tidy("Think it over...") == "Think it over...")
        // Numbers that are part of the task stay.
        #expect(TaskSuggestions.tidy("3 copies of the contract") == "3 copies of the contract")
    }

    @Test func cleanDropsBlanksDuplicatesAndExistingTasks() {
        let existing = [TaskItem(text: "Call mom"), TaskItem(text: "Email", isDone: true)]
        let raw = ["", "Call mom about Sunday dinner", "Buy coffee", "buy  coffee!", "Email Sarah the draft",
                   "Rebook dentist cleaning", "  "]
        #expect(TaskSuggestions.clean(raw, existing: existing)
                == ["Buy coffee", "Email Sarah the draft", "Rebook dentist cleaning"])
    }

    @Test func cleanIgnoresAccentsAndCase() {
        let existing = [TaskItem(text: "Envoyer le contrat à Marc")]
        #expect(TaskSuggestions.clean(["envoyer le contrat a marc", "Renouveler le passeport"], existing: existing)
                == ["Renouveler le passeport"])
    }

    @Test func cleanCapsTheCount() {
        let raw = (1...30).map { "Task number \($0)" }
        #expect(TaskSuggestions.clean(raw, existing: []).count == TaskSuggestions.maxCount)
    }

    @Test func overlapNeedsTwoWholeWords() {
        #expect(TaskSuggestions.overlaps("call mom", "call mom about sunday"))
        #expect(!TaskSuggestions.overlaps("email", "email sarah"))
        #expect(!TaskSuggestions.overlaps("call mo", "call mom"))
    }

    @Test func promptNotesCutsAtALineBreak() {
        let short = TaskSuggestions.promptNotes("  hello\n")
        #expect(short.text == "hello" && !short.wasTruncated)

        let long = String(repeating: "a line of notes\n", count: 100) // 1600 chars
        let cut = TaskSuggestions.promptNotes(long, limit: 500)
        #expect(cut.wasTruncated)
        #expect(cut.text.count <= 500)
        #expect(cut.text.hasSuffix("a line of notes"))
    }

    @Test func appendTasksAddsAfterDroppingBlankLine() {
        var tasks = [TaskItem(text: "Existing"), TaskItem(text: "")]
        tasks.appendTasks(["Buy coffee", " ", "Call garage"])
        #expect(tasks.map(\.text) == ["Existing", "Buy coffee", "Call garage"])
        #expect(tasks.allSatisfy { !$0.isDone })
    }
}
