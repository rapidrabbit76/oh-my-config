#!/bin/bash
# tmux 상태바용 디스크 사용량 (루트 파티션)

usage=$(df -h / | awk 'NR==2 {print $5}')
echo "${usage}"
