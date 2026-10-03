---
name: writing-great-skills
description: 寫 / 改一支 skill 的品質裁量原則——讓 skill 可預測的詞彙與槓桿。skillopt 每輪產 skill diff 時的 reference。觸發詞:「寫 skill」「改 skill」「這 skill 怎麼寫」「skill 品質」「該不該拆 skill」「skill 太長」「觸發詞蔓生」「writing great skills」。
---

# writing-great-skills — 寫好一支 skill 的原則

改造自 mattpocock/skills 的 `writing-great-skills`(MIT license),原文 GLOSSARY 術語已內聯於本檔,完整原文詞彙表 verbatim 放同目錄 `GLOSSARY.md`(深查才讀)。這是**參考型 skill**(全 reference,不是步驟),給 `skillopt` 每輪蒸餾 / 產 skill diff 時當品質裁量標準。

一支 skill 存在,是為了從隨機系統裡擰出**確定性**。**可預測性(predictability)**——agent 每次跑走**同一套流程**(不是產出同一份輸出)——是根本美德;下面每根槓桿都服務它。

## 呼叫方式(invocation):兩種,付不同的成本

- **model-invoked(模型可自行呼叫)**:保留 description,agent 能自主觸發、別的 skill 也搆得到(你仍可打名字)。代價=**context load**:description 每一回合都待在視窗裡。作法:不設 `disable-model-invocation`,寫面向模型、觸發詞豐富的 description。
- **user-invoked(只使用者呼叫)**:把 description 從 agent 搆得到的範圍拿掉,只有你打名字能叫、別的 skill 搆不到。零 context load,但花**cognitive load**:**你**變成那個要記得它存在的索引。作法:`disable-model-invocation: true`,description 變成給人看的一行摘要、拿掉觸發詞。

只在「agent 必須自己搆到、或別的 skill 必須搆到」時選 model-invocation。純手動觸發的就設 user-invoked,不付 context load。當 user-invoked skill 多到你記不住,那堆積的 cognitive load 用一支 **router skill** 解:一支 user-invoked skill 點名其他支 + 何時用哪支(專案 CLAUDE.md 的按需讀取路由表就扮此角色)。

## 寫 description

model-invoked 的 description 做兩件事:講這 skill 是什麼、列該觸發它的**分支(branch)**。每個字都加 context load,所以 description 比 body 更該狠刪:

- **把 skill 的 leading word 放最前面**——description 就是它做觸發工作的地方。
- **一個分支一個觸發詞**。同義詞把單一分支重講=**duplication**(重複)。收斂成一個,只留真正不同的分支。
- **砍掉 body 已有的身分敘述**。description 只留觸發詞 + 「別的 skill 需要它時」的搆入子句。

## 資訊階梯(information hierarchy)

skill 由兩種內容組成——**步驟(steps)**與**參考(reference)**——可自由混。核心決定是各放在階梯的哪一階(按 agent 多急著要它排序):

1. **skill 內步驟**:SKILL.md 裡有序的動作,主層。每步以**完成判準(completion criterion)**收尾——告訴 agent「做完了」的條件。要**可檢查**(agent 分得出做完 vs 沒做完)、必要處要**窮盡**(「每個改到的 model 都交代」而非「產一份變更清單」)。判準含糊 → 招來 **premature completion(提早收工)**。
2. **skill 內參考**:SKILL.md 裡按需查的定義 / 規則 / 事實。常是合理的平面 peer-set(一個 review 的每條規則同一階)——正常安排,不是壞味道。
3. **外部參考**:推出 SKILL.md 到另一個檔,用**context pointer(情境指標)**搆,指標觸發才載入。

苛刻的完成判準逼出扎實的 **legwork(現場功夫)**——不管有沒有步驟,「每條規則都套」綁平面參考,就跟「每步都做」綁序列一樣。往下推太少 → 頂層腫;推太多 → 藏了 agent 真正需要的料。這個張力就是整個決定。

