import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.settingsTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            CalendarSettingsView()
                .tabItem { Label("Calendars", systemImage: "calendar") }
                .tag("calendars")
            SharingSettingsView()
                .tabItem { Label("Sharing", systemImage: "person.2") }
                .tag("sharing")
        }
        .frame(width: 520, height: 520)
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppActions.self) private var actions

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                Picker("Hour height", selection: $settings.hourHeight) {
                    Text("Fit the day to the window").tag(0.0)
                    Text("Compact").tag(48.0)
                    Text("Comfortable").tag(64.0)
                    Text("Spacious").tag(84.0)
                }
            }
            Section("Schedule") {
                Picker("Day starts at", selection: $settings.startHour) {
                    ForEach(0..<23, id: \.self) { h in Text(TimeFormat.clock(h * 60, compact: true)).tag(h) }
                }
                .onChange(of: settings.startHour) { if settings.endHour <= settings.startHour { settings.endHour = settings.startHour + 1 } }
                Picker("Day ends at", selection: $settings.endHour) {
                    ForEach(1...24, id: \.self) { h in Text(TimeFormat.clock(h * 60, compact: true)).tag(h) }
                }
                .onChange(of: settings.endHour) { if settings.endHour <= settings.startHour { settings.startHour = settings.endHour - 1 } }
                Picker("Week starts on", selection: $settings.firstWeekday) {
                    Text("Monday").tag(Weekday.monday)
                    Text("Sunday").tag(Weekday.sunday)
                    Text("Saturday").tag(Weekday.saturday)
                }
                Toggle("Show weekly intentions", isOn: $settings.showWeeklyIntentions)
            }
            Section("Data") {
                LabeledContent("Location") {
                    Text((try? DeskSchema.storeURL().path(percentEncoded: false)) ?? "Unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Button("Reveal in Finder") { actions.revealDataFolder() }
                    Spacer()
                    Button("Export Backup…") { actions.exportBackup() }
                    Button("Import Backup…") { actions.importBackup() }
                }
                Text("Desk stores everything on this Mac. Nothing is sent anywhere. A JSON backup contains all notes, blocks and routines.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
