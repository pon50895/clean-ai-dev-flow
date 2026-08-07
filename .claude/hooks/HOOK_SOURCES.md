# Hook source-of-truth table

Before editing any hook, check this table for where the live copy actually is.
Editing a dead copy is wasted effort.

| hook | live source | wired via | notes |
|---|---|---|---|
| all hooks in this directory | this repo `.claude/hooks/` | `.claude/settings.json` (and `.claude/settings.local.json` for personal overrides) | single copy, no drift, as of this writing |

If your setup grows a second layer (e.g. a user-global `~/.claude/settings.json`
that wires a hook of the same name to a different file, or a personal
`settings.local.json` override), add a row here documenting which copy is
live and which settings file wires it — that split is exactly what causes
"edited the dead copy, nothing changed" incidents.

Verify what's actually wired: `jq -r '[.hooks[]?[]?.hooks[]?.command]|.[]' <settings.json>`.
Check every settings file in play (project `settings.json` + `settings.local.json`,
and any user-global equivalents) to see which one is really wired.
