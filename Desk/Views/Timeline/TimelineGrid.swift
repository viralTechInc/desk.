import SwiftUI

/// Shared hour grid for the Day (one column) and Week (seven columns) screens.
/// Handles drag-to-create, drag-to-move (across columns), and bottom-edge resize.
struct TimelineGrid: View {
    let days: [LocalDate]
    var showHeaders: Bool
    /// When set, the grid shows that partner's blocks instead of mine and nothing can be edited.
    var partner: PartnerDesk? = nil

    @Environment(PlannerStore.self) private var store
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(AppActions.self) private var actions
    @Environment(CalendarService.self) private var calendarService
    @Environment(SharingService.self) private var sharing

    @State private var drag: DragState?

    enum DragState: Equatable {
        case create(day: Int, anchor: Int, current: Int)
        case move(EventOccurrence, day: Int, start: Int)
        case resize(EventOccurrence, end: Int)
    }

    var body: some View {
        let _ = store.revision
        let _ = calendarService.revision
        let _ = sharing.revision
        let range = days.first!...days.last!
        let (entries, allDay) = gather(range: range)
        let hasToday = days.contains(appState.today)

        VStack(spacing: 0) {
            if showHeaders {
                WeekHeaderRow(days: days)
                Hairline()
            }
            if !allDay.isEmpty {
                AllDayStrip(days: days, events: allDay)
                Hairline()
            }
            GeometryReader { outer in
                let available = outer.size.height - Self.topInset - Self.bottomInset
                let base = settings.geometry(fitting: available)
                let expanded = base.expanded(toInclude: entries)
                // Re-fit after expanding so out-of-range events still keep the day on one screen.
                let geometry = expanded == base ? base
                    : TimelineGeometry(startHour: expanded.startHour, endHour: expanded.endHour,
                                       hourHeight: settings.hourHeight > 0 ? settings.hourHeight
                                        : max(AppSettings.minimumHourHeight, (available / CGFloat(expanded.endHour - expanded.startHour)).rounded(.down)))
                timeline(geometry: geometry, hasToday: hasToday, entries: entries,
                         overflows: geometry.totalHeight + Self.topInset + Self.bottomInset > outer.size.height + 1)
            }
        }
    }

    static let topInset: CGFloat = 14
    static let bottomInset: CGFloat = 14

    /// My blocks, my calendars and (outlined) my partners' blocks and events — or, for a
    /// partner's page, exactly their blocks and the calendar events they share.
    private func gather(range: ClosedRange<LocalDate>) -> (entries: [ScheduleEntry], allDay: [ExternalEvent]) {
        if let partner {
            let blocks = partner.occurrences(in: range, calendar: appState.calendar)
            let external = partner.calendarEvents(in: range, calendar: appState.calendar)
            return (ScheduleMerger.timedEntries(blocks: blocks, external: external), ScheduleMerger.allDay(external))
        }
        let events = store.occurrences(in: range)
        let external = calendarService.events(in: range, calendar: appState.calendar)
            + sharing.partnerEvents(in: range, calendar: appState.calendar)
        return (ScheduleMerger.timedEntries(blocks: events, external: external), ScheduleMerger.allDay(external))
    }

