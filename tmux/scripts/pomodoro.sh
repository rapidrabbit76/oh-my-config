#!/bin/bash
# tmux 상태바용 포모도로 타이머
# 사용법:
#   pomodoro.sh          → 현재 상태 표시 (tmux 상태바용)
#   pomodoro.sh start    → 25분 작업 시작
#   pomodoro.sh break    → 5분 휴식 시작
#   pomodoro.sh stop     → 정지
#   pomodoro.sh toggle   → 시작/정지 토글

STATE="/tmp/tmux_pomodoro"
WORK_MIN=25
BREAK_MIN=5

case "${1:-display}" in
    start)
        echo "work $(date +%s) $((WORK_MIN * 60))" > "$STATE"
        tmux display-message "🍅 포모도로 ${WORK_MIN}분 시작!"
        ;;
    break)
        echo "break $(date +%s) $((BREAK_MIN * 60))" > "$STATE"
        tmux display-message "☕ 휴식 ${BREAK_MIN}분 시작!"
        ;;
    stop)
        rm -f "$STATE"
        tmux display-message "⏹ 포모도로 정지"
        ;;
    toggle)
        if [[ -f "$STATE" ]]; then
            rm -f "$STATE"
            tmux display-message "⏹ 포모도로 정지"
        else
            echo "work $(date +%s) $((WORK_MIN * 60))" > "$STATE"
            tmux display-message "🍅 포모도로 ${WORK_MIN}분 시작!"
        fi
        ;;
    display)
        if [[ ! -f "$STATE" ]]; then
            echo "🍅 --:--"
            exit 0
        fi

        read -r mode start_ts duration < "$STATE"
        now=$(date +%s)
        elapsed=$((now - start_ts))
        remaining=$((duration - elapsed))

        if (( remaining <= 0 )); then
            if [[ "$mode" == "work" ]]; then
                # 작업 끝 → 자동으로 휴식 전환
                echo "break $(date +%s) $((BREAK_MIN * 60))" > "$STATE"
                tmux display-message "✅ 작업 완료! 휴식 시작 ☕"
                echo "☕ ${BREAK_MIN}:00"
            else
                # 휴식 끝
                rm -f "$STATE"
                tmux display-message "🔔 휴식 끝! 다시 집중하세요"
                echo "🍅 --:--"
            fi
            exit 0
        fi

        min=$((remaining / 60))
        sec=$((remaining % 60))

        if [[ "$mode" == "work" ]]; then
            printf "🍅 %02d:%02d" $min $sec
        else
            printf "☕ %02d:%02d" $min $sec
        fi
        ;;
esac
