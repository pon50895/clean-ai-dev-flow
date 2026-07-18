---
name: skillopt
description: 每週改進循環(系統心臟)。step 0 = 上輪提案的落地驗收(派 fresh agent 帶 receipts,不自驗)—— 沒有這步,檢討會變成「寫規則→下次照犯」的無限迴圈。接著讀 violations.jsonl + gate-fires.jsonl + 近期 memory feedback,把「復發 >=3 或 user 點名」的行為違規蒸餾成 bounded 強制邊界(優先機器 gate:hook / ESLint / Husky;其次紅線或 skill 條款),每輪上限 3 筆。每個提案是可逆的 add/delete/replace diff,附 before/after + 對應 violation。無自動 scorer,validation gate = user 人工逐筆 accept;結果寫進 IMPROVEMENT_LEDGER.md 供下輪 step 0 驗收。觸發:SessionStart 過期提醒(>7 天)或 user 講「週改進」/「skillopt」/「蒸餾」/「把 violations 變規則」/「改進開發流程」。
---

# Skillopt — In-house 自蒸餾(validation-gated bounded edits)

借 microsoft/SkillOpt 的核心一招:**bounded edits + validation gate**。我們沒有自動
scorer,所以 validation gate = **user 人工 review**。本 skill 只負責「把累積的行為
違規蒸餾成最小、可逆的強制邊界」,不裝任何框架。

## 與 dev-rule-curate 的分工(別重疊)

| skill | 動什麼 | 驅動來源 | 節奏 |
|---|---|---|---|
| `dev-rule-curate` | `dev-rule/*.md`(repo 紀律文件) | dev-rule drift / 引用斷裂 | milestone 後 |
| **skillopt(本)** | **強制層**:`.claude/hooks/*`、CLAUDE.md §1-§2 紅線、`.claude/skills/*`、ESLint/Husky 設定 | **violations.jsonl 重複模式** | 累積 ≥ 3 條同類 violation,或 user 觸發 |

口訣:dev-rule-curate 整理「寫給人讀的紀律」;skillopt 把「重複犯的錯」變成「機器會擋
或讀一次就內化的邊界」。

## 何時用 / 何時不用

用:
- `violations.jsonl` 同 `trigger_kind`(或同 tag)出現 ≥ 3 次,代表光靠文件沒擋住。
- user 說「skillopt」/「蒸餾」/「把這個變規則」。
- 一段 session 反覆被同一件事糾正(即時蒸餾,不必等 3 次)。

不用:
- 單一一次性失誤(YAGNI — 不為一次錯建規則,先 `learning-capture` 記著等它復發)。
- 規則已被現有 hook / ESLint / Husky 擋住(別疊第二道;先確認現有 gate 為何沒觸發)。
- 想加單一 dev-rule 條款 → 直接 Edit dev-rule,不走本 skill。

## 強制邊界的「梯子」(選最高一階能擋住的)

蒸餾的產物**優先級由高到低**——能用機器擋就別只寫一句話拜託 agent 守規矩:

1. **既有 hook 能擴一條 regex 就擋住** → 改 `.claude/hooks/bash-destructive-guard.js`
   的 deny/ask 清單(例:新增危險指令樣式)。一行 diff,最高 ROI。
2. **ESLint / Husky pre-commit 規則** → repo 已有的 lint / scan(emoji-scan、
   regulated-title-scan…)加一條 pattern。
3. **新 hook**(只有當 1/2 都不適用,且行為可由 tool-call payload 判定)。
4. **CLAUDE.md §1 紅線 / §2 高危清單**:無法機器化、但屬「絕對禁止」的行為,加一條
   Rxx 或一個 bullet。**這是 prose,成本最高,只在機器擋不到時用。**
5. **skill 條款 / memory feedback**:情境性紀律(非絕對),補進對應 skill 的反例段
   或 `learning-capture-json.sh` 寫一筆 correction。

> §0 curation 原則:已被機器 gate 強制的規則,不靠重讀文件維持。蒸餾的目標是「往梯子
> 上方移動」——把 prose 規則升級成 gate,而不是再加一段 prose。

## 觸發

**每週一次。** 觸發不靠記得:`session-learning-inject.sh`(SessionStart hook)讀
`.planning/learning/IMPROVEMENT_LEDGER.md` 的最後日期,超過 7 天就在開場印過期提醒。
或 user 直接講「週改進」。

