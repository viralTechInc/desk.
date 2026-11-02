import SwiftUI
import SwiftData

/// Wires the store, settings, navigation state and actions together once per launch.
@MainActor
final class AppModel {
    let store: PlannerStore
    let settings: AppSettings
    let appState: AppState
    let actions: AppActions
    let shortcuts: ShortcutMonitor
    let calendarService: CalendarService
    let sharing: SharingService
    let feed: ScheduleFeed
    let startupError: String?

    init() {
        let settings = AppSettings()
        let calendar = DeskCalendar(firstWeekday: settings.firstWeekday)
        var startupError: String?
        let container: ModelContainer
        do {
            container = try DeskSchema.container()
        } catch {
            startupError = "Desk couldn't open its data file (\(error.localizedDescription)). Running without saving — export a backup of anything you type."
            container = try! DeskSchema.container(inMemory: true)
        }
        let store = PlannerStore(container: container, calendar: calendar)
        let appState = AppState(calendar: calendar)
        let actions = AppActions(store: store, appState: appState, settings: settings)
        self.store = store
        self.settings = settings
        self.appState = appState
        self.actions = actions
        self.shortcuts = ShortcutMonitor(appState: appState, actions: actions)
        self.calendarService = CalendarService()
        var shareFolder: URL?
        var shareDefaults = UserDefaults.standard
        #if DEBUG
        // Scripted runs point at a plain folder instead of a remembered bookmark, with their
        // own preferences so two scratch instances get distinct identities and the real
        // app's sharing settings are never touched.
        let env = ProcessInfo.processInfo.environment
        if let path = env["DESK_SHARE_FOLDER"], !path.isEmpty {
            shareFolder = URL(fileURLWithPath: path, isDirectory: true)
            let name = env["DESK_SHARE_NAME"] ?? "scratch"
            shareDefaults = UserDefaults(suiteName: "com.desk.planner.scratch-share-\(name)") ?? .standard
            shareDefaults.set(name, forKey: SharingService.Keys.displayName)
        }
        #endif
        self.sharing = SharingService(store: store, defaults: shareDefaults, folderOverride: shareFolder)
        self.feed = ScheduleFeed(store: store, calendarService: calendarService, appState: appState)
        self.startupError = startupError
        shortcuts.install()
        #if DEBUG
        DebugHooks.install(model: self)
        #endif
    }

    func attach(window: NSWindow) {
        shortcuts.window = window
        actions.window = window
        #if DEBUG
        // UI tests pin the window size so layout-dependent coordinates are deterministic.
        if let spec = ProcessInfo.processInfo.environment["DESK_WINDOW_SIZE"], !didApplyWindowSize,
           let x = spec.firstIndex(of: "x"), let w = Double(spec[..<x]), let h = Double(spec[spec.index(after: x)...]) {
            didApplyWindowSize = true
            window.setContentSize(NSSize(width: w, height: h))
            window.center()
        }
        #endif
    }

    private var didApplyWindowSize = false
}

@main
struct DeskApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Desk", id: "main") {
            RootView()
                .environment(model.appState)
                .environment(model.store)
                .environment(model.settings)
                .environment(model.actions)
                .environment(model.calendarService)
                .environment(model.sharing)
                .frame(minWidth: 760, minHeight: 540)
                .onAppear {
                    if let err = model.startupError {
                        model.appState.alert = .init(title: "Data unavailable", message: err)
                    }
                }
                .background(WindowReader { window in model.attach(window: window) })
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands { DeskCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model.settings)
                .environment(model.actions)
                .environment(model.store)
                .environment(model.appState)
                .environment(model.calendarService)
                .environment(model.sharing)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model.feed)
                .environment(model.appState)
                .environment(model.store)
                .environment(model.calendarService)
        } label: {
            MenuBarLabel()
                .environment(model.feed)
                .environment(model.store)
                .environment(model.calendarService)
        }
        .menuBarExtraStyle(.window)
    }
}

extension AppActions: Observable {}
