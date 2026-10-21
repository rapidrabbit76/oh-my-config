"""Who alerts come from. An agent is one subclass registered with ``@agent``.

The least an agent needs is a ``key`` (what ``agent-notify send <key>`` and
the config use), a ``name`` and an ``avatar``. One whose CLI runs hooks also
implements ``session_of`` and ``on_hook``: ``agent-notify hook <key>`` reads
the hook's JSON, drops it unless that session's switch is on, and hands it
to ``on_hook`` in a detached process, so the CLI never waits on a channel.
One that can name its newest session in a folder implements ``session_in``,
which ``agent-notify <key> on|off|away|status [dir]`` uses.

Two-way (a session switched to ``away``): ``on_hook_sync`` may answer a hook
itself, waiting for an answer from Discord (an approval, say), and
``deliver_text`` hands a message from Discord to the session as a prompt.

The config may override a profile: ``<KEY>_NAME`` and ``<KEY>_AVATAR``
(``CODEX_NAME=Codex @ work``).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import ClassVar, Dict, List, Mapping, Optional, Type

from agent_notify.channels import Profile
from agent_notify.config import Config
from agent_notify.notifier import Notifier


@dataclass(frozen=True)
class HookReply:
    """What ``on_hook_sync`` did: ``output`` is printed for the CLI to read;
    ``handled`` keeps the event from also going to ``on_hook``."""

    output: Optional[Dict] = None
    handled: bool = False


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

    def locate(self, folder: str) -> Dict[str, str]:
        """What away mode keeps with a session started from ``folder`` (Codex: its tmux pane)."""
        return {}

    def on_hook(self, event: Mapping, notifier: Notifier) -> None:
        """Acts on one hook event of a session with alerts on. Runs detached."""

    def on_hook_sync(self, event: Mapping, notifier: Notifier, mode: str) -> HookReply:
        """Runs in the hook itself, before ``on_hook``; the CLI waits for it."""
        return HookReply()

    def deliver_text(self, session: str, text: str, info: Mapping) -> bool:
        """Hands a message from Discord to an away session. By default it waits
        in the session's inbox (``agent-notify inbox``) for the agent to read."""
        from agent_notify import interactive

        interactive.to_inbox(self.key, session, text)
        return True


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
