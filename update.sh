#!/usr/bin/env bash
# oh-my-config updater — keeps a clone of the repo and re-syncs installed configs.
#
#   update.sh                     Update now (fetch + sync every installed component)
#   update.sh --auto              Shell startup hook: asks "Update now? [Y/n]" when a check found
#                                 a new version (checks run once a day in the background)
#   update.sh --register <name>   Called by installers (tmux | yazi | nvim)
#
# Only config files are synced. Packages, ~/.zshrc and *.local files are never touched.
# Local edits are kept; if upstream changed the same file, the local copy is saved as
# <file>.bak.<timestamp> and replaced.
# Disable the startup prompt with: export OMC_DISABLE_AUTO_UPDATE=1

REPO_URL="https://github.com/rapidrabbit76/oh-my-config.git"
OMC_HOME="${OMC_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/oh-my-config}"
COMPONENTS_FILE="$HOME/.config/oh-my-config/components"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-config"
INTERVAL=$((24 * 60 * 60))
HOOK_MARKER="# oh-my-config auto-update"

OLD_REV=""
CHANGED=()

ensure_clone() {
  [[ -d "$OMC_HOME/.git" ]] && return 0
  mkdir -p "$(dirname "$OMC_HOME")"
  git clone -q --depth 1 "$REPO_URL" "$OMC_HOME"
}

# sync_file <path in repo> <destination>
sync_file() {
  local src="$OMC_HOME/$1" dest=$2
  [[ -f "$src" ]] || return 0
  cmp -s "$src" "$dest" && return 0
  if [[ -f "$dest" && -n "$OLD_REV" ]] &&
    ! git -C "$OMC_HOME" show "$OLD_REV:$1" 2>/dev/null | cmp -s - "$dest"; then
    # Edited locally: keep it unless upstream changed this file too
    git -C "$OMC_HOME" show "$OLD_REV:$1" 2>/dev/null | cmp -s - "$src" && return 0
    cp -p "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  CHANGED+=("$dest")
}

# Keep these lists in sync with each component's install.sh
sync_tmux() {
  local before=${#CHANGED[@]} f
  sync_file tmux/.tmux.conf "$HOME/.config/oh-my-config/tmux/.tmux.conf"
  for f in "$OMC_HOME"/tmux/scripts/*.sh; do
    sync_file "tmux/scripts/${f##*/}" "$HOME/.tmux/scripts/${f##*/}"
    chmod +x "$HOME/.tmux/scripts/${f##*/}"
  done
  # Installs from before detect_host.sh existed: detect once
  [[ -f "$HOME/.config/oh-my-config/tmux/host.conf" ]] || "$HOME/.tmux/scripts/detect_host.sh"
  if (( ${#CHANGED[@]} > before )) && tmux info &>/dev/null; then
    tmux source-file "$HOME/.tmux.conf" &>/dev/null
  fi
}

sync_yazi() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/yazi" f
  for f in yazi.toml keymap.toml theme.toml init.lua \
    plugins/mediainfo.yazi/main.lua plugins/compress-each.yazi/main.lua; do
    sync_file "yazi/$f" "$dir/$f"
  done
  sync_file yazi/scripts/smart-open "$HOME/.local/bin/smart-open"
  chmod +x "$HOME/.local/bin/smart-open" 2>/dev/null
}

sync_nvim() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim" f
  # lua/plugins/colorscheme.lua is the theme picked at install time, so it is left alone
  for f in init.lua .neoconf.json lazyvim.json stylua.toml \
    lua/config/lazy.lua lua/config/options.lua lua/config/keymaps.lua lua/config/autocmds.lua \
    lua/plugins/example.lua; do
    sync_file "nvim/$f" "$dir/$f"
  done
}

install_hook() {
  local rc="$HOME/.zshrc" home='$HOME'
  [[ -f "$rc" ]] || rc="$HOME/.bashrc"
  grep -qF "$HOOK_MARKER" "$rc" 2>/dev/null && return 0
  printf '\n%s (asks before updating config files)\n[[ -f "%s/update.sh" ]] && bash "%s/update.sh" --auto\n' \
    "$HOOK_MARKER" "${OMC_HOME/#$HOME/$home}" "${OMC_HOME/#$HOME/$home}" >>"$rc"
}

register() {
  case "$1" in tmux | yazi | nvim) ;; *) echo "unknown component: $1" >&2; return 1 ;; esac
  ensure_clone || return 1
  mkdir -p "$(dirname "$COMPONENTS_FILE")"
  grep -qx "$1" "$COMPONENTS_FILE" 2>/dev/null || echo "$1" >>"$COMPONENTS_FILE"
  install_hook
}

