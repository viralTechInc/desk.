import SwiftUI
import AppKit

/// Shared "what's happening now" for the menu bar. Re-reads the merged schedule for today
/// whenever Desk data, the system calendars, or the clock minute changes.
@MainActor
@Observable
final class ScheduleFeed {
    private let store: PlannerStore
    private let calendarService: CalendarService
    private let appState: AppState
    private(set) var status = ScheduleMerger.Status(current: nil, upcoming: [], remainingMinutes: nil, minutesUntilNext: nil)
    private(set) var todayEntries: [ScheduleEntry] = []
    private(set) var nowMinutes = 0
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(store: PlannerStore, calendarService: CalendarService, appState: AppState) {
        self.store = store
        self.calendarService = calendarService
        self.appState = appState
        refresh()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.refresh()
            }
        }
    }

    func refresh(now: Date = Date()) {
        appState.refreshToday(now: now)
        let today = appState.today
        let blocks = store.occurrences(on: today)
        let external = calendarService.events(in: today...today, calendar: appState.calendar)
        todayEntries = ScheduleMerger.timedEntries(blocks: blocks, external: external)
        nowMinutes = appState.calendar.minutesFromMidnight(now)
        status = ScheduleMerger.status(entries: todayEntries, nowMinutes: nowMinutes)
    }

    var menuBarTitle: String { ScheduleMerger.menuBarTitle(status) ?? "desk." }
}

struct MenuBarLabel: View {
    @Environment(ScheduleFeed.self) private var feed
    @Environment(PlannerStore.self) private var store
    @Environment(CalendarService.self) private var calendarService

    var body: some View {
        let _ = store.revision
        let _ = calendarService.revision
        Label {
            Text(feed.menuBarTitle)
        } icon: {
            Image(systemName: feed.status.current?.isExternal == true ? "calendar" : "square.text.square")
        }
        .labelStyle(.titleAndIcon)
        .onChange(of: store.revision) { feed.refresh() }
        .onChange(of: calendarService.revision) { feed.refresh() }
    }
}

/// Popover contents: current item, next three, and a way back into the planner.
struct MenuBarContent: View {
    @Environment(ScheduleFeed.self) private var feed
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appState.calendar.headingString(appState.today))
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(Theme.ink)

            if let current = feed.status.current, let remaining = feed.status.remainingMinutes {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Now")
                    EntryRow(entry: current, trailing: "\(ScheduleMerger.short(remaining)) left")
                }
            } else {
                Text(feed.todayEntries.isEmpty ? "Nothing scheduled today." : "Free right now.")
                    .font(Theme.caption).foregroundStyle(Theme.inkMuted)
            }

            if !feed.status.upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Next")
                    ForEach(Array(feed.status.upcoming.enumerated()), id: \.element.id) { i, entry in
                        EntryRow(entry: entry, trailing: i == 0 ? "in \(ScheduleMerger.short(entry.startMinutes - feed.nowMinutes))" : TimeFormat.clock(entry.startMinutes))
                    }
                }
            }

            Hairline()
            HStack {
                Button("Open Desk") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(QuietButtonStyle(prominent: true))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(Theme.surface)
        .onAppear { feed.refresh() }
    }
}

private struct EntryRow: View {
    let entry: ScheduleEntry
    let trailing: String
    @Environment(CalendarService.self) private var calendarService
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(entry.color).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if entry.isExternal {
                        Image(systemName: "calendar").font(.system(size: 9)).foregroundStyle(Theme.inkMuted)
                    }
                    Text(entry.title).font(Theme.bodyMedium).foregroundStyle(Theme.ink).lineLimit(1)
                }
                Text("\(TimeFormat.range(entry.startMinutes, entry.endMinutes))\(entry.subtitle.map { " · \($0)" } ?? "")")
                    .font(Theme.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer()
            if let link = entry.conference {
                Button("Join") { calendarService.join(link) }
                    .buttonStyle(QuietButtonStyle(prominent: true))
                    .help(link.joinTitle)
            }
            Text(trailing).font(Theme.caption).foregroundStyle(Theme.inkMuted)
        }
    }
}
