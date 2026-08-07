---
name: planning-archive-sweep
description: Periodically move stale SESSION_HANDOFF / STARTUP_PROMPT docs, completed phase directories, and one-off dated audits into a `.planning/archive/` subdirectory, so bootstrap doesn't load clutter and context doesn't get polluted by stale documents. Dry-run for the user before moving anything. Trigger words: "clean up .planning", "archive sweep", "archive", "clear out old handoffs".
---

# Planning Archive Sweep

Your project bootstrap loads a set of archive subdirectories (e.g. `.planning/archive/handoff/`),
but the actual moving-things-there tends to happen ad-hoc. This skill provides a consistent
sweep process.

## When to use

- Every 14 days / after finishing a phase
- `.planning/HANDOFF/` has accumulated more than 5 SESSION_HANDOFF docs
- User says "clean up .planning" / "archive" / "clear out old stuff"
- Before a handoff, when the user explicitly asks for a cleanup

## When not to use

- The handoff for a phase still in progress (never archive the current segment + the one before it)
- A phase doc still referenced by a WIP feature branch
- Docs already pushed in an open PR (archive after merge)

## Sweep rules

### A. `.planning/HANDOFF/`

| Action | Rule |
|---|---|
| Keep | the newest 2 `SESSION_HANDOFF_*` files + their matching `STARTUP_PROMPT_*` |
| Move to `.planning/archive/handoff/` | everything else |

### B. `.planning/HANDOFF.json`

| Action | Rule |
|---|---|
| Clear `db_lock` | if `acquired_at` is > 7 days old and there's no matching open PR/branch |
| Truncate `db_lock_history` | keep only the most recent 10 entries |
| Remove `completed_tasks` | if the phase has shipped (a matching PR is merged on main) |

### C. `.planning/phases/<phase>/`

| Phase status | Action |
|---|---|
| Marked Shipped/Completed in your project doc | move the whole directory to `.planning/archive/phases/` |
| Active (not done) | leave in place |
| A phase has PLAN / SUMMARY / VERIFICATION docs together | move them all together, don't split |

### D. One-off dated audits / lessons

| Path pattern | Action |
|---|---|
| `.planning/audit/<date>-*` | move to `.planning/archive/dated/` |
| `.planning/lessons/<date>-*` | same |
| any other `<component>-<date>-*` one-off doc | same |

### E. Leftover files

| Pattern | Action |
|---|---|
| `*.md.bak` / `*~` / `.DS_Store` | list them for the user — **the user deletes these themselves**, not you |
| git-untracked but matches an archive pattern | ask the user whether to commit first, then archive |

## Steps

### 1. Dry-run scan

```bash
ls -lt .planning/HANDOFF/SESSION_HANDOFF_*.md 2>&1
ls -lt .planning/HANDOFF/STARTUP_PROMPT_*.md 2>&1
jq '.db_lock, (.db_lock_history | length)' .planning/HANDOFF.json
ls .planning/phases/ 2>&1
find .planning/audit .planning/lessons -type f -name "*.md" 2>/dev/null | head -20
```

### 2. Proposal table

```
| Action | Path | Why |
|---|---|---|
| KEEP | .planning/HANDOFF/SESSION_HANDOFF_2026-06-01-PART1.md | most recent |
| ARCHIVE | .planning/HANDOFF/SESSION_HANDOFF_2026-05-30-PART2.md | older than the newest 2 |
| ARCHIVE | .planning/phases/some-shipped-phase/ | marked SHIPPED |
| CLEAR | HANDOFF.json db_lock | leftover from 2026-05-09, branch already merged |
| USER-ACT | .planning/audit/lessons.md.bak | .bak file, needs the user to rm it |
```

### 3. User confirms -> execute with git mv

```bash
mkdir -p .planning/archive/handoff .planning/archive/phases .planning/archive/dated
git mv .planning/HANDOFF/SESSION_HANDOFF_2026-05-XX-PART2.md .planning/archive/handoff/
git mv .planning/phases/<shipped-phase> .planning/archive/phases/
```

### 4. Clear HANDOFF.json (direct edit)

```javascript
// db_lock: {}
// db_lock_history: keep only .slice(-10)
```

### 5. Commit + push

```bash
git commit -m "chore(planning): archive sweep — N handoffs / M phase dirs"
# open a PR, or go straight to main for pure-archival docs changes if your project allows it
```

## Writing discipline

- No emoji.
- **Never `rm`**: archive with `git mv`; anything that needs deleting gets listed for the user.
- **Dry-run always comes first**: never `mv` anything without user confirmation.
- **Protect active branches**: if a feature branch references a phase doc (grep for it), warn
  the user before archiving.
- **Check cross-links**: if an archived doc has internal links, note any that break in the PR
  description.

## Counter-examples

- Moving an old handoff the moment you see it (the user might still be referencing it)
- Clearing `db_lock` without checking for a matching WIP branch first
- Moving hundreds of files in one PR (hard to review — split into batches under 20 files)
- Archiving an active phase's PLAN.md by mistake
