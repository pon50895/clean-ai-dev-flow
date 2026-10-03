---
name: code-review
description: Audit a PR per the project's CLAUDE.md red lines + test gate. Verdict (PASS/BLOCK/FLAG) goes in a PR comment, with a 4-section guidance block on BLOCK; PR open/draft state follows the RTM rule (feature-pipeline), this skill does not change it. 觸發詞:「審 PR」「code review」「PR 稽核」「幫我看這個 PR」「檢查 PR 合不合規」「這個 PR 能過嗎」「紅線稽核」。
---

# code-review

Single-responsibility skill: audit one PR against the project's red lines + test gate, post the verdict as a PR comment.

Project-specific values come from the project, not this file: red-line list and test-gate wording from the project `CLAUDE.md`; test / lint / typecheck / build commands and workspace names from `kit.json`. Red-line numbers below are written as "the project's red line on X" because numbering differs per project; cite the project's own number in the verdict.

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

## Decision matrix

PR 開 OPEN 的時機由 RTM 紀律決定(PR 只在 RTM 開 OPEN,見 `feature-pipeline`);本 skill 只出 verdict,不改 PR 的 open/draft 狀態。

Always use a file-based comment body: `gh pr comment <N> --body-file <file>`, with the file placed in the session scratchpad (or the project's tmp dir), not inline.

**Write the verdict file with the Write tool, NOT a bash heredoc / cat / printf** — any shell-substitution form triggers a permission dialog and gets flaky on backticks. The Write tool has zero dialogs.

**Also do not use** `gh pr review --approve` / `--request-changes` — a shared GitHub credential blocks self-review; the verdict header (PASS/BLOCK/FLAG) lives in the comment body.

**Standard audit flow (2 steps, 0 dialogs)**:
1. Write tool → `<scratch>/<n>-verdict.md` (audit full text + verdict header)
2. `bash gh pr comment <N> --body-file <scratch>/<n>-verdict.md` (single line, no substitution)

| Outcome | Condition | Action |
|---|---|---|
| **PASS** | red lines clear + 3 test gates clear | `gh pr comment` (verdict header PASS) |
| **BLOCK** | Any red-line fail OR test gate unchecked OR test output missing | `gh pr comment` with the 4-section guidance; PR state untouched |
| **FLAG** | LOC > 500 / scope creep / non-blocking flag | `gh pr comment` listing the flag, does not block merge |

## BLOCK comment 4-section format (mandatory)

```
[BLOCK] test gate / red-line violation

Reason: <which test gate / project red line failed>

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

- `Bash(gh pr view *)`, `Bash(gh pr diff *)`, `Bash(gh pr checks *)`, `Bash(gh pr comment * --body *)`
- `Bash(git -C * log *)`, `Bash(git -C * diff *)`
- File paths read for source verification (Read tool)

## Constraints

- **NEVER** auto-merge a PR ("I open, the user merges")
- **NEVER** modify the PR's code during review (write feedback in the PR comment, let the author fix)
- Use the PR's worktree for typecheck/build verification, not a fresh /tmp checkout (a cold checkout needs a full install and stalls the audit)
- Run tests in mock mode if integration env not available (the project's anti-deadlock policy)

## Reply protocol

- PASS → reply: `PR #<N> DONE — red lines ok, test gate ok, LOC <X>` (1 line)
- BLOCK → reply: `PR #<N> BLOCK — <one-line reason>` + post comment
- FLAG → reply: `PR #<N> FLAG — <flag reason>` + post comment

## Related skills

- `pr-conflict-solver`: pre-step if mergeable=CONFLICTING
- `git-gh-ops`: provides primitives (pr-comment-block)

## Examples

User: "review #155"
→ pre-flight + Layer 1-5 audit → decision (PASS/BLOCK/FLAG) → post comment
