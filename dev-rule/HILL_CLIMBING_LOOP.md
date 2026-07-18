# Hill Climbing Loop（Loop 4 — 自我改進）

> 修改本檔須在 PR 標註 `[DEV-RULE]`，請用戶 review。

前三層自動化的是「工作」(Loop 1 寫碼 / Loop 2 review / Loop 3 dispatch)。
這層自動化的是「**改進**」——讓 harness 每跑一輪就比上一輪強一點。

## 為什麼這層之前是空的

Loop 4 需要 trace。**這專案早就在寫 trace 了**，只是沒人回頭讀:

| 失敗訊號 | 已經被寫進哪 |
|---------|-------------|
| review 反覆打槍 / 升級仲裁 | `.planning/COORDINATOR_LOG.md` |
| 測試 FAIL / flaky | `.planning/TEST_RESULTS.md` |
| 權限被擋 / timeout | `.planning/USER_PERMISSION_QUEUE.md` |
| 紅線 R1-R11 被踩 | `.planning/COORDINATOR_LOG.md` |
| regression | `.planning/REGRESSION_REGISTRY.md` |

缺的不是資料，是「讀 trace → 找出 harness 哪裡爛 → 改它」這個迴圈。

## 迴圈

```
agent 跑 (Loop 1-3) → 失敗訊號沉澱進 .planning/*.md
  ↓
dispatcher 每 N 個 PR(或每週)跑 retro.sh
  ↓  scripts/colyn-roles/retro.sh
找出反覆撞牆的地方 + 指出最可能要改的 harness 檔
  ↓
supervisor 挑 count 最高的 1 條，寫成 [DEV-RULE] PR
  ↓
【人類閘門】user review harness 改動 → merge
  ↓
下一輪 agent 在同一個地方不再撞牆 ← 迴圈深入內層，更新 agent 設定
```

關鍵(文章原話):外層迴圈的回傳箭頭不只回到頂部——它**深入內層直接更新 agent 設定**
(prompt / role spec / rubric / 權限白名單)。每跑一圈外層，內層就強一點。

## 觸發

dispatcher 職責表新增一條(見 `scripts/colyn-roles/role-dispatcher.md`):

> **Retro sweep** — 每累積 N 個 merged PR(預設 5)或每週一,跑 `retro.sh`，
> 把輸出貼進 supervisor INBOX `[dispatcher RETRO]`。dispatcher 不改 harness(紅線),
> 只負責把訊號端上桌。

## 人類在哪裡

**harness 改動一律走 `[DEV-RULE]` PR + 人工 review 才部署。** retro.sh 只「建議改點」，
不自動改規範。這就是文章說的「Loop 4 的人類切入點 = harness 改動要經過人類 review」。
self-improving 不等於 self-deploying。

## 限制 / 升級路徑

retro.sh 是 grep 啟發式，不讀語意。訊號量小時夠用(指出「哪個檔反覆出事」已足以開 PR)。
等 trace 變大、誤報變多，再把 retro.sh 換成讀完整 trace 的 LLM retro agent
(輸入同樣是 `.planning/*.md`，輸出同樣是 `[DEV-RULE]` PR 草稿)——介面不變，只換引擎。
