#!/usr/bin/env node
/**
 * PreToolUse hook: auto-approve read-only Bash commands run against the
 * developer's working tree(s) on macOS / Linux. Covers two classes:
 *
 *   1. Read-only `git` invocations on any worktree under
 *      $CLAUDE_HOOK_GIT_PREFIX (default: $HOME/Desktop/).
 *   2. Trivial read-only POSIX no-ops used as fillers in chained commands:
 *      `echo`, `cat`, `:` (colon builtin), `true`, `false`, `printf`.
 *      `cat` is gated by a path allow-list + secret-file deny-list.
 *
 * Why this exists
 * ---------------
 * Claude Code's permission matcher is a literal-prefix string match. It does
 * NOT expand "**" globs and it evaluates a chained command (cmd1 && cmd2)
 * as a single string. Maintaining an allow list across N sibling worktrees
 * x M read-only git subcommands x &&-chained combinations was infeasible,
 * and even simple idioms like `git log <ref> 2>/dev/null || echo missing`
 * fell back to a prompt because `echo` segment had no `git` verb.
 *
 * What this hook does
 * -------------------
 * Reads the PreToolUse JSON payload on stdin. If tool_name is "Bash" and
 * EVERY segment of the command (split on &&, ||, ;) is one of:
 *   (a) a known read-only git invocation on cwd or under
 *       $CLAUDE_HOOK_GIT_PREFIX (default $HOME/Desktop/, via -C),
 *   (b) `echo ARGS...` / `printf ARGS...` (no redirection, no $()),
 *   (c) `cat PATH...` where every PATH is under an allow-listed root and
 *       does not match the secret-file deny-list,
 *   (d) `:`, `true`, or `false` no-op builtin,
 * then it emits a permissionDecision=allow JSON object on stdout.
 *
 * Anything not matching falls through (no output) and the standard
 * permission flow takes over: existing allow list, then user prompt.
 *
 * Hard rules (per CLAUDE.md sec. 1 R8 / sec. 2)
 * ---------------------------------------------
 *   - Destructive git subcommands NEVER approved here: push, pull, reset,
 *     clean, rm, commit, merge, rebase, cherry-pick, restore, checkout,
 *     stash pop/drop/clear/apply/save, branch -d/-D/-m, tag (create),
 *     remote add/remove/set-url, config --set/--unset/--add, gc, prune,
 *     repack, filter-branch, replace, update-ref, am, format-patch (write),
 *     mv, switch.
 *   - Sentinel flags reject the entire command regardless of subcommand:
 *     --no-verify, --force, -f (in destructive contexts), --hard, --soft,
 *     --keep, hooksPath= , -c core.hooksPath .
 *   - Stdout redirection (` > ` / ` >> `), command substitution (`$(...)`,
 *     backticks), and single pipes are vetoed at the sentinel layer; the
 *     stderr-to-/dev/null idiom `2>/dev/null` is NOT vetoed (the regex
 *     requires whitespace before `>`).
 *   - `cat` path restriction: every positional path must be under one of
 *     $HOME/Desktop/, $HOME/Documents/, /tmp/, /var/tmp/, or be a relative
 *     path that does not contain `..` and does not start with `/`. Paths
 *     matching the secret deny-list (.env*, *.pem, *.key, id_rsa*, *.crt,
 *     credentials*, secrets*, .aws/*, .ssh/*) are rejected even if otherwise
 *     in-scope.
 *   - git -C target must be under $CLAUDE_HOOK_GIT_PREFIX (default $HOME/Desktop/).
 *
 * Failure mode
 * ------------
 * Any parser error or unexpected input causes silent fall-through (no JSON
 * emitted, exit 0). User is never blocked by a hook bug; at worst they see
 * the original prompt.
 */

'use strict';

const fs = require('fs');
const os = require('os');

// -----------------------------------------------------------------------------
// Read stdin
// -----------------------------------------------------------------------------
let raw = '';
try {
  raw = fs.readFileSync(0, 'utf8');
} catch {
  process.exit(0);
}

