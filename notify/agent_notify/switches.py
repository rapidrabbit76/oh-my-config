"""Which sessions of an agent have alerts on: one empty file each.

A sidebar can read a switch with nothing but a file test:
``$XDG_STATE_HOME/oh-my-config/notify/on/<agent>/<session>``.
"""

from __future__ import annotations

import re
import time
from pathlib import Path

from agent_notify.config import STATE_DIR

SESSION_ID = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
KEEP_DAYS = 30


class Switches:
    def __init__(self, agent: str, root: Path = STATE_DIR / "on"):
        self.dir = root / agent

    def _path(self, session: str) -> Path:
        if not SESSION_ID.match(session) or session in (".", ".."):
            raise ValueError(f"not a session id: {session!r}")
        return self.dir / session

    def is_on(self, session: str) -> bool:
        try:
            return self._path(session).exists()
        except ValueError:
            return False

    def set(self, session: str, on: bool) -> bool:
        path = self._path(session)
        if on:
            self.dir.mkdir(parents=True, exist_ok=True)
            path.touch()
        else:
            _unlink(path)
        return on

    def toggle(self, session: str) -> bool:
        return self.set(session, not self.is_on(session))

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
