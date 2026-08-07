#!/usr/bin/env node
/**
 * PreToolUse(Bash) — git commit/PR body heredoc guard.
 *
 * Heredoc-fed commit / PR body: `git commit <<EOF`, `git commit --amend -F -
 * <<EOF`, `gh pr create ... <<EOF`, or any `-m`/`--body` fed by a heredoc.
 * Distilled from a live incident: an `--amend` fed by heredoc SILENTLY kept
 * the OLD message — no error, no warning — so a required evidence line never
 * landed and a downstream push gate blocked on the stale HEAD. The only
 * signal was grepping the message afterwards. Fix: Write the body to a file,
 * then use a file flag: `git commit -F <file>` / `gh pr create --body-file <file>`.
 * Escape: ALLOW_HEREDOC_BODY=1.
 *
 * Scope note: commit+push bundling is deliberately NOT blocked here — a
 * non-blocking warning elsewhere can nudge a split, and the real harm (a
 * HEAD-reading gate seeing a stale HEAD) self-corrects by failing with its
 * own message. Only the heredoc case fails with NO other signal, so only it
 * earns a hard block.
 *
 * Narrow regex; anything unrecognized passes silently. Never throws — a
 * footgun guard must never block legit work on its own bug. Escape mirrors
 * other ALLOW_*-style env acks so an intentional case stays one keystroke.
 */
const fs = require('fs');

function exit0() { process.exit(0); }

let raw = '';
try { raw = fs.readFileSync(0, 'utf8'); } catch { exit0(); }

let cmd = '';
try { cmd = (JSON.parse(raw).tool_input || {}).command || ''; } catch { exit0(); }
if (!cmd) exit0();

function deny(reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  }));
  process.exit(0);
}

const isCommit = /\bgit\b[^\n]*\bcommit\b/.test(cmd);
const isGhBody = /\bgh\s+pr\s+(create|edit)\b/.test(cmd);
// Heredoc start token: <<EOF, <<-EOF, << 'EOF', <<"EOF", << EOF.
const hasHeredoc = /<<-?\s*['"]?[A-Za-z_]/.test(cmd);

if (hasHeredoc && (isCommit || isGhBody) && process.env.ALLOW_HEREDOC_BODY !== '1') {
  deny(
    'GIT BODY HEREDOC: feeding a commit/PR body via heredoc (<<EOF) has silently failed to ' +
    'apply in the past (an --amend kept the OLD message, dropping a required evidence line). ' +
    'Write the body to a file with the Write tool, then use a file flag: ' +
    '`git commit -F <file>` or `gh pr create --body-file <file>`. ' +
    'Override (logged): ALLOW_HEREDOC_BODY=1 <cmd>');
}

exit0();
