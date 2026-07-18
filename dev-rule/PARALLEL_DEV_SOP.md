# PARALLEL_DEV_SOP.md — 平行多 Session 開發標準作業流程

> 整合自 2026-05-06 launch v1 衝刺實戰經驗。
> Source of truth: 此檔對「colyn + tmux + 多 Claude session 並行」場景優先於 README / blog post。
> 修改前必須在 PR 標註 `[DEV-RULE]` + `[CLAUDE.md]` 並請用戶 review。

---

## 1. 適用情境（CP 值評估）

### 1.1 用這套（推薦）

| 情境 | 為什麼 |
|------|------|
| 1-2 週短 sprint，多個獨立 phase 平行做 | 並行 throughput 補償 spec 起步成本 |
| Phase 之間檔案不重疊（API + UI 分開、不同模組） | rebase 衝突低 |
| Spec 已寫好（OPENSPEC + ROADMAP 完整） | session 不用反覆問用戶 |
| 有時間壓力，需要 5x throughput | 並行的核心價值 |

### 1.2 別用這套（會反效果）

| 情境 | 為什麼 |
|------|------|
| 單一小 bug fix（< 半天） | tmux + worktree 設定成本 > 收益 |
| 多 phase 都動同一個 schema | §4.6 db_lock 強制序列化，無法真並行 |
| Spec 不清楚 / 業務邏輯探索期 | N 個 session 各自亂猜 → N 倍混亂 |
| Token 預算緊（5 session ≈ 5x 用量） | 每 session 都要讀 spec + bootstrap |

---

## 2. 標準流程

### 2.1 環境建立（容器化 colyn）

```bash
# 一次性：建容器
mkdir -p ~/Desktop/<project>
cd ~/Desktop/<project>
git clone git@github.com:<org>/<repo>.git main
cd main
colyn init -p <dev-server-port> -y       # -p 給主 worktree 預設 dev port
```

效果：容器結構長這樣

```
~/Desktop/<project>/
├── main/                  ← colyn 容器根
│   ├── main/              ← 實際主 worktree（colyn 默認就叫 main）
│   ├── worktrees/         ← 後續 colyn add 的 worktree 會放這裡
│   └── .colyn/            ← colyn 配置
```

### 2.2 加 worktree

每個 phase 一個 worktree：

```bash
cd ~/Desktop/<project>/main
colyn add feat/<phase-branch-name>
```

colyn 自動：
- 建 `worktrees/task-N/` 目錄
- 給每個 worktree 獨立 `.env.local` 帶 `PORT` 偏移（5173 + N）
- 建 tmux window N，3-pane layout（Claude / Dev Server / Bash）

### 2.3 Port 偏移擴充（需要多 service 並跑時）

colyn 只設 `PORT`，但專案有多個 service。需要時手動補 `.env.local`：

```bash
# 每個 worktree 的 .env.local：
PORT=5173+N           # vite client
EXPRESS_PORT=3001+N   # express server
YJS_WS_PORT=4456+N    # yjs websocket
```

詳見 `CLAUDE.md` §4.5。**多 worktree 不要同時跑 dev server 除非你補完所有 port**。

### 2.4 tmux 操作備忘

| 動作 | 預設 keymap (prefix `Ctrl-b`) |
|------|---|
| Attach | `tmux attach -t main` |
| 切 window | `Ctrl-b 0..9` 或 `Ctrl-b w` (列表) 或滑鼠點狀態列 |
| 切 pane | `Ctrl-b o` 或 `Ctrl-b 方向鍵` |
| Detach | `Ctrl-b d` |
| 強制 reload conf | `tmux source-file ~/.tmux.conf` |

> macOS Mission Control 預設綁 `Ctrl+數字` 切 desktop，會跟 `Ctrl-b 數字` 衝突。  
> 解：System Settings → Keyboard → Mission Control → 取消「Switch to Desktop N」綁定。

