#!/usr/bin/env node
/**
 * agent-model-guard.js — PreToolUse(Agent) guard: deny subagent dispatch that
 * omits an explicit `model`.
 *
 * Why this exists:
 *   Omitting `model` on an Agent call makes the subagent inherit whatever
 *   model the current session happens to be running on. If the main session
 *   is on your most expensive tier, every subagent dispatch silently inherits
 *   that cost — for tasks (batch edits, searches, mechanical checks) that a
 *   cheaper tier handles fine. This is a purely mechanical check: it can't
 *   judge whether the chosen tier is *right* for the task, only that a tier
 *   was chosen deliberately. Tier selection guidance lives in
 *   dev-rule/MODEL_DISPATCH.md §1 — read it before dispatching.
 *
 * Behavior: deny (not ask) — bounces back to the model to fill in `model`
 * itself, zero user-facing prompts. A hook bug must never block dispatch, so
 * every failure mode falls through to exit 0.
 */
const fs = require('fs');
const path = require('path');

let raw = '';
try { raw = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }

let payload;
try { payload = JSON.parse(raw); } catch { process.exit(0); }

if (!payload || payload.tool_name !== 'Agent') process.exit(0);

const model = payload.tool_input && payload.tool_input.model;

if (model && typeof model === 'string' && model.trim() !== '') process.exit(0);

const reason =
  'agent-model-guard: this Agent call omitted `model` — the subagent would inherit ' +
  'whatever model the current session is running on, which may be far more expensive ' +
  'than the task needs.\n\n' +
  'Re-dispatch with an explicit `model` (see dev-rule/MODEL_DISPATCH.md §1 for tiers ' +
  'and when to use each):\n' +
  '- default for search/implementation/verification -> the mid-tier alias (e.g. "sonnet")\n' +
  '- batch mechanical edits -> the cheapest alias (e.g. "haiku")\n' +
  '- high-stakes design/review judgment -> do it yourself on the main line, or the top tier\n\n' +
  'Never fill this in from memory — confirm the actual alias/model-id your harness resolves ' +
  'against dev-rule/MODEL_DISPATCH.md §1 (it may be stale; update it if so).';

process.stdout.write(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    permissionDecision: 'deny',
    permissionDecisionReason: reason,
  },
}));

try {
  const ledger = path.join(__dirname, '..', '..', '.planning', 'learning', 'gate-fires.jsonl');
  fs.appendFileSync(ledger, JSON.stringify({
    ts: new Date().toISOString(),
    verdict: 'deny',
    why: 'agent model omitted',
    cmd: ('Agent(' + ((payload.tool_input && payload.tool_input.subagent_type) || '?') + '): ' + ((payload.tool_input && payload.tool_input.description) || '')).slice(0, 120),
  }) + '\n');
} catch { /* ledger failure must never block work */ }

process.exit(0);
