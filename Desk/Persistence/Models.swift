import Foundation
import SwiftData

// Persistence models. Deliberately flat: no SwiftData relationships. Rules and their
// overrides are linked by `ruleID`, which keeps undo snapshots, backups and queries simple.
// Dates are stored as integer keys (yyyymmdd) and times as minutes from midnight; see
// `LocalDate` for the policy.

@Model
final class DailyPage {
    @Attribute(.unique) var dateKey: Int
    var priorities: [String]
    var brainDump: String
    var createdAt: Date
    var updatedAt: Date

    init(dateKey: Int, priorities: [String] = [], brainDump: String = "", now: Date = Date()) {
        self.dateKey = dateKey
        self.priorities = priorities
        self.brainDump = brainDump
        self.createdAt = now
        self.updatedAt = now
    }

    var date: LocalDate { LocalDate(key: dateKey)! }

    /// A page with no user text is considered empty and may be pruned.
    var isBlank: Bool {
        brainDump.isEmpty && priorities.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

@Model
final class WeeklyPage {
    @Attribute(.unique) var weekStartKey: Int
    var intentions: [String]
    var updatedAt: Date

    init(weekStartKey: Int, intentions: [String] = [], now: Date = Date()) {
        self.weekStartKey = weekStartKey
        self.intentions = intentions
        self.updatedAt = now
    }

    var isBlank: Bool { intentions.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
}

@Model
final class TimeBlock {
    @Attribute(.unique) var id: UUID
    var dateKey: Int
    var title: String
    var startMinutes: Int
    var endMinutes: Int
    var categoryRaw: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), dateKey: Int, title: String, startMinutes: Int, endMinutes: Int,
         category: BlockCategory, note: String = "", now: Date = Date()) {
        self.id = id
        self.dateKey = dateKey
        self.title = title
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.categoryRaw = category.rawValue
        self.note = note
        self.createdAt = now
        self.updatedAt = now
    }

    var category: BlockCategory {
        get { BlockCategory(rawValue: categoryRaw) ?? .work }
        set { categoryRaw = newValue.rawValue }
    }
}

@Model
final class RecurrenceRule {
    @Attribute(.unique) var id: UUID
    var title: String
    var categoryRaw: String
    var note: String
    var startMinutes: Int
    var endMinutes: Int
    var weekdayMask: Int
    var effectiveStartKey: Int
    var effectiveEndKey: Int?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, category: BlockCategory, note: String = "",
         startMinutes: Int, endMinutes: Int, weekdays: WeekdaySet,
         effectiveStart: LocalDate, effectiveEnd: LocalDate? = nil, now: Date = Date()) {
        self.id = id
        self.title = title
        self.categoryRaw = category.rawValue
        self.note = note
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.weekdayMask = weekdays.mask
        self.effectiveStartKey = effectiveStart.key
        self.effectiveEndKey = effectiveEnd?.key
        self.createdAt = now
        self.updatedAt = now
    }

    var category: BlockCategory {
        get { BlockCategory(rawValue: categoryRaw) ?? .work }
        set { categoryRaw = newValue.rawValue }
    }
    var weekdays: WeekdaySet {
        get { WeekdaySet(mask: weekdayMask) }
        set { weekdayMask = newValue.mask }
    }
}

@Model
final class OccurrenceOverride {
    @Attribute(.unique) var id: UUID
    var ruleID: UUID
    var originalDateKey: Int
    var isCancelled: Bool
    var dateKey: Int?
    var title: String?
    var startMinutes: Int?
    var endMinutes: Int?
    var categoryRaw: String?
    var note: String?
    var updatedAt: Date

    init(id: UUID = UUID(), ruleID: UUID, originalDate: LocalDate, isCancelled: Bool = false,
         date: LocalDate? = nil, title: String? = nil, startMinutes: Int? = nil, endMinutes: Int? = nil,
         category: BlockCategory? = nil, note: String? = nil, now: Date = Date()) {
        self.id = id
        self.ruleID = ruleID
        self.originalDateKey = originalDate.key
        self.isCancelled = isCancelled
        self.dateKey = date?.key
        self.title = title
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.categoryRaw = category?.rawValue
        self.note = note
        self.updatedAt = now
    }

    var category: BlockCategory? {
        get { categoryRaw.flatMap(BlockCategory.init(rawValue:)) }
        set { categoryRaw = newValue?.rawValue }
    }

    /// True when the override changes nothing — such records are deleted on save.
    var isNoOp: Bool {
        !isCancelled && dateKey == nil && title == nil && startMinutes == nil
            && endMinutes == nil && categoryRaw == nil && note == nil
    }
}

enum DeskSchema {
    static let models: [any PersistentModel.Type] = [
        DailyPage.self, WeeklyPage.self, TimeBlock.self, RecurrenceRule.self, OccurrenceOverride.self,
    ]

    /// Bumped whenever the backup/model layout changes.
    static let backupVersion = 1

    /// Default on-disk location: ~/Library/Application Support/Desk/Desk.store
    /// (inside the app's sandbox container when sandboxed).
    static func storeURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Desk", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Desk.store")
    }

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            config = ModelConfiguration(schema: schema, url: try storeURL())
        }
        return try ModelContainer(for: schema, configurations: [config])
    }
}
