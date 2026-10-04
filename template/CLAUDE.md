# CLAUDE.md — Top-Level Agent Directive (<專案名稱>)

> 交給 Claude / Gemini / Codex / 任何 LLM CLI 的最高指導文件；啟動時自動載入，
> 無論模型或供應商切換，行為準則一致。平行開發時每個 worktree / workspace 都須遵守。
>
> 本檔由 clean-ai-dev-flow 的 `scripts/bootstrap.sh` 產生，尖括號 `<...>` 與標「(填寫)」處依專案補齊。
> 機器 gate（`.githooks/`）的指令、workspace、基線路徑讀自 `.claude/kit.json`，不寫死在本檔。
>
> 分層：§1–§2.5 硬約束（部分由機器 gate 強制）｜§0 啟動程序｜§3–§4 流程協定｜§5–§9 速查與情境協定。
> § 編號是跨檔穩定錨點（hooks / skills / dev-rule / handoff 均引用），只動內容不動編號、不重排。

---

## 0. 啟動程序 (Bootstrap — 每次新對話必做)

### 0.1 核心必讀

1. `.planning/PROJECT.md` — 當前狀態精簡版（若尚未建立，先問使用者是否要建）。
2. 最新 `.planning/HANDOFF/SESSION_HANDOFF_<YYYY-MM-DD>-PART<N>.md`（若存在）— 上一段交接。接續舊 session 先 `git worktree list` 對齊：summary 提到的檔案在當前 cwd 找不到，**禁止**判定「檔案遺失」，先到其他 worktree 路徑確認。
3. `.planning/learning/violations.jsonl`（若存在）— 跨 session 學習紀錄。

讀完不必複誦，但回答須體現上述事實。

### 0.2 按需查閱（情境觸發才讀，讀了才動手）

| 情境 | 必讀文件 | 機器 gate |
|---|---|---|
| 新 feature 開工 / Plan 階段 | `dev-rule/GSD_WORKFLOW.md`、`dev-rule/README.md` | — |
| 動 API / DB schema / 跨 service 結構 | (專案規格文件路徑，填寫) | — |
| 測試或本機環境故障排除 | `dev-rule/TEST-EXPERIENCE.md` | — |
| Bash 權限摩擦 / 高危指令邊界 | `dev-rule/BASH_TOOL_GATE.md` | 全域 destructive-guard hook |
| 派 subagent / 多模型分工 / 判斷卡關 | `dev-rule/MODEL_DISPATCH.md`、`dev-rule/JUDGMENT_RUBRICS.md` | — |
| 依賴被 pin 住（Dependabot 反覆升版） | `dev-rule/DEPENDENCY_PINS.md` | pre-commit dependency pins |
| 密鑰外洩 / 輪換 | `dev-rule/SECURITY_ROTATION_SOP.md` | pre-commit secret scan |
| 碰金流 / 法遵 / 個資 / UI 標準 | (專案自訂文件，填寫) | — |

規則：情境命中卻沒讀對應文件就動手 = 違反 R2。
prod deploy 必須使用者明講「deploy／上線」才執行 —「ok」只授權問句中最小的一步（預設流程止於 PR）。

**Karpathy 心法常駐 (default-on)**：所有寫 / 改 / 重構 code 預設套用 `karpathy-guidelines` skill（細則見 §8）。

---

## 1. 紅線 (Hard Red Lines — 絕對禁止)

下列行為一律拒絕執行，且必須說明原因：

| # | 禁止 | 補救 |
|---|------|------|
| R1 | 使用 Emoji（代碼、註釋、日誌、回覆） | 改為文字描述 |
| R2 | 私自腦補需求；條件不足卻動手 | 反問用戶 |
| R3 | 全文件覆寫 (full-file overwrite) | 精確 Edit / 局部替換 |
| R4 | 提交編譯不通過的代碼 | 先在本地驗證 |
| R5 | 繞過法律合規攔截（同意條款、個資、法遵標記） | 強制走合規流程 |
| R6 | 前端使用原生 `alert()` / `confirm()` / `prompt()` | 改用專案的 toast / dialog 元件 |
| R7 | 自行刪除非自身改動造成的代碼或註釋 | 僅清自己造成的 orphan |
| R8 | 自動執行毀滅性指令（見 §2） | 必須請求用戶確認 |
| R9 | 在 `main` / `master` 直接 commit 或 push | 一律開 feature branch + PR |
| R10 | 未跑測試（功能 + regression）就 merge | 強制 §2.5 測試門檻 |
| R11 | 用 `git commit --no-verify` 跳過 git hooks | 修通鉤子或修代碼 |

---

## 2. 高風險指令白名單與確認協定

以下指令**必須先用文字說明影響、請求明確確認**才可執行；即使環境已加入 Bash 白名單，AI 仍須口頭詢問（用戶須明確回「確認 / yes / 執行」）：

