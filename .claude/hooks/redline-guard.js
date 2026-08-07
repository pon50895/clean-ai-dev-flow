#!/usr/bin/env node
/**
 * PreToolUse hook: 擋 settings.json deny-list 天生擋不到的紅線。
 *
 * deny-list 比對的是「指令字串 / 路徑」,所以 R9(push main)、R11(--no-verify)
 * 那種已經在 deny-list 解決了。這支只補兩個 deny-list 構造上做不到的:
 *
 *   R1  禁 emoji — emoji 在「寫進檔案的內容」裡,不是指令也不是路徑,
 *       permission matcher 看不到。掃 Edit/Write/MultiEdit 的新內容。
 *   R9  禁在 main/master 直接 commit — deny-list 擋了 push origin main,
 *       但沒擋「在 main 分支上 git commit」。這裡補上(查 git 指令實際要跑的那個 repo 的分支,
 *       認前導 cd,才不會在跨 repo commit 時誤用 session 專案的分支)。
 *
 * 不符合就 deny 並說明理由;其他一律放行(no output)。
 *
 * ponytail: 只做確定性能判的兩條。R3 full-file overwrite / R7 刪別人代碼
 * 這種要語意判斷的留給 reviewer subagent,不硬塞進 hook。
 */
"use strict";

const { execSync } = require("child_process");
const os = require("os");
const path = require("path");

// 只抓「真的會顯示成 emoji」的:預設 emoji 樣式(🚀✅)、或被 VS16 強制成 emoji(❤️)、
// 或 keycap(1️⃣)。刻意不用 Extended_Pictographic —— 它把 © ® ™ ↔ ✔ 這種預設文字樣式的
// 符號也算進去,會誤擋版權檔頭。ponytail: 漏掉「不帶 VS16 的裸 ❤」這種文字樣式 heart 可接受。
const EMOJI = /\p{Emoji_Presentation}|\p{Emoji}\u{FE0F}|\u{20E3}/u;

function deny(reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  }));
  process.exit(0);
}

function newContent(tool, input) {
  // 各 edit 工具放新內容的欄位不同;只取「將寫入」的部分。
  if (tool === "Write") return input.content || "";
  if (tool === "Edit") return input.new_string || "";
  if (tool === "MultiEdit") return (input.edits || []).map((e) => e.new_string || "").join("\n");
  return "";
}

// 找出 git 指令「實際會在哪個 repo 跑」的 cwd。
// 之前只在 hook 自己的 cwd 查分支,跨 repo(`cd 別的專案 && git commit`)時查到的是「當前
// session 專案」的分支,誤擋別的 repo 的 commit。這裡優先認指令裡的前導 `cd <dir>`,其次用
// payload.cwd(session cwd),最後才 fallback process.cwd()。
// ponytail: `cd` 解析是啟發式 —— 只認第一個 cd、支援引號與 ~;多段 cd / 變數展開不涵蓋,
//   查不到就 fallback,最壞退回舊行為,不會比原本更鬆。
function gitCwd(command, payloadCwd) {
  const base = payloadCwd || process.cwd();
  const m = /(?:^|&&|;|\|)\s*cd\s+(?:"([^"]+)"|'([^']+)'|([^\s&;|]+))/.exec(command || "");
  let dir = m ? (m[1] || m[2] || m[3]) : base;
  if (dir === "~" || dir.startsWith("~/")) dir = path.join(os.homedir(), dir.slice(1));
  return path.isAbsolute(dir) ? dir : path.resolve(base, dir);
}

function onMainBranch(cwd) {
  try {
    const b = execSync("git rev-parse --abbrev-ref HEAD", { cwd, encoding: "utf8" }).trim();
    return b === "main" || b === "master";
  } catch {
    return false; // 不是 git repo / 查不到 → 不擋
  }
}

function main(payload) {
  const tool = payload.tool_name;
  const input = payload.tool_input || {};

  // R1: emoji in content
  if (tool === "Write" || tool === "Edit" || tool === "MultiEdit") {
    if (EMOJI.test(newContent(tool, input))) {
      deny("R1: 內容含 emoji。dev-rule 紅線 R1 禁用 emoji(代碼/註釋/日誌),改成文字描述。");
    }
  }

  // R9: commit on main/master
  // (?!-) 排掉 plumbing 的 git commit-tree;裸 git commit / commit -m 仍命中。
  if (tool === "Bash" && /\bgit\s+commit\b(?!-)/.test(input.command || "") &&
      onMainBranch(gitCwd(input.command, payload.cwd))) {
    deny("R9: 不可在 main/master 直接 commit。開 feature branch:git switch -c feat/<name> 後再 commit。");
  }
}

let raw = "";
process.stdin.on("data", (c) => (raw += c));
process.stdin.on("end", () => {
  // --self-test: 不讀 stdin,跑內建檢查
  if (process.argv[2] === "--self-test") return selfTest();
  try { main(JSON.parse(raw || "{}")); } catch { /* 壞 payload → 放行,不擋正常流程 */ }
});

function selfTest() {
  const assert = (c, m) => { if (!c) { console.error("FAIL: " + m); process.exit(1); } };
  assert(EMOJI.test("ship it 🚀"), "應抓到 emoji");
  assert(EMOJI.test("done ✅"), "應抓到 checkmark emoji");
  assert(EMOJI.test("love ❤️"), "VS16 強制 emoji 應抓到");
  assert(!EMOJI.test("正常中文 normal code() // 註解"), "中文/代碼不該誤判");
  assert(!EMOJI.test("a -> b, x >= y"), "箭頭/符號不該誤判");
  // reviewer (Loop 2) 抓到的回歸:版權符號不是 emoji,不該擋
  assert(!EMOJI.test("Copyright (c) 2026 © ® ™ ℹ ✔"), "版權/文字樣式符號不該誤擋");
  // commit-tree 是 plumbing,不動分支,不該被當 R9 commit
  assert(!/\bgit\s+commit\b(?!-)/.test("git commit-tree abc"), "commit-tree 不該誤判");
  assert(/\bgit\s+commit\b(?!-)/.test("git commit -m x"), "正常 commit 仍該命中");
  assert(newContent("Write", { content: "x🎉" }).includes("🎉"), "Write 取 content");
  assert(newContent("Edit", { new_string: "y😀" }).includes("😀"), "Edit 取 new_string");
  // gitCwd: 前導 cd 要蓋過 session cwd(跨 repo 誤擋的根因)
  assert(gitCwd("cd /foo && git commit -m x", "/bar") === "/foo", "cd 絕對路徑優先於 payload.cwd");
  assert(gitCwd("git commit -m x", "/bar") === "/bar", "無 cd 時用 payload.cwd");
  assert(gitCwd('cd "/a b" && git commit', "/bar") === "/a b", "cd 帶引號路徑");
  assert(gitCwd("cd ~/proj && git commit", "/bar") === path.join(os.homedir(), "proj"), "cd 波浪號展開");
  assert(gitCwd("cd sub && git commit", "/bar") === "/bar/sub", "cd 相對路徑對 payload.cwd 解析");
  console.log("SELF-TEST PASS");
}
