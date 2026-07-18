#!/usr/bin/env bash
# permission-queue-poll.sh — supervisor poll for user permission async channel (R4)
#
# Logic:
#   1. Read USER_PERMISSION_QUEUE.md — find PENDING entries
#   2. Read USER_PERMISSION_GRANTS.md — match QID
#   3. Apply grant (or timeout safe-default)
#   4. Append decision to COORDINATOR_LOG.md
#
# Run by supervisor cron each tick. Output: summary of decisions.

set -euo pipefail

ROOT="${ROOT:-$(pwd)}"
QUEUE="${PERMISSION_QUEUE:-$ROOT/.planning/USER_PERMISSION_QUEUE.md}"
GRANTS="${PERMISSION_GRANTS:-$ROOT/.planning/USER_PERMISSION_GRANTS.md}"
LOG="${COORD_LOG:-$ROOT/.planning/COORDINATOR_LOG.md}"

[[ -f "$QUEUE" ]] || { echo "QUEUE missing"; exit 0; }
[[ -f "$GRANTS" ]] || { echo "GRANTS missing"; exit 0; }

python3 - "$QUEUE" "$GRANTS" "$LOG" <<'PY'
import re, sys
from datetime import datetime, timezone, timedelta

queue_path, grants_path, log_path = sys.argv[1:]

with open(queue_path) as f:
    queue_text = f.read()
with open(grants_path) as f:
    grants_text = f.read()

pending_re = re.compile(
    r"\[(?P<ts>[^\]]+)\] \[(?P<qid>QID-\d+)\] action=\"(?P<action>[^\"]+)\".*?"
    r"category: (?P<cat>\S+).*?"
    r"risk: (?P<risk>\S+).*?"
    r"safe-default: (?P<safe>[^\n]+).*?"
    r"timeout: (?P<timeout>[^\n]+).*?"
    r"state: (?P<state>\S+)",
    re.DOTALL,
)

grants_re = re.compile(
    r"\[(?P<qid>QID-\d+)\]\s+(?P<decision>GRANTED|DENIED|DEFER)(?:\s+reason=\"(?P<reason>[^\"]*)\")?"
)
grants_map = {}
for m in grants_re.finditer(grants_text):
    grants_map[m.group("qid")] = (m.group("decision"), m.group("reason") or "")

decisions = []
for m in pending_re.finditer(queue_text):
    if m.group("state") != "PENDING":
        continue
    qid = m.group("qid")
    if qid in grants_map:
        decision, reason = grants_map[qid]
        decisions.append((qid, decision, f"user-grant: {reason}"))
        continue
    timeout = m.group("timeout").strip()
    ts_str = m.group("ts").strip()
    try:
        # accept formats like "2026-05-08 05:30 CST" or "2026-05-08 05:30 +0800"
        ts_clean = ts_str
        for tzname in [" CST", " UTC", " GMT"]:
            ts_clean = ts_clean.replace(tzname, "")
        ts_clean = ts_clean.strip()
        ts_dt = datetime.strptime(ts_clean, "%Y-%m-%d %H:%M")
        ts_dt = ts_dt.replace(tzinfo=timezone(timedelta(hours=8)))
        age = (datetime.now(timezone(timedelta(hours=8))) - ts_dt).total_seconds()
    except Exception:
        age = 0
    timeout_secs = {
        "30min": 1800, "2hr": 7200, "overnight": 8 * 3600, "block-until-answer": 10**9,
    }.get(timeout, 7200)
    if age >= timeout_secs:
        decisions.append((qid, "TIMEOUT-DEFAULTED", f"safe-default: {m.group('safe').strip()}"))

if decisions:
    import os
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "a") as f:
        for qid, dec, reason in decisions:
            f.write(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] [permission-queue] {qid} {dec} | {reason}\n")
    print(f"PROCESSED {len(decisions)} decision(s):")
    for qid, dec, reason in decisions:
        print(f"  {qid} → {dec} ({reason})")
else:
    print("NO-PENDING")
PY
