#!/usr/bin/env node
// karpathy-activate — SessionStart hook.
//
// A project's rules may declare these principles as default-on for every
// code change, but stating that in prose doesn't make it happen — nothing
// injects the principles, so it relies on the agent remembering to go read
// the relevant doc. This mirrors other SessionStart hooks in this repo: print
// the condensed ruleset to stdout, which the harness injects as session
// context. Full detail can live in a dedicated skill (e.g.
// karpathy-guidelines) — invoke it for non-trivial refactors.
//
// Keep this to condensed essence, not the full skill body — injecting a large
// block every session is itself the kind of bloat this discipline argues
// against. Upgrade path: if drift recurs, widen the text.

process.stdout.write(
  [
    'KARPATHY DEFAULT-ON — applies to every code write/edit/refactor this session:',
    '1. Think before coding — state assumptions; if multiple readings exist, surface them, do not pick silently; push back when a simpler path exists.',
    '2. Simplicity first — minimum code that solves it; nothing speculative; no abstraction for single-use code; if 200 lines could be 50, rewrite.',
    '3. Surgical changes — touch only what the request needs; do not "improve" adjacent code; match existing style; only remove orphans YOUR change created.',
    '4. Goal-driven — turn the task into a verifiable success criterion and loop until it holds.',
    'Trivial tasks: use judgment. Deep refactor: invoke the karpathy-guidelines skill (or equivalent) for full detail.',
  ].join('\n')
);
