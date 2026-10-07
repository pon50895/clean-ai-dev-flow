---
name: feature-pipeline
description: 跑一條「調研 → 企劃 → 依難度分派開發 → 驗證 → 開 PR」的多模型開發流水線。研究層用 fable 系列產企劃、opus 系列指揮開發計畫、依難度分派開發(前端→fable、substantive 後端→opus、明確實作→sonnet、機械→haiku)、依單向門 / 雙向門複驗(單向門 opus + user 細看、雙向門 sonnet,fresh-context;小問題審查者就地自修不再多跑一輪)、opus 於 RTM 開 PR(PR body 標 Door 與 Blast Radius)。全程仍守專案 CLAUDE.md 原有開發標準(emoji 紅線、branch+test+PR、RTM、ponytail/karpathy)。觸發詞:「開發流水線」「feature pipeline」「跑開發流程」「照標準流程做這個 feature」。
---

# feature-pipeline

標準 feature 開發流水線(多模型分工),任何專案通用。單一職責:把一個 feature 需求,按固定五階段推到「可上線的 open PR」,每階段用對的模型、守對的門檻。

專案相關的值不寫死在本檔,從專案讀:test / lint / typecheck / build 指令與 workspace 名稱讀 `kit.json`;紅線與測試門檻讀專案 `CLAUDE.md`;模型分工的完整對照見 `~/claude-ops-playbook/C-model-dispatch.md`(專案有自己的 `dev-rule/MODEL_DISPATCH.md` 則以專案為準);工程心法見 `ponytail` / `karpathy-guidelines` skill。本檔只定「流程骨架 + 每階段的 gate」。

## 何時用
- 要把一個非 trivial 的 feature 從想法做到 PR,且想用多模型分工壓成本、保品質。
- 觸發詞:「跑開發流水線 / feature pipeline / 照標準流程做 X」。
- trivial 一次性小改不需要走全流程,用判斷。

## 多代理角色與統籌結構(大型任務必用)

單線由 main loop 邊聊邊統籌,在**大型/多批任務**會漏掉 lint、build gate:main loop 的 context 被別的 feature、除錯、對話塞滿,注意力被攤薄。**focused 的活不要交給滿載的 context。** 採三層分工,職責不混。

### 三層架構

**第 1 層 — user 對接 + 緊急調度(main loop)**
- 只做兩件事:(a) 跟 user 對話——收指令、轉述結論、拍板呈給 user;(b) 緊急調度——插隊、重導向、批間協調的「對外」那半。
- **不當統籌、不邊聊邊監管。** 大型任務一開工就把監管交給第 2 層,自己退回對接位。

**第 2 層 — 監管者(專職 opus 系列 agent,乾淨 context,只盯這一個 sub-project)**
- 統籌全流程:讀計畫 → 依計畫派/驅動第 3 層執行 → 每批**派 fresh-context 複驗**(不自驗)→ 判每批 RTM-ready → 把可 RTM 的 PR 呈給第 1 層。
- **批間協調是監管者的責任**:計畫中途升版、前一批的更正、下一批的相依(例:前一批的共用 token / 型別集要夠後一批用),主動同步給執行/複驗者,不讓 stale 資訊帶著跑。
- 為什麼要專職:乾淨 context 只裝這件事,注意力不被 user 對話與別的 feature 攤薄——監管才握得牢。

**第 3 層 — 執行(依角色/難度派)**
| 子角色 | 誰 | 職責 |
|---|---|---|
| 設計 + 規劃 | **fable 系列** | 企劃 / 設計系統 / 分批計畫 / 對映表。可再分維度派 subagent |
| 開發 | fable(前端/UI)/ haiku(最基本/機械)/ sonnet(明確實作)/ opus(substantive 後端:高風險金流·安全·架構與抽象邏輯·領域判斷) | 實作各批,套 ponytail/karpathy |
| 測試 / 複驗(裁判) | **fresh-context**,依 Door 選:單向門 opus、雙向門 sonnet,機械性審查角色一律 sonnet;**非作者** | 每批獨立多維複驗;機械類與小範圍正確性 finding 就地自修(見第 4 階) |

### 監管鐵律(三層都守)
- **執行者不當自己裁判**:誰執行、誰就不驗自己那批。每批 push 後一定派 fresh-context 複驗(乾淨 context),綠才 RTM。
- **層級不越權**:第 1 層不下場寫 code / 不邊聊邊監管;第 2 層不自驗自己協調的批(複驗是獨立第 3 層);第 3 層執行者不自 RTM。
- **harness 限制的務實處理**:若 subagent 無法再派 subagent(第 2 層監管者無法自行 spawn 第 3 層),則由第 1 層 main loop 當監管者的「手」代為 spawn——但**決策與協調的角色定位仍是監管者**,main loop 兼手時要刻意保持監管紀律不被 user 對話攤薄;能專職就專職。

