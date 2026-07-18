# colyn-roles — 平行 Claude 角色啟動腳本

> 對應 CLAUDE.md §4「平行開發協定」與 dev-rule/PARALLEL_DEV_SOP.md。
> 本目錄是「執行層」腳本；規則層在 dev-rule/，兩者勿混。

---

## 角色矩陣

| tmux idx | 角色 | 預設模型 | Worktree | 主要職責 |
|---------|------|---------|----------|---------|
| 0 | **supervisor**（仲裁者）| `claude-opus-4-7` | `main/` | 規格仲裁、跨 worktree 衝突解析、指派任務、決定 worker 模型 |
| 1 | **alarm** | `claude-haiku-4-5-20251001` | `worktrees/sentinel-monitor` | 監控 idle / bell / CI 紅燈，必要時呼叫 supervisor |
| 2 | **reviewer** | `claude-sonnet-4-6` | `worktrees/reviewer-monitor` | 對 PR / commit 做代碼 + 規格雙審 |
| 3 | worker (task-2) | `claude-sonnet-4-6` | `worktrees/task-2` | 寫碼；模型由 supervisor 依難度上調至 opus |
| 4 | worker (task-3) | `claude-sonnet-4-6` | `worktrees/task-3` | 同上 |
| 5 | worker (task-4) | `claude-sonnet-4-6` | `worktrees/task-4` | 同上 |
| 6 | worker (task-5) | `claude-sonnet-4-6` | `worktrees/task-5` | 同上 |

**模型版本決策說明**
- Supervisor → Opus 4.7：仲裁需要最強推理。
- Alarm → Haiku 4.5：監控只看 status，token 越省越好。
- Reviewer → Sonnet 4.6（不是 4.5）：4.6 為最新一代，能力上沒理由退回 4.5；Opus 留給仲裁。
- Worker → Sonnet 4.6 預設；遇 launch-critical / 跨模組重構 / 演算法設計，supervisor 可指示某個 worker 切 Opus 4.7。

---

## 統一視覺面板（高度比例 50% / 25% / 25%）

`start.sh` / `restart.sh` 都會建出 `main:roles` 這個獨立 window，把 7 個角色塞進同一視窗：

```
+-------------------------------------------------+
|                                                 |
|   [tmux-0] SUPERVISOR        Opus 4.7           |  上 50%
|   cwd: main/                                    |
|                                                 |
+--------------+--------------+-------------------+
| [tmux-1]     | [tmux-2]     | [tmux-3]          |
| ALARM        | REVIEWER     | WORKER task-2     |  中 25%
| Haiku 4.5    | Sonnet 4.6   | Sonnet 4.6        |
+--------------+--------------+-------------------+
| [tmux-4]     | [tmux-5]     | [tmux-6]          |
| WORKER       | WORKER       | WORKER            |  下 25%
| task-3       | task-4       | task-5            |
+--------------+--------------+-------------------+
```

---

## 工具鏈安裝

第一次設置或新機器，先跑工具檢查 + 安裝：

```bash
bash scripts/colyn-roles/install-tools.sh           # 已裝就跳過
DRY_RUN=1 bash scripts/colyn-roles/install-tools.sh   # 只查不裝
```

涵蓋 colyn / gsd / karpathy-guidelines / gitnexus 四套；規範細節見 `dev-rule/TOOLS_INSTALL.md`。

---

## 三個入口腳本

### 1. `start.sh` — 手動冷啟（用戶執行）
```bash
bash scripts/colyn-roles/start.sh
```
- 檢查 / 建立 tmux session `main`
- 建立 7 個獨立 window（windows 0..6，與目前 colyn 編號對齊）
- 額外建立 `main:roles` 統一視覺 window（50/25/25 layout）
- 在每個 pane 啟動正確角色 + 正確模型 + 正確 system prompt
- 已存在的 Claude session **不會被 kill**（idempotent）；只在 pane 是 zsh / 空 shell 時 exec claude

### 2. `restart.sh` — tmux 死掉後復活
```bash
bash scripts/colyn-roles/restart.sh
```
- 偵測 session `main` 是否還在；不在就重建
- 比對既有 windows 與目標佈局，補齊缺失的 window
- 強制重啟「Claude session 已掉線」的 pane（用 ps 檢測 PID 是否存活）
- 適用情境：macOS 重開機、`tmux kill-server` 之後、容器重啟

### 3. `roles.sh` — 單一 pane 角色啟動（給已 attach 的 pane 用）
```bash
# 在已 attach 進去的 pane 跑：
bash scripts/colyn-roles/roles.sh supervisor
bash scripts/colyn-roles/roles.sh alarm
bash scripts/colyn-roles/roles.sh reviewer
bash scripts/colyn-roles/roles.sh worker task-3
bash scripts/colyn-roles/roles.sh worker task-3 claude-opus-4-7   # supervisor 升級指令
```

第三個參數可覆寫模型。

---

## 既有 Claude 怎麼換模型（不要 kill 重啟）

對「已經跑著 Claude 在工作」的 pane，**不要** kill。直接在該 pane 內輸入：
```
/model claude-sonnet-4-6
/model claude-opus-4-7
```

只有「pane 是空 zsh」或「Claude 已掉線」的 pane 才走 `roles.sh`。

---

## 環境變數

| 變數 | 預設 | 用途 |
|------|------|------|
| `WORKSPACE_ROOT` | `$HOME/Desktop/parallel-dev-workspace` | colyn 容器根（含 `main/` 與 `worktrees/`）|
| `TMUX_SESSION` | `main` | tmux session 名 |
| `UNIFIED_WIN` | `roles` | 統一視窗 window 名 |
| `WORKER_MODEL` | `claude-sonnet-4-6` | worker 預設模型 |
| `WORKER_NAMES` | `task-2 task-3 task-4 task-5` | worker worktree 名單（空白分隔）|

---

## 與 colyn 的角色分工

| 動作 | 工具 |
|------|------|
| 建 worktree + tmux window + `.env.local` PORT 偏移 | `colyn add feat/<branch>` |
| 在 pane 內啟 Claude（角色 + 模型 + system prompt）| 本目錄 `roles.sh` / `start.sh` / `restart.sh` |
| 退 worktree | `colyn rm <name>` 或 `git worktree remove` |

---

## Workflow Protocols（規範層）

兩個跨角色的協作 loop 全部寫在 `dev-rule/WORKFLOW_PROTOCOLS.md`：

| 章節 | 內容 | 涉及角色 |
|------|------|---------|
| §1 Context-Full Handoff Protocol | 任何 session context 將滿時的承接流程；落點檔；跨角色升級鏈；紅線 | 全角色 |
| §2 Review-Failure Loop | reviewer request-changes 後的收斂；升級 supervisor 的觸發；仲裁選項；紅線 | reviewer / worker / supervisor |

每張 `role-*.md` 角色卡末段的「Workflow Protocols」段都引用此檔，作為 SSOT。
本目錄是執行層腳本；規則層在 `dev-rule/`，**修改 dev-rule/ 必須走 PR 標 `[DEV-RULE]`**。

---

*Last revised: 2026-05-07*
