import SwiftUI

/// Native menu bar. Letter shortcuts (T, N, J/K…) live in `ShortcutMonitor`; the menus carry
/// command-key equivalents so every action is discoverable in the menu bar.
struct DeskCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Block") { model.actions.addBlock() }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { model.actions.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo") { model.actions.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .importExport) {
            Button("Export Backup…") { model.actions.exportBackup() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Import Backup…") { model.actions.importBackup() }
            Divider()
            Button("Load Demo Data…") { model.appState.confirmDemoData = true }
            Button("Remove Demo Data…") { model.appState.confirmRemoveDemoData = true }
        }
        CommandGroup(after: .toolbar) {
            Button("Toggle Light / Dark") { model.settings.toggleAppearance() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Picker("Appearance", selection: Binding(get: { model.settings.appearance }, set: { model.settings.appearance = $0 })) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0) }
            }
            Divider()
            Button(model.appState.viewingPartnerID == nil ? "Show Partner’s Desk" : "Show My Desk") { switchDesk() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Sharing Settings…") { model.appState.openSettings(tab: "sharing") }
        }
        CommandMenu("Go") {
            Button("Today") { model.appState.goToToday() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Tomorrow") { model.appState.goToTomorrow() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("Previous") { model.appState.goPrevious() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Next") { model.appState.goNext() }
                .keyboardShortcut("]", modifiers: .command)
            Divider()
            Button("Day") { model.appState.show(.day) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Week") { model.appState.show(.week) }
                .keyboardShortcut("2", modifiers: .command)
        }
        CommandMenu("Calendars") {
            Button("Choose Calendars…") { model.appState.openSettings(tab: "calendars") }
            Button("Refresh Calendars") { refreshCalendars() }
                .keyboardShortcut("r", modifiers: .command)
        }
        CommandMenu("Notebook") {
            Button("Focus Brain Dump") { model.appState.requestFocus(.brainDump) }
                .keyboardShortcut("b", modifiers: [.command, .option])
            Button("Focus First Priority") { model.appState.requestFocus(.firstPriority) }
                .keyboardShortcut("p", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { model.appState.showShortcutHelp.toggle() }
                .keyboardShortcut("/", modifiers: .command)
        }
    }

    /// Cycles mine → each partner → mine; with nobody sharing yet it opens the Sharing settings.
    private func switchDesk() {
        let partners = model.sharing.partners
        guard !partners.isEmpty else { model.appState.openSettings(tab: "sharing"); return }
        let current = model.appState.viewingPartnerID
        if let current, let i = partners.firstIndex(where: { $0.id == current }), i + 1 < partners.count {
            model.appState.showPartner(partners[i + 1].id)
        } else if current == nil {
            model.appState.showPartner(partners[0].id)
        } else {
            model.appState.showPartner(nil)
        }
    }

    /// Refresh is only meaningful once Desk may read the calendar database. Before that,
    /// the menu item does the useful thing instead of silently doing nothing.
    private func refreshCalendars() {
        let service = model.calendarService
        switch service.access {
        case .authorized:
            service.refreshCalendars()
        case .notDetermined:
            Task { await service.requestAccess() }
        case .denied, .restricted, .writeOnly:
            model.appState.openSettings(tab: "calendars")
        }
    }
}