let payload;
try {
  payload = JSON.parse(raw);
} catch {
  process.exit(0);
}

if (!payload || payload.tool_name !== 'Bash') {
  process.exit(0);
}

const cmd = (payload.tool_input && payload.tool_input.command) || '';
if (!cmd || typeof cmd !== 'string') {
  process.exit(0);
}

// -----------------------------------------------------------------------------
// Sentinel flags: presence anywhere in the command vetoes approval
// -----------------------------------------------------------------------------
const SENTINEL_VETO = [
  /(^|\s)--no-verify(\s|$)/,
  /(^|\s)--force(\s|$)/,
  /(^|\s)-f(\s|$)/,         // -f means force in nearly every git destructive ctx
  /(^|\s)--hard(\s|$)/,
  /(^|\s)--soft(\s|$)/,
  /(^|\s)--mixed(\s|$)/,
  /(^|\s)hooksPath\s*=/,
  /(^|\s)-c\s+core\.hooksPath/,
  /(^|\s)>\s*/,             // any redirection -> not pure read
  /(^|\s)>>\s*/,
  /\$\(/,                   // command substitution -> can't statically prove safe
  /`[^`]/,                  // backtick command substitution
];

for (const pat of SENTINEL_VETO) {
  if (pat.test(cmd)) {
    process.exit(0);
  }
}

// -----------------------------------------------------------------------------
// Allowed read-only subcommand grammar
// -----------------------------------------------------------------------------
// Auto-approve only git operations under this prefix. Override via env var
// CLAUDE_HOOK_GIT_PREFIX (must end with "/"). Falls back to ~/Desktop/.
const DESKTOP_PREFIX = process.env.CLAUDE_HOOK_GIT_PREFIX || `${os.homedir()}/Desktop/`;

// Plain read-only verbs: anything after the verb is fine (--stat, paths, refs).
// Excludes verbs that have read-only AND write modes (branch, stash, config,
// remote, tag, fetch, worktree, gc-related); those are gated below.
const PLAIN_READONLY = new Set([
  'status',
  'log',
  'diff',
  'show',
  'rev-parse',
  'rev-list',
  'ls-files',
  'ls-tree',
  'reflog',
  'blame',
  'describe',
  'cat-file',
  'merge-base',
  'name-rev',
  'for-each-ref',
  'symbolic-ref',
  'check-ignore',
  'check-attr',
  'whatchanged',
  'shortlog',
  'count-objects',
  'verify-commit',
  'verify-tag',
  'show-ref',
  'show-branch',
  'help',
  'version',
  'grep',
  'annotate',
  'fsck',          // diagnostic, no writes
]);

// Subcommand-specific gates
function gateBranch(args) {
  // Allow only listing forms. Reject -d/-D/-m/-M/-c/-C/--unset-upstream/--set-upstream.
  // Allow no-arg, or args that begin with a flag in the safe set.
  const SAFE_BRANCH_FLAGS = new Set([
    '-a', '--all',
    '-r', '--remotes',
    '-v', '-vv', '--verbose',
    '-l', '--list',
    '--contains',
    '--no-contains',
    '--merged',
    '--no-merged',
    '--show-current',
    '--points-at',
    '--column',
    '--no-column',
    '--sort',
    '--format',
    '--color',
    '--no-color',
    '-i', '--ignore-case',
    '--track', // read-only when listing? actually this writes upstream config -> reject
  ]);
  // Reject --track explicitly (writes config)
  if (args.some(a => a === '--track' || a === '--no-track' || a === '--set-upstream-to' || a === '--unset-upstream' || /^--set-upstream-to=/.test(a))) {
    return false;
  }
  // Reject any -d/-D/-m/-M/-c/-C
  if (args.some(a => /^-[dDmMcC]$/.test(a) || a === '--delete' || a === '--move' || a === '--copy' || a === '--edit-description')) {
    return false;
  }
  // If first non-flag is a name without a recognized listing flag, it's a creation -> reject.
  // Simplest safe rule: every arg must be a flag (starts with -) OR be a value following a known
  // listing flag like --contains/--merged/--points-at/--sort/--format/--color.
  const FLAGS_WITH_VALUE = new Set(['--contains', '--no-contains', '--merged', '--no-merged', '--points-at', '--sort', '--format', '--color', '--column']);
  let i = 0;
  while (i < args.length) {
    const a = args[i];
    if (a.startsWith('-')) {
      // value-taking flag with =VALUE form
      if (a.includes('=')) { i++; continue; }
      // flag that consumes next arg
      if (FLAGS_WITH_VALUE.has(a)) { i += 2; continue; }
      // bare flag — must be in safe set
      if (!SAFE_BRANCH_FLAGS.has(a)) return false;
      i++;
    } else {
      // bare positional argument: only allowed as a value for the previous flag,
      // which we already advanced past. So a bare arg here means branch creation/rename.
      return false;
    }
  }
  return true;
}

