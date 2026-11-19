---
name: docs-update
description: Bring the public README.md of cc-telemetry up to date with the code after a feature, branch, fix or behaviour change — in the voice, density and section shapes the README already uses. Use when the user asks to document a change, update or audit the README, or types /docs-update. Verifies every statement against the code (scripts, compose, collector, views, dashboards), runs check-readme.py. Never changes git state.
argument-hint: "[<base>..<branch> | feature name]"
---

# Docs update (README)

The user guide of cc-telemetry is one file: `README.md` at the repo root, public, English, for
people who install the stack on their own PCs. This skill brings it in step with the code so the
new text reads as if the same author wrote the whole file.

## Hard limits

- **Read-only git only:** `status`, `log`, `diff`, `show`, `ls-files`, `grep`, `blame`,
  `rev-parse`, `branch --show-current`, also with `-C <dir>`. One git command per Bash call,
  never prefixed with `cd <dir> &&`.
- **The code is the reference.** Commit messages, PR texts, `claude-context/` docs and the
  README itself can be wrong. Every behaviour you write down is one you read in the code (or saw
  on the live stack). What you cannot confirm stays out and is reported in chat.
- **Public file:** nothing about the user's own PCs, IPs, networks, Windows edition or projects
  (`claude-context/server-state.local.md` is private). No mention of the AI setup
  (`claude-context`, agents, skills, the ledger) and no attribution. Claude Code's own
  `CLAUDE.md` and `~/.claude/settings.json` are product features and may be explained.
- Never read `.env` or `backup/`; name a setting (`GRAFANA_ADMIN_PASSWORD`), never a value.
- Only `README.md` changes. A screenshot, a new doc file or a change in code is reported, not made.
- Project instructions (`CLAUDE.md`, `claude-context/guides/docs-writing.md`) win over this file.

## Workflow

### 1. Scope
What to document: the current branch against its base, plus uncommitted changes —
`git log --reverse --no-merges --format='=== %h %s%n%b' <base>..HEAD`, `git diff --stat
<base>...HEAD`, `git status --short`. The base is the branch the PR goes into: an argument, else
`main`. A named feature narrows it. In a parallel-task worktree run everything with
`git -C <wt>` and edit `<wt>/README.md`.

### 2. Learn the README — every run, never from memory
Read the whole file: the section order (intro → 1. Server → 2. Clients → 3. Dashboards → Tips →
4. Maintenance → 5. Troubleshooting → Verified on first deployment → What is sent), the contents
line, the terms it uses (Reuse them; never a synonym for something the README already names),
then [references/style-guide.md](references/style-guide.md).

### 3. Gather the facts
The code behind each change, by kind:

| Fact | Read it from |
| --- | --- |
| Server setup steps, options, prompts, defaults | `setup-server.ps1`, `setup-server.sh`, `linux-server-tools/*.sh` |
| Client setup steps, options, files written | `client/setup-client.ps1`, `client/setup-client.sh`, `client/*.json`, the session-meta hook files in `client/` |
| Ports, bind addresses, image tags, `.env` keys | `docker-compose.yml`, `.env.example`, `otel-collector.yaml` |
| What is sent / dropped | `otel-collector.yaml` processors, `client/*.json` env keys, `clickhouse/views.sql` |
| Dashboards, panels, variables, links | `grafana/dashboards/*.json`, `grafana/rail/` |
| Tips (category, threshold, link) | `cc.tips` in `clickhouse/views.sql` |
| Verified versions | the live stack (`claude-context/guides/verification.md`), never a guess |

Every failure path of a changed step: its exact message (the script's `Write-Host` / `echo`
text) and what the reader does next. Grep the README for every identifier the change touches —
those statements may now be false.

### 4. Impact map

| Change | Section |
| --- | --- |
| New or changed script option or step | 1a/1b (server) or 2a/2b (client), and the option table there |
| New port, bind or firewall behaviour | intro paragraph of 1. Server, 1a/1b, Troubleshooting |
| New dashboard, panel, variable or link | 3. Dashboards (the dashboard's table), Tips for `cc.tips` |
| New `.env` key or image tag | 1b / 4. Maintenance; "Verified on first deployment" only for a re-verified deployment |
| Attribute newly collected or dropped | **What is sent** — always |
| New failure the reader can hit | 5. Troubleshooting row: `Symptom | What to check` |
| New section | the contents line under the intro |

### 5. Write
Follow the style guide. Keep edits local: do not reflow or reword paragraphs you are not
changing (the README keeps one sentence per line in places — match the paragraph you edit).

### 6. Verify
```
py -3 claude-context/skills/docs-update/scripts/check-readme.py --root . [--forbid <regex>]...
```
It checks in-page anchors, relative links, repo paths in backticks and banned words — outside
fenced code blocks only, so read the fences you touched yourself. Pass the
user's PC names, IPs and project names from `server-state.local.md` as `--forbid` patterns on
the command line (never write them into a file). It must print `OK`. Also re-read every command
you added: copy-pasteable, from the repo root, PowerShell for Windows and bash for Linux.

### 7. Report in chat
- First line: branch and base documented.
- Sections changed, one line each: what they now say that they did not before.
- Statements from commits the code did not confirm; behaviour that looks like a bug.
- Open questions, and anything you chose not to document.

### 8. Revisions
Apply corrections. When a correction is a general style rule, offer to add it to
`references/style-guide.md`; add it only after the user agrees.
