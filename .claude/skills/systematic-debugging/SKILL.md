---
name: systematic-debugging
description: Structured debugging SOP — find the root cause before touching anything, don't guess. Four phases: root-cause investigation -> comparative analysis -> hypothesis testing -> fix. Complements a broader system-health-audit skill (breadth scan) with a fixed procedure for digging deep on a single bug. Trigger words: "debug", "find the root cause", "why is this broken", "systematic-debugging", or two-plus consecutive "I tried X, didn't work" signs of thrashing. Adapted from obra/superpowers' skill of the same name, wired into this project's codebase-memory / GSD / worktree flow.
---

# Systematic Debugging — find the root cause, don't guess

Core idea: **find the root cause before you fix anything. Patching the symptom is a failure
mode.** Guess-and-check isn't faster — it's slower, and it commonly introduces new bugs.
Adapted from obra/superpowers, wired into this project's own tooling.

## When to use

- A specific bug has you stuck, or you notice yourself "tried X, didn't work, trying Y" two or
  more times in a row (thrashing).
- A multi-component chain (client -> API -> engine/DB) and you don't know which layer is broken.
- Difference from a broader system-health audit: that kind of skill is a breadth scan ("is the
  system healthy overall"); this one is a depth dig ("why is this specific bug broken").

## When not to use

- A "reportedly broken" bug you haven't reproduced yet -> reproduce first (that's Phase 1 step
  2), don't fix based on imagination.
- A one-line typo / compile error the stack trace points straight at -> just fix it, no need for
  all four phases.

## Four phases (all mandatory; a red flag means restart from Phase 1)

### Phase 1 — Root-cause investigation (before touching anything)
1. **Read the error message word for word**: stack traces / line numbers / error codes often
   hand you the answer directly — don't skip past them.
2. **Get a stable repro -> converge it into a red-capable loop**: collapse the repro steps into
   **one command**, and it must have **actually been run and watched fail once** — paste the
   real output as evidence, not "it should fail." Four checks: can go red (asserts the specific
   symptom, not just "didn't crash"), deterministic (same input, same result every time),
   fast (seconds, so it actually gets run), agent-runnable (you can run it yourself, no need to
   ask the user to click through it manually). **Without this red command in hand, you're not
   allowed to move to the next step, let alone propose a fix hypothesis.**
3. **Minimize**: once it's red, shrink the repro to the smallest case that still reproduces it —
   strip anything unrelated to the symptom (steps/data/code paths) until removing anything more
   makes it stop failing. The minimized case is often the clue itself; skipping this step and
   writing a hypothesis anyway is still guessing.
4. **Check recent changes**: `git log -p -- <file>`, related PRs, dependency/config diffs. Most
   regressions surface here. (Also rule out running stale code — a classic docker bind-mount /
   stale-branch trap.)
5. **Instrument across layers**: for a multi-component system, add logs/breakpoints at every
   boundary to pin down which layer is broken — don't guess.
6. **Trace the data flow backward**: follow a bad value up the call chain to its source. Use
   your codebase-memory tool's path-tracing (from -> to) to get the whole path in one shot
   (including callback/JSX dynamic hops), which beats manual grep + read for accuracy.

### Phase 2 — Comparative analysis
- Find "working, similar code" elsewhere in the codebase (codebase-memory search/callers).
- Read the reference implementation in full (not skimmed), list **every** difference between
  working and broken.
- Nail down dependencies, config, and implicit assumptions.

### Phase 3 — Hypothesis and verification
- Write an explicit hypothesis: "I think the root cause is X, because Y."
- **Single-variable** minimal test: change exactly one variable at a time, check the result
  before moving on.
- If unsure, admit the knowledge gap (ask the user / check docs) — don't force a guess.

### Phase 4 — Fix
- **Write a failing test first** (a unit/E2E/assertion that reproduces the bug), then fix it.
- Make **one** change targeted at the root cause; verify the fix + confirm no regression (your
  project's test gate).
- Ship through an isolated worktree -> PR; the test goes in the same PR (a firm rule of this
  workflow).
- **Safety valve: the same issue failing to fix 3+ times means questioning the architecture** —
  that's a design problem, not an isolated bug. Stop and discuss with the user.

## Red flags (any of these -> back to Phase 1)

- Proposing a fix before you actually understand the problem.
- Changing multiple things at once.
- Skipping repro / evidence gathering.
- "Let's just try X and see if it helps" as a mindset.
- Every fix attempt makes a new problem surface elsewhere.

## Wrap-up

- Once fixed and verified, if this bug is the "will recur — behavioral/environmental" kind,
  log it to your violations/lessons ledger; if it's worth a hard enforcement boundary, hand it
  to your skillopt-equivalent skill to distill into a gate.
- No subjective commentary; state root cause and evidence as facts (`path:line` + repro steps +
  diff).

## Counter-examples

- Using "time pressure / looks simple / I'm pretty sure" as a reason to skip phases (none of
  these are valid reasons — the original skill this was adapted from calls this out explicitly).
- Changing code without reproducing first (you're fixing an imagined bug).
- Trying three fixes at once in one PR (can't tell which one worked, also violates atomic-PR
  discipline).
