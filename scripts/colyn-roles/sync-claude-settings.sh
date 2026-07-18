#!/usr/bin/env bash
# sync-claude-settings.sh — symlink .claude/settings.local.json from main to all worktrees
#
# Solves: each worktree's .claude/ is independent + gitignored. Without symlink,
# settings.local.json edits in main don't propagate, leading to "missing
# allowlist after git switch / new worktree" pain.
#
# Run after: settings change OR new worktree creation.
#
# Usage: bash scripts/colyn-roles/sync-claude-settings.sh
# Env:   MAIN_ROOT (default cwd), WORKTREES_DIR (default ../worktrees)

set -euo pipefail

MAIN_ROOT="${MAIN_ROOT:-$(pwd)}"
WORKTREES_DIR="${WORKTREES_DIR:-$MAIN_ROOT/../worktrees}"
SETTINGS_FILE="$MAIN_ROOT/.claude/settings.local.json"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo "ERROR: $SETTINGS_FILE not found. Aborting."
  exit 1
fi

if [[ ! -d "$WORKTREES_DIR" ]]; then
  echo "INFO: no worktrees dir at $WORKTREES_DIR — nothing to sync"
  exit 0
fi

echo "=== source: $SETTINGS_FILE ==="
echo ""

count=0
for wt in "$WORKTREES_DIR"/*/; do
  [[ -d "$wt" ]] || continue
  wt_name=$(basename "$wt")
  target="$wt.claude/settings.local.json"

  mkdir -p "$wt.claude"

  if [[ -L "$target" ]]; then
    echo "[$wt_name] symlink already exists — skip"
  elif [[ -f "$target" ]]; then
    backup="$target.backup-$(date +%H%M%S)"
    mv "$target" "$backup"
    ln -s "$SETTINGS_FILE" "$target"
    echo "[$wt_name] backed up existing -> $backup, symlinked"
    count=$((count+1))
  else
    ln -s "$SETTINGS_FILE" "$target"
    echo "[$wt_name] symlinked"
    count=$((count+1))
  fi
done

echo ""
echo "=== synced $count worktree(s) ==="
