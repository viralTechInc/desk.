#!/bin/zsh
# Archive, sign with your Apple Developer team and upload to TestFlight — no Xcode UI needed.
#
# One-time setup (your side):
#   1. App Store Connect → Apps → "+" → macOS app "Desk", bundle ID com.desk.planner.
#   2. App Store Connect → Users and Access → Integrations → App Store Connect API → "+"
#      (role: App Manager or Developer). Note the Key ID and Issuer ID, download AuthKey_<ID>.p8
#      and put it in ~/.private_keys/ (Apple's tools look there).
#   3. Create .testflight.env next to this repo's project.yml (it is git-ignored):
#        DESK_TEAM_ID=XXXXXXXXXX        # 10-character Team ID (developer.apple.com → Membership)
#        ASC_KEY_ID=XXXXXXXXXX
#        ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#        ASC_KEY_PATH=$HOME/.private_keys/AuthKey_XXXXXXXXXX.p8   # optional
#   4. TestFlight → add testers (internal: team members on App Store Connect; external: any email).
#
# Each run: scripts/testflight.sh   → new build number (UTC timestamp), archive, upload.
# Builds show up in TestFlight within ~10–30 minutes; testers get them automatically.
set -e
cd "$(dirname "$0")/.."
[[ -f .testflight.env ]] && source .testflight.env
: "${DESK_TEAM_ID:?Set DESK_TEAM_ID in .testflight.env (see header of this script)}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID in .testflight.env}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID in .testflight.env}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[[ -f "$ASC_KEY_PATH" ]] || { echo "API key not found at $ASC_KEY_PATH"; exit 1 }

BUILD="${DESK_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
ARCHIVE=build/TestFlight/Desk.xcarchive
EXPORT=build/TestFlight/export
AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "→ Desk $VERSION ($BUILD) for team $DESK_TEAM_ID"
xcodegen generate >/dev/null
rm -rf "$ARCHIVE" "$EXPORT"

xcodebuild -project Desk.xcodeproj -scheme Desk -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive -quiet \
  -allowProvisioningUpdates "${AUTH[@]}" \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM="$DESK_TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD"

cat > build/TestFlight/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$DESK_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist build/TestFlight/ExportOptions.plist \
  -allowProvisioningUpdates "${AUTH[@]}"

echo "✓ Uploaded Desk $VERSION ($BUILD). It appears in App Store Connect → TestFlight once processed."
