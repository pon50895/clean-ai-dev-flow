---
name: pr-conflict-solver
description: Resolve PR merge conflicts via rebase or merge strategies. Detects squash-merge dupes (auto-skip) vs real conflicts (additive vs semantic). Use when gh pr view shows mergeable=CONFLICTING or the user reports a PR conflict. Trigger words: "resolve PR conflict", "merge conflict", "this PR conflicts", "rebase conflict", "mergeable CONFLICTING", "pr conflict".
---

# pr-conflict-solver

Single-responsibility skill: resolve PR conflicts using safe rebase strategies.

## When to invoke

- `gh pr view <N> --json mergeable --jq .mergeable` returns `CONFLICTING`
- User says "PR #N conflicted"

## Inputs

- `pr`: PR number (e.g. 152)
- `strategy` (optional): `rebase` (default) | `merge` | `auto-detect`

## Pre-flight checks (critical — don't race a branch someone else is actively working on)

1. Identify the branch and its worktree from the PR head branch:
   ```
   gh pr view <N> --json headRefName,headRefOid --jq '"\(.headRefName) \(.headRefOid[0:7])"'
   ```
2. Find the worktree directory matching that branch name (if you use worktrees for isolation).
3. **Check the worktree's status**:
   ```
   git -C <worktree> status --short
   ```
4. Decision:
   - **Clean (or only auto-generated hook-manager files)** -> safe to rebase this branch
     yourself.
   - **Modified business files / untracked WIP** -> STOP. Whoever owns that branch needs to
     commit or stash first — don't rebase out from under someone's uncommitted work. Retry later.
5. Verify mergeable:
   ```
   gh pr view <N> --json mergeable --jq .mergeable
   ```

## Resolution (squash-merge dupe — the most common case)

If the conflict comes from a squash-merge of overlapping PRs:
```
git -C <worktree> fetch origin
git -C <worktree> rebase origin/main
# rebase auto-drops "already applied" commits from the squash; should come out clean
git -C <worktree> log --oneline -5  # verify a clean, linear history
git -C <worktree> push --force-with-lease
gh pr view <N> --json mergeable --jq .mergeable  # confirm MERGEABLE
```

## Resolution (real conflict — needs manual merge)

If `git rebase origin/main` stops on a real conflict:

1. Read each conflicted file (look for `<<<<<<< HEAD` markers).
2. Classify the conflict:
   - **Additive (both sides add different things, same intent)** -> resolve by combining
     (low risk, your own judgment is fine).
   - **Semantic (genuinely different code on both sides for the same concern)** -> STOP, ask
     the user.
3. Resolve via the Edit tool (preserve both sides' new code, drop the conflict markers).
4. `git -C <worktree> add <resolved-files>`
5. `GIT_EDITOR=true git -C <worktree> rebase --continue`
6. `git -C <worktree> push --force-with-lease`
7. Verify mergeable.

## Resolution (disjoint-history — GitHub says CONFLICTING but a merge-tree dry run says CLEAN)

**Symptom (a known trap):** `gh pr view <N> --json mergeable` returns `CONFLICTING`/`DIRTY`, but
a local `git merge-tree --write-tree origin/main origin/<branch>` reports **no conflict**. The
two disagree because the branch has **no common ancestor** with `origin/main` — its base got
reparented to a different root (common when a branch was authored in a workflow-agent worktree
whose history diverged from the rest of the repo).

**Confirm it:**
```
git fetch origin
git merge-base origin/main origin/<branch>            # prints nothing / errors "no merge base"
git log origin/main..origin/<branch> --oneline        # shows the real fix commit PLUS
                                                       # many already-squash-merged dupes
```
A plain `git rebase origin/main` on this branch would try to replay 1000+ commits (starting from
"Initial commit") and conflict on root files like README.md — do **not** go down that path.

**Fix — cherry-pick the real commit(s) onto a fresh branch off current main:**
```
# isolated worktree so a dirty primary working tree stays untouched
git worktree add -f .claude/worktrees/wt-<N> origin/main
cd .claude/worktrees/wt-<N>
git switch -c fresh-<N>                                 # branch == current origin/main
git cherry-pick <real-fix-sha>                          # the 1-3 commits unique to the branch
# resolve any REAL content conflict here (additive/semantic rules above apply)
tsc --noEmit                                             # verify compile
npx jest --config jest.config.unit.js <touched-spec>    # run the fix's own test
git push origin fresh-<N>:<branch> --force-with-lease=<branch>:<old-sha>  # replace disjoint branch
cd <repo-root> && git worktree remove .claude/worktrees/wt-<N> --force
gh pr view <N> --json mergeable --jq .mergeable         # now MERGEABLE/CLEAN
```

**Notes:**
- Identify `<real-fix-sha>` as the commit(s) whose message matches the PR title; ignore the
  squash-merge dupes that `git log origin/main..branch` also lists.
- A hard reset may be blocked by an auto-mode guard — use `git switch -c <new> origin/main` to
  position a fresh branch instead of resetting.
- Always isolate in a throwaway worktree; the primary worktree often has untracked stray files
  that block `git switch` and `git rebase`.

## Notifying whoever owns the branch

After a force-push, tell whoever's working on that branch: rebased on origin/main, conflict type
(additive/semantic), new SHA, PR is now mergeable and waiting on the user to merge, and that
they need `git pull --ff-only` before their next commit (history changed under them).

## Constraints

- **NEVER** force-push without `--force-with-lease`.
- **NEVER** rebase a branch with non-trivial WIP sitting in its worktree (see pre-flight above).
- **STOP** for semantic conflicts (real code disagreement) — ask the user.
- Whoever is actively working on a branch should not be the one running rebase/force-push on it
  themselves while this resolution is in progress — coordinate first.

## Reply protocol

- Squash-dupe auto-resolved -> reply: `PR #<N> rebased clean (squash-dupe), force-pushed, MERGEABLE`
- Additive conflict resolved -> reply: `PR #<N> conflict resolved (additive), files: <list>, force-pushed, MERGEABLE`
- Semantic conflict -> reply: `PR #<N> SEMANTIC conflict, need user judgment on: <files>` + show diff hunks
- Branch has WIP -> reply: `branch has WIP, notified owner to commit/stash, retry later`

## Related skills

- `code-review`: run this skill first if `code-review` finds mergeable=CONFLICTING

## Examples

User: "#152 conflicted"
-> pre-flight checks the branch's worktree -> real conflict found -> both sides additive ->
resolve by combining -> force-push -> MERGEABLE

User: "#199 is stuck with a PR conflict"
-> pre-flight the branch's worktree -> STOP if WIP found, otherwise rebase
