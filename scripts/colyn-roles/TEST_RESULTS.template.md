# Test Results Log — Tester → Worker async channel (TEMPLATE)

> Copy to `<project>/.planning/TEST_RESULTS.md` before first use.
>
> **Purpose**: Tester pane writes test outcomes here. Workers + reviewer + supervisor read.
>
> **Append-only**. Each TR-N gets one RESULT entry per run.

## Format

```
[YYYY-MM-DD HH:MM TZ] [TR-N RESULT] worker=<task-N> pr=<pr-num-or-pending> status=PASS|FAIL
  request_type: full-test-suite | unit-only | regression-only | e2e-only
  duration: NNs
  unit: passed=N failed=0 (file: apps/.../foo.test.ts)
  integration: passed=N failed=0 (file: apps/.../foo.integ.test.ts)
  e2e_scoped: passed=N failed=0 (file: apps/e2e/tests/foo.spec.ts)
  regression_smoke: passed=N failed=0 skipped_external=M
  external_deps_added: [@<service>]
  test_loc: NNN, prod_loc: NNN, ratio: 0.XX
  registry_appended: yes | no
  blockers: [...]
  raw_log_path: /tmp/test-TR-N-<timestamp>.log  # for debug
```

## Results log (append-only)

(empty — populated by tester pane main:8)

---

## How worker reads

After pushing TR-N to TEST_REQUEST_QUEUE.md, worker:
1. Tail this file watching for `[TR-N RESULT]` entry
2. Parse status field
3. If PASS → add+commit subagent test files (if any), push, open PR
4. If FAIL → read blockers, fix, push new commit, optionally re-request via new TR-N

## How reviewer reads

When auditing PR:
1. Find latest `[TR-N RESULT] pr=<my-pr> status=PASS` entry
2. Verify against §2.5.1 R10 build gate (must be PASS, must include all required layers)
3. Cross-check `registry_appended: yes` (cumulative regression maintained)
4. If FAIL or stale → BLOCK PR with comment pointing to TR-N

## How supervisor reads

For arbitration:
- Test-related disputes → grep TR-N for evidence
- Quarterly ratio audit: avg ratio across N PRs (target 0.5-0.75)
- External-dep growth: count unique @-tags added; if growing fast, plan staging-test infra
