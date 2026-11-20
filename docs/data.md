# Data and privacy

This page lists what the clients send, what the server keeps and what it throws away, where the
data lives, how to stop sending your prompts and how to delete what is stored. It describes
Claude Code 2.1.323 with the settings the client script writes.

!!! warning "The data is personal"
    The stack stores your prompts, file paths and account e-mail. Run it only on a PC and a
    network you trust. If the sessions are work sessions, check that your employer allows the
    data to go to this server before you connect a PC.

---

## What Claude Code sends

| Group | What | Depends on |
| --- | --- | --- |
| Prompts | The text of your prompts (`user_prompt.prompt`) | `OTEL_LOG_USER_PROMPTS=1`, which the client script sets |
| Claude's replies | The full text of the replies (`assistant_response.response`) | The same switch: there is no separate one. The server drops it, see below |
| Tool parameters | File paths, search patterns and Bash commands. Not file contents and not tool output: only their size in bytes (`tool_result_size_bytes`) | `OTEL_LOG_TOOL_DETAILS=1`, which the client script sets |
| Usage | Model, tokens (cache included), cost, durations, time to first token, effort, subagent and skill names, permission decisions, hook timings | Always |
| API errors | The HTTP status and the error message of a failed request | Always |
| Metrics | Tokens, cost, lines of code changed, active time | Always |
| Identity | Account e-mail, account and organization IDs, plan (`pro`, ...), session and prompt IDs, OS version, and the `host` and `project` that the client script puts into `OTEL_RESOURCE_ATTRIBUTES` | Always |

The `project` shown in the dashboards is not sent as such. When you set no label, the server
works it out from the file paths of the tool calls and from the working directory that the
session hook sends, see [Project](clients.md#project).

### The session hook

The client script also installs a hook that sends, once per session and when something changes,
to port `4318`:

- the session title and the git branch;
- the first working directory, which contains your OS user name;
- the Claude Code version.

It reads them from the local session files. It never reads or sends your prompts or Claude's
replies. To remove it, run the client script with `-NoSessionMeta` (Windows) or
`--no-session-meta` (Linux), see [Undo](clients.md#undo).

---

## What the server drops

The collector deletes the `response` attribute, Claude's reply text, from every log event before
it is stored (`attributes/drop_response` in `otel-collector.yaml`). The dashboards do not use
it. The length of the reply (`response_length`) stays. Everything in the table above is stored
as it arrives, with no other filter.

---

## Where the data lives

- **The telemetry stays on the server PC.** The collector writes every event to ClickHouse (`otel.otel_logs`
  and the metrics tables), which keeps it in the Docker volume `clickhouse-data`. The
  collector has no other exporter: nothing is forwarded to another server.
- **What Grafana contacts by itself.** The stack does not change Grafana's defaults, so Grafana
  sends anonymous usage statistics and checks grafana.com for updates, and the ClickHouse plugin
  is downloaded from grafana.com on the first start. This traffic has no prompts or events in
  it. The server therefore needs internet access on the first start and is not fully offline.
- **Reachable from the LAN only if you allowed it.** On a Windows server, Grafana is
  published on `localhost` only and the OTLP ports are open to the LAN only after
  `-EnableLan`. On a Linux server all three ports are open to the LAN unless you pass
  `--local-only`. See [the server page](server.md). OTLP has no authentication and Grafana is
  plain HTTP: use LAN mode on a trusted network only.
- **For as long as you keep it.** The stack sets no retention, see
  [Disk use and retention](maintenance.md#disk-use-and-retention). Claude Code deletes its
  own session files after about 30 days; the server keeps the history longer.
- **In backups.** A dump from `linux-server-tools/backup.sh` holds all of it, prompts included,
  in `backup/`, see [Back up and restore](maintenance.md#back-up-and-restore).
- **Shown in Grafana.** Everyone who can log in to Grafana sees the prompts, paths and e-mails
  of every connected PC. The prompt text shows on **Sessions** and **Prompts**.

---

## Prompt logging

The client script always sets `OTEL_LOG_USER_PROMPTS` to `1`. Without it the prompt text is not
sent: the prompt columns in the dashboards are empty or `<REDACTED>`, and the rest keeps working,
because costs, tokens and tool calls do not need the text.

| You want to | Do this on the client |
| --- | --- |
| Stop sending prompts | In `env` of `settings.json` (`%USERPROFILE%\.claude\settings.json` on Windows, `~/.claude/settings.json` on Linux) set `OTEL_LOG_USER_PROMPTS` to `0` or delete the key. Restart the Claude Code sessions |
| Send them again | Set it to `1` and restart the sessions |
| Also stop sending paths and commands | Do the same with `OTEL_LOG_TOOL_DETAILS`. The project guess and some panels that use file paths then stay empty |

!!! warning "The client script puts the value back"
    The script rewrites its own keys on every run, so after you turn prompt logging off, a
    re-run of `setup-client.ps1` or `setup-client.sh` sets `OTEL_LOG_USER_PROMPTS` to `1` again.
    Change the value again after each run. The script has no option for it.

Prompts that were already sent stay stored. Turning the switch off does not delete them.

---

## Delete data

The repo has no command that deletes part of the data, such as one PC or one session. What it
supports is removing everything and starting empty.

!!! warning "This cannot be undone"
    Dump first if you may want the data back: `bash linux-server-tools/backup.sh dump` (with
    `wsl -d Ubuntu --` in front when Docker runs in WSL), see
    [Back up and restore](maintenance.md#back-up-and-restore). The dump then holds the prompts
    you wanted to remove, so delete it too once you do not need it.

1. Stop the clients from sending, or the new events fill the stack again: see
   [Undo](clients.md#undo) and the table above.
2. On the server, from the `cc-telemetry` folder, remove the stack together with its volumes
   (add `wsl -d Ubuntu --` in front when Docker runs in WSL):

    ```bash
    docker compose down -v
    ```

    This deletes `clickhouse-data`, and Grafana's own database with it.
3. Run the server script again. It starts a stack with empty tables and keeps `.env`.
4. Delete the folders in `backup/` that you no longer need, the `pre-update-*` folders that
   `--update` writes included.

Stopping the stack without `-v` deletes nothing, see
[Stop and remove the stack](maintenance.md#stop-and-remove-the-stack).
