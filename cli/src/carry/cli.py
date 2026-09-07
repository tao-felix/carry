"""The `carry` command."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import traceback
from datetime import datetime, timedelta

import typer
from rich.console import Console
from rich.table import Table
from rich.text import Text

from carry import __version__, container, digest as digest_mod, launchd, pro as pro_mod, processing
from carry.config import (CARRY_HOME, CONFIG_PATH, CONTAINER_DIR, CONTEXT_DIR, DB_PATH, SOURCES, effective_processing,
                          effective_sources, load_config, policy_updated_at, save_config)
from carry.sources import READERS
from carry.store import Store
from carry.util import LOCAL_TZ, now

app = typer.Typer(add_completion=False, no_args_is_help=True, rich_markup_mode="rich",
                  help="Everything your phone knows, on your agent's desk.")
con = Console(highlight=False)
MOSS, TANGERINE, DIM = "#2E5E4E", "#E8562B", "grey50"

APP_READERS = {"health": container.collect_health, "location": container.collect_location, "inbox": container.collect_inbox}


def _badge(source: str) -> Text:
    s = SOURCES[source]
    return Text("via iCloud", style=MOSS) if s.channel == "icloud" else Text("via Carry app", style=TANGERINE)


def _fda_ok() -> bool:
    from carry.sources import messages

    ok, _ = messages.available()
    return ok


def _agent_binary() -> str:
    return os.path.realpath(sys.executable)


def _fda_hint(for_agent: bool) -> list[Text]:
    who = "the background sync" if for_agent else "this terminal"
    return [
        Text(f"Full Disk Access is off for {who}.", style="bold yellow"),
        Text("  System Settings → Privacy & Security → Full Disk Access → + → add:", style=DIM),
        Text(f"    {_agent_binary()}", style=DIM) if for_agent else Text("    your terminal app (Terminal, iTerm, Claude, Cursor…)", style=DIM),
        Text("  Without it, Notes, Voice Memos, Messages, Calendar, Reminders, Safari and Screen Time cannot be read there.", style=DIM),
    ]


def _agent_snippet() -> str:
    return (
        "My phone context lives in ~/.carry/context/ (written by Carry). Read latest.md at the start of a session when my "
        "request touches my day, my health, places, notes, or things I shared from my phone. "
        "Use `carry search \"<query>\"` for anything older."
    )


@app.callback(invoke_without_command=True)
def _root(version: bool = typer.Option(False, "--version", "-V", help="Print version and exit.")):
    if version:
        con.print(f"carry {__version__}")
        raise typer.Exit()


@app.command()
def init(yes: bool = typer.Option(False, "--yes", "-y", help="Install the background sync without asking."),
         no_agent: bool = typer.Option(False, "--no-agent", help="Do not install the background sync.")):
    """Detect what this Mac can read, write the config, install the 15-minute sync, print the agent snippets."""
    cfg = load_config()
    CARRY_HOME.mkdir(parents=True, exist_ok=True)
    con.print(Text("Carry", style="bold") + Text(f"  {__version__}", style=DIM))
    con.print(Text("Read: the sources you switch on. Goes to: your iCloud Drive, then this Mac. Seen by: the agents you point at ~/.carry/context/. No Carry server.\n", style=DIM))

    fda = _fda_ok()
    if not fda:
        for line in _fda_hint(for_agent=False):
            con.print(line)
        con.print()

    enabled, decided_by = effective_sources(cfg)
    t = Table(show_header=True, header_style="bold", box=None, pad_edge=False)
    t.add_column("source"), t.add_column("channel"), t.add_column("on"), t.add_column("found on this Mac")
    for name, s in SOURCES.items():
        if s.channel == "icloud":
            ok, note = READERS[name].available()
        else:
            ok = container.present()
            note = f"Carry folder {'found' if ok else 'not found yet (install the iPhone app)'}"
        state = Text("on", style=MOSS) if enabled[name] else Text("off", style=DIM)
        t.add_row(Text(s.label, style="" if enabled[name] else DIM), _badge(name), state,
                  Text(note, style="" if ok else "yellow"))
    con.print(t)
    con.print(Text(f"\nSources decided on the {decided_by}" + (" (the iPhone app's sources.json wins)" if decided_by == "phone" else " (config.toml; the iPhone app takes over once installed)"), style=DIM))

    save_config(cfg)
    con.print(Text(f"→ {CONFIG_PATH}", style=DIM))

    if not no_agent and (yes or typer.confirm("Install the background sync (every 15 minutes while awake)?", default=True)):
        p = launchd.install(cfg["carry"]["schedule_minutes"])
        con.print(Text(f"→ {p}  (every {cfg['carry']['schedule_minutes']} min)", style=DIM))
        con.print(Text("\nOne more grant, once: the background sync runs as its own program, so macOS asks again.", style="bold"))
        for line in _fda_hint(for_agent=True)[1:3]:
            con.print(line)
        con.print(Text("  Then: carry agent restart   (or wait for the next 15-minute run)", style=DIM))
        subprocess.run(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"], capture_output=True)

    con.print("\n[bold]Run the first sync[/bold]  `carry sync`  then  `carry today`")
    con.print("\n[bold]Point your agent at it[/bold]")
    con.print(Text("Claude Code:  claude mcp add carry -- carry mcp", style=DIM))
    con.print(Text('Codex:        ~/.codex/config.toml → [mcp_servers.carry] command = "carry"  args = ["mcp"]  default_tools_approval_mode = "auto"', style=DIM))
    con.print(Text("CLAUDE.md / AGENTS.md paragraph:", style=DIM))
    con.print(Text("  " + _agent_snippet(), style=DIM))


@app.command()
def sync(quiet: bool = typer.Option(False, "--quiet", "-q"),
         no_digest: bool = typer.Option(False, "--no-digest"),
         no_process: bool = typer.Option(False, "--no-process", help="Skip OCR / transcription this run."),
         since: str = typer.Option(None, "--since", help="Backfill start YYYY-MM-DD for a first run.")):
    """Read every enabled source incrementally, process media (Pro), rewrite the digests, write the heartbeat."""
    cfg = load_config()
    store = Store()
    log = (lambda *a, **k: None) if quiet else con.print
    enabled, decided_by = effective_sources(cfg)
    backfill = datetime.strptime(since, "%Y-%m-%d").replace(tzinfo=LOCAL_TZ) if since else now() - timedelta(days=cfg["carry"]["backfill_days"])
    if since:
        for name in list(READERS) + list(APP_READERS):
            store.set_cursor(name, None, 0)
            store.con.execute("update sync_state set cursor=NULL where source=?", (name,))
    totals: dict[str, int] = {}
    ran_photos = False
    for name, s in SOURCES.items():
        if not enabled[name]:
            continue
        try:
            if s.channel == "icloud":
                if name in ("photos", "screenshots"):
                    if ran_photos:
                        continue
                    ran_photos = True
                    ok, note = READERS[name].available()
                    n = READERS[name].collect(store, cfg, backfill, enabled) if ok else 0
                    totals["photos/screenshots"] = n
                else:
                    ok, note = READERS[name].available()
                    n = READERS[name].collect(store, cfg, backfill) if ok else 0
                    totals[name] = n
                if not ok:
                    store.set_cursor(name, None, 0, error=note)
                    log(Text(f"  skip {name}: {note}", style="yellow"))
            else:
                totals[name] = APP_READERS[name](store, cfg, backfill) if container.present() else 0
            store.commit()
        except Exception as e:  # noqa: BLE001
            store.set_cursor(name, None, 0, error=str(e))
            log(Text(f"  error {name}: {e}", style="red"))
            if os.environ.get("CARRY_DEBUG"):
                traceback.print_exc()
    log("synced  " + "  ".join(f"{k} +{v}" for k, v in totals.items()))

    pro = pro_mod.status()
    proc = effective_processing(cfg)
    if not no_process:
        done = processing.run(store, proc, pro.active, log=log)
        if pro.active and any(done.values()):
            log("processed  " + "  ".join(f"{k} {v}" for k, v in done.items() if v))
        elif not pro.active:
            pend = processing.pending_counts(store)
            waiting = sum(pend.values())
            if waiting:
                log(Text(f"{waiting} pictures/recordings are waiting for Pro to become text ({pro.reason})", style=DIM))
    if not no_digest:
        written = digest_mod.write_all(store, enabled, pro.active, decided_by)
        log(Text(f"→ {written[0]}", style=DIM))
    hb = container.write_heartbeat(store, pro.active, policy_updated_at(), now().strftime("%Y-%m-%d"))
    if hb:
        log(Text(f"→ heartbeat {hb.name}", style=DIM))
    store.close()


@app.command()
def today():
    """Print today's digest."""
    _print_digest(now().strftime("%Y-%m-%d"))


