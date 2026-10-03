#!/usr/bin/env node
/**
 * scripts/kit/emoji-scan.mjs - R1 emoji red-line enforcement.
 *
 * 掃原始碼中的 emoji codepoint,命中則印 path:line:col 並 exit 1。
 *   node scripts/kit/emoji-scan.mjs [files...]
 *     有給檔案 -> 只掃這些(pre-commit 傳 staged 檔)
 *     沒給     -> 掃 `git ls-files` 的全部追蹤檔
 *
 * kit.json 可調(全部選填):
 *   emojiScan.allowChars      : 永遠放行的字元,預設 版權符號(U+00A9)。例:占星符號 U+2609 U+263D U+2640 U+2642
 *   emojiScan.excludePrefixes : 額外略過的路徑前綴(相對專案根),例:["src/data/emoji-picker/"]
 * 內建略過:node_modules/dist/build/.next/coverage 等目錄,以及 dev-rule/ .planning/ docs/ .claude/ .githooks/。
 *
 * 單行放行:同一行放 `emoji-scan-ignore-line` 標記(註解內或 JSON 值旁)。
 * 偵測:Unicode property \p{Extended_Pictographic}(不會誤傷中文與一般符號)。
 */

import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { dirname, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadKit, isMain } from './kit.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const cfg = loadKit(ROOT).emojiScan || {};

const EXCLUDE_DIR_SEGMENTS = new Set([
  'node_modules', 'dist', 'build', '.next', '.turbo', 'coverage',
  'playwright-report', 'test-results', '.git',
]);
const EXCLUDE_PATH_PREFIXES = [
  'dev-rule/', '.planning/', 'docs/', '.claude/', '.githooks/',
  ...(Array.isArray(cfg.excludePrefixes) ? cfg.excludePrefixes : []),
];
const SOURCE_EXT = new Set([
  '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs',
  '.css', '.scss', '.html', '.json', '.md',
  '.py', '.sql', '.go', '.rs', '.java', '.rb', '.php', '.sh', '.vue', '.svelte',
]);
const ALLOW_CHARS = Array.isArray(cfg.allowChars) ? cfg.allowChars : ['©'];
const WHITELIST_CODEPOINTS = new Set(ALLOW_CHARS.map((c) => String(c).codePointAt(0)));
// 修飾用字元不單獨計(只在真 emoji 旁邊才有意義)
const COMBINING_OR_VS = new Set([0x200D, 0xFE0F, 0xFE0E]);
const EMOJI_RE = /\p{Extended_Pictographic}/u;

function inScope(rel) {
  if (rel.split('/').some((seg) => EXCLUDE_DIR_SEGMENTS.has(seg))) return false;
  if (EXCLUDE_PATH_PREFIXES.some((p) => rel.startsWith(p))) return false;
  const dot = rel.lastIndexOf('.');
  if (dot < 0) return false;
  return SOURCE_EXT.has(rel.slice(dot).toLowerCase());
}

function scanContent(content) {
  const hits = [];
  const lines = content.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!EMOJI_RE.test(line)) continue;
    if (line.includes('emoji-scan-ignore-line')) continue;
    let col = 0;
    for (const ch of line) {
      const cp = ch.codePointAt(0);
      col += 1;
      if (cp == null || WHITELIST_CODEPOINTS.has(cp) || COMBINING_OR_VS.has(cp)) continue;
      if (EMOJI_RE.test(ch)) {
        hits.push({ line: i + 1, col, char: ch, cp: 'U+' + cp.toString(16).toUpperCase().padStart(4, '0') });
      }
    }
  }
  return hits;
}

async function scanFile(rel) {
  if (!inScope(rel)) return [];
  let content;
  try {
    content = await readFile(resolve(ROOT, rel), 'utf8');
  } catch {
    return [];
  }
  return scanContent(content).map((h) => ({ file: rel, ...h }));
}

function trackedFiles() {
  try {
    return execFileSync('git', ['ls-files'], { cwd: ROOT, encoding: 'utf8' }).split('\n').filter(Boolean);
  } catch {
    return [];
  }
}

async function main() {
  const argv = process.argv.slice(2);
  const files = argv.length > 0
    ? argv.map((a) => relative(ROOT, resolve(process.cwd(), a)).split(sep).join('/'))
    : trackedFiles();
  const violations = [];
  for (const rel of files) violations.push(...(await scanFile(rel)));
  report(violations);
}

function report(violations) {
  if (violations.length === 0) {
    console.log('[emoji-scan] OK - no emoji found in scanned sources.');
    process.exit(0);
  }
  console.error('');
  console.error('============================================================');
  console.error('[emoji-scan] BLOCKED: emoji detected (R1 no-emoji red line).');
  console.error('============================================================');
  console.error('Replace with plain text, or add `emoji-scan-ignore-line` on the same');
  console.error('line if it is legitimate UI/data. Allowed chars: ' + ALLOW_CHARS.join(' '));
  console.error('');
  for (const v of violations) console.error(`  ${v.file}:${v.line}:${v.col}  ${v.cp}  ${v.char}`);
  console.error('');
  console.error(`Total: ${violations.length} hit(s).`);
  process.exit(1);
}

if (isMain(import.meta.url)) {
  main().catch((err) => {
    console.error('[emoji-scan] FATAL:', err);
    process.exit(2);
  });
}