**不排無人值守 cron。** step 4 的 validation gate 需要 user 在場逐筆裁決;
cron 在 user 不在時跑 = 產出一份沒人裁決的報告 = 前三次循環的死法。

---

## 步驟

### 0. 落地驗收(閉環邊 —— 沒有這步,前三次全部失效)

**先做這步,再談新提案。**

上一輪 ledger 裡標 `accepted` 的每一項,**派一個 fresh-context agent** 帶清單去驗:
目標檔裡到底有沒有?要 `檔案:行號` 當 receipt。

```bash
# 上一輪 accepted 的清單
sed -n '/### 提案桌/,/^###/p' .planning/learning/IMPROVEMENT_LEDGER.md
```

**鐵律**:
- **沒有 receipt 的「已落地」視同未落地。**
- **驗的人不是提的人** —— 這條對改進迴圈自身也成立。自驗會漏,實測如此。
- 未落地的項:user 裁決「補落」或「正式放棄」。**放棄也要寫進 ledger**,
  比讓它以殭屍狀態掛在那裡誠實。

**為什麼這步是核心(實測,不是主張)**:某次用 fresh agent 稽核**前一次檢討**的 5 項提案 →
**落地 2/5,而且兩項都是機器 gate**;三項 prose(brief 紀律段 / 報告標記已驗未驗 / handoff 欄位)
**至今沒寫進任何目標檔** —— 而系統裡沒有任何東西會發現這件事。

更痛的:兩個月前的一份 handoff 就診斷過「學習迴圈的 capture 是手動、solo session 沒在用」——
**那個診斷同樣沒有 consumer,同樣蒸發**。

**斷掉的環節從來不是「想不到要改什麼」,是「提案落地與生效沒人驗收」。**
每次事故都能產出正確的診斷;沒有一次有人回頭確認那個診斷有沒有變成 code。

### 1. 收集訊號(read-only)

```bash
# open/active violations(最該處理的)
grep -E '"status": *"(open|active)"' .planning/learning/violations.jsonl 2>/dev/null
# 按 trigger_kind / tag 數重複
grep -oE '"trigger_kind": *"[^"]+"' .planning/learning/violations.jsonl | sort | uniq -c | sort -rn
# 壞 pattern 嘗試數:guard 每次 deny/ask 自動記,這是唯一不能自吹的行為計數器
grep -oE '"why": *"[^"]{0,40}' .planning/learning/gate-fires.jsonl 2>/dev/null | sort | uniq -c | sort -rn
ls -t memory/feedback_*.md 2>/dev/null | head -10
ls -t .planning/HANDOFF/SESSION_HANDOFF_*.md 2>/dev/null | head -2   # 看「紀律與補課」段
# 現有強制層(別重疊)
ls .claude/hooks/; grep -nE 'deny|ask' .claude/hooks/bash-destructive-guard.js | head
grep -rn 'R1\|R2\|R3\|R4\|R5\|R6\|R7\|R8\|R9\|R10\|R11' CLAUDE.md | head
```

### 2. 分群 → 候選

把 violations 按 `trigger_kind` / tag 分群。每群問:
- 復發次數?(< 3 且非 user 點名 → 不動,留紀錄)
- 現有哪道 gate 應該擋住卻沒擋?(先修那道,通常比加新規則對)
- 梯子上能擋住的最高一階是哪階?

### 3. Bounded edit 提案桌(dry-run,先給 user)

每筆提案**必須**是一筆小、可逆的 diff,附下列欄位——這就是 SkillOpt 的 bounded edit:

| # | 對應 violation id | 目標檔 | 梯子階 | before | after | 為什麼這階 |
|---|---|---|---|---|---|---|

規則:
- **一筆提案 = 一個邏輯邊界**。不把五條規則塞一個 diff。
- before/after 用真實片段(不是「大概改成這樣」)。
- 若某 violation 蒸餾不出 bounded edit(太情境、無法一般化)→ 標「不蒸餾,維持
  per-session 紀律」並說明,不硬湊規則。
- **不刪 R1-R11 任一紅線**;只增不刪紅線。改 hook deny 清單只增不減既有項。

### 4. Validation gate(user 人工)

把提案桌貼給 user。**user 逐筆 accept / reject / 改寫**才動手——這是 in-house 唯一的
validation(無自動 scorer)。user 沒點頭的不寫進檔。

### 5. 落地 → 一次 PR

