---
name: commit-message
description: Draft git commit messages in the user's Linux-kernel style (area prefix, why-first body, wrapped plain text) from staged changes, the worktree, or an existing commit to reword — any project, any repo (submodules and nested repos included). Use when the user asks to write, draft, compose, shorten or fix a commit message or title, or types /commit-message. Produces a text file checked against the repo's .gitlint; never commits and never changes git state.
argument-hint: "[repo-dir] [staged | worktree | <commit>]"
---

# Commit message

Write commit messages the way the user writes them: an `area: Summary` title and
a short plain-text body that says **why** before **what**, verified against the
diff.

## Hard limits

- **Read-only git only:** `status`, `log`, `diff`, `show`, `ls-files`, `grep`,
  `blame`, `rev-parse`, `branch --show-current`, `submodule status`, also with
  `-C <dir>`. Never `add`, `commit`, `commit --amend`, `rebase`, `reset`,
  `stash`, `checkout`, or anything else that changes a repo. Splitting a commit
  is the user's job — say which files / hunks go together.
- **No trailers:** never `Signed-off-by:`, `Co-Authored-By:`, `Reviewed-by:`,
  "Generated with" or any other — hooks or the user add the sign-off. The draft
  ends with its last body paragraph (or the `[n]` link lines).
- **No attribution:** the message never mentions an AI, an assistant or this
  tooling. If the project's instructions ban words in repo content, the message
  obeys that ban too (pass them to the checker with `--ban`).
- Respect project instructions that keep certain files out of drafts (e.g. a
  submodule pointer or a debug define the user manages): describe the rest and
  don't mention those files.
- One git command per Bash call, run from the session's directory: never
  prefix it with `cd <dir> &&` (Claude Code asks before every `cd` + `git`
  compound, whatever the allow rules say); for another repo use
  `git -C <dir> ...`. If the project says its repo sits in a directory where
  every command asks for approval, run as few git calls there as possible
  (skip `--stat`, one `log`, one diff) and never in parallel.

## Workflow

### 1. Scope

Work out from the arguments and the repo state, asking only what stays open (in
one chat message):

- **Repo** — the current one by default. If the request is ambiguous and a
  submodule or nested repo also has staged changes, ask which.
- **Changes** — in this order: staged (`git diff --cached`); if nothing is
  staged, the worktree (`git diff`, plus untracked files from `git status`) —
  say that you used it; a commit hash means rewording that commit
  (`git show <commit>`).

### 2. Gather the facts

- `git diff --cached --stat` (or the matching variant), then the full diff.
- The code around the change when the diff alone doesn't show why it matters
  (callers, the bug the change prevents, the consumer it affects).
- **Area prefix:** `git log --format=%s -10 -- <file>` for the main touched
  files — reuse the prefix the history already uses for them.
- The style: `git log --no-merges --format='=== %s%n%b' -15` once, if the
  repo's conventions are not already known from project instructions.
- `.gitlint` at the repo root (the checker reads it) and any commit rules in the
  project's instructions; those win over this file where they differ.
- A branch name with a ticket ID or user notes ("this fixes the crash on ...")
  are good sources for the *why* — but check them against the diff.

### 3. One logical change?

If the change set mixes unrelated changes (a fix plus an unrelated rename, two
features, formatting of untouched code), say so, list the groups with their
files, and offer one message per group. Write a combined message only if the
user wants one commit anyway.

Tests that cover the change belong to it — no separate message unless the user
commits them separately.

### 4. Write

**Title** — `area: Summary`

- `area` = base name of the touched module/file without extension, or a
  directory / tool when the change is wider (`src`, `unit-tests`, `Makefile`,
  `ci`, `build`, `docs`, `git`). Nested areas chain (`mycfg: handler: ...`).
- Summary starts with a capitalised imperative verb: Fix, Add, Remove, Update,
  Rename, Move, Support, Improve, Refactor, Set, Bump, Enable. It names the
  effect, not the mechanics ("Fix double free after poll_devs_scan_xxx()", not
  "Remove free() call").
- Functions carry `()`; twin functions as the project writes them (`_xxx()`).
- No trailing punctuation; within the repo's length limit (gitlint default 72).
- Submodule pointer bump: `git: Update <name> submodule`, no body.

**Body** — omit only when the title says everything (version bump, submodule
bump, an obvious one-line fix). Otherwise, blank line after the title, plain
text wrapped to the repo's limit (default 79):

1. **Why**: the problem or motivation and its consequence — what broke, for
   whom, how it showed up. For a bug fix, the trigger and the result
   ("If X failed we called Y with NULL, which leads to segfault").
2. **What**: what the commit does about it, imperative or "So ..." form
   ("Move the check to ...", "So introduce ...").
3. **Also ...**: secondary changes in their own paragraph.

Formatting:

- Lists: two-space indent + `- `; items end with `;`, the last with `.`.
- Quote code only when it shows what the diff cannot: the call or input that
  triggers a bug, an error message, before/after usage a consumer has to
  change. Never quote the lines the commit itself adds or changes — say what
  they do in one sentence. A quote goes on its own lines, indented 2–4 spaces,
  blank line before and after. No tabs.
- References: `[1]` in the text, `[1] <URL>` lines at the end.
- No Markdown — no backticks, headings or bold; identifiers as-is.
- No commit hashes of the same branch, no test counts, no file-by-file
  walkthrough. Describe what the code does now, not how the branch got there.
- Length: most messages are 2–4 short paragraphs; a large change can have a list
  of secondary changes. A body never retells the diff.

### 5. Check

Save to a file — the session scratchpad directory if there is one, otherwise ask
— named `commit-<repo>-<area>.txt` (one file per message). Then run the checker
from this skill's directory:

```
python3 <skill-dir>/scripts/check-msg.py <file> --repo <repo-dir> [--ban <regex>]...
```

It applies the repo's `.gitlint` (title regex and length, trailing punctuation,
whitespace, tabs, blank second line, body line length with ignored URL lines)
and also fails on trailers, Markdown and banned words. Fix and re-run until it
prints `OK`.

### 6. Report in chat

- The message itself in a fenced block (it is short — unlike an MR description,
  show it).
- The command: `git -C <repo-dir> commit -F <file>` (or `--amend -F` for a
  reword) — for the user to run.
- What you were unsure about: a guessed *why*, an area prefix with no history,
  a split you suggest.

### 7. Revisions

Apply corrections to the file and re-run the checker. When a correction is a
general style rule (it would apply to other commits too), offer to add it to
this SKILL.md, phrased project-independently; add it only after the user agrees.

## References

`references/examples.md` — real messages from the user's repos, best first, with
what each one shows. Read it before writing; copy the tone and density, never
the content.
