---
name: product-marketing
description: 建立並維護「問問命理平台」的行銷定位 SSOT 文件(產品定位、受眾、訊息、customer language),讓其他行銷 skill(free-tools-growth / social-media / referral-programs)開工前都先讀它、講一致的話。觸發詞:「行銷定位」「產品定位」「positioning」「我們對誰講什麼」「受眾是誰」「product marketing」「更新定位文件」,或任何行銷 skill 找不到定位 context 時。
---

# product-marketing — 行銷定位 SSOT

改造自 coreyhaines31/marketingskills 的 `product-marketing`(MIT license)。原版建 `.agents/product-marketing.md`;本版落地到本專案路徑並綁定命理定位與法遵紅線。

單一職責:產出 / 更新一份**行銷定位 context 文件**,當作所有對外文案的事實來源。其他行銷 skill 不重問定位,一律先讀它。

## 定位文件在哪(本專案 SSOT)

- 主檔:`docs/strategy/PRODUCT_MARKETING_CONTEXT.md`(不存在就建 v1)。
- 上位依據:`docs/strategy/NARRATIVE_PLAYBOOK_FROM_FEEDBACK.md`(漏斗定調 §1.3、匯出政策 §1.2 的 SSOT)。定位文件與 playbook 衝突時,以 playbook 為準,並在定位文件註明。

## 何時用

- 要開任何對外文案(landing / 漏斗 / 招募 / hero / 社群 / 建造日誌)前,先確認定位文件在、且沒過期。
- free-tools-growth / social-media / referral-programs 找不到定位 context 時,先跑這支補上。
- 定位有變(受眾、主打領域、免費/付費分層)時更新版本。

## 工作流程

1. **先查現有 context**。`PRODUCT_MARKETING_CONTEXT.md` 若在,讀它 + 最近 changelog,摘要現況,問使用者要更新哪幾節。不存在才走建立流程。
2. **建立 v1**:優先從 repo 現況起草(README、portal landing、`.planning/PROJECT.md`、`.planning/` 定位相關 memory),再請使用者逐節校正補缺。不要憑空腦補市場數據。
3. **每次實質更新 bump 版本**(v1 → v2)+ 一行 changelog(最新在上,寫「改了什麼、為什麼」)。錯字修正免 bump。

## 定位文件內容(命理版十二節)

1. **產品是什麼** — 問問=命理 AI 品牌(非老師市集、非純工具月費)。八字 / 紫微 / 塔羅 / 占星 / 六爻金錢卦 / 奇門。
2. **目標受眾** — B2C 先行:對命理好奇、想被賦權而非被算命判死的人。老師是次要付費方(為案源付費),不是主打。
3. **Persona** — 用具體人物,別用「25-40 歲上班族」這種空泛標籤。寫他們實際的煩惱句。
4. **問題 / 痛點** — 他們真的 Google 什麼、卡在哪。用他們的原話。
5. **競品地景** — 誰在做、我們差在哪(判斷層 + 辯證層 = 護城河;蒸餾式解讀會磨平)。
6. **差異化** — **命盤=系統規格書非判決書**:命理元素對應軟工概念,吉凶=乘載 / 例外處理,不是判決。
7. **反受眾 / 常見反對** — 「這不就是巴納姆效應?」→ 三層 + archetypes 防空泛。誰不是我們的客(想要鐵口直斷宿命論的人)。
8. **轉換動態** — 從免費工具 → 領報告 → 預約 / 付費解讀的路徑;北極星=歸屬預約。
9. **Customer language(最重要)** — 抄客戶原話,別改成漂亮官腔。原話反映他們真的怎麼想。台灣人怎麼講就怎麼記。
10. **品牌語氣** — 台灣式口語、賦權非恐嚇、去宿命論、去 AI 腔(禁「接住 / 讀懂」)。
11. **Proof points** — 只寫**真的發生過**的事實。禁宣稱未實作的驗證 / 審核 / 保證(法遵紅線,見下)。
12. **目標** — 當前 pre-revenue 口碑期:單價低 + 月上限 + 轉化,不是規模化廣告。

## 命理定位紅線(寫進文件、也約束所有引用它的 skill)

- **賦權非恐嚇、去宿命論**:定位語言不製造恐懼逼購。
- **供應商保密**:對外一律講「AI」,不點名任何模型 / 供應商。
- **不宣稱未發生的驗證**:入駐 ≠ 驗證;沒做過的審核 / 認證 / 保證一律不寫(feedback_no_unverified_verification_claims_in_public_copy)。
- **不寫死價錢**:金額後台動態,文案不 hardcode。
- **台灣式**:去中國用語、去 AI 腔、去對稱排比空洞金句。

## 收尾

存檔後告知:「定位文件已更新到 vN。其他行銷 skill(free-tools-growth / social-media / referral-programs)會自動引用它。」對外定稿前,文案仍須過 `de-ai-tone`(潤語氣)+ `journal-preflight-scan`(claim 逐條查證)兩關。
