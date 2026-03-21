#!/bin/bash
# tmux 상태바용 네트워크 속도 + WiFi 링크 대역폭 (macOS)
# en0 인터페이스의 RX/TX 바이트 변화량 + system_profiler 링크 속도 (60초 캐시)

IFACE="en0"
CACHE="/tmp/tmux_net_speed"
BW_CACHE="/tmp/tmux_net_bandwidth"
BW_TTL=60

read -r rx tx <<< "$(netstat -ib -I "$IFACE" 2>/dev/null | awk 'NR==2 {print $7, $10}')"

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

# WiFi 링크 대역폭 (60초 캐시, system_profiler가 느려서)
bw_str=""
refresh_bw=false
if [[ -f "$BW_CACHE" ]]; then
    bw_ts=$(stat -f %m "$BW_CACHE" 2>/dev/null || echo 0)
    now=$(date +%s)
    (( now - bw_ts >= BW_TTL )) && refresh_bw=true
else
    refresh_bw=true
fi

if $refresh_bw; then
    rate=$(system_profiler SPAirPortDataType 2>/dev/null | awk '/Transmit Rate/{print $NF; exit}')
    if [[ -n "$rate" ]]; then
        if (( rate >= 1000 )); then
            bw_str=$(awk "BEGIN{printf \"%.1fG\", $rate/1000}")
        else
            bw_str="${rate}M"
        fi
        echo "$bw_str" > "$BW_CACHE"
    fi
fi

[[ -z "$bw_str" && -f "$BW_CACHE" ]] && bw_str=$(cat "$BW_CACHE")
[[ -z "$bw_str" ]] && bw_str="--"

echo "$speed_str ($bw_str)"
