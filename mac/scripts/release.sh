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
: "${CARRY_SIGN_IDENTITY:?set CARRY_SIGN_IDENTITY to a 'Developer ID Application: …' identity in the keychain}"
security find-identity -v -p codesigning | grep -qF "$CARRY_SIGN_IDENTITY" || { echo "✗ identity not in keychain: $CARRY_SIGN_IDENTITY" >&2; exit 1; }
notary_args=(--keychain-profile "${CARRY_NOTARY_PROFILE:-carry-notary}")
[ -n "${APPLE_API_KEY:-}" ] && notary_args=(--key "$APPLE_API_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER")
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Carry/Info.plist 2>/dev/null || echo 0.1.0)
out=dist; rm -rf "$out" build/Release; mkdir -p "$out"
echo "· identity: $CARRY_SIGN_IDENTITY"; echo "· version: $version"; echo "· notarize: $notarize"

xcodegen generate >/dev/null
xcodebuild -project CarryMac.xcodeproj -scheme Carry -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="$CARRY_SIGN_IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$(echo "$CARRY_SIGN_IDENTITY" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" build | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
app="build/Build/Products/Release/Carry.app"
codesign --verify --deep --strict --verbose=2 "$app"

if [ "$notarize" != false ]; then
  ditto -c -k --keepParent "$app" "$out/Carry-app.zip"
  xcrun notarytool submit "$out/Carry-app.zip" "${notary_args[@]}" --wait
  xcrun stapler staple "$app"
fi

dmg="$out/Carry-$version-arm64.dmg"
staging=$(mktemp -d); cp -R "$app" "$staging/"; ln -s /Applications "$staging/Applications"
hdiutil create -volname "Carry" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
codesign --sign "$CARRY_SIGN_IDENTITY" --timestamp "$dmg"
if [ "$notarize" != false ]; then
  xcrun notarytool submit "$dmg" "${notary_args[@]}" --wait
  xcrun stapler staple "$dmg"
fi

echo "— acceptance (what the recipient's Mac will run) —"
codesign -dvv "$app" 2>&1 | grep -E "Authority=|TeamIdentifier=" | head -3
echo "  Gatekeeper: $(spctl -a -vvv "$app" 2>&1 | tr '\n' ' ')"
[ "$notarize" != false ] && { echo "  staple(app): $(xcrun stapler validate "$app" 2>&1 | tail -1)"; echo "  staple(dmg): $(xcrun stapler validate "$dmg" 2>&1 | tail -1)"; }
echo "→ $dmg"
