# Carry engine (port spec for the Mac app)

Goal: a person installs **Carry.app** on the Mac and **Carry** on the iPhone and never opens a terminal. Everything the
Python CLI does today must therefore live inside Carry.app, in Swift, on system frameworks only. The Python package in
`cli/` stays as the open-source reference implementation and the headless/developer path; both must produce the same
files, so an agent cannot tell which one wrote `~/.carry/context/`.

Restraint is a feature. Every screen answers: what is read, where it goes, who sees it. No settings that a normal person
would not understand. If a choice can be made for the user, make it.

## 1. What must work without any permission

On first launch, before any grant, Carry.app already produces a useful digest from:

- Photos and Screenshots (`~/Pictures/Photos Library.photoslibrary/database/Photos.sqlite`, read-only, never copied; derivatives for OCR)
- Everything the iPhone app wrote to the iCloud container (Health, Location, Share inbox, sources.json, manifest, license)

Then **one** card offers Full Disk Access. With it, the app reads Notes, Voice Memos, Messages, Calendar, Reminders,
Safari, Screen Time. Nothing else is ever asked. (Calendar/Reminders via EventKit and Notes via Apple Events would avoid
FDA but cost two more prompts each; one FDA switch is simpler for the user, so FDA it is.)

The FDA card: on tap, attempt to open `~/Library/Messages/chat.db` (so macOS lists Carry in the pane), open
`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`, poll every 2 s, then sync. Copy:
"One switch, once. macOS doesn't let any app flip it for you."

## 2. Store

`~/.carry/carry.db`, SQLite (system `libsqlite3`, FTS5 is compiled in), WAL. Schema is exactly `cli/src/carry/store.py`:

```
items(id TEXT PK, source, kind, ts, ts_end, day, title, text, meta JSON, path, device, processed INT, created_at, updated_at)
items_fts: fts5(title, text, content='items', content_rowid='rowid', tokenize='trigram')  + the three sync triggers
sync_state(source PK, cursor, last_run, last_count, last_error)
```

Rules:
- `id = sha1(parts joined by "|")[:20]` with the same parts per source as the Python readers (photo: `"photo", ZUUID`; memo: `"memo", ZPATH`; note: `"note", ZIDENTIFIER`; message: `"msg", guid`; calendar: `"cal", ROWID, occurrence_date`; reminder: `"rem", store file name, Z_PK`; safari: `"safari", visit id`; usage: `"usage", day, bundle, device`; health: `"health", t, start, end, src`; location: `"loc", kind, arrive|ts, lat, lon`; inbox: `"inbox", id`).
- A re-read never overwrites `text` of a row with `processed = 1` (OCR / transcript survive).
- Timestamps are RFC 3339 with the local offset. `day` is the local date of `ts`.
- Cursors: photos = max `ZADDEDDATE` (first run: `ZDATECREATED > now − backfill_days`); voice memos = max `ZDATE`; notes = max `ZMODIFICATIONDATE1`; messages = max `date` (ns); safari = max `visit_time`; calendar/reminders/screen time = windowed re-read; container JSONL = byte offset per file; inbox = re-read all (ids are stable); HAE = per-file mtime+size.

## 3. Readers (Apple data already on the Mac)

All read-only, `sqlite3_open_v2(..., SQLITE_OPEN_READONLY)`. Apple epoch = 978307200; Messages `date` is nanoseconds.

| source | file | query / decode |
|---|---|---|
| photos, screenshots | Photos.sqlite | `ZASSET` (ZUUID, ZFILENAME, ZDIRECTORY, ZDATECREATED, ZADDEDDATE, ZKIND, ZKINDSUBTYPE, ZLATITUDE, ZLONGITUDE, ZFAVORITE, ZHIDDEN, ZTRASHEDSTATE) ⋈ `ZADDITIONALASSETATTRIBUTES` (ZASSET → Z_PK; ZORIGINALFILENAME) ⋈ `ZASSETDESCRIPTION` (ZASSETATTRIBUTES; ZLONGDESCRIPTION). screenshot ⇔ ZKINDSUBTYPE = 10; video ⇔ ZKIND = 1. Image for OCR: `resources/derivatives/<first char of UUID>/<UUID>_1_105_c.*`, else `_1_101_o.*`, else `originals/<ZDIRECTORY>/<ZFILENAME>`. |
| voice_memos | Group Containers/group.com.apple.VoiceMemos.shared/Recordings/CloudRecordings.db | `ZCLOUDRECORDING` (ZENCRYPTEDTITLE or ZCUSTOMLABEL, ZPATH, ZDURATION, ZDATE); audio = `Recordings/<ZPATH>` (.qta/.m4a). Duration 0 happens; probe with AVAsset. |
| notes | Group Containers/group.com.apple.notes/NoteStore.sqlite | `ZICCLOUDSYNCINGOBJECT` (ZTITLE1, ZSNIPPET, ZMODIFICATIONDATE1, ZCREATIONDATE1/3, ZFOLDER→ZTITLE2, ZIDENTIFIER, ZMARKEDFORDELETION=0, ZISPASSWORDPROTECTED) ⋈ `ZICNOTEDATA` (ZNOTE, ZDATA). Body = gunzip(ZDATA) then protobuf field path Document(2) → Note(3) → note_text(2), UTF-8. Locked notes: snippet only. |
| messages (off by default) | ~/Library/Messages/chat.db | `message` ⋈ `handle` ⋈ `chat_message_join` ⋈ `chat` (chat_identifier, display_name, style 43 = group). Text = `text`, else typedstream: find `NSString`, skip 8 bytes (`NSString` + 5 class-info bytes ending in `+`), length byte (0x81 → 2-byte LE, 0x82 → 4-byte LE), UTF-8. Names from Contacts (`AddressBook-v22.abcddb`: ZABCDRECORD, ZABCDPHONENUMBER.ZFULLNUMBER, ZABCDEMAILADDRESS.ZADDRESS; phones normalised to last 10 digits). Numeric senders without a contact = notifications, folded into one digest line. |
| calendar | Group Containers/group.com.apple.calendar/Calendar.sqlitedb | `OccurrenceCache` (occurrence_date, occurrence_end_date, event_id) ⋈ `CalendarItem` (summary, all_day, calendar_id, description, status ≠ 3) ⋈ `Calendar` (title). Window: backfill → +14 days. |
| reminders | Group Containers/group.com.apple.reminders/Container_v1/Stores/Data-*.sqlite | `ZREMCDREMINDER` (ZTITLE, ZDUEDATE, ZCOMPLETED, ZCOMPLETIONDATE, ZCREATIONDATE, ZLASTMODIFIEDDATE, ZLIST→ZREMCDBASELIST.ZNAME, ZNOTES, ZFLAGGED). Far-future sentinel dates → nil. |
| safari (off by default) | ~/Library/Safari/History.db | `history_visits` (visit_time, title, history_item) ⋈ `history_items` (url). |
| screen_time | ~/Library/Application Support/Knowledge/knowledgeC.db | `ZOBJECT` where ZSTREAMNAME = '/app/usage' (ZSTARTDATE, ZENDDATE, ZVALUESTRING = bundle id) ⋈ `ZSOURCE.ZDEVICEID` (non-null ⇒ iPhone when Screen Time shares across devices). Aggregate minutes per (day, bundle, device); recompute the last two days each run. Bundle → name via `NSWorkspace.urlForApplication(withBundleIdentifier:)` + a small map for iOS bundles. |

