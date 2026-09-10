---
name: carry
description: Read the owner's phone context that Carry keeps on this Mac — photos and screenshots (with OCR text on Pro), voice memos (with transcripts), notes, calendar, reminders, health, places, screen time and anything shared from the phone. Use it whenever a request touches the owner's day ("what did I photograph / record / share today", "where was I", "that screenshot with the price list", "what's on my calendar"), or before summarising or planning anything for them. Works from files alone; the carry CLI and MCP server add search.
license: MIT
metadata:
  author: Carry (https://carry-site.vercel.app)
  version: "0.1"
---

# Carry: the owner's phone, on your desk

Carry is a personal context engine. The owner's iPhone writes what it knows to their own iCloud; Carry for Mac reads it and keeps a local, plain-text copy on this Mac. **There is no Carry server.** Everything below is the owner's private data: read it to help them, never send it anywhere they did not ask for.

## Where it lives (files first, no setup)

```
~/.carry/context/
  latest.md        → today (symlink). Read this first.
  YYYY-MM-DD.md    → one digest per day, rewritten every 15 minutes while the Mac is awake
  week.md          → the last 7 days as a table
  README.md        → the owner's own note on what this folder is
```

A digest has one section per source in this order: Inbox (shared from the phone), Health, Places, Screenshots, Photos, Voice memos, Notes, Messages, Calendar (today + next 7 days), Reminders, Safari, Screen time. Timestamps are the owner's local time.

How to read it:
- `off (you chose)` — the owner switched that source off on their phone. Say so if asked; do not look for that data elsewhere.
- `waiting for text: photos 228` (in `carry status`) or a screenshot with no text — Pro is off, so images and audio have no OCR/transcript yet. Say "Carry has the file but no text for it".
- `Nothing today: …` — the source is on, nothing arrived. Not an error.
- No digest file at all — Carry has not synced on this Mac. Tell the owner to open **Carry for Mac** (menu bar) or run `carry sync`.

## Three levels of access

| Level | When | How |
|---|---|---|
| **File** | Any agent, no tools | Read `~/.carry/context/latest.md`; older days by date |
| **CLI** | You can run shell commands | `carry today` · `carry digest 2026-09-08` · `carry search "<query>" [--source screenshots] [--since 2026-09-01]` · `carry recent voice_memos` · `carry status` |
| **MCP** | Claude Code / Codex / Cursor with the `carry` server | tools `digest(date)`, `search(query, source?, since?, limit?)`, `recent(source, limit?)`, `item(id)`, `sources()` |

Source names: `photos screenshots voice_memos notes messages calendar reminders safari screen_time health location inbox`.
Search is full-text trigram, so Chinese and partial words work. `item(id)` returns a long transcript or OCR text in full; the digest only shows the first lines.

MCP setup, if the owner asks: `claude mcp add --transport http carry http://127.0.0.1:47850/mcp` (Carry for Mac serves it while running) or `claude mcp add carry -- carry mcp` (CLI, stdio).

## Playbook

1. **Start of a session that touches the owner's day** → read `latest.md` once. Do not re-read every turn; it changes every 15 minutes at most.
2. **"What did I photograph / screenshot / record today?"** → the Photos / Screenshots / Voice memos sections of today's digest. For text inside a screenshot use `search`, then `item` for the full OCR.
3. **"Find that screenshot / memo about X"** → `carry search "X" --source screenshots` (or `voice_memos`). Give the timestamp and the matching text, then offer the full item.
4. **"Where was I this afternoon?" / "how did I sleep?"** → Places / Health sections. These come from the Carry iPhone app; if the section says nothing, the owner may not have granted Health or Location on the phone. Say that, do not guess.
5. **"What did I send you from my phone?"** → Inbox. Items shared through the iOS share sheet land here with the page title and URL; treat a shared link as something the owner wants read or acted on.
6. **Planning, summaries, "what should I do today"** → combine Calendar (today + next 7 days), Reminders (overdue first) and Inbox before anything else.
7. **Older than today** → `carry digest YYYY-MM-DD` or `search --since`. Do not scan the folder day by day when a search would do.

## Rules

- Quote the owner's data back to them; do not paste it into external services, files outside this Mac, or messages to other people unless they explicitly ask.
- Respect switched-off sources. Never try to read Messages, Safari or Health through other paths when Carry shows them off.
- When you are unsure whether Carry is current, run `carry status` (or the `sources` tool) and report the last sync time instead of assuming.
- Carry never modifies the phone. There is nothing to "write back"; changes to what is collected are made by the owner in the iPhone app.