@app.command()
def digest(date: str = typer.Argument(..., help="YYYY-MM-DD, or 'yesterday'")):
    """Print one day's digest."""
    if date == "yesterday":
        date = (now() - timedelta(days=1)).strftime("%Y-%m-%d")
    _print_digest(date)


def _print_digest(day: str):
    p = CONTEXT_DIR / f"{day}.md"
    if not p.exists():
        con.print(Text(f"No digest for {day}. Run `carry sync`.", style="yellow"))
        raise typer.Exit(1)
    sys.stdout.write(p.read_text())


@app.command()
def search(query: str, source: str = typer.Option(None, "--source", "-s"), since: str = typer.Option(None, "--since"),
           limit: int = typer.Option(20, "--limit", "-n")):
    """Full-text search across everything Carry has read."""
    store = Store()
    rows = store.search(query, source, since, limit)
    if not rows:
        con.print(Text("nothing found", style=DIM))
    for r in rows:
        meta = json.loads(r["meta"] or "{}")
        head = Text(f"{r['ts'][:16]}  ", style=DIM) + Text(f"{r['source']:12s}", style=MOSS if SOURCES[r['source']].channel == "icloud" else TANGERINE)
        con.print(head + Text(f" {r['title'] or ''}"))
        body = (r["text"] or meta.get("url") or "")
        if body:
            con.print(Text("    " + " ".join(body.split())[:300], style=DIM))
    store.close()


