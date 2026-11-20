# Ledgers — ownership and the worktree buffer

Who edits `pending-bugs.md`, and how ledger work is done from a `cc-telemetry-<name>` worktree.

## Ownership
- `pending-bugs.md` — reviewer and mr-reviewer **add**, developer **removes** the entries it fixes,
  context-auditor **prunes** on a requested audit. Nobody else edits it.
- Fixing a `pending-bugs.md` entry is a normal "fix Y"; never fix ledger bugs unasked.

## In a parallel-task worktree
**In a parallel-task worktree (`cc-telemetry-<name>`) nobody edits `claude-context/`** — neither
the main folder's copy (reached through the worktree's `.claude` junction) nor the worktree's own
tracked copy: not the ledger, module files, CLAUDE.md, guides, agents or skills. The user keeps
`claude-context/` in step from the main folder; a branch that never touches it merges without
context conflicts. Enforced by the PreToolUse hook `hooks/guard-worktree-context.py` (blocks
Edit/Write/NotebookEdit and writing Bash/PowerShell commands into `claude-context`/`.claude` when
the session's `cwd` or `CLAUDE_PROJECT_DIR` is inside a `cc-telemetry-*` folder). A blocked call is
final — never write through another path or tool.
- Ledger work goes to the worktree buffer `<wt>/.wt-ledger/pending-bugs.md` (git-ignored by the
  root `.gitignore`), with `## Add` (full entries in the ledger's format, each under its
  `### <area>` heading) and `## Remove` (one line each: ledger area + the entry's first words +
  why — fixed by which file/stage).
- Read the main ledger **and** the buffer before adding, so nothing is listed twice.
- A feature plan written in the worktree goes to the buffer as `plan-<name>.md`
  (`guides/feature-planning.md`).
- Any other context change (module file, CLAUDE.md, guide, agent, skill) is only reported to the
  user ("Docs impact").
- The buffer is moved into `claude-context/` only by `parallel-task finish`, from the main folder,
  on the user's command, before the worktree is removed (`git worktree remove --force` deletes
  ignored files).

## Exception: a worktree for the AI setup itself
When the task is a change of `claude-context/` (agents, skills, hooks, guides), the **user** creates
the empty marker `<wt>/.wt-context-unlocked`. The hook then lets the session write the worktree's
**own** `claude-context/` copy (committed on the branch like code); the main folder's copy and
`<wt>/.claude` stay locked. Claude never creates or removes the marker.
