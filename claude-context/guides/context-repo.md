# The `claude-context/` folder and the `.claude` junction

How the AI setup is stored and linked; read before changing agents, skills, hooks or settings.

`claude-context/` is a normal folder **tracked by the cc-telemetry repo** (no nested repo: this
project has no reason to hide the tooling). It is the **single source** of
the project's AI setup:

```
claude-context/                 .claude  ── directory junction ──> claude-context
├── CLAUDE.md                   (so .claude/CLAUDE.md, .claude/settings.json,
├── settings.json                .claude/agents/<name>.md, .claude/skills/<name>,
├── .gitignore                   .claude/hooks/... all resolve to the files on the left)
├── agents/*.md                 developer, reviewer, context-auditor, docs-auditor, mr-reviewer
├── skills/<name>/              commit-message, parallel-task, docs-update, mr-description
├── hooks/                      guard-secrets.py, guard-worktree-context.py (PreToolUse, wired in settings.json;
│                               not the repo-root hooks/, which holds the MkDocs hook app_version.py)
├── guides/*.md                 rules moved out of CLAUDE.md, read on demand
├── scripts/                    check-dashboard.js (verification helper)
├── plans/                      feature plans (guides/feature-planning.md)
├── pull-requests/              git-ignored: PR descriptions drafted by mr-description
├── context-claude.md
├── modules/*.md
├── pending-bugs.md
└── server-state.local.md       git-ignored: the user's own PCs, IPs, networks, decisions
```

- **Link method: one directory junction**, created from the repo root:
  `MSYS_NO_PATHCONV=1 cmd /c mklink /J .claude claude-context` (Developer Mode is off on the
  user's PC, so file symlinks are impossible; a junction needs no rights). Consequences:
  everything in `claude-context/` is also visible under `.claude/`; machine-local files Claude
  Code writes into `.claude/` (e.g. `settings.local.json`) physically land in `claude-context/`
  and are kept out of git by `claude-context/.gitignore`. `.claude` itself is in the root
  `.gitignore` (git would otherwise see the junction).
- A fresh clone has no `.claude`: re-create the junction with the command above. On Linux use a
  directory symlink instead: `ln -s claude-context .claude`.
- **Never create `claude-context/rules/`**: through the junction it becomes `.claude/rules/`,
  which Claude Code loads into every session. On-demand rules go to `guides/`.
- A new agent or skill needs no link step: add `claude-context/agents/<name>.md` or
  `claude-context/skills/<name>/`. Agent definitions are read at session start — restart the
  session to pick up a new one.
- Never replace the junction with a copied folder; always edit the files in `claude-context/`.
- Claude Code treats the resolved `.claude` folder as protected: commands and edits in
  `claude-context/` may ask for approval even when a rule allows them.

## Git
- Denied in `settings.json` (also as `git -C <dir> ...`): `add`, `commit`, `push`, `pull`,
  `fetch`, `checkout`, `switch`, `restore`, `reset`, `stash`, `rebase`, `merge`, `cherry-pick`,
  `revert`, `tag`, `rm`, `mv`, `clean`, `am`, `apply`, `init`, `worktree remove/prune/move/lock`,
  branch delete/rename, plus `rm -r`/`rmdir`. Give the user the command instead.
- **One exception, parallel tasks:** the `parallel-task` skill may run `git worktree add -b` and
  the junctions `mklink /J` — only in the shapes written in the skill, each behind an `ask` rule
  (the user clicks Allow/Deny). `git worktree list` is allowed. Deleting is denied: the skill checks
  the worktree and hands the user the cleanup commands. Worktrees live next to the repo as
  `..\cc-telemetry-<name>`, never under `.claude/`.
- **In a worktree `claude-context/` is locked** (`guides/ledgers.md`): the hook
  `hooks/guard-worktree-context.py` (Edit, Write, NotebookEdit, Bash, PowerShell) blocks writes into
  `claude-context`/`.claude` and any `docker compose` when the session's cwd or
  `CLAUDE_PROJECT_DIR` is inside a `cc-telemetry-*` folder. A worktree made for an AI-setup change
  gets the user-created marker `.wt-context-unlocked`, which unlocks its own copy only.
- Also denied for the Bash tool: data-destroying stack commands (`docker compose down -v`,
  `docker volume rm/prune`, `wsl --unregister`). The PowerShell tool is not covered by these
  rules — the CLAUDE.md "Safety" rule applies there: the user runs them after a dump.

## Secrets enforcement
`Read(...)` deny rules for `**/.env` and `**/backup/**`, `Edit` deny for `.env` and settings
files, and the PreToolUse hook `hooks/guard-secrets.py` (Bash, PowerShell, Read, Grep, Glob):
blocks a command or path naming `.env` (not `.env.example`) or the `backup/` folder; a lone
`ls`, `Test-Path` or `git check-ignore` passes. Runs with `py -3` when the Python launcher
exists (Windows, where `python` is the Store stub), otherwise with `python3` (Linux, e.g. the
Raspberry Pi). The choice is an `if`, not `||`: with `||`, a block (exit 2) would re-run the hook.
