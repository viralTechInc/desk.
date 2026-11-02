import SwiftUI

/// Notebook-first day page: date heading, then a two-column sheet — notebook left (about
/// two thirds: priorities, day brain dump, week brain dump), a narrower schedule right.
struct DayView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlannerStore.self) private var store

    var body: some View {
        let date = appState.selectedDate
        let weekStart = appState.calendar.startOfWeek(containing: date)
        GeometryReader { geo in
            let stacked = geo.size.width < 900
            VStack(alignment: .leading, spacing: 0) {
                DateHeading(date: date)
                    .padding(.horizontal, Theme.margin)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                Group {
                    if stacked {
                        VStack(spacing: 0) {
                            NotebookPanel(editor: store.editor(for: date), weekEditor: store.weekEditor(for: weekStart))
                                .frame(maxHeight: 380)
                            Hairline()
                            TimelinePane(date: date)
                        }
                    } else {
                        HStack(spacing: 0) {
                            NotebookPanel(editor: store.editor(for: date), weekEditor: store.weekEditor(for: weekStart))
                                .frame(width: (geo.size.width - Theme.margin * 2) * 0.64)
                            Hairline(vertical: true)
                            TimelinePane(date: date)
                        }
                    }
                }
                .id("\(date.key)-\(store.pageGeneration)")
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, Theme.padding)
            }
        }
    }
}

struct DateHeading: View {
    @Environment(AppState.self) private var appState
    let date: LocalDate

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(appState.calendar.headingString(date))
                .font(Theme.dateHeading)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("dateHeading")
            if let subtitle = appState.calendar.subtitleString(date, today: appState.today) {
                Text(subtitle)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }
}

/// The right-hand column of the day page.
struct TimelinePane: View {
    @Environment(AppActions.self) private var actions
    let date: LocalDate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(text: "Schedule")
                Spacer()
                Button { actions.addBlock() } label: { Image(systemName: "plus") }
                    .buttonStyle(IconButtonStyle())
                    .help("Add block (A)")
                    .accessibilityLabel("Add block")
            }
            .padding(.horizontal, Theme.padding)
            .padding(.top, Theme.padding - 4)
            .padding(.bottom, 6)
            TimelineGrid(days: [date], showHeaders: false)
        }
    }
}