```bash
# 已在 worktree;主樹永遠停 main
# 依 user accept 的提案 Edit 目標檔(hook / CLAUDE.md / skill)
# 改 hook → 一律跑陽性對照,不要只跑「它有沒有擋到」:
bash scripts/colyn-roles/hook-selftest.sh    # 陽性+陰性,exit 0 才算 harness 可信
git add -A && git commit -m "chore(skillopt): distill N violations → M bounded gates"
git push -u origin HEAD && gh pr create --base main --fill
```

碰 CLAUDE.md → PR 標題含 `[CLAUDE.md]`(§ 末規定)。PR body 必含提案桌 + 哪些 user
accept / reject + 對應 violation id,讓 reviewer 一頁看完蒸餾鏈。

### 6. 收口 violations

PR merge 後,把被蒸餾的 violation 用 `learning-capture-json.sh` 或直接 Edit 標
`"status": "resolved"` 並在 `fix_applied` 指向該 PR/hook。蒸餾成功的訊號 = 它不再復發。

**注意**:標 `resolved` 是「已蒸餾成 gate」,**不是「已解決」**。真正的解決訊號是
下輪 step 1 的 `gate-fires.jsonl` 顯示那個 pattern 的嘗試數在降。標了 resolved 但
gate-fires 週週照樣觸發 = 那道 gate 在擋,但行為沒內化 —— 那是資料,不是失敗。

### 7. 寫進 ledger(閉環的另一半 —— 沒寫 = 下輪 step 0 驗無可驗)

`.planning/learning/IMPROVEMENT_LEDGER.md` **最上面**追加一節。**單一滾動檔,不產 dated 報告**
(dated 報告就是前三次蒸發的那種東西)。超過 200 行把最舊的節搬 `.planning/archive/`。

一節含:日期 + 五步各一到三行 + 提案桌(含 user 裁決欄)。

**提案桌的 `狀態` 欄只有三種值**,下輪 step 0 照它驗:
- `accepted` — user 點頭,**下輪必驗 receipt**
- `rejected` — user 否決,寫理由(否決也是資料)
- `superseded` — 被後來的提案取代

### 8. 垃圾 sweep + 成本三指標(附掛在週循環,不另設儀式)

**垃圾**:merged worktree 自清;**非 merged 的、prod 上的垃圾檔 → 列清單給 user**
(rm 是 user 地盤,見既有 memory)。

**成本三指標**(全部進 ledger,三個月後判定系統有效性):

| 指標 | 定義 | 來源 | 性質 |
|---|---|---|---|
| A. 被推翻判定數/週 | 對 user 講的斷語事後被推翻 | violations tag `refuted-verdict` | 半自動(入帳靠規則,最弱一環) |
| B. 壞 pattern 嘗試數/週 | guard deny/ask 觸發,按 why 分組 | `gate-fires.jsonl` | **全自動,不能自吹** |
| C. 重工分鐘/週 | 跑完才發現無效的驗證、重做 | violations 自報欄 | 估計,**明標不當實測用** |

**明確不做**:subagent token 精算(harness 不吐帳單,編數字違反「查證不編造」)。

---

## 寫作紀律

- R1:NO emoji。
- bounded = 小且可逆;改 hook 只增 pattern 不動既有邏輯。
- 機器擋得住就別寫 prose(梯子往上爬,不往下加段落)。
- **不為單次失誤建規則(YAGNI);復發 ≥3 或 user 點名才蒸餾。**
  **前三次循環全部違反了這條** —— 每次事故 → 當晚一份大文檔 → N 個新機制。
  每次犯錯只做「入帳」(一行,30 秒);**加碼集中到週循環,讓復發數據決定,而不是事故當晚的情緒。**
- 不刪紅線、不減既有 deny 清單。
- 提案一律 dry-run 過 user;validation gate 不可跳。
- **改 hook 後一律跑 `hook-selftest.sh`(陽性對照)** —— 只跑「它有沒有擋到」測不出 harness 壞掉。

## 反例

- 把整條 violation summary 複製貼進 CLAUDE.md(那是紀錄不是規則;要蒸餾成可執行邊界)。
- 為一次性失誤加一條紅線(規則膨脹,下個 session 讀更貴)。
- 加第二道 hook 去擋已被現有 hook 擋的事(先查現有 gate 為何沒觸發)。
- 自己 accept 自己的提案就 commit(跳過 user validation gate = 失去 in-house 唯一把關)。
- 一個 PR 動 > 8 筆規則(reviewer 無法逐筆 audit;拆 PR)。
