"""App usage from knowledgeC.db (/app/usage). This Mac always; the iPhone too when Screen Time's
"Share Across Devices" is on (then rows carry a device id)."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

from carry.apps import app_name
from carry.util import LOCAL_TZ, apple_to_dt, dt_to_apple, open_ro, stable_id

DB = Path.home() / "Library/Application Support/Knowledge/knowledgeC.db"


def available() -> tuple[bool, str]:
    if not DB.exists():
        return False, "No knowledgeC.db"
    try:
        con = open_ro(DB)
        n = con.execute("select count(*) from ZOBJECT where ZSTREAMNAME='/app/usage'").fetchone()[0]
        con.close()
        return True, f"{n:,} usage rows"
    except Exception as e:  # noqa: BLE001
        return False, f"Cannot read ({e}). Grant Full Disk Access."




def collect(store, cfg, backfill_start: datetime) -> int:
    con = open_ro(DB)
    # Recompute the last two days every run; older days are stable.
    start = max(backfill_start, datetime.now(LOCAL_TZ).replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=1))
    if not store.get_cursor("screen_time"):
        start = backfill_start
    rows = con.execute(
        """select o.ZSTARTDATE, o.ZENDDATE, o.ZVALUESTRING as bundle, s.ZDEVICEID as device
           from ZOBJECT o left join ZSOURCE s on o.ZSOURCE = s.Z_PK
           where o.ZSTREAMNAME='/app/usage' and o.ZSTARTDATE >= ? and o.ZENDDATE > o.ZSTARTDATE""",
        (dt_to_apple(start),),
    ).fetchall()
    minutes: dict[tuple[str, str, str], float] = defaultdict(float)
    for r in rows:
        s = apple_to_dt(r["ZSTARTDATE"])
        if not s or not r["bundle"]:
            continue
        device = "iphone" if r["device"] else "mac"
        minutes[(s.strftime("%Y-%m-%d"), r["bundle"], device)] += (r["ZENDDATE"] - r["ZSTARTDATE"]) / 60
    new = 0
    for (day, bundle, device), mins in minutes.items():
        if mins < 1:
            continue
        ts = datetime.strptime(day, "%Y-%m-%d").replace(tzinfo=LOCAL_TZ)
        if store.upsert(id=stable_id("usage", day, bundle, device), source="screen_time", kind="app_usage", ts=ts,
                        title=app_name(bundle), meta={"bundle": bundle, "minutes": round(mins), "device": device}, device=device):
            new += 1
    con.close()
    store.set_cursor("screen_time", "1", new)
    return new
