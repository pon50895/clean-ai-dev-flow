# GSD 開發流程規範 (GSD Process)

## 1. 核心哲學
- **寫程式前先思考 (Think Before Coding)**: 絕不盲目實作。若需求不明，必須反問。
- **簡潔優先 (Simplicity First)**: 拒絕過度工程，不為一次性需求建立抽象。
- **目標驅動 (Goal-Driven)**: 每個任務必須有明確的驗收標準 (Success Criteria)。

## 2. 四階段循環
### 2.1 討論 (Discuss)
- 確認業務邏輯、UI 風格、法律合規。
- AI 必須挑戰用戶的潛在風險預設。

### 2.2 規劃 (Plan)
- 建立或更新 `.planning/PLAN.md`。
- 拆解原子化 Task（Research -> Code -> Integration -> Verification）。

### 2.3 執行 (Execute)
- **精確修改**: 僅更動必要代碼，禁止執行全文件覆蓋。
- **代碼品質**: 包含詳細註釋，解釋關鍵邏輯。
- **SSOT**: 共享資源存放在 `packages/shared-content/`（或專案約定位置）。

### 2.4 驗證 (Verify)
- **P0 檢核**: 必須通過 Husky 提交鉤子。
- **視覺審計**: AI 必須執行物理截圖核對。
- **存檔**: 每次重大功能完成後，必須更新 `ROADMAP.md` 並提交 Commit。

## 3. 提交規範 (Commit Hygiene)
- 嚴禁提交測試碎片（日誌、偵錯腳本）。
- Commit Message 必須具備語義化標籤（feat, fix, chore, docs）。

## 4. Branch & Worktree 策略 (Branch & Worktree Policy)

### 4.1 觸發條件 (When to Use a Worktree)
凡符合以下任一條件，**必須切 worktree** 以避免污染 `main`：
- 跨 Wave / 跨模組的多檔修改（例如同時動 server + client + 基礎設施）。
- 風險較高、回滾成本大的功能（DB schema migration、第三方支付、外部服務串接）。
- 需要在主分支保持可發布狀態的同時，平行開發新功能。
- 需要 reviewer 在獨立檢視下測試的功能。

可直接在 `main` 上修的情境（**不需切 worktree**）：
- 單檔 hotfix、文檔更新、UI 文案調整。
- 已被 main 鎖定且需立即發布的安全修補。

### 4.2 命名規範 (Naming Convention)
- 功能分支：`feature/{module}-{slug}`（例：`feature/p1-1-session-closure`）。
- 修補分支：`fix/{module}-{slug}`（例：`fix/api-token-expiry`）。
- 重構分支：`refactor/{area}-{slug}`。
- 文檔/維運：`chore/{slug}`。

Worktree 目錄統一放在專案上層，命名與分支對齊：
- 路徑慣例：`../wt-{slug}`（例：`../wt-p1-1-closure`）。
- 禁止把 worktree 放在主專案資料夾內（避免被 IDE 重複索引）。

### 4.3 標準指令 (Standard Commands)
建立 worktree：
```
git worktree add ../wt-{slug} -b feature/{module}-{slug}
```

切換進入工作：
```
cd ../wt-{slug}
```

完工後合併（在主專案執行）：
```
cd /path/to/<your-project>
git merge --no-ff feature/{module}-{slug}
git worktree remove ../wt-{slug}
git branch -d feature/{module}-{slug}
```

### 4.4 禁忌事項 (Hard Rules)
- **禁止** 在 `main` 進行測試性大改後再 reset。
- **禁止** 兩個 worktree 同時修改 `.planning/` 同一份文件（避免 merge 衝突）。
- **禁止** 在 worktree 內直接 push 到 `main`，必須走 PR 或本地 merge。
- **禁止** 跨 worktree 共用 `node_modules`／`.env`（必各自安裝、各自設置）。
- 若 worktree 內含敏感資訊（金鑰、token），刪除前確認 `git status` 無未追蹤檔案外洩。

