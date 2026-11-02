# Desk — Agent Progress

## Platform decision
Native macOS app: Swift 6 (strict concurrency), SwiftUI, SwiftData, macOS 14+ deployment target.
Environment check: Xcode 27.0 / Swift 6.4 / macOS 27.0 SDK / xcodegen 2.46 available → native path, no web fallback.
Project file is generated from `project.yml` with xcodegen (`xcodegen generate`; `Desk.xcodeproj` is gitignored).
References folder (`references/image.jpg`, `references/weekly-plan.pdf`) was **not present**; built from the written spec.

## Milestones (all done 2026-11-01)
- [x] Phase 0 — scaffold, build baseline
- [x] Phase 1 — domain models, SwiftData persistence, recurrence engine, undo transactions, backup format, seed data, unit tests
- [x] Phase 2 — Day screen: toolbar, serif date heading, 52/48 split (stacks under 900 pt), priorities, brain dump (NSTextView), timeline
- [x] Phase 3 — Week screen: seven columns, drag-create / move across days / resize, overlap columns, scope prompt for routines, intentions row
- [x] Phase 4 — letter shortcuts + menus, context menus, settings, shortcut help, backup export/import, demo data (opt-in), app icon, Release build in `dist/`

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
- Posted `NSEvent`s reach AppKit controls/SwiftUI buttons but NOT SwiftUI gestures; drags are tested with XCUITest's
  `click(forDuration:thenDragTo:)` (`press(forDuration:thenDragTo:)` does not drive SwiftUI drags on macOS).

## Test results (final run, 2026-11-01 22:50)
`xcodebuild -project Desk.xcodeproj -scheme Desk -destination 'platform=macOS' test`
- DeskTests: 31 tests in 4 suites — all passed (LocalDate/DeskCalendar, RecurrenceEngine, OverlapLayout, PlannerStore).
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
