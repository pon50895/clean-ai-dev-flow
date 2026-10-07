---
name: agent-dispatch
description: 日常「單發交辦一個 subagent」時用的輕量紀律 —— 派工前寫好三要素 brief(目標+動機 / 驗收條件 / 回報格式)+ 派工前自檢(需求清楚嗎、能平行嗎)+ 收工後對驗收條件逐條驗(附證據了嗎、fresh-context 二驗了嗎),防止 brief 潦草→agent 誤解→返工。大型多批 feature 走 feature-pipeline,這支是日常一次一個 agent 的輕量版。觸發詞:「交辦」「派 agent」「派個 subagent」「開個 subagent 做」「dispatch」「寫 brief」「驗收 agent 產出」「agent 回報做完了」「這樣可以交出去嗎」。
---

# agent-dispatch — 單發交辦 subagent 的紀律

日常「派一個 subagent 去做一件事」時用。**不是** feature-pipeline(那是整條多模型流水線,大型/多批 feature 才用)。這支只解一個反覆踩的問題:brief 寫太潦草 → agent 誤解需求 → 來回返工;或把 agent 的自述當完成、沒逐條驗收就交出去 / merge。

用在三個時機:
1. 準備派 subagent 前(寫 brief)。
2. 需求還模糊、自己都講不清時(先釐清再派)。
3. agent 回報「做完了」時(驗收)。

---

## 0. 派工前自檢(先問自己三題)

- **需求清楚嗎?** 我能一句話講清楚「做完長什麼樣」嗎?講不清 → 先 `grill-me`(或 `grill-with-docs`,若碰領域模型/schema)把需求問到共識,**再派**。憑腦補開工 = R2。
- **是不是一個大改 / 難反轉的動作?** 是 → 先讓 agent(或自己)出**方案**給你拍板,再動手。不要一步到位大改。
- **能平行嗎?** 多個彼此獨立的任務 → 一則訊息內同時派多個 agent(省時)。有依賴 → 排序,等前一個結論再派下一個。
- **是不是自辦例外(de minimis)?** —— 見下方條款,四條都滿足才自辦,並存不是取代。

**自辦例外(de minimis)**:「實作(產出 diff)一律派」一字不動,這條例外只涵蓋查證類。

同時滿足四條 → 主對話直接做,不派 agent、不算違規:(1) 唯讀或冪等,不產生 diff、不 commit;
(2) 預估 <= 5 次工具呼叫;(3) 所需具體參數(連線、路徑、SHA)主對話已握有、agent 得重新探測;
(4) 產出是數字、清單或斷語。硬上限:第 8 次工具呼叫未完成、或發現需要 Edit/Write →
立即停手改派,把已取得的參數寫進 brief。

**證據形式**:自跑查證要下斷語時,必須引用該檢查的 stdout 原文。只產 exit code 的工具(`diff -q`、`grep -q`、`test -e`)只能支持「存在與否」,不得作為程度性斷語(更嚴重／更糟／形同虛設／不是小 bug)的唯一證據。

---

## 1. Brief 三要素(缺一不派)

每份 brief 必含,缺一項 agent 一定歪:

1. **目標與動機** —— 要做什麼 + **為什麼**(動機讓 agent 在邊界情境自己做對決定)。附「做完長什麼樣」的具體樣貌。
2. **驗收條件** —— 可逐條打勾的 Success Criteria(不是「做好一點」,是「X 檔 200、Y 測試綠、Z 無 emoji」)。這條後面收工時要一條條驗。
3. **回報格式** —— 要什麼回來:檔案:行號、實跑輸出、PR#、還是結論一句話。講明「附證據,沒證據的通過視同未驗」。

---

## 2. 貼進 brief 的紀律段(依情境刪不適用的行)

> 多數環境已有機器 gate(destructive-guard 類 hook)在守,但 brief 明寫可讓 agent 不去撞、user 零彈窗。