## 五階段(每階段有一個交付物 + 一個 gate)

### 1. 調研(Research)→ 企劃
- 模型:**fable 系列**(最高階設計/研究層:高階調研、介面/契約設計、戰略方向建議;最貴但這層值得投。環境若無 fable,用最強的可用模型替代)。
- 做:市場/競品/可行性/風險/成本調研,產出**企劃**(問題、選項、建議、風險、成本、粗估工期),存 `.planning/research/<TOPIC>_<date>.md`。
- **Gate**:企劃給 **user 拍板**才進下一階。研究層可指派 subagent 分維度(競品掃描、法遵、成本)。

### 2. 企劃 → 開發計畫(Plan)
- 模型:**opus 系列**(指揮官,不下場寫大量 code)。
- 做:把拍板的企劃拆成**原子化 Task**(GSD:Research→Code→Integration→Verification)+ **PR 拆分**(每 PR 一邏輯單位)+ golden/測試策略,寫 `.planning/phases/<phase>/PLAN.md`。可先用 `to-spec` / `to-tickets` 產規格與垂直切片票。
- **Gate**:PLAN 的範圍與 PR 拆分給 user 過目(至少關鍵取捨),再開工。

### 3. 依難度分派開發(Execute)
- 模型:**按任務難度選**(前端→fable、substantive 後端→opus、明確實作→sonnet、最基本/機械→haiku):
  - **fable** — **前端/UI 處理**;以及最高階設計層(介面/契約設計、高階調研、戰略方向建議——見第 1 階段)。
  - **haiku** — 最基本程式操作、機械/格式、大量小改、樣板接線。
  - **sonnet** — 規格明確的中等實作。預設選這個。
  - **opus** — substantive 後端:高風險金流/安全、**架構與抽象程式邏輯的實作**(class 定義、abstract class / trait / interface 的實作、抽象層、跨模組結構;介面該長怎樣的「設計決策」歸第 1 階段的 fable,opus 負責把定案落成 code)、產品核心領域的判斷邏輯(規則正確性),或判斷密度高的實作。
  - **前提(降 tier 的先決條件):任務要拆分夠好——brief 切乾淨、範圍明確、驗收條件具體到該 tier agent 能獨立理解執行。** tier 愈低,拆分要愈細;拆不乾淨就別降 tier。
  - **升級規則:派定的 tier 先做到底,不預設往上換更貴的;只有同一任務連錯 2 次才帶完整失敗軌跡往上升 tier(haiku 錯 1 次即升 sonnet)。** 別一次不成就升;第 2 次錯後不做第 3 次同樣嘗試。
- **成本序**:fable > opus > sonnet > haiku(價格以 `~/claude-ops-playbook/C-model-dispatch.md` 為準)。**fable 最貴——只用於前端/UI、最高階設計/研究/戰略;非這些用途不預設 fable,複查亦禁預設 fable。** 預設 sonnet、升級 opus,全部用系列名(隨最新版),不釘版本號。
- 做:各 dev agent 在自己 feature branch 上小步 commit;**每個 code 改動預設套 ponytail(最省解法)+ karpathy(想清楚、精準改、可驗證成功條件)**。平行改共享檔要 worktree 隔離。
- **給開發 agent 的 brief 必帶「測試規則」段**(照抄,不放專案 CLAUDE.md;完整版在 `code-review` 的 Test shape):
  ```
  測試規則(只從對外介面測):
  - 後端 API 打 HTTP 路由,驗狀態碼 / 回應 / DB 結果;模組只用對外 export 的方法 + 真(測試)DB;前端用 testing-library 依角色與可見文字。
  - 只可 mock 跨程序外部服務(LLM、物件儲存、送關 / 政府申報、Email、訊息推播),不 mock 自己的內部模組。
  - 禁:套套邏輯(把實作常數 / 公式抄進測試當預期值)、斷言私有呼叫次數、斷言完整使用者文案字串(改斷言代碼 / 嚴重度)。
  - 計算類預期值要有獨立來源(官方範例、人工算好的 golden、真實資料),不可在測試裡用同一套公式算。
  ```
- **Gate**:寫完自帶測試(專案 CLAUDE.md 的三道測試門檻:unit / scoped regression / build);typecheck 綠、相關 spec 綠。**未寫測試不進驗證。**

