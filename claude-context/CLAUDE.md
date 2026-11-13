# CLAUDE.md — cc-telemetry

<!-- This file lives at claude-context/CLAUDE.md and is surfaced as .claude/CLAUDE.md because
     .claude is a directory junction to claude-context (see guides/context-repo.md). Paths are
     written repo-root-relative. Rules most tasks do not need live in claude-context/guides/ and
     are read on demand — keep this file short. -->

cc-telemetry is a local usage-statistics stack for Claude Code: clients export OpenTelemetry
events (OTLP gRPC :4317) to a server PC running OTel Collector → ClickHouse → Grafana in Docker
(Docker Desktop, or Docker Engine inside WSL2). Two PowerShell scripts set up the server
(`setup-server.ps1`) and each client (`client/setup-client.ps1`). `README.md` is the public,
English guide for people; keep it in step with the code.

## Navigation
1. `claude-context/context-claude.md` — hub (glossary, data flow, module map, conventions,
   ledger). Always read first.
2. The module file of your area in `claude-context/modules/`: `stack`, `telemetry-data`,
   `dashboard`, `setup-scripts`.
3. Source last.

Ledger: `claude-context/pending-bugs.md` (suspected bugs and unverified behaviour).
**The user's own server and clients** (PC names, IPs, networks, past decisions about their data):
`claude-context/server-state.local.md` — git-ignored; read it before working on the live
server or connecting a PC. Never copy its content into tracked files.

### Guides — read the one that matches the task before starting it

| Task | Guide |
| --- | --- |
| Writing or reviewing SQL views, dashboard JSON, PowerShell, bash, compose/collector config | `claude-context/guides/conventions.md` |
| Checking a change on the live stack (SQL, dashboard queries, scripts) | `claude-context/guides/verification.md` |
| Drafting a commit message | `claude-context/guides/commit-messages.md` |
| Writing context docs or the README | `claude-context/guides/docs-writing.md` |
| Changing the AI setup (junction, agents, skills, hooks, settings) | `claude-context/guides/context-repo.md` |

---

## The user's tools
Windows 10, VS Code (editing, diffs, **all git** — Source Control view or a command to paste
into the VS Code terminal), PowerShell in the terminal. Your Bash tool is Git Bash; a PowerShell
tool is available too. Docker runs inside WSL here (`wsl -d Ubuntu -- docker compose ...` from
the repo root).

## Git
- Read-only git only: `status`, `log`, `diff`, `show`, `blame`, `ls-files`, `grep`, `rev-parse`,
  `branch --show-current` (also as `git -C <dir> ...`). The rest is denied in `settings.json` —
  never work around a denied command; give the user the exact command instead.
- `claude-context/` is tracked by this repo (no nested repo); `.claude` is git-ignored.

## Secrets and private data
- `.env` holds the ClickHouse and Grafana passwords; `backup/` holds dumps of the telemetry
  (the user's prompts). Never print, copy or read them. Scripts read `.env` themselves
  (`wsl/ch.sh`, `claude-context/scripts/check-dashboard.js`) — use those.
- The hook `hooks/guard-secrets.py` and `Read` deny rules block calls naming them; a blocked call
  is final — never rephrase the path, ask the user.
- No personal data (PC names, IPs, user names, networks, the user's other projects) in tracked
  files: it goes to `claude-context/server-state.local.md`.

## Safety
Never without the user's explicit "yes": anything that deletes data (`docker compose down -v`,
`docker volume rm`, `wsl --unregister`, `DELETE`/`DROP` in ClickHouse — dump first with
`wsl/backup.sh dump`); Windows system settings (network profile, firewall, services); commands
needing admin rights (hand them to the user). Never help bypass corporate controls (VPN,
firewalls, IT policy); warn before corporate data would go to a personal server. Client setup is
always per-user, never system-wide.

## Commit messages
Draft one **only when the user directly asks**; never on your own initiative, never in a
summary, never by a subagent. Format: `claude-context/guides/commit-messages.md` (or the
`commit-message` skill). Never any trailer (`Co-Authored-By`, `Signed-off-by`, ...).

## Answering
Answer in Russian. Never split an answer across tool calls: investigate first, then write ONE
answer at the end. Focused and brief; high-level unless depth is asked for. After a setup stage:
what works, what was fixed, what is left for the user.

---

## Sub-Agent Workflow

**Always pass the agent's model explicitly**: read the `model:` key in
`claude-context/agents/<name>.md` (re-read it — definitions are cached at session start) and pass
it as `model` on the Agent call.

| Agent | Model | Role | Writes |
| --- | --- | --- | --- |
| `developer` | sonnet | implements features/fixes in views, dashboard, scripts, config, README; verifies on the live stack | code, README; removes `pending-bugs.md` entries it fixes |
| `reviewer` | sonnet | reviews the diff vs `HEAD`; "review only" and "bug hunt in <area>" | only appends to `pending-bugs.md` |
| `context-auditor` | opus | keeps `context-claude.md`, `modules/*.md` and the ledger in sync with the code | `claude-context/` docs only |

**Feature chain** — always sequential: developer → reviewer (BLOCKED → back to developer with the
blocker list). **Trivial change** (comment or text, a typo, README wording, a constant the user
named with its new value, a rename inside one function) → no reviewer; end the reply with the bold
line **РЕВЬЮЕР НЕ ЗАПУСКАЛСЯ (ТРИВИАЛЬНАЯ ПРАВКА)**. Never trivial: SQL view logic, dashboard
queries or variables, collector pipeline, anything in the setup scripts touching the network,
firewall, WSL, `.env` or user settings files, or more than ~10 lines. In doubt → not trivial.

**Routing:** "implement X" / "fix Y" → full chain. "review only" → reviewer. "find bugs in X" /
"bug hunt" → reviewer in bug-hunt mode (ledger only). Never fix ledger bugs unasked.

**Context updates are user-initiated only** — never as the closing step of a feature; pass the
developer's "Docs impact" to the user instead. "update claude-context / context" →
context-auditor. Never edit module files directly.
