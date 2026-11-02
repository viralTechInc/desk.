import Foundation

// Plain Codable value records mirroring the persistence models. They serve two purposes:
// undo snapshots (restore exact prior state) and the JSON backup format.

struct PageRecord: Codable, Hashable, Sendable {
    var date: LocalDate
    var priorities: [String]
    var brainDump: String
    var createdAt: Date
    var updatedAt: Date
}

struct WeekRecord: Codable, Hashable, Sendable {
    var weekStart: LocalDate
    var intentions: [String]
    var updatedAt: Date
}

struct BlockRecord: Codable, Hashable, Sendable {
    var id: UUID
    var date: LocalDate
    var title: String
    var startMinutes: Int
    var endMinutes: Int
    var category: BlockCategory
    var note: String
    var createdAt: Date
    var updatedAt: Date
}

struct RuleRecord: Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var category: BlockCategory
    var note: String
    var startMinutes: Int
    var endMinutes: Int
    var weekdays: WeekdaySet
    var effectiveStart: LocalDate
    var effectiveEnd: LocalDate?
    var createdAt: Date
    var updatedAt: Date
}

struct OverrideRecord: Codable, Hashable, Sendable {
    var id: UUID
    var ruleID: UUID
    var originalDate: LocalDate
    var isCancelled: Bool
    var date: LocalDate?
    var title: String?
    var startMinutes: Int?
    var endMinutes: Int?
    var category: BlockCategory?
    var note: String?
    var updatedAt: Date
}

/// Everything Desk stores, as one document.
struct BackupDocument: Codable, Sendable {
    var app = "Desk"
    var version: Int = DeskSchema.backupVersion
    var exportedAt: Date
    var timeZone: String
    var pages: [PageRecord]
    var weeks: [WeekRecord]
    var blocks: [BlockRecord]
    var rules: [RuleRecord]
    var overrides: [OverrideRecord]

    var summary: String {
        var parts: [String] = []
        parts.append("\(pages.count) daily page\(pages.count == 1 ? "" : "s")")
        parts.append("\(blocks.count) block\(blocks.count == 1 ? "" : "s")")
        parts.append("\(rules.count) routine\(rules.count == 1 ? "" : "s")")
        return parts.joined(separator: ", ")
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

// MARK: - Model ↔ record mapping

extension DailyPage {
    var record: PageRecord {
        PageRecord(date: date, priorities: priorities, brainDump: brainDump, createdAt: createdAt, updatedAt: updatedAt)
    }
    convenience init(record r: PageRecord) {
        self.init(dateKey: r.date.key, priorities: r.priorities, brainDump: r.brainDump, now: r.createdAt)
        self.updatedAt = r.updatedAt
    }
}

extension WeeklyPage {
    var record: WeekRecord {
        WeekRecord(weekStart: LocalDate(key: weekStartKey)!, intentions: intentions, updatedAt: updatedAt)
    }
    convenience init(record r: WeekRecord) {
        self.init(weekStartKey: r.weekStart.key, intentions: r.intentions, now: r.updatedAt)
    }
}

extension TimeBlock {
    var record: BlockRecord {
        BlockRecord(id: id, date: LocalDate(key: dateKey)!, title: title, startMinutes: startMinutes,
                    endMinutes: endMinutes, category: category, note: note, createdAt: createdAt, updatedAt: updatedAt)
    }
    convenience init(record r: BlockRecord) {
        self.init(id: r.id, dateKey: r.date.key, title: r.title, startMinutes: r.startMinutes,
                  endMinutes: r.endMinutes, category: r.category, note: r.note, now: r.createdAt)
        self.updatedAt = r.updatedAt
    }
    func apply(_ r: BlockRecord) {
        dateKey = r.date.key; title = r.title; startMinutes = r.startMinutes; endMinutes = r.endMinutes
        category = r.category; note = r.note; createdAt = r.createdAt; updatedAt = r.updatedAt
    }
    var input: SingleBlockInput {
        SingleBlockInput(id: id, date: LocalDate(key: dateKey)!, title: title, category: category,
                         note: note, startMinutes: startMinutes, endMinutes: endMinutes)
    }
}

extension RecurrenceRule {
    var record: RuleRecord {
        RuleRecord(id: id, title: title, category: category, note: note, startMinutes: startMinutes,
                   endMinutes: endMinutes, weekdays: weekdays, effectiveStart: LocalDate(key: effectiveStartKey)!,
                   effectiveEnd: effectiveEndKey.flatMap(LocalDate.init(key:)), createdAt: createdAt, updatedAt: updatedAt)
    }
    convenience init(record r: RuleRecord) {
        self.init(id: r.id, title: r.title, category: r.category, note: r.note, startMinutes: r.startMinutes,
                  endMinutes: r.endMinutes, weekdays: r.weekdays, effectiveStart: r.effectiveStart,
                  effectiveEnd: r.effectiveEnd, now: r.createdAt)
        self.updatedAt = r.updatedAt
    }
    func apply(_ r: RuleRecord) {
        title = r.title; category = r.category; note = r.note; startMinutes = r.startMinutes; endMinutes = r.endMinutes
        weekdays = r.weekdays; effectiveStartKey = r.effectiveStart.key; effectiveEndKey = r.effectiveEnd?.key
        createdAt = r.createdAt; updatedAt = r.updatedAt
    }
    var input: RuleInput {
        RuleInput(id: id, title: title, category: category, note: note, startMinutes: startMinutes,
                  endMinutes: endMinutes, weekdays: weekdays, effectiveStart: LocalDate(key: effectiveStartKey)!,
                  effectiveEnd: effectiveEndKey.flatMap(LocalDate.init(key:)))
    }
}

extension OccurrenceOverride {
    var record: OverrideRecord {
        OverrideRecord(id: id, ruleID: ruleID, originalDate: LocalDate(key: originalDateKey)!, isCancelled: isCancelled,
                       date: dateKey.flatMap(LocalDate.init(key:)), title: title, startMinutes: startMinutes,
                       endMinutes: endMinutes, category: category, note: note, updatedAt: updatedAt)
    }
    convenience init(record r: OverrideRecord) {
        self.init(id: r.id, ruleID: r.ruleID, originalDate: r.originalDate, isCancelled: r.isCancelled, date: r.date,
                  title: r.title, startMinutes: r.startMinutes, endMinutes: r.endMinutes, category: r.category,
                  note: r.note, now: r.updatedAt)
    }
    func apply(_ r: OverrideRecord) {
        ruleID = r.ruleID; originalDateKey = r.originalDate.key; isCancelled = r.isCancelled; dateKey = r.date?.key
        title = r.title; startMinutes = r.startMinutes; endMinutes = r.endMinutes; category = r.category
        note = r.note; updatedAt = r.updatedAt
    }
    var input: OverrideInput {
        OverrideInput(ruleID: ruleID, originalDate: LocalDate(key: originalDateKey)!, isCancelled: isCancelled,
                      date: dateKey.flatMap(LocalDate.init(key:)), title: title, startMinutes: startMinutes,
                      endMinutes: endMinutes, category: category, note: note)
    }
}
