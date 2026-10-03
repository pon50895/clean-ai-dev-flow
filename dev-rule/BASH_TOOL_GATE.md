# Bash Tool Gate (Positive Classification Rule)

> Replaces the negative "F4.1: 0 raw bash" prohibition with a positive
> classification gate + few-shot calibration. Cross-session, model-agnostic.
>
> Why positive: LLMs are autoregressive. Negative prompts ("don't do X")
> get washed out by training priors that suggest X. Positive forcing
> functions ("the next tool MUST be Y") align the next-token probability
> distribution with the desired action.

## Classification gate (run before EVERY Bash tool call)

Classify the command:

**TRIVIAL** — ALL of:
- single allowlisted verb (`git` / `tmux` / `gh` / `bash skill.sh` / `ls` / `cd` / etc)
- no shell metacharacters: `&&` `;` `|` `<<` `>>` `$(...)` backticks
- no control flow: `for` `while` `do` `done` `if` `case`
- ≤ 80 characters total including args
- single line

**NON-TRIVIAL** — any one of the above triggers fails.

## Forcing functions

If TRIVIAL → call Bash directly. No script needed.

If NON-TRIVIAL → the **next tool call** in this turn MUST be `Write` to:
- `scripts/<task>.sh` (if reusable / committed) OR
- `/tmp/<task>.sh` (if one-shot / scratch)

The tool call after Write MUST be `Bash: bash <that-path>`.

No exceptions. No "this one is small enough". No inline justification text
between Write and Bash that hedges.

## Reading files

Use `Read` tool — never `cat` / `head` / `tail` / `grep` via Bash.
`Read` is permission-free for read-allowed paths and shows line numbers.

## Few-shot calibration

These are the only correct shapes. Match exactly.

### Example A — TRIVIAL

```
user: "show git status"
Bash: git status --short
```

single allowlisted verb, 22 chars, no chain → OK

### Example B — NON-TRIVIAL (loop)

```
user: "capture all 7 worker panes"
Write: scripts/fleet-capture-all.sh
       #!/usr/bin/env bash
       for p in 1 2 3 4 5 6 7; do
         echo "=== main:$p ==="
         tmux capture-pane -t main:$p -p | tail -25
       done
Bash:  bash scripts/fleet-capture-all.sh
```

for-loop trigger → script first, never inline

### Example C — NON-TRIVIAL (chain)

```
user: "swap window 9 to 0 then kill 9"
Write: /tmp/swap-and-kill.sh
       #!/usr/bin/env bash
       set -e
       tmux swap-window -s main:9 -t main:0
       sleep 1
       tmux send-keys -t main:9 '/exit' Enter
       sleep 3
       tmux kill-window -t main:9
Bash:  bash /tmp/swap-and-kill.sh
```

4-step chain → script first

### Example D — TRIVIAL but tempting to chain

```
user: "check 2 things: status and last commit"
Bash 1: git status --short
Bash 2: git log -1 --oneline
```

2 trivial calls in same response > 1 chained bash. Use parallel tool calls
in a single message to batch — never `cmd1; cmd2` inline.

### Example E — NON-TRIVIAL (heredoc / substitution)

```
user: "create a PR with body from this template"
Write: /tmp/pr-body.md   (the actual body text)
Bash:  gh pr create --title "..." --body-file /tmp/pr-body.md
```

heredoc trigger → write body to file first, never inline
`gh pr create --body "$(cat <<EOF ... EOF)"`.

## Anti-patterns to refuse

- `for x in ...; do ...; done` inline in Bash tool call
- `cmd1 && cmd2 && cmd3` chained
- `cat <<EOF` heredoc inline
- `... | grep ... | sed ...` pipelines (use Read tool + reasoning)
- `find . | xargs ...` (write a script)

## Self-check primer (run mentally before every Bash tool call)

1. Is it a single allowlisted verb? Yes → continue.
2. Any of `&&` `;` `|` `for` `while` `<<` `$(...)`? Yes → STOP, write script first.
3. Greater than 80 chars? Yes → STOP, write script first.
4. Reading a file? Yes → use Read tool, NOT cat / grep.

If self-check passes all 4, the Bash call is safe.

## Apology Loop diagnostic (when this rule is violated)

If you catch yourself producing a violation followed by an apology and
then another violation in the same session:
- This is "Apology Loop" — autoregressive context pollution from accumulated
  apology tokens reinforces the violation pattern.
- Stop apologizing in prose. Apologies are tokens that pollute context further.
- Hard reset: ask the user to `/clear` the session and re-bootstrap with this
  rule loaded fresh, with no polluted apology tokens in context.
- Do not promise to "stop violating" — promises are tokens, not action.
  The next tool call is the only proof that matters.

---

*Single source of truth for Bash tool discipline. Loaded on demand via CLAUDE.md §0.2.*
