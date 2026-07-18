# 多 Session 協作 Protocols (Workflow Protocols)

> 本檔補強 CLAUDE.md §4「平行開發協定」與 dev-rule/PARALLEL_DEV_SOP.md 沒寫到的兩個關鍵 loop：
> 1. Context-Full Handoff — 任何 session context 將滿時的承接流程
> 2. Review-Failure Loop — reviewer request-changes 後的收斂流程
>
> 修改本檔須在 PR 標註 `[DEV-RULE]`，請用戶 review。

---

## 1. Context-Full Handoff Protocol

### 1.1 觸發條件（任一即動工）

- Claude Code 顯示「context 即將壓縮」/「auto-compact 即將觸發」提示
- 主動估：回應頻繁截斷 / 模型開始忘記 session 早期決策 / 多次重新讀同一份檔
- token 用量已達單 session 預算上限（參考 `dev-rule/PARALLEL_DEV_SOP.md` §5.3 token 經濟）

> **不要等 auto-compact 自動觸發**。自動壓縮會丟關鍵上下文，handoff 文件比 auto-compact 可靠。

### 1.2 預設規則：**同角色、新 session 接棒**

| 角色 | Handoff 落點 | 新 session 啟動序列 |
|------|--------------|-------------------|
| supervisor (tmux-0) | `.planning/COORDINATOR_HANDOFF_<YYYY-MM-DD-HHMM>.md` | 見 §1.6 六步驟交接協議（舊 coord 自己啟動新 coord + swap window） |
| alarm (tmux-1) | `.planning/COORDINATOR_LOG.md`（append-only，天然可續）| `bash scripts/colyn-roles/roles.sh alarm` |
| reviewer (tmux-2) | 進行中 review 留 draft 在 PR；`gh pr list` 自然查得到 | `bash scripts/colyn-roles/roles.sh reviewer` |
| worker (tmux-3..6) | `/gsd:pause-work` 產出的 phase-level handoff | `/gsd:resume-work`，或新 worker `bash scripts/colyn-roles/roles.sh worker <name>` |

### 1.3 Handoff 文件最低必填欄位

```markdown
# COORDINATOR_HANDOFF_<date>.md（範例給 supervisor 角色，其他角色比照）

## 接棒指引（Bootstrap for next session）
- CWD: <絕對路徑>
- Branch: <branch-name>
- Active phase: <phase-id>
- Last commit: <sha> @ <timestamp>

## 進行中（In-flight）
- [ ] <未完待辦 1>
- [ ] <未完待辦 2>

## 已決定（Decisions made this session）
- <關鍵決策 1，附理由>
- <關鍵決策 2，附理由>

## 未決定（Open questions）
- <要等 user 回答的事 1>
- <要等 user 回答的事 2>

## 紅線提醒（Red lines hit / risks）
- <本 session 差點踩紅線的事>
```

不可少的：CWD、Branch、未完待辦、未決定問題。

### 1.4 例外：跨角色升級鏈（當預設無法走）

| 情境 | 升級對象 | 限制 |
|------|---------|------|
| alarm 滿 + 沒人接 | supervisor 暫兼 alarm | Opus 大才小用；只是暫代，下個 idle 窗口起新 alarm session |
| reviewer 滿 + 沒人接 | supervisor 暫兼 review | **不可 review 自己仲裁過的 spec**（避免球員兼裁判）；該 PR 跳過 |
| worker 滿 + phase 緊急 | supervisor 指派**另一個 worker** 透過 HANDOFF 接 | **禁止**直接讓 supervisor 寫業務代碼（§supervisor 紅線：仲裁者不寫業務代碼） |
| supervisor 滿 | **無人可暫代** | user 開新 supervisor session 期間，worker 遇規格爭議**停手等**，不要自己決策 |

### 1.5 紅線

- **不要在 context 已經壓縮過後才寫 handoff**：壓縮後的 session 已可能失去早期關鍵決策，handoff 內容會殘缺
- **不要把 handoff 內容直接塞給新 session 當 user message**：會炸 token；新 session 應該在啟動序列裡讀 handoff 文件
- **handoff 文件的 path 要絕對化**：寫 `apps/server/src/...` 不夠，要 `/absolute/path/to/your-project/apps/server/src/...`，避免 cwd 不一致時找不到

---

## 2. Review-Failure Loop（Reviewer ↔ Worker ↔ Supervisor）

### 2.1 預設 Loop（worker ↔ reviewer，最多 2 輪）

```
worker push PR
  ↓
reviewer 走 Karpathy lens (4 條) + OWASP R1-R10 + GSD/UI/法律 checklist
  ↓
[REQUEST_CHANGES]
  ↓
reviewer ping worker：
  tmux send-keys -t main:<worker-window>.0 \
    '[REVIEW] PR #<N> request-changes: <一句話原因>' Enter
  ↓
worker 讀 PR comments → 修 → push 新 commit → 在 PR 留言「ready for re-review」
  ↓
reviewer 二審
  ↓
APPROVE → supervisor 合併 PR（或 worker 走 §2.5.1 自我合）
或
REQUEST_CHANGES（第 2 輪）→ 升級 supervisor 仲裁（§2.2）
```

