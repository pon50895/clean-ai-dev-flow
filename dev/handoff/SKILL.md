---
name: handoff
description: 結束 session / 換手 / context 即將滿時,寫一份「上段交付 + 下段接手」的雙文件:`SESSION_HANDOFF_<YYYY-MM-DD>-PART<N>.md`(交付清單)+ `STARTUP_PROMPT_<YYYY-MM-DD>-PART<N+1>.md`(下段接手 prompt)。確保下個 session 不用從零拼湊狀態。觸發詞:「handoff」/「換手」/「交接」/「幫我寫交接文件」/「記錄目前進度給下一段」/「先停了,把現在狀態存下來」/「capture where we are for next time」/「session 收尾」。使用者要「暫停並保存目前進度、讓下一段接得上」時就觸發,即使沒明講 handoff。
---

# Handoff Skill

替 supervisor / solo dev 在 session 邊界寫一致的、可被下一段直接吃進 bootstrap 的雙文件。

## 硬上限(MANDATORY — 生成時強制,不靠記憶)

- **SESSION_HANDOFF ≤ 80 行;STARTUP_PROMPT = 約 100 字的一段話。** 短而有效 > 長而完整(長文檔下段讀不完反而 drift,交接文件要精簡且有效)。
- 「有效」的定義: 砍掉某行下段會做錯事才留;不會就砍。細節一律指向 PR 號 / spec 路徑。
- **寫完每份必跑 `wc -l <檔>` 自檢**。超標 → **必須砍**:細節推回 PR / 既有 spec 連結,不在 handoff 複述;同類項合併成一行;刪掉「為完整而完整」的段落。砍到過線才可 commit。
- **若專案有「違規 / 教訓帳」(例如 `violations.jsonl`),入帳是 commit 前的硬條件。**
  每次犯錯當下入一行(30 秒),「改規則 / 加 gate」留給週期檢討依復發數據決定,不在事故當晚加碼。
  handoff 的必填欄是這條的兜底:寫 handoff 時發現沒入帳,現在補。專案沒有這本帳就略過此條。
- 寧可少寫、指向 PR 號 / spec 路徑,也不要長。下段助理會自己 `Read` 那些來源。

## 何時用

- Context 用到 70%+,準備換手
- 完成一個大型 wave / phase,告一段落
- 用戶說「handoff」/「換手」/「交接」/「session 收尾」/「準備換手」
- 完成所有 in-flight 工作,需要記錄狀態給未來

## 何時不用

- 對話 < 30 turn 且都沒 ship 任何 PR
- 純資訊性 Q&A(沒動 code,沒開 PR)
- 用戶只說「總結」/「summary」(那是 quick recap,不是 handoff)

## 兩個產出檔的固定位置(一律落主樹,不管在哪個 worktree 跑)

**下段 session 從主樹(primary working tree)開機(cwd)。** 每個 worktree 各有一份 `.planning/` 副本,若 handoff 寫進當下 worktree,下段開機找不到 —— 交接鏈就斷(實際踩過:handoff 寫在某個 worktree,主樹開機撲空,要人工撈)。**所以先取主樹路徑,兩份檔都寫進主樹的 `.planning/HANDOFF/`。**

```bash
# 主樹 = git worktree list 的第一筆(primary working tree),不寫死路徑
MAIN_WT=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
```

| 檔案 | 路徑 |
|---|---|
| 本段交付 | `$MAIN_WT/.planning/HANDOFF/SESSION_HANDOFF_<YYYY-MM-DD>-PART<N>.md` |
| 下段接手 prompt | `$MAIN_WT/.planning/HANDOFF/STARTUP_PROMPT_<YYYY-MM-DD>-PART<N+1>.md` |

兩份都落主樹後,下段從主樹開機、STARTUP_PROMPT 內的相對引用 `.planning/HANDOFF/...` 自然解得回來,不用改成絕對路徑。

`<N>` = 該日的第幾段(1-based)。先 `ls $MAIN_WT/.planning/HANDOFF/SESSION_HANDOFF_<YYYY-MM-DD>-*` 看當日已有幾段,接下去寫。

## 必跑的探查指令(在開寫前 batch 跑完)

```bash
git fetch origin --prune 2>&1 | tail -3
git log origin/main --oneline -20
gh pr list --state open --json number,title,headRefName,mergeable
gh pr list --state merged --limit 30 --json number,title,mergedAt,headRefName  # 過去 24h 哪些 merge 了
cat .planning/audit/lint-baseline.json 2>/dev/null
cat .planning/audit/tsc-baseline.json 2>/dev/null
docker ps --format "table {{.Names}}\t{{.Status}}"
git status --short
# 活著的 subagent 盤點(subagent 會撐過 /clear,別憑記憶說「都終止了」):
git worktree list                                    # 有 WIP 的 agent worktree = 可能有 agent 還在跑
ps aux | grep -iE 'claude' | grep -v grep            # 本 repo cwd 的 claude 程序數 vs 你以為的 session 數
```

