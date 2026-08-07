#!/usr/bin/env bash
# start-fleet.sh — manual cold-start the entire 9-pane AI dev fleet
#
# Idempotent: re-runs are safe (skips already-running panes).
#
# Layout:
#   main:0 supervisor   (Opus 4.7, main worktree)
#   main:1 dispatcher   (Sonnet 4.6, sentinel-monitor)
#   main:2 reviewer     (Sonnet 4.6, reviewer-monitor)
#   main:3 task-2       (Sonnet 4.6, worktrees/task-2)
#   main:4 task-3       (Sonnet 4.6/Opus 4.7, worktrees/task-3)
#   main:5 task-6       (Sonnet 4.6, worktrees/task-6)
#   main:6 task-5       (Sonnet 4.6, worktrees/task-5)
#   main:7 task-7       (Sonnet 4.6, worktrees/task-7)
#   main:8 tester       (Sonnet 4.6, main worktree)
#
# Usage:
#   bash scripts/start-fleet.sh              # idempotent boot
#   FORCE_RELAUNCH=1 bash scripts/start-fleet.sh   # kill + restart all panes
#
# After: tmux attach -t main

set -euo pipefail

: "${ROOT:=}"
if [ -z "$ROOT" ]; then
  echo "ERROR: ROOT not set. Export ROOT=/path/to/workspace (parent dir containing main/ + worktrees/)" >&2
  echo "  example: ROOT=\$HOME/Desktop/my-project bash scripts/start-fleet.sh" >&2
  exit 2
fi
MAIN="$ROOT/main"
WT="$ROOT/worktrees"
COLYN="$MAIN/scripts/colyn-roles"
SESSION="${TMUX_SESSION:-main}"
FORCE="${FORCE_RELAUNCH:-0}"

# Brief files
BRIEF_SUPERVISOR="$COLYN/supervisor-bootstrap-brief.md"  # may not exist yet — fallback to role-supervisor.md
BRIEF_DISPATCHER="$COLYN/dispatcher-bootstrap-brief.md"
BRIEF_REVIEWER="$COLYN/reviewer-bootstrap-brief.md"
BRIEF_TESTER="$COLYN/tester-bootstrap-brief.md"

# Pane definitions: idx | name | cwd | brief | model
PANES=(
  "0|supervisor|$MAIN|$BRIEF_SUPERVISOR|claude-opus-4-8"
  "1|dispatcher|$WT/sentinel-monitor|$BRIEF_DISPATCHER|claude-sonnet-4-6"
  "2|reviewer|$WT/reviewer-monitor|$BRIEF_REVIEWER|claude-sonnet-4-6"
  "3|task-2|$WT/task-2||claude-sonnet-4-6"
  "4|task-3|$WT/task-3||claude-sonnet-4-6"
  "5|task-6|$WT/task-6||claude-sonnet-4-6"
  "6|task-5|$WT/task-5||claude-sonnet-4-6"
  "7|task-7|$WT/task-7||claude-sonnet-4-6"
  "8|tester|$MAIN|$BRIEF_TESTER|claude-sonnet-4-6"
)

# 1. Ensure session exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[fleet] creating tmux session '$SESSION'"
  tmux new-session -d -s "$SESSION" -n "supervisor" -c "$MAIN"
fi

# 2. Ensure each window
ensure_window() {
  local idx="$1" name="$2" cwd="$3"
  if tmux list-windows -t "$SESSION" -F '#I' | grep -qx "$idx"; then
    echo "  [main:$idx] $name window exists"
  else
    echo "  [main:$idx] $name CREATE cwd=$cwd"
    tmux new-window -t "$SESSION:$idx" -k -n "$name" -c "$cwd"
  fi
}

is_claude_running() {
  local pane="$1"
  local cmd
  cmd=$(tmux display-message -p -t "$pane" '#{pane_current_command}' 2>/dev/null || echo "zsh")
  case "$cmd" in
    zsh|bash|sh|fish) return 1 ;;
    *) return 0 ;;  # likely Claude (shows version like "2.1.133")
  esac
}

boot_claude() {
  local pane="$1" model="$2" brief="$3"
  if is_claude_running "$pane" && [ "$FORCE" != "1" ]; then
    echo "    [main:$pane] Claude already running — skip (use FORCE_RELAUNCH=1 to override)"
    return 0
  fi

  if [ "$FORCE" = "1" ] && is_claude_running "$pane"; then
    echo "    [main:$pane] FORCE — sending /exit"
    tmux send-keys -t "$pane" "/exit" Enter
    sleep 2
    tmux send-keys -t "$pane" Enter  # confirm exit
    sleep 2
  fi

  echo "    [main:$pane] booting claude (model=$model)"
  tmux send-keys -t "$pane" "claude" Enter
  sleep 6
  if [ "$model" != "claude-sonnet-4-6" ]; then
    # Sonnet is the default for Max plan; only switch if different
    tmux send-keys -t "$pane" "/model $model" Enter
    sleep 3
  fi

  if [ -n "$brief" ] && [ -f "$brief" ]; then
    echo "    [main:$pane] paste brief: $(basename $brief)"
    tmux load-buffer "$brief"
    tmux paste-buffer -t "$pane"
    tmux send-keys -t "$pane" Enter
    sleep 1
  else
    echo "    [main:$pane] no brief (or brief file missing) — manual bootstrap needed"
  fi
}

echo "=== Phase 1: ensure 9 windows ==="
for entry in "${PANES[@]}"; do
  IFS='|' read -r idx name cwd brief model <<< "$entry"
  ensure_window "$idx" "$name" "$cwd"
done

echo ""
echo "=== Phase 2: boot Claude in each pane ==="
for entry in "${PANES[@]}"; do
  IFS='|' read -r idx name cwd brief model <<< "$entry"
  pane="$SESSION:$idx"
  echo "  [$idx] $name"
  boot_claude "$pane" "$model" "$brief"
done

echo ""
echo "=== Phase 3: setup lifecycle-sweep cron (5min cadence) ==="
# Note: requires user manually run a CronCreate from supervisor pane to schedule auto-sweep
echo "  Manual step: from supervisor (main:0), run:"
echo "    bash scripts/skill.sh lifecycle-sweep"
echo "  Or schedule via cron / ScheduleWakeup once supervisor is booted."

echo ""
echo "=== DONE ==="
echo ""
echo "Attach to fleet:"
echo "  tmux attach -t $SESSION"
echo ""
echo "Quick status:"
echo "  bash scripts/skill.sh fleet-status"
