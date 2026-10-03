---
name: product-marketing
description: 建立並維護專案的行銷定位 SSOT 文件(產品定位、受眾、訊息、customer language),讓其他行銷 skill(free-tools-growth / social-media / referral-programs)開工前都先讀它、講一致的話。觸發詞:「行銷定位」「產品定位」「positioning」「我們對誰講什麼」「受眾是誰」「product marketing」「更新定位文件」,或任何行銷 skill 找不到定位 context 時。
---

# product-marketing — 行銷定位 SSOT

改造自 coreyhaines31/marketingskills 的 `product-marketing`(MIT license)。原版建 `.agents/product-marketing.md`;本版改為落地到「當前專案自己的 product-marketing context 文件」,不綁特定產業。

單一職責:產出 / 更新一份**行銷定位 context 文件**,當作所有對外文案的事實來源。其他行銷 skill 不重問定位,一律先讀它。

## 定位文件在哪(由專案決定)

- 主檔:專案自己的 product-marketing context 文件。優先看專案 CLAUDE.md 有沒有指定路徑;沒指定時慣例放 `docs/strategy/PRODUCT_MARKETING_CONTEXT.md`,並先問 user 一次確認。不存在就建 v1。
- 上位依據:若專案另有更上位的敘事 / 漏斗定調文件,定位文件與它衝突時以它為準,並在定位文件註明。
- **北極星指標不寫死在本 skill**:由專案在定位文件第 8、12 節自己定義(例如付費筆數、預約數、啟用數),其他行銷 skill 一律引用該處。

## 何時用

- 要開任何對外文案(landing / 漏斗 / 招募 / hero / 社群 / 更新日誌)前,先確認定位文件在、且沒過期。
- free-tools-growth / social-media / referral-programs 找不到定位 context 時,先跑這支補上。
- 定位有變(受眾、主打功能、免費 / 付費分層)時更新版本。

## 工作流程

1. **先查現有 context**。定位文件若在,讀它 + 最近 changelog,摘要現況,問使用者要更新哪幾節。不存在才走建立流程。
2. **建立 v1**:優先從 repo 現況起草(README、landing page、專案狀態文件、相關 memory),再請使用者逐節校正補缺。不要憑空腦補市場數據。
3. **每次實質更新 bump 版本**(v1 → v2)+ 一行 changelog(最新在上,寫「改了什麼、為什麼」)。錯字修正免 bump。

## 定位文件範本(十二節,欄位留空給專案填)

1. **產品是什麼** — 一句話定義 + 它不是什麼。
2. **目標受眾** — 誰先、誰後;誰是付費方、誰是使用方。
3. **Persona** — 用具體人物,別用「25-40 歲上班族」這種空泛標籤。寫他們實際的煩惱句。
4. **問題 / 痛點** — 他們真的 Google 什麼、卡在哪。用他們的原話。
5. **競品地景** — 誰在做、我們差在哪(護城河是什麼)。
6. **差異化** — 一到三條,每條要能被驗證,不是形容詞。
7. **反受眾 / 常見反對** — 最常被質疑的點與回應;誰不是我們的客。
8. **轉換動態** — 從第一次接觸到付費 / 成交的路徑;**北極星指標在此定義**。
9. **Customer language(最重要)** — 抄客戶原話,別改成漂亮官腔。原話反映他們真的怎麼想。台灣人怎麼講就怎麼記。
10. **品牌語氣** — 台灣式口語、不恐嚇、去 AI 腔(細節見 `de-ai-tone`)。
11. **Proof points** — 只寫**真的發生過**的事實。禁宣稱未實作的驗證 / 審核 / 保證(見下)。
12. **目標** — 當前階段目標與資源限制(例如 pre-revenue 口碑期:單價低 + 轉化,不是規模化廣告)。

## 對外文案共通紅線(寫進文件、也約束所有引用它的 skill;專案可增補)

- **不製造恐懼逼購**:定位語言賦權、不恐嚇。
- **不宣稱未發生的驗證**:沒做過的審核 / 認證 / 保證一律不寫;「入駐」不等於「驗證」。
- **不寫死價錢**:金額以系統為準,文案不 hardcode。
- **供應商保密**(若專案政策如此):對外講產品能力,不點名底層模型 / 供應商。
- **台灣式**:去中國用語、去 AI 腔、去對稱排比空洞金句。

## 收尾

存檔後告知:「定位文件已更新到 vN。其他行銷 skill(free-tools-growth / social-media / referral-programs)會自動引用它。」對外定稿前,文案仍須過 `de-ai-tone`(潤語氣)+ 專案自己的 claim 逐條查證流程(每句斷言對照實際 code / 資料)兩關。
