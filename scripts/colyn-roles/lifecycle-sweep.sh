#!/usr/bin/env bash
# lifecycle-sweep.sh — cron-driven ctx-full handler for ROUTINE roles (no LLM cost)
#
# Routine roles (dispatcher / reviewer / tester) are STATELESS — /clear + re-bootstrap
# is safe (no WIP loss). Workers are NOT handled here (they have WIP, need HANDOFF first).
#
# Usage: bash scripts/colyn-roles/lifecycle-sweep.sh [--dry-run]
#
# Behavior:
#   - For each routine pane, parse ctx % from progress bar
#   - If ctx ≥ 80% → /clear + paste corresponding bootstrap brief
#   - If ctx ≥ 70% → log warning, no action
#   - Log all actions to COORDINATOR_LOG.md

set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
COLYN="$ROOT/scripts/colyn-roles"
LOG="$ROOT/.planning/COORDINATOR_LOG.md"
DRY_RUN="${1:-}"

# Pane → role + bootstrap brief mapping (routine roles only)
# bash 3.x compatible — parallel arrays
PANES=(1 2 8)
BRIEFS=(
  "$COLYN/dispatcher-bootstrap-brief.md"
  "$COLYN/reviewer-bootstrap-brief.md"
  "$COLYN/tester-bootstrap-brief.md"
)

WARN_THRESHOLD=70
FULL_THRESHOLD=80

log() {
  printf '[%s] [lifecycle-sweep] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

action_count=0
warn_count=0
ok_count=0

for i in "${!PANES[@]}"; do
  pane="${PANES[$i]}"
  brief="${BRIEFS[$i]}"
  capture=$(tmux capture-pane -t "main:$pane" -p 2>/dev/null || echo "")
  if [[ -z "$capture" ]]; then
    echo "[main:$pane] DEAD or empty — skipping"
    continue
  fi

  # Parse ctx % from PROGRESS BAR LINE specifically (avoid matching % in dialogs)
  # Look for line containing model+name+progress: e.g. "Sonnet 4.6 │ task-N ████░░░░░░ 42%"
  ctx=$(echo "$capture" | grep -E '(Sonnet|Opus|Haiku)[^|]*│' | grep -oE '[0-9]+%' 2>/dev/null | tail -1 | tr -d '%' || true)
  ctx="${ctx:-0}"

  role=$(basename "$brief" -bootstrap-brief.md | sed 's/.md$//')

  if [[ "$ctx" -ge "$FULL_THRESHOLD" ]]; then
    echo "[main:$pane] $role ctx=${ctx}% FULL — /clear + re-bootstrap"
    if [[ "$DRY_RUN" != "--dry-run" ]]; then
      if [[ ! -f "$brief" ]]; then
        echo "  ERROR: brief missing at $brief — skipping"
        log "FAIL main:$pane brief missing $brief"
        continue
      fi
      tmux send-keys -t "main:$pane" "/clear" Enter
      sleep 3
      tmux load-buffer "$brief"
      tmux paste-buffer -t "main:$pane"
      tmux send-keys -t "main:$pane" Enter
      log "RECYCLED main:$pane $role ctx=${ctx}% → /clear + paste $brief"
      action_count=$((action_count+1))
    fi
  elif [[ "$ctx" -ge "$WARN_THRESHOLD" ]]; then
    echo "[main:$pane] $role ctx=${ctx}% WARN (no action, threshold=${FULL_THRESHOLD}%)"
    log "WARN main:$pane $role ctx=${ctx}%"
    warn_count=$((warn_count+1))
  else
    echo "[main:$pane] $role ctx=${ctx}% OK"
    ok_count=$((ok_count+1))
  fi
done

echo ""
echo "=== summary: actions=$action_count warns=$warn_count ok=$ok_count ==="
[[ "$DRY_RUN" == "--dry-run" ]] && echo "(dry-run mode — no actual /clear performed)"