從輸出構建這段的 reality(別憑記憶):
- merged PRs(這段 user 直接 merge 的)
- RTM 等 merge 的 PRs(我開的但 user 還沒 merge)
- **還在跑的 background agent(逐個記名 + 其 worktree)** —— 見下「活著的 subagent」硬規則
- 環境(docker stack 起來嗎、有 uncommitted 嗎)
- baseline 數字(lint / tsc / coverage 變化)

## SESSION_HANDOFF 結構(8 個固定 section)

```markdown
# SESSION HANDOFF — YYYY-MM-DD PART<N>

> 一段話總結這段做了什麼、現在狀態。

## 本段交付(merged)

表格 / 清單:`#<PR>` 標題 + 一行說明 + 重點 metric(行數 / coverage / hits)。
分群:大方向 → 細項。

## RTM 等 user merge

| PR | 主題 | 重點 / 風險 |
|---|---|---|

## 在跑中(in-flight)

- BG bash:`<task-id>`,做什麼,預期多久,完成 trigger 什麼
- BG agent:**`<agent-name>`(逐個記名,不只寫「一個 agent」)**,做什麼,在哪個 worktree
- BG workflow:`<wf-id>`,做什麼

> **活著的 subagent**:subagent 會撐過 `/clear`,換手不等於終止;重派會讓兩個 agent 撞同一個 worktree。所以:
> 1. 寫 handoff 時逐個記 agent 名 + worktree(例:「`token-lead2` 在 `wt-tok-b4` 跑 B4」,不寫「有一個 agent 在跑 B4」)。
> 2. STARTUP_PROMPT 寫「接手先確認 `<agent-name>` 是否還活著(worktree 有沒有新 commit、`ps` 有沒有多的 claude 程序);活著就接手它的回報、不重派,確認死了才重起」,不寫「若它終止 → 重起」。

## Baseline 數字(本段量得 / 變化)

- Coverage:`client X% / server Y% / e2e Z`
- Lint:`<workspace> err/warn(降幅)`
- Tsc:`<workspace> errors(降幅)`
- Emoji-scan:`hits(降幅)`
- Bundle:`<指標>(變化)`

## 紀律與補課(本段確認 / 更新)

- **違規 / 教訓已入帳(專案有這本帳時必填,不可省略)**:本段被 user 糾正的、被推翻的判定、
  踩到的壞 pattern,每個都要有對應 entry,寫進哪本帳照專案 CLAUDE.md 的規定。
  **填「無」必須說明為什麼這段一次都沒錯** —— 通常真相是沒入帳,不是沒犯。
- 本段 user 提的新規則
- 本段踩到的雷 + 對應對策(寫進 memory 或紀律)
- 本段觸發的舊紀律(per memory)而留下的 friction

## 待辦(下段優先序)

### 立即
1. **<事件>** — 為什麼 / 怎麼動 / 預估
2. ...

### 中期
- ...

### 用戶端動作(只能 user 做)
- 例:GitHub Settings → Branches → main → required checks
- 例:申請 Sentry DSN
- 例:6/1 enable disabled workflows

## 環境/狀態快照

- main:`<sha>`(`#<PR>` 後)
- container 狀態
- 未提交 / 散落檔案

## Memory 重點(本段更新)

- `<memory-name>` — 改了什麼

