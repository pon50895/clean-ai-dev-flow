#!/usr/bin/env bash
# Classify a branch diff as a one-way or two-way door by path rules (feature-pipeline / code-review).
# One-way = hard or costly to reverse after merge: schema/migration, tax/money calculation, payments,
# auth/RBAC/tenant isolation, statutory file generators (XML), outbound notifications, secrets, deploy/infra.
# Usage (inside the repo): door-check.sh [base-ref] [head-ref]
#   base-ref default: kit.json baseRef, else origin/main. head-ref default: HEAD.
# Default is one-way: a diff is two-way only when every changed file matches a two-way rule
# (docs, .planning, tests, locales, images, styles). A missed rule then costs an extra opus review,
# never a skipped one. Each one-way file is tagged:
#   [high-risk]    matches a one-way rule below - reviewer must not self-fix (code-review).
#   [unclassified] matches neither list - reviewed as one-way; sort it into a list at the weekly skillopt.
# Project additions (ERE regexes on repo-relative paths, added to the defaults below):
#   kit.json review.oneWayDoorPaths, review.twoWayDoorPaths. A one-way rule wins over a two-way rule.
# Output: "Door: one-way" + tagged paths, or "Door: two-way". Exit 0 either way; 2 on usage/git error.
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
two_way_rules=(
  '\.md$'
  '(^|/)\.planning/'
  '(^|/)docs?/'
  '(^|/)__tests__/'
  '\.(test|spec)\.[cm]?[jt]sx?$'
  '(^|/)e2e/'
  '(^|/)locales?/'
  '\.(png|jpe?g|gif|svg|webp|ico)$'
  '\.(css|scss)$'
)
if [ -n "$kit" ]; then
  while IFS= read -r extra; do [ -n "$extra" ] && rules+=("$extra"); done \
    < <(jq -r '.review.oneWayDoorPaths // [] | .[]' "$kit")
  while IFS= read -r extra; do [ -n "$extra" ] && two_way_rules+=("$extra"); done \
    < <(jq -r '.review.twoWayDoorPaths // [] | .[]' "$kit")
fi

first_match() { # first_match <file> <rule>... -> prints the matching rule, exit 1 if none
  local file="$1" rule; shift
  for rule in "$@"; do
    printf '%s\n' "$file" | grep -Eq -- "$rule" && { printf '%s' "$rule"; return 0; }
  done
  return 1
}

matched=""
while IFS= read -r file; do
  [ -n "$file" ] || continue
  if rule="$(first_match "$file" "${rules[@]}")"; then
    matched+="  [high-risk] $file   <- $rule"$'\n'
  elif ! first_match "$file" "${two_way_rules[@]}" >/dev/null; then
    matched+="  [unclassified] $file"$'\n'
  fi
done < <(git diff --name-only "$base"..."$head")

if [ -n "$matched" ]; then
  echo "Door: one-way"
  printf '%s' "$matched"
else
  echo "Door: two-way"
fi
