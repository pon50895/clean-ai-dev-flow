# GitHub Projects 看板工作流程 (Project Board SOP)

> 本文件補足 `OPENSPEC.md §22.2` 的「**操作面 SOP + AI 請求話術**」。
> 規範層級在 OPENSPEC，本檔為日常執行手冊。
> SSOT 順序：**git PR > Project 看板 > PROJECT.md / ROADMAP.md**

**Project URL**: (填寫：GitHub Project 看板 URL)

---

## 0. 每個 Claude / Codex / Gemini Session 開頭三步（強制）

無論任何 AI agent 開新對話，**動工前**必跑三步並把結果回覆給用戶：

```bash
# (1) 看 In Progress 有誰在做（避免撞 sibling worktree）
gh project item-list 1 --owner pon50895 --format json --limit 50 \
  --jq '.items[] | select(.status=="In Progress") | {title, content: .content.title, url: .content.url}'

# (2) 看本 worktree 與 main 的距離
git -C "$(pwd)" log --oneline origin/main..HEAD
git -C "$(pwd)" status --short

# (3) 看 sibling worktree 健康度（可能撞檔的對象）
git worktree list
```

**回覆格式範例**：
```
看板 In Progress: Phase 09 (issue #69), Phase 14 (issue #74)
本分支領先 main: 2 commits（feat/...）
Sibling worktree: <project>-phase09-xxx / <project>-phase14-yyy（無撞檔風險）
建議下一步: <根據 .planning/PROJECT.md 與看板現況>
```

---

## 1. 何時必須更新看板

| 觸發事件 | 看板動作 | 自動 / 手動 |
|----------|----------|-------------|
| 開新 phase / wave | 開 issue（`label: phase,P0,planned`），手動加到看板 -> Todo | 手動 |
| 開 feature branch 開工 | 把對應 issue 拖到 In Progress | 手動 |
| 提 PR 帶 `Closes #N` | merge 後 issue 自動關閉，看板自動移到 Done | 全自動 |
| 提 PR 不帶 `Closes #N`（罕見） | merge 後手動 `gh project item-add` + 標 Done | 手動 |
| 卡外部依賴（S3/SES/金流 等第三方服務） | 加 label `Blocked` + `@<service>` | 手動 |
| 依賴解除 | 移回 In Progress 或 Done | 手動 |
| Phase 04..16 任何狀態變動 | 同步看板 + 更新 .planning/PROJECT.md `[x]` | 手動 |

**禁止**：
- PR body 漏寫 `Closes #N`（會留 ghost card 永不更新）
- 看 `PROJECT.md [x]` 推斷 phase 完成（須查 `gh issue view <N> --json state` 才準）
- 同一 phase 在兩個 worktree 同時動工（branch name 視為 lock）
- 改 sibling worktree 的 commit（違反 CLAUDE.md §4.2.1 反 race）

---

## 2. 標準 Claude / Codex / Gemini 請求話術（用戶複製即可）

### 2.1 開工前對齊
```
看一下目前看板 In Progress 有哪些，避免我撞 sibling worktree
```
AI 必跑：`gh project item-list 1 --owner pon50895 --format json --jq '.items[] | select(.status=="In Progress")'`

### 2.2 開新 phase / 工作項
```
我要開始做 Phase X.Y <簡述>，幫我：
1. gh issue create --label phase,P0,planned
2. 加到 Project board -> Todo
3. 拖到 In Progress
4. 開 feature branch <type>/<scope>-<desc>
```

### 2.3 提 PR 時自動串看板
```
幫我提 PR，PR body 必須含 Closes #<issue-number>
```
AI 必檢查：commit 訊息或 PR body 至少一處含 `Closes #N`，否則要求補 issue number 才開 PR。

### 2.4 PR 已 merged 但沒上看板（補救）
```
PR #<N> 已經 merged 了但沒進看板，幫我補：
1. 開 retroactive issue（label: phase 或 chore，視類型）
2. issue body 第一行寫「Tracks already-merged PR #<N>」
3. gh project item-add 到看板並直接標 Done
4. 在 PR comment 加註 issue 連結
```

### 2.5 卡外部依賴
```
這個 PR / phase 卡 <第三方服務名>，幫我：
1. PR / issue 加 label Blocked + @<service>
2. 看板拖到 Blocked column（若有）或留 In Progress + label
3. 同步寫一筆到 .planning/audit/PENDING_EXTERNAL.md
```

### 2.6 每日健康度
```
跑 scripts/wt-status.sh 給我看 worktree + 看板現況
```

### 2.7 Session 結束 / 換 AI agent 交接
```
我要切到 codex / gemini，幫我寫 DEVELOPER_HANDOFF.md：
1. 當前看板 In Progress / Blocked 列表
2. 各 worktree 分支 + 未 commit WIP
3. 已 merged 但漏進看板的 PR 清單
4. 下一步建議（依據 .planning/PROJECT.md 優先順序）
```

