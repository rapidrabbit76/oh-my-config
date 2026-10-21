"""Codex CLI, through its hooks (~/.codex/hooks.json): Stop, PermissionRequest.

A thread's switch is set from codex-sidebar (``n``) or ``agent-notify codex on``.
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
import time
from datetime import datetime
from pathlib import Path
from typing import Mapping, Optional

from agent_notify.agents import Agent, agent
from agent_notify.alert import Alert
from agent_notify.notifier import Notifier
from agent_notify.switches import Switches
from agent_notify.util import meta, took, where

CODEX_HOME = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")
# An approval left this long counts as waiting for you.
WAIT_S = float(os.environ.get("AGENT_NOTIFY_WAIT_SECONDS") or 30)
TAIL_BYTES = 2_000_000


def _state_db() -> Optional[Path]:
    dbs = sorted(CODEX_HOME.glob("state_*.sqlite"), key=lambda p: p.stat().st_mtime, reverse=True)
    return dbs[0] if dbs else None


def _query(sql: str, *args: str) -> Optional[tuple]:
    db = _state_db()
    if db is None:
        return None
    try:
        with sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=2) as conn:
            return conn.execute(sql, args).fetchone()
    except sqlite3.Error:
        return None


def _stamp(path: str) -> tuple:
    try:
        st = os.stat(path)
        return (st.st_mtime_ns, st.st_size)
    except OSError:
        return (0, 0)


def _turn_seconds(rollout: str) -> Optional[float]:
    """Since the rollout's last task_started."""
    try:
        with open(rollout, "rb") as f:
            f.seek(max(0, os.path.getsize(rollout) - TAIL_BYTES))
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return None
    for line in reversed(lines):
        if '"task_started"' not in line:
            continue
        try:
            stamp = json.loads(line)["timestamp"]
            # 2026-10-21T14:56:49.123Z: Python 3.9 reads neither the Z nor every fraction.
            stamp = re.sub(r"\.\d+", "", stamp).replace("Z", "+00:00")
            return time.time() - datetime.fromisoformat(stamp).timestamp()
        except (ValueError, KeyError, TypeError):
            return None
    return None


@agent
class Codex(Agent):
    key = "codex"
    name = "Codex"
    avatar = "https://avatars.githubusercontent.com/u/14957082?s=256"  # github.com/openai
    hook_events = ("Stop", "PermissionRequest")

    def session_in(self, folder: str) -> Optional[str]:
        row = _query(
            "SELECT id FROM threads WHERE cwd = ? AND archived = 0 AND source NOT LIKE '{%'"
            " ORDER BY (source = 'cli') DESC, updated_at_ms DESC LIMIT 1",
            os.path.realpath(folder),
        )
        return row[0] if row else None

    def title_of(self, thread: str) -> str:
        row = _query(
            "SELECT coalesce(nullif(name, ''), nullif(title, ''), '') FROM threads WHERE id = ?", thread
        )
        return (row[0] if row else "").replace("\n", " ")

    def on_hook(self, event: Mapping, notifier: Notifier) -> None:
        name = event.get("hook_event_name")
        thread = self.session_of(event) or ""
        title = self.title_of(thread)
        folder = str(event.get("cwd") or "")
        rollout = str(event.get("transcript_path") or "")

        if name == "Stop":
            seconds = _turn_seconds(rollout) if rollout else None
            alert = Alert(
                self.key,
                "done",
                f"Done · {title}" if title else "Done",
                str(event.get("last_assistant_message") or ""),
                meta(where(folder), took(seconds) if seconds is not None else ""),
            )
            notifier.deliver(self, alert)

        elif name == "PermissionRequest":
            before = _stamp(rollout)
            time.sleep(WAIT_S)
            # An answer, or the turn going on, writes to the rollout.
            if _stamp(rollout) != before or not Switches(self.key).is_on(thread):
                return
            tool = event.get("tool_input") if isinstance(event.get("tool_input"), dict) else {}
            detail = tool.get("description") or tool.get("command") or tool.get("cmd") or ""
            if isinstance(detail, list):
                detail = " ".join(map(str, detail))
            body = f"{event.get('tool_name') or 'a tool'}: {detail}" if detail else str(event.get("tool_name") or "")
            alert = Alert(
                self.key,
                "wait",
                f"Waiting for approval · {title}" if title else "Waiting for approval",
                body,
                where(folder),
            )
            notifier.deliver(self, alert)
