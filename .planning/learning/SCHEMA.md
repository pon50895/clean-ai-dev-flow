# Learning Persistence Schema

> Captures cross-session behavioral feedback (F-rule violations, brief errors,
> dispatch mistakes) so future agent sessions can avoid recurring patterns.
> File-based, plain JSON Lines, zero external dependencies.

## Files

| Path | Purpose | Retention |
|------|---------|-----------|
| `.planning/learning/violations.jsonl` | Active violations (last 30 days) | Active |
| `.planning/learning/violations-archive.jsonl` | Archived violations | Permanent |
| `.planning/learning/corrections.jsonl` | User-confirmed correct patterns | Permanent |

## Entry schema (violations.jsonl)

JSON Lines (1 entry per line). Required fields:

```json
{
  "id": "v-YYYY-MM-DD-NNN",
  "ts": "2026-05-08T10:30:00+0800",
  "session": "supervisor-9",
  "role": "supervisor | dispatcher | worker | reviewer | tester",
  "trigger_pattern": "concrete bash/code/text pattern that violated",
  "trigger_kind": "raw-bash-loop | inline-heredoc | source-env-chain | reverse-ask-framing | unverified-brief-assumption | dialog-cycle | ...",
  "violation_summary": "human-readable one-line",
  "user_correction_quote": "<verbatim user message that flagged it, if any>",
  "fix_applied": "what fix landed; pointer to commit/script/PR",
  "rule_reference": "CLAUDE.md §X | dev-rule/<file>.md | BASH_TOOL_GATE.md Example Y",
  "tags": ["F4.1", "bash-discipline", ...],
  "status": "active | resolved | archived",
  "applies_to_roles": ["supervisor", "dispatcher", "worker", "reviewer", "tester"]
}
```

## Producer / consumer

| Action | Producer | Consumer |
|--------|----------|----------|
| Capture violation | supervisor (any session) on user feedback OR self-detection | — |
| Archive cron | weekly script (move >30d entries) | — |
| Bootstrap inject | — | every role's bootstrap brief (top 10 entries with `applies_to_roles` match) |
| Manual review | user / supervisor | grep / cat / ripgrep |

## Skill verbs

```bash
# Capture (during user-correction tick)
bash scripts/skill.sh capture-violation <role> <kind> <description> \
    [--correction "<user quote>"] \
    [--fix "<what fix>"] \
    [--rule "<reference>"] \
    [--applies-to-roles "supervisor,dispatcher"]

# Inject into bootstrap (called at session start)
bash scripts/skill.sh inject-recent-violations <role> [n=10]
# Outputs markdown ready to paste into bootstrap brief

# Archive old entries (cron)
bash scripts/skill.sh archive-violations [--older-than 30d]
```

## Bootstrap inject contract

Every role bootstrap brief MUST end with:

```
## Recent violations to avoid (last 10)

<output of: bash scripts/skill.sh inject-recent-violations <role>>
```

CLAUDE.md §0 item 13 directs new sessions to load this on bootstrap.

## Why JSONL (not vector / DB)

- `git diff` works on it — review history readable
- `ripgrep` finds patterns instantly
- No server, no migration, no corruption risk
- Cross-machine portable (clone repo = have learnings)
- Per architecture principle "file-based first" (CLAUDE.md §8 Karpathy + this project's value vs ruflo)

Vector recall is a Phase B/C addition (Item 4 of 4-item roadmap), not needed here.

## Tags taxonomy

- `F1` `F2` `F3` `F4` `F4.1` `F5` — F-rule violations from session logs
- `R1`-`R11` — CLAUDE.md red-line violations
- `bash-discipline` — BASH_TOOL_GATE related
- `dispatch` — brief quality / dispatch routing
- `claude-self` — model behavior issue (Apology Loop, etc.)
- `dialog-cycle` — settings allowlist gap
- `architecture` — wrong assumption about codebase

---

*Author: supervisor-9 session 2026-05-08, Item 1 of post-launch refactor roadmap.*
