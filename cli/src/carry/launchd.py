"""A LaunchAgent that runs `carry sync` every N minutes while the Mac is awake."""

from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

from carry.config import LOG_DIR

LABEL = "app.carry.sync"
PLIST = Path.home() / "Library/LaunchAgents" / f"{LABEL}.plist"


def _program() -> list[str]:
    exe = shutil.which("carry")
    if exe:
        return [exe, "sync", "--quiet"]
    return [sys.executable, "-m", "carry", "sync", "--quiet"]


def install(minutes: int) -> Path:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    PLIST.parent.mkdir(parents=True, exist_ok=True)
    plist = {
        "Label": LABEL,
        "ProgramArguments": _program(),
        "StartInterval": max(60, minutes * 60),
        "RunAtLoad": True,
        "StandardOutPath": str(LOG_DIR / "sync.log"),
        "StandardErrorPath": str(LOG_DIR / "sync.err"),
        "EnvironmentVariables": {"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + str(Path.home() / ".local/bin")},
    }
    # The developer override travels into the agent when it is set at install time.
    if os.environ.get("CARRY_PRO") == "1":
        plist["EnvironmentVariables"]["CARRY_PRO"] = "1"
    if PLIST.exists():
        subprocess.run(["launchctl", "bootout", f"gui/{_uid()}", str(PLIST)], capture_output=True)
    PLIST.write_bytes(plistlib.dumps(plist))
    subprocess.run(["launchctl", "bootstrap", f"gui/{_uid()}", str(PLIST)], capture_output=True)
    return PLIST


def uninstall() -> bool:
    if not PLIST.exists():
        return False
    subprocess.run(["launchctl", "bootout", f"gui/{_uid()}", str(PLIST)], capture_output=True)
    PLIST.unlink()
    return True


def kickstart() -> None:
    subprocess.run(["launchctl", "kickstart", "-k", f"gui/{_uid()}/{LABEL}"], capture_output=True)


def installed() -> bool:
    return PLIST.exists()


def _uid() -> int:
    return os.getuid()
