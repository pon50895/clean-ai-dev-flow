# PREREQUISITES — 前置需求

> 裝完這份清單再走 [`GETTING_STARTED.md`](./GETTING_STARTED.md)。每一項都寫：為什麼需要、怎麼裝（Mac，brew 優先）、怎麼驗證裝好了。
> 只用「原生 subagent」路徑的話，前 6 項（含 Homebrew）是必須；後兩項（ponytail、karpathy-guidelines）是 feature-pipeline 驗證階段會用到，強烈建議一起裝。
> 要走進階 tmux fleet 的話，另外還需要 `dev-rule/TOOLS_INSTALL.md` 列的 colyn / gsd / GitNexus，那些是 fleet 專屬，不在這份清單。
> 全新 Mac、想一次裝完第 0-5 項，直接跑 committed script：[`scripts/install-prereqs.sh`](./scripts/install-prereqs.sh)（見清單最後一節）。

---

## 清單總覽

| # | 工具 | 必要性 |
|---|---|---|
| 0 | Homebrew | 必須——下面第 2、3、4 項的 `brew install` 都靠它；全新 Mac 預設沒裝 |
| 1 | Claude Code CLI | 必須——整條 dev-flow 跑在它裡面 |
| 2 | gh（GitHub CLI） | 必須——PR create/ready/merge、看板查詢都靠它 |
| 3 | node + npm | 必須——committed hooks 是 Node script |
| 4 | git ≥ 2.30 | 必須——worktree 平行開發 + hook 機制需要新版 |
| 5 | git hooks 接線（`core.hooksPath`） | 必須——沒接線，repo 帶的 hook 檔案是死的 |
| 6 | ponytail skill（plugin） | 建議——feature-pipeline 驗證階段的過度工程檢查 |
| 7 | karpathy-guidelines skill | 建議——feature-pipeline 每個 code 改動預設套用的工程心法 |

---

## 0. Homebrew

**為什麼需要**：下面第 2 項（gh）、第 3 項（node）、第 4 項（git）都用 `brew install` 裝。一台全新 Mac 預設沒有 Homebrew，直接照抄後面的指令會在第一個 `brew install gh` 就失敗，錯誤訊息是 `command not found: brew`，跟後面任何一步都無關，容易讓第一次用的人卡住。

**前置條件**：Homebrew 安裝過程會自動檢查並在需要時觸發安裝 Xcode Command Line Tools（第一次會跳出系統對話框，需要你手動點「安裝」，可能要等幾分鐘）；過程也可能要求輸入你的 Mac 登入密碼（`sudo`）。這是 Homebrew 官方安裝腳本本身的行為，不是這份文件加的步驟。

**怎麼裝**：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

裝完官方腳本會印出一段 `eval "$(/opt/homebrew/bin/brew shellenv)"`（Apple Silicon）或 `/usr/local/bin/brew shellenv`（Intel）——**照著印出的指令貼到終端機執行一次**，並貼進你的 `~/.zprofile`（腳本通常會問你要不要自動加），否則新開的終端機視窗還是找不到 `brew`。

**怎麼驗證**：

```bash
brew --version
```

預期印出版本號，例如 `Homebrew 4.x.x`。

---

## 1. Claude Code CLI

**為什麼需要**：整條 dev-flow（skills、agents、hooks、模型調度）都跑在 Claude Code 裡面。沒有它，`.claude/skills/`、`.claude/hooks/`、agent 派工全部是不會被執行的靜態檔案。

**怎麼裝**：

```bash
npm install -g @anthropic-ai/claude-code
```

若 Homebrew 有對應 formula 也可以：

```bash
brew install claude-code
```

（若上面指令找不到 formula，用 npm 那行即可，這是官方發布管道。）

**怎麼驗證**：

```bash
claude --version
```

預期輸出版本號，例如 `1.x.x`。第一次用還需要登入一次：`claude`（進入後照提示走 OAuth 登入）。

---

## 2. gh（GitHub CLI）

**為什麼需要**：`dev-rule/PROJECT_BOARD_WORKFLOW.md` 與 feature-pipeline 的 Ship 階段都用 `gh` 做 PR create/ready/merge、查看板狀態。這個 clean repo 沒有自己包一層 gh wrapper，直接依賴系統裝好的 `gh`。

**怎麼裝**：

```bash
brew install gh
gh auth login
```

`gh auth login` 走互動流程：選 `GitHub.com` → 選 `HTTPS` → 選瀏覽器授權（或貼 token）。

**怎麼驗證**：

```bash
gh --version
gh auth status
```

預期 `gh auth status` 印出 `Logged in to github.com as <你的帳號>`。

---

## 3. node + npm

**為什麼需要**：repo 內 committed 的 hook 是 Node script（`.claude/hooks/redline-guard.js`、`.claude/hooks/git-readonly-approve.js`），`scripts/*.sh` 也預期系統有 node。沒有 node runtime，這些 hook 不會觸發，R1/R9 這類機器化的擋線形同虛設。

**怎麼裝**：

```bash
brew install node
```

**怎麼驗證**：

```bash
node --version
npm --version
```

預期都印出版本號（建議 node ≥ 18）。再驗證 hook 檔案本身可執行：

```bash
node -e "require('<clean-ai-dev-flow-path>/.claude/hooks/redline-guard.js')" 2>&1 | head -1
```

沒有 `Cannot find module` 之類的錯誤即可（這個 hook 是被 Claude Code 呼叫的，不是拿來直接 require 執行的库，這裡只是確認 node 能解析這個檔案語法）。

---

## 4. git ≥ 2.30

