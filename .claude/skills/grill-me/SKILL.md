---
name: grill-me
description: Pre-work "interrogation" — before writing any code / plan, ask one question at a time about requirements, decision branches, and the tradeoffs on each branch, until both sides agree on what to build and why. A structured tool for the Discuss stage of a Discuss/Plan/Execute/Verify loop; prevents starting work on assumed requirements. Trigger words: "grill me", "interrogate me", "help me nail down the requirements", "clarify before I start", "stress test this idea", "does this plan have holes", "Discuss stage".
---

# grill-me — pre-work interrogation

Adapted from mattpocock/skills' `grill-me` + `grilling` (MIT license), wired into this
project's Discuss stage. Single responsibility: before touching code, use a one-question-at-a-
time interview to pin down requirements and decisions. No code, no file edits — only questions.

## When to use

- Before Plan, on any "new feature / bugfix / refactor" (the Discuss stage).
- Requirements are vague, specs might contradict each other, or you're about to start work on
  an assumption — this is the guardrail against building on unverified assumptions.
- The user says "does this plan make sense / did I miss anything / help me think this through".

## Rules (follow all of them)

1. **One question at a time**, wait for the answer before the next one. Dumping a pile of
   questions at once makes it hard to answer any of them well.
2. **Walk the decision tree**: follow each branch of the decision downward, resolving
   dependencies between branches as you go. Ask upstream decisions first, then whatever they
   determine downstream.
3. **Every question comes with your recommended answer** — never ask a blank question. Say "I'd
   recommend X because Y, do you agree?" so the user can sign off or override with minimum effort.
4. **Look up facts yourself, only ask about decisions**: anything you can verify from the
   environment (files, codebase-memory, git, existing specs) — go check it, don't ask about it.
   Only **decisions** (tradeoffs, priorities, scope) go to the user.
5. **Don't touch anything until there's agreement**: no code, no PR, no file edits until the
   user confirms "we're aligned."

## What to ask about

- **Scope**: what's in scope this time, what's explicitly out? What can be cut as YAGNI?
- **Acceptance criteria**: what does "done" look like? Which test / which status code / which
  visual comparison proves it?
- **Existing conflicts**: do any specs contradict each other? Is this area already claimed by
  another in-flight workstream (check your handoff docs)?
- **Compliance / legal** (when touching public-facing copy, payments, or regulated claims):
  is the framing honest? Are you claiming a verification/review that hasn't actually happened?
- **Risky assumptions**: which single assumption, if wrong, makes the whole thing wasted work?
  Verify that one first.

## Wrap-up

Once there's agreement, produce a "consensus summary" (what's in scope / what's out / acceptance
criteria / decisions made) and hand it to the next step: writing it into your plan doc for the
Plan stage. When the work touches domain models / terminology / schema, use `grill-with-docs`
instead (interviews while writing terms and decisions into a doc as you go).
