import SwiftUI

/// Popover for a block, laid out like a small card: title, then three quiet sections
/// (category, when, repeat), a note, and the actions. Edits are committed when the popover
/// closes (or Done / Return); Esc cancels.
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
    @State private var showingCalendar = false
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
        VStack(alignment: .leading, spacing: 0) {
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
                .padding(.bottom, 16)
            }

            // Title, with the category colour as a bar beside it.
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(draft.category.color)
                    .frame(width: 4, height: 22)
                    .animation(.easeOut(duration: 0.15), value: draft.category)
                    .accessibilityHidden(true)
                TextField("Title", text: $draft.title, prompt: Text("What is this block for?").foregroundStyle(Theme.inkFaint))
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .focused($focus, equals: .title)
                    .onSubmit { finish() }
                    .accessibilityIdentifier("blockEditor.title")
            }
            .padding(.bottom, 8)
            Hairline()
                .padding(.bottom, 18)

            // Category
            EditorSection(label: "Category") {
                CategoryPicker(selection: $draft.category)
            }
            .padding(.bottom, 18)

            // When
            EditorSection(label: "When") {
                HStack(spacing: 8) {
                    Button { showingCalendar = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.inkMuted)
                            Text(dateLabel)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .fieldChrome()
                    }
                    .buttonStyle(.plain)
                    .help("Change date")
                    .accessibilityLabel("Date, \(dateLabel)")
                    .popover(isPresented: $showingCalendar, arrowEdge: .bottom) {
                        DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .padding(12)
                            .background(Theme.surfaceRaised)
                    }

                    TimeField(text: $startText, minutes: $draft.startMinutes, label: "Start", focus: $focus, field: .start) { newStart in
                        // Keep duration when the start moves.
                        let duration = draft.endMinutes - draft.startMinutes
                        draft.startMinutes = newStart
                        draft.endMinutes = min(newStart + max(duration, TimeRules.minimumDuration), TimeRules.dayMinutes)
                        endText = TimeFormat.clock(draft.endMinutes)
                    }
                    Text("–")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkFaint)
                    TimeField(text: $endText, minutes: $draft.endMinutes, label: "End", focus: $focus, field: .end) { newEnd in
                        draft.endMinutes = max(newEnd, draft.startMinutes + TimeRules.minimumDuration)
                        endText = TimeFormat.clock(draft.endMinutes)
                    }
                    Spacer(minLength: 4)
                    Text(TimeFormat.duration(max(draft.endMinutes - draft.startMinutes, 0)))
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 18)

            // Repeat
            EditorSection(label: "Repeat", trailing: {
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
                        .foregroundStyle(Theme.inkMuted)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Repeat presets")
            }) {
                WeekdayToggles(selection: $draft.weekdays, first: settings.firstWeekday)
            }
            .padding(.bottom, 18)

            // Note
            TextField("Note", text: $draft.note, prompt: Text("Add a note…").foregroundStyle(Theme.inkFaint), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .lineLimit(1...4)
                .focused($focus, equals: .note)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fieldChrome(filled: true)
                .padding(.bottom, 18)

            Hairline()
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                if occurrence.isRecurring {
                    Menu {
                        Button("Skip This Occurrence") { finished = true; store.delete(occurrence, scope: .thisOccurrence); close() }
                        Button("Delete Routine…", role: .destructive) { finished = true; appState.seriesDeletion = occurrence; close() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(Theme.inkMuted)
                    .help("Skip or delete")
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
                        .keyboardShortcut(.cancelAction)
                }
                Button("Done") { finish() }
                    .buttonStyle(FilledButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 372)
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

    /// "Fri, Nov 7" — or "Today" / "Tomorrow" when that is what it is.
    private var dateLabel: String {
        if draft.date == appState.today { return "Today" }
        if draft.date == appState.calendar.adding(days: 1, to: appState.today) { return "Tomorrow" }
        return appState.calendar.noon(draft.date).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
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

/// A small uppercase label (with an optional control on the right) above its content.
private struct EditorSection<Content: View, Trailing: View>: View {
    let label: String
    let trailing: Trailing
    let content: Content

    init(label: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.label = label
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.inkFaint)
                Spacer()
                trailing
            }
            content
        }
    }
}

extension EditorSection where Trailing == EmptyView {
    init(label: String, @ViewBuilder content: () -> Content) {
        self.init(label: label, trailing: { EmptyView() }, content: content)
    }
}

/// Rounded hairline box shared by the editor's fields so they all read as one family.
private struct FieldChrome: ViewModifier {
    var filled = false
    var focused = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(filled ? Theme.surface : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(focused ? Theme.accent : Theme.hairlineStrong, lineWidth: 1)
            )
    }
}

private extension View {
    func fieldChrome(filled: Bool = false, focused: Bool = false) -> some View {
        modifier(FieldChrome(filled: filled, focused: focused))
    }
}

private struct TimeField: View {
    @Binding var text: String
    @Binding var minutes: Int
    let label: String
    var focus: FocusState<BlockEditorView.Field?>.Binding
    let field: BlockEditorView.Field
    let onCommit: (Int) -> Void

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .frame(width: 74, height: 28)
            .fieldChrome(focused: focus.wrappedValue == field)
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
        HStack(spacing: 10) {
            ForEach(BlockCategory.allCases) { cat in
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { selection = cat }
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(cat.color, lineWidth: 1.5)
                            .frame(width: 24, height: 24)
                            .opacity(selection == cat ? 1 : 0)
                        Circle()
                            .fill(cat.color)
                            .frame(width: selection == cat ? 14 : 16, height: selection == cat ? 14 : 16)
                    }
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(cat.label)
                .accessibilityLabel(cat.label)
                .accessibilityAddTraits(selection == cat ? [.isSelected] : [])
            }
            Spacer(minLength: 8)
            Text(selection.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .contentTransition(.opacity)
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
                    withAnimation(.easeOut(duration: 0.12)) { selection.toggle(day) }
                } label: {
                    Text(day.letter)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(on ? Theme.surface : Theme.inkMuted)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(on ? Theme.ink : .clear))
                        .overlay(Circle().strokeBorder(on ? .clear : Theme.hairlineStrong, lineWidth: 1))
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
