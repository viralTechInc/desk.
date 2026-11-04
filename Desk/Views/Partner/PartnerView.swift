import SwiftUI

/// A partner's Desk exactly as they see it — priorities, brain dumps and schedule — read
/// from the shared folder. Nothing on these screens can be edited.
struct PartnerView: View {
    @Environment(AppState.self) private var appState
    @Environment(SharingService.self) private var sharing

    var body: some View {
        let _ = sharing.revision
        if let id = appState.viewingPartnerID, let partner = sharing.partner(id: id) {
            switch appState.viewMode {
            case .day: PartnerDayView(partner: partner)
            case .week: PartnerWeekView(partner: partner)
            }
        } else {
            VStack(spacing: 10) {
                Text("This desk isn't shared any more")
                    .font(Theme.bodyMedium).foregroundStyle(Theme.ink)
                Text("Their file left the shared folder. You'll see it again as soon as it comes back.")
                    .font(Theme.caption).foregroundStyle(Theme.inkMuted)
                Button("Back to Mine") { appState.showPartner(nil) }
                    .buttonStyle(QuietButtonStyle(prominent: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Small line under the date: whose desk this is and how fresh the copy is.
struct PartnerBadge: View {
    let partner: PartnerDesk
    @State private var now = Date()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person").font(.system(size: 10, weight: .semibold))
            Text("\(partner.possessive) desk · updated \(freshness) · read-only")
        }
        .font(Theme.caption)
        .foregroundStyle(Theme.inkMuted)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .accessibilityIdentifier("partner.badge")
    }

    private var freshness: String {
        let seconds = max(0, now.timeIntervalSince(partner.updatedAt))
        if seconds < 90 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h ago" }
        return partner.updatedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

struct PartnerDayView: View {
    @Environment(AppState.self) private var appState
    let partner: PartnerDesk

    var body: some View {
        let date = appState.selectedDate
        let weekStart = appState.calendar.startOfWeek(containing: date)
        GeometryReader { geo in
            let stacked = geo.size.width < 900
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(bottomPadding: 4) { DateHeading(date: date) }
                PartnerBadge(partner: partner)
                    .padding(.horizontal, Theme.margin)
                    .padding(.bottom, 14)

                Group {
                    if stacked {
                        VStack(spacing: 0) {
                            PartnerNotebookPanel(partner: partner, date: date, weekStart: weekStart)
                                .frame(maxHeight: 380)
                            Hairline()
                            PartnerTimelinePane(partner: partner, days: [date], showHeaders: false)
                        }
                    } else {
                        HStack(spacing: 0) {
                            PartnerNotebookPanel(partner: partner, date: date, weekStart: weekStart)
                                .frame(width: (geo.size.width - Theme.margin * 2) * 0.64)
                            Hairline(vertical: true)
                            PartnerTimelinePane(partner: partner, days: [date], showHeaders: false)
                        }
                    }
                }
                .id("\(partner.id)-\(date.key)-\(partner.updatedAt.timeIntervalSince1970)")
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, Theme.pageBottom)
            }
        }
    }
}

struct PartnerWeekView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    let partner: PartnerDesk

    var body: some View {
        let days = appState.weekDays
        let intentions = partner.week(for: days[0])?.intentions.filter { !$0.isEmpty } ?? []
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(bottomPadding: 4) { WeekHeading(days: days) }
            PartnerBadge(partner: partner)
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 14)

            VStack(spacing: 0) {
                if settings.showWeeklyIntentions, !intentions.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        SectionLabel(text: "Intentions")
                        Text(intentions.joined(separator: "  ·  "))
                            .font(Theme.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.padding)
                    .padding(.vertical, 10)
                    Hairline()
                }
                TimelineGrid(days: days, showHeaders: true, partner: partner)
            }
            .id("\(partner.id)-\(days[0].key)-\(partner.updatedAt.timeIntervalSince1970)")
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.pageBottom)
        }
    }
}

/// The partner's schedule column, same chrome as mine minus the add button.
struct PartnerTimelinePane: View {
    let partner: PartnerDesk
    let days: [LocalDate]
    let showHeaders: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(text: "Schedule")
                Spacer()
            }
            .padding(.horizontal, Theme.padding)
            .padding(.top, Theme.padding - 4)
            .padding(.bottom, 6)
            TimelineGrid(days: days, showHeaders: showHeaders, partner: partner)
        }
    }
}

/// Priorities and both brain dumps, as text. Mirrors `NotebookPanel` without editors.
struct PartnerNotebookPanel: View {
    @Environment(AppState.self) private var appState
    let partner: PartnerDesk
    let date: LocalDate
    let weekStart: LocalDate

    var body: some View {
        let page = partner.page(for: date)
        let week = partner.week(for: weekStart)
        let priorities = (page?.priorities ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Top priorities")
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                ForEach(Array((priorities.isEmpty ? [""] : priorities).enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.system(size: 14, design: .serif))
                            .foregroundStyle(Theme.inkFaint)
                            .frame(width: 22, alignment: .trailing)
                        Text(text.isEmpty ? "Nothing written yet" : text)
                            .font(Theme.priority)
                            .foregroundStyle(text.isEmpty ? Theme.inkFaint : Theme.ink)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) { Hairline(color: Theme.ruledLine).padding(.leading, 32) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(partner.possessive) priorities")

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        SectionLabel(text: "Brain dump").fixedSize()
                        Spacer(minLength: 0)
                        TaskCount(tasks: page?.tasks ?? [])
                    }
                    .padding(.bottom, 4)
                    TaskListReader(tasks: page?.tasks ?? [])
                    NotesReader(text: page?.brainDump ?? "", hint: "Nothing written for this day.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.trailing, Theme.padding)

                Hairline(vertical: true)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        SectionLabel(text: "Week brain dump").fixedSize()
                        Text(appState.calendar.weekRangeString(containing: date))
                            .font(Theme.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
                        Spacer(minLength: 0)
                        TaskCount(tasks: week?.tasks ?? [])
                    }
                    .padding(.bottom, 4)
                    TaskListReader(tasks: week?.tasks ?? [])
                    NotesReader(text: week?.brainDump ?? "", hint: "Nothing written for this week.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.leading, Theme.padding)
            }
            .padding(.top, 26)
        }
        .padding(Theme.padding)
    }
}

/// Read-only notes on the same ruled paper as the editor.
struct NotesReader: View {
    let text: String
    let hint: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RuledPaper()
                .padding(.top, 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if text.isEmpty {
                Text(hint)
                    .font(Theme.body)
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.top, 8)
                    .padding(.leading, 1)
            } else {
                ScrollView(.vertical) {
                    Text(text)
                        .font(Theme.body)
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(7)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                        .padding(.leading, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityLabel(text.isEmpty ? hint : text)
    }
}

/// Details of a partner's block. Everything is read-only.
struct ReadOnlyBlockPopover: View {
    let occurrence: EventOccurrence
    let owner: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(occurrence.category.color).frame(width: 10, height: 10)
                Text(occurrence.displayTitle).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
            }
            Text("\(TimeFormat.range(occurrence.startMinutes, occurrence.endMinutes)) · \(occurrence.category.label)\(occurrence.isRecurring ? " · weekly" : "")")
                .font(Theme.body).foregroundStyle(Theme.ink)
            if !occurrence.note.isEmpty {
                Text(occurrence.note)
                    .font(Theme.caption).foregroundStyle(Theme.inkMuted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("From \(owner)’s desk. Only they can change it.")
                .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 280)
        .background(Theme.surfaceRaised)
    }
}
