# 平行開發工具鏈 (Parallel-Dev Tool Stack)

> 本檔列出本專案平行開發 SOP 依賴的 4 套外部工具、用途、檢查方式、安裝方式。
> 執行層腳本見 `scripts/colyn-roles/install-tools.sh`。
> 修改本檔須在 PR 標註 `[DEV-RULE]`，請用戶 review。

---

## 1. 工具矩陣

| 工具 | 用途 | 安裝後落點 | 角色關聯 |
|------|------|----------|---------|
| **colyn** | git worktree + tmux + dev port 編排；多 Claude session 並行的容器層 | binary in `$PATH`（`command -v colyn`）| 全角色（基礎建設）|
| **gsd** (get-shit-done) | meta-prompting + spec-driven dev；本專案 GSD 四階段流程（Discuss/Plan/Execute/Verify）依賴 | `~/.claude/commands/gsd/` 或 `~/.claude/skills/gsd-*` | supervisor + worker |
| **karpathy-guidelines** | LLM coding 行為規範（4 原則：Think / Simplicity / Surgical / Goal-Driven）| `~/.claude/skills/karpathy-guidelines` | reviewer 首要 lens；supervisor / worker 也讀 |
| **GitNexus** | codebase 索引成 knowledge graph；看單次改動的 blast radius / 跨模組依賴 | binary in `$PATH`；MCP for Claude Code | supervisor 仲裁時用；reviewer 大型 PR 時用 |

---

## 2. 檢查邏輯（已裝就跳過）

| 工具 | 偵測方式 |
|------|---------|
| colyn | `command -v colyn` |
| gsd | `[ -d ~/.claude/commands/gsd ]` 或 `ls ~/.claude/skills/ \| grep -qiE '^gsd'` |
| karpathy-guidelines | `[ -d ~/.claude/skills/karpathy-guidelines ]` |
| GitNexus | `command -v gitnexus` |

---

## 3. 安裝方式

### 3.1 一鍵腳本（推薦）

```bash
bash scripts/colyn-roles/install-tools.sh
```

特性：
- 偵測已裝就跳過，**不重複安裝**
- `DRY_RUN=1` 只查不裝（先看狀態）
- `FORCE_REINSTALL=1` 不管已裝強制重跑
- karpathy 因為要在 Claude Code session 內跑 `/plugin` 指令，shell 端只 fallback 下載 CLAUDE.md 到 `/tmp/karpathy-CLAUDE.md`，不自動安裝 plugin

### 3.2 各工具的官方安裝指令（fallback / 手動）

```bash
# 1. colyn
npm install -g colyn-cli
colyn setup

# 2. gsd（互動式 installer，會問 runtime 與 global/local）
npx -y get-shit-done-cc@latest

# 3. karpathy-guidelines（在 Claude Code session 內執行）
/plugin marketplace add forrestchang/andrej-karpathy-skills
/plugin install andrej-karpathy-skills@karpathy-skills

# 4. gitnexus
npm install -g gitnexus
npx gitnexus setup    # 第一次裝完設 MCP for Claude Code
```

---

## 4. 工具與角色的對應

| 角色 | 必裝 | 用途 |
|------|------|------|
| supervisor (tmux-0) | colyn + gsd + GitNexus + karpathy | 編排 / 規格 / 仲裁 blast radius / 行為 lens |
| alarm (tmux-1) | colyn | 只跑監控指令 |
| reviewer (tmux-2) | karpathy + gsd + GitNexus | review lens / 規格對照 / 大型 PR 影響面 |
| worker (tmux-3..6) | colyn + gsd | worktree + 寫碼流程 |

---

## 5. CI / 新人 onboarding 強制檢查

新 worker session 啟動時，**bootstrap 序列**應該包括執行：

```bash
DRY_RUN=1 bash scripts/colyn-roles/install-tools.sh
```

任何 `[MISSING]` 出現 → 該角色無法正常工作，先 install 再開工。

---

## 6. 與其他文件的關係

| 文件 | 關係 |
|------|------|
| `dev-rule/PARALLEL_DEV_SOP.md` | 平行開發 SOP；本檔是其工具層細節 |
| `dev-rule/WORKFLOW_PROTOCOLS.md` | 跨 session 協作 protocol；GitNexus 在 §2 review 升級時用 |
| `scripts/colyn-roles/install-tools.sh` | 本檔的執行層 |
| `scripts/colyn-roles/role-supervisor.md` §工具庫 | 仲裁時的工具決策表 |
| `scripts/colyn-roles/role-reviewer.md` Karpathy lens | karpathy 的 review 應用 |

---

*工具版本變動 / 新增工具請 PR 標 `[DEV-RULE]`，並同步更新 `install-tools.sh` 的偵測邏輯。*
