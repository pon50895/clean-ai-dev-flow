#!/usr/bin/env bash
#
# rotate-coord-inbox.sh — rotate .planning/COORD_INBOX.txt when size > 1MB.
#
# Spec: dev-rule/AUTOMATION_RUNTIME_FILES.md §7.1
#
# Trigger: file size > 1MB → archive with timestamp, reset to empty.
# Designed for daily cron: `0 3 * * * /path/to/rotate-coord-inbox.sh`
#
# Env vars:
#   PROJECT_ROOT       Workspace root (default: $HOME/Desktop/parallel-dev-workspace)
#   INBOX_PATH         Override full INBOX path (rare; default derived from PROJECT_ROOT)
#   ARCHIVE_DIR        Where to put rotated files (default: PROJECT_ROOT/main/.planning/archive)
#   SIZE_THRESHOLD     Bytes; rotate if size >= this (default: 1048576 = 1 MiB)
#   RETENTION_DAYS     Delete archives older than N days (default: 30)
#   DRY_RUN=1          Show what would happen, don't write
#
# Exit codes:
#   0  rotated OR no rotation needed (success)
#   1  config / path error
#   2  could not acquire lock (another rotate already running)

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$HOME/Desktop/parallel-dev-workspace}"
INBOX_PATH="${INBOX_PATH:-$PROJECT_ROOT/worktrees/sentinel-monitor/.planning/COORD_INBOX.txt}"
ARCHIVE_DIR="${ARCHIVE_DIR:-$PROJECT_ROOT/main/.planning/archive}"
LOG_PATH="$PROJECT_ROOT/main/.planning/COORDINATOR_LOG.md"
SIZE_THRESHOLD="${SIZE_THRESHOLD:-1048576}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DRY_RUN="${DRY_RUN:-0}"

LOCK_DIR="/tmp/rotate-coord-inbox.lock.d"

# ----------------------------------------------------------------------------
# 1. Acquire lock (prevent concurrent rotation)
# ----------------------------------------------------------------------------
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  pid_file="$LOCK_DIR/pid"
  if [ -f "$pid_file" ]; then
    old_pid="$(cat "$pid_file" 2>/dev/null || echo "")"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      echo "[rotate-inbox] lock held by pid $old_pid, skipping" >&2
      exit 2
    fi
    # Stale lock — clean up
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
# 2. Pre-flight
# ----------------------------------------------------------------------------
if [ ! -f "$INBOX_PATH" ]; then
  # No inbox = nothing to rotate. Not an error.
  echo "[rotate-inbox] no inbox at $INBOX_PATH (nothing to do)"
  exit 0
fi

mkdir -p "$ARCHIVE_DIR"

# ----------------------------------------------------------------------------
# 3. Check size
# ----------------------------------------------------------------------------
# stat -c works on Linux; stat -f on macOS.
if size=$(stat -f %z "$INBOX_PATH" 2>/dev/null); then
  : # macOS
elif size=$(stat -c %s "$INBOX_PATH" 2>/dev/null); then
  : # Linux
else
  size=$(wc -c < "$INBOX_PATH" | tr -d ' ')
fi

ts="$(date '+%Y-%m-%d %H:%M:%S %Z')"

if [ "$size" -lt "$SIZE_THRESHOLD" ]; then
  echo "[rotate-inbox] size=$size < threshold=$SIZE_THRESHOLD; no rotation"
  # Still run retention cleanup
else
  archive_name="COORD_INBOX-$(date +%Y%m%d-%H%M%S).txt"
  archive_path="$ARCHIVE_DIR/$archive_name"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[rotate-inbox] [DRY] would: mv $INBOX_PATH $archive_path"
    echo "[rotate-inbox] [DRY] would: : > $INBOX_PATH"
  else
    mv "$INBOX_PATH" "$archive_path"
    : > "$INBOX_PATH"
    # Log to COORDINATOR_LOG (best-effort; LOG may not exist on first run)
    if [ -f "$LOG_PATH" ] || mkdir -p "$(dirname "$LOG_PATH")" 2>/dev/null; then
      echo "[$ts] [INBOX rotated] size=${size}B -> $archive_name" >> "$LOG_PATH" || true
    fi
    echo "[rotate-inbox] rotated: size=${size}B -> $archive_name"
  fi
fi

# ----------------------------------------------------------------------------
# 4. Retention cleanup
# ----------------------------------------------------------------------------
if [ "$DRY_RUN" = "1" ]; then
  echo "[rotate-inbox] [DRY] would: find $ARCHIVE_DIR -name 'COORD_INBOX-*.txt' -mtime +$RETENTION_DAYS -print"
  find "$ARCHIVE_DIR" -name 'COORD_INBOX-*.txt' -mtime "+$RETENTION_DAYS" -print 2>/dev/null || true
else
  deleted=$(find "$ARCHIVE_DIR" -name 'COORD_INBOX-*.txt' -mtime "+$RETENTION_DAYS" -print -delete 2>/dev/null | wc -l | tr -d ' ')
  if [ "$deleted" -gt 0 ]; then
    echo "[rotate-inbox] retention: deleted $deleted archives older than ${RETENTION_DAYS}d"
    [ -f "$LOG_PATH" ] && echo "[$ts] [INBOX retention] purged $deleted archives older than ${RETENTION_DAYS}d" >> "$LOG_PATH" || true
  fi
fi

exit 0
