#!/usr/bin/env node
/**
 * PreToolUse hook: deterministic destructive-command guard for Bash.
 *
 * Why this exists
 * ---------------
 * The personal settings.local.json allows `Bash(*)` for ergonomics (the
 * developer was hitting constant prompts on compound / chained commands like
 * `cd x && ...`, `for ...; do ...; done`, `gh pr create`, etc.). But:
 *   1. Claude Code's permission matcher is LITERAL-PREFIX only — it does NOT
 *      do substring/glob matching, and it sees a chained command as one
 *      string. So an `ask` rule like `Bash(*rm -rf*)` never fires on
 *      `cd x && rm -rf y`. Prefix `ask` rules are easily bypassed by chaining.
 *   2. Relying on the assistant to "verbally confirm per CLAUDE.md §2" is
 *      unreliable — LLM behavior drifts over a long session.
 *
 * This hook closes both gaps deterministically: it regexes the FULL command
 * string (catching chained / mid-command occurrences) and forces a decision
 * regardless of the allow-list:
 *   - DENY  → catastrophic, irreversible (hard block; assistant cannot run it)
 *   - ASK   → destructive but sometimes legitimate (forces a user prompt)
 *
 * Hook output overrides the allow-list, so `Bash(*)` cannot bypass it.
 *
 * Failure mode: any parse error → silent fall-through (exit 0). A hook bug
 * must never block normal work; at worst the allow-list applies as before.
 */
'use strict';

const fs = require('fs');

let raw = '';
try { raw = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }

let payload;
try { payload = JSON.parse(raw); } catch { process.exit(0); }

if (!payload || payload.tool_name !== 'Bash') process.exit(0);
const rawCmd = (payload.tool_input && payload.tool_input.command) || '';
if (!rawCmd || typeof rawCmd !== 'string') process.exit(0);

