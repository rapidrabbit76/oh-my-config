#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/rapidrabbit76/oh-my-config.git"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_DIR/config.toml"
SIDEBAR="$HOME/.local/bin/codex-sidebar"
MARK_BEGIN="# >>> oh-my-config codex keymap >>>"
MARK_END="# <<< oh-my-config codex keymap <<<"
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
  SCRIPT_DIR="$CLEANUP_DIR/codex"
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

# Drops the managed keymap block (markers included) from config.toml, with the
# one blank line the installer put before it.
remove_block() {
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0 == b { skip = 1; held = ""; next }
    $0 == e { skip = 0; next }
    skip { next }
    $0 == "" && !held { held = "\n"; next }
    { printf "%s%s\n", (held ? "\n" : ""), $0; held = "" }
    END { if (held) printf "\n" }' "$CONFIG"
}

# codex doctor exits non-zero for unrelated checks (auth, network), so read
# its output rather than its status.
config_loads() {
  local out
  out=$(codex doctor </dev/null 2>&1 || true)
  [[ "$out" != *"config could not be loaded"* ]]
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
    ║              ◎  Codex CLI                      ║
    ║         ctrl-x leader keys + sidebar           ║
    ║                                               ║
    ╚═══════════════════════════════════════════════╝
BANNER
  echo -e "${NC}"
  echo -e "  ${DIM}leader keymap · tmux session sidebar · context / limits / plan${NC}"
  echo ""
}

# ─── Uninstall ───────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
  echo ""
  echo -e "${BOLD}${RED}  Uninstalling oh-my-config codex...${NC}"
  echo ""

  if [[ -f "$CONFIG" ]] && grep -qxF "$MARK_BEGIN" "$CONFIG"; then
    cp -p "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    tmp="$(mktemp)"
    remove_block >"$tmp" && cat "$tmp" >"$CONFIG" && rm -f "$tmp"
    ok "Removed the keymap block from ${DIM}${CONFIG/#$HOME/~}${NC} (backup kept)"
  fi
  [[ -f "$SIDEBAR" ]] && rm -f "$SIDEBAR" && ok "Removed ${SIDEBAR/#$HOME/~}"
  sed -i.bak '/^codex$/d' "$HOME/.config/oh-my-config/components" 2>/dev/null && rm -f "$HOME/.config/oh-my-config/components.bak" || true

  echo ""
  ok "Uninstall complete"
  exit 0
fi

show_banner

# ─── [1/4] Pre-flight ───────────────────────────────────
echo -e "${BOLD}  [1/4] Pre-flight checks${NC}"
echo ""

if ! command -v codex &>/dev/null; then
  error "codex not found — install the Codex CLI first: https://developers.openai.com/codex"
  exit 1
fi
ok "$(codex --version 2>/dev/null | head -1)"

missing=""
for cmd in jq sqlite3; do command -v "$cmd" &>/dev/null || missing+=" $cmd"; done
if [[ -n "$missing" ]]; then
  error "missing:$missing — the sidebar reads Codex's state with them"
  exit 1
fi
ok "jq, sqlite3"
command -v tmux &>/dev/null && ok "tmux ${DIM}(sidebar pane)${NC}" || warn "tmux not found — run codex-sidebar in a second terminal instead"

# ─── [2/4] Auto-update clone ────────────────────────────
echo ""
echo -e "${BOLD}  [2/4] Auto-update clone${NC}"
echo ""

if bash "$SCRIPT_DIR/../update.sh" --register codex 2>/dev/null; then
  ok "Update check on ${DIM}(asks at shell start when a new version exists)${NC}"
else
  warn "Auto-update setup failed — re-run the installer later"
fi

# ─── [3/4] Keymap ───────────────────────────────────────
echo ""
echo -e "${BOLD}  [3/4] Keymap${NC}"
echo ""

mkdir -p "$CODEX_DIR"
touch "$CONFIG"
if grep -qxF "$MARK_BEGIN" "$CONFIG"; then
  ok "Already in ${DIM}${CONFIG/#$HOME/~}${NC}"
elif grep -qE '^\[tui\.keymap\.(global|chat)\]' "$CONFIG"; then
  # A second [tui.keymap.global] table would stop Codex from loading its config.
  warn "Your config already has its own [tui.keymap.*] tables — left it alone"
  warn "Merge by hand from ${DIM}${SCRIPT_DIR/#$HOME/~}/keymap.toml${NC}"
else
  backup="$CONFIG.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "$CONFIG" "$backup"
  { [[ -s "$CONFIG" ]] && echo ""; cat "$SCRIPT_DIR/keymap.toml"; } >>"$CONFIG"
  if config_loads; then
    ok "Added the ctrl-x leader keymap to ${DIM}${CONFIG/#$HOME/~}${NC} (backup kept)"
  else
    cp -p "$backup" "$CONFIG"
    error "Codex rejected the keymap (codex doctor) — restored your config"
    exit 1
  fi
fi

# ─── [4/4] Sidebar ──────────────────────────────────────
echo ""
echo -e "${BOLD}  [4/4] Sidebar${NC}"
echo ""

# Keep in sync with sync_codex in ../update.sh
mkdir -p "$(dirname "$SIDEBAR")"
cp "$SCRIPT_DIR/scripts/codex-sidebar" "$SIDEBAR"
chmod +x "$SIDEBAR"
ok "Installed ${DIM}${SIDEBAR/#$HOME/~}${NC}"

if grep -qs "codex-sidebar" "$HOME/.config/oh-my-config/tmux/.tmux.conf" "$HOME/.tmux.conf" "$HOME/.tmux.conf.local"; then
  ok "tmux binding ${CYAN}Prefix + C${NC} present"
  if tmux info &>/dev/null; then
    tmux source-file "$HOME/.tmux.conf" &>/dev/null && ok "tmux config reloaded" || true
  fi
else
  warn "No tmux binding — add to ~/.tmux.conf.local:"
  echo -e "    ${DIM}bind C run-shell \"~/.local/bin/codex-sidebar toggle #{q:pane_id}\"${NC}"
fi

# ─── Done ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}  ╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║         Installation complete! 🎉             ║${NC}"
echo -e "${GREEN}  ╠═══════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}ctrl-x l${NC}    sessions   ${CYAN}ctrl-x e${NC}  editor    ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}ctrl-x a${NC}    mode       ${CYAN}ctrl-x o${NC}  transcript${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}Prefix + C${NC}  Codex sidebar (tmux)          ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}                                              ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  Uninstall: ${DIM}install.sh --uninstall${NC}          ${GREEN}║${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ╚═══════════════════════════════════════════════╝${NC}"
echo ""
