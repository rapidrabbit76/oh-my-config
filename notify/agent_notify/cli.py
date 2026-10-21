"""agent-notify — Discord / ntfy alerts from coding agents.

  agent-notify setup                          Ask for the channels, save them, send a test
  agent-notify test                           A test from every agent to every channel
  agent-notify status                         Channels, agents and their profiles
  agent-notify send [--wait] [--session S] <agent> <kind> <title> [body] [meta]
                                              kind: done | wait | error | info; detached unless --wait
  agent-notify hook <agent>                   An agent's CLI hook (its JSON on stdin)
  agent-notify switch <agent> <session> off|alerts|away|toggle|get [--pane %N]
  agent-notify <agent> off|alerts|away|status [dir]
                                              The agent's newest session in dir (default: .)

Answering from Discord (a bot token, then `agent-notify pair`; sessions in away):
  agent-notify pair                           Link your Discord account: react ✅ to the bot's message
  agent-notify ask                            Post a question (JSON on stdin), print the answer (JSON)
  agent-notify cancel <token>                 That question was answered in the terminal
  agent-notify inbox <agent> <session>        Messages from Discord for the session (JSON), taken
  agent-notify bridge [status|start|stop]     The process that reads answers and messages

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


def take_flag(args: List[str], flag: str) -> str:
    """Removes ``flag value`` from args and returns the value ("" if absent)."""
    if flag in args:
        i = args.index(flag)
        value = args[i + 1] if i + 1 < len(args) else ""
        del args[i : i + 2]
        return value
    return ""


def cmd_send(args: List[str]) -> int:
    args = list(args)
    wait = "--wait" in args
    if wait:
        args.remove("--wait")
    session = take_flag(args, "--session")
    if len(args) < 3:
        print("usage: agent-notify send [--wait] [--session S] <agent> <kind> <title> [body] [meta]", file=sys.stderr)
        return 2
    key, kind, title, *rest = args
    body, meta = (rest + ["", ""])[:2]
    alert = Alert(key, kind, title, body, meta, session)
    if not wait:
        try:
            Notifier.deliver_later(alert)
        except Exception as e:  # noqa: BLE001
            log(f"send skipped ({type(e).__name__})")
        return 0
    sent = Notifier().deliver(get_agent(key), alert)
    return 0 if any(sent.values()) else 1


def cmd_hook(args: List[str]) -> int:
    """Never fails the CLI that called it: always 0, and nothing printed but
    an answer the agent's hook protocol reads (an approval from Discord)."""
    try:
        key = args[0] if args else ""
        agent = get_agent(key)
        event = json.loads(sys.stdin.read() or "{}")
        if not isinstance(event, dict):
            return 0
        session = agent.session_of(event)
        switches = Switches(agent.key)
        mode = switches.mode(session) if session else "off"
        if mode != "off":
            notifier = Notifier()
            reply = agent.on_hook_sync(event, notifier, mode)
            if reply.output is not None:
                print(json.dumps(reply.output))
            if not reply.handled:
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
        elif job.get("bridge"):
            from agent_notify.bridge import Bridge

            Bridge(notifier.config).run()
    except Exception as e:  # noqa: BLE001
        log(f"job skipped ({type(e).__name__})")
    return 0


# ─── Switches ────────────────────────────────────────────


def cmd_switch(args: List[str]) -> int:
    args = list(args)
    pane = take_flag(args, "--pane")
    if len(args) < 2:
        print("usage: agent-notify switch <agent> <session> off|alerts|away|toggle|get [--pane %N]", file=sys.stderr)
        return 2
    key, session, action = args[0], args[1], (args[2] if len(args) > 2 else "get")
    action = {"on": "alerts"}.get(action, action)
    switches = Switches(key)
    try:
        if action in ("off", "alerts", "away"):
            switches.set_mode(session, action, pane=pane)
        elif action == "toggle":
            switches.toggle(session)
        elif action != "get":
            print(f"unknown action: {action}", file=sys.stderr)
            return 2
    except ValueError as e:
        print(e, file=sys.stderr)
        return 2
    mode = switches.mode(session)
    if mode == "away":
        from agent_notify import bridge

        bridge.ensure()
    print(mode)
    return 0


def cmd_agent(key: str, args: List[str]) -> int:
    action = args[0] if args else "status"
    if action not in ("on", "off", "alerts", "away", "status"):
        print(f"usage: agent-notify {key} off|alerts|away|status [dir]", file=sys.stderr)
        return 2
    folder = args[1] if len(args) > 1 else "."
    session = get_agent(key).session_in(folder)
    if not session:
        print(f"No {key} session in {folder}", file=sys.stderr)
        return 1
    print(f"{key} session {session}: ", end="")
    extra = []
    if action == "away":
        pane = get_agent(key).locate(folder).get("pane", "")
        extra = ["--pane", pane] if pane else []
    return cmd_switch([key, session, "get" if action == "status" else action, *extra])


