---
name: memory-curate
description: 壓縮 user 自動 memory 索引(`~/.claude/projects/<project>/memory/MEMORY.md`),讓它保持在讀取上限(24.4KB)以下。汰除已結案 entry、合併同題、砍冗長尾巴,dry-run 給 user 確認再覆寫。觸發詞:「memory-curate」「壓縮 memory」「MEMORY.md 太大」「memory 索引整理」「memory 逼近上限」。
---

# Memory Curate

`MEMORY.md` 是每 session 自動注入的 memory 索引,有 ~24.4KB 讀取上限。它會隨專案膨脹逼近上限,注入內容一旦被截斷,新 session 就讀不到早期教訓。本 skill 提供一致的壓縮流程。

## 核心觀念

- **MEMORY.md 是 working-set 快取,不是檔案庫。** 它的職責是「index 進 topic 檔」,不是「裝下所有細節」。細節永遠留在被連結的 topic 檔(`memory/*.md`),索引本身只留標題 + 一句 hook。
- **膨脹是 curation 題,不是 capacity 題。** 定期汰除結案 entry,讓索引維持 bounded,才是主解。
- **砍尾巴只是輔助,效果有限。** 實測單純砍冗長句尾只降 ~11% 體積;真正的 headroom 來自汰除整條已結案 entry。
- **逃生門:分片。** 若索引真的塞不下 live working set(仍在被高頻引用的 entry 太多),把 MEMORY.md 變薄、改成 router 指向 domain 子索引(例如 `memory/<domain-a>-index.md`、`memory/<domain-b>-index.md`),而不是繼續硬塞一份。

## 何時用

1. **Hook 門檻觸發**:PostToolUse 或 harness 提示 MEMORY.md 逼近讀取上限時。
2. **Handoff 收尾檢查**:`handoff` skill 收尾跑 `wc -c MEMORY.md`,超過 20KB 時。
3. **每月巡檢**:跟 violations 歸檔(`$LEARN_DIR/violations.jsonl`,`$LEARN_DIR` 解法見 skillopt)、`/ponytail-audit`、`planning-archive-sweep` 排一起跑。

## 何時不用

- 索引目前 <17KB 且沒有 hook 警告 — 不必主動動。
- 單一 entry 仍在被近期 session 高頻引用(不算「結案」),即使冗長也先留著,改壓縮寫法而非刪除。

## 步驟

### 1. 備份

```bash
cp "$MEMORY_MD_PATH" "/tmp/MEMORY.md.bak-$(date +%Y%m%d%H%M%S)"
wc -c "$MEMORY_MD_PATH"
```

`$MEMORY_MD_PATH` 通常是 `~/.claude/projects/<project-slug>/memory/MEMORY.md`。

### 2. 盤點 entry,分三類

逐段(每個 `- [標題](連結)` 為一個 entry)判斷:

| 分類 | 判準 | 動作 |
|---|---|---|
| **結案** | 已 ship + 已穩定運行一段時間 + 近期(近 1-2 個月)session 沒再被引用/踩坑 | 從索引移除,併進底部「已結案不入索引」footer(只留一句話帶過,不留連結) |
| **同題** | 多條 entry 講同一件事的不同階段(如「PR-1 做了」「PR-2 做了」「全部完成」) | 合併成一條,只留最新狀態 + 累積要點 |
| **仍活躍** | 近期仍被引用、仍是未結案的工作方向、或是常踩的 gotcha | 留著,但檢查有沒有冗長尾巴可砍(細節推回 topic 檔,索引只留 hook) |

### 3. 寫 dry-run 提案

呈現表格給 user 確認,不要直接覆寫:

```
| 動作 | Entry | 為什麼 |
|---|---|---|
| ARCHIVE | project_xxx_2026_06_01 | 已 ship+prod 驗證+近 2 月無引用 |
| MERGE | project_yyy_pr1 + project_yyy_pr2 → project_yyy | 同題不同階段,合併留最新狀態 |
| TRIM | feedback_zzz | 尾巴冗長,砍到一句 hook,細節已在 topic 檔 |
| KEEP | project_www | 近期仍活躍被引用 |
```

同時報目前大小與預估壓縮後大小。

### 4. User 確認後執行

- 用 Edit 對 MEMORY.md 做精確區段替換(R3:禁全檔覆寫)。
- **只動索引行,絕不刪 topic 檔本身**(`memory/*.md` 底下的個別檔案保留,即使索引不再連結它 — 之後有需要仍可用 `memory_search` / grep 撈回)。
- 目標:**<17KB**,留出到 24.4KB 上限的 headroom。

### 5. 驗證

```bash
wc -c "$MEMORY_MD_PATH"
```

確認低於目標值,且被移除的 entry 內容確實出現在底部 footer 或已合併,不是憑空消失。

## 安全規則

- 動前必備份(`/tmp` 或 scratchpad,不用 `git`,因為 memory 目錄不一定是 git repo)。
- 動作前一定 dry-run 給 user 過目,不擅自覆寫。
- 不刪 topic 檔,只動索引本身。
- 不用 `--force` 之類跳過確認的捷徑。

## 反例

- 看到 entry 長就直接刪,不判斷是否仍活躍(可能砍掉正在踩的坑)。
- 一次全砍到最小,不给 user 看 dry-run 表格。
- 誤刪 topic 檔本身(索引只是 pointer,檔案要留)。
- 只砍尾巴不汰除結案 entry(效果有限,治標不治本)。