Container readers (`~/Library/Mobile Documents/iCloud~app~carry~ios/Documents/`): see DATA-CONTRACT §1–§8. Call
`NSFileManager.startDownloadingUbiquitousItem` on the folder first. Also read Health Auto Export JSON at
`~/Library/Mobile Documents/com~apple~CloudDocs/AutoExport/**` as a fallback (translation table in `cli/src/carry/container.py`).

## 4. Processing (what Pro unlocks)

- OCR: `VNRecognizeTextRequest`, `.accurate`, languages `["zh-Hans", "en-US", "ja-JP"]`, confidence ≥ 0.3, lines joined with `\n`. Screenshots and inbox images always; photos only when `ocr_photos` is on.
- Transcription: macOS 26 `SpeechAnalyzer` + `SpeechTranscriber` (on-device, long-form, multilingual). Fallback on macOS 14/15: `SFSpeechRecognizer` with `requiresOnDeviceRecognition`, file split into ≤ 60 s chunks. Cap 90 minutes per recording, 3 recordings per run. Copy the audio to `~/.carry/tmp/` first (the source folder may be readable only by the app).
- Gate: `license.json` verified offline (§6) or `CARRY_PRO=1` in the environment (developer override; the app exposes it as a hidden defaults key `CarryProOverride`).

## 5. Digest

`~/.carry/context/YYYY-MM-DD.md`, `latest.md` (symlink to today), `week.md`, `README.md`. Rewritten every sync for the last 7 days. Section order and wording exactly as `cli/src/carry/digest.py`: header line, Inbox, Health (sleep from stage records ending 00:00–14:00 of the day; steps sum; resting HR / HRV / HR range; energy; workouts; weight; SpO₂), Places, Screenshots (≤ 12, OCR excerpt 220 chars), Photos, Voice memos (transcript excerpt 600), Notes edited, Messages (threads + folded notifications, or "off (you chose)"), Calendar + Next 7 days (deduped by title), Reminders (due / done / overdue), Safari, Screen time; then the three footers: not read in the last sync (FDA), nothing today, switched off.

## 6. License

StoreKit 2 JWS from `license.json`: `x5c` chain to Apple Root CA G3 (embed the PEM), ES256 over `header.payload`
(`SecKeyVerifySignature` with the leaf's public key), `productId ∈ {app.carry.pro.annual, app.carry.pro}`, no
`revocationDate`, `expiresDate` + 3 days grace > now.

## 7. Agents

- Files first: nothing to configure. The app's "For agents" card shows the CLAUDE.md / AGENTS.md paragraph with a Copy button.
- MCP: the app serves Streamable HTTP MCP on `http://127.0.0.1:47850/mcp` (tools `digest`, `search`, `recent`, `item`, `sources`; resource `carry://digest/today`) while running. Buttons: "Add to Claude Code" runs `claude mcp add --transport http carry http://127.0.0.1:47850/mcp` when the `claude` binary exists; "Add to Codex" writes the `[mcp_servers.carry]` block (`url = "http://127.0.0.1:47850/mcp"`, `default_tools_approval_mode = "auto"`) into `~/.codex/config.toml` after showing the diff. Cursor: show the JSON to paste.
- The Python CLI's stdio server keeps working for people who prefer it.

## 8. Coexistence with the CLI

While Carry.app runs it writes `~/.carry/app.json` every minute and schedules syncs itself; the CLI's `init` then skips
its LaunchAgent, and `status` shows "scheduler: Carry for Mac". If both run, WAL and stable ids make double writes
harmless.

## 9. Heartbeat and phone

After every sync write `heartbeat/<host>.json` into the container (DATA-CONTRACT §8) so the iPhone shows
"Mac read 3 min ago". Obey `sources.json` from the phone over any local switch.
