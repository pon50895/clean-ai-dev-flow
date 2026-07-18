# dev-rule/sample/ — 開發環境 Bootstrap Sample 檔

> 跨機器 / 跨 worktree 都要重新 setup 的 baseline 配置,把「sprint baseline」鎖在版控。
> 修改本目錄下任何檔案須 PR 標 `[DEV-RULE]`,請用戶 review。

---

## 1. 雙檔結構(2026-05-30 split 後)

| 檔案 | 角色 | 部署到(target 端) | 是否 committed? |
|---|---|---|---|
| `settings.json` | 共享層:通用 allow + ask + **全部 deny** | `<target>/.claude/settings.json` | ✅ 進 git |
| `settings.local.json` | 個人層:絕對路徑 / bypass env / 個人 CLI(含 `MY-NEW-PROJECT` 佔位符) | `<target>/.claude/settings.local.json` | ❌ gitignored |
| `.claude.local.json` *(legacy)* | 舊單檔 schema | — | 已 deprecated,僅作 fallback |

**為什麼這樣分**:
- `settings.json` 帶資安底線(~230 條 deny:破壞性指令、機敏檔、persistence、curl-pipe-sh、reverse shell、.git/hooks 寫禁...),這些「跨人跨機器都成立」,該共享
- `settings.local.json` 含絕對路徑(`/Users/your-name/Desktop/MY-NEW-PROJECT/**`)+ bypass env(`SKIP_P0_REGRESSION=1 git commit`)+ 個人工具(colyn);**換一台機器就要改**,不該共享

完整刀切原則見 `split-settings` skill 文件。

---

## 2. 啟動序列(新 worker / 新機器 / 新 worktree)

```bash
# 1. 工具裝起來(含 codegraph MCP auto-wire)
bash scripts/colyn-roles/install-tools.sh

# 2. 部署權限基線
bash scripts/colyn-roles/apply-claude-settings.sh    # 同步 settings.local.json from sample

# 3. 重啟 Claude Code session 才會吃到新 allow / deny

# 4. 起 tmux roles
bash scripts/colyn-roles/start.sh
```

**注意**:
- 透過 `bootstrap-to-new-project.sh` 部署的新專案,**首次 setup 不必跑 apply-claude-settings.sh** —— bootstrap 已直接寫入 target `.claude/`。apply 用於日後 sample 變動時同步。
- 在這個 repo(clean-ai-dev-flow)內,`settings.json` 由 git 追蹤,新 worktree `git switch` 後直接取得;只有 `settings.local.json` 需要每個 worktree 各跑一次 `apply` 或讓 `sync-claude-settings.sh` symlink。

---

## 3. 變更流程(Change Process)

當你發現 sample 缺 / 多某條規則時:

### 3.1 走 PR 改 sample(規範路徑)

1. **不要直接動 `.claude/settings.local.json` 推上去** —— 那是 gitignored,永遠不會被別人看到
2. 改 `dev-rule/sample/settings.json`(或 `settings.local.json`):因 `Write(**/dev-rule/**)` 在 deny,Claude 走 `/tmp` 中轉 + `mv` 模式;見 `dev-rule/WORKFLOW_PROTOCOLS.md` review-failure loop
3. PR 標題 `[DEV-RULE]`,commit 訊息註明「為了 X 加 Y allow / 為了 Z 加 deny」
4. Reviewer 走 Karpathy lens 檢查 over-permission;附帶**檢查 deny 規則數量不能下降**(SkillOpt 紀律:settings 演化的 validation gate)
5. Merge 後通知所有 active worker「跑 `bash scripts/colyn-roles/apply-claude-settings.sh` 同步」

### 3.2 新增 allow rule 的判準

