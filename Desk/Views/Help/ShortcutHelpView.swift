import SwiftUI

struct ShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let groups: [(String, [(String, String)])] = [
        ("Navigate", [
            ("T", "Today"), ("N", "Tomorrow"), ("J  /  K", "Previous / next day, or week"),
            ("D  /  W", "Day / Week view"),
        ]),
        ("Write", [
            ("B", "Focus brain dump"), ("P", "Focus first priority"),
            ("Return", "Next priority line (adds one at the end)"),
        ] + (TaskExtractor.isAvailable ? [("⌥⌘T", "Find tasks in brain dump")] : [])),
        ("Schedule", [
            ("A", "Add a block"), ("Drag on grid", "Create a block"), ("Drag block", "Move it (across days in Week)"),
            ("Drag bottom edge", "Resize"), ("Click block", "Edit"), ("Right‑click", "Duplicate, skip, delete"),
        ]),
        ("General", [
            ("Esc", "Close popover / deselect"), ("⌘Z  /  ⇧⌘Z", "Undo / redo"),
            ("⇧⌘L", "Light / dark"), ("⇧⌘P", "My desk / partner’s desk"), ("⇧⌘E", "Export backup"), ("⌘,", "Settings"), ("?", "This help"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Keyboard shortcuts").font(.system(size: 18, weight: .medium, design: .serif)).foregroundStyle(Theme.ink)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(QuietButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
            Text("Letter shortcuts work whenever you're not typing in a text field. While typing, letters are just letters.")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkMuted)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 20) {
                ForEach(groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: group.0)
                        ForEach(group.1, id: \.0) { key, action in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(key)
                                    .font(.system(size: 12, weight: .medium).monospaced())
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.hairline.opacity(0.8)))
                                    .frame(minWidth: 96, alignment: .leading)
                                Text(action).font(Theme.caption).foregroundStyle(Theme.inkMuted)
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 600)
        .background(Theme.surface)
    }
}