    @ViewBuilder
    private func timeline(geometry: TimelineGeometry, hasToday: Bool, entries: [ScheduleEntry], overflows: Bool) -> some View {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        TimeGutter(geometry: geometry)
                            .frame(width: Theme.gutterWidth)
                        GeometryReader { geo in
                            let columnWidth = geo.size.width / CGFloat(days.count)
                            ZStack(alignment: .topLeading) {
                                GridLines(geometry: geometry, columns: days.count)
                                HStack(spacing: 0) {
                                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                                        DayColumn(
                                            day: day, index: index, columnWidth: columnWidth, columnCount: days.count,
                                            geometry: geometry,
                                            entries: displayedEntries(entries, dayIndex: index),
                                            readOnlyOwner: partner?.name,
                                            draggingID: draggingID,
                                            drag: $drag,
                                            onCreate: { start, end in actions.createBlock(date: day, start: start, end: end) },
                                            onMoveEnd: { occ, dayIndex, start in
                                                actions.move(occ, toDate: days[dayIndex], startMinutes: start)
                                            },
                                            onResizeEnd: { occ, end in actions.resize(occ, endMinutes: end) })
                                        .frame(width: columnWidth)
                                    }
                                }
                                if case .move(let occ, let dayIndex, let start) = drag {
                                    MoveGhost(occurrence: occ, start: start)
                                        .frame(width: max(columnWidth - 6, 20), height: max(geometry.height(forDuration: occ.durationMinutes), 18))
                                        .offset(x: columnWidth * CGFloat(dayIndex) + 3, y: geometry.y(forMinutes: start))
                                        .allowsHitTesting(false)
                                        .transition(.opacity)
                                }
                                if hasToday, let todayIndex = days.firstIndex(of: appState.today) {
                                    NowLine(geometry: geometry, calendar: appState.calendar)
                                        .frame(width: columnWidth)
                                        .offset(x: columnWidth * CGFloat(todayIndex))
                                        .allowsHitTesting(false)
                                }
                                // Scroll anchors, one per hour.
                                ForEach(geometry.hours, id: \.self) { hour in
                                    Color.clear.frame(width: 1, height: 1)
                                        .offset(y: geometry.y(forMinutes: hour * 60))
                                        .id("hour-\(hour)")
                                }
                            }
                            .coordinateSpace(name: "grid")
                        }
                        .frame(height: geometry.totalHeight)
                    }
                    .padding(.top, Self.topInset)
                    .padding(.bottom, Self.bottomInset)
                    .padding(.trailing, 12)
                }
                .scrollDisabled(!overflows)
                .onAppear { if overflows { scrollToStart(proxy, geometry: geometry) } }
                .onChange(of: days) { if overflows { scrollToStart(proxy, geometry: geometry) } }
            }
            .overlay(alignment: .top) {
                if entries.isEmpty, drag == nil, days.count == 1 {
                    Text(partner == nil ? "Drag on the grid to block time, or press A" : "Nothing planned")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkFaint)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    private var draggingID: String? {
        switch drag {
        case .move(let occ, _, _): occ.id
        case .resize(let occ, _): occ.id
        default: nil
        }
    }

    /// Entries for one column, with an in-progress resize applied so the block grows live.
    private func displayedEntries(_ entries: [ScheduleEntry], dayIndex: Int) -> [ScheduleEntry] {
        var result = entries.filter { $0.date == days[dayIndex] }
        if case .resize(let occ, let end) = drag, let i = result.firstIndex(where: { $0.id == occ.id }) {
            var resized = occ
            resized.endMinutes = end
            result[i] = .block(resized)
        }
        return result
    }

    /// Only used when the grid is taller than the viewport: today scrolls to the current hour,
    /// other days to the configured start hour (the grid may have been expanded above it).
    private func scrollToStart(_ proxy: ScrollViewProxy, geometry: TimelineGeometry) {
        let target: Int
        if days.contains(appState.today) {
            let nowHour = appState.calendar.minutesFromMidnight(Date()) / 60
            target = min(max(nowHour - 1, geometry.startHour), geometry.endHour - 1)
        } else {
            target = max(geometry.startHour, settings.startHour)
        }
        guard target > geometry.startHour else { return }
        proxy.scrollTo("hour-\(target)", anchor: .top)
    }
}

// MARK: - Columns

private struct DayColumn: View {
    let day: LocalDate
    let index: Int
    let columnWidth: CGFloat
    let columnCount: Int
    let geometry: TimelineGeometry
    let entries: [ScheduleEntry]
    /// Set for a partner's page: blocks show details on click but can't be changed.
    let readOnlyOwner: String?
    let draggingID: String?
    @Binding var drag: TimelineGrid.DragState?
    let onCreate: (Int, Int) -> Void
    let onMoveEnd: (EventOccurrence, Int, Int) -> Void
    let onResizeEnd: (EventOccurrence, Int) -> Void

