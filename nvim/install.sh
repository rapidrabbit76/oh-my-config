#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/rapidrabbit76/oh-my-config.git"
NVIM_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
NVIM_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nvim"
NVIM_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nvim"
BACKUP_DIR="$NVIM_DIR.bak.$(date +%Y%m%d%H%M%S)"
REMOTE_MODE=false
CLEANUP_DIR=""

if [[ "${BASH_SOURCE[0]}" == "bash" ]] || [[ "${BASH_SOURCE[0]}" == "/dev/stdin" ]] || [[ ! -f "${BASH_SOURCE[0]}" ]]; then
  REMOTE_MODE=true
  CLEANUP_DIR="$(mktemp -d)"
  trap 'rm -rf "$CLEANUP_DIR"' EXIT
  if command -v git &>/dev/null; then
    git clone --depth 1 "$REPO_URL" "$CLEANUP_DIR" 2>/dev/null
  else
    echo "Error: git is required for remote install"
    exit 1
  fi
  SCRIPT_DIR="$CLEANUP_DIR/nvim"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}  ✓${NC} $1"; }
warn()  { echo -e "${YELLOW}  ⚠${NC} $1"; }
error() { echo -e "${RED}  ✗${NC} $1"; }

PROGRESS_CURRENT=0
PROGRESS_TOTAL=0

progress_start() {
  PROGRESS_CURRENT=0
  PROGRESS_TOTAL=$1
}

progress_tick() {
  local label="${1:-}"
  PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
  local percent=$((PROGRESS_CURRENT * 100 / PROGRESS_TOTAL))
  local width=30
  local filled=$((PROGRESS_CURRENT * width / PROGRESS_TOTAL))
  local empty=$((width - filled))
  local bar=""
  for ((i = 0; i < filled; i++)); do bar+="█"; done
  for ((i = 0; i < empty; i++)); do bar+="░"; done
  printf "\r  ${CYAN}%s${NC} ${DIM}%3d%%${NC} ${DIM}%s${NC}" "$bar" "$percent" "$label"
  if [[ $PROGRESS_CURRENT -eq $PROGRESS_TOTAL ]]; then
    printf "\n"
  fi
}

NVIM_MIN_VERSION="0.11.2"

version_ge() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}

