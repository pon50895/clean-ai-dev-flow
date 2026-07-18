# User Permission Grants — User → Supervisor Response Channel (TEMPLATE)

> Copy to `<project>/.planning/USER_PERMISSION_GRANTS.md` before first use.
>
> **Purpose**: User reply to entries in `USER_PERMISSION_QUEUE.md`. Append-only. Supervisor polls each tick.
>
> **Format**: `[QID-N] <GRANTED|DENIED|DEFER> reason="..." [optional: until="<date>"]`

## Grants log (append-only)

(empty — populated by user)

## Pre-authorization (sprint-level batch grants)

> User can pre-authorize entire categories for the current sprint. Supervisor reads this section first; if action falls within scope, no QID needed.

```
sprint: <sprint-name> (until <date>)
pre-auth:
  - category: stale-worktree-recycle, max: 5, condition: "PR merged + clean status + no sibling deps"
  - category: reviewer-restart, max: unlimited, condition: "ctx > 80% OR alarm-bypass"
  - category: dispatch-brief-edits, max: unlimited, condition: "additive only, no remove existing rules"
  - category: cron-cadence-tweaks, max: 2/day, condition: "stay 4-30 min range"
  - category: tmux-window-rm-empty, max: unlimited, condition: "0 panes OR all panes idle >2hr"
```

## Push-channel preferences

```
user_push_channel: TBD  # options: pushover, telegram, sms, email, none
push_quiet_hours: 22:00-09:00  # only urgent during these hours
push_urgent_threshold: launch-blocker | data-loss | security-incident
```
