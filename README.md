# cc-telemetry — local Claude Code usage statistics

```text
PC-1, PC-2, …  Claude Code ──OTLP gRPC :4317──►  server PC (Docker)
                                                 OTel Collector → ClickHouse → Grafana :3000
```

Everything stays on your LAN. Claude Code exports the events itself, so client PCs need no extra software, only settings.
Claude Code **2.1.310 or newer** is required: older versions do not put `agent_id` on tool events.

Setup is one script on the server PC and one script on every PC whose sessions you want to see (the server PC included).
Both are safe to re-run. Each comes in a Windows and a Linux variant:

| | Windows (PowerShell) | Linux (bash) |
| --- | --- | --- |
| Server, once | [setup-server.ps1](setup-server.ps1) | [setup-server.sh](setup-server.sh) |
| Client, every PC | [client/setup-client.ps1](client/setup-client.ps1) | [client/setup-client.sh](client/setup-client.sh) |

The server and the clients are independent: they only talk OTLP over TCP port 4317. Any mix works, for example a Linux server
with Windows clients.

Contents: [1. Server](#1-server-one-pc) · [2. Clients](#2-clients-every-pc) · [3. Dashboard](#3-dashboard) ·
[4. Maintenance](#4-maintenance) · [5. Troubleshooting](#5-troubleshooting) · [What is sent](#what-is-sent)

## 1. Server (one PC)

Internet access is needed on the first start (images and the Grafana ClickHouse plugin are downloaded).
On a Windows server the ports `3000` (Grafana) and `4318` (OTLP HTTP) are published on `localhost` only; only `4317` can be opened to the LAN.
On a Linux server `4318` stays local, while `4317` and Grafana (port `3000` by default) are opened to the LAN by default (see 1b).

### 1a. Server on Windows

Requirements, one of:

- **Docker Desktop** (WSL2 backend), which needs Windows 10 22H2 (build 19045) or Windows 11. Start it before running the script.
- **Older Windows 10**: WSL2 with an Ubuntu distro and systemd enabled (`[boot]` / `systemd=true` in `/etc/wsl.conf`).
  The script installs Docker Engine inside it; Docker Desktop is not needed.

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

Options: `-Mode desktop|wsl` (skip auto-detection), `-Distro <name>` (default `Ubuntu`), `-LanIp <address>`
(if the LAN address is detected wrong), `-Yes` (install Docker into WSL without asking).
Best reserve the server's IP in the router's DHCP; if it changes, run `setup-server.ps1 -EnableLan` again.

The Windows script always checks and prints Grafana on port `3000`. If you set `GRAFANA_PORT` in `.env` by hand, Docker publishes
that port, but the script's check and the printed address still say 3000; use the Windows script with the default port.

### 1b. Server on Linux

Requirements: a systemd-based distribution. On Debian, Ubuntu and derivatives the script installs Docker Engine and the compose
plugin from `download.docker.com` if they are missing. On other distributions install
[Docker Engine with the compose plugin](https://docs.docker.com/engine/install/) first.

```bash
cd cc-telemetry
bash setup-server.sh              # reachable from the LAN (default: Linux servers are usually headless)
bash setup-server.sh --local-only # this PC only
```

Run it as your normal user (it also works as root, but then no user is added to the `docker` group). It asks before it uses
`sudo`. If you are not in the `docker` group, the script runs Docker through `sudo` and says so; `sudo usermod -aG docker $USER`
and a new login remove the need.

The script:

1. checks that `docker` and the compose plugin are present and the daemon answers; if not, offers to install them (Debian/Ubuntu
   and derivatives whose release Docker publishes packages for) or tells you what to install. The installer also enables the
   `docker` service at boot and adds your user to the `docker` group;
2. creates `.env` with random passwords (an existing `.env` is kept) and sets `OTLP_BIND`, `GRAFANA_BIND` and `GRAFANA_PORT` in it
   (see below), plus `CLICKHOUSE_VERSION` on an old ARM CPU (see "Raspberry Pi 4");
3. stops with a message if the Grafana port is taken by another program (a busy 4317/4318 is reported as a warning), then starts
   the stack and waits until the `cc.*` views are created;
4. checks Grafana and the OTLP port (`localhost:4317`), and that the `docker` service starts at boot
   (offers `sudo systemctl enable docker` if not), so the stack comes back after a restart;
5. LAN access (unless `--local-only`): publishes ports 4317 (clients) and Grafana on all interfaces, adds `ufw` or `firewalld`
   rules for them (whichever is active; asks first) and prints the server's LAN address.

At the end it prints the Grafana address (`http://<server-ip>:<grafana-port>`, log in as `admin`) and the ready-to-run client
commands for Windows (`powershell -ExecutionPolicy Bypass -File .\setup-client.ps1 -ServerIp <server-ip> -Project <project folder>`)
and Linux (`bash setup-client.sh --server-ip <server-ip> --project <project folder>`; copy the client script to that PC first).

Options: `--local-only` (4317 and Grafana on this PC only), `--lan` (back to all interfaces after an earlier `--local-only`;
`--enable-lan` is the same), `--lan-ip <address>` (if the LAN address is detected wrong), `--grafana-port <n>`,
`--clickhouse-version <tag>`, `--update` (see "Updating the server"), `--yes` (do not ask before installing Docker, using `sudo`
or enabling the service), `--help`.

**Ports and the firewall.** Docker publishes ports through its own `iptables` rules, which `ufw` and `firewalld` do not
filter. Therefore the script controls access with the address Docker publishes each port on, two lines in `.env`:
`OTLP_BIND` (port 4317) and `GRAFANA_BIND` (Grafana), each `0.0.0.0` (every PC that can reach the host) or `127.0.0.1`
(this PC only). The firewall rules the script adds do not limit access, they only let the traffic in; `--local-only` does not
remove rules added earlier (remove them yourself with `ufw delete allow <port>/tcp` or `firewall-cmd --remove-port=<port>/tcp`).
Without a flag, a missing `OTLP_BIND` becomes `0.0.0.0` and a missing `GRAFANA_BIND` copies `OTLP_BIND`; values already in `.env`
are kept, so running the script again does not change the exposure by itself. The one exception to "unchanged": an `.env` from an
earlier version of the script that has `OTLP_BIND=0.0.0.0` but no `GRAFANA_BIND` now gets `GRAFANA_BIND=0.0.0.0` (the script
warns); use `--local-only` to keep Grafana on this PC. `--local-only` and `--lan` set both explicitly. A bind you set by hand,
for example `OTLP_BIND=192.168.1.5`, counts as reachable from the LAN: the script opens the firewall for it and prints that address.

If you start the stack by hand with a plain `docker compose up -d`: with no `GRAFANA_BIND` Grafana is published on `localhost`
only, with no `OTLP_BIND` port 4317 is published on `0.0.0.0` (and `ufw`/`firewalld` do not stop it). Put both lines into `.env`
first (the script on Linux writes `GRAFANA_BIND=0.0.0.0` for the LAN default).

**Grafana port.** If another program already uses port 3000 (for example another Grafana), Docker cannot publish it and the
script stops with "port is already in use". Run `bash setup-server.sh --grafana-port 3001`: the port is stored as `GRAFANA_PORT`
in `.env` (a plain re-run keeps it), and the checks, the firewall rule and the printed addresses use it. The ports 4317 and 4318
are fixed; the script only warns if another program holds them.

**Raspberry Pi 4 and other old ARM CPUs.** Since ClickHouse 22.10 (PR #41610) the ARM builds need ARMv8.2 with the `lrcpc` CPU
feature; on a Raspberry Pi 4 (Cortex-A72, ARMv8.0) every newer image, including 23.3, stops with `Illegal instruction`
(exit code 132). The newest tag known to run there is `22.3.20.29`. On `aarch64` without `lrcpc` in `/proc/cpuinfo` the script
writes `CLICKHOUSE_VERSION=22.3.20.29` to `.env` if the key is missing, replaces the value `23.3.22.3` (what earlier versions of
the script wrote, and which does not run there) and warns. Any other value you set stays; if it is 22.10 or newer, the script
warns and suggests `bash setup-server.sh --clickhouse-version 22.3.20.29`. `--clickhouse-version <tag>` sets another tag on any
machine; remove the line from `.env` to return to the default. Caveats: 22.3 dates from 2022 and has long been out of support
(no security fixes: use it on a trusted LAN only), a data volume written by a newer ClickHouse does not start with it (so a Pi 4
needs a fresh volume), and a Native dump from a newer server (`linux-server-tools/backup.sh`) should be restored into a fresh
stack and checked with a row count per table. The collector's tables, the `cc.*` views and every dashboard query were checked on
22.3 (see the verification notes in section 5).

**Security.** Grafana is plain HTTP behind the `admin` login (no anonymous access); OTLP has no authentication. Use the LAN
mode on a trusted home or office network only, or `--local-only` and an SSH tunnel for Grafana.

**Updating the server.** To move a running Linux server to a newer version of this repository without losing data:

1. Close the Claude Code sessions on the clients that send to this server.
2. Run `bash setup-server.sh --update` in the `cc-telemetry` folder (add the options you normally use, for example `--local-only`).
3. Start the Claude Code sessions on the clients again. Sessions that were running during the update may not reconnect to the
   restarted collector.

The first time, run `git pull` yourself: older versions of the script have no `--update`. The command:

1. stops with a message if ClickHouse does not answer or if the git working tree has local changes to tracked files (`.env`
   and `backup/` are git-ignored and do not count);
2. dumps all `otel.*` tables to `backup/pre-update-<date>-<time>/` and records the row count of every table there. Earlier dumps
   stay; delete old `pre-update-*` folders yourself. Before dumping, it compares the free disk space with the uncompressed size
   of the data (the dump is that large) and stops if there is less, or warns if there is less than 1.5 times that. If Docker
   needs `sudo` here, the dump files belong to root;
3. runs `git pull --ff-only`. It never merges or rebases. If the branch has no upstream, it prints a warning and continues with
   the files as they are;
4. runs `setup-server.sh` again from the updated file with your other options. This starts changed containers, recreates the
   `cc.*` views and repeats the checks. Containers whose image and configuration did not change keep running, and the data
   volumes are never removed;
5. compares the row counts. Every table must have at least as many rows as before; the script prints `OK`, or a `FAIL` banner
   with the dump folder, and exits with status 1.

If `git pull` fails (for example because the branch diverged), nothing on the stack has changed. Fix the repository and run
`--update` again.

**Roll back** to the previous version (the script prints its commit):

```bash
git checkout <previous commit>
bash setup-server.sh
```

The data stays in the volume, so the rollback needs no restore. Use the dump only if a table lost rows (the `FAIL` banner).
`restore` appends rows, so use it only for tables that are empty now:

```bash
BACKUP_DIR=backup/pre-update-<date>-<time> bash linux-server-tools/backup.sh restore            # all tables
BACKUP_DIR=backup/pre-update-<date>-<time> bash linux-server-tools/backup.sh restore otel_logs  # one table
```

If Docker needs `sudo` on this PC, `BACKUP_DIR=... sudo bash ...` loses the variable (sudo resets the environment) and would
restore the default `backup` folder. Pass it after sudo instead (the script prints the right form):

```bash
sudo env BACKUP_DIR=backup/pre-update-<date>-<time> bash linux-server-tools/backup.sh restore
```

After a rollback, `git checkout main` returns the branch for the next `--update` (on a detached `HEAD` there is no upstream and
nothing is pulled).

### 1c. Both

Open `http://localhost:3000` (or your `GRAFANA_PORT`): user `admin`, password `GRAFANA_ADMIN_PASSWORD` from `.env`.
The **Claude Code usage** dashboard is the home page.

The OTLP port has no authentication: enable LAN access on a trusted network only.

## 2. Clients (every PC)

Run the client script on every PC whose Claude Code sessions you want to see, the server PC included. It changes only
your own user's files. It needs the server's address: the LAN IP printed by the server script, or `localhost` on the server PC itself.

### 2a. Client on Windows

Copy [client/setup-client.ps1](client/setup-client.ps1) to the PC (it is the only file a client needs) and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-client.ps1 -ServerIp <SERVER_IP> -Project C:\Projects\ProjA, C:\Projects\ProjB
```

- `-ServerIp`: the server's address.
- `-Project`: optional. Folders to label explicitly with their name; add more later by re-running with other folders.
  Without it the server infers the project from file paths (see "Project" below).
- `-PcName`: optional, the computer name by default; letters, digits, `.`, `_`, `-`.
- `-WhatIf`: show the result and write nothing.

It adds the telemetry keys to the `env` section of `%USERPROFILE%\.claude\settings.json` and
`OTEL_RESOURCE_ATTRIBUTES=project=<folder name>,host=<PC name>` to `<project>\.claude\settings.local.json` (created if missing;
only for the `-Project` folders).
It leaves every other key (permissions, model, plugins, …) as it was, saves `<file>.bak` before the first change,
checks that the result is valid JSON (Windows PowerShell 5.1 re-indents it; the content stays the same)
and tests the connection to `<SERVER_IP>:4317`.

### 2b. Client on Linux

Copy [client/setup-client.sh](client/setup-client.sh) to the PC (it is the only file a client needs). It needs `jq` or `python3`.
Run it as your normal user, without `sudo`:

```bash
bash setup-client.sh --server-ip <SERVER_IP> --project ~/projects/ProjA --project ~/projects/ProjB
```

- `--server-ip`: the server's address (required).
- `--project`: optional. A folder to label explicitly with its name; repeat the option for more, add more later by re-running.
  Without it the server infers the project from file paths (see "Project" below).
- `--pc-name`: optional, `hostname -s` by default; letters, digits, `.`, `_`, `-`.
- `--settings-dir`: project settings folder if it is not `.claude`.
- `--dry-run`: show the result and write nothing.

It does the same as the Windows script: it merges the keys into `~/.claude/settings.json` and
`<project>/.claude/settings.local.json`, leaves every other key as it was, saves `<file>.bak` before the first change,
checks that the result is valid JSON (the JSON is re-indented with two spaces; the content stays the same)
and tests the connection to `<SERVER_IP>:4317`.

### 2c. After the client script

1. Claude Code must be **2.1.310 or newer** (`claude --version`, otherwise `claude update`).
2. Only if you used `-Project` / `--project`: project settings are read only in a **trusted** folder. If a project was never
   opened in Claude Code on this PC, run `claude` in it once and accept the trust dialog.
3. **Restart running sessions**, settings are read at start: in VS Code *Developer: Reload Window*,
   in the terminal exit and continue with `claude -c`.
4. Make any request. Within 5–10 s the session appears in Grafana; its project shows in the **Project** dropdown once the
   session has touched a file (or at once with an explicit label).

### Project

Claude Code does not send the working directory, so the dashboard's `project` is decided on the server, per session:

1. **Explicit label wins.** `project=<name>` from `OTEL_RESOURCE_ATTRIBUTES` (written by `-Project` / `--project`) is used as is.
   Use it for projects whose sessions touch no files (pure chat, MCP only) and for folders the guess gets wrong.
2. **Otherwise inferred** from the absolute file paths of the session's tool calls (Read, Edit, Write, Glob, Grep, ...):
   the folder name (lower case, as with `--project`) that appears most often, ties broken alphabetically. The folder is the
   first path segment after the home directory and generic containers such as `Documents`, `projects`, `src`, `dev`, `work`,
   `repos`, `github`: `C:\Users\me\Documents\Projects\Alpha\a.cpp` and `/home/me/src/alpha/a.cpp` both give `alpha`.
   A worktree folder `alpha-feature` counts as `alpha` when `alpha` is also known (seen in other paths or set as a label).
   Worktree folding is a name-prefix heuristic: it can merge different projects whose names share a prefix (`my` and
   `my-app`) and is not transitive (`b`, `b-c`, `b-c-d`); an explicit `--project` label avoids it.
   Paths in hidden folders (`~/.claude`), temp and system folders are ignored.
3. **Otherwise `unknown`**: no explicit label and no file paths in the session. Files attached with an `@` mention
   do not count: Claude Code inlines them without a tool call and its `at_mention` event carries no path.

It is computed on every query, so sessions recorded earlier get their project too. A project in an unusual layout (folders
directly under `/data/x/y/`) is named after the first folder (`data`): label it with `--project`.

Only sessions started after the setup are recorded. Telemetry is sent live: past sessions in `~/.claude/projects`
(`%USERPROFILE%\.claude\projects` on Windows) are not uploaded, and events produced while the server is unreachable
are dropped after a short retry.

<details>
<summary>Manual client setup (what the scripts write)</summary>

User settings (`%USERPROFILE%\.claude\settings.json` on Windows, `~/.claude/settings.json` on Linux), **add** to `"env"`
(don't replace the section):

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

Optional, only to label a project explicitly (otherwise it is inferred from file paths, see "Project"): in the project's
`.claude/settings.local.json`, add to `"env"`:

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

Run these from the `cc-telemetry` folder. Re-running the server script is also a quick health check.

On a Windows server with Docker in WSL, prefix the commands with `wsl -d Ubuntu --`. On a Linux server run them as they are
(add `sudo` if you are not in the `docker` group).

```bash
docker compose ps                         # all Up (views-init: Exited (0))
docker compose run --rm views-init        # recreate the views after editing clickhouse/views.sql
docker compose down                       # stop (data stays in the volume)
```

SQL without typing the password (taken from `.env`, never printed):

```powershell
"SELECT event, count() FROM cc.events GROUP BY event" | wsl -d Ubuntu -- bash linux-server-tools/ch.sh   # Windows server, Docker in WSL
```

```bash
echo "SELECT event, count() FROM cc.events GROUP BY event" | bash linux-server-tools/ch.sh               # Linux server
```

Backup and restore of all collected data (`backup/` is git-ignored: it contains your prompts). Shown for a Linux server;
on Windows with Docker in WSL run `wsl -d Ubuntu -- bash linux-server-tools/backup.sh …` from PowerShell:

```bash
bash linux-server-tools/backup.sh dump              # otel.* tables -> backup/<table>.native
bash linux-server-tools/backup.sh restore           # appends rows: use on a fresh, empty stack
bash linux-server-tools/backup.sh restore <table>   # one table only
```

`BACKUP_DIR=<folder>` in front of the command uses another folder instead of `backup` (for dump and restore). A relative
folder is relative to the `cc-telemetry` folder, not to the current directory. With `sudo`, write `sudo env BACKUP_DIR=<folder> bash ...`.

With Docker in WSL the data lives inside the distro: `wsl --unregister` deletes it. Dump first.

Data is kept indefinitely in the `clickhouse-data` volume. The `cc.*` views are plain (not materialized),
so editing `views.sql` recomputes the whole history.

## 5. Troubleshooting

| Symptom | What to check |
| --- | --- |
| Dashboard is empty | `docker compose logs otel-collector` (ClickHouse errors?), the client's connection test (`Test-NetConnection <SERVER_IP> -Port 4317` on Windows, the last line of `setup-client.sh` on Linux), `CLAUDE_CODE_ENABLE_TELEMETRY` in `settings.json`, sessions restarted after the setup |
| "Unknown table cc.events" | `docker compose logs views-init`, then `docker compose run --rm views-init` |
| Variable dropdowns are empty | Dashboard settings → Variables → open the variable → Run query → Save |
| ClickHouse plugin does not load | no internet on first start; `docker compose restart grafana` |
| `project = unknown` | the session touched no file with an absolute path and has no explicit label (`settings.local.json` with `OTEL_RESOURCE_ATTRIBUTES`, folder must be trusted); `OTEL_LOG_TOOL_DETAILS` must be `1` for paths to be sent |
| A project has an odd name (`data`, ...) | its folder sits in an unusual place; set the label with `-Project` / `--project` |
| `actor = agent?` | the subagent is still running and its name has not arrived yet, or Claude Code is older than 2.1.310 |
| Stack in WSL is down from time to time | `wsl -l -v` shows `Stopped`: the keepalive is not running; re-run `setup-server.ps1` |
| Port 4317 closed from another PC but open on the server's `localhost` (Windows server) | `setup-server.ps1 -EnableLan` not run, or the server's LAN IP changed (re-run it); network marked Public |
| Port 4317 closed from another PC but open on the server's `localhost` (Linux server) | `setup-server.sh` was run with `--local-only` (`OTLP_BIND=127.0.0.1` in `.env`; use `--lan`), or a firewall other than `ufw`/`firewalld` blocks it |
| Grafana does not open from another PC (Linux server) | `GRAFANA_BIND=127.0.0.1` in `.env` (run `setup-server.sh --lan`), or a firewall other than `ufw`/`firewalld` blocks the Grafana port; use `http://<server-ip>:<GRAFANA_PORT>` (3000 by default) |
| Linux server: "port is already allocated" / "address already in use" for Grafana | another program uses the port: `bash setup-server.sh --grafana-port 3001` |
| Linux server: `clickhouse` restarts with `Illegal instruction` | the ARM CPU is too old for ClickHouse 22.10 and newer (Raspberry Pi 4): see "Raspberry Pi 4" in 1b; re-run `setup-server.sh` or set `CLICKHOUSE_VERSION=22.3.20.29` in `.env` |
| Linux server: stack is down after a reboot | `systemctl is-enabled docker`; run `sudo systemctl enable docker` or re-run `setup-server.sh` |
| Linux server: `permission denied` for `docker` | you are not in the `docker` group: `sudo usermod -aG docker $USER`, log in again |
| `setup-client.ps1` cannot be run | run it as shown, via `powershell -ExecutionPolicy Bypass -File …` |
| `setup-client.sh`: "jq or python3 is required" | install one of them, for example `sudo apt install jq` |

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
  Docker Engine 29.9.3, starts the stack, all checks pass (2026-11-14). The data was then restored with `linux-server-tools/backup.sh`.
- `.sh/.sql/.yaml` are pinned to LF in `.gitattributes`: with CRLF, `init-views.sh` fails inside the container.
- `setup-server.sh` (health-check run with `--local-only`) and `setup-client.sh` (with `python3`) on Ubuntu 26.04 in WSL2
  (2026-11-14): the stack answers on `localhost` from Windows with the ports bound to `127.0.0.1`. The Docker install, firewall
  and `jq` paths of the Linux scripts are not verified on a physical Linux host.
- ClickHouse 23.3.22.3 and 22.3.20.29 (x86, a separate compose project each): the collector creates `otel_logs` and the five
  `otel_metrics_*` tables, `views-init` creates all `cc.*` views, they return rows for sample events (prompt, requests with a
  subagent and a skill, tool calls, subagent end), all 23 dashboard queries pass (with all variables on All and with a project,
  session, actor and skill set) and the Grafana datasource health check is OK. The Skills panel uses `ON` joins instead of
  `USING` for 23.3. A Native dump of `otel_logs` and `otel_metrics_sum` from a newer ClickHouse was inserted into 23.3 and
  22.3 unchanged; the views gave the same counts and cost as on the source. 23.3 does not run on a Raspberry Pi 4 (`Illegal
  instruction`); 22.3.20.29 does (`SELECT version()` there), but the whole stack was not run on a real Pi 4 (arm64 image of the
  same version).

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
  and the `host` (and optionally `project`) you set. Nothing new is sent for the project guess: the server derives it from the
  tool-call paths above.

Everything is stored only on the server PC, indefinitely. If you don't want prompts stored, remove `OTEL_LOG_USER_PROMPTS`:
the `first_prompt` column will then be empty.
