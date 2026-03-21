#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/rapidrabbit76/oh-my-config.git"
TMUX_CONF="$HOME/.tmux.conf"
TMUX_SCRIPTS="$HOME/.tmux/scripts"
TPM_DIR="$HOME/.tmux/plugins/tpm"
BACKUP_FILE="$TMUX_CONF.bak.$(date +%Y%m%d%H%M%S)"
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
  SCRIPT_DIR="$CLEANUP_DIR/tmux"
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
    ║          🖥  Tmux Terminal Multiplexer         ║
    ║            Catppuccin + Status Bar             ║
    ║                                               ║
    ╚═══════════════════════════════════════════════╝
BANNER
  echo -e "${NC}"
  echo -e "  ${DIM}catppuccin mocha · nerd font icons · pomodoro timer${NC}"
  echo ""
}

# ─── Uninstall ───────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
  echo ""
  echo -e "${BOLD}${RED}  Uninstalling oh-my-config tmux...${NC}"
  echo ""

  [[ -f "$TMUX_CONF" ]] && rm -f "$TMUX_CONF" && ok "Removed ~/.tmux.conf"
  [[ -d "$TMUX_SCRIPTS" ]] && rm -rf "$TMUX_SCRIPTS" && ok "Removed ~/.tmux/scripts/"
  [[ -d "$TPM_DIR" ]] && rm -rf "$TPM_DIR" && ok "Removed TPM"

  echo ""
  ok "Uninstall complete"
  warn "Restore from backup: ${DIM}cp ~/.tmux.conf.bak.* ~/.tmux.conf${NC}"
  exit 0
fi

show_banner

# ─── [1/5] Pre-flight ───────────────────────────────────
echo -e "${BOLD}  [1/5] Pre-flight checks${NC}"
echo ""

OS="unknown"
PKG_MANAGER=""
if [[ "$(uname)" == "Darwin" ]]; then
  OS="macos"
  command -v brew &>/dev/null && PKG_MANAGER="brew"
elif [[ "$(uname)" == "Linux" ]]; then
  OS="linux"
  command -v apt &>/dev/null && PKG_MANAGER="apt"
  command -v brew &>/dev/null && PKG_MANAGER="brew"
fi
ok "Detected ${BOLD}$OS${NC}"

if command -v tmux &>/dev/null; then
  TMUX_VERSION=$(tmux -V 2>/dev/null)
  ok "Found $TMUX_VERSION"
else
  warn "tmux not found"
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    read -rp "  Install tmux via brew? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
      brew install tmux && ok "tmux installed"
    else
      error "tmux is required"; exit 1
    fi
  elif [[ "$PKG_MANAGER" == "apt" ]]; then
    read -rp "  Install tmux via apt? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
      sudo apt update -qq && sudo apt install -y tmux && ok "tmux installed"
    else
      error "tmux is required"; exit 1
    fi
  else
    error "tmux is required. Install it manually and re-run."
    exit 1
  fi
fi

if command -v git &>/dev/null; then
  ok "Found git"
else
  error "git is required (for TPM)"
  exit 1
fi

NERD_FONT_FOUND=false
if [[ "$OS" == "macos" ]]; then
  if fc-list 2>/dev/null | grep -qi "nerd" || ls ~/Library/Fonts/*[Nn]erd* &>/dev/null; then
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
  warn "Nerd Font not detected — icons may not render"
  echo -e "       ${DIM}Install: brew install --cask font-hack-nerd-font${NC}"
fi

# ─── [2/5] Backup ───────────────────────────────────────
echo ""
echo -e "${BOLD}  [2/5] Backup${NC}"
echo ""

if [[ -f "$TMUX_CONF" ]] || [[ -L "$TMUX_CONF" ]]; then
  cp -P "$TMUX_CONF" "$BACKUP_FILE"
  ok "Backed up to ${DIM}$BACKUP_FILE${NC}"
else
  ok "No existing config to back up"
fi

# ─── [3/5] Config files ────────────────────────────────
echo ""
echo -e "${BOLD}  [3/5] Config files${NC}"
echo ""

mkdir -p "$TMUX_SCRIPTS"

ITEMS=(".tmux.conf" "net_speed.sh" "disk_usage.sh" "public_ip.sh" "pomodoro.sh")
progress_start ${#ITEMS[@]}

cp "$SCRIPT_DIR/.tmux.conf" "$TMUX_CONF"
progress_tick ".tmux.conf"

for script in net_speed.sh disk_usage.sh public_ip.sh pomodoro.sh; do
  cp "$SCRIPT_DIR/scripts/$script" "$TMUX_SCRIPTS/$script"
  chmod +x "$TMUX_SCRIPTS/$script"
  progress_tick "$script"
done

# ─── [4/5] TPM ──────────────────────────────────────────
echo ""
echo -e "${BOLD}  [4/5] Tmux Plugin Manager${NC}"
echo ""

if [[ -d "$TPM_DIR" ]]; then
  ok "TPM already installed"
else
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR" 2>/dev/null
  ok "TPM installed to ${DIM}$TPM_DIR${NC}"
fi

# ─── [5/5] Reload ───────────────────────────────────────
echo ""
echo -e "${BOLD}  [5/5] Reload${NC}"
echo ""

if pgrep -x tmux &>/dev/null; then
  tmux source-file "$TMUX_CONF" 2>/dev/null && ok "Config reloaded" || warn "Reload failed — reload manually: tmux source-file ~/.tmux.conf"
else
  ok "tmux not running — config will apply on next launch"
fi

# ─── Done ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}  ╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║         Installation complete! 🎉             ║${NC}"
echo -e "${GREEN}  ╠═══════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}Prefix + I${NC} (Shift+i) to install plugins   ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}Prefix + P${NC} to start pomodoro timer       ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}Prefix + r${NC} to reload config              ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}                                              ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  Prefix = ${CYAN}Ctrl+Space${NC} or ${CYAN}Ctrl+b${NC}             ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  Uninstall: ${DIM}install.sh --uninstall${NC}          ${GREEN}║${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ╚═══════════════════════════════════════════════╝${NC}"
echo ""