function gateStash(args) {
  // Only `stash list`, `stash show ...`. Reject pop/drop/clear/apply/save/push/create/store.
  if (args.length === 0) return false; // bare `git stash` = stash push
  const sub = args[0];
  return sub === 'list' || sub === 'show';
}

function gateWorktree(args) {
  // Only `worktree list`. Reject add/remove/move/lock/unlock/prune/repair.
  return args.length >= 1 && args[0] === 'list';
}

function gateConfig(args) {
  // Only --get/--get-all/--get-regexp/--list/-l. Reject --set/--add/--unset/--replace-all/--rename-section/--remove-section/--edit/-e.
  if (args.length === 0) return false;
  const READ_FLAGS = new Set(['--get', '--get-all', '--get-regexp', '--get-urlmatch', '--list', '-l', '--show-origin', '--show-scope', '--name-only']);
  for (const a of args) {
    if (a.startsWith('-') && !READ_FLAGS.has(a) && !a.startsWith('--global') && !a.startsWith('--local') && !a.startsWith('--system') && !a.startsWith('--worktree') && !a.startsWith('--file=')) {
      // Unknown or write flag
      if (a === '--set' || a === '--add' || a === '--unset' || a === '--unset-all' || a === '--replace-all' || a === '--rename-section' || a === '--remove-section' || a === '--edit' || a === '-e') {
        return false;
      }
      return false;
    }
  }
  // Must contain at least one read flag (otherwise it's a positional set: `git config foo.bar value`)
  return args.some(a => READ_FLAGS.has(a));
}

function gateRemote(args) {
  // Only `remote`, `remote -v`, `remote get-url ...`, `remote show ...`.
  if (args.length === 0) return true;
  const sub = args[0];
  if (sub === '-v' || sub === '--verbose') return true;
  if (sub === 'get-url' || sub === 'show') return true;
  return false;
}

function gateTag(args) {
  // Only `tag`, `tag -l`, `tag --list`, `tag -n...`. Reject creation (positional name) and -d/-v.
  if (args.length === 0) return true;
  // Reject -d/-D/-v/--verify (verify-tag exists separately) and bare creation
  if (args.some(a => a === '-d' || a === '--delete' || a === '-s' || a === '-a' || a === '--sign' || a === '-u' || a === '-f' || a === '--force' || a === '-m' || a === '-F' || a === '--cleanup')) {
    return false;
  }
  // Allow -l/--list and -n[NUM] and --contains/--points-at and --sort/--format/--color
  const SAFE_TAG_FLAGS = /^(-l|--list|-n\d*|--contains|--no-contains|--points-at|--merged|--no-merged|--sort|--format|--color|--no-color|--column|--no-column|--ignore-case|-i)$/;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a.startsWith('-')) {
      if (!SAFE_TAG_FLAGS.test(a) && !a.startsWith('--sort=') && !a.startsWith('--format=') && !a.startsWith('--color=')) {
        return false;
      }
    } else {
      // positional pattern argument (for -l) — allowed only if a listing flag is present
      const hasListing = args.some(x => x === '-l' || x === '--list' || /^-n\d*$/.test(x));
      if (!hasListing) return false;
    }
  }
  return true;
}