    @Environment(AppState.self) private var appState
    @Environment(AppActions.self) private var actions
    @Environment(PlannerStore.self) private var store
    @Environment(CalendarService.self) private var calendarService
    @State private var selectedExternalID: String?
    @State private var selectedReadOnlyID: String?

    private var readOnly: Bool { readOnlyOwner != nil }

    var body: some View {
        let laidOut = OverlapLayout.layout(entries)
        ZStack(alignment: .topLeading) {
            background

            ForEach(laidOut) { item in
                switch item.item {
                case .block(let occ):
                    if let owner = readOnlyOwner {
                        readOnlyBlockView(occ, item, among: laidOut, owner: owner)
                    } else {
                        blockView(occ, item, among: laidOut)
                    }
                case .external(let ev):
                    externalView(ev, item, among: laidOut)
                }
            }

            if case .create(let d, let anchor, let current) = drag, d == index {
                let (s, e) = (min(anchor, current), max(anchor, current))
                CreateGhost(start: s, end: max(e, s + TimeRules.minimumDuration))
                    .frame(width: max(columnWidth - 6, 20), height: max(geometry.height(forDuration: max(e, s + TimeRules.minimumDuration) - s), 18))
                    .offset(x: 3, y: geometry.y(forMinutes: s))
                    .allowsHitTesting(false)
            }
        }
        .frame(height: geometry.totalHeight, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private var background: some View {
        let base = Color.clear
            .contentShape(Rectangle())
            .accessibilityLabel(readOnly ? "\(readOnlyOwner ?? "")’s schedule for \(day.description)" : "Schedule for \(day.description)")
            .accessibilityIdentifier("timeline.column.\(index)")
        if readOnly {
            base
        } else {
            base
                .gesture(createGesture)
                .contextMenu {
                    Button("Add Block Here") {
                        let start = TimeRules.snapDown(geometry.startMinutes + 9 * 60 - geometry.startMinutes)
                        onCreate(start, min(start + 60, TimeRules.dayMinutes))
                    }
                }
        }
    }

    /// A partner's block: same look as mine, click for details, no gestures at all.
    @ViewBuilder
    private func readOnlyBlockView(_ occ: EventOccurrence, _ item: LaidOutItem<ScheduleEntry>, among laidOut: [LaidOutItem<ScheduleEntry>], owner: String) -> some View {
        let inner = columnWidth - 6
        let width = max(inner * item.widthFraction - (item.columnCount > 1 ? 2 : 0), 14)
        let x = 3 + inner * item.xFraction
        let height = OverlapLayout.visualHeight(of: item, among: laidOut, geometry: geometry, floor: 16)
        let isSelected = selectedReadOnlyID == occ.id
        TimeBlockView(occurrence: occ, isSelected: isSelected, compact: height < 34, micro: height < 20)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { selectedReadOnlyID = occ.id }
            .help(height < 20 ? "\(occ.displayTitle) · \(TimeFormat.range(occ.startMinutes, occ.endMinutes))" : "")
            .popover(isPresented: Binding(get: { selectedReadOnlyID == occ.id }, set: { if !$0 { selectedReadOnlyID = nil } }),
                     arrowEdge: columnCount > 1 && index >= columnCount - 2 ? .leading : .trailing) {
                ReadOnlyBlockPopover(occurrence: occ, owner: owner)
            }
            .offset(x: x, y: geometry.y(forMinutes: occ.startMinutes) + 1)
            .zIndex(isSelected ? 2 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(occ.displayTitle), \(TimeFormat.range(occ.startMinutes, occ.endMinutes)), \(owner)’s block")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("partnerBlock.\(occ.displayTitle)")
    }

    @ViewBuilder
    private func externalView(_ ev: ExternalEvent, _ item: LaidOutItem<ScheduleEntry>, among laidOut: [LaidOutItem<ScheduleEntry>]) -> some View {
        let inner = columnWidth - 6
        let width = max(inner * item.widthFraction - (item.columnCount > 1 ? 2 : 0), 14)
        let x = 3 + inner * item.xFraction
        let height = OverlapLayout.visualHeight(of: item, among: laidOut, geometry: geometry, floor: 16)
        let isSelected = selectedExternalID == ev.id
        ExternalEventView(event: ev, isSelected: isSelected, compact: height < 34, micro: height < 20)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { selectedExternalID = ev.id }
            .contextMenu {
                if !ev.isPartner {
                    Button("Open in Calendar") { calendarService.openInCalendar(ev) }
                }
            }
            .popover(isPresented: Binding(get: { selectedExternalID == ev.id }, set: { if !$0 { selectedExternalID = nil } }),
                     arrowEdge: columnCount > 1 && index >= columnCount - 2 ? .leading : .trailing) {
                ExternalEventPopover(event: ev)
            }
            .offset(x: x, y: geometry.y(forMinutes: ev.startMinutes) + 1)
            .zIndex(isSelected ? 2 : 0.5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ev.displayTitle), \(TimeFormat.range(ev.startMinutes, ev.endMinutes)), \(ev.calendarTitle) calendar")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("external.\(ev.displayTitle)")
            .accessibilityAction(named: ev.isPartner ? "Show details" : "Open in Calendar") {
                if ev.isPartner { selectedExternalID = ev.id } else { calendarService.openInCalendar(ev) }
            }
    }

    @ViewBuilder
    private func blockView(_ occ: EventOccurrence, _ item: LaidOutItem<ScheduleEntry>, among laidOut: [LaidOutItem<ScheduleEntry>]) -> some View {
        let inner = columnWidth - 6
        let width = max(inner * item.widthFraction - (item.columnCount > 1 ? 2 : 0), 14)
        let x = 3 + inner * item.xFraction
        let height = OverlapLayout.visualHeight(of: item, among: laidOut, geometry: geometry, floor: 16)
        let isSelected = appState.selectedOccurrenceID == occ.id
        let isEditing = appState.editingOccurrenceID == occ.id

        TimeBlockView(occurrence: occ, isSelected: isSelected || isEditing, isDimmed: draggingID == occ.id && isMoving,
                      compact: height < 34, micro: height < 20)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(moveGesture(occ))
            .overlay(alignment: .bottom) {
                ResizeHandle()
                    .frame(height: min(8, max(3, (height / 3).rounded(.down))))
                    .gesture(resizeGesture(occ))
            }
            .help(height < 20 ? "\(occ.displayTitle) · \(TimeFormat.range(occ.startMinutes, occ.endMinutes))" : "")
            .contextMenu { contextMenu(occ) }
            .popover(isPresented: Binding(
                get: { appState.editingOccurrenceID == occ.id },
                set: { if !$0, appState.editingOccurrenceID == occ.id { appState.editingOccurrenceID = nil } }),
                     arrowEdge: columnCount > 1 && index >= columnCount - 2 ? .leading : .trailing) {
                BlockEditorView(occurrence: occ, isNew: appState.editingIsNew && appState.editingOccurrenceID == occ.id,
                                weekdays: store.currentWeekdays(for: occ))
            }
            .offset(x: x, y: geometry.y(forMinutes: occ.startMinutes) + 1)
            .zIndex(isSelected ? 2 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(occ.displayTitle), \(TimeFormat.range(occ.startMinutes, occ.endMinutes))\(occ.isRecurring ? ", repeats weekly" : "")")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("block.\(occ.displayTitle)")
            .accessibilityAction(named: "Edit") { appState.edit(occ) }
            .accessibilityAction(named: "Delete") { actions.delete(occ) }
            .accessibilityAction(named: "Move 15 minutes earlier") { actions.move(occ, toDate: occ.date, startMinutes: max(0, occ.startMinutes - 15)) }
            .accessibilityAction(named: "Move 15 minutes later") { actions.move(occ, toDate: occ.date, startMinutes: min(TimeRules.dayMinutes - occ.durationMinutes, occ.startMinutes + 15)) }
            .accessibilityAction(named: "Extend 15 minutes") { actions.resize(occ, endMinutes: min(TimeRules.dayMinutes, occ.endMinutes + 15)) }
            .accessibilityAction(named: "Shorten 15 minutes") { actions.resize(occ, endMinutes: max(occ.startMinutes + TimeRules.minimumDuration, occ.endMinutes - 15)) }
    }

    private var isMoving: Bool {
        if case .move = drag { return true }
        return false
    }

    @ViewBuilder
    private func contextMenu(_ occ: EventOccurrence) -> some View {
        Button("Edit…") { appState.edit(occ) }
        Button("Duplicate") { actions.duplicate(occ) }
        Divider()
        if occ.isRecurring {
            Button("Skip This Occurrence") { store.delete(occ, scope: .thisOccurrence) }
            Button("Delete Routine…") { appState.seriesDeletion = occ }
        } else {
            Button("Delete") { store.delete(occ, scope: .thisOccurrence) }
        }
    }

    // MARK: Gestures

    /// One gesture for the empty grid: a click (≤ 4 pt of movement) deselects and ends text
    /// editing; a drag selects a time range and creates a block.
    private var createGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard isDrag(value) else { return }
                let anchor = geometry.snappedMinutes(forY: value.startLocation.y)
                let current = geometry.snappedMinutes(forY: value.location.y)
                drag = .create(day: index, anchor: anchor, current: current)
            }
            .onEnded { value in
                guard isDrag(value) else {
                    drag = nil
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    appState.escape()
                    return
                }
                let anchor = geometry.snappedMinutes(forY: value.startLocation.y)
                let current = geometry.snappedMinutes(forY: value.location.y)
                drag = nil
                let s = min(anchor, current)
                let e = max(max(anchor, current), s + TimeRules.minimumDuration)
                onCreate(s, min(e, TimeRules.dayMinutes))
            }
    }

    private func isDrag(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > 4 || abs(value.translation.height) > 4
    }

    /// One gesture per block: a click opens the editor; a drag moves it (across days in Week).
    private func moveGesture(_ occ: EventOccurrence) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("grid"))
            .onChanged { value in
                guard isDrag(value) else { return }
                let (dayIndex, start) = moveTarget(occ, value)
                drag = .move(occ, day: dayIndex, start: start)
            }
            .onEnded { value in
                guard isDrag(value) else {
                    drag = nil
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    appState.edit(occ)
                    return
                }
                let (dayIndex, start) = moveTarget(occ, value)
                drag = nil
                onMoveEnd(occ, dayIndex, start)
            }
    }

