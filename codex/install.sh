#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/rapidrabbit76/oh-my-config.git"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_DIR/config.toml"
SIDEBAR="$HOME/.local/bin/codex-sidebar"
NOTIFY="$HOME/.local/bin/agent-notify"
HOOKS="$CODEX_DIR/hooks.json"
MARK_BEGIN="# >>> oh-my-config codex keymap >>>"
MARK_END="# <<< oh-my-config codex keymap <<<"
OMC_HOME="${OMC_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/oh-my-config}"
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

# agent-notify's entries in ~/.codex/hooks.json: added once per event, removed
# by --uninstall; every other hook there is left as it is.
HOOK_EVENTS='["Stop", "PermissionRequest"]'
hook_cmd() { printf '"%s" hook codex' "$NOTIFY"; }
HOOKS_ADD='($events | fromjson) as $ev | .hooks //= {}
  | reduce $ev[] as $e (.; if any(.hooks[$e][]?.hooks[]?; .command == $cmd) then .
      else .hooks[$e] = ((.hooks[$e] // []) + [{hooks: [{type: "command", command: $cmd, timeout: 10}]}]) end)'
HOOKS_REMOVE='.hooks |= (with_entries(.value |= map(.hooks |= map(select(.command != $cmd)) | select(.hooks | length > 0)))
  | with_entries(select(.value | length > 0)))'

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
  if [[ -f "$HOOKS" ]] && grep -qF "agent-notify" "$HOOKS" && command -v jq &>/dev/null; then
    tmp="$(mktemp)"
    if jq --arg cmd "$(hook_cmd)" "$HOOKS_REMOVE" "$HOOKS" >"$tmp"; then
      cp -p "$HOOKS" "$HOOKS.bak.$(date +%Y%m%d%H%M%S)"
      cat "$tmp" >"$HOOKS"
      ok "Removed the alert hooks from ${DIM}${HOOKS/#$HOME/~}${NC} (backup kept)"
    fi
    rm -f "$tmp"
  fi
  sed -i.bak '/^codex$/d' "$HOME/.config/oh-my-config/components" 2>/dev/null && rm -f "$HOME/.config/oh-my-config/components.bak" || true
  # agent-notify is shared with the claude component; your channels file stays.
  if [[ -f "$NOTIFY" ]] && ! grep -qx claude "$HOME/.config/oh-my-config/components" 2>/dev/null; then
    rm -f "$NOTIFY" && ok "Removed ${NOTIFY/#$HOME/~} ${DIM}(channels kept in ~/.config/oh-my-config/notify.env)${NC}"
  fi

  echo ""
  ok "Uninstall complete"
  exit 0
fi

show_banner

# ─── [1/5] Pre-flight ───────────────────────────────────
echo -e "${BOLD}  [1/5] Pre-flight checks${NC}"
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

# ─── [2/5] Auto-update clone ────────────────────────────
echo ""
echo -e "${BOLD}  [2/5] Auto-update clone${NC}"
echo ""

if bash "$SCRIPT_DIR/../update.sh" --register codex 2>/dev/null; then
  ok "Update check on ${DIM}(asks at shell start when a new version exists)${NC}"
else
  warn "Auto-update setup failed — re-run the installer later"
fi

# ─── [3/5] Keymap ───────────────────────────────────────
echo ""
echo -e "${BOLD}  [3/5] Keymap${NC}"
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

# ─── [4/5] Sidebar ──────────────────────────────────────
echo ""
echo -e "${BOLD}  [4/5] Sidebar${NC}"
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

# ─── [5/5] Alerts ───────────────────────────────────────
echo ""
echo -e "${BOLD}  [5/5] Alerts (Discord / ntfy)${NC}"
echo ""

# Keep in sync with sync_notify in ../update.sh. The launcher runs the
# agent_notify package from the clone, which update.sh keeps current.
mkdir -p "$(dirname "$NOTIFY")"
cp "$SCRIPT_DIR/../notify/agent-notify" "$NOTIFY"
chmod +x "$NOTIFY"
ok "Installed ${DIM}${NOTIFY/#$HOME/~}${NC} ${DIM}(runs ${OMC_HOME/#$HOME/~}/notify)${NC}"
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' &>/dev/null; then
  warn "Alerts need Python 3.9 or newer (python3) — until then they stay off, harmlessly"
fi

[[ -s "$HOOKS" ]] || echo '{"hooks": {}}' >"$HOOKS"
tmp="$(mktemp)"
if ! jq --arg cmd "$(hook_cmd)" --arg events "$HOOK_EVENTS" "$HOOKS_ADD" "$HOOKS" >"$tmp" 2>/dev/null; then
  warn "${HOOKS/#$HOME/~} is not valid JSON — left it alone, alerts stay off"
elif cmp -s <(jq -S . "$tmp") <(jq -S . "$HOOKS"); then
  ok "Alert hooks already in ${DIM}${HOOKS/#$HOME/~}${NC}"
else
  cp -p "$HOOKS" "$HOOKS.bak.$(date +%Y%m%d%H%M%S)"
  cat "$tmp" >"$HOOKS"
  ok "Added Stop / PermissionRequest hooks to ${DIM}${HOOKS/#$HOME/~}${NC} (backup kept)"
  warn "Codex runs a new hook only once you trust it: in Codex, ${CYAN}/hooks${NC} → trust the two agent-notify hooks"
fi
rm -f "$tmp"
if "$NOTIFY" status &>/dev/null; then
  ok "Channels set ${DIM}(agent-notify status)${NC}"
else
  warn "No channel yet — run ${CYAN}agent-notify setup${NC} to add a Discord webhook or an ntfy topic"
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
echo -e "${GREEN}  ║${NC}  ${CYAN}n${NC} in the sidebar: alerts on / off           ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}                                              ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  Uninstall: ${DIM}install.sh --uninstall${NC}          ${GREEN}║${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ╚═══════════════════════════════════════════════╝${NC}"
echo ""
