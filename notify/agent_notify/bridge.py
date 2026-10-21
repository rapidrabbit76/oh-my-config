"""Hearing back. ``ask`` posts a question and waits for its answer; the
``Bridge``, one background process, reads the listening channel while any
session is away or any question waits: reactions and replies become answers,
other messages from you become prompts for an away session.

Only the owner's messages count (DISCORD_OWNER_ID, set by ``agent-notify
pair``), and only a session switched to ``away`` takes a prompt.
"""

from __future__ import annotations

import fcntl
import os
import signal
import time
from typing import Iterator, Optional, Tuple

from agent_notify import interactive as ia
from agent_notify.agents import agent_types, get_agent
from agent_notify.channels import Inbound, Interactive, listening
from agent_notify.config import STATE_DIR, Config, log
from agent_notify.discord_api import DiscordError
from agent_notify.notifier import detach
from agent_notify.switches import Switches

LOCK = STATE_DIR / "bridge.lock"
POLL_S = float(os.environ.get("AGENT_NOTIFY_POLL_SECONDS") or 3)
IDLE_EXIT_S = 120
YES_WORDS = {"y", "yes", "ok", "allow", "approve", "go", "ㅇ", "ㅇㅇ", "네", "응", "승인", "허용"}


def _exit(*_) -> None:
    raise SystemExit(0)


def _lock() -> Optional[int]:
    """The bridge's lock, held for its life; None when another holds it."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    fd = os.open(LOCK, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        os.close(fd)
        return None
    os.ftruncate(fd, 0)
    os.write(fd, str(os.getpid()).encode())
    return fd


def is_running() -> bool:
    fd = _lock()
    if fd is None:
        return True
    os.close(fd)
    return False


def ensure() -> None:
    """Starts the bridge unless one runs."""
    if not is_running():
        detach({"bridge": True})


def stop() -> bool:
    try:
        pid = int(LOCK.read_text().strip())
    except (OSError, ValueError):
        return False
    if not is_running():
        return False
    try:
        os.kill(pid, signal.SIGTERM)
        return True
    except OSError:
        return False


def away_sessions() -> Iterator[Tuple[str, str]]:
    """(agent, session) of every away session, most recently switched first."""
    found = []
    for cls in agent_types():
        switches = Switches(cls.key)
        for session, _ in switches.sessions("away"):
            try:
                found.append(((switches.dir / session).stat().st_mtime, cls.key, session))
            except OSError:
                pass
    for _, agent, session in sorted(found, reverse=True):
        yield agent, session


def text_answer(question: ia.Question, text: str) -> ia.Answer:
    if question.kind == "approve":
        return ia.Answer("allow") if text.strip().lower() in YES_WORDS else ia.Answer("deny", value=text)
    # A reply naming an option by number picks it.
    if text.strip().isdigit() and 1 <= int(text) <= len(question.options):
        return ia.Answer("choice", values=[question.options[int(text) - 1]])
    return ia.Answer("text", value=text)


class Bridge:
    def __init__(self, config: Optional[Config] = None):
        self.config = config or Config.load()

    def route(self, channel: Interactive, message: Inbound) -> None:
        if message.reply_to and ia.is_pending(message.reply_to):
            question = next((q for mid, _, q in ia.pending() if mid == message.reply_to), None)
            if question:
                ia.answer(message.reply_to, text_answer(question, message.text))
                channel.ack(message, True)
                return
        target = ia.sent_to(message.reply_to) if message.reply_to else None
        if target is None:
            target = next(away_sessions(), None)
        delivered = False
        if target:
            agent_key, session = target
            switches = Switches(agent_key)
            info = switches.info(session)
            # Only an away session takes a prompt from outside.
            if info["mode"] == "away":
                delivered = get_agent(agent_key).deliver_text(session, message.text, info)
        channel.ack(message, delivered)
        log(f"bridge: message {'delivered to' if delivered else 'not delivered'} {target[0] if target else 'no session'}")

    def step(self, channel: Interactive, cursor: str) -> str:
        for message_id, channel_id, question in list(ia.pending()):
            answer = channel.poll_answer(channel_id, message_id, question)
            if answer:
                ia.answer(message_id, answer)
        messages, cursor = channel.poll_messages(cursor)
        for message in messages:
            self.route(channel, message)
        return cursor

    def run(self) -> int:
        fd = _lock()
        if fd is None:
            return 0
        channel = listening(self.config)
        if channel is None:
            log("bridge: no channel can hear back (bot token and agent-notify pair)")
            return 0
        signal.signal(signal.SIGTERM, _exit)
        cursor, idle_since, errors = None, time.time(), 0
        try:
            while True:
                busy = any(True for _ in ia.pending()) or next(away_sessions(), None) is not None
                if busy:
                    idle_since = time.time()
                elif time.time() - idle_since > IDLE_EXIT_S:
                    return 0
                try:
                    if cursor is None:
                        cursor = channel.start_cursor()
                    cursor = self.step(channel, cursor)
                    errors = 0
                except DiscordError as e:
                    errors += 1
                    log(f"bridge: discord {e.status or 'unreachable'}")
                    time.sleep(min(60, POLL_S * 2 ** min(errors, 5)))
                ia.prune()
                time.sleep(POLL_S)
        finally:
            os.close(fd)


class StillWaiting(Exception):
    """``ask(final=False)`` ran out of time with the question still open."""

    def __init__(self, message_id: str):
        super().__init__(message_id)
        self.message_id = message_id


def ask(question: ia.Question, timeout_s: float, token: str = "", resume: str = "", final: bool = True) -> Optional[ia.Answer]:
    """Posts ``question`` (or, with ``resume``, keeps waiting on the one already
    posted) and waits for its answer; None if ``token`` is cancelled (answered
    in the terminal) or, ``final``, it times out. Not ``final``, a timeout
    raises StillWaiting and the question stays open for the next call."""
    config = Config.load()
    channel = listening(config)
    if channel is None:
        return None
    sender = get_agent(question.agent).profile(config)
    if resume and ia.is_pending(resume) or resume and (ia.ANSWERS / f"{resume}.json").exists():
        message_id = resume
    else:
        try:
            _, message_id = channel.ask(question, sender)
        except DiscordError as e:
            log(f"ask: could not post ({e.status})")
            return None
        ia.clear_cancel(token)
    ensure()
    outcome, answered, keep = "", False, False
    signal.signal(signal.SIGTERM, _exit)
    deadline = time.time() + timeout_s
    try:
        while True:
            got = ia.take_answer(message_id)
            if got:
                outcome, answered = f"✅ Answered here: {got.label()}", True
                return got
            if ia.is_cancelled(token):
                outcome = "Answered in the terminal"
                return None
            if time.time() > deadline:
                if not final:
                    keep = True
                    raise StillWaiting(message_id)
                outcome = "No answer in time — back to the terminal"
                return None
            time.sleep(0.5)
    finally:
        if not keep:
            ia.forget(message_id)
            ia.clear_cancel(token)
            try:
                channel.close(message_id, question, sender, outcome or "Answered in the terminal", answered)
            except DiscordError:
                pass
