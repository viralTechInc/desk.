import AppKit
import Foundation
import Observation

/// Shares this Desk with a partner through a folder both Macs can see (an iCloud Drive
/// folder shared between two Apple IDs, or any Dropbox/Drive folder). Each Desk keeps one
/// `<name>.desk.json` file there, rewritten shortly after every change; every other
/// `.desk.json` in the folder is a partner's planner, shown read-only.
///
/// No server is involved: the folder's own sync moves the files. A Desk only ever writes
/// its own file and only ever reads the others.
@MainActor
@Observable
final class SharingService {
    /// Stable per-installation identity written into the file, so a renamed own file is
    /// still recognised as "mine" and never shown as a partner.
    let installID: String

    private(set) var folderURL: URL?
    var displayName: String {
        didSet {
            guard displayName != oldValue else { return }
            defaults.set(displayName, forKey: Keys.displayName)
            removeOwnFile(named: ownFileName)
            ownFileName = SharedDeskFile.fileName(for: displayName)
            schedulePublish(after: .milliseconds(300))
        }
    }
    /// Lay the partners' blocks over my own schedule (outlined, read-only).
    var showPartnerBlocks: Bool {
        didSet { defaults.set(showPartnerBlocks, forKey: Keys.showPartnerBlocks); revision &+= 1 }
    }
    /// Put this Mac's calendar events (the enabled calendars, a few weeks around today) in
    /// the shared file so the partner sees them too.
    var shareCalendarEvents: Bool {
        didSet {
            guard shareCalendarEvents != oldValue else { return }
            defaults.set(shareCalendarEvents, forKey: Keys.shareCalendarEvents)
            lastWritten = nil
            schedulePublish(after: .milliseconds(300))
        }
    }
    /// Supplies the calendar events to share; the app wires it to `CalendarService`.
    @ObservationIgnored var eventProvider: (@MainActor (ClosedRange<LocalDate>) -> [ExternalEvent])?
    private(set) var partners: [PartnerDesk] = []
    private(set) var lastPublished: Date?
    private(set) var lastError: String?
    /// Bumped whenever partners change so views re-derive.
    private(set) var revision = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private unowned let store: PlannerStore
    @ObservationIgnored private let usesBookmark: Bool
    @ObservationIgnored private var ownFileName: String
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: (any DispatchSourceFileSystemObject)?
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var lastWritten: Data?
    @ObservationIgnored private var stamps: [String: Date] = [:]
    @ObservationIgnored private var decoded: [String: PartnerDesk] = [:]

    enum Keys {
        static let bookmark = "sharing.folderBookmark"
        static let displayName = "sharing.displayName"
        static let installID = "sharing.installID"
        static let showPartnerBlocks = "sharing.showPartnerBlocks"
        static let ownFileName = "sharing.ownFileName"
        static let shareCalendarEvents = "sharing.shareCalendarEvents"
    }

    /// Days of calendar events written to the file, around today.
    static let eventWindow = (behind: 7, ahead: 42)

    /// `folderOverride` (tests, scripted screenshots) uses that folder directly and never
    /// touches the saved bookmark.
    init(store: PlannerStore, defaults: UserDefaults = .standard, folderOverride: URL? = nil) {
        self.store = store
        self.defaults = defaults
        usesBookmark = folderOverride == nil
        if let id = defaults.string(forKey: Keys.installID) {
            installID = id
        } else {
            installID = UUID().uuidString
            defaults.set(installID, forKey: Keys.installID)
        }
        let savedName = defaults.string(forKey: Keys.displayName) ?? ""
        let name = savedName.isEmpty ? Self.defaultName() : savedName
        displayName = name
        showPartnerBlocks = defaults.object(forKey: Keys.showPartnerBlocks) as? Bool ?? true
        shareCalendarEvents = defaults.object(forKey: Keys.shareCalendarEvents) as? Bool ?? true
        ownFileName = defaults.string(forKey: Keys.ownFileName) ?? SharedDeskFile.fileName(for: name)
        if let folderOverride {
            activate(folderOverride, scoped: false)
        } else if let data = defaults.data(forKey: Keys.bookmark) {
            resolveBookmark(data)
        }
    }

