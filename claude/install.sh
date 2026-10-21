#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/rapidrabbit76/oh-my-config.git"
OMC_HOME="${OMC_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/oh-my-config}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
KEYBINDINGS="$CLAUDE_DIR/keybindings.json"
MARKETPLACE="oh-my-config"
PLUGIN="opencode-sidebar@$MARKETPLACE"
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
  SCRIPT_DIR="$CLEANUP_DIR/claude"
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

# Adds our bindings to the user's file. A chord the user already binds keeps
# the user's action. Keep in sync with sync_claude in ../update.sh
KEYBINDINGS_MERGE='.[1].bindings as $ours | .[0] | .bindings = (reduce $ours[] as $b (.bindings // [];
  if any(.[]; .context == $b.context)
  then map(if .context == $b.context
    then .bindings as $m | .bindings = $m + ($b.bindings | with_entries(select(.key as $k | $m | has($k) | not)))
    else . end)
  else . + [$b] end))'

# Removes exactly the bindings we added (same chord, same action).
KEYBINDINGS_UNMERGE='.[1].bindings as $ours | .[0] | .bindings |= (map(.context as $c | .bindings |= with_entries(
  .key as $k | .value as $v
  | select([$ours[] | select(.context == $c) | .bindings | select(has($k)) | .[$k] == $v] | any | not)))
  | map(select(.bindings != {})))'

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
    ║              ✳  Claude Code                    ║
    ║         opencode-style sidebar + keys          ║
    ║                                               ║
    ╚═══════════════════════════════════════════════╝
BANNER
  echo -e "${NC}"
  echo -e "  ${DIM}session sidebar · ctrl+x leader keys · git / PR / MCP status${NC}"
  echo ""
}

# ─── Uninstall ───────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
  echo ""
  echo -e "${BOLD}${RED}  Uninstalling oh-my-config claude...${NC}"
  echo ""

  if command -v claude &>/dev/null; then
    claude plugin uninstall "$PLUGIN" &>/dev/null && ok "Removed plugin $PLUGIN" || warn "Plugin $PLUGIN was not installed"
    claude plugin marketplace remove "$MARKETPLACE" &>/dev/null && ok "Removed marketplace $MARKETPLACE" || true
  fi
  if [[ -f "$KEYBINDINGS" ]] && command -v jq &>/dev/null; then
    cp -p "$KEYBINDINGS" "$KEYBINDINGS.bak.$(date +%Y%m%d%H%M%S)"
    tmp="$(mktemp)"
    jq -s "$KEYBINDINGS_UNMERGE" "$KEYBINDINGS" "$SCRIPT_DIR/keybindings.json" >"$tmp" && mv "$tmp" "$KEYBINDINGS"
    ok "Removed ctrl+x bindings from ${DIM}${KEYBINDINGS/#$HOME/~}${NC} (backup kept)"
  fi
  sed -i.bak '/^claude$/d' "$HOME/.config/oh-my-config/components" 2>/dev/null && rm -f "$HOME/.config/oh-my-config/components.bak" || true

  echo ""
  ok "Uninstall complete"
  exit 0
fi

show_banner

# ─── [1/4] Pre-flight ───────────────────────────────────
echo -e "${BOLD}  [1/4] Pre-flight checks${NC}"
echo ""

if ! command -v claude &>/dev/null; then
  error "claude not found — install Claude Code first: https://code.claude.com"
  exit 1
fi
ok "claude $(claude --version 2>/dev/null | awk '{print $1}')"

if ! command -v jq &>/dev/null; then
  error "jq not found — needed to merge keybindings (brew install jq / apt install jq)"
  exit 1
fi
ok "jq"

command -v git &>/dev/null && ok "git" || warn "git not found — sidebar git status stays empty"
command -v gh &>/dev/null && ok "gh ${DIM}(PR status)${NC}" || warn "gh not found — sidebar PR status stays empty (optional)"

# ─── [2/4] Repo clone (also the plugin's source) ─────────
echo ""
echo -e "${BOLD}  [2/4] Auto-update clone${NC}"
echo ""

# The plugin is read straight from this clone, so update.sh keeps it current.
if bash "$SCRIPT_DIR/../update.sh" --register claude 2>/dev/null; then
  ok "Clone at ${DIM}${OMC_HOME/#$HOME/~}${NC} · update check on"
else
  error "Could not set up ${OMC_HOME/#$HOME/~}"
  exit 1
fi

# ─── [3/4] Keybindings ──────────────────────────────────
echo ""
echo -e "${BOLD}  [3/4] Keybindings${NC}"
echo ""

mkdir -p "$CLAUDE_DIR"
if [[ -f "$KEYBINDINGS" ]]; then
  tmp="$(mktemp)"
  jq -s "$KEYBINDINGS_MERGE" "$KEYBINDINGS" "$SCRIPT_DIR/keybindings.json" >"$tmp"
  if cmp -s <(jq -S . "$tmp") <(jq -S . "$KEYBINDINGS"); then
    rm -f "$tmp"
    ok "Already set in ${DIM}${KEYBINDINGS/#$HOME/~}${NC}"
  else
    cp -p "$KEYBINDINGS" "$KEYBINDINGS.bak.$(date +%Y%m%d%H%M%S)"
    mv "$tmp" "$KEYBINDINGS"
    ok "Merged into ${DIM}${KEYBINDINGS/#$HOME/~}${NC} (backup kept)"
  fi
  # Chords the user had bound to something else keep the user's action.
  taken="$(jq -r -s '.[1].bindings as $ours | .[0].bindings as $mine
    | [$ours[] as $b | $b.bindings | to_entries[] as $e
       | $mine[] | select(.context == $b.context) | .bindings[$e.key] // empty
       | select(. != $e.value) | $e.key] | unique | join(", ")' "$KEYBINDINGS" "$SCRIPT_DIR/keybindings.json")"
  [[ -n "$taken" ]] && warn "Kept your own action on: $taken"
else
  cp "$SCRIPT_DIR/keybindings.json" "$KEYBINDINGS"
  ok "Wrote ${DIM}${KEYBINDINGS/#$HOME/~}${NC}"
fi

# ─── [4/4] Sidebar plugin ───────────────────────────────
echo ""
echo -e "${BOLD}  [4/4] Sidebar plugin${NC}"
echo ""

if claude plugin marketplace list 2>/dev/null | grep -qE "❯ $MARKETPLACE\$"; then
  ok "Marketplace $MARKETPLACE already added"
elif claude plugin marketplace add "$OMC_HOME" &>/dev/null; then
  ok "Added marketplace $MARKETPLACE ${DIM}(${OMC_HOME/#$HOME/~})${NC}"
else
  error "Could not add marketplace — run: claude plugin marketplace add ${OMC_HOME/#$HOME/~}"
  exit 1
fi

if claude plugin install "$PLUGIN" --scope user &>/dev/null; then
  ok "Installed $PLUGIN"
else
  error "Could not install — run: claude plugin install $PLUGIN"
  exit 1
fi

# ─── Done ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}  ╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║         Installation complete! 🎉             ║${NC}"
echo -e "${GREEN}  ╠═══════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}/sidebar${NC}    toggle the session sidebar      ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}ctrl+x l${NC}    sessions   ${CYAN}ctrl+x n${NC}  new       ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}ctrl+x m${NC}    model      ${CYAN}ctrl+x t${NC}  theme     ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}                                              ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  Open sessions: run ${CYAN}/reload-plugins${NC}          ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  Uninstall: ${DIM}install.sh --uninstall${NC}          ${GREEN}║${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ╚═══════════════════════════════════════════════╝${NC}"
echo ""
