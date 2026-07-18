# Command Policy — AUTO-APPROVE / AUTO-DENY / ESCALATE

> SSOT for sentinel (Haiku 4.5, tmux:1) command classification.
> Coordinator (Opus 4.7, tmux:0) and workers reference this when deciding which commands run unsupervised.

## Decision tree

```
Bash prompt appears in a worker pane
        |
        v
Match against AUTO-APPROVE patterns (exact / prefix)?
        |
   YES -+- NO
   |       |
   v       v
Send "1"  Match against AUTO-DENY patterns (substring)?
+ log              |
              YES -+- NO
              |       |
              v       v
          Send "3"  ESCALATE
          + [URGENT] log + log [ESCALATE]
          + ping main:0 + ping main:0
                            (do NOT touch prompt)
```

**Bias**: when in doubt -> escalate. False positive (waking coord) is cheap; false negative (auto-approving destructive command) is catastrophic.

---

## AUTO-APPROVE whitelist

Commands matching these patterns are read-only / test / build / additive install and safe.

### Git (read-only)
| Pattern | Notes |
|---|---|
| `git status`, `git status --short`, `git status -sb`, `git status -uno` | working tree inspection |
| `git diff`, `git diff --stat`, `git diff --name-only`, `git diff <ref>...HEAD` | diff inspection |
| `git log --oneline -<N>`, `git log <ref>`, `git log --graph` | history read |
| `git branch`, `git branch -a`, `git branch --merged` | branch list |
| `git fetch origin`, `git fetch --all`, `git fetch --prune` | remote sync, no local mutation |
| `git ls-remote ...` | remote inspection |
| `git show <sha>`, `git show <sha> --stat` | commit inspection |
| `git rev-parse HEAD`, `git rev-parse --abbrev-ref HEAD` | ref resolution |
| `git stash list`, `git stash show` | stash read |
| `git remote -v`, `git remote show origin` | remote inspection |

### Test runners
| Pattern | Notes |
|---|---|
| `npm run test*`, `npm test*` | jest / vitest / playwright wrapped |
| `npx jest <pattern>`, `npx jest --testPathPattern=...`, `npx jest --config <path>` | direct jest |
| `npx vitest <pattern>`, `npx vitest run` | vitest |
| `npx playwright test --grep ...`, `npx playwright test <path>` | E2E |

### Build / typecheck (no network mutation)
| Pattern | Notes |
|---|---|
| `npm run build*`, `npm run build --workspace=...` | build verification |
| `npx tsc --noEmit*` | typecheck |
| `npx prisma generate`, `npx prisma format`, `npx prisma validate` | non-destructive prisma |
| `npx eslint <path>`, `npx prettier --check <path>` | lint |

### Filesystem read
| Pattern | Notes |
|---|---|
| `cat <file>`, `head -<N> <file>`, `tail -<N> <file>` | read |
| `ls`, `ls -la`, `ls /<path>` | dir list |
| `find <path> -name <pattern>`, `find <path> -type f` | search (NOT with -delete or -exec) |
| `grep <flags> <pattern> <file>`, `grep -r <pattern> <dir>` | search |
| `wc -l`, `wc -c`, `pwd` | counts / cwd |
| `realpath <path>`, `readlink <path>` | path resolution |

### Docker (read-only)
| Pattern | Notes |
|---|---|
| `docker ps`, `docker ps -a`, `docker ps --format ...` | list |
| `docker logs <container> --tail <N>`, `docker logs <container> -f` | log inspection |
| `docker inspect <container>`, `docker inspect <container> --format ...` | meta read |
| `docker exec <container> <readonly-cmd>` | exec read-only (cat/ls/ps inside container) |
| `docker exec <container> psql -U <u> -d <db> -c "SELECT ..."` | SQL SELECT only |
| `docker volume ls`, `docker network ls`, `docker image ls` | resource list |

### GitHub CLI (read-only)
| Pattern | Notes |
|---|---|
| `gh pr view <num>`, `gh pr list`, `gh pr diff <num>`, `gh pr status` | PR inspection |
| `gh issue view <num>`, `gh issue list` | issue read |
| `gh api repos/...` (GET only) | API read |
| `gh run list`, `gh run view <id>` | CI inspection |

### HTTP (read-only)
| Pattern | Notes |
|---|---|
| `curl -s <url>`, `curl -I <url>`, `curl -o /dev/null <url>` | GET / HEAD |
| `curl -s -w "%{http_code}" <url>` | status check |
| `wget --spider <url>` | reachability |

### Package install (additive only)
| Pattern | Notes |
|---|---|
| `npm install --no-audit --no-fund` | install per package.json (no version change) |
| `npm ci` | clean install per lockfile |
| `pip install <pkg>`, `pip install -r requirements.txt` | python install |
| `npx ts-node <script>` | run TS script (treats as test/build) |

---

## AUTO-DENY blacklist

