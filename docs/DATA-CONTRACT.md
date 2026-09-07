# Carry data contract (schema 1)

This is the interface between the three parts of Carry. All three must agree on it:

- **iOS app** (`ios/`) captures what iCloud does not carry (Health, Location, Share inbox) and holds the single control surface: which sources the engine covers.
- **Mac daemon / CLI** (`cli/`, the `carry` command) reads (a) Apple data that iCloud already synced to the Mac and (b) the files the iOS app wrote to the iCloud container. It builds one local store and produces the digest, the MCP server, and the CLI.
- **Website** (`web/`) only describes this. It never sees data.

There is **no Carry server**. Transport is the user's own iCloud. Everything below lives inside the user's iCloud Drive and on the user's Mac.

## 1. The iCloud container

Container identifier: `iCloud.app.carry.ios` (owner sets Team ID in Xcode; the identifier stays).

- iOS writes via `FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.app.carry.ios")` + `/Documents`.
- Mac reads at `~/Library/Mobile Documents/iCloud~app~carry~ios/Documents/`.
- The Mac daemon must call `brctl download <path>` (or `NSFileManager.startDownloadingUbiquitousItem`) before reading, because "Optimize Mac Storage" leaves placeholders.
- Windows (iCloud for Windows) exposes the same folder under `iCloudDrive\iCloud~app~carry~ios\`. Not a v1 target, but do not break it.

```
Documents/
  manifest.json                 # who wrote this, app version, device
  sources.json                  # THE control surface: what the engine covers
  license.json                  # optional. StoreKit 2 signed transaction (JWS) for the single Pro plan
  health/YYYY-MM-DD.jsonl       # one line per sample, append-only, local-date buckets
  location/YYYY-MM-DD.jsonl     # visits and significant-change points
  inbox/<id>.json               # one item per share-sheet action
  inbox/<id>.<ext>              # optional attachment for that item (jpg/png/pdf/...)
  heartbeat/<mac-host>.json     # WRITTEN BY THE MAC. Lets the phone show "Mac read at 21:30"