*Last revised: YYYY-MM-DD PART<N> close — <一行 summary>。*
```

## STARTUP_PROMPT 結構(**極簡 — 細節留在 HANDOFF doc**)

核心原則:**不要重複 HANDOFF doc 裡的內容**。下段助理會 `Read` HANDOFF。startup prompt 只給:
- 怎麼 bootstrap
- 一個 sync 指令塊
- 1-3 行最緊急優先序(指向 HANDOFF §待辦看細節)
- BG task 接手 path

範本(**約 100 字一段話**,不要用多行範本):

> 接手本專案 **team lead**。**必讀兩份、缺一不可:本 STARTUP_PROMPT + `.planning/HANDOFF/SESSION_HANDOFF_<DATE>-PART<N>.md` 全文,兩份都讀完才動手(只讀 STARTUP 會漏東漏西)。** 跑專案 CLAUDE.md 的啟動程序,git pull + 環境健檢。最優先:<1-2 件,各幾個字>。**team lead 模式:用 `feature-pipeline` skill 自主驅動,in-scope 工作自決不問執行順序(scope-expanding 才問);派 dev/verify subagent 分工,自己收結論。** **user 沒指定做什麼 = 直接從 HANDOFF §待辦「立即」第一條開工,不要問他要做哪件。** 讀完報「已讀,接手」,同一則訊息就開始做第一條。

**這段範本裡的三句是強制的,寫 STARTUP_PROMPT 時必須原樣帶上**:
0. 「**必讀兩份、缺一不可:本 STARTUP + SESSION_HANDOFF 全文,兩份都讀完才動手**」(只讀 STARTUP 會漏東漏西)
1. 「in-scope 工作自決不問執行順序」
2. 「user 沒指定 = 直接從 §待辦『立即』第一條開工,不要問」

**禁止**把開場寫成「最優先看 user 要什麼」/「若他沒指定,依序」—— 那是在邀請下段助理問,下段就會問(實際發生過:範本沒這句,生成的 prompt 自己長出來,接手助理照著問了)。紀律寫在旁註 = 沒落地;要進**被複製的那段字**。

**team lead 模式**:接手者是 team lead 不是單兵 solo dev — 預設用 `feature-pipeline` skill(若已安裝)把 feature 推到 PR,in-scope 決策自決,不逐步問「先做哪條」;只有 scope-expanding 或商業/戰略取捨才回問 user。派工 + fresh-context 驗證 + RTM 開 PR,主對話只收結論。

寫的時候自我檢查:
- 整段是不是約 100 字一段話?如果不是,把細節推回 HANDOFF。
- 有沒有 1:1 重複 HANDOFF 內容?有就刪。
- 接手第一步指令塊夠不夠?(sync + 看 PR + 健康檢查 + BG tail = 4-5 行 bash)

## 寫作紀律

- 整份文件不用 emoji(若專案有此紅線)。
- **不重複** CLAUDE.md / 專案規範文件已有的內容 — 那些下段會自己載入。
- **只記「session-specific reality」**:這段做了什麼、現在狀態、為什麼這樣做、下段該怎麼接。
- **每個 RTM 的 PR 都標 PR 編號 + 風險點**(尤其是 force-push、含 baseline 變更、跨 workspace 改動)。
- **時序明確**:用 commit SHA / PR 號 / 時間戳,不要寫「最近」「之前」這種模糊詞。
- **PR body 引用方式**:`#1074` 而非 「the vite fix」。
- **TaskList 完成後清空**(handoff 完不留 stale tasks)。

## 收尾 housekeeping(寫 handoff 前先做，這是本 session 的責任，不留給下段/user）

0. **清背景進程(TaskStop 不夠)**：`TaskStop` 只停 task 追蹤,底層 dev server 子進程(`npm run dev` / `vite` 等)會變孤兒繼續跑(佔 port、跨 session 累積)。收尾必用 `ps aux | grep -iE 'npm run dev|vite' | grep -v grep` 實查殘留,**別憑 TaskStop 就寫「dev 環境全停」(是假的,handoff 會失真)**。有殘留 → **先一句話預告 user「要 kill 這些 dev server,可能跳一次權限提示」**,再依 `lsof -ti :<port>` 找到的 PID 清掉。確認 `ps` 殘留 0 才算收尾完。
1. **回收 merged worktree**：用 `reap-worktrees` skill(先 dry-run,確認清單只含 PR 已 merged 的殘留,再由 user 決定 `--apply`)。只清 merged；有 WIP / open PR / 主樹一律跳過。**別排成無人值守 cron**（會誤刪別 session WIP）——每次收尾自己跑。
2. **暫存檔歸位**：所有臨時/preview/一次性測試檔（vite preview `.tsx/.html`、截圖、腳本）只放 **gitignored 位置**（專案指定的暫存目錄或 scratchpad）。**絕不散落在原始碼樹再逐個 `rm`**（`rm` 通常是 user 地盤，且會觸發權限提示）。移進去是本 session 的責任。
3. **本地分支修剪**：squash-merge 後 branch SHA 不在 main，`git branch -d` 判「未 merged」拒刪 → 累積幾百個。週期清「本地 ∩ `gh pr list --state merged`」的分支(內容確定在 main)：
   `comm -12 <(git branch --format='%(refname:short)'|sort) <(gh pr list --state merged --limit 2000 --json headRefName -q '.[].headRefName'|sort) | xargs git branch -D`(BSD xargs 用 stdin 重導，非 `-a`)。只刪 merged;`git branch -D` 可能觸發一次權限提示(可接受)。
4. **git 樹乾淨確認**：`git status --short` 不該有 stray untracked 的 `xxx.tsx` 測試遺留 / preview 檔;有就是沒歸位(見 2)。
5. **TaskList 清空**（見下）。
6. **MEMORY.md 大小檢查**：`wc -c "$MEMORY_MD_PATH"`（`~/.claude/projects/<project>/memory/MEMORY.md`）；>20KB（逼近 24.4KB 讀取上限）→ 先跑 `memory-curate` skill(若已安裝)壓縮，別把臃腫索引留給下段。

