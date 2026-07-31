#!/usr/bin/env node
/**
 * over-ask-reminder.js — Stop hook 提醒:把 in-scope 動作包成問句丟回 user 了嗎。
 *
 * 為什麼存在:over-ask(該自決卻回頭問)是 agent 最常見的判斷型壞習慣之一。它發生在
 * 「輸出層」——不是某個工具呼叫,是最後一段話的措辭,所以 PreToolUse guard 攔不到。
 * 唯一的攔截點是 Stop hook 掃最後一則訊息(同 opus5-verify-reminder.js 的機制)。
 * 「知道規則」不夠,判斷型行為需要執行時的檢查點。
 *
 * 行為:掃主對話最後一則訊息,窄 regex 命中「把該自己做的 in-scope 動作當選項丟回 user」
 * 的句型(要我…嗎/還是你…/要不要我/現在做還是 backlog/我先…還是…)時,注入一行提醒。
 * 提醒同時區分兩種正確處理:in-scope 執行自決直接做;重大建議正式攤開,別用順帶問法帶過。
 *
 * 硬約束:這是提醒不是 deny。永遠 exit 0,絕不阻斷任何流程。全 try/catch,
 * hook 自身故障不得影響任何事。
 *
 * 已知代價(刻意接受,不擴大 regex):會誤中「合法的高風險/scope/商業取捨」問句。
 * 命中只多一行提醒、非 deny,誤中代價可接受;擴大詞表是明確禁止的方向。
 */

const fs = require('fs');

// 窄句型:第一人稱行動 offer 當成問句 / 我-做 vs user-做或延後 的二選一。
const OVER_ASK_PATTERNS = [
  /要我.{0,30}(嗎|還是|\?|？)/,
  /要不要我/,
  /需要我.{0,20}(嗎|還是|\?|？)/,
  /還是你(來|自己|要|先)/,
  /(現在做|先做|現在派|先派).{0,15}(還是|backlog|之後再|等你)/,
  /我(先|直接|來|這就).{0,20}還是/,
];

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

  if (typeof text === 'string' && text.length > 0) {
    const hit = OVER_ASK_PATTERNS.some((re) => re.test(text));

    if (hit) {
      process.stdout.write(
        '提醒:偵測到把動作包成問句丟回 user(要我…嗎/還是你…/現在做還是 backlog)。分兩種處理,別混:\n' +
        '(1) in-scope 執行(順序、複驗、建置、backlog-vs-now)→ 自決並直接發工具呼叫,不 say-vs-do;指定範圍做完就收尾停手,不無限擴張。\n' +
        '(2) 重大建議/決策(毀滅性或高風險指令、scope 擴張、架構或商業戰略)→ 不是不提,是要正式攤開(利害 + 取捨 + 建議),不能用順帶一句的問法帶過。\n'
      );
    }
  }
} catch { /* 提醒故障絕不擋工作 */ }

process.exit(0);
