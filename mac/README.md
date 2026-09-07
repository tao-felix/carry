# Carry for Mac

The Mac half of Carry, complete in one app: a luggage tag in the menu bar, one window, no Dock icon, and the whole engine inside. A person installs Carry.app and the Carry iPhone app and never opens a terminal.

The engine is a Swift port of the Python reference in `cli/src/carry/` (`docs/ENGINE.md` is the contract). Both write the same `~/.carry/carry.db` rows (same ids, same fields) and byte-for-byte the same `~/.carry/context/*.md`, so an agent cannot tell which one wrote them. The CLI stays the open-source reference and the headless path.

## What it does

- **Reads** (read-only, never copied): Photos and Screenshots from `Photos.sqlite`; with Full Disk Access also Voice Memos, Notes (gzip + protobuf body), Messages (typedstream bodies, names from Contacts), Calendar (occurrence cache), Reminders, Safari, Screen Time (`knowledgeC.db`). Plus everything the iPhone app wrote to the iCloud container: Health, Location, Share inbox, `sources.json`, `manifest.json`, `license.json`; and Health Auto Export JSON as a fallback.
- **Processing** (Pro): OCR with Vision (`VNRecognizeTextRequest`, accurate, zh-Hans / en-US / ja-JP, confidence ≥ 0.3) for screenshots, inbox images and, when `ocr_photos` is on, photos. Transcription with `SpeechAnalyzer` + `SpeechTranscriber` on macOS 26 (on-device, long-form; a 78-minute memo takes about 75 s), `SFSpeechRecognizer` over ≤ 60 s chunks on macOS 14/15. A transcriber speaks one language, so with several preferred languages the engine transcribes the first 45 s in each and keeps the one with the highest confidence. Cap 90 minutes per recording, 3 per run; audio is copied to `~/.carry/tmp/` first.
- **Digest**: `~/.carry/context/YYYY-MM-DD.md` for the last 7 days, `latest.md` (symlink), `week.md`, `README.md`, section order and wording exactly as `digest.py`.
- **Store**: `~/.carry/carry.db`, system `libsqlite3`, WAL, FTS5 trigram, the schema and triggers of `store.py`, the "never overwrite processed text" rule, per-source cursors.
- **License**: `license.json` (StoreKit 2 JWS) verified offline, chain to the embedded Apple Root CA G3, ES256 over `header.payload`, product id `app.carry.pro` / `app.carry.pro.annual`, 3-day grace. Developer override: `defaults write app.carry.mac CarryProOverride -bool true` (the old `CARRY_PRO` defaults key migrates once) or `CARRY_PRO=1` in the environment.
- **MCP**: Streamable HTTP on `http://127.0.0.1:47850/mcp` while the app runs (loopback only, non-localhost `Origin` refused). Tools `digest`, `search`, `recent`, `item`, `sources`; resource `carry://digest/today`; same schemas and result text as `mcp_server.py`. `POST` JSON-RPC 2.0 answered with `application/json`; notifications get `202`; `GET` gets `405` (no SSE stream).
- **Heartbeat**: `heartbeat/<host>.json` in the container after every sync, same host rule as the CLI.
- **Sync**: at launch, after wake, every 5 / 15 / 30 / 60 minutes (default 15), and on "Sync now". Never two at once. Errors land in `sync_state.last_error` with the CLI's wording ("… Grant Full Disk Access."). The last lines of every run go to `~/.carry/logs/app.log`.
- **Sources**: toggles write `[sources]` in `~/.carry/config.toml` with the CLI's layout, so `carry` and the app agree. When the iPhone's `sources.json` is present it wins and the toggles are disabled.
- **Window**: status line, Full Disk Access card, iPhone card, the twelve sources with channel badges, Pro card (engine license status), **For agents** card, footer (context folder, Run at login, schedule). Everything says what is read, where it goes, who sees it.

## The Full Disk Access flow

Detection is a real read attempt: `open(2)` on `~/Library/Messages/chat.db` (`EPERM` → not granted; `ENOENT` → try `~/Library/Safari/History.db`; neither → nothing to protect). "Grant in System Settings" performs that read (so macOS lists Carry in the pane), opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`, and polls every 2 seconds.

macOS keeps a running process's verdict until it relaunches, so the poll asks twice: the in-process probe, and a child process (`/bin/dd` reading one byte; children are attributed to the app and get a fresh verdict). When only the child says yes, the card shows **Relaunch Carry**; the fresh instance syncs with the grant. Copy stays honest: *One switch, once. macOS doesn't let any app flip it for you.*

## For agents

- The CLAUDE.md / AGENTS.md paragraph with Copy.
- **Add to Claude Code**: if `claude` exists (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `PATH`) the app runs `claude mcp add --transport http carry http://127.0.0.1:47850/mcp` and shows the result line; otherwise it shows the command with Copy.
- **Codex**: the `[mcp_servers.carry]` TOML block with Copy; if `~/.codex/config.toml` exists, "Append for me" backs it up to `config.toml.bak` first (disabled when the table is already there).
- A mono line: `MCP: http://127.0.0.1:47850/mcp · running while Carry runs`.

## Coexistence with the CLI

