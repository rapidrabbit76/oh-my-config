#!/bin/bash
# tmux 상태바용 공인 IP (5분 캐시)
# API 호출을 최소화하기 위해 캐시 사용

CACHE="/tmp/tmux_public_ip"
TTL=300

get_file_mtime() {
  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f %m "$1" 2>/dev/null || echo 0
  else
    stat -c %Y "$1" 2>/dev/null || echo 0
  fi
}

if [[ -f "$CACHE" ]]; then
  cached_ts=$(get_file_mtime "$CACHE")
  now=$(date +%s)
  age=$((now - cached_ts))

  if (( age < TTL )); then
    cat "$CACHE"
    exit 0
  fi
fi

ip=$(curl -s --connect-timeout 2 --max-time 3 ifconfig.me 2>/dev/null)

if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "$ip" > "$CACHE"
  chmod 600 "$CACHE"
  echo "$ip"
else
  [[ -f "$CACHE" ]] && cat "$CACHE" || echo "N/A"
fi
