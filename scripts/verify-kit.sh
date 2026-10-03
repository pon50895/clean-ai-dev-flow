#!/usr/bin/env bash
#
# scripts/verify-kit.sh - 可移植開發套件驗收(票 09)。
#
# 在全新暫存 git repo 跑 scripts/bootstrap.sh,再驗 5 項,各自印 PASS/FAIL,任一 FAIL 則 exit 1。
# 不依賴服務、不連網(只用本機 git / node / jq,remote 是本地 bare repo)。
#
#   1. 範本到位:檔案存在、重跑 bootstrap 無變更、目標 .claude/ 只有 kit.json 與 schema
#   2. gate 依 kit.json:main commit 被擋、feature commit 通過、push main 被擋、force push 被擋、未設定 ratchet 跳過
#   3. 全域 hook:~/.claude/settings.json 掛載存在且檔案存在;以假 payload 斷言 deny / allow
#   4. 通用 skill:~/.claude/skills 中指向 clean 的 symlink 可解析、SKILL.md 存在、無寫死專案字樣
#   5. tarot 回歸:origin/main 的 hook 掛載指向存在檔案、已移走的 13 支 skill 不在、保留的命理 skill 在
#
# 用法:
#   bash scripts/verify-kit.sh
#
# 可覆寫的環境變數:
#   PLAYBOOK_DIR   (預設 $HOME/claude-ops-playbook)
#   TAROT_REPO     (預設 $HOME/Desktop/tarot/main/main;只讀 origin/main,不 fetch)
#   CLAUDE_HOME    (預設 $HOME/.claude)
#
# 暫存目錄用 mktemp 建立,不自行刪除(系統會清 tmp)。

set -uo pipefail

KIT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAYBOOK_DIR="${PLAYBOOK_DIR:-$HOME/claude-ops-playbook}"
TAROT_REPO="${TAROT_REPO:-$HOME/Desktop/tarot/main/main}"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

for tool in git node jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "[verify-kit] missing tool: $tool" >&2; exit 2; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/verify-kit.XXXXXX")"
PROJ="$TMP/proj"
REMOTE="$TMP/remote.git"
OUT="$TMP/out.log"

SECTION_FAIL=0
TOTAL_FAIL=0
RESULTS=()

ok()  { echo "    ok    $1"; }
bad() { echo "    FAIL  $1"; SECTION_FAIL=1; }
# check <label> <exit-code-of-condition(0=true)>
check() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

section_begin() { SECTION_FAIL=0; echo ""; echo "== $1"; }
section_end() {
  if [ "$SECTION_FAIL" -eq 0 ]; then echo "[$1] PASS"; RESULTS+=("$1 PASS")
  else echo "[$1] FAIL"; RESULTS+=("$1 FAIL"); TOTAL_FAIL=1; fi
}

echo "[verify-kit] kit source : $KIT_SRC"
echo "[verify-kit] playbook   : $PLAYBOOK_DIR"
echo "[verify-kit] tmp dir    : $TMP"

# ---------------------------------------------------------------------------
# 1. 範本到位
# ---------------------------------------------------------------------------
section_begin "1 範本到位"
mkdir -p "$PROJ"
git -C "$PROJ" init -q -b main
git -C "$PROJ" config user.email verify@kit.local
git -C "$PROJ" config user.name verify-kit

bash "$KIT_SRC/scripts/bootstrap.sh" "$PROJ" >"$OUT" 2>&1
check "bootstrap 第一次執行 exit 0" $?

for p in CLAUDE.md .claude/kit.json .claude/kit.schema.json .githooks/pre-commit .githooks/pre-push \
         scripts/kit/kit.mjs dev-rule; do
  [ -e "$PROJ/$p" ]; check "存在: $p" $?
done
[ "$(git -C "$PROJ" config --get core.hooksPath)" = ".githooks" ]; check "core.hooksPath=.githooks" $?

