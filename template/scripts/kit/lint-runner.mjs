#!/usr/bin/env node
// scripts/kit/lint-runner.mjs
//
// Multi-workspace lint ratchet,workspace 清單與基線路徑來自 kit.json:
//   ratchet.lint.workspaces : ["apps/web", { "path": "pkg/api", "command": "npx eslint ." }]
//   ratchet.lint.baseline   : 預設 ".planning/audit/lint-baseline.json"
//   commands.lint           : workspace 未指定 command 時的預設(再預設 "npm run --silent lint")
// workspace 的指令在該 workspace 目錄內執行;path 為 "." 代表專案根。
//
// Modes:
//   --mode=run        純 lint(任何 workspace 有 error 即失敗)
//   --mode=baseline   lint 每個 workspace,把計數寫入基線 JSON
//   --mode=check      lint 後與基線比對,只在「高於基線」時失敗;低於基線提示可下調
// Options:
//   --only=a,b        只檢查這些 workspace(baseline 模式忽略)
//   --since=<ref>     只檢查 `git diff <ref>...HEAD` 動到的 workspace;
//                     沒有相關 code 變更就直接略過;動到 lint 設定/基線/lockfile 則改跑全部
//
// 為什麼自製 runner:ESLint 的 --max-warnings 只管 warning,ratchet 需要 errors+warnings 的合計上限。
// kit.json 沒設任何 workspace 時:印一行說明並 exit 0(模組未啟用,不報錯)。

import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, resolve, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { loadKit, normalizeWorkspaces, isMain } from "./kit.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "../..");

const kit = loadKit(ROOT);
const cfg = (kit.ratchet && kit.ratchet.lint) || {};
const WORKSPACES = normalizeWorkspaces(cfg.workspaces);
const BASELINE_REL = cfg.baseline || ".planning/audit/lint-baseline.json";
const BASELINE_PATH = resolve(ROOT, BASELINE_REL);
const DEFAULT_COMMAND = (kit.commands && kit.commands.lint) || "npm run --silent lint";
const CODE_EXT = /\.(ts|tsx|js|jsx|mjs|cjs)$/;
const NAMES = WORKSPACES.map((w) => w.path);

function parseArgs() {
  const get = (k) => {
    const a = process.argv.find((x) => x.startsWith("--" + k + "="));
    return a ? a.slice(k.length + 3) : null;
  };
  const only = get("only");
  return {
    mode: get("mode") || "run",
    since: get("since"),
    only: only ? only.split(",").map((s) => s.trim()).filter(Boolean) : null,
  };
}

// 純函式(可獨立測試):依 --mode / --only 決定要跑的 workspace。
// 找不到的名稱 / 全無效 -> 退回全部(漏報比慢更糟)。
function resolveTargetWorkspaces(mode, only, names = NAMES) {
  if (!only) return { targets: names, warnings: [] };
  if (mode === "baseline") {
    return { targets: names, warnings: ["--only ignored in baseline mode (baseline always covers all workspaces)."] };
  }
  const warnings = [];
  const valid = only.filter((ws) => names.includes(ws));
  const invalid = only.filter((ws) => !names.includes(ws));
  if (invalid.length) {
    warnings.push("--only: unknown workspace(s) ignored: " + invalid.join(", ") + " (known: " + names.join(", ") + ")");
  }
  if (valid.length === 0) {
    warnings.push("--only: no valid workspaces in list, falling back to full check.");
    return { targets: names, warnings };
  }
  return { targets: valid, warnings };
}

// --since:由 git diff 決定受影響 workspace。回傳 null = 無相關變更(略過);否則 names 子集。
function resolveSince(ref) {
  const res = spawnSync("git", ["diff", "--name-only", "--diff-filter=ACMR", ref + "...HEAD"], {
    cwd: ROOT, encoding: "utf8",
  });
  if (res.status !== 0) {
    console.log("[lint-runner] --since: cannot diff against " + ref + ", running full check.");
    return NAMES;
  }
  const files = res.stdout.split("\n").filter(Boolean);
  const wide = files.filter((f) =>
    /^(eslint\.config\.|\.eslintrc|package-lock\.json$|\.claude\/kit\.json$|kit\.json$)/.test(f) ||
    f === "scripts/kit/lint-runner.mjs" || f === BASELINE_REL);
  if (wide.length) {
    console.log("[lint-runner] scope: full (diff touches lint config / baseline):");
    for (const f of wide) console.log("[lint-runner]   " + f);
    return NAMES;
  }
  const code = files.filter((f) => CODE_EXT.test(f));
  const touched = WORKSPACES
    .filter((w) => w.path === "." || code.some((f) => f.startsWith(w.path.replace(/\/+$/, "") + "/")))
    .map((w) => w.path);
  if (touched.length === 0) return null;
  console.log("[lint-runner] scope: " + touched.join(", ") + " (diff-touched workspace(s) only).");
  return touched;
}