// Sanitize: strip quoted strings + heredoc bodies before pattern-matching, so
// destructive patterns appearing as LITERAL TEXT (commit messages, gh --body,
// echo "...") don't false-positive. Only actual command-position tokens remain.
function sanitize(s) {
  let out = s;
  // Remove heredoc blocks: <<MARKER ... MARKER  /  <<'MARKER' ... MARKER
  out = out.replace(/<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1[\s\S]*?^\s*\2\s*$/gm, ' ');
  // Remove any remaining heredoc header + trailing (unterminated in this string)
  out = out.replace(/<<-?\s*(['"]?)[A-Za-z_][A-Za-z0-9_]*\1[\s\S]*$/m, ' ');
  // Remove single- and double-quoted spans.
  out = out.replace(/'[^']*'/g, ' ').replace(/"[^"]*"/g, ' ');
  return out;
}

const cmd = sanitize(rawCmd);

// ---------------------------------------------------------------------------
// EXEMPTION (deliberately narrow): `rm` confined to ONE dev scratch dir.
//
// WHY THIS SHAPE: blanket-banning `rm` makes agents beg for permission on every
// throwaway file (commit-message drafts, PR bodies, probe output), which trains
// the human to reflex-approve — and then they also reflex-approve the real ones.
// Blanket-allowing `rm` is obviously worse. So: auto-allow ONLY when EVERY target
// lives under one gitignored scratch folder. Any rm touching a path outside it,
// using `..` (traversal), or hiding targets behind shell tricks still falls
// through to the ASK rule. All other destructive verbs (git reset/clean/checkout/
// --force, kill, sudo, DB ops, docker) are UNAFFECTED.
//
// SETUP: point this at a gitignored scratch dir in your repo, and make sure
// something clears it (cron / CI / manual). Keep it narrow — widening this is
// how the exemption stops being an exemption.
// ---------------------------------------------------------------------------
const DEV_TMP_SEGMENT = process.env.AGENT_SCRATCH_DIR || 'tmp/agent-scratch/';
function rmConfinedToDevTmp(command) {
  const parts = command.split(/&&|\|\||;|\n/);
  let sawRm = false;
  for (const part of parts) {
    const m = part.match(/\brm\b([^]*)/);
    if (!m) continue;
    sawRm = true;
    const args = m[1].trim().split(/\s+/).filter((t) => t && !t.startsWith('-'));
    if (args.length === 0) return false;              // bare `rm` — not confined
    for (const a of args) {
      if (a.includes('..')) return false;             // path traversal — refuse
      if (!a.includes(DEV_TMP_SEGMENT)) return false; // target outside scratch
    }
  }
  return sawRm;
}

function rmIsAllGitRm(command) {
  const parts = command.split(/&&|\|\||;|\n/);
  let sawRm = false;
  for (const part of parts) {
    if (!/\brm\b/.test(part)) continue;
    sawRm = true;
    if (!/\bgit\s+rm\b/.test(part)) return false;
    if (/\brm\b/.test(part.replace(/\bgit\s+rm\b/g, ' '))) return false;
  }
  return sawRm;
}
const rmExempt = rmConfinedToDevTmp(cmd) || rmIsAllGitRm(cmd);


// ---------------------------------------------------------------------------
// DENY — catastrophic / irreversible. Hard block.
// ---------------------------------------------------------------------------
const DENY = [
  // rm -rf targeting root, home, or a bare glob/var that can nuke everything
  { re: /\brm\s+-[a-zA-Z]*r[a-zA-Z]*f?\b[^|;&\n]*\s(\/|~|\$HOME|\/\*|\.\s*$)/, why: 'rm -rf on root/home/glob' },
  { re: /\brm\s+-[a-zA-Z]*f[a-zA-Z]*r\b[^|;&\n]*\s(\/|~|\$HOME|\/\*)/, why: 'rm -fr on root/home/glob' },
  // disk / filesystem destroyers
  { re: /\bdd\b[^|;&\n]*\sof=\/dev\//, why: 'dd to a device' },
  { re: /\bmkfs\b/, why: 'mkfs (format filesystem)' },
  { re: /\b(>|>>)\s*\/dev\/(sd|disk|nvme|hd)/, why: 'write to raw disk device' },
  // fork bomb
  { re: /:\s*\(\s*\)\s*\{\s*:\s*\|\s*:/, why: 'fork bomb' },
  // remote-script execution via process substitution: `. <(curl …)`, `source <(wget …)`.
  // settings.json CANNOT block this — Claude Code's permission matcher parses `<(` as a
  // shell operator before prefix-matching sees it, so `Bash(. <:*)` / `Bash(source <:*)`
  // silently never fire (verified 2026-07-18). A hook sees the raw string, so the block
  // has to live here. Matches the downloader inside the process sub; the repo's own
  // installer uses `$(curl …)` (command sub), which this deliberately does not touch.
  { re: /<\(\s*(curl|wget)\b/, why: 'remote-script exec via process substitution (. <(curl…) / source <(wget…)) — download to a file, review it, then run' },
  // recursive chmod/chown from root
  { re: /\bchmod\s+-R\s+[0-7]{3,4}\s+\//, why: 'recursive chmod from /' },
  // force-push to the protected main/master branch
  { re: /\bgit\s+push\b[^|;&\n]*(--force|--force-with-lease|-f)\b[^|;&\n]*\b(origin\s+)?(main|master)\b/, why: 'force-push to main/master' },
  { re: /\bgit\s+push\b[^|;&\n]*\b(origin\s+)?(main|master)\b[^|;&\n]*(--force|--force-with-lease|-f)\b/, why: 'force-push to main/master' },
  // database obliteration
  { re: /\bDROP\s+DATABASE\b/i, why: 'DROP DATABASE' },
  // docker volume / full prune that wipes data
  { re: /\bdocker(\s+compose|-compose)?\b[^|;&\n]*\bdown\b[^|;&\n]*(-v|--volumes)\b/, why: 'docker compose down -v (wipes volumes)' },
  { re: /\bdocker\s+volume\s+rm\b/, why: 'docker volume rm' },
  { re: /\bdocker\s+system\s+prune\b[^|;&\n]*--volumes/, why: 'docker system prune --volumes' },
  // ── 自我欺騙防護(這兩條擋的不是「危險」,是「假數據」)────────────────────
  //
  // pipe 吞掉 exit code / 輸出。真實案例:同一個 session 裡踩兩次。
  //   `npm run build 2>&1 | tail -15 && echo "EXIT: $?"` -> $? 是 tail 的,不是 build 的
  //      -> 誤判「build 綠」,實際 31 個 type error。
  //   `jest 2>&1 | tail -30` 背景跑 -> 吃掉全部輸出,只剩 stack trace 尾巴,
  //      看不到它其實是 OOM 掛的,白白重跑一輪。
  // deny(非 ask)= 彈回模型自己改寫,人類零彈窗。
  { re: /\|\s*(tail|head)\b[^|;&\n]*(\$\?|&&\s*echo)/, why: 'pipe 吞掉 exit code/輸出 — 改用 `cmd > /tmp/x.log 2>&1; code=$?` 再讀檔' },

  // 並行 jest 撞共用 test DB。真實案例:同時跑兩份全套 -> FAIL 從 3 漲到 40/56,
  // 兩份數據全是垃圾,而且是「看起來像 regression」的那種垃圾,浪費 15 分鐘追鬼。
  // 專案 memory 早就寫著「並行會撞 DB」—— 但 memory 是背景知識,不是動作前的檢查項。
  // 所以把知識掛在 chokepoint 上:deny message 自己帶知識,不靠誰記得去讀。
  //
  // 只在「已有 jest 實例在跑」時擋(見 decide() 的 jestRule exemption)——
  // 單獨跑單檔是正當操作,無差別擋只會製造警報通膨。
  //
  // SETUP: 改成你的測試指令(vitest/pytest/go test…)與你的實際痛點。
  { re: /\bjest\b/, why: '已有 jest 在跑,會撞共用 test DB。等它跑完,或只跑受影響單檔 `npx jest <file> --runInBand`。(若你的專案全套跑會 OOM,把那個事實也寫進這行 —— deny message 是知識的最佳落點)', jestRule: true },
];

// ---------------------------------------------------------------------------
// ASK — destructive but sometimes legitimate. Force a prompt.
// ---------------------------------------------------------------------------
const ASK = [
  // rm is user-only: AI never runs any rm, even a bare flagless delete. Broader
  // than the -r/-f rule below, and deliberately so — the point is that deleting
  // things is the human's call, not that recursive deletes are scarier.
  // The narrow scratch-dir exemption above is the only way through.
  { re: /\brm\s/, why: 'rm is user-only — AI never runs rm (list files for the user instead)', rmRule: true },
  { re: /\brm\s+-[a-zA-Z]*[rf]/, why: 'recursive/forced rm', rmRule: true },
  { re: /\bfind\b[^|;&\n]*\s-delete\b/, why: 'find -delete' },
  // npm ci wipes and rebuilds node_modules. Real case: it clobbered a running
  // dev container's bind-mounted install mid-session. Drop this rule if your
  // setup doesn't share node_modules with anything live.
  { re: /\bnpm\s+ci\b/, why: 'npm ci wipes node_modules (§2); use link-worktree-node-modules.sh in worktrees' },
  { re: /\bgit\s+reset\s+--hard\b/, why: 'git reset --hard (discards changes)' },
  { re: /\bgit\s+clean\s+-[a-zA-Z]*f/, why: 'git clean -f (deletes untracked)' },
  { re: /\bgit\s+push\b[^|;&\n]*(--force|--force-with-lease|-f)\b/, why: 'force push' },
  { re: /\bgit\s+checkout\s+--\s/, why: 'git checkout -- (discards file changes)' },
    // git branch -D: squash-merge 讓 -d(安全版)永遠失效 —— 本 repo 刪 merged branch 只能用 -D,
  // 是常規操作而非高危指令,誤刪有 reflog 90 天可救。無條件 ASK 只會製造警報通膨:
  // 每天彈好幾次 → 習慣性按 yes → 連 rm / DROP TABLE 也照按。只攔真正該問的:protected branch。
  { re: /\bgit\s+branch\s+-D\b[^|;&\n]*\s(main|master|develop)(\s|$)/, why: 'force-delete a protected branch (main/master/develop)' },
  { re: /--no-verify\b/, why: 'bypasses git hooks (--no-verify)' },
  { re: /\bHUSKY=0\b/, why: 'bypasses husky hooks (HUSKY=0)' },
  { re: /core\.hooksPath\s*=\s*\/dev\/null/, why: 'disables all git hooks' },
  { re: /\bdocker\s+system\s+prune\b/, why: 'docker system prune' },
  { re: /\bDROP\s+TABLE\b/i, why: 'DROP TABLE' },
  { re: /\bTRUNCATE\b/i, why: 'TRUNCATE' },
  { re: /\bDELETE\s+FROM\b/i, why: 'DELETE FROM' },
  { re: /\bkill\s+-9\b/, why: 'kill -9' },
  { re: /\bsudo\b/, why: 'sudo (elevated privileges)' },
  { re: /\bchmod\s+777\b/, why: 'chmod 777' },
  { re: /\bchown\b/, why: 'chown' },
  // 寫入/複製 .env / secret / 憑證檔:permission deny 的 Edit(path) 只擋編輯工具,
  // Bash 的 redirect / cp / mv / tee / sed -i 完全繞得過。§2「修改 .env / secrets / *.pem
  // 需確認」+「.env 絕不碰」→ ASK 強制確認(init-local-env 這類合法場景存在,故非硬 deny)。
  // 只攔「寫入動作」,純讀(cat/grep/source .env)不匹配。
  { re: /(?:>|>>)\s*['"]?\S*\.(?:env|pem|key)\b/, why: 'redirect 寫入 .env/secret 檔 — .env 絕不碰,要動先確認' },
  { re: /\b(?:cp|mv|tee|rsync|install)\s[^|;&\n]*\.(?:env|pem|key)\b/, why: '複製/搬移/寫入 .env/secret 檔 — 禁把 .env 複製進 worktree,要動先確認' },
  { re: /\bsed\s+-i\b[^|;&\n]*\.(?:env|pem|key)\b/, why: 'sed -i 就地改 .env/secret 檔 — 要動先確認' },
  { re: /(?:(?:>|>>)\s*['"]?\S*|\b(?:cp|mv|tee|sed\s+-i)\b[^|;&\n]*)credentials\S*\.json\b/, why: '寫入/複製 credentials json — 要動先確認' },
];

function decide() {
  for (const { re, why, jestRule } of DENY) {
    if (!re.test(cmd)) continue;
    // jest: 只有「已經有 jest 在跑」才擋 — 單獨跑單檔是正當操作。實測 2026-07-17:
    // pgrep 不會匹配到本 hook 自己的 node 行程,無 jest 時 exit=1 → 放行。
    if (jestRule && !jestRunning()) continue;
    return { d: 'deny', why };
  }
  for (const { re, why, rmRule } of ASK) {
    if (!re.test(cmd)) continue;
    if (rmRule && rmExempt) continue; // rm confined to dev scratch dir — auto-allowed
    return { d: 'ask', why };
  }
  return null;
}

function jestRunning() {
  try {
    require('child_process').execSync('pgrep -f jest', { stdio: 'pipe' });
    return true;
  } catch {
    return false; // pgrep exit 1 = 沒有 jest 在跑
  }
}

const verdict = decide();
if (!verdict) process.exit(0); // not destructive — let allow-list / other hooks decide

// gate-fires ledger(2026-07-17 D2):每次 verdict 觸發時記一行。
// 這是系統裡唯一「不能自吹」的行為計數器 —— deny 觸發 = 我又嘗試了那個壞 pattern
// (然後被彈回改寫)。嘗試次數的週曲線就是「內化了沒」的可否證數據,
// 週改進循環(skillopt step 4)讀它,不靠 orchestrator 自評。
// 鐵律:自身故障絕不擋工作 —— 全包 try/catch,失敗靜默。
try {
  const ledgerPath = require('path').join(__dirname, '..', '..', '.planning', 'learning', 'gate-fires.jsonl');
  fs.appendFileSync(ledgerPath, JSON.stringify({
    ts: new Date().toISOString(),
    verdict: verdict.d,
    why: verdict.why,
    cmd: rawCmd.slice(0, 120),
  }) + '\n');
} catch { /* ledger 寫不進去不該擋任何指令 */ }


// Autonomous-pane mode: in a non-interactive fleet role (reviewer, alarm, …)
// there is no human to answer an "ask" prompt, so an ask verdict would HANG
// the pane forever. Such roles launch their Claude session with
// CLAUDE_ASK_AS_DENY=1, which downgrades every ask → deny (hard block, no
// wait). Interactive sessions leave it unset and keep the ask prompt.
const askAsDeny = process.env.CLAUDE_ASK_AS_DENY === '1';
let decision = verdict.d;
let autoDenied = false;
if (decision === 'ask' && askAsDeny) {
  decision = 'deny';
  autoDenied = true;
}

const reason =
  decision === 'deny'
    ? autoDenied
      ? `bash-destructive-guard: ${verdict.why}. Auto-denied in autonomous pane ` +
        `(CLAUDE_ASK_AS_DENY=1) — no human to confirm; run it from an interactive session.`
      : `bash-destructive-guard: ${verdict.why}. Blocked as catastrophic/irreversible ` +
        `(CLAUDE.md §2). Remove the deny rule to override.`
    : `bash-destructive-guard: ${verdict.why}. Requires explicit confirmation (CLAUDE.md §2).`;

const out = {
  hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    permissionDecision: decision,
    permissionDecisionReason: reason,
  },
};
process.stdout.write(JSON.stringify(out));
process.exit(0);
