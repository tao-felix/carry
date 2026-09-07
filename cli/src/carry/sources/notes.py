"""Apple Notes (NoteStore.sqlite). Title and snippet come straight from the table; the body is decoded
from the gzip+protobuf blob, falling back to the snippet when a note is locked or the format changes."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from carry.util import apple_to_dt, decode_note_body, dt_to_apple, open_ro, stable_id, table_columns

DB = Path.home() / "Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"


def available() -> tuple[bool, str]:
    if not DB.exists():
        return False, "No Notes database"
    try:
        con = open_ro(DB)
        n = con.execute("select count(*) from ZICCLOUDSYNCINGOBJECT where ZTITLE1 is not null and ZMARKEDFORDELETION=0").fetchone()[0]
        con.close()
        return True, f"{n:,} notes"
    except Exception as e:  # noqa: BLE001
        return False, f"Cannot read ({e}). Grant Full Disk Access."


def collect(store, cfg, backfill_start: datetime) -> int:
    con = open_ro(DB)
    cols = table_columns(con, "ZICCLOUDSYNCINGOBJECT")
    created_col = "ZCREATIONDATE1" if "ZCREATIONDATE1" in cols else ("ZCREATIONDATE3" if "ZCREATIONDATE3" in cols else "ZMODIFICATIONDATE1")
    locked_col = "n.ZISPASSWORDPROTECTED" if "ZISPASSWORDPROTECTED" in cols else "0"
    cursor = store.get_cursor("notes")
    since = float(cursor) if cursor else dt_to_apple(backfill_start)
    rows = con.execute(
        f"""select n.Z_PK, n.ZIDENTIFIER, n.ZTITLE1 as title, n.ZSNIPPET as snippet, n.ZMODIFICATIONDATE1 as modified,
                  n.{created_col} as created, {locked_col} as locked, d.ZDATA as data, f.ZTITLE2 as folder
           from ZICCLOUDSYNCINGOBJECT n
           left join ZICNOTEDATA d on d.ZNOTE = n.Z_PK
           left join ZICCLOUDSYNCINGOBJECT f on f.Z_PK = n.ZFOLDER
           where n.ZTITLE1 is not null and n.ZMARKEDFORDELETION=0 and n.ZMODIFICATIONDATE1 > ?
           order by n.ZMODIFICATIONDATE1""",
        (since,),
    ).fetchall()
    new = 0
    last = since
    for r in rows:
        ts = apple_to_dt(r["modified"])
        if not ts:
            continue
        body = None if r["locked"] else decode_note_body(r["data"])
        text = body or (r["snippet"] or "").strip() or None
        meta = {"folder": r["folder"], "created": (apple_to_dt(r["created"]) or ts).isoformat(timespec="seconds"),
                "locked": bool(r["locked"]), "identifier": r["ZIDENTIFIER"]}
        if store.upsert(id=stable_id("note", r["ZIDENTIFIER"] or r["Z_PK"]), source="notes", kind="note", ts=ts,
                        title=r["title"].strip(), text=text, meta=meta, keep_processed=False):
            new += 1
        last = max(last, r["modified"] or 0)
    con.close()
    store.set_cursor("notes", str(last), new)
    return new
