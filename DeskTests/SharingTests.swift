import Testing
import Foundation
@testable import Desk

@Suite("Sharing", .serialized)
@MainActor
struct SharingTests {
    let cal = TestSupport.calendar()
    let monday = TestSupport.d(2026, 11, 2)

    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("desk-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func defaults() -> UserDefaults {
        let name = "desk.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func fileNamesAreSlugs() {
        #expect(SharedDeskFile.fileName(for: "Louis-David") == "louis-david.desk.json")
        #expect(SharedDeskFile.fileName(for: "  Émilie  Roy ") == "émilie-roy.desk.json")
        #expect(SharedDeskFile.fileName(for: "***") == "desk.desk.json")
        #expect(SharedDeskFile.isSharedFile(URL(fileURLWithPath: "/x/a.desk.json")))
        #expect(!SharedDeskFile.isSharedFile(URL(fileURLWithPath: "/x/.a.desk.json.icloud")))
        #expect(!SharedDeskFile.isSharedFile(URL(fileURLWithPath: "/x/backup.json")))
    }

    @Test func partnerSnapshotExpandsRoutinesLikeTheOwner() throws {
        let store = try TestSupport.store()
        store.createBlock(BlockDraft(title: "Gym", date: monday, startMinutes: 7 * 60, endMinutes: 8 * 60,
                                     category: .fitness, weekdays: WeekdaySet([.monday, .wednesday])))
        store.createBlock(BlockDraft(title: "Lunch", date: monday, startMinutes: 12 * 60, endMinutes: 13 * 60, category: .personal))
        store.editor(for: monday).brainDump = "call mom"
        store.editor(for: monday).setPriority("Ship", at: 0)
        store.weekEditor(for: monday).brainDump = "week notes"
        store.flush()

        let file = SharedDeskFile(installID: "her", name: "Émilie", updatedAt: Date(), document: store.backupDocument())
        let partner = PartnerDesk(file: file, url: URL(fileURLWithPath: "/tmp/x.desk.json"))
        #expect(partner.possessive == "Émilie’s")
        #expect(partner.page(for: monday)?.brainDump == "call mom")
        #expect(partner.page(for: monday)?.priorities == ["Ship"])
        #expect(partner.week(for: monday)?.brainDump == "week notes")

        let wednesday = TestSupport.d(2026, 11, 4)
        let occ = partner.occurrences(in: monday...wednesday, calendar: cal)
        #expect(occ.map(\.title) == ["Gym", "Lunch", "Gym"])

        let events = partner.events(in: monday...monday, calendar: cal)
        #expect(events.count == 2)
        #expect(events.filter(\.isPartner).count == events.count)
        #expect(events.first?.calendarTitle == "Émilie’s desk")
        #expect(events.first?.origin == .partner(name: "Émilie", note: ""))
    }

    @Test func publishWritesOwnFileAndReadsPartners() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TestSupport.store()
        store.editor(for: monday).brainDump = "mine"
        store.flush()

        let mine = SharingService(store: store, defaults: defaults(), folderOverride: folder)
        mine.displayName = "Louis"
        mine.publishNow()
        let own = folder.appendingPathComponent("louis.desk.json")
        #expect(FileManager.default.fileExists(atPath: own.path))
        #expect(mine.lastPublished != nil)
        #expect(mine.partners.isEmpty)   // my own file is never a partner

        // A partner's Desk drops its file into the same folder.
        let hers = try TestSupport.store()
        hers.editor(for: monday).brainDump = "hers"
        hers.flush()
        let herFile = SharedDeskFile(installID: "her-install", name: "Émilie", updatedAt: Date(), document: hers.backupDocument())
        try BackupDocument.encoder().encode(herFile).write(to: folder.appendingPathComponent("emilie.desk.json"))
        mine.reload()
        #expect(mine.partners.map(\.name) == ["Émilie"])
        #expect(mine.partner(id: "her-install")?.page(for: monday)?.brainDump == "hers")

        // Her Desk sees mine the same way, and not itself (even an older copy of its own file).
        let herDefaults = defaults()
        herDefaults.set("her-install", forKey: SharingService.Keys.installID)
        let herService = SharingService(store: hers, defaults: herDefaults, folderOverride: folder)
        herService.displayName = "Émilie"
        herService.publishNow()
        herService.reload()
        #expect(herService.partners.map(\.name) == ["Louis"])

        // Two files from the same installation collapse into one partner, the newest.
        mine.reload()
        #expect(mine.partners.count == 1)

        // Removing the files removes the partner.
        herService.stopSharing()
        try FileManager.default.removeItem(at: folder.appendingPathComponent("emilie.desk.json"))
        mine.reload()
        #expect(mine.partners.isEmpty)
    }

    @Test func unchangedPlannerIsNotRewritten() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TestSupport.store()
        let mine = SharingService(store: store, defaults: defaults(), folderOverride: folder)
        mine.displayName = "Louis"
        mine.publishNow()
        let own = folder.appendingPathComponent("louis.desk.json")
        let first = try Data(contentsOf: own)
        mine.publishNow()
        let second = try Data(contentsOf: own)
        #expect(second == first)
        store.editor(for: monday).brainDump = "changed"
        store.flush()
        mine.publishNow()
        let third = try Data(contentsOf: own)
        #expect(third != first)
    }

    @Test func renamingMovesTheOwnFile() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TestSupport.store()
        let mine = SharingService(store: store, defaults: defaults(), folderOverride: folder)
        mine.displayName = "Louis"
        mine.publishNow()
        mine.displayName = "LD"
        mine.publishNow()
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["ld.desk.json"])
    }

    @Test func partnerBlocksOverlayAndCanBeHidden() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TestSupport.store()
        let mine = SharingService(store: store, defaults: defaults(), folderOverride: folder)
        let hers = try TestSupport.store()
        hers.createBlock(BlockDraft(title: "Yoga", date: monday, startMinutes: 18 * 60, endMinutes: 19 * 60, category: .fitness))
        let herFile = SharedDeskFile(installID: "her", name: "Émilie", updatedAt: Date(), document: hers.backupDocument())
        try BackupDocument.encoder().encode(herFile).write(to: folder.appendingPathComponent("emilie.desk.json"))
        mine.reload()
        #expect(mine.partnerEvents(in: monday...monday, calendar: cal).map(\.title) == ["Yoga"])
        mine.showPartnerBlocks = false
        #expect(mine.partnerEvents(in: monday...monday, calendar: cal).isEmpty)
    }
}