`~/.carry/app.json` (`{"pid", "version", "last_seen"}`) is written at launch and every minute and removed on quit. `carry init` sees it and skips its LaunchAgent; `carry status` says "scheduler: Carry for Mac". If the CLI's LaunchAgent is installed when the app starts, the app removes it once (`launchctl bootout` + delete the plist) and keeps a `CARRY_PRO=1` it carried as `CarryProOverride`. If both run anyway, WAL and stable ids make double writes harmless.

## Build and run

Requirements: Xcode 26 (SwiftUI, macOS 14+ deployment target, macOS 26 SDK for SpeechAnalyzer), [xcodegen](https://github.com/yonaskolb/XcodeGen). No third-party dependencies: `libsqlite3`, Vision, Speech, AVFoundation, Network, Security, Compression, CryptoKit.

```bash
cd mac
xcodegen generate
xcodebuild -project CarryMac.xcodeproj -scheme Carry -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/Carry.app
```

DEBUG-only launch arguments (see `project.yml`): `-carryAppearance dark`, `-carryPreview 1` (ungranted FDA card and a sample iPhone), `-carrySnapshot /path.png` (window PNG after `-carrySnapshotDelay` seconds, default 3), `-carryScroll bottom`, `-carryNoProcess 1` (skip OCR / transcription), `-carrySyncAndQuit 1` (sync once and exit). DEBUG builds also honour `CARRY_HOME` and `CARRY_CONTAINER` from the environment, and `-CarryProOverride 0|1` as a defaults argument. With a scratch `CARRY_HOME` the app leaves the real LaunchAgent alone.

### Parity test against the CLI

Run the Python reference and the app into two scratch homes and diff:

```bash
CARRY_HOME=/tmp/carry-parity-py CARRY_PRO=0 carry sync --no-process -q
CARRY_HOME=/tmp/carry-parity-swift build/Build/Products/Debug/Carry.app/Contents/MacOS/Carry \
  -carryNoProcess 1 -carrySyncAndQuit 1 -CarryProOverride 0
diff <(sqlite3 /tmp/carry-parity-py/carry.db "select id,source,kind,ts,ts_end,day,title,text,meta,path,device,processed from items order by id") \
     <(sqlite3 /tmp/carry-parity-swift/carry.db "select id,source,kind,ts,ts_end,day,title,text,meta,path,device,processed from items order by id")
diff /tmp/carry-parity-py/context/$(date +%F).md /tmp/carry-parity-swift/context/$(date +%F).md   # only the "generated …" line may differ
```

Both must be empty (apart from the timestamp line). The same test with `CARRY_CONTAINER=` pointing at a folder shaped like the iCloud container (plus `health_auto_export_dir` in `config.toml`) covers Health, Location, inbox, Health Auto Export and the heartbeat; with `messages = true` / `safari = true` in `config.toml` it covers those readers.

### MCP smoke test

```bash
curl -s -X POST http://127.0.0.1:47850/mcp -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}'
curl -s -X POST http://127.0.0.1:47850/mcp -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
curl -s -X POST http://127.0.0.1:47850/mcp -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search","arguments":{"query":"分身"}}}'
claude mcp add --transport http carry http://127.0.0.1:47850/mcp && claude mcp list
```

## Files

- `Carry/CarryApp.swift` (entry, MenuBarExtra, AppDelegate, DEBUG arguments), `AppModel.swift` (state, scheduler, FDA flow, agents actions), `Models.swift` (status shapes), `Support.swift` (home, presence file, log, FDA probes, heartbeat file, LaunchAgent, `Shell`), `MainWindow.swift`, `MainView.swift` (the cards), `MenuContent.swift`, `MenuBarIcon.swift`, `Theme.swift`, `UI.swift` (design system from `docs/DESIGN.md`).
- `Carry/Engine/`: `Util.swift` (Python-exact time, ids, whitespace, excerpts, float repr, ordered JSON), `SQLite.swift`, `Store.swift`, `Config.swift` (source registry, TOML, `sources.json` policy), `Apps.swift`, `Decoders.swift` (typedstream, Notes protobuf, gunzip), `Readers/` (one file per Apple source), `Container.swift` (iCloud container, Health Auto Export, heartbeat), `Processing/` (`VisionOCR.swift`, `Transcribe.swift`, `Processing.swift`), `License.swift`, `Digest.swift`, `Sync.swift` (the engine: sync, status, sources), `MCPServer.swift`.

## Signing, notarization, distribution

The project leaves hardened runtime off so it builds anywhere. Before handing the app to anyone:

1. **Developer ID**. Sign with a Developer ID Application certificate. TCC keys the Full Disk Access grant to the app's code signature; a stable identity keeps the grant across updates.
2. **Hardened runtime**. `ENABLE_HARDENED_RUNTIME: YES`. No entitlements beyond that: the app is not sandboxed (it reads `~/.carry`, Apple's databases, the iCloud container) and `SMAppService.mainApp` needs none. `NSSpeechRecognitionUsageDescription` is in `Info.plist` for the macOS 14/15 transcription path.
3. **Notarize and staple**, then ship as a DMG: `scripts/release.sh`, verify with `scripts/verify-dmg.sh`.
4. Keep `LSUIElement` true; the Dock stays empty on purpose.

No App Store: Full Disk Access is outside the sandbox.
