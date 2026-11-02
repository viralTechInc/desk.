import AppKit
import EventKit
import Observation
import SwiftUI

/// Read-only bridge to the macOS calendar database (iCloud, Google, Exchange… whatever is
/// set up in System Settings → Internet Accounts). The OS syncs; Desk only observes.
@MainActor
@Observable
final class CalendarService {
    enum Access: Equatable, Sendable {
        case notDetermined
        case authorized
        case denied
        case restricted
        case writeOnly
    }

    private(set) var access: Access
    private(set) var calendars: [CalendarInfo] = []
    /// Bumped whenever the system calendar database or the selection changes.
    private(set) var revision = 0
    private(set) var lastError: String?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var disabledIDs: Set<String>

    private enum Keys {
        static let disabled = "calendar.disabledIDs"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.access = Self.map(EKEventStore.authorizationStatus(for: .event))
        self.disabledIDs = Set(defaults.stringArray(forKey: Keys.disabled) ?? [])
        if access == .authorized { refreshCalendars() }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.databaseChanged() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.databaseChanged() }
        })
        observers.append(center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.databaseChanged() }
        })
    }

    // MARK: Access

    var isAvailable: Bool { access == .authorized }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            access = granted ? .authorized : Self.map(EKEventStore.authorizationStatus(for: .event))
            lastError = nil
        } catch {
            access = Self.map(EKEventStore.authorizationStatus(for: .event))
            lastError = error.localizedDescription
        }
        refreshCalendars()
    }

    func openSystemPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInternetAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func map(_ status: EKAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .fullAccess, .authorized: .authorized
        case .writeOnly: .writeOnly
        @unknown default: .denied
        }
    }

    // MARK: Calendars & selection

    func refreshCalendars() {
        guard access == .authorized else { calendars = []; revision &+= 1; return }
        store.refreshSourcesIfNecessary()
        calendars = store.calendars(for: .event).map { cal in
            let source = cal.source
            return CalendarInfo(
                id: cal.calendarIdentifier, title: cal.title,
                sourceID: source?.sourceIdentifier ?? "", sourceTitle: source?.title ?? "Other",
                sourceKind: Self.kind(of: source), color: Color(nsColor: cal.color ?? .systemGray),
                allowsModifications: cal.allowsContentModifications)
        }
        .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
        revision &+= 1
    }

    private static func kind(of source: EKSource?) -> String {
        guard let source else { return "Other" }
        switch source.sourceType {
        case .local: return "On My Mac"
        case .calDAV: return source.title.localizedCaseInsensitiveContains("google") ? "Google" : "CalDAV"
        case .exchange: return "Exchange"
        case .mobileMe: return "iCloud"
        case .subscribed: return "Subscription"
        case .birthdays: return "Birthdays"
        @unknown default: return "Other"
        }
    }

    /// Calendars grouped by account, preserving sorted order.
    var calendarsBySource: [(source: String, kind: String, calendars: [CalendarInfo])] {
        var order: [String] = []
        var groups: [String: [CalendarInfo]] = [:]
        var kinds: [String: String] = [:]
        for c in calendars {
            if groups[c.sourceID] == nil { order.append(c.sourceID); kinds[c.sourceID] = c.sourceKind }
            groups[c.sourceID, default: []].append(c)
        }
        return order.map { id in (groups[id]!.first!.sourceTitle, kinds[id] ?? "", groups[id]!) }
    }

    /// Newly discovered calendars are enabled by default; the user opts out per calendar.
    func isEnabled(_ calendar: CalendarInfo) -> Bool { !disabledIDs.contains(calendar.id) }

    var enabledCalendarIDs: Set<String> {
        Set(calendars.filter(isEnabled).map(\.id))
    }

    func setEnabled(_ enabled: Bool, for calendar: CalendarInfo) {
        if enabled { disabledIDs.remove(calendar.id) } else { disabledIDs.insert(calendar.id) }
        defaults.set(Array(disabledIDs).sorted(), forKey: Keys.disabled)
        revision &+= 1
    }

    func setAll(enabled: Bool) {
        disabledIDs = enabled ? [] : Set(calendars.map(\.id))
        defaults.set(Array(disabledIDs).sorted(), forKey: Keys.disabled)
        revision &+= 1
    }

    // MARK: Events

    /// Per-day slices of every event on enabled calendars within the range. Fetched fresh
    /// from EventKit each call; callers depend on `revision` to re-query after changes.
    func events(in range: ClosedRange<LocalDate>, calendar deskCalendar: DeskCalendar) -> [ExternalEvent] {
        guard access == .authorized else { return [] }
        let enabled = store.calendars(for: .event).filter { !disabledIDs.contains($0.calendarIdentifier) }
        guard !enabled.isEmpty else { return [] }
        let start = deskCalendar.startOfDay(range.lowerBound)
        let end = deskCalendar.startOfDay(deskCalendar.adding(days: 1, to: range.upperBound))
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: enabled)
        let events = store.events(matching: predicate)
        var result: [ExternalEvent] = []
        var seen: Set<String> = []
        for ev in events {
            guard let startDate = ev.startDate, let endDate = ev.endDate else { continue }
            let source = ExternalEventSplitter.Source(
                eventIdentifier: ev.eventIdentifier ?? ev.calendarItemIdentifier,
                title: ev.title ?? "", start: startDate, end: endDate, isAllDay: ev.isAllDay,
                calendarID: ev.calendar.calendarIdentifier, calendarTitle: ev.calendar.title,
                sourceTitle: ev.calendar.source?.title ?? "", color: Color(nsColor: ev.calendar.color ?? .systemGray),
                location: ev.location, isBusy: ev.availability != .free)
            for slice in ExternalEventSplitter.slices(of: source, in: range, calendar: deskCalendar) where !seen.contains(slice.id) {
                seen.insert(slice.id)
                result.append(slice)
            }
        }
        return result
    }

    /// Opens the event in the Calendar app (falls back to launching Calendar).
    func openInCalendar(_ event: ExternalEvent) {
        if let url = URL(string: "ical://ekevent/\(event.eventIdentifier)"), NSWorkspace.shared.open(url) { return }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func databaseChanged() {
        let status = Self.map(EKEventStore.authorizationStatus(for: .event))
        if status != access { access = status }
        refreshCalendars()
    }
}
