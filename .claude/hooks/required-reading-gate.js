#!/usr/bin/env node
/**
 * required-reading-gate.js — PreToolUse(Edit|Write) hook: turn a
 * "context-triggered required reading" routing table into a machine gate.
 *
 * Why this exists: a routing table like "touch frontend UI code, read the UI
 * standards doc first; touch payment/compliance code, read the compliance
 * doc first" is easy to state in a project's rules doc and easy to skip in
 * practice — pure self-discipline doesn't hold up under a long session.
 * read-ledger.js (PostToolUse Read) already records "which files this
 * session actually read" as a checkable fact; this hook checks that ledger
 * before an Edit/Write: if a rule matches the target path but its required
 * doc isn't in the ledger, deny and ask for a Read first. Never bounces to
 * the user, never costs their time — it's a self-correcting loop for the
 * agent.
 *
 * Exception: editing the rule docs themselves (dev-rule/**, .claude/**,
 * .planning/**) is exempt — a rules file shouldn't be gated by its own rule.
 *
 * Ledger matching uses endsWith(), because Read may use an absolute path
 * while the rule table only has a relative suffix.
 *
 * Fail-open, always: missing ledger, malformed payload, any throw — fall
 * through silently (exit 0). This is a discipline nudge, not a security
 * boundary: better to miss a case than to block normal work.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

let raw = '';
try { raw = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }

let payload;
try { payload = JSON.parse(raw); } catch { process.exit(0); }

try {
  if (!payload || (payload.tool_name !== 'Edit' && payload.tool_name !== 'Write')) process.exit(0);

  const filePath = payload.tool_input && payload.tool_input.file_path;
  const sessionId = payload.session_id;
  if (!filePath || typeof filePath !== 'string') process.exit(0);
  if (!sessionId || typeof sessionId !== 'string') process.exit(0);

  // Normalize to forward-slash for cross-platform safety.
  const rawNorm = filePath.split(path.sep).join('/');

  // Agent worktrees typically live at <repo>/worktrees/<name>/ — strip that
  // prefix first, or every rule below silently stops firing for any edit
  // made inside a worktree (a real regression seen in practice: adjust the
  // pattern to match wherever your project actually places worktrees).
  const normPath = rawNorm.replace(/^.*\/worktrees\/[^/]+\//, '');

  // --- exception: editing the rule docs themselves is exempt -----------------
  const SELF_EXEMPT = /(^|\/)dev-rule\/|(^|\/)\.claude\/|(^|\/)\.planning\//;
  if (SELF_EXEMPT.test(normPath)) process.exit(0);

  // --- rule table --------------------------------------------------------------
  // Adjust paths/patterns to match your project's actual layout and docs.
  const RULES = [
    {
      name: 'UI',
      test: (p) => /(^|\/)src\/.*\.(tsx|jsx|css)$/.test(p),
      required: 'dev-rule/UI_VISUAL_STANDARDS.md',
      context: 'touching frontend UI',
    },
    {
      name: 'LEGAL',
      test: (p) => {
        const lower = p.toLowerCase();
        if (/payment|billing|consent/.test(lower)) return true;
        if (/(^|\/)packages\/shared-content\//.test(p) && /legal/.test(lower)) return true;
        return false;
      },
      required: 'dev-rule/LEGAL_COMPLIANCE.md',
      context: 'touching payment / compliance / consent flows',
    },
  ];

  const matched = RULES.filter((r) => r.test(normPath));
  if (matched.length === 0) process.exit(0);

  const ledgerPath = path.join(os.tmpdir(), `claude-read-ledger-${sessionId}.txt`);
  let ledgerLines = [];
  try {
    ledgerLines = fs.readFileSync(ledgerPath, 'utf8').split('\n').filter(Boolean);
  } catch {
    ledgerLines = []; // no ledger yet = nothing has been read this session
  }

  const hasRead = (requiredSuffix) => ledgerLines.some((line) => line.endsWith(requiredSuffix));

  const unread = matched.filter((r) => !hasRead(r.required));
  if (unread.length === 0) process.exit(0);

  const lines = unread
    .map((r) => `${r.context}: read ${r.required} first, then retry this edit.`)
    .join('\n');

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: `required-reading-gate:\n${lines}`,
    },
  }));
} catch { /* fail-open: gate failure must never block work */ }

process.exit(0);
