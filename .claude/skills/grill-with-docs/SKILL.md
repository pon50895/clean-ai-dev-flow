---
name: grill-with-docs
description: Interrogation-style interview plus live domain modeling — one question at a time before starting work, while writing the terms, definitions, and hard-to-reverse decisions that come out of it directly into a doc (glossary / ADR). Use for designs that touch a domain model or terminology (business rules, pricing, payments, schema). Extends Discuss with a domain-terminology source of truth. Trigger words: "grill with docs", "interview while modeling", "clarify terminology", "domain model", "what does this term actually mean", "build a glossary", "this design touches schema / domain concepts".
---

# grill-with-docs — interrogate + build the domain model

Adapted from mattpocock/skills' `grill-with-docs` (= `grilling` + `domain-modeling`, MIT
license), wired into this project's Discuss stage and domain-terminology discipline. Single
responsibility: pin down requirements via interview before starting work, **while**
simultaneously writing the terms and decisions that come out of it into a doc — modeling as you
go, not passively reading an existing doc afterward.

Do the `grill-me` interview mechanics first (below), then layer modeling on top.

## When to use

- The design touches a **domain model / terminology / schema**: a pricing state machine, a
  business-rule engine, a DB schema change.
- A term is ambiguous in conversation (what does "tier", "credit", "window" actually mean here)
  and needs a definition that gets written down.
- Before a change that crosses service / API / DB boundaries (align with your architecture spec
  if you have one).

## Interview mechanics (same as grill-me)

1. One question at a time, wait for the answer before the next one.
2. Walk the decision tree, upstream before downstream, resolve dependencies between branches.
3. Every question comes with a recommended answer.
4. Look up facts yourself (codebase-memory / existing specs / code); only ask about decisions.
5. Don't touch code until there's agreement.

## Layered on top: model while you interview

- **Challenge and clarify language**: when the user's term conflicts with an existing glossary /
  spec, point it out on the spot; push a vague term toward a precise, canonical definition;
  stress-test the concept's boundaries with concrete edge cases.
- **Cross-check against code**: compare what's said out loud against the actual code
  (codebase-memory `search_graph` / `get_code_snippet`), and surface contradictions immediately
  ("you said X is allowed, but the code currently does Y"). For business-rule engines especially,
  trust the real output over comments.
- **Lock in decisions as documentation, in real time**:
  - Terms / definitions -> write into that domain's glossary / source of truth (wherever your
    project already keeps this — don't open a second, competing source).
  - Decisions that are **hard to reverse + non-obvious + involve a real tradeoff** -> open an
    ADR / decision record (in your design-docs directory or the relevant plan doc). If a
    decision doesn't meet all three conditions, skip the ADR — don't let documentation bloat.
- **Be lazy about creating docs**: only create a doc when there's something concrete to record;
  don't pre-build empty scaffolding (YAGNI).

## Wrap-up

Output: a consensus summary + the paths to whatever terminology definitions / ADRs got written.
Hand it to the Plan stage. For requirements clarification that doesn't touch the domain model,
the lighter `grill-me` is enough.
