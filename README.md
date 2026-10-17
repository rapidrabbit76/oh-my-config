# oh-my-config

Personal dotfiles repo, born out of pure rage after Claude Code butchered my config directory.

Portable, cross-platform terminal configs that survive across macOS, Linux, and SSH sessions. One-liner install, version-controlled, never losing my setup again.

## Full Setup (all at once)

Install everything — zsh + tmux + yazi + nvim:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/zsh/install.sh) && \
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/tmux/install.sh) && \
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/yazi/install.sh) && \
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/nvim/install.sh)
```

Or install each component individually:

---

## Zsh

Modern zsh environment — oh-my-zsh, starship prompt, 18 modern CLI replacements (eza, bat, ripgrep, zoxide, btop, etc.)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/zsh/install.sh)
```

or with wget:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/zsh/install.sh)
```

> [**Full documentation →**](zsh/README.md)

## Tmux

Catppuccin Mocha themed tmux with enhanced status bar — network speed, disk, public IP, pomodoro timer.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/tmux/install.sh)
```

or with wget:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/tmux/install.sh)
```

> [**Full documentation →**](tmux/README.md)

## Yazi

Portable yazi file manager setup — 26 plugins, cross-platform (macOS / Linux / SSH).

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/yazi/install.sh)
```

or with wget:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/yazi/install.sh)
```

> [**Full documentation →**](yazi/README.md)

## Neovim

LazyVim-based Neovim setup with an interactive 6-theme picker (Claude, Tokyo Night, Catppuccin, Gruvbox, Rose Pine, Kanagawa) — preview swatches inside the terminal.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/nvim/install.sh)
```

or with wget:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/nvim/install.sh)
```

> [**Full documentation →**](nvim/README.md)

## Auto-update

The tmux, yazi and nvim installers keep a clone of this repo in `~/.local/share/oh-my-config` and add one line to `~/.zshrc`.
Like oh-my-zsh, it asks before updating: once a day it checks GitHub in the background, and when a new version exists
the next shell asks `[oh-my-config] Update available (…). Update now? [Y/n]`. Answering `n` skips that version.

- Only config files are synced: no package installs, and `~/.zshrc` / `*.local` files are never touched.
- Local edits are kept. If upstream changed the same file, your copy is saved as `<file>.bak.<timestamp>` first.
- Update now: `bash ~/.local/share/oh-my-config/update.sh`
- Turn off the prompt: `export OMC_DISABLE_AUTO_UPDATE=1` in `~/.zshrc.local`

## Structure

```
oh-my-config/
├── zsh/                          Zsh shell environment
│   ├── .zshrc
│   ├── install.sh
│   └── README.md                 ← detailed docs
├── tmux/                         Tmux terminal multiplexer config
│   ├── .tmux.conf
│   ├── install.sh
│   ├── README.md                 ← detailed docs
│   └── scripts/
│       ├── net_speed.sh
│       ├── disk_usage.sh
│       ├── public_ip.sh
│       ├── pomodoro.sh
│       └── tab_sidebar.sh        side tab list (Prefix + b)
├── yazi/                         Yazi file manager config
│   ├── yazi.toml
│   ├── keymap.toml
│   ├── theme.toml
│   ├── init.lua
│   ├── install.sh
│   ├── README.md                 ← detailed docs
│   ├── scripts/smart-open
│   └── plugins/mediainfo.yazi/
├── nvim/                         Neovim config (LazyVim)
│   ├── init.lua
│   ├── .neoconf.json
│   ├── lazyvim.json
│   ├── stylua.toml
│   ├── install.sh
│   ├── README.md                 ← detailed docs
│   ├── lua/config/               base options/keymaps/autocmds/lazy
│   ├── lua/plugins/example.lua   LazyVim starter example
│   └── themes/                   6 colorscheme templates
├── update.sh                     auto-update (config sync)
└── README.md
```

## License

MIT
