#!/usr/bin/env bash
# reap-docker.sh — 分類本機 docker 資源,砍掉「臨時起的、已停的」容器與沒人用的 image / 匿名 volume。
#
# 用法:
#   bash reap-docker.sh                          # dry-run:只列判決表,不動任何東西
#   bash reap-docker.sh --apply                  # 真的砍
#   KEEP='name1 name2' bash reap-docker.sh --apply   # 額外保留這些容器
#   MIN_AGE_HOURS=6 bash reap-docker.sh          # 停止未滿 N 小時的不砍(預設 1)
#
# 判決(fail-closed,不確定一律留):
#   容器  running / paused / restarting  -> 留(正在用)
#         有 compose project label        -> 留(專案開發容器,停了也可能要 docker start)
#         停止未滿 MIN_AGE_HOURS          -> 留(可能是別的 session 剛停、等下要再起)
#         其餘 exited / created / dead    -> 砍,docker rm -v(只連帶砍它的匿名 volume)
#   image dangling(<none>)               -> 砍(docker image prune)
#   volume 懸空且名稱是 64 位 hash(匿名)   -> 砍
#          懸空但有名字(具名)              -> 只列出,永不自動砍(可能是 DB 資料)
#   build cache                           -> 只列大小,要清自己跑 docker builder prune
# 為什麼要人跑:docker rm / volume rm 屬高風險指令,assistant 只代跑 dry-run。

set -u
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
MIN_AGE_HOURS=${MIN_AGE_HOURS:-1}
docker info >/dev/null 2>&1 || { echo "docker daemon 沒在跑"; exit 1; }
now=$(date +%s)

declare -a REAP_C KEEP_C
while IFS='|' read -r name state project; do
  why=""
  if [ -n "${KEEP:-}" ] && printf '%s\n' $KEEP | grep -qxF "$name"; then why="你指定保留"
  elif [ "$state" = running ] || [ "$state" = paused ] || [ "$state" = restarting ]; then why="$state"
  elif [ -n "$project" ]; then why="compose 專案 $project"
  else
    finished=$(docker inspect -f '{{.State.FinishedAt}}' "$name" 2>/dev/null | cut -c1-19)
    ts=$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "$finished" +%s 2>/dev/null || date -u -d "$finished" +%s 2>/dev/null || echo "")
    if [ -n "$ts" ] && [ "$ts" -gt 0 ] && [ $(( (now - ts) / 3600 )) -lt "$MIN_AGE_HOURS" ]; then
      why="停止未滿 ${MIN_AGE_HOURS} 小時"
    fi
  fi
  if [ -n "$why" ]; then KEEP_C+=("KEEP  $name  ($why)"); else REAP_C+=("$name"); fi
done < <(docker ps -a --format '{{.Names}}|{{.State}}|{{.Label "com.docker.compose.project"}}')

images=$(docker images -q -f dangling=true | wc -l | tr -d ' ')
anon_vols=$(docker volume ls -q -f dangling=true | grep -E '^[0-9a-f]{64}$')
named_vols=$(docker volume ls -q -f dangling=true | grep -vE '^[0-9a-f]{64}$')

echo "=== 容器 保留 (${#KEEP_C[@]}) ==="
printf '%s\n' "${KEEP_C[@]}" 2>/dev/null
echo
echo "=== 容器 可砍 (${#REAP_C[@]}) ==="
printf 'REAP  %s\n' "${REAP_C[@]}" 2>/dev/null
echo
echo "=== dangling image 可砍:$images 個"
echo "=== 懸空匿名 volume 可砍:$(printf '%s' "$anon_vols" | grep -c .) 個(砍容器時連帶的不在此數)"
echo "=== 懸空具名 volume(只列,不砍;確定不要自己 docker volume rm):"
printf '%s\n' "$named_vols" | sed '/^$/d; s/^/      /'
echo "=== build cache:$(docker system df --format '{{.Type}} {{.Size}}' | grep -i 'build cache' | cut -d' ' -f3-)(要清自己跑 docker builder prune)"

if [ "$APPLY" = 0 ]; then
  echo
  echo "(dry-run,沒動任何東西。確認無誤後加 --apply 真的砍)"
  exit 0
fi

echo
total=${#REAP_C[@]}; n=0
for c in "${REAP_C[@]}"; do
  n=$((n+1)); printf '[reap %d/%d] %s ... ' "$n" "$total" "$c"
  docker rm -v "$c" >/dev/null 2>&1 && echo ok || echo "skip(已不在 / 狀態變了)"
done
docker image prune -f >/dev/null && echo "dangling image 已清"
for v in $anon_vols; do docker volume rm "$v" >/dev/null 2>&1; done
echo "匿名 volume 已清"
echo
docker system df