```

Rules:
- All timestamps are RFC 3339 with offset, e.g. `2026-09-07T21:30:00+08:00`. Never naive.
- Files are append-only or replace-whole. Never rewrite JSONL in place.
- JSONL day buckets use the **device's local date** at sample start.
- IDs are stable so the Mac can dedupe: `id = sha1(source + "|" + kind + "|" + start + "|" + end + "|" + src)` on the Mac side; the phone does not need to compute them.
- Keep every file small (< 5 MB). iCloud syncs small files fast and reliably.

## 2. `manifest.json`

```json
{
  "schema": 1,
  "app_version": "0.1.0",
  "device": { "name": "Tao's iPhone", "model": "iPhone17,1", "os": "iOS 26.0" },
  "updated_at": "2026-09-07T21:00:00+08:00"
}
```

## 3. `sources.json` (control surface)

Every source the engine knows about, whether it comes via iCloud or via the app, is listed here with the user's choice. The Mac daemon **obeys this file**: a source disabled here is not read on the Mac, even if the data is sitting there.

```json
{
  "schema": 1,
  "updated_at": "2026-09-07T21:00:00+08:00",
  "sources": {
    "photos":      { "enabled": true,  "channel": "icloud" },
    "screenshots": { "enabled": true,  "channel": "icloud" },
    "voice_memos": { "enabled": true,  "channel": "icloud" },
    "notes":       { "enabled": true,  "channel": "icloud" },
    "messages":    { "enabled": false, "channel": "icloud" },
    "calendar":    { "enabled": true,  "channel": "icloud" },
    "reminders":   { "enabled": true,  "channel": "icloud" },
    "safari":      { "enabled": false, "channel": "icloud" },
    "screen_time": { "enabled": true,  "channel": "icloud" },
    "health":      { "enabled": true,  "channel": "app",
                     "types": ["sleep","steps","heart_rate","resting_heart_rate","hrv","active_energy","workouts","body_mass","blood_oxygen"] },
    "location":    { "enabled": true,  "channel": "app" },
    "inbox":       { "enabled": true,  "channel": "app" }
  },
  "processing": {
    "ocr": true,
    "transcribe": true
  }
}
```

- `channel: "icloud"` = Apple already syncs it to the Mac; the app only records the user's choice.
- `channel: "app"` = only the Carry app can capture it.
- `processing.*` are the user's wishes. On the Mac they only take effect when the single Pro plan is active (see §7).
- Defaults when a user first installs: everything on **except** `messages` and `safari` (most private; opt-in).
- The Mac CLI may also toggle sources locally (`carry sources`). If both exist, `sources.json` from the phone wins; the CLI prints a note saying so.

## 4. Health: `health/YYYY-MM-DD.jsonl`

One JSON object per line.

```json
{"t":"steps","start":"2026-09-07T08:00:00+08:00","end":"2026-09-07T09:00:00+08:00","v":523,"u":"count","src":"Tao's Apple Watch"}
{"t":"heart_rate","start":"...","end":"...","v":62,"u":"bpm","src":"..."}
{"t":"resting_heart_rate","start":"...","end":"...","v":54,"u":"bpm","src":"..."}
{"t":"hrv","start":"...","end":"...","v":48.2,"u":"ms","src":"..."}
{"t":"active_energy","start":"...","end":"...","v":38.1,"u":"kcal","src":"..."}
{"t":"body_mass","start":"...","end":"...","v":71.4,"u":"kg","src":"..."}
{"t":"blood_oxygen","start":"...","end":"...","v":0.97,"u":"ratio","src":"..."}
{"t":"sleep","start":"2026-09-06T23:40:00+08:00","end":"2026-09-07T00:55:00+08:00","v":"core","u":"stage","src":"..."}
{"t":"workout","start":"...","end":"...","v":"running","u":"type","src":"...","meta":{"distance_m":5012,"energy_kcal":410}}
```

- `t` values: `steps, heart_rate, resting_heart_rate, hrv, active_energy, body_mass, blood_oxygen, sleep, workout`.
- Sleep stages `v`: `inBed, asleepUnspecified, awake, core, deep, rem`.
- Steps and active energy are written as **hourly buckets** (HKStatisticsCollectionQuery), not raw samples, to keep files small.
- Heart rate is written as raw samples but at most one per 5 minutes (keep the last in each 5-minute window).
- The app keeps `HKQueryAnchor`s per type in its own UserDefaults and appends only new samples.
- Apple forbids reading HealthKit while the phone is locked. Sync is therefore "hourly, when unlocked". The app must not pretend otherwise.

## 5. Location: `location/YYYY-MM-DD.jsonl`

```json
{"kind":"visit","arrive":"2026-09-07T09:12:00+08:00","depart":"2026-09-07T11:40:00+08:00","lat":31.2304,"lon":121.4737,"acc_m":40,"place":"Xuhui, Shanghai"}
{"kind":"point","ts":"2026-09-07T12:05:00+08:00","lat":31.2,"lon":121.5,"acc_m":120}
```

- `visit` comes from `CLVisit`. `place` is an optional reverse-geocoded label (CLGeocoder, best effort, cached).
- `point` comes from significant-location-change updates. Keep at most one per 10 minutes.
- Coordinates are full precision; the user chose to enable this source.

## 6. Inbox: `inbox/<id>.json` (+ attachment)

Written by the Share Extension. `<id>` = `YYYYMMDDTHHmmssZ-<6 random base32 chars>`.

```json
{
  "id": "20260907T130522Z-K7Q2MX",
  "ts": "2026-09-07T21:05:22+08:00",
  "kind": "url",
  "title": "The page title if known",
  "url": "https://example.com/post",
  "text": "Selected text or the shared text, if any",
  "file": null,
  "from_app": "com.apple.mobilesafari",
  "note": "User's optional one-line note typed in the share sheet"
}
```

- `kind`: `url | text | image | file`.
- For `image`/`file`, `file` is the sibling filename, e.g. `20260907T130522Z-K7Q2MX.jpg`. Images are re-encoded JPEG ≤ 2000px on the long edge.
- `from_app` is best effort (not always available to extensions).

## 7. License: `license.json`

The single paid plan is **Carry Pro** (product id `app.carry.pro`, auto-renewing monthly). There is exactly one plan. Do not add tiers.

```json
{ "schema": 1, "product_id": "app.carry.pro", "jws": "<StoreKit 2 signed transaction, compact JWS>", "updated_at": "..." }
```

- The iOS app writes the latest verified `Transaction` JWS (`transaction.jwsRepresentation`) whenever entitlement changes and at least once a day while active.
- The Mac verifies the JWS offline: `x5c` chain up to Apple Root CA G3, ES256 signature, `productId == app.carry.pro`, `expiresDate` in the future (with a 3-day grace).
- What Pro unlocks, and only this: **post-processing of media on the Mac**. Screenshot and photo OCR (Vision), voice memo and inbox audio transcription (Whisper). Everything else is free and open source.
- Developer override for testing on the Mac: `CARRY_PRO=1`.

## 8. Heartbeat: `heartbeat/<mac-host>.json` (Mac → phone)

```json
{
  "host": "Tao-MacBook-Pro",
  "carry_version": "0.1.0",
  "last_sync_at": "2026-09-07T21:30:00+08:00",
  "last_digest_date": "2026-09-07",
  "counts": { "health": 1234, "location": 12, "inbox": 3, "photos": 40, "notes": 2 },
  "pro": true,
  "sources_applied_at": "2026-09-07T21:00:00+08:00"
}
```

The phone shows this on its main screen as "Your Mac read this 12 minutes ago". If there is no heartbeat, the phone says so plainly and tells the user to install the CLI.

## 9. What the Mac produces (for agents)

```
~/.carry/
  config.toml                   # local settings (paths, schedule)
  carry.db                      # SQLite + FTS5, the one store
  context/
    README.md                   # tells an agent what is here and how to read it
    2026-09-07.md               # the daily digest, the product
    latest.md                   # symlink to today
    week.md                     # rolling 7-day summary
```

Interfaces, in order of importance: files (any agent can `cat`), `carry mcp` (stdio MCP: Claude Code, Codex, Cursor), `carry` CLI (`today`, `search`, `recent`, `status`).
