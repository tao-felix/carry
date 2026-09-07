"""Paths, the source registry, and the local config file. The phone's sources.json wins over config.toml."""

from __future__ import annotations

import json
import os
import tomllib
from dataclasses import dataclass
from pathlib import Path

from carry.util import parse_iso

CARRY_HOME = Path(os.environ.get("CARRY_HOME", Path.home() / ".carry"))
CONTEXT_DIR = CARRY_HOME / "context"
DB_PATH = CARRY_HOME / "carry.db"
CONFIG_PATH = CARRY_HOME / "config.toml"
LOG_DIR = CARRY_HOME / "logs"
CONTAINER_ID = "iCloud.app.carry.ios"
CONTAINER_DIR = Path(
    os.environ.get(
        "CARRY_CONTAINER",
        Path.home() / "Library/Mobile Documents/iCloud~app~carry~ios/Documents",
    )
)
PRO_PRODUCT_ID = "app.carry.pro"


@dataclass(frozen=True)
class Source:
    name: str
    channel: str  # "icloud" (Apple already syncs it) or "app" (only the Carry app captures it)
    label: str
    reads: str
    default: bool


SOURCES: dict[str, Source] = {
    s.name: s
    for s in [
        Source("photos", "icloud", "Photos", "New photos: time, place, caption. Text inside them with Pro.", True),
        Source("screenshots", "icloud", "Screenshots", "New screenshots. The text inside them with Pro.", True),
        Source("voice_memos", "icloud", "Voice Memos", "New recordings: title, length. Transcript with Pro.", True),
        Source("notes", "icloud", "Notes", "Notes edited today: title and text.", True),
        Source("messages", "icloud", "Messages", "iMessage and SMS threads active today.", False),
        Source("calendar", "icloud", "Calendar", "Today's and upcoming events.", True),
        Source("reminders", "icloud", "Reminders", "Due, overdue and completed today.", True),
        Source("safari", "icloud", "Safari", "Pages visited today.", False),
        Source("screen_time", "icloud", "Screen Time", "Apps used today and for how long.", True),
        Source("health", "app", "Health", "Sleep, steps, heart rate, HRV, workouts, weight, blood oxygen.", True),
        Source("location", "app", "Location", "Places visited: arrive, leave, where.", True),
        Source("inbox", "app", "Share inbox", "Anything you shared to Carry from any app.", True),
    ]
}

DEFAULT_CONFIG = {
    "carry": {"backfill_days": 30, "schedule_minutes": 15},
    "sources": {name: s.default for name, s in SOURCES.items()},
    "processing": {
        "ocr": True,
        "transcribe": True,
        "ocr_photos": False,
        "transcribe_max_minutes": 90,
        "max_transcriptions_per_run": 3,
        "whisper_model": "mlx-community/whisper-large-v3-turbo",
    },
}


def _toml_dump(d: dict) -> str:
    lines = []
    for section, values in d.items():
        lines.append(f"[{section}]")
        for k, v in values.items():
            if isinstance(v, bool):
                lines.append(f"{k} = {'true' if v else 'false'}")
            elif isinstance(v, (int, float)):
                lines.append(f"{k} = {v}")
            else:
                lines.append(f'{k} = "{v}"')
        lines.append("")
    return "\n".join(lines)


def load_config() -> dict:
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))
    if CONFIG_PATH.exists():
        with CONFIG_PATH.open("rb") as f:
            user = tomllib.load(f)
        for section, values in user.items():
            cfg.setdefault(section, {}).update(values)
    return cfg


def save_config(cfg: dict) -> None:
    CARRY_HOME.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(_toml_dump(cfg))


def phone_policy() -> dict | None:
    """sources.json written by the iOS app, or None if the phone has not spoken yet."""
    p = CONTAINER_DIR / "sources.json"
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text())
    except Exception:
        return None


def effective_sources(cfg: dict) -> tuple[dict[str, bool], str]:
    """Which sources are on right now, and who decided ("phone" or "mac")."""
    policy = phone_policy()
    if policy and isinstance(policy.get("sources"), dict):
        enabled = {}
        for name in SOURCES:
            entry = policy["sources"].get(name)
            enabled[name] = bool(entry.get("enabled", SOURCES[name].default)) if isinstance(entry, dict) else cfg["sources"].get(name, SOURCES[name].default)
        return enabled, "phone"
    return {name: bool(cfg["sources"].get(name, SOURCES[name].default)) for name in SOURCES}, "mac"


def effective_processing(cfg: dict) -> dict:
    policy = phone_policy()
    proc = dict(cfg["processing"])
    if policy and isinstance(policy.get("processing"), dict):
        for k in ("ocr", "transcribe"):
            if k in policy["processing"]:
                proc[k] = bool(policy["processing"][k])
    return proc


def policy_updated_at() -> str | None:
    policy = phone_policy()
    if not policy:
        return None
    dt = parse_iso(policy.get("updated_at", ""))
    return dt.isoformat(timespec="seconds") if dt else None
