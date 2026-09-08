#!/usr/bin/env bash
# Archive, export and upload Carry for iOS to App Store Connect (TestFlight).
#
# Needs, in the environment (e.g. `set -a; . ~/.claude/.env; set +a`):
#   APPLE_API_KEY_ID / APPLE_API_ISSUER   App Store Connect API key (the .p8 lives in ~/.appstoreconnect/private_keys)
# and, installed on this Mac:
#   an "Apple Distribution" identity for $TEAM, plus the two App Store provisioning profiles
#   named below (download them from developer.apple.com → Profiles, double-click to install).
#
# Usage:  ios/scripts/testflight.sh [build-number]
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM="${CARRY_TEAM:-PZHSCK4VXU}"
PROFILE_APP="${CARRY_PROFILE_APP:-Carry App Store}"
PROFILE_SHARE="${CARRY_PROFILE_SHARE:-Carry Share App Store}"
BUILD="${1:-$(date +%Y%m%d%H%M)}"
OUT="${CARRY_TF_OUT:-$HOME/Claude_Code/tmp/carry-tf}"
mkdir -p "$OUT"

: "${APPLE_API_KEY_ID:?set APPLE_API_KEY_ID}"; : "${APPLE_API_ISSUER:?set APPLE_API_ISSUER}"
xcodegen generate >/dev/null

echo "▸ archive (build $BUILD)"
xcodebuild -project Carry.xcodeproj -scheme Carry -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Carry.xcarchive" archive \
  CURRENT_PROJECT_VERSION="$BUILD" DEVELOPMENT_TEAM="$TEAM" \
  CARRY_SIGN_STYLE=Manual CARRY_PROFILE_APP="$PROFILE_APP" CARRY_PROFILE_SHARE="$PROFILE_SHARE" \
  CODE_SIGN_IDENTITY="Apple Distribution" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  > "$OUT/archive.log" 2>&1 || { tail -30 "$OUT/archive.log"; exit 1; }

cat > "$OUT/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>$TEAM</string>
  <key>uploadSymbols</key><true/>
  <key>provisioningProfiles</key><dict>
    <key>app.carry.ios</key><string>$PROFILE_APP</string>
    <key>app.carry.ios.share</key><string>$PROFILE_SHARE</string>
  </dict>
</dict></plist>
PLIST

echo "▸ export"
rm -rf "$OUT/export"
xcodebuild -exportArchive -archivePath "$OUT/Carry.xcarchive" -exportOptionsPlist "$OUT/export.plist" \
  -exportPath "$OUT/export" > "$OUT/export.log" 2>&1 || { tail -30 "$OUT/export.log"; exit 1; }

echo "▸ validate"
xcrun altool --validate-app -f "$OUT/export/Carry.ipa" -t ios --apiKey "$APPLE_API_KEY_ID" --apiIssuer "$APPLE_API_ISSUER" \
  > "$OUT/validate.log" 2>&1 || { grep -v '^$' "$OUT/validate.log" | tail -20; exit 1; }

echo "▸ upload"
xcrun altool --upload-app -f "$OUT/export/Carry.ipa" -t ios --apiKey "$APPLE_API_KEY_ID" --apiIssuer "$APPLE_API_ISSUER" \
  > "$OUT/upload.log" 2>&1 || { grep -v '^$' "$OUT/upload.log" | tail -20; exit 1; }
grep -E "UPLOAD SUCCEEDED|Delivery UUID" "$OUT/upload.log"
echo "→ App Store Connect will process the build in a few minutes; TestFlight groups with automatic distribution get it right after."
