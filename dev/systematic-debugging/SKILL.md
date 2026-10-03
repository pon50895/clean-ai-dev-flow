---
name: systematic-debugging
description: 結構化除錯 SOP — 先找根因再動手,不靠猜。四階段:根因調查 → 對照分析 → 假設驗證 → 修復。補「單一 bug 深挖」的固定流程(廣度掃描另用穩定度審計類 skill)。觸發詞:「除錯」/「debug」/「找根因」/「為什麼會壞」/「systematic-debugging」,或連續 2 次以上「試了沒用」的 thrashing 跡象。改寫自 obra/superpowers 同名 skill,接上 codebase-memory / GSD / worktree 流程。
---

# Systematic Debugging — 先找根因,不靠猜

核心:**動手修之前先找到根因。對症狀打補丁 = 失敗。** 猜測式 try-and-check 不是更快,
是更慢(常引入新 bug)。改寫自 obra/superpowers,接上 codebase-memory 與 worktree/PR 流程。

## 何時用

- 一個具體 bug 卡住,或你發現自己「試了 X 沒用、再試 Y」連續 2 次以上(thrashing)。
- 多元件鏈路(client → API → 後端服務 / DB)不知道哪一層壞。
- 與穩定度審計類 skill 的差別:那類是「系統穩不穩」的廣度掃描;這支是「這個 bug 為什麼壞」的深度挖。

## 何時不用

- 還沒重現的「聽說會壞」→ 先重現(就是 Phase 1 step 2),不要憑想像改。
- 一行 typo / 編譯錯(stack trace 直接指)→ 直接修,不必走四階段。

## 四階段(缺一不可,紅旗出現就 restart)

### Phase 1 — 根因調查(動手前)
1. **逐字讀錯誤訊息**:stack trace / 行號 / error code 常直接給答案,別跳過。
2. **穩定重現 → 收斂成 red-capable 迴路**:重現步驟收斂成**一條指令**,且要**已實跑過、親眼看它紅一次**才算數(貼實跑輸出當證據,不是「應該會紅」)。四個勾:能紅(斷言確切症狀,不是「沒 crash」)、決定性(同輸入穩定同結果)、秒級(跑得起才會真的跑)、agent 自己能跑(不必求 user 手動操作)。**沒有這條已變紅的指令 = 還沒資格進下一步,更不准提修復假設。**
3. **Minimise**:紅了之後先把重現案例砍到最小——去掉跟症狀無關的步驟/資料/程式碼路徑,砍到再砍就不紅為止。縮到最小的案例本身常是線索;沒縮過就直接寫假設 = 又在猜。
4. **查近期改動**:`git log -p -- <file>`、相關 PR、依賴/設定 diff。多數 regression 在這步現形。同時排除「跑的是 stale 碼」(docker bind-mount、舊分支、未重啟的 dev server 都是經典陷阱)。
5. **跨層插探針**:多元件系統在每個邊界加 log/斷點,定位是哪一層壞,別假設。
6. **逆追資料流**:壞值往呼叫鏈上游追到源頭。用 codebase-memory 的 `trace_path` 一次拿整條呼叫路徑(含 callback / JSX 這類動態跳轉),比手動 grep + read 準。

### Phase 2 — 對照分析
- 找同 codebase 裡「會動的類似程式」(codebase-memory 的 `search_graph` / `trace_path`)。
- 完整讀參考實作(不是掃過),列出 working vs broken 的**每一處差異**。
- 釐清依賴、設定、隱含假設。

### Phase 3 — 假設與驗證
- 寫出明確假設:「我認為根因是 X,因為 Y」。
- **單變數**最小驗證:一次只改一個變因,看結果再前進。
- 不確定就承認知識缺口(問 user / 查文件),不要硬猜。

### Phase 4 — 修復
- **先寫 failing test**(重現該 bug 的單元 / E2E / 斷言),再修。
- 只做**一個**針對根因的改動;驗 fix + 確認無 regression(專案 `kit.json` 的 test 指令與 CLAUDE.md 的測試門檻)。
- 走獨立 worktree → PR;test 進同一 PR。
- **安全閥:同一問題 3 次以上修不好 → 質疑架構本身**,這是設計問題不是孤立 bug,停手找 user 討論。

## 紅旗(出現就回 Phase 1)

- 還沒搞懂就先提修法。
- 同時改多處。
- 跳過重現 / 證據蒐集。
- 「先試 X 看會不會好」心態。
- 每修一次就在別處冒出新問題。

## 收尾

- 修完且驗證後,若這個 bug 屬「會復發的行為/環境類」→ 寫進專案的 violations / lessons ledger(若專案有 learning-capture 腳本與 schema 就用它,慣例在 `.planning/learning/`);屬「值得變強制邊界」→ 交給 `skillopt` 蒸餾成 gate。
- 不寫主觀評語;根因與證據用事實陳述(`path:line` + 重現步驟 + diff)。

## 反例

- 拿「時間緊急 / 看起來很簡單 / 我很確定」當跳過階段的理由(原 skill 明列:這些都不成立)。
- 沒重現就改 code(改的是想像中的 bug)。
- 一個 PR 同時試三種修法(無法判斷哪個有效,也違反 atomic PR)。
