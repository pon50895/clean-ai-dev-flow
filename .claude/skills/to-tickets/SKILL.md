---
name: to-tickets
description: Slice a plan / spec / discussion into tracer-bullet vertical-slice tickets, each explicitly declaring what "blocks" it (which tickets must land first), written to .planning/phases/<phase>/tickets/, ready to feed straight into feature-pipeline for parallel dispatch. Wide refactors go through expand-contract instead. Trigger words: "to tickets", "slice this up", "break into tickets", "split the work", "slice before dispatch", "vertical slice", "turn the plan into dispatchable tickets".
---

# to-tickets — slice a plan into tracer-bullet tickets

Adapted from mattpocock/skills' `to-tickets` (MIT license), wired into the gap between this
project's Plan stage and feature-pipeline dispatch. Single responsibility: slice a plan / spec
/ discussion into a set of **tickets** — tracer-bullet vertical slices, each declaring **which
other tickets block it**. This formalizes what would otherwise be ad-hoc judgment calls about
which tickets block each other and which can run in parallel across subagents.

## When to use

- After `to-spec` has written the plan doc, before feature-pipeline dispatch.
- A chunk of work needs to be split across multiple worktrees / subagents in parallel, and the
  dependencies and parallelizable boundaries need to be worked out first.

## Process

### 1. Gather context
Use whatever's already in the conversation; if the user shares a reference (spec path / PR /
issue), fetch and read it in full.

### 2. Explore the codebase (optional)
If you haven't already, use codebase-memory to understand the current state. Ticket titles /
descriptions use the domain's own glossary; respect existing ADRs in that area. Look for
**prefactor** opportunities: "make the change easy, then make the easy change."

### 3. Slice into vertical slices
Slice into **tracer bullet** tickets:

- Each slice cuts a **narrow but complete** path through every layer it touches (schema / API /
  UI / tests) — **vertical**, not a horizontal, single-layer slice.
- A completed slice can be **demoed / verified on its own**.
- Each slice is sized to **fit inside one fresh context window** (roughly, one subagent brief's
  worth of work).
- Do prefactors first.

Every ticket declares its **blockers** — which tickets must be finished before it can start.
Unblocked tickets can be dispatched immediately.

### 4. Wide-refactor exception = expand-contract
A **wide refactor** (renaming a field, retyping a shared symbol — a single mechanical change
with a blast radius across the whole repo, breaking thousands of call sites at once, with no
vertical slice that can land green on its own) does not get forced into tracer-bullet shape.
Sequence it as expand-contract instead:

- **expand**: add the new shape alongside the old one; nothing breaks.
- **migrate**: call sites move over in batches, sized by blast radius (per package / per
  directory), each batch one ticket blocked by expand, staying green throughout because the old
  shape is still there as a fallback.
- **contract**: once there are no callers left, delete the old shape — one ticket, blocked by
  all migrate batches.
- If even batches can't land green independently: keep the sequence, but have them share one
  integration branch, all blocking a single final integrate-and-verify ticket — green is only
  promised there.
- Use codebase-memory's change-impact tooling against a git diff to estimate blast radius and
  decide how to size the batches.

### 5. Quiz the user
Present the breakdown as a numbered list. For each ticket give: **title** / **blocked by**
(which tickets must finish first) / **what it delivers** (what end-to-end behavior starts
working). Ask the user: is the granularity right (too coarse / too fine)? Are the blocking
edges right (does each ticket depend only on what actually gates it)? Merge or split as needed.
Iterate until approved.

### 6. Write the tickets
Once approved, one file per ticket at `.planning/phases/<phase>/tickets/<NN>-<slug>.md`,
numbered in dependency order (blockers first, starting at `01`). The work **frontier** is
whichever tickets have all their blockers cleared; a purely linear chain runs top to bottom.
Don't modify or close any parent issue.

**Feed feature-pipeline**: unblocked tickets can be dispatched to different subagents /
worktrees in parallel simultaneously; blocking edges define the dispatch topology (who waits
on whom).

## Ticket template

```
# <NN> — <ticket title>

**What this builds:** what end-to-end behavior this ticket makes work, from the user's
perspective — not a layer-by-layer implementation checklist.
**Blocked by:** ticket number/title that gates this one, or "none — ready to start".
**Status:** ready

- [ ] acceptance criterion 1
- [ ] acceptance criterion 2
```

Don't include specific file paths / code snippets (they go stale fast). Exception: a snippet
produced by a prototype, more precise than prose (a state machine / schema / type shape) can be
inlined, noted as coming from a prototype — keep only the decision essence.

Full chain: `grill-me` / `grill-with-docs` (Discuss) -> `to-spec` (condense) ->
**`to-tickets` (slice)** -> feature-pipeline (parallel dispatch).
