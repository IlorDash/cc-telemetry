# Install the server

The server is one PC that runs the whole stack in Docker: OTel Collector, ClickHouse and Grafana.
You install it once with one script; the script is safe to run again.

## Before you start

| You need | Windows server | Linux server |
| --- | --- | --- |
| System | Windows 10 22H2 or Windows 11 with Docker Desktop (WSL2 backend), **or** an older Windows 10 with WSL2 | A systemd-based distribution |
| Docker | Docker Desktop, running before you start the script; or Docker Engine inside a WSL2 Ubuntu distro with systemd on (the script installs it there) | Docker Engine with the compose plugin; on Debian, Ubuntu and derivatives the script installs it if it is missing |
| Shell | Windows PowerShell | bash, as your normal user |
| Internet | On the first start: the images and the Grafana ClickHouse plugin are downloaded | The same |
| Ports | `4317` (OTLP gRPC), `4318` (OTLP HTTP, session titles), `3000` (Grafana) free on this PC | The same; Grafana can use another port |
| Disk | Space for the Docker images and for the data, which is kept for 365 days and grows with use (see [Disk use and retention](maintenance.md#disk-use-and-retention)) | The same; 180 days on a Raspberry Pi 4 |

Other Linux distributions: install [Docker Engine with the compose
plugin](https://docs.docker.com/engine/install/) yourself first.

---

## Install on Windows

1. Start Docker Desktop. With Docker Engine in WSL there is nothing to start.
2. Get the repository and open its folder in PowerShell:

    ```powershell
    git clone https://github.com/IlorDash/cc-telemetry.git
    cd cc-telemetry
    ```

3. Run the script. By default only this PC can reach the server: Grafana is published on
   `localhost`, and the Windows firewall keeps the OTLP ports closed to the LAN.

    ```powershell
    powershell -ExecutionPolicy Bypass -File .\setup-server.ps1
    ```

4. If the script finds no Docker Desktop but a WSL distro without Docker, it asks `Docker is not
   installed in WSL 'Ubuntu'. Install Docker Engine there now? [Y/n]`. Answer `Y`, or start the
   script with `-Yes` to skip the question.
5. Wait for the `Done` step. It prints the Grafana address and the command to run on a client.
6. To accept data from other PCs, run the script again with `-EnableLan`. It asks for admin
   rights through UAC; approve it.

    ```powershell
    powershell -ExecutionPolicy Bypass -File .\setup-server.ps1 -EnableLan
    ```

The `Done` step also prints the client command for other PCs, with the server's LAN address,
whenever it finds one (also before `-EnableLan`). Use that address when you [connect a PC](clients.md).

!!! tip "Reserve the server's address"
    Reserve the server's IP address in your router's DHCP settings. If the address changes, run
    `setup-server.ps1 -EnableLan` again and re-run the client script on every PC with the new
    address.

### Windows options

| Option | What it does |
| --- | --- |
| `-Mode <mode>` | Where Docker runs: `auto` (default), `desktop` or `wsl`. `auto` uses Docker Desktop if it answers, otherwise a WSL distro; the other two skip the detection |
| `-Distro <name>` | The WSL distro for `wsl` mode (default `Ubuntu`) |
| `-EnableLan` | Accept data from other PCs: firewall rules and, for WSL, port forwards (admin rights through UAC) |
| `-LanIp <address>` | The LAN address to use and print, when the script detects the wrong one |
| `-Yes` | Install Docker into WSL without asking |

---

## Install on Linux

1. Get the repository and open its folder:

    ```bash
    git clone https://github.com/IlorDash/cc-telemetry.git
    cd cc-telemetry
    ```

2. Run the script as your normal user, not with `sudo`. By default the server is reachable from
   the LAN, because Linux servers are usually headless:

    ```bash
    bash setup-server.sh
    ```

    To keep everything on this PC only:

    ```bash
    bash setup-server.sh --local-only
    ```

3. Answer the questions. The script asks before it uses `sudo`: to install Docker, to enable the
   `docker` service at boot, and to add firewall rules. `--yes` answers yes to all of them.
4. Wait for the `Done` step. It prints the Grafana address, the client command for Windows and
   the client command for Linux, with the server's address filled in.

If you are not in the `docker` group, the script runs Docker through `sudo` and says so. To stop
needing that, run `sudo usermod -aG docker $USER` and log in again.

### Linux options

| Option | What it does |
| --- | --- |
| `--local-only` | Publish 4317, 4318 and Grafana on this PC only (`OTLP_BIND` and `GRAFANA_BIND` = `127.0.0.1` in `.env`) |
| `--lan` | Publish them on all interfaces again after an earlier `--local-only`. `--enable-lan` is the same |
| `--lan-ip <addr>` | The LAN address to report, when the script detects the wrong one |
| `--grafana-port <n>` | Host port of Grafana, 1-65535, default 3000. Kept as `GRAFANA_PORT` in `.env`; use it when 3000 is taken |
| `--clickhouse-version <tag>` | ClickHouse image tag, kept as `CLICKHOUSE_VERSION` in `.env` (default 25.8). A change between 22.3 and a newer version is refused while there is data, see [Change the ClickHouse version](maintenance.md#change-the-clickhouse-version) |
| `--update` | Update a running server without losing data. See [Maintenance](maintenance.md#update-the-server) |
| `--yes` | Do not ask before installing Docker, using `sudo` or enabling the service. `-y` is the same |
| `--help` | Print the options. `-h` is the same |

`--local-only` and `--lan` exclude each other. An unknown option stops the script with `Unknown
option: <option>` and the option list.

### Ports and access on Linux

| You run | Result |
| --- | --- |
| `bash setup-server.sh` | 4317, 4318 and Grafana are published on all interfaces; the script adds `ufw` or `firewalld` rules for them (whichever is active, after asking) |
| `bash setup-server.sh --local-only` | The three ports stay on this PC |
| `bash setup-server.sh --lan` | Back to all interfaces |

Docker publishes ports through its own `iptables` rules, which `ufw` and `firewalld` do not
filter. The script therefore controls access with the address each port is published on: the
lines `OTLP_BIND` (ports 4317 and 4318) and `GRAFANA_BIND` (Grafana) in `.env`, each `0.0.0.0`
(every PC that can reach this host) or `127.0.0.1` (this PC only). The firewall rules only let
the traffic in; they do not limit who can connect.

A re-run without `--lan` or `--local-only` keeps the values already in `.env`, so it does not
change who can connect. `--local-only` does not remove firewall rules added earlier: remove them
yourself with `ufw delete allow <port>/tcp` or `firewall-cmd --remove-port=<port>/tcp`.

!!! warning "An older `.env` without `GRAFANA_BIND`"
    The one case where a re-run (or `--update`) changes the exposure: `.env` from an older
    version of the script has `OTLP_BIND` but no `GRAFANA_BIND`. The script then copies
    `OTLP_BIND` into `GRAFANA_BIND`. With `OTLP_BIND=0.0.0.0`, Grafana, which was local-only
    before, becomes reachable from the LAN, and the script prints
    `WARN GRAFANA_BIND was missing and OTLP_BIND=0.0.0.0: Grafana is now published on 0.0.0.0,
    reachable from the LAN (it was local-only before). To keep it on this PC: re-run with
    --local-only.`

    To keep Grafana on this PC and leave the OTLP ports as they are, set `GRAFANA_BIND=127.0.0.1`
    in `.env` and run the script again: it keeps the value. `--local-only` also closes 4317 and
    4318.

!!! note "Starting the stack without the script"
    With a plain `docker compose up -d`, the values missing from `.env` fall back to the compose
    defaults: with no `OTLP_BIND`, ports 4317 and 4318 are published on `0.0.0.0` (`ufw` and
    `firewalld` do not stop it), and with no `GRAFANA_BIND`, Grafana is published on `127.0.0.1`.
    To keep the OTLP ports on this PC, add `OTLP_BIND=127.0.0.1` to `.env` first.

!!! warning "Trusted network only"
    Grafana is plain HTTP behind the `admin` login. OTLP (4317 and 4318) has no authentication.
    Use LAN mode on a trusted home or office network only. Otherwise use `--local-only`.

!!! note "Raspberry Pi 4 and other old ARM CPUs"
    ClickHouse images newer than 22.3 stop with `Illegal instruction` on an ARM CPU without the
    `lrcpc` feature. On such a CPU the script writes `CLICKHOUSE_VERSION=22.3.20.29` to `.env`
    and warns. ClickHouse 22.3 is long out of support: use it on a trusted LAN only.
    With 22.3 the script also writes the settings of a small server: a retention of 180 days
    instead of 365 (`RETENTION_DAYS`), and resource limits for ClickHouse (`CLICKHOUSE_LIMITS=small`,
    `CLICKHOUSE_CPUS=2`). See [Disk use and retention](maintenance.md#disk-use-and-retention) and
    [Resource limits and logs](maintenance.md#resource-limits-and-logs).

---

## What the script does

| Step | Windows | Linux |
| --- | --- | --- |
| 1. Docker | Finds Docker Desktop, or Docker Engine in WSL; offers to install it in WSL | Checks that `docker`, the compose plugin and the daemon answer; offers to install them on Debian and Ubuntu |
| 2. `.env` | Creates it with random passwords; an existing `.env` is kept | The same, and writes `OTLP_BIND`, `GRAFANA_BIND` and `GRAFANA_PORT`, and the keys `RETENTION_DAYS`, `CLICKHOUSE_LIMITS` and `CLICKHOUSE_CPUS` when they are missing |
| 3. Stack | Starts it and waits until the `cc.*` views are created | Stops if the Grafana port is taken (a busy 4317 or 4318 is only a warning), then starts the stack, waits for the views and applies the retention TTL (see [Disk use and retention](maintenance.md#disk-use-and-retention)) |
| 4. Checks | Grafana on `localhost:3000`, OTLP on `localhost:4317` and `localhost:4318` | The same on the published addresses; also checks that the `docker` service starts at boot |
| 5. After that | WSL only: starts a hidden keepalive and adds it to the Startup folder (`cc-telemetry-keepalive.vbs`), so WSL does not stop the stack | LAN mode: firewall rules and the server's LAN address |
| 6. `-EnableLan` | Firewall rules for TCP 4317 and 4318 (Private networks) and, for WSL, a port forward of both from the LAN address | (part of step 5) |

On Windows, Grafana is published on `localhost` only; the script never opens it to the LAN.

Re-run the script whenever you want a quick health check. It never regenerates `.env` and
never removes data.

---

## Check that it works

1. Open `http://localhost:3000` on the server PC. On a Linux server reachable from the LAN, other
   PCs open `http://<server-ip>:3000`, with your `GRAFANA_PORT` if you changed it.
2. Log in as `admin`. The password is `GRAFANA_ADMIN_PASSWORD` in the `.env` file in the
   `cc-telemetry` folder.
3. The **Overview** dashboard opens as the home page. It is empty until a PC sends its first
   events.
4. Check the containers (on a Windows server with Docker in WSL, put `wsl -d Ubuntu --` in front):

    ```bash
    docker compose ps
    ```

    Every service is `Up`, and `views-init` is `Exited (0)`.

---

## If it fails

!!! warning "If it fails"
    The script prints `FAIL <message>` and stops, or `WARN <message>` and goes on. Fix the cause
    and run the script again.

    | Message | Cause | What to do |
    | --- | --- | --- |
    | `No Docker found. Install Docker Desktop (Windows 10 22H2+ / Windows 11), or on older Windows install WSL2 with Ubuntu (admin: wsl --install -d Ubuntu), reboot, and run this script again.` | Windows: neither Docker Desktop nor a WSL distro was found | Install one of them, then run the script again |
    | `Docker Desktop is not running. Start it and run this script again.` | Windows: `-Mode desktop`, and Docker does not answer | Start Docker Desktop and wait until it is ready |
    | `WSL distro 'Ubuntu' not found (wsl -l -v). Use -Distro <name>.` | Windows: no distro of that name | Pass the name from `wsl -l -v` as `-Distro` |
    | `systemd is off in WSL 'Ubuntu'. Add to /etc/wsl.conf:  [boot]  systemd=true  then run 'wsl --terminate Ubuntu' and this script again.` | Windows: the script cannot install Docker without systemd | Do what the message says |
    | `Docker installation in WSL failed, see the output above.` or `Docker installation failed, see the output above.` | The Docker installer failed | Read the output above the message and fix that error |
    | `Docker was installed but does not answer. Run: wsl -d <distro> -- docker info` | Windows: Docker is installed in WSL but does not start | Run the command from the message and read the error |
    | `Docker is installed but does not answer. Start it: sudo systemctl start docker, then run this script again.` | Linux: the daemon is stopped | Start it and run the script again |
    | `No permission to use Docker and sudo is not available. Add yourself to the docker group (sudo usermod -aG docker $USER), log in again and re-run.` | Linux: you are not in the `docker` group and there is no `sudo` | Do what the message says |
    | `Docker (with the compose plugin) is missing. Install Docker Engine and the compose plugin for your distribution (https://docs.docker.com/engine/install/), then run this script again.` | Linux: not Debian or Ubuntu, so the script does not install Docker | Install Docker Engine and the compose plugin, then run the script again |
    | `Docker is required.` | You answered `n` to the Docker installation, or there was no terminal to ask | Run again and answer `Y`, or use `-Yes` / `--yes` |
    | `TCP port 3000 is already in use by another program, so Grafana cannot publish it. Pick a free port, for example: bash setup-server.sh --grafana-port 3001` | Linux: another program uses the Grafana port | Run with `--grafana-port 3001`; the port is kept in `.env` |
    | `TCP port <p> is already in use by another program: the collector cannot start until it is freed.` | Linux: warning; another program holds 4317 or 4318 | Stop that program. The OTLP ports cannot be changed |
    | `docker compose up failed, see the output above.` or `docker compose <args> failed (exit <n>)` | The stack did not start | Read the Docker error above the message |
    | `views-init did not finish cleanly (<state>)` | The `cc.*` views were not created; the script prints the `views-init` log first | Read that log; run the script again |
    | `Grafana does not answer yet; check: docker compose logs grafana` | Warning; Grafana is still starting, or its ClickHouse plugin could not be downloaded | Wait a minute and open Grafana; with no internet on the first start, restore it and run `docker compose restart grafana` |
    | `localhost:<port> is closed; check: docker compose logs otel-collector` | Warning; the collector does not listen on that port | Read the collector log |
    | `admin rights were not granted; LAN access is not configured` | Windows: you declined the UAC prompt | Run with `-EnableLan` again and approve it |
    | `Could not find the LAN address. Re-run with -LanIp <address>.` | Windows: no network adapter with a default gateway was found | Pass the address as `-LanIp`. On Linux the same warning asks for `--lan-ip <address>` |
    | `network '<alias>' is Public, the firewall rule does not apply to it. ...` | Windows: the firewall rule covers Private networks only | If this is your own home or office network, run the command the message prints, as admin |
    | `<address>:<port> is not reachable yet` | Warning; the firewall, the port forward or the address is not right yet | Run again; check the network profile and the address |
    | `--local-only and --lan exclude each other` | Linux: you passed both options | Pass one of them |
    | `--lan-ip '<value>' is not an IPv4 address (like 192.168.1.10)` | Linux: the value is not an IPv4 address | Pass an address like `192.168.1.10` |
    | `--grafana-port '<value>' is not a port number (1-65535)` | Linux: the value is not a port number | Pass a number from 1 to 65535 |
    | `--clickhouse-version '<value>' is not an image tag (like 25.8 or 22.3.20.29)` | Linux: the value is not a valid image tag | Pass a tag like `25.8` |

→ More symptoms are on [the Troubleshooting page](troubleshooting.md), updating and backups on
[the Maintenance page](maintenance.md), and what the stack stores on
[the Data and privacy page](data.md). Next: [connect a PC](clients.md).
