"""The product: one Markdown file per day that any agent can read. Plus a rolling week and a README."""

from __future__ import annotations

import json
import re
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

from carry.apps import app_name
from carry.config import CONTEXT_DIR, SOURCES
from carry.util import LOCAL_TZ, day_bounds, excerpt, human_duration, now, parse_iso

ASLEEP = {"core", "deep", "rem", "asleepUnspecified"}


def _m(row) -> dict:
    return json.loads(row["meta"] or "{}")


def _t(row) -> str:
    dt = parse_iso(row["ts"])
    return dt.strftime("%H:%M") if dt else ""


def _health_summary(store, day: str) -> list[str]:
    start, end = day_bounds(day)
    lines = []
    # Last night's sleep: stage records that end between 00:00 and 14:00 of `day`.
    sleep = store.ending_between("health", "sleep", start, start + timedelta(hours=14))
    if sleep:
        by = defaultdict(float)
        first, last = None, None
        for r in sleep:
            s, e = parse_iso(r["ts"]), parse_iso(r["ts_end"])
            if not s or not e:
                continue
            stage = _m(r).get("v")
            by[stage] += (e - s).total_seconds()
            if stage in ASLEEP:
                first = s if first is None or s < first else first
                last = e if last is None or e > last else last
        asleep = sum(v for k, v in by.items() if k in ASLEEP)
        if asleep:
            parts = [f"Sleep {human_duration(asleep)}"]
            if first and last:
                parts.append(f"{first.strftime('%H:%M')}–{last.strftime('%H:%M')}")
            for k, label in (("deep", "deep"), ("rem", "REM"), ("core", "core"), ("awake", "awake")):
                if by.get(k):
                    parts.append(f"{label} {human_duration(by[k])}")
            lines.append(" · ".join(parts))
    steps = sum((_m(r).get("v") or 0) for r in store.between("health", start, end, "steps"))
    if steps:
        lines.append(f"Steps {int(steps):,}")
    rhr = store.between("health", start, end, "resting_heart_rate")
    hrv = store.between("health", start, end, "hrv")
    bits = []
    if rhr:
        bits.append(f"resting HR {_m(rhr[-1]).get('v')} bpm")
    if hrv:
        vals = [_m(r).get("v") or 0 for r in hrv]
        bits.append(f"HRV {sum(vals) / len(vals):.0f} ms")
    hr = store.between("health", start, end, "heart_rate")
    if hr:
        vals = [_m(r).get("v") or 0 for r in hr]
        bits.append(f"HR {min(vals):.0f}–{max(vals):.0f}")
    if bits:
        lines.append(" · ".join(bits))
    energy = sum((_m(r).get("v") or 0) for r in store.between("health", start, end, "active_energy"))
    if energy:
        lines.append(f"Active energy {energy:.0f} kcal")
    for r in store.between("health", start, end, "workout"):
        m = _m(r)
        extra = [f"{m['distance_m'] / 1000:.1f} km" if m.get("distance_m") else None,
                 f"{m['energy_kcal']:.0f} kcal" if m.get("energy_kcal") else None]
        s, e = parse_iso(r["ts"]), parse_iso(r["ts_end"])
        dur = human_duration((e - s).total_seconds()) if s and e else ""
        lines.append(f"Workout {m.get('v')} {dur} " + " ".join(x for x in extra if x))
    for kind, label, unit in (("body_mass", "Weight", "kg"), ("blood_oxygen", "SpO₂", "")):
        rows = store.between("health", start, end, kind)
        if rows:
            v = _m(rows[-1]).get("v")
            lines.append(f"{label} {v * 100:.0f}%" if kind == "blood_oxygen" and isinstance(v, (int, float)) else f"{label} {v} {unit}".strip())
    return lines


