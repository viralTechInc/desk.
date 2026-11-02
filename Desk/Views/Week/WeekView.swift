import SwiftUI

/// Seven-day master schedule with optional weekly intentions.
struct WeekView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlannerStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let days = appState.weekDays
        VStack(alignment: .leading, spacing: 0) {
            PageHeader { WeekHeading(days: days) }

            VStack(spacing: 0) {
                if settings.showWeeklyIntentions {
                    WeeklyIntentionsRow(editor: store.weekEditor(for: days[0]))
                        .id("\(days[0].key)-\(store.pageGeneration)")
                    Hairline()
                }
                TimelineGrid(days: days, showHeaders: true)
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.pageBottom)
        }
    }
}

/// "November 2 – 8, 2026" with a quiet "This week" beside it when today is in range.
struct WeekHeading: View {
    @Environment(AppState.self) private var appState
    let days: [LocalDate]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(appState.calendar.weekRangeString(containing: appState.selectedDate))
                .font(Theme.weekHeading)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("weekHeading")
            if days.contains(appState.today) {
                Text("This week").font(Theme.caption).foregroundStyle(Theme.inkMuted)
            }
        }
    }
}

/// Three quiet lines of intention for the week. Collapsible; never tall.
struct WeeklyIntentionsRow: View {
    let editor: WeekPageEditor
    @AppStorage("intentionsCollapsed") private var collapsed = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { collapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    SectionLabel(text: "Intentions")
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .buttonStyle(.plain)
            .help(collapsed ? "Show weekly intentions" : "Hide weekly intentions")
            .accessibilityLabel(collapsed ? "Show weekly intentions" : "Hide weekly intentions")

            if !collapsed {
                ForEach(0..<WeekPageEditor.rows, id: \.self) { i in
                    TextField("", text: Binding(get: { editor.intentions[i] }, set: { editor.setIntention($0, at: i) }),
                              prompt: Text(i == 0 ? "This week I want to…" : "").foregroundStyle(Theme.inkFaint))
                        .textFieldStyle(.plain)
                        .font(Theme.body)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottom) { Hairline(color: Theme.ruledLine).offset(y: 6) }
                        .accessibilityLabel("Intention \(i + 1)")
                }
            } else {
                Text(editor.intentions.filter { !$0.isEmpty }.joined(separator: "  ·  "))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(.horizontal, Theme.padding)
        .padding(.vertical, collapsed ? 10 : 14)
    }
}