### 4. 驗證(Verify)
- **先判 Door**(路徑規則強制,不憑感覺):`bash ${CLAUDE_SKILL_DIR}/door-check.sh <base> <head>`。內建預設涵蓋 migration / schema、稅費 / 金額計算、金流、auth / RBAC / 租戶、法定檔案(XML)產生器、對外推播、secret、deploy;專案在 `kit.json` `review.oneWayDoorPaths` 補自己的路徑(ERE regex,與預設聯集)。任一檔命中 → 單向門。腳本沒命中但你知道會動 prod 資料或對外送出 → 仍標單向門,並建議把該路徑補進 `kit.json`。
- 模型(fresh-context,不自驗):
  - **單向門 → opus 複驗 + PR 標「user 細看」**(user 審 merge 時逐行看,不只看摘要)。
  - **雙向門 → sonnet 複驗。**
  - **機械性審查角色(紅線掃描、emoji、格式、license grep、Test shape 檢查)一律 sonnet**,不論 Door。
  - **前提:brief 把任務切乾淨、驗收條件具體到 agent 能獨立理解執行,不靠猜。**
- 做:對每個 PR 的 diff 做**多維獨立 review**(fresh-context,不自驗)。**維度全集(每次 review 缺一不可;標「若」的維度,專案沒有該面向時標 N/A 並說明)**:
  1. **功能完整性** — 有沒有做到、邊界/錯誤路徑有沒有顧
  2. **規格符合** — 符 user 拍板的規格與產品核心領域規則
  3. **視覺**(若有 UI) — 專案的 UI 標準(主題一致、i18n、可及性,依專案 CLAUDE.md);專案有視覺驗證 skill 就派上
  4. **法遵/合規**(若專案受規管) — 適用法規的揭露/同意/對外文案要求;派對應的合規 reviewer
  5. **財務**(若涉及計費) — 金流/計費/退款正確・歸屬・冪等;派對應的金流 reviewer
  6. **效能** — 查詢/N+1・載入・快取/ISR・背景任務可靠性
  7. **CX 合理性** — 信任・摩擦・認知負荷・誠實邊界
  8. **後台/管理端一致性**(若有 admin) — 權限最小化(特權角色對使用者個資 least-privilege)・i18n・與既有 admin 樣式和狀態機一致(不自成一格)
  9. **karpathy 工程心法** — 想清楚・簡潔優先・精準修改・目標驅動可驗證(`karpathy-guidelines`)
  10. **ponytail 過度設計** — YAGNI・最省解法・可刪則刪・無投機抽象(`ponytail`)
  另照**專案 CLAUDE.md 紅線**(emoji 規則:code/註釋/log/PR body/UI 全掃,除 review 這一維外亦有機器 gate 擋,雙重防線;全檔覆寫、直接 commit 到受保護分支、`--no-verify` 等同理)+ **測試門檻** + 邏輯正確性。**每維逐條附「檔案:行號」證據,回 PASS / PASS-with-nit / FAIL**。依 PR 性質派對應 reviewer(碰金流→金流/合規 reviewer、碰 UI→視覺驗證 skill、邏輯/效能→品質稽核 agent)。可用 `code-review` / `ponytail` / `karpathy-guidelines`,以及專案自備的領域術語 reviewer(若有)。
- **Gate**:FAIL 依 `code-review` 的 Findings triage 分流,不再一律打回第 3 階:
  - **機械類**(命名、格式、遺留註解 / 工單代號、emoji、文案、測試斷言對齊現行行為)→ 複驗者直接修 → 重跑範圍化測試 → 原子 commit 推回 PR 分支。
  - **小範圍且修法明確的正確性問題**(含違反測試規則的測試:改寫成介面測試,不可刪)→ 複驗者修 + 補測試 → 另派一次 sonnet read-back → 通過才 commit。
  - **單向門路徑上的問題或需設計取捨** → 不自修,打回第 3 階(或呈 user),PR 標「需 user 判斷」。
  - 每次自修把「問題 / 修法 / commit sha / 測試輸出」補到 PR(comment + description 的 `## 審查紀錄` 段;Bitbucket 用 `git-gh-ops/bitbucket/` 兩支腳本)。
  - 安全/金流類的「PASS-with-nit」若 nit 是覆蓋缺口,先補再開。

