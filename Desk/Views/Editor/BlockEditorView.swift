import SwiftUI

/// Compact popover for a block: title, category, date, times, repeat, note.
/// Edits are committed when the popover closes (or Done / Return); Esc cancels.
struct BlockEditorView: View {
    let occurrence: EventOccurrence
    let isNew: Bool
    let weekdays: WeekdaySet

    @Environment(PlannerStore.self) private var store
    @Environment(AppState.self) private var appState
    @Environment(AppActions.self) private var actions
    @Environment(AppSettings.self) private var settings

    @State private var draft: BlockDraft
    @State private var scope: EditScope = .thisOccurrence
    @State private var startText: String
    @State private var endText: String
    @State private var finished = false
    @FocusState private var focus: Field?

    enum Field: Hashable { case title, start, end, note }

    init(occurrence: EventOccurrence, isNew: Bool, weekdays: WeekdaySet) {
        self.occurrence = occurrence
        self.isNew = isNew
        self.weekdays = weekdays
        let d = BlockDraft(from: occurrence, weekdays: weekdays)
        _draft = State(initialValue: d)
        _startText = State(initialValue: TimeFormat.clock(d.startMinutes))
        _endText = State(initialValue: TimeFormat.clock(d.endMinutes))
    }

    private var original: BlockDraft { BlockDraft(from: occurrence, weekdays: weekdays) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if occurrence.isRecurring {
                Picker("Apply to", selection: $scope) {
                    Text("This occurrence").tag(EditScope.thisOccurrence)
                    Text("Entire routine").tag(EditScope.entireSeries)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .disabled(draft.weekdays != weekdays)
                .help(draft.weekdays != weekdays ? "Changing repeat days always applies to the entire routine." : "")
            }

            TextField("Title", text: $draft.title, prompt: Text("Title").foregroundStyle(Theme.inkFaint))
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink)
                .focused($focus, equals: .title)
                .onSubmit { finish() }
                .accessibilityIdentifier("blockEditor.title")

            CategoryPicker(selection: $draft.category)

            HStack(spacing: 8) {
                DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .controlSize(.small)
                    .frame(width: 112)
                    .accessibilityLabel("Date")
                TimeField(text: $startText, minutes: $draft.startMinutes, label: "Start", focus: $focus, field: .start) { newStart in
                    // Keep duration when the start moves.
                    let duration = draft.endMinutes - draft.startMinutes
                    draft.startMinutes = newStart
                    draft.endMinutes = min(newStart + max(duration, TimeRules.minimumDuration), TimeRules.dayMinutes)
                    endText = TimeFormat.clock(draft.endMinutes)
                }
                Text("–").foregroundStyle(Theme.inkMuted)
                TimeField(text: $endText, minutes: $draft.endMinutes, label: "End", focus: $focus, field: .end) { newEnd in
                    draft.endMinutes = max(newEnd, draft.startMinutes + TimeRules.minimumDuration)
                    endText = TimeFormat.clock(draft.endMinutes)
                }
                Text(TimeFormat.duration(max(draft.endMinutes - draft.startMinutes, 0)))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .frame(minWidth: 52, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Repeat").font(Theme.caption).foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Menu {
                        Button("Never") { draft.weekdays = .none }
                        Button("Weekdays") { draft.weekdays = .weekdays }
                        Button("Every day") { draft.weekdays = .everyDay }
                        Button("Weekly on \(appState.calendar.weekday(of: draft.date).fullName)") {
                            draft.weekdays = WeekdaySet([appState.calendar.weekday(of: draft.date)])
                        }
                    } label: {
                        Text(draft.weekdays.isEmpty ? "Never" : draft.weekdays.summary(startingAt: settings.firstWeekday))
                            .font(Theme.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Repeat presets")
                }
                WeekdayToggles(selection: $draft.weekdays, first: settings.firstWeekday)
            }

            TextField("Note", text: $draft.note, prompt: Text("Note").foregroundStyle(Theme.inkFaint), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.caption)
                .foregroundStyle(Theme.ink)
                .lineLimit(1...4)
                .focused($focus, equals: .note)

            HStack {
                if occurrence.isRecurring {
                    Menu {
                        Button("Skip This Occurrence") { finished = true; store.delete(occurrence, scope: .thisOccurrence); close() }
                        Button("Delete Routine…", role: .destructive) { finished = true; appState.seriesDeletion = occurrence; close() }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(Theme.inkMuted)
                    .accessibilityLabel("Remove")
                } else {
                    Button { finished = true; store.delete(occurrence, scope: .thisOccurrence); close() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Delete block")
                    .accessibilityLabel("Delete block")
                }
                Spacer()
                if isNew {
                    Button("Cancel") { cancel() }
                        .buttonStyle(QuietButtonStyle())
                }
                Button("Done") { finish() }
                    .buttonStyle(QuietButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(Theme.surfaceRaised)
        .onAppear {
            if isNew || occurrence.title.isEmpty { focus = .title }
        }
        .onExitCommand { cancel() }
        .onDisappear {
            // Click-outside dismissal commits like Done.
            if !finished { commit() }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { appState.calendar.noon(draft.date) },
            set: { draft.date = appState.calendar.localDate(from: $0) })
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        commit()
        close()
    }

    private func cancel() {
        guard !finished else { return }
        finished = true
        if isNew {
            store.delete(occurrence, scope: .thisOccurrence)
        }
        close()
    }

    private func close() {
        if appState.editingOccurrenceID == occurrence.id {
            appState.editingOccurrenceID = nil
            appState.editingIsNew = false
        }
    }

    private func commit() {
        // Parse any time text that was typed but not submitted.
        if let s = TimeFormat.parse(startText), s != draft.startMinutes {
            let duration = draft.endMinutes - draft.startMinutes
            draft.startMinutes = s
            draft.endMinutes = min(s + max(duration, TimeRules.minimumDuration), TimeRules.dayMinutes)
        }
        if let e = TimeFormat.parse(endText), e != draft.endMinutes { draft.endMinutes = e }
        var d = draft
        d.title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard d != original else { return }
        actions.lastCategory = d.category
        let effectiveScope: EditScope = (occurrence.isRecurring && d.weekdays != weekdays) ? .entireSeries : scope
        store.update(occurrence, with: d, scope: effectiveScope)
    }
}

// MARK: - Pieces

private struct TimeField: View {
    @Binding var text: String
    @Binding var minutes: Int
    let label: String
    var focus: FocusState<BlockEditorView.Field?>.Binding
    let field: BlockEditorView.Field
    let onCommit: (Int) -> Void

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .font(.system(size: 12).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: 70)
            .focused(focus, equals: field)
            .onSubmit { apply() }
            .onChange(of: focus.wrappedValue) { _, new in
                if new != field { apply() }
            }
            .onChange(of: minutes) { _, new in
                if TimeFormat.parse(text) != new { text = TimeFormat.clock(new) }
            }
            .accessibilityLabel(label)
    }

    private func apply() {
        if let m = TimeFormat.parse(text), m != minutes {
            onCommit(min(m, TimeRules.dayMinutes))
        }
        text = TimeFormat.clock(minutes)
    }
}

struct CategoryPicker: View {
    @Binding var selection: BlockCategory
    var body: some View {
        HStack(spacing: 8) {
            ForEach(BlockCategory.allCases) { cat in
                Button {
                    selection = cat
                } label: {
                    ZStack {
                        Circle().fill(cat.color).frame(width: 18, height: 18)
                        if selection == cat {
                            Circle().strokeBorder(Theme.ink.opacity(0.7), lineWidth: 2).frame(width: 24, height: 24)
                        }
                    }
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(cat.label)
                .accessibilityLabel(cat.label)
                .accessibilityAddTraits(selection == cat ? [.isSelected] : [])
            }
            Spacer()
            Text(selection.label)
                .font(Theme.caption)
                .foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Category")
    }
}

struct WeekdayToggles: View {
    @Binding var selection: WeekdaySet
    let first: Weekday
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.ordered(startingAt: first), id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    selection.toggle(day)
                } label: {
                    Text(day.letter)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(on ? Theme.surface : Theme.inkMuted)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(on ? Theme.ink : Theme.hairline.opacity(0.9)))
                }
                .buttonStyle(.plain)
                .help(day.fullName)
                .accessibilityLabel(day.fullName)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Repeat on")
    }
}
