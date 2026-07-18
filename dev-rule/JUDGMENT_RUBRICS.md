# 判斷力 Rubrics（JUDGMENT_RUBRICS）

> 交付 D+F。把高階判斷寫成弱模型可打勾執行的清單，每條附正例/反例（皆為去識別化的實務案例）。
> 配套：`dev-rule/MODEL_DISPATCH.md`（派工）。

## 1. 何時該升級模型（或把問題還給 user）

升級判準——任一成立就升：
- [ ] 同一子任務：**haiku 錯 1 次即升 sonnet；sonnet 連錯 2 次才升 opus**（帶完整失敗軌跡升級，不是重貼一次 prompt；門檻細節以 `MODEL_DISPATCH.md` §5 為準）。
- [ ] 任務涉及**金流正確性 / 併發 / 安全邊界**的「設計」而非「照抄樣板」。
- [ ] 需要跨 3+ 個模組推理出「改 A 會不會壞 B」且 codebase-memory 的 detect_changes 答不了。

**正例**：唯一鍵並發插入的 race——「交易內 catch 唯一鍵衝突為何無效」是 DB 語義推理 → 高階模型判斷；判完的修法（批量插入設定跳過重複）是樣板，套用可降級。
**反例**：i18n key 填充連錯兩次就升 opus——錯的原因是規格沒寫清楚，該修的是交辦 prompt（補驗收條件），不是升模型。

## 2. 何時算「真的完成」

全部打勾才算完成；工具回報成功 ≠ 完成：
- [ ] 用**最終使用者的方式**驗過一次（頁面=瀏覽器真載；API=curl 真打；build=真跑 `next build`/`vite build`，不是只 tsc）。
- [ ] 測試綠是「相關的測試」綠，且紅的部分已證明是 pre-existing（stash/clean-base 對照過）。
- [ ] 暫時狀態已收（dev server 關/告知、worktree 清、env flag 還原）或明列在回覆的收尾清單。
- [ ] 有副作用的動作（deploy/merge/發信）逐一確認過事實結果，不是看指令 exit 0。

**正例**：某排程頁「線上也壞」誤判——curl 抓 SPA 殼看到 404 字串就下結論，瀏覽器真載其實正常。結論：判「壞」與判「好」都要用真瀏覽器。
**反例**：tsc 綠就 push → 一個只在 production build 才觸發的用法（例如框架對某 hook 的 SSR 限制）讓 prod build 炸掉，本機 tsc 完全看不到。

## 3. 何時停下來問 user（vs 自決）

**必問**（任一成立）：
- [ ] 動作不可逆且出了門（prod deploy、對外發布、寄信、刪資料）。**deploy 要 user 明講「deploy/上線」才做**——「ok」只授權問句裡最小的那一步。
- [ ] 商業/定價/法遵/品牌語感的取捨（對外文案的調性是 owner 層級決定——AI 出草稿、user 定稿）。
- [ ] 發現的問題超出本次 scope 且修了會改行為（先 surface，不順手修）。
- [ ] 兩份規格文件互相矛盾。
- [ ] 改動會**放寬或關閉任何安全/驗證機制**：限流(rate limit)、輸入驗證、簽章/付款簽章驗證、權限/authz 檢查、CSP/CORS、資安掃描器、pre-commit/push hook、Dependabot 類自動化。**收緊可自決，放寬必問**——「測試過不了所以放寬驗證」是事故的開頭，不是修法（另見 §4 停手訊號、CLAUDE.md R5/R11、§2 secrets 清單）。

**自決不問**（問了反而煩）：
- in-scope 的實作細節、測試怎麼寫、worktree/分支操作、便宜 subagent 派工、文件 drift 的當場修正（**限 §5 表中標「可自改」的檔案；CLAUDE.md / hooks / settings.json 仍需問 user**）。

**正例**：某個「擋重複提交」需求的擋法有三種 trade-off（全擋 vs 同類擋 vs 只擋處理中）→ 問了，因為它改變用戶行為。
**反例**：該問而沒問——把「merge+deploy」綁在一句問，user 說 ok 就上了 prod（user 只想要 PR）。一句話一個授權。

## 4. 什麼訊號代表「方向錯了該換路」（而非重試）

- [ ] 同一個修法連續 2 次被同一個 gate/error 擋 → 讀懂 gate 的訊息換做法，不是換寫法再撞（例：heredoc gate → 改 `git commit -F`，不是換 heredoc 語法）。
- [ ] 為了讓工具動起來開始「繞過安全機制」（--no-verify、skip hook、關掉驗證）→ 立即停，這是方向錯的最強訊號（R11）。
- [ ] 修 A 引出 B、修 B 引出 C（第三層連鎖）→ 停下來畫因果，多半是根因找錯層。
- [ ] 開始想「先 merge 再補測試」→ R10 紅線，回頭。

**正例**：screencapture 拿不到瀏覽器截圖 → 換路（對話內嵌圖/部署真站），不是試第五種截圖指令。

## 5. 維護協議（F）——這套制度檔怎麼安全演化

| 檔案 | 弱模型可自行改? | 規則 |
|---|---|---|
| `MODEL_DISPATCH.md` §1 模型實值表 | 可 | 查證後可更新，commit message 附查證來源 |
| `MODEL_DISPATCH.md` 其他章節 / 本檔 | 先問 user | 提案 diff 給 user 看過再進 PR |
| `CLAUDE.md` | 不可 | 依其 footer：PR 標 `[CLAUDE.md]` + user review |
| 診斷 / 事後檢討檔（dated） | 可（限新增 dated 檔） | 舊診斷不改寫，新事件寫新檔或 memory |
| memory（`feedback_*`/`project_*`）| 可 | 照既有 memory 慣例；教訓優先寫 memory，重複踩 3 次以上才升格進 dev-rule |
| hooks / `settings.json` | 不可 | user 核准才動（碰 agent 編排 / 權限的 hook 一律照此） |

**踩雷教訓的落點順序**：memory 一筆（當下）→ 若跨 session 重複發生 → 升格寫進本檔或 MODEL_DISPATCH（走 PR）→ 若可機器化 → 提案做成 hook/lint（走 skillopt 流程）。
**精簡時機**：本檔或 MODEL_DISPATCH 超過 200 行、或有條目 3 個月沒被引用過 → 跑一次精簡提案給 user。

## 6. Session 收尾 checklist（每次 context 將滿或收工前）

- [ ] 背景程序清點：dev server / Workflow / BG task——關掉或明列給 user。
- [ ] worktree 清點：本 session 開的，merged 的清掉、未完的寫進 handoff。
- [ ] 未 push 的 commit / 未開的 PR：處理或交接。
- [ ] handoff 寫了嗎（100-150 行上限）？memory 該記的記了嗎？
- [ ] 對 user 的未兌現承諾（「稍後給你 X」）：兌現或明說沒做。
