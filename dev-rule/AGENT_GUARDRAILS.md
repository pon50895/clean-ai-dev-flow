# Agent Guardrails — 擋 agent 的機制,與適度放寬

> **這份講的不是「有哪些規則」,是「為什麼規則沒用、機制才有用」。**
>
> 來源:一個真實 session 的 14 個失誤 + 三次「檢討 → 寫規則 → 下次照犯」的循環。

---

## 0. 核心結論(先看這段,其他都是註腳)

**寫規則不改變行為。** 三次檢討的實測:

- 第一次檢討提了 5 項改進 → **落地 2 項**,而且**兩項都是機器 gate**(ESLint 規則)
- 另外 3 項是 prose(「brief 要加紀律段」「報告要標記已驗/未驗」「handoff 要填欄位」)
  → **至今沒寫進任何目標檔**,而**系統裡沒有任何東西會發現這件事**
- 兩天後,同一個人漏寫了那條「brief 紀律段」,agent 跑 `rm`,使用者被彈窗

**同一晚的天然對照組**:
- pre-push 的 ponytail 半阻斷(機器)→ **沒被跳過**
- 「UI 改動要視覺驗證」(prose)→ **被跳過**

**判準**:能用機器擋的就不要靠人記得。**沒有 owner 的 prose 會蒸發。**

---

## 1. 為什麼 permissions 不夠,要 hook

`settings.json` 的 `permissions` 是三層 allow / ask / deny,但它**做 substring/glob matching**,
把 chained command 當**一個字串**看:

```bash
cd /tmp && rm -rf ~/important    # permission matcher 看到的是整條,不是中間那個 rm
```

hook 拿到的是完整 command string,可以 regex 全文。**兩者互補,不是二選一。**

同理 `Edit`/`Write` 的 emoji 檢查:permission matcher 看不到檔案**內容**,只看路徑。

---

## 2. 適度放寬:為什麼「全擋」跟「全放」一樣糟

**警報通膨(alarm inflation)是真的**:一個每天彈五次的 gate,人類會學會反射性按 yes ——
然後真正危險的那次也照按。**所以精確度比嚴格度重要。**

本 repo 的四個 exemption,每個都有具體理由:

| Gate | 放寬 | 為什麼 |
|---|---|---|
| `rm` | 只放行**一個** gitignored scratch dir(`AGENT_SCRATCH_DIR`) | 全擋 → agent 每個暫存檔都來要權限 → 人類反射按 yes。全放 → 顯然更糟。只放一個資料夾,路徑外/`..` traversal/shell 花招一律 fall through |
| 並行測試 | 只在**已有實例在跑**時擋 | 單獨跑單檔是正當操作,無差別擋 = 每次跑測試都要吵 |
| `git branch -D` | **建議**只攔 `main/master/develop` | squash-merge 讓 `-d`(安全版)永遠失效 → 刪 merged branch **只能用 -D** → 那是每天的常規操作,不是高危指令。誤刪還有 reflog 90 天 |
| brief guard | 只擋**有寫入意圖**的 agent | 唯讀 agent(Explore/稽核/查證)佔多數,無差別擋純製造摩擦 |

**判準**:問「這個 gate 一週會擋幾次?其中幾次是真的該擋?」比例太低就是在訓練人類忽略它。

---

## 3. deny vs ask:誰看到那個訊息

| verdict | 誰看到 | 用在哪 |
|---|---|---|
| **deny** | **模型**(彈回去讓它自己改寫) | 有正確替代寫法的東西:`\| tail` → 改 `> file`;缺紀律段 → 自己補;並行測試 → 等它跑完 |
| **ask** | **人類**(彈窗) | 真的需要人類判斷的:`rm`、`git reset --hard`、`DROP TABLE`、`sudo` |

**deny 是零摩擦的**。這是本 repo 大多數新 gate 選 deny 的原因 ——
它們擋的不是「危險」,是「**自我欺騙**」,而自我欺騙的解法是「換個寫法」不是「問人類」。

`CLAUDE_ASK_AS_DENY=1`:在無人值守的 pane 裡,ask 會**永遠 hang**(沒有人可以回答)。
該 env 把 ask 降級成 deny,讓自動化流程不卡死。

