#!/usr/bin/env bash
# learning-inject.sh — output recent active violations as markdown for bootstrap brief injection
#
# Usage:
#   bash scripts/colyn-roles/learning-inject.sh <role> [n=10]
#
# Pipe into bootstrap brief or paste into prompt.

set -euo pipefail

ROLE="${1:?usage: learning-inject.sh <role> [n=10]}"
N="${2:-10}"

REPO="$(git rev-parse --show-toplevel)"
FILE="$REPO/.planning/learning/violations.jsonl"

if [ ! -f "$FILE" ] || [ ! -s "$FILE" ]; then
  echo "(no .planning/learning/violations.jsonl entries yet)"
  exit 0
fi

ROLE="$ROLE" N="$N" FILE="$FILE" node <<'NODE_EOF'
const fs = require("fs");
const role = process.env.ROLE;
const n = parseInt(process.env.N, 10);
const lines = fs.readFileSync(process.env.FILE, "utf8").trim().split("\n").filter(Boolean);
const entries = lines
  .map(l => { try { return JSON.parse(l); } catch (_) { return null; } })
  .filter(Boolean)
  .filter(e => e.status === "active" && (e.applies_to_roles || []).includes(role))
  .sort((a, b) => (b.ts || "").localeCompare(a.ts || ""))
  .slice(0, n);

if (entries.length === 0) {
  console.log("(no active violations applicable to " + role + ")");
  process.exit(0);
}

console.log("## Recent violations to avoid (last " + entries.length + ", auto-injected from .planning/learning/violations.jsonl)");
console.log("");
for (const e of entries) {
  console.log("### " + e.id + " — " + e.trigger_kind);
  console.log("**Avoid**: " + e.violation_summary);
  if (e.user_correction_quote) console.log("**User feedback**: \"" + e.user_correction_quote + "\"");
  if (e.fix_applied)           console.log("**Correct fix**: " + e.fix_applied);
  if (e.rule_reference)        console.log("**Rule**: " + e.rule_reference);
  console.log("");
}
NODE_EOF
