#!/usr/bin/env bash
# Classify a branch diff as a one-way or two-way door by path rules (feature-pipeline / code-review).
# One-way = hard or costly to reverse after merge: schema/migration, tax/money calculation, payments,
# auth/RBAC/tenant isolation, statutory file generators (XML), outbound notifications, secrets, deploy/infra.
# Usage (inside the repo): door-check.sh [base-ref] [head-ref]
#   base-ref default: kit.json baseRef, else origin/main. head-ref default: HEAD.
# Project additions: kit.json review.oneWayDoorPaths = ["<ERE regex on repo-relative path>", ...] (added to the defaults below).
# Output: "Door: one-way" + matched paths, or "Door: two-way". Exit 0 either way; 2 on usage/git error.
set -euo pipefail

root="$(git rev-parse --show-toplevel)" || exit 2
kit=""
for candidate in "$root/.claude/kit.json" "$root/kit.json"; do
  [ -f "$candidate" ] && { kit="$candidate"; break; }
done

base="${1:-}"
if [ -z "$base" ] && [ -n "$kit" ]; then base="$(jq -r '.baseRef // empty' "$kit")"; fi
base="${base:-origin/main}"
head="${2:-HEAD}"
for ref in "$base" "$head"; do
  git rev-parse --verify --quiet "$ref" >/dev/null || { echo "ERROR: ref '$ref' not found" >&2; exit 2; }
done

rules=(
  '(^|/)migrations?/'
  '(^|/)schema\.prisma$'
  '\.sql$'
  '(^|/)(tax|taxes|duty|duties)(/|[._-])'
  '(^|/)(billing|payments?|checkout|invoic(e|es|ing)|ledger|wallet)(/|[._-])'
  '(^|/)(auth|authz|rbac|permissions?|tenan(t|cy))(/|[._-])'
  '(^|/)[^/]*xml[^/]*(/|\.[A-Za-z]+$)'
  '(^|/)(notifications?|push|mailers?|email|sms|webhooks?)(/|[._-])'
  '(^|/)\.env'
  '(^|/)(secrets?|deploy|infra)(/|[._-])'
)
if [ -n "$kit" ]; then
  while IFS= read -r extra; do [ -n "$extra" ] && rules+=("$extra"); done \
    < <(jq -r '.review.oneWayDoorPaths // [] | .[]' "$kit")
fi

matched=""
while IFS= read -r file; do
  [ -n "$file" ] || continue
  for rule in "${rules[@]}"; do
    if printf '%s\n' "$file" | grep -Eq -- "$rule"; then
      matched+="  $file   <- $rule"$'\n'
      break
    fi
  done
done < <(git diff --name-only "$base"..."$head")

if [ -n "$matched" ]; then
  echo "Door: one-way"
  printf '%s' "$matched"
else
  echo "Door: two-way"
fi
