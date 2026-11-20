"""PreToolUse hook: no claude-context edits and no second stack from a parallel-task worktree.

A parallel-task worktree is a sibling folder cc-telemetry-<name> of the main cc-telemetry folder
(skills/parallel-task). Its .claude is a junction to the MAIN folder's claude-context, and its own
claude-context/ is the branch's tracked copy. The user keeps claude-context in step from the main
folder, so a session or subagent working in a worktree must not change either copy: ledger
findings go to the buffer <worktree>/.wt-ledger/ and move into claude-context at
`parallel-task finish` (guides/ledgers.md).

Exception: a worktree created for a change of the AI setup itself. The user (never Claude)
creates the empty marker file <worktree>/.wt-context-unlocked; then the worktree's OWN
claude-context copy is writable. The main folder's claude-context stays locked.

The lock is decided by where the call runs: the hook input's cwd and CLAUDE_PROJECT_DIR. If either
is inside a folder cc-telemetry-<name>, the call is checked:
  - Edit / Write / NotebookEdit: blocked when the target runs through claude-context or .claude
    of the main folder or of any worktree (own copy allowed when unlocked), or is the marker.
  - Bash / PowerShell: blocked when the command names claude-context or .claude AND looks like a
    write (redirection into it, sed -i, tee, cp, mv, rm, touch, mkdir, *-Item / *-Content, an
    inline script) - unless the worktree is unlocked and the command names no absolute path into
    another folder's claude-context. Also blocked: `docker compose` / `docker-compose` (from a
    worktree it would start a second stack with an empty volume and clashing ports) and any
    command naming the marker file.
Text heuristic, not a boundary - like guard-secrets.py it stops the accidental write.
Reads (Read/Grep/Glob, git log/diff, ls) stay free.

Exit 0 = no decision (normal permission flow), exit 2 = block, reason on stderr.
Unparsable input is blocked (fail closed).
"""

import json
import os
import posixpath
import re
import sys

MAIN = "cc-telemetry"
MARKER = ".wt-context-unlocked"

# <drive>:/.../cc-telemetry-<name>[/...]  -> group 1 = the worktree root
WORKTREE_ROOT = re.compile(r"^(.*/" + MAIN + r"-[^/]+)(/|$)")
# claude-context or .claude directly inside cc-telemetry or cc-telemetry-<name>.
# The Claude config folder (~/.claude/projects/...) is not under such a folder and stays writable.
CONTEXT_PATH = re.compile(r"(/" + MAIN + r"(-[^/]+)?)/(claude-context|\.claude)(/|$)")
# Relative paths, as commands write them from the worktree root.
CONTEXT_WORD = re.compile(r"(^|[\s\"'=/\\])(claude-context|\.claude)([/\\\s\"']|$)", re.IGNORECASE)
DOT_CLAUDE_WORD = re.compile(r"(^|[\s\"'=/\\])\.claude([/\\\s\"']|$)", re.IGNORECASE)
DOCKER_COMPOSE =re.compile(r"\bdocker(\s+|-)compose\b", re.IGNORECASE)

REDIRECT = re.compile(r"(?<![0-9&<>-])>>?\s*[\"']?([^\s\"';|&]+)")
WRITE_CMD = re.compile(
    r"\b(sed\s+(-[a-z]*i|--in-place)|tee|cp|mv|rm|rmdir|touch|mkdir|truncate|dd|ln|install|mklink"
    r"|set-content|add-content|out-file|new-item|remove-item|copy-item|move-item|rename-item)\b",
    re.IGNORECASE,
)
# Read-only commands whose arguments may mention write verbs or "docker compose" as text.
READ_ONLY_START = re.compile(
    r"^\s*(grep|rg|ls|cat|head|tail|wc|diff|git\s+(-C\s+\S+\s+)?(grep|log|diff|show|status|ls-files|blame))\b",
    re.IGNORECASE,
)
CHAINING = re.compile(r"[;&|<>`\n\r]|\$\(|--output")
QUOTED = re.compile(r"\"[^\"]*\"|'[^']*'")
INLINE_SCRIPT = re.compile(
    r"\b(py|python3?|powershell|pwsh|node|perl|bash|sh|zsh|cmd)\b.*\s[-/](c|e|command)\b", re.IGNORECASE | re.DOTALL
)


