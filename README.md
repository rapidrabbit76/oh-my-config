# oh-my-config

Personal dotfiles repo, born out of pure rage after Claude Code butchered my config directory.

Portable, cross-platform terminal configs that survive across macOS, Linux, and SSH sessions. One-liner install, version-controlled, never losing my setup again.

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

## Structure

```
oh-my-config/
├── tmux/                         Tmux terminal multiplexer config
│   ├── .tmux.conf
│   ├── install.sh
│   ├── README.md                 ← detailed docs
│   └── scripts/
│       ├── net_speed.sh
│       ├── disk_usage.sh
│       ├── public_ip.sh
│       └── pomodoro.sh
├── yazi/                         Yazi file manager config
│   ├── yazi.toml
│   ├── keymap.toml
│   ├── theme.toml
│   ├── init.lua
│   ├── install.sh
│   ├── README.md                 ← detailed docs
│   ├── scripts/smart-open
│   └── plugins/mediainfo.yazi/
└── README.md
```

## License

MIT
