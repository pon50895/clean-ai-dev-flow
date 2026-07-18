# User Permission Queue — Async ASK Channel (TEMPLATE)

> Copy to `<project>/.planning/USER_PERMISSION_QUEUE.md` before first use.
>
> **Purpose**: supervisor 不再用 blocking dialog 問 user 權限。改寫 file 列入 queue, 繼續 monitoring loop。User 醒了 / 回來 review queue, 寫 grants 進 `USER_PERMISSION_GRANTS.md`。supervisor poll grants file 照辦。
>
> **Why**: 解 supervisor SPOF。當 supervisor 卡 dialog 等 user, fleet 全停。Async queue → supervisor 永遠不卡。

## Format (append-only)

```
[YYYY-MM-DD HH:MM TZ] [QID-N] action="<one-line action>"
  category: <PR-conflict | worktree-rm | tmux-rm | settings-edit | secret-rotate | other>
  risk: <low | medium | high | critical>
  rationale: <why I propose this>
  safe-default: <what I do if user doesn't respond by timeout>
  timeout: <30min | 2hr | overnight | block-until-answer>
  context: <link to relevant file / PR / INBOX entry>
  state: <PENDING | GRANTED | DENIED | TIMEOUT-DEFAULTED>
```

## Active queue (sorted oldest first)

(empty — populated by supervisor as needed)

---

## Process for supervisor (write side)

1. Need permission → append entry with QID-N (next sequential)
2. Set safe-default + timeout — NEVER permission-block on critical actions without safe-default
3. Continue work loop
4. Each tick: poll `USER_PERMISSION_GRANTS.md` for matching QID, apply decision
5. Each tick: check timeout — if elapsed AND state=PENDING, apply safe-default and update state=TIMEOUT-DEFAULTED
6. Log all decisions to COORDINATOR_LOG.md

## Process for user (read side)

1. Read this file when you wake up / check in
2. Edit `USER_PERMISSION_GRANTS.md` — append `[QID-N] GRANTED|DENIED reason="..."`
3. supervisor picks up next tick

## Categories needing async (vs blocking dialog)

| Category | Use async queue? | Rationale |
|---|---|---|
| PR conflict resolution | YES | Often blocked overnight; safe-default = wait, no harm |
| Worktree removal | YES | Reversible if needed; safe-default = don't remove |
| tmux non-empty pane rm | YES | Reversible; safe-default = leave alone |
| settings.json edits | YES | Cosmetic; safe-default = preserve current |
| Secret rotation | YES | Critical but not time-sensitive; safe-default = defer |
| DROP TABLE / git reset --hard | NO | Critical destructive; never auto-default; block until explicit |
| Production push --force | NO | Same |

## Push-channel escalation (Tier 3)

If `risk: critical` AND `timeout: block-until-answer` AND elapsed > 1 hr → write to `.planning/PUSH_NOTIFY_QUEUE.md` for external delivery (Pushover / Telegram / SMS — TBD plumbing). Never spam: max 1 push / 4 hr per user.
