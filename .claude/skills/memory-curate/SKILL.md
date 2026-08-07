---
name: memory-curate
description: Compress the user's auto-injected memory index (`~/.claude/projects/<project>/memory/MEMORY.md`) so it stays under its read-size limit (roughly 24.4KB). Retire closed-out entries, merge same-topic entries, trim verbose tails. Dry-run for the user before overwriting. Trigger words: "memory-curate", "compress memory", "MEMORY.md is too big", "clean up the memory index", "memory is near the limit".
---

# Memory Curate

`MEMORY.md` is an index auto-injected every session, with a read-size limit around 24.4KB. It
tends to grow toward that limit as a project goes on, and once injected content gets truncated,
a new session can't see early lessons anymore. This skill provides a consistent compression
process.

## Core ideas

- **MEMORY.md is a working-set cache, not an archive.** Its job is "index into topic files," not
  "hold every detail." Detail always lives in the linked topic file (`memory/*.md`); the index
  itself keeps only a title + a one-line hook.
- **Growth is a curation problem, not a capacity problem.** Regularly retiring closed-out
  entries — keeping the index bounded — is the real fix.
- **Trimming tails alone has limited effect.** In practice, purely trimming verbose sentence
  tails only reduces size by roughly 10%; the real headroom comes from retiring entire
  closed-out entries.
- **Escape hatch: split it.** If the index genuinely can't hold the live working set (too many
  entries still being referenced frequently), thin MEMORY.md down into a router pointing at
  domain sub-indexes (e.g. `memory/some-domain-index.md`), rather than continuing to cram
  everything into one file.

## When to use

1. **A hook threshold fires**: a PostToolUse hook or the harness warns that MEMORY.md is nearing
   its read limit.
2. **Handoff wrap-up check**: the `handoff` skill's wrap-up runs `wc -c MEMORY.md`, and it's over
   20KB.
3. **Monthly sweep**: pair it with your violations-log archival, an over-engineering audit, and
   `planning-archive-sweep` as a regular monthly pass.

## When not to use

- The index is currently under ~17KB and no hook has warned — no need to act proactively.
- A single entry is still being referenced frequently by recent sessions (not "closed out" yet),
  even if it's verbose — leave it, and change how it's compressed rather than deleting it.

## Steps

### 1. Back up

```bash
cp "$MEMORY_MD_PATH" "/tmp/MEMORY.md.bak-$(date +%Y%m%d%H%M%S)"
wc -c "$MEMORY_MD_PATH"
```

`$MEMORY_MD_PATH` is typically `~/.claude/projects/<project-slug>/memory/MEMORY.md`.

### 2. Inventory entries into three buckets

For each entry (each `- [title](link)` line), judge:

| Category | Criteria | Action |
|---|---|---|
| **Closed out** | shipped + stable for a while + not referenced/tripped over in the last 1-2 months | remove from the index, fold into a one-line mention in a bottom "closed out, not indexed" footer |
| **Same topic** | multiple entries describe different stages of the same thing ("PR-1 did X," "PR-2 did Y," "all done") | merge into one entry, keep only the latest state + accumulated points |
| **Still active** | still referenced recently, still an open workstream, or a frequently-hit gotcha | keep, but check for a trimmable tail (push detail back into the topic file, keep only the hook in the index) |

### 3. Write a dry-run proposal

Present a table to the user for confirmation, don't overwrite directly:

```
| Action | Entry | Why |
|---|---|---|
| ARCHIVE | project_xxx_2026_06_01 | shipped + verified in production + no references in 2 months |
| MERGE | project_yyy_pr1 + project_yyy_pr2 -> project_yyy | same topic, different stages, merge to latest state |
| TRIM | feedback_zzz | verbose tail, trim to one hook line, detail already lives in its topic file |
| KEEP | project_www | still actively referenced |
```

Also report current size and estimated size after compression.

### 4. Execute after user confirmation

- Use Edit for precise section replacement on MEMORY.md (never a full-file overwrite).
- **Only touch index lines, never delete the topic files themselves** (`memory/*.md` files stay,
  even if the index no longer links them — they're still retrievable by search later).
- Target: **under 17KB**, leaving headroom to the 24.4KB limit.

### 5. Verify

```bash
wc -c "$MEMORY_MD_PATH"
```

Confirm it's under the target, and that removed entries genuinely show up in the bottom footer
or got merged — not silently vanished.

## Safety rules

- Always back up before touching anything (to `/tmp` or a scratchpad, not git — the memory
  directory isn't necessarily a git repo).
- Always dry-run for the user before overwriting; never do it unilaterally.
- Never delete a topic file, only the index.
- Never use a force/skip-confirmation shortcut.

## Counter-examples

- Deleting an entry just because it's long, without checking whether it's still active (might
  cut a gotcha someone's currently dealing with).
- Cutting everything to the bone in one pass without showing the user a dry-run table first.
- Accidentally deleting a topic file itself (the index is just a pointer — the file has to stay).
- Only trimming tails without retiring closed-out entries (limited effect, doesn't fix the root
  cause).
