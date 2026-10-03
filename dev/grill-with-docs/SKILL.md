---
name: grill-with-docs
description: 逼問式訪談 + 同步建領域模型——動工前一次一題把需求問清楚,同時把釐清出來的術語、定義、難以反轉的決策當場寫進文件(glossary / ADR)。用在牽涉領域模型或術語(專業領域詞彙 / 金流狀態機 / schema)的設計。補 GSD Discuss + 領域術語 SSOT。觸發詞:「grill with docs」「邊問邊建模」「釐清術語」「domain model」「這個詞到底指什麼」「建 glossary」「設計要動 schema / 領域概念」。
---

# grill-with-docs — 逼問 + 建領域模型

改造自 mattpocock/skills 的 `grill-with-docs`(= `grilling` + `domain-modeling`,MIT license),接上 GSD **Discuss** 與領域術語紀律。單一職責:動工前用訪談釘死需求,**同時**把釐清出的術語與決策寫進文件——邊問邊改模型,不是被動讀既有文件。

先做 `grill-me` 的訪談機制(見下),再疊上建模動作。

## 何時用

- 設計牽涉**領域模型 / 術語 / schema**:專業領域的核心概念、金流狀態機、資料庫 schema、API 契約。
- 一個詞在對話裡指涉不清(同一個詞在不同模組指不同東西),需要當場定義並落文件。
- 跨 service / API / DB 結構改動前(對齊專案的 API / schema 規格文件,路徑讀專案 CLAUDE.md)。

## 訪談機制(同 grill-me)

1. 一次一題,等回答再問下一題。
2. 走決策樹,先上游後下游,解決分支依賴。
3. 每題附推薦答案。
4. 事實自己查(codebase-memory / 既有 spec / code),決策才問人。
5. 達成共識前不動手改 code。

## 疊加:邊問邊建模

- **挑戰並釐清語言**:使用者用的詞跟既有 glossary / spec 衝突時當場點出;把模糊術語逼向精確、canonical 的定義;用具體的 edge case 情境壓測概念關係(例:「訂單已部分退款時,狀態算已付款還是已退款?」把邊界問出來)。
- **對照 code 校準**:把口頭說的行為對照實際 code(codebase-memory `search_graph` / `get_code_snippet`),矛盾馬上講出來(「你說 X 可以,但程式現在做的是 Y」)。涉及計算 / 引擎的行為要對真實輸出,不信註解。
- **決策定案就即時落文件**:
  - 術語 / 定義 → 寫進該領域的 grounding / SSOT(專案既有的詞彙來源位置,讀專案 CLAUDE.md;別另開重複來源)。
  - **難以反轉 + 沒 context 會意外 + 有真實取捨**的決策 → 開一則 ADR / 決策紀錄(放專案設計文件目錄,慣例 `.planning/design/`,或該 phase PLAN)。三個條件不同時滿足就不開 ADR,避免文件膨脹。
- **懶建檔**:有具體東西要記才建檔,不預先鋪空殼(YAGNI)。

## 領域邊界注意

- 領域術語邊界:專案管理 / 行銷詞不可滲進領域核心;不自創領域術語;不跨體系混用。專案若有領域術語稽核的標準或 skill,對齊它。
- 專案 CLAUDE.md 若有領域層的設計原則(例如資料模型該存參數而非寫死結論),建模時照做。

## 收尾

產出:共識摘要 + 已落地的術語定義 / ADR 路徑。交給 Plan 階段寫 `.planning/phases/<phase>/PLAN.md`。純需求釐清、不動領域模型時,用較輕的 `grill-me` 即可。
