# Claude Code Session Bootstrap Checklist

接續舊 session（看到 "This session is being continued..." 摘要）時，**必須**依序執行下列檢查，才能開始任何實質工作。

## Step 0: Worktree 校對（最優先）

```bash
git worktree list
git stash list
```

從上一個 session 的 summary 抽出 3 個「已建立」或「已修改」檔案，於當前 cwd 驗證：

```bash
ls <abs-path-1> <abs-path-2> <abs-path-3>
```

**判斷規則**:

| 情境 | 動作 |
|---|---|
| 檔案都在當前 cwd | 直接接續工作 |
| 檔案都不在當前 cwd，但其他 worktree 路徑下有 | 標註 `[CWD: <other-worktree-path>]`，主動建議用戶切過去；後續工具呼叫一律使用絕對路徑 |
| 所有 worktree 都找不到 | 檢查 `git stash list`、`git reflog`，仍找不到再向用戶確認 |

**禁止**: 未完成上述三步驟前，不得宣稱「檔案遺失」「工作未保存」「需要重做」。

## Step 1: 環境同步

依 `dev-rule/AI_INSTRUCTIONS.md §1` 執行：
- `open-source-spec/OPENSPEC.md`
- `dev-rule/` 全部規範
- `.planning/PROJECT.md`

## Step 2: 任務狀態回填

- 從 summary 的 "Pending Tasks" 區段重建 TodoWrite 清單。
- 在每則回覆開頭以 `[CWD: <絕對路徑>]` 標註當前路徑。

## Step 3: 開工確認

向用戶簡短回報：
1. 當前 cwd 與分支
2. 上一個 session 的最後待辦
3. 是否有 stash／未提交變更
4. 接下來打算做什麼

確認 OK 後再動手。

---

## 為什麼有這份文件

2026-05-04 曾因 session 切換時直接信任 env 預設 cwd，未檢查平行 worktree，誤判 10 個 spec 檔為「遺失」，浪費對話來回排查。本 checklist 為防呆而生。

完整規範見 `dev-rule/GSD_WORKFLOW.md §4.6`。
Worktree 開啟／退場 recipe 見 `.claude/WORKTREE_LIFECYCLE.md`（規範本身在 §4.7）。
