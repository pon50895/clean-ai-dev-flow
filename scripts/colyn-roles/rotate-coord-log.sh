#!/usr/bin/env bash
#
# rotate-coord-log.sh — daily roll of .planning/COORDINATOR_LOG.md + 7-day retention.
#
# Spec: dev-rule/AUTOMATION_RUNTIME_FILES.md §7.2
#
# Action:
#   1. Move current LOG to archive with yesterday's date
#   2. Start a fresh LOG with today's header
#   3. Delete LOG archives older than 7 days
#
# Designed for daily cron at midnight: `0 0 * * * /path/to/rotate-coord-log.sh`
#
# Env vars:
#   PROJECT_ROOT       Workspace root (default: $HOME/Desktop/parallel-dev-workspace)
#   LOG_PATH           Override full LOG path (default: PROJECT_ROOT/main/.planning/COORDINATOR_LOG.md)
#   ARCHIVE_DIR        Where to put rotated files (default: PROJECT_ROOT/main/.planning/archive)
#   RETENTION_DAYS     Delete archives older than N days (default: 7)
#   DRY_RUN=1          Show what would happen, don't write
#
# Exit codes:
#   0  rotated OR no rotation needed (success)
#   1  config / path error
#   2  could not acquire lock (another rotate already running)

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$HOME/Desktop/parallel-dev-workspace}"
LOG_PATH="${LOG_PATH:-$PROJECT_ROOT/main/.planning/COORDINATOR_LOG.md}"
ARCHIVE_DIR="${ARCHIVE_DIR:-$PROJECT_ROOT/main/.planning/archive}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
DRY_RUN="${DRY_RUN:-0}"

LOCK_DIR="/tmp/rotate-coord-log.lock.d"

# ----------------------------------------------------------------------------
# 1. Acquire lock
# ----------------------------------------------------------------------------
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  pid_file="$LOCK_DIR/pid"
  if [ -f "$pid_file" ]; then
    old_pid="$(cat "$pid_file" 2>/dev/null || echo "")"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      echo "[rotate-log] lock held by pid $old_pid, skipping" >&2
      exit 2
    fi
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR"
  else
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR"
  fi
fi
echo "$$" > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT

# ----------------------------------------------------------------------------
# 2. Cross-platform yesterday date helper
# ----------------------------------------------------------------------------
yesterday_date() {
  if date -v-1d +%Y%m%d >/dev/null 2>&1; then
    # macOS / BSD
    date -v-1d +%Y%m%d
  else
    # GNU / Linux
    date -d 'yesterday' +%Y%m%d
  fi
}

# ----------------------------------------------------------------------------
# 3. Roll current LOG
# ----------------------------------------------------------------------------
mkdir -p "$ARCHIVE_DIR"
mkdir -p "$(dirname "$LOG_PATH")"

today="$(date +%Y-%m-%d)"

if [ -f "$LOG_PATH" ]; then
  yest="$(yesterday_date)"
  archive_name="COORDINATOR_LOG-${yest}.md"
  archive_path="$ARCHIVE_DIR/$archive_name"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[rotate-log] [DRY] would: mv $LOG_PATH $archive_path"
    echo "[rotate-log] [DRY] would: write fresh header to $LOG_PATH"
  else
    # If yesterday's archive already exists (script ran twice on same day), append.
    if [ -f "$archive_path" ]; then
      cat "$LOG_PATH" >> "$archive_path"
      : > "$LOG_PATH"
    else
      mv "$LOG_PATH" "$archive_path"
    fi
    echo "# COORDINATOR LOG — $today" > "$LOG_PATH"
    echo "" >> "$LOG_PATH"
    echo "[rotate-log] rolled: $LOG_PATH -> $archive_name"
  fi
else
  # No LOG yet; create a fresh one so first writers don't fail
  if [ "$DRY_RUN" = "1" ]; then
    echo "[rotate-log] [DRY] would: create fresh $LOG_PATH (no prior log)"
  else
    echo "# COORDINATOR LOG — $today" > "$LOG_PATH"
    echo "" >> "$LOG_PATH"
    echo "[rotate-log] no prior log; created fresh $LOG_PATH"
  fi
fi

# ----------------------------------------------------------------------------
# 4. Retention cleanup (7-day default)
# ----------------------------------------------------------------------------
if [ "$DRY_RUN" = "1" ]; then
  echo "[rotate-log] [DRY] would: find $ARCHIVE_DIR -name 'COORDINATOR_LOG-*.md' -mtime +$RETENTION_DAYS -print"
  find "$ARCHIVE_DIR" -name 'COORDINATOR_LOG-*.md' -mtime "+$RETENTION_DAYS" -print 2>/dev/null || true
else
  deleted=$(find "$ARCHIVE_DIR" -name 'COORDINATOR_LOG-*.md' -mtime "+$RETENTION_DAYS" -print -delete 2>/dev/null | wc -l | tr -d ' ')
  if [ "$deleted" -gt 0 ]; then
    echo "[rotate-log] retention: deleted $deleted log archives older than ${RETENTION_DAYS}d"
    ts="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "[$ts] [LOG retention] purged $deleted archives older than ${RETENTION_DAYS}d" >> "$LOG_PATH" || true
  fi
fi

exit 0
