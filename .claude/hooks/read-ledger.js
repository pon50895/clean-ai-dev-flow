#!/usr/bin/env node
/**
 * read-ledger.js — PostToolUse(Read) hook: keep a per-session ledger of
 * which files this session has actually read.
 *
 * Why this exists: a "required reading" routing table (e.g. §0.2-style rules
 * in your project's CLAUDE.md — touch UI code, read the UI standards doc;
 * touch payment code, read the compliance doc) is easy to state and easy to
 * ignore in practice, because nothing checks whether it actually happened.
 * This hook turns "did I read it" into a checkable fact so a companion
 * PreToolUse hook (required-reading-gate.js) can deny an Edit/Write when the
 * required doc genuinely was not read this session.
 *
 * Design:
 *   - The ledger is a per-session plain-text file, one absolute path per
 *     line, under os.tmpdir() (never committed, never shared across sessions).
 *   - It records paths only, not content — it answers "was this read", not
 *     "was it understood".
 *   - Fail-open: a malformed payload, missing field, or write failure is
 *     always exit 0 with no output, never blocking. A broken ledger should
 *     cost "one missing line", never "a blocked Read".
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
  if (!payload || payload.tool_name !== 'Read') process.exit(0);

  const sessionId = payload.session_id;
  const filePath = payload.tool_input && payload.tool_input.file_path;
  if (!sessionId || typeof sessionId !== 'string') process.exit(0);
  if (!filePath || typeof filePath !== 'string') process.exit(0);

  const ledgerPath = path.join(os.tmpdir(), `claude-read-ledger-${sessionId}.txt`);
  fs.appendFileSync(ledgerPath, filePath + '\n');
} catch { /* fail-open: ledger failure must never block work */ }

process.exit(0);
