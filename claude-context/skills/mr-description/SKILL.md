---
name: mr-description
description: Compose a GitHub pull request description and title for a cc-telemetry branch from the changes between a source and a base branch, in the user's style. Use when the user asks to write, draft, compose, shorten or update a PR/MR description or title, or types /mr-description. Runs the mr-reviewer gate first. Produces a Markdown file only; never creates PRs and never changes git state.
argument-hint: "[source-branch] [-> base-branch]"
---

# PR description

Write pull request descriptions the way the user writes them: short, about what a reader of the
PR (the user later, someone installing the stack, a reviewer) needs to know, verified against the
code.

## Hard limits

- **Read-only git only:** `status`, `log`, `diff`, `show`, `ls-files`, `grep`, `rev-parse`,
  `branch --show-current`, `worktree list`, also with `-C <dir>`. Never `add`, `commit`,
  `checkout`, `switch`, `fetch`, `pull`, `push`, `merge`, branch create/delete. If a branch is
  missing locally, ask the user — do not fetch it.
- **No GitHub actions:** never `gh`, curl against the GitHub API or any connector to create, edit
  or comment on a PR. The output is a text file; the user creates the PR.
- **No attribution:** the description never mentions an AI, an assistant, this tooling,
  "generated with" or `Co-Authored-By`. The repo is public: no personal data (PC names, IPs,
  networks, the user's other projects) — `claude-context/server-state.local.md` stays private.
- One git command per Bash call, never prefixed with `cd <dir> &&`; for a worktree use
  `git -C <wt> ...`.

## Workflow

### 1. Scope — one round of questions
Run from a session in the **main folder** (the output goes to its `claude-context/`, which is
locked inside a worktree); the source branch may be a worktree's. Look around (current branch,
`git worktree list`, `git rev-parse --verify <branch>` for a named branch), parse the arguments,
then ask everything still open **in one plain chat message** and stop until the user answers:

1. **Source branch** — propose the current branch (or the worktree's branch).
2. **Base branch** — the branch the PR goes into. Propose the branch the source was started from:
   for a parallel-task worktree the main folder's branch at `start`, otherwise `main`. Check with
   `git log --oneline <base>..<source>` that the range holds only the branch's own commits.

Skip a question the arguments or earlier messages already answer.

### 1a. PR review gate
Dispatch **mr-reviewer** (model from `claude-context/agents/mr-reviewer.md` frontmatter) with
`source`, `base` and `<wt>` if any. Relay its verdict in one line.
- **BLOCKED** → stop: show the blockers, write no description.
- Warnings → go on; list them in the chat report so the user can fix them first.
- The user may say "skip review" — then skip this step and say so in the report.

### 2. Gather the facts
- Full commit messages — usually the best source of *why*:
  `git log --reverse --format='=== %h %s%n%b' <base>..<source>`.
- `git diff --stat <base>...<source>` (three dots: changes on the source since the merge base).
- Diffs of what a user meets: script options and steps, ports and bind addresses, `.env` keys,
  image tags, collector processors (what is sent / dropped), `cc.*` view columns the dashboards
  read, dashboards (new panels, variables, links), README sections.
- The code behind every claim you are going to make.
- Past PR titles: `git log --merges --format='%s%n%b' -20 <base>` (GitHub puts the PR title in the
  merge commit body).

### 3. Verify
- Every statement must be backed by the diff or the code. Commit messages can be wrong or stale;
  leave unconfirmed claims out and report them in chat.
- Describe the **final state of the branch**, not its history. A defect introduced and fixed
  within the branch is not a bug fix of the PR. Bug fixes are defects present on the base branch.

### 4. Classify

| Change | Goes to |
| --- | --- |
| Something a user sees or can do: a dashboard, panel, variable, tip, script option, setup step, platform | **New features** — one item per capability |
| Internal work a feature needed (a new view column, a shared helper in a script) | One sentence **inside that feature** |
| Wrong behaviour that exists on the base branch | **Bug fixes** — group related defects |
| README changes beyond what a feature item already says | **Documentation** |
| AI setup (`claude-context/`: agents, skills, hooks, guides, module docs) | **Tooling** — one short item, or leave out when it is only doc upkeep |
| Anything that needs action on an installed stack or client: re-run a setup script, `views-init`, new `.env` key, new port to open, changed image tag, data newly collected or dropped, removed dashboard or panel | **Upgrade notes** |
| Refactoring without visible effect, renames, formatting, comments | **Leave out** |

Describe a change at its real scope ("every dashboard", not "the Sessions dashboard", when the
shared variable changed everywhere).

### 5. Write

Sections, in this order; omit empty ones:

```markdown
## New features
## Bug fixes
## Documentation
## Tooling
## Upgrade notes
```

Items:
- Feature: `- **Bold lead-in.** ...` — the motivation in one sentence when it is not obvious,
  then what it does. One short paragraph, at most ~6 lines; a nested list only for peer things
  (e.g. the panels of a new dashboard).
- Bug fix: `- **What was broken** — consequence; the fix.` One or two sentences.
- Upgrade note: `- **Kind:** what to run or change.` — kinds: Re-run, Views, `.env`, Ports, Data,
  Removed. Commands in backticks, copy-pasteable.
- Identifiers, paths, commands in backticks; panels and dashboards by their exact titles. Wrap at
  ~100 columns.
- No implementation walkthroughs (file by file, SQL internals), no commit hashes, no check counts.
- Length: a large branch ~40 lines; a small PR can be five.

Example of the shape (not of the content):

```markdown
## New features

- **Account filter on every dashboard.** Two Claude accounts sending to one server were mixed.
  A new Account variable, first in the shared set, narrows every panel and the other dropdowns;
  drill-down links keep the selection.

## Upgrade notes

- **Views:** run `docker compose run --rm views-init` on the server after pulling.
```

File: `claude-context/pull-requests/<source-branch>.md` in the main folder (git-ignored: the PR
on GitHub keeps the text). If the file exists, read it first — the user may have edited it — and
ask before replacing it. The title is not part of the file.

### 6. Report in chat
Short, not the description itself:
- the file path and the review verdict (or "review skipped");
- a title: imperative, the main capability, ≤ ~70 characters, in the style of past PR titles;
  plus a narrower alternative when the PR mixes topics;
- reviewer warnings still open;
- claims from commits that the code did not confirm;
- things deliberately left out that the user might want back;
- open questions.

### 7. Revisions
Apply the user's corrections to the file. When a correction is a general style rule, offer to
add it to this SKILL.md; add it only after the user agrees.
