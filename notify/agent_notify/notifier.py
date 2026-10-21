"""Sends an alert to every configured channel, now or from a detached process."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, Dict, Mapping, Optional

from agent_notify.alert import Alert
from agent_notify.channels import Profile, configured
from agent_notify.config import STATE_DIR, Config, log

if TYPE_CHECKING:
    from agent_notify.agents import Agent

ROOT = Path(__file__).resolve().parent.parent
SPOOL = STATE_DIR / "spool"
# How a detached child starts this package again (see the agent-notify launcher).
BOOT = "import sys; sys.path.insert(0, sys.argv.pop(1)); from agent_notify.cli import main; sys.exit(main())"


def detach(job: Mapping) -> None:
    """Runs ``job`` in a process of its own session that shares no fd with the
    caller, so the caller returns at once. The job goes through a file only the
    user can read, not argv, where any local process could see an answer."""
    try:
        SPOOL.mkdir(parents=True, exist_ok=True)
        fd, path = tempfile.mkstemp(dir=SPOOL, suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(job, f, ensure_ascii=False)
        subprocess.Popen(
            [sys.executable, "-E", "-s", "-c", BOOT, str(ROOT), "_run", path],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
    except OSError as e:
        log(f"could not start a sender ({type(e).__name__})")


def take_job(path: str) -> Optional[Dict]:
    """Reads and removes a spooled job; one outside the spool is refused."""
    file = Path(path).resolve()
    if file.parent != SPOOL.resolve():
        return None
    try:
        job = json.loads(file.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    finally:
        try:
            file.unlink()
        except OSError:
            pass
    return job if isinstance(job, dict) else None


class Notifier:
    def __init__(self, config: Optional[Config] = None):
        self.config = config or Config.load()

    def sender(self, agent: "Agent") -> Profile:
        return agent.profile(self.config)

    def deliver(self, agent: "Agent", alert: Alert, only: Optional[str] = None) -> Dict[str, bool]:
        """Sends now; which channels took it. No channel set: ``{}``."""
        sender = self.sender(agent)
        return {ch.key: ch.send(alert, sender) for ch in configured(self.config, only)}

    @staticmethod
    def deliver_later(alert: Alert) -> None:
        detach({"send": alert.__dict__})

    @staticmethod
    def handle_later(agent_key: str, event: Mapping) -> None:
        detach({"hook": agent_key, "event": dict(event)})
