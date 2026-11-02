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
}