`~/.tmux.conf` 推薦設定見 §6.1。

### 2.5 AUTONOMY MODE Directive

每個 worker session 啟動後，必須讀 `.planning/LAUNCH_FREEZE.md`（或 sprint 級的等價文件）裡的 AUTONOMY MODE 段落。核心精神：

- **預設不問用戶**：實作層細節（schema 欄位、API DTO 形狀、檔案組織、變數命名）自行決定
- **白名單才問**：規格矛盾、§2 高風險、跨 worktree 影響、用戶可見的業務邏輯文案
- **報告協議**：atomic commit 不報告，push 前簡短報告，phase 完成正式交接

完整模板見 `.planning/LAUNCH_FREEZE.md` 或 §6.2。

### 2.6 Coordinator（主協調者）模式

主 worktree 的 Claude 不寫業務代碼，只做：
- spec 文件管理（OPENSPEC / ROADMAP / PROJECT.md / LAUNCH 級廣播檔）
- 跨 session 衝突仲裁
- 環境問題（AWS / DB / docker）排查
- 用戶 ↔ worker session 之間翻譯

啟動 `/loop` dynamic mode 後，coordinator 還能：
- 每 15-25 分鐘掃 worker pane
- 自動 approve read-only permission prompts（見 §3）
- 偵測 idle / 衝突，寫 `.planning/COORDINATOR_LOG.md`

---

## 3. 權限白名單 — 可 / 不可 bypass

### 3.1 可 bypass（coordinator 自動 approve，不打擾用戶）

| 類別 | 範例 | 為什麼安全 |
|------|------|---------|
| **Read-only diagnostic** | `git status`, `git log`, `git diff`, `ls`, `cat`, `grep`, `awk`（select pattern）, `sed -n '<range>p'`, `find`, `wc`, `head/tail`, `dig`, `tmux list-*`, `colyn ls/info`, `docker ps/logs/inspect`, `docker compose ps/logs` | 純讀取系統 / git / 容器狀態，無副作用 |
| **HTTP GET** | `curl -s/-sS`（只要不是 PUT/POST/DELETE） | 純讀取外部 |
| **Build / Test (idempotent)** | `npm test`, `npx jest`, `npx vitest`, `npx playwright test`, `npm run typecheck/lint/build`, `npx prisma generate` | 不變動代碼 / 資料庫 |
| **Rebase 內部操作** | `git rebase --continue`, `git rebase --abort`, `git rebase --skip`（**已開始的 rebase 內**） | 收尾操作；無新破壞 |
| **複雜 read-only 多行 bash** | git status + branch + log + rev-list + ls 串接 | Claude Code 可能誤判，但內容全部 read-only |
| **MCP tools 帶 read/get/list/search/view** | `mcp__github__list_pull_requests` 等 | tool 本身設計為 read-only |

### 3.2 不可 bypass（coordinator 必停手 + 寫 log，等用戶回來）

| 類別 | 範例 | 為什麼必須用戶批准 |
|------|------|---------|
| **資料/歷史不可逆毀滅** | `rm -rf`, `git push --force`（不含 `--force-with-lease`）, `git reset --hard`, `git clean -fdx`, `git filter-branch` | 數據 / 歷史一旦執行不可回 |
| **資料庫毀滅** | `DROP TABLE`, `TRUNCATE`, `DELETE FROM` 無 WHERE, `npx prisma migrate reset` | 資料丟失 |
| **Secret 變更** | 寫入 `.env*`, `*.pem`, `*.key`, `credentials*.json`, `service-account*.json` | 攻擊面 / 資安 |
| **權限變更** | `sudo`, `su`, `chmod 777`, `chown`, `setfacl` | 系統權限改變不可回 |
| **跳過 hook** | `git commit --no-verify`, `git push --no-verify`, `-c core.hooksPath=/dev/null` | 繞過 R10 / R11 紅線 |
| **直推 main** | `git push origin main`（除非 `ALLOW_MAIN_PUSH=1`） | §1 R9 / §2.5 |
| **Docker 毀滅** | `docker volume rm`, `docker-compose down -v`, `docker system prune -a` | 資料 volume 丟失 |
| **Container 內任意執行** | `docker exec <container> bash/sh` | 可在容器內做任何事 |
| **任意代碼執行** | `node <script>`, `python <script>`, `bash <script>`, `npx <pkg>`, `bunx <pkg>` | wildcard 化 = 後門 |

