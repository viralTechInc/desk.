import Foundation

/// A calendar date without a time or time zone — the unit Desk plans in.
///
/// All date arithmetic goes through `DeskCalendar`, which pins the Gregorian
/// calendar to the user's current time zone and performs day arithmetic at noon so
/// daylight-saving transitions can never skip or duplicate a day.
struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Compact sortable integer key, e.g. 2026-11-02 → 20261102. Used as the stored
    /// primary key for daily pages and single blocks so range queries are plain integer
    /// comparisons.
    var key: Int { year * 10_000 + month * 100 + day }

    init?(key: Int) {
        guard key > 0 else { return nil }
        let y = key / 10_000
        let m = (key / 100) % 100
        let d = key % 100
        guard (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    static func < (lhs: LocalDate, rhs: LocalDate) -> Bool { lhs.key < rhs.key }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// ISO-8601 calendar date string (yyyy-MM-dd), used in backups.
    var isoString: String { description }

    init?(isoString: String) {
        let parts = isoString.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }
}

/// Days of the week, numbered like `Calendar` (Sunday = 1 … Saturday = 7).
enum Weekday: Int, CaseIterable, Codable, Sendable, Hashable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Bit used in a weekday mask (bit 0 = Sunday … bit 6 = Saturday).
    var bit: Int { 1 << (rawValue - 1) }

    var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }

    var letter: String { String(shortName.prefix(1)) }

    var fullName: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    /// Weekdays in display order starting from `first`.
    static func ordered(startingAt first: Weekday) -> [Weekday] {
        var result: [Weekday] = []
        var current = first
        for _ in 0..<7 {
            result.append(current)
            current = Weekday(rawValue: current.rawValue % 7 + 1)!
        }
        return result
    }
}

/// A set of weekdays stored as a 7-bit mask.
struct WeekdaySet: Hashable, Codable, Sendable {
    private(set) var mask: Int

    init(mask: Int) { self.mask = mask & 0b111_1111 }
    init(_ days: some Sequence<Weekday>) {
        mask = days.reduce(0) { $0 | $1.bit }
    }

    static let none = WeekdaySet(mask: 0)
    static let weekdays = WeekdaySet([.monday, .tuesday, .wednesday, .thursday, .friday])
    static let everyDay = WeekdaySet(mask: 0b111_1111)

    func contains(_ day: Weekday) -> Bool { mask & day.bit != 0 }
    mutating func insert(_ day: Weekday) { mask |= day.bit }
    mutating func remove(_ day: Weekday) { mask &= ~day.bit }
    mutating func toggle(_ day: Weekday) { contains(day) ? remove(day) : insert(day) }

    var isEmpty: Bool { mask == 0 }
    var days: [Weekday] { Weekday.allCases.filter(contains) }
    var count: Int { days.count }

    /// Short human summary like "Mon–Fri", "Every day", "Mon, Wed, Fri".
    func summary(startingAt first: Weekday = .monday) -> String {
        if mask == WeekdaySet.everyDay.mask { return "Every day" }
        if mask == WeekdaySet.weekdays.mask { return "Weekdays" }
        if mask == WeekdaySet([.saturday, .sunday]).mask { return "Weekends" }
        let ordered = Weekday.ordered(startingAt: first).filter(contains)
        return ordered.map(\.shortName).joined(separator: ", ")
    }
}

/// The calendar policy for the whole app: Gregorian, user's current time zone,
/// configurable first weekday. Everything that touches `Date` goes through here.
struct DeskCalendar: Sendable {
    var calendar: Calendar