ensure_brew() {
  if $HAS_BREW; then return 0; fi
  warn "Homebrew not found — needed for reliable latest neovim"
  read -rp "  Install Homebrew now? [Y/n] " answer
  if [[ ! "${answer:-Y}" =~ ^[Yy]?$ ]]; then return 1; fi
  if [[ "$OS" == "linux" ]]; then
    if [[ "$PKG_MANAGER" == "apt" ]]; then
      sudo apt update -qq && sudo apt install -y build-essential procps curl file git &>/dev/null || true
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
      sudo dnf groupinstall -y 'Development Tools' &>/dev/null || true
      sudo dnf install -y procps-ng curl file git &>/dev/null || true
    fi
  fi
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ "$OS" == "linux" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true
  elif [[ "$OS" == "macos" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || \
    eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
  fi
  if command -v brew &>/dev/null; then
    HAS_BREW=true
    PKG_MANAGER="brew"
    ok "Homebrew installed"
    return 0
  fi
  return 1
}

install_nvim_tarball() {
  local install_dir="$HOME/.local"
  local bin_dir="$install_dir/bin"
  mkdir -p "$bin_dir" "$install_dir/share"

  local arch_suffix="x86_64"
  [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && arch_suffix="arm64"

  local url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${arch_suffix}.tar.gz"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  info "Downloading nvim tarball..."
  echo -e "       ${DIM}$url${NC}"
  if ! curl -fsSL "$url" -o "$tmp_dir/nvim.tar.gz"; then
    error "Download failed"
    rm -rf "$tmp_dir"
    return 1
  fi
  if ! tar xzf "$tmp_dir/nvim.tar.gz" -C "$tmp_dir" 2>/dev/null; then
    error "Extraction failed"
    rm -rf "$tmp_dir"
    return 1
  fi

  local extracted
  extracted="$(find "$tmp_dir" -maxdepth 1 -type d -name 'nvim-linux*' | head -1)"
  if [[ -z "$extracted" ]]; then
    error "Could not locate extracted nvim directory"
    rm -rf "$tmp_dir"
    return 1
  fi

  local install_target="$install_dir/share/nvim-prebuilt"
  rm -rf "$install_target"
  mv "$extracted" "$install_target"
  ln -sf "$install_target/bin/nvim" "$bin_dir/nvim"
  rm -rf "$tmp_dir"

  ok "nvim installed to $install_target"
  ok "Symlinked to $bin_dir/nvim"

  if ! echo "$PATH" | tr ':' '\n' | grep -qx "$bin_dir"; then
    export PATH="$bin_dir:$PATH"
    warn "$bin_dir not in PATH — exported for current session"
    warn "Add to ~/.zshrc or ~/.bashrc:"
    echo -e "       ${DIM}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
  fi
  return 0
}

install_or_upgrade_nvim() {
  local action="${1:-Install}"

  if [[ "$OS" == "macos" ]]; then
    if ! $HAS_BREW; then
      ensure_brew || { error "Homebrew is required for macOS install"; return 1; }
    fi
    if brew list --versions neovim &>/dev/null; then
      info "${action}ing neovim via brew (already installed → upgrade)"
      brew upgrade neovim 2>/dev/null && ok "neovim upgraded" || warn "brew upgrade returned non-zero (already latest?)"
    else
      info "${action}ing neovim via brew"
      brew install neovim &>/dev/null && ok "neovim installed" || { error "brew install neovim failed"; return 1; }
    fi
    return 0
  fi

  echo ""
  echo -e "  ${BOLD}Choose method:${NC}"
  echo -e "    ${CYAN}1)${NC} Homebrew (Linuxbrew) ${DIM}— always latest, recommended${NC}"
  echo -e "    ${CYAN}2)${NC} Official prebuilt tarball ${DIM}— ~/.local/share/nvim-prebuilt, no sudo${NC}"
  if [[ -n "$PKG_MANAGER" ]] && [[ "$PKG_MANAGER" != "brew" ]]; then
    echo -e "    ${CYAN}3)${NC} Native ${PKG_MANAGER} ${DIM}(may be older than $NVIM_MIN_VERSION)${NC}"
  fi
  echo ""
  read -rp "  Choice [default: 1]: " method
  method="${method:-1}"

  case "$method" in
    1)
      ensure_brew || { error "Homebrew install declined/failed"; return 1; }
      if brew list --versions neovim &>/dev/null; then
        info "${action}ing neovim via brew (already installed → upgrade)"
        brew upgrade neovim 2>/dev/null && ok "neovim upgraded" || warn "brew upgrade returned non-zero (already latest?)"
      else
        info "${action}ing neovim via brew"
        brew install neovim &>/dev/null && ok "neovim installed via brew" || { error "brew install failed"; return 1; }
      fi
      ;;
    2)
      install_nvim_tarball || return 1
      ;;
    3)
      case "$PKG_MANAGER" in
        apt)
          if sudo apt update -qq && sudo apt install -y neovim &>/dev/null; then
            ok "neovim installed via apt"
            warn "apt's neovim is often outdated — if still < $NVIM_MIN_VERSION, re-run and pick option 1 or 2"
          else
            error "apt install failed"; return 1
          fi
          ;;
        dnf)
          sudo dnf install -y neovim &>/dev/null && ok "neovim installed via dnf" || { error "dnf install failed"; return 1; }
          ;;
        pacman)
          sudo pacman -S --noconfirm neovim &>/dev/null && ok "neovim installed via pacman" || { error "pacman install failed"; return 1; }
          ;;
        *)
          error "No supported native package manager"; return 1
          ;;
      esac
      ;;
    *)
      error "Invalid choice"
      return 1
      ;;
  esac
  return 0
}

show_banner() {
  echo ""
  echo -e "${BOLD}${CYAN}"
  cat << 'BANNER'
    ╔═══════════════════════════════════════════════╗
    ║                                               ║
    ║    ░█▄█░█░█░░░█▀▀░█▀█░█▀█░█▀▀░▀█▀░█▀▀░░    ║
    ║    ░█░█░░█░░░░█░░░█░█░█░█░█▀▀░░█░░█░█░░░    ║
    ║    ░▀░▀░░▀░░░░▀▀▀░▀▀▀░▀░▀░▀░░░▀▀▀░▀▀▀░░░    ║
    ║                                               ║
    ║          ⚡ Neovim Environment Setup           ║
    ║         LazyVim + 6 colorscheme picker         ║
    ║                                               ║
    ╚═══════════════════════════════════════════════╝
BANNER
  echo -e "${NC}"
  echo -e "  ${DIM}lazyvim · interactive theme picker · cross-platform${NC}"
  echo ""
}