def build_day(store, day: str, enabled: dict[str, bool], pro: bool, decided_by: str) -> str:
    start, end = day_bounds(day)
    weekday = start.strftime("%A")
    out = [f"# {day} ({weekday})", "",
           f"_Carry digest · generated {now().strftime('%Y-%m-%d %H:%M')} · sources chosen on the {decided_by}"
           f" · Pro {'on' if pro else 'off'}_", ""]
    empty = []

    def section(title: str, lines: list[str]):
        if lines:
            out.extend([f"## {title}", *lines, ""])
        else:
            empty.append(title)

    # Inbox first: what the user deliberately sent.
    if enabled.get("inbox"):
        lines = []
        for r in store.day_items(day, "inbox"):
            m = _m(r)
            head = f"- {_t(r)} **{r['title']}**"
            if m.get("url"):
                head += f" <{m['url']}>"
            if m.get("from_app"):
                head += f" _(from {app_name(m['from_app'])})_"
            lines.append(head)
            if m.get("note"):
                lines.append(f"  - note: {m['note']}")
            if r["text"] and r["text"] != m.get("note"):
                lines.append(f"  - {excerpt(r['text'], 400)}")
        section(f"Inbox ({len(lines and store.day_items(day, 'inbox'))})", lines)

    if enabled.get("health"):
        section("Health", [f"- {x}" for x in _health_summary(store, day)])

    if enabled.get("location"):
        lines = []
        for r in store.between("location", start, end, "visit"):
            s, e = parse_iso(r["ts"]), parse_iso(r["ts_end"])
            span = f"{s.strftime('%H:%M')}–{e.strftime('%H:%M')}" if s and e else (s.strftime("%H:%M") if s else "")
            m = _m(r)
            lines.append(f"- {span} {m.get('place') or f'{m.get('lat')}, {m.get('lon')}'}")
        section("Places", lines)

    if enabled.get("screenshots"):
        rows = store.day_items(day, "screenshots")
        lines = []
        for r in rows[:12]:
            text = excerpt(r["text"], 220)
            lines.append(f"- {_t(r)} " + (text if text else ("_(no text yet, Pro is off)_" if not pro else "_(no text found)_")))
        if len(rows) > 12:
            lines.append(f"- … {len(rows) - 12} more, `carry recent screenshots`")
        section(f"Screenshots ({len(rows)})", lines)

    if enabled.get("photos"):
        rows = store.day_items(day, "photos")
        lines = []
        places = sum(1 for r in rows if _m(r).get("lat") is not None)
        kinds = defaultdict(int)
        for r in rows:
            kinds[r["kind"]] += 1
        if rows:
            lines.append("- " + ", ".join(f"{n} {k}{'s' if n > 1 else ''}" for k, n in kinds.items()) + (f", {places} with location" if places else ""))
        for r in rows:
            if r["text"]:
                lines.append(f"- {_t(r)} {excerpt(r['text'], 200)}")
        section(f"Photos ({len(rows)})", lines)

    if enabled.get("voice_memos"):
        rows = store.day_items(day, "voice_memos")
        lines = []
        for r in rows:
            m = _m(r)
            head = f"- {_t(r)} **{r['title']}** ({human_duration(m.get('duration_s'))})"
            lines.append(head)
            if r["text"]:
                lines.append(f"  - {excerpt(r['text'], 600)}")
            elif not pro:
                lines.append("  - _(transcript needs Pro)_")
        section(f"Voice memos ({len(rows)})", lines)

    if enabled.get("notes"):
        rows = store.day_items(day, "notes")
        lines = []
        for r in rows:
            m = _m(r)
            folder = f" _({m['folder']})_" if m.get("folder") else ""
            lines.append(f"- {_t(r)} **{r['title']}**{folder}")
            body = r["text"] or ""
            if body.startswith(r["title"]):
                body = body[len(r["title"]):].strip()
            if body:
                lines.append(f"  - {excerpt(body, 400)}")
        section(f"Notes edited ({len(rows)})", lines)

    if enabled.get("messages"):
        rows = store.day_items(day, "messages")
        threads: dict[str, list] = defaultdict(list)
        notices = []
        for r in rows:
            (notices if _m(r).get("notification") else threads[r["title"]]).append(r)
        lines = []
        for name, msgs in sorted(threads.items(), key=lambda kv: kv[1][-1]["ts"], reverse=True)[:15]:
            lines.append(f"- **{name}** · {len(msgs)} message{'s' if len(msgs) > 1 else ''}")
            for r in msgs[-2:]:
                lines.append(f"  - {_t(r)} {_m(r).get('sender', '')}: {excerpt(r['text'], 160)}")
        if notices:
            tags = []
            for r in notices:
                m = re.search(r"[【\[]([^】\]]{1,20})[】\]]", r["text"] or "")
                tags.append(m.group(1) if m else excerpt(r["text"], 24))
            lines.append(f"- {len(notices)} SMS notifications: " + "; ".join(dict.fromkeys(tags)))
        section(f"Messages ({len(threads)} threads, {len(notices)} notifications)", lines)
    elif "messages" in enabled:
        out.extend(["## Messages", "- off (you chose)", ""])

    if enabled.get("calendar"):
        lines = []
        for r in store.between("calendar", start, end):
            m = _m(r)
            e = parse_iso(r["ts_end"])
            when = "all day" if m.get("all_day") else f"{_t(r)}–{e.strftime('%H:%M')}" if e else _t(r)
            cal = f" _({m['calendar']})_" if m.get("calendar") else ""
            lines.append(f"- {when} {r['title']}{cal}")
        section(f"Calendar ({len(lines)})", lines)
        upcoming: dict[str, list] = {}
        for r in store.between("calendar", end, end + timedelta(days=7)):
            if not _m(r).get("all_day"):
                upcoming.setdefault(r["title"], []).append(r)
        if upcoming:
            lines = []
            for title, rs in list(upcoming.items())[:8]:
                first = parse_iso(rs[0]["ts"]).strftime("%a %d %H:%M")
                lines.append(f"- {first} {title}" + (f" _(×{len(rs)} this week)_" if len(rs) > 1 else ""))
            out.extend(["### Next 7 days", *lines, ""])

    if enabled.get("reminders"):
        lines = []
        rows = store.con.execute("select * from items where source='reminders' order by ts").fetchall()
        due_today, done_today, overdue = [], [], []
        for r in rows:
            m = _m(r)
            due, done = parse_iso(m.get("due") or ""), parse_iso(m.get("completed_at") or "")
            if done and start <= done < end:
                done_today.append(r)
            elif not m.get("completed") and due and start <= due < end:
                due_today.append(r)
            elif not m.get("completed") and due and due < start:
                overdue.append(r)
        for r in due_today:
            lines.append(f"- [ ] {r['title']} _(due today)_")
        for r in done_today:
            lines.append(f"- [x] {r['title']}")
        if overdue:
            lines.append(f"- {len(overdue)} overdue: " + "; ".join(r["title"] for r in overdue[:5]))
        section("Reminders", lines)

    if enabled.get("safari"):
        rows = store.day_items(day, "safari")
        seen, lines = set(), []
        for r in reversed(rows):
            if r["text"] in seen:
                continue
            seen.add(r["text"])
            lines.append(f"- {_t(r)} {r['title']} <{r['text']}>")
            if len(lines) >= 15:
                break
        section(f"Safari ({len(rows)} visits)", lines)

    if enabled.get("screen_time"):
        rows = sorted(store.day_items(day, "screen_time"), key=lambda r: -_m(r).get("minutes", 0))
        by_device = defaultdict(list)
        for r in rows:
            by_device[_m(r).get("device", "mac")].append(r)
        lines = []
        for device, items in by_device.items():
            top = ", ".join(f"{r['title']} {human_duration(_m(r)['minutes'] * 60)}" for r in items[:8])
            lines.append(f"- {device}: {top}")
        section("Screen time", lines)

    if empty:
        out.append(f"_Nothing today: {', '.join(empty)}_")
    off = [SOURCES[k].label for k, v in enabled.items() if not v and k != "messages"]
    if off:
        out.append(f"_Switched off: {', '.join(off)}_")
    return "\n".join(out).rstrip() + "\n"


