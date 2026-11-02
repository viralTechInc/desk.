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
            Group {
                if appState.viewingPartnerID != nil {
                    PartnerView()
                } else {
                    switch appState.viewMode {
                    case .day: DayView()
                    case .week: WeekView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            FooterBar()
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
    @Environment(SharingService.self) private var sharing
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .onChange(of: store.saveState) {
                if case .saved = store.saveState { sharing.schedulePublish() }
            }
            .onChange(of: sharing.revision) {
                // The partner being viewed vanished from the folder: fall back to mine.
                if let id = appState.viewingPartnerID, sharing.partner(id: id) == nil, sharing.partners.isEmpty {
                    appState.showPartner(nil)
                }
            }
            .onChange(of: appState.settingsRequest) {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .onChange(of: appState.selectedDate) { store.flush() }
            .onChange(of: appState.viewMode) { store.flush() }
            .onChange(of: settings.firstWeekday, initial: true) { applyCalendar() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in appState.refreshToday() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.flush(); sharing.publishNow() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in store.flush(); sharing.publishNow() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in appState.refreshToday(); sharing.reload() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in applyCalendar() }
    }

    private func applyCalendar() {
        let cal = DeskCalendar(firstWeekday: settings.firstWeekday)
        store.calendar = cal
        appState.updateCalendar(cal)
    }
}

/// Heading row of every page: the title (and subtitle) with the previous/next arrows beside
/// it, and the Day / Week switcher — plus the desk switcher once a partner shares — flush right.
/// Sits under the hidden title bar, so it keeps clear of the window controls.
struct PageHeader<Title: View>: View {
    @Environment(AppState.self) private var appState
    @Environment(SharingService.self) private var sharing
    var bottomPadding: CGFloat = 14
    @ViewBuilder let title: Title

    var body: some View {
        @Bindable var appState = appState
        let _ = sharing.revision
        HStack(alignment: .center, spacing: 14) {
            title
            HStack(spacing: 2) {
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

            if !sharing.partners.isEmpty {
                DeskSwitcher(partners: sharing.partners,
                             selection: Binding(get: { appState.viewingPartnerID }, set: { appState.showPartner($0) }))
            }
            ViewModeSwitcher(mode: Binding(get: { appState.viewMode }, set: { appState.show($0) }))
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, Theme.headerTop)
        .padding(.bottom, bottomPadding)
    }
}

/// Thin strip under the page: the wordmark bottom-left, save state and the light/dark switch
/// bottom-right. Everything that used to live in a toolbar above the page, out of the way.
struct FooterBar: View {
    @Environment(PlannerStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Text("desk.")
                .font(Theme.wordmark)
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)

            Spacer(minLength: 16)

            SaveIndicator(state: store.saveState)
                .frame(minWidth: 90, alignment: .trailing)

            Button { settings.toggleAppearance() } label: {
                Image(systemName: scheme == .dark ? "sun.max" : "moon")
            }
            .buttonStyle(IconButtonStyle())
            .help(scheme == .dark ? "Switch to light mode (⇧⌘L)" : "Switch to dark mode (⇧⌘L)")
            .accessibilityLabel(scheme == .dark ? "Switch to light mode" : "Switch to dark mode")
            .accessibilityIdentifier("toolbar.appearance")
        }
        .padding(.horizontal, Theme.margin)
        .frame(height: Theme.footerHeight)
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

/// "Mine | <partner>" switcher, shown only once a partner's file is in the shared folder.
struct DeskSwitcher: View {
    let partners: [PartnerDesk]
    @Binding var selection: String?

    var body: some View {
        HStack(spacing: 2) {
            segment(id: nil, label: "Mine")
            ForEach(partners) { p in segment(id: p.id, label: p.name) }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.hairline.opacity(0.8)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Whose desk")
        .accessibilityIdentifier("toolbar.desk")
    }

    private func segment(id: String?, label: String) -> some View {
        let on = selection == id
        return Button(label) { selection = id }
            .buttonStyle(.plain)
            .font(Theme.toolbar)
            .foregroundStyle(on ? Theme.ink : Theme.inkMuted)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(on ? Theme.surface : .clear)
                    .shadow(color: on ? .black.opacity(0.06) : .clear, radius: 1, y: 1)
            )
            .help(id == nil ? "My desk" : "\(label)’s desk (⇧⌘P switches)")
            .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
