import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Commands shared by menus, shortcuts and views. Owns the file dialogs and the
/// "ask which scope" step for recurring occurrences.
@MainActor
final class AppActions {
    let store: PlannerStore
    let appState: AppState
    let settings: AppSettings
    weak var window: NSWindow?

    init(store: PlannerStore, appState: AppState, settings: AppSettings) {
        self.store = store
        self.appState = appState
        self.settings = settings
    }

    // MARK: Blocks

    var lastCategory: BlockCategory {
        get { BlockCategory(rawValue: UserDefaults.standard.string(forKey: "lastCategory") ?? "") ?? .work }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lastCategory") }
    }

    /// "A" / ⌘N: adds a one-hour block at a sensible slot and opens its editor.
    func addBlock() {
        let slot = appState.defaultNewBlockSlot()
        createBlock(date: slot.date, start: slot.start, end: min(slot.start + 60, TimeRules.dayMinutes))
    }

    func createBlock(date: LocalDate, start: Int, end: Int) {
        let draft = BlockDraft(title: "", date: date, startMinutes: start, endMinutes: end, category: lastCategory)
        if let occ = store.createBlock(draft) {
            appState.edit(occ, isNew: true)
        }
    }

    func move(_ occ: EventOccurrence, toDate date: LocalDate, startMinutes: Int) {
        guard occ.date != date || occ.startMinutes != startMinutes else { return }
        withScope(for: occ, verb: "Move") { [store] scope in
            store.move(occ, toDate: date, startMinutes: startMinutes, scope: scope)
        }
    }

    func resize(_ occ: EventOccurrence, endMinutes: Int) {
        guard occ.endMinutes != endMinutes else { return }
        withScope(for: occ, verb: "Resize") { [store] scope in
            store.resize(occ, endMinutes: endMinutes, scope: scope)
        }
    }

    func delete(_ occ: EventOccurrence) {
        if occ.isRecurring {
            appState.scopePrompt = ScopePrompt(
                title: "Remove “\(occ.displayTitle)”",
                message: "Skip just this occurrence, or delete the whole routine?",
                apply: { [weak self] scope in
                    guard let self else { return }
                    switch scope {
                    case .thisOccurrence: self.store.delete(occ, scope: .thisOccurrence)
                    case .entireSeries: self.appState.seriesDeletion = occ
                    }
                })
        } else {
            store.delete(occ, scope: .thisOccurrence)
        }
        if appState.editingOccurrenceID == occ.id { appState.editingOccurrenceID = nil }
    }

    func deleteSeriesConfirmed(_ occ: EventOccurrence) {
        store.delete(occ, scope: .entireSeries)
        if appState.editingOccurrenceID == occ.id { appState.editingOccurrenceID = nil }
    }

    func duplicate(_ occ: EventOccurrence) {
        if let copy = store.duplicate(occ) {
            appState.selectedOccurrenceID = copy.id
        }
    }

    private func withScope(for occ: EventOccurrence, verb: String, _ apply: @escaping @MainActor (EditScope) -> Void) {
        if occ.isRecurring {
            appState.scopePrompt = ScopePrompt(
                title: "\(verb) “\(occ.displayTitle)”",
                message: "Change only this occurrence, or every week of the routine?",
                apply: apply)
        } else {
            apply(.thisOccurrence)
        }
    }

    // MARK: Undo

    /// ⌘Z: text controls undo their own typing; otherwise the planner's block history.
    func undo() {
        if let window, ShortcutMonitor.isEditingText(in: window) {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        } else {
            store.undoManager.undo()
        }
    }

    func redo() {
        if let window, ShortcutMonitor.isEditingText(in: window) {
            NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
        } else {
            store.undoManager.redo()
        }
    }

    // MARK: Backup

    func exportBackup() {
        store.flush()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Desk Backup \(appState.today.isoString).json"
        panel.title = "Export Backup"
        panel.message = "Everything in Desk — notes, blocks and routines — as one JSON file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try store.exportBackup()
            try data.write(to: url, options: .atomic)
        } catch {
            appState.alert = .init(title: "Couldn't export", message: error.localizedDescription)
        }
    }

    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "Import Backup"
        panel.message = "Choose a Desk backup. You'll be asked to confirm before anything is replaced."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let doc = try PlannerStore.decodeBackup(data)
            appState.pendingImport = doc
        } catch {
            appState.alert = .init(title: "Couldn't read backup", message: error.localizedDescription)
        }
    }

    func importConfirmed(_ doc: BackupDocument) {
        do {
            try store.importBackup(doc)
            appState.dismissOverlays()
        } catch {
            appState.alert = .init(title: "Import failed", message: error.localizedDescription)
        }
    }

    func loadDemoData() {
        let doc = SeedData.document(weekContaining: appState.today, calendar: store.calendar)
        store.insert(doc)
        store.afterBulkChange()
    }

    func removeDemoData() {
        let removed = store.removeDemoData(weekContaining: appState.today)
        appState.alert = .init(
            title: removed == 0 ? "No demo data found" : "Demo data removed",
            message: removed == 0
                ? "Nothing matching the sample week is in your planner."
                : "Removed \(removed) sample item\(removed == 1 ? "" : "s"). Your own notes and blocks were left as they were.")
    }

    func revealDataFolder() {
        if let url = try? DeskSchema.storeURL() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