    init(timeZone: TimeZone = .current, firstWeekday: Weekday = .monday) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = firstWeekday.rawValue
        cal.locale = .autoupdatingCurrent
        self.calendar = cal
    }

    var firstWeekday: Weekday {
        get { Weekday(rawValue: calendar.firstWeekday) ?? .monday }
        set { calendar.firstWeekday = newValue.rawValue }
    }

    var timeZone: TimeZone { calendar.timeZone }

    // MARK: Conversions

    func localDate(from date: Date) -> LocalDate {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDate(year: c.year!, month: c.month!, day: c.day!)
    }

    func today(now: Date = Date()) -> LocalDate { localDate(from: now) }

    /// Noon on the given day. Noon is used as the anchor for arithmetic because it is
    /// never skipped or repeated by daylight-saving transitions.
    func noon(_ date: LocalDate) -> Date {
        var c = DateComponents()
        c.year = date.year; c.month = date.month; c.day = date.day
        c.hour = 12; c.minute = 0; c.second = 0
        return calendar.date(from: c)!
    }

    /// Start of the given day in the user's time zone.
    func startOfDay(_ date: LocalDate) -> Date {
        calendar.startOfDay(for: noon(date))
    }

    /// A specific wall-clock time on a day. On a day whose clocks skip the requested
    /// time, `Calendar` returns the next valid instant.
    func date(_ date: LocalDate, minutesFromMidnight: Int) -> Date {
        var c = DateComponents()
        c.year = date.year; c.month = date.month; c.day = date.day
        c.hour = minutesFromMidnight / 60; c.minute = minutesFromMidnight % 60
        return calendar.date(from: c) ?? startOfDay(date).addingTimeInterval(TimeInterval(minutesFromMidnight * 60))
    }

    /// Wall-clock minutes since midnight for an instant (0..<1440).
    func minutesFromMidnight(_ instant: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: instant)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: Arithmetic

    func adding(days: Int, to date: LocalDate) -> LocalDate {
        let shifted = calendar.date(byAdding: .day, value: days, to: noon(date))!
        return localDate(from: shifted)
    }

    func adding(weeks: Int, to date: LocalDate) -> LocalDate {
        adding(days: weeks * 7, to: date)
    }

    func days(from: LocalDate, to: LocalDate) -> Int {
        calendar.dateComponents([.day], from: startOfDay(from), to: startOfDay(to)).day!
    }

    func weekday(of date: LocalDate) -> Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: noon(date)))!
    }

    /// The first day of the week containing `date`, honoring `firstWeekday`.
    func startOfWeek(containing date: LocalDate) -> LocalDate {
        let wd = weekday(of: date).rawValue
        let offset = (wd - calendar.firstWeekday + 7) % 7
        return adding(days: -offset, to: date)
    }

    /// Seven consecutive days starting at the week start.
    func weekDays(containing date: LocalDate) -> [LocalDate] {
        let start = startOfWeek(containing: date)
        return (0..<7).map { adding(days: $0, to: start) }
    }

    /// Inclusive sequence of days.
    func days(in range: ClosedRange<LocalDate>) -> [LocalDate] {
        var result: [LocalDate] = []
        var d = range.lowerBound
        while d <= range.upperBound {
            result.append(d)
            d = adding(days: 1, to: d)
        }
        return result
    }

    // MARK: Formatting

    func headingString(_ date: LocalDate) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = calendar.locale
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return f.string(from: noon(date))
    }

    func subtitleString(_ date: LocalDate, today: LocalDate) -> String? {
        let delta = days(from: today, to: date)
        switch delta {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = calendar.locale
            f.setLocalizedDateFormatFromTemplate("yyyy")
            let year = f.string(from: noon(date))
            if abs(delta) <= 6 {
                return delta > 0 ? "In \(delta) days" : "\(abs(delta)) days ago"
            }
            return year
        }
    }

    func shortDayString(_ date: LocalDate) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = calendar.locale
        f.setLocalizedDateFormatFromTemplate("EEE d")
        return f.string(from: noon(date))
    }

    func weekRangeString(containing date: LocalDate) -> String {
        let days = weekDays(containing: date)
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = calendar.locale
        let first = days[0], last = days[6]
        if first.month == last.month {
            f.setLocalizedDateFormatFromTemplate("MMMM d")
            let a = f.string(from: noon(first))
            return "\(a) – \(last.day), \(last.year)"
        } else {
            f.setLocalizedDateFormatFromTemplate("MMM d")
            let a = f.string(from: noon(first))
            let b = f.string(from: noon(last))
            return first.year == last.year ? "\(a) – \(b), \(last.year)" : "\(a), \(first.year) – \(b), \(last.year)"
        }
    }
}

/// Formatting helpers for minutes-from-midnight values.
enum TimeFormat {
    /// "6:00", "13:30" (24h) or "6 AM" style depending on locale preference.
    static func clock(_ minutes: Int, compact: Bool = false) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        let h = m / 60, mm = m % 60
        if uses24Hour {
            return compact && mm == 0 ? String(format: "%d:00", h) : String(format: "%d:%02d", h, mm)
        }
        let suffix = h < 12 ? "AM" : "PM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        if compact {
            return mm == 0 ? "\(h12) \(suffix)" : String(format: "%d:%02d %@", h12, mm, suffix)
        }
        return String(format: "%d:%02d %@", h12, mm, suffix)
    }

    /// "8:00 – 12:00"
    static func range(_ start: Int, _ end: Int) -> String {
        "\(clock(start)) – \(clock(end))"
    }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return h == 1 ? "1 hr" : "\(h) hr"
        default: return "\(h) hr \(m) min"
        }
    }

    static var uses24Hour: Bool {
        let f = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? ""
        return !f.contains("a")
    }

    /// Parses "9", "9:30", "930", "9:30 pm", "14h" into minutes from midnight.
    static func parse(_ text: String) -> Int? {
        var s = text.trimmingCharacters(in: .whitespaces).lowercased()
        var pm: Bool? = nil
        if s.hasSuffix("pm") { pm = true; s.removeLast(2) }
        else if s.hasSuffix("am") { pm = false; s.removeLast(2) }
        else if s.hasSuffix("p") { pm = true; s.removeLast() }
        else if s.hasSuffix("a") { pm = false; s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "h", with: ":")
        if s.hasSuffix(":") { s.removeLast() }
        var h = 0, m = 0
        if let colon = s.firstIndex(where: { $0 == ":" || $0 == "." }) {
            guard let hh = Int(s[..<colon]), let mm = Int(s[s.index(after: colon)...]) else { return nil }
            h = hh; m = mm
        } else {
            guard let n = Int(s) else { return nil }
            if n >= 100 { h = n / 100; m = n % 100 } else { h = n }
        }
        if let pm {
            if pm && h < 12 { h += 12 }
            if !pm && h == 12 { h = 0 }
        }
        guard (0...24).contains(h), (0..<60).contains(m) else { return nil }
        let total = h * 60 + m
        return total > 1440 ? nil : total
    }
}

/// Encoded as a "yyyy-MM-dd" string so backups stay human-readable.
extension LocalDate: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let d = LocalDate(isoString: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date \(s)")
        }
        self = d
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(isoString)
    }
}
