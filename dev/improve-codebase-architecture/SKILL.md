---
name: improve-codebase-architecture
description: 掃 codebase 找「淺模組加深」機會(介面對實作太寬、或包了幾乎沒東西),出一份排序報告,選一個用 grill 深挖。與 ponytail-audit 互補:ponytail 獵「該刪的複雜度」,這支獵「介面太寬該收深的模組」——但**從屬於 ponytail:能刪先刪,不能刪才收深,平手刪**。觸發詞:「架構加深」「淺模組」「improve architecture」「介面太寬」「模組收深」「每月架構審計」。
---

# improve-codebase-architecture — 找淺模組加深機會

改造自 mattpocock/skills 的 `improve-codebase-architecture`(MIT license)。目標:找出架構摩擦,提出**加深機會**——把淺模組(介面幾乎跟實作一樣複雜、或包了幾乎沒東西)變深,提升可測性與 AI 可導覽性。

## 先講清楚:從屬於 ponytail(不打架的前提)

「加深模組」= 把大實作藏進小介面,本質偏**加抽象**;這跟 ponytail 的刪除優先 / YAGNI 會衝突。所以本 skill **明確從屬於 ponytail**:

- 每個疑似淺模組,先跑 **deletion test**:刪掉它會讓複雜度**收斂**,還是只是**搬家**?
  - 「收斂」→ 這就是訊號:先問**能不能直接刪**(ponytail 勝);刪不掉、且刪了複雜度會散掉,才問**能不能收深**。
  - 「只是搬家」→ 不是好目標,跳過。
- **平手一律刪**,不加抽象。單一實作的介面、只為測試抽出的純函式(真 bug 藏在怎麼呼叫它、而非函式本身)——這些是「刪 / 內聯」的對象,不是「加深」的對象。
- 這支跟 `/ponytail-audit` 是**每月巡檢的一對**:ponytail 掃「該砍的過度設計」,這支掃「介面太寬、locality 差的淺模組」。兩者衝突時 ponytail 優先。

read-only:只出報告,不改 code(要動另開 PR 走 GSD)。

## 詞彙

- 架構詞彙統一用:**module / interface / depth(深度)/ seam(測試接縫)/ adapter / leverage / locality**。別漂移成「component / service / API / boundary」。
- 領域詞用該領域的 glossary / SSOT(專案 CLAUDE.md 指的詞彙來源);尊重專案設計文件目錄(慣例 `.planning/design/`)的既有 ADR / spec,不重打已定案的決策。

## 流程

### 1. 探(先框範圍 — YAGNI)
加深只在「未來會再改到」的模組才划算,所以把重量放在**近期常動**的區域:

- user 指了方向(某模組 / 子系統 / 痛點)→ 直接用,跳過下面推斷。
- 否則 `git log --oneline` 走一段歷史找 hot spot(反覆出現的檔 / 區),讓那些路徑先吸引注意;改動很散沒明顯熱點就放寬。

先讀該區的領域 glossary 與 ADR。再用 codebase-memory(`get_architecture` 看叢集 / hotspot,`trace_path` 追流)+ 必要時派 `Explore` subagent 走 codebase,**有機地探、記下哪裡有摩擦**:

- 理解一個概念要在很多小模組間彈來彈去?
- 哪些模組**淺**——介面幾乎跟實作一樣複雜?
- 純函式只為可測性抽出、但真 bug 藏在怎麼呼叫它(沒 locality)?
- 緊耦合模組從 seam 漏出去?
- 哪些區沒測試、或透過現有介面很難測?

對每個疑似淺模組跑 deletion test(見上「從屬於 ponytail」)。

### 2. 出排序報告
產一份 self-contained 報告(Artifact 或 scratchpad HTML;CSS inline;外部 script 只允許 Artifact 白名單 CDN,圖表優先手刻 SVG,讀者離線也看得到)。每個候選一張卡:

- **檔案** — 牽涉哪些檔 / 模組
- **問題** — 現架構為何造成摩擦
- **解法** — 白話描述會怎麼改(**先寫「能不能刪」的判定**,再寫「若不能刪,如何收深」)
- **效益** — 用 locality / leverage 講,測試會怎麼變好
- **before / after** — 並排小圖示出「淺」與「加深」(或「刪除」)
- **建議強度** — `強` / `值得探` / `臆測` 徽章
- **deletion test 結論** — 收斂 / 搬家

報告結尾一段 **Top 建議**:先做哪個、為什麼。ADR 衝突只在摩擦大到值得重開 ADR 時才提,並在卡上標明。

**先不提具體介面設計。** 報告寫完問 user:「想深挖哪一個?」

### 3. grill 深挖迴圈
user 選一個候選後,用 `grill-me`(或牽涉領域模型 / 術語就用 `grill-with-docs`)走決策樹:約束、相依、加深後模組的形狀、seam 後面藏什麼、哪些測試存活。決策定案就即時落文件(術語 → 領域 SSOT;難逆轉+反直覺+真取捨的決策 → 設計文件目錄的 ADR),對齊 `grill-with-docs` 的建模紀律。

## 收尾
選定的加深(或刪除)交給 GSD Plan → 走 feature-pipeline 實作。本 skill 本身不改 code。
