# cc-telemetry

cc-telemetry shows how you use Claude Code: cost, tokens, sessions, prompts, tools, subagents and
errors. Claude Code sends its telemetry to a server PC on your LAN, where it is stored and shown
in Grafana; nothing leaves your network.

This guide describes version {{ app_version }}.

## How the data flows

```text
Claude Code (every PC)  ─ OTLP gRPC :4317 ─┐
session hook            ─ OTLP HTTP :4318 ─┤
                                           ▼
        OTel Collector ─► ClickHouse ─► Grafana :3000
```

Claude Code exports the events itself, so a client PC needs settings only, no extra software.
A small hook that the client script installs adds the session titles and git branches. Claude
Code **2.1.310 or newer** is required: older versions do not put `agent_id` on tool events.

## What the dashboards answer

Grafana shows seven dashboards. A rail on the left of each one switches between them and keeps
the time range and the variables.

| Dashboard | Question it answers |
| --- | --- |
| **Overview** | What did I spend and how well did the cache work in this period, by day, project and model? |
| **Sessions** | What happened in one session: its prompts, requests, subagents and tools over time? |
| **Prompts** | Which prompts cost the most, and what does a typical prompt cost? |
| **Efficiency** | Where are tokens and money lost, and which tips apply to my work? |
| **Agents & skills** | How much do subagents and skills cost, and which runs are outliers? |
| **Tools & files** | Which tools fail or are rejected, and which files are re-read or edited most? |
| **Health** | How fast and how reliable are the API requests and the hooks? |

## Supported platforms

| Role | Windows | Linux |
| --- | --- | --- |
| Server (once) | PowerShell script, Docker Desktop or Docker Engine in WSL2 | bash script, Docker Engine |
| Client (every PC) | PowerShell script | bash script |

The server and the clients only talk OTLP over TCP, so any mix works, for example a Linux server
with Windows clients.

## Where to start

| You want to | Go to |
| --- | --- |
| Install the server | [Server](server.md) |
| Connect a PC | [Clients](clients.md) |
| Read a dashboard | Dashboards (not written yet) |
| Fix a failed step | Troubleshooting (not written yet) |
| Know what is collected | What is sent (not written yet) |

!!! note "Languages"
    This guide comes in English and Russian; switch the language in the header. Grafana itself
    is English only, so dashboard and panel titles stay in English on the Russian pages.
