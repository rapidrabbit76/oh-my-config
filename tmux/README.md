# Tmux Configuration

Catppuccin Mocha themed tmux setup with enhanced status bar, pomodoro timer, and cross-platform support (macOS / Linux).

---

## Install

### One-liner (curl)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/tmux/install.sh)
```

### One-liner (wget)

```bash
bash <(wget -qO- https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/tmux/install.sh)
```

### From source

```bash
git clone https://github.com/rapidrabbit76/oh-my-config.git
cd oh-my-config/tmux
./install.sh
```

### Uninstall

```bash
cd oh-my-config/tmux
./install.sh --uninstall
```

---

## What the installer does

1. Check for tmux / git / Nerd Font
2. Install tmux if missing (brew / apt)
3. Backup existing `~/.tmux.conf` (timestamped)
4. Copy config + status bar scripts to `~/.tmux/scripts/`
5. Install TPM (Tmux Plugin Manager)
6. Reload config if tmux is running

---

## Plugins

| Plugin | Description |
| --- | --- |
| [catppuccin/tmux](https://github.com/catppuccin/tmux) | Catppuccin Mocha theme |
| [tmux-cpu](https://github.com/tmux-plugins/tmux-cpu) | CPU & RAM percentage |
| [tmux-battery](https://github.com/tmux-plugins/tmux-battery) | Battery status |
| [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) | Session save/restore |
| [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) | Auto session save |

> After install, press **Prefix + I** (Shift+i) to install plugins via TPM.

---

## Status Bar

```
 session │ windows │ dir │  git │ 󰛳 ↓1K ↑0B (2.4G) │  CPU │  RAM │ 󰋊 disk │ 🔋 bat │ 󰩟 IP │ 🍅 pomo │  date
```

| Segment | Color (Mocha) | Script |
| --- | --- | --- |
| Git branch | Green `#a6e3a1` | inline |
| Network speed + bandwidth | Teal `#94e2d5` | `net_speed.sh` |
| CPU | Blue `#89b4fa` | tmux-cpu plugin |
| RAM | Yellow `#f9e2af` | tmux-cpu plugin |
| Disk usage | Peach `#fab387` | `disk_usage.sh` |
| Battery | Pink `#f5c2e7` | tmux-battery plugin |
| Public IP | Lavender `#b4befe` | `public_ip.sh` (5min cache) |
| Pomodoro | Red `#f38ba8` | `pomodoro.sh` |

---

## Keybindings

### Prefix

| Key | Action |
| --- | --- |
| `Ctrl+Space` | Primary prefix |
| `Ctrl+b` | Secondary prefix |

### Pane Navigation (no prefix)

| Key | Action |
| --- | --- |
| `Option+h` | Move left |
| `Option+j` | Move down |
| `Option+k` | Move up |
| `Option+l` | Move right |

### Window & Pane

| Key | Action |
| --- | --- |
| `Prefix + %` | Split horizontal |
| `Prefix + "` | Split vertical |
| `Prefix + L` | Last window |
| `Prefix + Tab` | Yazi file explorer (50% split) |
| `Prefix + r` | Reload config |

### Pomodoro Timer

| Key | Action |
| --- | --- |
| `Prefix + P` | Start/stop toggle (25min work) |
| `Prefix + O` | Stop timer |

Work → Break transition is automatic (25min work → 5min break).

### Copy Mode (vi)

| Key | Action |
| --- | --- |
| `v` | Begin selection |
| `y` | Copy to clipboard |
| `Enter` | Copy to clipboard |
| Mouse drag | Copy (no clear) |
| Scroll wheel | 5 lines per tick |

---

## Requirements

- **tmux** >= 3.2
- **git** (for TPM)
- **Nerd Font** (for icons) — e.g., Hack Nerd Font, D2Coding Nerd Font
- Terminal with true color support
