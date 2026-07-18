#!/usr/bin/env bash
# retro.sh — Loop 4 (Hill Climbing) 的 trace 收割器。
#
# 不是 LLM。只是把 .planning/ 裡「已經在寫」的失敗訊號 grep 出來、分類、計數,
# 並對每個類別指出「最可能要改的 harness 檔案」。輸出一份 retro brief 給
# supervisor / 人類決定是否開 [DEV-RULE] PR。協定見 dev-rule/HILL_CLIMBING_LOOP.md。
#
# 用法:
#   bash retro.sh [PLANNING_DIR]   # 預設 ./.planning
#   bash retro.sh --self-test      # 跑內建 fixture 自我檢查
#
# ponytail: grep 啟發式,不做語意分析。訊號變吵(誤報多)再升級成讀 trace 的 LLM retro agent。

set -euo pipefail

DIR=""        # 由 main 設定
TOTAL=0

# check <regex> <file-in-planning> <最可能要改的 harness 檔>
# 印一列:該訊號在該 trace 檔出現幾行 + 撞牆時下一個該改的 harness 檔。
check() {
  local rx="$1" file="$2" target="$3" n=0
  if [[ -f "$DIR/$file" ]]; then
    n=$(grep -icE "$rx" "$DIR/$file" 2>/dev/null || true)
  fi
  TOTAL=$((TOTAL + n))
  printf '%-6s  %-24s  %s\n' "$n" "$file" "$target"
}

scan() {
  DIR="${1%/}"; TOTAL=0
  printf '%s\n' "=== Loop 4 RETRO BRIEF — trace: $DIR ==="
  printf '%s\n' "(每列 = 一條 loop 反覆撞牆的地方;count 高者優先做成 [DEV-RULE] PR)"
  printf '\n%-6s  %-24s  %s\n' "COUNT" "TRACE FILE" "最可能的 harness 改點"
  printf '%s\n' "------------------------------------------------------------------------"
  check "REQUEST_CHANGES|REVIEW-ESCALATE" COORDINATOR_LOG.md      "ai-architecture/REVIEWER.md + role-worker.md (rubric/brief 太鬆)"
  check "\\bFAIL\\b|flaky"                TEST_RESULTS.md         "DATA_SAFETY_AND_TESTING.md + role-tester.md (測試環境/序列化)"
  check "TIMEOUT|denied|escalate"         USER_PERMISSION_QUEUE.md "sample/.claude.local.json (allowlist 缺項)"
  check "\\bR(1[01]|[1-9])\\b|red.?line"  COORDINATOR_LOG.md      "AI_INSTRUCTIONS.md (紅線講不清/常被踩)"
  check "regression"                      REGRESSION_REGISTRY.md  "DATA_SAFETY_AND_TESTING.md (regression gate)"
  check "tech.?debt|deferred"             POST_LAUNCH_TECH_DEBT.md "排 phase 還債,非 harness 問題"
  printf '%s\n' "------------------------------------------------------------------------"
  printf 'TOTAL signals: %s\n' "$TOTAL"
  if [[ "$TOTAL" -eq 0 ]]; then
    printf '\n沒有失敗訊號 — 本輪 loop 乾淨,無需 harness 改動。\n'
  else
    printf '\n下一步 (人類閘門): supervisor 挑 count 最高的 1 條,把「改點」寫成 [DEV-RULE] PR,\n'
    printf '人工 review 後 merge → 下一輪 agent 在同一個地方不再撞牆。這就是 hill climbing 的一步。\n'
  fi
}

self_test() {
  local t; t="$(mktemp -d)/.planning"; mkdir -p "$t"
  printf '%s\n' "PR #4 REQUEST_CHANGES" "[REVIEW-ESCALATE] PR #4" "踩到 R7 刪別人代碼" >"$t/COORDINATOR_LOG.md"
  printf '%s\n' "test_login FAIL" "flaky: docker race" >"$t/TEST_RESULTS.md"
  local out; out="$(scan "$t")"
  grep -qE "^2 +COORDINATOR_LOG.md +ai-architecture/REVIEWER" <<<"$out" || { echo "FAIL: review churn≠2"; echo "$out"; exit 1; }
  grep -qE "^2 +TEST_RESULTS.md +DATA_SAFETY" <<<"$out"            || { echo "FAIL: test fail≠2"; echo "$out"; exit 1; }
  grep -qE "^1 +COORDINATOR_LOG.md +AI_INSTRUCTIONS" <<<"$out"     || { echo "FAIL: redline≠1"; echo "$out"; exit 1; }
  local empty; empty="$(mktemp -d)/.planning"; mkdir -p "$empty"
  scan "$empty" | grep -q "TOTAL signals: 0" || { echo "FAIL: 空目錄應 0"; exit 1; }
  echo "SELF-TEST PASS"
}

case "${1:-}" in
  --self-test) self_test ;;
  "")          scan "./.planning" ;;
  *)           scan "$1" ;;
esac
