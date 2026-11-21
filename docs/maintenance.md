# Maintain the server

This page covers what you do with a running server: update it, check it, back up and restore the
data, change its settings, and stop or remove it. Problems are on
[the Troubleshooting page](troubleshooting.md).

Run every command from the `cc-telemetry` folder on the server PC.

| Your server | How to run the `docker compose ...` and `bash linux-server-tools/...` commands |
| --- | --- |
| Linux | As they are. Add `sudo` if you are not in the `docker` group |
| Windows | Put `wsl -d Ubuntu --` in front, from PowerShell (use your distro name if it is not `Ubuntu`) |

---

## Check the stack

```bash
docker compose ps
```

Every service is `Up` and `views-init` is `Exited (0)`. `views-init` is a one-shot job that
creates the `cc.*` tables and views, so it is not supposed to keep running. `cc-refresh` starts
after it and rebuilds two small tables every 5 minutes (see [How the views are
built](#recreate-the-views)); its log says `refresh ok` after each run.

Logs of one service (add `-f` to follow them, `--tail 100` for the last lines):

```bash
docker compose logs otel-collector
docker compose logs clickhouse
docker compose logs grafana
docker compose logs views-init
docker compose logs cc-refresh
```

The collector log is the first place to look when events do not arrive; it says
`Everything is ready` after a start.

Running the server script again is also a health check: it never regenerates `.env` and never
removes data. It prints `FAIL` for what is wrong and `WARN` for what is only suspicious.

To run SQL without typing the password, pipe it into `ch.sh`. The password is read from `.env`
and never printed:

```bash
echo "SELECT event, count() FROM cc.events GROUP BY event" | bash linux-server-tools/ch.sh
```

```powershell
"SELECT event, count() FROM cc.events GROUP BY event" | wsl -d Ubuntu -- bash linux-server-tools/ch.sh
```

---

## Update the server

An update moves the server to a newer version of this repository. Your data is in the
`clickhouse-data` volume and is never removed by an update.

### Linux

Run in the `cc-telemetry` folder, with the options you normally use:

```bash
bash setup-server.sh --update
```

!!! note "The first time, run `git pull` yourself"
    Versions of the script from before `--update` existed do not know the option. Run `git pull`
    once, then use `--update` from then on.

The command goes through these steps and stops at the first problem:

| Step | What it does | When it refuses |
| --- | --- | --- |
| Checks | Looks for `.env`, asks ClickHouse a test question and checks the git working tree | `.env` is missing (this folder is not a configured server yet); ClickHouse does not answer; tracked files have local changes (`.env` and `backup/` are git-ignored and do not count) |
| Safety dump | Writes every `otel.*` table to `backup/pre-update-<date>-<time>/` and the row count of each table next to it. Earlier dumps stay | The free disk space is less than the uncompressed size of the data (the dump is that large); it warns when there is less than 1.5 times that. It also stops when it cannot create the folder or the dump fails |
| Code | Runs `git pull --ff-only`. It never merges or rebases | The pull fails (a diverged branch, no network): nothing on the stack has changed. With no upstream branch or no git repository it only warns and goes on with the files as they are |
| Server script | Runs `setup-server.sh` again from the updated file with your other options: starts changed containers, recreates the `cc.*` views (and copies the events missing from `cc.events_t`), applies the retention TTL (see [Disk use and retention](#disk-use-and-retention)), repeats the checks. If `otel-collector.yaml` or a file under `grafana/provisioning/` is newer than the running container (it compares file times with the container start, so it works also when you ran `git pull` before `--update`), it restarts that service; a changed `grafana/provisioning/` is also what makes the `ru` folder with the Russian dashboard copies appear on an older server. Dashboard files are re-read by Grafana by itself | The usual install errors, see [the server page](server.md#if-it-fails) |
| Data check | Before the dump it fixes a cutoff, the retention minus one day ago (179 days for 180), and counts the rows younger than that in every table; after the update it counts them again with the same cutoff. Older rows may be removed by the retention TTL: it only reports how many | A table has fewer rows younger than the cutoff: a `FAIL` banner with the dump folder, exit status 1 |

On success it prints `update finished, no data lost` with the dump folder and the rollback
command. The dump folders are not deleted for you: delete old `pre-update-*` folders yourself
when you no longer need them. If Docker runs through `sudo`, the dump files belong to root.

An update also publishes port `4318` and opens it in the firewall on a LAN server, so an older
server gets it too.

!!! warning "Grafana on an older server"
    When `.env` has `OTLP_BIND=0.0.0.0` but no `GRAFANA_BIND` (written by an older version of
    the script), the update publishes Grafana on `0.0.0.0` as well and prints `WARN GRAFANA_BIND
    was missing and OTLP_BIND=0.0.0.0: Grafana is now published on 0.0.0.0, reachable from the
    LAN (it was local-only before) ...`. To keep Grafana on this PC, set `GRAFANA_BIND=127.0.0.1` in
    `.env` and run `bash setup-server.sh` again, or pass `--local-only` to close the OTLP ports
    too. See [the server page](server.md#ports-and-access-on-linux).

### Windows

The Windows script has no `--update`. Pull the new version and run the script again:

```powershell
git pull
powershell -ExecutionPolicy Bypass -File .\setup-server.ps1
```

The script starts changed containers and recreates the `cc.*` views. It does not change the
retention TTL of existing tables: see [Change the retention](#change-the-retention) for the
manual steps. It restarts `otel-collector` or `grafana` when
`otel-collector.yaml` or a file under `grafana/provisioning/` is newer than the running container,
so a pulled configuration is loaded; a file that was only touched costs one extra restart of a few
seconds. On a server set up before the Russian dashboards existed, that restart is what makes
Grafana show the folder `ru` with their copies. To restart a service yourself (add the WSL prefix
when Docker runs in WSL):

```bash
docker compose restart otel-collector grafana
```

There is no automatic safety dump on Windows. If you want one, [dump the data
yourself](#back-up-and-restore) before `git pull`. To pick up only a change in
`clickhouse/views.sql`, you do not need the whole script:

```bash
docker compose run --rm views-init
```

A server set up before the session hook existed needs `setup-server.ps1 -EnableLan` once more
to open port `4318`.

### Roll back

The `--update` output ends with the previous commit. To return to it:

```bash
git checkout <previous commit>
bash setup-server.sh
```

On Windows, run `setup-server.ps1` instead of `setup-server.sh`. The data stays in the volume,
so a rollback needs no restore. After a rollback, run `git checkout main` so that the next
`--update` has an upstream branch to pull (on a detached `HEAD` nothing is pulled).

---

## Back up and restore

`linux-server-tools/backup.sh` dumps every `otel.*` table to a `<table>.native` file in the
`backup` folder (ClickHouse Native format). The `cc.*` tables and views are not dumped: they are
rebuilt from `otel.otel_logs` by `views-init` and `cc-refresh`.

```bash
bash linux-server-tools/backup.sh dump              # otel.* tables -> backup/<table>.native
bash linux-server-tools/backup.sh restore           # appends rows: use on a fresh, empty stack
bash linux-server-tools/backup.sh restore <table>   # one table only
```

On a Windows server with Docker in WSL, from PowerShell:

```powershell
wsl -d Ubuntu -- bash linux-server-tools/backup.sh dump
```

`BACKUP_DIR=<folder>` in front of the command uses another folder for dump and restore. A
relative folder is relative to the `cc-telemetry` folder, not to the current directory:

```bash
BACKUP_DIR=backup/pre-update-<date>-<time> bash linux-server-tools/backup.sh restore otel_logs
```

If Docker needs `sudo`, the variable is lost after it. Pass it through `env`:

```bash
sudo env BACKUP_DIR=backup/pre-update-<date>-<time> bash linux-server-tools/backup.sh restore
```

!!! warning "Restore appends rows"
    `restore` adds the dumped rows to what is in the table. Run it only for tables that are
    empty now, for example on a fresh stack after `setup-server.*`. On a table that already has
    rows you get duplicates. Check the row counts first.

!!! warning "The backup holds your prompts"
    `backup/` is git-ignored because the dump contains everything the stack stores, including
    prompts. Keep it where you keep other private files. With Docker in WSL the data lives
    inside the distro: `wsl --unregister` deletes it, so dump first.

The dump is in the Native format, so it is not tied to the volume. To move data to a server with
another ClickHouse version, restore it into a fresh stack and compare the row count of every
table.

---

## Change the ClickHouse version

Within one side of the 22.3 boundary the tag changes in place: `25.8` to `26.3`, or `22.3.20.29`
to another 22.3 release. Between ClickHouse 22.3 (the Raspberry Pi 4 tag) and a newer version
the existing data volume does not survive: 25.x reads the indexes of parts written by 22.3
wrongly (the dashboards fail with `CORRUPTED_DATA`), and a volume written by a newer ClickHouse
does not start on 22.3 at all. So `setup-server.sh` **refuses** such a change while the volume
holds data, or while ClickHouse does not answer and the volume exists, and stops before it
writes the tag. There is no switch to force it. Move the data through a dump:

1. Dump the data into a new folder and check that the files are not empty:
   `BACKUP_DIR=backup/version-change-<date> bash linux-server-tools/backup.sh dump`
   (with `sudo`: `sudo env BACKUP_DIR=... bash ...`). Under `--update` the dump of the update is
   already taken; the error names its folder.
2. Stop the stack: `docker compose down`, **without** `-v`. Clients cannot send until it runs again.
3. Delete the ClickHouse volume, which is the step that removes the data the dump holds:
   `docker volume rm <project>_clickhouse-data` (the exact name is in the error message;
   `docker volume ls` lists it).
4. Start with the new version: `bash setup-server.sh --clickhouse-version <tag>`, with your other options.
5. Restore: `BACKUP_DIR=backup/version-change-<date> bash linux-server-tools/backup.sh restore`.
   The restore goes through the materialized view, so `cc.events_t` is refilled by it. Compare the
   row counts of the tables with the dump.

If ClickHouse does not answer, the script cannot tell whether the volume holds data and refuses
as well. A volume that no running ClickHouse ever used (for example the container never started
on this CPU) holds no data: after `docker compose down` (no `-v`) remove it with
`docker volume rm` and run the script again. If you changed `CLICKHOUSE_VERSION` in `.env` by
hand and do not want to switch, put the old value back and run the script again.

On a Windows server with Docker in WSL, run the same commands with `wsl -d Ubuntu --` in front.
`setup-server.ps1` writes no tag, so in step 4 set `CLICKHOUSE_VERSION=<tag>` in `.env` by hand
and run `setup-server.ps1`. The script does not check the change on Windows, so do not skip
step 1.

!!! warning "Back up first"
    Step 3 deletes the only copy of the data on the server. Do it only after you have checked the dump.

---

## Recreate the views

The collector writes the raw events to `otel.otel_logs`. The dashboards read the `cc.*` views,
which do not parse those raw events on every query:

- the materialized view `cc.events_mv` flattens every new Claude Code event into the table
  `cc.events_t` as it arrives;
- the `cc.*` views are plain views over that table and over two small tables: the project of each
  session (`cc.session_project_t`) and the tips (`cc.tips_t`). The `cc-refresh` service rebuilds
  those two every 5 minutes from `clickhouse/refresh.sql`. So a new session can show the project
  `unknown` for up to 5 minutes, and the tips are as old as the last refresh.

Editing `clickhouse/views.sql` changes what the dashboards show for the whole history. Apply it
with:

```bash
docker compose run --rm views-init
```

It waits until the collector has created `otel.otel_logs`, creates the missing tables
(`schema.sql`), copies the events that `cc.events_t` does not have yet from `otel.otel_logs`, one
month at a time (`backfill.sql`), and recreates the views. It is safe to repeat. After a first
install or an update over a large history the copy takes a while. Running `setup-server.sh` or
`setup-server.ps1` does the same. If `views-init` fails, `docker compose up -d` fails too, and the
server scripts print its log.

!!! note "Changing `cc.events_mv` or the columns of `cc.events_t`"
    `views-init` creates them with `CREATE ... IF NOT EXISTS`, so a change to them is skipped on
    an existing server, and the stored rows keep the old values. Such a change needs a migration:
    dump first, then rebuild `cc.events_t` from `otel.otel_logs`, one month at a time (one insert
    over more than 100 days is refused).

Do not run `clickhouse/refresh.sql` by hand while `cc-refresh` is running.

---

## Disk use and retention

Data is kept for `RETENTION_DAYS` days, set in `.env`: a TTL removes older rows from the `otel.*`
tables and from `cc.events_t`, a whole day at a time. `setup-server.sh` writes the key when it is
missing: 180 with ClickHouse 22.3 (a Raspberry Pi 4, see [the server page](server.md#ports-and-access-on-linux)),
365 otherwise. The value is kept on later runs. `setup-server.ps1` does not write it, and without
the key the stack uses 365.

Claude Code deletes its own local session files after about 30 days, so the server keeps your
history longer than the PC does.

To see how much room the data takes:

```bash
echo "SELECT table, formatReadableSize(sum(bytes_on_disk)) AS size, sum(rows) AS rows FROM system.parts WHERE database IN ('otel', 'cc') AND active GROUP BY table" | bash linux-server-tools/ch.sh
```

The events are stored twice, raw in `otel.otel_logs` and flattened in `cc.events_t`. Deleting
data is described on [the Data and privacy page](data.md#delete-data).

### Change the retention

Edit `RETENTION_DAYS` in `.env`, then run the server script again.

| Server | What happens |
| --- | --- |
| Linux | `setup-server.sh` changes the TTL of the existing tables. A longer period needs no question. A shorter one deletes the rows older than the new period: a plain run asks at the terminal (default no; `--yes` does not answer it; without a terminal it skips the step with a warning), `--update` goes ahead after its dump |
| Windows | `views-init` sets the TTL only on `otel.*` tables that have none and have no rows older than the period. Change an existing TTL yourself (below) |

On Linux, `setup-server.sh` also lists the old system log tables (`query_log`, `text_log`,
`trace_log`, `metric_log` and the others [switched off below](#resource-limits-and-logs), with their
rotated copies `query_log_0`, ...) that an older install left behind, with rows, size and a
`DROP TABLE` command for each, and the total size; it does not delete them. If a log is still
written, the running ClickHouse has not loaded the config yet: run
`docker compose restart clickhouse` and the script again.

On Windows nothing lists them. After a restart of ClickHouse, list the tables and drop the ones you
do not need (`ch.sh` runs inside WSL):

```powershell
"SELECT name, total_rows, formatReadableSize(total_bytes) AS size FROM system.tables WHERE database = 'system' AND match(name, '_log(_[0-9]+)?$') ORDER BY total_bytes DESC" | wsl -d Ubuntu -- bash linux-server-tools/ch.sh
"DROP TABLE system.text_log SYNC" | wsl -d Ubuntu -- bash linux-server-tools/ch.sh
```

Tables of logs that you switched on yourself, and an empty one, are also in that list.

To change it by hand, run the SQL through `ch.sh` (replace `180`; dump first when the period gets
shorter):

```sql
ALTER TABLE cc.events_t MODIFY TTL toDateTime(ts) + INTERVAL 180 DAY;
ALTER TABLE otel.otel_logs MODIFY TTL TimestampTime + toIntervalDay(180);
ALTER TABLE otel.otel_metrics_sum MODIFY TTL toDateTime(TimeUnix) + toIntervalDay(180);  -- also _gauge, _histogram, _exponential_histogram, _summary
```

---

## Resource limits and logs

`CLICKHOUSE_LIMITS=small` in `.env` runs ClickHouse with limits sized for a small server such as a
Raspberry Pi 4: 3 GB of memory for the server and 1.5 GB per query, 3 threads per query, two
background merges, small caches and at most 8 queries at a time. `CLICKHOUSE_CPUS` limits the
container to that many CPU cores (`0` = no limit). `setup-server.sh` writes `small` and `2` with
ClickHouse 22.3, `none` and `0` otherwise; without the keys the stack uses `none` and `0`, which
are ClickHouse's own defaults. The limits are in `clickhouse/limits/small/`. A dashboard query that
needs more than 1.5 GB fails instead of slowing the server down.

On every server, ClickHouse writes no system logs (`query_log`, `processors_profile_log`,
`error_log`, `trace_log` and the rest that a ClickHouse version enables by default), and its
text log is kept at level `warning`, 10 MB per file and two older files
(`clickhouse/config.d/common.xml` and `clickhouse/users.d/common.xml`). The collector writes
events to ClickHouse every 30 seconds, so a new event reaches the dashboards up to 30 seconds
late.

After editing one of these XML files run `docker compose restart clickhouse`. A change of
`CLICKHOUSE_LIMITS` or `CLICKHOUSE_CPUS` needs `bash setup-server.sh` or `docker compose up -d`,
which recreates the `clickhouse` container in a few seconds; the collector retries meanwhile.

!!! tip "Find a slow panel"
    Switch `query_log` on for a while: delete the line `<query_log remove="1"/>` in
    `clickhouse/config.d/common.xml`, set `<log_queries>1</log_queries>` in
    `clickhouse/users.d/common.xml` and run `docker compose restart clickhouse`. The slow query
    is then in `system.query_log` (`query_duration_ms`, `query`). Afterwards restore both files,
    restart ClickHouse again and run `DROP TABLE system.query_log SYNC`.

---

## Change a setting

| You want to | Do this |
| --- | --- |
| Use another Grafana port (Linux) | `bash setup-server.sh --grafana-port 3001`. The port is kept as `GRAFANA_PORT` in `.env` |
| Use another Grafana port (Windows) | Not supported: the script checks and prints port `3000` only |
| Use other OTLP ports | Not supported: `4317` and `4318` are fixed |
| Keep the server on this PC only, or open it to the LAN (Linux) | `bash setup-server.sh --local-only` or `--lan`. To change only Grafana, set `GRAFANA_BIND` in `.env` (`127.0.0.1` or `0.0.0.0`) and run the script again; it keeps the value. See [the server page](server.md#ports-and-access-on-linux) |
| Open the server to the LAN (Windows) | `setup-server.ps1 -EnableLan` |
| Keep the data for another period | Set `RETENTION_DAYS` in `.env` and run the server script, see [Change the retention](#change-the-retention) |
| Switch the limits of a small server on or off | Set `CLICKHOUSE_LIMITS` (`small` or `none`) and `CLICKHOUSE_CPUS` in `.env` and run the server script, see [Resource limits and logs](#resource-limits-and-logs) |
| Use another ClickHouse version (Linux) | `bash setup-server.sh --clickhouse-version <tag>`. A change between 22.3 and a newer version is refused while there is data: see [Change the ClickHouse version](#change-the-clickhouse-version) |
| Change the Grafana admin password | The repo has no switch for it. `GRAFANA_ADMIN_PASSWORD` in `.env` is read by Grafana when it creates its database on the first start, so editing `.env` later does not change the password. Change it in Grafana (your profile), or reset it with `grafana cli admin reset-admin-password` inside the grafana container |
| Change the ClickHouse password | The repo has no switch for it. `CLICKHOUSE_PASSWORD` in `.env` is applied only when the ClickHouse volume is first created, and the collector, Grafana and `ch.sh` all read it from `.env`. Changing it later breaks the connection |

---

## Stop and remove the stack

| You want to | Command | Your data |
| --- | --- | --- |
| Stop the stack | `docker compose stop` | Kept |
| Start it again | `docker compose up -d`, or run the server script | Kept |
| Stop and remove the containers | `docker compose down` | Kept in the volumes `clickhouse-data` and `grafana-data` |
| Remove everything, data included | `docker compose down -v` | **Deleted** |

!!! warning "`down -v` deletes all collected data"
    `-v` removes the volumes, and with them every event the stack has stored and Grafana's own
    database. There is no undo. Dump first (see [Back up and restore](#back-up-and-restore)) and
    check that the dump is not empty. A plain `docker compose down` is safe.

On a Windows server with Docker in WSL, `wsl --unregister <distro>` also deletes the data.

Stopping the stack does not undo what the Windows script set up. Remove those parts yourself
when you no longer need them:

| Part | How to remove it |
| --- | --- |
| The keepalive (WSL only) | Delete `cc-telemetry-keepalive.vbs` from your Startup folder; it ends with the next sign-out or reboot |
| Firewall rules and port forwards (`-EnableLan`) | Rules named `OTLP 4317 (Claude Code telemetry)` and `OTLP 4318 (Claude Code telemetry)`, and `netsh interface portproxy` forwards for both ports. Both need admin rights |
| Firewall rules on Linux | `ufw delete allow <port>/tcp` or `firewall-cmd --remove-port=<port>/tcp` |

The clients keep sending to the server until you [undo their settings](clients.md#undo).
