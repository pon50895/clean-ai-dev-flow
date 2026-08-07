#!/usr/bin/env node
// emoji-reminder -- Stop hook.
//
// 為什麼:R1「無 emoji 於任何地方」含「回覆本身」,但 scripts/emoji-scan.mjs(pre-commit)
// 只掃 commit 的檔案,攔不到「對話回覆裡的 emoji」—— 那是輸出層,只有 Stop hook 掃得到。
// 仿 over-ask-reminder.js / severity-claim-reminder.js:掃最後一則訊息,用與 emoji-scan.mjs
// 相同的 Unicode Extended_Pictographic 判定(已校準:不誤中箭頭 -> / 破折號 -- / box-drawing),
// 命中就注入提醒。
//
// 硬約束:提醒不是 deny。永遠 exit 0,絕不阻斷。全 try/catch,hook 自身故障不得影響任何事。

const fs = require('fs');

const EMOJI_RE = /\p{Extended_Pictographic}/u; // 同 scripts/emoji-scan.mjs:95

function getLastAssistantMessageText(transcriptPath) {
  if (!transcriptPath || !fs.existsSync(transcriptPath)) return null;

  const lines = fs.readFileSync(transcriptPath, 'utf8').split('\n').filter(Boolean);

  for (let i = lines.length - 1; i >= 0; i -= 1) {
    let rec;
    try { rec = JSON.parse(lines[i]); } catch { continue; }

    if (rec.type === 'assistant' && rec.message) {
      const content = rec.message.content;
      if (typeof content === 'string') return content;
      if (Array.isArray(content)) {
        return content
          .filter((c) => c && c.type === 'text')
          .map((c) => c.text)
          .join('\n');
      }
    }
  }
  return null;
}

try {
  const payload = JSON.parse(fs.readFileSync(0, 'utf8'));
  const text = getLastAssistantMessageText(payload.transcript_path);

  if (typeof text === 'string' && text.length > 0 && EMOJI_RE.test(text)) {
    process.stdout.write(
      '提醒:R1 —— 回覆裡出現 emoji。R1 禁 emoji 於任何地方(回覆 / code / 註釋 / 日誌 / commit / PR),改用文字描述。\n'
    );
  }
} catch { /* 提醒故障絕不擋工作 */ }

process.exit(0);
