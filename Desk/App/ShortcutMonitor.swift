import AppKit
import SwiftUI

/// Single-key shortcuts that work only when no text control is being edited.
/// Installed as a local key-down monitor so typing in notes is never intercepted.
@MainActor
final class ShortcutMonitor {
    private var monitor: Any?
    private let appState: AppState
    private let actions: AppActions
    /// The main planner window; events in other windows (Settings) are ignored.
    weak var window: NSWindow?

    init(appState: AppState, actions: AppActions) {
        self.appState = appState
        self.actions = actions
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors are always invoked on the main thread.
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    /// The monitor lives for the whole app session; `uninstall` exists for completeness.
    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        // A sheet or popover above the main window owns the keyboard.
        if window.attachedSheet != nil { return false }
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        guard flags.isEmpty else { return false }
        if Self.isEditingText(in: window) {
            return false
        }
        if event.keyCode == 53 { // Escape
            appState.escape()
            return true
        }
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1 else { return false }
        switch chars {
        case "t": appState.goToToday()
        case "n": appState.goToTomorrow()
        case "j": appState.goPrevious()
        case "k": appState.goNext()
        case "d": appState.show(.day)
        case "w": appState.show(.week)
        case "b": appState.requestFocus(.brainDump)
        case "p": appState.requestFocus(.firstPriority)
        case "a": actions.addBlock()
        case "?": appState.showShortcutHelp.toggle()
        default: return false
        }
        return true
    }

    /// True when the first responder is a text view or a text field's field editor.
    static func isEditingText(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        if responder is NSText { return true }
        if let view = responder as? NSView, view.enclosingScrollView?.documentView is NSTextView { return true }
        return false
    }
}

/// Captures the hosting NSWindow of a SwiftUI view hierarchy.
struct WindowReader: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in
            if let w = v?.window { onWindow(w) }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let w = nsView.window { onWindow(w) }
    }
}
