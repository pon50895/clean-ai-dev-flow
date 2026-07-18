# GETTING_STARTED — 從 clone 到跑第一個 feature-pipeline

> 目標：在 macOS 上，從零開始，走到「一個新專案已經套用 dev-rule + feature-pipeline，並且成功跑完一次五階段流水線」。
> 每步都有預期輸出；卡住就對照該步的「若失敗」。
> 前置工具沒裝齊先看 [`PREREQUISITES.md`](./PREREQUISITES.md)（含一鍵安裝 script）。

全程只用「原生 subagent」路徑（見 README「平行開發兩條路」），不需要 tmux/colyn。這是多數人該停留的路徑。

---

## 0. 確認前置工具

```bash
claude --version && gh --version && node --version && git --version
```

**預期輸出**：四個版本號都印出來，沒有 `command not found`。任何一個缺 → 先做完 [`PREREQUISITES.md`](./PREREQUISITES.md) 再回來。

---

## 1. Clone 本 repo

```bash
cd ~/Desktop
git clone <this-repo-url> clean-ai-dev-flow
cd clean-ai-dev-flow
ls
```

**預期輸出**：看到 `CLAUDE.md`、`dev-rule/`、`.claude/`、`.githooks/`、`scripts/`、`README.md`。

---

## 2. 建立你自己的目標專案

用一個全新的空目錄示範（已有專案的話跳到步驟 3，把 `~/Desktop/my-app` 換成你的專案路徑）：

```bash
mkdir -p ~/Desktop/my-app
cd ~/Desktop/my-app
git init -b main
mkdir -p .planning
```

**預期輸出**：`git init` 印出 `Initialized empty Git repository in .../my-app/.git/`。

---

## 3. 複製規範層 + 五階段流水線 skill

```bash
cp -r ~/Desktop/clean-ai-dev-flow/dev-rule ./dev-rule
mkdir -p .claude/skills .claude/agents .claude/hooks
cp -r ~/Desktop/clean-ai-dev-flow/.claude/skills/feature-pipeline ./.claude/skills/feature-pipeline
cp    ~/Desktop/clean-ai-dev-flow/.claude/agents/reviewer.md      ./.claude/agents/reviewer.md
cp    ~/Desktop/clean-ai-dev-flow/.claude/hooks/*.js              ./.claude/hooks/
cp -r ~/Desktop/clean-ai-dev-flow/.githooks                       ./.githooks
```

**驗證**：

```bash
test -f dev-rule/AI_INSTRUCTIONS.md && echo "OK: dev-rule copied"
test -f .claude/skills/feature-pipeline/SKILL.md && echo "OK: feature-pipeline skill copied"
```

**預期輸出**：兩行都印 `OK: ...`。

---

## 4. 啟用 git hooks（R1 emoji 掃描 + gitleaks 秘密掃描 + push 前測試 gate）

```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push
git config core.hooksPath
```

**預期輸出**：最後一行印出 `.githooks`。這一步是最容易漏的——沒做，`dev-rule/` 裡寫的紅線只是「文件上」的約束，實際不會被機器擋。gitleaks 未安裝時 `pre-commit` 會印警告但不擋 commit（見 `.githooks/pre-commit` 內註解）；要真的擋秘密外洩，去 `PREREQUISITES.md` 裝 gitleaks。

---

## 5. 寫最小專案層 CLAUDE.md

新建 `CLAUDE.md`（Write 工具，不要 heredoc）：

```markdown
# CLAUDE.md — <你的專案名>

啟動時先讀完 `dev-rule/` 全部 `.md`，之後所有工作以 `dev-rule/` 為最高準則，衝突以 dev-rule 為準。

## 業務語境
<這裡填你的專案在做什麼，一兩段話>

## 當前里程碑
<這裡填目前在做的 phase / feature>
```

這份檔案是給你的專案填業務語境用的 placeholder；`dev-rule/` 本身不需要修改。

---

## 6. 開 Claude session，確認規範已生效

```bash
cd ~/Desktop/my-app
claude
```

進入 session 後，第一句話：

```
先讀完 dev-rule/ 全部 .md，之後所有工作以 dev-rule 為最高準則。列出你讀到的紅線 R1-R11 清單確認。
```

**預期輸出**：Claude 回覆列出 R1（禁 emoji）到 R11（禁 --no-verify）的清單，且過程沒有卡在 permission prompt（讀 `dev-rule/*.md` 是純讀取，不需要額外權限）。

---

## 7. 跑第一個 feature-pipeline

在同一個 session 裡，給一個小而具體的 feature 需求（範例用一個最小可行的玩具功能，換成你真正要做的東西）：

```
跑開發流水線：幫這個專案加一個 /health 端點，回傳 { "status": "ok" }。這是一個非常小的 feature，
調研/企劃階段可以精簡，但完整走五階段（調研→企劃→分派開發→驗證→開 PR）並在每個 gate 停下來讓我確認。
```

Claude 應該會依 `.claude/skills/feature-pipeline/SKILL.md` 的五階段走：

1. **調研 → 企劃**：产出簡短企劃（多小的 feature 也要有取捨說明），停下來要你拍板。
2. **企劃 → 開發計畫**：把它拆成原子化 Task，寫成 `.planning/phases/<phase>/PLAN.md`，停下來要你過目 PR 拆分。
3. **依難度分派開發**：在 feature branch（不是 main）上小步 commit；`/health` 這種規模應該用中階模型直接做。
4. **驗證**：另開一個 fresh-context 的驗證（可用 `.claude/agents/reviewer.md` 這個 subagent），逐項附「檔案:行號」證據。
5. **開 PR**：驗證過了才 push + 開 PR，且只在你明確要求 RTM（ready to merge）時才轉成 open 狀態。

**驗證每個 gate**：

```bash
# 步驟 3 之後：確認在 feature branch，不是 main
git branch --show-current   # 不應印出 main

# 步驟 5 之後（若你已授權開 PR）：
gh pr list --limit 1
```

**若卡住**：

| 症狀 | 可能原因 | 解法 |
|---|---|---|
| Claude 直接開始寫 code，跳過調研/計畫 | 需求描述太像「直接做」而非「跑流水線」 | 重新明確說「跑開發流水線」「照 feature-pipeline 五階段做」 |
| commit 被 pre-commit 擋，說 gitleaks 找到東西 | 真的疑似秘密字串，或誤判 | 真秘密：移除重寫；誤判：見 `.githooks/pre-commit` 內註解，用 `.gitleaks.toml` allowlist |
| push 被 pre-push 擋，說測試失敗 | 專案沒有 test script，或測試真的紅 | 沒 test script 會直接放行（見 hook 內判斷）；測試真紅要修好才能 push，不可 `--no-verify`（R11） |
| Claude 想直接在 main 上 commit | 沒先開 feature branch | 提醒它 R9：一律 feature branch + PR |

---

## 8. 收尾檢查

```bash
git status --short   # 工作樹是否乾淨
git log --oneline -5 # 是否都是 feature branch 上的原子化 commit，不是塞在 main
```

跑到這裡，你已經有一個套用了 dev-rule + feature-pipeline 的專案，走過一次完整五階段。接下來的日常開發重複步驟 6-8 即可；不需要每次都重新 bootstrap。

要進階到多 LLM 供應商的 tmux fleet，回到 `README.md`「進階：tmux fleet」一節。