@app.command()
def recent(source: str = typer.Argument(..., help="photos, screenshots, voice_memos, notes, messages, calendar, reminders, safari, screen_time, health, location, inbox"),
           limit: int = typer.Option(20, "--limit", "-n")):
    """Most recent items from one source."""
    if source not in SOURCES:
        con.print(Text(f"unknown source {source}", style="red"))
        raise typer.Exit(1)
    store = Store()
    for r in store.recent(source, limit):
        meta = json.loads(r["meta"] or "{}")
        con.print(Text(f"{r['ts'][:16]}  ", style=DIM) + Text(r["title"] or r["kind"]) + Text(f"  {r['id']}", style=DIM))
        body = r["text"] or ", ".join(f"{k}={v}" for k, v in meta.items() if v not in (None, "", False))
        if body:
            con.print(Text("    " + " ".join(str(body).split())[:240], style=DIM))
    store.close()


@app.command()
def status():
    """Where things stand: sources, counts, last sync, Pro, iPhone heartbeat."""
    cfg = load_config()
    store = Store()
    enabled, decided_by = effective_sources(cfg)
    counts, state = store.counts(), store.sync_state()
    t = Table(box=None, pad_edge=False, header_style="bold")
    for c in ("source", "channel", "on", "items", "last sync", "note"):
        t.add_column(c)
    for name, s in SOURCES.items():
        st = state.get(name if name != "screenshots" else "photos")
        last = st["last_run"][5:16].replace("T", " ") if st and st["last_run"] else "never"
        note = (st["last_error"] or "") if st else ""
        t.add_row(Text(s.label, style="" if enabled[name] else DIM), _badge(name),
                  Text("on", style=MOSS) if enabled[name] else Text("off", style=DIM), str(counts.get(name, 0)), last, Text(note, style="red"))
    con.print(t)
    p = pro_mod.status()
    con.print(Text(f"\nSources decided on the {decided_by}. ", style=DIM) + Text("Pro on" if p.active else "Pro off", style="bold" if p.active else DIM) + Text(f" · {p.reason}", style=DIM))
    m = container.manifest()
    if m:
        d = m.get("device", {})
        con.print(Text(f"iPhone: {d.get('name', '?')} · {d.get('os', '')} · app {m.get('app_version', '?')} · last wrote {m.get('updated_at', '?')[:16]}", style=DIM))
    else:
        con.print(Text(f"iPhone: no Carry folder at {CONTAINER_DIR} yet. Install the app, or set CARRY_CONTAINER.", style=DIM))
    pend = processing.pending_counts(store)
    if sum(pend.values()):
        con.print(Text("waiting for text: " + ", ".join(f"{k} {v}" for k, v in pend.items() if v), style=DIM))
    blocked = [SOURCES[n].label for n, st in state.items() if n in SOURCES and st["last_error"] and "Full Disk Access" in (st["last_error"] or "")]
    if blocked:
        con.print(Text(f"last run could not read: {', '.join(blocked)}", style="yellow"))
        for line in _fda_hint(for_agent=launchd.installed()):
            con.print(line)
    con.print(Text(f"agent: {'installed' if launchd.installed() else 'not installed'} · db {DB_PATH} · context {CONTEXT_DIR}", style=DIM))
    store.close()


