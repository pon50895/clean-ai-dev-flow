# clean-ai-dev-flow

> **AI 平行開發的乾淨流程模板**。把 `dev-rule/` 當作最高指導原則（SSOT），讓 Claude / Gemini / Codex / 任何 LLM CLI 跨 session、跨機器、跨專案都遵循同一套規範。

---

## 這是什麼

一套從實戰衝刺中萃取出來的「AI 開發治理層」：一份可複製的規範目錄（`dev-rule/`）+ 一條標準開發流水線（調研→企劃→分派開發→驗證→開 PR）+ 兩條平行開發路徑（原生 subagent / tmux 多進程 fleet）。目標是讓任何專案在接上 AI coding agent 時，行為是**可預期、可稽核、可重現**的，而不是每個 session 各自腦補規則。

## 解決什麼問題

用 AI agent 平行開發常見的失敗模式：

- **沒有共同規則** → 每條 session 自己猜紅線，猜出 N 種版本
- **沒有分階段流程** → agent 一收到需求就直接改 code，跳過調研/規劃/驗證，品質全靠運氣
- **驗證等於自我驗證** → 寫代碼的 agent 順手說「測過了」，沒有 fresh-context 的第二意見
- **模型用錯地方** → 拿最貴的模型做機械改檔，或拿最便宜的模型做金流/安全判斷
- **平行開發互相覆寫** → 多個 agent 同時改共享檔案、搶 DB migration、worktree 髒了沒人收
- **權限設定每個新環境重來一次** → `.claude/settings.local.json` 是 gitignored，沒模板就卡在 permission prompt

這個 repo 把「怎麼解」寫成可複製的文件 + 腳本，不是每次重新發明。

---

## 核心概念

### 1. `dev-rule/` 是 SSOT（規範層）

所有 LLM CLI 啟動時先讀 `dev-rule/`，遇衝突以它為準。修改 `dev-rule/` 走 PR 標 `[DEV-RULE]`，人工 review 才能改「AI 的最高法」。核心文件：紅線（R1-R11）、GSD 四階段、平行開發 SOP、安全標準、模型調度、判斷 rubrics。

### 2. GSD 四階段循環（單一 feature 的最小流程）

任何一個改動都走 **Discuss → Plan → Execute → Verify**，跳過任一階段要說明理由。細節見 `dev-rule/GSD_WORKFLOW.md`。這是最小單位；下面的五階段流水線是把它套進「多模型分工」的外殼。

### 3. feature-pipeline 五階段（多模型分工的標準流水線）

把一個非 trivial feature 從想法推到「可上線的 open PR」，每階段用對的模型、守對的門檻：

| 階段 | 模型 | 產出 | Gate |
|---|---|---|---|
| 1. 調研 → 企劃 | 最高階模型 | `.planning/research/<TOPIC>.md` | user 拍板才進下一階 |
| 2. 企劃 → 開發計畫 | 中高階模型（指揮官） | `.planning/phases/<phase>/PLAN.md`（原子化 Task + PR 拆分） | 範圍與 PR 拆分給 user 過目 |
| 3. 依難度分派開發 | 按任務難度選（見 model-dispatch） | feature branch 上的小步 commit | 自帶測試（unit/scoped regression/build）三道門檻 |
| 4. 驗證 | 中/低階模型，fresh-context，不自驗 | 逐項附「檔案:行號」證據的 review | FAIL 打回第 3 階；PASS-with-nit 若是覆蓋缺口先補 |
| 5. 開 PR | 中高階模型（指揮官） | open PR（RTM 才開） | user 於 RTM 親自 merge；deploy 需另外明講 |

完整定義（含驗證的維度全集）在 `.claude/skills/feature-pipeline/SKILL.md`；套用方式見下方「如何在自己專案套用」。

### 4. 模型調度（model dispatch）

「指揮官不下場」——高階模型只花在「換便宜模型就掉品質」的判斷上；大量讀取、掃 repo、批次改檔、驗證一律派便宜模型。完整判準表、交辦三要素（目標動機/驗收條件/回報格式）、升降級規則見 `dev-rule/MODEL_DISPATCH.md`。

### 5. 判斷力 Rubrics（judgment rubrics）

把「何時升級模型」「何時算真的完成」「何時該停下問 user vs 自決」寫成弱模型可打勾執行的清單，每條附正例/反例。見 `dev-rule/JUDGMENT_RUBRICS.md`。這份是 model-dispatch 的判斷力配套，避免 agent 卡關時瞎猜。

### 6. 平行開發兩條路

