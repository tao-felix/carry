# Carry

**Everything your phone knows, on your agent's desk.**

Desktop agents (Claude Code, Codex, Cursor) can read almost everything on your computer, but nothing on your phone. Carry fixes that with no server and no terminal:

1. **Carry for Mac** (`mac/`), a menu-bar app. It reads what iCloud already synced to your Mac (Photos and screenshots, Voice Memos, Notes, Messages, Calendar, Reminders, Safari, Screen Time) plus what the Carry iPhone app captured, keeps one local SQLite store, writes a daily digest to `~/.carry/context/`, and serves MCP on localhost while it runs. One switch in System Settings (Full Disk Access) unlocks the protected sources; the app takes you to that switch.
2. **Carry for iPhone** (`ios/`), a thin app. It captures the three things iCloud does not carry to your Mac: Health, Location, and a Share-sheet inbox ("send this to my agent"). It is also the single control surface for which sources the engine covers.
3. **`carry`** (`cli/`), the same engine as a Python CLI for developers and headless Macs. Reference implementation; produces the same files.
4. **The site** (https://carry-site.vercel.app for now).

Transport is your own iCloud Drive. There is no Carry server. Your Mac reads it, your agents read your Mac.

One paid plan, **Carry Pro**, turns pictures and audio into text your agent can read (OCR, transcription). Everything else is free and MIT.

## Layout

```
mac/    Xcode project (xcodegen), Carry for Mac: menu bar app with the engine, FDA flow, scheduler, localhost MCP
ios/    Xcode project (xcodegen), Carry app + CarryShare extension
cli/    Python package, the `carry` command (uv), reference implementation of the engine
web/    Next.js landing page (Vercel)
docs/   DATA-CONTRACT.md (the interface all parts obey), ENGINE.md (the engine spec), DESIGN.md
scripts/ e2e-sim.sh (iPhone simulator ↔ Mac end-to-end)
```

## Quick start (Mac, developer path)

```bash
uv tool install ./cli        # or: uv tool install carry-context
carry init                   # detects sources, checks Full Disk Access, installs the 15-minute sync
carry today                  # prints today's digest
carry mcp                    # stdio MCP server for Claude Code / Codex / Cursor
```

Then point your agent at `~/.carry/context/` (the `carry init` output prints the exact snippet for CLAUDE.md / AGENTS.md).

```bash
claude mcp add carry -- carry mcp          # Claude Code
```

```toml
# Codex: ~/.codex/config.toml
[mcp_servers.carry]
command = "carry"
args = ["mcp"]
default_tools_approval_mode = "auto"       # interactive Codex still asks once; `codex exec` needs --dangerously-bypass-approvals-and-sandbox as of 0.146
```

## Status

v0.1, September 2026. Mac + iPhone first. Android is next.
