#!/usr/bin/env bash
# send-brief.sh — paste brief file into a tmux pane (avoids settings dialog from inline tmux send-keys)
#
# Usage: bash send-brief.sh <pane-id> <brief-file>
# Example: bash send-brief.sh main:5 /tmp/brief-task-6.md

set -euo pipefail

pane="${1:?pane-id required, e.g. main:5}"
brief="${2:?brief-file path required}"

if [[ ! -f "$brief" ]]; then
  echo "ERROR: brief file $brief not found"
  exit 1
fi

tmux load-buffer "$brief"
tmux paste-buffer -t "$pane"
tmux send-keys -t "$pane" Enter

lines=$(wc -l < "$brief" 2>/dev/null || echo "?")
echo "send-brief: sent $lines lines from $brief to $pane"