```markdown
## 工作區與紀律(嚴格)

**工作區**
- 你的 worktree:`<PATH>`,branch `<BRANCH>`,已從 origin/main(`<SHA>`)拉好。只在這個路徑工作。
- 禁止碰主樹 `<MAIN_TREE_PATH>`(user 正在用,可能有未提交改動)。
- 禁止碰其他 worktree(可能有別的 agent 在跑)。跨 worktree 讀取用 `git show <ref>:<path>`。

**破壞性操作(guard 會擋,別請求 user 放行)**
- 禁 `rm` —— rm 是 user 地盤,AI 不執行。要 user 刪 → 列清單給他。暫存檔放專案允許的暫存目錄(brief 指定)。
- 禁 `git stash`(worktree 共用 .git,會交叉污染)/ `reset --hard` / `clean -f` / `checkout --` 收拾非自身改動。
- 禁 `git push --force` / `--no-verify` / `HUSKY=0`。補漏檔用新 commit,不用 `--amend`。
- 禁對 `.env*` 做任何寫入(cp/sed/重導向也擋)—— 是 user 地盤的 secrets;讀取查證可以,不印 secret 值。

**prod**
- 禁止對 prod 做任何寫入。唯讀查證可以(ssh grep / psql SELECT)。prod DB 只能 SELECT,不 dump 個資。
- **禁止部署**(跑 deploy.sh)—— deploy 只有 user 本回合明講才做,不是你的權限。

**紅線 / 測試**
- R1 任何地方不得有 emoji(code / 註釋 / commit / 回報)。R3 精確 Edit 不全檔覆寫。R4 不提交編不過的 code。
- 非 super_admin UI 都要 i18n(zh-TW + en)。
- 輸出寫檔再讀(`cmd > /tmp/x.log 2>&1; code=$?`),不要 `| tail`(吃掉 exit code)。jest 只跑受影響單檔 `npx jest <file> --runInBand`。

**調查紀律**
- 每個判定追到根,列出查了哪些層才敢下判定;只看一個檔的判定不合格。
- 陽性對照鐵律:任何「不存在 / 沒觸發 / 沒有 X」的斷語,先用同一方法驗一個已知存在的 X;做不到就標「未驗」。
- 沒跑完不報數字。拿不準標「需 user 決定」。

**完成的定義**
- commit + push 到自己的 feature branch;不動 sibling worktree。不要開 PR(交辦者開)。
- 回報附實際輸出(測試/build/typecheck)。驗不到就說驗不到,不美化。
```

---

## 3. 收工驗收檢查表(agent 回報「做完了」時)

**不要把 agent 的自述當完成。** 逐條過:

- [ ] **對驗收條件逐條打勾** —— brief 第 2 項每一條都有對應證據?缺哪條就退回補,不放水。
- [ ] **附證據了嗎** —— 有實跑輸出 / 檔案:行號 / PR#?「通過」但沒證據 = 未驗,不採信。
- [ ] **fresh-context 二驗** —— 高風險 / 要推翻既有結論 / 要 merge 前,派一個**乾淨 context** 的 agent read-back 或實跑複驗。說的人不能是驗的人。
- [ ] **範圍乾淨** —— diff 只碰該碰的?有沒有順手改了沒交代的東西(scope creep)?
- [ ] **無 emoji / 守紅線** —— 快速掃一遍 R1、i18n、精確 Edit。

任一條不過 → 退回讓 agent 補,附具體缺口。不要自己默默補完當作它做的。

---

## 4. 防返工三條(本 skill 的存在理由)

1. **需求模糊先 grill-me,別急著派** —— 潦草 brief 是返工的頭號來源。一句話講不清「做完長什麼樣」就先釐清。
2. **大改先出方案再動** —— 難反轉的改動,先要一份方案拍板,不要 agent 直接一路改到底。
3. **premature merge 防範** —— 沒過第 3 節驗收表(尤其 fresh-context 二驗)之前不 merge、不 deploy。agent 說「好了」不等於可以出去。user 本回合沒明講 deploy = 不 deploy。

---

## 與其他 skill 的關係

- 需求釐清 → `grill-me` / `grill-with-docs`(碰領域模型/schema)。
- 大型多批 feature 的完整流水線 → `feature-pipeline`(這支太輕,那支才是牛刀)。
- 收尾換手 → `handoff`。
