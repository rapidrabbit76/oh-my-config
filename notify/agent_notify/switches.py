"""Which sessions of an agent have alerts on, and how: one file each.

``$XDG_STATE_HOME/oh-my-config/notify/on/<agent>/<session>``: an empty file
means ``alerts`` (sent only), ``{"mode": "away", ...}`` means ``away`` (sent,
and answers from Discord go back to the session). A sidebar can show the
switch with a file test and ``grep -q away``.
"""

from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import Dict, Iterator, Tuple

from agent_notify.config import STATE_DIR

SESSION_ID = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
KEEP_DAYS = 30
MODES = ("off", "alerts", "away")


class Switches:
    def __init__(self, agent: str, root: Path = STATE_DIR / "on"):
        self.agent = agent
        self.dir = root / agent

    def _path(self, session: str) -> Path:
        if not SESSION_ID.match(session) or session in (".", ".."):
            raise ValueError(f"not a session id: {session!r}")
        return self.dir / session

    def info(self, session: str) -> Dict:
        """``{"mode": ...}`` and whatever was stored with it (a tmux pane, say)."""
        try:
            text = self._path(session).read_text(encoding="utf-8").strip()
        except (ValueError, OSError):
            return {"mode": "off"}
        try:
            data = json.loads(text) if text else {}
        except ValueError:
            data = {}
        data = data if isinstance(data, dict) else {}
        data["mode"] = data.get("mode") if data.get("mode") in ("alerts", "away") else "alerts"
        return data

    def mode(self, session: str) -> str:
        return self.info(session)["mode"]

    def is_on(self, session: str) -> bool:
        return self.mode(session) != "off"

    def set_mode(self, session: str, mode: str, **extra: str) -> str:
        if mode not in MODES:
            raise ValueError(f"not a mode: {mode!r}")
        path = self._path(session)
        if mode == "off":
            _unlink(path)
            return mode
        self.dir.mkdir(parents=True, exist_ok=True)
        data = {k: v for k, v in extra.items() if v}
        path.write_text(json.dumps({"mode": mode, **data}) if mode == "away" or data else "", encoding="utf-8")
        return mode

    def set(self, session: str, on: bool) -> bool:
        self.set_mode(session, "alerts" if on else "off")
        return on

    def toggle(self, session: str) -> bool:
        return self.set(session, not self.is_on(session))

    def sessions(self, mode: str = "away") -> Iterator[Tuple[str, Dict]]:
        """Sessions in ``mode``, most recently switched first."""
        try:
            paths = sorted(self.dir.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
        except OSError:
            return
        for path in paths:
            if path.is_file() and SESSION_ID.match(path.name):
                info = self.info(path.name)
                if info["mode"] == mode:
                    yield path.name, info

    def prune(self) -> None:
        """Drop switches of sessions untouched for KEEP_DAYS."""
        cutoff = time.time() - KEEP_DAYS * 86400
        try:
            for path in self.dir.iterdir():
                if path.is_file() and path.stat().st_mtime < cutoff:
                    _unlink(path)
        except OSError:
            pass


def _unlink(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass
