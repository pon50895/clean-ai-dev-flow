# 模型調度守則（MODEL_DISPATCH）

> 交付 C+E。讀者是弱模型 session。原則一句話：**指揮官不下場**——主對話只花在
> 「換便宜模型就掉品質」的判斷上；大量讀取、掃 repo、查網頁、批次改檔、驗證一律派便宜 subagent。
> 制度出處：2026-07-04 高階模型 session；診斷依據見專案的 harness 診斷紀錄（若有）。

## 1. 可用模型（模型用系列名，不釘版本號；版本隨最新版）

| 別名 | 系列 | 用途定位 |
|---|---|---|
| fable | Fable 系列 | 最高階。只用在:立制度、最難的架構/金流判斷、多方案評審的裁判;調研/企劃層 |
| opus | Opus 系列（現行 `claude-opus-5-5`） | 升級目標。需要高判斷密度的實作/審查、sonnet 連錯兩次後的接手；產出照 §5 抽驗 |
| sonnet | Sonnet 系列（現行 `claude-sonnet-5-5`） | 中階工作馬。**subagent 預設值**。搜尋、研究、實作明確規格、審查初篩 |
| haiku | Haiku 系列 | 輕量。批次機械改檔、格式轉換、大量檔案掃描 |

- Agent 工具 `model` 參數收：`sonnet` / `opus` / `haiku` / `fable`；別名一律解析到該系列最新版。
- Workflow 內 agent 另有 `effort`：`low`/`medium`/`high`/`xhigh`/`max`——機械工用 `low`，最難的 verify/judge 才升。
- **勿憑記憶填型號**。要寫 ID 時查 harness 文件，文件只寫系列名，現行 ID 僅作註記。

### 1.1 模型選擇政策

**預設 sonnet、升級 opus**，兩者都隨最新版。成本與品質的取捨：貴模型不等於誠實或受控，subagent 產出一律照 §5/§6 驗收（歷史實證：subagent 在 log 塞捏造資料——不存在的檔案、假 session_id）。

1. **每次 `Agent` 呼叫必須明寫 `model`**。省略 = 繼承 session 模型，成本不可控。
2. **subagent 預設 `sonnet`**；調研 / 企劃層用 `fable`（§8 流水線慣例）；高判斷密度的實作或審查用 `opus`。
3. **升級條件**：見 §5（haiku 錯一次升 sonnet；sonnet 同一子任務連錯 2 次升 opus；opus 仍錯則停下回報 user）。
4. **錯模處置**：發現在跑的 agent 用錯模型——剛派的停掉重派（把前一支 worktree 路徑寫進新 brief 接手）；已深入的讓它跑完，產出加倍驗。
5. **產出驗收（任何模型、任何來源）**：fresh-agent 二驗 + 對照表 + 陽性對照 + §5「抽驗存在性」，缺一不收。這是程序性紀律，非自動稽核機器（#2558 教訓：不造無法驗證的機器）。

## 2. 本環境派工的硬限制（先讀，否則派了就被擋）

1. **ai-team-os hook 會擋非 Explore/Plan 型別的 Agent 派工**（`[OS BLOCK] Local agents not allowed`）。
   繞法（擇一）：(a) 用 `subagent_type: "Explore"`（唯讀搜索/研究）或 `"Plan"`（規劃）；
   (b) 用 `Workflow` 工具（不受此限，適合多 agent 編排）；(c) user 已核准移除該 hook 後恢復自由派工。
2. 主樹唯讀（live-QA 樹）。要改檔的 subagent 給它 worktree（Agent `isolation: "worktree"` 或先手動建）。
3. 瀏覽器（claude-in-chrome）只有主線能開，不能派給 subagent——視覺驗證是主線工作；截圖後**在對話中嵌圖讓 user 目視確認**（AI 不以自己判讀截圖代替 user 確認）。

## 3. 什麼工派給誰（判準表）

| 任務 | 派給 | 理由 |
|---|---|---|
| 「X 在哪/誰呼叫 X」 | 不派——`mcp__codebase-memory__*` 直查 | 圖索引比 agent 快且省 |
| 廣域搜索（多檔案/多命名慣例） | Explore + sonnet | 唯讀、結論導向 |
| 競品/網頁研究 | Explore + sonnet（背景跑） | 主線不等網頁 |
| 批次機械改檔（重命名、格式、i18n key 填充） | Workflow/agent + haiku, effort low | 規格明確 = 便宜模型夠 |
| 實作明確規格的 feature | sonnet（附驗收條件） | 規格寫清楚就不掉品質 |
| 金流/安全/併發邏輯的設計與 review | opus 以上，主線親做 | 換便宜就掉品質的判斷 |
| 多維稽核（安全/金流/schema） | Workflow `stability-audit`（多 agent + 對抗驗證） | 已驗證可用的既有編排 |
| 驗證別人的產出 | fresh-context agent（見 §5） | 不自驗 |

## 4. 交辦三要素（每次派工的 prompt 必含，缺一不派）

