# Guide style (site pages and README)

How the guide site (`docs/<page>.md` + `.ru.md`) and `README.md` are written. The pages as they
stand win where they differ — match the page, not this guide. The short rule set is in
`claude-context/guides/docs-writing.md`; this file adds the voice details and the page shapes.

## Reader and voice

The reader installs the stack on their own PCs, reads a dashboard or has something broken. They
have one task.

- **Describe behaviour, not features.** Not "supports LAN access", but "`-EnableLan` opens ports
  4317 and 4318 in the Windows firewall and forwards them from the LAN IP to WSL".
- **Every failure gets an outcome:** what the reader checks or runs next.
- **Give the reason when it changes what the reader does**, in one clause: "Re-run the client
  script after the server's IP changes: the address is written into `settings.json`."
- No marketing words (simply, just, easily, powerful, seamless), no hedging, no meta text
  ("this section describes ...").
- Second person, present tense, active voice.

## Density

- One fact per sentence, 10–25 words. Paragraphs of 1–4 sentences.
- Tables over prose for anything enumerable: options, panels, messages, ports, env keys.
- Say a thing once, on the page that owns it (the page → source map in
  `claude-context/modules/docs-site.md`); elsewhere, link to it.

## Markup

| Thing | Markup | Example |
| --- | --- | --- |
| Command, path, file, option, env var, value, port, view, column, message | `` `code` `` | `-EnableLan`, `cc.sessions` |
| Grafana dashboard, panel, variable, button — exactly as in the JSON | `**bold**` | **Efficiency**, **Cache hit rate by project** |
| A whole command to run | fenced block, `powershell` or `bash` | |
| Link to another page | relative file + anchor | `[Ports](server.md#ports-and-access-on-linux)` |
| Keyboard keys | `++ctrl+c++` | |

- Wrap prose at ~95 columns; table rows are exempt. `---` between major sections on long pages.
- List continuations (a paragraph or fence inside a list item) are indented **4** spaces.
- Tables use `| --- |` separators (the user's markdownlint).
- Commands are copy-pasteable from the repo root; placeholders as `<SERVER_IP>`.
- Never a literal value of a secret; name the `.env` key.
- Images: `[![alt](assets/x.png)](assets/x.png)` — the image links to its full-size file; alt
  text says what the screenshot shows. Only demo data (`tools/docs-demo/`).

## Admonitions

Always titled; an untitled one renders as a bare box that tells the reader nothing.

| Kind | Use |
| --- | --- |
| `!!! warning "If it fails"` (or another title) | failures closing a procedure, risks |
| `!!! note "…"` | a consequence that will surprise someone, a requirement |
| `!!! tip "…"` | helpful but not required |
| `!!! info "…"` | status of the document itself, e.g. the unreleased banner |

## Page shapes

**`index`** — what the stack is in two sentences, How the data flows, What the dashboards answer
(`Dashboard | Question it answers` + a screenshot), Supported platforms, **Where to start**
routing each reader to one page (install, connect a PC, read dashboards, something failed,
release notes).

**`server`, `clients`** — Before you start (a requirements table per OS) → numbered steps per OS
with the command in a fenced block → an option table per OS (`Option | What it does`) → what the
script does (`Step | Windows | Linux`) → how to check that it works → If it fails, linked to
`troubleshooting`.

**`dashboards`** — the rail, the variables (and the panels that ignore them), the time range,
clicks; then one section per dashboard: **Question:** line, screenshot, a
`Panel | Shows | Click` table, the terms the panels use.

**`tips`** — what a tip is, then one table row per `cc.tips` rule, thresholds exactly as in the
view, what the affected tokens and cost mean, which panel a tip opens.

**`maintenance`** — one section per task (check, update, roll back, back up / restore, recreate
the views, change a setting, stop / remove), each as numbered steps with the commands.

**`troubleshooting`** — opens with What to include in a report; then sections by step (Server
install, Client, No data in Grafana, Dashboards, Update) with tables
`Message | Cause | What to do` (or `Symptom | …` where nothing is printed) or numbered checks.
Messages verbatim from the scripts.

**`data`** — what Claude Code sends and the server keeps, what the collector drops and why,
where the data lives, what Grafana contacts by itself, prompt logging on/off, deleting data. A
change to collected or dropped data always updates it.

**`release-X-Y-Z`** — `# Version X.Y.Z`, a date line `*Released 19 November 2026.*` (or the
`<!-- unreleased` marker + `!!! info` banner while in preparation), then sections chosen from
What's new / Fixed / Improvements / Data and privacy; each item a bold lead and the behaviour,
linking into the guide. Newest first in `nav`.

**`README.md`** — intro, How the data flows, Quick start (server and client, Windows and Linux,
minimal commands), links to the site in English and Russian. No details that live on the site.

## Russian twins

- Same page set, same headings in the same order, so the language switcher lands in the same
  place and a missing update shows as a structural difference. Idiomatic Russian, same level of
  detail — not a word-by-word rendering.
- Dashboard, panel, rail, column and variable titles and options are quoted exactly as on the
  **Russian copy** of the dashboard (`grafana/dashboards/ru/*.json`, built from
  `grafana/i18n/ru.json`) — the reader of a Russian page uses the Russian dashboards. Screenshots
  on Russian pages come from the Russian copies (`assets/ru/<name>.png`).
- Grafana's own UI (`All`, menus, the time picker), script options and script messages stay in
  English verbatim; the explanation next to them is in Russian.
- Links into Russian pages use the Russian anchors (`--strict` catches a wrong one).
- Russian typography: «…» for quoted names, em dash — with spaces, `ё` where it is written.
- Both files change together, in the same commit.
