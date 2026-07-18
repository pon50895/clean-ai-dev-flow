# Development Rules — SSOT for AI Parallel-Dev

本目錄是 **clean-ai-dev-flow** 的規範層 SSOT，給任何 AI 助手（Claude / Codex / Gemini / 任何 LLM CLI）與人類開發者讀。所有提交前必須對照本目錄文件自我檢查。

> 修改本目錄任何檔案，PR 必標 `[DEV-RULE]`，由人工 review。

---

## 1. 核心開發流程 (GSD Workflow)

所有功能開發必須遵循以下四步驟循環（細節見 [`GSD_WORKFLOW.md`](./GSD_WORKFLOW.md)）：

1. **討論 (Discuss)**：確認業務邏輯、UI 需求、合規約束。AI 助手必須挑戰潛在風險預設，不假設、不腦補。
2. **規劃 (Plan)**：建立 `.planning/` 下的 PLAN.md，定義原子化任務與成功標準。
3. **執行 (Execute)**：精確修改、原子化 commit；嚴禁全文件覆蓋。
4. **驗證 (Verify)**：強制執行 P0 檢核（功能 + 視覺 + 安全）。

---

## 2. P0 品質標準

任何 commit 必須通過：

- **功能連通性**：API、資料庫、關鍵頁面回傳 `200 OK`
- **視覺一致性**：符合本專案 UI 標準（見 [`UI_VISUAL_STANDARDS.md`](./UI_VISUAL_STANDARDS.md)）
- **法律合規**：涉及註冊／同意流程必須走強制閱讀 + `acceptedLegal` 校驗（見 [`LEGAL_COMPLIANCE.md`](./LEGAL_COMPLIANCE.md)）

---

## 3. 溝通與代碼規範

- **無 Emoji 政策**：嚴禁在代碼、註釋、日誌、回覆中使用 Emoji
- **原子化提交**：commit 必須清晰且不含測試殘留物
- **唯一事實來源 (SSOT)**：法律文本、系統設定等共享資料統一存放（建議路徑：`packages/shared-content/` 或專案約定位置）

---

## 4. 分支與 Worktree 策略

跨模組、含 schema migration、第三方整合等高風險功能 **必須切 worktree**。
完整規範與標準指令見 [`GSD_WORKFLOW.md §4`](./GSD_WORKFLOW.md#4-branch--worktree-策略-branch--worktree-policy)。

---

## 5. 資訊安全準則

所有提交前必須對照 [`SECURITY_STANDARDS.md`](./SECURITY_STANDARDS.md) 進行 OWASP Top 10 自我檢查。涵蓋存取控制、加密、注入、SSRF、設定錯誤、登入認證、Token 與審計日誌等強制規範。

密鑰輪換流程見 [`SECURITY_ROTATION_SOP.md`](./SECURITY_ROTATION_SOP.md)。

---

## 6. AI 平行開發 SOP

多 AI session 平行寫碼的協作協議：

- [`PARALLEL_DEV_SOP.md`](./PARALLEL_DEV_SOP.md) — 平行開發 SOP、權限白名單、衝突處理
- [`PARALLEL_DEVELOPMENT.md`](./PARALLEL_DEVELOPMENT.md) — worktree 命名、共享改動例外、反 race 原則
- [`WORKFLOW_PROTOCOLS.md`](./WORKFLOW_PROTOCOLS.md) — Context-Full Handoff + Review-Failure Loop
- [`AI_INSTRUCTIONS.md`](./AI_INSTRUCTIONS.md) — AI 助手執行協定、紅線清單、對話臨界壓縮
- [`PROJECT_BOARD_WORKFLOW.md`](./PROJECT_BOARD_WORKFLOW.md) — GitHub Project Board 對齊協議
- [`DATA_SAFETY_AND_TESTING.md`](./DATA_SAFETY_AND_TESTING.md) — 資料安全紅線(破壞性測試不可碰共用 DB)、test-DB guard、備份強制、dev 容器陷阱、migration 安全、測試分層
- [`SKILL_OPTIMIZATION.md`](./SKILL_OPTIMIZATION.md) — 用 Microsoft SkillOpt 以資料驅動方式優化可複用 skill 文字(trajectory + validation-gated)

AI 角色定義與行為規範：
- [`ai-architecture/COORDINATOR.md`](./ai-architecture/COORDINATOR.md) — 仲裁者
- [`ai-architecture/SENTINEL.md`](./ai-architecture/SENTINEL.md) — 監控守望者
- [`ai-architecture/REVIEWER.md`](./ai-architecture/REVIEWER.md) — 代碼審查者
- [`ai-architecture/COMMAND_POLICY.md`](./ai-architecture/COMMAND_POLICY.md) — sentinel 命令分類 SSOT
- [`ai-architecture/SKILLS_REQUIRED.md`](./ai-architecture/SKILLS_REQUIRED.md) — 各角色必備 skills

---

## 7. 工具鏈

[`TOOLS_INSTALL.md`](./TOOLS_INSTALL.md) — 平行開發 SOP 依賴的外部工具（colyn、gsd、karpathy-guidelines、GitNexus）安裝方式與檢查邏輯。

執行層腳本見 `scripts/colyn-roles/`（不在 SSOT 內，是規範的執行工具）。

---

## 8. Sample 配置

[`sample/.claude.local.json`](./sample/.claude.local.json) — Claude Code 權限基線範本，部署到每個 worktree 的 `.claude/settings.local.json`。三層權限：allow（自動放行）/ ask（每次跳問）/ deny（硬擋）。

---

*本目錄為通用 AI 平行開發治理層。專案專屬的業務語境、紅線重申請寫在根目錄 `CLAUDE.md`，不要污染本目錄。*

---

## 三層升級為四層 (added 2026-05-08)

### R-Coord 鎖層 (新增)

新增第四層：**R-coord 資源協調**。在 fleet 跨 worktree 平行開發時，4 種稀缺資源的協調機制 (R1 docker / R2 db schema / R3 arbiter / R4 user permission)。

| 層 | 內容 | 觸發 |
|----|------|------|
| **規範層** `dev-rule/` | 紅線 / SOP / 標準 | 啟動讀 |
| **執行層** `scripts/colyn-roles/` | tmux 7-role 編排 + role-tester / role-dispatcher | 部署使用 |
| **設定層** `dev-rule/sample/.claude.local.json` | sprint-mode 權限 baseline | 部署到 worktree |
| **R-Coord 層** `scripts/colyn-roles/{db,docker}-coord.sh` + `permission-queue-poll.sh` | 4 scarce resource 序列化 | 跨 worker 自動 |

### 關鍵 scripts
- `scripts/skill.sh` — Trusted Execution Path 入口 (allowlist `bash skill.sh *` 收斂 100+ patterns)
- `scripts/colyn-roles/db-coord.sh` — R2 schema 鎖
- `scripts/colyn-roles/docker-coord.sh` — R1 docker 鎖
- `scripts/colyn-roles/permission-queue-poll.sh` — R4 user permission async
- `scripts/colyn-roles/sync-claude-settings.sh` — symlink settings 跨 worktree