---

## 4. 陽性對照鐵律(這條最重要)

**任何「不存在 / 沒觸發 / 沒有 X」的斷語,必須先用同一方法驗一個已知存在的 X。**

真實案例(同一個 session 內踩三次):

1. 測 hook 回 `ALLOW` → 宣稱「規則失效」。**實際上是 payload 缺 `tool_name`,hook 提早 exit 0** ——
   測法根本沒碰到規則
2. `$(...)` 捕獲混進 job control 輸出 → JSON parse 炸 → 又一次「規則失效」誤判
3. `grep deploy.sh` 沒找到備份指令 → 宣稱「沒有備份機制」。**實際上備份是另一支 cron 每天在跑**

**三次都是陰性結果,而測法從沒被驗證過能產生陽性結果。** 陰性結果 + 未驗證的方法 = 什麼都不能推論。

所以:`scripts/colyn-roles/hook-selftest.sh` 每次都跑**陽性 + 陰性**兩組。
陽性組沒擋到 → **harness 壞了,不是規則失效**。這個歧義被一次執行消除。

**推廣**:這不只適用 hook。grep 前先 grep 一個已知在檔裡的詞;查 API 前先查一個已知存在的欄位。

---

## 5. 檔案清單

| 檔 | 是什麼 | 觸發 |
|---|---|---|
| `.claude/hooks/bash-destructive-guard.js` | Bash 指令的 deny/ask 判定 | PreToolUse `Bash` |
| `.claude/hooks/agent-brief-guard.js` | 派工 brief 缺紀律段就 deny | PreToolUse `Agent` |
| `.claude/hooks/agent-payload-probe.js` | 一次性探針,記錄 Agent payload 真實形狀 | 需要時才掛 |
| `.claude/hooks/redline-guard.js` | Edit/Write 內容檢查(emoji / main branch commit) | PreToolUse `Edit\|Write\|MultiEdit\|Bash` |
| `scripts/colyn-roles/hook-selftest.sh` | **陽性+陰性對照**。改任何 guard 後必跑 | 手動 |
| `scripts/colyn-roles/session-learning-inject.sh` | SessionStart 注入 violations + 週期過期提醒 | SessionStart |
| `scripts/colyn-roles/briefs/AGENT_BRIEF_DISCIPLINE.md` | 派工紀律段範本(被 brief-guard 逼著複製) | 派 agent 時 |
| `.planning/learning/SCHEMA.md` | violations.jsonl 的 schema | — |

---

## 6. 新專案怎麼裝

1. 複製 `.claude/hooks/`、`scripts/colyn-roles/`(guard 相關)、`.planning/learning/`
2. `settings.json` 掛上(見本 repo 的 `.claude/settings.json` `hooks` 區塊)
3. **改掉專案特定的部分**:
   - `bash-destructive-guard.js` 的 `AGENT_SCRATCH_DIR`(預設 `tmp/agent-scratch/`)—— 要 gitignored,
     而且要有東西定期清它
   - jest 那條規則 → 改成你的測試指令(vitest / pytest / go test),
     **並把你的實際痛點寫進 deny message**(deny message 是知識的最佳落點,不靠誰記得去讀 memory)
   - `AGENT_BRIEF_DISCIPLINE.md` 的 `<PATH>` / `<SCRATCH_DIR>` / 專案紅線
4. **跑 `bash scripts/colyn-roles/hook-selftest.sh`** —— 6/6 綠才算裝好
5. 建 `.planning/learning/violations.jsonl`(空檔即可),SessionStart 注入才有東西可注

---

## 7. 這套東西的失效判據(寫在這裡,讓後人能判)

**不要相信「我覺得有變好」。** 以下三條任一成立 = 這套設計失敗:

1. **`gate-fires.jsonl` 有活動,但 `violations.jsonl` 連續 30 天零新增**
   → producer 邊死了(沒有人在記錄新的失誤),只剩機器在擋舊的
2. **被推翻的判定數週均沒有下降**
   → 「內化了」是假的
3. **改進 ledger 斷更 ≥3 週**
   → 週循環沒在跑,這套變成裝飾

三條都是**檔案裡的數字**,不是感覺。任何人都能查,包括三個月後的你。