def build_week(store, days: list[str]) -> str:
    out = [f"# Last 7 days ({days[-1]} → {days[0]})", "", "| day | inbox | shots | photos | memos | notes | sleep | steps | places |",
           "|---|---|---|---|---|---|---|---|---|"]
    for day in days:
        c = store.day_counts(day)
        h = _health_summary(store, day)
        sleep = next((x.split(" · ")[0].replace("Sleep ", "") for x in h if x.startswith("Sleep")), "")
        steps = next((x.replace("Steps ", "") for x in h if x.startswith("Steps")), "")
        start, end = day_bounds(day)
        places = len(store.between("location", start, end, "visit"))
        out.append(f"| {day} | {c.get('inbox', 0)} | {c.get('screenshots', 0)} | {c.get('photos', 0)} | {c.get('voice_memos', 0)} |"
                   f" {c.get('notes', 0)} | {sleep} | {steps} | {places} |")
    out.append("")
    out.append("Read a day: `~/.carry/context/<date>.md`. Search anything: `carry search \"<query>\"`.")
    return "\n".join(out) + "\n"


README = """# Your phone context

This folder is written by Carry (https://carry.app) on this Mac. It is the living context of the owner's phone.

- `latest.md` → today. Read it first when a request touches the owner's day, health, places, notes, or things they shared from their phone.
- `YYYY-MM-DD.md` → one file per day, rewritten every 15 minutes while the Mac is awake.
- `week.md` → a 7-day table.
- Full text and older days: `carry search "<query>"` or the `carry` MCP server (`carry mcp`).

Sources are chosen by the owner on their phone. A section that says "off" was switched off on purpose; do not try to read it elsewhere.
Nothing here leaves this Mac unless you send it somewhere. Treat it as the owner's private data.
"""


def write_all(store, enabled: dict[str, bool], pro: bool, decided_by: str, days_back: int = 7) -> list[Path]:
    CONTEXT_DIR.mkdir(parents=True, exist_ok=True)
    today = now().strftime("%Y-%m-%d")
    days = [(now() - timedelta(days=i)).strftime("%Y-%m-%d") for i in range(days_back)]
    written = []
    for day in days:
        p = CONTEXT_DIR / f"{day}.md"
        p.write_text(build_day(store, day, enabled, pro, decided_by))
        written.append(p)
    latest = CONTEXT_DIR / "latest.md"
    if latest.is_symlink() or latest.exists():
        latest.unlink()
    latest.symlink_to(f"{today}.md")
    (CONTEXT_DIR / "week.md").write_text(build_week(store, days))
    (CONTEXT_DIR / "README.md").write_text(README)
    return written
