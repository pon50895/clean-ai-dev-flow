# AI 助手執行協定 (AI Execution Protocol)

如果您是新接手的 AI 助手，請在開始工作前強制執行以下步驟：

## 1. 環境同步
0. **Worktree 對齊（接續舊 session 時最優先）**:
   - 執行 `git worktree list` 列出所有平行 worktree。
   - 若先前對話 summary 提到任何「已建立／已修改」的檔案，先 `ls` 對應路徑驗證是否存在於當前 cwd。
   - 若當前 cwd 找不到 summary 標榜的檔案，**禁止**直接判定為「檔案遺失」或「未建立」，必須先到其他 worktree 路徑下 `ls` 確認。
   - 確認後若上一個 session 是在另一個 worktree 作業，必須建議用戶切換 cwd（或主動 `cd`）後再繼續，並在每則回覆開頭標註當前所在路徑。
1. 讀取 `open-source-spec/OPENSPEC.md` 了解全局架構。
2. 讀取 `/dev-rule` 目錄下的所有規範。
3. 讀取 `.planning/PROJECT.md` 了解目前進度。

## 2. 執行守則
- **禁止私自腦補**: 條件不足時必須反問。
- **糾錯優先**: 若用戶請求違反本規範（例如要求加入 Emoji），必須主動拒絕並說明原因。
- **物理驗證**: 每個任務完成後，必須自行啟動瀏覽器代理人或測試腳本進行「物理驗證」，不得僅憑「代碼已寫」就宣稱完成。

## 3. 紅線 R1-R11 (Red Lines) — SSOT

> 這張表是紅線的唯一正本。README / GETTING_STARTED / CLAUDE.md 只引用它，不複製全表（複製即漂移）。
> 下方 §RC 的資源協調用 RC 前綴，與這裡的 R 前綴分屬兩套，勿混。

| # | 禁止 | 補救 |
|---|------|------|
| R1 | 使用 Emoji（代碼、註釋、日誌、回覆、PR body） | 改為文字描述 |
| R2 | 私自腦補需求；條件不足卻動手 | 反問用戶 |
| R3 | 全文件覆寫 (full-file overwrite) | 精確 Edit / 局部替換 |
| R4 | 提交編譯不通過的代碼 | 先在本地驗證 |
| R5 | 繞過法律合規攔截、`acceptedLegal` 標記 | 強制 Click-Wrap |
| R6 | 使用 `alert()` / `confirm()` / `prompt()` | 改用 toast / 自訂 confirm dialog |
| R7 | 刪除任何非「本次改動直接產生」的代碼或註釋 | 只清自己造成的 orphan；要刪舊代碼列檔案+行號+理由，經 review 核准 |
| R8 | 自動執行毀滅性指令 | 必須請求用戶確認 |
| R9 | 在 `main` / `master` 直接 commit 或 push | 一律開 feature branch + PR |
| R10 | 未跑測試（功能 + regression）就 merge | `dev-rule/GSD_WORKFLOW.md` §測試門檻 |
| R11 | 用 `--no-verify` 跳過 hook | 修通 hook 或修代碼 |

## 4. 對話臨界壓縮 (Dialogue Threshold Compression)
- **觸發背景**: 當對話紀錄接近系統 Context Window 限制，或當前任務涉及大量檔案變動、邏輯碎片化時。
- **主動動作**: AI 助手必須主動執行「進度快照 (Progress Snapshot)」，摘要已解決的衝突、已實作的邏輯、未完成的 Bug 以及遺留的待辦事項。
- **開啟新對話提示**: 摘要完成後，必須建議用戶「開啟新的對話 (New Thread)」，並說明這是為了防止對話過長導致最早的上下文或關鍵決策被系統遺忘。
- **交付要求**: 壓縮內容需包含「當前物理路徑 (CWD)」與「變動檔案清單 (Modified Files)」，確保接手助理能快速回復上下文。
- **多 session 執行細則**: 平行開發時不同角色（supervisor / alarm / reviewer / worker）的 handoff 落點與啟動序列見 `dev-rule/WORKFLOW_PROTOCOLS.md` §1。**不要等 auto-compact 自動觸發**；先寫 handoff 文件再讓 user 開新 session。

---
*啟動指令: 「我已閱讀並理解 /dev-rule 中的所有規範，準備開始工作。」*

---

## §RC Scarce Resource Coordination (added 2026-05-08)

> RC = Resource Coordination。這套 RC1-RC4 是「稀缺資源協調」，與 §3 的紅線 R1-R11 是**兩套不同編號**，勿混。

4 scarce resources require formal coordination across the fleet:

| ID | Resource | Why scarce | Coordinator |
|----|----------|-----------|-------------|
| **RC1** | Docker daemon | Single instance, all worktrees share containers/ports/volumes | `docker-coord.sh` (5-min stale lock) |
| **RC2** | DB schema | `prisma migrate dev` is exclusive | `db-coord.sh` (15-min stale lock with heartbeat) |
| **RC3** | Arbiter capacity | Single supervisor (Opus 4.7) = SPOF, $25/hr expensive | Split into supervisor (仲裁) + dispatcher (routine) + tester (test orchestration) |
| **RC4** | User permission grants | Singular human, sleep cycles | Async `USER_PERMISSION_QUEUE.md` + `USER_PERMISSION_GRANTS.md` channel |

### RC1 Docker — usage rules
- **Workers MUST NOT** run `docker compose down/up`, `volume rm`, `image rm`, or mutating `docker exec`
- Workers escalate via INBOX `[worker DOCKER-REQUEST]` — supervisor/dispatcher/tester executes
- Read-only ops (`docker ps`, `logs`, `stats`, ro `exec`) are unrestricted

### RC2 DB schema — usage rules
- Workers acquire lock via `bash skill.sh db-coord acquire <wt> <branch> <phase> "<purpose>"` BEFORE `prisma migrate dev`
- Refresh heartbeat every 5 min while holding (auto-sweep at 15 min stale)
- Release explicitly when done (`db-coord release <wt>`)
- Concurrent worker getting DENIED → only `prisma generate` allowed, wait for release

### RC3 Arbiter capacity — split roles
- **supervisor (main:0, Opus high-tier)**: spec arbitration, phase decisions, conflict resolution
- **dispatcher (main:1, Sonnet mid-tier)**: routine triage, IDLE detect, INBOX poll, lock sweep
- **tester (main:8, Sonnet mid-tier)**: central test orchestration, holds RC1 lock during runs
- **reviewer (main:2)**: PR audit only

### RC4 User permission — async channel
- supervisor writes to `.planning/USER_PERMISSION_QUEUE.md` with QID, timeout, safe-default
- supervisor continues monitoring loop (NEVER blocks on dialog)
- user (when available) writes decision to `.planning/USER_PERMISSION_GRANTS.md`
- supervisor polls grants per tick (`bash skill.sh permission-poll`)
- timeout elapsed without grant → apply safe-default (logged)

### Central Test Orchestration (replaces worker-spawn subagent pattern)

**Old pattern (deprecated)**: each worker spawns its own tester subagent (Agent tool) — caused RC1 docker contention.

**New pattern**: workers push test request to `.planning/TEST_REQUEST_QUEUE.md`. Central tester pane (main:8) consumes serially:
1. Pick oldest PENDING entry
2. Acquire docker-coord lock
3. Run 4 test layers (unit / integration / e2e-scoped / cumulative regression)
4. Append spec to `.planning/REGRESSION_REGISTRY.md` if PASS
5. Write result to `.planning/TEST_RESULTS.md`
6. Release lock + INBOX `[tester DONE TR-N]`

Worker IDLE waits for result before push + open PR.
