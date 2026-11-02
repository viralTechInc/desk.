#!/bin/zsh
# Interaction smoke test against a DEBUG build. Uses a scratch store inside the sandbox container.
set -e
cd "$(dirname "$0")/.."
C=$HOME/Library/Containers/ca.viraltech.desk/Data/tmp
D=build/desk-debug
APP=build/DerivedData/Build/Products/Debug/Desk.app
pkill -x Desk 2>/dev/null || true; sleep 0.5
rm -rf $C/smoke; mkdir -p $C/smoke/shots
open $APP --env DESK_STORE_PATH=$C/smoke/Desk.store; sleep 3
$D resize 1440 900; sleep 0.8
$D date 2026-11-03; sleep 0.5            # a Tuesday with no events
# 1. drag-create 10:00 → 11:30 in the day column (6AM at y≈228, 39px/hour)
$D drag 1100 384 1100 442; sleep 1.0
$D screenshot $C/smoke/shots/1-created.png; sleep 0.8
$D type "Test block"; sleep 0.3
$D click 300 760; sleep 0.8               # click notebook → popover commits
$D dump $C/smoke/1.txt; sleep 0.3
# 2. move it two hours later
$D drag 1100 410 1100 488; sleep 1.0
$D dump $C/smoke/2.txt; sleep 0.3
# 3. resize bottom edge 13:30 → 14:00 (end y ≈ 228+7.5*39=520 → 540)
$D drag 1100 517 1100 542; sleep 1.0
$D dump $C/smoke/3.txt; sleep 0.3
$D screenshot $C/smoke/shots/3-moved-resized.png; sleep 0.8
# 4. keyboard: click empty grid first, then letters
$D click 1100 300; sleep 0.4
$D key w; sleep 0.8; $D screenshot $C/smoke/shots/4-week.png; sleep 0.8
$D key k; sleep 0.5; $D dump $C/smoke/4-nextweek.txt; sleep 0.3
$D key d; sleep 0.5; $D key t; sleep 0.5; $D dump $C/smoke/4-today.txt; sleep 0.3
$D date 2026-11-03; sleep 0.5
$D key b; sleep 0.5; $D type "notes line one"; sleep 0.2
$D key n; sleep 0.3                        # must type an 'n', not navigate
$D key return; sleep 0.2; $D type "	indented"; sleep 0.3
$D key p; sleep 0.5; $D type "First priority"; sleep 0.3
$D action flush; sleep 0.5
$D dump $C/smoke/5-text.txt; sleep 0.3
$D screenshot $C/smoke/shots/5-text.png; sleep 0.8
# 5. undo (not editing text): click grid, ⌘Z twice → resize and move undone
$D click 1100 300; sleep 0.3
$D key z 1; sleep 0.5; $D key z 1; sleep 0.5
$D dump $C/smoke/6-undo.txt; sleep 0.3
# 6. restart and check persistence
$D action quit; sleep 1.5
open $APP --env DESK_STORE_PATH=$C/smoke/Desk.store; sleep 3
$D resize 1440 900; sleep 0.5
$D date 2026-11-03; sleep 0.5
$D dump $C/smoke/7-restart.txt; sleep 0.3
$D screenshot $C/smoke/shots/7-restart.png; sleep 0.8
for f in $C/smoke/*.txt; do echo "== $(basename $f)"; cat $f; echo; done
