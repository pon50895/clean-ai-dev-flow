#!/usr/bin/env bash
# session-learning-inject.sh — SessionStart wrapper:把 CLAUDE.md §0.1 的「自動注入」從假變真。
#
# 為什麼存在(2026-07-17 fresh 稽核):
#   CLAUDE.md §0.1 寫「violations.jsonl last 10 自動注入」—— 對 solo session 是**假的**。
#   learning-inject.sh 一直存在,但只被 fleet 腳本引用(supervisor-self-replace.sh:194、
#   gen-recovery-prompt.sh),而 settings.json 的 SessionStart 只掛 karpathy-activate.js。
#   結果:三次檢討都寫了 violations / 提案,沒有任何東西會讀它們。
#   (更痛的:兩個月前的一份 handoff 就診斷過「capture 是手動、solo session 沒在用」——
#    那個診斷同樣沒有 consumer,同樣蒸發。)
#
# 這支腳本就是那條缺掉的 consumer 邊。它做兩件事:
#   1. 注入 last-10 active violations(learning-inject.sh 的輸出)
#   2. 讀 IMPROVEMENT_LEDGER.md 最後日期,超過 7 天印過期提醒
#      -> 週改進循環的觸發從「記得」變成「被機器提醒」
#
# 鐵律:自身故障絕不擋 session 啟動。任何錯誤都靜默,exit 0。

set -uo pipefail

REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$REPO" ] || exit 0

# --- 1. violations last-10 -------------------------------------------------
INJECT="$REPO/scripts/colyn-roles/learning-inject.sh"
VIOL="$REPO/.planning/learning/violations.jsonl"
if [ -x "$INJECT" ] || [ -f "$INJECT" ]; then
  if [ -s "$VIOL" ]; then
    echo "## 跨 session 學習(violations.jsonl last 10 — 這是機器注入,不是文件)"
    echo
    bash "$INJECT" supervisor 10 2>/dev/null || true
    echo
  fi
fi

# --- 2. 週改進循環過期提醒 --------------------------------------------------
LEDGER="$REPO/.planning/learning/IMPROVEMENT_LEDGER.md"
if [ -f "$LEDGER" ]; then
  # 抓檔內最後一個 YYYY-MM-DD(ledger 每輪標日期)
  LAST="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$LEDGER" 2>/dev/null | sort | tail -1)"
  if [ -n "$LAST" ]; then
    # GNU date(EC2)先試,失敗退 BSD date(mac)
    LAST_TS="$(date -d "$LAST" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$LAST" +%s 2>/dev/null)" || LAST_TS=""
    if [ -n "$LAST_TS" ]; then
      DAYS=$(( ( $(date +%s) - LAST_TS ) / 86400 ))
      if [ "$DAYS" -gt 7 ]; then
        echo "## 週改進循環已過期 ${DAYS} 天(上次:${LAST})"
        echo
        echo "跑 \`skillopt\` skill 的週循環。step 0 = 上週提案的落地驗收(派 fresh agent 帶 receipts,"
        echo "不自驗)—— 前三次檢討失效的原因就是沒有人驗收提案有沒有真的落地。"
        echo "ledger:\`.planning/learning/IMPROVEMENT_LEDGER.md\`"
        echo
      fi
    fi
  fi
else
  echo "## 週改進循環尚未啟動"
  echo
  echo "\`.planning/learning/IMPROVEMENT_LEDGER.md\` 不存在。跑 \`skillopt\` skill 建立第一輪。"
  echo
fi

exit 0