lock() {
  mkdir -p "$CACHE_DIR"
  mkdir "$CACHE_DIR/lock" 2>/dev/null || return 1
  trap 'rmdir "$CACHE_DIR/lock" 2>/dev/null' EXIT
  date +%s >"$CACHE_DIR/last-check"
}

update() {
  local new_rev comp tilde='~'
  lock || { echo "oh-my-config: another update is running" >&2; return 1; }
  rm -f "$CACHE_DIR/available"

  ensure_clone || return 1
  OLD_REV=$(git -C "$OMC_HOME" rev-parse HEAD)
  git -C "$OMC_HOME" fetch -q --depth 1 origin main &&
    git -C "$OMC_HOME" reset -q --hard FETCH_HEAD || return 1
  new_rev=$(git -C "$OMC_HOME" rev-parse HEAD)

  while read -r comp; do
    case "$comp" in tmux | yazi | nvim) "sync_$comp" ;; esac
  done <"$COMPONENTS_FILE"

  if (( ${#CHANGED[@]} )); then
    [[ "$new_rev" == "$OLD_REV" ]] && echo "oh-my-config ${new_rev:0:7}" || echo "oh-my-config ${OLD_REV:0:7} → ${new_rev:0:7}"
    printf '  updated %s\n' "${CHANGED[@]/#$HOME/$tilde}"
  else
    echo "oh-my-config is up to date (${new_rev:0:7})"
  fi
}

# Background: only look for a new version, never change anything
check() {
  local new_rev
  lock || return 0
  ensure_clone || return 1
  git -C "$OMC_HOME" fetch -q --depth 1 origin main || return 1
  new_rev=$(git -C "$OMC_HOME" rev-parse FETCH_HEAD)
  [[ "$new_rev" == "$(git -C "$OMC_HOME" rev-parse HEAD)" ]] && return 0
  [[ "$new_rev" == "$(cat "$CACHE_DIR/skipped" 2>/dev/null)" ]] && return 0
  echo "$new_rev" >"$CACHE_DIR/available"
}

# Shell startup: ask about a version found by an earlier check, then maybe start a new check
auto() {
  [[ "${OMC_DISABLE_AUTO_UPDATE:-}" == 1 ]] && return 0
  [[ -t 0 && -t 1 ]] || return 0
  local new_rev answer last tilde='~'
  if [[ -f "$CACHE_DIR/available" ]]; then
    new_rev=$(cat "$CACHE_DIR/available")
    printf '[oh-my-config] Update available (%s → %s). Update now? [Y/n] ' \
      "$(git -C "$OMC_HOME" rev-parse --short HEAD)" "${new_rev:0:7}"
    read -r answer
    if [[ "$answer" == [nN]* ]]; then
      rm -f "$CACHE_DIR/available"
      echo "$new_rev" >"$CACHE_DIR/skipped"
      echo "[oh-my-config] Skipped. Update later with: bash ${OMC_HOME/#$HOME/$tilde}/update.sh"
    else
      update
    fi
    return 0
  fi
  last=$(cat "$CACHE_DIR/last-check" 2>/dev/null || echo 0)
  (( $(date +%s) - last < INTERVAL )) && return 0
  (nohup bash "$0" --check </dev/null >/dev/null 2>&1 &)
}

main() {
  case "${1:-}" in
    --auto) auto ;;
    --check) check ;;
    --register) register "${2:-}" ;;
    "") update ;;
    *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; return 1 ;;
  esac
}

# Everything runs from main so a `git reset` of this very file mid-run cannot break parsing
main "$@"; exit $?
