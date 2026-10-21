"""Who alerts come from. An agent is one subclass registered with ``@agent``.

The least an agent needs is a ``key`` (what ``agent-notify send <key>`` and
the config use), a ``name`` and an ``avatar``. One whose CLI runs hooks also
implements ``session_of`` and ``on_hook``: ``agent-notify hook <key>`` reads
the hook's JSON, drops it unless that session's switch is on, and hands it
to ``on_hook`` in a detached process, so the CLI never waits on a channel.
One that can name its newest session in a folder implements ``session_in``,
which ``agent-notify <key> on|off|status [dir]`` uses.

The config may override a profile: ``<KEY>_NAME`` and ``<KEY>_AVATAR``
(``CODEX_NAME=Codex @ work``).
"""

from __future__ import annotations

from typing import ClassVar, Dict, List, Mapping, Optional, Type

from agent_notify.channels import Profile
from agent_notify.config import Config
from agent_notify.notifier import Notifier


class Agent:
    key: ClassVar[str]
    name: ClassVar[str]
    avatar: ClassVar[str] = ""
    # The hook events on_hook acts on, for the docs and for installers.
    hook_events: ClassVar[tuple] = ()

    def profile(self, config: Config) -> Profile:
        prefix = self.key.upper().replace("-", "_")
        return Profile(
            name=config.get(f"{prefix}_NAME") or self.name,
            avatar=config.get(f"{prefix}_AVATAR", self.avatar),
        )

    def session_of(self, event: Mapping) -> Optional[str]:
        """The session a hook event belongs to."""
        value = event.get("session_id")
        return value if isinstance(value, str) else None

    def session_in(self, folder: str) -> Optional[str]:
        """The newest session in a folder, where the agent can tell."""
        return None

    def on_hook(self, event: Mapping, notifier: Notifier) -> None:
        """Acts on one hook event of a session with alerts on. Runs detached."""


class GenericAgent(Agent):
    """Any key with no class of its own: ``send`` still works, under that name."""

    def __init__(self, key: str):
        self.key = key  # type: ignore[misc]
        self.name = key  # type: ignore[misc]


_AGENTS: Dict[str, Type[Agent]] = {}


def agent(cls: Type[Agent]) -> Type[Agent]:
    _AGENTS[cls.key] = cls
    return cls


def get_agent(key: str) -> Agent:
    cls = _AGENTS.get(key)
    return cls() if cls else GenericAgent(key)


def agent_types() -> List[Type[Agent]]:
    return list(_AGENTS.values())


# Registered on import.
from agent_notify.agents import claude, codex  # noqa: E402,F401
