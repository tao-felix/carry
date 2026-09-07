"""What Pro unlocks and nothing else: turning pictures and audio into text on this Mac."""

from __future__ import annotations

import json
import os
from pathlib import Path

from carry.util import excerpt

OCR_LANGS = ["zh-Hans", "en-US", "ja-JP"]


def ocr_image(path: str) -> str | None:
    from ocrmac import ocrmac

    try:
        ann = ocrmac.OCR(path, recognition_level="accurate", language_preference=OCR_LANGS).recognize()
    except Exception:  # noqa: BLE001
        return None
    lines = [t for t, conf, _ in ann if t and conf >= 0.3]
    return "\n".join(lines).strip() or None


def transcribe_audio(path: str, model: str) -> tuple[str | None, str | None]:
    """Returns (text, error). Copies the audio to a scratch file first: under launchd, ffmpeg (a child
    process) is denied Apple's protected containers even when this process may read them. Tries the
    cached model offline first so a missing proxy cannot break a background run."""
    import shutil
    import tempfile

    os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")
    os.environ.setdefault("TQDM_DISABLE", "1")
    import mlx_whisper

    from carry.config import CARRY_HOME

    scratch_dir = CARRY_HOME / "tmp"
    scratch_dir.mkdir(parents=True, exist_ok=True)
    fd, scratch = tempfile.mkstemp(prefix="memo-", suffix=Path(path).suffix or ".m4a", dir=scratch_dir)
    os.close(fd)
    try:
        try:
            shutil.copyfile(path, scratch)
        except OSError as e:
            return None, f"cannot read audio: {e}"
        last_error = None
        for offline in ("1", "0"):
            os.environ["HF_HUB_OFFLINE"] = offline
            try:
                out = mlx_whisper.transcribe(scratch, path_or_hf_repo=model, verbose=None)
                text = (out.get("text") or "").strip()
                return (text or None), None
            except Exception as e:  # noqa: BLE001
                msg = " ".join(str(e).split())
                last_error = f"{type(e).__name__}: {msg[-300:]}"
        return None, last_error
    finally:
        Path(scratch).unlink(missing_ok=True)


def audio_seconds(path: str) -> float | None:
    """Duration via ffprobe, for recordings whose database row says 0."""
    import subprocess

    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                             capture_output=True, text=True, timeout=20)
        return float(out.stdout.strip()) if out.stdout.strip() else None
    except Exception:  # noqa: BLE001
        return None


def pending_counts(store) -> dict[str, int]:
    return {
        "screenshots": len(store.pending("screenshots", 10_000)),
        "photos": len(store.pending("photos", 10_000)),
        "voice_memos": len(store.pending("voice_memos", 10_000)),
        "inbox": len([r for r in store.pending("inbox", 10_000) if r["kind"] == "image"]),
    }


def run(store, proc: dict, pro: bool, limit: int = 60, log=print) -> dict[str, int]:
    """Process items that still lack text. Returns counts per source. Does nothing without Pro."""
    done = {"screenshots": 0, "photos": 0, "inbox": 0, "voice_memos": 0}
    if not pro:
        return done
    if proc.get("ocr", True):
        targets = [("screenshots", store.pending("screenshots", limit))]
        if proc.get("ocr_photos"):
            targets.append(("photos", store.pending("photos", limit)))
        targets.append(("inbox", [r for r in store.pending("inbox", limit) if r["kind"] == "image"]))
        for source, rows in targets:
            for r in rows:
                if not r["path"] or not Path(r["path"]).exists():
                    store.set_processed(r["id"], r["text"], {"ocr": "missing-file"})
                    continue
                text = ocr_image(r["path"])
                base = r["text"] if source == "inbox" else None
                merged = "\n".join(x for x in (base, text) if x) or None
                store.set_processed(r["id"], merged, {"ocr": "vision", "ocr_chars": len(text or "")})
                done[source] += 1
                log(f"  ocr  {source:12s} {excerpt(text, 60) or '(no text)'}")
        store.commit()
    if proc.get("transcribe", True):
        max_s = float(proc.get("transcribe_max_minutes", 90)) * 60
        model = proc.get("whisper_model", "mlx-community/whisper-large-v3-turbo")
        per_run = int(proc.get("max_transcriptions_per_run", 3))
        for r in store.pending("voice_memos", limit):
            meta = json.loads(r["meta"] or "{}")
            if not r["path"] or not Path(r["path"]).exists():
                store.set_processed(r["id"], None, {"transcript": "missing-file"})
                continue
            seconds = meta.get("duration_s") or audio_seconds(r["path"]) or 0
            if seconds > max_s:
                store.set_processed(r["id"], None, {"transcript": "skipped-too-long", "duration_s": round(seconds)})
                continue
            if per_run <= 0:
                break
            per_run -= 1
            log(f"  whisper {r['title'][:40]} ({seconds / 60:.0f} min)…")
            text, err = transcribe_audio(r["path"], model)
            store.set_processed(r["id"], text, {"transcript": "whisper" if text else "failed", "model": model,
                                                "duration_s": round(seconds), "error": err})
            done["voice_memos"] += 1
            store.commit()
    return done
