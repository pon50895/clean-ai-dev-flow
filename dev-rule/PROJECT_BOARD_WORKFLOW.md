# GitHub Project Board 工作流程 (Project Board SOP)

> 本文件給任何 AI agent（Claude / Codex / Gemini / 其他 LLM CLI）讀，定義「動工前對齊 Project Board」的通用協議。
> SSOT 順序：**git PR > Project 看板 > .planning/PROJECT.md / ROADMAP.md**
> 修改本檔走 PR 標 `[DEV-RULE]`。

---

## 0. 前置條件

本協議假設專案有一個 GitHub Project（Projects v2，新版）作為唯一的 phase / task 看板。

設定變數（替換成你的專案）：

```bash
GH_USER="<your-github-user>"        # GitHub 帳號或組織
PROJECT_NUMBER="<N>"                # GitHub Project 編號（URL 結尾數字）
PROJECT_OWNER_FLAG="--owner $GH_USER"  # user-scope；組織則 --owner <org-name>
```

> **沒有 Project Board 的專案**：可跳過本檔，回退到只用 `.planning/PROJECT.md` 當 SSOT；但**動工前對齊**的精神（§1）仍適用，靠 `.planning/PROJECT.md` 的 `[ ] / [x]` 與 `git branch --list` 取代。

---

## 1. 每個 AI session 開頭三步（強制）

無論任何 AI agent 開新對話，**動工前**必跑三步並把結果回覆給用戶：

```bash
# (1) 看 In Progress 有誰在做（避免撞 sibling worktree）
gh project item-list "$PROJECT_NUMBER" $PROJECT_OWNER_FLAG --format json --limit 50 \
  --jq '.items[] | select(.status=="In Progress") | {title, content: .content.title, url: .content.url}'

# (2) 看本 worktree 與 main 的距離
git -C "$(pwd)" log --oneline origin/main..HEAD
git -C "$(pwd)" status --short

# (3) 看 sibling worktree 健康度（可能撞檔的對象）
git worktree list
```

**回覆格式範例**：
```
看板 In Progress: <Phase A> (issue #N1), <Phase B> (issue #N2)
本分支領先 main: 2 commits（feat/...）
Sibling worktree: <wt-A> / <wt-B>（無撞檔風險）
建議下一步: <根據 .planning/PROJECT.md 與看板現況>
```

---

## 2. 何時必須更新看板

| 觸發事件 | 看板動作 | 自動 / 手動 |
|----------|----------|-------------|
| 開新 phase / wave | 開 issue（`label: phase, P0, planned`），手動加到看板 → Todo | 手動 |
| 開 feature branch 開工 | 把對應 issue 拖到 In Progress | 手動 |
| 提 PR 帶 `Closes #N` | merge 後 issue 自動關閉，看板自動移到 Done | 全自動 |
| 提 PR 不帶 `Closes #N`（罕見） | merge 後手動 `gh project item-add` + 標 Done | 手動 |
| 卡外部依賴（第三方服務、SaaS） | 加 label `Blocked` + `@<service>` | 手動 |
| 依賴解除 | 移回 In Progress 或 Done | 手動 |
| 任何 phase 狀態變動 | 同步看板 + 更新 `.planning/PROJECT.md` `[x]` | 手動 |

**禁止**：
- PR body 漏寫 `Closes #N`（會留 ghost card 永不更新）
- 看 `.planning/PROJECT.md [x]` 推斷 phase 完成（須查 `gh issue view <N> --json state` 才準）
- 同一 phase 在兩個 worktree 同時動工（branch name 視為 lock）
- 改 sibling worktree 的 commit（違反反 race rule）

---

## 3. 標準 AI 請求話術（用戶複製即可）

### 3.1 開工前對齊
```
看一下目前看板 In Progress 有哪些，避免我撞 sibling worktree
```
AI 必跑：`gh project item-list "$PROJECT_NUMBER" --owner "$GH_USER" --format json --jq '.items[] | select(.status=="In Progress")'`

### 3.2 開新 phase / 工作項
```
我要開始做 Phase X.Y <簡述>，幫我：
1. gh issue create --label phase,P0,planned
2. 加到 Project board → Todo
3. 拖到 In Progress
4. 開 feature branch <type>/<scope>-<desc>
```

### 3.3 提 PR 時自動串看板
```
幫我提 PR，PR body 必須含 Closes #<issue-number>
```
AI 必檢查：commit 訊息或 PR body 至少一處含 `Closes #N`，否則要求補 issue number 才開 PR。

### 3.4 PR 已 merged 但沒上看板（補救）
```
PR #<N> 已經 merged 了但沒進看板，幫我補：
1. 開 retroactive issue（label: phase 或 chore，視類型）
2. issue body 第一行寫「Tracks already-merged PR #<N>」
3. gh project item-add 到看板並直接標 Done
4. 在 PR comment 加註 issue 連結
```

