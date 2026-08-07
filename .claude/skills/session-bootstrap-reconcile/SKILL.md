---
name: session-bootstrap-reconcile
description: When taking over a new session, reconcile what HANDOFF claims against the current repo / docker / PR reality, and list the drift (a stale db_lock, something marked RTM that already merged, a container that's down, etc.) so the next assistant doesn't decide based on stale documents. Trigger words: "take over", "bootstrap", "reconcile", "first step after handoff".
---

# Session Bootstrap Reconcile

Run this at the start of a new session (after bootstrapping your project rules doc) to
reconcile "what HANDOFF claims" against "what's actually true." The `handoff` skill is
responsible for **writing**; this skill is responsible for **reading + checking**.

## When to use

- Right after reading a STARTUP_PROMPT, to confirm reality
- Handoff was more than 24h ago, and you suspect HANDOFF content has gone stale
- The user mentions "the last session did X" and you want to verify it
- Lots of PRs / DB locks / background tasks are running at once and need reconciling

## When not to use

- Mid-conversation (already reconciled)
- Handoff was just written (content is guaranteed fresh)
- Pure informational Q&A that doesn't depend on reality

## Steps

### 1. Load the last one or two HANDOFF docs

```bash
ls -t .planning/HANDOFF/SESSION_HANDOFF_*.md | head -2
ls -t .planning/HANDOFF/STARTUP_PROMPT_*.md | head -1
```

Read the most recent SESSION_HANDOFF and its matching STARTUP_PROMPT.

### 2. Run a reality check (batch these calls)

```bash
git fetch origin --prune && git log origin/main --oneline -15
gh pr list --state open --json number,title,headRefName,mergeable
gh pr list --state merged --limit 30 --jq '.[] | select(.mergedAt > "<since>") | [.number, .title] | @tsv'
docker ps --format "{{.Names}}\t{{.Status}}" && curl -sf http://localhost/api/health
cat .planning/HANDOFF.json
```

`<since>` = the timestamp pulled from the HANDOFF doc's "Last revised:" line.

### 3. Diff matrix

Reconcile every claim the HANDOFF doc makes against reality:

| Type | HANDOFF says | Reality | Status |
|---|---|---|---|
| RTM PR | #1175 waiting on merge | `gh pr view` -> MERGED | **already merged, drop from the todo list** |
| In-progress branch | feat/some-feature in progress | `git branch -r` -> doesn't exist | **not carried into the new session, needs restarting** |
| db_lock | should be empty (unheld) | HANDOFF.json db_lock has a leftover from last session | **stale, needs clearing** |
| container | 8 healthy | `docker ps` -> 7 + 1 unhealthy | **one container is down, needs fixing** |
| background task | task-XYZ running | `TaskGet` -> already completed / doesn't exist | **stale, ignore** |

### 4. Report (short)

Give the user a short table:

```
| Source | Status |
|---|---|
| HANDOFF + STARTUP_PROMPT | complete / gaps |
| project rules doc set | read in full / items skipped |
| memory highlights | internalized / still pending |
| the one stale thing | <one concrete sentence> |
```

No orphans, no cross-session conflicts -> "no drift, taking over."
Drift found -> "N things need attention: 1. ... 2. ... 3. ..." + a proposed fix order.

## Writing discipline

- No emoji.
- **Don't repeat your project rules doc / dev-rule**: those are already auto-loaded for the
  next session.
- Only list **actual differences**, don't restate HANDOFF content.
- Keep it under 15 lines of table + 5 lines of bullets.

## Counter-examples

- Pasting the whole SESSION_HANDOFF back into the reply (wastes context).
- Trusting HANDOFF without running the reality check (stale information gets absorbed as fact).
- Reporting "everything's fine" without listing specific verification items (unauditable by
  the next session).