if [[ "${1:-}" == "--uninstall" ]]; then
  echo ""
  echo -e "${BOLD}${RED}  Uninstalling oh-my-config nvim...${NC}"
  echo ""

  [[ -d "$NVIM_DIR" ]]       && rm -rf "$NVIM_DIR"       && ok "Removed ~/.config/nvim"
  [[ -d "$NVIM_DATA_DIR" ]]  && rm -rf "$NVIM_DATA_DIR"  && ok "Removed ~/.local/share/nvim (lazy.nvim plugins)"
  [[ -d "$NVIM_STATE_DIR" ]] && rm -rf "$NVIM_STATE_DIR" && ok "Removed ~/.local/state/nvim"
  [[ -d "$NVIM_CACHE_DIR" ]] && rm -rf "$NVIM_CACHE_DIR" && ok "Removed ~/.cache/nvim"

  echo ""
  ok "Uninstall complete"
  warn "Restore from backup: ${DIM}cp -r ~/.config/nvim.bak.* ~/.config/nvim${NC}"
  warn "Neovim binary itself is NOT removed (manual cleanup)"
  exit 0
fi

show_banner

# ═══════════════════════════════════════════════════════════
# [1/6] Platform detection
# ═══════════════════════════════════════════════════════════
echo -e "${BOLD}  [1/6] Platform detection${NC}"
echo ""

OS="unknown"
PKG_MANAGER=""
HAS_BREW=false
ARCH="$(uname -m)"

if [[ "$(uname)" == "Darwin" ]]; then
  OS="macos"
elif [[ "$(uname)" == "Linux" ]]; then
  OS="linux"
fi

if command -v brew &>/dev/null; then
  HAS_BREW=true
  PKG_MANAGER="brew"
elif command -v apt &>/dev/null; then
  PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
  PKG_MANAGER="dnf"
elif command -v pacman &>/dev/null; then
  PKG_MANAGER="pacman"
fi

ok "Detected ${BOLD}$OS${NC} ($ARCH) ${DIM}[${PKG_MANAGER:-none}]${NC}"

# ═══════════════════════════════════════════════════════════
# [2/6] Neovim + dependencies
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}  [2/6] Neovim + dependencies${NC}"
echo ""