### 3.5 卡外部依賴
```
這個 PR / phase 卡 <service-name>，幫我：
1. PR / issue 加 label Blocked + @<service>
2. 看板拖到 Blocked column（若有）或留 In Progress + label
3. 同步寫一筆到 .planning/audit/PENDING_EXTERNAL.md
```

### 3.6 Session 結束 / 換 AI agent 交接
```
我要切到 codex / gemini，幫我寫 DEVELOPER_HANDOFF.md：
1. 當前看板 In Progress / Blocked 列表
2. 各 worktree 分支 + 未 commit WIP
3. 已 merged 但漏進看板的 PR 清單
4. 下一步建議（依據 .planning/PROJECT.md 優先順序）
```

---

## 4. PR `Closes #N` 撰寫規範

PR body 必須在**第一段**就出現 `Closes #N` 才能保證 GitHub 自動處理：

```markdown
Closes #<issue-number>

## Summary
<本 PR 做了什麼>

## Test plan
- [x] 單元
- [x] regression（受影響 spec）
- [x] build
```

**多 issue 寫法**：`Closes #11, #12, #13`（GitHub 接受逗號分隔）

**部分完成寫法**（不關 issue，但連結）：用 `Refs #N` 而非 `Closes #N`

**治理 / 純文件 PR**（無 underlying issue）：commit 訊息加 tag `[DEV-RULE]` / `[CLAUDE.md]` / `[OPENSPEC]`，merge 後依 §3.4 補 retroactive issue。

---

## 5. 取得 Project 欄位 ID（給 `gh project item-edit`）

不同專案的 project ID / status field ID / option ID 不同，第一次設定先抓出來：

```bash
# 取得 project node ID（PVT_kwH... 開頭）
gh project list $PROJECT_OWNER_FLAG --format json \
  --jq '.projects[] | select(.number==<N>) | {id, title}'

# 取得欄位 ID 與 Status options
gh project field-list <N> $PROJECT_OWNER_FLAG --format json \
  --jq '.fields[] | select(.name=="Status") | {id, options}'
```

把抓到的 ID 寫進專案根目錄 `.planning/PROJECT_BOARD.env`（gitignored 或 committed 視團隊決定）：

```bash
PROJECT_ID=PVT_kwHO...
STATUS_FIELD_ID=PVTSSF_lAHO...
STATUS_TODO=<id>
STATUS_IN_PROGRESS=<id>
STATUS_DONE=<id>
```

之後 AI 跑 `gh project item-edit` 時 source 這支檔案讀變數，不要把 ID 硬編進規範文件。

---

## 6. AI 自我檢核清單（每個 PR 動作前必過）

- [ ] Session 開頭跑過 §1 三步
- [ ] 動工前看過 In Progress column，無撞 sibling worktree
- [ ] commit message 與 PR body 都標 phase（如 `[Phase 09]`）或治理 tag（`[DEV-RULE]` / `[CLAUDE.md]`）
- [ ] PR body 第一段含 `Closes #N`（除非確定無對應 issue）
- [ ] merge 後若無 `Closes`，主動補 retroactive issue + 上看板
- [ ] 卡外部依賴 → 同步寫 `.planning/audit/PENDING_EXTERNAL.md`
- [ ] Session 結束前更新 `DEVELOPER_HANDOFF.md`

違反任何一項：在回覆中明示原因 + 提案補救動作，不偷偷略過。

---

## 7. 跨 AI Agent 共用責任 (Multi-Agent Mandate)

本檔對 **Claude / Codex / Gemini / 任何 LLM CLI** 一視同仁。
切換 AI agent 不重置義務 — 看板狀態必須在 AI handoff 時保持與 git 真相同步。

| Agent | 必讀 | 必做 |
|-------|------|------|
| Claude Code | `CLAUDE.md` + 本檔 | §1 三步 + §6 檢核清單 |
| Codex | `AGENTS.md`（若有）+ `CLAUDE.md` + 本檔 | 同上 |
| Gemini | `GEMINI.md`（若有）+ `CLAUDE.md` + 本檔 | 同上 |

**真相來源**：永遠以 `gh issue view` / `gh pr view` / `gh project item-list` 為準，
不信任任何 .md 檔的 `[x]` markers。

---

## 8. 相關文件

| 文件 | 角色 |
|------|------|
| `dev-rule/PROJECT_BOARD_WORKFLOW.md`（本檔） | SOP + AI 請求話術 |
| `.planning/PROJECT.md` | 當前 milestone 與 phase 列表（補充看板用，非 SSOT）|
| `.planning/PROJECT_BOARD.env` | 專案層 project ID / field ID 環境變數 |
| `dev-rule/PARALLEL_DEVELOPMENT.md` | 多 worktree 反 race 原則 |
| `dev-rule/WORKFLOW_PROTOCOLS.md` | 跨 session 協作 protocol（context handoff、review failure loop）|
