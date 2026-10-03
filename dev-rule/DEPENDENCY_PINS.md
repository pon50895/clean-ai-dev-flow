# Dependency Pins

## 為何有 pin
Dependabot 之類的 bot 會把相容性未就緒的套件反覆升上去（升、退回、又升）。只靠文件擋不住 bot，所以用機器 gate：`scripts/dependency-pins.json` 登記「某 workspace 的某套件只能在某 range」，`scripts/kit/check-dependency-pins.mjs` 不符就 exit 1。

## 目前的 pin（SSOT 是 `scripts/dependency-pins.json`）

| workspace | package | allowedRange | 原因 | 解鎖條件 | refs |
|---|---|---|---|---|---|
| (尚無；新增 pin 時在此補一列) | | | | | |

## 設定與執行位置
- 開關：`.claude/kit.json` 的 `modules.dependencyPins`（預設開；沒有 pin 檔或 pin 為空陣列時自動略過）。pin 檔路徑：`dependencyPins.file`（預設 `scripts/dependency-pins.json`）。
- pre-commit：有 `package.json` 被 staged 時跑（`.githooks/pre-commit` 第 4 段）。
- 手動：`node scripts/kit/check-dependency-pins.mjs`
- 需要 `semver` 套件（`npm i -D semver`）；解析不到時印警告並略過，不擋 commit。

## 如何新增 pin
在 JSON 加一筆並同步本表：

```json
{
  "workspace": ".",
  "package": "eslint",
  "allowedRange": "^9",
  "reason": "為何不能升（例：某 plugin 的 peer 還不支援 10）",
  "unlockWhen": "什麼條件成立才解鎖",
  "refs": ["#123"]
}
```

`workspace` 是含 `package.json` 的目錄（相對專案根，`.` 為根）。

## 如何解除 pin
1. 確認解鎖條件已成立（例：`npm view <package> peerDependencies`）。
2. 升版並 `npm install` 更新 lockfile。
3. 若有開 lint / tsc ratchet，跑 `node scripts/kit/lint-runner.mjs --mode=check` 確認無 parse-fail、不超過 baseline。
4. 在同一支 PR 內從 `scripts/dependency-pins.json` 移除該筆並更新本表。

## Bot 設定的限制
若 CI 因故停用（帳單、額度），bot 的 PR 不會跑 CI，pin 只攔得到本地 commit。這時另在 bot 設定檔（例：`.github/dependabot.yml` 的 `ignore`）直接擋掉該大版本；解除 pin 時須同時移除該 ignore 項。