@app.command()
def sources(name: str = typer.Argument(None), enable: bool = typer.Option(None, "--on/--off")):
    """List sources, or switch one on/off on this Mac (the iPhone app's choice wins when present)."""
    cfg = load_config()
    if name:
        if name not in SOURCES or enable is None:
            con.print(Text("usage: carry sources <name> --on|--off", style="red"))
            raise typer.Exit(1)
        cfg["sources"][name] = enable
        save_config(cfg)
        _, by = effective_sources(cfg)
        if by == "phone":
            con.print(Text("Saved locally, but the iPhone app's sources.json is present and wins. Change it on the phone.", style="yellow"))
    enabled, by = effective_sources(cfg)
    for n, s in SOURCES.items():
        con.print((Text("on ", style=MOSS) if enabled[n] else Text("off", style=DIM)) + Text(f"  {s.label:12s}", style="" if enabled[n] else DIM) + _badge(n) + Text(f"  {s.reads}", style=DIM))
    con.print(Text(f"decided on the {by}", style=DIM))


@app.command(name="pro")
def pro_cmd():
    """Is the single Pro plan active on this Mac, and what it unlocks."""
    p = pro_mod.status()
    con.print(Text("Pro on" if p.active else "Pro off", style="bold") + Text(f"  {p.reason}", style=DIM))
    if p.expires_at:
        con.print(Text(f"until {p.expires_at} ({p.environment})", style=DIM))
    con.print(Text("Pro turns pictures and audio into text your agent can read: screenshot & photo OCR, voice memo transcription.", style=DIM))
    con.print(Text("Subscribe in the Carry iPhone app; the license syncs here through your iCloud. Everything else is free.", style=DIM))


@app.command()
def mcp():
    """Run the stdio MCP server (for `claude mcp add carry -- carry mcp`)."""
    from carry.mcp_server import run

    run()


@app.command()
def agent(action: str = typer.Argument(..., help="install | uninstall | restart | status")):
    """Manage the background sync LaunchAgent."""
    cfg = load_config()
    if action == "install":
        con.print(Text(f"→ {launchd.install(cfg['carry']['schedule_minutes'])}", style=DIM))
    elif action == "uninstall":
        con.print("removed" if launchd.uninstall() else "not installed")
    elif action == "restart":
        launchd.kickstart()
        con.print("kicked")
    else:
        con.print("installed" if launchd.installed() else "not installed")


@app.command(name="open")
def open_cmd():
    """Open the context folder in Finder."""
    CONTEXT_DIR.mkdir(parents=True, exist_ok=True)
    subprocess.run(["open", str(CONTEXT_DIR)])


if __name__ == "__main__":
    app()