## 寫完後(預設:handoff 直接 commit + push 進 main,不走 PR;專案不允許就改走 PR)

**先看專案開關**:`jq -r '.handoff.commit // true' "$MAIN_WT/kit.json"`(或 `.claude/kit.json`)。
- `false`(專案 `.gitignore` 刻意不收交接文件,例:去識別化)→ **只寫主樹 `.planning/HANDOFF/` 本機檔,不 `git add -f` / commit / push**;landed 檢查改為 `test -f` 兩檔都在主樹。下段從主樹開機照樣讀得到。不可用 `-f` 繞 gitignore。
- `true` 或未設 → 照下面流程 commit + push。

**handoff 是 docs 不是 code,預設直接 commit + push 進 `main`,不開 PR。** 若專案禁止直接動 main(branch protection / hook),handoff 檔改走專案的一般 PR 流程,並先問 user。
**沒 push = 只是某 worktree 的未追蹤檔,會擱淺** —— 實際踩過:擱在某個 worktree,主樹開機撈不到,下段被誤導。
push 進 git 後 `git show origin/main:.planning/HANDOFF/...` 隨時撈得回。

在主樹(`$MAIN_WT`)收尾,一次同步 + 提交 + 更新到當前:

```bash
cd "$MAIN_WT"
git pull --ff-only origin main            # 主樹更新到當前資料(不再凍;有本機 WIP 擋 ff 就先問 user 怎麼處理,別強推)
git add "$MAIN_WT/.planning/HANDOFF/SESSION_HANDOFF_<DATE>-PART<N>.md" \
        "$MAIN_WT/.planning/HANDOFF/STARTUP_PROMPT_<DATE>-PART<N+1>.md"
# 若專案的 hook 對 main 直接 commit/push 有閘,只用該專案文件明載給 handoff 的正規 escape(例如環境變數);
# 沒有明載就停手問 user,不繞 hook、不用 --no-verify。
# commit 用 `-- <pathspec>` 只提交 handoff 兩檔,避免把其他 staged(如 guard WIP)一起帶進 main。
git commit -m "docs(handoff): SESSION_HANDOFF + STARTUP_PROMPT for <DATE> PART<N>" \
        -- "$MAIN_WT/.planning/HANDOFF/SESSION_HANDOFF_<DATE>-PART<N>.md" \
           "$MAIN_WT/.planning/HANDOFF/STARTUP_PROMPT_<DATE>-PART<N+1>.md"
git push origin main    # 直接進 main,不開 PR
```

**確認真的 landed(務必,不可略)**:

```bash
git cat-file -e origin/main:.planning/HANDOFF/STARTUP_PROMPT_<DATE>-PART<N+1>.md \
  && echo "landed" || echo "FAILED — 沒進 git,重推"
git -C "$MAIN_WT" pull --ff-only origin main   # 主樹再 pull 一次,確認停在當前資料
```

沒印 `landed` 不算 handoff 完成。最後把 startup prompt 路徑回給 user。

(可選)update memory:若本段有任何 回饋級規律(被 user 糾正或定下的紀律),寫進 memory。

## 反例(別這樣做)

- 把整個 session 對話 dump 進 HANDOFF(超長,下段沒人讀完)
- 只列 PR 號不寫風險(下段 merge 完才知道踩到雷)
- 寫「TODO:完善」這種空話(具體到下一步指令)
- 用 emoji 標重點
- 假設下段「應該知道」某事(下段是新對話,什麼都不知道)
- STARTUP_PROMPT 開場寫「最優先看 user 要什麼」/「若他沒指定」—— 下段助理會照著問。待辦序列已經在 HANDOFF 裡了,直接叫他開工。
- STARTUP_PROMPT 寫「(某 BG agent)若換手後終止 → 重起」—— 假設終止,下段照做就在同 worktree 重複派工。改寫「先確認活著否,活著就接手不重派」。

---

*Last revised: 2026-07-18 — 修 handoff 擱淺 bug(handoff 寫在某個 worktree,主樹開機撈不到,下段被誤導讀舊檔)。三處改動:(1) 輸出路徑錨定主樹(`MAIN_WT=$(git worktree list --porcelain \| awk '/^worktree /{print $2; exit}')`,跨 worktree 實測指回主樹);(2)「寫完後」改為 commit + push 直進 main 不走 PR + `git cat-file` 確認 landed(handoff docs 的例外);(3) 收尾在主樹 `git pull --ff-only` 更新到當前。全流程用丟棄 branch 實跑通過。*
