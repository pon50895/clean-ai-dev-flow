#!/usr/bin/env node
// scripts/kit/tsc-runner.mjs
//
// Multi-workspace `tsc --noEmit` ratchet,workspace 與基線路徑來自 kit.json:
//   ratchet.tsc.workspaces : ["apps/web", { "path": "apps/api", "project": "tsconfig.app.json" }]
//   ratchet.tsc.baseline   : 預設 ".planning/audit/tsc-baseline.json"
// project 預設 "tsconfig.json";指令在 workspace 目錄內執行:`npx tsc --noEmit -p <project>`。
//
// Modes:
//   --mode=baseline   typecheck 每個 workspace,把錯誤數寫入基線 JSON
//   --mode=check      與基線比對,只在「高於基線」時失敗(預設)
// Options:
//   --since=<ref>     `git diff <ref>...HEAD` 沒動到 workspace 內的 .ts/.tsx 就略過
//
// 為什麼自製 runner:tsc 沒有內建 ratchet;既有專案常帶著舊型別錯誤,gate 只擋「新增」。
// kit.json 沒設任何 workspace 時:印一行說明並 exit 0(模組未啟用,不報錯)。

import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, resolve, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { loadKit, normalizeWorkspaces, isMain } from "./kit.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "../..");

const kit = loadKit(ROOT);
const cfg = (kit.ratchet && kit.ratchet.tsc) || {};
const WORKSPACES = normalizeWorkspaces(cfg.workspaces).map((w) => ({
  name: w.path,
  project: w.project || "tsconfig.json",
}));
const BASELINE_PATH = resolve(ROOT, cfg.baseline || ".planning/audit/tsc-baseline.json");

function parseArgs() {
  const get = (k) => {
    const a = process.argv.find((x) => x.startsWith("--" + k + "="));
    return a ? a.slice(k.length + 3) : null;
  };
  return { mode: get("mode") || "check", since: get("since") };
}

// --since:有 ts/tsx 變更落在任一 workspace 內才需要跑(跑全部,型別錯誤可跨 workspace 傳遞)。
function hasRelevantChanges(ref) {
  const res = spawnSync("git", ["diff", "--name-only", "--diff-filter=ACMR", ref + "...HEAD"], {
    cwd: ROOT, encoding: "utf8",
  });
  if (res.status !== 0) return true; // 無法比對 -> 跑(漏報比慢更糟)
  const files = res.stdout.split("\n").filter((f) => /\.(ts|tsx)$/.test(f));
  return files.some((f) =>
    WORKSPACES.some((w) => w.name === "." || f.startsWith(w.name.replace(/\/+$/, "") + "/")));
}

function runTsc(ws) {
  const res = spawnSync("npx", ["tsc", "--noEmit", "-p", ws.project], {
    cwd: resolve(ROOT, ws.name), encoding: "utf8", stdio: ["ignore", "pipe", "pipe"],
  });
  const out = (res.stdout || "") + "\n" + (res.stderr || "");

  // 摘要列: "Found N errors in M files." / "Found 1 error in 1 file."
  const summary = out.match(/Found\s+(\d+)\s+errors?/);
  if (summary) return { errors: Number(summary[1]), exit: res.status ?? 0, output: out, ts2304: countTs2304(out) };
  // 沒摘要列且 exit 0 = 乾淨
  if ((res.status ?? 0) === 0) return { errors: 0, exit: 0, output: out, ts2304: 0 };
  // 退而求其次:數 "error TS####:" 行
  const matches = out.match(/error TS\d+:/g);
  if (matches) return { errors: matches.length, exit: res.status ?? 1, output: out, ts2304: countTs2304(out) };
  return { errors: null, exit: res.status ?? 1, output: out, ts2304: countTs2304(out) };
}

// TS2304 "Cannot find name 'X'":lint 清理誤刪仍在用的 import 時,執行期才爆 "X is not defined"。
// 零容忍:任何 TS2304 直接失敗,不進基線。
function countTs2304(out) {
  const m = out.match(/error TS2304:/g);
  return m ? m.length : 0;
}

