#!/bin/bash
# Play the recipient: quarantine the DMG like a browser download, mount it, and run the checks Gatekeeper runs.
#   ./scripts/verify-dmg.sh dist/Carry-0.1.0-arm64.dmg
set -uo pipefail
dmg=${1:?path to the DMG}; work=$(mktemp -d); mnt="$work/mnt"; mkdir -p "$mnt"
cp "$dmg" "$work/dl.dmg"; xattr -w com.apple.quarantine "0083;00000000;Safari;$(uuidgen)" "$work/dl.dmg"
hdiutil attach "$work/dl.dmg" -nobrowse -quiet -mountpoint "$mnt" || { echo "✗ cannot mount"; exit 1; }
app="$mnt/Carry.app"; fail=0
ok(){ echo "  ✓ $1"; }; bad(){ echo "  ✗ $1"; fail=1; }
g=$( (spctl -a -vv "$app" 2>&1 || true) | tr '\n' ' '); case "$g" in *accepted*) ok "Gatekeeper accepts ($g)";; *) bad "Gatekeeper rejects ($g)";; esac
xcrun stapler validate "$app" >/dev/null 2>&1 && ok "app stapled (opens offline)" || bad "app not stapled"
xcrun stapler validate "$work/dl.dmg" >/dev/null 2>&1 && ok "dmg stapled" || bad "dmg not stapled"
codesign --verify --deep --strict "$app" 2>/dev/null && ok "signature chain verifies" || bad "signature broken"
codesign -d --entitlements :- "$app" 2>/dev/null | grep -q "com.apple.security" && ok "hardened runtime entitlements present" || echo "  · no extra entitlements (fine for Carry)"
hdiutil detach "$mnt" -quiet -force 2>/dev/null || true; rm -rf "$work"
[ $fail = 0 ] && echo "PASS: a stranger can install this" || { echo "FAIL"; exit 1; }
