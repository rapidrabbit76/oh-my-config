# Neovim Configuration

LazyVim-based Neovim setup with an interactive colorscheme picker. Cross-platform (macOS / Linux).

---

## Install

### One-liner (curl)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/nvim/install.sh)
```

### One-liner (wget)

```bash
bash <(wget -qO- https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/nvim/install.sh)
```

### From source

```bash
git clone https://github.com/rapidrabbit76/oh-my-config.git
cd oh-my-config/nvim
./install.sh
```

### Uninstall

```bash
cd oh-my-config/nvim
./install.sh --uninstall
```

> Removes `~/.config/nvim`, `~/.local/share/nvim`, `~/.local/state/nvim`, and `~/.cache/nvim`. The Neovim binary itself is left in place.

---

## What the installer does

1. Detect platform (macOS / Linux) and package manager (brew / apt / dnf / pacman)
2. Audit Neovim (>= 0.11.2 required by LazyVim) and **auto-upgrade if outdated** — picks latest via brew (macOS / Linuxbrew) or official prebuilt tarball (Linux fallback)
3. Audit optional CLI deps — `ripgrep`, `fd`, `lazygit`
4. Detect Nerd Font (warn only)
5. Backup existing `~/.config/nvim/` to `~/.config/nvim.bak.<timestamp>/`
6. **Interactive theme picker** — pick from 6 colorschemes with live ANSI swatch previews
7. Deploy LazyVim starter config + chosen theme to `~/.config/nvim/`
8. Optional: bootstrap plugins headlessly (`nvim --headless "+Lazy! sync" +qa`)

---

## Theme picker

Pick during install — preview swatches show primary/secondary colors right in the terminal:

| # | Theme            | Plugin                                   | Vibe                                    |
| - | ---------------- | ---------------------------------------- | --------------------------------------- |
| 1 | Claude           | `rapidrabbit76/claude.inspired.theme.nvim` | warm orange + beige · Anthropic vibes  |
| 2 | Tokyo Night      | `folke/tokyonight.nvim`                  | deep blue + purple · LazyVim default    |
| 3 | Catppuccin Mocha | `catppuccin/nvim`                        | pastel pink + lavender · matches tmux   |
| 4 | Gruvbox          | `ellisonleao/gruvbox.nvim`               | retro yellow + red · timeless classic   |
| 5 | Rose Pine        | `rose-pine/neovim`                       | soft rose + gold · cozy                 |
| 6 | Kanagawa         | `rebelot/kanagawa.nvim`                  | japanese indigo + sakura · muted wave   |

> Re-run `install.sh` anytime to switch themes — only `lua/plugins/colorscheme.lua` changes, your other plugin files are preserved.

---

## Config layout

```
~/.config/nvim/
├── init.lua                       Bootstrap entrypoint
├── .neoconf.json                  Lua-LS + neodev config
├── lazyvim.json                   LazyVim metadata (extras list, news version)
├── stylua.toml                    Lua formatter config
└── lua/
    ├── config/
    │   ├── lazy.lua               Lazy.nvim setup + LazyVim spec
    │   ├── options.lua            Vim options overrides (empty by default)
    │   ├── keymaps.lua            Custom keymaps (empty by default)
    │   └── autocmds.lua           Custom autocmds (empty by default)
    └── plugins/
        ├── colorscheme.lua        ← managed by installer (your chosen theme)
        └── example.lua            LazyVim starter example (no-op)
```

The installer **manages** these specific files:
- All four `lua/config/*.lua` files
- `lua/plugins/example.lua` and `lua/plugins/colorscheme.lua`
- The four top-level files (`init.lua`, `.neoconf.json`, `lazyvim.json`, `stylua.toml`)

Any **other** files you put in `lua/plugins/` (your own custom plugins) are left alone on re-install.

---

## What's included

- **[LazyVim](https://www.lazyvim.org/)** as the base distribution — opinionated defaults, mason auto-install, treesitter, LSP, telescope, neo-tree, etc.
- **6 colorscheme plugins** to choose from (only the selected one is enabled)
- **No LazyVim extras** by default — add them via `:LazyExtras` after install

To add language support, run `:LazyExtras` inside nvim and pick from `lang.typescript`, `lang.python`, `lang.rust`, etc.

---

## Optional dependencies

The installer offers to install these via brew if missing. They make LazyVim much nicer but aren't strictly required.

| Tool       | Used by                          |
| ---------- | -------------------------------- |
| ripgrep    | Telescope live grep (`<leader>/`) |
| fd         | Telescope find files (`<leader>ff`) |
| lazygit    | Git UI (`<leader>gg`)            |

A **Nerd Font** is also recommended for file/git icons. The installer warns if none is detected but does not auto-install (configure your terminal font separately).

---

## Cross-platform

| Platform        | Package manager  | Neovim install path           |
| --------------- | ---------------- | ----------------------------- |
| macOS           | Homebrew         | `brew install neovim`         |
| Ubuntu / Debian | apt (or brew)    | `sudo apt install neovim` *   |
| Fedora          | dnf (or brew)    | `sudo dnf install neovim`     |
| Arch            | pacman (or brew) | `sudo pacman -S neovim`       |

> ⚠️  On older Ubuntu LTS, apt's neovim is below LazyVim's minimum (0.11.2). The installer detects this and offers a 3-way picker: **Linuxbrew** (recommended, always latest), **official prebuilt tarball** to `~/.local/share/nvim-prebuilt` (no sudo), or native package manager (with explicit "may be outdated" warning).

---

## Switching themes later

Two ways:

1. **Re-run installer** — pick a different number when the picker shows up. Only `colorscheme.lua` is rewritten.
2. **Edit manually** — copy any file from `themes/*.lua` over `~/.config/nvim/lua/plugins/colorscheme.lua`, then `:Lazy sync` inside nvim.

---

## Requirements

- **Neovim** >= 0.11.2 (LazyVim minimum — installer auto-upgrades if outdated)
- **git**, **curl**
- Terminal with **true color** + **256 color** ANSI support (for the theme picker swatches)
- **Nerd Font** for icons (recommended, not required)
