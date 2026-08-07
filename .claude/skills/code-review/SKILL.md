---
name: code-review
description: Audit a PR against your project's red lines + test gate. Apply your project's PR open/draft policy — PASS keeps it OPEN, FAIL demotes it to DRAFT with guidance. Use when you need to audit a specific PR directly. Trigger words: "review PR", "code review", "audit this PR", "can this PR pass", "red-line audit".
---

# code-review

Single-responsibility skill: audit one PR against project red lines + test gate, act per your
project's open/draft policy.

## When to invoke

- User says "review PR #N"
- Pre-merge sanity check on a critical PR
- You need an independent audit pass before merge

## Inputs

- `pr`: PR number (e.g. 152)

## Pre-flight

```
gh pr view <N> --json number,title,headRefName,baseRefName,additions,deletions,changedFiles,isDraft,mergeable,statusCheckRollup
```

Verify:
- baseRefName == main
- mergeable in [MERGEABLE, UNKNOWN] (CONFLICTING -> run `pr-conflict-solver` first)

## Audit checklist (sequential)

### Layer 1: red lines (per your project rules doc)

Adapt the specific rule numbers to whatever your project's red-line doc actually defines; the
checks below are the common shape:

| Check | Cmd |
|---|---|
| Emoji in code/comments/log | `gh pr diff <N> \| grep -E '[\\u{1F000}-\\u{1FFFF}]'` |
| Full-file overwrite (>200 LOC single-file change without a commit message explaining why) | manual scan |
| Compile fail (tsc/build) | run in the PR's own branch checkout (not a throwaway /tmp dir): `tsc --noEmit` |
| Unsafe DOM/dynamic-eval sinks (`alert`/`confirm`/`prompt`, `dangerouslySetInnerHTML`, `eval`) | `gh pr diff <N> \| grep -E '\\b(alert\|confirm\|prompt)\\('` |
| Direct commit to main | `git log origin/main..HEAD --oneline` (should show nothing outside the PR's own branch history) |
| Test coverage for changed code | `gh pr diff <N>` shows a matching `*.spec.ts` / `*.test.tsx` for new code paths? |
| Bypassed git hooks (`--no-verify`) | `git log --format=%B \| grep -i 'no-verify\|hooks'` |

### Layer 2: three-gate test discipline

- [ ] Unit/component test: PR description shows tsc/build/scoped-test all green AND git log has
  a `test(...)` commit
- [ ] Scoped regression/e2e: relevant test files cover the changed feature, OR an
  external-dependency tag is applied per your project's anti-deadlock policy
- [ ] Build: `npm run build --workspace=<changed>` (or your build command) actually run

### Layer 3: scope flags

- LOC > 500 (lockfile excluded) -> FLAG (recommend splitting the PR)
- Cross-shared-package change -> FLAG for cross-workstream awareness
- Schema change -> FLAG whatever coordination your project requires for shared DB migrations

### Layer 4: license audit

Triggered whenever the PR adds/changes a `package.json` dependency, or introduces vendor code
(e.g. a CSS asset from a third-party SDK).

| Check | Cmd / Action |
|---|---|
| New deps in package.json | `gh pr diff <N> -- '**/package.json'` — list every added/changed dep |
| Each new dep's license | `npm view <pkg> license` — flag anything not in [MIT, ISC, BSD-2-Clause, BSD-3-Clause, Apache-2.0, CC0, Unlicense, 0BSD] |
| Commercial / EULA red flags | grep the diff for: `watermark`, `MADE WITH`, `EULA`, `LICENSE_KEY`, `licenseKey`, `requireLicense` — watch for vendor watermark CSS suppressed without paying for a license |
| AGPL / SSPL / BSL leakage | If the license is AGPL/SSPL/BSL/Commons-Clause, escalate to the user immediately (legal exposure, potential disclosure obligations even for internal use) |
| License compatibility | For a private/proprietary project, copyleft (GPL/AGPL) deps require legal review |
| Watermark/branding suppression | Any CSS rule hiding a vendor's branding/watermark -> BLOCK with an EULA-violation reason |

**Outcome:** any non-permissive license OR watermark suppression -> **BLOCK** with an `[EULA]`
tag in the verdict header. The PR description must document a license review pass before
re-audit.

### Layer 5: security & dependency CVE audit

Triggered whenever the PR adds/changes/pins a dependency, or touches auth / token / crypto /
file-upload / SQL paths.

#### 5a — Dependency CVE check
| Check | Cmd / Action |
|---|---|
| New / bumped deps | `gh pr diff <N> -- '**/package.json' '**/package-lock.json'` |
| CVE scan (per workspace touched) | `npm audit --workspace=<ws> --audit-level=high --json` — parse for `severity=high\|critical`. Zero critical/high allowed in new deps; pre-existing carry-overs OK with a `[CVE-CARRY]` flag if they predate this PR |
| Transitive lockfile bump | If the lockfile diff has new `node_modules/<x>` entries, audit those too |
| Pinning hygiene | New deps in security-sensitive paths (auth/crypto/file) should be pinned exact (no `^`/`~`); flag soft pinning |
| Cross-check with an OSV/vuln scanner (optional) | Run one if available; otherwise skip with a note |

#### 5b — Code-path security audit (diff touches sensitive files)

Triggers (any path match): auth/token/middleware modules, file-upload handlers, raw SQL
(`gh pr diff <N> | grep -E '\$queryRaw|\$executeRawUnsafe|sql\`'`), any new HTTP endpoint
handler, anything touching `.env*`/secret loading/JWT/session.

| Check | Action |
|---|---|
| Input validation at the boundary | Verify a schema validator on new API params; missing -> BLOCK |
| Authz check present | Every new endpoint has an auth/role gate; missing -> BLOCK |
| SQL injection | Parameterized queries only; raw SQL has parameter binding; missing -> BLOCK |
| XSS | Raw HTML injection / template injection in the diff -> BLOCK |
| Secret in diff | grep for private-key markers, cloud secret patterns, hardcoded passwords, bearer-token literals -> BLOCK + alert the user |
| Open redirect | Any redirect built from unvalidated user input, no allowlist -> BLOCK |
| CSRF | New state-changing endpoint without CSRF/SameSite protection -> FLAG |
| Rate limit | New unauthenticated endpoint without rate-limit middleware -> FLAG |

**Outcome:**
- Any high/critical CVE in a NEW dep -> **BLOCK** with a `[CVE]` tag
- Any unfixed code-path security issue -> **BLOCK** with a `[SEC]` tag
- Pinning / flag-tier issues -> **FLAG** (advisory, doesn't block merge)

## Decision matrix

**Use a file-based PR comment body** (write the verdict to a file with the Write tool, then
`gh pr comment <N> --body-file <file>`) — never a bash heredoc/`printf`/inline body, which can
trip a shell-substitution confirmation prompt on every review and get flaky on backticks.

**Don't use** `gh pr review --approve` / `--request-changes` if your GitHub credential is shared
across automated actors (self-review gets blocked by GitHub itself); express the verdict
(PASS/BLOCK/FLAG) in the comment body instead.

| Outcome | Condition | Action |
|---|---|---|
| **PASS** | red lines clear + all test gates clear | keep OPEN + post a comment with a PASS verdict header |
| **BLOCK** | any red-line fail OR a test gate unchecked OR missing test output | keep OPEN (don't demote to DRAFT unless your project's visibility policy calls for it) + post a comment with the 4-section guidance below |
| **FLAG** | LOC > 500 / scope creep / a non-blocking flag | keep OPEN + post a comment noting the flag |

## BLOCK comment format (mandatory, 4 sections)

```
[review BLOCK] test-gate / red-line violation

Reason: <the specific test gate / red line that failed>

Evidence:
- <commit hash> / <file:line> of the change
- <test output snippet> / <tsc error code>

Fix steps:
1. <concrete step 1>
2. <concrete step 2>
...
N. push + mark the PR ready again

Re-audit happens after resubmission.
```

## Constraints

- **NEVER** auto-merge a PR — you open, the human merges.
- **NEVER** modify the PR's code during review (write feedback in the PR comment, let the
  author fix it).
- Verify tsc/build in the PR's own branch checkout, not a throwaway scratch dir — running it
  somewhere disconnected from the actual branch has burned real review time before.
- Run tests in mock mode if an integration environment isn't available, per your project's
  anti-deadlock policy for external-dependency gaps.

## Reply protocol

- PASS -> reply: `PR #<N> DONE — red lines clear, test gate clear, LOC <X>` (1 line)
- BLOCK -> reply: `PR #<N> BLOCK — <one-line reason>` + post the comment
- FLAG -> reply: `PR #<N> FLAG — <flag reason>` + post the comment + keep OPEN

## Related skills

- `pr-conflict-solver`: run first if mergeable=CONFLICTING

## Examples

User: "review #155"
-> pre-flight + Layer 1-5 audit -> decision (PASS/BLOCK/FLAG) -> post comment + state the action
