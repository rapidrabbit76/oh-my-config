# Yazi Configuration

Claude-inspired yazi file manager setup with 26 plugins, cross-platform support (macOS / Linux / SSH), and a portable installer.

---

## Install

### One-liner (curl)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/yazi/install.sh)
```

### One-liner (wget)

```bash
bash <(wget -qO- https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/yazi/install.sh)
```

### From source

```bash
git clone https://github.com/rapidrabbit76/oh-my-config.git
cd oh-my-config/yazi
./install.sh
```

### Uninstall

```bash
cd oh-my-config/yazi
./install.sh --uninstall
```

---

## What the installer does

1. Check for yazi / ya / brew
2. Audit system dependencies — show all missing at once, offer one-click install
3. Backup existing `~/.config/yazi/` (timestamped)
4. Copy config files + deploy `smart-open` to `~/.local/bin/`
5. Install 26 yazi packages (9 official + 17 third-party) + claude-inspired flavor
6. Write shell integration (`y` wrapper) to `.zshrc` / `.bashrc`

---

## Plugins

### Official (yazi-rs) — 9

| Plugin       | Description                |
| ------------ | -------------------------- |
| smart-filter | Real-time fuzzy filter     |
| git          | Git status in file list    |
| jump-to-char | Quick jump by first char   |
| chmod        | Interactive permission edit |
| diff         | Side-by-side file diff     |
| toggle-pane  | Maximize/restore pane      |
| full-border  | Full UI border             |
| mount        | Disk mount/unmount manager |
| mime-ext     | Fast MIME detection by extension |

### Third-party — 17

| Plugin           | Description                          |
| ---------------- | ------------------------------------ |
| ouch             | Archive compress/extract/preview     |
| hexyl            | Binary hex preview (fallback)        |
| lazygit          | Lazygit integration                  |
| recycle-bin      | Trash management                     |
| bookmarks        | Vim-style persistent bookmarks       |
| duckdb           | CSV/TSV/Parquet table preview        |
| searchjump       | Flash.nvim-style label jump          |
| autosession      | Auto session persistence             |
| projects         | Project state save/load              |
| what-size        | Directory/selection size calc        |
| fr               | File content search (ripgrep + bat)  |
| yatline          | Customizable status/header bar       |
| dual-pane        | True dual-pane navigation (MC-style) |
| bypass           | Auto-skip single-child directories   |
| relative-motions | Vim-style `5j`/`3k` relative jumps   |
| restore          | Undo/recover trashed files           |
| eza-preview      | Directory preview with eza           |

### Flavor

| Package         | Description                |
| --------------- | -------------------------- |
| [claude-inspired](https://github.com/rapidrabbit76/claude-inspired) | Claude warm orange/beige theme |

### Manual

| Plugin    | Description              |
| --------- | ------------------------ |
| mediainfo | Audio metadata previewer |

---

## Keybindings

### File Operations

| Key     | Action                |
| ------- | --------------------- |
| `m a`   | Toggle custom linemode |
| `F`     | Smart filter          |
| `f`     | Jump to char          |
| `i`     | Search jump (label)   |
| `T`     | Toggle max preview    |
| `c a`   | Compress (ouch)       |
| `c m`   | Chmod                 |
| `c d`   | Diff                  |
| `z s`   | Calculate size        |
| `d d`   | Trash (via trash-cli) |
| `d D`   | Permanently delete    |
| `d u`   | Restore last deleted  |
| `d U`   | Restore (interactive) |
| `R b`   | Recycle bin           |
| `M t`   | Mount/unmount         |

### Search & Navigation

| Key       | Action                         |
| --------- | ------------------------------ |
| `g f`     | Search file contents (ripgrep) |
| `\ \`     | Toggle dual-pane               |
| `\ Tab`   | Focus other dual-pane          |
| `1`-`9`   | Relative motion (vim count)    |
| `e t`     | Toggle eza tree/list preview   |
| `e -`/`_` | Inc/dec eza tree level         |
| `e *`     | Toggle hidden in preview       |

### Git

| Key   | Action  |
| ----- | ------- |
| `g i` | Lazygit |

### Bookmarks

| Key   | Action           |
| ----- | ---------------- |
| `b s` | Save bookmark    |
| `b j` | Jump to bookmark |
| `b d` | Delete bookmark  |
| `b D` | Delete all       |

### Projects & Sessions

| Key   | Action            |
| ----- | ----------------- |
| `P s` | Save project      |
| `P l` | Load project      |
| `P P` | Load last project |
| `P d` | Delete project    |
| `Q`   | Save session & quit |

### Defaults (overridden)

| Key     | Action                                   |
| ------- | ---------------------------------------- |
| `t`     | New tab                                  |
| `1`-`9` | Relative motion (overrides tab switch)   |
| `[`/`]` | Prev/next tab                            |
| `q`     | Quit                                     |

---

## System Dependencies

| Tool              | Used by                               |
| ----------------- | ------------------------------------- |
| hexyl             | hexyl.yazi                            |
| trash-cli         | trash (dd), restore (du/dU)           |
| lazygit           | lazygit.yazi                          |
| duckdb            | duckdb.yazi                           |
| mediainfo         | mediainfo.yazi                        |
| ffmpegthumbnailer | Video thumbnail preview               |
| ouch              | ouch.yazi (compress/extract/preview)  |
| chafa             | smart-open (terminal image for SSH)   |
| eza               | eza-preview.yazi (directory preview)  |

All dependencies are auto-installed via `brew` / `linuxbrew` during setup.

---

## Cross-platform

| Environment     | Opener          | Image viewer |
| --------------- | --------------- | ------------ |
| macOS (local)   | `open`          | native       |
| Linux (local)   | `xdg-open`     | native       |
| SSH (no display) | terminal fallback | `chafa`   |

Handled by [`smart-open`](scripts/smart-open) — deployed to `~/.local/bin/` by the installer.

---

## Shell Integration

The installer writes a `y()` cd-on-exit wrapper to `.zshrc` / `.bashrc`.
Use `y` instead of `yazi` — your shell `cd`s to the last directory when you quit.

---

## Requirements

- **Yazi** >= 25.x (tested on 26.1.22)
- **Homebrew** or **Linuxbrew**
- Terminal with true color support
