# README style guide

How `README.md` is written. The README as it stands wins where it differs — match the file, not
this guide. The short rule set is in `claude-context/guides/docs-writing.md`; this file adds the
shapes.

## Reader and voice

The reader installs the stack on their own PCs or reads a dashboard. They have one task.

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
- A setup section: one or two sentences of what it does → the command in a fenced block →
  what it prints or changes → its options as a table.
- Say a thing once, in the section that owns it; elsewhere, link to it
  (`see [1b](#1b-server-on-linux)`).

## Markup

| Thing | Markup | Example |
| --- | --- | --- |
| Command, path, file, option, env var, value, port, view, column | `` `code` `` | `-EnableLan`, `cc.sessions` |
| Panel, dashboard, button, menu in Grafana | plain text with the exact label | Efficiency, Cache hit rate by project |
| A whole command to run | fenced block, `powershell` or `bash` | |
| Link to another section | `[text](#slug)` (GitHub slug: lowercase, punctuation dropped, spaces → `-`) | `[2. Clients](#2-clients-every-pc)` |

- Tables use `| --- |` separators (the user's markdownlint).
- Commands are copy-pasteable from the repo root; placeholders as `<SERVER_IP>`.
- Never a literal value of a secret; name the `.env` key.

## Section shapes

**Setup section (1a, 1b, 2a, 2b)** — "Requirements" as a short list → one fenced block with the
command variants, each with a trailing `# what this variant adds` comment → "The script:" and a
numbered list of what it does, in the order it does it: lowercase items ending with `;`, the
last with `.` → notes on re-running and on options that need more than a comment.

**Dashboards (3)** — a `Dashboard | Shows` table, then per dashboard what it answers and its
notable panels; drill-down links named by the panel they start from and the dashboard they open.

**Tips** — one table (`Category | Fires when (grouped by) | What to do | Link opens`), one row per
`cc.tips` category, thresholds exactly as in the view.

**Troubleshooting (5)** — one table `Symptom | What to check`. The symptom is what the reader sees
(the message text in backticks); the check names the command or setting and the fix.

**What is sent** — an `Observed with Claude Code X.Y.Z ...` line, then bullets with a bold lead
(**Text**, **Tool arguments**, **Usage**, **Identity**, **Session hook**) naming the attributes and
the env var that turns each on; what the collector drops and why; where it is stored. A change to
collected or dropped data always updates it.

**Verified on first deployment** — generic facts only (versions, behaviour seen), dated in the
heading; no PC names or editions of the user's machines.
