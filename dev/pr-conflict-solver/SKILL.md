---
name: pr-conflict-solver
description: Resolve PR merge conflicts via rebase or merge strategies. Detects squash-merge dupes (auto-skip) vs real conflicts (additive vs semantic). Use when gh pr view shows mergeable=CONFLICTING or user reports PR conflict. 觸發詞:「解 PR 衝突」「merge conflict」「PR 衝突了」「這個 PR 有衝突」「rebase 衝突」「mergeable CONFLICTING」「pr conflict」。
---

# pr-conflict-solver

Single-responsibility skill: resolve PR conflicts using safe rebase strategies.

Base branch and force-push switch: read the project's `kit.json` / CLAUDE.md. Snippets below use `main` as the base and `ALLOW_FORCE_PUSH=1` as the example env switch some pre-push hooks require; drop the prefix if the project has no such switch.

## When to invoke

- `gh pr view <N> --json mergeable --jq .mergeable` returns `CONFLICTING`
- User says "PR #N conflicted"

## Inputs

- `pr`: PR number (e.g. 152)
- `strategy` (optional): `rebase` (default) | `merge` | `auto-detect`

## Pre-flight checks (CRITICAL — anti-race: never rebase a branch someone else is actively working on)

1. Identify the worktree that owns the PR head branch:
   ```
   gh pr view <N> --json headRefName,headRefOid --jq '"\(.headRefName) \(.headRefOid[0:7])"'
   ```
2. Find worktree dir matching branch name (`git worktree list`)
3. **Check worktree status**:
   ```
   git -C <worktree> status --short
   ```
4. Decision:
   - **Clean (or only the hook manager's auto-generated files, e.g. `.husky/_/`)** → safe to rebase on this branch
   - **Modified business files / untracked** → STOP, tell the user that session must commit/stash first (parallel-dev anti-race rule in the project CLAUDE.md), retry later
5. Verify mergeable:
   ```
   gh pr view <N> --json mergeable --jq .mergeable
   ```

## Execution (squash-merge dupe — most common)

If conflict from squash-merge of overlapping PRs:
```
git -C <worktree> fetch origin
git -C <worktree> rebase origin/main
# Rebase auto-drops "previously applied" commits from squash; clean
git -C <worktree> log --oneline -5  # verify clean linear history
ALLOW_FORCE_PUSH=1 git -C <worktree> push --force-with-lease
gh pr view <N> --json mergeable --jq .mergeable  # confirm MERGEABLE
```

## Execution (real conflict — needs manual merge)

If `git rebase origin/main` stops with merge conflict:

1. Read each conflicted file (look for `<<<<<<< HEAD` markers)
2. Classify conflict:
   - **Additive (both sides add stuff, same intent)** → resolve by combining (low risk)
   - **Semantic (different code on both sides for same concern)** → STOP, ask user
3. Resolve via Edit tool (preserve both sides' new code, drop conflict markers)
4. `git -C <worktree> add <resolved-files>`
5. `GIT_EDITOR=true git -C <worktree> rebase --continue`
6. `ALLOW_FORCE_PUSH=1 git -C <worktree> push --force-with-lease`
7. Verify mergeable

## Execution (disjoint-history — GitHub CONFLICTING but `merge-tree` says CLEAN)

**Symptom:**
`gh pr view <N> --json mergeable` returns `CONFLICTING` / `DIRTY`, but a local
`git merge-tree --write-tree origin/main origin/<branch>` reports **no
conflict**. The two disagree because the branch has **no common ancestor**
with `origin/main` — its base was reparented to a different root (common when
the branch was authored in a workflow-agent worktree whose history diverged).

**Confirm it:**
```
git fetch origin
git merge-base origin/main origin/<branch>            # prints nothing / errors "no merge base"
git log origin/main..origin/<branch> --oneline        # shows the real fix commit PLUS
                                                       # many already-squash-merged dupes
```
A plain `git rebase origin/main` on this branch tries to replay 1000+ commits
(starting from "Initial commit") and conflicts on root files like README.md —
do **not** go down that path.

**Fix — cherry-pick the real commit(s) onto a fresh branch off current main:**
```
# isolated worktree so the dirty main working tree is untouched
git worktree add -f <scratch-dir>/wt-<N> origin/main
cd <scratch-dir>/wt-<N>
git switch -c fresh-<N>                                 # branch == current origin/main
git cherry-pick <real-fix-sha>                          # the 1-3 commits unique to the branch
# resolve any REAL content conflict here (additive/semantic rules above apply)
# verify: run the project's typecheck + the fix's own test (commands from kit.json)
ALLOW_FORCE_PUSH=1 git push origin fresh-<N>:<branch> \
  --force-with-lease=<branch>:<old-sha>                 # replace disjoint branch
cd <repo-root> && git worktree remove <scratch-dir>/wt-<N> --force
gh pr view <N> --json mergeable --jq .mergeable         # now MERGEABLE/CLEAN
```

**Notes:**
- Identify `<real-fix-sha>` as the commit(s) whose message matches the PR title;
  ignore the squash-merge dupes that `git log origin/main..branch` also lists.
- `git reset --hard` is denied by auto-mode / destructive-guard — use `git switch -c <new> origin/main`
  to position a fresh branch instead of resetting.
- Always isolate in a throwaway worktree; the primary main worktree often has
  untracked stray files that block `git switch` and `git rebase`.

## Branch-owner notification (anti-race)

After force-push success, tell the user (to relay to the session that owns the branch):
```
[NOTE <ts>] PR #<N> conflict resolved.
- Branch <branch> rebased on origin/main
- conflict type: additive / semantic
- new SHA: <sha>
- PR is now MERGEABLE, waiting for the user to merge
Before the next commit, run: git pull --ff-only (force-push rewrote history)
```

## Constraints

- Force-push is confirm-first (high-risk command per the project CLAUDE.md): state the branch + old/new SHA, wait for the user's explicit confirmation, then use `--force-with-lease`
- **NEVER** force-push without the project's force-push env switch if its pre-push hook requires one
- **NEVER** rebase on worktree with non-trivial WIP (anti-race)
- **STOP** for semantic conflicts (real code disagreement) — ask user
- Rebase and force-push on a PR branch are done by one session only: rebasing mid-work reorders the owner's commits

## Allowlist used

- `Bash(git -C * fetch *)`, `Bash(git -C * rebase *)`, `Bash(git -C * push --force-with-lease *)`
- the force-push env wrapper, if the project uses one
- Edit tool for manual conflict resolution

## Reply protocol

- Squash-dupe auto-resolved → reply: `PR #<N> rebased clean (squash-dupe), force-pushed, MERGEABLE`
- Additive conflict resolved → reply: `PR #<N> conflict resolved (additive), files: <list>, force-pushed, MERGEABLE` + notify branch owner
- Semantic conflict → reply: `PR #<N> SEMANTIC conflict, need user judgment on: <files>` + show diff hunks
- Owner WIP block → reply: `branch owner has WIP, asked to commit/stash, retry later`

## Related skills

- `git-gh-ops`: general git/gh wrappers

## Examples

User: "#152 conflicted"
→ pre-flight check the branch's worktree → real conflict (two shared config/route files) → both additive → resolve combining → confirm → force-push → MERGEABLE → notify

User: "#199 stuck PR conflict"
→ pre-flight the branch's worktree → STOP if WIP, otherwise rebase
