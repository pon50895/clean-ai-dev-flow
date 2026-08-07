#!/usr/bin/env node
/**
 * over-ask-reminder.js — Stop hook reminder: did the last reply turn
 * in-scope work into a question thrown back at the user?
 *
 * Why this exists: deferring in-scope, judgment-free decisions (ordering,
 * re-verification, build steps, backlog-vs-now) back to the user as a
 * question is a recurring failure mode. The rule already lives in
 * dev-rule/AI_INSTRUCTIONS.md / core-contract-inject.js, but a rule stated at
 * session start doesn't catch it at the moment of output — that needs a
 * checkpoint at generation time, not just at read time.
 *
 * Behavior: scans the last message in the main transcript; a narrow regex
 * matches sentence patterns that turn an in-scope action into an offer
 * ("want me to... ?", "or should you...", "should I do X now or later") and
 * injects a one-line reminder when it hits.
 *
 * Hard constraint: this is a reminder, not a deny. Always exits 0, never
 * blocks anything. Fully try/catch'd — a hook failure must never affect
 * anything else.
 *
 * Known tradeoff (deliberately accepted, do not widen the regex): this will
 * false-positive on legitimate high-stakes/scope/business-tradeoff
 * questions. A hit only adds one reminder line, it never denies, so the
 * false-positive cost is acceptable; widening the pattern list is the wrong
 * direction — false positives on real judgment calls are worse than a missed
 * reminder.
 */

const fs = require('fs');

// Narrow patterns: first-person action framed as a question, or a "I do X vs
// you do X / do it now vs defer" binary. English variants of the same shape
// as the Chinese ones — extend per your team's actual language, don't widen
// the semantic net.
const OVER_ASK_PATTERNS = [
  /want me to\b.{0,40}\?/i,
  /should I\b.{0,40}\?/i,
  /or would you (rather|prefer)/i,
  /do you want me to/i,
  /(do it now|do this now|should I do this).{0,20}(or|vs\.?)\s+(later|backlog|defer)/i,
];

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
    const hit = OVER_ASK_PATTERNS.some((re) => re.test(text));

    if (hit) {
      process.stdout.write(
        'Reminder: this reply looks like it turned in-scope work into a question thrown back ' +
        'at the user (want me to... / should I... / do it now or later). The convention here: ' +
        'decide and execute ordering, re-verification, build steps, and backlog-vs-now calls ' +
        'yourself; stop when the requested scope is done, without expanding it further. Only ' +
        'stop to ask on genuine high-stakes actions, scope expansion, red lines, or business ' +
        'strategy.\n'
      );
    }
  }
} catch { /* reminder failure must never block work */ }

process.exit(0);