    private static func defaultName() -> String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        let first = full.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "Me" : first
    }

    var isSharing: Bool { folderURL != nil }

    var ownFileURL: URL? { folderURL?.appendingPathComponent(ownFileName) }

    func partner(id: String) -> PartnerDesk? { partners.first { $0.id == id } }

    // MARK: Folder

    /// Asks for the folder to share through. Suggests iCloud Drive, where a folder shared
    /// with another Apple ID appears on both Macs.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Shared Folder"
        panel.message = "Pick the folder both of you share (for example a folder in iCloud Drive shared with your partner's Apple ID)."
        panel.prompt = "Share Here"
        if let cloud = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.deletingLastPathComponent() {
            panel.directoryURL = cloud
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFolder(url)
    }

    func setFolder(_ url: URL) {
        stopWatching()
        if usesBookmark {
            do {
                let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                defaults.set(data, forKey: Keys.bookmark)
            } catch {
                lastError = "Couldn't remember the folder: \(error.localizedDescription)"
                return
            }
        }
        activate(url, scoped: usesBookmark)
    }

    /// Stops publishing and forgets the folder. The own file is removed so the partner
    /// stops seeing a frozen copy.
    func stopSharing() {
        removeOwnFile(named: ownFileName)
        stopWatching()
        if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
        scopedURL = nil
        folderURL = nil
        defaults.removeObject(forKey: Keys.bookmark)
        partners = []
        decoded = [:]
        stamps = [:]
        lastWritten = nil
        lastPublished = nil
        lastError = nil
        revision &+= 1
    }

    private func resolveBookmark(_ data: Data) {
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: Keys.bookmark)
            }
            activate(url, scoped: true)
        } catch {
            lastError = "The shared folder can't be opened any more (\(error.localizedDescription)). Choose it again."
            defaults.removeObject(forKey: Keys.bookmark)
        }
    }

    private func activate(_ url: URL, scoped: Bool) {
        if scoped {
            guard url.startAccessingSecurityScopedResource() else {
                lastError = "macOS didn't allow access to the shared folder. Choose it again."
                return
            }
            scopedURL = url
        }
        folderURL = url
        lastError = nil
        defaults.set(ownFileName, forKey: Keys.ownFileName)
        startWatching()
        reload()
        schedulePublish(after: .milliseconds(100))
    }

    // MARK: Publishing

    /// Called after every save; coalesces bursts of typing into one write.
    func schedulePublish(after delay: Duration = .seconds(1.5)) {
        guard folderURL != nil else { return }
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.publishNow()
        }
    }

    /// Writes the own file immediately when its content changed since the last write.
    func publishNow() {
        publishTask?.cancel()
        publishTask = nil
        guard let folderURL else { return }
        let file = SharedDeskFile(installID: installID, name: displayName, updatedAt: Date(),
                                  document: store.backupDocument(), events: eventsToShare())
        do {
            // Compare without the timestamp so an unchanged planner never churns the sync.
            var probe = file
            probe.updatedAt = Date(timeIntervalSince1970: 0)
            let fingerprint = try BackupDocument.encoder().encode(probe)
            if fingerprint == lastWritten { return }
            let data = try BackupDocument.encoder().encode(file)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try data.write(to: folderURL.appendingPathComponent(ownFileName), options: .atomic)
            lastWritten = fingerprint
            lastPublished = file.updatedAt
            lastError = nil
        } catch {
            lastError = "Couldn't write to the shared folder: \(error.localizedDescription)"
        }
    }

    /// This Mac's calendar events for the shared window, or nil when not sharing them.
    func eventsToShare() -> [SharedEvent]? {
        guard shareCalendarEvents, let eventProvider else { return nil }
        let cal = store.calendar
        let today = cal.today()
        let range = cal.adding(days: -Self.eventWindow.behind, to: today)...cal.adding(days: Self.eventWindow.ahead, to: today)
        return eventProvider(range).filter { !$0.isPartner }.map(SharedEvent.init)
    }

    private func removeOwnFile(named name: String) {
        guard let folderURL else { return }
        try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(name))
        lastWritten = nil
    }

    // MARK: Reading partners

    /// Re-reads any `.desk.json` whose modification date changed. Cheap enough to call on
    /// every folder event, activation and poll tick.
    func reload() {
        guard let folderURL else { return }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else {
            return
        }
        var seen: Set<String> = []
        var changed = false
        for url in items {
            let name = url.lastPathComponent
            // iCloud placeholders for files not yet downloaded: ".<name>.desk.json.icloud".
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                try? fm.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard SharedDeskFile.isSharedFile(url) else { continue }
            seen.insert(name)
            let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if stamps[name] == stamp { continue }
            stamps[name] = stamp
            do {
                let data = try Data(contentsOf: url)
                let file = try BackupDocument.decoder().decode(SharedDeskFile.self, from: data)
                if file.installID == installID {
                    decoded[name] = nil
                } else {
                    decoded[name] = PartnerDesk(file: file, url: url)
                }
                changed = true
            } catch {
                // A half-synced file: keep the previous copy and try again on the next event.
                stamps[name] = nil
            }
        }
        for name in Array(decoded.keys) where !seen.contains(name) {
            decoded[name] = nil
            stamps[name] = nil
            changed = true
        }
        guard changed else { return }
        // A renamed partner leaves its old file behind until the sync catches up: keep
        // only the newest file per installation.
        var newest: [String: PartnerDesk] = [:]
        for p in decoded.values where (newest[p.id]?.updatedAt ?? .distantPast) < p.updatedAt {
            newest[p.id] = p
        }
        partners = newest.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        revision &+= 1
    }

    func partnerEvents(in range: ClosedRange<LocalDate>, calendar: DeskCalendar) -> [ExternalEvent] {
        guard showPartnerBlocks else { return [] }
        return partners.flatMap { $0.events(in: range, calendar: calendar) }
    }

    // MARK: Watching

    private func startWatching() {
        guard let folderURL else { return }
        let fd = open(folderURL.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .attrib], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleReload() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watcher = source
        }
        pollTask = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                self?.reload()
                // Every ten minutes: roll the calendar window forward and catch calendar
                // changes that arrived without a notification. A no-op when nothing changed.
                ticks += 1
                if ticks % 30 == 0 { self?.publishNow() }
            }
        }
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
        pollTask?.cancel()
        pollTask = nil
        reloadTask?.cancel()
        publishTask?.cancel()
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}