function gateFetch(args) {
  // git fetch is network read-only against remote, writes only refs/remotes/* and FETCH_HEAD.
  // It is safe across sibling worktrees. Reject --prune-tags? No, prune is fine for read-modeling.
  // But reject + force-style refspec: --force is already vetoed by SENTINEL_VETO.
  // Reject --recurse-submodules=on-demand? still fine.
  // Reject --write-fetch-head? default true, leave it.
  return true;
}

function gatePull() {
  // git pull = fetch + merge -> NOT read-only.
  return false;
}

const SUBCOMMAND_GATES = {
  branch: gateBranch,
  stash: gateStash,
  worktree: gateWorktree,
  config: gateConfig,
  remote: gateRemote,
  tag: gateTag,
  fetch: gateFetch,
  pull: gatePull,
};

// Verbs that are unconditionally write/destructive
const WRITE_VERBS = new Set([
  'push', 'pull', 'reset', 'clean', 'rm', 'commit', 'merge', 'rebase',
  'cherry-pick', 'revert', 'restore', 'checkout', 'switch', 'apply',
  'am', 'mv', 'add', 'init', 'clone', 'gc', 'prune', 'repack', 'pack-objects',
  'filter-branch', 'filter-repo', 'replace', 'update-ref', 'update-index',
  'symbolic-ref', // wait this can read... actually symbolic-ref HEAD is read-only
  'format-patch', 'send-email', 'request-pull', 'bisect', 'notes',
  'stripspace', 'mktag', 'mktree', 'hash-object', 'unpack-objects',
  'maintenance', 'commit-tree', 'write-tree', 'archive',
]);
// Note: archive writes a tarball but only to stdout/file -> we already vetoed redirection;
// it doesn't mutate the repo, but we still reject because user might pipe to /tmp.
// symbolic-ref read mode is in PLAIN_READONLY; remove from WRITE_VERBS.
WRITE_VERBS.delete('symbolic-ref');

// -----------------------------------------------------------------------------
// Non-git read-only verbs
// -----------------------------------------------------------------------------

// Roots under which `cat` is allowed to read. Anything outside these AND
// containing a leading "/" is rejected. Relative paths (no leading "/")
// are allowed if they do not contain ".." segments.
const CAT_ABSOLUTE_ALLOW_PREFIXES = [
  `${os.homedir()}/Desktop/`,
  `${os.homedir()}/Documents/`,
  '/tmp/',
  '/var/tmp/',
];

// Files whose name strongly suggests secret material. Rejected even if the
// containing directory is in scope. Matched against basename and full path.
const CAT_SECRET_PATTERNS = [
  /(^|\/)\.env(\.|$)/i,         // .env, .env.local, .env.production
  /(^|\/)\.env$/i,
  /\.pem$/i,
  /\.key$/i,                    // *.key (not "key" alone — covered by no-extension reject)
  /\.crt$/i,
  /\.cer$/i,
  /\.p12$/i,
  /\.pfx$/i,
  /\.jks$/i,
  /(^|\/)id_rsa($|\.)/,
  /(^|\/)id_ed25519($|\.)/,
  /(^|\/)id_ecdsa($|\.)/,
  /(^|\/)id_dsa($|\.)/,
  /(^|\/)credentials(\.|$)/i,   // credentials, credentials.json, credentials.yml
  /(^|\/)secrets?(\.|$)/i,      // secret, secrets, secret.json
  /(^|\/)\.aws\//,
  /(^|\/)\.ssh\//,
  /(^|\/)\.npmrc$/,             // npm auth tokens
  /(^|\/)\.netrc$/,
  /(^|\/)\.pypirc$/,
  /(^|\/)\.docker\/config\.json$/,
  /(^|\/)gcloud\//,
  /(^|\/)firebase[-_]?adminsdk/i,
  /serviceAccount.*\.json$/i,
];

function gateEcho(args) {
  // No paths, no stateful effects. Sentinel layer already vetoes redirection
  // and command substitution. Any printable args are fine.
  return true;
}

function gatePrintf(args) {
  // Same risk profile as echo: format string + args. No FS write since
  // redirection vetoed at sentinel layer.
  return args.length >= 1;
}

