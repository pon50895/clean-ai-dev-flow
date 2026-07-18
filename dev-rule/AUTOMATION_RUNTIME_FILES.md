# Automation Runtime Files — `.planning/COORD_*` 檔案規範

> 多 AI session（supervisor / sentinel / reviewer / N workers）平行開發時，session 之間靠**檔案訊息傳遞**（not tmux send-keys，因為 send-keys + Enter 在 user 占用 pane 時不可靠）。本檔說明這些 runtime 檔案的格式、讀寫協定、gitignore 策略、rotation 規則。

---

## 1. 檔案總覽

所有 runtime 檔案放在每個 worktree 的 `.planning/` 目錄下。三類：

| 檔案 | 寫入者 | 讀取者 | gitignore | 性質 |
|------|--------|--------|-----------|------|
| `.planning/COORD_INBOX.txt` | sentinel / reviewer | supervisor (coord) | **YES** | runtime queue，action items 等待 coord 處理 |
| `.planning/COORDINATOR_LOG.md` | 全角色 append | 任何人 on-demand `tail` | **YES** | 純 audit trail（HEARTBEAT、auto-approve/deny、state transitions）|
| `.planning/COORDINATOR_HANDOFF_<YYYY-MM-DD>.md` | supervisor | 下一個 supervisor / user 醒來 | **可選**（建議 commit）| session 交接快照，包含當前 fleet state、未決議題、下一步 |

---

## 2. 為什麼 file-only（不用 tmux send-keys）

實戰觀察：
- `tmux send-keys -t main:0 "<text>" Enter` 把訊息送到 user 在用的 pane，行為不穩定：
  - **user 在打字** → 字符插進 user draft，Enter 也按下去 → user 訊息被污染
  - **Claude streaming** → 訊息累積，Enter 不一定 auto-submit
  - **Enter 不可靠** → 約 30-50% 機率訊息卡 input box 不 submit
- File append (`echo "..." >> file`) 100% 可靠：
  - 不影響任何 pane 的 input
  - 接收方主動 poll，無 race condition
  - 可 audit、可 grep、可重播

**唯一例外**：sentinel 對 worker 的 `tmux send-keys -t main:N "1" Enter`（auto-approve）/ `"3" Enter`（auto-deny）— 直接互動 worker prompt UI，無 user 介入該 pane，可靠。

---

## 3. 檔案格式

### 3.1 `.planning/COORD_INBOX.txt`

純文字，**1 行 1 個 action item**。寫入者只 append，從不 modify / delete。

**格式**：
```
[YYYY-MM-DD HH:MM:SS TZ] [<source> <TAG>] <one-line summary>
```

範例：
```
[2026-05-07 04:47:59 CST] [sentinel ESCALATE] main:4 prompt: python3 script (non-standard pattern)
[2026-05-07 04:47:59 CST] [sentinel READY] main:5 just became idle: portal NextJS build green, can recycle
[2026-05-07 04:58:20 CST] [sentinel URGENT] main:3 tried §2 cmd: rm -rf node_modules. denied + logged.
```

**TAG 字典**（sentinel）：
- `URGENT` — sentinel 拒絕了 §2 高風險指令
- `ESCALATE` — sentinel 不知道怎麼處理的 prompt
- `SUSPICIOUS` — worker active >60min 同一 task，可能 stuck
- `READY` — worker 從 ACTIVE 變 IDLE，可能可派下一 task
- `IDLE-15m` / `IDLE-30m` — long idle alert
- `CTX-WARN` / `CTX-FULL` — sentinel 自己 ctx 即將 / 已滿

**TAG 字典**（reviewer）：
- `REVIEW-DONE` — PR 已 review，附 verdict
- `REVIEW-ESCALATE` — PR 規格爭議，需 supervisor 仲裁

### 3.2 `.planning/COORDINATOR_LOG.md`

Markdown append-only。**HEARTBEAT、INFO、auto-approve/deny** 紀錄都進這裡。

**格式**：
```markdown
[YYYY-MM-DD HH:MM:SS TZ] [<source> <category>] <message>
```

範例：
```markdown
[2026-05-07 04:47:00 CST] [SENTINEL ONLINE v3] Haiku 4.5 monitoring main:2/3/4/5/6
[2026-05-07 04:47:30 CST] [HEARTBEAT tick #1] main:2 PROMPT 0m, main:3 PROMPT 0m, main:4 PROMPT 0m, main:5 IDLE 2m, main:6 PROMPT 0m | a:2 d:0 e:2 | ctx:18%
[2026-05-07 04:48:01 CST] sentinel auto-approve main:4: python3 align_env_examples.py
[2026-05-07 04:53:00 CST] [HEARTBEAT tick #2] ...
```

### 3.3 `.planning/COORDINATOR_HANDOFF_<YYYY-MM-DD>.md`

