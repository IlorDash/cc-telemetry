# Troubleshooting

This page lists what goes wrong and what to do about it, grouped by what you were doing. Find the
message or the symptom in the table, read the cause, do the action. The install scripts print
`FAIL <message>` and stop, or `WARN <message>` and go on. Every script is safe to run again once
the cause is fixed.

---

## What to include in a report

If a row says to report it, or nothing here matches, open an issue at
[github.com/IlorDash/cc-telemetry/issues](https://github.com/IlorDash/cc-telemetry/issues) with:

- the full output of the script that failed, from the first line, not only the last message;
- your server: Linux or Windows, and for Windows whether Docker runs in Docker Desktop or in WSL;
- the output of these commands on the server, from the `cc-telemetry` folder (put
  `wsl -d Ubuntu --` in front when Docker runs in WSL):

    ```bash
    git log -1 --oneline
    docker compose ps
    docker compose logs --tail 100 otel-collector
    docker compose logs --tail 100 clickhouse
    docker compose logs --tail 100 views-init
    ```

- for a client problem: the output of the client script and `claude --version`.

!!! warning "Never attach `.env`"
    `.env` holds the ClickHouse and Grafana passwords. Do not paste it, and do not paste the
    contents of `backup/`, which holds your prompts. Read the output you attach before you send
    it: it can contain your IP addresses, PC names and folder paths.

Messages that say *report it* are not operator errors: the script did something it should not
have done, and repeating the operation will not help.

---

## Server install

The messages of the install scripts, with the cause and the fix of each, are on
[the server page](server.md#if-it-fails). These are the ones people meet most often.

| Message or symptom | Cause | What to do |
| --- | --- | --- |
| `No Docker found. Install Docker Desktop ...` | Windows: neither Docker Desktop nor a WSL distro was found | Install one of them, then run the script again |
| `Docker Desktop is not running. Start it and run this script again.` | Windows: Docker Desktop does not answer | Start it, wait until it is ready, run the script again |
| `systemd is off in WSL 'Ubuntu'. ...` | Windows: the script cannot install Docker into WSL without systemd | Do what the message says: add `[boot]` and `systemd=true` to `/etc/wsl.conf`, run `wsl --terminate Ubuntu`, run the script again |
| `TCP port 3000 is already in use by another program, so Grafana cannot publish it. ...` | Linux: another program uses the Grafana port | `bash setup-server.sh --grafana-port 3001` |
| `WARN GRAFANA_BIND was missing and OTLP_BIND=0.0.0.0: Grafana is now published on 0.0.0.0, ...` | Linux: `.env` from an older version has `OTLP_BIND` but no `GRAFANA_BIND`, so Grafana is now reachable from the LAN | To keep Grafana on this PC, set `GRAFANA_BIND=127.0.0.1` in `.env` and run the script again, or use `--local-only`. See [the server page](server.md#ports-and-access-on-linux) |
| `permission denied` for `docker` | Linux: you are not in the `docker` group | `sudo usermod -aG docker $USER`, then log in again |
| `views-init did not finish cleanly (<state>)` | The `cc.*` views were not created | Read the `views-init` log the script printed, run the script again; if it repeats, report it |
| `Grafana does not answer yet; check: docker compose logs grafana` | Grafana is still starting, or its ClickHouse plugin could not be downloaded (no internet on the first start) | Wait a minute and open Grafana; restore the internet and run `docker compose restart grafana` |
| `localhost:<port> is closed; check: docker compose logs otel-collector` | The collector does not listen on that port | Read the collector log |
| `Illegal instruction` in the `clickhouse` log, the container restarts | Linux: the ARM CPU is too old for ClickHouse 22.10 and newer (Raspberry Pi 4) | Run `setup-server.sh` again or set `CLICKHOUSE_VERSION=22.3.20.29` in `.env`, see [the server page](server.md#ports-and-access-on-linux) |
| The stack is down after a reboot (Linux) | The `docker` service does not start at boot | `systemctl is-enabled docker`; `sudo systemctl enable docker`, or run `setup-server.sh` again |
| The stack stops from time to time (Windows, Docker in WSL) | `wsl -l -v` shows the distro as `Stopped`: the keepalive is not running | Run `setup-server.ps1` again; it starts the keepalive and puts it in the Startup folder |

### Other PCs cannot reach the server

| Symptom | Cause | What to do |
| --- | --- | --- |
| Port 4317 or 4318 is closed from another PC but open on the server's `localhost` (Windows server) | `-EnableLan` was not run (a server from before the session hook needs it again for 4318), the server's LAN address changed, or the network is marked Public | Run `setup-server.ps1 -EnableLan`. If it warns that the network is `Public`, follow the message |
| The same (Linux server) | The script was run with `--local-only` (`OTLP_BIND=127.0.0.1` in `.env`), or a firewall other than `ufw` or `firewalld` blocks the port | `bash setup-server.sh --lan`; open the port in your firewall |
| Grafana does not open from another PC (Linux server) | `GRAFANA_BIND=127.0.0.1` in `.env`, or a firewall other than `ufw` or `firewalld` blocks the port | `bash setup-server.sh --lan`; use `http://<server-ip>:<GRAFANA_PORT>` (`3000` by default) |
| Grafana does not open from another PC (Windows server) | By design: on Windows, Grafana is published on `localhost` only | Open it on the server PC |

---

## Client

The messages of the client scripts are on [the clients page](clients.md#if-it-fails).

| Message or symptom | Cause | What to do |
| --- | --- | --- |
| `server <address>:4317 reachable: False` | The server is down, the address is wrong, or the port is closed on the server | Check the address, then see the table above |
| `server <address>:4318 (session titles) reachable: False` | Port 4318 is closed | Run the server script again (Windows: `-EnableLan`; Linux: without `--local-only`), then the client script |
| The client script cannot be run (Windows) | The execution policy blocks it | `powershell -ExecutionPolicy Bypass -File .\setup-client.ps1 ...` |
| `ERROR: python3, or jq 1.6 or newer, is required ...` | Linux: no tool to edit the JSON | Install one, for example `sudo apt install jq` |
| `ERROR: <file> is not valid JSON after the update; restore it from <file>.bak` | Linux: the write went wrong | Restore the file from `<file>.bak` and report it |
| Session titles, git branch or the project do not appear | Port 4318 is not reachable, or the hook was never installed (`-NoSessionMeta`), or the session is older than the hook | Fix port 4318 as above; re-run the client script without `-NoSessionMeta`; use `-ImportHistory` for old sessions. After a failed send the hook pauses for 10 minutes, and a new session's title arrives with the next prompt |
| `project` is `unknown` | No explicit label, no working directory from the hook, and the session touched no file with an absolute path | Label the project with `-Project` / `--project`; check that `OTEL_LOG_TOOL_DETAILS` is `1`; the folder must be trusted in Claude Code. See [Project](clients.md#project) |
| A project has an odd name (`data`, ...) | Its folder sits in an unusual place | Set the label with `-Project` / `--project` |

---

## No data in Grafana

Work down the list; stop at the first step that fails.

1. On the client, check the connection: the last lines of the client script show
   `reachable: True` or `False` for ports 4317 and 4318. On Windows,
   `Test-NetConnection <SERVER_IP> -Port 4317` repeats the test.
2. On the client, check that `CLAUDE_CODE_ENABLE_TELEMETRY` is `1` in the `env` section of
   `settings.json`, and that Claude Code is **2.1.310 or newer** (`claude --version`).
3. Restart the Claude Code session. Settings are read at start; in VS Code run *Developer:
   Reload Window*, in a terminal exit and continue with `claude -c`.
4. If the project settings are the problem: project settings are read only in a trusted folder.
   Open the folder in Claude Code once and accept the trust dialog.
5. On the server, read `docker compose logs otel-collector`. A ClickHouse error there means
   the events arrive but are not stored: read `docker compose logs clickhouse` too.
6. Make a request and wait 30 seconds (the collector writes events in batches every 30 s), then
   reload the dashboard. The first events fill **Overview**.

---

## Dashboards

| Symptom | Cause | What to do |
| --- | --- | --- |
| Panels are empty | No events in the time range, or a variable filters everything out | Widen the time range; set the variables to `All`. See [Time range and refresh](dashboards.md#time-range-and-refresh) |
| An error that the table or view `cc.events` does not exist | The `cc.*` views do not exist | `docker compose logs views-init`, then `docker compose run --rm views-init` |
| A new session shows `project = unknown` for longer than 5 minutes, or the tips look stale | The `cc-refresh` service does not run or fails | `docker compose logs cc-refresh`: every 5 minutes it prints `refresh ok` or `refresh FAILED` with the error. `docker compose up -d cc-refresh` starts it |
| A panel fails with a memory limit error (`MEMORY_LIMIT_EXCEEDED`) | The server runs with the limits of a small server: a query may use 1.5 GB | Narrow the time range or the variables. See [Resource limits and logs](maintenance.md#resource-limits-and-logs) |
| A variable dropdown is empty | The variable query did not run | Dashboard settings, Variables, open the variable, **Run query**, then save the dashboard |
| The ClickHouse plugin does not load | No internet on the first start | Restore it and run `docker compose restart grafana` |
| **Sessions**: "No session selected" under the table | By design: the panels below the table show the selected session only | Click a session name, or pick it in the **Session** variable. See [Variables](dashboards.md#variables) |
| **Skills used** and **Skills** are empty, `0` | An agent is picked as **Actor**: only the main session reports skill activations | Set **Actor** to `All` or `main` |
| `actor = agent?` | The subagent is still running and its name has not arrived yet, or Claude Code is older than 2.1.310 | Wait for the run to end; update Claude Code |
| The **API errors** panels on **Health** are empty | There was no `api_error` event yet | Nothing: they fill with the first failed request |
| The **Account** dropdown shows 8 characters instead of an e-mail | The events carry no e-mail, only the account ID | Nothing to fix; see [Variables](dashboards.md#variables) |
| The layout looks wrong on a narrow screen | Only Full HD (1920 px wide) and wider screens are supported | Use a wider screen |

---

## Update

Messages of `bash setup-server.sh --update`, in the order the steps run. The steps are on
[the Maintenance page](maintenance.md#update-the-server). Until the data check, the stack
is not touched.

| Message | Cause | What to do |
| --- | --- | --- |
| `.env not found: this folder is not a configured server yet. Run: bash setup-server.sh` | This folder has no `.env` | Run `bash setup-server.sh` first |
| `ClickHouse does not answer, so no safety dump is possible. Start the stack (docker compose up -d), wait until it is healthy and run --update again.` | The stack is down | Do what the message says |
| `The git working tree has local changes (listed above): ...` | Tracked files were edited; the pull could fail or merge them | Commit, stash or revert them (`git stash`), run `--update` again |
| `Cannot create backup/pre-update-<date>-<time>. ...` | `backup/` belongs to root (made by an earlier `sudo` run) | `sudo chown -R $(id -un) backup`, run `--update` again |
| `Not enough free disk space for the safety dump: ...` | The dump needs as much room as the uncompressed data | Free some space or delete old `backup/pre-update-*` folders; nothing was changed |
| `free disk space is tight: ...` | Warning: less than 1.5 times the dump size is free | Free some space; the update goes on |
| `The safety dump failed (see above). Nothing was changed.` or `Could not count the rows. Nothing was changed.` | ClickHouse failed during the dump | Read the output above, run `--update` again; if it repeats, report it |
| `git pull --ff-only failed (a diverged branch or no network). The stack was not touched.` | Your branch has commits the remote does not, or there is no network | Fix the repository (for example `git status`) and run `--update` again |
| `the current branch has no upstream: nothing is pulled, continuing with the files as they are.` | Warning: a detached `HEAD` or a local branch, for example after a rollback | `git checkout main`, then `--update` again |
| `this folder is not a git repository` or `no git repository: continuing with the files as they are.` | Warning: no `git pull` is possible | Get the new version yourself, then run `--update` or the plain script |
| `The update did not finish. The safety dump from before it is in: <folder>` | A step after the dump failed | Fix the error shown above this message and run `--update` again. The data volumes are never removed; the dump is a safety copy |
| `LOST <table>: <n> rows before, <m> now` with the banner `DATA MAY HAVE BEEN LOST DURING THE UPDATE` | A table has fewer rows than before the update | Do not run `restore` yet: it appends rows. Check the counts, restore only into tables that are empty now, see [Back up and restore](maintenance.md#back-up-and-restore). Then report it |
| `docker compose restart <service> failed, see the output above.` | The changed collector or Grafana configuration did not load | Read the log of that service; fix the file, restart it by hand |

To go back to the previous version, see [Roll back](maintenance.md#roll-back). On Windows there is
no `--update`: you run `git pull` and `setup-server.ps1` yourself, see the same page.
