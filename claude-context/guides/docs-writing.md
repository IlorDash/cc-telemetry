# Doc-writing rules

How to write the AI context docs and the README.

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

**README (public, for people, English)** — general instructions only: nothing specific to the
user's PCs (Windows edition they run, their virtualisation setup, their IPs or projects).
Describe behaviour, not features. Every failure gets an outcome: what the reader does next.
Second person, present tense, active voice; one fact per sentence; paragraphs of 1–4 sentences.
No marketing words (simply, just, easily, powerful, seamless), no hedging, no meta text.
Identifiers, paths, commands in backticks. Commands are copy-pasteable PowerShell from the repo
root. Keep in step with the code: the scripts' steps and options, the troubleshooting table,
"What is sent" (any change to collected or dropped attributes), "Verified on first deployment"
(generic facts only). Markdown tables use `| --- |` separators (the user's markdownlint).
