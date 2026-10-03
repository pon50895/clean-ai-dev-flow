#!/usr/bin/env node
// scripts/kit/kit.mjs
//
// 讀專案根目錄的 kit.json(`.claude/kit.json` 優先,再試 `kit.json`)。
// 零依賴,只用 node 內建。husky/githooks 與各 runner 共用。
//
// CLI(給 shell hook 用,不需 jq):
//   node scripts/kit/kit.mjs get <dotted.path>
//   輸出規則:
//     - 路徑不存在 / kit.json 不存在 / JSON 壞掉 -> 什麼都不印,exit 0
//     - 字串 / 數字 / 布林 -> 單行
//     - 字串陣列 -> 每項一行
//     - 其他陣列 / 物件 -> 單行 JSON
//   陣列可取 `.length`(例:ratchet.lint.workspaces.length)。

import { existsSync, readFileSync, realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const KIT_PATHS = [".claude/kit.json", "kit.json"];

// 直接執行(而非被 import)時為 true;用 realpath 比對,/tmp 這類 symlink 路徑也成立。
export function isMain(metaUrl) {
  try {
    return realpathSync(fileURLToPath(metaUrl)) === realpathSync(process.argv[1]);
  } catch {
    return false;
  }
}

export function loadKit(root) {
  for (const rel of KIT_PATHS) {
    const p = resolve(root, rel);
    if (!existsSync(p)) continue;
    try {
      return JSON.parse(readFileSync(p, "utf8"));
    } catch {
      console.error("[kit] WARNING: " + rel + " is not valid JSON, treated as empty.");
      return {};
    }
  }
  return {};
}

export function getPath(obj, dotted) {
  let cur = obj;
  for (const key of String(dotted).split(".")) {
    if (cur === null || cur === undefined) return undefined;
    cur = cur[key];
  }
  return cur;
}

// 把 `ratchet.*.workspaces` 的元素正規化成物件(字串視為 { path })。
export function normalizeWorkspaces(list) {
  if (!Array.isArray(list)) return [];
  return list
    .map((w) => (typeof w === "string" ? { path: w } : w))
    .filter((w) => w && typeof w.path === "string" && w.path.length > 0);
}

function main() {
  const [cmd, dotted] = process.argv.slice(2);
  if (cmd !== "get" || !dotted) {
    console.error("usage: node scripts/kit/kit.mjs get <dotted.path>");
    process.exit(2);
  }
  const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
  const v = getPath(loadKit(root), dotted);
  if (v === undefined || v === null) return;
  if (Array.isArray(v) && v.every((x) => typeof x === "string")) {
    for (const x of v) console.log(x);
  } else if (typeof v === "object") {
    console.log(JSON.stringify(v));
  } else {
    console.log(String(v));
  }
}

if (isMain(import.meta.url)) {
  main();
}
