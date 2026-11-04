import SwiftUI
import AppKit

/// A brain dump's task list: a check circle per line, inline editing, and an always-present
/// "Add a task" line at the bottom. Return on a task starts a new one below it; Backspace on an
/// empty task removes it; done tasks stay where they are, struck through.
struct TaskListEditor: View {
    @Binding var tasks: [TaskItem]
    /// Accessibility identifier prefix ("task" / "weekTask").
    let idPrefix: String
    /// The page's day, recorded on tasks checked off here.
    let day: LocalDate

    enum Focus: Hashable {
        case task(UUID)
        case newTask
    }

    @FocusState private var focus: Focus?
    @State private var draft = ""
    @State private var keyMonitor = KeyMonitor()

    /// Scroll anchor for the "Add a task" line.
    static let addRowID = "taskList.addRow"

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                TaskRow(
                    task: task,
                    text: Binding(
                        get: { tasks.first { $0.id == task.id }?.text ?? "" },
                        set: { tasks.setText($0, id: task.id) }),
                    focus: $focus,
                    identifier: "\(idPrefix).\(index + 1)",
                    onToggle: {
                        withAnimation(.spring(duration: 0.28, bounce: 0.25)) {
                            tasks.toggle(id: task.id, on: day)
                            tasks.pruneBlank(except: focusedTaskID)
                        }
                    },
                    onSubmit: {
                        tasks.pruneBlank(except: task.id)
                        let new = tasks.addTask("", after: task.id)
                        focus = .task(new.id)
                    },
                    onDeleteEmpty: { removeIfEmpty(task.id) },
                    onRemove: {
                        withAnimation(.easeOut(duration: 0.15)) { tasks.remove(id: task.id) }
                    })
                .id(task.id)
            }

            NewTaskRow(draft: $draft, focus: $focus, identifier: "\(idPrefix).add") {
                let text = draft.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    tasks.pruneBlank()
                    tasks.addTask(text)
                }
                draft = ""
                focus = .newTask
            }
            .id(Self.addRowID)
        }
        .accessibilityElement(children: .contain)
        .onChange(of: focus) { _, newValue in
            // A line left blank disappears once the cursor is somewhere else.
            if case .task(let id)? = newValue { tasks.pruneBlank(except: id) } else { tasks.pruneBlank() }
        }
        // Backspace on an empty line: the field editor swallows the key before SwiftUI's
        // `onKeyPress` sees it, so watch the event stream directly (as the letter shortcuts do).
        .onAppear {
            keyMonitor.install { [self] in
                guard let id = focusedTaskID else { return false }
                return removeIfEmpty(id)
            }
        }
        .onDisappear { keyMonitor.remove() }
    }

    private var focusedTaskID: UUID? {
        if case .task(let id)? = focus { return id }
        return nil
    }

    /// Removes the task when it has no text and moves the cursor to the line above
    /// (or to the add line when it was the first). Returns whether anything happened.
    @discardableResult
    private func removeIfEmpty(_ id: UUID) -> Bool {
        guard let i = tasks.firstIndex(where: { $0.id == id }), tasks[i].text.isEmpty else { return false }
        let previous = i > 0 ? tasks[i - 1].id : nil
        tasks.remove(id: id)
        focus = previous.map { .task($0) } ?? .newTask
        return true
    }
}

/// Local keyDown monitor for Backspace with no modifiers. `handler` returns true to swallow the key.
@MainActor
private final class KeyMonitor {
    private var token: Any?

