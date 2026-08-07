---
name: reap-worktrees
description: 清理累積的 git worktree。反射性直接給 user 完整可貼上的 command(dry-run 先看判決,--apply 再砍),不自己動手跑(bulk worktree remove 會被 destructive-guard 攔、rm 屬 user 地盤)。觸發詞:「清 worktree」「worktree 太多」「回收 worktree」「reap worktree」「砍 worktree」「worktree 清乾淨」。
---

# reap-worktrees

worktree 累積要清時,**反射性直接把下面兩條完整 command 丟給 user**(不解釋一堆、不自己跑)。腳本 `scripts/reap-worktrees.sh` 已在 repo。

## 直接給 user 這兩條

先看判決(dry-run,不動任何東西):

```
bash scripts/reap-worktrees.sh
```

確認判決無誤後真的砍(逐條印進度、可續跑):

```
bash scripts/reap-worktrees.sh --apply
```

額外保留某些 branch:`KEEP='feat/foo feat/bar' bash scripts/reap-worktrees.sh --apply`

## 腳本行為(user 問才說)

- 分類:已 merged / PR 關閉 / squash 被取代 / detached 無獨有 commit → **可砍**;未 merged 真 WIP → **留**。
- fail-closed:分類不確定一律留,main 永不砍。
- **branch ref 一律保留**(worktree remove 只砍工作目錄;已 commit 的不會丟,只有未提交改動會隨 --force 消失)。
- `--apply` 每砍一條印 `[reap n/total]` + ok/skip,最後印剩餘數;砍一半 timeout 再跑一次會跳過已砍的。

## 為什麼給 command 而非自己跑

assistant 的 bulk `git worktree remove --force` 會被 destructive-guard / auto-mode classifier 攔,且 rm 屬 user 地盤。這支 skill 的職責就是**把正確的完整 command 一次給對**,省去每次現拼一長串路徑(還會 2m timeout、無進度)。dry-run 的判決 assistant 可代跑(唯讀),砍由 user 跑。