### 2.2 升級 supervisor 的觸發條件（任一即升級）

| 觸發 | 描述 |
|------|------|
| 第 2 次 request-changes 後仍未收斂 | 避免 ping-pong 浪費 token |
| worker 不同意 reviewer 意見 | 規格 / 設計層級分歧；必須仲裁 |
| reviewer 自己不確定 | 規格本身歧義（不是 worker 的鍋）→ 應 COMMENT 而非 REQUEST_CHANGES，並 ping supervisor 求釋疑 |
| launch-critical 時程壓力 | reviewer 提非阻擋級建議（風格 / small refactor），worker 主張延後 → supervisor 決定「現在改 vs 進 backlog」 |

### 2.3 升級時的通知格式

```
tmux send-keys -t main:0.0 \
  '[REVIEW-ESCALATE] PR #<N>: worker 與 reviewer 在 <議題> 不同意，請仲裁' Enter
```

附帶：把 PR link 與爭議的 comment thread link 寫進 `.planning/COORDINATOR_LOG.md`，paper trail 不可缺。

### 2.4 Supervisor 仲裁時的選項

| 仲裁結果 | 後續動作 |
|---------|---------|
| **採納 reviewer** | tmux send-keys 給 worker：「按 reviewer 改」 |
| **駁回 reviewer** | 在 PR comment 寫仲裁理由（**paper trail，未來人能看到 why**），reviewer 改 APPROVE |
| **拆分**：阻擋級必改、建議級進 backlog | worker 修阻擋級；建議級寫進 `.planning/POST_LAUNCH_TECH_DEBT.md` |
| **重新規劃**：發現 PLAN.md 本身有錯 | 撤回 PR，回 `/gsd:discuss-phase` 重來 |

仲裁結果通知：

```
tmux send-keys -t main:<worker-window>.0 \
  '[ARBITRATION] PR #<N>: <採納/駁回/拆分>，理由：<一句話>' Enter
```

### 2.5 紅線

| 角色 | 不可做 | 為什麼 |
|------|-------|-------|
| reviewer | **不可繞過自己的 REQUEST_CHANGES 直接 APPROVE** | 「算了 approve 算了」會把問題推給未來；要放行只能由 supervisor 仲裁駁回 |
| reviewer | **不可替 worker 改代碼** | 角色分工：reviewer 留 comment，worker 修 |
| worker | **不可在 reviewer 重看前強行 merge** | 例外只有 §2.5.4 緊急 hotfix，且必須 supervisor 明確指示 + `hotfix/` 分支 |
| worker | **不可 force-push 蓋掉 reviewer 看過的 commit hash** | 保留歷史方便對比；要重整就用新 commit on top |
| supervisor | **不可幫 worker 改完代碼後 approve** | 仲裁者寫業務代碼是越權；要動由 worker 動，supervisor 只下指令 |
| supervisor | **不可仲裁同時又是 PR review approver** | 球員兼裁判；仲裁完讓 reviewer（或新 reviewer session）走完正常 review 才合 |

### 2.6 例外：reviewer 不在線時的時程壓力

如果 reviewer session 還沒就緒（context 滿、未啟動、user 還沒 attach），而 PR 有合併壓力：

1. **預設**：等 reviewer。CI 通過 + worker 自我 checklist（PR description 列 Karpathy lens 自評）即可進入「等 review」狀態，但**不可合**
2. **緊急例外**（hotfix only，§2.5.4）：supervisor 親自做 mini-review（不走 Karpathy 完整 lens，只做安全檢查），合併後 24 小時內補完整 reviewer 二審 + post-mortem

---

## 3. 與其他文件的關係

| 文件 | 關係 |
|------|------|
| `CLAUDE.md` §4.3 | 上下文交接總綱 → 本檔 §1 是其執行細則 |
| `dev-rule/AI_INSTRUCTIONS.md` §4 | 對話臨界壓縮 → 本檔 §1 是其分角色版本 |
| `dev-rule/GSD_WORKFLOW.md` §2.4 | 驗證階段 → 本檔 §2 是「驗證後 review 不過」的延伸 |
| `dev-rule/PARALLEL_DEV_SOP.md` §4 | 衝突處理 → 本檔 §2 補上「review 衝突」這條 |
| `scripts/colyn-roles/role-*.md` | 各 role 角色卡引用本檔 §1 §2 |

---

## 4. AI 自我檢查（任何 role 啟動後跑一遍）

- [ ] 我這個 session 是否從 handoff 文件啟動？讀過 §1.3 必填欄位嗎？
- [ ] 我目前的 context 用量大概到哪？快滿前要寫 handoff 嗎？
- [ ] 如果我是 reviewer / worker，現在卡在 review loop 第幾輪？要不要升級 supervisor？
- [ ] 我是否在做超出我 role 紅線的事（reviewer 改 code / supervisor 寫業務代碼 / worker 強行 merge）？

---

*規範層 SSOT。執行層腳本見 `scripts/colyn-roles/`。*
