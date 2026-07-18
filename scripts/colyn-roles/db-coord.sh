#!/usr/bin/env bash
# db-coord.sh — DB schema lock coordinator (R2 serializer)
#
# Solves: multiple worktrees racing prisma migrate / schema.sql apply.
# 只允許 ONE worktree 同時 hold lock。15-min stale auto-release。
#
# Usage:
#   db-coord.sh acquire <worktree> <branch> <phase> "<purpose>"
#   db-coord.sh release <worktree>
#   db-coord.sh check
#   db-coord.sh heartbeat <worktree>            # refresh while holding (call < 5min)
#   db-coord.sh sweep                            # expire stale (>15min no heartbeat)
#
# State file: $HANDOFF_PATH (db_lock field) — set HANDOFF_PATH env var per project
# Default: ./.planning/HANDOFF.json

set -euo pipefail

ROOT="${ROOT:-$(pwd)}"
HANDOFF="${HANDOFF_PATH:-$ROOT/.planning/HANDOFF.json}"
LOG="${COORD_LOG:-$ROOT/.planning/COORDINATOR_LOG.md}"
STALE_SECS=900

cmd="${1:-}"
shift || true

now_local() { date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\(..\)$/:\1/'; }
log() { mkdir -p "$(dirname "$LOG")"; printf '[%s] [db-coord] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

[[ -f "$HANDOFF" ]] || { mkdir -p "$(dirname "$HANDOFF")"; echo '{}' > "$HANDOFF"; }

case "$cmd" in
  acquire)
    worktree="${1:?worktree required}"
    branch="${2:?branch required}"
    phase="${3:?phase required}"
    purpose="${4:?purpose required}"
    python3 - "$HANDOFF" "$worktree" "$branch" "$phase" "$purpose" "$STALE_SECS" "$(now_local)" <<'PY'
import json, sys
from datetime import datetime, timezone
path, wt, br, ph, pp, stale, ts = sys.argv[1:]
stale = int(stale)
with open(path) as f:
    data = json.load(f)
lock = data.get("db_lock") or {}
if lock and lock.get("worktree"):
    hb = lock.get("heartbeat") or lock.get("acquired_at")
    try:
        hb_dt = datetime.fromisoformat(hb)
        age = (datetime.now(timezone.utc) - hb_dt.astimezone(timezone.utc)).total_seconds()
    except Exception:
        age = 0
    if lock.get("worktree") == wt:
        lock["heartbeat"] = ts
        data["db_lock"] = lock
        with open(path, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"REACQUIRED {wt} (already held); heartbeat refreshed")
        sys.exit(0)
    if age < stale:
        print(f"DENIED held by {lock.get('worktree')} for {int(age)}s (< {stale}s)")
        sys.exit(2)
    print(f"STALE {lock.get('worktree')} {int(age)}s; auto-released")
    data.setdefault("db_lock_history", []).append({**lock, "released_at": ts, "release_reason": "stale-sweep"})
new = {"worktree": wt, "branch": br, "phase": ph, "acquired_at": ts, "heartbeat": ts, "purpose": pp}
data["db_lock"] = new
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(f"ACQUIRED {wt} {br} (phase {ph})")
PY
    log "acquire $worktree $branch phase=$phase"
    ;;
  release)
    worktree="${1:?worktree required}"
    python3 - "$HANDOFF" "$worktree" "$(now_local)" <<'PY'
import json, sys
path, wt, ts = sys.argv[1:]
with open(path) as f:
    data = json.load(f)
lock = data.get("db_lock") or {}
if not lock or not lock.get("worktree"):
    print("NO-LOCK"); sys.exit(0)
if lock.get("worktree") != wt:
    print(f"DENIED held by {lock.get('worktree')} not {wt}"); sys.exit(2)
data.setdefault("db_lock_history", []).append({**lock, "released_at": ts})
data["db_lock"] = {}
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(f"RELEASED {wt}")
PY
    log "release $worktree"
    ;;
  check)
    python3 - "$HANDOFF" "$STALE_SECS" <<'PY'
import json, sys
from datetime import datetime, timezone
path, stale = sys.argv[1], int(sys.argv[2])
with open(path) as f:
    data = json.load(f)
lock = data.get("db_lock") or {}
if not lock or not lock.get("worktree"):
    print("FREE"); sys.exit(0)
hb = lock.get("heartbeat") or lock.get("acquired_at")
try:
    hb_dt = datetime.fromisoformat(hb)
    age = int((datetime.now(timezone.utc) - hb_dt.astimezone(timezone.utc)).total_seconds())
except Exception:
    age = -1
mark = " STALE" if age >= 0 and age >= stale else ""
print(f"HELD {lock.get('worktree')} branch={lock.get('branch')} phase={lock.get('phase')} age={age}s{mark} purpose={lock.get('purpose','')[:60]}")
PY
    ;;
  heartbeat)
    worktree="${1:?worktree required}"
    python3 - "$HANDOFF" "$worktree" "$(now_local)" <<'PY'
import json, sys
path, wt, ts = sys.argv[1:]
with open(path) as f:
    data = json.load(f)
lock = data.get("db_lock") or {}
if not lock or lock.get("worktree") != wt:
    print(f"NOT-HOLDER"); sys.exit(2)
lock["heartbeat"] = ts
data["db_lock"] = lock
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(f"HEARTBEAT {wt}")
PY
    ;;
  sweep)
    python3 - "$HANDOFF" "$STALE_SECS" "$(now_local)" <<'PY'
import json, sys
from datetime import datetime, timezone
path, stale, ts = sys.argv[1], int(sys.argv[2]), sys.argv[3]
with open(path) as f:
    data = json.load(f)
lock = data.get("db_lock") or {}
if not lock or not lock.get("worktree"):
    print("FREE no-op"); sys.exit(0)
hb = lock.get("heartbeat") or lock.get("acquired_at")
try:
    hb_dt = datetime.fromisoformat(hb)
    age = int((datetime.now(timezone.utc) - hb_dt.astimezone(timezone.utc)).total_seconds())
except Exception:
    age = -1
if age < 0 or age < stale:
    print(f"HELD {lock.get('worktree')} age={age}s — keep"); sys.exit(0)
data.setdefault("db_lock_history", []).append({**lock, "released_at": ts, "release_reason": "stale-sweep"})
data["db_lock"] = {}
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(f"SWEPT {lock.get('worktree')} age={age}s")
PY
    log "sweep stale db lock"
    ;;
  *)
    cat <<USAGE
db-coord.sh — DB schema lock coordinator (R2 scarce resource serializer)

Usage:
  db-coord.sh acquire <worktree> <branch> <phase> "<purpose>"
  db-coord.sh release <worktree>
  db-coord.sh check
  db-coord.sh heartbeat <worktree>     # refresh while holding (call <5 min)
  db-coord.sh sweep                     # expire stale (>${STALE_SECS}s)

Env: HANDOFF_PATH (default ./.planning/HANDOFF.json), COORD_LOG, ROOT
USAGE
    exit 1
    ;;
esac