| 類別 | 應加 allow | 為什麼 |
|------|----------|--------|
| Read-only diagnostic(cat / grep / ls / git log)| ✓ 隨意加 | 無副作用 |
| Build / test idempotent(npm test / playwright)| ✓ 加 | 不變動 source / DB |
| GitHub PR / Issue 操作(gh pr / gh issue)| ✓ 加 | 動 GitHub state,但可 revert |
| Branch 切換 / 看(git switch / branch -d / log / diff)| ✓ 加 | 切換 / 安全刪 |
| Push feature branch(git push -u origin feat/...)| ✓ 加 | hooks 仍擋 main / force |
| **任意執行**(`Bash(node *)` / `Bash(npx *)` / `Bash(python *)`)| **✗ 禁** | 等於開後門 |
| Container 任意 exec(`Bash(docker exec *)`)| **✗ 禁** | 同上 |
| Write 系統路徑(`Write(/etc/**)` / `Write(/usr/**)`)| **✗ 禁** | 系統污染 |

### 3.3 新增 deny rule 的判準

- 任何**不可回 history**:`git push --force` 到 main / `git reset --hard` / `git filter-branch`
- **資料毀滅**:`prisma migrate reset` / `rm -rf` / `docker volume rm` / `dd of=` / `mkfs`
- **secret 寫入**:`.env*` / `*.pem` / `id_rsa*` / `id_ed25519*` / `credentials*.json` / `service-account*.json`
- **Hook / 簽章繞過**:`* --no-verify` 全 wildcard / `* --no-gpg-sign` / `core.hooksPath=/dev/null` / `HUSKY=0`
- **規則檔修改**:`CLAUDE.md` / `dev-rule/**` / `open-source-spec/**`(走 PR 標 `[DEV-RULE]`,不可裸 write)
- **Persistence / 後門**:`crontab:*` / `launchctl load/bootstrap` / `**/.bashrc` `.zshrc` 等 shell rc / `Library/Launch{Agents,Daemons}/**`
- **資料外流 / 反向連線**:`curl -X POST/PUT/DELETE/PATCH` / `curl --data` / `scp` / `rsync` / `nc -e` / `*</dev/tcp/*` / `bash -i`
- **供應鏈污染**:`.git/hooks/**` / `.git/config` / `.npmrc` / `.pypirc` / `.docker/config.json` / `npm install -g`
- **機敏讀禁**:`**/.ssh/**` / `**/.aws/credentials` / `id_rsa` / `id_ed25519`

---

## 4. AI 自我檢查(每個 role session 啟動後跑一遍)

- [ ] 我所在的 worktree 是否有 `.claude/settings.json` 和 `.claude/settings.local.json`?缺哪個就跑 apply 或讓 bootstrap 重補
- [ ] 我是否能跑 `gh pr list` / `git pull origin main --rebase` 而不被 prompt?不行 → 重啟 session
- [ ] 我是否在做超出我 role 的事?

---

## 5. 與其他文件 / Skill 的關係

| 文件 / Skill | 關係 |
|------|------|
| `dev-rule/TOOLS_INSTALL.md` | 工具鏈安裝(不含 Claude 權限)|
| `dev-rule/SKILL_OPTIMIZATION.md` | SkillOpt 紀律:settings 演化要 trajectory + validation gate |
| `scripts/colyn-roles/install-tools.sh` | 工具鏈 installer + codegraph MCP auto-wire |
| `scripts/colyn-roles/apply-claude-settings.sh` | sample/settings.local.json → `.claude/settings.local.json` 的 applier |
| `scripts/colyn-roles/sync-claude-settings.sh` | 把 main 的 settings.local.json symlink 到各 worktree |
| `scripts/colyn-roles/bootstrap-to-new-project.sh` | 一鍵把整套部署到外部新專案,含 `.claude/` 雙層 |
| `split-settings` skill(`~/.claude/skills/split-settings/`)| 對其他 repo 做同樣拆分時的指引 |

---

*Last revised: 2026-05-30 — 從 single-file `.claude.local.json` 拆成 `settings.json` + `settings.local.json` 雙檔,補回 ~20 條漏掉的 deny 規則(curl POST/PUT/DELETE、reverse shell、persistence、.git/hooks 寫禁等)。*
