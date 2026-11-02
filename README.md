# Desk

A calm, private, notebook-first personal planner for macOS. A weekly calendar to
organize life; a daily notebook to organize the mind.

- **Day** — the notebook page: TOP PRIORITIES, a freeform BRAIN DUMP, and the day's
  SCHEDULE side by side. The whole day (06:00–22:00 by default) fits on screen without scrolling.
- **Week** — seven columns of colour-coded time blocks, weekly routines, optional intentions.

Everything is stored on your Mac. No account, no network, no telemetry, no AI.

## Platform

Native macOS app: **Swift 6 · SwiftUI · SwiftData**, deployment target macOS 14 (Sonoma).
Chosen because the full native toolchain (Xcode 27, Swift 6.4) was available; the web
fallback was not needed. The Xcode project is generated from `project.yml` with
[xcodegen](https://github.com/yonaskolb/XcodeGen), so the generated `Desk.xcodeproj` is not committed.

## Prerequisites

- macOS 14 or later to run; macOS 14+ with Xcode 16 or later to build (developed with Xcode 27).
- `brew install xcodegen` (only needed to regenerate the project file).

## Run the prebuilt app

`dist/Desk.app` (also zipped as `dist/Desk.zip`) is an ad-hoc signed Release build. On first
launch macOS may ask you to confirm opening an app from an unidentified developer:
right-click → Open, or allow it under System Settings → Privacy & Security.

## Build from source

```bash
xcodegen generate
```

```bash
xcodebuild -project Desk.xcodeproj -scheme Desk -configuration Release -destination 'platform=macOS' -derivedDataPath build/ReleaseDD build
```

The app lands in `build/ReleaseDD/Build/Products/Release/Desk.app`. Or open `Desk.xcodeproj`
in Xcode and press ⌘R. Signing is ad-hoc (`CODE_SIGN_IDENTITY: "-"`); set your own team in
`project.yml` if you want a Developer ID build.

## Tests

```bash
xcodebuild -project Desk.xcodeproj -scheme Desk -destination 'platform=macOS' test
```

- `DeskTests` — 42 unit tests: date arithmetic across DST (America/Toronto) and year
  boundaries, weekly recurrence expansion, exceptions (cancel / change / move), series edits
  after exceptions, store transactions with undo/redo, overlap layout, backup round trip,
  external-event slicing (multi-day, all-day, midnight end, DST), calendar filtering, mixed
  overlap layout, and menu-bar current/next selection.
- `DeskUITests` — 5 interaction tests driven by real system events: drag-to-create, move,
  resize and undo; letter shortcuts never typing into notes; notes and priorities surviving
  rapid navigation and relaunch; a block created in one view showing in the other; weekly
  routines and the "this occurrence / entire routine" prompt. The app window appears briefly
  while they run; each test uses a throwaway store.

## Using Desk

| Key | Action |
|---|---|
| T / N | Today / Tomorrow |
| J / K | Previous / next day (or week in Week view) |
| D / W | Day / Week |
| B / P | Focus brain dump / first priority |
| A | Add a block |
| Esc | Close popover, deselect |
| ⌘Z / ⇧⌘Z | Undo / redo (text while typing, otherwise block changes) |
| ? | Shortcut help |

Letter shortcuts only fire when you are not typing in a text field. The menu bar carries
⌘-equivalents for everything (Go, Notebook, File, Help menus).

- **Blocks**: drag on the grid to create, click to edit, drag to move (across days in Week),
  drag the bottom edge to resize, right-click for duplicate / skip / delete. 15-minute snapping;
  exact times can be typed in the editor (`9`, `9:30`, `14h`, `9:30 pm` all work).
- **Routines**: in the block editor pick weekdays under Repeat. Editing a recurring block asks
  for a scope: *This occurrence* creates an exception; *Entire routine* changes the series.
  Series edits apply to every non-overridden occurrence; exceptions keep only the fields they
  explicitly changed. Moving a series to another day rotates its weekday pattern. Turning
  Repeat off converts the series into a single block on the edited day. Deleting a routine asks
  for confirmation; everything else is undoable.
- **Notebook**: priorities start as three numbered lines; Return on the last line adds one,
  Backspace on an empty line removes it. The brain dump is plain text with tabs, undo/redo,
  spell check and find (⌘F). Nothing is ever turned into a task or carried to another day.
- **Settings (⌘,)**: appearance, hour height (fit to window / fixed), visible hours, first day of
  week, weekly intentions, data location, backup.

## Calendars from your Mac (Google, iCloud, Exchange…)

Desk reads the calendars already configured on your Mac through Apple's EventKit and shows
their events next to your blocks in Day, Week and the menu bar. Nothing is written back, no
Google Cloud project, no OAuth, no backend: the OS keeps the accounts in sync and Desk observes
the local calendar database.

Setup:

1. **System Settings → Internet Accounts** → add your Google (or iCloud/Exchange) account and
   turn on *Calendars* for it. Repeat for each account.
2. In Desk, open **Settings (⌘,) → Calendars** and click **Allow Calendar Access…**. macOS asks
   once; choose *Allow Full Access*. (Desk only reads events, but macOS 14's full-access level
   is what exposes event details to apps.)
3. Tick the calendars you want to see. Everything is on by default; new calendars appear
   automatically; selections are remembered on this Mac.

Behaviour:

- Events show in the calendar's own colour with a dashed outline so they read as "from
  outside"; click one for details and *Open in Calendar*. All-day events sit in a strip above
  the grid. Multi-day events are sliced per day. Events without a title (private/busy-only
  calendars) show as "Busy".
- Events with a video call show a camera icon. Desk finds Google Meet, Zoom, Microsoft Teams,
  Webex and FaceTime links in the event's URL, location or description (this is what Google
  syncs for Meet). The popover gets a *Join Google Meet* button and a copyable link, and the
  menu bar rows get a *Join* button.
