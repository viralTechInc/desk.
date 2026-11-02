import SwiftUI

/// TOP PRIORITIES over a freeform BRAIN DUMP, on the writing surface.
struct NotebookPanel: View {
    @Environment(AppState.self) private var appState
    let editor: DayPageEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Top priorities")
                .padding(.bottom, 6)
            PriorityEditor(editor: editor)

            SectionLabel(text: "Brain dump")
                .padding(.top, 26)
                .padding(.bottom, 4)
            BrainDumpEditor(editor: editor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Freeform notes: a plain NSTextView with its own undo stack, a paper hint when empty.
struct BrainDumpEditor: View {
    @Environment(AppState.self) private var appState
    let editor: DayPageEditor

    var body: some View {
        ZStack(alignment: .topLeading) {
            if editor.brainDump.isEmpty {
                RuledPaper()
                    .padding(.top, 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Text("Write freely — thoughts, ideas, reminders. Nothing here becomes a task.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.top, 8)
                    .padding(.leading, 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            PlainTextView(
                text: Binding(get: { editor.brainDump }, set: { editor.brainDump = $0 }),
                focusToken: appState.focusRequest.target == .brainDump ? appState.focusRequest.token : 0)
                .accessibilityLabel("Brain dump")
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
