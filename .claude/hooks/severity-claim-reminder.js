#!/usr/bin/env node
/**
 * severity-claim-reminder.js — Stop hook reminder: does a severity claim have
 * measurable evidence behind it?
 *
 * Why this exists: it's easy to escalate language ("this is worse than X",
 * "this isn't a small bug", "this is effectively dead") off a thin signal —
 * e.g. a command that only returns an exit code, with no actual diff/count
 * behind the claim. Knowing the rule ("back up severity claims with numbers
 * or a file:line reference") isn't the same as having a checkpoint that
 * fires at the moment of writing the claim.
 *
 * Behavior: scans the last message in the main transcript; a narrow regex
 * matches severity-escalation phrasing. If it hits and the same message has
 * neither a number nor a file:line-style reference, inject a one-line
 * reminder.
 *
 * Hard constraint: this is a reminder, not a deny. Always exits 0, never
 * blocks anything. Fully try/catch'd — a hook failure must never affect
 * anything else.
 *
 * Known tradeoff (deliberately accepted, do not widen the regex): this will
 * false-positive on legitimate design-discussion sentences (e.g. "the
 * experience would be worse without this"). A hit only adds one reminder
 * line, it never denies — mechanizing semantic judgment into pattern
 * matching has misfired on legitimate sentences before; the fix is a
 * tighter pattern, not a wider one.
 */

const fs = require('fs');

const SEVERITY_PATTERNS = [
  /worse than\b/i,
  /not a (small|minor|trivial) bug/i,
  /effectively (dead|useless|broken)/i,
];

const HAS_NUMBER = /\d/;
const HAS_FILE_LINE_REF = /[^\s:]+[.:][a-zA-Z0-9_/.\-]*:\d+/;

function getLastAssistantMessageText(transcriptPath) {
  if (!transcriptPath || !fs.existsSync(transcriptPath)) return null;

  const lines = fs.readFileSync(transcriptPath, 'utf8').split('\n').filter(Boolean);

  for (let i = lines.length - 1; i >= 0; i -= 1) {
    let rec;
    try { rec = JSON.parse(lines[i]); } catch { continue; }

    if (rec.type === 'assistant' && rec.message) {
      const content = rec.message.content;
      if (typeof content === 'string') return content;
      if (Array.isArray(content)) {
        return content
          .filter((c) => c && c.type === 'text')
          .map((c) => c.text)
          .join('\n');
      }
    }
  }
  return null;
}

try {
  const payload = JSON.parse(fs.readFileSync(0, 'utf8'));
  const text = getLastAssistantMessageText(payload.transcript_path);

  if (typeof text === 'string' && text.length > 0) {
    const hit = SEVERITY_PATTERNS.some((re) => re.test(text));

    if (hit && !HAS_NUMBER.test(text) && !HAS_FILE_LINE_REF.test(text)) {
      process.stdout.write(
        'Reminder: this is a severity claim (worse than / not a small bug / effectively dead) ' +
        'without a comparable measurement attached. Add a number or a file:line reference, or ' +
        'mark it unverified.\n'
      );
    }
  }
} catch { /* reminder failure must never block work */ }

process.exit(0);
