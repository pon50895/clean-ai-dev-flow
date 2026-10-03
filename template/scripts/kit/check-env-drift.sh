#!/usr/bin/env bash
# =============================================================================
# scripts/kit/check-env-drift.sh - .env 有、.env.example 沒記載的 key -> exit 1
# =============================================================================
# 自動探索:對每個「被 git 追蹤的」`.env.example` / `.env.local.example`,
# 比對同目錄下實際存在的 `.env` / `.env.local`。實際 .env 不存在就略過
# (CI、新 clone 沒有 .env,不會誤擋)。專案內沒有任何 .env.example -> 直接略過。
#
#   .env        vs  .env.example
#   .env.local  vs  .env.local.example(沒有就退回 .env.example)
#
# 由 .githooks/pre-commit 在 modules.envDrift 開啟時呼叫;也可手動:
#   bash scripts/kit/check-env-drift.sh
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

examples="$(git ls-files | grep -E '(^|/)\.env(\.local)?\.example$' || true)"
if [ -z "$examples" ]; then
  echo "[env-drift] no tracked .env.example - skipped."
  exit 0
fi

FAIL=0

extract_keys() {
  grep -v '^[[:space:]]*#' "$1" \
    | grep -v '^[[:space:]]*$' \
    | sed 's/^[[:space:]]*export[[:space:]]*//' \
    | cut -d= -f1 \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | sort -u
}

# check_pair ENV_FILE EXAMPLE_FILE
check_pair() {
  local env_file="$1" example_file="$2"
  [ -f "$env_file" ] || return 0
  [ -f "$example_file" ] || return 0

  local env_keys example_keys missing
  env_keys="$(extract_keys "$env_file")"
  example_keys="$(extract_keys "$example_file")"
  missing="$(comm -23 <(printf '%s\n' "$env_keys") <(printf '%s\n' "$example_keys") || true)"

  if [ -n "$missing" ]; then
    echo "[env-drift] DRIFT in $env_file:" >&2
    printf '%s\n' "$missing" | sed 's/^/  undocumented: /' >&2
    echo "  -> Add these to $example_file with placeholder values." >&2
    FAIL=1
  fi
}

while IFS= read -r ex; do
  dir="$(dirname "$ex")"
  case "$(basename "$ex")" in
    .env.example)
      check_pair "$dir/.env" "$ex"
      # .env.local 在沒有 .env.local.example 時也對 .env.example
      [ -f "$dir/.env.local.example" ] || check_pair "$dir/.env.local" "$ex"
      ;;
    .env.local.example)
      check_pair "$dir/.env.local" "$ex"
      ;;
  esac
done <<EOF
$examples
EOF

if [ "$FAIL" = "1" ]; then
  echo "" >&2
  echo "[env-drift] Fix: add undocumented keys to the corresponding .env.example," >&2
  echo "           then run  bash scripts/kit/check-env-drift.sh  to verify." >&2
  exit 1
fi

echo "[env-drift] OK - no undocumented env vars found."
exit 0
