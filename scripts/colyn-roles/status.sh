#!/usr/bin/env bash
#
# status.sh — One-page dev status for clean-ai-dev-flow.
#
# Prints a single screen covering: git state, open PRs, worktrees, tmux role
# panes, coord inbox depth, recent [DEV-RULE]/[WORKER]/[TESTER] commits.
# Tail includes a Mermaid block you can grep+paste into a handoff doc.
#
# Usage:
#   bash scripts/colyn-roles/status.sh           # full report
#   STATUS_GRAPH=0 bash ...                       # skip Mermaid tail
#   STATUS_LIMIT=5 bash ...                       # change recent-commit count
#
# Intentionally read-only. Safe to run any time.

set -uo pipefail
# NOTE: no -e — we tolerate missing tools / missing dirs and keep printing.

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LIMIT="${STATUS_LIMIT:-3}"
GRAPH="${STATUS_GRAPH:-1}"

bold()    { printf "\033[1m%s\033[0m\n" "$*"; }
dim()     { printf "\033[2m%s\033[0m\n" "$*"; }
section() { echo; bold "═══ $* ═══"; }
kv()      { printf "  %-18s %s\n" "$1" "$2"; }

cd "$ROOT" 2>/dev/null || { echo "[status] cannot cd to repo root"; exit 1; }

# ----------------------------------------------------------------------------
section "GIT"
# ----------------------------------------------------------------------------
branch=$(git branch --show-current 2>/dev/null || echo "(detached)")
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "(no upstream)")
ahead_behind=$(git rev-list --left-right --count "@{u}...HEAD" 2>/dev/null || echo "- -")
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
last_commit=$(git log -1 --pretty='%h %s (%cr)' 2>/dev/null || echo "n/a")

kv "branch"      "$branch"
kv "upstream"    "$upstream"
kv "ahead/behind" "$ahead_behind  (behind ahead)"
kv "dirty files" "$dirty"
kv "last commit" "$last_commit"

# ----------------------------------------------------------------------------
section "WORKTREES"
# ----------------------------------------------------------------------------
if git worktree list >/dev/null 2>&1; then
  git worktree list | while read -r path hash br; do
    wt_name=$(basename "$path")
    wt_dirty=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    printf "  %-30s %-30s dirty=%s\n" "$wt_name" "$br" "$wt_dirty"
  done
else
  dim "  (git worktree unavailable)"
fi

# ----------------------------------------------------------------------------
section "OPEN PRs"
# ----------------------------------------------------------------------------
if command -v gh >/dev/null 2>&1; then
  pr_out=$(gh pr list --limit 10 --json number,title,headRefName,isDraft,statusCheckRollup 2>/dev/null || echo "")
  if [ -z "$pr_out" ] || [ "$pr_out" = "[]" ]; then
    dim "  (no open PRs / gh not authed)"
  else
    echo "$pr_out" | jq -r '.[] |
      "  #\(.number) \(if .isDraft then "[draft] " else "" end)\(.title)\n     ↳ branch: \(.headRefName)"' 2>/dev/null \
      || dim "  (jq parse failed)"
  fi
else
  dim "  (gh not installed)"
fi

# ----------------------------------------------------------------------------
section "TMUX ROLES"
# ----------------------------------------------------------------------------
if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name} (#{window_panes}p)' 2>/dev/null \
    | grep -Ei 'supervisor|worker|tester|reviewer|dispatcher|alarm|coord' \
    | sed 's/^/  /' \
    || dim "  (no role windows matched)"
else
  dim "  (tmux not running)"
fi

# ----------------------------------------------------------------------------
section "COORD INBOX"
# ----------------------------------------------------------------------------
inbox="$ROOT/.planning/COORD_INBOX.txt"
log="$ROOT/.planning/COORDINATOR_LOG.md"
if [ -f "$inbox" ]; then
  lines=$(wc -l <"$inbox" | tr -d ' ')
  bytes=$(wc -c <"$inbox" | tr -d ' ')
  kv "inbox lines" "$lines  ($bytes bytes)"
  if [ "$lines" -gt 0 ]; then
    echo "  last 3 entries:"
    tail -3 "$inbox" | sed 's/^/    /'
  fi
else
  dim "  (no COORD_INBOX.txt)"
fi
if [ -f "$log" ]; then
  log_lines=$(wc -l <"$log" | tr -d ' ')
  kv "coord log lines" "$log_lines"
fi

# ----------------------------------------------------------------------------
section "RECENT TAGGED COMMITS"
# ----------------------------------------------------------------------------
git log --oneline -n 30 2>/dev/null \
  | grep -E '^[a-f0-9]+ \[(DEV-RULE|WORKER|TESTER|REVIEWER|SUPERVISOR|DISPATCHER|ALARM)\]' \
  | head -n "$LIMIT" \
  | sed 's/^/  /' \
  || dim "  (no tagged commits in last 30)"

# ----------------------------------------------------------------------------
section "SUMMARY"
# ----------------------------------------------------------------------------
issues=0
[ "$dirty" -gt 0 ] && { kv "⚠ uncommitted" "$dirty files"; issues=$((issues+1)); }
case "$ahead_behind" in
  "0	0"|"0 0") ;;
  *) kv "⚠ branch divergent" "$ahead_behind"; issues=$((issues+1));;
esac
[ "$issues" -eq 0 ] && kv "status" "clean"

# ----------------------------------------------------------------------------
# Optional Mermaid block — grep-friendly for paste into handoff docs
# ----------------------------------------------------------------------------
if [ "$GRAPH" = "1" ]; then
  echo
  bold "═══ MERMAID (for handoff paste) ═══"
  cat <<EOF
\`\`\`mermaid
flowchart LR
  branch["$branch<br/>dirty=$dirty"]:::active
  upstream["$upstream<br/>$ahead_behind"]
  branch --> upstream
  classDef active fill:#dfd,stroke:#393
\`\`\`
EOF
fi
