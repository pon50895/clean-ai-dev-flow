# CLAUDE.md — Claude-native 精簡入口

> 這份取代 `scripts/colyn-roles/` 整套 tmux 編排。同樣的四層 Loop，改用 Claude Code
> 內建原語(Agent tool / subagent / hooks / skills),不需要 tmux、colyn、worktree workspace。
> 規則(紅線/SOP/安全)仍以 `dev-rule/` 為 SSOT — 啟動先讀,衝突以 dev-rule 為準。

## 啟動序列
1. 讀 `dev-rule/AI_INSTRUCTIONS.md`(紅線 R1-R11)+ `dev-rule/GSD_WORKFLOW.md`(Discuss→Plan→Execute→Verify)
2. 衝突一律以 `dev-rule/` 為準;改 dev-rule 走 PR 標 `[DEV-RULE]` + 人工 review

## 四層 Loop，用 Claude 原生做

**Loop 1 — Agent（寫碼）**
> 直接做。需要平行不同 phase 時,用 `Agent` tool 一次 spawn 多個 subagent(同一 session,無 tmux)。
> 各 subagent 指定合適 model(雜活 haiku/sonnet、難仲裁 opus)。

**Loop 2 — Verification（驗證)**
> 寫的人 ≠ 驗的人。code 寫完,spawn 一個 reviewer subagent 照 `dev-rule/` 的 Karpathy lens + OWASP rubric 打分,
> 或跑 `/code-review`。確定性 grader(測試/lint)掛 PostToolUse / pre-commit hook,不必用 LLM。
> 沒過 → 把 feedback 餵回去重做。

**Loop 3 — Event-Driven（事件驅動)**
> 取代 dispatcher 的 poll:
> - 自動觸發 → `.claude/hooks/`(SessionStart 載 context、Stop 收尾檢查、PostToolUse 擋紅線)
> - 排程 → `/schedule`(cron cloud agent)或 `/loop <interval>`
> - 敏感操作前人類確認 → hook 攔截 + 詢問

**Loop 4 — Hill Climbing（自我改進)**
> 跑 `scripts/colyn-roles/retro.sh` 收割 `.planning/*.md` 的失敗訊號 → 指出該改的 harness 檔
> → 寫成 `[DEV-RULE]` PR → **人工 review 才 merge**。協定見 `dev-rule/HILL_CLIMBING_LOOP.md`。
> self-improving 不等於 self-deploying。

## 人類閘門(每層都有)
Loop 1 敏感操作前確認 · Loop 2 人可當 grader · Loop 3 審批產出 · Loop 4 harness 改動必過 PR review。

## 什麼時候才回去用 §2 的 tmux fleet
只有當你真的要「跨多個 LLM 供應商(Claude + Gemini + Codex)平行」、或要 5-7 個**獨立 OS 進程**互不共享 context 時。
純 Claude 工作流不需要 — 上面的 Agent tool 已經給你平行 subagent,且省掉 tmux/colyn/workspace/模型對齊那一整套故障面。
