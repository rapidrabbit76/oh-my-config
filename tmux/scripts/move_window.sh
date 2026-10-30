#!/usr/bin/env bash
# 현재 탭(window)을 다른 세션으로 옮김 (Prefix + M, 팝업 안에서 실행)
# fzf로 대상 세션을 고르면 그 세션 끝에 붙이고 클라이언트도 따라감.
# 목록에 없는 이름을 치고 Enter 하면 그 이름으로 새 세션을 만들어 옮김.
#
#   move_window.sh            원본 창 id / 세션은 @omc_mv_wid, @omc_mv_cur 옵션에서 읽음
#   (display-popup 은 포맷을 펼치지 않아 키 바인딩에서 set -gF 로 담아둠)

wid=$(tmux show -gv @omc_mv_wid 2>/dev/null)
cur=$(tmux show -gv @omc_mv_cur 2>/dev/null)
[ -n "$wid" ] || exit 1

target=$(tmux list-sessions -F $'#{session_name}\t#{session_windows} win' \
  | grep -v "^${cur}"$'\t' \
  | fzf --reverse --delimiter=$'\t' --prompt='세션> ' \
      --header='Enter: 이 세션으로 · 새 이름 + Enter: 새 세션으로 · Esc: 취소' \
      --print-query | tail -1 | cut -f1)
target=$(printf %s "$target" | tr -c 'A-Za-z0-9_-' _)
[ -n "$target" ] || exit 0

tmux has-session -t "=$target" 2>/dev/null || tmux new-session -d -s "$target"
# 원본 세션에 창이 하나뿐이면 옮기는 순간 세션이 사라지므로 클라이언트를 먼저 옮김
tmux switch-client -t "=$target"
tmux move-window -s "$wid" -t "=$target:"
tmux select-window -t "$wid"
