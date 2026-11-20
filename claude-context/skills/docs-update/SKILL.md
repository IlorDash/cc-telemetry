---
name: docs-update
description: Bring the public user docs of cc-telemetry — the bilingual guide site (docs/<page>.md + .ru.md twin) and the short README.md — up to date with the code after a feature, branch, fix or behaviour change, in the voice, density and page shapes the docs already use. Use when the user asks to document a change, update or audit the guide, the site or the README, or types /docs-update. Verifies every statement against the code (scripts, compose, collector, views, dashboards), runs the strict MkDocs build and check-readme.py. Never changes git state.
argument-hint: "[<base>..<branch> | feature name]"
---

# Docs update (guide site and README)

The user docs of cc-telemetry are public, for people who install the stack on their own PCs:

- the **guide site** — MkDocs Material, `docs/<page>.md` (English) + `docs/<page>.ru.md`
  (Russian twin), published to GitHub Pages from `main`; the detailed docs;
- **`README.md`** — intro, data flow, quick start, links to the site.

This skill brings them in step with the code so the new text reads as if the same author wrote
the whole guide.

## Hard limits

- **Read-only git only:** `status`, `log`, `diff`, `show`, `ls-files`, `grep`, `blame`,
  `rev-parse`, `branch --show-current`, also with `-C <dir>`. One git command per Bash call,
  never prefixed with `cd <dir> &&`.
- **The code is the reference.** Commit messages, PR texts, `claude-context/` docs and the
  docs themselves can be wrong. Every behaviour you write down is one you read in the code (or saw
  on the live stack). What you cannot confirm stays out and is reported in chat.
- **Public files:** nothing about the user's own PCs, IPs, networks, Windows edition or projects
  (`claude-context/server-state.local.md` is private). No mention of the AI setup
  (`claude-context`, agents, skills, the ledger) and no attribution. Claude Code's own
  `CLAUDE.md` and `~/.claude/settings.json` are product features and may be explained.
- Never read `.env` or `backup/`; name a setting (`GRAFANA_ADMIN_PASSWORD`), never a value.
- Only `docs/*.md`, `README.md`, and `mkdocs.yml` `nav` / `nav_translations` (for a new page)
  change. A screenshot, CSS, the build config or a change in code is reported, not made.
- Project instructions (`CLAUDE.md`, `claude-context/guides/docs-writing.md`) win over this file.

## Workflow

### 1. Scope
What to document: the current branch against its base, plus uncommitted changes —
`git log --reverse --no-merges --format='=== %h %s%n%b' <base>..HEAD`, `git diff --stat
<base>...HEAD`, `git status --short`. The base is the branch the PR goes into: an argument, else
`develop`. A named feature narrows it. In a parallel-task worktree run everything with
`git -C <wt>` and edit the files under `<wt>`.

### 2. Learn the docs — every run, never from memory
Read the `nav` in `mkdocs.yml` (index, server, clients, dashboards, tips, maintenance,
troubleshooting, data, release notes), then each page the change touches in **both** languages,
the README (intro, How the data flows, Quick start, links), the terms they use (reuse them; never
a synonym for something the guide already names), then
[references/style-guide.md](references/style-guide.md) and the page → source map in
`claude-context/modules/docs-site.md`.

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
| Observed behaviour, versions | the live stack (`claude-context/guides/verification.md`), never a guess |

Every failure path of a changed step: its exact message (the script's `Write-Host` / `echo`
text) and what the reader does next. Grep `docs/` and the README for every identifier the change
touches — those statements may now be false, in both languages.

### 4. Impact map

| Change | Page(s) |
| --- | --- |
| New or changed script option or step | `server` or `clients` (option table, steps); `troubleshooting` for its failures |
| New port, bind or firewall behaviour | `server`, `index`; README quick start |
| New dashboard, panel, variable or link | `dashboards` (that dashboard's table); the `index` table for a new dashboard |
| `cc.tips` rule | `tips` |
| New `.env` key or image tag | `maintenance` |
| Attribute newly collected or dropped | `data` — always |
| New failure the reader can hit | `troubleshooting` row: `Message` / `Cause` / `What to do` |
| New version | a `release-X-Y-Z` page (EN + RU) + `nav` entry, newest first, with the `<!-- unreleased` marker until the release |
| New page | `nav`; `nav_translations` when its title differs in Russian |
| Quick-start command, requirement or port | `README.md` |

Every change to an English page goes into its `.ru.md` twin in the same place.

### 5. Write
Follow the style guide. Keep edits local: do not reflow or reword paragraphs you are not
changing. List continuations are indented 4 spaces.

### 6. Verify
```
.venv/Scripts/python.exe -m mkdocs build --strict
py -3 claude-context/skills/docs-update/scripts/check-readme.py --root . [--forbid <regex>]...
py -3 claude-context/skills/docs-update/scripts/check-readme.py --root . --file docs/<page>.md [--forbid <regex>]...
```
The strict build must exit 0 with no warnings: it owns links and anchors on the site (if
`check-readme.py` disagrees on an anchor in `docs/`, the build wins). `check-readme.py` checks
relative links, repo paths in backticks and banned words — outside fenced code blocks only, so read
the fences you touched yourself; run it on the README and on every page you changed. Pass the
user's PC names, IPs and project names from `server-state.local.md` as `--forbid` patterns on
the command line (never write them into a file). It must print `OK`. Also re-read every command
you added: copy-pasteable, from the repo root, PowerShell for Windows and bash for Linux.
No `.venv`: `py -3 -m venv .venv` and `.venv\Scripts\python.exe -m pip install -r docs/requirements.txt`.

### 7. Report in chat
- First line: branch and base documented.
- Pages changed (EN + RU), one line each: what they now say that they did not before.
- Statements from commits the code did not confirm; behaviour that looks like a bug.
- Open questions, anything you chose not to document, screenshots that are now outdated.

### 8. Revisions
Apply corrections. When a correction is a general style rule, offer to add it to
`references/style-guide.md`; add it only after the user agrees.
