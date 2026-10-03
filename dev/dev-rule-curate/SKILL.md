---
name: dev-rule-curate
description: 定期檢視 dev-rule/*.md 是否仍對應當前 repo,(a) 標出引用已不存在 phase/file 的條款 (b) 找到與 newer rule 重複的條款 (c) 從近期 feedback memory / violations.jsonl 抽出尚未落到 dev-rule 的紀律。dry-run 提案給 user 確認再改。觸發詞:「整理 dev-rule」/「dev-rule curate」/「補紀律」/「dev-rule audit」。
---

# Dev-Rule Curate

專案 CLAUDE.md 按情境路由到 `dev-rule/*.md`,這些文件會 drift:phase 改名 / file 重構 / 紀律已內化到 memory 但 dev-rule 還沒更新。本 skill 做半年 / 大里程碑後的 audit。

## 何時用

- 完成一個 milestone(launch / phase 群結束)
- bootstrap 載入 dev-rule 時發現引用斷裂(例:某 phase 已歸檔但 dev-rule 還 link)
- memory `feedback_*` 累積 > 5 條未對應到 dev-rule
- 用戶說「整理 dev-rule」/「補紀律」/「dev-rule audit」

## 何時不用

- 還在做 phase 中段(dev-rule 改動會引發協作中斷)
- 只想加單一條紀律 → 直接 Edit dev-rule/<file>.md 即可,不需要 skill 全 sweep
- 新 dev-rule 文件還沒共識(先討論再 curate)

## 三類動作

### A. 修剪(prune)

| Pattern | 動作 |
|---|---|
| dev-rule 引用 phase X,但該 phase 已在 `.planning/archive/phases/` 或看板標 Done | 候選改寫成歷史 reference 或整段歸 `dev-rule/archive/` |
| dev-rule 引用 file path Z,`ls` 不存在 | 候選刪 link 或更新 path |
| 兩條 dev-rule 描述同件事(grep 重複關鍵字) | 候選合併,保留 specific 的一條 |
| 已被 CLAUDE.md / 專案上層規格文件 supersede 的條款 | 候選刪 |

### B. 增補(augment)

| 來源 | 抽取規則 |
|---|---|
| `$LEARN_DIR/violations.jsonl` last 30 entries(`$LEARN_DIR` 解法見 skillopt:playbook `~/claude-ops-playbook/learning/` 或專案 `.planning/learning/`) | 重複出現 ≥ 3 次同類 violation → 對應 dev-rule 沒列出,需補 |
| `~/.claude/projects/<project-slug>/memory/feedback_*.md` last 14 days | 與 dev-rule 無對應條目的紀律 → 候選新增 |
| 最近 SESSION_HANDOFF `## 紀律與補課` 段 | 該段提到「memory 新增 feedback_X」但 dev-rule 沒體現 → 補 |

### C. cross-link 健全(integrity)

| 檢查 | 動作 |
|---|---|
| `dev-rule/*.md` 提到的 `[[name]]` link | grep memory + 其他 dev-rule 確認 target 存在 |
| dev-rule 互引(`see <OTHER>.md §R4`)| 確認 anchor / section 仍存在 |
| CLAUDE.md 路由表列的 `dev-rule/*.md` vs 實際檔 | 檔可能新增或改名 |

## 步驟

### 1. 掃描

```bash
ls dev-rule/*.md dev-rule/archive/*.md 2>/dev/null
ls ~/.claude/projects/<project-slug>/memory/feedback_*.md 2>/dev/null
tail -50 "$LEARN_DIR/violations.jsonl" 2>/dev/null
ls -t .planning/HANDOFF/SESSION_HANDOFF_*.md | head -3
grep -nrE "Phase\\s+[0-9]+|\\.planning/phases/|`[^`]+\\.(ts|tsx|md|json)`" dev-rule/*.md
```

### 2. 三色提案

| Color | 動作 | 表格欄位 |
|---|---|---|
| RED prune | 刪 / 改寫 | dev-rule path + line + 為什麼 |
| GREEN augment | 新增段落 | 來源(memory / handoff)+ 提案落點(哪個 dev-rule 文件 + 哪一段) |
| YELLOW integrity | 修連結 | broken link + 提議的修法(改 path / archive link / 刪) |

### 3. 對抗式自審

提案前自問:
- 此 prune 候選是否被 active feature branch 引用?(`grep -r "<rule>" feat/* 2>/dev/null`)
- 此 augment 條目是否其實已存在另一段?(別重複加)
- 此 cross-link 修補有沒有破壞既有可讀性?

### 4. user 確認 → 一次 PR

```bash
git switch -c chore/dev-rule-curate-<date>
# Edit dev-rule/*.md per 提案
git commit -m "chore(dev-rule): curate — prune N / augment M / fix K cross-links"
git push -u origin HEAD
gh pr create --base main --fill
```

PR body 必含三色提案表格 + 對抗式自審結論,讓 reviewer 一頁看完。

## 寫作紀律

- **R1**:NO emoji
- **不刪未確認的條款**:即使看起來過期,先標 RED + dry-run,等 user 點頭
- **保留紀律的 why**:歸檔不刪 — 條款可能後來又用到,搬 `dev-rule/archive/`
- **不刪安全 / 法遵類 dev-rule 內容**:法律 / 安全規範一律保守,只能補不能刪
- **不寫主觀評語**:「這條看起來沒用」→ 改寫成「Phase X 已歸檔,本條已 stale」

## 反例

- 一次 PR 動 > 30 條紀律(reviewer 無法逐條 audit)
- 把 memory 的 feedback 整段複製貼到 dev-rule(memory 是 session 紀律,dev-rule 是 repo 紀律,語境不同)
- 刪掉 R1-R11 任何一條紅線(那是 CLAUDE.md SSoT,不在 dev-rule 範圍)
- 沒 dry-run 直接 PR(reviewer 看不到改動意圖)
