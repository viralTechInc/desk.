import Foundation
import SwiftData
import Observation

enum SaveState: Equatable, Sendable {
    case idle
    case saving
    case saved(Date)
    case failed(String)
}

/// Which instances an edit to a recurring occurrence applies to.
enum EditScope: Sendable {
    case thisOccurrence
    case entireSeries
}

/// The single source of truth for planner data. All reads and writes go through here.
///
/// - Block/rule mutations are deterministic transactions: each captures a snapshot of the
///   affected records before and after, registers an undo that restores the snapshot, and
///   saves immediately.
/// - Notebook text is written into the model objects synchronously (so no view can ever
///   observe stale data) and persisted to disk with a short debounce; `flush()` forces it.
@MainActor
@Observable
final class PlannerStore {
    let container: ModelContainer
    let context: ModelContext
    var calendar: DeskCalendar {
        didSet { revision &+= 1 }
    }
    let undoManager = UndoManager()
    let now: @Sendable () -> Date

    /// Incremented on every data change so views re-derive occurrences.
    private(set) var revision = 0
    /// Incremented when pages are replaced wholesale (import, demo data) so notebook views reload.
    private(set) var pageGeneration = 0
    private(set) var saveState: SaveState = .idle

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var editors: [LocalDate: DayPageEditor] = [:]
    @ObservationIgnored private var weekEditors: [LocalDate: WeekPageEditor] = [:]
    @ObservationIgnored private var touchedPages: Set<LocalDate> = []
    @ObservationIgnored private var touchedWeeks: Set<LocalDate> = []