NVIM_OK=false
NVIM_NEEDS_UPGRADE=false
if command -v nvim &>/dev/null; then
  NVIM_VER_RAW="$(nvim --version 2>/dev/null | head -1)"
  NVIM_VER="$(echo "$NVIM_VER_RAW" | sed -E 's/^NVIM v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
  if [[ "$NVIM_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && version_ge "$NVIM_VER" "$NVIM_MIN_VERSION"; then
    ok "Found $NVIM_VER_RAW ${DIM}(LazyVim requires >= $NVIM_MIN_VERSION)${NC}"
    NVIM_OK=true
  else
    warn "Found $NVIM_VER_RAW — LazyVim requires >= $NVIM_MIN_VERSION"
    NVIM_NEEDS_UPGRADE=true
  fi
else
  warn "Neovim not found"
fi

if ! $NVIM_OK; then
  echo ""
  if $NVIM_NEEDS_UPGRADE; then
    read -rp "  Upgrade Neovim to latest? [Y/n] " answer
  else
    read -rp "  Install latest Neovim? [Y/n] " answer
  fi
  if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
    if $NVIM_NEEDS_UPGRADE; then
      install_or_upgrade_nvim "Upgrade" || true
    else
      install_or_upgrade_nvim "Install" || true
    fi

    hash -r 2>/dev/null || true
    if command -v nvim &>/dev/null; then
      NVIM_VER_RAW="$(nvim --version 2>/dev/null | head -1)"
      NVIM_VER="$(echo "$NVIM_VER_RAW" | sed -E 's/^NVIM v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
      if [[ "$NVIM_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && version_ge "$NVIM_VER" "$NVIM_MIN_VERSION"; then
        ok "Now running $NVIM_VER ${DIM}(>= $NVIM_MIN_VERSION)${NC}"
        NVIM_OK=true
      else
        error "Installed Neovim still too old: $NVIM_VER (need >= $NVIM_MIN_VERSION)"
        warn "Manually grab latest: https://github.com/neovim/neovim/releases/latest"
        exit 1
      fi
    else
      error "Neovim install failed"
      exit 1
    fi
  else
    error "Neovim >= $NVIM_MIN_VERSION is required for LazyVim"
    exit 1
  fi
fi

for dep in git curl; do
  if command -v "$dep" &>/dev/null; then
    ok "Found $dep"
  else
    warn "$dep not found — installing"
    if $HAS_BREW; then
      brew install "$dep" &>/dev/null
    elif [[ "$PKG_MANAGER" == "apt" ]]; then
      sudo apt install -y "$dep" &>/dev/null
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
      sudo dnf install -y "$dep" &>/dev/null
    elif [[ "$PKG_MANAGER" == "pacman" ]]; then
      sudo pacman -S --noconfirm "$dep" &>/dev/null
    fi
    command -v "$dep" &>/dev/null && ok "$dep installed" || error "Failed to install $dep"
  fi
done

OPTIONAL_DEPS=(
  "ripgrep:rg:Telescope live grep"
  "fd:fd:Telescope find files"
  "lazygit:lazygit:LazyVim git UI (<leader>gg)"
)

MISSING_OPT=()
for entry in "${OPTIONAL_DEPS[@]}"; do
  IFS=':' read -r pkg cmd desc <<< "$entry"
  if command -v "$cmd" &>/dev/null; then
    ok "$pkg ${DIM}($desc)${NC}"
  else
    MISSING_OPT+=("$pkg")
    warn "$pkg missing ${DIM}($desc)${NC}"
  fi
done

if [[ ${#MISSING_OPT[@]} -gt 0 ]] && $HAS_BREW; then
  echo ""
  read -rp "  Install missing optional tools via brew? [Y/n] " answer
  if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
    progress_start ${#MISSING_OPT[@]}
    for pkg in "${MISSING_OPT[@]}"; do
      if brew install "$pkg" &>/dev/null; then
        progress_tick "$pkg"
      else
        progress_tick "$pkg (failed)"
      fi
    done
  fi
fi

NERD_FONT_FOUND=false
if [[ "$OS" == "macos" ]]; then
  if fc-list 2>/dev/null | grep -qi "nerd" || ls ~/Library/Fonts/*[Nn]erd* &>/dev/null 2>&1; then
    NERD_FONT_FOUND=true
  fi
elif [[ "$OS" == "linux" ]]; then
  if fc-list 2>/dev/null | grep -qi "nerd"; then
    NERD_FONT_FOUND=true
  fi
fi

if $NERD_FONT_FOUND; then
  ok "Nerd Font detected"
else
  warn "Nerd Font not detected — file/git icons in LazyVim may not render"
  if [[ "$OS" == "macos" ]] && $HAS_BREW; then
    echo -e "       ${DIM}Install: brew install --cask font-hack-nerd-font${NC}"
  else
    echo -e "       ${DIM}Install: https://www.nerdfonts.com/font-downloads${NC}"
  fi
fi

# ═══════════════════════════════════════════════════════════
# [3/6] Backup existing config
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}  [3/6] Backup${NC}"
echo ""

if [[ -d "$NVIM_DIR" ]] && [[ -n "$(ls -A "$NVIM_DIR" 2>/dev/null)" ]]; then
  cp -R "$NVIM_DIR" "$BACKUP_DIR"
  ok "Backed up to ${DIM}$BACKUP_DIR${NC}"
else
  ok "No existing config to back up"
fi

# ═══════════════════════════════════════════════════════════
# [4/6] Theme picker
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}  [4/6] Pick a colorscheme${NC}"
echo ""

# Theme registry — keep aligned with files in themes/
# format: name|file_basename|primary_ansi|secondary_ansi|description
THEMES=(
  "Claude|claude|215|223|warm orange + beige · Anthropic vibes"
  "Tokyo Night|tokyonight|111|141|deep blue + purple · LazyVim default"
  "Catppuccin Mocha|catppuccin|218|147|pastel pink + lavender · matches your tmux"
  "Gruvbox|gruvbox|214|167|retro yellow + red · timeless classic"
  "Rose Pine|rose-pine|217|187|soft rose + gold · cozy"
  "Kanagawa|kanagawa|103|181|japanese indigo + sakura · muted wave"
)

print_swatch() {
  local color1="$1" color2="$2"
  printf "\033[38;5;%sm▓▓\033[38;5;%sm▓▓\033[0m" "$color1" "$color2"
}

echo -e "  ${DIM}Choose a theme — preview swatches show primary/secondary colors:${NC}"
echo ""
for i in "${!THEMES[@]}"; do
  IFS='|' read -r name file c1 c2 desc <<< "${THEMES[$i]}"
  num=$((i + 1))
  printf "    ${CYAN}%d)${NC} " "$num"
  print_swatch "$c1" "$c2"
  printf " ${BOLD}%-20s${NC} ${DIM}%s${NC}\n" "$name" "$desc"
done

echo ""
THEME_CHOICE=""
while [[ -z "$THEME_CHOICE" ]]; do
  read -rp "  Choice [1-${#THEMES[@]}, default: 1]: " choice
  choice="${choice:-1}"
  if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#THEMES[@]} ]]; then
    THEME_CHOICE="$choice"
  else
    warn "Invalid choice — enter a number between 1 and ${#THEMES[@]}"
  fi
done

IFS='|' read -r THEME_NAME THEME_FILE _ _ THEME_DESC <<< "${THEMES[$((THEME_CHOICE - 1))]}"
echo ""
ok "Selected ${BOLD}$THEME_NAME${NC} ${DIM}($THEME_DESC)${NC}"

# ═══════════════════════════════════════════════════════════
# [5/6] Deploy config
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}  [5/6] Deploy config${NC}"
echo ""

mkdir -p "$NVIM_DIR/lua/config" "$NVIM_DIR/lua/plugins"

DEPLOY_FILES=(
  "init.lua"
  ".neoconf.json"
  "lazyvim.json"
  "stylua.toml"
  "lua/config/lazy.lua"
  "lua/config/options.lua"
  "lua/config/keymaps.lua"
  "lua/config/autocmds.lua"
  "lua/plugins/example.lua"
)

progress_start $((${#DEPLOY_FILES[@]} + 1))
for f in "${DEPLOY_FILES[@]}"; do
  if [[ -f "$SCRIPT_DIR/$f" ]]; then
    cp "$SCRIPT_DIR/$f" "$NVIM_DIR/$f"
    progress_tick "$f"
  else
    progress_tick "$f (missing in source)"
  fi
done

# Clean up stale theme files from prior installs (legacy claude-theme.lua, etc.)
LEGACY_THEME_FILES=(
  "claude-theme.lua"
  "tokyonight.lua"
  "catppuccin.lua"
  "gruvbox.lua"
  "rose-pine.lua"
  "kanagawa.lua"
)
for legacy in "${LEGACY_THEME_FILES[@]}"; do
  rm -f "$NVIM_DIR/lua/plugins/$legacy"
done

cp "$SCRIPT_DIR/themes/$THEME_FILE.lua" "$NVIM_DIR/lua/plugins/colorscheme.lua"
progress_tick "colorscheme.lua ($THEME_NAME)"

# ═══════════════════════════════════════════════════════════
# [6/6] Bootstrap plugins
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}  [6/6] Bootstrap plugins${NC}"
echo ""

read -rp "  Install LazyVim plugins now (headless, ~1-2 min)? [Y/n] " answer
if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
  info "Running: nvim --headless \"+Lazy! sync\" +qa"
  echo -e "  ${DIM}(plugin downloads stream below — be patient)${NC}"
  echo ""
  if nvim --headless "+Lazy! sync" +qa 2>&1 | tail -20; then
    echo ""
    ok "Plugins installed"
  else
    nvim_exit=$?
    echo ""
    warn "Plugin sync exited with code $nvim_exit — open nvim manually and run :Lazy sync"
  fi
else
  ok "Skipped — plugins will install on first nvim launch"
fi

echo ""
echo -e "${GREEN}  ╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║         Installation complete! 🎉             ║${NC}"
echo -e "${GREEN}  ╠═══════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ║${NC}  Theme: ${CYAN}$(printf '%-37s' "$THEME_NAME")${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  Run ${CYAN}nvim${NC} to start                          ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}:Lazy${NC}            plugin manager              ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}:LazyExtras${NC}      add LazyVim extras           ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}:checkhealth${NC}     diagnose issues               ${GREEN}║${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ║${NC}  ${DIM}Switch theme: re-run install.sh${NC}              ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  ${DIM}Uninstall:    install.sh --uninstall${NC}         ${GREEN}║${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${DIM}Also install zsh, tmux & yazi configs:${NC}"
echo -e "  ${CYAN}bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/zsh/install.sh)${NC}"
echo -e "  ${CYAN}bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/tmux/install.sh)${NC}"
echo -e "  ${CYAN}bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/yazi/install.sh)${NC}"
echo ""
