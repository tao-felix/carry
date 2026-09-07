"""One SQLite store for everything, with FTS5 (trigram, so Chinese works) and per-source cursors."""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime
from pathlib import Path

from carry.config import DB_PATH
from carry.util import LOCAL_TZ, day_of, iso, now

SCHEMA = """
create table if not exists items (
  id text primary key,
  source text not null,
  kind text not null,
  ts text not null,
  ts_end text,
  day text not null,
  title text,
  text text,
  meta text,
  path text,
  device text,
  processed integer default 0,
  created_at text,
  updated_at text
);
create index if not exists items_day on items(day, source);
create index if not exists items_source_ts on items(source, ts);
create virtual table if not exists items_fts using fts5(title, text, content='items', content_rowid='rowid', tokenize='trigram');
create trigger if not exists items_ai after insert on items begin
  insert into items_fts(rowid, title, text) values (new.rowid, new.title, new.text);
end;
create trigger if not exists items_ad after delete on items begin
  insert into items_fts(items_fts, rowid, title, text) values('delete', old.rowid, old.title, old.text);
end;
create trigger if not exists items_au after update on items begin
  insert into items_fts(items_fts, rowid, title, text) values('delete', old.rowid, old.title, old.text);
  insert into items_fts(rowid, title, text) values (new.rowid, new.title, new.text);
end;
create table if not exists sync_state (
  source text primary key,
  cursor text,
  last_run text,
  last_count integer default 0,
  last_error text
);
"""


class Store:
    def __init__(self, path: Path = DB_PATH):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.con = sqlite3.connect(path, timeout=30)
        self.con.row_factory = sqlite3.Row
        self.con.execute("pragma journal_mode=wal")
        self.con.executescript(SCHEMA)

    # --- items -------------------------------------------------------------
    def upsert(self, *, id: str, source: str, kind: str, ts: datetime, ts_end: datetime | None = None,
               title: str | None = None, text: str | None = None, meta: dict | None = None,
               path: str | None = None, device: str | None = None, keep_processed: bool = True) -> bool:
        """Insert or update. Returns True when the row is new."""
        t = iso(ts)
        row = self.con.execute("select processed, text from items where id=?", (id,)).fetchone()
        stamp = iso(now())
        if row is None:
            self.con.execute(
                "insert into items(id,source,kind,ts,ts_end,day,title,text,meta,path,device,processed,created_at,updated_at)"
                " values(?,?,?,?,?,?,?,?,?,?,?,0,?,?)",
                (id, source, kind, t, iso(ts_end), day_of(ts), title, text, json.dumps(meta or {}, ensure_ascii=False), path, device, stamp, stamp),
            )
            return True
        # Never let a re-read overwrite text that processing (OCR / transcript) produced.
        if keep_processed and row["processed"]:
            new_text = row["text"]
        else:
            new_text = text if (text or not keep_processed) else row["text"]
        self.con.execute(
            "update items set source=?,kind=?,ts=?,ts_end=?,day=?,title=?,text=?,meta=?,path=?,device=?,updated_at=? where id=?",
            (source, kind, t, iso(ts_end), day_of(ts), title, new_text, json.dumps(meta or {}, ensure_ascii=False), path, device, stamp, id),
        )
        return False

    def set_processed(self, id: str, text: str | None, extra_meta: dict | None = None) -> None:
        row = self.con.execute("select meta from items where id=?", (id,)).fetchone()
        meta = json.loads(row["meta"] or "{}") if row else {}
        meta.update(extra_meta or {})
        self.con.execute("update items set text=?, processed=1, meta=?, updated_at=? where id=?",
                         (text, json.dumps(meta, ensure_ascii=False), iso(now()), id))

    def pending(self, source: str, limit: int = 200) -> list[sqlite3.Row]:
        return self.con.execute("select * from items where source=? and processed=0 and path is not null order by ts desc limit ?",
                                (source, limit)).fetchall()

    def day_items(self, day: str, source: str | None = None) -> list[sqlite3.Row]:
        if source:
            return self.con.execute("select * from items where day=? and source=? order by ts", (day, source)).fetchall()
        return self.con.execute("select * from items where day=? order by source, ts", (day,)).fetchall()

    def between(self, source: str, start: datetime, end: datetime, kind: str | None = None) -> list[sqlite3.Row]:
        q = "select * from items where source=? and ts>=? and ts<?"
        args: list = [source, iso(start), iso(end)]
        if kind:
            q += " and kind=?"
            args.append(kind)
        return self.con.execute(q + " order by ts", args).fetchall()

    def ending_between(self, source: str, kind: str, start: datetime, end: datetime) -> list[sqlite3.Row]:
        return self.con.execute("select * from items where source=? and kind=? and ts_end>=? and ts_end<? order by ts",
                                (source, kind, iso(start), iso(end))).fetchall()

    def recent(self, source: str, limit: int = 20) -> list[sqlite3.Row]:
        return self.con.execute("select * from items where source=? order by ts desc limit ?", (source, limit)).fetchall()

    def get(self, id: str) -> sqlite3.Row | None:
        return self.con.execute("select * from items where id=?", (id,)).fetchone()

    def search(self, query: str, source: str | None = None, since: str | None = None, limit: int = 20) -> list[sqlite3.Row]:
        q = query.strip()
        if not q:
            return []
        args: list = []
        if len(q) >= 3:
            sql = ("select i.*, bm25(items_fts) as rank from items_fts join items i on i.rowid=items_fts.rowid"
                   " where items_fts match ?")
            args.append('"' + q.replace('"', '""') + '"')
        else:
            sql = "select i.*, 0 as rank from items i where (i.title like ? or i.text like ?)"
            args += [f"%{q}%", f"%{q}%"]
        if source:
            sql += " and i.source=?"
            args.append(source)
        if since:
            sql += " and i.ts>=?"
            args.append(since)
        sql += " order by rank, i.ts desc limit ?"
        args.append(limit)
        return self.con.execute(sql, args).fetchall()

    def counts(self) -> dict[str, int]:
        return {r["source"]: r["n"] for r in self.con.execute("select source, count(*) n from items group by source")}

    def day_counts(self, day: str) -> dict[str, int]:
        return {r["source"]: r["n"] for r in self.con.execute("select source, count(*) n from items where day=? group by source", (day,))}

    def days_with_data(self, limit: int = 14) -> list[str]:
        return [r["day"] for r in self.con.execute("select distinct day from items order by day desc limit ?", (limit,))]

    # --- cursors -----------------------------------------------------------
    def get_cursor(self, source: str) -> str | None:
        row = self.con.execute("select cursor from sync_state where source=?", (source,)).fetchone()
        return row["cursor"] if row else None

    def set_cursor(self, source: str, cursor: str | None, count: int, error: str | None = None) -> None:
        self.con.execute(
            "insert into sync_state(source,cursor,last_run,last_count,last_error) values(?,?,?,?,?)"
            " on conflict(source) do update set cursor=coalesce(excluded.cursor, sync_state.cursor), last_run=excluded.last_run,"
            " last_count=excluded.last_count, last_error=excluded.last_error",
            (source, cursor, iso(now()), count, error),
        )

    def sync_state(self) -> dict[str, sqlite3.Row]:
        return {r["source"]: r for r in self.con.execute("select * from sync_state")}

    def commit(self) -> None:
        self.con.commit()

    def close(self) -> None:
        self.con.commit()
        self.con.close()
