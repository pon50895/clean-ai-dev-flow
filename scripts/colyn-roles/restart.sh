#!/usr/bin/env bash
#
# restart.sh — tmux 死掉 / kill-server 後復活。
#
# 適用情境：
# - macOS 重開機後 tmux session 沒了
# - 你不小心 `tmux kill-server`
# - 容器 / colyn 重建後 tmux 從 0 開始
#
# 與 start.sh 的差別：
# - restart.sh 會先把舊 session 完全砍掉（如果還在），然後從零重建
# - 假設 worktree 都還在（沒被 colyn rm 掉）
# - 既有 Claude session 會被新 pane 取代（舊的 conversation context 由 Claude --continue 回復）
#
# 用法：
#   bash scripts/colyn-roles/restart.sh
#   NO_KILL=1 bash scripts/colyn-roles/restart.sh   # 不砍舊 session，只補缺漏（行為等同 start.sh）

set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION="${TMUX_SESSION:-main}"
NO_KILL="${NO_KILL:-0}"

# ----------------------------------------------------------------------------
# 1. 確認 worktree 還在
# ----------------------------------------------------------------------------
ROOT="${WORKSPACE_ROOT:-$HOME/Desktop/parallel-dev-workspace}"
WORKER_NAMES="${WORKER_NAMES:-task-2 task-3 task-4 task-5}"

declare -a WORKERS
read -r -a WORKERS <<< "$WORKER_NAMES"

required_dirs=(
  "$ROOT/main"
  "$ROOT/worktrees/sentinel-monitor"
  "$ROOT/worktrees/reviewer-monitor"
)
for w in "${WORKERS[@]}"; do
  required_dirs+=("$ROOT/worktrees/$w")
done

missing=0
for d in "${required_dirs[@]}"; do
  if [ ! -d "$d" ]; then
    echo "[restart] MISSING worktree: $d" >&2
    missing=1
  fi
done
if [ "$missing" -eq 1 ]; then
  echo "[restart] some worktrees are gone. Run colyn add or git worktree add to recreate them, then re-run restart.sh." >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# 2. 砍舊 session（除非 NO_KILL=1）
# ----------------------------------------------------------------------------
if [ "$NO_KILL" != "1" ]; then
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "[restart] killing existing session '$SESSION' (NO_KILL=1 to skip)"
    tmux kill-session -t "$SESSION"
  else
    echo "[restart] no existing session '$SESSION' to kill"
  fi
else
  echo "[restart] NO_KILL=1 → behaving like start.sh"
fi

# ----------------------------------------------------------------------------
# 3. 委派 start.sh 重建一切
# ----------------------------------------------------------------------------
echo "[restart] delegating to start.sh"
exec bash "$SELF_DIR/start.sh"
