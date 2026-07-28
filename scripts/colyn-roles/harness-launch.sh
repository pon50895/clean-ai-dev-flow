#!/usr/bin/env bash
# harness-launch.sh — 依目標模型切到對應 harness branch 再啟動 claude。
#
# 用法:  bash scripts/colyn-roles/harness-launch.sh opus-4-8
#         bash scripts/colyn-roles/harness-launch.sh opus-5
#
# 兩條 branch(harness/opus-4-8 / harness/opus-5)只差 dev-rule/HARNESS_MODEL 一行,
# 帶動 model-profile.sh 給出不同的 opus model id / fleet 併發 / 驗收嚴格度。
#
# 安全:working tree 有未 commit 的「已追蹤」變更就不切 branch(fail-safe),
#       絕不 stash / reset / clean —— 不蓋掉任何工作。
set -euo pipefail

TARGET="${1:-}"
case "$TARGET" in
  opus-4-8) BRANCH="harness/opus-4-8"; MODEL="claude-opus-4-8" ;;
  opus-5)   BRANCH="harness/opus-5";   MODEL="claude-opus-5" ;;
  *) echo "用法: $0 opus-4-8|opus-5" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# 只看已追蹤檔的變更(未追蹤檔切 branch 不受影響,不擋)。
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "[harness-launch] 偵測到未 commit 的已追蹤變更 → 不切 branch(避免蓋掉工作)。" >&2
  echo "[harness-launch] 先 commit / 處理 WIP 再跑;此次用當前 branch 啟動。" >&2
elif [ "$(git rev-parse --abbrev-ref HEAD)" = "$BRANCH" ]; then
  echo "[harness-launch] 已在 $BRANCH。" >&2
else
  if ! git switch "$BRANCH" 2>/dev/null; then
    echo "[harness-launch] branch $BRANCH 不存在。先建立(git branch $BRANCH)後再跑。" >&2
    exit 3
  fi
  echo "[harness-launch] 已切到 $BRANCH" >&2
fi

echo "[harness-launch] 啟動 claude --model $MODEL (profile: $TARGET)" >&2
exec claude --model "$MODEL"