    init(container: ModelContainer, calendar: DeskCalendar = DeskCalendar(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.container = container
        self.context = container.mainContext
        self.context.autosaveEnabled = false
        self.calendar = calendar
        self.now = now
        undoManager.levelsOfUndo = 200
        // Explicit grouping: each transaction is one undo step regardless of run-loop timing.
        undoManager.groupsByEvent = false
    }

    // MARK: - Reads

    func occurrences(in range: ClosedRange<LocalDate>) -> [EventOccurrence] {
        let lo = range.lowerBound.key, hi = range.upperBound.key
        let blocks = fetch(FetchDescriptor<TimeBlock>(predicate: #Predicate { $0.dateKey >= lo && $0.dateKey <= hi }))
        let rules = fetch(FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.effectiveStartKey <= hi }))
            .filter { $0.effectiveEndKey == nil || $0.effectiveEndKey! >= lo }
        let overrides = overrides(forRules: rules.map(\.id))
        return RecurrenceEngine.occurrences(
            in: range, rules: rules.map(\.input), overrides: overrides.map(\.input),
            singles: blocks.map(\.input), calendar: calendar)
    }

    func occurrences(on date: LocalDate) -> [EventOccurrence] {
        occurrences(in: date...date)
    }

    func occurrence(withID id: String, in range: ClosedRange<LocalDate>) -> EventOccurrence? {
        occurrences(in: range).first { $0.id == id }
    }

    func rule(withID id: UUID) -> RuleRecord? {
        fetchRule(id)?.record
    }

    var isEmpty: Bool {
        count(DailyPage.self) == 0 && count(TimeBlock.self) == 0 && count(RecurrenceRule.self) == 0
    }

    // MARK: - Notebook pages

    func editor(for date: LocalDate) -> DayPageEditor {
        if let e = editors[date] { return e }
        let page = fetchPage(date)
        let e = DayPageEditor(date: date, priorities: page?.priorities ?? [], brainDump: page?.brainDump ?? "",
                              tasks: page?.tasks ?? [], store: self)
        editors[date] = e
        return e
    }

    func weekEditor(for weekStart: LocalDate) -> WeekPageEditor {
        if let e = weekEditors[weekStart] { return e }
        let page = fetchWeek(weekStart)
        let e = WeekPageEditor(weekStart: weekStart, intentions: page?.intentions ?? [], brainDump: page?.brainDump ?? "",
                               tasks: page?.tasks ?? [], store: self)
        weekEditors[weekStart] = e
        return e
    }

    func setPriorities(_ priorities: [String], for date: LocalDate) {
        let page = fetchPage(date) ?? insertPage(date)
        guard page.priorities != priorities else { return }
        page.priorities = priorities
        page.updatedAt = now()
        touchedPages.insert(date)
        scheduleSave()
    }

    func setBrainDump(_ text: String, for date: LocalDate) {
        let page = fetchPage(date) ?? insertPage(date)
        guard page.brainDump != text else { return }
        page.brainDump = text
        page.updatedAt = now()
        touchedPages.insert(date)
        scheduleSave()
    }

    func setTasks(_ tasks: [TaskItem], for date: LocalDate) {
        let page = fetchPage(date) ?? insertPage(date)
        let kept = tasks.trimmedForStorage
        guard page.tasks != kept else { return }
        page.tasks = kept
        page.updatedAt = now()
        touchedPages.insert(date)
        scheduleSave()
    }

    func setIntentions(_ intentions: [String], for weekStart: LocalDate) {
        let page = fetchWeek(weekStart) ?? insertWeek(weekStart)
        guard page.intentions != intentions else { return }
        page.intentions = intentions
        page.updatedAt = now()
        touchedWeeks.insert(weekStart)
        scheduleSave()
    }

    func setWeekBrainDump(_ text: String, for weekStart: LocalDate) {
        let page = fetchWeek(weekStart) ?? insertWeek(weekStart)
        guard page.brainDump != text else { return }
        page.brainDump = text
        page.updatedAt = now()
        touchedWeeks.insert(weekStart)
        scheduleSave()
    }

    func setWeekTasks(_ tasks: [TaskItem], for weekStart: LocalDate) {
        let page = fetchWeek(weekStart) ?? insertWeek(weekStart)
        let kept = tasks.trimmedForStorage
        guard page.tasks != kept else { return }
        page.tasks = kept
        page.updatedAt = now()
        touchedWeeks.insert(weekStart)
        scheduleSave()
    }

    func pageRecord(for date: LocalDate) -> PageRecord? { fetchPage(date)?.record }
    func weekRecord(for weekStart: LocalDate) -> WeekRecord? { fetchWeek(weekStart)?.record }

    private func insertPage(_ date: LocalDate) -> DailyPage {
        let p = DailyPage(dateKey: date.key, now: now())
        context.insert(p)
        return p
    }

    private func insertWeek(_ weekStart: LocalDate) -> WeeklyPage {
        let p = WeeklyPage(weekStartKey: weekStart.key, now: now())
        context.insert(p)
        return p
    }

    // MARK: - Block mutations

    /// Creates a one-off block, or a weekly routine when the draft has weekdays.
    @discardableResult
    func createBlock(_ draft: BlockDraft) -> EventOccurrence? {
        let d = normalized(draft)
        var createdID: String?
        transaction("Add Block", blocks: [], rules: []) {
            if d.isRecurring {
                let rule = RecurrenceRule(title: d.title, category: d.category, note: d.note,
                                          startMinutes: d.startMinutes, endMinutes: d.endMinutes,
                                          weekdays: d.weekdays, effectiveStart: d.date, now: now())
                context.insert(rule)
                createdID = EventOccurrence(source: .recurring(ruleID: rule.id, originalDate: d.date), date: d.date,
                                            title: "", startMinutes: 0, endMinutes: 0, category: .work, note: "",
                                            isException: false).id
                return ([], [rule.id])
            } else {
                let block = TimeBlock(dateKey: d.date.key, title: d.title, startMinutes: d.startMinutes,
                                      endMinutes: d.endMinutes, category: d.category, note: d.note, now: now())
                context.insert(block)
                createdID = EventOccurrence(source: .single(blockID: block.id), date: d.date, title: "",
                                            startMinutes: 0, endMinutes: 0, category: .work, note: "",
                                            isException: false).id
                return ([block.id], [])
            }
        }
        guard let createdID else { return nil }
        // When a routine is created on a day it doesn't repeat on, the occurrence shown is
        // the first generated one; look it up in a week window.
        let window = d.date...calendar.adding(days: 7, to: d.date)
        return occurrence(withID: createdID, in: window) ?? occurrences(in: window).first { occ in
            if case .recurring(let rid, _) = occ.source, case .recurring(let cid, _)? = parseSource(createdID) { return rid == cid }
            return false
        }
    }

    /// Applies an edited draft to an occurrence.
    func update(_ occ: EventOccurrence, with draft: BlockDraft, scope: EditScope) {
        let d = normalized(draft)
        switch occ.source {
        case .single(let blockID):
            updateSingle(blockID: blockID, draft: d)
        case .recurring(let ruleID, let originalDate):
            switch scope {
            case .thisOccurrence:
                overrideOccurrence(ruleID: ruleID, originalDate: originalDate, draft: d)
            case .entireSeries:
                updateSeries(ruleID: ruleID, anchor: occ, draft: d)
            }
        }
    }

    /// Moves an occurrence to a new date/start time, preserving its duration.
    func move(_ occ: EventOccurrence, toDate date: LocalDate, startMinutes: Int, scope: EditScope) {
        let duration = occ.durationMinutes
        var draft = BlockDraft(from: occ, weekdays: currentWeekdays(for: occ))
        draft.date = date
        draft.startMinutes = startMinutes
        draft.endMinutes = startMinutes + duration
        update(occ, with: draft, scope: scope)
    }

    /// Changes an occurrence's end time.
    func resize(_ occ: EventOccurrence, endMinutes: Int, scope: EditScope) {
        var draft = BlockDraft(from: occ, weekdays: currentWeekdays(for: occ))
        draft.endMinutes = endMinutes
        update(occ, with: draft, scope: scope)
    }

    func delete(_ occ: EventOccurrence, scope: EditScope) {
        switch occ.source {
        case .single(let blockID):
            transaction("Delete Block", blocks: [blockID], rules: []) {
                if let b = fetchBlock(blockID) { context.delete(b) }
                return ([], [])
            }
        case .recurring(let ruleID, let originalDate):
            switch scope {
            case .thisOccurrence:
                transaction("Skip Occurrence", blocks: [], rules: [ruleID]) {
                    let o = fetchOverride(ruleID: ruleID, originalDate: originalDate)
                        ?? insertOverride(ruleID: ruleID, originalDate: originalDate)
                    o.isCancelled = true
                    o.updatedAt = now()
                    return ([], [])
                }
            case .entireSeries:
                transaction("Delete Routine", blocks: [], rules: [ruleID]) {
                    deleteRuleAndOverrides(ruleID)
                    return ([], [])
                }
            }
        }
    }

    /// Creates a one-off copy of the occurrence on the same date.
    @discardableResult
    func duplicate(_ occ: EventOccurrence) -> EventOccurrence? {
        let draft = BlockDraft(title: occ.title, date: occ.date, startMinutes: occ.startMinutes,
                               endMinutes: occ.endMinutes, category: occ.category, note: occ.note)
        var result: EventOccurrence?
        transaction("Duplicate Block", blocks: [], rules: []) {
            let block = TimeBlock(dateKey: draft.date.key, title: draft.title, startMinutes: draft.startMinutes,
                                  endMinutes: draft.endMinutes, category: draft.category, note: draft.note, now: now())
            context.insert(block)
            result = EventOccurrence(source: .single(blockID: block.id), date: draft.date, title: draft.title,
                                     startMinutes: draft.startMinutes, endMinutes: draft.endMinutes,
                                     category: draft.category, note: draft.note, isException: false)
            return ([block.id], [])
        }
        return result
    }

    /// The weekday set of the series an occurrence belongs to (empty for single blocks).
    func currentWeekdays(for occ: EventOccurrence) -> WeekdaySet {
        if case .recurring(let ruleID, _) = occ.source, let r = fetchRule(ruleID) { return r.weekdays }
        return .none
    }

    // MARK: Mutation internals

    private func normalized(_ draft: BlockDraft) -> BlockDraft {
        var d = draft
        let n = TimeRules.normalized(start: d.startMinutes, end: d.endMinutes)
        d.startMinutes = n.start
        d.endMinutes = n.end
        d.title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return d
    }

    private func updateSingle(blockID: UUID, draft d: BlockDraft) {
        guard let block = fetchBlock(blockID) else { return }
        if d.isRecurring {
            // Promote a one-off block into a weekly routine starting on its date.
            transaction("Repeat Block", blocks: [blockID], rules: []) {
                context.delete(block)
                let rule = RecurrenceRule(title: d.title, category: d.category, note: d.note,
                                          startMinutes: d.startMinutes, endMinutes: d.endMinutes,
                                          weekdays: d.weekdays, effectiveStart: d.date, now: now())
                context.insert(rule)
                return ([], [rule.id])
            }
        } else {
            transaction("Edit Block", blocks: [blockID], rules: []) {
                block.title = d.title
                block.dateKey = d.date.key
                block.startMinutes = d.startMinutes
                block.endMinutes = d.endMinutes
                block.category = d.category
                block.note = d.note
                block.updatedAt = now()
                return ([], [])
            }
        }
    }

    private func overrideOccurrence(ruleID: UUID, originalDate: LocalDate, draft d: BlockDraft) {
        guard let rule = fetchRule(ruleID) else { return }
        transaction("Edit Occurrence", blocks: [], rules: [ruleID]) {
            let o = fetchOverride(ruleID: ruleID, originalDate: originalDate)
                ?? insertOverride(ruleID: ruleID, originalDate: originalDate)
            o.isCancelled = false
            o.title = d.title == rule.title ? nil : d.title
            o.dateKey = d.date == originalDate ? nil : d.date.key
            o.startMinutes = d.startMinutes == rule.startMinutes ? nil : d.startMinutes
            o.endMinutes = d.endMinutes == rule.endMinutes ? nil : d.endMinutes
            o.category = d.category == rule.category ? nil : d.category
            o.note = d.note == rule.note ? nil : d.note
            o.updatedAt = now()
            if o.isNoOp { context.delete(o) }
            return ([], [])
        }
    }

    /// Series edit policy (see RecurrenceEngine docs):
    /// - Fields the user changed are written to the rule. For the anchor occurrence (the one
    ///   being edited), any override on those same fields is cleared so the edit is visible there.
    /// - Other exceptions keep the fields they explicitly overrode and follow the series otherwise.
    /// - A date change rotates the weekday set by the moved number of days.
    /// - Turning recurrence off converts the series into a single block on the edited date.
    /// - Overrides whose original date the rule no longer generates are deleted.
    private func updateSeries(ruleID: UUID, anchor: EventOccurrence, draft d: BlockDraft) {
        guard let rule = fetchRule(ruleID), case .recurring(_, let originalDate) = anchor.source else { return }
        if !d.isRecurring {
            transaction("Stop Repeating", blocks: [], rules: [ruleID]) {
                deleteRuleAndOverrides(ruleID)
                let block = TimeBlock(dateKey: d.date.key, title: d.title, startMinutes: d.startMinutes,
                                      endMinutes: d.endMinutes, category: d.category, note: d.note, now: now())
                context.insert(block)
                return ([block.id], [])
            }
            return
        }
        transaction("Edit Routine", blocks: [], rules: [ruleID]) {
            let anchorOverride = fetchOverride(ruleID: ruleID, originalDate: originalDate)
            // "Changed" is judged against what the anchor currently displays (so an edit made
            // through an overridden occurrence is detected), but values are applied to the
            // rule as absolutes.
            if d.title != anchor.title { rule.title = d.title; anchorOverride?.title = nil }
            if d.category != anchor.category { rule.category = d.category; anchorOverride?.category = nil }
            if d.note != anchor.note { rule.note = d.note; anchorOverride?.note = nil }
            if d.startMinutes != anchor.startMinutes || d.endMinutes != anchor.endMinutes {
                rule.startMinutes = d.startMinutes
                rule.endMinutes = d.endMinutes
                anchorOverride?.startMinutes = nil
                anchorOverride?.endMinutes = nil
            }
            var weekdays = d.weekdays
            if d.date != anchor.date {
                // Rotate the pattern so the anchor's original weekday lands on the target weekday.
                let dayDelta = ((calendar.days(from: originalDate, to: d.date) % 7) + 7) % 7
                weekdays = WeekdaySet(weekdays.days.map { wd in
                    Weekday(rawValue: (wd.rawValue - 1 + dayDelta) % 7 + 1)!
                })
                anchorOverride?.dateKey = nil
            }
            if weekdays != rule.weekdays {
                rule.weekdays = weekdays
            }
            // Make sure the day the user is looking at is covered by the series.
            if d.date.key < rule.effectiveStartKey { rule.effectiveStartKey = d.date.key }
            rule.updatedAt = now()
            if let o = anchorOverride, o.isNoOp { context.delete(o) }
            pruneOrphanOverrides(for: rule)
            return ([], [])
        }
    }

    private func pruneOrphanOverrides(for rule: RecurrenceRule) {
        let input = rule.input
        for o in overrides(forRules: [rule.id]) {
            let original = LocalDate(key: o.originalDateKey)!
            if !input.generates(on: original, calendar: calendar) || o.isNoOp {
                context.delete(o)
            }
        }
    }

    private func deleteRuleAndOverrides(_ ruleID: UUID) {
        for o in overrides(forRules: [ruleID]) { context.delete(o) }
        if let r = fetchRule(ruleID) { context.delete(r) }
    }

    private func insertOverride(ruleID: UUID, originalDate: LocalDate) -> OccurrenceOverride {
        let o = OccurrenceOverride(ruleID: ruleID, originalDate: originalDate, now: now())
        context.insert(o)
        return o
    }

    private func parseSource(_ id: String) -> OccurrenceSource? {
        let parts = id.split(separator: ":")
        if parts.count == 2, parts[0] == "single", let u = UUID(uuidString: String(parts[1])) { return .single(blockID: u) }
        if parts.count == 3, parts[0] == "rule", let u = UUID(uuidString: String(parts[1])),
           let k = Int(parts[2]), let d = LocalDate(key: k) { return .recurring(ruleID: u, originalDate: d) }
        return nil
    }

    // MARK: - Transactions & undo

    /// Snapshot of a set of blocks and rules (with all their overrides). Restoring a snapshot
    /// deletes everything in scope and re-inserts the captured records.
    struct Snapshot: Sendable {
        var blockIDs: Set<UUID>
        var ruleIDs: Set<UUID>
        var blocks: [BlockRecord]
        var rules: [RuleRecord]
        var overrides: [OverrideRecord]
    }

    private func snapshot(blocks: Set<UUID>, rules: Set<UUID>) -> Snapshot {
        Snapshot(blockIDs: blocks, ruleIDs: rules,
                 blocks: blocks.compactMap { fetchBlock($0)?.record },
                 rules: rules.compactMap { fetchRule($0)?.record },
                 overrides: overrides(forRules: Array(rules)).map(\.record))
    }

    /// Runs `body` as an undoable transaction. `body` returns the IDs it created so they join
    /// the snapshot scope.
    private func transaction(_ name: String, blocks: Set<UUID>, rules: Set<UUID>,
                             _ body: () -> (blocks: Set<UUID>, rules: Set<UUID>)) {
        var before = snapshot(blocks: blocks, rules: rules)
        let created = body()
        let scopeBlocks = blocks.union(created.blocks)
        let scopeRules = rules.union(created.rules)
        before.blockIDs = scopeBlocks
        before.ruleIDs = scopeRules
        let after = snapshot(blocks: scopeBlocks, rules: scopeRules)
        registerUndo(name: name, restoring: before, redoing: after)
        commit()
    }

    private func registerUndo(name: String, restoring before: Snapshot, redoing after: Snapshot) {
        let needsGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if needsGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                store.restore(before)
                store.registerUndo(name: name, restoring: after, redoing: before)
            }
        }
        undoManager.setActionName(name)
        if needsGroup { undoManager.endUndoGrouping() }
    }

    private func restore(_ s: Snapshot) {
        // Update in place where an object with the same ID still exists: deleting and
        // re-inserting a model with the same unique attribute in one transaction is merged
        // by SwiftData and the record would vanish.
        let blockRecords = Dictionary(uniqueKeysWithValues: s.blocks.map { ($0.id, $0) })
        for id in s.blockIDs {
            switch (fetchBlock(id), blockRecords[id]) {
            case (let existing?, let record?): existing.apply(record)
            case (let existing?, nil): context.delete(existing)
            case (nil, let record?): context.insert(TimeBlock(record: record))
            case (nil, nil): break
            }
        }
        let ruleRecords = Dictionary(uniqueKeysWithValues: s.rules.map { ($0.id, $0) })
        for id in s.ruleIDs {
            switch (fetchRule(id), ruleRecords[id]) {
            case (let existing?, let record?): existing.apply(record)
            case (let existing?, nil): context.delete(existing)
            case (nil, let record?): context.insert(RecurrenceRule(record: record))
            case (nil, nil): break
            }
        }
        let overrideRecords = Dictionary(uniqueKeysWithValues: s.overrides.map { ($0.id, $0) })
        let existingOverrides = overrides(forRules: Array(s.ruleIDs))
        var seen: Set<UUID> = []
        for o in existingOverrides {
            if let record = overrideRecords[o.id] { o.apply(record); seen.insert(o.id) } else { context.delete(o) }
        }
        for (id, record) in overrideRecords where !seen.contains(id) {
            context.insert(OccurrenceOverride(record: record))
        }
        commit()
    }

    /// Saves immediately and notifies observers.
    private func commit() {
        revision &+= 1
        flush()
    }

    // MARK: - Saving

    func scheduleSave(after delay: Duration = .milliseconds(600)) {
        saveTask?.cancel()
        if case .saving = saveState {} else { saveState = .saving }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes all pending changes to disk now. Safe to call at any time.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        pruneBlankPages()
        guard context.hasChanges else {
            if case .saving = saveState { saveState = .saved(now()) }
            return
        }
        do {
            try context.save()
            saveState = .saved(now())
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    /// Pages that end up with no text are removed so the store never fills with empty days.
    private func pruneBlankPages() {
        for date in touchedPages {
            if let p = fetchPage(date), p.isBlank { context.delete(p) }
        }
        touchedPages.removeAll()
        for week in touchedWeeks {
            if let p = fetchWeek(week), p.isBlank { context.delete(p) }
        }
        touchedWeeks.removeAll()
    }

    // MARK: - Backup

    func exportBackup() throws -> Data {
        try BackupDocument.encoder().encode(backupDocument())
    }

    /// Everything in the store as one value; also what a shared desk publishes.
    func backupDocument() -> BackupDocument {
        flush()
        return BackupDocument(
            exportedAt: now(), timeZone: calendar.timeZone.identifier,
            pages: fetch(FetchDescriptor<DailyPage>(sortBy: [SortDescriptor(\.dateKey)])).map(\.record),
            weeks: fetch(FetchDescriptor<WeeklyPage>(sortBy: [SortDescriptor(\.weekStartKey)])).map(\.record),
            blocks: fetch(FetchDescriptor<TimeBlock>(sortBy: [SortDescriptor(\.dateKey), SortDescriptor(\.startMinutes)])).map(\.record),
            rules: fetch(FetchDescriptor<RecurrenceRule>(sortBy: [SortDescriptor(\.createdAt)])).map(\.record),
            overrides: fetch(FetchDescriptor<OccurrenceOverride>(sortBy: [SortDescriptor(\.originalDateKey)])).map(\.record))
    }

    static func decodeBackup(_ data: Data) throws -> BackupDocument {
        let doc = try BackupDocument.decoder().decode(BackupDocument.self, from: data)
        guard doc.version <= DeskSchema.backupVersion else {
            throw BackupError.newerVersion(doc.version)
        }
        return doc
    }

    /// Replaces all data with the backup's contents. Not undoable; callers confirm first.
    func importBackup(_ doc: BackupDocument) throws {
        flush()
        deleteAllData()
        insert(doc)
        try context.save()
        afterBulkChange()
    }

    func insert(_ doc: BackupDocument) {
        for r in doc.pages { context.insert(DailyPage(record: r)) }
        for r in doc.weeks { context.insert(WeeklyPage(record: r)) }
        for r in doc.blocks { context.insert(TimeBlock(record: r)) }
        for r in doc.rules { context.insert(RecurrenceRule(record: r)) }
        for r in doc.overrides { context.insert(OccurrenceOverride(record: r)) }
    }

    /// Removes exactly the records `SeedData` adds for the week containing `date`, leaving
    /// everything the user made alone. Matching is by content, since demo IDs are random.
    /// Returns how many rules, blocks and pages were removed.
    @discardableResult
    func removeDemoData(weekContaining date: LocalDate) -> Int {
        let seed = SeedData.document(weekContaining: date, calendar: calendar)
        var removed = 0

        let rules = fetch(FetchDescriptor<RecurrenceRule>())
        var removedRuleIDs: Set<UUID> = []
        for seedRule in seed.rules {
            if let match = rules.first(where: { r in
                !removedRuleIDs.contains(r.id) && Self.matches(r, seedRule)
            }) {
                removedRuleIDs.insert(match.id)
                context.delete(match)
                removed += 1
            }
        }
        if !removedRuleIDs.isEmpty {
            for o in overrides(forRules: Array(removedRuleIDs)) { context.delete(o) }
        }

        let blocks = fetch(FetchDescriptor<TimeBlock>())
        for seedBlock in seed.blocks {
            if let match = blocks.first(where: { Self.matches($0, seedBlock) }) {
                context.delete(match)
                removed += 1
            }
        }

        for seedPage in seed.pages {
            if let page = fetchPage(seedPage.date), page.priorities == seedPage.priorities, page.brainDump == seedPage.brainDump,
               page.tasks.map(\.text) == seedPage.tasks.map(\.text) {
                context.delete(page)
                removed += 1
            }
        }
        for seedWeek in seed.weeks {
            if let week = fetchWeek(seedWeek.weekStart),
               DayPageEditor.trimmed(week.intentions) == DayPageEditor.trimmed(seedWeek.intentions), week.brainDump.isEmpty,
               week.tasks.map(\.text) == seedWeek.tasks.map(\.text) {
                context.delete(week)
                removed += 1
            }
        }
        afterBulkChange()
        return removed
    }

    private static func matches(_ r: RecurrenceRule, _ seed: RuleRecord) -> Bool {
        guard r.title == seed.title, r.categoryRaw == seed.category.rawValue, r.note == seed.note else { return false }
        guard r.startMinutes == seed.startMinutes, r.endMinutes == seed.endMinutes else { return false }
        return r.weekdayMask == seed.weekdays.mask && r.effectiveStartKey == seed.effectiveStart.key && r.effectiveEndKey == nil
    }

    private static func matches(_ b: TimeBlock, _ seed: BlockRecord) -> Bool {
        guard b.dateKey == seed.date.key, b.title == seed.title, b.categoryRaw == seed.category.rawValue else { return false }
        return b.startMinutes == seed.startMinutes && b.endMinutes == seed.endMinutes && b.note == seed.note
    }

    func deleteAllData() {
        for p in fetch(FetchDescriptor<DailyPage>()) { context.delete(p) }
        for p in fetch(FetchDescriptor<WeeklyPage>()) { context.delete(p) }
        for p in fetch(FetchDescriptor<TimeBlock>()) { context.delete(p) }
        for p in fetch(FetchDescriptor<RecurrenceRule>()) { context.delete(p) }
        for p in fetch(FetchDescriptor<OccurrenceOverride>()) { context.delete(p) }
    }

    /// Call after bulk replacement so editors and undo don't refer to stale objects.
    func afterBulkChange() {
        editors.removeAll()
        weekEditors.removeAll()
        touchedPages.removeAll()
        touchedWeeks.removeAll()
        undoManager.removeAllActions()
        revision &+= 1
        pageGeneration &+= 1
        flush()
    }

    enum BackupError: LocalizedError {
        case newerVersion(Int)
        var errorDescription: String? {
            switch self {
            case .newerVersion(let v): "This backup was made by a newer version of Desk (format \(v))."
            }
        }
    }

    // MARK: - Fetch helpers

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do { return try context.fetch(descriptor) } catch {
            saveState = .failed("Couldn't read data: \(error.localizedDescription)")
            return []
        }
    }

    private func count<T: PersistentModel>(_ type: T.Type) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
    }

    private func fetchPage(_ date: LocalDate) -> DailyPage? {
        let key = date.key
        var d = FetchDescriptor<DailyPage>(predicate: #Predicate { $0.dateKey == key })
        d.fetchLimit = 1
        return fetch(d).first
    }

    private func fetchWeek(_ weekStart: LocalDate) -> WeeklyPage? {
        let key = weekStart.key
        var d = FetchDescriptor<WeeklyPage>(predicate: #Predicate { $0.weekStartKey == key })
        d.fetchLimit = 1
        return fetch(d).first
    }

    private func fetchBlock(_ id: UUID) -> TimeBlock? {
        var d = FetchDescriptor<TimeBlock>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return fetch(d).first
    }

    private func fetchRule(_ id: UUID) -> RecurrenceRule? {
        var d = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return fetch(d).first
    }

    private func fetchOverride(ruleID: UUID, originalDate: LocalDate) -> OccurrenceOverride? {
        let key = originalDate.key
        var d = FetchDescriptor<OccurrenceOverride>(predicate: #Predicate { $0.ruleID == ruleID && $0.originalDateKey == key })
        d.fetchLimit = 1
        return fetch(d).first
    }

    private func overrides(forRules ids: [UUID]) -> [OccurrenceOverride] {
        guard !ids.isEmpty else { return [] }
        return fetch(FetchDescriptor<OccurrenceOverride>(predicate: #Predicate { ids.contains($0.ruleID) }))
    }
}

/// View-facing editing object for one day's notebook. Writes through to the store
/// synchronously; the store debounces the disk write.
@MainActor
@Observable
final class DayPageEditor {
    let date: LocalDate
    private(set) var priorities: [String]
    var brainDump: String {
        didSet { store?.setBrainDump(brainDump, for: date) }
    }
    /// The brain dump's task list. Edited through the array helpers on `[TaskItem]`.
    var tasks: [TaskItem] {
        didSet { store?.setTasks(tasks, for: date) }
    }
    @ObservationIgnored private weak var store: PlannerStore?

    static let minimumRows = 3

    init(date: LocalDate, priorities: [String], brainDump: String, tasks: [TaskItem] = [], store: PlannerStore?) {
        self.date = date
        self.priorities = Self.padded(priorities)
        self.brainDump = brainDump
        self.tasks = tasks
        self.store = store
    }

    var isBlank: Bool {
        brainDump.isEmpty && tasks.trimmedForStorage.isEmpty
            && priorities.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func setPriority(_ text: String, at index: Int) {
        guard priorities.indices.contains(index), priorities[index] != text else { return }
        priorities[index] = text
        persistPriorities()
    }

    /// Adds a row after `index` and returns the new row's index.
    @discardableResult
    func insertPriority(after index: Int) -> Int {
        let at = min(index + 1, priorities.count)
        priorities.insert("", at: at)
        persistPriorities()
        return at
    }

    /// Removes an empty row (never below the minimum). Returns true if removed.
    @discardableResult
    func removePriorityIfEmpty(at index: Int) -> Bool {
        guard priorities.count > Self.minimumRows, priorities.indices.contains(index),
              priorities[index].isEmpty else { return false }
        priorities.remove(at: index)
        persistPriorities()
        return true
    }

    private func persistPriorities() {
        store?.setPriorities(Self.trimmed(priorities), for: date)
    }

    static func padded(_ rows: [String]) -> [String] {
        var r = rows
        while r.count < minimumRows { r.append("") }
        return r
    }

    /// Stored form: trailing empty rows dropped (the UI always pads back to the minimum).
    static func trimmed(_ rows: [String]) -> [String] {
        var r = rows
        while let last = r.last, last.isEmpty { r.removeLast() }
        return r
    }
}

@MainActor
@Observable
final class WeekPageEditor {
    let weekStart: LocalDate
    private(set) var intentions: [String]
    var brainDump: String {
        didSet { store?.setWeekBrainDump(brainDump, for: weekStart) }
    }
    var tasks: [TaskItem] {
        didSet { store?.setWeekTasks(tasks, for: weekStart) }
    }
    @ObservationIgnored private weak var store: PlannerStore?
    static let rows = 3

    init(weekStart: LocalDate, intentions: [String], brainDump: String = "", tasks: [TaskItem] = [], store: PlannerStore?) {
        self.weekStart = weekStart
        var r = intentions
        while r.count < Self.rows { r.append("") }
        self.intentions = Array(r.prefix(Self.rows))
        self.brainDump = brainDump
        self.tasks = tasks
        self.store = store
    }

    func setIntention(_ text: String, at index: Int) {
        guard intentions.indices.contains(index), intentions[index] != text else { return }
        intentions[index] = text
        store?.setIntentions(DayPageEditor.trimmed(intentions), for: weekStart)
    }
}
