"""The iCloud container written by the Carry iOS app: health, location, inbox, manifest, license,
plus the heartbeat the Mac writes back so the phone can say "Mac read this 12 minutes ago"."""

from __future__ import annotations

import json
import socket
from datetime import datetime
from pathlib import Path

from carry import __version__
from carry.config import CONTAINER_DIR
from carry.util import icloud_download, iso, now, parse_iso, stable_id


def present() -> bool:
    return CONTAINER_DIR.exists()


def manifest() -> dict | None:
    p = CONTAINER_DIR / "manifest.json"
    try:
        return json.loads(p.read_text()) if p.exists() else None
    except Exception:  # noqa: BLE001
        return None


def _jsonl_files(sub: str) -> list[Path]:
    d = CONTAINER_DIR / sub
    return sorted(d.glob("*.jsonl")) if d.exists() else []


def _line_cursor(store, key: str) -> dict[str, int]:
    raw = store.get_cursor(key)
    try:
        return json.loads(raw) if raw else {}
    except Exception:  # noqa: BLE001
        return {}


def _read_new_lines(path: Path, offset: int) -> tuple[list[dict], int]:
    data = path.read_bytes()
    if offset > len(data):  # file was replaced; start over
        offset = 0
    out = []
    for line in data[offset:].splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except Exception:  # noqa: BLE001
            continue
    return out, len(data)


def collect_health(store, cfg, backfill_start: datetime) -> int:
    icloud_download(CONTAINER_DIR / "health")
    cursors = _line_cursor(store, "health")
    new = 0
    for f in _jsonl_files("health"):
        recs, size = _read_new_lines(f, cursors.get(f.name, 0))
        for r in recs:
            start, end = parse_iso(r.get("start", "")), parse_iso(r.get("end", ""))
            if not start:
                continue
            t = r.get("t", "unknown")
            v, u, src = r.get("v"), r.get("u", ""), r.get("src", "")
            text = f"{v} {u}".strip() if not isinstance(v, str) else f"{v}"
            meta = {"v": v, "u": u, "src": src}
            if isinstance(r.get("meta"), dict):
                meta.update(r["meta"])
            if store.upsert(id=stable_id("health", t, r.get("start"), r.get("end"), src), source="health", kind=t,
                            ts=start, ts_end=end, title=t, text=text, meta=meta, device="iphone"):
                new += 1
        cursors[f.name] = size
    store.set_cursor("health", json.dumps(cursors), new)
    return new


def collect_location(store, cfg, backfill_start: datetime) -> int:
    icloud_download(CONTAINER_DIR / "location")
    cursors = _line_cursor(store, "location")
    new = 0
    for f in _jsonl_files("location"):
        recs, size = _read_new_lines(f, cursors.get(f.name, 0))
        for r in recs:
            kind = r.get("kind", "point")
            if kind == "visit":
                ts, end = parse_iso(r.get("arrive", "")), parse_iso(r.get("depart", ""))
            else:
                ts, end = parse_iso(r.get("ts", "")), None
            if not ts:
                continue
            place = r.get("place")
            meta = {"lat": r.get("lat"), "lon": r.get("lon"), "acc_m": r.get("acc_m"), "place": place}
            if store.upsert(id=stable_id("loc", kind, r.get("arrive") or r.get("ts"), r.get("lat"), r.get("lon")),
                            source="location", kind=kind, ts=ts, ts_end=end, title=place or f"{r.get('lat')}, {r.get('lon')}",
                            meta=meta, device="iphone"):
                new += 1
        cursors[f.name] = size
    store.set_cursor("location", json.dumps(cursors), new)
    return new


def collect_inbox(store, cfg, backfill_start: datetime) -> int:
    d = CONTAINER_DIR / "inbox"
    icloud_download(d)
    if not d.exists():
        store.set_cursor("inbox", None, 0)
        return 0
    new = 0
    for f in sorted(d.glob("*.json")):
        try:
            r = json.loads(f.read_text())
        except Exception:  # noqa: BLE001
            continue
        ts = parse_iso(r.get("ts", "")) or now()
        kind = r.get("kind", "text")
        text = (r.get("text") or "").strip() or None  # the note stays in meta; the digest prints it on its own line
        attachment = d / r["file"] if r.get("file") else None
        meta = {"url": r.get("url"), "from_app": r.get("from_app"), "note": r.get("note"), "file": r.get("file")}
        title = (r.get("title") or "").strip() or r.get("url") or ((r.get("text") or "")[:60].strip()) or kind.capitalize()
        if store.upsert(id=stable_id("inbox", r.get("id") or f.stem), source="inbox", kind=kind, ts=ts, title=title,
                        text=text, meta=meta, path=str(attachment) if attachment and attachment.exists() else None,
                        device="iphone"):
            new += 1
    store.set_cursor("inbox", None, new)
    return new


def write_heartbeat(store, pro: bool, sources_applied_at: str | None, last_digest_date: str | None) -> Path | None:
    if not present():
        return None
    d = CONTAINER_DIR / "heartbeat"
    d.mkdir(parents=True, exist_ok=True)
    host = socket.gethostname().split(".")[0]
    counts = store.counts()
    payload = {
        "host": host,
        "carry_version": __version__,
        "last_sync_at": iso(now()),
        "last_digest_date": last_digest_date,
        "counts": {k: counts.get(k, 0) for k in ("health", "location", "inbox", "photos", "screenshots", "notes", "voice_memos")},
        "pro": pro,
        "sources_applied_at": sources_applied_at,
    }
    p = d / f"{host}.json"
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2))
    tmp.replace(p)
    return p
