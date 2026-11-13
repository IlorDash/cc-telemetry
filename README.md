# cc-telemetry — local Claude Code usage statistics

```text
PC-1, PC-2, …  Claude Code ──OTLP gRPC :4317──►  server PC (Docker)
                                                 OTel Collector → ClickHouse → Grafana :3000
```

Everything stays on your LAN. Claude Code exports the events itself, so client PCs need no extra software, only settings.
Claude Code **2.1.310 or newer** is required: older versions do not put `agent_id` on tool events.

Setup is two scripts: [setup-server.ps1](setup-server.ps1) once on the server PC, [client/setup-client.ps1](client/setup-client.ps1)
on every PC whose sessions you want to see (the server PC included). Both are safe to re-run.

Contents: [1. Server](#1-server-one-pc) · [2. Clients](#2-clients-every-pc) · [3. Dashboard](#3-dashboard) ·
[4. Maintenance](#4-maintenance) · [5. Troubleshooting](#5-troubleshooting) · [What is sent](#what-is-sent)

## 1. Server (one PC)

### Requirements

One of:

- **Docker Desktop** (WSL2 backend), which needs Windows 10 22H2 (build 19045) or Windows 11. Start it before running the script.
- **Older Windows 10**: WSL2 with an Ubuntu distro and systemd enabled (`[boot]` / `systemd=true` in `/etc/wsl.conf`).
  The script installs Docker Engine inside it; Docker Desktop is not needed.

Internet access is needed on the first start (images and the Grafana ClickHouse plugin are downloaded).

### Run

```powershell
cd cc-telemetry
powershell -ExecutionPolicy Bypass -File .\setup-server.ps1               # this PC only
powershell -ExecutionPolicy Bypass -File .\setup-server.ps1 -EnableLan    # + accept data from other PCs (asks for admin via UAC)
```

The script:

1. finds Docker: Docker Desktop, or Docker Engine in WSL (offers to install it there if missing);
2. creates `.env` with random passwords (an existing `.env` is kept);
3. starts the stack and waits until the `cc.*` views are created;
4. checks Grafana (`localhost:3000`) and the OTLP port (`localhost:4317`);
5. WSL only: WSL stops a distro ~15 s after the last Windows-started process exits, which would stop the stack.
   The script runs a hidden keepalive and adds it to the Startup folder (no admin rights needed);
6. with `-EnableLan`: adds a firewall rule for TCP 4317 (Private networks) and, for WSL, a port forward
   from the LAN address to WSL (WSL2 on Windows 10 listens on `localhost` only). Warns if the network is marked Public.

At the end it prints the Grafana address and the ready-to-run client command with the server's LAN IP.

Open `http://localhost:3000`: user `admin`, password `GRAFANA_ADMIN_PASSWORD` from `.env`.
The **Claude Code usage** dashboard is the home page.

Options: `-Mode desktop|wsl` (skip auto-detection), `-Distro <name>` (default `Ubuntu`), `-LanIp <address>`
(if the LAN address is detected wrong), `-Yes` (install Docker into WSL without asking). The OTLP port has no authentication: enable LAN access on a trusted network only.
Best reserve the server's IP in the router's DHCP; if it changes, run `setup-server.ps1 -EnableLan` again.

## 2. Clients (every PC)

Copy [client/setup-client.ps1](client/setup-client.ps1) to the PC (it is the only file a client needs) and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-client.ps1 -ServerIp <SERVER_IP> -Project C:\Projects\ProjA, C:\Projects\ProjB
```

- `-ServerIp`: the server's LAN address (printed by `setup-server.ps1`); `localhost` on the server PC itself.
- `-Project`: the folders you open in Claude Code. Add more later by re-running with other folders.
- `-PcName`: optional, the computer name by default; letters, digits, `.`, `_`, `-`.

The script:

- adds the telemetry keys to the `env` section of `%USERPROFILE%\.claude\settings.json`;
- adds `OTEL_RESOURCE_ATTRIBUTES=project=<folder name>,host=<PC name>` to `<project>\.claude\settings.local.json`
  (created if missing);
- leaves every other key (permissions, model, plugins, …) as it was, saves `<file>.bak` before the first change,
  checks that the result is valid JSON (Windows PowerShell 5.1 re-indents it; the content stays the same);
- tests the connection to `<SERVER_IP>:4317`.

Then:

1. Claude Code must be **2.1.310 or newer** (`claude --version`, otherwise `claude update`).
2. Project settings are read only in a **trusted** folder: if a project was never opened in Claude Code on this PC,
   run `claude` in it once and accept the trust dialog.
3. **Restart running sessions**, settings are read at start: in VS Code *Developer: Reload Window*,
   in the terminal exit and continue with `claude -c`.
4. Make any request. Within 5–10 s the project appears in the **Project** dropdown in Grafana.

Only sessions started after the setup are recorded. Telemetry is sent live: past sessions in `%USERPROFILE%\.claude\projects`
are not uploaded, and events produced while the server is unreachable are dropped after a short retry.

<details>
<summary>Manual client setup (what the script writes)</summary>

`%USERPROFILE%\.claude\settings.json`, **add** to `"env"` (don't replace the section):

```json
"env": {
  "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
  "OTEL_LOGS_EXPORTER": "otlp",
  "OTEL_METRICS_EXPORTER": "otlp",
  "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
  "OTEL_EXPORTER_OTLP_ENDPOINT": "http://<SERVER_IP>:4317",
  "OTEL_LOG_TOOL_DETAILS": "1",
  "OTEL_LOG_USER_PROMPTS": "1",
  "OTEL_LOGS_EXPORT_INTERVAL": "2000",
  "OTEL_RESOURCE_ATTRIBUTES": "project=unknown,host=<PC_NAME>"
}
```

Each project's `.claude\settings.local.json`, add to `"env"`:

```json
"OTEL_RESOURCE_ATTRIBUTES": "project=<project folder name, lower case>,host=<PC_NAME>"
```

- `project` must equal the project folder name (case does not matter): tool-call paths are made relative by it,
  and worktrees `<project>-<name>` fold into the main folder.
- It is one variable for both attributes, so `host` is repeated: the project value fully replaces the user one.

</details>

## 3. Dashboard

The variables at the top are nested: **Project → Session → Actor → Skill** (`All` = no filter).
Clicking a `session_id`, agent name or skill in the tables sets that filter.

| Section | Shows |
| --- | --- |
| Summary | cost, tokens, number of sessions and tool calls under the current filters |
| Sessions | project sessions (first prompt = title), prompts of the selected session |
| Tokens and cost | main / agents / auxiliary requests (`aux:*`, e.g. the session title), cost over time |
| Agents and skills | runs, tokens and tool calls per agent and per skill |
| Tools | tools × actor × skill, Bash commands, rejections (permissions/hooks) |
| Files | top files and directories, accesses by area (`claude-context`, `software`, …), re-reads within a session |
| Hooks | time spent in your hooks |

**Actor**: `main` is the main session, an agent name (`developer`, `Explore`, …) is a subagent, `aux:*` are Claude Code's
own service requests.
**Skill**: a tool call is attributed to a skill through the `request_id` of the model request that carried `skill.name`.
Claude Code does this attribution itself; the label lasts until the end of the prompt in which the skill was invoked.

The refresh rate is picked at the top right (from 5 s), as in any Grafana dashboard.

## 4. Maintenance

With Docker in WSL, prefix these with `wsl -d Ubuntu --` (run from the `cc-telemetry` folder).
Re-running `setup-server.ps1` is also a quick health check.

```powershell
docker compose ps                         # all Up (views-init: Exited (0))
docker compose run --rm views-init        # recreate the views after editing clickhouse/views.sql
docker compose down                       # stop (data stays in the volume)
```

SQL without typing the password (taken from `.env`, never printed):

```powershell
"SELECT event, count() FROM cc.events GROUP BY event" | wsl -d Ubuntu -- bash wsl/ch.sh
```

Backup and restore of all collected data (`backup/` is git-ignored: it contains your prompts):

```powershell
wsl -d Ubuntu -- bash wsl/backup.sh dump              # otel.* tables -> backup\<table>.native
wsl -d Ubuntu -- bash wsl/backup.sh restore           # appends rows: use on a fresh, empty stack
wsl -d Ubuntu -- bash wsl/backup.sh restore <table>   # one table only
```

With Docker in WSL the data lives inside the distro: `wsl --unregister` deletes it. Dump first.

Data is kept indefinitely in the `clickhouse-data` volume. The `cc.*` views are plain (not materialized),
so editing `views.sql` recomputes the whole history.

## 5. Troubleshooting

| Symptom | What to check |
| --- | --- |
| Dashboard is empty | `docker compose logs otel-collector` (ClickHouse errors?), `Test-NetConnection` from the client, `CLAUDE_CODE_ENABLE_TELEMETRY` in `settings.json`, sessions restarted after the setup |
| "Unknown table cc.events" | `docker compose logs views-init`, then `docker compose run --rm views-init` |
| Variable dropdowns are empty | Dashboard settings → Variables → open the variable → Run query → Save |
| ClickHouse plugin does not load | no internet on first start; `docker compose restart grafana` |
| `project = unknown` | no `settings.local.json` with `OTEL_RESOURCE_ATTRIBUTES`, or the folder is not trusted |
| `actor = agent?` | the subagent is still running and its name has not arrived yet, or Claude Code is older than 2.1.310 |
| Stack in WSL is down from time to time | `wsl -l -v` shows `Stopped`: the keepalive is not running; re-run `setup-server.ps1` |
| Port 4317 closed from another PC but open on the server's `localhost` | `setup-server.ps1 -EnableLan` not run, or the server's LAN IP changed (re-run it); network marked Public |
| `setup-client.ps1` cannot be run | run it as shown, via `powershell -ExecutionPolicy Bypass -File …` |

## Verified on first deployment (2026-11-13, Docker Engine 29.9.3 in WSL2, Claude Code 2.1.323)

- Images clickhouse 25.8, otel-collector-contrib 0.135.0, grafana 12.1.0 pull fine; `views-init` exits with 0.
  The collector creates `otel.otel_logs` at startup, so the wait loop in `init-views.sh` usually does not trigger.
- `otel.otel_logs`: `Timestamp DateTime64(9)`, `ServiceName LowCardinality(String)`,
  `ResourceAttributes`/`LogAttributes Map(LowCardinality(String), String)`, as the views expect.
- `grafana-clickhouse-datasource` (4.23.5) installs via `GF_PLUGINS_PREINSTALL_SYNC`; the deprecated `GF_INSTALL_PLUGINS` was removed.
- All 4 variables and 19 panel queries run through `/api/ds/query` without errors; the plugin expands `$__timeFilter`,
  `$__timeInterval`, `$__fromTime`, `$__toTime`. String `query` in variables is supported by the plugin.
- The main session in the VS Code extension reports `query_source = sdk` (same as `claude -p`) and is counted as `main`.
  Custom subagents report `agent:custom` with an `agent_id`. The value for the interactive terminal CLI has not been seen yet
  (expected `repl_main_thread`).
- Session titles (`/rename` → `custom-title`, auto `ai-title`) are **not** in telemetry: they live only in the local
  transcripts `~/.claude/projects/*/<session>.jsonl`. The Sessions table therefore shows the first prompt instead.
- `setup-server.ps1 -Yes` on a freshly installed WSL Ubuntu 26.04.1 LTS (systemd on by default, no Docker): installs
  Docker Engine 29.9.3, starts the stack, all checks pass (2026-11-14). The data was then restored with `wsl/backup.sh`.
- `.sh/.sql/.yaml` are pinned to LF in `.gitattributes`: with CRLF, `init-views.sh` fails inside the container.

## What is sent

Observed with Claude Code 2.1.323 and the client settings above:

- **Text**: your prompts (`user_prompt.prompt`, needs `OTEL_LOG_USER_PROMPTS=1`). The same variable also makes clients send
  the **full text of Claude's replies** (`assistant_response.response`; there is no separate switch). The dashboard does not use
  it, so the collector deletes it before storage (`attributes/drop_response` in `otel-collector.yaml`); only `response_length` is kept.
- **Tool arguments** (`OTEL_LOG_TOOL_DETAILS=1`): file paths, search patterns, Bash commands. Not file contents and not tool
  output: only their size (`tool_result_size_bytes`).
- **Usage**: model, tokens (incl. cache), cost, durations, time to first token, effort, subagent and skill names, permission
  decisions, hook timings; plus metrics (tokens, cost, lines of code changed, active time).
- **Identity**: account email, account/organization IDs, plan (`pro`, …), session and prompt IDs, OS version,
  and the `project`/`host` you set.

Everything is stored only on the server PC, indefinitely. If you don't want prompts stored, remove `OTEL_LOG_USER_PROMPTS`:
the `first_prompt` column will then be empty.
