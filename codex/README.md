# Codex CLI

opencode-style Codex CLI: `ctrl-x` leader keys and a session sidebar in a tmux pane.

The Codex TUI has no API for plugins to draw panels, so the sidebar is a script that runs beside Codex in tmux and reads Codex's own state files.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/codex/install.sh)
```

Requirements: Codex CLI with configurable keymaps (0.128 or newer), `jq`, `sqlite3`. Optional: `tmux` with the [tmux component](../tmux/README.md) for `Prefix + C`.

The installer:

1. Appends [`keymap.toml`](keymap.toml) to `~/.codex/config.toml` between `# >>> oh-my-config codex keymap >>>` markers, checks with `codex doctor` that Codex still loads the config, and restores the backup if not. If your config already has `[tui.keymap.global]` or `[tui.keymap.chat]` tables it leaves the file alone and asks you to merge by hand (a second table of the same name would stop Codex from loading).
2. Installs `codex-sidebar` to `~/.local/bin`.
3. Registers with `update.sh`, which keeps `codex-sidebar` current. The keymap block is never rewritten after install, so `/keymap` changes and hand edits stay.

Uninstall: `bash ~/.local/share/oh-my-config/codex/install.sh --uninstall` (removes the block, the script and the registration).

## Keys

Codex's leader is `ctrl-x` (also its default).

| Key | Action |
|---|---|
| `ctrl-x l` | Sessions (agents view: resume, fork, rename, new) |
| `ctrl-x e` | Edit the prompt in `$EDITOR` (`ctrl-g` still works) |
| `ctrl-x a` | Next permission mode |
| `ctrl-x o` | Transcript (`ctrl-t` still works) |
| `ctrl-x f` | Find in transcript (`f3` still works) |
| `ctrl-x v` | Toggle Vim mode |

Codex has no keymap action for the model picker, a new session or the theme picker: use `/model`, `/new` and `/theme`.

The footer is Codex's own `tui.status_line` (built-in items such as `model-with-reasoning`, `git-branch`, `context-used`, `five-hour-limit`, `weekly-limit`); the installer does not touch it.

## Sidebar

`Prefix + C` in tmux opens it to the right of the current pane, and again closes it. `q` in the sidebar closes it too, and it closes by itself with the pane it watches. Without tmux, run `codex-sidebar` in a second terminal in the project folder.

```
Fix login redirect loop                   thread title (/rename wins)
my-project
 main*  ↑1                                branch, dirty, ahead / behind
⎇ main worktree                           or: worktree <name>
gpt-5.5 · high · 8 turns · 1h20m
last turn 21s                             or: ● working

Context
█████████░░░░░░░░░░░░░░░ 40%
338k / 828k tokens · 21519k total

Limits
5h   12% used  ↻ 3h12m
7d    2% used  ↻ 6d1h

Plan                                      last update_plan
✓ read the config
▸ write the migration

Recent                                    last 5 tool calls
✓ exec_command git status
```

It picks the newest thread whose folder is the pane's folder (a CLI thread first when Codex runs in the pane), from `~/.codex/state_*.sqlite`, and reads that thread's rollout file. It redraws when the rollout changes and every 10 seconds for git. Nothing is sent anywhere and no tokens are used.

`codex-sidebar --once [dir]` prints it once.

## Structure

```
codex/
├── install.sh
├── keymap.toml                   leader keymap block for ~/.codex/config.toml
└── scripts/codex-sidebar         the sidebar (installed to ~/.local/bin)
```
