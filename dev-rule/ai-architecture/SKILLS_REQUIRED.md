# Skills Required (multi-agent setup)

> Claude Code skills that must be installed for the launch v1 multi-agent system to work fully.

## Required skills

### 1. karpathy-guidelines

**Purpose**: Used by REVIEWER (tmux:2 Sonnet 4.6) for every PR review. Implements Andrej Karpathy's 4 principles to catch over-engineering, scope creep, R7 violations.

**Source**: https://github.com/forrestchang/andrej-karpathy-skills

**Install** (user-level, applies to all sessions):

```bash
git clone https://github.com/forrestchang/andrej-karpathy-skills.git /tmp/karpathy-skills
mkdir -p ~/.claude/skills
cp -R /tmp/karpathy-skills/skills/karpathy-guidelines ~/.claude/skills/
ls ~/.claude/skills/karpathy-guidelines/SKILL.md  # verify
```

**Verify**: Open Claude Code, type `/` — `karpathy-guidelines` should appear in skills list.

**Used by**:
- REVIEWER (tmux:2) — invokes per PR review
- Coord may invoke during arbitration of edge-case reviews

## Optional skills (in use)

- **simplify** — manual code review trigger (orthogonal to reviewer auto-flow)
- **claude-api** — when working on Anthropic SDK integrations
- **schedule** / **loop** — task scheduling (used by sentinel, reviewer)
- **fewer-permission-prompts** — coord uses to add permission patterns to settings
- **update-config** — coord uses to modify settings.json

## Verify on new machine

```bash
ls ~/.claude/skills/
# Should include: karpathy-guidelines (and any others above)
```

If missing, reinstall per above. Without karpathy-guidelines, REVIEWER falls back to CLAUDE.md §8 inline references (less rigorous than the formal skill).
