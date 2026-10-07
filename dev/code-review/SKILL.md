---
name: code-review
description: Audit a PR per the project's CLAUDE.md red lines + test gate, then triage findings - mechanical and small clear-cut correctness issues are fixed by the reviewer on the PR branch (one review round, not review-then-dispatch-then-reverify), one-way-door or design-tradeoff issues go back marked 需 user 判斷. Verdict (PASS/FIXED/BLOCK/FLAG) and every self-fix are recorded on the PR (comment + 審查紀錄 line in the description, GitHub or Bitbucket). PR open/draft state follows the RTM rule (feature-pipeline), this skill does not change it. 觸發詞:「審 PR」「code review」「PR 稽核」「幫我看這個 PR」「檢查 PR 合不合規」「這個 PR 能過嗎」「紅線稽核」。
---

# code-review

Single-responsibility skill: audit one PR against the project's red lines + test gate, fix what is safe to fix in place (see Findings triage), record the verdict and fixes on the PR.

Project-specific values come from the project, not this file: red-line list and test-gate wording from the project `CLAUDE.md`; test / lint / typecheck / build commands and workspace names from `kit.json`. Red-line numbers below are written as "the project's red line on X" because numbering differs per project; cite the project's own number in the verdict.

If `kit.json` `prHost` is `bitbucket`: input is the PR's branch plus its numeric PR id (from the PR URL); translate every `gh` command below with the table in `git-gh-ops` (PR host: bitbucket). Recording on the PR uses `${CLAUDE_SKILL_DIR}/../git-gh-ops/bitbucket/comment-pr.sh` (verdict comment) and `update-pr.sh` (審查紀錄 line); if the PR id is unknown or the scripts are blocked by the permission classifier, fall back to reporting in chat and say so.

Model: the mechanical layers (1-4, test-shape check, license grep) run on **sonnet**. One-way-door PRs (see `feature-pipeline` Door rule, `door-check.sh`) get the correctness / security judgement on **opus**.

## When to invoke

- User says "review PR #N"
- Pre-merge sanity check on a critical PR
- A feature-pipeline verification step asks for a PR audit

## Inputs

- `pr`: PR number (e.g. 152)

## Pre-flight

```
gh pr view <N> --json number,title,headRefName,baseRefName,additions,deletions,changedFiles,isDraft,mergeable,statusCheckRollup
```

Verify:
- baseRefName == the project's default branch (normally `main`)
- headRefName matches the project's branch naming convention (`<type>/<scope>-<desc>`)
- mergeable in [MERGEABLE, UNKNOWN] (CONFLICTING → spawn `pr-conflict-solver` first)

## Audit checklist (sequential)

### Layer 1: red lines (per the project CLAUDE.md)

Read the project's red-line table first and audit every row. The checks below are the common shape; map each to the project's own rule number.

