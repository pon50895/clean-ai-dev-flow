# Claude Code Worktree Lifecycle Recipe

完整規範見 `dev-rule/GSD_WORKFLOW.md §4.7`。本檔僅給 AI 在 session 內快查／執行用。

> **路徑慣例**：本檔示範用 `$REPO` 代表你的 main worktree 絕對路徑（例：`~/Desktop/<your-project>`），用 `$WS` 代表 workspace 容器根（例：`~/Desktop/parallel-dev-workspace`）。實際執行時請替換成你的真實路徑。

## 開啟（Spawn）

```bash
# 從最新 main 開分支 + 建 worktree（路徑與分支名對齊）
git -C "$REPO" switch main
git -C "$REPO" pull --rebase
git -C "$REPO" worktree add \
  "$WS/wt-{slug}" -b {type}/{module}-{slug}
```

`{type}` ∈ `feat / fix / chore / refactor / docs / test`。

## 工作（Work）

於該 worktree 路徑下走 GSD 四階段（discuss → plan → execute → verify）。
每次 AI 回覆開頭以 `[CWD: <絕對路徑>]` 標註當前路徑（§4.6 規定）。

## 退場前盤點（**必跑**）

對每一個候選 worktree：

```bash
p=<absolute-worktree-path>
echo "branch: $(git -C "$p" branch --show-current)"
echo "commits ahead of main: $(git -C "$p" rev-list --count main..HEAD)"
echo "real dirty:"
git -C "$p" status --porcelain | grep -v ".husky/_/"
```

## 分類動作

| 盤點結果 | 動作 |
|---|---|
| commits=0, real_dirty=0 | `git worktree remove <path>` |
| commits=0, real_dirty 只是 `.planning/HANDOFF.json` 等 meta | `git worktree remove --force <path>` |
| commits=0, real_dirty 含實質檔案 | **先**：`git -C <path> add ... && git -C <path> -c core.hooksPath=/dev/null commit -m "..."`<br>**再**：`git worktree remove <path>` |
| commits>=1, 已 merged 進 main | `git worktree remove <path>` → `git branch -d <branch>` |
| commits>=1, 未 merged | **禁砍**；先開 PR 或 `git stash` |

## Branch 處置（與 worktree 退場解耦）

- 已 merged → `git branch -d <branch>`
- 未 merged 但放棄 → `git branch -D <branch>`（在 commit / PR 註明放棄理由）
- 未 merged 但延後 → 留 branch、只移 worktree（branch 當作「規劃中」label）

## 紅線（不可違反）

1. 禁止對含未提交實質工作的 worktree `--force` 移除。
2. 禁止砍別的 session 正在用的 worktree（移除前 `git worktree list` 確認）。
3. 禁止在自己當前 cwd 內 `git worktree remove .`，必先 `cd` 到 main worktree。

## 為什麼有這份文件

整理多條平行 worktree 時，曾發現某條 worktree 內藏 100+ 行的未提交研究報告。若直接 `--force` 移除即永久遺失。本 recipe 把「先 commit 再 remove」的順序固定下來，並把 branch 處置與 worktree 退場解耦。
