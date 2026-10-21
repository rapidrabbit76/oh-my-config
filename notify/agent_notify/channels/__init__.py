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


_CHANNELS: Dict[str, Type[Channel]] = {}


def channel(cls: Type[Channel]) -> Type[Channel]:
    _CHANNELS[cls.key] = cls
    return cls


def channel_types() -> List[Type[Channel]]:
    return list(_CHANNELS.values())


def configured(config: Config, only: Optional[str] = None) -> List[Channel]:
    return [
        cls(config)
        for cls in channel_types()
        if (only is None or cls.key == only) and cls.state(config) == "on"
    ]


# Registered on import.
from agent_notify.channels import discord, ntfy  # noqa: E402,F401
