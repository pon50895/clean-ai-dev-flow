#!/usr/bin/env bash
#
# start.sh — 手動冷啟動。建立 tmux session + 各角色 windows + 統一視覺面板。
#
# 適用情境：
# - 第一次設置完 colyn / 重開機後，要把所有角色 + Claude session 拉起來
# - tmux session 還在但角色 pane 沒 Claude
#
# 不會 kill 既有的 Claude session（idempotent）。
# 只在 pane 是空 zsh 時 send `roles.sh <role>` 啟動 Claude。
#
# 用法：
#   bash scripts/colyn-roles/start.sh
#   FORCE_RELAUNCH=1 bash scripts/colyn-roles/start.sh   # 強制 relaunch 所有 pane

set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ROLES_SH="$SELF_DIR/roles.sh"

ROOT="${WORKSPACE_ROOT:-$HOME/Desktop/parallel-dev-workspace}"
SESSION="${TMUX_SESSION:-main}"
UNIFIED_WIN="${UNIFIED_WIN:-roles}"
WORKER_NAMES="${WORKER_NAMES:-task-2 task-3 task-4 task-5}"
FORCE="${FORCE_RELAUNCH:-0}"

declare -a WORKERS
read -r -a WORKERS <<< "$WORKER_NAMES"

if [ ! -x "$ROLES_SH" ]; then
  chmod +x "$ROLES_SH"
fi

# ----------------------------------------------------------------------------
# 0. Preflight：workspace 是否就緒
#
# start.sh 在每個 pane `cd` 進 $ROOT/main 與 $ROOT/worktrees/*。這些是 colyn
# 的 workspace 佈局(不是本 repo),bootstrap 不會自動建。少任何一個,底下的
# `tmux new-window -c <不存在目錄>` 會在 set -e 下整個腳本暴斃且訊息難懂。
# 這裡先檢查、缺就把「該怎麼補」講白後退出,而不是讓人對著 tmux 錯誤瞎猜。
# ----------------------------------------------------------------------------
missing=()
[ -d "$ROOT/main" ] || missing+=("$ROOT/main")
[ -d "$ROOT/worktrees/sentinel-monitor" ] || missing+=("$ROOT/worktrees/sentinel-monitor")
[ -d "$ROOT/worktrees/reviewer-monitor" ] || missing+=("$ROOT/worktrees/reviewer-monitor")
for w in "${WORKERS[@]}"; do
  [ -d "$ROOT/worktrees/$w" ] || missing+=("$ROOT/worktrees/$w")
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "[start] FAIL: workspace 未就緒,以下目錄不存在:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  cat >&2 <<EOF

start.sh 假設 colyn workspace 已建好。先擇一處理:

  1. workspace 在別處   → export WORKSPACE_ROOT=<你的 workspace 路徑> 再重跑
  2. 還沒建 workspace   → 用 colyn 建出 main + 各 worktree(見 README §3.1):
                             colyn add feat/task-2   # 對每個 worker 重複
                          直到 $ROOT/main 與上列 worktrees 都存在
  3. 不需要 7-agent fleet → 你大概不需要這支腳本。單一 agent 路徑見
                          README「最小可跑路徑」一節,零 tmux/colyn 設定。

EOF
  exit 1
fi

# ----------------------------------------------------------------------------
# 1. 確保 tmux session 存在
# ----------------------------------------------------------------------------
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[start] creating tmux session '$SESSION'"
  tmux new-session -d -s "$SESSION" -n "supervisor" -c "$ROOT/main"
fi

# ----------------------------------------------------------------------------
# 2. 確保 7 個獨立 windows（0..6）對應 7 個角色
#
# 排版：
#   window 0 → supervisor (main/)
#   window 1 → alarm      (worktrees/sentinel-monitor)
#   window 2 → reviewer   (worktrees/reviewer-monitor)
#   window 3..6 → worker  (worktrees/${WORKERS[0..3]})
# ----------------------------------------------------------------------------

