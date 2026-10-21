"""Claude Code. Its alerts come from the opencode-sidebar mod, which keeps the
session's switch itself and calls ``agent-notify send claude``."""

from __future__ import annotations

from agent_notify.agents import Agent, agent


@agent
class Claude(Agent):
    key = "claude"
    name = "Claude Code"
    avatar = "https://avatars.githubusercontent.com/u/76263028?s=256"  # github.com/anthropics
