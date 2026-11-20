#!/usr/bin/env python3
"""Check README.md of cc-telemetry for links and names that no longer match the repo.

  - in-page links [text](#anchor) must match a heading (GitHub slug rules);
  - relative links [text](path[#anchor]) must point to an existing file or folder;
  - repo paths in backticks (`clickhouse/views.sql`, `grafana/dashboards/`) must exist,
    when they start with a top-level name of the repo;
  - words that tie the public README to the AI setup (claude-context, the ledger, agent
    names) and every --forbid REGEX (e.g. the user's PC names, passed at run time and
    never written into a tracked file) must not appear.
Fenced code blocks are skipped (commands with placeholders); read the fences yourself.

Usage: check-readme.py [--root DIR] [--file README.md] [--forbid REGEX]...
Exit status: 0 clean, 1 problems found, 2 cannot read the file.
"""

import argparse
import re
import sys
from pathlib import Path

# CLAUDE.md and ~/.claude are Claude Code features the README may explain; the project's own
# AI setup folder and its files are not.
BANNED = [r"claude-context", r"pending-bugs", r"server-state", r"\.wt-ledger", r"context-auditor", r"docs-auditor", r"mr-reviewer"]
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
CODE_SPAN = re.compile(r"`([^`\n]+)`")
FENCE = re.compile(r"^\s*(```|~~~)")


def slug(heading):
    s = heading.strip().lower()
    s = re.sub(r"`", "", s)
    s = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", s)
    s = re.sub(r"[^\w\- ]", "", s, flags=re.UNICODE)
    return s.replace(" ", "-")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--file", default="README.md")
    ap.add_argument("--forbid", action="append", default=[])
    a = ap.parse_args()
    for rx in a.forbid:
        try:
            re.compile(rx)
        except re.error as e:
            print(f"error: bad --forbid regex {rx!r}: {e}", file=sys.stderr)
            return 2

    root = Path(a.root).resolve()
    path = root / a.file
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    top = {p.name for p in root.iterdir() if not p.name.startswith(".") or p.name in (".env.example", ".gitattributes")}
    anchors, seen = set(), {}
    prose = []  # (line number, text outside fenced code)
    in_fence = False
    for n, line in enumerate(lines, 1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        prose.append((n, line))
        m = re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", line)
        if m:
            base = slug(m.group(2))
            k = seen.get(base, 0)
            seen[base] = k + 1
            anchors.add(base if k == 0 else f"{base}-{k}")

    problems = []
    for n, line in prose:
        for target in LINK.findall(line):
            if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I):
                continue  # http:, https:, mailto:
            file_part, _, frag = target.partition("#")
            if not file_part:
                if frag.lower() not in anchors:
                    problems.append(f"{n}: in-page link #{frag} matches no heading")
            elif not (path.parent / file_part).exists():
                problems.append(f"{n}: link to missing path {file_part}")
        for span in CODE_SPAN.findall(line):
            tok = span.strip()
            if " " in tok or "/" not in tok or tok.startswith(("/", "~", "$", "%", "http")):
                continue
            first = tok.split("/", 1)[0]
            if first in top and not any(c in tok for c in "*<>{}"):
                if not (root / tok.rstrip("/")).exists():
                    problems.append(f"{n}: `{tok}` does not exist in the repo")
        for rx in BANNED + a.forbid:
            if re.search(rx, line, re.I):
                problems.append(f"{n}: forbidden text /{rx}/")

    for p in problems:
        print(p)
    print(f"{len(problems)} problem(s)" if problems else "OK")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
