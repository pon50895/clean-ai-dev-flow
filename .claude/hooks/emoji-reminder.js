#!/usr/bin/env node
// emoji-reminder -- Stop hook.
//
// Why: a "no emoji anywhere" red line typically includes "the reply itself",
// but a pre-commit content scan only covers committed files — it can't catch
// emoji in a conversational reply, because that's output-layer text that
// never gets written to a file. A Stop hook is the only place that can see
// the last reply. Mirrors the other Stop-hook reminders in this file set:
// scan the last message, reuse the same Unicode class this repo's
// PreToolUse content guard (redline-guard.js) already uses for consistency,
// inject a reminder on a hit.
//
// Hard constraint: reminder, not deny. Always exit 0, never block. Fully
// try/catch'd — a hook failure must never affect anything else.

const fs = require('fs');

// Keep this in sync with whatever Unicode class your PreToolUse content guard
// uses (e.g. redline-guard.js), so the two checks agree on what counts.
const EMOJI_RE = /\p{Emoji_Presentation}|\p{Emoji}\u{FE0F}|\u{20E3}/u;

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

  if (typeof text === 'string' && text.length > 0 && EMOJI_RE.test(text)) {
    process.stdout.write(
      'Reminder: the reply contains emoji. No-emoji applies everywhere (replies / code / ' +
      'comments / logs / commits / PRs) — use plain text instead.\n'
    );
  }
} catch { /* reminder failure must never block work */ }

process.exit(0);