- `rm -rf` / 任何遞迴刪除 (`rm -r`, `find ... -delete`)
- `git reset --hard` / `git clean -fdx` / `git push --force`
- `docker volume rm` / `docker-compose down -v` / `docker system prune`
- 資料庫 `DROP TABLE`, `TRUNCATE`, 無 WHERE 的 `DELETE FROM`
- `kill -9` 對非 Claude 自啟流程
- `sudo` / `su` / `chmod 777` / `chown` 變更系統權限
- 修改 `.env`、`secrets`、`*.pem`、`credentials.json`
- 跳過 git hooks (`--no-verify`)
- 寫入 `node_modules/`、`.git/objects/`
- 對 `main` / `master` 直接 push（必須走 PR）

確認句型範例：「即將執行 `git reset --hard origin/main`，這會丟棄你本地未提交的 X 個變更。是否確認？」

專案內可拋棄的暫存目錄（`rm` 不擋）宣告在 `.claude/kit.json` 的 `destructiveGuard.allowPaths`。

---

## 2.5 Branch-First 提交門檻 (Mandatory Branch & Test Gate)

**所有 commit 必須先通過測試。任何情況下都不可直接在 `main` 上 commit / push / merge。**

### 2.5.1 強制工作流程
1. **開分支**（一律從最新 `main` 拉）：`git switch main && git pull --rebase` → `git switch -c <type>/<scope>-<desc>`。`<type>` = `feat`/`fix`/`chore`/`refactor`/`docs`/`test`。
2. **小步提交**：原子化 commit，訊息走 Conventional Commits。
3. **本地三道測試門檻（範圍化，缺一不可）**，指令見 `.claude/kit.json` 的 `commands`：
   - **單元 / 元件**：`commands.test`（受改動範圍為主）。
   - **回歸 (Scoped Regression)**：跑與本次改動直接相關的整合 / E2E，加至少一條全站冒煙路徑。**不要求所有 spec 全綠。**
   - **建置**：`commands.build` 無錯；型別檢查 `commands.typecheck`。
4. **物理驗證**（UI 變動）：截圖比對、目標頁 200 OK。
5. **簡化門檻**：開 PR 前對 diff 跑 `/ponytail-review` 拿 delete-list，能砍當下砍、刻意保留標 `ponytail:` 註解。`kit.json` 開啟 `modules.ponytailAck` 時，pre-push 對碰 code 的 diff 半阻斷 push：套完 delete-list 後以 `PONYTAIL_REVIEWED=1 git push` 放行。
   - **事實斷言門檻**：開 PR 前，派一個沒寫這份改動的 fresh-context agent 去「推翻」PR 在文件、commit message、PR 描述裡新增的每一句事實 / 因果敘述。第三方行為的斷言，沒有擷取到的 trace 或原始碼出處就一律是 `needs_validation`。每句結局三選一：`confirmed`（附證據：`檔案:行號` 或實跑輸出）、`needs_validation`（寫明未驗的那個事實，文字也照實寫「尚未驗證」）、刪除。
6. **推遠端 + 開 PR**：`git push -u origin <branch>` → `gh pr create --base main --fill`。
7. **PR 過 CI + Code Review 才 merge**；merge 後刪 feature branch；isolation-agent worktree 一併回收（`git worktree remove`）。判 merged 看 PR 狀態非 SHA。

> **外部依賴標籤制**：受第三方服務（儲存、金流、郵件、通訊…）影響的測試須在 spec 加 `@<service>` tag；本地與 CI 預設跳過 tagged spec，Release 前在 staging 統一跑。避免外部服務未完成卡死功能 PR，同時保留上線前完整驗證入口。

### 2.5.2 無法自動跑測試時
- 明確告知用戶「本次變動需先跑 X / Y / Z 測試才符合 R10」，列出建議測試檔與指令。**絕不替用戶跳過測試**；測試環境失效先修環境再寫代碼。

### 2.5.3 反卡死條款 (Anti-Deadlock)
**核心：嚴格但不卡死。** 測試門檻擋住正當進度時，主動辨識並提案繞道，不無限重試：

| 情境 | 正確做法 |
|------|---------|
| 測試失敗來自外部服務未配置 | 加 `@<service>` tag，CI 跳過，記入 `.planning/audit/PENDING_EXTERNAL.md` |
| 測試環境本身故障（DB 連不上、port 衝突） | 先修環境，不修代碼 |
| 既有 spec 在 main 上已紅 | 不負責修復，加 skip + 註解 + TODO，不擋本 PR |
| 改動牽連 spec 爆炸（>20 條） | 拆 PR；每 PR 一個邏輯單位 |
| 外部 API quota 用完 | 走 mock；標 `@requires-quota` |
| 用戶要求「先合再修測試」 | **拒絕**，但提案先合到 `staging` 分支，不合 main |

> **未通過的測試一定記錄在案**（`.planning/audit/PENDING_EXTERNAL.md` 或 PR description），永不消失於黑箱。

### 2.5.4 緊急 Hotfix 例外
- 生產事故：開 `hotfix/<incident>` 仍走 PR；至少跑「冒煙 + 受影響模組單元測試」才合併；24 小時內補完整 regression + post-mortem。**任何「先 commit 再測」的提議一律拒絕。**