Markdown rich format。Supervisor 在 session 結束前寫，下一個 supervisor 接手或 user 醒來讀。

**必填段落**（不少）：
- §0 用戶當前指示（最近一次 directive）
- §1 PR 狀態（merged / open）
- §N-Role tmux 現況（每個 pane branch + 狀態 + 模型 + ctx %）
- §INBOX 累積（未處理 action items）
- §待 user 決策清單（規格不清項目，supervisor 不能腦補的）
- §自動化模式運作方式（sentinel /loop / supervisor wakeup 設定）
- §user 醒來必看 checklist
- §supervisor 紅線重申
- §失敗回復策略

---

## 4. 寫入協定

### 4.1 INBOX append（sentinel / reviewer 用）

```bash
# Bash echo — 最 portable，不用任何工具
echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] [sentinel ESCALATE] main:N <summary>" \
  >> "${PROJECT_ROOT}/worktrees/sentinel-monitor/.planning/COORD_INBOX.txt"
```

**注意**：
- 用**絕對路徑**（避免不同 worktree cwd 寫到不同檔案）
- **never** 用 `cat >>` 加 heredoc（複雜引號容易出錯）
- **never** 用 Edit/Write tool（pre-commit hook 可能擋 .planning 改動）

### 4.2 LOG append（全角色用）

```bash
echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] [HEARTBEAT tick #N] <fleet status>" \
  >> "${PROJECT_ROOT}/.planning/COORDINATOR_LOG.md"
```

**注意**：
- COORDINATOR_LOG 建議**只一份**（main worktree 路徑），所有 worktree 都寫到同一個檔避免分散
- 但 COORD_INBOX 可以**多份**（每個 worktree 各自）— coord 輪詢時讀全部

### 4.3 HANDOFF write（supervisor 用）

```bash
# 一次寫整份，覆蓋 OK（不是 append）
cat > "${PROJECT_ROOT}/.planning/COORDINATOR_HANDOFF_$(date +%Y-%m-%d).md" <<'EOF'
# Coordinator Handoff — YYYY-MM-DD

## 0. 用戶當前指示
...
EOF
```

或用 Claude Code 的 Write tool（前提：當前 worktree 沒 deny `.planning/**` 的 Write）。

---

## 5. 讀取協定

### 5.1 Coord poll INBOX（每 30 min）

```bash
# 顯示 INBOX 全部（檔案應 < 100 行；rotation 後保證）
cat "${PROJECT_ROOT}/worktrees/sentinel-monitor/.planning/COORD_INBOX.txt"

# 或只看新增（須維護自己的 last-seen line number）
# 簡單做法：標記處理過的 entry 加 [done] 字尾，下次 grep -v '\[done\]'
```

### 5.2 User 醒來看 LOG

```bash
# 最近 40 行
tail -40 "${PROJECT_ROOT}/.planning/COORDINATOR_LOG.md"

# 最近 1 小時
awk -v cutoff="$(date -v-1H '+%Y-%m-%d %H:%M:%S')" '$0 >= "[" cutoff' \
  "${PROJECT_ROOT}/.planning/COORDINATOR_LOG.md"
```

### 5.3 Reviewer 已 review 的 PR list

```bash
# REVIEWER_SEEN.txt 也是同類 runtime queue
cat "${PROJECT_ROOT}/.planning/REVIEWER_SEEN.txt"
# 內容：每行一個 PR 編號
```

---

## 6. `.gitignore` 策略

開源專案建議：

```gitignore
# === Multi-AI Session Runtime Files ===
# These contain transient state from sentinel/reviewer/coord ticks.
# Per-developer machine local; never commit.
.planning/COORD_INBOX.txt
.planning/COORDINATOR_LOG.md
.planning/REVIEWER_SEEN.txt
.planning/HANDOFF.json

# Per-session backups
.planning/*.local-backup
.planning/*.bak.*

# Coordinator handoffs are useful audit trail; KEEP committable
# (don't add COORDINATOR_HANDOFF_*.md to gitignore)
```

**HANDOFF 為什麼建議 commit**：
- 隊友能 review 過往決策
- post-mortem 用得上
- 公開 OSS 專案展示「這個專案怎麼用 AI 開發」有教育價值
- 檔名有日期，自然 timestamp，無需 rotation

**INBOX / LOG 為什麼不 commit**：
- 純 runtime queue，commit 會炸 git history
- 含本機絕對路徑、tty 路徑等 environment-specific 資訊
- 多 dev / 多機器同時跑會 merge conflict 爆炸

---

## 7. Rotation 策略

INBOX 跟 LOG 都會無限長大，需要 rotation。

### 7.1 INBOX rotation（建議：daily + size 雙閾值）

