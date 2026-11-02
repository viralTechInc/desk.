import SwiftUI
import Observation

enum ViewMode: String, CaseIterable, Identifiable {
    case day, week
    var id: String { rawValue }
    var label: String { self == .day ? "Day" : "Week" }
}

enum FocusTarget: Equatable {
    case brainDump
    case firstPriority
}

/// A deferred edit on a recurring occurrence that first needs the user to choose a scope.
struct ScopePrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let apply: @MainActor (EditScope) -> Void
}

/// Navigation, selection and transient UI state. Not persisted (except the last view mode
/// for the session, which the spec asks to remember only while running).
@MainActor
@Observable
final class AppState {
    var viewMode: ViewMode = .day
    var selectedDate: LocalDate
    private(set) var today: LocalDate
    var calendar: DeskCalendar

    /// Occurrence whose editor popover is open, and whether it was just created.
    var editingOccurrenceID: String?
    var editingIsNew = false
    var selectedOccurrenceID: String?

    var scopePrompt: ScopePrompt?
    var seriesDeletion: EventOccurrence?
    var showShortcutHelp = false
    var alert: AlertContent?
    var pendingImport: BackupDocument?
    var confirmDemoData = false

    /// Incremented to request focus; the target says where.
    private(set) var focusRequest: (target: FocusTarget, token: Int) = (.brainDump, 0)

    struct AlertContent: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    init(calendar: DeskCalendar = DeskCalendar(), now: Date = Date()) {
        self.calendar = calendar
        self.today = calendar.today(now: now)
        self.selectedDate = calendar.today(now: now)
    }

    // MARK: Navigation

    var isViewingToday: Bool { selectedDate == today }

    var weekDays: [LocalDate] { calendar.weekDays(containing: selectedDate) }

    func goToToday() { select(today) }
    func goToTomorrow() { select(calendar.adding(days: 1, to: today)) }

    func goPrevious() {
        select(viewMode == .day ? calendar.adding(days: -1, to: selectedDate) : calendar.adding(weeks: -1, to: selectedDate))
    }

    func goNext() {
        select(viewMode == .day ? calendar.adding(days: 1, to: selectedDate) : calendar.adding(weeks: 1, to: selectedDate))
    }

    func select(_ date: LocalDate) {
        guard date != selectedDate else { return }
        selectedDate = date
        dismissOverlays()
    }

    func show(_ mode: ViewMode) {
        guard mode != viewMode else { return }
        viewMode = mode
        dismissOverlays()
    }

    func showDay(_ date: LocalDate) {
        selectedDate = date
        viewMode = .day
        dismissOverlays()
    }

    func refreshToday(now: Date = Date()) {
        let t = calendar.today(now: now)
        if t != today { today = t }
    }

    func updateCalendar(_ cal: DeskCalendar) {
        calendar = cal
        refreshToday()
    }

    // MARK: Overlays & focus

    func dismissOverlays() {
        editingOccurrenceID = nil
        editingIsNew = false
        selectedOccurrenceID = nil
        showShortcutHelp = false
    }

    /// Esc: close whatever is open, else deselect.
    func escape() {
        if showShortcutHelp { showShortcutHelp = false; return }
        if editingOccurrenceID != nil { editingOccurrenceID = nil; editingIsNew = false; return }
        selectedOccurrenceID = nil
    }

    func requestFocus(_ target: FocusTarget) {
        if viewMode != .day { viewMode = .day }
        focusRequest = (target, focusRequest.token + 1)
    }

    func edit(_ occurrence: EventOccurrence, isNew: Bool = false) {
        selectedOccurrenceID = occurrence.id
        editingOccurrenceID = occurrence.id
        editingIsNew = isNew
    }

    /// Where a new block created via the Add Block command should land.
    func defaultNewBlockSlot(now: Date = Date()) -> (date: LocalDate, start: Int) {
        let date = viewMode == .day ? selectedDate : (weekDays.contains(today) ? today : weekDays[0])
        if date == today {
            let m = TimeRules.snap(calendar.minutesFromMidnight(now) + 30)
            return (date, min(m, TimeRules.dayMinutes - 60))
        }
        return (date, 9 * 60)
    }
}
