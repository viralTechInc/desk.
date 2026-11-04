import SwiftUI

/// The small sparkle beside a brain dump's task count. It reads the freeform notes with the
/// on-device model and offers the to-dos it finds; the person picks which ones join the list.
/// The notes themselves are never changed. Hidden when Apple Intelligence isn't available
/// or there are no notes to read.
struct TaskSuggestionsButton: View {
    let notes: String
    @Binding var tasks: [TaskItem]
    /// Accessibility identifier prefix ("task" / "weekTask").
    let idPrefix: String
    /// Opens when the Notebook ▸ Find Tasks in Brain Dump command asks (day column only).
    var answersMenuCommand = false

    @Environment(AppState.self) private var appState
    @State private var showing = false

    private var hasNotes: Bool { !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        if TaskExtractor.isAvailable {
            Button { showing.toggle() } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(showing ? Theme.accent : Theme.inkMuted)
                    .frame(width: 22, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hasNotes ? 1 : 0)
            .disabled(!hasNotes)
            .help("Find tasks in your notes")
            .accessibilityLabel("Find tasks in notes")
            .accessibilityIdentifier("\(idPrefix).suggest")
            .accessibilityHidden(!hasNotes)
            .onHover { if $0 && hasNotes { TaskExtractor.prewarm() } }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                TaskSuggestionsPopover(notes: notes, tasks: $tasks, idPrefix: idPrefix) { showing = false }
            }
            .onChange(of: appState.pendingTaskSuggestions) { _, _ in answerMenuCommand() }
            .onAppear { answerMenuCommand() }
        }
    }

    private func answerMenuCommand() {
        guard answersMenuCommand, appState.pendingTaskSuggestions else { return }
        appState.pendingTaskSuggestions = false
        if hasNotes { showing = true } else { appState.requestFocus(.brainDump) }
    }
}

private struct TaskSuggestionsPopover: View {
    let notes: String
    @Binding var tasks: [TaskItem]
    let idPrefix: String
    let close: () -> Void

    private struct Suggestion: Identifiable {
        let id = UUID()
        let text: String
        var include = true
    }

    private enum Phase {
        case reading
        case found([Suggestion], truncated: Bool)
        case failed(String)
    }

    @State private var phase = Phase.reading

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                SectionLabel(text: "Tasks in your notes")
            }
            .padding(.bottom, 12)

            content
        }
        .padding(18)
        .frame(width: 340)
        .background(Theme.surface)
        .task(id: notes) { await read() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .reading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Reading your notes…")
                    .font(Theme.body)
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            footer {
                Button("Cancel", action: close)
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }

        case .found(let suggestions, let truncated) where suggestions.isEmpty:
            Text(truncated ? "No new to-dos in the first part of these notes." : "No new to-dos in these notes.")
                .font(Theme.body)
                .foregroundStyle(Theme.inkMuted)
                .padding(.vertical, 6)
            footer {
                Button("Done", action: close)
                    .buttonStyle(FilledButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }

        case .found(let suggestions, let truncated):
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    SuggestionRow(
                        text: suggestion.text, include: suggestion.include,
                        identifier: "\(idPrefix).suggestion.\(index + 1)"
                    ) { toggle(suggestion.id) }
                }
            }
            Text(truncated ? "Only the first part of these long notes was read, privately on this Mac."
                           : "Read privately on this Mac. Nothing leaves it.")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            footer {
                Button("Cancel", action: close)
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                let count = suggestions.filter(\.include).count
                Button(count == 1 ? "Add 1 Task" : "Add \(count) Tasks") { add(suggestions) }
                    .buttonStyle(FilledButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(count == 0)
                    .accessibilityIdentifier("\(idPrefix).suggestion.add")
            }

        case .failed(let message):
            Text(message)
                .font(Theme.body)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
            footer {
                Button("Close", action: close)
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Try Again") { Task { await read() } }
                    .buttonStyle(FilledButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func footer(@ViewBuilder buttons: () -> some View) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            buttons()
        }
        .padding(.top, 14)
    }

    private func read() async {
        phase = .reading
        do {
            let result = try await TaskExtractor.extract(from: notes, existing: tasks)
            phase = .found(result.tasks.map { Suggestion(text: $0) }, truncated: result.wasTruncated)
        } catch is CancellationError {
            // The popover closed; nothing to show.
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func toggle(_ id: UUID) {
        guard case .found(var suggestions, let truncated) = phase,
              let i = suggestions.firstIndex(where: { $0.id == id }) else { return }
        suggestions[i].include.toggle()
        phase = .found(suggestions, truncated: truncated)
    }

    private func add(_ suggestions: [Suggestion]) {
        let chosen = suggestions.filter(\.include).map(\.text)
        // Re-check against the list as it is now, in case it changed while the model read.
        let fresh = TaskSuggestions.clean(chosen, existing: tasks)
        withAnimation(.easeOut(duration: 0.15)) { tasks.appendTasks(fresh) }
        close()
    }
}

private struct SuggestionRow: View {
    let text: String
    let include: Bool
    let identifier: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: include ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(include ? Theme.accent : Theme.inkFaint)
                    .frame(width: 16)
                Text(text)
                    .font(Theme.body)
                    .foregroundStyle(include ? Theme.ink : Theme.inkFaint)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Hairline(color: Theme.ruledLine).padding(.leading, 26) }
        .accessibilityLabel(text)
        .accessibilityValue(include ? "Will be added" : "Skipped")
        .accessibilityAddTraits(include ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