### 3.3 灰色地帶（依 sprint 緊迫度、case-by-case）

| 類別 | 範例 | 何時放行 / 何時擋 |
|------|------|---------|
| `git push --force-with-lease` | 推剛 rebase 完的 feature 分支 | sprint 內可放行（hook 仍會擋 main）；非 sprint 仍 case-by-case |
| `git stash:*` | rebase 配套 / 暫存 WIP | 建議放行，非毀滅 |
| `git pull --rebase:*` | 同步 main | 建議放行（個人分支，無共用衝突風險） |
| `git rebase <branch>`（新啟動） | 多人協作的分支 reorder | 看 ahead/behind，分歧大時要用戶確認 |
| `npm install <pkg>` / `npm uninstall` | 加套件 | 建議用戶看一下；不擋 sprint |

---

## 4. 衝突處理

### 4.1 跨 worktree DB schema 衝突

**§4.6 序列化**：同時段只允許一個 worktree 跑 `prisma migrate dev`。

協調 protocol：
1. 想動 schema 的 session 先讀 `.planning/HANDOFF.json` 看 `db_lock` 欄位
2. 沒人持有 lock → 寫入 `db_lock: <worktree-name> + timestamp`，commit (`chore: acquire db_lock`)
3. 跑完 migrate → push migration → 刪除 `db_lock`，commit (`chore: release db_lock`)
4. 其他 session 看到 lock 存在 → 只能 `prisma generate`，不可動 schema

### 4.2 多 session 動同一檔

`§4.2.1 反 Race`：
- coordinator 偵測：跨 session diff 同檔
- 通知雙方：「你跟 task-X 都改 `<file>`，先協調再動」
- 仲裁寫入 `.planning/HANDOFF.json` 的 `file_lock` array

### 4.3 Rebase 衝突卡住

- `git rebase --abort` 是逃生口（loop coordinator 可 bypass）
- 衝突的 commit hash 寫入 `COORDINATOR_LOG.md`
- 用戶醒來決定：手動 resolve / 用 `git rebase --skip` 跳過 / 重來

### 4.4 Review-Failure Loop（reviewer ↔ worker ↔ supervisor）

完整 loop、升級條件、仲裁選項、紅線**全部寫在 `dev-rule/WORKFLOW_PROTOCOLS.md` §2**。本節僅列關鍵指針：

- 預設 loop 最多 2 輪 worker ↔ reviewer；第 2 輪未收斂自動升級 supervisor
- 升級觸發：第 2 輪未收斂 / worker 不同意 / reviewer 不確定 / launch-critical 時程壓力
- 通知模板：
  ```
  tmux send-keys -t main:<worker-window>.0 '[REVIEW] PR #N request-changes: <reason>' Enter
  tmux send-keys -t main:0.0 '[REVIEW-ESCALATE] PR #N: <爭議>' Enter
  tmux send-keys -t main:<worker-window>.0 '[ARBITRATION] PR #N: <採納/駁回/拆分>' Enter
  ```
- 紅線：reviewer 不可繞過自己的 REQUEST_CHANGES 直接 APPROVE；supervisor 不可幫 worker 改完代碼後 approve

### 4.5 Context-Full Handoff

任何 session context 將滿時的承接流程**全部寫在 `dev-rule/WORKFLOW_PROTOCOLS.md` §1**。本節僅列關鍵指針：

