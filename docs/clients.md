# Connect a PC

Run the client script on every PC whose Claude Code sessions you want to see, the server PC
included. The script changes only your own user's files and needs no extra software: Claude Code
exports the events itself.

## Before you start

| You need | Details |
| --- | --- |
| Claude Code | Version **2.1.310 or newer**: older versions do not put `agent_id` on tool events. Check with `claude --version`, update with `claude update` |
| The server address | The LAN address the server script printed, or `localhost` on the server PC itself |
| The client script | [`client/setup-client.ps1`](https://github.com/IlorDash/cc-telemetry/blob/main/client/setup-client.ps1) (Windows) or [`client/setup-client.sh`](https://github.com/IlorDash/cc-telemetry/blob/main/client/setup-client.sh) (Linux). It is the only file a client needs: copy it to the PC |
| Windows | Windows PowerShell 5.1, nothing else |
| Linux | `python3` or `jq` 1.6 or newer. The session hook also needs bash 4+, GNU `find`, and `curl` or `python3` |
| Network | Ports `4317` and `4318` of the server reachable from this PC (see [the server page](server.md)) |

---

## Install on Windows

1. Copy `setup-client.ps1` to the PC.
2. Run it with the server address. `-Project` is optional and takes the folders to label with
   their name (see [Project](#project)):

    ```powershell
    powershell -ExecutionPolicy Bypass -File .\setup-client.ps1 -ServerIp <server-ip> -Project C:\Projects\ProjA, C:\Projects\ProjB
    ```

3. Read the last lines. Both connection tests should say `reachable: True`.
4. Open any project folder you listed in `-Project` in Claude Code once and accept the trust
   dialog, if you never opened it on this PC.
5. Restart running Claude Code sessions: in VS Code run **Developer: Reload Window**; in the
   terminal exit and continue with `claude -c`. Settings are read when a session starts.
6. Make any request, then [check that events arrive](#check-that-events-arrive).

### Windows options

| Option | What it does |
| --- | --- |
| `-ServerIp <address>` | The server's address. Required; letters, digits, `.`, `_`, `-` |
| `-Project <folder>, ...` | Folders to label explicitly with their name. Add more later by running the script again with other folders |
| `-PcName <name>` | The name shown as `host`. Default: the computer name; letters, digits, `.`, `_`, `-` |
| `-SettingsDir <name>` | The project settings folder, if it is not `.claude` |
| `-UserSettings <file>` | The user settings file. Default: `%USERPROFILE%\.claude\settings.json`; the hook folder goes next to it |
| `-ImportHistory` | Once: upload title, branch and folder of the sessions already on this PC |
| `-NoSessionMeta` | Do not install the session hook; on a re-run it removes the hook and its files |
| `-WhatIf` | Show the result and write nothing |

---

## Install on Linux

1. Copy `setup-client.sh` to the PC.
2. Run it as your normal user, without `sudo`. Repeat `--project` for more folders:

    ```bash
    bash setup-client.sh --server-ip <server-ip> --project ~/projects/ProjA --project ~/projects/ProjB
    ```

3. Read the last lines. Both connection tests should say `reachable: True`.
4. Open each folder you listed with `--project` in Claude Code once and accept the trust dialog,
   if you never opened it on this PC.
5. Restart running Claude Code sessions: in VS Code run **Developer: Reload Window**; in the
   terminal exit and continue with `claude -c`.
6. Make any request, then [check that events arrive](#check-that-events-arrive).

### Linux options

| Option | What it does |
| --- | --- |
| `--server-ip <addr>` | The server's address. Required; `localhost` on the server PC itself |
| `--project <dir>` | A folder to label explicitly with its name. Repeat for more; add more later by running the script again |
| `--pc-name <name>` | The name shown as `host`. Default: `hostname -s`; letters, digits, `.`, `_`, `-` |
| `--settings-dir <dir>` | The project settings folder, if it is not `.claude` |
| `--user-settings <file>` | The user settings file. Default: `~/.claude/settings.json`; the hook folder goes next to it |
| `--import-history` | Once: upload title, branch and folder of the sessions already on this PC |
| `--no-session-meta` | Do not install the session hook; on a re-run it removes the hook and its files |
| `--dry-run` | Show the result and write nothing |
| `--help` | Print the options. `-h` is the same |

`--import-history` cannot be combined with `--no-session-meta`, and the same holds for
`-ImportHistory` and `-NoSessionMeta` on Windows. The Linux script checks every file before it
writes the first one, so a bad input changes nothing.

---

## What the script changes

| What | Windows | Linux |
| --- | --- | --- |
| Telemetry keys (the `env` section) | `%USERPROFILE%\.claude\settings.json` | `~/.claude/settings.json` |
| Session hook entry (`hooks.UserPromptSubmit`) | the same file | the same file |
| Hook script and its state file | `%USERPROFILE%\.claude\cc-telemetry\session-meta.ps1` and `session-meta.state.json` | `~/.claude/cc-telemetry/session-meta.sh` and `session-meta.state` |
| Project label | `<project>\.claude\settings.local.json`, only for the `-Project` folders (created if missing) | `<project>/.claude/settings.local.json`, only for the `--project` folders (created if missing) |
| Backup | `<file>.bak`, saved before the first change | the same |

Every other key in these files (permissions, model, plugins, other hooks) stays as it was. The
script checks that the result is valid JSON; the files are re-indented, the content stays the
same. Nothing outside your own user is touched.

The keys the script writes to `env`:

| Key | Value |
| --- | --- |
| `CLAUDE_CODE_ENABLE_TELEMETRY` | `1` |
| `OTEL_LOGS_EXPORTER` | `otlp` |
| `OTEL_METRICS_EXPORTER` | `otlp` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://<server-ip>:4317` |
| `OTEL_LOG_TOOL_DETAILS` | `1` (file paths, search patterns and Bash commands are sent) |
| `OTEL_LOG_USER_PROMPTS` | `1` (your prompts are sent) |
| `OTEL_LOGS_EXPORT_INTERVAL` | `2000` |
| `OTEL_RESOURCE_ATTRIBUTES` | `project=unknown,host=<PC name>`; in a `-Project` folder: `project=<folder name in lower case>,host=<PC name>` |

The script is safe to run again: it updates its own keys and its own hook entry in place and
never duplicates them. Run it again with a new address when the server's address changes.

!!! note "What is sent"
    `OTEL_LOG_USER_PROMPTS=1` sends your prompts. The same switch also makes Claude Code send
    its replies; the server drops the reply text before storing it. The full list of what is
    collected is on [the Data and privacy page](data.md).

### Undo

| You want to | Do this |
| --- | --- |
| Remove the session hook | Run the script again with `-NoSessionMeta` (Windows) or `--no-session-meta` (Linux). It deletes the `UserPromptSubmit` entry and the hook script and state file, and the `cc-telemetry` folder next to `settings.json` once it is empty |
| Stop the telemetry | Delete the keys above from `env` in `settings.json` (and `OTEL_RESOURCE_ATTRIBUTES` from the project `settings.local.json`), or restore `<file>.bak`. The script has no switch for this |

!!! note "`-NoSessionMeta` keeps the telemetry on"
    It removes the hook only: Claude Code keeps sending its telemetry. `<file>.bak` holds the
    file as it was before the first run, so restoring it also drops later changes to that file.

---

## Session titles, git branch and working directory

Claude Code's telemetry carries neither the session title, nor the git branch, nor the working
directory. They exist only in the local session files (`~/.claude/projects/*/<session>.jsonl`;
`%USERPROFILE%\.claude\projects` on Windows). Unless you disable it, the script therefore adds a
`UserPromptSubmit` hook to the user `settings.json`. It runs in the background (`async`, so it
does not delay your prompt) and your other hooks stay.

On every prompt the hook sends the session title (the `/rename` title, otherwise Claude Code's
automatic title), the git branch, the first working directory and the Claude Code version of the
current session and of the sessions that changed since the last run. It sends them to
`<server-ip>:4318`, and only when something changed. It never reads or sends prompts or replies.

| Situation | What happens |
| --- | --- |
| A new session | Claude Code generates the title after the first prompt, so it reaches the server with the next prompt, in any session |
| `/rename` | Picked up with the next prompt |
| The server is unreachable | After a failed send the hook does nothing for 10 minutes, then tries again with the same sessions |
| Sessions that already exist | Claude Code keeps session files about 30 days. Run the script once with `-ImportHistory` / `--import-history` to upload title, branch and folder of the sessions already on the PC. It sends nothing else from them |
| You do not want the hook | Run the script with `-NoSessionMeta` / `--no-session-meta` |

---

## Project

The project name in the dashboards is decided on the server, per session, in this order:

| Order | Source | Result |
| --- | --- | --- |
| 1 | An explicit label: `project=<name>` from `OTEL_RESOURCE_ATTRIBUTES`, written by `-Project` / `--project` | Used as is. Use it for projects whose sessions touch no files (pure chat, MCP only) and where the guess is wrong |
| 2 | The first working directory of the session, sent by the hook | Its folder, by the same folder rules as in the next row. Sessions from before the hook get it after `-ImportHistory` / `--import-history`, while their session files still exist |
| 3 | The absolute file paths of the session's tool calls | The folder name (lower case) that appears most often, ties broken alphabetically |
| 4 | None of the above | `unknown` |

How the folder is taken from a path: it is the first path segment after your home directory and
generic containers such as `Documents`, `projects`, `src`, `dev`, `work`, `repos`, `github`.
`C:\Users\me\Documents\Projects\Alpha\a.cpp` and `/home/me/src/alpha/a.cpp` both give `alpha`.
Paths in hidden folders (`~/.claude`), temp and system folders are ignored. A worktree folder
`alpha-feature` counts as `alpha` when `alpha` is also known; this is a name-prefix guess, so it
can merge different projects whose names share a prefix (`my` and `my-app`). An explicit
`-Project` / `--project` label avoids it.

!!! note "Files attached with `@` do not count"
    Claude Code inlines them without a tool call, and the event carries no path. A session that
    only has `@` attachments and no label ends up as `unknown`.

A project in an unusual layout (folders directly under `/data/x/y/`) is named after the first
folder (`data`): label it with `--project`. The project is computed on every query, so sessions
recorded earlier get it too.

Only sessions started after the setup are recorded. Telemetry is sent live: past sessions are
not uploaded (`-ImportHistory` adds only title, branch and folder to sessions the server already
knows), and events produced while the server is unreachable are dropped after a short retry.

---

## Check that events arrive

1. Restart the Claude Code sessions, then make any request.
2. Open Grafana (see [the server page](server.md)) and look at the **Overview** dashboard. Within
   a few seconds the session appears.
3. The project shows in the **Project** dropdown once the session has touched a file or its
   working directory has arrived through the hook, or at once with an explicit label.

---

## If it fails

!!! warning "If it fails"
    Fix the cause and run the script again. It is safe to repeat.

    | Message or symptom | Cause | What to do |
    | --- | --- | --- |
    | The script cannot be run (execution policy) | Windows blocks unsigned scripts | Start it exactly as shown, through `powershell -ExecutionPolicy Bypass -File ...` |
    | `server <address>:4317 reachable: False` | The server is down, the address is wrong, or the port is closed on the server | Check the address; on the server run its script again (Windows: with `-EnableLan`; Linux: without `--local-only`) |
    | `server <address>:4318 (session titles) reachable: False` and `Session titles are sent only once port 4318 is reachable (update and re-run the server setup).` | Port 4318 is closed; a server set up before the session hook existed has 4317 only | Run the server script again (Windows: `-EnableLan`; Linux: without `--local-only`), then this script |
    | `ERROR: --server-ip is required` | Linux: no server address | Pass `--server-ip <address>` |
    | `ERROR: --server-ip '<value>' must be a host name or IPv4 address` or `ERROR: --pc-name '<value>' may contain only letters, digits, . _ -` | Linux: a value with other characters | Use letters, digits, `.`, `_`, `-` |
    | `ERROR: python3, or jq 1.6 or newer, is required to edit the JSON settings. Install one (for example: sudo apt install jq) and run again.` | Linux: no tool to edit the JSON | Install `python3` or `jq` |
    | `ERROR: project folder not found: <dir>` | Linux: a `--project` folder does not exist. On Windows PowerShell reports that it cannot find the path | Fix the path |
    | `ERROR: cannot merge into <file> (is it valid JSON?)` | Linux: the settings file is not valid JSON or not an object. On Windows PowerShell reports the JSON parse error | Fix the file by hand; the script has not changed it |
    | `ERROR: cannot change the hooks in <file> (unexpected "hooks" layout?)` | Linux: `hooks` or its `UserPromptSubmit` list in the settings has an unexpected type. On Windows the script stops with `"hooks" is not an object` or `hooks.UserPromptSubmit is not an array` | Fix `hooks` in the settings file by hand |
    | `ERROR: <file> is not valid JSON after the update; restore it from <file>.bak` | Linux: the write went wrong | Restore the file from `<file>.bak` and report it |
    | `-ImportHistory cannot be combined with -NoSessionMeta` (Windows), `ERROR: --import-history cannot be combined with --no-session-meta` (Linux) | Both options were passed | Pass one of them |
    | `import failed (exit code <n>)` | Windows: the history import failed | Run the script again with `-ImportHistory` |
    | `Unknown option: <option>` | Linux: a mistyped option | Check the options table |
    | Nothing appears in Grafana | The session was not restarted, Claude Code is older than 2.1.310, or a `-Project` folder was never trusted | Restart the session; check `claude --version`; open the folder once in Claude Code and accept the trust dialog |

→ More symptoms are on [the Troubleshooting page](troubleshooting.md), and what is collected on
[the Data and privacy page](data.md). Back to [the server](server.md).
