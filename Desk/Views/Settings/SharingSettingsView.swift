import SwiftUI

/// Settings → Sharing: the folder this Desk publishes to, my name, and who else is there.
struct SharingSettingsView: View {
    @Environment(SharingService.self) private var sharing
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var sharing = sharing
        let _ = sharing.revision
        Form {
            Section("Share my desk") {
                if let folder = sharing.folderURL {
                    LabeledContent("Shared folder") {
                        Text(folder.path(percentEncoded: false))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .textSelection(.enabled).lineLimit(3).multilineTextAlignment(.trailing)
                    }
                    TextField("My name", text: $sharing.displayName)
                        .accessibilityIdentifier("sharing.name")
                    LabeledContent("Status") {
                        if let err = sharing.lastError {
                            Text(err).font(.system(size: 11)).foregroundStyle(Theme.danger).multilineTextAlignment(.trailing)
                        } else if let at = sharing.lastPublished {
                            Text("Published \(at.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                        } else {
                            Text("Publishing…").foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button("Change Folder…") { sharing.chooseFolder() }
                        Button("Publish Now") { sharing.publishNow() }
                        Spacer()
                        Button("Stop Sharing", role: .destructive) { sharing.stopSharing() }
                    }
                    Text("Desk keeps one file in that folder — \(sharing.ownFileURL?.lastPathComponent ?? "") — with your notes, blocks and routines, rewritten a moment after you change anything. Nothing else leaves this Mac.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("See each other's desks").font(.headline)
                        Text("Choose a folder you both can see. The simplest is a folder in iCloud Drive: in Finder, right‑click it → Share → Collaborate, and invite your partner's Apple ID. Then each of you picks that folder here.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("No server is involved — the folder's own sync moves two small files. Each Desk only writes its own file and reads the other's.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let err = sharing.lastError {
                            Text(err).font(.system(size: 11)).foregroundStyle(Theme.danger)
                        }
                        Button("Choose Shared Folder…") { sharing.chooseFolder() }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("sharing.choose")
                    }
                    .padding(.vertical, 4)
                }
            }

            if sharing.isSharing {
                Section("Partners in the folder") {
                    if sharing.partners.isEmpty {
                        Text("Nobody yet. Once your partner picks the same folder in their Desk, their desk appears here and as a switch in the toolbar.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(sharing.partners) { p in
                            HStack {
                                Image(systemName: "person").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                    Text("Updated \(p.updatedAt.formatted(date: .abbreviated, time: .shortened)) · \(p.document.summary)")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Show") { appState.showPartner(p.id) }
                            }
                        }
                    }
                    Toggle("Show partners' blocks on my schedule", isOn: $sharing.showPartnerBlocks)
                    Text("Their blocks appear outlined next to yours, like calendar events, so you can see when they're busy. Nothing you do can change them.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
