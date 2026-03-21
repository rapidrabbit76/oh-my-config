#!/bin/bash
# tmux 상태바용 네트워크 속도 + WiFi 링크 대역폭 (macOS / Linux)
# macOS: netstat -ib + system_profiler, Linux: /sys/class/net + iw/iwconfig

CACHE="/tmp/tmux_net_speed"
BW_CACHE="/tmp/tmux_net_bandwidth"
BW_TTL=60
OS="$(uname)"

detect_iface() {
  if [[ "$OS" == "Darwin" ]]; then
    echo "en0"
  else
    ip route 2>/dev/null | awk '/default/{print $5; exit}' || echo "eth0"
  fi
}

IFACE=$(detect_iface)

get_bytes() {
  if [[ "$OS" == "Darwin" ]]; then
    netstat -ib -I "$IFACE" 2>/dev/null | awk 'NR==2 {print $7, $10}'
  else
    local rx_file="/sys/class/net/$IFACE/statistics/rx_bytes"
    local tx_file="/sys/class/net/$IFACE/statistics/tx_bytes"
    if [[ -f "$rx_file" && -f "$tx_file" ]]; then
      echo "$(cat "$rx_file") $(cat "$tx_file")"
    fi
  fi
}

read -r rx tx <<< "$(get_bytes)"

if [[ -z "$rx" || -z "$tx" ]]; then
  echo "↓-- ↑--"
  exit 0
fi

human() {
  local b=$1
  if (( b >= 1073741824 )); then
    awk "BEGIN{printf \"%.1fG\", $b/1073741824}"
  elif (( b >= 1048576 )); then
    awk "BEGIN{printf \"%.1fM\", $b/1048576}"
  elif (( b >= 1024 )); then
    awk "BEGIN{printf \"%.0fK\", $b/1024}"
  else
    echo "${b}B"
  fi
}

speed_str="↓-- ↑--"
if [[ -f "$CACHE" ]]; then
  read -r prev_rx prev_tx prev_ts < "$CACHE"
  now=$(date +%s)
  dt=$((now - prev_ts))
  [[ $dt -lt 1 ]] && dt=1

  drx=$(( (rx - prev_rx) / dt ))
  dtx=$(( (tx - prev_tx) / dt ))

  # 음수 방지 (인터페이스 리셋 등)
  [[ $drx -lt 0 ]] && drx=0
  [[ $dtx -lt 0 ]] && dtx=0

  speed_str="↓$(human $drx) ↑$(human $dtx)"
fi
echo "$rx $tx $(date +%s)" > "$CACHE"
chmod 600 "$CACHE"

# WiFi 링크 대역폭 (60초 캐시, system_profiler/iw 가 느려서)
get_wifi_bandwidth() {
  if [[ "$OS" == "Darwin" ]]; then
    system_profiler SPAirPortDataType 2>/dev/null | awk '/Transmit Rate/{print $NF; exit}'
  else
    iw dev "$IFACE" link 2>/dev/null | awk '/tx bitrate/{print int($3); exit}' || \
      iwconfig "$IFACE" 2>/dev/null | awk -F'[:=]' '/Bit Rate/{gsub(/ .*/,"",$2); print int($2); exit}'
  fi
}

bw_str=""
refresh_bw=false
if [[ -f "$BW_CACHE" ]]; then
  if [[ "$OS" == "Darwin" ]]; then
    bw_ts=$(stat -f %m "$BW_CACHE" 2>/dev/null || echo 0)
  else
    bw_ts=$(stat -c %Y "$BW_CACHE" 2>/dev/null || echo 0)
  fi
  now=$(date +%s)
  (( now - bw_ts >= BW_TTL )) && refresh_bw=true
else
  refresh_bw=true
fi

if $refresh_bw; then
  rate=$(get_wifi_bandwidth)
  if [[ -n "$rate" && "$rate" -gt 0 ]] 2>/dev/null; then
    if (( rate >= 1000 )); then
      bw_str=$(awk "BEGIN{printf \"%.1fG\", $rate/1000}")
    else
      bw_str="${rate}M"
    fi
    echo "$bw_str" > "$BW_CACHE"
    chmod 600 "$BW_CACHE"
  fi
fi

[[ -z "$bw_str" && -f "$BW_CACHE" ]] && bw_str=$(cat "$BW_CACHE")
[[ -z "$bw_str" ]] && bw_str="--"

echo "$speed_str ($bw_str)"
