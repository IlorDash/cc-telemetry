# cc-telemetry — local Claude Code usage statistics

cc-telemetry shows how you use Claude Code: cost, tokens, sessions, prompts, tools, subagents and
errors. Claude Code sends its telemetry to a server PC on your LAN, where it is stored in
ClickHouse and shown in seven Grafana dashboards.

**Guide: <https://ilordash.github.io/cc-telemetry/>** · **Руководство на русском:
<https://ilordash.github.io/cc-telemetry/ru/>**

The guide has the full installation, the dashboards, the tips, maintenance, troubleshooting and
what data is collected. This page only gets you started.

## How the data flows

```text
Claude Code (every PC)  ─ OTLP gRPC :4317 ─┐
session hook            ─ OTLP HTTP :4318 ─┤
                                           ▼
        OTel Collector ─► ClickHouse ─► Grafana :3000
```

Claude Code exports the events itself, so a client PC needs settings only. A small hook that the
client script installs adds the session titles and git branches. Claude Code **2.1.310 or newer**
is required. The server and the clients can run on different systems: any mix of Windows and
Linux works.

## Quick start

### 1. Server (once)

Docker runs the stack. On Windows you need Docker Desktop (running) or WSL2 with Ubuntu; on
Linux the script installs Docker on Debian and Ubuntu if it is missing.

Windows (PowerShell):

```powershell
git clone https://github.com/IlorDash/cc-telemetry.git
cd cc-telemetry
powershell -ExecutionPolicy Bypass -File .\setup-server.ps1
powershell -ExecutionPolicy Bypass -File .\setup-server.ps1 -EnableLan   # accept data from other PCs (UAC prompt)
```

Linux (bash, as your normal user):

```bash
git clone https://github.com/IlorDash/cc-telemetry.git
cd cc-telemetry
bash setup-server.sh              # reachable from the LAN
bash setup-server.sh --local-only # this PC only
```

At the end the script prints the Grafana address and the client command with the server's
address. Open Grafana, log in as `admin` with `GRAFANA_ADMIN_PASSWORD` from `.env`. Running the
script again is safe: it keeps `.env` and the data.

The OTLP ports have no authentication: use the LAN mode on a trusted network only.

### 2. Client (every PC)

Copy the script to the PC and run it with the server's address.

Windows (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-client.ps1 -ServerIp <server-ip>
```

The script is [client/setup-client.ps1](client/setup-client.ps1).

Linux (bash, without `sudo`):

```bash
bash setup-client.sh --server-ip <server-ip>
```

The script is [client/setup-client.sh](client/setup-client.sh).

On the server PC itself, use `localhost` as the address. The script changes only your own
user's Claude Code settings and keeps every other key. Then restart running Claude Code
sessions and make a request: within a few seconds the session appears in Grafana.

## Next

Everything else is in the guide: <https://ilordash.github.io/cc-telemetry/> (Russian:
<https://ilordash.github.io/cc-telemetry/ru/>).
