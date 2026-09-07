# carry (Mac CLI)

The Mac side of Carry. Reads what iCloud already synced to this Mac plus what the Carry iPhone app wrote to the iCloud container, keeps one local SQLite store (`~/.carry/carry.db`, FTS5 trigram so Chinese works), and writes the daily digest your agents read.

```bash
uv tool install carry-context            # from PyPI, or: uv tool install ./cli --with ocrmac --with mlx-whisper
carry init          # detects sources, checks Full Disk Access, installs the 15-minute LaunchAgent, prints agent snippets
carry sync          # incremental read of every enabled source → digests → heartbeat to the phone
carry today         # today's digest (also ~/.carry/context/latest.md)
carry search "..."  # full text across everything
carry recent notes  # last items of one source
carry status        # counts, last sync, Pro, iPhone heartbeat
carry sources       # what is on; the iPhone app's sources.json wins when present
carry mcp           # stdio MCP server (claude mcp add carry -- carry mcp)
carry pro           # is the single Pro plan active on this Mac
carry agent install|uninstall|status
```

## What it reads (all read-only, nothing copied)

| source | where on the Mac | needs Full Disk Access |
|---|---|---|
| Photos, Screenshots | `~/Pictures/Photos Library.photoslibrary/database/Photos.sqlite` | no |
| Voice Memos | `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/` | no |
| Notes | `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite` | no |
| Messages | `~/Library/Messages/chat.db` (+ Contacts for names) | yes |
| Calendar | `~/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb` | no |
| Reminders | `~/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/` | no |
| Safari | `~/Library/Safari/History.db` | yes |
| Screen Time | `~/Library/Application Support/Knowledge/knowledgeC.db` | yes |
| Health, Location, Share inbox | `~/Library/Mobile Documents/iCloud~app~carry~ios/Documents/` (written by the iPhone app) | no |

## Pro

One plan. It unlocks media post-processing on this Mac: screenshot/photo OCR (Apple Vision via `ocrmac`) and voice memo transcription (`mlx-whisper`, Apple Silicon). The license is a StoreKit 2 signed transaction the iPhone app drops into the container as `license.json`; `carry` verifies it offline against Apple Root CA G3. Developer override: `CARRY_PRO=1`.

## Config

`~/.carry/config.toml`: `backfill_days` (first-run window, default 30), `schedule_minutes` (15), `[processing]` `ocr`, `transcribe`, `ocr_photos` (off: photos are only OCR'd when you ask), `transcribe_max_minutes` (90), `max_transcriptions_per_run` (3), `whisper_model`.

Environment: `CARRY_HOME` (default `~/.carry`), `CARRY_CONTAINER` (override the iCloud container path, handy for testing), `CARRY_DEBUG=1` (tracebacks).

## Development

```bash
cd cli && uv venv .venv && uv pip install --python .venv/bin/python -e . ocrmac mlx-whisper
CARRY_HOME=/tmp/carry-home CARRY_CONTAINER=/tmp/carry-container .venv/bin/carry sync
```
