#!/usr/bin/env bash
# 호스트 특성을 한 번만 감지해서 상태바 설정으로 저장 (설치 시, 또는 기존 설치의 첫 업데이트 때)
# 배터리가 없는 서버/컨테이너에서는 배터리 위젯을 뺌. 다시 감지하려면 host.conf를 지우고 재실행.

OUT="$HOME/.config/oh-my-config/tmux/host.conf"

has_battery() {
  if [[ "$(uname)" == "Darwin" ]]; then
    pmset -g batt 2>/dev/null | grep -q InternalBattery
  else
    grep -qsx Battery /sys/class/power_supply/*/type
  fi
}

mkdir -p "$(dirname "$OUT")"
{
  echo "# Generated once by ~/.tmux/scripts/detect_host.sh — delete this file and re-run to detect again"
  if has_battery; then echo "set -g @omc_battery on"; else echo "set -g @omc_battery off"; fi
} >"$OUT"
