---
name: session-bootstrap-reconcile
description: 接手新 session 時對齊 HANDOFF 與當前 repo / docker / PR 實況,列出偏移(stale db_lock、已 merge 但仍標 RTM、container down 等),避免下段助理憑舊文件決策。觸發詞:「接手」/「bootstrap」/「對齊」/「換手第一步」。
---

# Session Bootstrap Reconcile

新 session 開頭(讀完專案 CLAUDE.md 的啟動程序之後)用這支對齊「HANDOFF 寫的狀態」vs「實際狀態」。`handoff` skill 負責**寫**,本 skill 負責**讀 + 校對**。

## 何時用

- 接手 STARTUP_PROMPT 後,確認 reality
- 換手 24h 以上,擔心 HANDOFF 內容過期
- 用戶提到「上段做了 X」但你想驗一下
- 大量 PR / DB lock / BG task 同時在跑,需要對齊

## 何時不用

- 對話中段(已經對齊過了)
- handoff 才剛寫完(內容必新鮮)
- 純資訊 Q&A 不依賴 reality

## 步驟

### 1. 載入兩份 HANDOFF(最新 1-2 份)

```bash
ls -t .planning/HANDOFF/SESSION_HANDOFF_*.md | head -2
ls -t .planning/HANDOFF/STARTUP_PROMPT_*.md | head -1
```

Read 最新的 SESSION_HANDOFF 與對應的 STARTUP_PROMPT。

### 2. 跑 reality 探查(一次平行批)

```bash
git fetch origin --prune && git log origin/main --oneline -15
gh pr list --state open --json number,title,headRefName,mergeable
gh pr list --state merged --limit 30 --jq '.[] | select(.mergedAt > "<since>") | [.number, .title] | @tsv'
docker ps --format "{{.Names}}\t{{.Status}}" && curl -sf http://localhost/api/health
cat .planning/HANDOFF.json
```

`<since>` = HANDOFF doc 的 timestamp(從 `Last revised:` 行抽出)

### 3. Diff matrix

對齊每個 HANDOFF 提到的 claim 與 reality:

| 類型 | HANDOFF 說 | Reality | 狀態 |
|---|---|---|---|
| RTM PR | #1175 等 merge | gh pr view → MERGED | **已 merge,可從待辦移除** |
| 開發中 branch | feat/lunar-X 在做 | git branch -r → 不存在 | **新 session 沒繼承,需重啟** |
| db_lock | 空(沒人持有) | HANDOFF.json db_lock 有上段殘留 | **stale,需清** |
| container | 8 個 healthy | docker ps → 7 個 + 1 unhealthy | **某服務 down,需修復** |
| BG task | task-XYZ 跑中 | TaskGet → 已 completed/不存在 | **過期,忽略** |

### 4. 報表(短)

回給 user 一張表:

```
| 來源 | 狀態 |
|---|---|
| HANDOFF + STARTUP_PROMPT | 完整 / 缺漏 |
| CLAUDE.md 啟動程序的核心必讀 | 已讀 / 缺漏 |
| memory 重點 | 已內化 / 待補 |
| 唯一 stale | <具體一句> |
```

無孤兒、無 cross-session 衝突 → 「無偏移,接手」
有偏移 → 「N 處需注意:1. ... 2. ... 3. ...」+ 提案修復順序

## 寫作紀律

- **R1**:整份回覆 NO emoji
- **不重複 CLAUDE.md**:已自動載入;dev-rule 按情境才讀
- 只列「實際差異」,不要把 HANDOFF 內容複述一遍
- 報告只放實際差異,讓下段一眼掃完

## 反例

- 把 SESSION_HANDOFF 內容整段複製貼到回覆(浪費 context)
- 沒跑 reality 探查直接信 HANDOFF(過時資訊吃進腦)
- 報告寫成「都 OK」沒列具體驗證項(下段無法 audit)
