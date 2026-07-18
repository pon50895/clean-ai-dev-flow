#!/usr/bin/env bash
# docker-coord.sh — Docker write-op serializer (R1 scarce resource)
#
# Held by: supervisor / dispatcher / reviewer (NOT workers).
# 5-min stale threshold (docker write ops should be fast).
#
# Locked ops:  docker compose down/up/restart/build, volume rm, network rm,
#              image rm, mutating docker exec (e.g. npm install in container)
# NOT locked:  docker ps, docker images, docker logs, docker stats,
#              docker exec <ro-cmd>, build artifact (read code, write artifact)

set -euo pipefail

ROOT="${ROOT:-$(pwd)}"
LOCK="${DOCKER_LOCK_PATH:-$ROOT/.planning/DOCKER_LOCK.json}"
LOG="${COORD_LOG:-$ROOT/.planning/COORDINATOR_LOG.md}"
STALE_SECS=300

cmd="${1:-}"; shift || true
now_local() { date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\(..\)$/:\1/'; }
log() { mkdir -p "$(dirname "$LOG")"; printf '[%s] [docker-coord] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

[[ -f "$LOCK" ]] || { mkdir -p "$(dirname "$LOCK")"; echo '{}' > "$LOCK"; }

case "$cmd" in
  acquire)
    actor="${1:?actor required (e.g. supervisor / dispatcher / reviewer)}"
    op="${2:?op description required}"
    python3 - "$LOCK" "$actor" "$op" "$STALE_SECS" "$(now_local)" <<'PY'
import json, sys
from datetime import datetime, timezone
path, actor, op, stale, ts = sys.argv[1:]
stale = int(stale)
with open(path) as f:
    data = json.load(f)
held = data.get("holder")
if held:
    hb = data.get("acquired_at")
    try:
        hb_dt = datetime.fromisoformat(hb)
        age = (datetime.now(timezone.utc) - hb_dt.astimezone(timezone.utc)).total_seconds()
    except Exception:
        age = 0
    if held == actor:
        data["acquired_at"] = ts
        data["op"] = op
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
        print(f"REACQUIRED {actor}"); sys.exit(0)
    if age < stale:
        print(f"DENIED held by {held} for {int(age)}s (< {stale}s) op={data.get('op','?')}"); sys.exit(2)
    print(f"STALE {held} {int(age)}s — releasing")
data.update({"holder": actor, "op": op, "acquired_at": ts})
with open(path, "w") as f:
    json.dump(data, f, indent=2)
print(f"ACQUIRED {actor} op={op[:60]}")
PY
    log "acquire $actor op=$op"
    ;;
  release)
    actor="${1:?actor required}"
    python3 - "$LOCK" "$actor" <<'PY'
import json, sys
path, actor = sys.argv[1:]
with open(path) as f:
    data = json.load(f)
if not data.get("holder"):
    print("NO-LOCK"); sys.exit(0)
if data.get("holder") != actor:
    print(f"DENIED held by {data.get('holder')} not {actor}"); sys.exit(2)
with open(path, "w") as f:
    json.dump({}, f, indent=2)
print(f"RELEASED {actor}")
PY
    log "release $actor"
    ;;
  check)
    python3 - "$LOCK" "$STALE_SECS" <<'PY'
import json, sys
from datetime import datetime, timezone
path, stale = sys.argv[1], int(sys.argv[2])
with open(path) as f:
    data = json.load(f)
if not data.get("holder"):
    print("FREE"); sys.exit(0)
hb = data.get("acquired_at")
try:
    hb_dt = datetime.fromisoformat(hb)
    age = int((datetime.now(timezone.utc) - hb_dt.astimezone(timezone.utc)).total_seconds())
except Exception:
    age = -1
mark = " STALE" if age >= 0 and age >= stale else ""
print(f"HELD {data.get('holder')} age={age}s{mark} op={data.get('op','?')[:60]}")
PY
    ;;
  sweep)
    python3 - "$LOCK" "$STALE_SECS" <<'PY'
import json, sys
from datetime import datetime, timezone
path, stale = sys.argv[1], int(sys.argv[2])
with open(path) as f:
    data = json.load(f)
if not data.get("holder"):
    print("FREE no-op"); sys.exit(0)
hb = data.get("acquired_at")
try:
    hb_dt = datetime.fromisoformat(hb)
    age = int((datetime.now(timezone.utc) - hb_dt.astimezone(timezone.utc)).total_seconds())
except Exception:
    age = -1
if age < 0 or age < stale:
    print(f"HELD {data.get('holder')} age={age}s — keep"); sys.exit(0)
print(f"SWEPT {data.get('holder')} age={age}s")
with open(path, "w") as f:
    json.dump({}, f, indent=2)
PY
    log "sweep stale docker lock"
    ;;
  *)
    cat <<USAGE
docker-coord.sh — Docker write-op lock (R1 scarce resource)
  acquire <actor> "<op>"
  release <actor>
  check
  sweep                     # expire stale (>${STALE_SECS}s)

Env: DOCKER_LOCK_PATH (default ./.planning/DOCKER_LOCK.json)
USAGE
    exit 1
    ;;
esac