| Check | Cmd |
|---|---|
| Emoji in code/comments/PR body | the project's machine gate (emoji-scan hook / CI job) — confirm it is green; scan the PR body by eye |
| Full-file overwrite (>200 LOC single-file change without a commit msg explaining why) | manual scan |
| Compile fail (typecheck/build) | run in the PR's worktree (NOT a cold /tmp checkout) with the `kit.json` typecheck command |
| Legal / consent / compliance bypass flags (whatever the project's CLAUDE.md names) | `gh pr diff <N> \| grep -i <flag-name>` |
| Forbidden browser dialogs / unsafe sinks (`alert`/`confirm`/`prompt`, `dangerouslySetInnerHTML`, `eval`) if the project forbids them | `gh pr diff <N> \| grep -E '\\b(alert\|confirm\|prompt)\\('` |
| Direct commit to a protected branch | `git -C <wt> log origin/main..HEAD --oneline` (should NOT show direct main commits) |
| Test gate cover (tests run for changed module) | `gh pr diff <N>` shows spec/test files for new code paths? |
| Hook bypass (`--no-verify`) | `git -C <wt> log --format=%B \| grep -i 'no-verify\|hooks\|husky'` |

### Layer 2: three test gates (per the project CLAUDE.md)

- [ ] Unit/component test: PR description checks typecheck / build / scoped tests green AND git log has `test(...)` commit
- [ ] Scoped regression / E2E: relevant specs cover changed feature OR the project's external-dependency tag is applied (anti-deadlock policy in CLAUDE.md)
- [ ] Build: the `kit.json` build command for the changed workspace, run in the PR's worktree
- [ ] Test shape: new / changed tests test only through the public interface (rules below)

#### Test shape: only through the public interface

Tests that pin implementation details turn red on every harmless change and push the next agent into a fix-reverify loop. Every new / changed test in the diff must fit:

- **Backend API**: hit the HTTP route; assert status code, response body, and resulting DB state.
- **Module**: call only what the module exports, against the real (test) DB.
- **Frontend**: testing-library queries by role and visible text, not component internals.
- **Mock only cross-process external services**: LLM, object storage, government / customs filing gateway, email, message push. Never mock the project's own internal modules.
- **Forbidden**:
  - tautological tests: copying an implementation constant or formula into the test as the expected value;
  - mocking the project's own internal modules;
  - asserting call counts of private / internal functions;
  - asserting a full user-facing message string (assert the code / severity / key instead).
- **Calculation expected values need an independent source**: an official worked example, a hand-computed golden, or real data. Never compute the expected value in the test with the same formula as the code.

Example (2026-10-07, real project): a test asserted the full Chinese text of a validation-issue message; when the message switched to integer display it went red every time, while the behaviour was fine. Asserting the issue code + severity would have stayed green.

A violating test is a **small correctness** finding (see Findings triage): rewrite it as an interface test, then commit. Never just delete it.

### Layer 3: Scope flags

- LOC > 500 (lockfile excluded) → FLAG (split PR recommendation)
- Cross-shared-package change → FLAG for cross-worktree awareness (shared-package paths from the project CLAUDE.md)
- Schema / migration change → FLAG the project's DB coordination requirement (lock / serialization rule in CLAUDE.md, if any)

### Layer 4: License audit

Triggered whenever PR adds / changes a package manifest dependency OR introduces vendor code (e.g. CSS asset from a third-party SDK).

| Check | Cmd / Action |
|---|---|
| New deps in manifest | `gh pr diff <N> -- '**/package.json'` — list every added/changed dep |
| Each new dep license | `npm view <pkg> license` — flag anything not in [MIT, ISC, BSD-2-Clause, BSD-3-Clause, Apache-2.0, CC0, Unlicense, 0BSD] |
| Commercial / EULA red flags | grep diff for: `watermark`, `MADE WITH`, `EULA`, `LICENSE_KEY`, `licenseKey`, `requireLicense` (e.g. hiding a vendor's watermark without a license) |
| AGPL / SSPL / BSL leakage | If license is AGPL/SSPL/BSL/Commons-Clause, escalate to user IMMEDIATELY (legal exposure, even for internal use can trigger disclosure obligations) |
| License compatibility with project | If the project is private/proprietary, copyleft (GPL/AGPL) deps require legal review |
| Watermark / branding suppression | Any CSS rule that hides a vendor's branding/watermark → BLOCK with EULA-violation reason |

**Outcome:** any non-permissive license OR watermark suppression → **BLOCK** with `[EULA]` tag in verdict header. PR description must document license review pass before re-audit.

### Layer 5: Security & dependency CVE audit

Triggered whenever PR adds / changes / pins a dependency OR touches auth / token / crypto / file upload / SQL paths.

#### 5a — Dependency CVE check
| Check | Cmd / Action |
|---|---|
| New / bumped deps | `gh pr diff <N> -- '**/package.json' '**/package-lock.json'` |
| CVE scan (per workspace touched) | `npm audit --workspace=<ws> --audit-level=high --json` — parse `vulnerabilities` for `severity=high|critical`. ZERO critical / high allowed in new deps; existing carry-overs OK with `[CVE-CARRY]` flag if pre-existed in main. |
| Transitive lockfile bump | If the lockfile diff has any new `node_modules/<x>` entries, run audit on those too |
| Pinning hygiene | New deps SHOULD be pinned to exact (no `^` / `~`) for security-sensitive paths (auth / crypto / file). FLAG soft pinning. |
| OSV cross-check (optional) | `npx osv-scanner --lockfile=package-lock.json` if `osv-scanner` available; else skip with note |

#### 5b — Code-path security audit (when diff touches sensitive files)

Triggers (any path match; adapt the globs to the project layout in CLAUDE.md / kit.json):
- auth, token, middleware directories
- upload / file-handling code
- Anywhere with raw SQL: `gh pr diff <N> | grep -E '\$queryRaw|\$executeRawUnsafe|sql\`'`
- Any new HTTP endpoint handler
- Any change touching `.env*`, secret loading, JWT/session

| Check | Action |
|---|---|
| Input validation at boundary | Verify the project's schema validator (zod / joi / class-validator…) on new API params; missing → BLOCK |
| Authz check present | Every new endpoint has an auth / role gate; missing → BLOCK |
| SQL injection | Parameterized queries only; raw SQL has parameter binding; missing → BLOCK |
| XSS | `dangerouslySetInnerHTML`, `v-html`, raw template injection in PR diff → BLOCK |
| Secret in diff | grep diff for: `BEGIN PRIVATE KEY`, `aws_secret`, `api_key`, `password\s*=\s*['"]`, `Bearer [a-zA-Z0-9]` literal → BLOCK + alert user |
| Open redirect | Any `res.redirect(req.query....)` without allowlist check → BLOCK |
| CSRF | New POST/PUT/DELETE endpoint without CSRF token / SameSite cookie verification → FLAG |
| Rate limit | New unauth-callable endpoint without rate-limit middleware → FLAG |

**Outcome:**
- Any high/critical CVE in NEW dep → **BLOCK** with `[CVE]` tag
- Any unfixed code-path security issue → **BLOCK** with `[SEC]` tag
- Pinning / FLAG-tier issues → **FLAG** (advisory, doesn't block merge)

## Findings triage(審查者自修分流)

目的:一個小問題只跑一輪。舊流程「審查只回報 → 再派開發修 → 再派複驗」一個 typo 也要三輪 agent,吃掉大量 token。審查者先分類每個 finding,能安全就地修的就修:

| 類型 | 例 | 處理 |
|---|---|---|
| **機械類** | 命名、格式、遺留註解 / 工單代號、emoji、文案、測試斷言對齊現行行為(行為沒變、只是斷言過時) | 審查者直接修 → 重跑範圍化測試(受影響 spec + typecheck)→ 原子 commit 推回 PR 分支 → 記錄到 PR |
| **小範圍正確性** | 修法明確、只動 1-2 檔、不碰單向門路徑:漏掉的邊界、錯的條件、違反 Test shape 的測試(改寫成介面測試,不可刪) | 審查者修 + 補 / 改測試 → **另派一次 fresh-context sonnet read-back**(看 diff + 實跑測試,不採信審查者自述;審查者是 subagent 不能再派時,由 orchestrator 代派)→ read-back 通過才 commit 推回 → 記錄到 PR |
| **單向門 / 需設計取捨** | 稅費 / 金額 / 法定檔案(XML)計算、權限 / 租戶隔離、migration / schema、金流、prod 資料、對外推播;或修法不只一種、要選方向 | **不自修**。BLOCK 打回,comment 標頭與審查紀錄都標「需 user 判斷」,附選項與取捨 |

判定單向門:跑 `bash ${CLAUDE_SKILL_DIR}/../feature-pipeline/door-check.sh <base> <head>`(路徑規則,專案在 `kit.json` `review.oneWayDoorPaths` 補自己的路徑)。finding 所在檔案命中 → 一律走第三列,即使修法看起來很小。

自修紀律:
- 在 PR 自己的 worktree / 分支上修;先 `git -C <wt> status --short` 確認乾淨,有別人的 WIP 就不修、改成 BLOCK。
- 每個 finding 一個原子 commit(Conventional Commits,描述寫問題 + 修法),一律新 commit,不 `--amend`、不 force push、不 `--no-verify`。
- 測試沒過、或修一次沒修好 → 停手,改走 BLOCK(不做第二次同樣嘗試)。
- 自修過的 PR 仍維持 RTM 原狀:不 merge、不改 open/draft。

## Recording on the PR(審查紀錄補到 PR)

每次審查結束、每個自修 commit,都補到 PR 上,不只在對話回報:

1. **Comment**(verdict 全文):格式見下方 PASS / FIXED / BLOCK / FLAG;FIXED 逐條列「問題 / 修法 / commit sha / 測試輸出摘錄」。
2. **Description 的 `## 審查紀錄` 段追加一行**:`<YYYY-MM-DD> <reviewer model> <VERDICT> <sha 或 -> <一句摘要>`(BLOCK 需 user 判斷的寫「需 user 判斷: <議題>」)。段落不存在則建立在 description 末尾。

| | GitHub | Bitbucket(`kit.json` `prHost: bitbucket`) |
|---|---|---|
| comment | `gh pr comment <N> --body-file <f>` | `${CLAUDE_SKILL_DIR}/../git-gh-ops/bitbucket/comment-pr.sh <remote> <id> <f>` |
| 審查紀錄 | `gh pr view <N> --json body --jq .body > <scratch>/cur.md`,用 Edit 在 `## 審查紀錄` 段尾加一行存 `<scratch>/new.md`,`gh pr edit <N> --body-file <scratch>/new.md` | `${CLAUDE_SKILL_DIR}/../git-gh-ops/bitbucket/update-pr.sh <remote> <id> "<line>"` |

Bitbucket 腳本支援 `DRY_RUN=1`(只印 method / URL / payload,不讀憑證不送出);第一次在新專案使用先 dry run。被權限 classifier 擋下時不繞過,改在對話回報並告知 user 加 allow rule(見 `git-gh-ops`)。

## Decision matrix

PR 開 OPEN 的時機由 RTM 紀律決定(PR 只在 RTM 開 OPEN,見 `feature-pipeline`);本 skill 只出 verdict,不改 PR 的 open/draft 狀態。

Always use a file-based comment body (`--body-file` / the Bitbucket script's body file), with the file placed in the session scratchpad (or the project's tmp dir), not inline.

**Write the verdict file with the Write tool, NOT a bash heredoc / cat / printf** — any shell-substitution form triggers a permission dialog and gets flaky on backticks. The Write tool has zero dialogs.

**Also do not use** `gh pr review --approve` / `--request-changes` — a shared GitHub credential blocks self-review; the verdict header (PASS/FIXED/BLOCK/FLAG) lives in the comment body.

**Standard audit flow**:
1. Audit (Layers 1-5) → triage findings → self-fix the fixable ones (commits pushed to the PR branch)
2. Write tool → `<scratch>/<n>-verdict.md` (audit full text + verdict header)
3. Post the comment + append the 審查紀錄 line (table above)

| Outcome | Condition | Action |
|---|---|---|
| **PASS** | red lines clear + 3 test gates clear, no findings | comment (verdict header PASS) + 審查紀錄 |
| **FIXED** | every finding was mechanical / small correctness and is now fixed, tests re-run green (small correctness: sonnet read-back passed) | comment listing 問題 / 修法 / sha / 測試輸出 + 審查紀錄; no re-review round needed |
| **BLOCK** | any finding left unfixed: one-way door / design trade-off (標「需 user 判斷」), self-fix failed, red-line fail, test gate unchecked, test output missing | comment with the 4-section guidance + 審查紀錄; PR state untouched |
| **FLAG** | LOC > 500 / scope creep / non-blocking flag | comment listing the flag + 審查紀錄, does not block merge |

## BLOCK comment 4-section format (mandatory)

```
[BLOCK] test gate / red-line violation | 需 user 判斷: <議題>   (pick the matching header)

Reason: <which test gate / project red line failed, or the one-way-door / trade-off question with options>

Evidence:
- <commit hash> / <file:line> of the change
- <test output snippet> / <tsc error code>

Fix steps:
1. cd <the PR's worktree path>
2. <concrete step 1>
3. <concrete step 2>
...
N. git push (push the fix to the same branch)

Re-audit after the fix.
```

## Allowlist coverage

- `Bash(gh pr view *)`, `Bash(gh pr diff *)`, `Bash(gh pr checks *)`, `Bash(gh pr comment * --body *)`, `Bash(gh pr edit * --body-file *)`
- `Bash(git -C * log *)`, `Bash(git -C * diff *)`
- `Bash(<skills-dir>/git-gh-ops/bitbucket/comment-pr.sh:*)`, `Bash(<skills-dir>/git-gh-ops/bitbucket/update-pr.sh:*)`, `Bash(bash <skills-dir>/feature-pipeline/door-check.sh:*)` (user adds these in settings, where `${CLAUDE_SKILL_DIR}` is not substituted: `<skills-dir>` is `~/.claude/skills` for a symlink install, or the plugin cache path shown by the permission prompt for a plugin install; the Bitbucket ones touch credentials)
- File paths read for source verification (Read tool)

## Constraints

- **NEVER** auto-merge a PR ("I open, the user merges")
- Modify the PR's code only per Findings triage (mechanical / small correctness, never a one-way-door path); everything else goes back as BLOCK
- Use the PR's worktree for typecheck/build verification, not a fresh /tmp checkout (a cold checkout needs a full install and stalls the audit)
- Run tests in mock mode if integration env not available (the project's anti-deadlock policy)

## Reply protocol

- PASS → reply: `PR #<N> DONE — red lines ok, test gate ok, LOC <X>` (1 line)
- FIXED → reply: `PR #<N> FIXED — <k> findings self-fixed (<sha list>), tests green` + post comment
- BLOCK → reply: `PR #<N> BLOCK — <one-line reason>` (or `需 user 判斷: <議題>`) + post comment
- FLAG → reply: `PR #<N> FLAG — <flag reason>` + post comment

## Related skills

- `pr-conflict-solver`: pre-step if mergeable=CONFLICTING
- `git-gh-ops`: provides primitives (pr-comment-block, Bitbucket comment / description scripts)
- `feature-pipeline`: Door rule (`door-check.sh`) and who re-verifies

## Examples

User: "review #155"
→ pre-flight + Layer 1-5 audit → triage → self-fix mechanical / small correctness → decision (PASS/FIXED/BLOCK/FLAG) → comment + 審查紀錄 line
