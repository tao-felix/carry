"""Reminders from the app-group stores (one SQLite per account)."""

from __future__ import annotations

import glob
from datetime import datetime
from pathlib import Path

from carry.util import apple_to_dt, dt_to_apple, has_table, open_ro, stable_id, table_columns

STORES = str(Path.home() / "Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/Data-*.sqlite")


def _files() -> list[Path]:
    return [Path(f) for f in sorted(glob.glob(STORES))]


def available() -> tuple[bool, str]:
    files = _files()
    if not files:
        return False, "No Reminders stores visible. Grant Full Disk Access."
    total = 0
    try:
        for f in files:
            con = open_ro(f)
            total += con.execute("select count(*) from ZREMCDREMINDER where ZMARKEDFORDELETION=0").fetchone()[0]
            con.close()
        return True, f"{total:,} reminders"
    except Exception as e:  # noqa: BLE001
        return False, f"Cannot read ({e}). Grant Full Disk Access."


def collect(store, cfg, backfill_start: datetime) -> int:
    since = dt_to_apple(backfill_start)
    new = 0
    for f in _files():
        con = open_ro(f)
        cols = table_columns(con, "ZREMCDREMINDER")
        lists = {}
        if has_table(con, "ZREMCDBASELIST") and "ZNAME" in table_columns(con, "ZREMCDBASELIST"):
            lists = {r["Z_PK"]: r["ZNAME"] for r in con.execute("select Z_PK, ZNAME from ZREMCDBASELIST")}
        notes_col = "ZNOTES" if "ZNOTES" in cols else "null"
        rows = con.execute(
            f"""select Z_PK, ZTITLE, ZDUEDATE, ZCOMPLETED, ZCOMPLETIONDATE, ZCREATIONDATE, ZLASTMODIFIEDDATE, ZLIST,
                      {notes_col} as notes, ZFLAGGED
               from ZREMCDREMINDER where ZMARKEDFORDELETION=0 and ZTITLE is not null
                 and (ZLASTMODIFIEDDATE > ? or ZDUEDATE > ? or ZCOMPLETED = 0)""",
            (since, since),
        ).fetchall()
        for r in rows:
            due = apple_to_dt(r["ZDUEDATE"])
            done = apple_to_dt(r["ZCOMPLETIONDATE"]) if r["ZCOMPLETED"] else None
            created = apple_to_dt(r["ZCREATIONDATE"])
            ts = done or due or created
            if not ts:
                continue
            meta = {"list": lists.get(r["ZLIST"], ""), "completed": bool(r["ZCOMPLETED"]),
                    "due": due.isoformat(timespec="seconds") if due else None,
                    "completed_at": done.isoformat(timespec="seconds") if done else None,
                    "flagged": bool(r["ZFLAGGED"]), "created": created.isoformat(timespec="seconds") if created else None}
            if store.upsert(id=stable_id("rem", f.name, r["Z_PK"]), source="reminders", kind="reminder", ts=ts,
                            title=r["ZTITLE"].strip(), text=(r["notes"] or "").strip() or None, meta=meta):
                new += 1
        con.close()
    store.set_cursor("reminders", None, new)
    return new
