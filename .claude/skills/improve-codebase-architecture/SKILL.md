---
name: improve-codebase-architecture
description: Scan the codebase for "deepen this shallow module" opportunities (an interface that's as wide as its implementation, or a wrapper that barely holds anything), produce a ranked report, and dig into one candidate with a grill-style interview. Complements an over-engineering audit: that audit hunts complexity worth deleting; this one hunts interfaces worth deepening — but stays subordinate to deletion: delete first if you can, only deepen what you can't delete, and delete on a tie. Trigger words: "deepen the architecture", "shallow module", "improve architecture", "interface too wide", "deepen this module", "monthly architecture audit".
---

# improve-codebase-architecture — find shallow-module deepening opportunities

Adapted from mattpocock/skills' `improve-codebase-architecture` (MIT license). Goal: find
architectural friction and propose **deepening opportunities** — turning a shallow module (an
interface nearly as complex as its implementation, or a wrapper holding almost nothing) into a
deep one, improving testability and navigability.

## First: this is subordinate to deletion-first review (so the two don't fight)

"Deepen a module" means hiding a bigger implementation behind a smaller interface — that's
fundamentally adding abstraction, which can conflict with a deletion-first, YAGNI-driven review
pass. So this skill is **explicitly subordinate** to that kind of review:

- For every suspected shallow module, run a **deletion test** first: if you delete it, does
  complexity **converge**, or does it just **move somewhere else**?
  - "Converges" -> that's the signal: ask **can this just be deleted** first (deletion wins);
    only ask **can this be deepened** if it can't be deleted and deleting it would scatter
    complexity elsewhere.
  - "Just moves" -> not a good target, skip it.
- **Ties go to deletion**, never to adding abstraction. A single-implementation interface, a pure
  function extracted only for testability (where the real bug lives in how it's called, not in
  the function itself) — these are candidates for deletion/inlining, not deepening.
- This pairs with a monthly over-engineering audit: that one hunts "what to cut," this one hunts
  "shallow, poor-locality interfaces." When they conflict, deletion wins.

Read-only: produces a report only, doesn't change code (any actual change goes through your
normal plan-and-execute flow).

## Vocabulary

- Keep architecture vocabulary consistent: **module / interface / depth / seam (test seam) /
  adapter / leverage / locality**. Don't let it drift into "component / service / API /
  boundary."
- Domain terms use that domain's own glossary / source of truth; respect existing ADRs/specs
  rather than re-litigating decisions already made.

## Process

### 1. Explore (scope first — YAGNI)
Deepening only pays off for modules that will actually get touched again, so weight attention
toward areas that **change often**:

- If the user points at a specific area (a module / subsystem / pain point), use that directly,
  skip the inference below.
- Otherwise, walk `git log --oneline` history to find hot spots (files/areas that keep coming
  up), and let those draw the attention; if changes are too scattered with no clear hot spot,
  broaden the scope.

Read the domain glossary and ADRs for that area first. Then use codebase-memory
(architecture/hotspot views, path tracing) plus an Explore-style subagent if needed to walk the
codebase and **organically note where the friction is**:

- Does understanding one concept require bouncing between many small modules?
- Which modules are **shallow** — an interface nearly as complex as the implementation behind it?
- A pure function extracted purely for testability, but the real bug lives in how it's called
  (no locality)?
- Tightly-coupled modules leaking through their seam?
- Areas with no tests, or that are hard to test through the existing interface?

Run the deletion test (see above) on every suspected shallow module.

### 2. Produce a ranked report
Produce a **self-contained** report (an artifact or a scratchpad HTML file; **inline CSS, no
CDN dependencies** if your publishing target has a content-security policy — use native diagram
syntax or hand-drawn SVG for any diagrams, don't link external JS). One card per candidate:

- **Files** — which files/modules are involved
- **Problem** — why the current architecture causes friction
- **Fix** — plain-language description of the change (**lead with "can this just be deleted,"**
  then "if not, how would it get deepened")
- **Benefit** — described in terms of locality/leverage, how testing improves
- **Before/after** — a small side-by-side sketch of "shallow" vs. "deepened" (or "deleted")
- **Confidence** — a `strong` / `worth exploring` / `speculative` badge
- **Deletion-test result** — converges / just moves

End the report with a **top recommendation**: which one to do first, and why. Only bring up an
ADR conflict when the friction is significant enough to warrant reopening it, and flag it on the
card.

**Don't propose a specific interface design yet.** Once the report is written, ask the user
"which one do you want to dig into?"

### 3. Grill-style deep dive
Once the user picks a candidate, use `grill-me` (or `grill-with-docs` if it touches domain
models/terminology) to walk the decision tree: constraints, dependencies, the shape of the
deepened module, what's hidden behind the seam, which tests survive. Lock in decisions as
documentation as you go (terms -> the domain's glossary/source of truth; hard-to-reverse +
non-obvious + real-tradeoff decisions -> an ADR), matching `grill-with-docs`' modeling discipline.

## Wrap-up
The chosen deepening (or deletion) goes into your normal plan-and-dispatch flow. This skill
itself never changes code.