# ─── Answering from Discord ──────────────────────────────


def cmd_ask() -> int:
    """A question as JSON on stdin ({agent, session, kind, title, body, options,
    descriptions, multi, meta, timeout, token, resume, final}); prints the
    answer as JSON; {"pending": id} when ``final`` is false and the time ran
    out (call again with ``resume: id``); {} when there is none (timed out,
    answered in the terminal, nothing can hear back)."""
    from agent_notify import bridge
    from agent_notify.interactive import Question

    result = {}
    try:
        data = json.loads(sys.stdin.read() or "{}")
        timeout = float(data.pop("timeout", 3600))
        token = str(data.pop("token", ""))
        resume = str(data.pop("resume", "") or "")
        final = bool(data.pop("final", True))
        fields = {k: data[k] for k in Question.__dataclass_fields__ if k in data}
        try:
            answer = bridge.ask(Question(**fields), timeout, token, resume, final)
        except bridge.StillWaiting as wait:
            answer, result = None, {"pending": wait.message_id}
        if answer:
            result = {"kind": answer.kind, "value": answer.value, "values": answer.values}
    except Exception as e:  # noqa: BLE001
        log(f"ask skipped ({type(e).__name__})")
    print(json.dumps(result, ensure_ascii=False))
    return 0


def cmd_cancel(args: List[str]) -> int:
    from agent_notify import interactive

    try:
        interactive.cancel(args[0])
    except (IndexError, ValueError):
        return 2
    return 0


def cmd_inbox(args: List[str]) -> int:
    from agent_notify import interactive

    texts = []
    try:
        texts = interactive.take_inbox(args[0], args[1])
    except (IndexError, ValueError):
        pass
    print(json.dumps(texts, ensure_ascii=False))
    return 0


def cmd_bridge(args: List[str]) -> int:
    from agent_notify import bridge

    action = args[0] if args else "status"
    if action == "start":
        bridge.ensure()
    elif action == "stop":
        print("stopped" if bridge.stop() else "not running")
        return 0
    elif action == "run":
        return bridge.Bridge().run()
    print("running" if bridge.is_running() else "not running")
    return 0


def cmd_pair() -> int:
    """Links the Discord account that reacts ✅ to the bot's message."""
    import time

    from agent_notify.channels.discord import BOT_TOKEN, WEBHOOK
    from agent_notify.discord_api import Discord as Api
    from agent_notify.discord_api import DiscordError

    config = Config.load()
    webhook, token = config.get("DISCORD_WEBHOOK_URL"), config.get("DISCORD_BOT_TOKEN")
    if not WEBHOOK.match(webhook) or not BOT_TOKEN.match(token):
        print("Set the Discord webhook and the bot token first: agent-notify setup", file=sys.stderr)
        return 1
    api = Api(token)
    try:
        bot = str(api.me()["id"])
        body = {
            "username": "agent-notify",
            "allowed_mentions": {"parse": []},
            "embeds": [{"title": "🔗 Pair agent-notify", "description": "React ✅ to this message within 2 minutes.\nOnly that account's answers will count.", "color": 0x5865F2}],
        }
        posted = api.webhook_post(webhook, body)
        channel_id, message_id = str(posted["channel_id"]), str(posted["id"])
        api.react(channel_id, message_id, "✅")
    except DiscordError as e:
        print(f"Discord refused ({e}). Is the bot in the server, with View Channel, Read Message History and Add Reactions?", file=sys.stderr)
        return 1
    print("Waiting for your ✅ on the message in Discord…")
    deadline = time.time() + 120
    while time.time() < deadline:
        try:
            people = [u for u in api.reactors(channel_id, message_id, "✅") if u != bot]
        except DiscordError:
            people = []
        if people:
            config.set("DISCORD_OWNER_ID", people[0])
            config.save()
            done = dict(body, embeds=[{"title": "✅ Paired", "description": "Answers from this account now reach your agents.", "color": 0x57F287}])
            del done["username"]
            try:
                api.webhook_edit(webhook, message_id, done)
            except DiscordError:
                pass
            print("Paired.")
            return 0
        time.sleep(2)
    print("No ✅ in 2 minutes; run agent-notify pair again.", file=sys.stderr)
    return 1


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
            if not s.is_asked:
                continue
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
        if command == "ask":
            return cmd_ask()
        if command == "cancel":
            return cmd_cancel(rest)
        if command == "inbox":
            return cmd_inbox(rest)
        if command == "bridge":
            return cmd_bridge(rest)
        if command == "pair":
            return cmd_pair()
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