snap() { (cd "$PROJ" && find . -path ./.git -prune -o -type f -print | sort | xargs cksum | cksum); }
S1="$(snap)"
bash "$KIT_SRC/scripts/bootstrap.sh" "$PROJ" >"$OUT" 2>&1
check "bootstrap 第二次執行 exit 0" $?
grep -q "created=0 unchanged=[0-9]* skipped=0" "$OUT"; check "重跑 summary: created=0 skipped=0" $?
[ "$S1" = "$(snap)" ]; check "重跑後檔案內容與清單無變更" $?

EXTRA="$(cd "$PROJ/.claude" && ls -A | grep -vxE 'kit\.json|kit\.schema\.json' || true)"
[ -z "$EXTRA" ]; check ".claude/ 只有 kit.json 與 kit.schema.json${EXTRA:+ (多出: $EXTRA)}" $?
[ ! -e "$PROJ/.claude/skills" ] && [ ! -e "$PROJ/.claude/hooks" ]; check ".claude/ 沒有 skills/ 或 hooks/" $?
section_end "1 範本到位"

# ---------------------------------------------------------------------------
# 2. gate 依 kit.json
# ---------------------------------------------------------------------------
section_begin "2 gate 依 kit.json"
git init -q --bare -b main "$REMOTE"
git -C "$PROJ" remote add origin "$REMOTE"
git -C "$PROJ" add -A
git -C "$PROJ" commit -q -m "chore: bootstrap" >"$OUT" 2>&1
RC=$?
[ "$RC" -ne 0 ] && grep -q "BLOCKED: Cannot commit directly to 'main'" "$OUT"
check "main 上 commit 被擋(pre-commit BLOCKED)" $?

git -C "$PROJ" switch -q -c chore/kit-verify
git -C "$PROJ" commit -q -m "chore: bootstrap" >"$OUT" 2>&1
RC=$?
check "feature 分支 commit 通過" $RC
[ "$RC" -ne 0 ] && sed 's/^/        | /' "$OUT" | head -20

git -C "$PROJ" push -q origin chore/kit-verify >"$OUT" 2>&1
check "feature 分支 push 通過(未設定 ratchet 跳過、不報錯)" $?

# 把 ratchet 模組打開但 workspaces 為空,仍應跳過不報錯(不 commit,只改工作樹)
node -e '
  const fs=require("fs"),f=process.argv[1],j=JSON.parse(fs.readFileSync(f,"utf8"));
  j.modules.lintRatchet=true; j.modules.tscRatchet=true; fs.writeFileSync(f,JSON.stringify(j,null,2));
' "$PROJ/.claude/kit.json"
echo "more" > "$PROJ/note.txt"
git -C "$PROJ" add note.txt
git -C "$PROJ" commit -q -m "chore: note" >"$OUT" 2>&1
git -C "$PROJ" push -q origin chore/kit-verify >"$OUT" 2>&1
check "ratchet 開啟但 workspaces 空 -> push 跳過不報錯" $?

git -C "$PROJ" push origin HEAD:main >"$OUT" 2>&1
RC=$?
[ "$RC" -ne 0 ] && grep -q "BLOCKED: Direct push to 'refs/heads/main'" "$OUT"
check "push 到 main 被擋(pre-push BLOCKED)" $?

git -C "$PROJ" commit -q --amend -m "chore: note rewritten" >/dev/null 2>&1
git -C "$PROJ" push --force origin chore/kit-verify >"$OUT" 2>&1
RC=$?
[ "$RC" -ne 0 ] && grep -q "BLOCKED: Force push" "$OUT"
check "force push 被擋(pre-push BLOCKED)" $?
section_end "2 gate 依 kit.json"

# ---------------------------------------------------------------------------
# 3. 全域 hook 生效
# ---------------------------------------------------------------------------
section_begin "3 全域 hook 生效"
SETTINGS="$CLAUDE_HOME/settings.json"
HOOKDIR="$PLAYBOOK_DIR/hooks"
if [ ! -f "$SETTINGS" ]; then
  bad "找不到 $SETTINGS"
else
  # event|matcher|hook(對照 playbook hooks/SETTINGS_MOUNT.md 掛載表)
  MOUNTS="SessionStart|core-contract-inject
