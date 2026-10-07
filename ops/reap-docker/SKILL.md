---
name: reap-docker
description: 清理本機 docker 累積的臨時容器、dangling image、懸空匿名 volume。反射性直接給 user 完整可貼上的 command(dry-run 先看判決,--apply 再砍),assistant 只代跑 dry-run 不代砍(docker rm / volume rm 屬高風險)。觸發詞:「清 docker」「docker 太多」「清容器」「回收 docker」「reap docker」「docker 佔空間」「清已停容器」。
---

# reap-docker

本機 docker 要清時,assistant 先代跑 dry-run 把判決表給 user 看,再把 `--apply` 那條完整 command 丟給 user 自己跑。腳本跟著本 skill 走,任何專案都能用,不需要專案內有 scripts。

## 流程

1. assistant 跑 dry-run(唯讀,不動任何東西):

```
bash ~/.claude/skills/reap-docker/reap-docker.sh
```

2. 判決表給 user 看,特別點出「保留」裡的 compose 專案容器與「懸空具名 volume」,讓 user 確認沒有要留的臨時容器被列進可砍。
3. 給 user 這條自己跑:

```
bash ~/.claude/skills/reap-docker/reap-docker.sh --apply
```

額外保留某些容器:`KEEP='l-a-pg l-a-redis' bash ~/.claude/skills/reap-docker/reap-docker.sh --apply`

## 判決規則(user 問才說)

- 容器:running / paused / restarting 留;有 compose project label 的留(專案開發容器停了也可能要 `docker start`);停止未滿 `MIN_AGE_HOURS`(預設 1)的留(別的 session 可能剛停、等下要再起);其餘已停的砍,用 `docker rm -v`,只連帶砍它自己的匿名 volume。
- image:只砍 dangling(`<none>`),有 tag 的不動。
- volume:懸空且名稱是 64 位 hash 的匿名 volume 砍;懸空的具名 volume 只列出、永不自動砍(可能是 DB 資料)。
- build cache:只列大小。

## 不要做

- 不要自己拼 `docker rm` 清單代跑:曾把正在用的容器列進 rm 清單。一律走腳本判決。
- 不要 `docker system prune -a` / `docker volume prune`:會連有 tag 的 image、具名 volume 一起砍。
