#!/usr/bin/env bash
# skill.sh — Trusted Execution Path entrypoint
#
# Per design: collapse all routine command variants under a single allowlist
# entry "bash skill.sh *". Reduces dialog churn from hundreds of patterns to 1.
#
# 3-tier permission model:
#   LOW   (read-only / test / lint)        → all-allowed verbs
#   MID   (env mutate / install)            → constrained args
#   HIGH  (destructive / push --force / .env) → NOT IN HERE, native dialog
#
# Usage: bash skill.sh <verb> [args...]
#
# Verbs (alphabetical):
#   db-coord <subcmd>         R2 schema lock (acquire/release/check/heartbeat/sweep)
#   docker-coord <subcmd>     R1 docker write-op lock
#   permission-poll           R4 user permission queue poll
#   send-brief <pane> <file>  paste brief into worker pane
#   fleet-status              capture all worker panes (read-only)
#   inbox-tail [n]            tail INBOX
#   inbox-truncate            archive + truncate INBOX (after digest)
#   p0-probe                  curl P0 endpoints (set P0_ENDPOINTS env var)
#   pr-state <pr>             gh pr view summary
#   test unit <workspace>     jest/vitest in workspace
#   test integration <ws>     integration tests
#   test e2e-scoped <spec>    playwright scoped
#   test regression-smoke     playwright cumulative from REGRESSION_REGISTRY
#   test build <workspace>    npm run build
#   sync-settings             symlink .claude/settings.local.json across worktrees
#   git-status                porcelain status (read-only)
#   git-log [n]               oneline log (read-only)

set -euo pipefail

ROOT="${ROOT:-$(pwd)}"
COLYN="$ROOT/scripts/colyn-roles"

verb="${1:-}"
shift || true

case "$verb" in
  db-coord)        bash "$COLYN/db-coord.sh" "$@" ;;
  docker-coord)    bash "$COLYN/docker-coord.sh" "$@" ;;
  permission-poll) bash "$COLYN/permission-queue-poll.sh" ;;

  send-brief)
    pane="${1:?pane-id required}"; file="${2:?brief-file required}"
    bash "$COLYN/send-brief.sh" "$pane" "$file"
    ;;

  inbox-tail)
    n="${1:-15}"
    INBOX="${COORD_INBOX:-$ROOT/.planning/COORD_INBOX.txt}"
    tail -"$n" "$INBOX"
    ;;
  inbox-truncate)
    INBOX="${COORD_INBOX:-$ROOT/.planning/COORD_INBOX.txt}"
    archive="$ROOT/.planning/inbox-archive/$(date +%Y%m%d-%H%M%S).txt"
    mkdir -p "$(dirname "$archive")"
    cp "$INBOX" "$archive"
    : > "$INBOX"
    echo "INBOX archived to $archive and truncated"
    ;;

  fleet-status)
    panes="${FLEET_PANES:-1 2 3 4 5 6 7}"
    for w in $panes; do
      echo "=== main:$w ==="
      tmux capture-pane -t "main:$w" -p 2>&1 | tail -5
      echo ""
    done
    ;;
  p0-probe)
    endpoints="${P0_ENDPOINTS:-/ /api/health}"
    base="${P0_BASE:-http://localhost}"
    for path in $endpoints; do
      code=$(/usr/bin/curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$base$path" 2>/dev/null || echo "ERR")
      echo "$path -> $code"
    done
    ;;
  pr-state)
    pr="${1:?pr number required}"
    gh pr view "$pr" --json number,title,state,isDraft,mergeable,mergeStateStatus \
      --jq '"#\(.number) state=\(.state) draft=\(.isDraft) mergeable=\(.mergeable) mergeStatus=\(.mergeStateStatus) \(.title)"'
    ;;

  test)
    sub="${1:?test subcmd: unit|integration|e2e-scoped|regression-smoke|build}"
    shift
    bash "$COLYN/run-pr-test-suite.sh" "$sub" "$@"
    ;;

  git-status)
    git -C "$ROOT" status --short | head -30
    ;;
  git-log)
    n="${1:-10}"
    git -C "$ROOT" log --oneline -"$n"
    ;;

  sync-settings)
    bash "$COLYN/sync-claude-settings.sh"
    ;;

  ""|help|-h|--help)
    grep -E '^#   [a-z-]+' "$0" | sed 's/^#   /  /'
    ;;
  *)
    echo "ERROR: unknown verb '$verb'"
    echo "Run 'bash skill.sh help' for verbs."
    exit 2
    ;;
esac
