"""agent-notify — Discord / ntfy alerts from coding agents.

  agent-notify setup                          Ask for the channels, save them, send a test
  agent-notify test                           A test from every agent to every channel
  agent-notify status                         Channels, agents and their profiles
  agent-notify send [--wait] <agent> <kind> <title> [body] [meta]
                                              kind: done | wait | error | info; detached unless --wait
  agent-notify hook <agent>                   An agent's CLI hook (its JSON on stdin)
  agent-notify switch <agent> <session> on|off|toggle|get
  agent-notify <agent> on|off|status [dir]    The agent's newest session in dir (default: .)

Channels: ~/.config/oh-my-config/notify.env (mode 600). A channel that is down,
slow or wrong never blocks or breaks the agent: sends run detached with a 10s
limit, hook and send exit 0 and print nothing, and failures only go to
~/.local/state/oh-my-config/notify/notify.log (never a URL or a token).
"""

from __future__ import annotations

import getpass
import json
import os
import socket
import sys
from typing import List, Optional

from agent_notify.agents import agent_types, get_agent
from agent_notify.alert import Alert
from agent_notify.channels import channel_types
from agent_notify.config import CONFIG_PATH, LOG_PATH, Config, log
from agent_notify.notifier import Notifier, take_job
from agent_notify.switches import Switches

HOME = os.path.expanduser("~")


def tilde(path) -> str:
    text = str(path)
    return "~" + text[len(HOME):] if text.startswith(HOME) else text


def usage() -> int:
    print(__doc__.strip())
    return 2


# ─── Sending ─────────────────────────────────────────────


def cmd_send(args: List[str]) -> int:
    wait = bool(args) and args[0] == "--wait"
    if wait:
        args = args[1:]
    if len(args) < 3:
        print("usage: agent-notify send [--wait] <agent> <kind> <title> [body] [meta]", file=sys.stderr)
        return 2
    key, kind, title, *rest = args
    alert = Alert(key, kind, title, *(rest[:2]))
    if not wait:
        try:
            Notifier.deliver_later(alert)
        except Exception as e:  # noqa: BLE001
            log(f"send skipped ({type(e).__name__})")
        return 0
    sent = Notifier().deliver(get_agent(key), alert)
    return 0 if any(sent.values()) else 1


def cmd_hook(args: List[str]) -> int:
    """Never fails the CLI that called it: nothing printed, always 0."""
    try:
        key = args[0] if args else ""
        agent = get_agent(key)
        event = json.loads(sys.stdin.read() or "{}")
        if not isinstance(event, dict):
            return 0
        session = agent.session_of(event)
        switches = Switches(agent.key)
        if session and switches.is_on(session):
            Notifier.handle_later(agent.key, event)
        switches.prune()
    except Exception as e:  # noqa: BLE001
        log(f"hook {args[:1]} skipped ({type(e).__name__})")
    return 0


def cmd_run(args: List[str]) -> int:
    """A detached job (see notifier.detach)."""
    job = take_job(args[0]) if args else None
    if not job:
        return 0
    try:
        notifier = Notifier()
        if "send" in job:
            alert = Alert(**job["send"])
            notifier.deliver(get_agent(alert.agent), alert)
        elif "hook" in job:
            get_agent(job["hook"]).on_hook(job.get("event") or {}, notifier)
    except Exception as e:  # noqa: BLE001
        log(f"job skipped ({type(e).__name__})")
    return 0


# ─── Switches ────────────────────────────────────────────


def cmd_switch(args: List[str]) -> int:
    if len(args) < 2:
        print("usage: agent-notify switch <agent> <session> on|off|toggle|get", file=sys.stderr)
        return 2
    key, session, action = args[0], args[1], (args[2] if len(args) > 2 else "get")
    switches = Switches(key)
    try:
        if action == "on":
            switches.set(session, True)
        elif action == "off":
            switches.set(session, False)
        elif action == "toggle":
            switches.toggle(session)
        elif action != "get":
            print(f"unknown action: {action}", file=sys.stderr)
            return 2
    except ValueError as e:
        print(e, file=sys.stderr)
        return 2
    print("on" if switches.is_on(session) else "off")
    return 0


