#!/bin/bash
# Build, sign, notarize, staple and package Carry for Mac as a DMG that a stranger's Mac will open.
# Modeled on laoji's release-dmg.sh: two notarization passes (app, then DMG) so "double-click the image" works offline.
#
#   CARRY_SIGN_IDENTITY="Developer ID Application: <name> (<TEAM>)" \
#   CARRY_NOTARY_PROFILE=carry-notary   # once: xcrun notarytool store-credentials carry-notary --apple-id … --team-id … --password <app-specific>
#   # or, like laoji: APPLE_API_KEY=/path/AuthKey.p8 APPLE_API_KEY_ID=… APPLE_API_ISSUER=…
#   ./scripts/release.sh
#
# CARRY_NOTARIZE=false signs only (for checking the chain locally; that package must not be shipped).
set -euo pipefail
cd "$(dirname "$0")/.."
notarize=${CARRY_NOTARIZE:-true}
notarize_or_die() {  # submit, wait, and stop with Apple's own log when the ticket is not Accepted
  local out; out=$(xcrun notarytool submit "$1" "${notary_args[@]}" --wait 2>&1); echo "$out"
  local id; id=$(echo "$out" | awk '/^  id:/{print $2; exit}')
  echo "$out" | grep -q "status: Accepted" || { echo "✗ notarization not accepted; Apple's log:"; xcrun notarytool log "$id" "${notary_args[@]}" | head -60; exit 1; }
}
: "${CARRY_SIGN_IDENTITY:?set CARRY_SIGN_IDENTITY to a 'Developer ID Application: …' identity in the keychain}"
security find-identity -v -p codesigning | grep -qF "$CARRY_SIGN_IDENTITY" || { echo "✗ identity not in keychain: $CARRY_SIGN_IDENTITY" >&2; exit 1; }
notary_args=(--keychain-profile "${CARRY_NOTARY_PROFILE:-carry-notary}")
[ -n "${APPLE_API_KEY:-}" ] && notary_args=(--key "$APPLE_API_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER")
version=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
out=dist; dd=build-release; rm -rf "$out" "$dd"; mkdir -p "$out"
echo "· identity: $CARRY_SIGN_IDENTITY"; echo "· version: $version"; echo "· notarize: $notarize"

xcodegen generate >/dev/null
xcodebuild -project CarryMac.xcodeproj -scheme Carry -configuration Release -derivedDataPath "$dd" \
  CODE_SIGN_IDENTITY="$CARRY_SIGN_IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$(echo "$CARRY_SIGN_IDENTITY" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')" \
  ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" build | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
app="$dd/Build/Products/Release/Carry.app"
codesign --verify --deep --strict --verbose=2 "$app"

if [ "$notarize" != false ]; then
  ditto -c -k --keepParent "$app" "$out/Carry-app.zip"
  notarize_or_die "$out/Carry-app.zip"
  xcrun stapler staple "$app"
fi

dmg="$out/Carry-$version-arm64.dmg"
staging=$(mktemp -d); cp -R "$app" "$staging/"; ln -s /Applications "$staging/Applications"
hdiutil create -volname "Carry" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
codesign --sign "$CARRY_SIGN_IDENTITY" --timestamp "$dmg"
if [ "$notarize" != false ]; then
  notarize_or_die "$dmg"
  xcrun stapler staple "$dmg"
fi

echo "— acceptance (what the recipient's Mac will run) —"
codesign -dvv "$app" 2>&1 | grep -E "Authority=|TeamIdentifier=" | head -3
echo "  Gatekeeper: $(spctl -a -vvv "$app" 2>&1 | tr '\n' ' ')"
[ "$notarize" != false ] && { echo "  staple(app): $(xcrun stapler validate "$app" 2>&1 | tail -1)"; echo "  staple(dmg): $(xcrun stapler validate "$dmg" 2>&1 | tail -1)"; }
echo "→ $dmg"
