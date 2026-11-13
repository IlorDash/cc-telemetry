"""PreToolUse hook: keep agents away from the stack's secrets and the telemetry dumps.

  - .env       ClickHouse and Grafana passwords (in clear text)
  - backup/    dumps of otel.* tables made by wsl/backup.sh: the user's prompts,
               file paths, Bash commands, account email
Read(...) deny rules cover only the Read/Grep/Glob tools, and Bash(...) rules
only match the start of a command; native Windows has no Bash sandbox. This hook
checks the whole Bash / PowerShell command and the paths of Read/Grep/Glob.

Scripts that need the passwords read .env themselves (wsl/ch.sh,
claude-context/scripts/check-dashboard.js) - their command lines do not name it.

It is a text heuristic, not a boundary: a deliberately obfuscated name gets
through. It stops the accidental cat/type/Get-Content/grep of these files.

Exit 0 = no decision (normal permission flow), exit 2 = block, reason on stderr.
Unparsable input is blocked too (fail closed).
"""

import json
import re
import sys

SECRET_PATTERNS = [
    # .env as a file name: not .env.example, not $env:NAME, not a .envrc
    re.compile(r"(^|[\s\"'=/\\(])\.env(?![\w.-])", re.IGNORECASE),
    # the backup/ folder (wsl/backup.sh itself is fine: "backup." not "backup/")
    re.compile(r"(^|[\s\"'=/\\(])backup[/\\]", re.IGNORECASE),
    re.compile(r"(^|[\s\"'=/\\(])backup[\"']?\s*$", re.IGNORECASE),
]

# Commands that may name the files without reading them. Only single commands -
# no chaining, pipes, redirection or substitution that could append a read.
ALLOWED_PREFIXES = (
    "ls ",
    "Test-Path ",
    "git check-ignore ",
    "git status",
)
CHAINING = re.compile(r"[;&|<>`]|\$\(")


def block(reason):
    sys.stderr.write(
        "Blocked by guard-secrets hook: " + reason + ". .env holds the stack passwords and "
        "backup/ holds the user's telemetry dumps; do not read them. Use wsl/ch.sh or "
        "claude-context/scripts/check-dashboard.js, which read .env themselves, or ask the user.\n"
    )
    sys.exit(2)


def names_secret(text):
    return any(p.search(text) for p in SECRET_PATTERNS)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        block("hook input is not valid JSON")

    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input") or {}

    if tool in ("Bash", "PowerShell"):
        command = (tool_input.get("command") or "").strip()
        if not names_secret(command):
            sys.exit(0)
        if command.startswith(ALLOWED_PREFIXES) and not CHAINING.search(command):
            sys.exit(0)
        block("the command names a secret file")

    if tool in ("Read", "Grep", "Glob"):
        for key in ("file_path", "path", "glob", "pattern" if tool == "Glob" else None):
            if key and names_secret(str(tool_input.get(key) or "")):
                block(tool + " targets a secret file")
        sys.exit(0)

    sys.exit(0)


if __name__ == "__main__":
    main()