### 4.5 工作切換協議 (Switching Discipline)
- 開始新 worktree 前，先確認當前 worktree `git status` 乾淨或有 commit / stash。
- AI 助手在 worktree 內作業時，必須在每次回覆中**明確指出當前所在路徑**，避免使用者混淆。
- worktree 完工合併後，必須同步更新 `.planning/PROJECT.md` 與 `ROADMAP.md` 的對應狀態。

### 4.6 Session 銜接 cwd 校對 (Session Handoff cwd Reconciliation)
新 AI session 銜接舊 session 時，因系統 env 預設 cwd 與舊 session 工作 worktree 可能不一致，必須執行以下校對流程：

1. **列舉 worktree**: `git worktree list` 取得所有路徑。
2. **檔案存在性驗證**: 從 summary 抽出至少 3 個「已修改／已建立」檔案路徑，於當前 cwd 用 `ls` 驗證。
3. **Cross-check**: 若任一檔案不在當前 cwd，**改至其他 worktree 路徑**重新 `ls`。
4. **誤判防呆**: 嚴禁未經 step 3 就宣稱「檔案遺失」「session 工作未保存」「需要重做」。
5. **路徑切換**: 確認舊 session 作業路徑後，在回覆開頭以 `[CWD: <絕對路徑>]` 標註，並建議用戶 `cd` 過去（或在工具呼叫使用絕對路徑）。
6. **stash 殘留檢查**: 同步執行 `git stash list` 確認是否有未取出的進度。

**反例（曾發生）**: 舊 session 在 `../wt-{slug}` 完成 10 個 spec 檔，新 session 啟動於主 worktree 直接 `ls apps/e2e/tests/admin/<spec>.spec.ts` 找不到，誤判為「檔案遺失」。正確做法是先 `git worktree list` 看到平行 worktree 後，去那邊 `ls` 才會發現檔案完整存在。

### 4.7 Worktree 退場流程 (Decommission Lifecycle)

完工或廢棄的 worktree **必須**主動退場，避免堆積。退場時必須先盤點，確保不丟工作。

#### 4.7.1 盤點（每個候選 worktree 都跑一遍）

```bash
p=<worktree-absolute-path>
git -C "$p" branch --show-current                        # branch 名
git -C "$p" rev-list --count main..HEAD                  # 領先 main 幾個 commit
git -C "$p" status --porcelain | grep -v ".husky/_/"     # 過濾 auto-gen 後的真 dirty
```

#### 4.7.2 分類處置

| 情境 | 動作 |
|---|---|
| `commits=0` 且 `real_dirty=0` | `git worktree remove <path>` |
| `commits=0`，`real_dirty` 只有 `.planning/HANDOFF.json` 等 meta | `git worktree remove --force <path>`（SSOT meta 不留分身） |
| `commits=0`，含實質檔案（research / spec / 程式碼） | **先**到該 worktree 內 `git add` + `git -c core.hooksPath=/dev/null commit -m "..."`，把工作鎖進 branch；**再** `git worktree remove <path>` |
| `commits>=1`、已 merged | `git worktree remove <path>` 後 `git branch -d <branch>` |
| `commits>=1`、未 merged | **禁止砍**；先開 PR 或 `git stash` 再評估 |

#### 4.7.3 Branch 是否一併刪除

由「該 branch 代表的工作是否還會做」決定，與 worktree 存在與否解耦：

- 已 merged 進 main → `git branch -d <branch>`
- 未 merged 但放棄 → `git branch -D <branch>`，並在 commit 訊息或 PR description 註明放棄理由
- 未 merged 但延後 → 保留 branch（變成「規劃中」label），只移 worktree

#### 4.7.4 禁忌

- 禁止對含未提交實質工作的 worktree 直接 `--force`。
- 禁止刪除其他 session 正在使用的 worktree（移除前先 `git worktree list` 並確認）。
- 禁止在自己當前 cwd 的 worktree 內執行 `git worktree remove .`（先 `cd` 到 main worktree 再操作）。

#### 4.7.5 反例

整理多條平行 worktree 時，曾發現某條 worktree 內藏 100+ 行的研究報告未提交。若直接 `worktree remove --force` 就會永久遺失。正確做法：先 `git -C <path> commit` 該檔到對應 branch，再移 worktree。AI 簡略快查見 `.claude/WORKTREE_LIFECYCLE.md`。
