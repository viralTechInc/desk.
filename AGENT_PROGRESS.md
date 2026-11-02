# Desk — Agent Progress

## Platform decision
Native macOS app: Swift 6 (strict concurrency), SwiftUI, SwiftData, macOS 14+ deployment target.
Environment check: Xcode 27.0 / Swift 6.4 / macOS 27.0 SDK / xcodegen 2.46 available → native path, no web fallback.
Project file is generated from `project.yml` with xcodegen (`xcodegen generate`; `Desk.xcodeproj` is gitignored).
References folder (`references/image.jpg`, `references/weekly-plan.pdf`) was **not present**; built from the written spec.

## Milestones (all done 2026-11-01)
- [x] Phase 0 — scaffold, build baseline
- [x] Phase 1 — domain models, SwiftData persistence, recurrence engine, undo transactions, backup format, seed data, unit tests
- [x] Phase 2 — Day screen: toolbar, serif date heading, 64/36 split (stacks under 900 pt), priorities, day + week brain dumps side by side (NSTextView), timeline
- [x] Phase 3 — Week screen: seven columns, drag-create / move across days / resize, overlap columns, scope prompt for routines, intentions row
- [x] Phase 4 — letter shortcuts + menus, context menus, settings, shortcut help, backup export/import, demo data (opt-in), app icon, Release build in `dist/`

## Calendar integration (EventKit) — 2026-11-01, second request
- `Desk/Calendar/CalendarService.swift`: `EKEventStore`, `requestFullAccessToEvents()`, authorization states
  (not determined / denied / restricted / write-only / authorized), calendars grouped by `EKSource`, per-calendar
  enable/disable persisted in UserDefaults (`calendar.disabledIDs`; new calendars are on by default), observes
  `.EKEventStoreChanged`, app activation and `.NSSystemTimeZoneDidChange`. Read-only: never creates/edits/deletes.
- `ExternalEventSplitter` turns absolute start/end into per-day slices (multi-day, all-day, midnight end, DST);
  `ScheduleMerger` merges blocks + external events, filters by enabled calendars and computes the menu-bar
  "current / next three / remaining / countdown" with meetings winning over overlapping blocks.
- Timeline: `OverlapLayout` is generic over `TimelineItem`; `ScheduleEntry = .block | .external`. External events
  render dashed/outlined in the calendar colour with the calendar name, click → details popover + "Open in
  Calendar" (`ical://ekevent/<id>`), all-day events in a strip above the grid (Day and Week).
- Settings → Calendars tab (permission request, denied/restricted guidance with deep links to Privacy & Security and
  Internet Accounts, grouped checkboxes, Show/Hide all). Calendars menu: Choose Calendars…, Refresh (⌘R).
- Menu bar companion: `MenuBarExtra` (window style) fed by `ScheduleFeed` (refreshes on store/calendar changes and
  every 30 s): current item with time left, next items with countdown, Open Desk / Quit.
- Entitlement `com.apple.security.personal-information.calendars`; `NSCalendarsFullAccessUsageDescription`.
- Not verifiable by the agent: granting the macOS calendar permission is a user action, so rendering of real
  Google/iCloud events was not observed in a screenshot. Logic is covered by 11 new unit tests (42 total).

## Owner feedback applied
- "Need to see it without scrolling down": the timeline fits the visible hours (06:00–22:00) to the window height by default
  (`AppSettings.hourHeight == 0` = fit; 22 pt/hour floor before it scrolls). Fixed heights remain available in Settings.

## Decisions
- Dates are `LocalDate` (y/m/d, integer key `yyyymmdd`); times are minutes from midnight. Arithmetic anchors at noon → DST-safe (tests cross America/Toronto transitions).
- No SwiftData relationships; rules ↔ overrides linked by `ruleID`. Keeps undo snapshots, backups and queries trivial.
- Undo is snapshot-based per transaction on a store-owned `UndoManager` with explicit grouping (`groupsByEvent = false`).
  Restore updates models in place: SwiftData merges a delete + insert of the same unique ID within one transaction and the record vanishes (found via failing tests).
