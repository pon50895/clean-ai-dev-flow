---
name: to-tickets
description: 把 plan / spec / 對話拆成 tracer-bullet 垂直切片票,每票明宣告「阻塞邊」(哪些票先完成才能開始),落 .planning/phases/<phase>/tickets/,直接餵 feature-pipeline 平行派工。寬重構走 expand–contract。觸發詞:「to tickets」「拆票」「拆成 ticket」「拆工作」「派工前拆」「垂直切片」「plan 拆成可派的票」。
---

# to-tickets — plan 拆成 tracer-bullet 票

改造自 mattpocock/skills 的 `to-tickets`(MIT license),接上 GSD **Plan → feature-pipeline 派工** 之間的前置。單一職責:把 plan / spec / 對話拆成一組**票**——tracer-bullet 垂直切片,每票宣告**阻塞它的其他票**。補的是:Micro-Wave / atomic PR 常只是「習慣」不是「產出物」,哪些票互相阻塞、哪些能平行派給 subagent,每次靠臨場判斷——這支把它形式化。

## 何時用

- `to-spec` 寫完 PLAN.md 後、feature-pipeline 派工前。
- 一塊工作要拆給多個 worktree / subagent 平行做,需要先算清楚相依與可平行的邊界。

## 流程

### 1. 收集 context
用對話裡已有的;user 傳 ref(spec 路徑 / PR / issue)就 fetch 讀全文。

### 2. 探 codebase(選用)
還沒探就用 codebase-memory 理解現狀。票的標題 / 描述用領域 glossary 詞彙,尊重該區 ADR。找 **prefactor** 機會:「先讓改動變容易,再做那個容易的改動。」

### 3. 拆垂直切片
拆成 **tracer bullet** 票:

- 每片切一條**窄但完整**的路徑,打穿每一層(schema / API / UI / 測試)——**垂直**,不是單層的水平切片。
- 完成的片能**自己 demo / 驗**。
- 每片 size 到**塞得進一個 fresh context window**(= 一個 subagent brief 的大小)。
- prefactor 先做。

每票給**阻塞邊**——哪些票必須先完成它才能開始。無阻塞的票可立即開跑。

### 4. 寬重構例外 = expand–contract
**寬重構**(rename 一個欄位、retype 一個共享 symbol 這類單一機械改動,blast radius 掃遍全 repo,一次改斷上千個 call site,沒有垂直切片能單獨落綠)不要硬塞成 tracer bullet,排成 expand–contract:
- **expand**:新形加在舊形旁邊,什麼都不破。
- **migrate**:call sites 分批遷移,批大小按 blast radius(每 package / 每目錄)切,每批一票 blocked by expand,靠舊形還在保 CI 批批綠。
- **contract**:沒有 caller 後刪舊形,一票 blocked by 所有 migrate 批。
- 連批都無法單獨綠時:保留序列,但讓它們共用一條 integration branch,全部 block 一個 final integrate-and-verify 票,綠只承諾在那裡。
- 用 codebase-memory `detect_changes` 吃 git diff 估 blast radius,決定批怎麼切。

### 5. Quiz user
把拆解當編號列表 present。每票給:**標題** / **Blocked by**(哪些票先完成)/ **交付什麼**(這票讓什麼端到端行為 work)。問 user:粒度對嗎(太粗 / 太細)?阻塞邊對嗎(每票只依賴真的 gate 它的票)?要不要併 / 拆?迭代到 user approve。

### 6. 落票
approve 後,一票一檔寫 `.planning/phases/<phase>/tickets/<NN>-<slug>.md`,依相依序編號(blocker 先,從 `01` 起)。工作 **frontier**:阻塞邊全完成的票才可開;純線性鏈就從上到下。不改 / 不關任何 parent issue。

**餵 feature-pipeline**:無阻塞邊的票 → 可同時派給不同 subagent / worktree 平行跑;阻塞邊 = 派工拓撲(誰等誰)。

## 票模板

```
# <NN> — <票標題>

**要建什麼:** 這票讓什麼端到端行為 work,從使用者視角——不是分層的實作清單。
**Blocked by:** gate 這票的票號 / 標題,或「無 — 可立即開始」。
**Status:** ready

- [ ] 驗收條件 1
- [ ] 驗收條件 2
```

不放具體檔案路徑 / 碼片段(很快 stale)。例外:prototype 產出、比散文更精確的 snippet(state machine / schema / type shape)可內聯,註明來自 prototype,只留決策精華。

完整鏈:`grill-me` / `grill-with-docs`(Discuss)→ `to-spec`(凝規格)→ **`to-tickets`(拆票)** → feature-pipeline(平行派工)。
