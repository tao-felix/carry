"""Small helpers shared by every module: Apple time, ids, read-only SQLite, iCloud placeholders,
and two binary decoders (Messages typedstream, Notes protobuf)."""

from __future__ import annotations

import gzip
import hashlib
import sqlite3
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

APPLE_EPOCH = 978307200  # 2001-01-01T00:00:00Z
LOCAL_TZ = datetime.now().astimezone().tzinfo


def now() -> datetime:
    return datetime.now(LOCAL_TZ)


def apple_to_dt(v) -> datetime | None:
    """Apple Core Data timestamp (seconds, or nanoseconds for Messages) to aware local datetime."""
    if v is None:
        return None
    try:
        v = float(v)
    except (TypeError, ValueError):
        return None
    if v == 0:
        return None
    if v > 1e12:  # Messages stores nanoseconds
        v = v / 1e9
    try:
        return datetime.fromtimestamp(v + APPLE_EPOCH, tz=LOCAL_TZ)
    except (ValueError, OverflowError, OSError):  # Apple uses far-future sentinels for "no date"
        return None


def dt_to_apple(dt: datetime) -> float:
    return dt.timestamp() - APPLE_EPOCH


def parse_iso(s: str) -> datetime | None:
    if not s:
        return None
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=LOCAL_TZ)
    return dt.astimezone(LOCAL_TZ)


def iso(dt: datetime | None) -> str | None:
    return dt.astimezone(LOCAL_TZ).isoformat(timespec="seconds") if dt else None


def day_of(dt: datetime) -> str:
    return dt.astimezone(LOCAL_TZ).strftime("%Y-%m-%d")


def day_bounds(day: str) -> tuple[datetime, datetime]:
    start = datetime.strptime(day, "%Y-%m-%d").replace(tzinfo=LOCAL_TZ)
    return start, start + timedelta(days=1)


def stable_id(*parts) -> str:
    return hashlib.sha1("|".join(str(p) for p in parts).encode()).hexdigest()[:20]


def open_ro(path: Path) -> sqlite3.Connection:
    """Open a live Apple database read-only without copying it (Photos.sqlite can be gigabytes)."""
    if not path.exists():
        raise FileNotFoundError(path)
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=5)
    con.row_factory = sqlite3.Row
    return con


def table_columns(con: sqlite3.Connection, table: str) -> set[str]:
    return {r[1] for r in con.execute(f"pragma table_info('{table}')")}


def has_table(con: sqlite3.Connection, table: str) -> bool:
    return con.execute("select 1 from sqlite_master where name=?", (table,)).fetchone() is not None


def icloud_download(path: Path) -> None:
    """Ask iCloud to materialise placeholders below `path`. Cheap, safe to call every sync."""
    if not path.exists():
        return
    try:
        subprocess.run(["brctl", "download", str(path)], capture_output=True, timeout=20)
    except Exception:
        pass
    for ph in path.rglob(".*.icloud"):
        try:
            subprocess.run(["brctl", "download", str(ph)], capture_output=True, timeout=20)
        except Exception:
            pass


def decode_attributed_body(blob: bytes | None) -> str | None:
    """Extract the plain string from a Messages `attributedBody` typedstream blob."""
    if not blob:
        return None
    i = blob.find(b"NSString")
    if i < 0:
        return None
    i += len(b"NSString") + 5  # skips the class-info bytes ending in '+'
    if i >= len(blob):
        return None
    b = blob[i]
    if b == 0x81:
        n = int.from_bytes(blob[i + 1 : i + 3], "little")
        i += 3
    elif b == 0x82:
        n = int.from_bytes(blob[i + 1 : i + 5], "little")
        i += 5
    else:
        n = b
        i += 1
    return blob[i : i + n].decode("utf-8", errors="replace") or None


def _varint(buf: bytes, i: int) -> tuple[int, int]:
    shift = 0
    out = 0
    while i < len(buf):
        b = buf[i]
        i += 1
        out |= (b & 0x7F) << shift
        if not b & 0x80:
            break
        shift += 7
    return out, i


def pb_fields(buf: bytes) -> list[tuple[int, int, object]]:
    """Minimal protobuf walker: returns (field_number, wire_type, value)."""
    i = 0
    out = []
    while i < len(buf):
        key, i = _varint(buf, i)
        fn, wt = key >> 3, key & 7
        if wt == 0:
            v, i = _varint(buf, i)
        elif wt == 1:
            v = buf[i : i + 8]
            i += 8
        elif wt == 2:
            n, i = _varint(buf, i)
            v = buf[i : i + n]
            i += n
        elif wt == 5:
            v = buf[i : i + 4]
            i += 4
        else:
            break
        out.append((fn, wt, v))
    return out


def decode_note_body(zdata: bytes | None) -> str | None:
    """Apple Notes body: gzip → protobuf Document(2).Note(3).note_text(2)."""
    if not zdata:
        return None
    try:
        raw = gzip.decompress(zdata)
    except Exception:
        return None
    for fn, wt, v in pb_fields(raw):
        if fn == 2 and wt == 2:
            for fn2, wt2, v2 in pb_fields(v):
                if fn2 == 3 and wt2 == 2:
                    for fn3, wt3, v3 in pb_fields(v2):
                        if fn3 == 2 and wt3 == 2:
                            return v3.decode("utf-8", errors="replace").strip() or None
    return None


def human_duration(seconds: float | None) -> str:
    if not seconds:
        return "0m"
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}h{m:02d}m"
    if m:
        return f"{m}m{s:02d}s" if s and m < 5 else f"{m}m"
    return f"{s}s"


def excerpt(text: str | None, n: int = 240) -> str:
    if not text:
        return ""
    t = " ".join(text.split())
    return t if len(t) <= n else t[: n - 1].rstrip() + "…"
