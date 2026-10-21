# agent-notify

Discord and ntfy alerts from coding agents: when a turn ends, and when one has waited 30 seconds on a permission prompt or a question. Each agent sends under its own name and profile picture, so Claude Code and Codex read as two different senders in the same channel.

Alerts are off until you turn them on, per session:

- **Claude Code**: `[ ] alerts` in the sidebar (or `n` while it is focused), or `/notify`.
- **Codex**: `n` in the tmux sidebar (`Prefix + C`), or `agent-notify codex on` in the project folder.

The [claude](../claude/README.md) and [codex](../codex/README.md) components install it: a launcher at `~/.local/bin/agent-notify` that runs this folder from the oh-my-config clone, which `update.sh` keeps current. It needs Python 3.9 or newer, standard library only.

## Setup

```bash
agent-notify setup     # asks for a Discord webhook URL and/or an ntfy topic URL, then sends a test
agent-notify test      # a test from every agent to every channel
agent-notify status    # channels, agents and their profiles
```

- **Discord**: channel settings → Integrations → Webhooks → New Webhook → Copy Webhook URL.
- **ntfy**: `https://ntfy.sh/<a long random topic>` (anyone who knows a topic on ntfy.sh can read it, so make it hard to guess), or a topic on your own server, with an access token if it needs one. Subscribe to it in the ntfy app.

Either one, or both. They are saved to `~/.config/oh-my-config/notify.env` (mode 600), read as plain `KEY=value` lines and never run, and nothing of them goes into this repo:

```
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/…
NTFY_URL=https://ntfy.sh/…
NTFY_TOKEN=
CODEX_NAME=Codex @ work           optional: an agent's name or picture of your own
CLAUDE_AVATAR=https://…/me.png
```

## What an alert looks like

```
[avatar] Claude Code
✅ Done · Fix login redirect loop          session title
Fixed the redirect loop: …                 the answer, cut at 1000 characters
my-project · main · 2m 14s                 folder, branch, how long the turn took

[avatar] Codex
⏸️ Waiting for approval · Migrate the db
Bash: git push origin main
```

- **Discord**: the webhook posts as the agent (its `username` and `avatar_url`), with mentions off, so an `@everyone` in an answer pings nobody.
- **ntfy**: the title starts with the agent's name and the picture is the notification icon (the Android app shows icons; iOS shows the name).

The default pictures are the GitHub avatars of the anthropics and openai organizations.

## Answering from Discord (away)

Switch a session to **away** and Discord works both ways:

| In the session | In Discord |
|---|---|
| A question (Claude's AskUserQuestion) | The question with 1️⃣ 2️⃣ … : react to pick (several, then ✅, for a multi-select), or reply with your own answer. The terminal's dialog stays open; whichever answers first wins. |
| An approval (Claude's permission prompt, Codex's PermissionRequest) | ✅ allow, ❌ deny, or reply to deny with a message (`ok` / `ㅇㅇ` allow). The terminal's prompt shows after 10 minutes with no answer. |
| — | Reply to an alert: the text is sent to that session as a prompt (Claude Code: as a message; Codex: typed into its tmux pane). A message that is not a reply goes to the newest away session. 📨 under it: delivered; ⚠️: no away session took it. |

Switching: Claude Code `[ ] away` in the sidebar (or `a`) or `/away`; Codex `a` in the tmux sidebar, or `agent-notify codex away` in the project folder.

It needs a Discord **bot** besides the webhook: the webhook still posts (each agent's name and avatar), the bot reads your reactions and replies.

1. discord.com/developers → New Application → **Bot** → Reset Token. Under Privileged Gateway Intents turn on **Message Content Intent**.
2. OAuth2 → URL Generator → `bot`, with View Channels, Read Message History, Add Reactions, Send Messages; invite it to the server of the alert channel.
3. `agent-notify setup` → paste the bot token (hidden), then `agent-notify pair` and react ✅ to its message: only that account's answers count from then on.

A background process, `agent-notify bridge`, reads the channel every 3 seconds (Discord's REST API, no open port) while a session is away or a question waits, and exits two minutes after the last one. `agent-notify bridge status|stop`.

Safety: only the paired account is heard; only a session switched to away takes a prompt; everything passes through files only you can read, removed once used. Anyone who can post as that account can approve tool use and prompt your agents, so keep the account and the bot token to yourself.

## When a channel fails

Nothing in the agent waits on it or breaks:

- A send runs in a detached process with a 10 second limit; the caller returns at once. What it sends goes to that process through a file only you can read, not its command line.
- `hook` and `send` always exit 0 and print nothing, even with Python missing. To a Codex `PermissionRequest` hook no output means "no decision", so the approval prompt shows as usual.
- A failure is one line in `~/.local/state/oh-my-config/notify/notify.log`: the agent, the channel and the HTTP status or error kind, never the URL or the token.

## Codex hooks

`codex/install.sh` adds `agent-notify hook codex` for `Stop` and `PermissionRequest` to `~/.codex/config.toml`, in its own marked block (not `~/.codex/hooks.json`: Codex skips that whole file when it holds a field it does not know, which some tools leave there). Codex runs a new hook only once you trust it: open `/hooks` in Codex and trust the two `agent-notify hook codex` entries. The hook does nothing for a thread whose alerts are off. A permission request is sent if the thread's rollout file has not moved for 30 seconds (an answer writes to it).

```
agent-notify codex on|off|status [dir]          the newest Codex thread in dir
agent-notify switch <agent> <session> on|off|toggle|get
```

A switch is an empty file, `~/.local/state/oh-my-config/notify/on/<agent>/<session>`, so a sidebar can show it with a file test.

## Adding an agent

```
agent_notify/
├── cli.py                 the commands
├── alert.py               Alert: kind (done / wait / error / info), title, body, meta
├── notifier.py            Notifier: every configured channel, now or detached
├── switches.py            Switches: per-session on / off
├── config.py              notify.env, paths, the log
├── agents/                Agent (base) + @agent registry
│   ├── claude.py
│   └── codex.py
└── channels/              Channel (base) + @channel registry
    ├── discord.py
    └── ntfy.py
```

An agent is one file in `agents/` (and one name in the import at the bottom of `agents/__init__.py`):

```python
from agent_notify.agents import Agent, agent
from agent_notify.alert import Alert

@agent
class Gemini(Agent):
    key = "gemini"                      # agent-notify send gemini …, GEMINI_NAME / GEMINI_AVATAR
    name = "Gemini CLI"
    avatar = "https://…/gemini.png"     # a public PNG or JPEG
    hook_events = ("AfterAgent",)

    # Only for a CLI with hooks: `agent-notify hook gemini` reads the hook's JSON,
    # keeps it if that session's switch is on, and calls this in a detached process.
    def on_hook(self, event, notifier):
        if event.get("hook_event_name") == "AfterAgent":
            notifier.deliver(self, Alert(self.key, "done", "Done", event.get("prompt_response", "")))
```

An agent with no hooks needs only `key`, `name` and `avatar`; whatever drives it calls `agent-notify send <key> done "<title>" "<body>" "<meta>"`. A key with no class still sends, under the key as its name. A channel is the same shape in `channels/`: `settings` (what setup asks) and `request()` (the HTTP POST).

Tests: `python3 -m unittest discover -s notify/tests` from the repo root.
