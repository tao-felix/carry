"""stdio MCP server: `carry mcp`. Claude Code, Codex and Cursor all speak this."""

from __future__ import annotations

import json

from mcp.server.mcpserver import MCPServer

from carry.config import CONTEXT_DIR, SOURCES, effective_sources, load_config
from carry.store import Store
from carry.util import now

server = MCPServer("carry", instructions=(
    "Carry exposes the owner's phone context: photos and screenshots (with OCR text when Pro is on), voice memos "
    "(with transcripts), notes, messages, calendar, reminders, Safari, screen time, plus health, places and a share inbox "
    "captured by the Carry iPhone app. Start with digest('today') for an overview; use search for anything specific."))


def _row(r) -> dict:
    return {"id": r["id"], "source": r["source"], "kind": r["kind"], "ts": r["ts"], "ts_end": r["ts_end"],
            "title": r["title"], "text": r["text"], "meta": json.loads(r["meta"] or "{}")}


@server.tool()
def digest(date: str = "today") -> str:
    """The daily Markdown digest. `date` is YYYY-MM-DD, 'today' or 'yesterday'."""
    if date == "today":
        date = now().strftime("%Y-%m-%d")
    elif date == "yesterday":
        from datetime import timedelta

        date = (now() - timedelta(days=1)).strftime("%Y-%m-%d")
    p = CONTEXT_DIR / f"{date}.md"
    return p.read_text() if p.exists() else f"No digest for {date}. Run `carry sync` on the Mac."


@server.tool()
def search(query: str, source: str | None = None, since: str | None = None, limit: int = 20) -> list[dict]:
    """Full-text search across everything (trigram, so Chinese works). `source` filters to one source name;
    `since` is an ISO date."""
    store = Store()
    try:
        return [_row(r) for r in store.search(query, source, since, limit)]
    finally:
        store.close()


@server.tool()
def recent(source: str, limit: int = 20) -> list[dict]:
    """Most recent items from one source: photos, screenshots, voice_memos, notes, messages, calendar, reminders,
    safari, screen_time, health, location, inbox."""
    store = Store()
    try:
        return [_row(r) for r in store.recent(source, limit)]
    finally:
        store.close()


@server.tool()
def item(id: str) -> dict | None:
    """One item in full (for long transcripts or OCR text)."""
    store = Store()
    try:
        r = store.get(id)
        return _row(r) if r else None
    finally:
        store.close()


@server.tool()
def sources() -> list[dict]:
    """Which sources are switched on, and who decided (phone or mac)."""
    enabled, by = effective_sources(load_config())
    return [{"name": n, "label": s.label, "channel": s.channel, "enabled": enabled[n], "decided_by": by, "reads": s.reads}
            for n, s in SOURCES.items()]


@server.resource("carry://digest/today")
def today_resource() -> str:
    return digest("today")


def run() -> None:
    server.run(transport="stdio")
