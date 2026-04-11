#!/usr/bin/env bash
set -euo pipefail

# oh-my-config: Yazi portable installer
# Usage: ./install.sh [--uninstall]

REPO_URL="https://github.com/rapidrabbit76/oh-my-config.git"
YAZI_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/yazi"
BACKUP_DIR="$YAZI_CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
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
  SCRIPT_DIR="$CLEANUP_DIR/yazi"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# ─── Colors ──────────────────────────────────────────────
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

# ─── Progress bar ────────────────────────────────────────
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

# ─── Banner ──────────────────────────────────────────────
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
    ║          ⣿  Yazi File Manager Config          ║
    ║             Claude-inspired theme              ║
    ║                                               ║
    ╚═══════════════════════════════════════════════╝
BANNER
  echo -e "${NC}"
  echo -e "  ${DIM}24 plugins · cross-platform · portable${NC}"
  echo ""
}

# ─── Uninstall ───────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
  echo ""
  echo -e "${BOLD}${RED}  Uninstalling oh-my-config yazi...${NC}"
  echo ""

  if [[ -d "$YAZI_CONFIG_DIR" ]]; then
    rm -f "$YAZI_CONFIG_DIR/yazi.toml"
    rm -f "$YAZI_CONFIG_DIR/keymap.toml"
    rm -f "$YAZI_CONFIG_DIR/theme.toml"
    rm -f "$YAZI_CONFIG_DIR/init.lua"
    rm -rf "$YAZI_CONFIG_DIR/plugins/mediainfo.yazi"
    rm -f "$HOME/.local/bin/smart-open"
    ok "Config files removed"
  fi

  if command -v ya &>/dev/null; then
    UNINSTALL_PKGS=(
      "ndtoan96/ouch"
      "yazi-rs/plugins:smart-filter"
      "yazi-rs/plugins:git"
      "yazi-rs/plugins:jump-to-char"
      "yazi-rs/plugins:chmod"
      "yazi-rs/plugins:diff"
      "yazi-rs/plugins:toggle-pane"
      "yazi-rs/plugins:full-border"
      "yazi-rs/plugins:mount"
      "yazi-rs/plugins:mime-ext"
      "Reledia/hexyl"
      "uhs-robert/recycle-bin"
      "Lil-Dank/lazygit"
      "dedukun/bookmarks"
      "wylie102/duckdb"
      "DreamMaoMao/searchjump"
      "barbanevosa/autosession"
      "MasouShizuka/projects"
      "pirafrank/what-size"
      "lpnh/fr"
      "imsi32/yatline"
      "dawsers/dual-pane"
      "Rolv-Apneseth/bypass"
      "dedukun/relative-motions"
      "boydaihungst/restore"
      "ahkohd/eza-preview"
      "rapidrabbit76/claude-inspired"
    )
    progress_start ${#UNINSTALL_PKGS[@]}
    for pkg in "${UNINSTALL_PKGS[@]}"; do
      ya pkg delete "$pkg" 2>/dev/null || true
      progress_tick "$pkg"
    done
    ok "Packages removed"
  fi

  echo ""
  ok "Uninstall complete"
  exit 0
fi

# ─── Show banner ─────────────────────────────────────────
show_banner

# ─── Pre-flight checks ──────────────────────────────────
echo -e "${BOLD}  [1/6] Pre-flight checks${NC}"
echo ""

if ! command -v yazi &>/dev/null; then
  error "yazi not found. Install it first:"
  echo "        brew install yazi ffmpegthumbnailer"
  exit 1
fi

YAZI_VERSION=$(yazi --version 2>/dev/null | head -1)
ok "Found $YAZI_VERSION"

if ! command -v ya &>/dev/null; then
  error "ya (yazi helper) not found"
  exit 1
fi
ok "Found ya"

BREW=""
if command -v brew &>/dev/null; then
  BREW="brew"
  ok "Found brew"
else
  warn "brew not found — cannot auto-install dependencies"
fi

# ─── Dependency audit ───────────────────────────────────
echo ""
echo -e "${BOLD}  [2/6] Dependency audit${NC}"
echo ""

DEP_MAP=(
  "hexyl:hexyl:Binary hex previewer"
  "trash-cli:trash-put:Trash management (recycle-bin, restore)"
  "lazygit:lazygit:Git TUI integration"
  "duckdb:duckdb:CSV/Parquet table preview"
  "mediainfo:mediainfo:Audio/video metadata preview"
  "ffmpegthumbnailer:ffmpegthumbnailer:Video thumbnail generation"
  "ouch:ouch:Archive compress/extract/preview"
  "chafa:chafa:Terminal image viewer (SSH fallback)"
  "eza:eza:Directory tree preview"
)

MISSING_DEPS=()
MISSING_DESCS=()

for entry in "${DEP_MAP[@]}"; do
  IFS=':' read -r pkg cmd desc <<< "$entry"
  if command -v "$cmd" &>/dev/null; then
    ok "$pkg ${DIM}($desc)${NC}"
  else
    MISSING_DEPS+=("$pkg")
    MISSING_DESCS+=("$desc")
    error "$pkg ${DIM}($desc)${NC}"
  fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
  echo ""
  echo -e "  ${YELLOW}╭─ Missing ${#MISSING_DEPS[@]} dependencies ─────────────────────╮${NC}"
  for i in "${!MISSING_DEPS[@]}"; do
    printf "  ${YELLOW}│${NC}  %-22s %s\n" "${MISSING_DEPS[$i]}" "${DIM}${MISSING_DESCS[$i]}${NC}"
  done
  echo -e "  ${YELLOW}╰──────────────────────────────────────────────╯${NC}"
  echo ""
  if [[ -n "$BREW" ]]; then
    echo -e "  ${DIM}Install all at once:${NC}"
    echo -e "  ${CYAN}brew install ${MISSING_DEPS[*]}${NC}"
    echo ""
    read -rp "  Install missing dependencies now? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
      echo ""
      progress_start ${#MISSING_DEPS[@]}
      INSTALL_FAILED=()
      for dep in "${MISSING_DEPS[@]}"; do
        if brew install "$dep" &>/dev/null; then
          progress_tick "$dep"
        else
          progress_tick "$dep (failed)"
          INSTALL_FAILED+=("$dep")
        fi
      done
      if [[ ${#INSTALL_FAILED[@]} -gt 0 ]]; then
        warn "Failed to install: ${INSTALL_FAILED[*]}"
        warn "Related plugins may not work correctly."
      else
        ok "All dependencies installed"
      fi
    else
      warn "Skipping dependency install — some plugins may not work"
    fi
  else
    echo -e "  ${DIM}Install manually with your package manager, then re-run this script.${NC}"
  fi
else
  echo ""
  ok "All dependencies satisfied"
fi

# ─── Backup existing config ─────────────────────────────
echo ""
echo -e "${BOLD}  [3/6] Backup${NC}"
echo ""

if [[ -d "$YAZI_CONFIG_DIR" ]] && [[ "$(ls -A "$YAZI_CONFIG_DIR" 2>/dev/null)" ]]; then
  cp -r "$YAZI_CONFIG_DIR" "$BACKUP_DIR"
  ok "Backed up to ${DIM}$BACKUP_DIR${NC}"
else
  ok "No existing config to back up"
fi

# ─── Copy config files ──────────────────────────────────
echo ""
echo -e "${BOLD}  [4/6] Config files${NC}"
echo ""

mkdir -p "$YAZI_CONFIG_DIR/plugins/mediainfo.yazi"
mkdir -p "$YAZI_CONFIG_DIR/plugins/compress-each.yazi"

CONFIG_FILES=(yazi.toml keymap.toml theme.toml init.lua)
progress_start $((${#CONFIG_FILES[@]} + 3))

for f in "${CONFIG_FILES[@]}"; do
  cp "$SCRIPT_DIR/$f" "$YAZI_CONFIG_DIR/$f"
  progress_tick "$f"
done

cp "$SCRIPT_DIR/plugins/mediainfo.yazi/main.lua" "$YAZI_CONFIG_DIR/plugins/mediainfo.yazi/main.lua"
progress_tick "mediainfo.yazi"

cp "$SCRIPT_DIR/plugins/compress-each.yazi/main.lua" "$YAZI_CONFIG_DIR/plugins/compress-each.yazi/main.lua"
progress_tick "compress-each.yazi"

SMART_OPEN_DIR="$HOME/.local/bin"
mkdir -p "$SMART_OPEN_DIR"
cp "$SCRIPT_DIR/scripts/smart-open" "$SMART_OPEN_DIR/smart-open"
chmod +x "$SMART_OPEN_DIR/smart-open"
progress_tick "smart-open"

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$SMART_OPEN_DIR"; then
  warn "smart-open installed to $SMART_OPEN_DIR (not in PATH)"
  echo -e "       ${DIM}Add: export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
fi

# ─── Install yazi plugins ───────────────────────────────
echo ""
echo -e "${BOLD}  [5/6] Plugins & flavor${NC}"
echo ""

OFFICIAL_PLUGINS=(
  "yazi-rs/plugins:smart-filter"
  "yazi-rs/plugins:git"
  "yazi-rs/plugins:jump-to-char"
  "yazi-rs/plugins:chmod"
  "yazi-rs/plugins:diff"
  "yazi-rs/plugins:toggle-pane"
  "yazi-rs/plugins:full-border"
  "yazi-rs/plugins:mount"
  "yazi-rs/plugins:mime-ext"
)

THIRDPARTY_PLUGINS=(
  "ndtoan96/ouch"
  "Reledia/hexyl"
  "uhs-robert/recycle-bin"
  "Lil-Dank/lazygit"
  "dedukun/bookmarks"
  "wylie102/duckdb"
  "DreamMaoMao/searchjump"
  "barbanevosa/autosession"
  "MasouShizuka/projects"
  "pirafrank/what-size"
  "lpnh/fr"
  "imsi32/yatline"
  "dawsers/dual-pane"
  "Rolv-Apneseth/bypass"
  "dedukun/relative-motions"
  "boydaihungst/restore"
  "ahkohd/eza-preview"
)

FLAVORS=(
  "rapidrabbit76/claude-inspired"
)

ALL_PACKAGES=("${OFFICIAL_PLUGINS[@]}" "${THIRDPARTY_PLUGINS[@]}" "${FLAVORS[@]}")
PLUGIN_FAILED=()

progress_start ${#ALL_PACKAGES[@]}
for pkg in "${ALL_PACKAGES[@]}"; do
  if ya pkg add "$pkg" &>/dev/null; then
    progress_tick "${pkg##*/}"
  else
    progress_tick "${pkg##*/} (failed)"
    PLUGIN_FAILED+=("$pkg")
  fi
done

mkdir -p "$YAZI_CONFIG_DIR/plugins/dual-pane.yazi"  # workaround: dual-pane uses init.lua, ya pkg needs dir

if [[ ${#PLUGIN_FAILED[@]} -gt 0 ]]; then
  warn "Failed packages: ${PLUGIN_FAILED[*]}"
else
  ok "All ${#ALL_PACKAGES[@]} packages installed"
fi

# ─── Shell integration ──────────────────────────────────
echo ""
echo -e "${BOLD}  [6/6] Shell integration${NC}"
echo ""

SHELL_SNIPPET='# yazi cd-on-exit wrapper
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}
alias ranger="y"'

ZSHRC="$HOME/.zshrc"
BASHRC="$HOME/.bashrc"

if [[ -f "$ZSHRC" ]]; then
  if grep -q "function y()" "$ZSHRC" 2>/dev/null; then
    ok "Already in .zshrc"
  else
    echo "" >> "$ZSHRC"
    echo "$SHELL_SNIPPET" >> "$ZSHRC"
    ok "Added to .zshrc ${DIM}(run: source ~/.zshrc)${NC}"
  fi
elif [[ -f "$BASHRC" ]]; then
  if grep -q "function y()" "$BASHRC" 2>/dev/null; then
    ok "Already in .bashrc"
  else
    echo "" >> "$BASHRC"
    echo "$SHELL_SNIPPET" >> "$BASHRC"
    ok "Added to .bashrc ${DIM}(run: source ~/.bashrc)${NC}"
  fi
fi

# ─── Done ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}  ╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║         Installation complete! 🎉         ║${NC}"
echo -e "${GREEN}  ╠═══════════════════════════════════════════╣${NC}"
echo -e "${GREEN}  ║                                           ║${NC}"
echo -e "${GREEN}  ║${NC}   Run ${CYAN}yazi${NC} or ${CYAN}y${NC} to start               ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}   Press ${CYAN}~${NC} inside yazi for help          ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}   Uninstall: ${DIM}$0 --uninstall${NC}  ${GREEN}║${NC}"
echo -e "${GREEN}  ║                                           ║${NC}"
echo -e "${GREEN}  ╚═══════════════════════════════════════════╝${NC}"
echo ""