### 2.5.5 平行開發專屬
- 每個 worktree 在自己 feature branch 工作，不共用分支。跨 worktree 共享改動須先合進 `main` 才能被其他 worktree pull。合併衝突後到者負責 rebase。

---

## 3. GSD 四階段循環（強制流程）

任何「新功能 / 修 Bug / 重構」都須走完：

1. **Discuss** — 釐清業務邏輯、UI、合規；主動挑戰風險假設。
2. **Plan** — 寫入 `.planning/phases/<phase>/PLAN.md`，原子化 Task（Research → Code → Integration → Verification）。
3. **Execute** — 精確修改、加註釋、共享資源放單一 SSOT 位置。
4. **Verify** — P0 檢核（API 200、視覺、合規）+ 物理驗證（截圖、E2E）+ §2.5 三道測試門檻 + PR。

跳過任一階段須明示理由並徵得用戶同意。**§2.5 的分支 + 測試 + PR 門檻不可跳過。**

---

## 4. 平行開發協定 (Parallel Development)

多個 Claude/AI CLI 同時運作，遵守：

### 4.1 Workspace 隔離
- 每條 workstream 用獨立 git worktree：`git worktree add -b <type>/<scope>-<desc> <path> main`（從最新 main 拉）。`main` 為整合分支，只接受 PR 合併。

### 4.2 衝突避免
- 動工前看 `.planning/HANDOFF.json` 與 `.planning/HANDOFF/`，確認無人佔用該模組。跨模組共享程式碼的 commit 訊息標 `[shared]` 並通知用戶。同檔被兩條工作流同時碰觸時暫停請示。

### 4.2.1 反 Race（Sibling Worktrees）
**核心：絕不在「sibling worktree 有顯著未 commit WIP」的 branch 上替它加 commit。**
- 跨 worktree 同步（cherry-pick / merge / rebase）前先 `git -C <sibling> status --short`：乾淨 → 可 merge；有業務檔 modified/untracked → 改成提示用戶去那 session 自己 pull，不替它動。
- 在 sibling 有 WIP 時禁止 `git -C <sibling> pull --rebase`（會 reorder 它的 commit）。

### 4.3 上下文交接
- session 結束或 context 即將壓縮前，用 `handoff` skill 寫交接文件，含 CWD、活躍分支、變動檔清單、未完待辦、下一步。不要假設快取仍存在。

### 4.4 模型/供應商中立
- 不依賴特定模型專屬功能。指令用標準 shell，長腳本寫入 `scripts/` 而非 inline。

### 4.5 Port 隔離（多 worktree 同跑 dev server）
同時段只有一個 worktree 用預設 port；其他在自己的 `.env.local` 宣告偏移（主 worktree N=0，sibling N=1,2,3…）。啟動前 `lsof -i :<port>` 確認無衝突。

### 4.6 DB Schema 序列化（共用本地資料庫）
所有 worktree 共用同一本地資料庫時，schema migration 屬獨佔：同時段只有一個 worktree 可跑；跑前在 `.planning/HANDOFF.json` 加 `db_lock: <worktree-name>`，跑完刪除；其他 worktree 見 lock 存在時只能做不動 schema 的同步（如 client generate）。

---

## 5. 當前里程碑 (Current Milestone)

(填寫：進度 SSOT 指向哪裡，例：GitHub Project 看板 URL。本檔不複寫里程碑快照，避免 stale。)

---

## 6. 技術架構速查 (Tech Stack)

業務語境：(填寫：這個專案做什麼、給誰用、關鍵合規限制)

| Service | Port | 備註 |
|---------|------|------|
| (填寫) | (填寫) | |

- 前端：(填寫)
- 後端：(填寫)
- 資料庫 / 快取：(填寫)
- 測試 / 建置指令：見 `.claude/kit.json` 的 `commands`。

---

## 7. 溝通協定

- **語言**：(填寫，例：繁體中文；程式碼、檔名、技術術語可保留英文)。
- **格式**：表格、清單、代碼優先；避免寒暄冗詞。
- **代碼引用**：`path:line` 格式。
- **二級思考**：主動指出技術債、稅務、隱私風險，不盲目附和。
- **Token 經濟**：大型變動拆 Micro-Wave；單次輸出避免超過單一組件/服務方法。

---

## 8. Karpathy 工程心法

1. **寫程式前先思考** — 不假設、不猜測，呈現 trade-off。
2. **簡潔優先** — 100 行能解決就不寫 1000 行。
3. **精準修改** — 只碰必須碰的地方。
4. **目標驅動** — 明確 Success Criteria + 迭代驗證。

---

## 9. 終止條件 (When to Stop & Ask)

立即停手並請示用戶：規格文件互相矛盾；即將觸碰 §2 高風險指令；某模組已有他工作流佔用（看 HANDOFF）；無法在不破壞現有測試下完成需求；用戶請求違反 §1 紅線。

---

*Single Source of Truth for AI agents. 修改前必須在 PR 標註 `[CLAUDE.md]` 並請用戶 review。*
