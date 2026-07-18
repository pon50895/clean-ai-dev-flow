# Test Request Queue — Worker → Tester async channel (TEMPLATE)

> Copy to `<project>/.planning/TEST_REQUEST_QUEUE.md` before first use.
>
> **Purpose**: workers push test requests here, tester pane (main:8) consumes them sequentially. Solves R1 docker contention.
>
> **Why central**: Docker daemon is single-instance scarce. Concurrent test runs from independent worker subagents race for containers / DB / ports → flaky. Central tester serializes via docker-coord lock.

## Format (append-only)

```
[YYYY-MM-DD HH:MM TZ] [TR-N] worker=<task-N> branch=<feat-branch>
  pr_draft: <pr-number-or-pending>
  phase: <phase-id>
  workspace: <e.g. apps/server>
  feature_files:
    - <path> (+NN LOC, NEW|MOD|DEL)
    - <path> (+NN LOC, NEW|MOD|DEL)
  feature_spec_glob: <e.g. consultation-room.spec.ts or apps/e2e/tests/feat-*.spec.ts>
  request: full-test-suite | unit-only | regression-only | e2e-only
  external_deps_anticipated: [@<service>]
  notes: <free-text from worker>
  state: PENDING | RUNNING | DONE | FAILED | TIMEOUT-DEFAULTED
```

## Active queue (sorted oldest first)

(empty — populated by workers via `bash scripts/skill.sh test-request <args>`)

---

## Process for worker (write side)

When worker finishes feature work:

```bash
bash scripts/skill.sh test-request \
  --worker "task-N" \
  --branch "feat/foo" \
  --phase "phase-NN/wave-X" \
  --workspace "apps/server" \
  --files "apps/server/src/foo.ts:+120,apps/server/src/bar.ts:+45" \
  --spec-glob "foo.spec.ts" \
  --request "full-test-suite"
```

This appends a TR-N entry with state=PENDING. Worker then IDLEs awaiting result (poll TEST_RESULTS.md).

## Process for tester (read side)

Per tick (5 min):
1. Read this file, pick oldest PENDING entry
2. Acquire docker-coord lock (`bash skill.sh docker-coord acquire tester TR-N`)
3. Run 4 test layers per request spec
4. Write result to TEST_RESULTS.md
5. Update queue entry state PENDING → DONE
6. Append to REGRESSION_REGISTRY.md if PASS
7. Release docker-coord lock
8. INBOX inform `[tester DONE TR-N pr=<pr> status=PASS|FAIL]`

## Process for worker (poll result)

```bash
# Poll TEST_RESULTS.md for matching TR-N
while ! grep "TR-N RESULT" .planning/TEST_RESULTS.md; do sleep 60; done
# Extract result, decide push or fix
```

OR worker IDLE waits for INBOX `[tester DONE TR-N]` ping.

## Timeout policy

- PENDING > 1 hr without tester pickup → INBOX `[tester QUEUE-STALE TR-N]` to supervisor
- RUNNING > 30 min → suspect tester pane stuck → supervisor /clear + restart
- TIMEOUT-DEFAULTED → tester unavailable, worker proceeds with self-tested CI as fallback (BLOCK risk on reviewer)

## Categories

| Request type | Layers run | Cost |
|---|---|---|
| `full-test-suite` | unit + integration + e2e + regression | ~5-10 min |
| `unit-only` | unit only | ~1-2 min |
| `regression-only` | regression smoke only | ~3-5 min |
| `e2e-only` | e2e-scoped only | ~2-4 min |

Default: `full-test-suite` (unless worker has reason to skip).
