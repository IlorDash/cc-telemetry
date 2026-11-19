---
name: mr-description
description: Compose merge request / pull request descriptions in the user's style from the changes between a source and a base branch — any project, any tech stack, one description per repo (submodules and nested repos included). Use when the user asks to write, draft, compose, shorten or update an MR/PR description or title, or types /mr-description. Produces a Markdown file only; never creates MRs and never changes git state.
argument-hint: "[source-branch] [-> base-branch]"
---

# MR description

Write merge request descriptions the way the user writes them: short, about what
a reader of the MR (reviewer, consumer of the API, release notes author) needs
to know, verified against the code.

## Hard limits

- **Read-only git only:** `status`, `log`, `diff`, `show`, `ls-files`, `ls-tree`,
  `grep`, `rev-parse`, `branch --show-current`, also with `-C <dir>`. List
  branches with `git rev-parse --abbrev-ref --branches --remotes` and find
  submodules with `git ls-files --stage` (mode `160000`) — `branch -a` and
  `submodule status` may not be on the project's allow list. If the project's
  instructions allow fewer git commands, use only those. Never run anything that
  changes the state of any repo,
  submodule or nested repo: no `add`, `commit`, `checkout`, `switch`, `fetch`,
  `pull`, `push`, `stash`, `reset`, `merge`, `rebase`, `tag`, `submodule update`,
  branch create/rename/delete. If a branch is missing locally, ask the user —
  do not fetch it.
- **No git platform actions:** never run `glab`, `gh`, curl against GitLab /
  GitHub APIs, or any MCP connector to create, edit or comment on an MR. The
  output is a text file; the user creates the MR.
- **No attribution:** the description never mentions an AI, an assistant, this
  tooling, "generated with", `Co-Authored-By` or similar. If the project's
  instructions ban words in repo content, the MR text obeys that ban too.
- One git command per Bash call — compound commands (`&&`, `;`, pipes into
  further git) may be refused by the permission rules. Never prefix it with
  `cd <dir> &&` (Claude Code asks before every `cd` + `git` compound, whatever
  the allow rules say); for another repo use `git -C <dir> ...`.

## Workflow

### 1. Scope — one round of questions

Before reading any diff, look around (current branch, local and remote-tracking
branches, submodules, directories with their own `.git` inside the working
tree) and parse the arguments for source and base. Then ask everything that is
still open **in one plain chat message** and stop until the user answers:

1. **Source branch** — propose the current branch.
2. **Base branch** — propose the integration branch the project's instructions
   name (e.g. "single branch `main`"); otherwise `develop` if it exists;
   otherwise ask. Never assume `main` / `master` just because it is the default
   branch.
3. **Repos** — list every repo with changes between source and base: the parent,
   each submodule whose pointer moved, each nested repo with a matching branch.
   Ask which of them get an MR. A submodule has its own branches: check the same
   names exist there, otherwise ask for them. A repo with no submodules and no
   nested repos needs no question — just name it.
4. **Tickets** — always ask, as free text: ID and a one-line summary per ticket
   (Jira key, GitHub / GitLab issue `#N`, ...), and which repo it belongs to.
   "none" means no tickets section.

Skip a question only when the arguments or earlier messages already answer it.

### 1a. Pre-MR review gate

If the project's instructions define a review to run before an MR description,
run it now, after the scope is settled and before gathering facts, and follow
their rules on findings (they may stop the skill). Without such a rule, skip
this step.

### 2. Gather the facts (per repo)

- Full commit messages — usually the best source of *why*:
  `git log --reverse --format='=== %h %s%n%b' <base>..<source>`
- File overview: `git diff --stat <base>...<source>` (three dots: changes on the
  source since the merge base).
- Diffs of the public surface: headers / interfaces / exported symbols, API and
  RPC definitions (endpoints, methods, policies), schemas and file formats, CLI,
  config, build files, install rules, CI config, migrations.
- The code behind any claim you are going to make.
- A moved submodule pointer in the parent is the submodule's own MR; the parent
  MR mentions it only as a dependency in Compatibility notes.
- Past MR titles, to match their style: merge commits on the base branch
  (`git log --merges --format='%s%n%b' -20 <base>`; GitLab and GitHub put the
  MR / PR title in the body of the merge commit), or squash commits ending in
  `(#N)`. With neither, follow the style of the base branch's commit titles
  (`git log --no-merges --format=%s -20 <base>`) without their `area:` prefix.

### 3. Verify

- Every statement must be backed by the diff or the code. Commit messages can be
  wrong or stale ("documented X" with no doc file changed, a change reverted
  later in the branch). Leave unconfirmed claims out and report them in chat.
- Describe the **final state of the branch**, not its history. A defect that was
  introduced and fixed within the same branch is not a bug fix of the MR — it is
  part of the feature, or nothing at all. Bug fixes are defects present on the
  base branch.

