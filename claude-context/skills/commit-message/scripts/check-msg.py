#!/usr/bin/env python3
"""Check a commit message draft against a repo's .gitlint rules and the
commit-message skill's own rules.

Usage: check-msg.py <msg-file> [--repo <dir>] [--ban <regex>]...

Re-implements the gitlint rules the user's repos enable, reading their
options from <repo>/.gitlint when it exists (gitlint itself is not used: the
system package may be older than the config it has to read). Without a
.gitlint, gitlint's defaults apply.

Extra checks on top of gitlint:
  - no trailers (Signed-off-by:, Co-Authored-By:, ...);
  - no Markdown (backticks, headings, bold);
  - no line matching any --ban regex (case-insensitive).

Prints one line per violation and exits 1, or prints OK and exits 0.
"""

import argparse
import configparser
import os
import re
import sys

TRAILER_RE = re.compile(r"^[A-Za-z][A-Za-z-]*-by:\s", re.IGNORECASE)
MARKDOWN_RE = re.compile(r"`|^#{1,6}\s|\*\*\S")
TITLE_PUNCT = "?:!.,;"


def load_gitlint(repo):
    cfg = {
        "title_max": 72,
        "body_max": 80,
        "title_regex": None,
        "ignore_body": None,
        "ignored": set(),
        "found": False,
    }
    path = os.path.join(repo, ".gitlint")
    if not os.path.isfile(path):
        return cfg
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(path)
    cfg["found"] = True
    if parser.has_option("general", "ignore"):
        cfg["ignored"] = {
            r.strip() for r in parser.get("general", "ignore").split(",") if r.strip()
        }
    if parser.has_option("title-max-length", "line-length"):
        cfg["title_max"] = parser.getint("title-max-length", "line-length")
    if parser.has_option("body-max-line-length", "line-length"):
        cfg["body_max"] = parser.getint("body-max-line-length", "line-length")
    if parser.has_option("title-match-regex", "regex"):
        cfg["title_regex"] = re.compile(parser.get("title-match-regex", "regex"))
    if parser.has_option("ignore-body-lines", "regex"):
        cfg["ignore_body"] = re.compile(parser.get("ignore-body-lines", "regex"))
    return cfg


def check(text, cfg, bans):
    errors = []
    lines = text.split("\n")
    # git strips comment lines and trailing blank lines before gitlint sees them
    lines = [l for l in lines if not l.startswith("#")]
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines or not lines[0].strip():
        return ["1: title is empty"]

    title = lines[0]
    if len(title) > cfg["title_max"]:
        errors.append(f"1: title-max-length: {len(title)} > {cfg['title_max']}")
    if title != title.rstrip():
        errors.append("1: title-trailing-whitespace")
    if title != title.lstrip():
        errors.append("1: title-leading-whitespace")
    if "\t" in title:
        errors.append("1: title-hard-tab")
    if title.rstrip() and title.rstrip()[-1] in TITLE_PUNCT:
        errors.append(f"1: title-trailing-punctuation: '{title.rstrip()[-1]}'")
    if cfg["title_regex"] and not cfg["title_regex"].search(title):
        errors.append(f"1: title-match-regex: does not match {cfg['title_regex'].pattern}")

    body = lines[1:]
    if body and body[0].strip():
        errors.append("2: body-first-line-empty: no blank line after the title")
    if not body and "body-is-missing" not in cfg["ignored"]:
        errors.append("body-is-missing")

    for num, line in enumerate(body, start=2):
        if line.startswith("#"):
            continue
        if "\t" in line:
            errors.append(f"{num}: body-hard-tab")
        if line != line.rstrip():
            errors.append(f"{num}: trailing whitespace")
        if cfg["ignore_body"] and cfg["ignore_body"].search(line):
            continue
        if len(line) > cfg["body_max"]:
            errors.append(f"{num}: body-max-line-length: {len(line)} > {cfg['body_max']}")
        if TRAILER_RE.match(line):
            errors.append(f"{num}: trailer not allowed: {line.split(':')[0]}")
        if MARKDOWN_RE.search(line):
            errors.append(f"{num}: Markdown not allowed: {line.strip()[:40]}")

    for num, line in enumerate(lines, start=1):
        for ban in bans:
            if ban.search(line):
                errors.append(f"{num}: banned word /{ban.pattern}/")
    return errors


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("msg_file")
    ap.add_argument("--repo", default=".", help="repo whose .gitlint applies")
    ap.add_argument("--ban", action="append", default=[], help="banned regex")
    args = ap.parse_args()

    with open(args.msg_file, encoding="utf-8") as f:
        text = f.read()
    cfg = load_gitlint(args.repo)
    bans = [re.compile(b, re.IGNORECASE) for b in args.ban]
    errors = check(text, cfg, bans)

    source = os.path.join(args.repo, ".gitlint") if cfg["found"] else "gitlint defaults"
    if errors:
        print(f"FAIL ({source})")
        for e in errors:
            print("  " + e)
        return 1
    print(f"OK ({source})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
