---
name: parallel-task
description: Run a second feature in parallel with work already in progress, in its own git worktree next to the main cc-telemetry folder, and tear it down when the feature is finished. Use when the user wants to start a feature/fix while the main folder already has uncommitted changes or another session works in it, says "parallel task", "second feature", "new worktree", "в отдельном worktree", or types /parallel-task; also use with "finish"/"фича закончена" to check a worktree and hand the user its cleanup commands. Creation commands go through the user's Allow/Deny prompt; anything that deletes is run by the user only; never commits.
argument-hint: "start <short-name> <task description> | finish [<short-name>] | status"
---

# Parallel task (git worktree)

One feature = one branch = one worktree folder next to the main repo:

```
<parent>\cc-telemetry          main folder (<main>), its current branch = <base>
<parent>\cc-telemetry-<name>   worktree (<wt>), branch <name>
```

Resolve the placeholders at run time, never write them into tracked files:
- `<main>`: `git rev-parse --show-toplevel` in the main folder; `<parent>` its parent folder.
- `<base>`: `git branch --show-current` in the main folder, unless the user names another branch.
- `<cfg>`: `$CLAUDE_CONFIG_DIR` if set, else `%USERPROFILE%\.claude` (`echo "$CLAUDE_CONFIG_DIR"`).
- Session folder of a path: the absolute path with every non-alphanumeric char replaced by `-`
  (`C:\Users\x\Projects\cc-telemetry` → `C--Users-x-Projects-cc-telemetry`; NTFS ignores the case
  of the drive letter). `ls "<cfg>/projects"` shows the main folder's one.

## Hard limits

- Repo-changing commands run **only** in the exact shapes listed below. Each matches an `ask`
  rule in `settings.json`, so the user sees an Allow/Deny prompt. Never rephrase a command to
  dodge the prompt, never chain it with `&&`/`;`, one command per Bash call, absolute paths,
  `git -C <dir>` instead of `cd`.
- A denied command is final: report it and give the user the command to run by hand.
- `start` and `finish` run from a session in the **main folder** (`git worktree add` needs it as
  cwd; `git -C <dir> worktree ...` is denied). A session inside another worktree tells the user to
  open one in the main folder.
- **Never delete anything yourself.** `git worktree remove/prune`, `rmdir`, `rm -r` are denied;
  do not look for another tool or command that deletes (`ExitWorktree` with `remove`, PowerShell
  `Remove-Item`, a script). Cleanup is always a list of commands the user runs.
- Never `commit`, `push`, `merge`, `branch -d`, `checkout` — the user does those in VS Code
  (Source Control view of the worktree folder).
- `<name>` is lowercase `[a-z0-9-]`, ≤ 30 chars, and never contains `claude`, `anthropic` or an
  agent name (the branch name is public).
- Do not use `EnterWorktree` with `name` (it creates the worktree under `.claude/worktrees/`, which
  is the `claude-context` junction, and branches from `origin/main`) and do not use Agent
  `isolation: "worktree"`. Use `EnterWorktree` only with `path`, to move this session into a
  worktree the user approved.

## What a worktree has and has not

| | In `<wt>` |
| --- | --- |
| code, README, tracked `claude-context/` | the branch's own copy (`claude-context/` read-only, below) |
| `.claude` | junction → `<main>\claude-context`: CLAUDE.md, agents, skills, hooks, settings, `settings.local.json` are the main folder's |
| `claude-context/server-state.local.md` | absent (git-ignored) — read `<main>\claude-context\server-state.local.md` |
| `.env`, `backup/` | absent; never copy or link them — the live-stack helpers run from `<main>` (`guides/verification.md`) |
| `.wt-ledger/` | ledger and plan buffer (git-ignored), `guides/ledgers.md` |
| the stack | **none** — the live stack runs from `<main>`; `docker compose` from `<wt>` would start a second stack with an empty volume and clashing ports (blocked by the hook) |

## status

Read-only overview, also the first step of `start`:

