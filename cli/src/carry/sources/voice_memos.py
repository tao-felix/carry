"""Voice Memos synced by iCloud (CloudRecordings.db + the audio files next to it)."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from carry.util import apple_to_dt, dt_to_apple, open_ro, stable_id, table_columns

DIR = Path.home() / "Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
DB = DIR / "CloudRecordings.db"


def available() -> tuple[bool, str]:
    if not DB.exists():
        return False, "No Voice Memos database"
    try:
        con = open_ro(DB)
        n = con.execute("select count(*) from ZCLOUDRECORDING").fetchone()[0]
        con.close()
        return True, f"{n:,} recordings"
    except Exception as e:  # noqa: BLE001
        return False, f"Cannot read ({e})"


def collect(store, cfg, backfill_start: datetime) -> int:
    con = open_ro(DB)
    cols = table_columns(con, "ZCLOUDRECORDING")
    title_col = "ZENCRYPTEDTITLE" if "ZENCRYPTEDTITLE" in cols else ("ZCUSTOMLABEL" if "ZCUSTOMLABEL" in cols else "ZPATH")
    cursor = store.get_cursor("voice_memos")
    since = float(cursor) if cursor else dt_to_apple(backfill_start)
    rows = con.execute(
        f"select Z_PK, {title_col} as title, ZPATH, ZDURATION, ZDATE from ZCLOUDRECORDING where ZDATE > ? order by ZDATE",
        (since,),
    ).fetchall()
    new = 0
    last = since
    for r in rows:
        ts = apple_to_dt(r["ZDATE"])
        if not ts or not r["ZPATH"]:
            continue
        path = DIR / r["ZPATH"]
        meta = {"duration_s": round(r["ZDURATION"] or 0, 1), "file": r["ZPATH"]}
        if store.upsert(id=stable_id("memo", r["ZPATH"]), source="voice_memos", kind="voice_memo", ts=ts,
                        title=(r["title"] or r["ZPATH"]).strip(), meta=meta, path=str(path) if path.exists() else None):
            new += 1
        last = max(last, r["ZDATE"] or 0)
    con.close()
    store.set_cursor("voice_memos", str(last), new)
    return new