```bash
# scripts/rotate-coord-inbox.sh
#!/usr/bin/env bash
INBOX="${PROJECT_ROOT}/worktrees/sentinel-monitor/.planning/COORD_INBOX.txt"
ARCHIVE_DIR="${PROJECT_ROOT}/.planning/archive"
mkdir -p "$ARCHIVE_DIR"

# Trigger: 檔案 > 1MB 或最後一行 timestamp > 24h 前
if [ -f "$INBOX" ]; then
  size=$(wc -c < "$INBOX")
  if [ "$size" -gt 1048576 ]; then
    mv "$INBOX" "$ARCHIVE_DIR/COORD_INBOX-$(date +%Y%m%d-%H%M).txt"
    : > "$INBOX"
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] [INBOX rotated] size was ${size} bytes" \
      >> "${PROJECT_ROOT}/.planning/COORDINATOR_LOG.md"
  fi
fi
```

每日 cron：`0 3 * * * /path/to/rotate-coord-inbox.sh`

### 7.2 LOG rotation（建議：daily roll + 7 day retention）

```bash
# scripts/rotate-coord-log.sh
#!/usr/bin/env bash
LOG="${PROJECT_ROOT}/.planning/COORDINATOR_LOG.md"
ARCHIVE_DIR="${PROJECT_ROOT}/.planning/archive"
mkdir -p "$ARCHIVE_DIR"

# Daily roll
if [ -f "$LOG" ]; then
  mv "$LOG" "$ARCHIVE_DIR/COORDINATOR_LOG-$(date -v-1d +%Y%m%d).md"
  echo "# COORDINATOR LOG — $(date '+%Y-%m-%d')" > "$LOG"
fi

# 7-day retention
find "$ARCHIVE_DIR" -name 'COORDINATOR_LOG-*.md' -mtime +7 -delete
find "$ARCHIVE_DIR" -name 'COORD_INBOX-*.txt' -mtime +30 -delete  # INBOX 留久一點
```

cron：`0 0 * * * /path/to/rotate-coord-log.sh`

### 7.3 HANDOFF（不 rotate，靠檔名 date）

每天的 HANDOFF 自然有 `COORDINATOR_HANDOFF_2026-05-07.md` 這種 date-based 檔名，無需 rotation。

舊的 HANDOFF 想清就 `rm` 或移到 `archive/`，但通常留著無妨（每份 < 50KB）。

---

## 8. 多 worktree path 問題

每個 worktree 有自己的 `.planning/`。實踐建議：

| 檔案 | 落點 |
|------|------|
| INBOX | sentinel 自己的 worktree（`worktrees/sentinel-monitor/.planning/COORD_INBOX.txt`）|
| LOG | main worktree（`<root>/.planning/COORDINATOR_LOG.md`）— 統一一份 |
| HANDOFF | main worktree |

理由：
- INBOX 是 sentinel 主 owner，放 sentinel 邊
- LOG 是全角色寫的 audit，放 main 共用
- HANDOFF 是 main worktree 的 supervisor 寫，自然在 main

每個寫者用**絕對路徑**避免錯。範例 SENTINEL.md：
```bash
echo "..." >> /Users/<you>/Desktop/<project>/main/.planning/COORDINATOR_LOG.md
echo "..." >> /Users/<you>/Desktop/<project>/worktrees/sentinel-monitor/.planning/COORD_INBOX.txt
```

或用環境變數：
```bash
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel)/..}"
echo "..." >> "${PROJECT_ROOT}/main/.planning/COORDINATOR_LOG.md"
```

---

## 9. AI 自我檢查（每個 role session 啟動跑）

- [ ] `.planning/COORD_INBOX.txt` 路徑我用的是絕對 path 還是相對？絕對才對
- [ ] 我是 sentinel/reviewer：寫 INBOX **不要** 用 tmux send-keys to main:0
- [ ] 我是 supervisor：每 30 min `cat INBOX`，處理新項目
- [ ] LOG / INBOX 檔有沒有 > 1MB？有 → rotate
- [ ] `.gitignore` 有沒有 cover INBOX、LOG？沒有 → 補

---

## 10. 與其他文件的關係

| 文件 | 關係 |
|------|------|
| `dev-rule/CLAUDE.md` §4 | 平行開發協定（worktree、cwd、handoff 總綱） |
| `dev-rule/WORKFLOW_PROTOCOLS.md` §1 | Context-Full Handoff Protocol — 啟動 / 收尾用 HANDOFF 檔的時機 |
| `dev-rule/PARALLEL_DEV_SOP.md` §6.5 | COORDINATOR_LOG 格式（早期版本） |
| `dev-rule/ai-architecture/SENTINEL.md` | sentinel 的寫入 protocol（INBOX TAGs 字典 etc） |
| `dev-rule/ai-architecture/COORDINATOR.md` | coord 的讀取 protocol（poll cadence etc） |

---

*Initial: 2026-05-07. Drawn from launch v1 sprint experience where tmux send-keys 對 user 占用的 pane 證實不可靠，改全 file-based。*
