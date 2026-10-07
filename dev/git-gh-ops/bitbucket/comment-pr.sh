#!/usr/bin/env bash
# Post a comment on a Bitbucket Cloud pull request (code-review verdict / self-fix record).
# Usage: comment-pr.sh <remote> <pr-id> <body-file>
#   DRY_RUN=1 comment-pr.sh ...   -> print method, URL, payload; no credential read, no API call.
# GitHub equivalent: gh pr comment <N> --body-file <body-file>
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_bb-common.sh
source "$here/_bb-common.sh"

remote="${1:?remote}"; pr="${2:?pr id}"; bodyfile="${3:?body file}"
[ -s "$bodyfile" ] || { echo "ERROR: body file $bodyfile missing or empty" >&2; exit 3; }

api="$(bb_pr_api "$remote" "$pr")"
payload="$(jq -n --rawfile b "$bodyfile" '{content:{raw:$b}}')"

if [ "${DRY_RUN:-0}" = "1" ]; then
  bb_call POST "$api/comments" "$payload"
  exit 0
fi

bb_load_cred
resp="$(bb_call POST "$api/comments" "$payload")"
href="$(echo "$resp" | jq -r '.links.html.href // empty' 2>/dev/null || true)"
if [ -n "$href" ]; then
  echo "COMMENT_URL: $href"
else
  echo "FAILED - API response:" >&2
  echo "$resp" | jq . >&2 2>/dev/null || echo "$resp" >&2
  exit 1
fi