function runLint(ws) {
  const cmd = ws.command || DEFAULT_COMMAND;
  const res = spawnSync("sh", ["-c", cmd], {
    cwd: resolve(ROOT, ws.path), encoding: "utf8", stdio: ["ignore", "pipe", "pipe"],
  });
  const out = (res.stdout || "") + "\n" + (res.stderr || "");
  // ESLint stylish 摘要列: "N problems (E errors, W warnings)"
  const m = out.match(/(\d+)\s+problems?\s*\((\d+)\s+errors?,\s*(\d+)\s+warnings?\)/);
  if (m) return { errors: Number(m[2]), warnings: Number(m[3]), exit: res.status ?? 0, output: out };
  // 沒摘要列且 exit 0 = 乾淨(eslint 零問題不印東西)
  if ((res.status ?? 0) === 0) return { errors: 0, warnings: 0, exit: 0, output: out };
  // 解析不了且非 0:交給呼叫端當 parse-fail
  return { errors: null, warnings: null, exit: res.status ?? 1, output: out };
}

function loadBaseline() {
  if (!existsSync(BASELINE_PATH)) {
    console.error("[lint-runner] baseline file missing: " + BASELINE_PATH);
    console.error("Create it once with:  node scripts/kit/lint-runner.mjs --mode=baseline");
    process.exit(2);
  }
  return JSON.parse(readFileSync(BASELINE_PATH, "utf8"));
}

function writeBaseline(results) {
  mkdirSync(dirname(BASELINE_PATH), { recursive: true });
  const existing = existsSync(BASELINE_PATH) ? JSON.parse(readFileSync(BASELINE_PATH, "utf8")) : {};
  const next = {
    capturedAt: new Date().toISOString().slice(0, 10),
    policy: "ratchet-only",
    note: existing.note || "lint check fails only when a workspace exceeds its baseline (errors + warnings combined).",
    workspaces: {},
  };
  for (const name of NAMES) {
    const r = results[name];
    next.workspaces[name] = !r || r.errors === null
      ? { errors: null, warnings: null, maxWarnings: null, note: "lint failed to parse - see logs" }
      : { errors: r.errors, warnings: r.warnings, maxWarnings: r.errors + r.warnings };
  }
  writeFileSync(BASELINE_PATH, JSON.stringify(next, null, 2) + "\n", "utf8");
  console.log("[lint-runner] wrote baseline: " + relative(ROOT, BASELINE_PATH));
}

const fmt = (r) => (!r || r.errors === null ? "parse-fail" : r.errors + " errors / " + r.warnings + " warnings");

function main() {
  const { mode, only, since } = parseArgs();

  if (WORKSPACES.length === 0) {
    console.log("[lint-runner] kit.json ratchet.lint.workspaces not set - lint ratchet skipped.");
    return;
  }

  let scope = NAMES;
  if (since && mode !== "baseline") {
    const s = resolveSince(since);
    if (s === null) {
      console.log("[lint-runner] no lint-relevant changes vs " + since + " - skipped.");
      return;
    }
    scope = s;
  }
  const { targets, warnings } = resolveTargetWorkspaces(mode, only && only.length ? only : null, scope);
  for (const w of warnings) console.log("[lint-runner] " + w);

  const results = {};
  for (const name of targets) {
    process.stdout.write("[lint-runner] " + name + " ... ");
    results[name] = runLint(WORKSPACES.find((w) => w.path === name));
    console.log(fmt(results[name]));
  }

  if (mode === "baseline") {
    writeBaseline(results);
    return;
  }

  if (mode === "check") {
    const baseline = loadBaseline();
    const regressions = [];
    for (const name of targets) {
      const r = results[name];
      const b = baseline.workspaces && baseline.workspaces[name];
      if (!b) {
        console.log("[lint-runner] " + name + ": no baseline entry, skipping");
        continue;
      }
      if (!r || r.errors === null) {
        regressions.push(name + ": lint runner could not parse output (exit=" + (r && r.exit) + ")");
        if (r) console.log(r.output);
        continue;
      }
      const current = r.errors + r.warnings;
      if (current > b.maxWarnings) {
        regressions.push(name + ": " + current + " problems (" + r.errors + "e/" + r.warnings + "w) exceeds baseline " + b.maxWarnings);
      } else if (current < b.maxWarnings) {
        console.log("[lint-runner] " + name + ": " + current + " <= baseline " + b.maxWarnings +
          " - consider ratcheting down: node scripts/kit/lint-runner.mjs --mode=baseline");
      }
    }
    if (regressions.length) {
      console.error("\n[lint-runner] LINT REGRESSION:");
      for (const r of regressions) console.error("  - " + r);
      console.error(
        "\nFix the new violations, or if you lowered the count on purpose, run\n" +
        "  node scripts/kit/lint-runner.mjs --mode=baseline\n" +
        "to lower the ceiling. The gate never raises the baseline automatically.\n");
      process.exit(1);
    }
    console.log("[lint-runner] OK - no regression vs baseline.");
    return;
  }

  // mode=run:任何 workspace 有 error 即失敗
  let failed = false;
  for (const name of targets) {
    const r = results[name];
    if (!r || (r.errors ?? 0) > 0 || r.exit !== 0) failed = true;
  }
  process.exit(failed ? 1 : 0);
}

export { resolveTargetWorkspaces };

if (isMain(import.meta.url)) {
  main();
}
