#!/usr/bin/env node
// scripts/kit/check-dependency-pins.mjs
//
// workspace 的 package.json 宣告的版本若落在 pin 檔 allowedRange 之外 -> exit 1。
// 防 Dependabot 把相容性未就緒的套件反覆升上去。見 dev-rule/DEPENDENCY_PINS.md。
//
// pin 檔路徑:kit.json 的 dependencyPins.file,預設 "scripts/dependency-pins.json"。
// 檔案不存在或為空陣列 -> 略過。格式:
//   [{ "workspace": ".", "package": "eslint", "allowedRange": "^9",
//      "reason": "...", "unlockWhen": "...", "refs": ["#123"] }]
// 需要 `semver` 套件(多數 JS 專案已有);解析不到時印警告並略過,不擋 commit。
import { existsSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadKit } from './kit.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const pinFile = (loadKit(root).dependencyPins || {}).file || 'scripts/dependency-pins.json';
const pinPath = join(root, pinFile);

if (!existsSync(pinPath)) {
  console.log(`[dependency-pins] no pin file (${pinFile}) - skipped.`);
  process.exit(0);
}
const pins = JSON.parse(readFileSync(pinPath, 'utf8'));
if (!Array.isArray(pins) || pins.length === 0) {
  console.log('[dependency-pins] no pins registered - skipped.');
  process.exit(0);
}

let semver;
try {
  semver = createRequire(join(root, 'package.json'))('semver');
} catch {
  console.warn('[dependency-pins] WARNING: `semver` not installed (npm i -D semver) - pin check skipped.');
  process.exit(0);
}

let failed = 0;
for (const pin of pins) {
  const pkgPath = join(root, pin.workspace, 'package.json');
  if (!existsSync(pkgPath)) continue;
  const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'));
  const declared = pkg.dependencies?.[pin.package] ?? pkg.devDependencies?.[pin.package];
  if (declared === undefined) continue;
  const min = semver.minVersion(declared);
  if (min && semver.satisfies(min, pin.allowedRange)) continue;
  failed++;
  console.error(`[dependency-pins] FAIL ${pin.workspace}: ${pin.package} is "${declared}", must satisfy "${pin.allowedRange}"`);
  console.error(`  reason:     ${pin.reason}`);
  console.error(`  unlockWhen: ${pin.unlockWhen}`);
  console.error(`  refs:       ${(pin.refs || []).join(' ')}`);
  console.error('  doc:        dev-rule/DEPENDENCY_PINS.md');
}
if (failed) process.exit(1);
console.log(`[dependency-pins] OK (${pins.length} pin(s))`);
