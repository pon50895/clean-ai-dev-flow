#!/usr/bin/env bash
#
# apply-claude-settings.sh — 把 dev-rule/sample/.claude.local.json
# 部署到當前 worktree 的 .claude/settings.local.json。
#
# 用法：
#   bash scripts/colyn-roles/apply-claude-settings.sh
#   APPLY_MODE=replace bash scripts/colyn-roles/apply-claude-settings.sh   # 不問直接覆蓋
#   APPLY_MODE=skip    bash scripts/colyn-roles/apply-claude-settings.sh   # 不存在才複製
#   APPLY_DRY=1        bash scripts/colyn-roles/apply-claude-settings.sh   # 只 show 要做什麼
#
# 自動偵測：
#   - 已存在的 settings.local.json 會跟 sample 比 diff，互動式選 replace/skip
#   - 部署完提示「重啟 Claude Code session 才會吃到新規則」

set -euo pipefail

WORKTREE="${WORKTREE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MODE="${APPLY_MODE:-prompt}"   # prompt | replace | skip
DRY="${APPLY_DRY:-0}"

# Sample lives at dev-rule/sample/settings.local.json (post 2026-05-30 split).
# Falls back to legacy single-file schema if the new files aren't present yet.
SAMPLE="$WORKTREE/dev-rule/sample/settings.local.json"
if [ ! -f "$SAMPLE" ] && [ -f "$WORKTREE/dev-rule/sample/.claude.local.json" ]; then
  SAMPLE="$WORKTREE/dev-rule/sample/.claude.local.json"
  echo "[apply] WARNING: using legacy sample schema ($SAMPLE). Run split before next deploy."
fi
TARGET_DIR="$WORKTREE/.claude"
TARGET="$TARGET_DIR/settings.local.json"

echo "=========================================="
echo " apply-claude-settings"
echo "=========================================="
echo "  worktree:   $WORKTREE"
echo "  sample:     $SAMPLE"
echo "  target:     $TARGET"
echo "  mode:       $MODE  (replace=覆蓋 / skip=不存在才複製 / prompt=互動)"
[ "$DRY" = "1" ] && echo "  DRY RUN: 不會真的寫"
echo ""

# ----------------------------------------------------------------------------
# Pre-flight
# ----------------------------------------------------------------------------
if [ ! -f "$SAMPLE" ]; then
  echo "[ERROR] sample not found: $SAMPLE"
  echo "        確認 dev-rule/sample/ 已從 origin 拉到本 worktree。"
  exit 1
fi

# 驗 JSON
if ! python3 -c "import json; json.load(open('$SAMPLE'))" 2>/dev/null; then
  echo "[ERROR] sample is not valid JSON"
  exit 1
fi

mkdir -p "$TARGET_DIR"

# ----------------------------------------------------------------------------
# 不存在 → 直接複製
# ----------------------------------------------------------------------------
if [ ! -f "$TARGET" ]; then
  echo "[apply] target 不存在 → 從 sample 複製"
  if [ "$DRY" = "1" ]; then
    echo "        [DRY] would: cp $SAMPLE $TARGET"
  else
    cp "$SAMPLE" "$TARGET"
    echo "        [OK] copied"
  fi
  echo ""
  echo "▶ 重啟 Claude Code session 才會生效："
  echo "  在 supervisor pane 內 Ctrl-C → bash scripts/colyn-roles/roles.sh supervisor"
  exit 0
fi

# ----------------------------------------------------------------------------
# 已存在 → diff + 處理
# ----------------------------------------------------------------------------
if cmp -s "$SAMPLE" "$TARGET"; then
  echo "[apply] target 與 sample 一致，無動作"
  exit 0
fi

echo "[apply] target 與 sample 有差異："
# diff -u 偵測差異會 return 1；pipefail + set -e 會讓腳本直接退出，
# 所以用 || true 吃掉這個非零退出碼。
{ diff -u "$SAMPLE" "$TARGET" || true; } | head -40
echo ""
echo "(diff 截前 40 行；完整跑 \`diff $SAMPLE $TARGET\`)"
echo ""

case "$MODE" in
  replace)
    echo "[apply] MODE=replace → 覆蓋 target"
    if [ "$DRY" = "1" ]; then
      echo "        [DRY] would: cp $SAMPLE $TARGET"
    else
      # 備份舊的
      cp "$TARGET" "$TARGET.bak.$(date +%Y%m%d-%H%M%S)"
      cp "$SAMPLE" "$TARGET"
      echo "        [OK] replaced (backup at $TARGET.bak.*)"
    fi
    ;;
  skip)
    echo "[apply] MODE=skip → 保留 target 原狀，不動"
    exit 0
    ;;
  prompt)
    echo "選擇處理方式："
    echo "  [r] replace — 用 sample 覆蓋（先備份舊的）"
    echo "  [s] skip    — 保留現有的，不動"
    echo "  [d] diff    — 看完整 diff 再決定"
    read -r -p "你的選擇 [r/s/d]: " choice
    case "$choice" in
      r|R)
        if [ "$DRY" = "1" ]; then
          echo "        [DRY] would: cp $SAMPLE $TARGET"
        else
          cp "$TARGET" "$TARGET.bak.$(date +%Y%m%d-%H%M%S)"
          cp "$SAMPLE" "$TARGET"
          echo "        [OK] replaced (backup at $TARGET.bak.*)"
        fi
        ;;
      s|S)
        echo "        [SKIP] 保留現有"
        exit 0
        ;;
      d|D)
        diff -u "$SAMPLE" "$TARGET" | less
        echo "        看完了再跑一次本腳本決定"
        exit 0
        ;;
      *)
        echo "        unknown choice → skip"
        exit 0
        ;;
    esac
    ;;
  *)
    echo "[ERROR] unknown APPLY_MODE: $MODE"
    exit 2
    ;;
esac

echo ""
echo "▶ 重啟 Claude Code session 才會生效："
echo "  在 supervisor pane 內 Ctrl-C → bash scripts/colyn-roles/roles.sh supervisor"
echo "  或對所有 worker：bash scripts/colyn-roles/restart.sh"
