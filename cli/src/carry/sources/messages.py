"""iMessage and SMS from ~/Library/Messages/chat.db (needs Full Disk Access). Off by default."""

from __future__ import annotations

import glob
import re
from datetime import datetime
from pathlib import Path

from carry.util import apple_to_dt, decode_attributed_body, dt_to_apple, open_ro, stable_id

DB = Path.home() / "Library/Messages/chat.db"
ADDRESSBOOK = str(Path.home() / "Library/Application Support/AddressBook/Sources/*/AddressBook-v22.abcddb")


def available() -> tuple[bool, str]:
    if not DB.exists():
        return False, "No Messages database"
    try:
        con = open_ro(DB)
        n = con.execute("select count(*) from message").fetchone()[0]
        con.close()
        return True, f"{n:,} messages"
    except Exception as e:  # noqa: BLE001
        return False, f"Cannot read chat.db ({e}). Grant Full Disk Access to your terminal."


def _norm(handle: str) -> str:
    h = handle.strip().lower()
    if "@" in h:
        return h
    digits = re.sub(r"\D", "", h)
    return digits[-10:] if len(digits) >= 10 else digits


def contact_names() -> dict[str, str]:
    """handle (normalised phone digits or email) → 'First Last', from the local Contacts store."""
    names: dict[str, str] = {}
    for f in glob.glob(ADDRESSBOOK):
        try:
            con = open_ro(Path(f))
            people = {r["Z_PK"]: " ".join(x for x in (r["ZFIRSTNAME"], r["ZLASTNAME"]) if x).strip() or (r["ZORGANIZATION"] or "")
                      for r in con.execute("select Z_PK, ZFIRSTNAME, ZLASTNAME, ZORGANIZATION from ZABCDRECORD")}
            for r in con.execute("select ZOWNER, ZFULLNUMBER from ZABCDPHONENUMBER"):
                if r["ZFULLNUMBER"] and people.get(r["ZOWNER"]):
                    names[_norm(r["ZFULLNUMBER"])] = people[r["ZOWNER"]]
            for r in con.execute("select ZOWNER, ZADDRESS from ZABCDEMAILADDRESS"):
                if r["ZADDRESS"] and people.get(r["ZOWNER"]):
                    names[_norm(r["ZADDRESS"])] = people[r["ZOWNER"]]
            con.close()
        except Exception:  # noqa: BLE001
            continue
    return names


def collect(store, cfg, backfill_start: datetime) -> int:
    con = open_ro(DB)
    names = contact_names()
    cursor = store.get_cursor("messages")
    since = float(cursor) if cursor else dt_to_apple(backfill_start) * 1e9
    rows = con.execute(
        """select m.ROWID, m.guid, m.date, m.is_from_me, m.text, m.attributedBody, m.cache_has_attachments,
                  h.id as handle, c.chat_identifier, c.display_name, c.ROWID as chat_id, c.style
           from message m
           left join handle h on h.ROWID = m.handle_id
           left join chat_message_join cmj on cmj.message_id = m.ROWID
           left join chat c on c.ROWID = cmj.chat_id
           where m.date > ? order by m.date""",
        (since,),
    ).fetchall()
    new = 0
    last = since
    for r in rows:
        ts = apple_to_dt(r["date"])
        if not ts:
            continue
        text = (r["text"] or "").strip() or decode_attributed_body(r["attributedBody"])
        if not text and not r["cache_has_attachments"]:
            last = max(last, r["date"] or 0)
            continue
        handle = r["handle"] or ""
        known = names.get(_norm(handle)) if handle else None
        who = known or handle or "me"
        # Numeric senders without a contact (10086, 1069…) are notifications, not people.
        notification = bool(handle) and not known and handle.lstrip("+").isdigit() and not (r["display_name"] or "").strip()
        chat_label = (r["display_name"] or "").strip() or who or r["chat_identifier"] or "unknown"
        meta = {"from_me": bool(r["is_from_me"]), "handle": handle, "sender": "me" if r["is_from_me"] else who,
                "chat_id": r["chat_id"], "group": bool(r["style"] == 43), "attachment": bool(r["cache_has_attachments"]),
                "notification": notification}
        if store.upsert(id=stable_id("msg", r["guid"]), source="messages", kind="message", ts=ts,
                        title=chat_label, text=text or "[attachment]", meta=meta):
            new += 1
        last = max(last, r["date"] or 0)
    con.close()
    store.set_cursor("messages", str(int(last)), new)
    return new