- 不要等 auto-compact 自動觸發；提前寫 handoff 文件
- 各角色 handoff 落點：supervisor → `COORDINATOR_HANDOFF_<date>.md`；alarm → `COORDINATOR_LOG.md`；reviewer → 進行中的 PR draft；worker → `/gsd:pause-work` 產 phase handoff
- 例外：supervisor 滿沒人可暫代；worker 遇規格爭議停手等

---

## 5. 教訓（從這次 launch 累積）

### 5.1 一定要做

1. **Spec 在 sprint 開始前完整寫進 OPENSPEC + ROADMAP**。Spec 不清 → session 反覆問 → 並行優勢被吃光
2. **第一輪 sprint 用 `/fewer-permission-prompts` skill 預擴 allow list**。預設 settings 太保守，不擴會被擋到瘋
3. **AUTONOMY MODE directive 寫進 sprint 廣播檔（如 LAUNCH_FREEZE.md）**。光放 CLAUDE.md 不夠，session 要看到「現在是 sprint 模式」的明確訊號才會放手做
4. **Stop hook 響鈴**（見 §6.3）。並行 4-5 個 Claude，光看狀態列不夠，要聲音指引哪個 session 完成 turn
5. **Edit/Write deny 鏡像 sensitive files 到所有可能 path**。以前只覆蓋舊 path，新路徑就漏。鏡像 deny 一定要全 path

### 5.2 不要踩

1. **不要替 sibling worktree 動有 WIP 的東西**（§4.2.1 anti-race）。WIP 會被搞壞
2. **不要 wildcard 化任意執行類**（`Bash(node:*)` / `Bash(npx:*)` / `Bash(python:*)`）= 開後門
3. **不要忘記 docker 容器掛載路徑**。重做 colyn 容器後，docker-compose.yml 的 `./` 還是綁舊路徑，prisma migrate / dev server 會找錯 schema
4. **不要直接在 main 上 commit / push**。always feature branch + PR；緊急用 `ALLOW_MAIN_*` 環境變數，但要記在 PR description

### 5.3 token 經濟

| 項目 | 成本估算 |
|------|--------|
| 主 coordinator session（不寫 code） | ~50k token / 12h |
| Worker session（寫 code + test） | ~200k token / 12h × N |
| /loop dynamic mode（每 20 min 醒）| ~5k token / 醒 |
| Spec 重讀（每次 /clear 後 bootstrap）| ~30k token / 次 |

5 session × 12h sprint ≈ 1M token，配 Opus 4.7 約 $15-30 USD。  
**比例上 1 個 phase 平行做完 vs serial 多 5-7 倍速度**，CP 值高但**不要無限延長**。

---

## 6. 附錄

### 6.1 ~/.tmux.conf 推薦設定

```conf
# Bell-only monitoring (no spam)
set -g monitor-bell on
set -g visual-bell off
set -g bell-action any

# Mouse on
set -g mouse on

# Auto-resize
set -g aggressive-resize on

# Bell visual indicator
set -g window-status-bell-style 'bg=red,fg=white,bold'
set -g window-status-activity-style 'bg=yellow,fg=black'

# Sound on bell (macOS)
set-hook -g alert-bell 'run-shell -b "afplay /System/Library/Sounds/Glass.aiff"'
```

### 6.2 AUTONOMY MODE Directive 模板（給 sprint 廣播檔）

```markdown
## AUTONOMY MODE Directive

### 預設行為（不要問）
- spec 已寫於 OPENSPEC + ROADMAP，先讀完才能說「需要規格」
- 實作層細節自己決定，記在 PLAN.md
- /gsd:discuss-phase 加 --auto flag
- 程式碼風格照既有模式
- 「我可以開始嗎」一律不要問，直接做

### 必須問用戶（白名單）
1. 規格真矛盾
2. CLAUDE.md §2 高風險
3. 影響其他 worktree（觸發 db_lock 等）
4. 用戶可見的業務邏輯決策

### 報告協議
- atomic commit 不必報
- push origin 前一句話報
- phase 完成正式交接
```

