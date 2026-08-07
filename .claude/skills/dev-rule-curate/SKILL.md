---
name: dev-rule-curate
description: Periodically review whether dev-rule/*.md still matches the current repo — (a) flag clauses that reference a phase/file that no longer exists (b) find clauses duplicated by a newer rule (c) pull discipline from recent feedback memory / violations.jsonl that hasn't landed in dev-rule yet. Dry-run the proposal for the user before changing anything. Trigger words: "curate dev-rule", "dev-rule curate", "backfill discipline", "dev-rule audit".
---

# Dev-Rule Curate

Your project rules doc's bootstrap loads the whole `dev-rule/*.md` set, but those files drift:
phases get renamed, files get refactored, discipline gets internalized into memory before
dev-rule catches up. This skill runs that audit after a milestone or every so often.

## When to use

- After finishing a milestone (a launch, or a batch of phases wrapping up)
- Bootstrap loading dev-rule surfaces a broken reference (e.g. a phase doc got archived but
  dev-rule still links it)
- More than 5 `feedback_*` memory entries have accumulated without a matching dev-rule clause
- User says "curate dev-rule" / "backfill discipline" / "dev-rule audit"

## When not to use

- Mid-phase (dev-rule changes would disrupt in-flight collaboration)
- You just want to add one rule -> Edit dev-rule/<file>.md directly, no need for a full sweep
- A new dev-rule doc doesn't have consensus yet (discuss first, curate after)

## Three kinds of action

### A. Prune

| Pattern | Action |
|---|---|
| dev-rule references phase X, but the project doc marks it Shipped/archived | Candidate: rewrite as historical reference, or move the whole section to `dev-rule/archive/` |
| dev-rule references file path Z, and `ls` shows it doesn't exist | Candidate: drop the link or update the path |
| Two dev-rule clauses describe the same thing (grep for repeated keywords) | Candidate: merge, keep the more specific one |
| A clause already superseded by a higher-level doc | Candidate: delete |

### B. Augment

| Source | What to extract |
|---|---|
| `.planning/learning/violations.jsonl`, last 30 entries | Same violation type recurring >= 3 times, with no matching dev-rule clause -> needs one |
| `memory/feedback_*.md`, last 14 days | Discipline with no dev-rule counterpart -> candidate for addition |
| Most recent SESSION_HANDOFF "discipline & backfill" section | Mentions a new feedback memory that dev-rule doesn't reflect yet -> backfill |

### C. Cross-link integrity

| Check | Action |
|---|---|
| `[[name]]`-style links inside `dev-rule/*.md` | grep memory + other dev-rule files to confirm the target exists |
| Cross-references between dev-rule docs ("see SECURITY_STANDARDS.md §R4") | Confirm the anchor/section still exists |
| Bootstrap order listed in your project rules doc vs. actual `dev-rule/*.md` files | Files may have been added or renamed |

## Steps

### 1. Scan

```bash
ls dev-rule/*.md dev-rule/archive/*.md 2>/dev/null
ls memory/feedback_*.md 2>/dev/null
tail -50 .planning/learning/violations.jsonl 2>/dev/null
ls -t .planning/HANDOFF/SESSION_HANDOFF_*.md | head -3
grep -nrE "Phase\s+[0-9]+|\.planning/phases/|\`[^\`]+\.(ts|tsx|md|json)\`" dev-rule/*.md
```

### 2. Three-color proposal

| Color | Action | Table columns |
|---|---|---|
| RED prune | delete / rewrite | dev-rule path + line + why |
| GREEN augment | add a section | source (memory / handoff) + proposed target (which doc, which section) |
| YELLOW integrity | fix a link | broken link + proposed fix (update path / archive link / delete) |

### 3. Adversarial self-check

Before proposing, ask yourself:
- Is this prune candidate referenced by an active feature branch? (`grep -r "<rule>" feat/* 2>/dev/null`)
- Does this augment candidate already exist somewhere else? (don't duplicate)
- Does this cross-link fix break existing readability?

### 4. User sign-off -> one PR

```bash
git switch -c chore/dev-rule-curate-<date>
# Edit dev-rule/*.md per the proposal
git commit -m "chore(dev-rule): curate — prune N / augment M / fix K cross-links"
git push -u origin HEAD
gh pr create --base main --fill
```

The PR body must include the three-color proposal table + the adversarial self-check
conclusion, so a reviewer can see everything on one page.

## Writing discipline

- No emoji.
- **Never delete an unconfirmed clause**: even if it looks stale, mark it RED + dry-run first,
  wait for sign-off.
- **Keep the "why" when archiving**: archive, don't delete — a clause might get relevant again;
  move it to `dev-rule/archive/`.
- **Never delete security/compliance content**: legal/security rules are conservative by
  default — only additions, never deletions.
- **No subjective commentary**: not "this looks unused" -> instead "the project doc marks
  phase X Shipped, this clause is stale."

## Counter-examples

- One PR touching > 30 rules (a reviewer can't audit that one by one)
- Pasting a whole memory feedback entry verbatim into dev-rule (memory is session discipline,
  dev-rule is repo discipline — different register)
- Deleting any red line (that's your rules doc's SSOT, out of scope for this skill)
- Opening a PR without a dry-run first (a reviewer can't see the intent behind the change)