1. **目標與動機**：做什麼 + 為什麼（讓 agent 能在邊角自行取捨）。
2. **驗收條件**：可判定的完成標準（「tsc exit=0」「回傳含 file:line 的清單」「頁面 200 且含字串 X」）。
3. **回報格式**：subagent 只回**結論 + `檔案:行號`**；長產物存檔後回傳路徑；不要貼原始碼/HTML 全文。

## 5. 升降級與驗證

- **升級**：haiku 錯一次 → sonnet；sonnet 同一子任務連錯 2 次 → 帶完整失敗軌跡升 opus。同一件事連錯 2 次即停，不做第 3 次同樣嘗試；opus 仍失敗 → 停下來回報 user。
- **降級**：高階模型解出「模式」後（例：確立了修法樣板），批次套用降回 haiku/sonnet。
- **驗證不自驗**：檔案產出用另一個 fresh-context agent read-back；程式碼用測試/實跑（不是 tsc 綠就算）；高風險判斷（金流/安全/刪東西）加第二意見或多答案評審擇優。
- **抽驗存在性（反捏造）**：subagent 回報中引用的檔案 / `檔案:行號` / 紀錄（log、jsonl、測試輸出），收貨時至少抽驗一筆真實存在（ls / grep / 打開該行）；**發現捏造一筆，整份回報作廢**、該 agent 的產出全部重驗。已知失敗模式=捏造 file:line 與捏造實測資料（實證：subagent 在 edit-fires.jsonl 塞不存在的檔與假 session_id）。
- **「完成」的定義**：見 `dev-rule/JUDGMENT_RUBRICS.md` §2——工具回報成功 ≠ 完成。

## 6. 任務交辦範本（E）——複製填空

### 搜尋
```
目標:找出 <什麼> 在 codebase 的所有出現處,因為 <動機>。
範圍:<目錄/檔型>。排除:<node_modules/test 等>。
驗收:回報「檔案:行號 + 一句該處在做什麼」的清單;沒找到就明說沒找到,不要猜。
回報:只要清單,不貼原始碼段落。
```

### 實作
```
目標:在 <檔案/模組> 實作 <行為>,因為 <動機>。
規格:<輸入/輸出/邊界條件,逐條>。
限制:surgical——只碰列出的檔;風格照同檔既有慣例;不加沒要求的抽象。
驗收:<測試指令> 全綠 + tsc exit=0;新增行為附最小測試。
回報:diff 摘要(檔案:行數) + 測試輸出末 10 行。
```

### 重構
```
目標:把 <現狀> 重構成 <目標形狀>,因為 <動機>。行為不可變。
安全網:先確認 <既有測試> 綠,重構後同一批測試必須仍綠。
限制:不順手修 bug、不改公開介面(有要一併改的先回報再動)。
驗收:測試前後皆綠 + diff 只含結構性變更。
回報:改了哪幾檔(檔案:行數)、行為等價的證據(測試輸出)。
```

### 研究
```
目標:回答 <問題>,供 <什麼決策> 使用。
方法:<來源範圍:web/codebase/文件>。二手資訊標明出處;查不到標「未確認」,不編造。
驗收:結論 ≤N 條 bullet,每條附證據(連結/檔案:行號);最後給「建議 + 信心程度」。
回報:只回結論,原始資料存 <路徑> 後傳路徑。
```

### 審查
```
目標:審查 <PR/diff/檔案>,焦點 <正確性/安全/金流/效能 擇一>。
方法:對每個 finding 給「檔案:行號 + 失敗情境(具體輸入→錯誤結果)」;
     不確定的標 PLAUSIBLE,能構造出重現的標 CONFIRMED。
驗收:finding 清單按嚴重度排序;0 個也要明說「查過 X/Y/Z 沒發現」。
回報:只回 finding 清單,不重述 diff 內容。
```

## 7. 維護（誰能改這份檔）
見 `dev-rule/JUDGMENT_RUBRICS.md` §5 維護協議。本檔的「模型實值」（§1 表）任何 session 查證後可自行更新（附查證來源）；其餘章節改動需 user 核准。

## 8. 完整開發流水線（多模型分工，user 2026-07-10 拍板）
把「調研 → 企劃 → 依難度分派開發 → 驗證 → 開 PR」串成標準流程，用哪個模型跑哪一階見
`.claude/skills/feature-pipeline/SKILL.md`（可用觸發詞「feature pipeline / 跑開發流水線」叫起）。
一句話：Fable 調研出企劃 → user 拍板 → Opus 拆 PLAN →
依任務難度派 haiku/sonnet/opus 開發（套 ponytail/karpathy）→ 依 Door 驗證（雙向門 Sonnet、單向門 Opus + user 細看；機械性審查一律 Sonnet；小問題審查者就地自修）fresh-context
（R1-R11 + §2.5 測試門檻）→ 通過後 Opus 於 RTM 開 open PR → user 親自 merge → deploy 需明講。
本檔 §1 模型表是該 skill 選模型的依據。
