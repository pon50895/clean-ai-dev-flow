#!/usr/bin/env node
/**
 * PreToolUse hook: PR discipline checklist on `gh pr create`.
 *
 * Why this exists
 * ---------------
 * The same per-PR discipline (write tests, keep PRs atomic, no emoji) tends
 * to get re-litigated by hand every time — it is mechanical, diff-derivable,
 * and exactly what a hook can enforce so a human doesn't have to keep saying it.
 *
 * What it does
 * ------------
 * Reads the PreToolUse JSON payload on stdin. If tool_name is "Bash" and the
 * command is a `gh pr create` invocation, it diffs the current branch against
 * its base (origin/main, else main) and runs three heuristics:
 *
 *   1. CODE without TEST  — source changed but no test file changed.
 *   2. NON-ATOMIC — very large diff (file/line thresholds): likely >1 topic.
 *   3. EMOJI — an added (+) diff line contains emoji.
 *
 * If any fire it returns permissionDecision="ask" with the checklist as the
 * reason, so the human confirms once (or the agent fixes and re-runs — a clean
 * re-run falls through silently). Clean PRs produce NO output (fall-through,
 * exit 0): zero added friction.
 *
 * Path assumptions below (a top-level `src/` per package, tests under
 * `__tests__/`, `*.test.*`/`*.spec.*`, or a top-level `e2e/` dir) are common
 * defaults — adjust the regexes to match your repo's actual layout.
 *
 * Failure mode
 * ------------
 * Any parse / git error -> silent fall-through (exit 0). A hook bug must
 * never block PR creation; at worst the checklist is skipped this once.
 */

'use strict';

const fs = require('fs');
const { execSync } = require('child_process');

// --- read stdin payload --------------------------------------------------
let raw = '';
try { raw = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }

let payload;
try { payload = JSON.parse(raw); } catch { process.exit(0); }

if (!payload || payload.tool_name !== 'Bash') process.exit(0);

const cmd = (payload.tool_input && payload.tool_input.command) || '';
if (!cmd || typeof cmd !== 'string') process.exit(0);

// Only act on a real `gh pr create` (tolerate global flags: `gh --repo x pr create`).
const IS_PR_CREATE = /(^|[\s;&|(])gh\s+(?:--?\S+(?:\s+\S+)?\s+)*pr\s+create\b/;
if (!IS_PR_CREATE.test(cmd)) process.exit(0);

const projectDir = payload.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();

function git(args) {
  return execSync(`git ${args}`, {
    cwd: projectDir,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
    maxBuffer: 32 * 1024 * 1024,
  }).trim();
}

// --- resolve base ref ----------------------------------------------------
let base = null;
for (const ref of ['origin/main', 'main', 'origin/master', 'master']) {
  try { git(`rev-parse --verify --quiet ${ref}`); base = ref; break; } catch { /* try next */ }
}
if (!base) process.exit(0);

// --- collect changed files + patch --------------------------------------
let files = [];
let patch = '';
try {
  const out = git(`diff --name-only ${base}...HEAD`);
  files = out ? out.split('\n').filter(Boolean) : [];
  patch = git(`diff --unified=0 ${base}...HEAD`);
} catch {
  // merge-base form failed (e.g. unrelated histories) — fall back to two-dot.
  try {
    const out = git(`diff --name-only ${base} HEAD`);
    files = out ? out.split('\n').filter(Boolean) : [];
    patch = git(`diff --unified=0 ${base} HEAD`);
  } catch { process.exit(0); }
}

if (files.length === 0) process.exit(0); // nothing to check

// --- classifiers -----------------------------------------------------------
// Adjust these to your repo's actual test/source layout.
const isTest = (f) =>
  /(^|\/)__tests__\//.test(f) ||
  /\.(test|spec)\.[cm]?[jt]sx?$/.test(f) ||
  /(^|\/)e2e\//.test(f);

const isSource = (f) =>
  /(^|\/)src\/.*\.[cm]?[jt]sx?$/.test(f) &&
  !isTest(f);

// --- heuristics ----------------------------------------------------------
const warnings = [];

const sourceFiles = files.filter(isSource);
const testFiles = files.filter(isTest);
if (sourceFiles.length > 0 && testFiles.length === 0) {
  warnings.push(
    `No test/e2e changes, but ${sourceFiles.length} source file(s) changed. ` +
    `Confirm tests genuinely aren't needed, or add one.`,
  );
}

// Non-atomic: large diff. Count added/removed lines from the patch.
let addedLines = 0;
let removedLines = 0;
for (const line of patch.split('\n')) {
  if (line.startsWith('+') && !line.startsWith('+++')) addedLines++;
  else if (line.startsWith('-') && !line.startsWith('---')) removedLines++;
}
const FILE_CAP = 30;
const LINE_CAP = 1000;
if (files.length > FILE_CAP || addedLines + removedLines > LINE_CAP) {
  warnings.push(
    `Diff looks large (${files.length} files / +${addedLines} -${removedLines} lines). ` +
    `Confirm it's a single logical unit; split into atomic PRs if it mixes topics.`,
  );
}

// Emoji on added lines. Emoji-specific ranges; avoids matching CJK / arrows.
const EMOJI = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{2B00}-\u{2BFF}\u{1F1E6}-\u{1F1FF}\u{FE0F}\u{2705}\u{2714}\u{2728}\u{274C}\u{2764}]/u;
for (const line of patch.split('\n')) {
  if (line.startsWith('+') && !line.startsWith('+++') && EMOJI.test(line)) {
    warnings.push('Emoji detected on an added line (see dev-rule redline on emoji). Remove it.');
    break;
  }
}

if (warnings.length === 0) process.exit(0); // clean — no friction

const reason =
  'PR discipline checklist (gh pr create) — please confirm the items below, then approve:\n' +
  warnings.map((w, i) => `  ${i + 1}. ${w}`).join('\n') +
  '\n(This is a reminder, not a hard block. Fix and re-run gh pr create to auto-clear, or approve directly.)';

const out = {
  hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    permissionDecision: 'ask',
    permissionDecisionReason: reason,
  },
};
process.stdout.write(JSON.stringify(out));
process.exit(0);
