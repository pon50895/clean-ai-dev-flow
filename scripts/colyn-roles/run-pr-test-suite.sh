#!/usr/bin/env bash
# run-pr-test-suite.sh — wrapper for tester subagent test runs (4 layers)
#
# Usage:
#   run-pr-test-suite.sh unit <workspace>          # jest/vitest in workspace
#   run-pr-test-suite.sh integration <workspace>   # cross-module integration tests
#   run-pr-test-suite.sh e2e-scoped <spec-pattern> # playwright matching pattern
#   run-pr-test-suite.sh regression-smoke           # cumulative from REGRESSION_REGISTRY.md
#   run-pr-test-suite.sh build <workspace>          # npm run build
#
# Exit codes:
#   0 — all green
#   1 — test failure (real)
#   2 — infra failure (skip via @ tag)
#   3 — usage error
#
# External @-tags auto-skipped: @s3 @oauth @payment @sms @requires-quota
# Override via TEST_SKIP_TAGS env var.

set -euo pipefail

ROOT="${ROOT:-$(pwd)}"
SKIP_TAGS="${TEST_SKIP_TAGS:-@s3|@oauth|@payment|@sms|@requires-quota}"
EXEC_PREFIX="${TEST_EXEC_PREFIX:-}"  # e.g. "docker exec <container> sh -c" for containerized runs

cd "$ROOT"

mode="${1:-}"
shift || true

run() {
  if [[ -n "$EXEC_PREFIX" ]]; then
    eval "$EXEC_PREFIX \"$*\""
  else
    eval "$*"
  fi
}

case "$mode" in
  unit)
    workspace="${1:?workspace required (e.g. apps/server / packages/core)}"
    echo "=== unit tests in $workspace ==="
    run "cd $workspace && npm test 2>&1 | tail -30"
    ;;
  integration)
    workspace="${1:?workspace required}"
    echo "=== integration tests in $workspace ==="
    # Convention: integration tests in __integration_tests__/ or test/integration/
    if [[ -d "$workspace/__integration_tests__" ]]; then
      run "cd $workspace && npm run test -- __integration_tests__ 2>&1 | tail -30"
    elif [[ -d "$workspace/test/integration" ]]; then
      run "cd $workspace && npm run test:integration 2>&1 | tail -30"
    else
      echo "no integration test dir found in $workspace (looked for __integration_tests__/ or test/integration/)"
      exit 0
    fi
    ;;
  e2e-scoped)
    spec="${1:?spec pattern required}"
    echo "=== playwright scoped: $spec ==="
    run "npx playwright test apps/e2e/tests/$spec --workers=1 --grep-invert='$SKIP_TAGS' 2>&1 | tail -40"
    ;;
  regression-smoke)
    echo "=== regression smoke (REGRESSION_REGISTRY.md cumulative) ==="
    REGISTRY="${REGRESSION_REGISTRY:-$ROOT/.planning/REGRESSION_REGISTRY.md}"
    if [[ ! -f "$REGISTRY" ]]; then
      echo "WARN: $REGISTRY not found — skipping cumulative; running default smoke"
      run "npx playwright test apps/e2e/tests/smoke.spec.ts --workers=1 --grep-invert='$SKIP_TAGS' 2>&1 | tail -30"
      exit 0
    fi
    specs=$(grep -oE 'apps/e2e/tests/[^ ]+\.spec\.ts' "$REGISTRY" | sort -u | head -20 | tr '\n' ' ')
    if [[ -z "$specs" ]]; then
      echo "WARN: no specs parsed from registry — fallback default smoke"
      specs="apps/e2e/tests/smoke.spec.ts"
    fi
    echo "specs: $specs"
    run "npx playwright test $specs --workers=1 --grep-invert='$SKIP_TAGS' 2>&1 | tail -40"
    ;;
  build)
    workspace="${1:?workspace required}"
    echo "=== build $workspace ==="
    run "npm run build --workspace=$workspace 2>&1 | tail -20"
    ;;
  *)
    cat <<USAGE
run-pr-test-suite.sh — tester subagent test runner (4 layers)

Modes:
  unit <workspace>             Layer 1 — jest/vitest unit/component tests
  integration <workspace>      Layer 2 — cross-module / service-to-DB tests
  e2e-scoped <spec-pattern>    Layer 3 — playwright on specific spec(s)
  regression-smoke              Layer 4 — cumulative from REGRESSION_REGISTRY.md
  build <workspace>             npm run build (build gate per §2.5.1 R10)

Env:
  TEST_SKIP_TAGS (default '@s3|@oauth|@payment|@sms|@requires-quota')
  TEST_EXEC_PREFIX (e.g. 'docker exec mycontainer sh -c' for containerized run)
  REGRESSION_REGISTRY (default ./.planning/REGRESSION_REGISTRY.md)
USAGE
    exit 3
    ;;
esac
