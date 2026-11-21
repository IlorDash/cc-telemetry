# Commit messages (the user commits; you only draft)

**Draft a commit message only when the user directly asks for one.** Never on your own initiative
— not at the end of a feature, a fix or a claude-context change, and no subagent does either.

Linux-kernel style ([describe your changes](https://www.kernel.org/doc/html/v4.19/process/submitting-patches.html#describe-your-changes)).
The repo has no `.gitlint`, so the checker applies the gitlint defaults; write drafts that also
pass these rules:

| Rule | Requirement |
| --- | --- |
| title | `area: Summary`, ≤ 65 chars, no trailing punctuation, no surrounding spaces or tabs |
| blank line | between title and body |
| body lines | ≤ 79 chars; lines with a URL are exempt; no tabs |
| trailers | **none** — no `Signed-off-by:`, `Co-Authored-By:`, "Generated with" |
| Markdown | none — no backticks, headings, bold; identifiers as-is |

**Title** — `area: Summary`:
- `area` = the touched component: `views` (`clickhouse/`), `dashboard`, `collector`, `compose`,
  `grafana` (provisioning), `setup-server`, `setup-client`, `wsl`, `README`, `claude-context`,
  `git` (`.gitignore`, `.gitattributes`). Nested areas chain: `dashboard: Sessions: ...`.
- Summary starts with a capitalised imperative verb: Fix, Add, Remove, Update, Rename, Move,
  Support, Improve, Refactor, Set, Bump, Enable, Hide, Drop.
- One logical change per commit: if the staged set mixes unrelated changes, say so and offer
  separate messages.

**Body** — omit only for self-explanatory changes. Otherwise:
1. Why first: the problem or motivation and its consequence (what broke, for whom, how).
2. Then what the commit does, imperative or "so ..." form.
3. Secondary changes in a separate paragraph starting with `Also ...`.
- Lists: two-space indent + `- `, items end with `;` (last with `.`).
- Code or commands: on their own lines, indented 2–4 spaces, blank line before and after.
- References: `[1]` in the text, `[1] <URL>` lines at the end.

Example:
```
dashboard: Hide sessions without prompts or requests

Every VS Code window reload starts Claude Code processes that report only
startup events under their own session id, so the Sessions table and the
Session variable filled up with empty rows.

Filter both by prompts > 0 OR tokens > 0. The data stays in the database.
```

Drafts go into a scratchpad file (`commit-cc-telemetry-<area>.txt`), checked with
`py -3 claude-context/skills/commit-message/scripts/check-msg.py <file> --repo .` (`python3` on
Linux), so the user
can run `git commit -F <file>`. The `commit-message` skill does exactly this.
