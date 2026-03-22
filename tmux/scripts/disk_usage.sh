#!/bin/bash
# tmux status bar disk usage.
# On macOS, user data lives on /System/Volumes/Data rather than /.

target="/"
if [[ "$(uname)" == "Darwin" ]]; then
  target="/System/Volumes/Data"
fi

usage=$(df -h "$target" | awk 'NR==2 {print $5}')
echo "${usage}"
