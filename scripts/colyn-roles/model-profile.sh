#!/usr/bin/env bash
# model-profile.sh — 依 dev-rule/HARNESS_MODEL 標記輸出當前模型 profile 的可調參數。
# 由 roles.sh / start-fleet.sh source。設計:harness/opus-4-8 與 harness/opus-5 兩條 branch
# 只差 dev-rule/HARNESS_MODEL 一行,其餘邏輯共用(避免跨 branch 重複邏輯腐化)。
#
# 匯出:
#   PROFILE_MODEL          當前 profile 名(opus-4-8 | opus-5)
#   PROFILE_MODEL_OPUS     opus 角色實際 model id
#   FLEET_MAX_WORKERS      fleet 併發 worker 上限(opus-5 砍半,收斂 ~5x 成本)
#   REQUIRE_DOUBLE_VERIFY  1=強制所有 opus-5 產出過 fresh-agent 二驗 + 抽驗存在性

_PROFILE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE_MODEL="$(tr -d '[:space:]' < "$_PROFILE_ROOT/dev-rule/HARNESS_MODEL" 2>/dev/null || true)"

case "$PROFILE_MODEL" in
  opus-5)
    PROFILE_MODEL_OPUS="claude-opus-5"
    FLEET_MAX_WORKERS="${FLEET_MAX_WORKERS:-3}"     # 4-8 的一半:Opus 5 ~5x 成本,收斂併發防燒
    REQUIRE_DOUBLE_VERIFY=1                         # Opus 5 曾實證捏造/過動 → 產出一律加倍驗
    ;;
  *)
    PROFILE_MODEL="opus-4-8"                        # 空/未知一律保守回 4-8
    PROFILE_MODEL_OPUS="claude-opus-4-8"
    FLEET_MAX_WORKERS="${FLEET_MAX_WORKERS:-6}"
    REQUIRE_DOUBLE_VERIFY=0
    ;;
esac
export PROFILE_MODEL PROFILE_MODEL_OPUS FLEET_MAX_WORKERS REQUIRE_DOUBLE_VERIFY
