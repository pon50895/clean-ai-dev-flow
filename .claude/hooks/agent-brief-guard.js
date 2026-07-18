#!/usr/bin/env node
/**
 * agent-brief-guard.js — 派工 brief 缺紀律段就 deny,彈回模型補上。
 *
 * 為什麼存在:
 *   一次檢討提出「派工 brief 加固定紀律段」,寫進報告後沒有下文。
 *   兩天後,指揮官派 agent 時 brief 寫了「禁止碰 prod」「不要跑全套測試」「不要碰主樹」——
 *   **就是漏了「rm 是使用者地盤」**。agent 跑了 rm、撞 guard、使用者被彈窗。
 *   那條紀律從來沒進過任何範本,每次靠指揮官當下想起來,而那次沒想起來。
 *
 *   事後稽核那次檢討的五項提案:**落地 2/5,而落地的兩項全是機器 gate**;
 *   三項 prose 至今沒寫進任何目標檔 —— 而系統裡沒有任何東西會發現這件事。
 *   結論:**沒有 owner 的 prose 會蒸發。規則會在壓力下被跳過,機制不會。**
 *   所以把「範本」升級成 hook。這是同一個提案的第二次嘗試,這次是機制。
 *
 * payload 形狀(用 agent-payload-probe.js 實測,不是從文件推論 ——
 * 官方文件沒有公布 Agent tool 的 tool_input schema):
 *   tool_name = "Agent"
 *   tool_input = { description: string, prompt: string, subagent_type: string }
 *
 * 行為:
 *   - 只擋「有寫入意圖」的 brief(提到 worktree / commit / push / Edit / Write / 改)
 *   - 唯讀 agent(Explore / 稽核 / 查證)一律放行 —— 無差別擋會製造摩擦
 *   - deny(不是 ask)-> 彈回模型自己補,**user 零彈窗**
 *   - 自身故障絕不擋工作
 */

const fs = require('fs');
const path = require('path');

let raw = '';
try { raw = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }

let payload;
try { payload = JSON.parse(raw); } catch { process.exit(0); }

if (!payload || payload.tool_name !== 'Agent') process.exit(0);

const prompt = (payload.tool_input && payload.tool_input.prompt) || '';
if (!prompt || typeof prompt !== 'string') process.exit(0);

// --- 寫入意圖偵測:沒有寫入意圖的 agent(Explore/稽核/查證)不需要這段 ------------
const WRITE_INTENT = /\bworktree\b|\bcommit\b|\bpush\b|\bbranch\b|\bEdit\b|\bWrite\b|修改|改寫|實作|落地/;
if (!WRITE_INTENT.test(prompt)) process.exit(0);

// --- 紀律段標記:範本的 heading 就是標記 ----------------------------------------
// 用 heading 不用個別條文 —— 條文會演化,heading 穩定;而且它逼人整段複製而非挑著抄。
const DISCIPLINE_MARKER = /##\s*工作區與紀律/;
if (DISCIPLINE_MARKER.test(prompt)) process.exit(0);

// --- deny:彈回模型,user 完全不會看到這個 --------------------------------------
const TEMPLATE = 'scripts/colyn-roles/briefs/AGENT_BRIEF_DISCIPLINE.md';
const reason =
  `agent-brief-guard: 這份 brief 有寫入意圖(worktree/commit/push/實作),但缺少必要的紀律段。\n` +
  `\n` +
  `2026-07-16 提過「派工 brief 固定紀律段」(P4),兩天沒落地 -> 07-17 派工漏寫「rm 是 user 地盤」\n` +
  `-> agent 跑 rm -> user 被彈窗。所以這條現在是機器 gate,不是提醒。\n` +
  `\n` +
  `把 ${TEMPLATE} 裡的整段「## 工作區與紀律(嚴格)」複製進 brief(依情境刪不適用的行),再派一次。\n` +
  `\n` +
  `該段至少要涵蓋:worktree 邊界(禁碰主樹/sibling)、禁 rm、禁 git stash/reset --hard/push --force、\n` +
  `補 commit 不用 --amend、禁全套 jest(本機必 OOM)、輸出寫檔不用 pipe tail、prod 唯讀、\n` +
  `R1 無 emoji、i18n、陽性對照鐵律、完成的定義(commit+push 不開 PR)。\n` +
  `\n` +
  `唯讀 agent(Explore/稽核/查證)不需要這段 —— 本 guard 只在偵測到寫入意圖時觸發。`;

process.stdout.write(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    permissionDecision: 'deny',
    permissionDecisionReason: reason,
  },
}));

// 記一筆到 gate-fires,週循環讀它(規則有沒有被內化的可否證數據)
try {
  const ledger = path.join(__dirname, '..', '..', '.planning', 'learning', 'gate-fires.jsonl');
  fs.appendFileSync(ledger, JSON.stringify({
    ts: new Date().toISOString(),
    verdict: 'deny',
    why: 'agent brief 缺紀律段',
    cmd: `Agent(${payload.tool_input.subagent_type}): ${payload.tool_input.description}`.slice(0, 120),
  }) + '\n');
} catch { /* ledger 故障不擋工作 */ }

process.exit(0);