    private func moveTarget(_ occ: EventOccurrence, _ value: DragGesture.Value) -> (Int, Int) {
        let dayIndex = min(max(Int(floor(value.location.x / columnWidth)), 0), columnCount - 1)
        let deltaMinutes = Int((value.translation.height / geometry.minuteHeight).rounded())
        let unclamped = TimeRules.snap(occ.startMinutes + deltaMinutes)
        let start = min(max(unclamped, 0), TimeRules.dayMinutes - occ.durationMinutes)
        return (dayIndex, start)
    }

    private func resizeGesture(_ occ: EventOccurrence) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("grid"))
            .onChanged { value in
                drag = .resize(occ, end: resizeTarget(occ, value))
            }
            .onEnded { value in
                let end = resizeTarget(occ, value)
                drag = nil
                onResizeEnd(occ, end)
            }
    }

    private func resizeTarget(_ occ: EventOccurrence, _ value: DragGesture.Value) -> Int {
        let deltaMinutes = Int((value.translation.height / geometry.minuteHeight).rounded())
        let snapped = TimeRules.snap(occ.endMinutes + deltaMinutes)
        return min(max(snapped, occ.startMinutes + TimeRules.minimumDuration), TimeRules.dayMinutes)
    }
}

// MARK: - Chrome

private struct TimeGutter: View {
    let geometry: TimelineGeometry
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(geometry.hours, id: \.self) { hour in
                if hour < geometry.endHour || hour == 24 {
                    Text(TimeFormat.clock(hour * 60, compact: true))
                        .font(Theme.gutter)
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.trailing, 8)
                        .offset(y: geometry.y(forMinutes: hour * 60) - 7)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: geometry.totalHeight, alignment: .topTrailing)
    }
}

