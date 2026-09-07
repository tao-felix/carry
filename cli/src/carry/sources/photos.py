"""Photos and screenshots from the iCloud Photos library (Photos.sqlite, read-only, never copied)."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from carry.util import apple_to_dt, dt_to_apple, open_ro, stable_id

LIBRARY = Path.home() / "Pictures/Photos Library.photoslibrary"
DB = LIBRARY / "database/Photos.sqlite"
SCREENSHOT_SUBTYPE = 10


def available() -> tuple[bool, str]:
    if not DB.exists():
        return False, "No Photos library at ~/Pictures"
    try:
        con = open_ro(DB)
        n = con.execute("select count(*) from ZASSET where ZTRASHEDSTATE=0").fetchone()[0]
        con.close()
        return True, f"{n:,} assets"
    except Exception as e:  # noqa: BLE001
        return False, f"Cannot read Photos.sqlite ({e}). Grant Full Disk Access."


def image_path(uuid: str, directory: str, filename: str) -> str | None:
    """Prefer the medium derivative (JPEG, always readable); fall back to the original."""
    deriv_dir = LIBRARY / "resources/derivatives" / uuid[0]
    if deriv_dir.exists():
        for cand in sorted(deriv_dir.glob(f"{uuid}_1_105_c.*")) + sorted(deriv_dir.glob(f"{uuid}_1_101_o.*")):
            return str(cand)
    orig = LIBRARY / "originals" / directory / filename
    return str(orig) if orig.exists() else None


def collect(store, cfg, backfill_start: datetime, enabled: dict[str, bool] | None = None) -> int:
    enabled = enabled or {"photos": True, "screenshots": True}
    con = open_ro(DB)
    cursor = store.get_cursor("photos")
    if cursor:
        where, arg = "a.ZADDEDDATE > ?", float(cursor)
    else:
        where, arg = "a.ZDATECREATED > ?", dt_to_apple(backfill_start)
    rows = con.execute(
        f"""select a.ZUUID, a.ZFILENAME, a.ZDIRECTORY, a.ZDATECREATED, a.ZADDEDDATE, a.ZKIND, a.ZKINDSUBTYPE,
                  a.ZLATITUDE, a.ZLONGITUDE, a.ZFAVORITE, aa.ZORIGINALFILENAME, d.ZLONGDESCRIPTION
           from ZASSET a
           left join ZADDITIONALASSETATTRIBUTES aa on aa.ZASSET = a.Z_PK
           left join ZASSETDESCRIPTION d on d.ZASSETATTRIBUTES = aa.Z_PK
           where a.ZTRASHEDSTATE=0 and a.ZHIDDEN=0 and {where}
           order by a.ZADDEDDATE""",
        (arg,),
    ).fetchall()
    new = 0
    max_added = float(cursor) if cursor else 0.0
    for r in rows:
        is_shot = r["ZKINDSUBTYPE"] == SCREENSHOT_SUBTYPE
        source = "screenshots" if is_shot else "photos"
        if not enabled.get(source, True):
            max_added = max(max_added, r["ZADDEDDATE"] or 0)
            continue
        ts = apple_to_dt(r["ZDATECREATED"])
        if not ts:
            continue
        kind = "screenshot" if is_shot else ("video" if r["ZKIND"] == 1 else "photo")
        lat, lon = r["ZLATITUDE"], r["ZLONGITUDE"]
        meta = {
            "uuid": r["ZUUID"],
            "original_filename": r["ZORIGINALFILENAME"],
            "favorite": bool(r["ZFAVORITE"]),
        }
        if lat is not None and lon is not None and lat > -180 and lon > -180:
            meta["lat"], meta["lon"] = round(lat, 5), round(lon, 5)
        caption = (r["ZLONGDESCRIPTION"] or "").strip() or None
        path = image_path(r["ZUUID"], r["ZDIRECTORY"] or "", r["ZFILENAME"] or "") if kind != "video" else None
        if store.upsert(id=stable_id("photo", r["ZUUID"]), source=source, kind=kind, ts=ts,
                        title=caption or r["ZORIGINALFILENAME"], text=caption, meta=meta, path=path):
            new += 1
        max_added = max(max_added, r["ZADDEDDATE"] or 0)
    con.close()
    store.set_cursor("photos", str(max_added) if max_added else cursor, new)
    return new