| 路徑 | 何時用 | 需要 |
|---|---|---|
| **原生 subagent（推薦、預設）** | 純 Claude Code 工作流；同一 session 內平行不同 phase | 只要 `dev-rule/` + Claude Code CLI，零 tmux/colyn |
| **tmux 多進程 fleet（進階、選配）** | 真的要同時操控 Claude + Gemini + Codex 等多個獨立 LLM 供應商進程 | tmux + colyn + `scripts/colyn-roles/` |

兩條路都遵守同一份 `dev-rule/PARALLEL_DEV_SOP.md`：worktree 隔離、DB migration 序列化、共享檔案改動要通知、反 race 規則。大部分人停在第一條路就夠用。

---

## 目錄導覽

```
clean-ai-dev-flow/
├── CLAUDE.md                        Claude-native 精簡入口：四層 Loop 對應原生 Agent/hooks/skills
├── dev-rule/                        規範層（SSOT）——新專案要複製走的核心
│   ├── AI_INSTRUCTIONS.md             紅線 R1-R11、AI 執行協定
│   ├── GSD_WORKFLOW.md                Discuss→Plan→Execute→Verify
│   ├── MODEL_DISPATCH.md              模型調度判準表、交辦範本
│   ├── JUDGMENT_RUBRICS.md            升級/完成/該問 user 的判準清單
│   ├── PARALLEL_DEV_SOP.md            平行開發 SOP、db_lock、反 race 規則
│   ├── PARALLEL_DEVELOPMENT.md        worktree 隔離、共享改動例外
│   ├── SECURITY_STANDARDS.md          OWASP 對應 + 個資合規
│   ├── LEGAL_COMPLIANCE.md            Click-Wrap 強制閱讀機制
│   ├── UI_VISUAL_STANDARDS.md         深色主題、雙語切換標準
│   ├── WORKFLOW_PROTOCOLS.md          Context-Full Handoff、Review-Failure Loop
│   ├── TOOLS_INSTALL.md               外部工具矩陣（tmux fleet 用）
│   ├── PROJECT_BOARD_WORKFLOW.md      看板狀態機
│   ├── SECURITY_ROTATION_SOP.md       密鑰輪換
│   ├── HILL_CLIMBING_LOOP.md          自我改進迴圈協定
│   └── sample/                        .claude.local.json 權限基線範本
├── .claude/
│   ├── skills/feature-pipeline/       五階段流水線 skill 定義
│   ├── agents/reviewer.md             Loop 2 驗證用 subagent
│   └── hooks/                         PreToolUse hook：redline-guard(R1/R9)、git-readonly-approve
├── .githooks/                         pre-commit(gitleaks 秘密掃描)、pre-push(本機測試 gate)
├── scripts/colyn-roles/               tmux fleet 執行層（supervisor/reviewer/worker/tester 腳本）
├── GETTING_STARTED.md                 從 clone 到跑第一個 feature-pipeline 的最小路徑
├── PREREQUISITES.md                   完整前置需求 + 一鍵安裝腳本
└── LICENSE                            BSD 3-Clause
```

---

## 如何在自己專案套用

**先看 [`PREREQUISITES.md`](./PREREQUISITES.md) 把工具裝齊**，再照 [`GETTING_STARTED.md`](./GETTING_STARTED.md) 走完整一步步流程（含每步預期輸出）。這裡只列最短路徑：

```bash
# 1. 把規範層複製進你的專案
cp -r ~/Desktop/clean-ai-dev-flow/dev-rule ~/your-project/dev-rule

# 2. 啟用 git hooks（gitleaks 秘密掃描 + push 前本機測試）
cd ~/your-project
git config core.hooksPath .githooks
cp -r ~/Desktop/clean-ai-dev-flow/.githooks ./.githooks

# 3. 開一個 Claude session，第一句話叫它讀規範
claude
#   對 Claude 說：「先讀完 dev-rule/ 全部 .md，之後所有工作以 dev-rule 為最高準則。」
```

這樣就有 GSD 四階段 + 紅線 gate。要用完整五階段 feature-pipeline，再複製 `.claude/skills/feature-pipeline/` 過去（見 GETTING_STARTED §4）。要上多進程 tmux fleet，走 `scripts/colyn-roles/bootstrap-to-new-project.sh`（見下方「進階：tmux fleet」）。

### 進階：tmux fleet（多 LLM 供應商平行）

只有要同時操控 Claude + Gemini + Codex 等**多個獨立 OS 進程**才需要。一鍵路徑：

```bash
INIT_REPO=1 bash scripts/colyn-roles/bootstrap-to-new-project.sh ~/Desktop/<your-new-project>
```

