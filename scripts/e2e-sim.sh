#!/bin/bash
# End-to-end: iOS app (simulator, DEBUG sandbox container) → Mac CLI → digest → heartbeat back to the app.
set -u
BUNDLE=app.carry.ios
E2E_HOME=${CARRY_E2E_HOME:-/tmp/carry-e2e-home}
DATA=$(xcrun simctl get_app_container booted $BUNDLE data 2>/dev/null)
CONT="$DATA/Documents/CarryContainer/Documents"
echo "container: $CONT"; ls -R "$CONT" 2>/dev/null | head -40
echo "--- sources.json ---"; cat "$CONT/sources.json" 2>/dev/null | head -40
echo "--- manifest.json ---"; cat "$CONT/manifest.json" 2>/dev/null
echo "--- inbox ---"; for f in "$CONT"/inbox/*.json; do [ -f "$f" ] && cat "$f" && echo; done
echo "--- health / location line counts ---"; wc -l "$CONT"/health/*.jsonl "$CONT"/location/*.jsonl 2>/dev/null
echo "--- license.json ---"; cat "$CONT/license.json" 2>/dev/null | cut -c1-200
rm -rf "$E2E_HOME"
echo "=== carry sync against the simulator container ==="
CARRY_HOME="$E2E_HOME" CARRY_CONTAINER="$CONT" CARRY_PRO=1 CARRY_DEBUG=1 carry sync 2>&1 | tail -8
echo "=== carry status ==="; CARRY_HOME="$E2E_HOME" CARRY_CONTAINER="$CONT" carry status 2>&1 | tail -8
echo "=== carry pro (StoreKit test cert is expected to FAIL chain validation) ==="; CARRY_HOME="$E2E_HOME" CARRY_CONTAINER="$CONT" carry pro 2>&1 | head -3
echo "=== digest: inbox + health + places sections ==="; CARRY_HOME="$E2E_HOME" CARRY_CONTAINER="$CONT" carry today 2>&1 | sed -n '1,30p'
echo "=== heartbeat written back for the app ==="; cat "$CONT"/heartbeat/*.json 2>/dev/null
