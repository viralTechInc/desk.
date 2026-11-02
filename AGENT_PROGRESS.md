# Desk — Agent Progress

## Platform decision
Native macOS app: Swift 6 (strict concurrency), SwiftUI, SwiftData, macOS 14+ deployment target.
Environment check: Xcode 27.0 / Swift 6.4 / macOS 27.0 SDK / xcodegen 2.46 available → native path, no web fallback.
Project file is generated from `project.yml` with xcodegen (run `xcodegen generate`).
References folder (`references/image.jpg`, `references/weekly-plan.pdf`) was **not present**; built from the written spec.

## Milestones
- [x] Phase 0 — scaffold, build baseline (2026-11-01)
- [x] Phase 1 — domain models, SwiftData persistence, recurrence engine, undo transactions, backup format, seed data, 31 unit tests passing
- [ ] Phase 2 — Day screen
- [ ] Phase 3 — Week screen + interactions
- [ ] Phase 4 — polish, shortcuts, settings, backup UI, docs

## Decisions
- Dates are `LocalDate` (y/m/d) with an integer key `yyyymmdd`; times are minutes from midnight. Arithmetic anchors at noon → DST-safe (tests cross America/Toronto transitions).
- No SwiftData relationships; rules ↔ overrides linked by `ruleID`. Keeps undo snapshots, backups and queries trivial.
- Undo is snapshot-based per transaction (affected blocks/rules + their overrides), registered on a store-owned `UndoManager` with explicit grouping (`groupsByEvent = false`) so it works identically in tests and the app.
- Restore updates models in place rather than delete+insert: SwiftData merges a delete and an insert of the same unique ID in one transaction and the record vanishes (found via failing tests).
- Series edit policy: changed fields apply as absolutes to the rule; the anchor occurrence's override on those fields is cleared; other exceptions keep what they explicitly overrode; day moves rotate the weekday set; orphaned overrides are pruned; turning recurrence off converts to a single block on the edited date.
- Notebook text is written into model objects synchronously, disk save debounced 600 ms; blank pages are pruned on flush so days are created lazily.

## Test results (last run)
`xcodebuild -project Desk.xcodeproj -scheme Desk -destination 'platform=macOS' test` → 31 tests, 4 suites, all passed.

## Current issues
None blocking.

## Next action
Build the Day screen (toolbar, notebook panel, timeline) in `Desk/Views`.
