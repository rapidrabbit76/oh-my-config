"""Where alerts go. A channel is one subclass registered with ``@channel``."""

from __future__ import annotations

import json
import socket
import urllib.error
import urllib.request
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Callable, ClassVar, Dict, List, Optional, Tuple, Type

from agent_notify import __version__
from agent_notify.alert import Alert
from agent_notify.config import Config, log

TIMEOUT_S = 10
USER_AGENT = f"agent-notify/{__version__} (+https://github.com/rapidrabbit76/oh-my-config)"


@dataclass(frozen=True)
class Profile:
    """Who an alert is from, as a channel shows it."""

    name: str
    avatar: str = ""  # a public PNG or JPEG URL


@dataclass(frozen=True)
class Setting:
    """One value a channel reads from the config, and how setup asks for it."""

    key: str
    prompt: str
    help: str = ""
    is_secret: bool = False
    is_required: bool = True
    check: Callable[[str], bool] = lambda value: True
    is_asked: bool = True  # False: set by a command (agent-notify pair), not by setup


@dataclass(frozen=True)
class Request:
    url: str
    body: Dict
    headers: Dict[str, str] = field(default_factory=dict)


class Channel(ABC):
    key: ClassVar[str]
    label: ClassVar[str]
    settings: ClassVar[Tuple[Setting, ...]]

    def __init__(self, config: Config):
        self.config = config

    def value(self, key: str) -> str:
        return self.config.get(key)

    @classmethod
    def state(cls, config: Config) -> str:
        """``off`` (nothing set), ``on``, or ``invalid`` (set, but wrong)."""
        values = [(s, config.get(s.key)) for s in cls.settings]
        if not any(v for s, v in values if s.is_required):
            return "off"
        for s, v in values:
            if (v or s.is_required) and not s.check(v):
                return "invalid"
        return "on"

    @abstractmethod
    def request(self, alert: Alert, sender: Profile) -> Request:
        """The HTTP request that sends ``alert``."""

    def describe(self) -> str:
        """What status shows of the target, with nothing secret in it."""
        return ""

    def send(self, alert: Alert, sender: Profile) -> bool:
        """Posts the alert; any failure is logged (never the URL) and returns False."""
        try:
            req = self.request(alert, sender)
            if isinstance(self, Interactive) and alert.session and self.can_listen(self.config):
                # Sent where the bot can see replies: remember the message, so a reply reaches the session.
                return self.post_alert(alert, sender)
            data = json.dumps(req.body, ensure_ascii=False).encode("utf-8")
            headers = {"Content-Type": "application/json", "User-Agent": USER_AGENT, **req.headers}
            http = urllib.request.Request(req.url, data=data, headers=headers, method="POST")
            with urllib.request.urlopen(http, timeout=TIMEOUT_S) as response:
                if 200 <= response.status < 300:
                    return True
                log(f"{alert.agent} {self.key} failed (http {response.status})")
        except urllib.error.HTTPError as e:
            e.close()
            log(f"{alert.agent} {self.key} failed (http {e.code})")
        except (urllib.error.URLError, socket.timeout, TimeoutError) as e:
            reason = getattr(e, "reason", e)
            log(f"{alert.agent} {self.key} failed ({type(reason).__name__})")
        except Exception as e:  # a channel must never take the caller down
            log(f"{alert.agent} {self.key} failed ({type(e).__name__})")
        return False


@dataclass(frozen=True)
class Inbound:
    """A message the user sent in the channel; ``reply_to`` is the message it answers."""

    id: str
    text: str
    reply_to: Optional[str] = None


class Interactive(ABC):
    """A channel that also hears back: answers to questions, and messages."""

    @classmethod
    @abstractmethod
    def can_listen(cls, config: Config) -> bool:
        """Everything set that hearing back needs (a bot token, the owner)."""

    @abstractmethod
    def post_alert(self, alert: Alert, sender: Profile) -> bool:
        """Sends an alert and remembers its message for replies."""

    @abstractmethod
    def ask(self, question, sender: Profile) -> Tuple[str, str]:
        """Posts a question; returns its channel and message ids."""

    @abstractmethod
    def poll_answer(self, channel_id: str, message_id: str, question):
        """The answer given so far by reactions, or None."""

    @abstractmethod
    def poll_messages(self, cursor: str) -> Tuple[List[Inbound], str]:
        """The user's messages after ``cursor``, and the new cursor."""

    @abstractmethod
    def start_cursor(self) -> str:
        """Where poll_messages starts: after whatever is there now."""

    @abstractmethod
    def close(self, message_id: str, question, sender: Profile, outcome: str, answered: bool) -> None:
        """Marks a question as settled: ``outcome`` says how, ``answered`` whether from here."""

    @abstractmethod
    def ack(self, message: Inbound, delivered: bool) -> None:
        """Tells the user a message reached its session, or did not."""


_CHANNELS: Dict[str, Type[Channel]] = {}


def channel(cls: Type[Channel]) -> Type[Channel]:
    _CHANNELS[cls.key] = cls
    return cls


def channel_types() -> List[Type[Channel]]:
    return list(_CHANNELS.values())


def listening(config: Config) -> Optional[Channel]:
    """The first configured channel that can hear back, if any."""
    for ch in configured(config):
        if isinstance(ch, Interactive) and ch.can_listen(config):
            return ch
    return None


def configured(config: Config, only: Optional[str] = None) -> List[Channel]:
    return [
        cls(config)
        for cls in channel_types()
        if (only is None or cls.key == only) and cls.state(config) == "on"
    ]


# Registered on import.
from agent_notify.channels import discord, ntfy  # noqa: E402,F401
