# Claude Code

opencode-style Claude Code: a session sidebar and `ctrl+x` leader keys, as a Claude Code plugin (a "mod") plus a few keybindings.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/claude/install.sh)
```

Then run `/reload-plugins` in any Claude Code session that was already open.

Requirements: Claude Code 2.1.287 or newer (plugin hooks modules), `jq`. Optional: `git` (branch / worktree), `gh` (PR status).

The installer:

1. Clones this repo to `~/.local/share/oh-my-config` (shared with the other components' auto-update).
2. Merges the bindings in [`keybindings.json`](keybindings.json) into `~/.claude/keybindings.json`. A chord you already bind keeps your action; the old file is kept as `keybindings.json.bak.<timestamp>`.
3. Adds that clone as the `oh-my-config` plugin marketplace and installs `opencode-sidebar@oh-my-config`. The plugin is read from the clone itself, so `update.sh` keeps it current.
4. Installs [`agent-notify`](../notify/README.md) to `~/.local/bin` for Discord / ntfy alerts (needs Python 3.9+). Run `agent-notify setup` once to add a channel.

Uninstall: `bash ~/.local/share/oh-my-config/claude/install.sh --uninstall` (removes the plugin, the marketplace and only the bindings it added).

Only the plugin alone, without the keybindings (the leader keys then do nothing):

```
/plugin install opencode-sidebar --marketplace rapidrabbit76/oh-my-config
```

## Keys

| Key | Action |
|---|---|
| `ctrl+x l` | Session list (`/resume`) |
| `ctrl+x n` | New session (`/clear`) |
| `ctrl+x t` | Theme (`/theme`) |
| `ctrl+x m` | Model picker |
| `ctrl+x e` | Edit the prompt in `$EDITOR` |
| `ctrl+x a` | Cycle mode (default → accept edits → plan) |
| `ctrl+x tab` | Focus the sidebar, so its keys work (Esc gives the prompt back) |
| `ctrl+x q` | Quit |

`keybindings.json` can only bind Claude Code's own actions, not slash commands. So `ctrl+x l`, `n` and `t` are bound to diff-panel actions that do nothing at the prompt, and the plugin draws a hint row above the prompt whose buttons claim those actions and run `/resume`, `/clear` and `/theme`. While the diff panel is open those three chords do their diff-panel job instead. `ctrl+x tab` (Claude Code's own focuses the hint row) is bound the same way, to a diff-dialog action, and opens the sidebar with the keys.

## Sidebar

`/sidebar` toggles it. In the fullscreen renderer (`/tui fullscreen`) it docks beside the transcript, and opens by itself when the terminal is at least 144 columns wide.

```
Fix login redirect loop                       session title (/rename wins)
my-project
 main*  ↑1                                    branch, dirty, ahead / behind
#12 open · CI ✓                               PR of this branch (gh)
⎇ main worktree                               or: worktree <name>
opus-5-5 · 14 turns · 1h20m
last turn 48s · 7 tools

[ compact ] [ rename ] [ export ]             click, or c / r / e while focused (ctrl+x tab)
n: ○ alerts Discord / ntfy                    n, or /notify: alerts for this session
a: ○ away answer in Discord                   a, or /away: answer and prompt from Discord
s: ● sound peon-ping                          s, or /sound: mute / unmute peon-ping (when installed)

Context
████████░░░░░░  52%
104k / 200k tokens · $1.23
■ Messages 52k                                what fills the window (/context)
■ System tools 31k

Limits
5h   6% used  ↻ 3h12m                         used, and time until reset
7d  41% used  ↻ 3d2h

MCP 6/9
✗ playwright                                  configured servers with no tools

Todo
▸ current task

Recent                                        last 5 tool calls
✓ Bash git status
```

## Alerts

`○ alerts` in the sidebar, or `/notify`, turns on Discord / ntfy alerts for this session: one when a turn ends (not an interrupted one, nor a subagent's), and one when a permission prompt or a question has waited 30 seconds for you. Channels are set with `agent-notify setup`; see [notify](../notify/README.md). A channel that is down never slows or breaks the session.

`○ away`, or `/away`, goes further: questions and approvals also go to Discord to answer there (react, or reply), and a reply to an alert becomes a prompt in this session. It needs a Discord bot; see [Answering from Discord](../notify/README.md#answering-from-discord-away).

## Refresh

It refreshes every 15 seconds and after each turn (the PR every minute, or right after `git push` / `gh pr`). It adds no tokens: everything is read from the engine or local commands, and the context breakdown is estimated locally.

## Structure

```
claude/
├── install.sh
├── keybindings.json              ctrl+x bindings merged into ~/.claude/keybindings.json
└── opencode-sidebar/             the plugin (listed in ../.claude-plugin/marketplace.json)
    ├── .claude-plugin/plugin.json
    ├── hooks/hooks.json
    ├── hooks/register.tsx        sidebar pane, hint row, /sidebar, /notify
    ├── tests/notify.test.tsx     claude plugin test claude/opencode-sidebar
    └── types/index.d.ts          its state contract
```
