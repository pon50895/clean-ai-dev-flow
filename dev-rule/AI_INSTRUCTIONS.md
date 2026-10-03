# AI 助手執行協定 (AI Execution Protocol)

> **2026-06-11 起不在 bootstrap 載入**(CLAUDE.md §0.1 context diet)。本檔內容
> 已併入 CLAUDE.md:紅線=§1、物理驗證=§3 Verify、臨界壓縮=§4.3、worktree 對齊=§0.1。
> 檔案保留供歷史查閱;更新行為準則一律改 CLAUDE.md,不改本檔。

如果您是新接手的 AI 助手，請在開始工作前強制執行以下步驟：

## 1. 環境同步
0. **Worktree 對齊（接續舊 session 時最優先）**:
   - 執行 `git worktree list` 列出所有平行 worktree。
   - 若先前對話 summary 提到任何「已建立／已修改」的檔案，先 `ls` 對應路徑驗證是否存在於當前 cwd。
   - 若當前 cwd 找不到 summary 標榜的檔案，**禁止**直接判定為「檔案遺失」或「未建立」，必須先到其他 worktree 路徑下 `ls` 確認。
   - 確認後若上一個 session 是在另一個 worktree 作業，必須建議用戶切換 cwd（或主動 `cd`）後再繼續，並在每則回覆開頭標註當前所在路徑。
1. 讀取專案規格文件（路徑見 CLAUDE.md §0.2）了解全局架構。
2. 讀取 `/dev-rule` 目錄下的所有規範。
3. 讀取 `.planning/PROJECT.md` 了解目前進度。

## 2. 執行守則
- **禁止私自腦補**: 條件不足時必須反問。
- **糾錯優先**: 若用戶請求違反本規範（例如要求加入 Emoji），必須主動拒絕並說明原因。
- **物理驗證**: 每個任務完成後，必須自行啟動瀏覽器代理人或測試腳本進行「物理驗證」，不得僅憑「代碼已寫」就宣稱完成。

## 3. 禁忌清單 (Red Lines)
- 嚴禁在未經同意的情況下刪除他人註釋。
- 嚴禁提交編譯不通過的代碼。
- 嚴禁繞過法律合規攔截邏輯。
- 嚴禁使用 Emoji。

## 4. 對話臨界壓縮 (Dialogue Threshold Compression)
- **觸發背景**: 當對話紀錄接近系統 Context Window 限制，或當前任務涉及大量檔案變動、邏輯碎片化時。
- **主動動作**: AI 助手必須主動執行「進度快照 (Progress Snapshot)」，摘要已解決的衝突、已實作的邏輯、未完成的 Bug 以及遺留的待辦事項。
- **開啟新對話提示**: 摘要完成後，必須建議用戶「開啟新的對話 (New Thread)」，並說明這是為了防止對話過長導致最早的上下文或關鍵決策被系統遺忘。
- **交付要求**: 壓縮內容需包含「當前物理路徑 (CWD)」與「變動檔案清單 (Modified Files)」，確保接手助理能快速回復上下文。
- **多 session 執行細則**: 平行開發時不同角色（supervisor / alarm / reviewer / worker）的 handoff 落點與啟動序列見 `dev-rule/WORKFLOW_PROTOCOLS.md` §1。**不要等 auto-compact 自動觸發**；先寫 handoff 文件再讓 user 開新 session。

---
*啟動指令: 「我已閱讀並理解 /dev-rule 中的所有規範，準備開始工作。」*