- Series edit policy: changed fields apply as absolutes to the rule; the anchor occurrence's override on those fields is cleared; other exceptions keep what they explicitly overrode; day moves rotate the weekday set; orphaned overrides are pruned; turning recurrence off converts to a single block on the edited date.
- Notebook text is written into model objects synchronously, disk save debounced 600 ms (immediate on navigation, view switch, deactivate, quit); blank pages are pruned so days are created lazily.
- Letter shortcuts use a local `NSEvent` monitor that bails out whenever the first responder is a text view/field editor; ⌘-equivalents live in the menus. Edit ▸ Undo/Redo is replaced so ⌘Z goes to the text view while typing and to block history otherwise.
- Grid/block gestures are single `DragGesture(minimumDistance: 0)` recognizers (≤ 4 pt = click) — avoids tap/drag competition.
- App Sandbox on, ad-hoc signed. Data in `~/Library/Containers/com.desk.planner/Data/Library/Application Support/Desk/Desk.store`.

## Dev tooling (DEBUG builds only)
- `DebugHooks` listens to a distributed notification; `scripts/desk-debug.swift` (compile to `build/desk-debug`) drives it:
  `screenshot <path>` (renders each visible window to PNG — the terminal has no screen-recording permission), `action demo|week|day|…`,
  `date yyyy-mm-dd`, `resize w h`, `appearance light|dark|system`. Paths must be inside the sandbox container
  (`~/Library/Containers/com.desk.planner/Data/tmp`).
- Env: `DESK_SCRATCH_STORE=<name>` (throwaway store in the container's tmp) or `DESK_STORE_PATH`; `DESK_WINDOW_SIZE=1440x900` pins the window.
- Hooks are installed only when `DESK_SCRATCH_STORE` or `DESK_DEBUG_HOOKS=1` is set. The notification is a broadcast, and on
  2026-11-02 an app run from Xcode against the real store answered a scripted `demo` command; the gate prevents a repeat.
  `action removeDemo` (and File → Remove Demo Data…) deletes exactly the seed records by content.
- `block <title> <startMinutes> <endMinutes>` creates a block on the selected date (used to reproduce short-block layouts).
- Short blocks: `OverlapLayout.visualHeight` gives slivers a 16 pt floor only when nothing follows in the same lane; otherwise
  they keep their true height and render a one-line micro label, so 12:00–12:15 never paints over a block at 12:15.
- Posted `NSEvent`s reach AppKit controls/SwiftUI buttons but NOT SwiftUI gestures; drags are tested with XCUITest's
  `click(forDuration:thenDragTo:)` (`press(forDuration:thenDragTo:)` does not drive SwiftUI drags on macOS).

## Test results (final run, 2026-11-01 22:50)
`xcodebuild -project Desk.xcodeproj -scheme Desk -destination 'platform=macOS' test`
- DeskTests: 42 tests in 5 suites — all passed (LocalDate/DeskCalendar, RecurrenceEngine, OverlapLayout, PlannerStore,
  External events & schedule merging).
- DeskUITests: 5 tests — all passed (drag-create → move → resize → undo×2; letter shortcuts vs. typing; notes/priorities survive
  rapid navigation and relaunch; block visible in Week and Day; weekly routine + "This Occurrence" scope prompt).
- Release build: `dist/Desk.app` (ad-hoc signed, `codesign --verify` ok), zipped as `dist/Desk.zip`.

Visual checks done from rendered screenshots: Day/Week at 1440×900 light and dark, block editor popover, 1100×720 week,
820×760 stacked day layout, shortcut help sheet.

## Known caveats
- Recurrence: weekly on chosen weekdays only; no end date in the UI (model supports it).
- Blocks cannot cross midnight.
- Ad-hoc signature → one-time right-click ▸ Open on first launch.
- The window remembers its last size (standard macOS behaviour); first launch defaults to 1440×900.
- Priority rows: Backspace-on-empty removal relies on SwiftUI `onKeyPress` on a focused TextField (macOS 14+); verified only by code review, not by UI test.

## Next action (if resuming)
Nothing blocking. Possible follow-ups: routine end dates in the editor, printing, a "stop repeating from this date" option.