### 5. 開 PR(Ship)
- 模型:**opus 系列**(推 PR 狀態)。
- 做:確認「可上線」(驗證通過 + typecheck/test 實跑綠 + mergeable)後,推分支、開 PR,於 **RTM** 轉 open(`gh pr ready`)。PR body 至少含以下段落(Door 取自第 4 階 `door-check.sh` 的結果):
  ```markdown
  ## Summary
  <改了什麼;用最小的圖 / 樹 / diff 草圖說清楚>

  ## Evidence
  <測試 / build / 截圖的實跑輸出,before / after>

  ## Door
  單向 | 雙向 —— <單向:命中的路徑 + 為什麼難回滾;標「user 細看」>

  ## Blast Radius
  <一個詞:例 局部 / 模組 / 跨模組 / 全站 / 對外> —— <merge 後可能波及什麼>

  ## 審查紀錄
  - <YYYY-MM-DD> <reviewer model> <PASS|FIXED|BLOCK|FLAG> <sha 或 -> <一句摘要>
  ```PR body 遵守專案 CLAUDE.md 的 emoji 規則(含 harness 預設附加的 Generated-with 標語:專案禁 emoji 就刪掉或換成純文字);多 PR 疊放用 stacked(base 指前一個分支)。
- **Gate**:**PR 只在 RTM 開 open**,user 於 RTM 親自 merge(以專案流程為準)。**prod deploy 需 user 明講「deploy/上線」才做**,預設止於 PR。

## Gate 對照:誰驗、何時驗

每個 gate 都有「機器擋 / 執行者自測 / 複驗者獨立驗」三個時點。**關鍵:機器沒擋的(build)靠人,執行者自報的(lint 數字/測試綠)一律由 fresh-context 複驗者重跑,不採信自述。** 指令一律取自專案 `kit.json`。

| Gate | 機器擋? | 執行者(push 前自測) | 複驗者(fresh-context,裁判) | 紀律 |
|---|---|---|---|---|
| **lint** | 專案若有 pre-push lint ratchet(baseline 檔)則是 | 自跑 `kit.json` 的 lint 指令,淨減無 regression,**不用專案的 escape hatch 環境變數繞** | **重跑確認數字 + baseline 向下 ratchet(非偷放寬) + 沒用 escape hatch** | escape hatch 只准淨減假回歸,淨增禁(改根因);baseline 只向下 |
| **typecheck** | 專案若有 pre-push typecheck baseline 則是 | 自跑 `kit.json` 的 typecheck 指令(各 workspace 用自己的 tsconfig) | 重跑確認無 regression | typecheck 綠 ≠ build 綠(見下) |
| **build** | **通常不擋** | **手動真跑** `kit.json` 的 build 指令(SSR / 靜態生成類錯誤 typecheck 抓不到) | **fresh 再跑一次當 ground truth** | build 是最容易漏的 gate——機器沒擋,執行者+複驗者各跑一次 |
| **P0 / 相關 spec** | 視專案 pre-commit 設定 | 跑受影響單檔 spec(不跑全套,免 OOM) | 重跑受影響 spec | 沒跑完不報數字 |
| **視覺** | 否 | 起 server 截圖抽驗 | **獨立起 server 截圖**(有深淺雙主題的檔雙 colorScheme);**refactor/token 化的零視差驗證要「跟線上 prod 對比」**,純樣式重構語意應零改變 | 截不到誠實標「僅 code 層」 |
| **整批整合 build**(多批任務) | 否 | — | **統籌:全部批 merge 後在最新 main 跑一次完整 build**,catch 跨批整合問題 | 單批各自綠 ≠ 合起來綠 |

**PR body gotcha**:含反引號的 body 用 `gh pr ... --body-file <檔>`,不要 inline(zsh 會把 `` `/login` `` 當命令替換執行,吃掉字)。

## 貫穿全程的硬標準(不可省)
- **emoji 紅線**(以專案 CLAUDE.md 為準):code/註釋/log/PR body/回覆全不行;標記用文字(可/不可/是/否),不用勾叉符號。
- **branch+test+PR**:一律 feature branch,絕不在受保護分支直 commit;測試門檻不跳。
- **RTM 紀律**:PR open only at RTM;user 只在 RTM review + 親自 merge。
- **ponytail + karpathy**:每個 code 改動預設套用(最省解法 + 想清楚精準改)。
- **驗證不自驗**:寫的人不驗自己;交付附證據(檔案:行號 / 實跑輸出)。

## 一句話流程
fable/opus 調研出企劃 → user 拍板 → opus 拆 PLAN → 依難度派 haiku/sonnet/opus/fable 開發(套 ponytail/karpathy)→ 判 Door(door-check.sh)→ 雙向門 sonnet / 單向門 opus fresh-context 驗證(專案紅線+測試門檻;小問題就地自修並記到 PR)→ 通過後 opus 於 RTM 開 open PR(標 Door / Blast Radius) → user 親自 merge → deploy 需明講。
