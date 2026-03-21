#!/bin/bash
# tmux 상태바용 공인 IP (5분 캐시)
# API 호출을 최소화하기 위해 캐시 사용

CACHE="/tmp/tmux_public_ip"
TTL=300  # 5분

if [[ -f "$CACHE" ]]; then
    cached_ts=$(stat -f %m "$CACHE" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$((now - cached_ts))

    if (( age < TTL )); then
        cat "$CACHE"
        exit 0
    fi
fi

# 백그라운드에서 갱신 (상태바 블로킹 방지)
ip=$(curl -s --connect-timeout 2 --max-time 3 ifconfig.me 2>/dev/null)

if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$ip" > "$CACHE"
    echo "$ip"
else
    [[ -f "$CACHE" ]] && cat "$CACHE" || echo "N/A"
fi