SessionStart|karpathy-activate
PreToolUse|bash-destructive-guard
PreToolUse|git-readonly-approve
PreToolUse|git-workflow-guard
PreToolUse|agent-model-guard
Stop|severity-claim-reminder
Stop|over-ask-reminder
Stop|emoji-reminder"
  N=0
  while IFS='|' read -r ev hk; do
    N=$((N+1))
    jq -e --arg ev "$ev" --arg hk "$hk" \
      '[.hooks[$ev][]?.hooks[]?.command | select(contains("claude-ops-playbook/hooks/" + $hk + ".js"))] | length > 0' \
      "$SETTINGS" >/dev/null 2>&1
    MOUNTED=$?
    [ -f "$HOOKDIR/$hk.js" ]; EXISTS=$?
    if [ "$MOUNTED" -eq 0 ] && [ "$EXISTS" -eq 0 ]; then ok "掛載 + 檔案存在: $ev / $hk"
    else bad "掛載=$([ $MOUNTED -eq 0 ] && echo yes || echo NO) 檔案=$([ $EXISTS -eq 0 ] && echo yes || echo NO): $ev / $hk"; fi
  done <<EOF
$MOUNTS
EOF
  echo "    (掛載表共 $N 條)"
fi

# 探測用專案:有一個 tracked 檔案
PROBE="$TMP/probe"
mkdir -p "$PROBE"
git -C "$PROBE" init -q -b main
git -C "$PROBE" config user.email verify@kit.local
git -C "$PROBE" config user.name verify-kit
echo tracked > "$PROBE/tracked.txt"
git -C "$PROBE" add -A
ALLOW_MAIN_COMMIT=1 git -C "$PROBE" commit -q -m init --no-verify

# probe <hook> <payload> -> deny | ask | allow | silent | BROKEN
probe() {
  local hook="$1" payload="$2" out rc
  out="$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$PROBE" node "$HOOKDIR/$hook.js" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then echo "BROKEN"; return; fi
  if [ -z "$out" ]; then echo "silent"; return; fi
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "ctx"' 2>/dev/null || echo "ctx"
}
bash_payload()  { jq -cn --arg c "$1" --arg d "$PROBE" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }
agent_payload() { # [model]
  if [ -n "${1:-}" ]; then jq -cn --arg m "$1" '{tool_name:"Agent",tool_input:{description:"d",prompt:"do x",subagent_type:"general-purpose",model:$m}}'
  else jq -cn '{tool_name:"Agent",tool_input:{description:"d",prompt:"do x",subagent_type:"general-purpose"}}'; fi
}
# expect_probe <label> <hook> <payload> <want: deny|silent>
expect_probe() {
  local got; got="$(probe "$2" "$3")"
  [ "$got" = "$4" ]; check "$1 -> $got(要 $4)" $?
}

if [ -f "$HOOKDIR/bash-destructive-guard.js" ]; then
  expect_probe "destructive: rm <tracked>"        bash-destructive-guard "$(bash_payload 'rm tracked.txt')" deny
  expect_probe "destructive: git rm --cached 放行" bash-destructive-guard "$(bash_payload 'git rm --cached tracked.txt')" silent
  expect_probe "destructive: --no-verify"         bash-destructive-guard "$(bash_payload 'git commit -m x --no-verify')" deny
  expect_probe "destructive: 唯讀 git log 放行"    bash-destructive-guard "$(bash_payload 'git log --oneline | head -5')" silent
  expect_probe "workflow: commit heredoc"          git-workflow-guard "$(bash_payload $'git commit -F - <<EOF\nmsg\nEOF')" deny
  expect_probe "workflow: commit -F file 放行"     git-workflow-guard "$(bash_payload 'git commit -F /tmp/m.txt')" silent
  expect_probe "agent-model: 省略 model"           agent-model-guard "$(agent_payload)" deny
  expect_probe "agent-model: model=sonnet 放行"    agent-model-guard "$(agent_payload sonnet)" silent
else
  bad "找不到 hooks 目錄: $HOOKDIR"
fi
section_end "3 全域 hook 生效"

