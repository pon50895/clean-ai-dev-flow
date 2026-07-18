---
name: feature-pipeline
description: 跑一條「調研 → 企劃 → 依難度分派開發 → 驗證 → 開 PR」的多模型開發流水線(user 拍板標準)。研究層由最高階模型產企劃、Opus 指揮開發計畫、依任務難度選 agent 模型、Sonnet/Haiku 驗證、Opus 於 RTM 開 PR。全程仍守 dev-rule 原有開發標準(R1 禁 emoji、branch+test+PR gate、RTM、ponytail/karpathy)。觸發詞:「開發流水線」「feature pipeline」「跑開發流程」「照標準流程做這個 feature」。
---

# feature-pipeline

the project 的標準 feature 開發流水線(多模型分工)。單一職責:把一個 feature 需求，按固定五階段推到「可上線的 open PR」，每階段用對的模型、守對的門檻。

不重複既有制度——模型對照見 `dev-rule/MODEL_DISPATCH.md`；紅線見 `dev-rule/AI_INSTRUCTIONS.md` R1-R11、測試門檻見 `dev-rule/GSD_WORKFLOW.md` §測試門檻;工程心法見 `ponytail` / `karpathy-guidelines` skill。本檔只定「流程骨架 + 每階段的 gate」。

## 何時用
- 要把一個非 trivial 的 feature 從想法做到 PR，且想用多模型分工壓成本、保品質。
- 觸發詞:「跑開發流水線 / feature pipeline / 照標準流程做 X」。
- trivial 一次性小改不需要走全流程,用判斷。

## 五階段(每階段有一個交付物 + 一個 gate)

### 1. 調研(Research)→ 企劃
- 模型:**最高階模型**(研究/判斷/綜合能力最強的那顆;若你的環境有專屬頂層模型別名,對應到這裡)。
- 做:市場/競品/可行性/風險/成本調研,產出**企劃**(問題、選項、建議、風險、成本、粗估工期),存 `.planning/research/<TOPIC>_<date>.md`。
- **Gate**:企劃給 **user 拍板**才進下一階。研究層可指派 subagent 分維度(競品掃描、法遵、成本)。

### 2. 企劃 → 開發計畫(Plan)
- 模型:**Opus**(指揮官,不下場寫大量 code)。
- 做:把拍板的企劃拆成**原子化 Task**(GSD:Research→Code→Integration→Verification)+ **PR 拆分**(每 PR 一邏輯單位)+ golden/測試策略,寫 `.planning/phases/<phase>/PLAN.md`。
- **Gate**:PLAN 的範圍與 PR 拆分給 user 過目(至少關鍵取捨),再開工。

### 3. 依難度分派開發(Execute)
- 模型:**按任務難度選**(對照 `dev-rule/MODEL_DISPATCH.md`):
  - **haiku** — 機械/格式/大量小改、樣板接線。
  - **sonnet** — 規格明確的實作、中等複雜。
  - **opus** — 高風險金流/安全、架構性、產品核心領域的判斷邏輯(規則正確性)。
- 做:各 dev agent 在自己 feature branch 上小步 commit;**每個 code 改動預設套 ponytail(最省解法)+ karpathy(想清楚、精準改、可驗證成功條件)**。平行改共享檔要 worktree 隔離。
- **Gate**:寫完自帶測試(三道:unit/scoped regression/build,見 `dev-rule/GSD_WORKFLOW.md` §測試門檻);tsc 綠、相關 spec 綠。**未寫測試不進驗證。**

### 4. 驗證(Verify)
- 模型:**Sonnet 或 Haiku**(fresh-context,不自驗)。
- 做:對每個 PR 的 diff 做**多維獨立 review**(fresh-context,不自驗)。**維度全集(user 拍板,每次 review 缺一不可)**:
  1. **功能完整性** — 有沒有做到、邊界/錯誤路徑有沒有顧
  2. **規格符合** — 符 user 拍板的規格與產品核心領域規則
  3. **視覺**(若有 UI) — 你的專案的 UI 標準(主題一致、i18n、可及性,依專案而定);有視覺驗證 skill 就派上
  4. **法遵/合規**(若專案受規管) — 適用法規的揭露/同意/對外文案要求;派對應的合規 reviewer
  5. **金流**(若涉及計費) — 計費/退款正確・歸屬・冪等;派對應的金流 reviewer
  6. **效能** — 查詢/N+1・載入・快取/ISR・背景任務可靠性
  7. **CX 合理性** — 信任・摩擦・認知負荷・誠實邊界
  8. **後台/管理端一致性**(若有 admin) — 權限最小化(特權角色對使用者個資 least-privilege)・i18n・與既有 admin 樣式和狀態機一致(不自成一格)
  9. **karpathy 工程心法** — 想清楚・簡潔優先・精準修改・目標驅動可驗證(`karpathy-guidelines`)
  10. **ponytail 過度設計** — YAGNI・最省解法・可刪則刪・無投機抽象(`ponytail`)
  另照 **`dev-rule/AI_INSTRUCTIONS.md` R1-R11**(**R1 無 emoji**:code/註釋/log/PR body/UI 全掃,除 review 這一維外,寫入時另有 `redline-guard` hook 機器擋 emoji,雙重 gate;R3 全檔覆寫、R9 main、R11 --no-verify)+ **`dev-rule/GSD_WORKFLOW.md` §測試門檻** + 邏輯正確性。**每維逐條附「檔案:行號」證據,回 PASS / PASS-with-nit / FAIL**。依 PR 性質派對應 reviewer(碰金流→金流/合規 reviewer、碰 UI→視覺驗證 skill、邏輯/效能→品質稽核 agent)。可用 `code-review` / `ponytail` / `karpathy-guidelines`,以及專案自備的領域術語 reviewer(若有)。
- **Gate**:FAIL → 打回第 3 階修;安全/金流類的「PASS-with-nit」若 nit 是覆蓋缺口,先補再開。

### 5. 開 PR(Ship)
- 模型:**Opus**(推 PR 狀態)。
- 做:確認「可上線」(驗證通過 + tsc/test 實跑綠 + mergeable)後,推分支、開 PR,於 **RTM** 轉 open(`gh pr ready`)。**PR body 也禁 emoji(R1 含 PR;harness 預設會在 PR body 尾端加一行機器人圖示的 Generated-with 標語,務必刪掉)。** 多 PR 疊放用 stacked(base 指前一個分支)。
- **Gate**:**PR 只在 RTM 開 open**,user 於 RTM 親自 merge(solo review path 見 memory)。**prod deploy 需 user 明講「deploy/上線」才做**,預設止於 PR。

## 貫穿全程的硬標準(不可省)
- **R1 禁 emoji**:code/註釋/log/PR body/回覆全不行;標記用文字(可/不可/是/否),不用勾叉符號。
- **branch+test+PR gate**:一律 feature branch,絕不在 main 直 commit;測試門檻不跳(R9/R10)。
- **RTM 紀律**:PR open only at RTM;user 只在 RTM review + 親自 merge。
- **ponytail + karpathy**:每個 code 改動預設套用(最省解法 + 想清楚精準改)。
- **驗證不自驗**:寫的人不驗自己;交付附證據(檔案:行號 / 實跑輸出)。

## 一句話流程
最高階模型 / Opus 調研出企劃 → user 拍板 → Opus 拆 PLAN → 依難度派 haiku/sonnet/opus 開發(套 ponytail/karpathy)→ Sonnet/Haiku fresh-context 驗證(R1-R11+測試門檻)→ 通過後 Opus 於 RTM 開 open PR → user 親自 merge → deploy 需明講。
