#!/usr/bin/env bash
# 측면 탭 목록 (Prefix + b 로 켜고 끔)
# 켜면 상단 탭 줄을 숨기고 창 왼쪽에 탭 목록 패널을 띄움. 창을 바꾸면 패널이 따라감.
# 패널에서 숫자 키 또는 마우스 클릭으로 탭 이동.
#
#   tab_sidebar.sh toggle <session_id> <window_id>
#   tab_sidebar.sh follow <session_id> <window_id>   (hook에서 호출)
#   tab_sidebar.sh render <session_id>               (사이드바 패널 내부 루프)

WIDTH=28
SELF="$HOME/.tmux/scripts/tab_sidebar.sh"

sidebar_pane() {
  tmux list-panes -s -t "$1" -F '#{pane_id} #{@omc_sidebar}' 2>/dev/null | awk '$2 == "1" { print $1; exit }'
}

open_sidebar() {
  local pane
  pane=$(tmux split-window -t "$2" -hbf -l "$WIDTH" -d -P -F '#{pane_id}' "$SELF render '$1'") || return
  tmux set -p -t "$pane" @omc_sidebar 1
}

toggle() {
  local sess=$1 win=$2 pane
  if [[ "$(tmux show -t "$sess" -qv @omc_sidebar_on)" == "1" ]]; then
    tmux set -t "$sess" -u @omc_sidebar_on
    tmux set -t "$sess" -u status
    tmux set -t "$sess" -u status-format
    pane=$(sidebar_pane "$sess")
    [[ -n "$pane" ]] && tmux kill-pane -t "$pane"
  else
    tmux set -t "$sess" @omc_sidebar_on 1
    tmux set -t "$sess" status on
    tmux set -t "$sess" 'status-format[0]' "#[align=left]#{T;=/#{status-left-length}:status-left}#[align=right]#{T:@omc_widgets}"
    open_sidebar "$sess" "$win"
  fi
}

follow() {
  local sess=$1 win=$2 pane
  [[ "$(tmux show -t "$sess" -qv @omc_sidebar_on)" == "1" ]] || return 0
  pane=$(sidebar_pane "$sess")
  if [[ -z "$pane" ]]; then
    open_sidebar "$sess" "$win"
  elif [[ "$(tmux display -p -t "$pane" '#{window_id}')" != "$win" ]]; then
    tmux join-pane -hbf -l "$WIDTH" -d -s "$pane" -t "$win"
  fi
}

render() {
  local sess=$1 me=$TMUX_PANE key seq row lines=() i active snapshot="" next
  local mouse_re='^\[<0;[0-9]+;([0-9]+)M$'
  printf '\e[?25l\e[?7l\e[?1000h\e[?1006h'
  trap 'printf "\e[?1000l\e[?1006l\e[?7h\e[?25h"' EXIT
  while :; do
    # 탭이 닫혀 사이드바만 남으면 스스로 닫음 (follow가 다음 창에 다시 띄움)
    [[ "$(tmux display -p -t "$me" '#{window_panes}' 2>/dev/null)" == "1" ]] && { tmux kill-pane -t "$me"; exit; }
    lines=()
    while IFS= read -r row; do lines+=("$row"); done < <(tmux list-windows -t "$sess" -F "#{window_index}	#{window_active}	#{?window_bell_flag,!,#{?window_activity_flag,•, }}	#{=/$((WIDTH - 9))/…:window_name}" 2>/dev/null)
    [[ ${#lines[@]} -eq 0 ]] && exit

    # 바뀐 게 있을 때만 다시 그림 (깜빡임 방지)
    next="$(tmux display -p -t "$me" '#{pane_height}')|${lines[*]}"
    if [[ "$next" != "$snapshot" ]]; then
      snapshot=$next
      printf '\e[H\e[2J\e[1;38;2;250;179;135m %s\e[0m\n\n' "$(tmux display -p -t "$sess" '#{session_name}')"
      for i in "${!lines[@]}"; do
        IFS=$'\t' read -r idx active flag name <<<"${lines[$i]}"
        if [[ "$active" == "1" ]]; then
          printf '\e[1;38;2;17;17;27;48;2;250;179;135m %2s \e[0;1;48;2;69;71;90m %s %s\e[K\e[0m\n' "$idx" "$flag" "$name"
        else
          printf '\e[38;2;127;132;156m %2s \e[0m %s \e[38;2;166;173;200m%s\e[0m\n' "$idx" "$flag" "$name"
        fi
      done
    fi

    IFS= read -rsn1 -t 1 key || continue
    if [[ "$key" == $'\e' ]]; then
      # SGR 마우스: ESC [ < btn ; x ; y M
      seq=""
      while IFS= read -rsn1 -t 1 key; do
        seq+=$key
        [[ "$key" == [Mm] ]] && break
      done
      [[ "$seq" =~ $mouse_re ]] || continue
      row=$((BASH_REMATCH[1] - 3))
      (( row >= 0 && row < ${#lines[@]} )) || continue
      IFS=$'\t' read -r idx _ <<<"${lines[$row]}"
    elif [[ "$key" == [0-9] ]]; then
      idx=$key
    else
      continue
    fi
    tmux select-window -t "$sess:$idx" 2>/dev/null
    # 같은 창을 골랐으면 포커스를 원래 패널로 돌려줌
    [[ "$(tmux display -p -t "$me" '#{pane_active}')" == "1" ]] && tmux last-pane -t "$me" 2>/dev/null
  done
}

case "$1" in
  toggle) toggle "$2" "$3" ;;
  follow) follow "$2" "$3" ;;
  render) render "$2" ;;
esac
exit 0