def cmd_agent(key: str, args: List[str]) -> int:
    action = args[0] if args else "status"
    if action not in ("on", "off", "status"):
        print(f"usage: agent-notify {key} on|off|status [dir]", file=sys.stderr)
        return 2
    folder = args[1] if len(args) > 1 else "."
    session = get_agent(key).session_in(folder)
    if not session:
        print(f"No {key} session in {folder}", file=sys.stderr)
        return 1
    print(f"{key} session {session}: ", end="")
    return cmd_switch([key, session, "get" if action == "status" else action])


# ─── Channels ────────────────────────────────────────────


def cmd_status() -> int:
    config = Config.load()
    any_on = False
    for cls in channel_types():
        state = cls.state(config)
        any_on |= state == "on"
        detail = f"  ({cls(config).describe()})" if state == "on" else ""
        print(f"{cls.key:<8} {state}{detail}")
    print()
    for cls in agent_types():
        sender = cls().profile(config)
        print(f"{cls.key:<8} {sender.name}  {sender.avatar or '(no avatar)'}")
    print()
    print(f"config   {tilde(CONFIG_PATH)}")
    if LOG_PATH.exists() and LOG_PATH.stat().st_size:
        print(f"log      {tilde(LOG_PATH)}")
    return 0 if any_on else 1


def cmd_test() -> int:
    config = Config.load()
    notifier = Notifier(config)
    host = socket.gethostname().split(".")[0]
    ok = False
    for cls in channel_types():
        state = cls.state(config)
        if state == "off":
            continue
        if state == "invalid":
            print(f"{cls.key:<8} ✗ invalid value in {tilde(CONFIG_PATH)}")
            continue
        for agent_cls in agent_types():
            agent = agent_cls()
            alert = Alert(agent.key, "info", "agent-notify test", f"{cls.label} works for {agent.name}.", host)
            if notifier.deliver(agent, alert, only=cls.key).get(cls.key):
                print(f"{cls.key:<8} ✓ {agent.name}")
                ok = True
            else:
                print(f"{cls.key:<8} ✗ {agent.name} failed (see {tilde(LOG_PATH)})")
    if not any(cls.state(config) != "off" for cls in channel_types()):
        print("No channel set: run agent-notify setup")
    return 0 if ok else 1


def cmd_setup() -> int:
    config = Config.load()
    print("agent-notify setup — Enter keeps a value, '-' clears it.")
    print(f"Saved to {tilde(CONFIG_PATH)} (only you can read it).")
    for cls in channel_types():
        print(f"\n{cls.label}")
        for s in cls.settings:
            current = config.get(s.key)
            if s.help:
                print(f"  {s.help}")
            shown = " (set)" if current and s.is_secret else (f" [{current}]" if current else "")
            ask = getpass.getpass if s.is_secret else input
            value = ask(f"  {s.prompt}{shown}: ").strip()
            if value == "-":
                value = ""
            elif not value:
                value = current
            value = value.rstrip("/")
            if value and not s.check(value):
                print(f"  ✗ not a valid {s.prompt.lower()} — nothing saved", file=sys.stderr)
                return 1
            config.set(s.key, value)
    config.save()
    print()
    return cmd_test()


# ─── Main ────────────────────────────────────────────────


def main(argv: Optional[List[str]] = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    command, rest = (args[0], args[1:]) if args else ("", [])
    try:
        if command == "send":
            return cmd_send(rest)
        if command == "hook":
            return cmd_hook(rest)
        if command == "_run":
            return cmd_run(rest)
        if command == "switch":
            return cmd_switch(rest)
        if command == "setup":
            return cmd_setup()
        if command == "test":
            return cmd_test()
        if command == "status":
            return cmd_status()
        if command in {cls.key for cls in agent_types()}:
            return cmd_agent(command, rest)
        if command in ("", "-h", "--help", "help"):
            return usage()
    except (KeyboardInterrupt, EOFError):
        print()
        return 130
    print(f"agent-notify: unknown command {command} (see --help)", file=sys.stderr)
    return 2

