---
name: git-gh-ops
description: General git/gh wrapper operations — branch creation, PR open/comment/merge state, fetch+pull patterns. Use as building block for higher-level skills (pr-conflict-solver, code-review). Also holds the gh-to-git translation table used when kit.json `prHost` is bitbucket.
---

# git-gh-ops

Cross-cutting helper skill: bundle common git + gh operations.

Protected branch names (`main` / `master` / `release`...) and the default base branch come from the project's `kit.json` (`protected_branches`) or CLAUDE.md; the templates below use `main` as the common default.

## PR host: bitbucket

Read `kit.json` `prHost` first. Missing or `github` -> the gh commands below apply. `bitbucket` -> `gh` does not work against the repo; never run it. `<remote>/<base>` comes from `kit.json` `baseRef` (e.g. `mvp/main`), `<branch>` from the user or the PR page. Translate:

| gh (github) | bitbucket equivalent |
|---|---|
| `gh pr view <N> --json mergeable` | `git fetch <remote> && git merge-tree --write-tree <remote>/<base> <remote>/<branch>` (non-zero exit = conflict) |
| `gh pr view <N> --json headRefName,...` | ask the user for the branch, or read it off the PR page; there is no CLI lookup |
| `gh pr diff <N> [-- <paths>]` | `git diff <remote>/<base>...<remote>/<branch> [-- <paths>]` |
| `gh pr create` | the `bitbucket-pr` skill |
| `gh pr comment <N> --body-file <f>` | `~/.claude/skills/git-gh-ops/bitbucket/comment-pr.sh <remote> <id> <f>` |
| `gh pr edit <N> --body-file <f>` (append to the `## 審查紀錄` section) | `~/.claude/skills/git-gh-ops/bitbucket/update-pr.sh <remote> <id> "<line>"` |
| `gh pr list --state ...` | `git branch -r --merged <remote>/<base>` for merged; open-PR state needs the PR page or `bitbucket-pr` |
| `gh pr ready` / draft | not applicable (no draft PRs) |

The two Bitbucket scripts read the same credential file as `bitbucket-pr` (`~/.claude/secrets/bitbucket.env`), pass it to curl via stdin config (never in argv or output), and take `<id>` = the numeric PR id from the PR URL. `DRY_RUN=1` prints method, URL and payload without reading credentials or calling the API (`update-pr.sh` also takes `DRY_RUN_DESCRIPTION_FILE=<f>` to preview the append). They live here, not in `bitbucket-pr`, because that skill is not version-controlled and this skill already owns the gh-to-Bitbucket translation. If the auto-mode classifier blocks them as credential access, do not work around it: ask the user to add an allow rule (`Bash(~/.claude/skills/git-gh-ops/bitbucket/comment-pr.sh:*)`, same for `update-pr.sh`) or fall back to reporting in chat.

## Operations covered

| Op | When | Cmd template |
|---|---|---|
| `branch-from-main` | new feature start | `git -C <wt> fetch origin && git -C <wt> switch main && git -C <wt> pull --ff-only && git -C <wt> switch -c <branch>` |
| `worktree-status` | pre-flight check | `git -C <wt> status --short` |
| `worktree-clean?` | anti-race check | status output is empty OR only the hook manager's auto-generated dir (e.g. `.husky/_/`) |
| `pr-open-state` | check ready/draft | `gh pr view <N> --json isDraft --jq .isDraft` |
| `pr-mergeable?` | merge readiness | `gh pr view <N> --json mergeable --jq .mergeable` |
| `pr-list-open` | sweep | `gh pr list --state open --json number,title,headRefName,isDraft,mergeable` |
| `pr-list-merged-today` | sprint audit | `gh pr list --state merged --search "merged:>=$(date +%Y-%m-%d)" --json number,title,mergedAt` |
| `pr-comment-block` | review BLOCK | `gh pr comment <N> --body-file <file>` (header `[BLOCK]`) |
| `pr-create` | at RTM only | `gh pr create --base main --fill` |
| `pr-ready` | RTM, create OPEN PR directly (no draft) | `gh pr create --base main --fill` |
| `force-push-lease` | post-rebase | `git -C <wt> push --force-with-lease` (if the project's pre-push hook requires an env switch such as `ALLOW_FORCE_PUSH=1`, prefix it; the env name is in the project's hook / kit.json) |

## Constraints

- **NEVER** `git push --force` (always `--force-with-lease`)
- **NEVER** push to a protected branch (`main` / `master` / `release`) directly; go through a feature branch + PR
- **NEVER** `--no-verify` hook bypass
- **NEVER** chained `&&` with cd-style commands → use `git -C` always
- PR is created as an OPEN PR only at RTM (board status ready, tests green); before that only push the branch and do not create a PR (no draft PRs; see `feature-pipeline`)

## Pre-flight pattern (anti-race)

Before any cross-worktree write op (rebase / merge / cherry-pick into sibling):
```
sib_status=$(git -C <sibling-wt> status --short | grep -v '^?? \.husky/_/$' | head -5)
if [ -n "$sib_status" ]; then
  echo "BLOCKED: sibling has WIP — ask the user to have that session pull itself, don't act for it"
  exit 1
fi
```

## Compound logic = wrap as helper script

Inline `for w in ...; do ... done` triggers a "Contains simple_expansion" permission dialog every invocation. **Always** wrap in a helper script under the project's scripts dir (e.g. `scripts/<op>.sh`) and invoke via `bash <abs-path>`.

## Allowlist coverage

Most operations covered by:
- `Bash(git -C * status:*)`, `Bash(git -C * log:*)`, `Bash(git -C * diff:*)` (read-only)
- `Bash(git -C * fetch:*)`, `Bash(git -C * pull --ff-only:*)`, `Bash(git -C * switch:*)`
- `Bash(gh pr:*)`, `Bash(gh pr comment * --body:*)`, `Bash(gh pr ready *)`, `Bash(gh api repos:*)`
- the force-push env wrapper, if the project uses one

If a new op hits the "Contains expansion" dialog → wrap it as a helper script.

## Reply protocol

- Operation success → terse: `<op>: <result>`
- Pre-flight fail → `<op> BLOCKED: <reason>`

## Related skills

- `pr-conflict-solver`: uses rebase + force-push-lease
- `code-review`: uses pr-comment-block