---

## 3. PR `Closes #N` 撰寫規範

PR body 必須在**第一段**就出現 `Closes #N` 才能保證 GitHub 自動處理：

```markdown
Closes #76

## Summary
<本 PR 做了什麼>

## Test plan
- [x] 單元
- [x] regression（受影響 spec）
- [x] build
```

**多 issue 寫法**：`Closes #76, #77, #78`（GitHub 接受逗號分隔）

**部分完成寫法**（不關 issue，但連結）：用 `Refs #76` 而非 `Closes #76`

**治理 / 純文件 PR**（無 underlying issue）：commit 訊息加 tag `[OPENSPEC]` / `[DEV-RULE]` / `[CLAUDE.md]`，
merge 後依 §2.4 補 retroactive issue。

---

## 4. 補救實例（2026-05-05 場景）

| PR | merge 時間 | 漏進原因 | 補救步驟 |
|----|-----------|----------|----------|
| #83 (OPENSPEC §22) | 11:19:29Z | 無 underlying issue（治理文件直開 PR） | 開 issue -> 加看板 -> 標 Done |
| #84 (Phase 09 financial ledger) | 11:21:17Z | 應對應 phase 09 issue (#69)，但 PR body 沒寫 `Closes` | 補編輯 PR body -> 手動移看板 |

補救指令範例：
```bash
# (a) 開 retroactive tracking issue
ISSUE_URL=$(gh issue create \
  --title "docs(openspec): §22 AI Tooling & Project Governance" \
  --body "Tracks already-merged PR #83 (retroactive board entry)." \
  --label chore,docs)

# (b) 加到 Project board
ITEM_ID=$(gh project item-add 1 --owner pon50895 --url "$ISSUE_URL" --format json --jq '.id')

# (c) 標為 Done
gh project item-edit \
  --id "$ITEM_ID" \
  --project-id PVT_kwHOAnbbEs4BWv3B \
  --field-id PVTSSF_lAHOAnbbEs4BWv3BzhSBjos \
  --single-select-option-id 98236657
```

---

## 5. Project 欄位 ID 速查（給 `gh project item-edit`）

```
PROJECT_ID    = PVT_kwHOAnbbEs4BWv3B
STATUS_FIELD  = PVTSSF_lAHOAnbbEs4BWv3BzhSBjos
Status options:
  Todo         = f75ad846
  In Progress  = 47fc9ee4
  Done         = 98236657
```

---

## 6. AI 自我檢核清單（每個 PR 動作前必過）

- [ ] Session 開頭跑過 §0 三步
- [ ] 動工前看過 In Progress column，無撞 sibling worktree
- [ ] commit message 與 PR body 都標 phase（如 `[Phase 09]`）或治理 tag（`[OPENSPEC]` / `[DEV-RULE]` / `[CLAUDE.md]`）
- [ ] PR body 第一段含 `Closes #N`（除非確定無對應 issue）
- [ ] merge 後若無 `Closes`，主動補 retroactive issue + 上看板
- [ ] 卡外部依賴 -> 同步寫 `.planning/audit/PENDING_EXTERNAL.md`
- [ ] Session 結束前更新 `DEVELOPER_HANDOFF.md`

違反任何一項：在回覆中明示原因 + 提案補救動作，不偷偷略過。

---

## 7. 跨 AI Agent 共用責任 (Multi-Agent Mandate)

本檔對 **Claude / Codex / Gemini / 任何 LLM CLI** 一視同仁。
切換 AI agent 不重置義務 — 看板狀態必須在 AI handoff 時保持與 git 真相同步。

| Agent | 必讀 | 必做 |
|-------|------|------|
| Claude Code | CLAUDE.md §0 載入 7 份規範 + 本檔 | §0 三步 + §6 檢核清單 |
| Codex | AGENTS.md（若有）+ CLAUDE.md + 本檔 | 同上 |
| Gemini | GEMINI.md（若有）+ CLAUDE.md + 本檔 | 同上 |

**真相來源**：永遠以 `gh issue view` / `gh pr view` / `gh project item-list` 為準，
不信任任何 .md 檔的 `[x]` markers。

---

## 8. 相關文件

| 文件 | 角色 |
|------|------|
| `open-source-spec/OPENSPEC.md §22.2` | 規範層（standard） |
| `dev-rule/PROJECT_BOARD_WORKFLOW.md`（本檔） | SOP + Claude 請求話術 |
| `.planning/GITHUB_PROJECTS_WORKFLOW.md` | 進階 SOP（cypher 查詢，將隨 `chore/tooling-projects-board` PR 合進 main） |
| `scripts/wt-status.sh` | 一頁看 worktree 健康度 + Project board |
| `dev-rule/PARALLEL_DEVELOPMENT.md` | 多 worktree 反 race 原則 |
| `CLAUDE.md §4.2.1` | 反 sibling worktree race rule |

*Last revised: 2026-05-05*
