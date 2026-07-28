#!/usr/bin/env bash
#
# roles.sh — single-pane Claude launcher for parallel-dev roles.
#
# 用法（在已 attach 進去的 pane 直接跑）：
#   bash scripts/colyn-roles/roles.sh supervisor
#   bash scripts/colyn-roles/roles.sh alarm
#   bash scripts/colyn-roles/roles.sh reviewer
#   bash scripts/colyn-roles/roles.sh worker task-3
#   bash scripts/colyn-roles/roles.sh worker task-3 claude-opus-4-7   # 模型覆寫
#
# 不會 kill 已存在的 Claude；直接 exec claude 取代當前 shell。

set -euo pipefail

ROOT="${WORKSPACE_ROOT:-$HOME/Desktop/parallel-dev-workspace}"
WORKER_MODEL="${WORKER_MODEL:-claude-sonnet-4-6}"

MODEL_OPUS="claude-opus-4-8"
MODEL_SONNET="claude-sonnet-4-6"
MODEL_HAIKU="claude-haiku-4-5-20251001"

# 解析腳本所在目錄（用於找 role-*.md cheatsheet）
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

role="${1:-}"
if [ -z "$role" ]; then
  cat <<EOF >&2
usage: $0 <role> [worker-name] [model-override]

  supervisor                     -> $MODEL_OPUS  in $ROOT/main
  alarm                          -> $MODEL_HAIKU in $ROOT/worktrees/sentinel-monitor
  reviewer                       -> $MODEL_SONNET in $ROOT/worktrees/reviewer-monitor
  worker <name> [model]          -> \$model      in $ROOT/worktrees/<name>
                                    (預設 worker model: $WORKER_MODEL)
EOF
  exit 2
fi

launch_claude() {
  local cwd="$1"
  local model="$2"
  local role_card="$3"
  local session_name="$4"

  cd "$cwd"

  local sys_prompt
  if [ -f "$role_card" ]; then
    sys_prompt="$(cat "$role_card")"
  else
    sys_prompt="You are running as role '$session_name' under the parallel-dev tmux setup. Read CLAUDE.md and dev-rule/ on startup."
  fi

  echo "[roles.sh] role=$session_name model=$model cwd=$cwd"
  echo "[roles.sh] role-card: $role_card"
  exec claude \
    --model "$model" \
    --name "$session_name" \
    --append-system-prompt "$sys_prompt"
}

case "$role" in
  supervisor)
    launch_claude "$ROOT/main" "$MODEL_OPUS" "$SELF_DIR/role-supervisor.md" "supervisor"
    ;;
  alarm)
    launch_claude "$ROOT/worktrees/sentinel-monitor" "$MODEL_HAIKU" "$SELF_DIR/role-alarm.md" "alarm"
    ;;
  reviewer)
    launch_claude "$ROOT/worktrees/reviewer-monitor" "$MODEL_SONNET" "$SELF_DIR/role-reviewer.md" "reviewer"
    ;;
  worker)
    name="${2:-}"
    if [ -z "$name" ]; then
      echo "worker requires <worktree-name> (e.g. task-2, task-3)" >&2
      exit 2
    fi
    model="${3:-$WORKER_MODEL}"
    if [ ! -d "$ROOT/worktrees/$name" ]; then
      echo "worktree not found: $ROOT/worktrees/$name" >&2
      exit 1
    fi
    launch_claude "$ROOT/worktrees/$name" "$model" "$SELF_DIR/role-worker.md" "worker-$name"
    ;;
  *)
    echo "unknown role: $role" >&2
    exit 2
    ;;
esac
