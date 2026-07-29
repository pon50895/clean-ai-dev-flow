#!/usr/bin/env node
/**
 * opus5-verify-reminder.js — Stop hook。
 *
 * 情境:Opus 5 在 user 這邊屬「未驗證階段」——可以用,但產出要當高風險來源加倍查。
 * 本 hook 從 transcript 讀當前 session 真實模型(CLI 寫入、非模型自報,Opus 5 捏造不了);
 * **只有 session 真的是 Opus 5 才注入抽驗提醒,其他模型(4.8 等)一律完全 no-op**——
 * 4.8 的既有開發流程零干擾。自身故障絕不擋收尾。
 *
 * 為什麼是提醒不是自動稽核:Opus 5 曾實證捏造 file:line / 假實測,但「不造無法驗證的
 * 自動稽核機器」,故用程序性提醒 + fresh-agent 二驗,不做自動 deny。
 */
const fs = require('fs');

function currentSessionModel(transcriptPath) {
  if (!transcriptPath) return null;
  try {
    const lines = fs.readFileSync(transcriptPath, 'utf8').split('\n');
    for (let i = lines.length - 1; i >= 0; i--) {
      if (!lines[i].trim()) continue;
      let o; try { o = JSON.parse(lines[i]); } catch { continue; }
      if (o && o.type === 'assistant' && o.message && typeof o.message.model === 'string') return o.message.model;
    }
  } catch { /* 讀不到 = 回 null = 不打擾 */ }
  return null;
}

let payload = {};
try { payload = JSON.parse(fs.readFileSync(0, 'utf8')); } catch { process.exit(0); }

if (currentSessionModel(payload.transcript_path) !== 'claude-opus-5') process.exit(0);

process.stdout.write(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: 'Stop',
    additionalContext:
      '[Opus 5 未驗證階段] 本 session 跑在 Opus 5。收貨 / 收尾前把它的產出當高風險來源:' +
      '每個「檔案:行號」、每筆「實測數字」至少抽驗一筆真實存在(ls / grep / 打開該行);' +
      '關鍵結論派 fresh-context agent 二驗;發現捏造一筆整份作廢重驗。',
  },
}));
process.exit(0);