ensure_window() {
  local idx="$1" name="$2" cwd="$3"
  if tmux list-windows -t "$SESSION" -F '#I' | grep -qx "$idx"; then
    # 已存在；確認 cwd（不強制改）
    local current
    current="$(tmux display-message -p -t "$SESSION:$idx.0" '#{pane_current_path}')"
    if [ "$current" != "$cwd" ] && [ "$FORCE" = "1" ]; then
      echo "[start] window $idx exists with cwd=$current; FORCE=1 → renaming"
      tmux rename-window -t "$SESSION:$idx" "$name"
    fi
  else
    echo "[start] creating window $idx ($name) cwd=$cwd"
    # 用 new-window -t main:$idx -k 強制建在指定 idx
    tmux new-window -t "$SESSION:$idx" -k -n "$name" -c "$cwd"
  fi
}

ensure_window 0 "supervisor" "$ROOT/main"
ensure_window 1 "alarm"      "$ROOT/worktrees/sentinel-monitor"
ensure_window 2 "reviewer"   "$ROOT/worktrees/reviewer-monitor"

w_idx=3
for w in "${WORKERS[@]}"; do
  ensure_window "$w_idx" "worker-$w" "$ROOT/worktrees/$w"
  w_idx=$((w_idx + 1))
done

# ----------------------------------------------------------------------------
# 3. 在每個 window pane 0 啟動 Claude（若還沒在跑）
# ----------------------------------------------------------------------------

is_claude_running() {
  local target="$1"
  local cmd
  cmd="$(tmux display-message -p -t "$target" '#{pane_current_command}' 2>/dev/null || echo "")"
  # Claude Code pane 顯示版本字串開頭數字（如 2.1.131）；普通 shell 是 zsh/bash
  case "$cmd" in
    zsh|bash|sh|fish) return 1 ;;
    *) return 0 ;;
  esac
}

# 從 Claude UI 截到的字串（如 "Sonnet 4.6"）映射回 model ID
ui_to_model_id() {
  case "$1" in
    opus-4.7)   echo "claude-opus-4-7" ;;
    sonnet-4.6) echo "claude-sonnet-4-6" ;;
    haiku-4.5)  echo "claude-haiku-4-5-20251001" ;;
    *) echo "" ;;
  esac
}

# 從 pane 抓 Claude UI 的模型字串（小寫破折號形式：opus-4.7 / sonnet-4.6 / haiku-4.5）
parse_pane_model() {
  local target="$1"
  tmux capture-pane -t "$target" -p 2>/dev/null \
    | grep -oE '(Opus|Sonnet|Haiku) [0-9]+\.[0-9]+' \
    | tail -1 \
    | tr '[:upper:]' '[:lower:]' \
    | tr ' ' '-'
}

# 角色 → 目標 model ID
target_model_for_role() {
  case "$1" in
    supervisor) echo "claude-opus-4-7" ;;
    alarm)      echo "claude-haiku-4-5-20251001" ;;
    reviewer)   echo "claude-sonnet-4-6" ;;
    worker)     echo "${WORKER_MODEL:-claude-sonnet-4-6}" ;;
    *)          echo "" ;;
  esac
}

launch_role_in_pane() {
  local target="$1" role="$2" arg="${3:-}" model_override="${4:-}"
  local target_model
  if [ -n "$model_override" ]; then
    target_model="$model_override"
  else
    target_model="$(target_model_for_role "$role")"
  fi

  if [ "$FORCE" != "1" ] && is_claude_running "$target"; then
    # Claude 已在跑 → 驗證模型是否正確
    local current_ui actual_model
    current_ui="$(parse_pane_model "$target")"
    actual_model="$(ui_to_model_id "$current_ui")"

    if [ -z "$actual_model" ]; then
      echo "[start] $target: claude running, model unknown ($current_ui) — skip"
      return 0
    fi
    if [ "$actual_model" = "$target_model" ]; then
      echo "[start] $target: claude already running with correct model ($current_ui), skip"
      return 0
    fi
    # 模型錯了 → 用 /model slash command 矯正（不 kill）
    echo "[start] $target: claude has WRONG model ($current_ui), correcting to $target_model via /model"
    tmux send-keys -t "$target" Escape
    sleep 0.3
    tmux send-keys -t "$target" "/model $target_model" Enter Enter
    return 0
  fi

  # Pane 是空 zsh → 啟動
  local cmd="bash $ROLES_SH $role"
  [ -n "$arg" ] && cmd="$cmd $arg"
  [ -n "$model_override" ] && cmd="$cmd $model_override"
  echo "[start] $target: launching → $cmd"
  tmux send-keys -t "$target" "$cmd" Enter
}