def norm(path):
    p = (path or "").replace("\\", "/").lower()
    p = re.sub(r"^/([a-z])/", r"\1:/", p)
    p = re.sub(r"^/mnt/([a-z])/", r"\1:/", p)
    if re.match(r"^[a-z]:/", p):
        p = p[:2] + posixpath.normpath(p[2:])  # resolve /x/../ so a detour cannot hide claude-context
    return p


def block(reason):
    sys.stderr.write(
        "Blocked by guard-worktree-context hook: " + reason + ". This session works in a "
        "parallel-task worktree: claude-context belongs to the main folder and changes only when "
        "the user finishes the feature; the live stack is run only from the main folder. Write "
        "ledger findings and plans to <worktree>/.wt-ledger/ instead; for any other claude-context "
        "change, tell the user what you would change; run stack checks with the main folder's "
        "helpers (claude-context/guides/verification.md).\n"
    )
    sys.exit(2)


def worktree_root(data):
    for p in (data.get("cwd"), os.environ.get("CLAUDE_PROJECT_DIR")):
        m = WORKTREE_ROOT.match(norm(p) + "/") if p else None
        if m:
            return m.group(1)
    return None


def unlocked(wt):
    return os.path.isfile(os.path.join(wt, MARKER))


def foreign_context(path_norm, wt, allow_own):
    """True when the normalised absolute path runs into a claude-context we may not write."""
    if not CONTEXT_PATH.search(path_norm):
        return False
    own_dir = wt + "/claude-context"
    if allow_own and (path_norm == own_dir or path_norm.startswith(own_dir + "/")):
        return False
    return True


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        block("hook input is not valid JSON")

    wt = worktree_root(data)
    if not wt:
        sys.exit(0)
    own = unlocked(wt)

    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input") or {}

    if tool in ("Edit", "Write", "NotebookEdit", "MultiEdit"):
        target = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        t = norm(target)
        if MARKER in t:
            block(tool + " targets the unlock marker (only the user creates it)")
        if re.match(r"^[a-z]:/", t):
            if foreign_context(t, wt, own):
                block(tool + " targets claude-context")
        elif CONTEXT_WORD.search(target) and not own:
            block(tool + " targets claude-context")
        sys.exit(0)

    if tool in ("Bash", "PowerShell"):
        command = tool_input.get("command") or ""
        cn = norm(command)
        if MARKER in command.lower():
            block("the command names the unlock marker (only the user creates or removes it)")
        if READ_ONLY_START.match(command) and not CHAINING.search(QUOTED.sub("", command)):
            sys.exit(0)
        # Quoted text (grep patterns, message drafts) is data, not a command.
        bare = QUOTED.sub(" ", command)
        if DOCKER_COMPOSE.search(bare):
            block("docker compose from a worktree would start a second stack")
        names_context = CONTEXT_WORD.search(command) or CONTEXT_PATH.search(cn)
        if not names_context:
            sys.exit(0)
        writes = (
            WRITE_CMD.search(bare) or INLINE_SCRIPT.search(command) or REDIRECT.search(command)
            or "--output" in command  # git diff/log/show --output=<file>
        )
        if own:
            # Unlocked: the worktree's own claude-context is writable; .claude (a junction to the
            # main folder), a relative path out of the worktree (..) and absolute paths into
            # another folder's claude-context are not.
            foreign = DOT_CLAUDE_WORD.search(command) or ".." in command or any(
                foreign_context(m.group(0), wt, True) for m in re.finditer(r"[a-z]:/[^\s\"';|&]*", cn)
            )
            if foreign and writes:
                block("the command may write into the main folder's claude-context")
            sys.exit(0)
        for target in REDIRECT.findall(command):
            if CONTEXT_WORD.search(" " + target) or CONTEXT_PATH.search(norm(target)):
                block("the command redirects output into claude-context")
        if writes:
            block("the command may write into claude-context")
        sys.exit(0)

    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:  # fail closed on anything unexpected
        block("the hook failed (" + type(e).__name__ + ")")
