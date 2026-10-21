"""Codex CLI, through its hooks (~/.codex/hooks.json): Stop, PermissionRequest.

A thread's switch is set from codex-sidebar (``n``) or ``agent-notify codex on``.
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, Mapping, Optional

from agent_notify.agents import Agent, HookReply, agent
from agent_notify.alert import Alert
from agent_notify.notifier import Notifier
from agent_notify.switches import Switches
from agent_notify.util import meta, took, where

CODEX_HOME = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")
# An approval left this long counts as waiting for you.
WAIT_S = float(os.environ.get("AGENT_NOTIFY_WAIT_SECONDS") or 30)
# Away: how long an approval waits for Discord before Codex asks in the terminal.
# Keep it under the PermissionRequest hook's timeout in config.toml (900s).
APPROVE_S = float(os.environ.get("AGENT_NOTIFY_APPROVE_SECONDS") or 600)
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

    def locate(self, folder: str) -> Dict[str, str]:
        """The tmux pane running Codex in ``folder``, where a reply gets typed."""
        try:
            ran = subprocess.run(
                ["tmux", "list-panes", "-a", "-F", "#{pane_id}\t#{pane_current_command}\t#{pane_current_path}"],
                capture_output=True, text=True, timeout=5,
            )
        except (OSError, subprocess.SubprocessError):
            return {}
        want = os.path.realpath(folder)
        for line in ran.stdout.splitlines():
            pane, command, path = (line.split("\t") + ["", ""])[:3]
            if command.startswith("codex") and os.path.realpath(path) == want:
                return {"pane": pane}
        return {}

    def title_of(self, thread: str) -> str:
        row = _query(
            "SELECT coalesce(nullif(name, ''), nullif(title, ''), '') FROM threads WHERE id = ?", thread
        )
        return (row[0] if row else "").replace("\n", " ")

    def approval_body(self, event: Mapping) -> str:
        tool = event.get("tool_input") if isinstance(event.get("tool_input"), dict) else {}
        detail = tool.get("description") or tool.get("command") or tool.get("cmd") or ""
        if isinstance(detail, list):
            detail = " ".join(map(str, detail))
        name = str(event.get("tool_name") or "a tool")
        return f"{name}: {detail}" if detail else name

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
                thread,
            )
            notifier.deliver(self, alert)

        elif name == "PermissionRequest":
            before = _stamp(rollout)
            time.sleep(WAIT_S)
            # An answer, or the turn going on, writes to the rollout.
            if _stamp(rollout) != before or not Switches(self.key).is_on(thread):
                return
            alert = Alert(
                self.key,
                "wait",
                f"Waiting for approval · {title}" if title else "Waiting for approval",
                self.approval_body(event),
                where(folder),
                thread,
            )
            notifier.deliver(self, alert)

    def on_hook_sync(self, event: Mapping, notifier: Notifier, mode: str) -> HookReply:
        """Away: an approval goes to Discord first, and its answer is the decision.
        No answer in APPROVE_S: no output, so Codex shows its own prompt."""
        if mode != "away" or event.get("hook_event_name") != "PermissionRequest":
            return HookReply()
        from agent_notify import bridge
        from agent_notify.channels import listening
        from agent_notify.interactive import Question

        # Nothing can hear back (no bot, not paired): the plain alert, as in alerts mode.
        if listening(notifier.config) is None:
            return HookReply()
        thread = self.session_of(event) or ""
        title = self.title_of(thread)
        question = Question(
            self.key,
            thread,
            "approve",
            f"Approve? · {title}" if title else "Approve?",
            self.approval_body(event),
            meta=where(str(event.get("cwd") or "")),
        )
        answer = bridge.ask(question, APPROVE_S)
        if answer is None:
            return HookReply(handled=True)
        decision = {"behavior": "allow"} if answer.kind == "allow" else {
            "behavior": "deny",
            "message": answer.value or "Denied from Discord.",
        }
        return HookReply({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}}, True)

    def deliver_text(self, session: str, text: str, info: Mapping) -> bool:
        """Types the message into the thread's Codex pane, as a paste then Enter."""
        pane = str(info.get("pane") or "")
        if not pane.startswith("%") or not _pane_alive(pane):
            return False
        try:
            subprocess.run(["tmux", "load-buffer", "-b", "agent-notify", "-"], input=text, text=True, timeout=5, check=True)
            subprocess.run(["tmux", "paste-buffer", "-p", "-d", "-b", "agent-notify", "-t", pane], timeout=5, check=True)
            subprocess.run(["tmux", "send-keys", "-t", pane, "Enter"], timeout=5, check=True)
            return True
        except (OSError, subprocess.SubprocessError):
            return False


def _pane_alive(pane: str) -> bool:
    """tmux display answers a missing pane with nothing, not an error: ask list-panes."""
    try:
        ran = subprocess.run(["tmux", "list-panes", "-a", "-F", "#{pane_id}"], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return False
    return pane in ran.stdout.split()
