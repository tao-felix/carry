# Carry

**Everything your phone knows, on your agent's desk.**

Desktop agents (Claude Code, Codex, Cursor) can read almost everything on your computer, but nothing on your phone. Carry fixes that with three small parts and no server:

1. **`carry`**, a Mac daemon and CLI. It reads what iCloud already synced to your Mac (Photos and screenshots, Voice Memos, Notes, Messages, Calendar, Reminders, Safari, Screen Time) plus what the Carry iOS app captured, builds one local SQLite store, and writes a daily digest to `~/.carry/context/`. It also speaks MCP.
2. **Carry for iOS**, a thin app. It captures the three things iCloud does not carry to your Mac: Health, Location, and a Share-sheet inbox ("send this to my agent"). It is also the single control surface for which sources the engine covers.
3. **The site** (https://carry-site.vercel.app for now), a page that explains all of this and links to the two above.

Transport is your own iCloud Drive. There is no Carry server. Your Mac reads it, your agents read your Mac.

One paid plan, **Carry Pro**, turns pictures and audio into text your agent can read (OCR, transcription). Everything else is free and MIT.

## Layout

```
cli/    Python package, the `carry` command (uv)
ios/    Xcode project (xcodegen), Carry app + CarryShare extension
web/    Next.js landing page (Vercel)
docs/   DATA-CONTRACT.md (the interface all three obey), DESIGN.md
```

## Quick start (Mac)

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