§2 high-risk per CLAUDE.md. Substring match — if ANY of these appear in the proposed command, deny "3" + log [URGENT] + ping coordinator.

### Filesystem destructive
| Pattern | Risk |
|---|---|
| `rm -rf*`, `rm -r *` | recursive delete |
| `find * -delete`, `find * -exec rm` | mass delete |

### Git destructive
| Pattern | Risk |
|---|---|
| `git reset --hard*` | discards local changes |
| `git clean -fd*`, `git clean -f*`, `git clean -fdx` | wipes untracked |
| `git push --force` (without `--force-with-lease`) | overwrites remote |
| `git push * main`, `git push * master` | direct push to protected (must go via PR) |
| `git branch -D *` (without coord auth) | force-delete branch |
| `git reflog expire`, `git gc --prune=now` | history pruning |

### Hook bypass (CLAUDE.md §1 R11)
| Pattern | Risk |
|---|---|
| `--no-verify` | skips Husky hooks |
| `--no-gpg-sign` | bypasses signing |
| `core.hooksPath` | redirects hook path |
| `HUSKY=0` | disables Husky env |
| `SKIP_P0_REGRESSION=1` (NOT for pure merge commits) | bypasses P0 (allowed only for merge commits) |

### Docker destructive
| Pattern | Risk |
|---|---|
| `docker volume rm*` | deletes volume = data loss |
| `docker-compose down -v*` | removes volumes |
| `docker system prune*`, `docker prune -a` | wipes images / volumes |
| `docker rm -f <container-with-data>` | force-remove |

### Database destructive
| Pattern | Risk |
|---|---|
| `DROP TABLE*`, `DROP DATABASE*`, `DROP SCHEMA*` | schema delete |
| `TRUNCATE*` | table wipe |
| `DELETE FROM <table>` (without `WHERE`) | mass delete |
| `prisma migrate reset*` | resets migration history + data |
| `prisma db push --force-reset` | destructive sync |

### Process / OS
| Pattern | Risk |
|---|---|
| `kill -9 *` (any non-claude pid) | force-kill external process |
| `sudo *`, `su -*`, `su <user>` | privilege escalation |
| `chmod 777*`, `chmod -R 777` | wide-open perms |
| `chown <user> *` | ownership change |
| `mkfs*`, `dd if=/dev/zero` | disk-level destructive |

### Secrets / credentials
| Pattern | Risk |
|---|---|
| any write to `.env*` | secret modification |
| any write to `*.pem`, `*.key`, `id_rsa*` | private key modification |
| any write to `credentials*.json`, `*-credentials.*` | API credentials |
| `cat .env*`, `cat *.pem` to stdout | secret leak — auto-deny by default; coord may approve case-by-case |

### CI / GitHub destructive
| Pattern | Risk |
|---|---|
| `gh pr close <num>`, `gh pr merge --admin` | PR mutation |
| `gh release delete*` | release deletion |
| `gh api * -X DELETE`, `gh api * -X PUT` (without coord auth) | API mutation |

---

## ESCALATE — anything else

If a command does NOT match auto-approve OR auto-deny, sentinel:

1. Do NOT touch the prompt — leave it sitting
2. Log: `[YYYY-MM-DD HH:MM:SS] [ESCALATE] sentinel main:N awaiting coord: <full command>`
3. Append action item to `.planning/COORD_INBOX.txt` (do NOT use tmux send-keys; see SENTINEL.md §INBOX write protocol)

Common escalate triggers:
- Multi-line command (heredoc, backslash-continued)
- Compound command with `&&` mixing safe + risky elements
- Unfamiliar tool (anything not in approve/deny lists)
- Suspicious flag combinations
- Command targeting `main:0` (coordinator pane) from a worker

---

## Compound command handling

When a single Bash prompt contains multiple commands joined by `&&` / `;` / `|`:

| Composition | Action |
|---|---|
| ALL parts in approve list | AUTO-APPROVE |
| ANY part in deny list | AUTO-DENY |
| Mix of approve + unknown | ESCALATE |
| Pipe (`\|`) where both parts approve (e.g., `cat file \| head -5`) | AUTO-APPROVE |
| Pipe where any part touches network output (`curl ... \| sh`) | AUTO-DENY |

---

## Update protocol

When a new command pattern emerges:

1. Coordinator decides classification (approve / deny / always-escalate)
2. Edit this file in a `chore/command-policy-update` PR
3. Re-paste SENTINEL.md to main:1 OR send `tmux send-keys -t main:1 "re-read COMMAND_POLICY.md and apply" Enter`
4. Sentinel picks up new patterns on next tick

---

## References

- CLAUDE.md §1 (R1-R11 red lines)
- CLAUDE.md §2 (high-risk command list)
- CLAUDE.md §2.5 (branch + test gate)
- `.planning/AGENT_GUARDRAILS.md` (per-project guardrails, if maintained)
- `dev-rule/ai-architecture/COORDINATOR.md`
- `dev-rule/ai-architecture/SENTINEL.md`
