"""Calendar events from the shared Calendar.sqlitedb. Uses the occurrence cache so repeating events show up."""

from __future__ import annotations

from datetime import datetime, timedelta
from pathlib import Path

from carry.util import apple_to_dt, dt_to_apple, has_table, open_ro, stable_id, table_columns

DB = Path.home() / "Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb"
LEGACY = Path.home() / "Library/Calendars/Calendar.sqlitedb"
LOOKAHEAD_DAYS = 14


def _db() -> Path:
    return DB if DB.exists() else LEGACY


def available() -> tuple[bool, str]:
    p = _db()
    if not p.exists():
        return False, "No Calendar database"
    try:
        con = open_ro(p)
        n = con.execute("select count(*) from CalendarItem").fetchone()[0]
        con.close()
        return True, f"{n:,} items"
    except Exception as e:  # noqa: BLE001
        return False, f"Cannot read ({e})"


def collect(store, cfg, backfill_start: datetime) -> int:
    con = open_ro(_db())
    cals = {r["ROWID"]: r["title"] for r in con.execute("select ROWID, title from Calendar")}
    start = dt_to_apple(backfill_start)
    end = dt_to_apple(datetime.now(backfill_start.tzinfo) + timedelta(days=LOOKAHEAD_DAYS))
    ci_cols = table_columns(con, "CalendarItem")
    loc = "ci.location_id" if "location_id" in ci_cols else "null"
    new = 0
    if has_table(con, "OccurrenceCache"):
        rows = con.execute(
            f"""select oc.occurrence_date as s, oc.occurrence_end_date as e, ci.ROWID as id, ci.summary, ci.all_day,
                      ci.calendar_id, ci.description, ci.status
               from OccurrenceCache oc join CalendarItem ci on ci.ROWID = oc.event_id
               where oc.occurrence_date >= ? and oc.occurrence_date < ? order by oc.occurrence_date""",
            (start, end),
        ).fetchall()
    else:
        rows = con.execute(
            """select ci.start_date as s, ci.end_date as e, ci.ROWID as id, ci.summary, ci.all_day, ci.calendar_id,
                      ci.description, ci.status
               from CalendarItem ci where ci.start_date >= ? and ci.start_date < ? order by ci.start_date""",
            (start, end),
        ).fetchall()
    for r in rows:
        ts = apple_to_dt(r["s"])
        if not ts or not r["summary"]:
            continue
        if r["status"] == 3:  # cancelled
            continue
        meta = {"calendar": cals.get(r["calendar_id"], ""), "all_day": bool(r["all_day"]),
                "notes": (r["description"] or "").strip()[:500] or None}
        if store.upsert(id=stable_id("cal", r["id"], r["s"]), source="calendar", kind="event", ts=ts,
                        ts_end=apple_to_dt(r["e"]), title=r["summary"].strip(), text=meta["notes"], meta=meta):
            new += 1
    con.close()
    store.set_cursor("calendar", None, new)
    return new
