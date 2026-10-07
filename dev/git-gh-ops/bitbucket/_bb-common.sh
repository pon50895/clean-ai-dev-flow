# Shared helpers for the Bitbucket Cloud PR scripts in this directory. Sourced, not executed.
# Credentials: ~/.claude/secrets/bitbucket.env (BITBUCKET_EMAIL + BITBUCKET_API_TOKEN), same file as bitbucket-pr/open-pr.sh.
# DRY_RUN=1: never reads the credential file and never calls the API; bb_call prints method, URL and payload instead.

BB_CRED="$HOME/.claude/secrets/bitbucket.env"

# bb_pr_api <remote> <pr-id> -> prints https://api.bitbucket.org/2.0/repositories/<ws>/<repo>/pullrequests/<id>
bb_pr_api() {
  local remote="$1" pr="$2" url path ws repo
  url="$(git remote get-url "$remote")"
  # git@bitbucket.org:WS/REPO.git  |  https://bitbucket.org/WS/REPO.git
  case "$url" in *bitbucket.org*) ;; *) echo "ERROR: remote '$remote' is not bitbucket.org ($url)" >&2; return 3 ;; esac
  path="${url#*bitbucket.org[:/]}"; path="${path%.git}"
  ws="${path%%/*}"; repo="${path##*/}"
  [ -n "$ws" ] && [ -n "$repo" ] || { echo "ERROR: cannot parse workspace/repo from '$url'" >&2; return 3; }
  [[ "$pr" =~ ^[0-9]+$ ]] || { echo "ERROR: pr id must be numeric, got '$pr'" >&2; return 3; }
  echo "https://api.bitbucket.org/2.0/repositories/$ws/$repo/pullrequests/$pr"
}

bb_load_cred() {
  [ -f "$BB_CRED" ] || { echo "ERROR: $BB_CRED missing (see bitbucket-pr skill)." >&2; return 3; }
  # shellcheck disable=SC1090
  source "$BB_CRED"
  : "${BITBUCKET_EMAIL:?set in $BB_CRED}"
  : "${BITBUCKET_API_TOKEN:?set in $BB_CRED}"
}

# bb_call <METHOD> <URL> [payload-json] -> response body on stdout.
# Credentials go to curl through a config on stdin (-K -), so the token never appears in the process list.
bb_call() {
  local method="$1" url="$2" payload="${3:-}"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "DRY_RUN $method $url"
    [ -n "$payload" ] && echo "$payload" | jq .
    return 0
  fi
  local args=(-sS -X "$method" -H "Content-Type: application/json" "$url")
  [ -n "$payload" ] && args+=(-d "$payload")
  printf 'user = "%s:%s"\n' "$BITBUCKET_EMAIL" "$BITBUCKET_API_TOKEN" | curl -K - "${args[@]}"
}
