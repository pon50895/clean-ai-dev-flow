---
name: to-spec
description: 把已經討論 / grill 完的結論「綜合」成一份規格(問題陳述 + user stories + 實作決策 + 測試 seam + scope),不再訪談,直接凝固成文,落 GSD Plan 階段的 PLAN.md。接在 grill-me / grill-with-docs 之後、寫 PLAN 之前。觸發詞:「to spec」「凝成規格」「寫 spec」「把討論變 PRD」「Plan 前收斂」「訪談完了寫規格」。
---

# to-spec — 對話凝成規格

改造自 mattpocock/skills 的 `to-spec`(MIT license),接上 GSD 四階段的 **Plan** 關卡。單一職責:把「已經在對話 / grill 裡討論清楚」的結論**綜合**成一份規格——**不再訪談**(還要問就回去用 `grill-me` / `grill-with-docs`)。補的是「grill 完 → 結論散在對話裡 → 寫 PLAN.md 靠自由發揮重組」這個斷層。

## 何時用

- `grill-me` / `grill-with-docs`(Discuss)收斂後、寫 `.planning/phases/<phase>/PLAN.md`(Plan)之前。
- 需求已清楚,只差把它固化成有結構、可驗收、測試邊界已定的文件。

## 規則

1. **不訪談,只綜合**:用你已經知道的(對話 + codebase)寫。缺料就回去 grill,不要在這支邊寫邊問。
2. **測試 seam 先議定**:對應專案的測試門檻紅線——測什麼不是 Execute 尾聲才補想的事,在這裡就跟 user 釘死。

## 流程

1. **探現況**:用 codebase-memory(`get_architecture` / `search_graph` / `get_code_snippet`)理解要動的區域現狀;通篇用該領域的 glossary / SSOT 詞彙(專案 CLAUDE.md 或 kit.json 指的詞彙來源),尊重既有 ADR / spec(專案放設計文件的目錄,慣例 `.planning/design/`)。
2. **畫測試 seam**:標出要在哪一層測這個 feature。**優先用既有 seam、用能用的最高層 seam、seam 越少越好(理想=一個)**。需要新 seam 就提在最高點。**跟 user 確認 seam 符合預期再往下。**
3. **依模板寫規格**,落 `.planning/phases/<phase>/PLAN.md`(或該 phase 的 SPEC 檔)。

## 規格模板

```
## 問題陳述
使用者面對的問題,從使用者視角描述。

## 解法
問題的解法,從使用者視角描述。

## User Stories
一份「長」的編號列表。每條格式:
1. 身為 <角色>,我想要 <功能>,以便 <好處>
涵蓋 feature 的所有面向,盡量詳盡。

## 實作決策
會建 / 改的模組、要動的介面、技術澄清、架構決策、schema 變動、API 契約、關鍵互動。
不放具體檔案路徑或碼片段(很快 stale)。
例外:prototype 產出的、比散文更精確的 snippet(state machine / reducer / schema / type shape)
可內聯進對應決策,註明來自 prototype,只留決策精華不留可跑 demo。

## 測試決策
什麼是好測試(只測外部行為、不測實作細節)、會測哪些模組、prior art(codebase 裡類似的測試)。

## Out of Scope
明確劃出這份規格不做的事。

## 補充
其他備註。
```

## 收尾

規格落 `.planning/phases/<phase>/PLAN.md` 後,交給 `to-tickets` 拆成 tracer-bullet 票(餵 feature-pipeline 平行派工),或直接進 Execute。完整鏈:`grill-me` / `grill-with-docs`(Discuss)→ `to-spec`(凝規格)→ `to-tickets`(拆票)→ feature-pipeline(派工)。