private struct GridLines: View {
    let geometry: TimelineGeometry
    let columns: Int
    var body: some View {
        Canvas { ctx, size in
            for hour in geometry.hours {
                let y = geometry.y(forMinutes: hour * 60) + 0.5
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(Theme.hairline), lineWidth: 1)
                if hour < geometry.endHour {
                    let hy = geometry.y(forMinutes: hour * 60 + 30) + 0.5
                    var hp = Path()
                    hp.move(to: CGPoint(x: 0, y: hy)); hp.addLine(to: CGPoint(x: size.width, y: hy))
                    ctx.stroke(hp, with: .color(Theme.ruledLine), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            if columns > 1 {
                let w = size.width / CGFloat(columns)
                for c in 1..<columns {
                    let x = (w * CGFloat(c)).rounded() + 0.5
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(Theme.hairline), lineWidth: 1)
                }
            }
        }
        .frame(height: geometry.totalHeight)
        .accessibilityHidden(true)
    }
}

private struct NowLine: View {
    let geometry: TimelineGeometry
    let calendar: DeskCalendar
    var body: some View {
        TimelineView(.everyMinute) { context in
            let minutes = calendar.minutesFromMidnight(context.date)
            if minutes >= geometry.startMinutes && minutes <= geometry.endMinutes {
                HStack(spacing: 0) {
                    Circle().fill(Theme.nowLine).frame(width: 7, height: 7).offset(x: -3)
                    Rectangle().fill(Theme.nowLine).frame(height: 1.5)
                }
                .offset(y: geometry.y(forMinutes: minutes) - 3.5)
                .accessibilityLabel("Now, \(TimeFormat.clock(minutes))")
            }
        }
    }
}

private struct ResizeHandle: View {
    @State private var hovering = false
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .accessibilityHidden(true)
    }
}