### 6.3 Claude Code Stop hook 響鈴

`.claude/settings.json`：
```json
"hooks": {
  "Stop": [{
    "matcher": "",
    "hooks": [{ "type": "command", "command": "printf '\\a'" }]
  }]
}
```

每個 turn 結束 → bell character → tmux flag 該 window 變紅 → tmux alert-bell hook 跑 afplay → 聲音定位

### 6.4 .planning/HANDOFF.json schema (建議)

```json
{
  "version": "1.1",
  "timestamp": "2026-05-06T00:00:00.000Z",
  "mode": "parallel-development",
  "primary_branch": "main",
  "active_phases": [...],
  "db_lock": null,
  "file_locks": [],
  "active_workers": [
    {"worktree": "task-2", "branch": "feat/...", "claude_active": true, "last_commit_at": "..."}
  ]
}
```

### 6.5 COORDINATOR_LOG.md 格式

主協調者（loop dynamic mode）每醒一次寫入：

```markdown
## [YYYY-MM-DD HH:MM:SS] iteration N

### auto-approves
- window 2: <command preview> — read-only, approved option 1

### blocked (need user)
- window 3: <command> — §2 high-risk (force push), wrote to log

### idle stalls (> 30 min no progress)
- window 5: last commit 35 min ago, pane shows "thinking" only

### conflicts
- task-2 + task-3 both edited apps/server/src/middleware/auth.ts
```

---

*Generated 2026-05-06 from launch v1 sprint experience.*
*Last revised: 2026-05-07 (added §4.4 Review-Failure Loop pointer + §4.5 Context-Full Handoff pointer to WORKFLOW_PROTOCOLS.md).*

---

## DB Schema Coordination (updated 2026-05-08, replaces manual db_lock commit dance)

### Old (deprecated)
```
git commit -m "chore: acquire db_lock <worktree>"
prisma migrate dev
git commit -m "chore: release db_lock"
```

### New (use db-coord.sh)
```bash
bash scripts/skill.sh db-coord acquire <worktree> <branch> <phase> "<purpose>"
# Output: ACQUIRED | DENIED (held by X for N seconds) | STALE (auto-released)

# Hold lock — refresh heartbeat every 5 min:
bash scripts/skill.sh db-coord heartbeat <worktree>

# Run migration (use docker exec to avoid inline DATABASE_URL leak):
docker exec <db-container> sh -c "cd /app/<workspace> && npx prisma migrate dev --name <migration>"

# Release when done:
bash scripts/skill.sh db-coord release <worktree>
```

### State location
`.planning/HANDOFF.json` field `db_lock` (with `heartbeat` timestamp).
History preserved in `db_lock_history[]`.

### Stale handling
- 15 min without heartbeat → auto-sweep on next `db-coord sweep` call
- Dispatcher runs sweep per tick (5 min cadence)
- Manual sweep: `bash scripts/skill.sh db-coord sweep`

## Docker Resource Coordination (added 2026-05-08)

Docker daemon is R1 scarce resource — single instance shared by all worktrees.

### Held by: supervisor / dispatcher / tester / reviewer
### NOT held by: workers (workers escalate via INBOX)

### Locked operations
- `docker compose down/up/restart/build`
- `docker volume rm` / `docker network rm` / `docker rm`
- `docker exec <container>` with mutating commands (npm install, prisma migrate)

### Unrestricted (no lock needed)
- `docker ps`, `docker images`, `docker logs`, `docker stats`
- `docker exec <container>` with read-only commands (curl, ls, cat, grep)
- `docker exec <container>` with build (read code, write artifact in container)

### Usage
```bash
bash scripts/skill.sh docker-coord acquire <actor> "<op-description>"
# ...mutating docker op...
bash scripts/skill.sh docker-coord release <actor>
```

5 min stale threshold — auto-sweep on next dispatcher tick.
