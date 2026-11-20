# Doc-writing rules

How to write the AI context docs, the site pages and the README.

**AI context docs (`claude-context/`)** — dense, AI-oriented reference: compact tables, fenced
ASCII flow diagrams, short "do not do this" callouts; no narrative prose, no marketing.
~60–150 lines per module file; split rather than bloat. Each module file: one-line purpose, a
**Files** table (path → role), then content. Record *why* and non-obvious behaviour — what
Claude Code actually sends, which service owns what, what is exposed, what happens on failure,
what was verified and on which version — not what a name already says. Repo-root-relative paths
in backticks. **Bugs and unverified behaviour only in `pending-bugs.md`**; a module may at most say
"see pending-bugs.md". **Observed facts** (what a Claude Code version sent, how Windows/WSL
behaved) are authoritative: write them with their source (`observed on Claude Code 2.1.323,
<date>`), never invent them. English. **No personal data** in tracked files — PC names, IPs, user
names, networks, the user's other projects go to `server-state.local.md` (git-ignored).

**Public docs (site pages and README)** — general instructions only: nothing specific to the
user's PCs (Windows edition they run, their virtualisation setup, their IPs or projects), no
mention of the AI setup. Describe behaviour, not features. Every failure gets an outcome: what
the reader does next. Second person, present tense, active voice; one fact per sentence;
paragraphs of 1–4 sentences. No marketing words (simply, just, easily, powerful, seamless), no
hedging, no meta text. Identifiers, paths, commands, options in backticks. Commands are
copy-pasteable from the repo root (PowerShell for Windows, bash for Linux). Markdown tables use
`| --- |` separators (the user's markdownlint).

**Site pages (`docs/<page>.md` + `docs/<page>.ru.md`)** — the detailed user guide; which page
owns which code: the page → source map in `modules/docs-site.md`.

- Tables over prose; titled admonitions (`!!! note "Title"`); ~95-column wrap; list
  continuations indented **4** spaces (3 breaks the list).
- Dashboard and panel titles in **bold**, exactly as in the JSON.
- The `.ru.md` twin has the same headings in the same order, idiomatic Russian; dashboard, panel,
  rail and variable titles and options are quoted as on the **Russian copy**
  (`grafana/dashboards/ru/*.json`), screenshots come from the Russian copies
  (`docs/assets/ru/`). Grafana's own UI (`All`, menus), script options and messages stay in
  English verbatim. Russian links point at Russian anchors.
- A change to collected or dropped attributes always updates `data`; a new failure the reader
  can hit gets a row in `troubleshooting`; a new page gets a `nav` entry and, when its title
  differs in Russian, a `nav_translations` entry.
- Screenshots only from the demo stack (`tools/docs-demo/`), never from the live stack; each
  image links to its full-size file.
- A new version gets a release-notes page with the `<!-- unreleased` marker until its release.
- `mkdocs build --strict` must exit 0 with no warnings.

**README** — intro, data flow, quick start, links to the site. Change it only when the quick-start
commands, requirements or ports change; details go to the site.

Page shapes and the docs check: `skills/docs-update/` (`references/style-guide.md`,
`scripts/check-readme.py`); a user-requested update or audit of the site or README runs as
docs-auditor.
