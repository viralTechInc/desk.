import SwiftUI
import AppKit

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlannerStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AppActions.self) private var actions

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            ToolbarView()
            Hairline()
            Group {
                switch appState.viewMode {
                case .day: DayView()
                case .week: WeekView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.canvas)
        .preferredColorScheme(settings.appearance.colorScheme)
        .sheet(isPresented: $appState.showShortcutHelp) { ShortcutHelpView() }
        .modifier(RootDialogs())
        .modifier(RootLifecycle())
    }
}

/// Confirmation dialogs and alerts driven by `AppState`.
private struct RootDialogs: ViewModifier {
    @Environment(AppState.self) private var appState
    @Environment(AppActions.self) private var actions

    func body(content: Content) -> some View {
        @Bindable var appState = appState
        content
            .confirmationDialog(
                appState.scopePrompt?.title ?? "",
                isPresented: Binding(get: { appState.scopePrompt != nil }, set: { if !$0 { appState.scopePrompt = nil } }),
                titleVisibility: .visible,
                presenting: appState.scopePrompt
            ) { prompt in
                Button("This Occurrence") { prompt.apply(.thisOccurrence) }
                Button("Entire Routine") { prompt.apply(.entireSeries) }
                Button("Cancel", role: .cancel) {}
            } message: { prompt in
                Text(prompt.message)
            }
            .alert(
                "Delete this routine?",
                isPresented: Binding(get: { appState.seriesDeletion != nil }, set: { if !$0 { appState.seriesDeletion = nil } }),
                presenting: appState.seriesDeletion
            ) { occ in
                Button("Delete Routine", role: .destructive) { actions.deleteSeriesConfirmed(occ) }
                Button("Cancel", role: .cancel) {}
            } message: { occ in
                Text("“\(occ.displayTitle)” will be removed from every week, including past weeks. You can undo this.")
            }
            .alert(
                "Replace everything with this backup?",
                isPresented: Binding(get: { appState.pendingImport != nil }, set: { if !$0 { appState.pendingImport = nil } }),
                presenting: appState.pendingImport
            ) { doc in
                Button("Replace", role: .destructive) { actions.importConfirmed(doc) }
                Button("Cancel", role: .cancel) {}
            } message: { doc in
                Text("The backup contains \(doc.summary), exported \(doc.exportedAt.formatted(date: .abbreviated, time: .shortened)). Your current notes and blocks will be replaced. This can't be undone — export a backup first if you want to keep them.")
            }
            .alert("Load demo data?", isPresented: $appState.confirmDemoData) {
                Button("Load") { actions.loadDemoData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Adds a sample week of routines, a few blocks and a filled-in page for today, alongside anything you already have.")
            }
            .alert("Remove the demo data?", isPresented: $appState.confirmRemoveDemoData) {
                Button("Remove", role: .destructive) { actions.removeDemoData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the sample routines, blocks and notes exactly as Load Demo Data added them for this week. Anything you changed or wrote yourself stays.")
            }
            .alert(
                appState.alert?.title ?? "",
                isPresented: Binding(get: { appState.alert != nil }, set: { if !$0 { appState.alert = nil } }),
                presenting: appState.alert
            ) { _ in
                Button("OK") {}
            } message: { a in
                Text(a.message)
            }
    }
}

/// Flushes and refreshes on navigation, activation, day change and time-zone change.
private struct RootLifecycle: ViewModifier {
    @Environment(AppState.self) private var appState
    @Environment(PlannerStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .onChange(of: appState.settingsRequest) {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .onChange(of: appState.selectedDate) { store.flush() }
            .onChange(of: appState.viewMode) { store.flush() }
            .onChange(of: settings.firstWeekday, initial: true) { applyCalendar() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in appState.refreshToday() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.flush() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in store.flush() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in appState.refreshToday() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in applyCalendar() }
    }

    private func applyCalendar() {
        let cal = DeskCalendar(firstWeekday: settings.firstWeekday)
        store.calendar = cal
        appState.updateCalendar(cal)
    }
}

struct ToolbarView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlannerStore.self) private var store

    var body: some View {
        @Bindable var appState = appState
        HStack(spacing: 12) {
            Text("desk.")
                .font(Theme.wordmark)
                .foregroundStyle(Theme.ink)
                .padding(.trailing, 8)
                .accessibilityHidden(true)

            ViewModeSwitcher(mode: Binding(get: { appState.viewMode }, set: { appState.show($0) }))

            Spacer(minLength: 16)

            HStack(spacing: 4) {
                Button { appState.goPrevious() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(IconButtonStyle())
                    .help(appState.viewMode == .day ? "Previous day (J)" : "Previous week (J)")
                    .accessibilityLabel(appState.viewMode == .day ? "Previous day" : "Previous week")
                Button { appState.goNext() } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(IconButtonStyle())
                    .help(appState.viewMode == .day ? "Next day (K)" : "Next week (K)")
                    .accessibilityLabel(appState.viewMode == .day ? "Next day" : "Next week")
            }

            Spacer(minLength: 16)

            SaveIndicator(state: store.saveState)
                .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.leading, 84) // room for the window controls
        .padding(.trailing, 20)
        .frame(height: Theme.toolbarHeight)
        .background(Theme.canvas)
    }
}

/// Quiet "Saving… / Saved" text that fades out, or a recoverable error.
struct SaveIndicator: View {
    let state: SaveState
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()
            case .saving:
                Text("Saving…")
            case .saved:
                Text("Saved").opacity(visible ? 1 : 0)
            case .failed(let message):
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text("Couldn't save")
                }
                .foregroundStyle(Theme.danger)
                .help(message + "\nYour text is still in the window — export a backup from the File menu.")
            }
        }
        .font(Theme.caption)
        .foregroundStyle(Theme.inkMuted)
        .animation(.easeInOut(duration: 0.4), value: visible)
        .onChange(of: state, initial: true) {
            hideTask?.cancel()
            if case .saved = state {
                visible = true
                hideTask = Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    if !Task.isCancelled { visible = false }
                }
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch state {
        case .idle: ""
        case .saving: "Saving"
        case .saved: "Saved"
        case .failed(let m): "Save failed: \(m)"
        }
    }
}