function gateNullop(args) {
  // `:`, `true`, `false` — no args expected, but tolerate them.
  return true;
}

function isCatPathSafe(path) {
  if (!path || typeof path !== 'string') return false;
  // Reject sentinel-like flags that invoke alternate behavior.
  // `cat -A` etc. is fine — unprintable chars only. Reject only the path
  // itself; flags handled by caller.
  // Empty path / dash-as-stdin handled by caller.
  // Reject any path whose absolute form escapes the allow roots.
  if (path.startsWith('/')) {
    // Match either `prefix` exactly (e.g. `/tmp`) or `prefix...` (e.g. `/tmp/x`).
    const inAllowedRoot = CAT_ABSOLUTE_ALLOW_PREFIXES.some((p) => {
      // p ends with "/", so test both `path === p.slice(0,-1)` and `path.startsWith(p)`.
      return path === p.replace(/\/$/, '') || path === p || path.startsWith(p);
    });
    if (!inAllowedRoot) {
      return false;
    }
  } else {
    // Relative path: reject if it tries to escape via "..".
    const parts = path.split('/');
    if (parts.includes('..')) return false;
  }
  // Apply secret pattern blacklist regardless of in-scope-ness.
  for (const pat of CAT_SECRET_PATTERNS) {
    if (pat.test(path)) return false;
  }
  return true;
}

function gateCat(args) {
  // Allowed flags: -n, -b, -A, -E, -T, -s, -v, -e, -t, --number, --show-ends,
  // --show-tabs, --squeeze-blank, --show-nonprinting, --help, --version,
  // --number-nonblank.
  // Reject any path that fails isCatPathSafe. Reject `-` (stdin) — there is
  // no stdin in our PreToolUse context, but treat it as suspicious.
  // Require at least one positional path.
  const SAFE_FLAGS = /^(-[nbAETsvet]+|--number|--number-nonblank|--show-ends|--show-tabs|--squeeze-blank|--show-nonprinting|--show-all|--help|--version)$/;
  let positionals = 0;
  for (const a of args) {
    if (a === '-') return false;          // stdin
    if (a === '--') continue;             // end-of-options sentinel: tolerate
    if (a.startsWith('-')) {
      if (!SAFE_FLAGS.test(a)) return false;
      continue;
    }
    if (!isCatPathSafe(a)) return false;
    positionals++;
  }
  return positionals >= 1;
}

// ---- Pipe-target read-only verbs ----------------------------------------
// These consume stdin from a piped predecessor (or, if invoked with a path
// argument, read from that path under the same allow-list as `cat`).
// Stdout redirection is already vetoed at the sentinel layer, so none of
// these can write to disk via shell.

function gateHeadTail(args) {
  // Reject `-f` (follow / never terminates), tolerate -n NUM, -c NUM, -NUM,
  // -q, -v, --lines=, --bytes=. Positional path must be in scope.
  let i = 0;
  while (i < args.length) {
    const a = args[i];
    if (a === '-f' || a === '--follow' || a === '--retry' || a.startsWith('--pid')) return false;
    if (a.startsWith('-')) {
      if (a === '-n' || a === '-c') { i += 2; continue; }
      if (/^-n[0-9]+$/.test(a) || /^-c[0-9]+$/.test(a) || /^-[0-9]+$/.test(a)) { i++; continue; }
      if (a === '-q' || a === '-v' || a === '--quiet' || a === '--silent' || a === '--verbose' || a === '--zero-terminated' || a === '-z') { i++; continue; }
      if (a.startsWith('--lines=') || a.startsWith('--bytes=')) { i++; continue; }
      if (a === '--help' || a === '--version') { i++; continue; }
      return false;
    }
    if (!isCatPathSafe(a)) return false;
    i++;
  }
  return true;
}

function gateWc(args) {
  for (const a of args) {
    if (a.startsWith('-')) {
      if (!/^(-[lwcmL]+|--lines|--words|--bytes|--chars|--max-line-length|--help|--version|--files0-from=.+)$/.test(a)) {
        return false;
      }
    } else if (!isCatPathSafe(a)) {
      return false;
    }
  }
  return true;
}

