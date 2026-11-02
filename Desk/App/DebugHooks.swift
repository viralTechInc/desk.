import AppKit
import SwiftUI

#if DEBUG
/// Development-only remote control used by `scripts/desk-debug` for screenshots and
/// scripted smoke tests. Compiled out of release builds.
@MainActor
enum DebugHooks {
    static let name = Notification.Name("com.desk.planner.debug")

    static func install(model: AppModel) {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { note in
            let info = note.userInfo as? [String: String] ?? [:]
            MainActor.assumeIsolated { handle(info, model: model) }
        }
    }

    private static func handle(_ info: [String: String], model: AppModel) {
        let state = model.appState
        switch info["cmd"] {
        case "screenshot":
            if let path = info["path"] { capture(to: path) }
        case "action":
            switch info["name"] {
            case "today": state.goToToday()
            case "tomorrow": state.goToTomorrow()
            case "prev": state.goPrevious()
            case "next": state.goNext()
            case "day": state.show(.day)
            case "week": state.show(.week)
            case "addBlock": model.actions.addBlock()
            case "demo": model.actions.loadDemoData()
            case "help": state.showShortcutHelp = true
            case "escape": state.escape()
            case "focusBrain": state.requestFocus(.brainDump)
            case "focusPriority": state.requestFocus(.firstPriority)
            case "undo": model.actions.undo()
            case "redo": model.actions.redo()
            case "flush": model.store.flush()
            case "settings":
                if let tab = info["value"] { state.settingsTab = tab }
                NSApp.activate(ignoringOtherApps: true)
                let handled = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    || NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                DebugTrace.log("settings handled=\(handled) windows=\(NSApp.windows.map { "\($0.title):\($0.isVisible):\(Int($0.frame.width))" })")
            case "previewCalendars":
                // Hosts the Calendars settings pane in a plain window for screenshots.
                let host = NSHostingController(rootView: CalendarSettingsView()
                    .environment(model.calendarService).environment(state).frame(width: 520, height: 480))
                let w = NSWindow(contentViewController: host)
                w.title = "Calendars preview"
                w.makeKeyAndOrderFront(nil)
            case "quit": NSApp.terminate(nil)
            default: break
            }
        case "date":
            if let s = info["value"], let d = LocalDate(isoString: s) { state.select(d) }
        case "resize":
            if let w = info["w"].flatMap(Double.init), let h = info["h"].flatMap(Double.init),
               let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) ?? NSApp.mainWindow {
                var f = window.frame
                f.origin.y += f.height - h
                f.size = NSSize(width: w, height: h)
                window.setFrame(f, display: true, animate: false)
            }
        case "edit":
            // Open the editor for the first occurrence on the selected date.
            if let occ = model.store.occurrences(on: state.selectedDate).first { state.edit(occ) }
        case "type":
            if let text = info["value"], let window = NSApp.keyWindow, let tv = window.firstResponder as? NSTextView {
                tv.insertText(text, replacementRange: tv.selectedRange())
            }
        case "click":
            // Note: posted events reach AppKit controls and SwiftUI buttons, but not SwiftUI
            // gestures (drag/tap on the grid). Those are covered by DeskUITests instead.
            if let x = info["x"].flatMap(Double.init), let y = info["y"].flatMap(Double.init) {
                synthesizeClick(at: CGPoint(x: x, y: y))
            }
        case "key":
            if let chars = info["value"], let window = mainWindow {
                let flags: NSEvent.ModifierFlags = info["cmd"] == "1" ? [.command] : []
                let code: UInt16 = chars == "esc" ? 53 : (chars == "return" ? 36 : 0)
                let text = chars == "esc" ? "\u{1B}" : (chars == "return" ? "\r" : chars)
                if let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, characters: text,
                                               charactersIgnoringModifiers: text, isARepeat: false, keyCode: code) {
                    NSApp.postEvent(down, atStart: false)
                }
            }
        case "dump":
            // Writes the selected week's occurrences as text for assertions.
            if let path = info["path"] {
                let days = state.weekDays
                let lines = model.store.occurrences(in: days[0]...days[6]).map {
                    "\($0.date.isoString) \(TimeFormat.clock($0.startMinutes))-\(TimeFormat.clock($0.endMinutes)) \($0.displayTitle)\($0.isRecurring ? " [R]" : "")\($0.isException ? " [X]" : "")"
                }
                let page = model.store.pageRecord(for: state.selectedDate)
                let text = (lines + ["---", "priorities: \(page?.priorities ?? [])", "brainDump: \(page?.brainDump.debugDescription ?? "nil")"]).joined(separator: "\n")
                try? text.write(toFile: path, atomically: true, encoding: .utf8)
            }
        case "appearance":
            if let v = info["value"], let a = Appearance(rawValue: v) { model.settings.appearance = a }
        default:
            break
        }
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.frame.width > 400 && !($0 is NSPanel) }
    }

    private static func synthesizeClick(at p: CGPoint) {
        guard let window = mainWindow, let content = window.contentView else { return }
        let loc = CGPoint(x: p.x, y: content.bounds.height - p.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: type, location: loc, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                NSApp.postEvent(e, atStart: false)
            }
        }
    }

    /// Renders every visible window of the app (main window, popovers, sheets) to PNG files.
    private static func capture(to path: String) {
        let base = (path as NSString).deletingPathExtension
        var index = 0
        for window in NSApp.windows where window.isVisible && window.contentView != nil {
            guard let view = window.contentView, view.bounds.width > 10 else { continue }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            let file = index == 0 ? "\(base).png" : "\(base)-\(index).png"
            do { try data.write(to: URL(fileURLWithPath: file)) } catch { DebugTrace.log("capture failed \(error)") }
            index += 1
        }
    }
}
#endif

#if DEBUG
/// File-backed trace for development runs (unified logging from a sandboxed app is hard to read
/// from the terminal). Appends to <container>/tmp/desk-trace.log.
enum DebugTrace {
    nonisolated(unsafe) private static let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("desk-trace.log")
    static func log(_ message: @autoclosure () -> String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message())\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
#endif
