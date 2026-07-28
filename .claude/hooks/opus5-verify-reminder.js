#!/usr/bin/env node
/**
 * opus5-verify-reminder.js — Stop hook。
 *
 * 當 harness 跑在 opus-5 profile(dev-rule/HARNESS_MODEL = opus-5)時,收尾前注入一條
 * 提醒:Opus 5 產出須附抽驗存在性證據。這是 R4 安全網的程序性一半——Opus 5 曾實證
 * 捏造 file:line 與假實測資料,但「不造無法驗證的自動稽核機器」(#2558 教訓),故用提醒 + 程序,
 * 不做自動 deny。非 opus-5 profile 直接放行。自身故障絕不擋收尾。
 */
const fs = require('fs');
const path = require('path');

try {
  const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const marker = fs.readFileSync(path.join(root, 'dev-rule', 'HARNESS_MODEL'), 'utf8').trim();
  if (marker !== 'opus-5') process.exit(0);

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'Stop',
      additionalContext:
        '[opus-5 profile] 本 harness 跑在 Opus 5。收貨 / 收尾前確認:產出裡每個「檔案:行號」、' +
        '每筆「實測數字」至少抽驗一筆真實存在(ls / grep / 打開該行);發現捏造一筆整份作廢重驗。' +
        '(dev-rule/MODEL_DISPATCH.md §1.1 R4 + §5 抽驗存在性)',
    },
  }));
} catch { /* 讀不到 marker 或故障不擋收尾 */ }

process.exit(0);
