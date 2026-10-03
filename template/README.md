# template/ - 專案層範本(由 scripts/bootstrap.sh 複製)

```
bash scripts/bootstrap.sh <target-dir> [--dry-run]
```

| 範本檔 | 落在目標專案 | 說明 |
|---|---|---|
| `CLAUDE.md` | `CLAUDE.md` | 專案 CLAUDE.md 範本;`<...>` 與「(填寫)」處待補 |
| `kit.json` | `.claude/kit.json` | 本頁下方欄位說明 |
| `kit.schema.json` | `.claude/kit.schema.json` | JSON schema(編輯器補完用) |
| `.githooks/pre-commit`、`pre-push` | `.githooks/` | 通用 git hook 骨架,全部讀 kit.json |
| `scripts/kit/*` | `scripts/kit/` | kit.mjs、lint-runner、tsc-runner、emoji-scan、check-env-drift.sh、check-dependency-pins.mjs |
| `scripts/dependency-pins.json` | `scripts/dependency-pins.json` | 空 pin 檔 |
| (`../dev-rule/`) | `dev-rule/` | 排除專案專屬的 LEGAL_COMPLIANCE.md、UI_VISUAL_STANDARDS.md |

不複製 `.claude/skills/`、`.claude/hooks/`:skill 由 `~/.claude/skills` symlink 在使用者層提供,hook 由 playbook 全域掛載。

## 為什麼用 core.hooksPath 不用 husky

bootstrap 執行 `git config core.hooksPath .githooks`。hook 是純 sh,只在讀 kit.json 時用 node(沒有 node 就整段略過);
目標專案不必是 node 專案、不必 `npm install`。目標若已使用 husky(core.hooksPath 不是空的),bootstrap 不覆蓋,
改印說明:從既有 hook 呼叫 `.githooks/pre-commit` 與 `.githooks/pre-push`。

## kit.json 欄位

位置:`.claude/kit.json`(優先)或專案根 `kit.json`。所有欄位選填;完整型別見 `kit.schema.json`。
全域 `bash-destructive-guard` hook(playbook)讀同一個檔的 `destructiveGuard.allowPaths`。

| 欄位 | 用途 |
|---|---|
| `commands.test/lint/typecheck/build` | 專案指令;CLAUDE.md 2.5 引用;`commands.lint` 是 lint ratchet 的預設指令 |
| `commands.p0` | pre-commit 的 P0 回歸指令(`modules.p0` 開啟才跑;純文件 commit 自動略過) |
| `protectedBranches` | 禁止直接 commit / push 的分支,預設 `["main","master"]` |
| `baseRef` | pre-push 範圍化 gate 的比較基準,預設 `origin/main` |
| `destructiveGuard.allowPaths` | 可拋棄的路徑前綴(相對專案根),底下 `rm` 不擋;與 playbook guard 對齊 |
| `secretScan.excludePaths` | secret 掃描額外排除的 git pathspec |
| `ratchet.lint.workspaces` | 要 lint 的目錄(`"."` 為根);字串或 `{ "path", "command" }` |
| `ratchet.lint.baseline` | 預設 `.planning/audit/lint-baseline.json` |
| `ratchet.tsc.workspaces` | 要 typecheck 的目錄;字串或 `{ "path", "project" }`(project 預設 `tsconfig.json`) |
| `ratchet.tsc.baseline` | 預設 `.planning/audit/tsc-baseline.json` |
| `emojiScan.allowChars` / `excludePrefixes` | emoji 掃描的放行字元(預設 `©`)與額外排除路徑 |
| `dependencyPins.file` | pin 檔路徑,預設 `scripts/dependency-pins.json` |
| `modules.*` | 可選模組開關,見下表 |

## 模組與 hook 段落對照

| 模組開關 | hook 段落 | 未寫時的預設 | 跳過條件 |
|---|---|---|---|
| (核心) | pre-commit 1 擋 protected branch commit | 開 | - |
| (核心) | pre-commit 2 staged secret 掃描 | 開 | - |
| `envDrift` | pre-commit 3 env drift | 開 | 沒有被追蹤的 `.env.example` |
| `dependencyPins` | pre-commit 4 dependency pins | 開 | 沒 staged `package.json`、沒 pin 檔、pin 為空、沒裝 semver |
| `emojiScan` | pre-commit 5 emoji(R1) | 開 | 沒有 staged 原始碼 |
| `p0` | pre-commit 6 P0 回歸 | 關 | `commands.p0` 空、純文件 commit |
| (核心) | pre-push 1 擋 push protected branch | 開 | - |
| (核心) | pre-push 2 擋 force push | 開 | - |
| `lintRatchet` | pre-push 3 lint ratchet | 關 | `ratchet.lint.workspaces` 為空、無相關 code 變更 |
| `tscRatchet` | pre-push 4 tsc ratchet | 關 | `ratchet.tsc.workspaces` 為空、無 ts/tsx 變更 |
| `ponytailAck` | pre-push 5 ponytail 半阻斷 | 關 | diff 沒有 ts/tsx/js/jsx |

Escape hatch:`ALLOW_MAIN_COMMIT=1`、`ALLOW_SECRET_COMMIT=1`、`SKIP_P0_REGRESSION=1`、`ALLOW_MAIN_PUSH=1`、`ALLOW_FORCE_PUSH=1`、
`ALLOW_DIRTY_LINT=1`、`ALLOW_DIRTY_TSC=1`、`PONYTAIL_REVIEWED=1`。

## Ratchet 基線

```
node scripts/kit/lint-runner.mjs --mode=baseline   # 建立 / 下調基線
node scripts/kit/lint-runner.mjs --mode=check      # 高於基線擋,低於基線提示可下調
node scripts/kit/tsc-runner.mjs  --mode=baseline|check
```