### 4. Classify

| Change | Goes to |
|--------|---------|
| Capability visible to a user or consumer: new endpoint / method / function family, new device, protocol or format support, new behaviour | **New features** — one item per capability |
| Internal work a feature needed (moved code, shared helper, refactor that enables it) | One sentence **inside that feature**, never its own item |
| Wrong behaviour that exists on the base branch | **Bug fixes** — group related defects into one item |
| Build flags, install rules, packaging, CI jobs, developer tooling targets | **CI / build** |
| Real documentation files changed (not code comments) | **Documentation** |
| Anything that can break a consumer or needs action: changed / removed public signatures, ABI or struct layout, schema / wire format, behaviour changes, new required flags or deps, MRs this one depends on, small new public API (helpers, functions moved between layers) | **Compatibility notes** |
| Version bumps, added or changed logging, refactoring without visible effect, renames, formatting, comment changes, test-only changes | **Leave out** |

There is no Refactoring section and no Tests section.

Describe a change **at its real scope**: when generic code changed while working
on a specific feature, write it generically ("a write-only parameter", not "a
write-only MYCFG parameter").

What is "public surface" depends on the stack. Besides code APIs, think of:
database schemas and views other queries or dashboards read, dashboard
identifiers and variables, ports and service config, setup / install script
flags, environment variables and `.env` keys, and **steps a deployed instance
needs** after the merge (re-run setup or an update command, migration, backfill,
re-import, client re-setup) — those go to Compatibility notes.

Changes to the repo's own AI-assistant setup (agent / skill definitions,
assistant context docs) are not part of the product: leave them out unless the
branch is only about them; then they go to **Documentation**.

### 5. Write

Sections, in this order; omit empty ones:

```markdown
## Jira tickets            <- name the tracker the user uses; only if tickets were given

This MR closes the following tickets:

- **ID** — one-sentence summary.
  (GitHub / GitLab issues: `- Closes #N — summary.`, so the issue is linked
  and closed on merge.)

## New features
## Bug fixes
## CI / build
## Documentation
## Compatibility notes
```

Items:

- Feature: `- **Bold lead-in.** ...` — the motivation in one sentence when it is
  not obvious (what could not be done, for whom), then what it does. One short
  paragraph, at most ~6 lines; a nested list only for peer things (e.g. a few new
  methods). A small fenced example only when it shows a new reply / format
  better than prose.
- Bug fix: `- **What was broken** — consequence; the fix.` One or two sentences.
- Compatibility note: `- **Kind:** ...` (signature change, struct layout,
  schema, behaviour, build, dependency).
- Identifiers in backticks, functions with `()`, TCP/RTU-style twins as `_xxx()`
  or `foo()` / `_bar()` as the project writes them. Wrap at ~80 columns.
- No implementation walkthroughs (internal call chains, private fields, file by
  file), no commit hashes, no test counts.
- Length: a large branch ends up about the size of
  `references/libmydev-support-mycfg.md`; a small MR can be five lines.

File: `<project root>/claude-context/merge-requests/<repo>-<source-branch>.md`
(a `/` in the branch name becomes `-`). If `claude-context/` is tracked by the
repo, the folder must be git-ignored (`git check-ignore -q <path>`); if it is
not, say so and give the user the `.gitignore` line instead of writing a file
git would pick up. If the project has no `claude-context/`, ask where to write.
If the file exists, read it first — the user may have edited it — and ask
before replacing it.

The title is not part of the file.

### 6. Report in chat

Short, not the description itself:

- the file path(s);
- a title per MR: imperative, the main capability, ≤ ~70 characters, in the style
  of the repo's past MR titles; plus a narrower alternative when the MR mixes
  topics;
- claims from commits that the code did not confirm;
- things deliberately left out that the user might want back;
- open questions.

### 7. Revisions

Apply the user's corrections to the file. When a correction is a general style
rule (it would apply to other MRs too), offer to add it to this SKILL.md, phrased
project-independently; add it only after the user agrees.

## References

Read before writing. They show tone, density and format only — never copy their
content or project terms.

Real MRs from the user's other repos with names replaced (`mydev`, `MYCFG`,
`PROJ-`); the domain is embedded C, the style applies to any stack.

- `references/libmydev-support-mycfg.md` — the preferred density for a large
  library branch: features with folded-in internals, grouped bug fixes, API/ABI
  compatibility notes.
- `references/mydev-manager-support-mycfg.md` — a service with new RPC
  methods, a reply format example, CI / build and behaviour-change notes, a
  dependency on another repo's MR.
- `references/libmydev-mycfg-rtu-older-style.md` — a full MR with a tickets
  section. Older style: its Refactoring and Tests sections are no longer used,
  and its items are longer than now preferred.
