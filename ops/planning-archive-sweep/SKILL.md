---
name: planning-archive-sweep
description: 定期把過期的 SESSION_HANDOFF / STARTUP_PROMPT / 已完成 phase 目錄 / 一次性 dated audit 搬到 `.planning/archive/` 子目錄,避免 bootstrap 載入垃圾、context 被 stale 文件污染。dry-run 給 user 確認再動。觸發詞:「整理 .planning」/「archive sweep」/「歸檔」/「清過期 handoff」。
---

# Planning Archive Sweep

專案 CLAUDE.md 通常規定 archive 子目錄(`.planning/archive/handoff/` 等),但搬移動作 ad-hoc。本 skill 提供一致的 sweep 流程。

## 何時用

- 每 14 天 / 每完成一個 phase
- `.planning/HANDOFF/` 累積到 > 5 份 SESSION_HANDOFF
- 用戶說「整理 .planning」/「歸檔」/「清過期」
- 換手前 user 主動要求清

## 何時不用

- 進行中 phase 的 handoff(永遠不歸檔當前段 + 上段)
- WIP feature branch 還引用著的 phase doc
- 已 push 到 PR 的 docs(等 merge 後再歸檔)

## Sweep 規則

### A. `.planning/HANDOFF/`

| 動作 | 規則 |
|---|---|
| 保留 | 最新 2 份 `SESSION_HANDOFF_*` + 對應 `STARTUP_PROMPT_*` |
| 搬 `.planning/archive/handoff/` | 其餘所有 dated handoff |

### B. `.planning/HANDOFF.json`

| 動作 | 規則 |
|---|---|
| 清 `db_lock` | 若 `acquired_at` > 7 天且無對應 open PR / branch |
| 截斷 `db_lock_history` | 只留最新 10 筆 |
| 移除 `completed_tasks` | 若 phase 已 ship(對 main 找對應 PR merged) |

### C. `.planning/phases/<phase>/`

| Phase 狀態 | 動作 |
|---|---|
| 看板(GitHub Project)標 Done / 對應 PR 已 merged | 整資料夾搬 `.planning/archive/phases/` |
| Active(未完) | 留原處 |
| 同一個 phase 有 PLAN / SUMMARY / VERIFICATION | 全部一起搬,不要拆 |

### D. 一次性 dated audit / lessons

| 路徑 pattern | 動作 |
|---|---|
| `.planning/audit/<date>-*` | 搬 `.planning/archive/dated/` |
| `.planning/lessons/<date>-*` | 同上 |
| `.planning/settings-recommendation-<date>-*` | 同上 |

### E. 殘留檔

| pattern | 動作 |
|---|---|
| `*.md.bak` / `*~` / `.DS_Store` | 列清單給 user,**user 自己 rm**(rm 屬 user 地盤) |
| git untracked 但符合 archive pattern | 提示 user 是否要 commit 後再搬 |

## 步驟

### 1. Dry-run scan

```bash
ls -lt .planning/HANDOFF/SESSION_HANDOFF_*.md 2>&1
ls -lt .planning/HANDOFF/STARTUP_PROMPT_*.md 2>&1
jq '.db_lock, (.db_lock_history | length)' .planning/HANDOFF.json
ls .planning/phases/ 2>&1
find .planning/audit .planning/lessons -type f -name "*.md" 2>/dev/null | head -20
```

### 2. 提案表格

```
| 動作 | 路徑 | 為什麼 |
|---|---|---|
| KEEP | .planning/HANDOFF/SESSION_HANDOFF_2026-06-01-PART1.md | 最新一份 |
| ARCHIVE | .planning/HANDOFF/SESSION_HANDOFF_2026-05-30-PART2.md | 早於最新 2 份 |
| ARCHIVE | .planning/phases/<shipped-phase>/ | 對應 PR 已 merged |
| CLEAR | HANDOFF.json db_lock | 2026-05-09 殘留,branch 已 merge |
| USER-ACT | .planning/audit/lessons-mvp.md.bak | bak 檔需 user rm |
```

### 3. user 確認 → 執行 git mv

```bash
mkdir -p .planning/archive/handoff .planning/archive/phases .planning/archive/dated
git mv .planning/HANDOFF/SESSION_HANDOFF_2026-05-XX-PART2.md .planning/archive/handoff/
git mv .planning/phases/<shipped-phase> .planning/archive/phases/
```

### 4. 清 HANDOFF.json(直接 edit)

```javascript
// db_lock empty: {}
// db_lock_history: 只留 .slice(-10)
```

### 5. commit + push

```bash
git switch -c chore/planning-archive-sweep-<date>   # R9: never commit on main
git commit -m "chore(planning): archive sweep — N handoffs / M phase dirs"
git push -u origin HEAD && gh pr create --base main --fill   # 純歸檔也走 branch + PR(branch-first 規則)
```

## 寫作紀律

- **R1**:NO emoji
- **絕不 rm**:歸檔用 `git mv`,刪檔列清單給 user
- **dry-run 必先**:不未經 user 確認直接 mv
- **保護 active branch**:若有 feature branch 引用了 phase doc(grep 看),警告 user
- **檢核 cross-link**:歸檔的 doc 內部 `[[link]]` 失效要在 PR description 標出

## 反例

- 看到舊 handoff 就直接搬(可能 user 還在參考)
- 把 db_lock 清掉但忘了看 git branch -r 確認沒有對應 WIP branch
- 一個 PR 搬幾百檔(難 review,拆成 < 20 檔一批)
- 把 active phase 的 PLAN.md 搬走(會誤判)
