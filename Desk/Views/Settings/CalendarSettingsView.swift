import SwiftUI

/// Settings → Calendars: which system calendars Desk shows, with clear states for
/// permission not yet asked, denied, and no calendars configured.
struct CalendarSettingsView: View {
    @Environment(CalendarService.self) private var calendarService

    var body: some View {
        Form {
            switch calendarService.access {
            case .notDetermined:
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Show your calendars in Desk").font(.headline)
                        Text("Events from the accounts set up in System Settings → Internet Accounts (Google, iCloud, Exchange…) appear next to your blocks. Desk only reads them; nothing is sent anywhere.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Allow Calendar Access…") {
                            Task { await calendarService.requestAccess() }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.vertical, 4)
                }
            case .denied, .restricted, .writeOnly:
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(calendarService.access == .restricted ? "Calendar access is restricted on this Mac" : "Calendar access is turned off",
                              systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(calendarService.access == .restricted
                             ? "A profile or parental control prevents Desk from reading calendars."
                             : "Turn on Desk under System Settings → Privacy & Security → Calendars (Full Access), then come back here.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Open Privacy Settings") { calendarService.openSystemPrivacySettings() }
                            Button("Check Again") { calendarService.refreshCalendars() }
                        }
                        if let err = calendarService.lastError {
                            Text(err).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            case .authorized:
                if calendarService.calendars.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No calendars yet").font(.headline)
                            Text("Add an account in System Settings → Internet Accounts and enable Calendars for it. New calendars show up here automatically.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("Open Internet Accounts") { calendarService.openInternetAccounts() }
                                Button("Refresh") { calendarService.refreshCalendars() }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    ForEach(calendarService.calendarsBySource, id: \.source) { group in
                        Section {
                            ForEach(group.calendars) { cal in
                                Toggle(isOn: Binding(get: { calendarService.isEnabled(cal) },
                                                     set: { calendarService.setEnabled($0, for: cal) })) {
                                    HStack(spacing: 8) {
                                        Circle().fill(cal.color).frame(width: 10, height: 10)
                                        Text(cal.title)
                                        if !cal.allowsModifications {
                                            Text("read-only").font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        } header: {
                            HStack {
                                Text(group.source)
                                Text(group.kind).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        HStack {
                            Button("Show All") { calendarService.setAll(enabled: true) }
                            Button("Hide All") { calendarService.setAll(enabled: false) }
                            Spacer()
                            Button("Open Internet Accounts") { calendarService.openInternetAccounts() }
                        }
                        Text("Calendar events are read-only in Desk. Changes you make in Calendar, Google or iCloud appear here automatically; the Mac keeps them in sync.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { calendarService.refreshCalendars() }
    }
}