function gateSort(args) {
  // Reject -o / --output= (writes to file).
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '-o' || a.startsWith('--output')) return false;
    if (a.startsWith('-')) continue;
    if (!isCatPathSafe(a)) return false;
  }
  return true;
}

function gateUniq(args) {
  // Last positional in uniq is OUTPUT path. Reject any 2nd positional to be safe.
  let positionals = 0;
  for (const a of args) {
    if (a.startsWith('-')) continue;
    positionals++;
    if (positionals > 1) return false; // would be output file
    if (!isCatPathSafe(a)) return false;
  }
  return true;
}

function gateTr(args) {
  // tr never writes to file; just stdin → stdout. Any flags fine.
  return true;
}

function gateCut(args) {
  for (const a of args) {
    if (a.startsWith('-')) continue;
    if (!isCatPathSafe(a)) return false;
  }
  return true;
}

function gateNl(args) {
  for (const a of args) {
    if (a.startsWith('-')) continue;
    if (!isCatPathSafe(a)) return false;
  }
  return true;
}

function gateColumn(args) {
  for (const a of args) {
    if (a.startsWith('-')) continue;
    if (!isCatPathSafe(a)) return false;
  }
  return true;
}

function gatePager(args) {
  // less / more: read-only pager. Path arg must be in scope.
  for (const a of args) {
    if (a.startsWith('-')) continue;
    if (a === '+') continue;
    if (a.startsWith('+')) continue; // less +<line>, +/<pattern> etc.
    if (!isCatPathSafe(a)) return false;
  }
  return true;
}

