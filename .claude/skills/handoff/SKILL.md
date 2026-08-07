---
name: handoff
description: When ending a session / handing off / context is about to fill up, write a matching pair of documents — SESSION_HANDOFF_<YYYY-MM-DD>-PART<N>.md (what this segment delivered) + STARTUP_PROMPT_<YYYY-MM-DD>-PART<N+1>.md (the next segment's kickoff prompt) — so the next session doesn't have to reconstruct state from scratch. Trigger words: "handoff", "hand off", "wrap up the session".
---

# Handoff Skill

Writes a consistent pair of documents at session boundaries that the next session can load
straight into its bootstrap.

## Hard limits (MANDATORY — enforced when generating, not left to memory)

- **SESSION_HANDOFF <= 80 lines; STARTUP_PROMPT = roughly 100 words, one paragraph.** Short and
  effective beats long and complete — a long doc doesn't get fully read by the next session and
  actively causes drift. Handoff docs should get tighter and more effective each time, not
  longer.
- **"Effective" is defined as**: cut a line unless the next session would get something wrong
  without it. If it wouldn't, cut it. Details point to a PR number / spec path instead of being
  restated.
- **After writing each file, run `wc -l <file>` on it.** Over the limit -> **must cut**: push
  detail back to the PR / existing spec instead of repeating it in the handoff; merge same-topic
  items into one line; delete "complete for completeness's sake" sections. Only cut-to-under-
  limit content gets committed.
- **Logging violations/corrections to your learning ledger is a hard precondition of committing**
  the handoff (if your project keeps one). The producer side of any self-improvement loop is
  only as good as this discipline — log each mistake as it happens (30 seconds), and leave
  "turn it into a rule / add a gate" for a weekly review driven by recurrence data, not the
  night of the incident. The handoff's mandatory field is the backstop: if you notice at
  handoff-writing time that something wasn't logged, log it now.
- Prefer writing less and pointing at a PR number / spec path over writing long prose. The next
  assistant will `Read` those sources itself.

## When to use

- Context is at 70%+ and you're about to hand off
- A large wave / phase just wrapped up
- The user says "handoff" / "wrap up the session" / "let's hand off"
- All in-flight work is done and the state needs to be recorded for the future

## When not to use

- Fewer than 30 turns of conversation and nothing shipped
- Pure informational Q&A (no code touched, no PR opened)
- The user just says "summarize" / "recap" (that's a quick recap, not a handoff)

## Where the two output files go (always the primary worktree, regardless of which worktree you're running in)

**The next session boots from the primary worktree's cwd.** Every worktree has its own copy of
your planning directory; if the handoff gets written into the worktree you happened to be
running in, the next session boots at the primary worktree and can't find it — the handoff chain
breaks. **So resolve the primary worktree path first, and write both files there.**

```bash
# primary worktree = the first entry in `git worktree list` (the primary working tree),
# don't hardcode the path
MAIN_WT=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
```

| File | Path |
|---|---|
| This segment's delivery | `$MAIN_WT/.planning/HANDOFF/SESSION_HANDOFF_<YYYY-MM-DD>-PART<N>.md` |
| Next segment's kickoff prompt | `$MAIN_WT/.planning/HANDOFF/STARTUP_PROMPT_<YYYY-MM-DD>-PART<N+1>.md` |

Once both land in the primary worktree, the next session boots there and the STARTUP_PROMPT's
relative references (`.planning/HANDOFF/...`) resolve naturally — no need for absolute paths.

`<N>` = the Nth segment that day (1-based). `ls $MAIN_WT/.planning/HANDOFF/SESSION_HANDOFF_<YYYY-MM-DD>-*`
first to see how many segments already exist today, then continue from there.

## Reality checks to run before writing (batch these up front)

```bash
git fetch origin --prune 2>&1 | tail -3
git log origin/main --oneline -20
gh pr list --state open --json number,title,headRefName,mergeable
gh pr list --state merged --limit 30 --json number,title,mergedAt,headRefName  # what merged in the last 24h
cat .planning/audit/lint-baseline.json 2>/dev/null
cat .planning/audit/tsc-baseline.json 2>/dev/null
docker ps --format "table {{.Names}}\t{{.Status}}"
git status --short
# inventory any subagents that might still be alive (they can outlive /clear, don't assume "all done")
git worktree list                                    # WIP in an agent worktree = an agent may still be running
ps aux | grep -iE 'claude' | grep -v grep            # process count for this repo's cwd vs. what you think is running
```

Build this segment's reality from the output (don't rely on memory):
- Merged PRs (the ones the user merged directly this segment)
- PRs waiting on merge (opened by you, not yet merged by the user)
- **Any background agent still running (name each one individually + its worktree)** — see the
  hard rule below
- Environment (is the stack up, any uncommitted changes)
- Baseline numbers (lint / tsc / coverage deltas)

## SESSION_HANDOFF structure (8 fixed sections)

```markdown
# SESSION HANDOFF — YYYY-MM-DD PART<N>

> One paragraph: what this segment did, current state.

## Delivered this segment (merged)

Table / list: `#<PR>` title + one-line description + key metric (lines / coverage / hits).
Group by theme -> detail.

## Waiting on merge

| PR | Topic | Key points / risk |
|---|---|---|

## In flight

- Background task: `<task-id>`, what it's doing, expected duration, what happens on completion
- Background agent: **`<agent-name>` (name each one individually, not "an agent")**, what it's
  doing, which worktree
- Background workflow: `<wf-id>`, what it's doing

> **Hard rule on live subagents (prevents duplicate dispatch)**:
> subagents **can outlive `/clear`** — don't assume a handoff means they're terminated. So:
> 1. **When writing this section, name each agent + its worktree individually** (not "an agent
>    is running task B" but "`<agent-name>` is running task B in worktree `<worktree>`").
> 2. **The STARTUP_PROMPT must not say "if it terminated -> restart it."** Instead: "first
>    confirm whether `<agent-name>` is still alive (check its worktree for new commits/messages,
>    check `ps` for an extra claude process); if alive, don't re-dispatch — pick up its report
>    directly; only restart once you've confirmed it's actually dead."
> 3. Counter-example: a STARTUP_PROMPT once said "it terminated on handoff -> restart it," and
>    the next assistant dispatched a second agent into the **same worktree**, and the two agents
>    collided on the same batch of work. Root cause = assuming termination + not checking first.

## Baseline numbers (measured / changed this segment)

- Coverage: `client X% / server Y% / e2e Z`
- Lint: `<workspace> err/warn (delta)`
- Tsc: `<workspace> errors (delta)`
- Emoji scan: `hits (delta)`
- Bundle: `<metric> (delta)`

## Discipline & backfill (confirmed / updated this segment)

- **Violations logged (mandatory, don't skip)**: `v-<id>` x N — anything this segment got
  corrected on by the user, a reversed verdict, or a bad pattern hit, each needs a matching entry
  in your violations ledger. **"None" requires an explanation of why this segment made zero
  mistakes** — usually the truth is it wasn't logged, not that nothing went wrong.
- New rules the user set this segment
- Traps hit this segment + the countermeasure (written into memory or discipline docs)
- Existing discipline (per memory) that caused friction this segment

## Todo (next segment's priority order)

### Immediate
1. **<item>** — why / how to approach it / rough estimate
2. ...

### Medium-term
- ...

### User-only actions (only the user can do these)
- e.g. GitHub Settings -> Branches -> main -> required checks
- e.g. apply for a Sentry DSN
- e.g. enable a disabled workflow on a specific date

## Environment / state snapshot

- main: `<sha>` (after `#<PR>`)
- container state
- uncommitted / stray files

## Memory highlights (updated this segment)

- `<memory-name>` — what changed

*Last revised: YYYY-MM-DD PART<N> close — <one-line summary>.*
```

## STARTUP_PROMPT structure (**minimal — detail stays in the HANDOFF doc**)

Core principle: **don't repeat what's in the HANDOFF doc**. The next assistant will `Read` the
HANDOFF. The startup prompt only gives:
- How to bootstrap
- One sync command block
- 1-3 lines of most-urgent priority (pointing at the HANDOFF's todo section for detail)
- Path to pick up any background task

Template (**roughly 100 words, one paragraph** — don't use a multi-line template):

> Taking over as **team lead** on this project. **Two required reads, no exceptions: this
> STARTUP_PROMPT + the full text of `.planning/HANDOFF/SESSION_HANDOFF_<DATE>-PART<N>.md` — read
> both before doing anything (reading only STARTUP will miss things).** Run your project's
> bootstrap, git pull + a docker health check. Top priority: <1-2 items, a few words each>.
> **Team-lead mode: use your feature-pipeline-equivalent skill to self-drive, decide in-scope
> execution order yourself (only ask when scope is expanding); dispatch dev/verify subagents,
> collect the conclusions yourself.** **If the user hasn't specified what to do, start directly
> from the first "Immediate" item in the HANDOFF's todo section — don't ask which one to do.**
> Once you've read both, reply "read, taking over," and start the first item in that same
> message.

**The following three lines in the template above are mandatory** (carry them verbatim when
writing a STARTUP_PROMPT):
0. "**Two required reads, no exceptions: this STARTUP + the full SESSION_HANDOFF, both before
   doing anything**" (reading only STARTUP will miss things)
1. "in-scope execution order is decided by you, not asked about"
2. "no user instruction = start directly from the todo section's first 'Immediate' item, don't
   ask which one"

**Do not** write the opening as "first check what the user wants" / "if they haven't specified,
proceed in order" — that invites the next assistant to ask, and it will (this has happened in
practice: a prompt without this line grew the question on its own, and the next assistant asked
it). Discipline written as a side note doesn't land — it has to be **inside the text that gets
copied**.

**Team-lead mode**: whoever takes over is a team lead, not a solo contributor — default to
using your feature-pipeline-equivalent skill to push features to PR, decide in-scope calls
yourself, don't ask "which one first" step by step; only bounce back to the user on
scope-expanding or business/strategic tradeoffs. Dispatch + fresh-context verification + open
PR at RTM — the main thread only collects conclusions.

Self-check when writing it:
- Is the whole thing roughly 100 words, one paragraph? If not, push detail back to HANDOFF.
- Does it repeat HANDOFF content 1:1? If so, delete it.
- Is the first-step instruction block enough? (sync + check PRs + health check + background-task
  tail = 4-5 lines of bash)

## Writing discipline

- **No emoji** anywhere in the document (domain-specific glyphs your project already uses as
  content, if any, are the only exception).
- **Don't repeat** what's already in your project rules doc / dev-rule / architecture spec —
  the next session loads those automatically.
- **Only record session-specific reality**: what this segment did, current state, why it was
  done this way, how the next segment should pick up.
- **Tag every PR waiting on merge with its PR number + risk points** (especially force-pushes,
  baseline changes, or cross-workspace changes).
- **Be explicit about time**: use commit SHAs / PR numbers / timestamps, not vague words like
  "recently" or "earlier."
- **Reference PRs by number**: `#1074`, not "the vite fix."
- **Clear your task list after handoff** (don't leave stale tasks for the next segment).

## Housekeeping before writing the handoff (this session's responsibility, not the next
session's or the user's)

0. **Clean up background processes (stopping a task tracker isn't enough)**: stopping task
   tracking doesn't stop the underlying dev-server subprocess it spawned — those can become
   orphans that keep running (hogging ports, accumulating across sessions). Actually check for
   leftovers (`ps aux | grep -iE 'npm run dev|dev:server|vite' | grep -v grep`) — **don't claim
   "dev environment fully stopped" based on the tracker alone (that's false, and it'll poison
   the handoff)**. If something's still running -> **give the user a one-line heads-up that
   you're about to kill dev servers** (so a permission prompt doesn't surprise them), then kill
   the relevant ports/processes. Confirm zero leftovers in `ps` before calling it done.
1. **Reap merged worktrees**: run your worktree-cleanup script in dry-run mode first, confirm
   the list only contains worktrees for already-merged PRs, then apply. Only clean up merged
   ones; anything with WIP / an open PR / the primary worktree gets skipped. **Don't schedule
   this as an unattended cron job** (it risks deleting another session's WIP, and unattended
   persistence needs explicit authorization) — run it yourself at the end of every session.
2. **Put temp files where they belong**: any temporary/preview/one-off test file (a preview
   `.tsx`/`.html`, screenshots, scratch scripts) goes only in a **gitignored location** — inside
   an app, use a gitignored tmp dir if your project has one; for cross-cutting stuff, use a
   scratchpad. **Never scatter them in the source tree and `rm` them one by one afterward**
   (deletion commands are the user's call, and stray files trip destructive-action guards).
   Putting things where they belong is this session's job, not a cron job's.
3. **Prune local branches**: after a squash-merge, the branch SHA isn't on main, so a normal
   branch-delete refuses it as "not merged" — these pile up into hundreds. Periodically clean
   "local branches that intersect with your merged-PR list" (content is confirmed on main):
   `comm -12 <(git branch --format='%(refname:short)'|sort) <(gh pr list --state merged --limit 2000 --json headRefName -q '.[].headRefName'|sort) | xargs git branch -D`
   (use stdin redirection with BSD xargs, not `-a`). Only delete merged ones; a forced branch
   delete may trip a confirmation prompt (acceptable).
4. **Confirm the git tree is clean**: `git status --short` shouldn't show a stray untracked
   test/preview file — if it does, it wasn't put away properly (see step 2).
5. **Clear the task list** (see above).
6. **Check your memory index size**: if your project auto-injects a memory index file, check its
   size; if it's approaching its read limit, compress it before handing off a bloated index to
   the next segment.

## After writing (commit + push straight to main — this is a docs exception, not a code change)

**Handoff docs are docs, not code — commit + push directly to `main`, no PR.** This is an
explicit, narrow exception to the "no direct commits to main" rule, scoped only to handoff docs.
**Not pushing means it's just an untracked file in some worktree, and it'll get stranded** — a
handoff that never leaves a non-primary worktree means the primary worktree boots and can't find
it, misleading the next segment. Once it's pushed, `git show origin/main:.planning/HANDOFF/...`
can always retrieve it.

Sync + commit + update, all from the primary worktree (`$MAIN_WT`):

```bash
cd "$MAIN_WT"
git pull --ff-only origin main            # bring the primary worktree current (if local WIP blocks
                                           # a fast-forward, ask the user how to handle it — don't force)
git add "$MAIN_WT/.planning/HANDOFF/SESSION_HANDOFF_<DATE>-PART<N>.md" \
        "$MAIN_WT/.planning/HANDOFF/STARTUP_PROMPT_<DATE>-PART<N+1>.md"
# if your pre-commit/pre-push hooks block direct commits to main, use whatever narrow escape
# hatch your project defines for this documented handoff-docs exception (not a generic bypass).
# commit with `-- <pathspec>` so only the two handoff files land on main, not anything else staged.
git commit -m "docs(handoff): SESSION_HANDOFF + STARTUP_PROMPT for <DATE> PART<N>" \
        -- "$MAIN_WT/.planning/HANDOFF/SESSION_HANDOFF_<DATE>-PART<N>.md" \
           "$MAIN_WT/.planning/HANDOFF/STARTUP_PROMPT_<DATE>-PART<N+1>.md"
git push origin main    # straight to main, no PR
```

**Confirm it actually landed (mandatory, don't skip)**:

```bash
git cat-file -e origin/main:.planning/HANDOFF/STARTUP_PROMPT_<DATE>-PART<N+1>.md \
  && echo "landed" || echo "FAILED — not in git, push again"
git -C "$MAIN_WT" pull --ff-only origin main   # pull once more, confirm it's current
```

Not printing `landed` means the handoff isn't done. Give the user the startup prompt's path at
the end.

(Optional) update memory: if this segment produced any lasting behavioral discipline (something
the user corrected or set a rule about), write it into memory.

## Counter-examples (don't do these)

- Dumping the entire session's conversation into the HANDOFF (way too long, the next segment
  won't read it all).
- Listing PR numbers without the risk (the next segment finds out the hard way after merging).
- Writing "TODO: finish this up" — vague filler instead of a concrete next instruction.
- Using emoji to mark important points (violates the no-emoji rule).
- Assuming the next segment "should already know" something (it's a fresh conversation, it
  knows nothing).
- STARTUP_PROMPT opening with "first check what the user wants" / "if unspecified" — the next
  assistant will follow that script and ask. The todo sequence is already in the HANDOFF; just
  tell it to start.
- STARTUP_PROMPT saying "(some background agent) restart it if it terminated on handoff" —
  assumes termination; the next assistant will follow that and duplicate-dispatch into the same
  worktree. Write "confirm it's alive first, take over without re-dispatching if so" instead.
