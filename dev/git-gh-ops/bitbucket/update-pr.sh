#!/usr/bin/env bash
# Append one line to the "## 審查紀錄" section of a Bitbucket Cloud PR description (GET, then PUT).
# The section is created at the end of the description if it does not exist yet.
# Usage: update-pr.sh <remote> <pr-id> "<line>"
#   DRY_RUN=1 update-pr.sh ...    -> print the GET and the PUT payload; no credential read, no API call.
#   DRY_RUN_DESCRIPTION_FILE=<f>  -> (dry run only) use <f> as the current description to preview the append.
# GitHub equivalent: gh pr view <N> --json body --jq .body > cur.md, append the same way, gh pr edit <N> --body-file new.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_bb-common.sh
source "$here/_bb-common.sh"

remote="${1:?remote}"; pr="${2:?pr id}"; line="${3:?line to append}"
api="$(bb_pr_api "$remote" "$pr")"
section='## 審查紀錄'

# append_review_line <current-description> <line> -> new description on stdout
append_review_line() {
  printf '%s\n' "$1" | awk -v section="$section" -v entry="- $2" '
    { lines[NR] = $0 }
    $0 == section { in_section = 1; insert_at = NR; next }
    in_section && /^## / { in_section = 0 }
    in_section && NF { insert_at = NR }
    END {
      for (i = 1; i <= NR; i++) {
        print lines[i]
        if (i == insert_at) print entry
      }
      if (!insert_at) { print ""; print section; print entry }
    }'
}

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "DRY_RUN GET $api"
  current="(current description)"
  [ -n "${DRY_RUN_DESCRIPTION_FILE:-}" ] && current="$(cat "$DRY_RUN_DESCRIPTION_FILE")"
  new_desc="$(append_review_line "$current" "$line")"
  bb_call PUT "$api" "$(jq -n --arg t '(current title)' --arg d "$new_desc" '{title:$t, description:$d}')"
  exit 0
fi

bb_load_cred
pr_json="$(bb_call GET "$api")"
state="$(echo "$pr_json" | jq -r '.state // empty')"
[ "$state" = "OPEN" ] || { echo "ERROR: PR #$pr state='$state' (only OPEN PRs can be edited)" >&2; exit 1; }
title="$(echo "$pr_json" | jq -r '.title')"
current="$(echo "$pr_json" | jq -r '.description // ""')"
new_desc="$(append_review_line "$current" "$line")"

resp="$(bb_call PUT "$api" "$(jq -n --arg t "$title" --arg d "$new_desc" '{title:$t, description:$d}')")"
if [ "$(echo "$resp" | jq -r '.id // empty' 2>/dev/null)" = "$pr" ]; then
  echo "UPDATED: #$pr description (審查紀錄 +1)"
else
  echo "FAILED - API response:" >&2
  echo "$resp" | jq . >&2 2>/dev/null || echo "$resp" >&2
  exit 1
fi
