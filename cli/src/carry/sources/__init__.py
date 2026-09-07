"""Readers for data Apple already synced to this Mac. Each module exposes
`available() -> (bool, str)` and `collect(store, cfg, backfill_start) -> int` (new items)."""

from carry.sources import calendar, messages, notes, photos, reminders, safari, screen_time, voice_memos

READERS = {
    "photos": photos,
    "screenshots": photos,  # one reader, two switches; photos.collect honours both
    "voice_memos": voice_memos,
    "notes": notes,
    "messages": messages,
    "calendar": calendar,
    "reminders": reminders,
    "safari": safari,
    "screen_time": screen_time,
}
