"""Safari history (iCloud-synced across devices). Off by default."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit

from carry.util import apple_to_dt, dt_to_apple, open_ro, stable_id

DB = Path.home() / "Library/Safari/History.db"


def available() -> tuple[bool, str]:
    if not DB.exists():
        return False, "No Safari history"
    try:
        con = open_ro(DB)
        n = con.execute("select count(*) from history_visits").fetchone()[0]
        con.close()
        return True, f"{n:,} visits"
    except Exception as e:  # noqa: BLE001
        return False, f"Cannot read ({e}). Grant Full Disk Access."


def collect(store, cfg, backfill_start: datetime) -> int:
    con = open_ro(DB)
    cursor = store.get_cursor("safari")
    since = float(cursor) if cursor else dt_to_apple(backfill_start)
    rows = con.execute(
        """select v.id, v.visit_time, v.title, i.url from history_visits v join history_items i on i.id = v.history_item
           where v.visit_time > ? order by v.visit_time""",
        (since,),
    ).fetchall()
    new = 0
    last = since
    for r in rows:
        ts = apple_to_dt(r["visit_time"])
        if not ts or not r["url"]:
            continue
        host = urlsplit(r["url"]).netloc
        if store.upsert(id=stable_id("safari", r["id"]), source="safari", kind="visit", ts=ts,
                        title=(r["title"] or host or r["url"]).strip(), text=r["url"], meta={"host": host}):
            new += 1
        last = max(last, r["visit_time"] or 0)
    con.close()
    store.set_cursor("safari", str(last), new)
    return new