1. `git status --short` in the main folder.
2. `git worktree list` (registered worktrees).
3. For each worktree: `git -C <wt> branch --show-current`, `git -C <wt> status --short`,
   `git log --oneline <base>..<branch>`, `ls -A <wt>/.wt-ledger`.

## start

1. **Analyse** (read-only). Collect the files changed in the main folder and in every existing
   worktree (staged, unstaged, commits ahead of `<base>`). From the new task description and the
   `context-claude.md` module map, list the files the new task will likely touch. Report in a short
   table:
   - overlap of files → **not parallel**: recommend finishing/committing the other task first, or
     doing it in the same branch; stop unless the user insists;
   - shared hot spots, conflict likely but small: `clickhouse/views.sql` (one file for all views),
     `README.md`, `docker-compose.yml`, `otel-collector.yaml`, a dashboard JSON both tasks edit →
     parallel OK only for different parts, name the expected merge conflict; two tasks changing
     view **logic** are not parallel (the live stack holds one version of the views);
   - `claude-context/` is no overlap: the worktree never edits it (hook
     `guard-worktree-context.py`); its ledger findings and plan go to `<wt>/.wt-ledger/` and move
     into `claude-context` at `finish`. A task that changes the AI setup itself: tell the user to
     create the unlock marker after step 3 (`guides/ledgers.md`, "Exception").
   - The new branch starts from the **committed** `<base>`; say so if the main folder holds
     uncommitted work the new task would need.
2. **Propose** `<name>` and `<base>` and ask the user to confirm them (AskUserQuestion) unless they
   gave them.