launch_role_in_pane "$SESSION:0.0" supervisor
launch_role_in_pane "$SESSION:1.0" alarm
launch_role_in_pane "$SESSION:2.0" reviewer

w_idx=3
for w in "${WORKERS[@]}"; do
  launch_role_in_pane "$SESSION:$w_idx.0" worker "$w"
  w_idx=$((w_idx + 1))
done

# ----------------------------------------------------------------------------
# 4. 建立 / 重建統一視覺面板（main:roles，7 panes，50/25/25 layout）
# ----------------------------------------------------------------------------
build_unified_window() {
  echo "[start] (re)building unified window: $SESSION:$UNIFIED_WIN"
  tmux kill-window -t "$SESSION:$UNIFIED_WIN" 2>/dev/null || true
  tmux new-window -t "$SESSION:" -n "$UNIFIED_WIN" -c "$ROOT/main"

  # 上 50% / 中 25% / 下 25%
  tmux split-window -t "$SESSION:$UNIFIED_WIN" -v -p 50    # pane 1 (bottom-half)
  tmux split-window -t "$SESSION:$UNIFIED_WIN.1" -v -p 50  # pane 2 (bottom 25%)

  # 中間 row 切 3 欄（pane 1 是 mid-left）
  tmux split-window -t "$SESSION:$UNIFIED_WIN.1" -h -p 67  # pane 3
  tmux split-window -t "$SESSION:$UNIFIED_WIN.3" -h -p 50  # pane 4

  # 下 row 切 3 欄（pane 2 是 bot-left）
  tmux split-window -t "$SESSION:$UNIFIED_WIN.2" -h -p 67  # pane 5
  tmux split-window -t "$SESSION:$UNIFIED_WIN.5" -h -p 50  # pane 6

  # Pane 對映：
  #   pane 0 → supervisor
  #   pane 1 → alarm           (mid-left)
  #   pane 3 → reviewer        (mid-mid)
  #   pane 4 → worker WORKERS[0] (mid-right)
  #   pane 2 → worker WORKERS[1] (bot-left)
  #   pane 5 → worker WORKERS[2] (bot-mid)
  #   pane 6 → worker WORKERS[3] (bot-right)
  tmux send-keys -t "$SESSION:$UNIFIED_WIN.0" "bash $ROLES_SH supervisor" Enter
  tmux send-keys -t "$SESSION:$UNIFIED_WIN.1" "bash $ROLES_SH alarm" Enter
  tmux send-keys -t "$SESSION:$UNIFIED_WIN.3" "bash $ROLES_SH reviewer" Enter
  tmux send-keys -t "$SESSION:$UNIFIED_WIN.4" "bash $ROLES_SH worker ${WORKERS[0]}" Enter
  tmux send-keys -t "$SESSION:$UNIFIED_WIN.2" "bash $ROLES_SH worker ${WORKERS[1]}" Enter
  tmux send-keys -t "$SESSION:$UNIFIED_WIN.5" "bash $ROLES_SH worker ${WORKERS[2]}" Enter
  tmux send-keys -t "$SESSION:$UNIFIED_WIN.6" "bash $ROLES_SH worker ${WORKERS[3]}" Enter

  tmux select-pane -t "$SESSION:$UNIFIED_WIN.0"
}

# 使用者可以選不要建統一視窗（容易搞混就跳過）
if [ "${SKIP_UNIFIED:-0}" != "1" ]; then
  build_unified_window
fi

# ----------------------------------------------------------------------------
# 5. 收尾報告
# ----------------------------------------------------------------------------
echo
echo "=== windows ==="
tmux list-windows -t "$SESSION" -F '  #I #W (#{pane_current_path})'
echo
echo "[start] done. Attach with: tmux attach -t $SESSION"
echo "[start] unified view:    tmux select-window -t $SESSION:$UNIFIED_WIN"