自動複製 `dev-rule/` + `scripts/colyn-roles/`、替換權限白名單佔位符、（`INIT_REPO=1` 時）`git init` + 建 `.planning/`。完成後：

```bash
cd ~/Desktop/<your-new-project>
bash scripts/colyn-roles/install-tools.sh          # 裝 colyn/gsd/karpathy/gitnexus/gitleaks
bash scripts/colyn-roles/apply-claude-settings.sh  # 部署權限基線
bash scripts/colyn-roles/start.sh                  # 起 7-role tmux session
```

拓撲：`main:0` supervisor（高階模型，仲裁）、`main:1` dispatcher/alarm（監控 idle/CI/drift）、`main:2` reviewer（PR audit）、`main:3-6+` workers（寫碼）、`main:8` tester（中央測試序列化，避免多 worker 撞 docker）。角色 spec 見 `scripts/colyn-roles/role-*.md`。

故障排除、smoke test 清單見 `GETTING_STARTED.md` §5。

---

## 紅線（一定要看）

R1-R11 紅線的正本在 `dev-rule/AI_INSTRUCTIONS.md` §3（禁 emoji、禁全檔覆寫、禁在 `main` 直 commit、禁 `--no-verify` 等 11 條）。這裡不複製全表，避免兩份漂移——啟動時一律以 `dev-rule/` 為準。

PR 狀態 mutation（merge/close/approve）只 user 能做，worker/agent 不可碰。

---

## 規範文件索引

`dev-rule/` 全部都是 SSOT：

| 文件 | 內容 |
|---|---|
| `AI_INSTRUCTIONS.md` | 紅線 R1-R11、AI 執行協定 |
| `GSD_WORKFLOW.md` | Discuss→Plan→Execute→Verify、worktree 退場流程 |
| `MODEL_DISPATCH.md` | 模型調度判準、交辦三要素、升降級規則 |
| `JUDGMENT_RUBRICS.md` | 升級/完成/該問 user 的判準清單（正例/反例） |
| `PARALLEL_DEV_SOP.md` | 多 session 平行開發 SOP、權限白名單、衝突處理 |
| `PARALLEL_DEVELOPMENT.md` | 工作流隔離、worktree 命名、共享改動例外 |
| `SECURITY_STANDARDS.md` | OWASP Top 10 對應 + 個資合規 |
| `LEGAL_COMPLIANCE.md` | Click-Wrap 強制閱讀機制 |
| `UI_VISUAL_STANDARDS.md` | 深色主題、Glassmorphism、雙語切換 |
| `WORKFLOW_PROTOCOLS.md` | Context-Full Handoff、Review-Failure Loop |
| `TOOLS_INSTALL.md` | tmux fleet 用外部工具矩陣、安裝方式 |
| `PROJECT_BOARD_WORKFLOW.md` | 看板狀態機 |
| `SECURITY_ROTATION_SOP.md` | 密鑰輪換流程 |
| `HILL_CLIMBING_LOOP.md` | 自我改進迴圈協定 |
| `sample/README.md` | `.claude.local.json` 變更流程、加 allow/deny 判準 |

---

## 為什麼要把 dev-rule 抽成獨立專案

- 多 AI session 平行寫碼時，沒有 SSOT 規則 = 每條 session 自己腦補 = N 倍混亂
- 跨機器 / 跨專案 / 跨 LLM 供應商切換時，沒共通基礎 = 重新定義所有紅線
- `.claude/settings.local.json` 是 gitignored，每個新環境都要重建 = 沒模板就卡 permission prompt
- Spec drift / commit drift / WIP 互相覆寫都源自「沒 SSOT」

把 dev-rule 當基礎建設層獨立出來，新專案複製過去就能立刻擁有完整規範、流水線、權限基線。

---

## 授權

本 repo 採用 **BSD 3-Clause License**（見根目錄 [`LICENSE`](./LICENSE)）。

**可以自由：** 複製、修改、再散布（source 或 binary）；商業使用、整合進私有/閉源產品；fork 後改寫 dev-rule 自用。

**三條義務：**
1. 保留著作權聲明——散布 source 時附上 `LICENSE` 完整內容
2. 散布 binary 時也要在文件中重現著作權聲明與授權條款
3. 不得用作者名或本專案名背書衍生品（避免被誤認為官方版）

**免責：** 本專案 AS-IS 提供，作者對使用本流程造成的任何後果不負責任。請自行依「紅線」與 `GETTING_STARTED.md` 驗證後再投入正式專案。

> **dev-rule SSOT 的社群慣例（非授權強制）：** fork 後向上游回貢獻 dev-rule 變更，建議 PR 標題加 `[DEV-RULE]`，由人工 review。
