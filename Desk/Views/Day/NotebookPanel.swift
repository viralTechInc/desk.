import SwiftUI

/// TOP PRIORITIES over two freeform pages side by side: the day's BRAIN DUMP and the
/// WEEK BRAIN DUMP shared by every day of that week.
struct NotebookPanel: View {
    @Environment(AppState.self) private var appState
    let editor: DayPageEditor
    let weekEditor: WeekPageEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Top priorities")
                .padding(.bottom, 6)
            PriorityEditor(editor: editor)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        SectionLabel(text: "Brain dump")
                            .fixedSize()
                        Spacer(minLength: 0)
                        TaskCount(tasks: editor.tasks)
                        TaskSuggestionsButton(
                            notes: editor.brainDump,
                            tasks: Binding(get: { editor.tasks }, set: { editor.tasks = $0 }),
                            idPrefix: "task", answersMenuCommand: true)
                    }
                    .padding(.bottom, 4)
                    BrainDumpEditor(editor: editor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.trailing, Theme.padding)

                Hairline(vertical: true)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        SectionLabel(text: "Week brain dump")
                            .fixedSize()
                        Text(appState.calendar.weekRangeString(containing: editor.date))
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkFaint)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        TaskCount(tasks: weekEditor.tasks)
                        TaskSuggestionsButton(
                            notes: weekEditor.brainDump,
                            tasks: Binding(get: { weekEditor.tasks }, set: { weekEditor.tasks = $0 }),
                            idPrefix: "weekTask")
                    }
                    .padding(.bottom, 4)
                    WeekBrainDumpEditor(editor: weekEditor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.leading, Theme.padding)
            }
            .padding(.top, 26)
        }
        .padding(Theme.padding)
    }
}

struct PriorityEditor: View {
    @Environment(AppState.self) private var appState
    let editor: DayPageEditor
    @FocusState private var focusedRow: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(editor.priorities.indices, id: \.self) { index in
                PriorityRow(
                    number: index + 1,
                    text: Binding(
                        get: { editor.priorities.indices.contains(index) ? editor.priorities[index] : "" },
                        set: { editor.setPriority($0, at: index) }),
                    isFirst: index == 0,
                    focused: $focusedRow,
                    index: index,
                    onSubmit: {
                        if index == editor.priorities.count - 1 {
                            let newIndex = editor.insertPriority(after: index)
                            focusedRow = newIndex
                        } else {
                            focusedRow = index + 1
                        }
                    },
                    onDeleteEmpty: {
                        guard index > 0, editor.removePriorityIfEmpty(at: index) else { return false }
                        focusedRow = index - 1
                        return true
                    })
            }
        }
        .onChange(of: appState.focusRequest.token) {
            if appState.focusRequest.target == .firstPriority { focusedRow = 0 }
        }
    }
}

private struct PriorityRow: View {
    let number: Int
    @Binding var text: String
    let isFirst: Bool
    var focused: FocusState<Int?>.Binding
    let index: Int
    let onSubmit: () -> Void
    let onDeleteEmpty: () -> Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(Theme.inkFaint)
                .frame(width: 22, alignment: .trailing)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: isFirst ? Text("What matters most?").foregroundStyle(Theme.inkFaint) : nil)
                .textFieldStyle(.plain)
                .font(Theme.priority)
                .foregroundStyle(Theme.ink)
                .focused(focused, equals: index)
                .onSubmit(onSubmit)
                .onKeyPress(.delete, phases: .down) { _ in
                    text.isEmpty && onDeleteEmpty() ? .handled : .ignored
                }
                .accessibilityLabel("Priority \(number)")
                .accessibilityIdentifier("priority.\(number)")
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Hairline(color: Theme.ruledLine).padding(.leading, 32)
        }
    }
}

/// The day's task list above its freeform notes.
struct BrainDumpEditor: View {
    @Environment(AppState.self) private var appState
    let editor: DayPageEditor

    var body: some View {
        BrainDumpPage(
            tasks: Binding(get: { editor.tasks }, set: { editor.tasks = $0 }),
            idPrefix: "task",
            text: Binding(get: { editor.brainDump }, set: { editor.brainDump = $0 }),
            hint: "Write freely — thoughts, ideas, reminders. Tasks go in the list above.",
            focusToken: appState.focusRequest.target == .brainDump ? appState.focusRequest.token : 0,
            accessibilityLabel: "Brain dump")
    }
}

/// Tasks and notes for the whole week; the same list and text appear on every day of that week.
struct WeekBrainDumpEditor: View {
    let editor: WeekPageEditor

    var body: some View {
        BrainDumpPage(
            tasks: Binding(get: { editor.tasks }, set: { editor.tasks = $0 }),
            idPrefix: "weekTask",
            text: Binding(get: { editor.brainDump }, set: { editor.brainDump = $0 }),
            hint: "Loose ends, carry-overs and ideas for the whole week.",
            focusToken: 0,
            accessibilityLabel: "Week brain dump")
    }
}

/// One brain dump column: the task list on top (never more than about half the column),
/// freeform notes filling the rest.
struct BrainDumpPage: View {
    @Binding var tasks: [TaskItem]
    let idPrefix: String
    @Binding var text: String
    let hint: String
    let focusToken: Int
    let accessibilityLabel: String

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                CappedTaskList(tasks: $tasks, idPrefix: idPrefix, maxHeight: max(120, geo.size.height * 0.55))
                    .padding(.bottom, 8)
                NotesEditor(text: $text, hint: hint, focusToken: focusToken, accessibilityLabel: accessibilityLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Freeform notes: a plain NSTextView with its own undo stack, a paper hint when empty.
struct NotesEditor: View {
    @Binding var text: String
    let hint: String
    let focusToken: Int
    let accessibilityLabel: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                RuledPaper()
                    .padding(.top, 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Text(hint)
                    .font(Theme.body)
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.top, 8)
                    .padding(.leading, 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            PlainTextView(text: $text, focusToken: focusToken)
                .accessibilityLabel(accessibilityLabel)
        }
    }
}

/// Faint horizontal rules, like a blank notebook page.
struct RuledPaper: View {
    var lineSpacing: CGFloat = 26
    var body: some View {
        Canvas { ctx, size in
            var y = lineSpacing
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(Theme.ruledLine), lineWidth: 1)
                y += lineSpacing
            }
        }
    }
}