- Changes made in Calendar, on your phone or on the web appear while Desk is running (EventKit
  change notifications, plus a refresh whenever Desk becomes active or you navigate). Removing
  an account in System Settings removes its events.
- The **menu bar** item shows what's happening now and how long is left, or the next item with a
  countdown (within two hours). Its popover lists the current item and the next three. When a
  meeting overlaps a Desk work block, the meeting is shown first; the block is untouched.
- If access was declined, Settings → Calendars explains and links to *Privacy & Security →
  Calendars*. If there are no calendars, it links to *Internet Accounts*.

Note for builds from source: the app is ad-hoc signed, so macOS treats each rebuild as a new
app for privacy purposes and may ask for calendar access again.

## Architecture

```
Desk/
  App/         DeskApp (scene + wiring), AppState (navigation/selection), AppActions (commands,
               file dialogs, scope prompts), AppSettings, DeskCommands (menus), ShortcutMonitor
               (letter keys via a local NSEvent monitor), DebugHooks (DEBUG-only remote control)
  Domain/      LocalDate + DeskCalendar (calendar/time-zone policy), WeekdaySet, BlockCategory,
               EventOccurrence/BlockDraft, RecurrenceEngine (pure expansion of rules + overrides),
               TimelineGeometry + OverlapLayout (shared by Day and Week)
  Persistence/ SwiftData models (DailyPage, WeeklyPage, TimeBlock, RecurrenceRule,
               OccurrenceOverride), Records (Codable mirrors used for undo snapshots and backups),
               PlannerStore (all reads/writes; transactional mutations with snapshot undo;
               debounced notebook saves), SeedData (opt-in demo content)
  Calendar/    CalendarService (EventKit, read-only; permissions, calendar list, enabled set,
               change observation), ExternalEvent + ExternalEventSplitter (per-day slices),
               ScheduleEntry (block | external), ScheduleMerger (pure merge + "now/next" logic)
  Views/       RootView + toolbar, Day (DayView, NotebookPanel, PlainTextView), Week,
               Timeline (TimelineGrid, TimeBlockView, ExternalEventView, AllDayStrip),
               Editor (BlockEditorView), Settings (General, Calendars), Help, MenuBar
DeskTests/     unit tests          DeskUITests/   XCUITest interaction tests
scripts/       make-icon.swift, desk-debug.swift (drives DEBUG builds for screenshots), shot.swift
```

Key decisions:

- Dates are `LocalDate` (year/month/day, stored as `yyyymmdd`), times are minutes from
  midnight. Day arithmetic anchors at noon so DST never skips or doubles a day.
- Recurring occurrences are never stored; `RecurrenceEngine` expands rules + overrides for the
  queried date window on demand. Day and Week read the same source.
- Block/rule mutations are transactions: a snapshot of the affected records is captured before
  and after and registered with a store-owned `UndoManager`. Text views keep their own undo
  stacks so ⌘Z while typing only affects typing.
- Notebook text is written to the model synchronously and saved to disk after a 600 ms
  debounce (and immediately on navigation, view switch, deactivation and quit). Blank pages are
  pruned, so days are created lazily.

## Where your data lives

SwiftData store (SQLite) inside the app's sandbox container:

```
~/Library/Containers/com.desk.planner/Data/Library/Application Support/Desk/Desk.store
```

Settings → Data → *Reveal in Finder* opens it. Preferences are in the container's
`UserDefaults`. Back up with **File → Export Backup…** (⇧⌘E): a single human-readable JSON
file with every page, block, routine and exception. **File → Import Backup…** previews the
file's contents and asks for confirmation before replacing the current data. Time Machine also
covers the container.

## Known limitations

- Recurrence is weekly-on-selected-weekdays only (no monthly/yearly/interval rules); routines
  have no end date in the UI.
- Blocks live within one day (no overnight blocks); the timeline shows 00:00–24:00 at most.
- Calendar events are read-only; no printing, no sync of Desk's own data.
- Ad-hoc signed: Gatekeeper requires a one-time right-click → Open.
