import SwiftUI

/// A read-only calendar event on the timeline: calendar colour, outlined (not filled like
/// Desk blocks), with the source calendar as a subtitle.
struct ExternalEventView: View {
    let event: ExternalEvent
    var isSelected = false
    var compact = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = event.color
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
                .padding(.vertical, 2)
                .mask(VStack(spacing: 2) { ForEach(0..<40, id: \.self) { _ in Rectangle().frame(height: 3) } })
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: event.conference == nil ? "calendar" : "video.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                        .opacity(0.6)
                        .accessibilityLabel(event.conference.map { "\($0.service.label) call" } ?? "")
                    Text(event.displayTitle)
                        .font(compact ? Font.system(size: 11.5, weight: .medium) : Theme.eventLabel)
                        .lineLimit(compact ? 1 : 2)
                    if compact {
                        Spacer(minLength: 0)
                        Text(TimeFormat.clock(event.startMinutes, compact: true))
                            .font(Font.system(size: 10.5)).opacity(0.75).lineLimit(1)
                    }
                }
                if !compact {
                    Text("\(timeText) · \(event.calendarTitle)")
                        .font(Theme.eventTime)
                        .opacity(0.78)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(scheme == .dark ? Color.white.opacity(0.9) : Theme.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, compact ? 2 : 5)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color.opacity(scheme == .dark ? 0.16 : 0.09)))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(color.opacity(isSelected ? 1 : 0.55), style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: isSelected ? [] : [4, 2]))
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var timeText: String {
        switch (event.continuesFromPreviousDay, event.continuesIntoNextDay) {
        case (true, true): "All day"
        case (true, false): "until \(TimeFormat.clock(event.endMinutes))"
        case (false, true): "from \(TimeFormat.clock(event.startMinutes))"
        case (false, false): TimeFormat.range(event.startMinutes, event.endMinutes)
        }
    }
}

/// Details popover for an external event. Everything is read-only; editing happens in Calendar.
struct ExternalEventPopover: View {
    let event: ExternalEvent
    @Environment(CalendarService.self) private var calendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(event.color).frame(width: 10, height: 10)
                Text(event.displayTitle).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
            }
            Text(event.isAllDay ? "All day" : TimeFormat.range(event.startMinutes, event.endMinutes))
                .font(Theme.body).foregroundStyle(Theme.ink)
            if let link = event.conference {
                Label(link.shortText, systemImage: "video")
                    .font(Theme.caption).foregroundStyle(Theme.inkMuted)
                    .lineLimit(1).truncationMode(.middle)
                    .help(link.url.absoluteString)
                    .contextMenu {
                        Button("Copy Link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
                        }
                    }
            }
            if let loc = event.location, !loc.isEmpty, event.conference?.url.absoluteString != loc.trimmingCharacters(in: .whitespacesAndNewlines) {
                Label(loc, systemImage: "mappin.and.ellipse").font(Theme.caption).foregroundStyle(Theme.inkMuted)
            }
            Text("\(event.calendarTitle) · \(event.sourceTitle)")
                .font(Theme.caption).foregroundStyle(Theme.inkMuted)
            Text("From your Mac's calendars. Desk shows it alongside your blocks but never changes it.")
                .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Open in Calendar") { calendarService.openInCalendar(event) }
                    .buttonStyle(QuietButtonStyle(prominent: event.conference == nil))
                if let link = event.conference {
                    Button(link.joinTitle) { calendarService.join(link) }
                        .buttonStyle(QuietButtonStyle(prominent: true))
                        .accessibilityIdentifier("external.join")
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(Theme.surfaceRaised)
    }
}

/// Compact chips for all-day events above the hour grid.
struct AllDayStrip: View {
    let days: [LocalDate]
    let events: [ExternalEvent]
    var showGutter = true
    @State private var selectedID: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if showGutter {
                Text("all day")
                    .font(Theme.gutter).foregroundStyle(Theme.inkFaint)
                    .frame(width: Theme.gutterWidth, alignment: .trailing)
                    .padding(.trailing, 8)
                    .padding(.top, 3)
            }
            ForEach(days, id: \.self) { day in
                let todays = events.filter { $0.date == day }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(todays.prefix(3)) { e in
                        AllDayChip(event: e)
                            .onTapGesture { selectedID = e.id }
                            .popover(isPresented: Binding(get: { selectedID == e.id }, set: { if !$0 { selectedID = nil } })) {
                                ExternalEventPopover(event: e)
                            }
                    }
                    if todays.count > 3 {
                        Text("+\(todays.count - 3) more").font(.system(size: 10.5)).foregroundStyle(Theme.inkMuted).padding(.leading, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 3)
            }
        }
        .padding(.trailing, 12)
        .padding(.vertical, 4)
    }
}

private struct AllDayChip: View {
    let event: ExternalEvent
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(event.color).frame(width: 6, height: 6)
            Text(event.displayTitle).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 3).fill(event.color.opacity(0.14)))
        .contentShape(Rectangle())
        .help("\(event.displayTitle) — \(event.calendarTitle)")
        .accessibilityLabel("All day: \(event.displayTitle), \(event.calendarTitle)")
    }
}
