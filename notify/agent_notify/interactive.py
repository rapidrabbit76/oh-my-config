"""Two-way alerts: a question posted to a channel and the answer that comes
back, a reply that becomes a prompt, and the files they pass through.

    sent/<message>.json      an alert's message → its agent and session, so a
                             reply to it reaches that session
    pending/<message>.json   a question waiting for its answer
    answers/<message>.json   that answer, written by the bridge
    inbox/<agent>/<session>/ replies for an agent that reads them itself
    cancel/<token>           the question was answered in the terminal

Every file is the user's alone (mode 600) and dropped once used.
"""

from __future__ import annotations

import json
import os
import tempfile
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Dict, Iterator, List, Optional, Tuple

from agent_notify.config import STATE_DIR

SENT = STATE_DIR / "sent"
PENDING = STATE_DIR / "pending"
ANSWERS = STATE_DIR / "answers"
INBOX = STATE_DIR / "inbox"
CANCEL = STATE_DIR / "cancel"

NUMBERS = ["1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣"]
YES, NO = "✅", "❌"
DELIVERED, UNDELIVERED = "📨", "⚠️"
SENT_KEEP_S = 7 * 86400


def write_private(path: Path, data: Dict) -> None:
    """Atomically, readable by the user alone."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, path)


def read_json(path: Path) -> Optional[Dict]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def drop(path: Path) -> None:
    try:
        path.unlink()
    except OSError:
        pass


def _name(value: str) -> str:
    """A message id or token as a file name: digits, letters, - and _ only."""
    clean = "".join(c for c in value if c.isalnum() or c in "-_")[:128]
    if not clean:
        raise ValueError("empty id")
    return clean


@dataclass
class Question:
    agent: str
    session: str
    kind: str  # "choice" (pick an option) or "approve" (allow / deny)
    title: str
    body: str = ""
    options: List[str] = field(default_factory=list)
    descriptions: List[str] = field(default_factory=list)
    multi: bool = False
    meta: str = ""

    def emojis(self) -> List[str]:
        if self.kind == "approve":
            return [YES, NO]
        marks = NUMBERS[: len(self.options)]
        return marks + [YES] if self.multi else marks

    def text(self) -> str:
        """The body as the channel shows it: the question, then how to answer."""
        lines = [self.body] if self.body else []
        if self.kind == "approve":
            lines.append(f"{YES} allow · {NO} deny · reply to deny with a message")
        else:
            for mark, label, note in zip(NUMBERS, self.options, self.descriptions + [""] * len(self.options)):
                lines.append(f"{mark} **{label}**" + (f" — {note}" if note else ""))
            lines.append("React to pick" + (f", then {YES}" if self.multi else "") + " · or reply with your own answer")
        return "\n".join(lines)


@dataclass
class Answer:
    kind: str  # "choice", "text", "allow" or "deny"
    value: str = ""
    values: List[str] = field(default_factory=list)

    def label(self) -> str:
        if self.kind == "choice":
            return ", ".join(self.values)
        if self.kind == "text":
            return f"“{self.value}”"
        return self.kind + (f": {self.value}" if self.value else "")


# ─── The registry ───────────────────────────────────────


def remember_sent(message_id: str, agent: str, session: str) -> None:
    write_private(SENT / f"{_name(message_id)}.json", {"agent": agent, "session": session, "at": time.time()})


def sent_to(message_id: str) -> Optional[Tuple[str, str]]:
    data = read_json(SENT / f"{_name(message_id)}.json")
    return (data["agent"], data["session"]) if data and data.get("agent") and data.get("session") else None


def add_pending(message_id: str, channel_id: str, question: Question) -> None:
    write_private(PENDING / f"{_name(message_id)}.json", {"channel": channel_id, "question": asdict(question)})


def pending() -> Iterator[Tuple[str, str, Question]]:
    try:
        paths = sorted(PENDING.glob("*.json"))
    except OSError:
        return
    for path in paths:
        data = read_json(path)
        if data:
            yield path.stem, data.get("channel", ""), Question(**data["question"])


def is_pending(message_id: str) -> bool:
    return (PENDING / f"{_name(message_id)}.json").exists()


def answer(message_id: str, ans: Answer) -> None:
    write_private(ANSWERS / f"{_name(message_id)}.json", asdict(ans))
    drop(PENDING / f"{_name(message_id)}.json")


def take_answer(message_id: str) -> Optional[Answer]:
    path = ANSWERS / f"{_name(message_id)}.json"
    data = read_json(path)
    if data is None:
        return None
    drop(path)
    return Answer(**data)


def forget(message_id: str) -> None:
    drop(PENDING / f"{_name(message_id)}.json")
    drop(ANSWERS / f"{_name(message_id)}.json")


def cancel(token: str) -> None:
    CANCEL.mkdir(parents=True, exist_ok=True)
    (CANCEL / _name(token)).touch()


def is_cancelled(token: str) -> bool:
    return bool(token) and (CANCEL / _name(token)).exists()


def clear_cancel(token: str) -> None:
    if token:
        drop(CANCEL / _name(token))


def to_inbox(agent: str, session: str, text: str) -> None:
    write_private(INBOX / _name(agent) / _name(session) / f"{time.time_ns()}.json", {"text": text})


def take_inbox(agent: str, session: str) -> List[str]:
    folder = INBOX / _name(agent) / _name(session)
    texts = []
    try:
        paths = sorted(folder.glob("*.json"))
    except OSError:
        return texts
    for path in paths:
        data = read_json(path)
        drop(path)
        if data and isinstance(data.get("text"), str):
            texts.append(data["text"])
    return texts


def prune() -> None:
    cutoff = time.time() - SENT_KEEP_S
    for folder in (SENT, ANSWERS, CANCEL):
        try:
            for path in folder.iterdir():
                if path.stat().st_mtime < cutoff:
                    drop(path)
        except OSError:
            pass
