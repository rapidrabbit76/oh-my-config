# oh-my-config

Personal dotfiles repo, born out of pure rage after Claude Code butchered my config directory.

Portable, cross-platform terminal configs that survive across macOS, Linux, and SSH sessions. One-liner install, version-controlled, never losing my setup again.

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
