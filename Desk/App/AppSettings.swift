import AppKit
import SwiftUI
import Observation

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Minimal user preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    /// What is actually on screen now: the chosen theme, or the system's when set to System.
    var effectiveColorScheme: ColorScheme {
        if let scheme = appearance.colorScheme { return scheme }
        let match = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
    }

    /// Flips between light and dark from whatever is showing; leaves System mode behind.
    func toggleAppearance() {
        appearance = effectiveColorScheme == .dark ? .light : .dark
    }

    @ObservationIgnored private let defaults: UserDefaults

    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    var startHour: Int { didSet { defaults.set(startHour, forKey: Keys.startHour) } }
    var endHour: Int { didSet { defaults.set(endHour, forKey: Keys.endHour) } }
    var firstWeekday: Weekday { didSet { defaults.set(firstWeekday.rawValue, forKey: Keys.firstWeekday) } }
    var showWeeklyIntentions: Bool { didSet { defaults.set(showWeeklyIntentions, forKey: Keys.showIntentions) } }
    var hourHeight: Double { didSet { defaults.set(hourHeight, forKey: Keys.hourHeight) } }
    /// Pencil-hatch the hours and days that have passed and grey out their blocks.
    var shadeElapsed: Bool { didSet { defaults.set(shadeElapsed, forKey: Keys.shadeElapsed) } }

    enum Keys {
        static let appearance = "appearance"
        static let startHour = "visibleStartHour"
        static let endHour = "visibleEndHour"
        static let firstWeekday = "firstWeekday"
        static let showIntentions = "showWeeklyIntentions"
        static let hourHeight = "hourHeight"
        static let shadeElapsed = "shadeElapsed"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        let s = defaults.object(forKey: Keys.startHour) as? Int ?? 6
        let e = defaults.object(forKey: Keys.endHour) as? Int ?? 22
        let clampedStart = min(max(s, 0), 23)
        startHour = clampedStart
        endHour = min(max(e, clampedStart + 1), 24)
        firstWeekday = Weekday(rawValue: defaults.object(forKey: Keys.firstWeekday) as? Int ?? 2) ?? .monday
        showWeeklyIntentions = defaults.object(forKey: Keys.showIntentions) as? Bool ?? true
        hourHeight = defaults.object(forKey: Keys.hourHeight) as? Double ?? 0
        shadeElapsed = defaults.object(forKey: Keys.shadeElapsed) as? Bool ?? true
    }

    /// Minimum hour height when fitting; below this the grid scrolls instead.
    static let minimumHourHeight: CGFloat = 22

    /// `hourHeight == 0` means "fit the visible hours into the available height" so the
    /// whole day is on screen without scrolling.
    func geometry(fitting availableHeight: CGFloat) -> TimelineGeometry {
        let hours = CGFloat(max(endHour - startHour, 1))
        let height: CGFloat
        if hourHeight > 0 {
            height = hourHeight
        } else {
            height = max(Self.minimumHourHeight, (availableHeight / hours).rounded(.down))
        }
        return TimelineGeometry(startHour: startHour, endHour: endHour, hourHeight: height)
    }
}
