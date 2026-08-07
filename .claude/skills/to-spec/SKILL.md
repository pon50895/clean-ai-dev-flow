---
name: to-spec
description: Synthesize already-discussed / grilled conclusions into a spec (problem statement + user stories + implementation decisions + test seams + scope) — no more interviewing, just condense into a written doc for the Plan stage. Sits between grill-me / grill-with-docs and writing the plan doc. Trigger words: "to spec", "condense into a spec", "write a spec", "turn the discussion into a PRD", "converge before Plan", "the interview's done, write the spec".
---

# to-spec — condense a discussion into a spec

Adapted from mattpocock/skills' `to-spec` (MIT license), wired into this project's Plan stage.
Single responsibility: **synthesize** what's already been agreed in conversation / a grill
session into a spec — **no more interviewing** (if there's still something to ask, go back to
`grill-me` / `grill-with-docs`). This fills the gap between "grill session converges -> the
conclusions are scattered across the conversation -> the plan doc gets freely reconstructed
from memory."

## When to use

- After `grill-me` / `grill-with-docs` (Discuss) has converged, before writing the plan doc
  (Plan).
- The requirements are already clear; what's missing is turning them into a structured,
  acceptance-testable, test-boundary-defined document.

## Rules

1. **No interviewing, only synthesis**: write from what you already know (the conversation +
   the codebase). Missing something? Go back and grill — don't ask mid-write in this step.
2. **Agree on the test seam first**: what gets tested isn't an afterthought bolted on at the end
   of Execute — pin it down here, with the user.

## Process

1. **Survey the current state**: use codebase-memory (`get_architecture` / `search_graph` /
   `get_code_snippet`) to understand the area you're about to touch; use the domain's own
   glossary / source-of-truth vocabulary throughout; respect existing ADRs / specs (your
   design-docs directory) rather than re-litigating decisions already made.
2. **Draw the test seam**: mark which layer this feature gets tested at. **Prefer an existing
   seam, the highest layer that will do the job, and as few seams as possible (ideally one).**
   If a new seam is needed, propose it at the highest point. **Confirm the seam matches
   expectations with the user before going further.**
3. **Write the spec from the template below**, into your plan doc (or that phase's SPEC file).

## Spec template

```
## Problem statement
The problem the user faces, described from the user's point of view.

## Solution
The solution to that problem, described from the user's point of view.

## User stories
A "long" numbered list. Each one:
1. As a <role>, I want <capability>, so that <benefit>
Cover every facet of the feature, err on the side of thorough.

## Implementation decisions
Which modules get built/changed, which interfaces are touched, technical clarifications,
architecture decisions, schema changes, API contracts, key interactions. Don't include
specific file paths or code snippets (they go stale fast). Exception: a snippet produced by
a prototype, more precise than prose (a state machine / reducer / schema / type shape) can be
inlined against the relevant decision, noted as coming from a prototype — keep only the
decision essence, not a runnable demo.

## Test decisions
What counts as a good test here (test external behavior, not implementation details), which
modules get tested, prior art (similar tests already in the codebase).

## Out of scope
Explicitly state what this spec does NOT cover.

## Notes
Anything else worth recording.
```

## Wrap-up

Once the spec lands in your plan doc, hand it to `to-tickets` to slice into tracer-bullet
tickets (feeding feature-pipeline for parallel dispatch), or go straight to Execute. Full
chain: `grill-me` / `grill-with-docs` (Discuss) -> `to-spec` (condense) -> `to-tickets` (slice)
-> feature-pipeline (dispatch).
