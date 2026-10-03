# GETTING_STARTED — 從 clone 到新專案套用完成

> 目標：在 macOS 上，把一個專案接上本套件的「專案層」（CLAUDE.md、kit.json、git hook 骨架、dev-rule），並確認規範生效。
> 一個指令完成：`bash scripts/bootstrap.sh <target-dir>`。不再手動 cp。
> 兩個 repo 的分工：skill 與專案範本在本 repo；全域規則、學習迴路與通用 hook 在 playbook（`~/claude-ops-playbook`）。

---

## 1. 前置工具

```bash
claude --version && gh --version && node --version && git --version
```

**預期輸出**：四個版本號都印出來。任何一個缺 → 先做完 [`PREREQUISITES.md`](./PREREQUISITES.md)（含一鍵安裝 script）。
node 只在 git hook 讀 `kit.json` 時用；目標專案不必是 node 專案。

---

## 2. Clone 本 repo

```bash
cd ~/Desktop
git clone <this-repo-url> clean-ai-dev-flow
cd clean-ai-dev-flow
ls
```

**預期輸出**：看到 `template/`、`dev-rule/`、`dev/`、`marketing/`、`ops/`、`scripts/`、`README.md`。

---

## 3. 先 dry-run

目標專案目錄必須已存在（新專案先 `mkdir` + `git init -b main`）：

```bash
bash scripts/bootstrap.sh ~/Desktop/my-app --dry-run
```

**預期輸出**：每個檔案一行 `WOULD CREATE: <相對路徑>`，結尾 `summary`，沒有寫入任何東西。
若出現 `SKIP (exists, differs)`，代表目標已有同名但內容不同的檔案，bootstrap 不會覆蓋它，之後自行手動合併。

---

## 4. 正式跑

```bash
bash scripts/bootstrap.sh ~/Desktop/my-app
```

複製的只有專案層：`CLAUDE.md`、`.claude/kit.json`（與 schema）、`.githooks/`、`scripts/kit/`、`dev-rule/`；並設定 `git config core.hooksPath .githooks`
（目標若已用 husky，不覆蓋，改印手動合併說明）。

**預期輸出**：`summary: created=N unchanged=0 skipped=0`。**冪等**：再跑一次應為 `created=0`。
刻意不複製 `.claude/skills/`、`.claude/hooks/`：skill 由使用者層 symlink 提供，hook 由 playbook 全域掛載，專案層再放一份會蓋掉使用者層版本。

---

## 5. 編輯 `.claude/kit.json` 與 CLAUDE.md

- `<目標>/CLAUDE.md`：把尖括號與「(填寫)」處補上（專案名、業務語境、當前里程碑）。
- `<目標>/.claude/kit.json`：填 `commands.test/lint/typecheck/build`、`ratchet` 的 workspace 清單、`protectedBranches`、`destructiveGuard.allowPaths`、要啟用的 `modules`。
  欄位說明見 [`template/README.md`](./template/README.md)，型別見 `kit.schema.json`。

---

## 6. user 層 skill symlink（每台機器做一次）

skill 的真檔在本 repo 的 `dev/`、`marketing/`、`ops/`；`~/.claude/skills/<name>` 是指過來的目錄級 symlink，所有專案共用：

```bash
ln -s ~/Desktop/clean-ai-dev-flow/dev/feature-pipeline ~/.claude/skills/feature-pipeline
ls -la ~/.claude/skills | grep clean-ai-dev-flow
```

其他 skill 同樣模式（`<類別>/<name>`）。完整 22 個對應表見 playbook `README.md`「`~/.claude/skills/*` 對應表」。
已存在同名真目錄時不要覆蓋，先確認內容再處理。

---

## 7. 全域 hook（指向 playbook）

通用 hook（destructive-guard、git-workflow-guard、agent-model-guard、reminder 類等）的權威在 playbook `hooks/`，
由 `~/.claude/settings.json` 以絕對路徑全域掛載，所有專案共用，**不要**在專案層再放一份。
掛載表與建議 diff：`~/claude-ops-playbook/hooks/SETTINGS_MOUNT.md`（改 settings.json 前先確認）。

---

## 8. 驗證規範生效

```bash
cd ~/Desktop/my-app
git config core.hooksPath      # 預期 .githooks
claude
```

進入 session 後第一句話：

```
先讀完 dev-rule/ 全部 .md，之後所有工作以 dev-rule 為最高準則。列出你讀到的紅線 R1-R11 清單確認。
```

**預期輸出**：Claude 列出 R1（禁 emoji）到 R11（禁 --no-verify）。之後可用 `feature-pipeline` skill 跑第一個五階段流水線（見 `dev/feature-pipeline/SKILL.md`）。

| 症狀 | 可能原因 | 解法 |
|---|---|---|
| Claude 直接開始寫 code，跳過調研/計畫 | 需求描述太像「直接做」 | 明說「跑開發流水線」「照 feature-pipeline 五階段做」 |
| commit 被 pre-commit 擋（secret 掃描） | 真秘密或誤判 | 真秘密移除重寫；誤判改 `kit.json` 的 `secretScan.excludePaths` |
| push 被 pre-push 擋 | 測試真的紅或 ratchet 退步 | 修好才能 push，不可 `--no-verify`（R11） |
| Claude 想直接在 main 上 commit | 沒先開 feature branch | 提醒 R9：一律 feature branch + PR |

---

## 附：進階 tmux fleet（選配）

只有要同時操控 Claude + Gemini + Codex 等多個獨立 LLM 進程才需要；執行層腳本在 `scripts/colyn-roles/`，說明見 `README.md`「進階：tmux fleet」。
舊的 `scripts/colyn-roles/bootstrap-to-new-project.sh` 已被 `scripts/bootstrap.sh` 取代，檔案保留但不再是入口。