    func install(_ handler: @escaping @MainActor () -> Bool) {
        remove()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 51, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
            return MainActor.assumeIsolated { handler() } ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

private struct TaskRow: View {
    let task: TaskItem
    @Binding var text: String
    var focus: FocusState<TaskListEditor.Focus?>.Binding
    let identifier: String
    let onToggle: () -> Void
    let onSubmit: () -> Void
    let onDeleteEmpty: () -> Bool
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onToggle) {
                CheckCircle(done: task.isDone, emphasized: hovering)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Mark as not done" : "Mark as done")
            .accessibilityLabel(task.isDone ? "Done" : "Not done")
            .accessibilityIdentifier("\(identifier).check")

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.body)
                .foregroundStyle(task.isDone ? Theme.inkFaint : Theme.ink)
                .strikethrough(task.isDone, color: Theme.inkFaint)
                .focused(focus, equals: .task(task.id))
                .onSubmit(onSubmit)
                .onKeyPress(.delete, phases: .down) { _ in
                    text.isEmpty && onDeleteEmpty() ? .handled : .ignored
                }
                .accessibilityLabel(task.isDone ? "Done task" : "Task")
                .accessibilityIdentifier(identifier)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Remove task")
            .accessibilityLabel("Remove task")
            .accessibilityHidden(!hovering)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .overlay(alignment: .bottom) {
            Hairline(color: Theme.ruledLine).padding(.leading, 28)
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The trailing line that turns typed text into a task on Return.
private struct NewTaskRow: View {
    @Binding var draft: String
    var focus: FocusState<TaskListEditor.Focus?>.Binding
    let identifier: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Theme.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                .accessibilityHidden(true)
            TextField("", text: $draft, prompt: Text("Add a task…").foregroundStyle(Theme.inkFaint))
                .textFieldStyle(.plain)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .focused(focus, equals: .newTask)
                .onSubmit(onSubmit)
                .accessibilityLabel("Add a task")
                .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 5)
    }
}

/// The check control: a thin ring that fills with the accent colour when done.
struct CheckCircle: View {
    let done: Bool
    var emphasized = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(done ? Theme.accent : (emphasized ? Theme.inkMuted : Theme.inkFaint), lineWidth: 1.5)
            Circle()
                .fill(Theme.accent)
                .scaleEffect(done ? 1 : 0.01)
                .opacity(done ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(done ? 1 : 0.4)
                .opacity(done ? 1 : 0)
        }
        .frame(width: 18, height: 18)
        .contentShape(Circle())
        .accessibilityHidden(true)
    }
}

/// "2 of 5 done", or nothing when the list is empty.
struct TaskCount: View {
    let tasks: [TaskItem]
    var body: some View {
        let total = tasks.trimmedForStorage.count
        if total > 0 {
            Text("\(tasks.doneCount) of \(total) done")
                .font(Theme.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
                .accessibilityLabel("\(tasks.doneCount) of \(total) tasks done")
        }
    }
}

/// The task list sized to its content, scrolling only once it would take more than
/// `maxHeight`, so the notes underneath always keep room.
struct CappedTaskList: View {
    @Binding var tasks: [TaskItem]
    let idPrefix: String
    let day: LocalDate
    let maxHeight: CGFloat
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                TaskListEditor(tasks: $tasks, idPrefix: idPrefix, day: day)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .scrollDisabled(contentHeight <= maxHeight)
            .frame(height: min(contentHeight, maxHeight))
            .onChange(of: tasks.count) { _, _ in
                if contentHeight > maxHeight {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(TaskListEditor.addRowID, anchor: .bottom) }
                }
            }
        }
    }
}

/// Read-only rendering of a partner's task list.
struct TaskListReader: View {
    let tasks: [TaskItem]

    var body: some View {
        if !tasks.isEmpty {
            VStack(spacing: 0) {
                ForEach(tasks) { task in
                    HStack(alignment: .center, spacing: 10) {
                        CheckCircle(done: task.isDone)
                        Text(task.text)
                            .font(Theme.body)
                            .foregroundStyle(task.isDone ? Theme.inkFaint : Theme.ink)
                            .strikethrough(task.isDone, color: Theme.inkFaint)
                            .lineLimit(1)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    .overlay(alignment: .bottom) { Hairline(color: Theme.ruledLine).padding(.leading, 28) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(task.text), \(task.isDone ? "done" : "not done")")
                }
            }
            .padding(.bottom, 8)
        }
    }
}
