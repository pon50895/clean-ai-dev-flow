#!/usr/bin/env bash
# hook-selftest.sh — 陽性/陰性對照,測 bash-destructive-guard.js 本身。
#
# 為什麼存在:
#   一個 session 裡,「規則失效」被誤判三次 —— 三次都是 harness 壞了,不是規則壞了:
#     1. `$(...)` 捕獲混進 job control 輸出 -> JSON parse 炸
#     2. payload 缺 `tool_name` -> guard 提早靜默 exit 0 -> 被誤讀成 ALLOW
#     3. `| tail` 吃掉輸出 -> 只剩 stack trace 尾巴
#   三次都是「陰性結果」(沒擋到),而從沒驗過這個測法能不能測出「陽性」(擋得到)。
#   陰性結果 + 沒驗過的方法 = 什麼都不能推論。
#
# 判讀鐵律(推廣到所有查證,不只 hook):
#   任何「不存在 / 沒觸發 / 沒有 X」的斷語,必須先用同一方法驗一個已知存在的 X。
#   陽性對照做不到 -> 標「未驗」,不要下斷語。
#
#   同一個病的另一個長相:grep 某個 script 沒找到備份指令 -> 宣稱「沒有備份機制」,
#   實際上備份是另一支 cron 每天在跑。正解是先 grep 一個已知在該檔裡的詞,
#   證明 grep 這個方法對這個檔有效,再談「沒找到」代表什麼。
#
# 用法:
#   bash scripts/colyn-roles/hook-selftest.sh            # 全部對照
#   bash scripts/colyn-roles/hook-selftest.sh --quiet    # 只回 exit code
#
# exit 0 = 對照全過(harness 可信,結果可採信)
# exit 1 = 對照失敗(harness 壞了 -> 任何「沒擋到」的結論都不可採信)

set -uo pipefail
REPO="$(git rev-parse --show-toplevel)"
HOOK="$REPO/.claude/hooks/bash-destructive-guard.js"
QUIET="${1:-}"

[ -f "$HOOK" ] || { echo "[selftest] FATAL: hook not found: $HOOK"; exit 1; }

# 完整 payload —— 缺 tool_name 會讓 guard 在 :38 靜默 exit 0(2026-07-17 踩過)
probe() {
  local cmd="$1"
  python3 - "$HOOK" "$cmd" <<'PY'
import json, subprocess, sys
hook, cmd = sys.argv[1], sys.argv[2]
payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
r = subprocess.run(["node", hook], input=payload, capture_output=True, text=True)
if not r.stdout.strip():
    print("ALLOW")
else:
    try:
        print(json.loads(r.stdout)["hookSpecificOutput"]["permissionDecision"].upper())
    except Exception as e:
        print(f"BROKEN:{e}")
PY
}

fail=0
check() {
  local label="$1" cmd="$2" want="$3"
  local got; got="$(probe "$cmd")"
  if [ "$got" = "$want" ]; then
    [ "$QUIET" = "--quiet" ] || printf '  OK    %-6s %-28s %s\n' "$got" "$label" "${cmd:0:44}"
  else
    printf '  FAIL  got=%-8s want=%-8s %-28s %s\n' "$got" "$want" "$label" "${cmd:0:44}"
    fail=1
  fi
}

[ "$QUIET" = "--quiet" ] || echo "[selftest] 陽性對照(必須擋到 —— 擋不到代表 harness 壞了,不是規則失效)"
check "陽性:catastrophic" 'docker compose down -v' 'DENY'
check "陽性:pipe 吃 exit"  'npm run build 2>&1 | tail -15 && echo "EXIT: $?"' 'DENY'
check "陽性:ask 級"        'git reset --hard origin/main' 'ASK'

[ "$QUIET" = "--quiet" ] || echo "[selftest] 陰性對照(必須放行 —— 擋到代表誤擋)"
check "陰性:唯讀 pipe"     'git log --oneline | head -5' 'ALLOW'
check "陰性:正確寫法"      'npm run build > /tmp/b.log 2>&1; code=$?' 'ALLOW'
check "陰性:單檔 jest"     'npx jest apps/server/src/foo.spec.ts --runInBand' 'ALLOW'

if [ "$fail" -eq 0 ]; then
  [ "$QUIET" = "--quiet" ] || echo "[selftest] OK — harness 可信,測試結果可採信"
  exit 0
else
  echo "[selftest] FAILED — harness 或規則壞了。在修好之前,"
  echo "           任何「沒擋到 / 規則失效」的結論都不可採信(2026-07-17 踩過三次)。"
  exit 1
fi
