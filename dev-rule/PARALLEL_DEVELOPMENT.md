# 平行開發紀律 (Parallel Development Discipline)

> 本文件是 `.claude/SESSION_BOOTSTRAP.md` 的同層補充規範，
> 對應 CLAUDE.md §4「平行開發協定」與 §2.5「Branch-First 提交門檻」。
> 任何 AI agent（Claude / Gemini / Codex 等）在本專案啟動時，
> 若涉及多條工作流並行，必須遵守本檔。

---

## 1. 核心定理

**一條獨立的工作邏輯單位 = 一個 git worktree = 一個 feature branch = 一個 PR。**

agent（執行者）只是工具；切分單位是「工作邏輯」，不是「agent」。

| 對象 | 單一性 |
|---|---|
| 工作流 (workstream) | 業務邏輯一致、可獨立 review、可獨立 revert 的最小單位 |
| worktree | 一條工作流綁定一個物理工作目錄 |
| branch | 一條工作流綁定一條 feature branch |
| PR | 一條工作流綁定一個 PR；不混雜不相干改動 |
| agent session | 同一條工作流可由多個 agent session 接力（透過 HANDOFF） |

---

## 2. 判定矩陣

| 情境 | 是否算平行開發 | 處理方式 |
|---|---|---|
| 同一個 agent 同時動兩件不相干工作 | 不是（屬於混淆） | 拆成兩條工作流，各自一個 worktree |
| 兩個 agent 同時動同一條工作流 | 不是（屬於衝突） | 由其中一個主導；另一個改做別條，或等候 handoff |
| 一個 agent 做完交棒給下一個 agent 接續同一條工作流 | 是合法接續，不是平行 | 同一個 worktree、同一個 branch、用 HANDOFF.json 交棒 |
| 兩個 agent 在不同 worktree、做不相干工作 | 是真正平行 | 各自走 §2.5 流程；合併進 main 順序由先到先得，後到者 rebase |
| 同一份 monorepo 共享套件（`packages/shared-*`） | 屬於跨工作流共享層 | 共享層改動必須先合進 main 才能被其他 worktree 拉用，並在 commit 訊息標 `[shared]` |

---

## 3. 反例（常見錯誤模式）

下列做法在本專案明確視為違規：

1. **「順手一起改」**
   做 A 任務時順手改了 B 任務的檔案，commit 一起進 A 的 PR。
   → 違反「PR 邏輯單位」原則。Code review 時無法獨立評估。
2. **「main 上多任務並進」**
   17 個未 commit 改動橫跨 3 條業務邏輯都堆在 main 工作區。
   → 違反 §R9（不在 main 直接 commit）與 PR 邏輯單位。
3. **「同一 branch 切換場景」**
   同一條 feature branch 在 admin auth 與 docker 修復之間反覆切換。
   → 應拆 branch。如果中途發現需要先修一個前置條件，採 stack-PR 或 rebase 方案，不混 commit。
4. **「agent 切人不切事」**
   兩個 agent 各自接到使用者不同的請求，但都在同一個 cwd、同一個 branch 上動。
   → 必開新 worktree。先到的 agent 鎖定當前 worktree，後到的 agent 走 `git worktree add`。

---

## 4. 開新工作流的標準步驟

```bash
# 1. 從乾淨 main 出發
git switch main && git status   # 確認工作區乾淨；若不乾淨先處理

# 2. 開新 worktree + branch（路徑以兄弟目錄為慣例）
git worktree add ../<repo>-<scope> -b <type>/<scope>-<short-desc>

# 3. 在新 worktree 工作
cd ../<repo>-<scope>

# 4. 完成後 push 並開 PR（依 §2.5）
git push -u origin <branch>
gh pr create --base main --fill

# 5. PR 合併後清掉 worktree
cd <主目錄>
git worktree remove ../<repo>-<scope>
git branch -d <branch>
```

`<type>` 與 `<scope>` 命名規則見 CLAUDE.md §2.5.1。

---

## 5. 從「混亂的 main 工作區」分流的標準作法

當 main 已有跨多條邏輯的未 commit 改動時，分流流程：

1. 列出所有未 commit 改動（含 untracked）：
   ```bash
   git status --short
   ```
2. **由人工或 AI 提案邏輯分組**，每組對應一條未來的工作流。
3. 對每一組，依下列 a/b 擇一：
   - **a. 已追蹤檔案改動**：用 `git stash push -m "group-<X>" -- <file...>` 將該組 stash 起來；在新 worktree 用 `git stash apply stash@{N}` 取出。
   - **b. 新增檔案 (untracked)**：直接 `mv <file> <new-worktree-path>/<file>`，或在新 worktree 重新建立。
4. 每組分完，本路徑 main 工作區應保留下一組或最後變乾淨。
5. 全部分完後，本路徑 main 應為 `git status` 乾淨；最後一條 docker / 環境類工作流可在本路徑開新 branch 進行。

> 注意：partial stash (`git stash push -- <file>`) 只 stash 已追蹤檔案；新增檔案需用 `mv` 或 `git add` 後再 stash。

---

## 6. 共享改動例外 (`packages/shared-*`)

跨工作流共享層的改動例外處理：

- 共享層改動必須先單獨開 PR 合進 main，**不可埋在某條業務工作流的 PR 裡**。
- commit 訊息以 `[shared]` 起頭，PR 標題前綴 `chore(shared):` 或 `feat(shared):`。
- 其他正在進行的 worktree 必須等共享層 PR 合併後 `git pull --rebase` 才能拉用新版。

---

## 7. AI 自我檢查清單

在動工前，AI 必須能對下列問題給出明確答案：

- [ ] 我現在處理的工作邏輯**只有一個**嗎？（若有兩個，停手並拆分）
- [ ] 我所在的 worktree 是專屬此工作流的嗎？（若不是，用 `git worktree add`）
- [ ] 我所在的 branch 不是 `main` / `master` 嗎？（若是，立刻開 feature branch）
- [ ] 我的 PR 範圍能用一句話描述嗎？（若需「並且」「順便」「同時」連接，太雜，須拆）
- [ ] 是否有其他 worktree / agent 正在動同一檔案？（看 `.planning/HANDOFF.json` 與 `git worktree list`）

任一項否，停手；先解決完才動代碼。

---

## 8. 與其他文件的關係

- `CLAUDE.md §4`：總綱（Workspace 隔離 / 衝突避免 / 上下文交接 / 模型中立）。本檔為其執行細則。
- `CLAUDE.md §2.5`：分支與測試門檻。本檔的 PR 紀律與其同源。
- `dev-rule/GSD_WORKFLOW.md §4.6`：Worktree 校對流程。
- `dev-rule/SECURITY_WORKTREES.md`：安全相關 worktree 隔離（若存在）。
- `.claude/SESSION_BOOTSTRAP.md`：session 接續時的 worktree 校對 checklist。

---

*Last revised: 2026-05-04*
*變更須在 PR 標註 `[CLAUDE-config]` 並請用戶 review。*
