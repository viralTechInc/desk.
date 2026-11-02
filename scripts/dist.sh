#!/bin/zsh
# Local, ad-hoc signed Release build into dist/Desk.app (+ dist/Desk.zip) and relaunch.
# This is the copy you run yourself; TestFlight builds come from scripts/testflight.sh.
set -e
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project Desk.xcodeproj -scheme Desk -configuration Release \
  -derivedDataPath build/ReleaseDD -destination 'platform=macOS' build -quiet
rm -rf dist/Desk.app dist/Desk.zip
mkdir -p dist
ditto build/ReleaseDD/Build/Products/Release/Desk.app dist/Desk.app
codesign --verify --deep --strict dist/Desk.app
(cd dist && ditto -c -k --keepParent Desk.app Desk.zip)
if [[ "$1" != "--no-launch" ]]; then
  pkill -f "dist/Desk.app/Contents/MacOS/Desk" 2>/dev/null || true
  sleep 0.5
  open dist/Desk.app
fi
echo "dist/Desk.app ready ($(defaults read "$PWD/dist/Desk.app/Contents/Info.plist" CFBundleShortVersionString) build $(defaults read "$PWD/dist/Desk.app/Contents/Info.plist" CFBundleVersion))"