**為什麼需要**：`dev-rule/PARALLEL_DEV_SOP.md` 的 worktree 平行開發，以及 `.githooks/` 的 pre-commit/pre-push gate，都依賴較新版 git 的 `git worktree` 穩定行為與 `core.hooksPath` 支援（`core.hooksPath` 從 git 2.9 就有，但 worktree 相關修正在 2.3x 系列才穩定）。

**怎麼裝**：

```bash
brew install git
```

裝完記得確認 `which git` 指向 brew 版本而不是系統內建的舊版（macOS 內建 git 版本常年落後）：

```bash
which git
```

若印出 `/usr/bin/git`，把 `/opt/homebrew/bin`（Apple Silicon）或 `/usr/local/bin`（Intel）加進 `PATH` 且排在 `/usr/bin` 前面。

**怎麼驗證**：

```bash
git --version
```

預期 `git version 2.30` 以上，建議 2.4x。

---

## 5. git hooks 接線（`core.hooksPath`）

**為什麼需要**：這是最容易漏、也最容易造成「以為有 gate 其實沒有」的一步。`.githooks/pre-commit`（gitleaks 秘密掃描）與 `.githooks/pre-push`（push 前本機測試）這兩個檔案存在於 repo 裡，但 git 預設只認 `.git/hooks/`，不會自動執行 `.githooks/` 下的東西。沒有這一步，README 和腳本描述的 R1/R10/ponytail 這類 gate 在新 clone 的環境裡完全不會被觸發。

**怎麼裝**（在你的目標專案內執行，clone 完/複製完 `.githooks/` 之後跑一次）：

```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push
```

**怎麼驗證**：

```bash
git config core.hooksPath
```

預期輸出 `.githooks`。再實測一次 pre-commit 是否真的會跑：

```bash
git commit --allow-empty -m "test: verify hooks wired"
```

預期看到 `.githooks/pre-commit` 印出的訊息（有裝 gitleaks 會跑掃描；沒裝會印 `[pre-commit] WARNING: gitleaks not installed`，但仍會放行——這是設計上不讓第一次用的人被卡死，見該檔案內註解）。跑完記得把這個測試 commit reset 掉：`git reset --soft HEAD~1`。

---

## 6. ponytail skill（plugin）

**為什麼需要**：`.claude/skills/feature-pipeline/SKILL.md` 的驗證階段（第 4 階）把「過度工程」列為固定檢查維度之一，執行者是 `ponytail` 這個 plugin skill。它不是 bundle 在這個 repo 裡的檔案，是透過 Claude Code 的 plugin marketplace 機制另外安裝的，新環境不會自動有。

**怎麼裝**：進入一個 Claude Code session，執行：

```
/plugin marketplace add DietrichGebert/ponytail
/plugin install ponytail@ponytail
```

（來源：[github.com/DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail)，MIT 授權的公開 plugin marketplace repo。若這個來源將來失效，用 `/plugin marketplace list` 或 `/plugin search ponytail` 在 session 內查詢目前可用的替代來源。）

**怎麼驗證**：在 Claude Code session 裡打 `/ponytail-help`，預期印出 ponytail 各模式/指令的快速參考卡，而不是「找不到指令」。

---

## 7. karpathy-guidelines skill

**為什麼需要**：feature-pipeline 的第 3 階（分派開發）明講「每個 code 改動預設套用 karpathy-guidelines（想清楚、簡潔優先、精準修改、目標驅動可驗證）」。這是一份行為準則 skill，依照 Claude Code 的 skill 機制放在 `~/.claude/skills/`（使用者層級，不是 repo 內的 `.claude/skills/`），所以它**不會**隨這個 repo 一起被 git clone 帶過去；換一台新機器要重新裝一次。

**怎麼裝**：這份 skill 沒有已知的公開 plugin marketplace 發布管道，所以這個 repo 直接把 `SKILL.md` 內容 bundle 進 [`dev-rule/templates/karpathy-guidelines-SKILL.md`](./dev-rule/templates/karpathy-guidelines-SKILL.md)——clone 這個 repo 就帶到手，不需要另外找來源。複製到使用者層級即可：

```bash
mkdir -p ~/.claude/skills/karpathy-guidelines
cp dev-rule/templates/karpathy-guidelines-SKILL.md ~/.claude/skills/karpathy-guidelines/SKILL.md
```

重點是它要落在**使用者層級**（`~/.claude/skills/`），不是專案層級（`.claude/skills/`），否則跳槽到新機器又要重複這一步。

**怎麼驗證**：

```bash
ls ~/.claude/skills/ | grep -i karpathy
```

預期印出 `karpathy-guidelines`（或含該字樣的目錄名）。也可以在 Claude Code session 裡直接問：「這個環境有 karpathy-guidelines skill 嗎？列出它的四個核心原則。」預期回覆列出：想清楚、簡潔優先、精準修改、目標驅動。

---

## 一鍵安裝 script（已是 repo 內 committed 檔案，clone 完就能跑）

涵蓋第 0-5 項（Homebrew + 工具本體 + hooks 接線）。第 6、7 項是 plugin/skill，需要在 Claude Code session 內互動安裝，腳本只能在結尾印出提醒指令（含第 7 項指向 bundle 好的 `dev-rule/templates/karpathy-guidelines-SKILL.md`），不能代跑。

```bash
bash scripts/install-prereqs.sh
```

腳本內容見 [`scripts/install-prereqs.sh`](./scripts/install-prereqs.sh)。跑完再依腳本結尾印出的第 6、7 項指示，在 Claude Code session 內完成剩下兩個 skill 的安裝。