// `cp` is a WRITE operation. We auto-approve it only under a deliberately
// narrow rule: the destination must be (a) anywhere under /tmp or /var/tmp,
// or (b) inside a `/.claude/` directory. Source must be under one of the
// cat-allow roots. This covers the legitimate use case of mirroring
// `.claude/hooks/*` and `.claude/settings.json` across sibling worktrees,
// without granting general write access to project source.
function gateCp(args) {
  const SAFE_FLAGS = new Set([
    '-r', '-R', '-p', '-a', '-v', '-i', '-n',
    '--recursive', '--preserve', '--archive', '--verbose', '--interactive',
    '--no-clobber', '--no-target-directory',
  ]);
  const positionals = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--') continue;
    if (a.startsWith('-')) {
      if (a.startsWith('--preserve=')) continue;
      if (a === '-f' || a === '--force' || a === '--remove-destination' || a === '--backup' || a.startsWith('--backup=')) {
        return false;
      }
      if (!SAFE_FLAGS.has(a)) return false;
      continue;
    }
    positionals.push(a);
  }
  if (positionals.length < 2) return false;

  const dest = positionals[positionals.length - 1];
  const sources = positionals.slice(0, -1);

  // Source must be in a cat-allow root.
  for (const s of sources) {
    if (!s.startsWith('/')) return false; // require absolute paths for cp
    if (s.split('/').includes('..')) return false;
    if (!CAT_ABSOLUTE_ALLOW_PREFIXES.some((p) => s.startsWith(p))) return false;
    for (const pat of CAT_SECRET_PATTERNS) {
      if (pat.test(s)) return false;
    }
  }

  // Destination: must be inside /.claude/ subtree OR under /tmp/.
  if (!dest.startsWith('/')) return false;
  if (dest.split('/').includes('..')) return false;
  const destInClaude = dest.includes('/.claude/');
  const destInTmp = dest.startsWith('/tmp/') || dest.startsWith('/var/tmp/');
  if (!destInClaude && !destInTmp) return false;
  // Even within /.claude/, reject .git/ or node_modules/ traversal artifacts.
  if (/\/\.git\//.test(dest)) return false;
  if (/\/node_modules\//.test(dest)) return false;
  for (const pat of CAT_SECRET_PATTERNS) {
    if (pat.test(dest)) return false;
  }
  return true;
}

function gateGrep(args) {
  // Reject -f FILE outside scope, tolerate other flags. Positional pattern
  // is the first non-flag; subsequent positionals are paths.
  // grep does not write files (no -o FILE flag in BSD/GNU grep — `-o`
  // means "only-matching", safe). Avoid recursive grep for now (-r/-R)
  // to keep the blast radius small if ever invoked from a wrong cwd —
  // user can fall back to the Grep tool.
  let i = 0;
  let sawPattern = false;
  while (i < args.length) {
    const a = args[i];
    if (a === '-r' || a === '-R' || a === '--recursive' || a === '--dereference-recursive') return false;
    if (a === '-f' || a === '--file') {
      const f = args[i + 1];
      if (!f || !isCatPathSafe(f)) return false;
      i += 2; sawPattern = true; continue;
    }
    if (a.startsWith('--file=')) {
      if (!isCatPathSafe(a.slice('--file='.length))) return false;
      i++; sawPattern = true; continue;
    }
    if (a === '-e' || a === '--regexp') {
      // pattern follows
      i += 2; sawPattern = true; continue;
    }
    if (a.startsWith('--regexp=')) { i++; sawPattern = true; continue; }
    if (a.startsWith('-')) { i++; continue; }
    // Positional
    if (!sawPattern) { sawPattern = true; i++; continue; }
    if (!isCatPathSafe(a)) return false;
    i++;
  }
  return sawPattern;
}

function gateLs(args) {
  // Read-only directory listing. Reject `--color=always > out` style is
  // already vetoed by sentinel. Path arg must be in scope.
  for (const a of args) {
    if (a.startsWith('-')) continue; // tolerate any ls flag
    if (!isCatPathSafe(a)) return false;
  }
  return true;
}

const NON_GIT_VERBS = {
  echo: gateEcho,
  printf: gatePrintf,
  cat: gateCat,
  ':': gateNullop,
  true: gateNullop,
  false: gateNullop,
  // Pipe-target read-only verbs
  head: gateHeadTail,
  tail: gateHeadTail,
  wc: gateWc,
  sort: gateSort,
  uniq: gateUniq,
  tr: gateTr,
  cut: gateCut,
  nl: gateNl,
  column: gateColumn,
  less: gatePager,
  more: gatePager,
  grep: gateGrep,
  ls: gateLs,
  // Narrowly-gated write verb: only mirrors files into /.claude/ subtree
  // or /tmp/. See gateCp for the full rule.
  cp: gateCp,
};

// -----------------------------------------------------------------------------
// Tokenizer: shell-aware split for a single segment
// -----------------------------------------------------------------------------
function tokenize(seg) {
  // Minimal shell tokenizer: handles single/double quotes, no $vars (vetoed already).
  const out = [];
  let cur = '';
  let i = 0;
  let quote = null;
  while (i < seg.length) {
    const c = seg[i];
    if (quote) {
      if (c === quote) { quote = null; i++; continue; }
      if (c === '\\' && i + 1 < seg.length) { cur += seg[i + 1]; i += 2; continue; }
      cur += c;
      i++;
    } else {
      if (c === '"' || c === "'") { quote = c; i++; continue; }
      if (/\s/.test(c)) {
        if (cur) { out.push(cur); cur = ''; }
        i++;
        continue;
      }
      if (c === '\\' && i + 1 < seg.length) { cur += seg[i + 1]; i += 2; continue; }
      cur += c;
      i++;
    }
  }
  if (cur) out.push(cur);
  return out;
}

// -----------------------------------------------------------------------------
// Per-segment safety check
// -----------------------------------------------------------------------------
function isSegmentSafe(seg) {
  const trimmed = seg.trim();
  if (!trimmed) return true; // empty segment after split is harmless

  const tokens = tokenize(trimmed);
  if (tokens.length === 0) return true;

  // Strip leading env-var assignments? (e.g. `FOO=bar git ...`). Reject — too risky.
  if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[0])) return false;

  // ---- Non-git read-only verbs (echo / printf / cat / : / true / false) ----
  if (Object.prototype.hasOwnProperty.call(NON_GIT_VERBS, tokens[0])) {
    return NON_GIT_VERBS[tokens[0]](tokens.slice(1));
  }

  if (tokens[0] !== 'git') return false;

  let idx = 1;

  // Optional `-C <path>` — must point under Desktop
  if (tokens[idx] === '-C') {
    const path = tokens[idx + 1];
    if (!path) return false;
    if (!path.startsWith(DESKTOP_PREFIX)) return false;
    idx += 2;
  }

  // Skip global options that are read-safe: --no-pager, --paginate, --git-dir=, --work-tree=
  // Reject -c (config override) outright since it can sneak in core.hooksPath etc.
  while (idx < tokens.length && tokens[idx].startsWith('-')) {
    const t = tokens[idx];
    if (t === '--no-pager' || t === '-p' || t === '--paginate' || t === '--no-replace-objects' || t === '--bare') {
      idx++;
      continue;
    }
    if (t.startsWith('--git-dir=') || t.startsWith('--work-tree=') || t.startsWith('--namespace=')) {
      // Allow only if value is under Desktop or is a relative-looking path within current worktree.
      const val = t.split('=')[1] || '';
      if (val && !val.startsWith(DESKTOP_PREFIX) && val.includes('/')) return false;
      idx++;
      continue;
    }
    // Anything else with -c / -P / unknown -> reject
    return false;
  }

  if (idx >= tokens.length) return false;

  const verb = tokens[idx];
  idx++;
  const args = tokens.slice(idx);

  if (WRITE_VERBS.has(verb)) return false;

  if (PLAIN_READONLY.has(verb)) return true;

  if (Object.prototype.hasOwnProperty.call(SUBCOMMAND_GATES, verb)) {
    return SUBCOMMAND_GATES[verb](args);
  }

  // Unknown verb — be conservative
  return false;
}