3. **Create** — each command is its own Bash call, each shows Allow/Deny:
   ```
   git worktree add -b <name> <parent>/cc-telemetry-<name> <base>
   MSYS_NO_PATHCONV=1 cmd /c mklink /J "<wt>\.claude" "<main>\claude-context"
   MSYS_NO_PATHCONV=1 cmd /c mklink /J "<cfg>\projects\<wt session folder>" "<cfg>\projects\<main session folder>"
   ```
   - `MSYS_NO_PATHCONV=1 cmd /c`: Git Bash rewrites `/J` into a path, so `cmd //c mklink /J ...`
     fails with "Invalid switch".
   - `.claude` junction: loads the main folder's CLAUDE.md, agents, skills, hooks and settings in
     the worktree. It is git-ignored by the root `.gitignore` (`/.claude`).
   - Session junction: Claude Code stores a session under `<cfg>\projects\<session folder of the
     cwd>`, so after `EnterWorktree` (and for any session started in the worktree) the transcript
     would land in a new folder. The junction sends it to the main folder's one, so `/resume` and
     the auto-memory find everything in one place. It must exist **before** `EnterWorktree`; if
     `mklink` fails because the folder already exists, stop before entering and tell the user
     (they move its sessions into the main folder's one and replace it with the junction).
   If any step fails or is denied, stop and report what exists now.
4. **Add the folder to the session** — the worktree sits outside the main folder, so every
   command there asks for approval until it is a working directory. `/add-dir` does not exist in
   the VS Code extension, and you may not edit `settings.local.json` (deny rule): show the user
   this entry **inside `permissions`** of `<main>\claude-context\settings.local.json` (keep other
   worktrees already listed), wait until they confirm, then go on:
   ```json
   "permissions": {
     "additionalDirectories": ["<wt with forward slashes>"]
   }
   ```
   The extension picks it up without a restart.
5. **Enter**: `EnterWorktree` with `path: <wt>`. All further work (plan, developer → reviewer
   chain, `git diff <base>`) runs there. From here on `claude-context/` is read-only for this
   session and every subagent (`guides/ledgers.md`).
6. **Tell the user**: in VS Code, File → Open Folder… → `cc-telemetry-<name>` (or File → New
   Window first) — diffs, commits and push (branch `<name>`) happen there, then a PR into `<base>`.
   The plan for the task follows (`guides/feature-planning.md`).

## finish

The user says the feature is done. All checks are read-only; stop and ask on any warning.

1. Resolve `<wt>` and `<name>` (argument, or the worktree this session entered). If `<wt>` is not
   a working directory of this session, first ask the user to add it as in start, 4.
2. Checks:
   - `git -C <wt> status --short` must be empty — anything listed is lost by the removal.
     The junction `.claude` and `.wt-ledger/` do not show (ignored); on a `<base>` whose
     `.gitignore` predates `/.wt-ledger/`, a `?? .wt-ledger/` line is expected — handle it in
     step 4, it is not a failed check.
   - `git log --oneline <base>..<name>` empty → merged locally. Otherwise
     `git log --oneline origin/<name>..<name>` (unpushed commits): say whether the branch is
     merged, pushed only, or local only. Commits stay on the branch (removal keeps the branch),
     but say so.
3. If the session is inside the worktree: `ExitWorktree` with `action: "keep"` (never `remove`).
   If the session was **started** in the worktree (not entered), the hook keeps `claude-context`
   locked for the whole session: tell the user to run step 4 and the cleanup from a new session
   opened in the main folder.
4. **Buffer** — `ls -A <wt>/.wt-ledger` and Read its files. Empty or missing → say "no ledger
   changes" and go on. Otherwise show the user a short table (entries to add, to remove, plans) and
   ask (AskUserQuestion) whether to move them into `claude-context` now. Only on the user's yes,
   from the main folder: dispatch **context-auditor** (model from its frontmatter) for a "buffer
   transfer" of `<wt>/.wt-ledger/pending-bugs.md`, then relay its report. Plan files
   `<wt>/.wt-ledger/plan-*.md`: with the same yes, copy each to `claude-context/plans/<name>.md`
   yourself (Read + Write; ask before overwriting). On no, stop here — no cleanup block, because
   the removal would delete the buffer.
5. **Hand over the cleanup** — you run none of it. Give the user a check table (status clean?
   merged? pushed?) and then, only if all is clean, this block filled in with the real paths, to
   paste into a PowerShell terminal opened in the main folder:
   ```powershell
   # Close the VS Code window of cc-telemetry-<name> first (open files block removal).
   # The block stops by itself (throw) when a step did not work - then show Claude the message.
   & {
     $wt = "<wt>"; $main = "<main>"
     $links = @("$wt\.claude", "<cfg>\projects\<wt session folder>")
     # 1. Remove the junctions. rmdir WITHOUT /s deletes only the link, not its target.
     foreach ($l in $links) {
       if (Test-Path $l) { cmd /c rmdir "$l" }
       if (Test-Path $l) { throw "junction still there: $l - nothing removed" }
     }
     # 2. The real targets must be intact.
     if (-not (Test-Path "$main\claude-context\CLAUDE.md")) { throw "main claude-context missing - STOP" }
     if (-not (Get-ChildItem "<cfg>\projects\<main session folder>" -Filter *.jsonl)) { throw "sessions missing - STOP" }
     # 3. Remove the worktree (the branch stays).
     git worktree remove $wt
     if ($LASTEXITCODE -ne 0) { throw "git worktree remove failed" }
     "done"
   }
   ```
   Explain each step in one line. Order matters: junctions first, otherwise step 3 may delete
   *through* them and wipe the real `claude-context` or the sessions; the `throw` lines make the
   paste stop instead of relying on the user to read the output. After the block, remind the
   user to remove `<wt>` from `permissions.additionalDirectories` in
   `<main>\claude-context\settings.local.json` (drop the key when it was the last entry). If a
   check failed, give no block — say what is left and stop.
6. When the user says it is done, verify read-only: `git worktree list` (entry gone),
   `ls -d <wt>` (folder gone), `ls -A <main>/claude-context` (intact), `ls "<cfg>/projects/<main
   session folder>"` (sessions intact). Then remind them to delete branch `<name>` after the PR is
   merged (VS Code: Command Palette → "Git: Delete Branch..." → `<name>`).

## Reminder at the end of a worktree session

When a chain summary is presented in a session that works inside `cc-telemetry-<name>`, end it
with one line: "Когда PR будет смержен, скажите «фича закончена» — я проверю worktree и дам
команды очистки." Never print the cleanup block before `finish` ran its checks.