function loadBaseline() {
  if (!existsSync(BASELINE_PATH)) {
    console.error("[tsc-runner] baseline file missing: " + BASELINE_PATH);
    console.error("Create it once with:  node scripts/kit/tsc-runner.mjs --mode=baseline");
    process.exit(2);
  }
  return JSON.parse(readFileSync(BASELINE_PATH, "utf8"));
}

function writeBaseline(results) {
  mkdirSync(dirname(BASELINE_PATH), { recursive: true });
  const next = {
    capturedAt: new Date().toISOString().slice(0, 10),
    policy: "ratchet-only",
    note: "tsc check fails only when a workspace exceeds its baseline error count. " +
      "Ratchet down by re-running --mode=baseline after fixes.",
    workspaces: {},
  };
  for (const ws of WORKSPACES) {
    const r = results[ws.name];
    next.workspaces[ws.name] = !r || r.errors === null
      ? { project: ws.project, errors: null, note: "tsc failed to parse - see logs" }
      : { project: ws.project, errors: r.errors };
  }
  writeFileSync(BASELINE_PATH, JSON.stringify(next, null, 2) + "\n", "utf8");
  console.log("[tsc-runner] wrote baseline: " + relative(ROOT, BASELINE_PATH));
}

const fmt = (r) => (!r || r.errors === null ? "parse-fail" : r.errors + " errors");

function main() {
  const { mode, since } = parseArgs();

  if (WORKSPACES.length === 0) {
    console.log("[tsc-runner] kit.json ratchet.tsc.workspaces not set - tsc ratchet skipped.");
    return;
  }
  if (since && mode === "check" && !hasRelevantChanges(since)) {
    console.log("[tsc-runner] no .ts/.tsx changes in tsc workspaces vs " + since + " - skipped.");
    return;
  }

  const results = {};
  for (const ws of WORKSPACES) {
    process.stdout.write("[tsc-runner] " + ws.name + " (" + ws.project + ") ... ");
    results[ws.name] = runTsc(ws);
    console.log(fmt(results[ws.name]));
  }

  if (mode === "baseline") {
    writeBaseline(results);
    return;
  }

  if (mode === "check") {
    const baseline = loadBaseline();
    const regressions = [];

    for (const ws of WORKSPACES) {
      const r = results[ws.name];
      if (r && r.ts2304 > 0) {
        regressions.push(ws.name + ": " + r.ts2304 + " TS2304 'Cannot find name' error(s) - zero-tolerance gate");
        for (const l of (r.output || "").split("\n").filter((l) => /error TS2304:/.test(l))) console.log("  " + l);
      }
    }

    for (const ws of WORKSPACES) {
      const r = results[ws.name];
      const b = baseline.workspaces && baseline.workspaces[ws.name];
      if (!b) {
        console.log("[tsc-runner] " + ws.name + ": no baseline entry, skipping");
        continue;
      }
      if (!r || r.errors === null) {
        regressions.push(ws.name + ": tsc runner could not parse output (exit=" + (r && r.exit) + ")");
        if (r) console.log(r.output);
        continue;
      }
      if (b.errors === null || b.errors === undefined) {
        console.log("[tsc-runner] " + ws.name + ": baseline is null, skipping");
        continue;
      }
      if (r.errors > b.errors) {
        regressions.push(ws.name + ": " + r.errors + " errors exceeds baseline " + b.errors + " (+" + (r.errors - b.errors) + ")");
        console.log(r.output); // 讓開發者看到哪些是新錯
      } else if (r.errors < b.errors) {
        console.log("[tsc-runner] " + ws.name + ": " + r.errors + " <= baseline " + b.errors +
          " - consider ratcheting down: node scripts/kit/tsc-runner.mjs --mode=baseline");
      }
    }
    if (regressions.length) {
      console.error("\n[tsc-runner] TSC REGRESSION:");
      for (const r of regressions) console.error("  - " + r);
      console.error(
        "\nFix the new type errors, or if you lowered the count on purpose, run\n" +
        "  node scripts/kit/tsc-runner.mjs --mode=baseline\n" +
        "to lower the ceiling. The gate never raises the baseline automatically.\n");
      process.exit(1);
    }
    console.log("[tsc-runner] OK - no tsc regression vs baseline.");
    return;
  }

  console.error("[tsc-runner] unknown mode: " + mode);
  process.exit(2);
}

if (isMain(import.meta.url)) {
  main();
}