// -----------------------------------------------------------------------------
// Split command on shell separators (&&, ||, ;) at top level only
// -----------------------------------------------------------------------------
function splitTopLevel(cmd) {
  const segs = [];
  let cur = '';
  let i = 0;
  let quote = null;
  let paren = 0;
  while (i < cmd.length) {
    const c = cmd[i];
    if (quote) {
      cur += c;
      if (c === quote) quote = null;
      else if (c === '\\' && i + 1 < cmd.length) { cur += cmd[i + 1]; i += 2; continue; }
      i++;
      continue;
    }
    if (c === '"' || c === "'") { quote = c; cur += c; i++; continue; }
    if (c === '(') { paren++; cur += c; i++; continue; }
    if (c === ')') { paren--; cur += c; i++; continue; }
    if (paren === 0) {
      if (c === '&' && cmd[i + 1] === '&') { segs.push(cur); cur = ''; i += 2; continue; }
      if (c === '|' && cmd[i + 1] === '|') { segs.push(cur); cur = ''; i += 2; continue; }
      if (c === ';') { segs.push(cur); cur = ''; i++; continue; }
      if (c === '|') {
        // Single pipe — split as a segment boundary. The downstream segment
        // (`head`, `tail`, `wc`, `grep`, `sort`, `less`, ...) is checked by
        // isSegmentSafe just like an &&-chained command would be. Any segment
        // that is not a known read-only verb falls through to user prompt.
        segs.push(cur);
        cur = '';
        i++;
        continue;
      }
    }
    cur += c;
    i++;
  }
  if (paren !== 0 || quote !== null) return null;
  segs.push(cur);
  return segs;
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------
const segments = splitTopLevel(cmd);
if (!segments || segments.length === 0) {
  process.exit(0);
}

let anyNonEmpty = false;
for (const s of segments) {
  if (s.trim()) anyNonEmpty = true;
  if (!isSegmentSafe(s)) {
    process.exit(0);
  }
}
if (!anyNonEmpty) process.exit(0);

const out = {
  hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    permissionDecision: 'allow',
    permissionDecisionReason:
      'Read-only git on Desktop worktree (auto-approved by .claude/hooks/git-readonly-approve.js)',
  },
};
process.stdout.write(JSON.stringify(out));
process.exit(0);