**漸進揭露(progressive disclosure)**=沿階梯往下移(從 SKILL.md 移進連結檔),讓頂層保持好讀。判斷法=**分支**:每個分支都要的 inline;只有部分分支搆到的推到 pointer 後面。pointer 的**措辭**(不是它指向誰)決定 agent 何時、多可靠地搆到那份料。階梯決定「往下多遠」,**co-location(同址)**決定「落下去後旁邊擺什麼」:一個概念的定義 / 規則 / 但書擺同一個標題下,別散開。

## 何時拆(when to split)

**granularity(粒度)**=你把 skill 切多細,每切一刀花掉兩種 load 之一,所以只在那刀值得時才切:

- **按呼叫拆**:有一個獨立的 leading word 該自己觸發它、或別的 skill 必須搆到,才拆出一支 model-invoked skill。你為那個永遠載入的 description 付 context load,所以那份獨立搆入得夠值。
- **按序列拆**:當後面還沒做的步驟(post-completion steps)誘使 agent 趕前面那步(premature completion),就把後面的步驟拆出視野外，逼 agent 對當前任務多做 legwork。

## 剪枝(pruning)

- 每個意義留**單一真相源(SSOT)**:一個權威處,改行為是一處編輯。
- 逐行檢查 **relevance(相關性)**:這行還關乎 skill 做的事嗎?
- 再**逐句**(不只逐行)獵 **no-op**:對每句孤立跑 no-op 測試,一句沒過就刪整句,不是修字。狠一點——大多沒過的散文該刪不該重寫。

## leading words(領頭詞)

**leading word** = 一個已住在模型預訓練裡的緊湊概念,agent 跑 skill 時拿它思考(如 _lesson_、_fog of war_、_tracer bullet_、_tight_、_red_)。全文重複(或只需一次),它累積出分散的定義,用最少 token 錨住一整區行為——靠招回模型已有的先驗。它兩頭服務可預測性:body 裡錨**執行**(詞一出現 agent 就伸手拿同一行為)、description 裡錨**觸發**(同一個詞住在你的 prompt / 文件 / code 裡,agent 把共享語言連到這 skill、更可靠地觸發它)。主動找機會用 leading word 重構:三處拼出的 triad(duplication)、description 花一句話比劃一個概念——都在求**收斂**成單一 token。例:「fast, deterministic, low-overhead」→ _tight_;「一個你信得過的迴圈」→ _red_(把模糊 gate 變二元可觀察狀態)。你贏兩次:更少 token + 更利的思考掛鉤。

## 失效模式(用來診斷 skill 的毛病)

- **premature completion(提早收工)**:一步還沒真做完就收,注意力滑向「已經做完」。防禦順序:先磨利完成判準(便宜、局部);只在它不可約地含糊**且**你真觀察到趕工,才用序列拆把 post-completion 步驟藏起來。
- **duplication(重複)**:同一意義出現在多處。花維護 + token,還把該意義在階梯上的顯著度灌到超過真實排名。
- **sediment(沉積)**:陳舊層層堆積,因為加東西感覺安全、刪感覺有風險。沒有剪枝紀律的 skill 的預設命運。
- **sprawl(蔓長)**:skill 純粹太長,即使每行都活且獨特。用階梯治:reference 推到 pointer 後、按分支 / 序列拆,讓每條路徑只帶它需要的。
- **no-op(空操作)**:模型預設就會做的一行,你付 load 說了等於沒說。測試:它有沒有改變「相對於預設」的行為?弱 leading word(agent 本就大致 thorough 卻寫 _be thorough_)就是 no-op;修法是更強的詞(_relentless_),不是換技巧。
- **negation(否定式)**:用禁令操控會反效果——「別想大象」點名了大象、讓它更浮現。改**正面 prompt**:講出目標行為,讓被禁的那個從沒被說出口;只在無法正面表述的硬 guardrail 才保留禁令,且仍配上「該做什麼」。

## 給 skillopt 的一句話
每輪蒸餾 violation 成 skill / 改 skill 前,拿這份對照:新規則是 no-op 嗎?是 negation(該翻正面)嗎?description 觸發詞蔓生了嗎?該拆兩支還是同址?有沒有 leading word 能把一段 restatement 收成一個 token?
