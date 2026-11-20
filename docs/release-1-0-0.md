# Version 1.0.0

!!! info "In preparation"
    Version 1.0.0 is not released yet. This page lists what it will contain and changes until the
    release.

<!-- unreleased: before the PR into main, put the date line back and remove this marker and the banner above it -->

This is the first release. It is the whole stack as the guide describes it: a server that stores
Claude Code telemetry, a script for every PC that sends it, and seven Grafana dashboards that
read it.

## What's new

**Server on Windows or Linux.** One script starts OTel Collector, ClickHouse and Grafana in
Docker and checks that they answer. On Windows it uses Docker Desktop or Docker Engine inside
WSL2, and installs Docker into WSL when you agree. On Linux it installs Docker on Debian and
Ubuntu. Every run is safe on a configured server: `.env` is never regenerated and no data is
removed. See [Install the server](server.md).

**LAN access you choose.** By default a Windows server accepts data from this PC only;
`-EnableLan` opens the OTLP ports to the LAN after a UAC prompt. A Linux server is reachable
from the LAN by default; `--local-only` keeps it on this PC. The OTLP ports have no
authentication, so use LAN mode on a trusted network only. See
[Ports and access on Linux](server.md#ports-and-access-on-linux).

**Clients on Windows or Linux.** One script per PC merges the telemetry settings into your own
`settings.json` and keeps every other key. A backup `<file>.bak` is saved before the first
change, and `-WhatIf` / `--dry-run` shows the result without writing it. See
[Connect a PC](clients.md).

**Session titles, git branches and projects.** A small hook sends the session title, git branch
and working directory after a prompt. The server then names the project from an explicit label,
the working directory or the file paths of the session. See
[Session titles, git branch and working directory](clients.md#session-titles-git-branch-and-working-directory)
and [Project](clients.md#project).

**Seven dashboards and a side rail.** Overview, Sessions, Prompts, Efficiency, Agents & skills,
Tools & files and Health show cost, cache use, prompts, tools, subagents and API health. The rail
on the left switches between them and keeps the time range and the variables. See
[Read the dashboards](dashboards.md).

**Dashboards in Russian.** Every dashboard has a Russian copy in the Grafana folder `ru`. The
**RU** / **EN** button in the controls row switches between a dashboard and its copy and keeps
the time range and the variables. The rail, panel, variable and column titles and the
descriptions are translated. Collected data (for example session names), Grafana's own
interface, tip titles and texts, and terms such as `cost_usd` and TTFT are not. See
[Russian dashboards](dashboards.md#russian-dashboards).

**Tips.** Eight rules look at the last 7 days and name what is worth a look, for example a low
cache hit rate or a file read many times. A tip opens the panel that shows the evidence. See
[Tips](tips.md).

**Update, back up, roll back.** On Linux, `--update` dumps the tables, pulls the new version,
restarts what changed and compares the row counts afterwards; it prints `FAIL` when a table lost
rows. `linux-server-tools/backup.sh` dumps and restores the collected data. See
[Maintain the server](maintenance.md).

**A guide in English and Russian.** This site, built from the same page set in both languages.

## Data and privacy

| What | Behaviour |
| --- | --- |
| Where it is stored | Only on the server PC, indefinitely; the collector has no exporter besides ClickHouse |
| Prompts | Stored when `OTEL_LOG_USER_PROMPTS=1`, which the client script sets. Remove the variable to stop |
| Claude's replies | The full text is dropped by the collector before storage; only the length is kept |
| Session hook | Sends title, git branch, working directory and version; never prompts or replies. `-NoSessionMeta` / `--no-session-meta` removes it |

The full list is on [Data and privacy](data.md#what-claude-code-sends).

!!! note "Requirements"
    Claude Code **2.1.310 or newer** is required on every client: older versions do not put
    `agent_id` on tool events.
