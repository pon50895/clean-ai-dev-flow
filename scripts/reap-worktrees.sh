#!/usr/bin/env bash
# reap-worktrees.sh — 分類所有 git worktree,砍掉「已 merged / PR 關閉 / squash 被取代 /
# detached 無獨有 commit」的殘留,verbose + 可續跑。branch ref 一律保留(worktree remove
# 只砍工作目錄,已 commit 的東西不會消失;只有未提交改動會隨 --force 消失)。
#
# 用法:
#   bash scripts/reap-worktrees.sh            # dry-run:只列判決表,不動任何東西
#   bash scripts/reap-worktrees.sh --apply    # 真的砍(逐條 print + 更新剩餘數,可重複跑)
#   KEEP='feat/foo feat/bar' bash scripts/reap-worktrees.sh --apply   # 額外保留這些 branch
#   INCLUDE_UNTRACKED=1 bash scripts/reap-worktrees.sh --apply        # 只有未追蹤檔的也砍(檔案會一起消失)
#
# 安全:fail-closed —— 分類不確定一律 KEEP,絕不誤砍。main 永不砍。
#       有已追蹤檔改動的 worktree 一律 KEEP;只有未追蹤檔的預設 KEEP 並列出檔名,
#       INCLUDE_UNTRACKED=1 才砍(--force 會連檔案一起砍掉)。
# 基準:kit.json 的 baseRef(例如 mvp/main),沒有就用 origin/main;prHost=bitbucket 時不查 gh。
# 為什麼要人跑:assistant 的 bulk `worktree remove --force` 會被 destructive-guard 攔,
# 且 rm 屬 user 地盤;這支就是給 user 一鍵跑的 verbose 版。

set -u
cd "$(git rev-parse --show-toplevel)" || exit 1
# 主 worktree = list 的第一筆;在別的 worktree 裡跑時 show-toplevel 不是它
MAIN_WT=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
SELF_WT=$(git rev-parse --show-toplevel)
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
kit() { [ -f kit.json ] && node -e "const k=require('./kit.json');process.stdout.write(k['$1']||'')" 2>/dev/null; }
MAIN=$(kit baseRef); MAIN=${MAIN:-origin/main}
PR_HOST=$(kit prHost); PR_HOST=${PR_HOST:-github}
git fetch -q "${MAIN%%/*}" "${MAIN#*/}" 2>/dev/null
declare -a REAP_PATH REAP_WHY
declare -a KEEP_LINE

# 逐 worktree 分類
while IFS= read -r line; do
  case "$line" in
    worktree\ *) WT=${line#worktree }; BR=""; DET=0 ;;
    branch\ *)   BR=${line#branch refs/heads/} ;;
    detached)    DET=1 ;;
    "")  # 一個 worktree 區塊結束 → 判決
      [ -z "${WT:-}" ] && continue
      # 主 worktree 與正在跑本腳本的 worktree 永不砍
      if [ "$WT" = "$MAIN_WT" ] || [ "$WT" = "$SELF_WT" ]; then WT=""; continue; fi
      # user 指定保留
      if [ -n "${KEEP:-}" ] && [ -n "$BR" ] && printf '%s\n' $KEEP | grep -qxF "$BR"; then
        KEEP_LINE+=("KEEP  $BR  (你指定保留)  $WT"); WT=""; continue
      fi
      verdict=""; why=""
      st=$(git -C "$WT" status --porcelain 2>/dev/null)
      tracked=$(printf '%s\n' "$st" | grep -c '^[^?]')
      untracked=$(printf '%s\n' "$st" | grep '^??' | cut -c4-)
      if [ "$tracked" != 0 ]; then
        verdict=KEEP; why="有 $tracked 個已追蹤檔改動"
      elif [ -n "$untracked" ] && [ "${INCLUDE_UNTRACKED:-0}" != 1 ]; then
        verdict=KEEP; why="只有未追蹤檔:$(printf '%s\n' "$untracked" | head -3 | tr '\n' ' ')(INCLUDE_UNTRACKED=1 才砍)"
      elif [ "$DET" = 1 ]; then
        H=$(git -C "$WT" rev-parse HEAD 2>/dev/null)
        if [ -n "$H" ] && git merge-base --is-ancestor "$H" "$MAIN" 2>/dev/null; then
          verdict=REAP; why="detached 無獨有 commit"
        else verdict=KEEP; why="detached 有獨有 commit"; fi
      elif [ -z "$BR" ]; then
        verdict=KEEP; why="無法判定(無 branch 資訊)"
      elif git merge-base --is-ancestor "$BR" "$MAIN" 2>/dev/null; then
        verdict=REAP; why="已 merged 進 main"
      else
        pr=""
        [ "$PR_HOST" = github ] && pr=$(gh pr list --head "$BR" --state all --json state -q '.[0].state' 2>/dev/null)
        if [ "$pr" = "MERGED" ] || [ "$pr" = "CLOSED" ]; then
          verdict=REAP; why="PR $pr(work 已定案,branch 保留)"
        elif [ -n "$(git rev-list "$BR" 2>/dev/null | head -1)" ] && \
             [ -z "$(git cherry "$MAIN" "$BR" 2>/dev/null | grep '^+')" ]; then
          verdict=REAP; why="squash 被取代(commit patch-equivalent 已在 main)"
        else
          verdict=KEEP; why="未 merged 真 WIP(無對應已關 PR)"
        fi
      fi
      if [ "$verdict" = REAP ]; then REAP_PATH+=("$WT"); REAP_WHY+=("$why")
      else KEEP_LINE+=("KEEP  ${BR:-<detached>}  ($why)  $WT"); fi
      WT="" ;;
  esac
done < <(git worktree list --porcelain; echo "")

echo "=== 保留 (${#KEEP_LINE[@]}) ==="
printf '%s\n' "${KEEP_LINE[@]}" 2>/dev/null
echo
echo "=== 可砍 (${#REAP_PATH[@]}) ==="
for i in "${!REAP_PATH[@]}"; do echo "REAP  ${REAP_WHY[$i]}  ${REAP_PATH[$i]}"; done

if [ "$APPLY" = 0 ]; then
  echo
  echo "(dry-run,沒動任何東西。確認無誤後加 --apply 真的砍)"
  exit 0
fi

echo
total=${#REAP_PATH[@]}; done_n=0
for i in "${!REAP_PATH[@]}"; do
  p="${REAP_PATH[$i]}"; n=$((i+1))
  echo "[reap $n/$total] ${p##*/} ..."
  if git worktree remove --force "$p" 2>/dev/null; then done_n=$((done_n+1)); echo "  ok"
  else echo "  skip(已不在/移除失敗,可再跑一次)"; fi
done
git worktree prune
echo
echo "完成:砍了 $done_n / $total;現存 worktree(含 main):$(git worktree list | wc -l | tr -d ' ')"
