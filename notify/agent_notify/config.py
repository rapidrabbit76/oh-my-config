"""Where agent-notify keeps things, and the channels file."""

from __future__ import annotations

import os
import time
from pathlib import Path
from typing import Dict, Optional


def _base(var: str, *default: str) -> Path:
    value = os.environ.get(var)
    return Path(value) if value else Path.home().joinpath(*default)


CONFIG_PATH = Path(
    os.environ.get("AGENT_NOTIFY_CONFIG")
    or _base("XDG_CONFIG_HOME", ".config") / "oh-my-config" / "notify.env"
)
STATE_DIR = _base("XDG_STATE_HOME", ".local", "state") / "oh-my-config" / "notify"
LOG_PATH = STATE_DIR / "notify.log"
LOG_KEEP = 200


def log(message: str) -> None:
    """One line in the log; never a URL or a token. Never raises."""
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")
        lines = LOG_PATH.read_text(encoding="utf-8").splitlines()
        if len(lines) > LOG_KEEP * 3 // 2:
            LOG_PATH.write_text("\n".join(lines[-LOG_KEEP:]) + "\n", encoding="utf-8")
    except OSError:
        pass


class Config:
    """``KEY=value`` lines, read as text: nothing in the file is run."""

    HEADER = "# agent-notify channels and profiles (oh-my-config). Keep this file private.\n"

    def __init__(self, values: Optional[Dict[str, str]] = None, path: Path = CONFIG_PATH):
        self.values: Dict[str, str] = dict(values or {})
        self.path = path

    @classmethod
    def load(cls, path: Path = CONFIG_PATH) -> "Config":
        values: Dict[str, str] = {}
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            return cls(values, path)
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            values[key.strip()] = value
        return cls(values, path)

    def get(self, key: str, default: str = "") -> str:
        return self.values.get(key, default)

    def set(self, key: str, value: str) -> None:
        if value:
            self.values[key] = value
        else:
            self.values.pop(key, None)

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        body = self.HEADER + "".join(f"{k}={v}\n" for k, v in sorted(self.values.items()))
        old = os.umask(0o077)
        try:
            self.path.write_text(body, encoding="utf-8")
        finally:
            os.umask(old)
        os.chmod(self.path, 0o600)
