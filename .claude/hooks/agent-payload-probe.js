#!/usr/bin/env node
/**
 * agent-payload-probe.js — 一次性探針:實測 Agent tool 的 PreToolUse payload 真實形狀。
 *
 * 為什麼存在(2026-07-17):
 *   要做「派工 brief 缺紀律段就 deny」的 hook,必須知道 payload 裡 subagent 的 prompt 叫什麼。
 *   claude-code-guide 查了官方文件:matcher "Agent" 可行、tool_name = "Agent"、deny 會彈回模型 ——
 *   但**官方文件沒有公布 Agent tool 的完整 tool_input schema**,`prompt` 這個欄位名是它從
 *   權限語法 `Agent(agentName)` **推論**的,不是文件。
 *
 *   今晚已經栽過三次「把推論當事實」。所以先探針、拿到真實 key,再寫功能 hook。
 *   這就是 hook-selftest.sh 檔頭那條判讀鐵律的同一件事:
 *   **任何「X 存在/不存在」的斷語,先用同一方法驗一個已知的 X。**
 *
 * 行為:純記錄,絕不擋任何東西(exit 0 without verdict)。
 * 產出:.planning/learning/agent-payload-probe.jsonl(每次 Agent 派工記一行 payload 骨架)
 *
 * 用完即刪 —— 這不是常駐 hook。拿到 schema 後把它從 settings.json 移除。
 */

const fs = require('fs');
const path = require('path');

let raw = '';
try { raw = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }

try {
  const payload = JSON.parse(raw);

  // 記錄骨架:key 名 + 型別 + 長度,不記完整 prompt 內容(可能很長)
  const shape = (obj, depth = 0) => {
    if (depth > 2 || obj === null || typeof obj !== 'object') {
      return typeof obj === 'string' ? `string(${obj.length})` : typeof obj;
    }
    if (Array.isArray(obj)) return `array(${obj.length})`;
    const out = {};
    for (const [k, v] of Object.entries(obj)) out[k] = shape(v, depth + 1);
    return out;
  };

  const record = {
    ts: new Date().toISOString(),
    tool_name: payload.tool_name ?? '(absent)',
    top_level_keys: Object.keys(payload),
    tool_input_shape: payload.tool_input ? shape(payload.tool_input) : '(no tool_input)',
    // 前 80 字用來確認「這個欄位真的是 subagent 的 brief」
    prompt_head: typeof payload?.tool_input?.prompt === 'string'
      ? payload.tool_input.prompt.slice(0, 80)
      : '(tool_input.prompt 不是 string —— 推論錯了)',
  };

  const out = path.join(__dirname, '..', '..', '.planning', 'learning', 'agent-payload-probe.jsonl');
  fs.appendFileSync(out, JSON.stringify(record) + '\n');
} catch { /* 探針故障絕不擋工作 */ }

process.exit(0);
