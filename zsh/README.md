# Zsh Configuration

Modern zsh environment with oh-my-zsh, starship prompt, and 18 modern CLI replacements. Cross-platform (macOS / Linux).

---

## Install

### One-liner (curl)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/zsh/install.sh)
```

### One-liner (wget)

```bash
bash <(wget -qO- https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/zsh/install.sh)
```

### From source

```bash
git clone https://github.com/rapidrabbit76/oh-my-config.git
cd oh-my-config/zsh
./install.sh
```

### Uninstall

```bash
cd oh-my-config/zsh
./install.sh --uninstall
```

---

## What the installer does

1. Detect platform (macOS / Linux) and package manager (brew / apt / dnf / pacman)
2. Install Homebrew if missing (optional)
3. Install core dependencies (zsh, git, curl)
4. Audit & install 18 modern CLI tools — show all missing at once, offer one-click install
5. Install Oh My Zsh + 4 custom plugins
6. Install Nerd Font (optional)
7. Install dev tools: pyenv, nvm, rust, uv (each optional)
8. Backup existing `~/.zshrc` (timestamped) and deploy clean config
9. Create `~/.zshrc.local` for secrets and machine-specific overrides

---

## CLI Tools

| Original | Replacement | Description |
| --- | --- | --- |
| `vim` | **neovim** | Terminal editor |
| `ls` | **eza** | Icons + git status + colors |
| `cat` | **bat** | Syntax highlighting + line numbers |
| `grep` | **ripgrep** | Fast recursive search |
| `find` | **fd** | Simple, fast, user-friendly |
| `cd` | **zoxide** | Frecency-based smart cd |
| `top` | **btop** | Resource monitor with graphs |
| `man` | **tealdeer** | Community-driven cheat sheets |
| `ps` | **procs** | Modern process viewer |
| `du` | **dust** | Intuitive disk usage |
| `df` | **duf** | Disk free with colors |
| `diff` | **git-delta** | Syntax-aware git diffs |
| — | **fzf** | Fuzzy finder for everything |
| — | **lazygit** | Git TUI |
| — | **starship** | Cross-shell prompt |
| — | **tmux** | Terminal multiplexer |
| — | **yazi** | Terminal file manager |
| — | **ncdu** | Disk usage explorer |

---

## Aliases

| Alias | Expands to | Description |
| --- | --- | --- |
| `vim` / `vi` | `nvim` | Neovim |
| `ls` | `eza --icons --group-directories-first` | Pretty ls |
| `cat` | `bat` | Syntax-highlighted cat |
| `grep` | `rg --color=always` | Ripgrep |
| `cd` | `z` (zoxide) | Smart directory jump |
| `top` | `btop` | Resource monitor |
| `help` | `tldr` | Cheat sheets |
| `ps` | `procs` | Process viewer |
| `du` | `dust` | Disk usage |
| `df` | `duf` | Disk free |
| `lg` | `lazygit` | Git TUI |
| `y` | yazi wrapper | File manager (cd-on-exit) |
| `ranger` | `y` | Yazi alias |

---

## Oh My Zsh Plugins

### Built-in

| Plugin | Description |
| --- | --- |
| git | Git aliases and functions |
| sudo | Double-tap ESC to prepend sudo |
| fzf | Fuzzy finder integration |
| tmux | Tmux aliases |
| aws | AWS CLI completions |
| docker | Docker completions |
| docker-compose | Docker Compose completions |
| kubectl | Kubernetes completions |
| kube-ps1 | Kubernetes context in prompt |

### Custom (auto-installed)

| Plugin | Description |
| --- | --- |
| [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) | Real-time command highlighting |
| [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | Fish-style suggestions |
| [zsh-completions](https://github.com/zsh-users/zsh-completions) | Additional completions |
| [alias-tips](https://github.com/djui/alias-tips) | Shows alias when you type full command |

---

## Dev Tools (optional)

| Tool | Description |
| --- | --- |
| pyenv + pyenv-virtualenv | Python version manager |
| nvm | Node.js version manager |
| rust/cargo | Rust toolchain |
| uv | Fast Python package manager |

Each is prompted during install — skip any you don't need.

---

## Secrets & Local Config

The installer creates `~/.zshrc.local` for machine-specific settings:

```bash
# ~/.zshrc.local — not tracked by git
export OPENAI_API_KEY="sk-..."
export PATH="$PATH:/custom/path"
```

This file is sourced at the end of `.zshrc`. Put API keys, custom PATHs, and local aliases here.

---

## Cross-platform

| Platform | Package Manager | Status |
| --- | --- | --- |
| macOS | Homebrew | Full support |
| Ubuntu/Debian | apt + brew | Full support |
| Fedora | dnf + brew | Full support |
| Arch | pacman + brew | Full support |

Tools like eza, zoxide, starship, lazygit are best installed via Homebrew on Linux. The installer offers to set it up.

---

## Requirements

- **Bash** >= 4.0 (for the installer)
- **Git** (for oh-my-zsh and plugins)
- **Nerd Font** (for icons) — e.g., Hack Nerd Font
- Terminal with true color support