# ---------------------------------------------------------------------------
# 4. 通用 skill
# ---------------------------------------------------------------------------
section_begin "4 通用 skill"
FORBIDDEN='wenwen|問問|八字|取用神|apps/(server|client|e2e)|tarot'
COUNT=0
for link in "$CLAUDE_HOME"/skills/*; do
  [ -L "$link" ] || continue
  tgt="$(readlink "$link")"
  case "$tgt" in *clean-ai-dev-flow*) ;; *) continue ;; esac
  COUNT=$((COUNT+1))
  name="$(basename "$link")"
  if [ ! -d "$link" ]; then bad "$name: symlink 無法解析 -> $tgt"; continue; fi
  if [ ! -f "$link/SKILL.md" ]; then bad "$name: 缺 SKILL.md"; continue; fi
  HITS="$(grep -rEIn "$FORBIDDEN" "$link/" 2>/dev/null | head -3 || true)"
  if [ -n "$HITS" ]; then bad "$name: 含寫死字樣"; echo "$HITS" | sed 's/^/        | /'
  else ok "$name"; fi
done
[ "$COUNT" -gt 0 ]; check "找到指向 clean 的 symlink($COUNT 支)" $?
section_end "4 通用 skill"

# ---------------------------------------------------------------------------
# 5. tarot 回歸
# ---------------------------------------------------------------------------
section_begin "5 tarot 回歸(origin/main)"
if ! git -C "$TAROT_REPO" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  bad "找不到 $TAROT_REPO 的 origin/main"
else
  REF="origin/main"
  echo "    (tarot origin/main = $(git -C "$TAROT_REPO" rev-parse --short origin/main))"
  CMDS="$(git -C "$TAROT_REPO" show "$REF:.claude/settings.json" 2>/dev/null \
    | jq -r '.hooks[]?[]?.hooks[]?.command' 2>/dev/null || true)"
  [ -n "$CMDS" ]; check "讀得到 .claude/settings.json 的 hook 掛載" $?
  while IFS= read -r cmd; do
    case "$cmd" in
      *'$CLAUDE_PROJECT_DIR/'*)
        rel="$(printf '%s' "$cmd" | sed -E 's/.*\$CLAUDE_PROJECT_DIR\/([^" ]+).*/\1/')"
        git -C "$TAROT_REPO" cat-file -e "$REF:$rel" 2>/dev/null
        check "hook 檔案存在: $rel" $? ;;
      *claude-ops-playbook*) ;;   # 全域 hook,由第 3 項驗
      *) ok "內建指令(無檔案): ${cmd:0:40}" ;;
    esac
  done <<EOF
$CMDS
EOF

  MOVED="dev-rule-curate git-gh-ops improve-codebase-architecture memory-curate planning-archive-sweep
pr-conflict-solver reap-worktrees session-bootstrap-reconcile skillopt systematic-debugging to-spec to-tickets writing-great-skills"
  for s in $MOVED; do
    if git -C "$TAROT_REPO" cat-file -e "$REF:.claude/skills/$s/SKILL.md" 2>/dev/null; then bad "已移走的 skill 仍在 tarot: $s"
    else ok "已移走(不在 tarot): $s"; fi
  done
  KEPT="admin-page-style-audit bazi-full-report blackbox-security-test blind-watermark codebase-memory
consult-sandbox daily-advice-review domain-know-how growth-loop journal-factory journal-preflight-scan
local-authed-screenshot schema-drift-repair ui-visual-verify wenwen-prod-deploy worktree-staging-env"
  for s in $KEPT; do
    git -C "$TAROT_REPO" cat-file -e "$REF:.claude/skills/$s/SKILL.md" 2>/dev/null
    check "保留的專案 skill 存在: $s" $?
  done
fi
section_end "5 tarot 回歸(origin/main)"

# ---------------------------------------------------------------------------
echo ""
echo "== 總結"
printf '  %s\n' "${RESULTS[@]}"
if [ "$TOTAL_FAIL" -eq 0 ]; then echo "[verify-kit] ALL PASS"; exit 0
else echo "[verify-kit] FAILED"; exit 1; fi