private struct CreateGhost: View {
    let start: Int
    let end: Int
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Theme.accent.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .overlay(alignment: .topLeading) {
                Text(TimeFormat.range(start, end))
                    .font(Theme.eventTime)
                    .foregroundStyle(Theme.accent)
                    .padding(6)
            }
    }
}

private struct MoveGhost: View {
    let occurrence: EventOccurrence
    let start: Int
    var body: some View {
        var ghost = occurrence
        ghost.endMinutes = start + occurrence.durationMinutes
        ghost.startMinutes = start
        return TimeBlockView(occurrence: ghost, isSelected: true, isDimmed: false, compact: false)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

/// Day headers for the Week screen; clicking one opens that day.
struct WeekHeaderRow: View {
    let days: [LocalDate]
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: Theme.gutterWidth)
            ForEach(days, id: \.self) { day in
                let isToday = day == appState.today
                Button { appState.showDay(day) } label: {
                    HStack(spacing: 6) {
                        Text(appState.calendar.weekday(of: day).shortName.uppercased())
                            .font(Theme.sectionLabel).tracking(0.8)
                            .foregroundStyle(isToday ? Theme.ink : Theme.inkMuted)
                        Text("\(day.day)")
                            .font(.system(size: 15, weight: isToday ? .semibold : .regular, design: .serif))
                            .foregroundStyle(isToday ? Theme.surface : Theme.ink)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(Circle().fill(isToday ? Theme.nowLine : .clear))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(appState.calendar.headingString(day))")
                .accessibilityLabel("\(appState.calendar.headingString(day))\(isToday ? ", today" : ""), open day")
            }
        }
        .padding(.trailing, 12)
    }
}
