#!/usr/bin/env python3
"""Synthetic Claude Code telemetry for the guide screenshots (made-up accounts, projects, prompts).

Writes JSONEachRow rows for otel.otel_logs to stdout: ~30 days ending now, deterministic for a
given --now (fixed seed). Python 3 standard library only.

    python3 generate.py [--now 2026-11-19T12:00:00] [--days 30] > logs.jsonl

Everything here is invented: nothing is copied from a real installation.
"""
import argparse
import json
import random
import sys
import time
import uuid
from datetime import datetime, timezone

SEED = 20261119
R = random.Random(SEED)
IDR = random.Random(SEED + 1)  # ids only, so changing behaviour does not reshuffle ids
ALNUM = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"


def new_uuid():
    return str(uuid.UUID(int=IDR.getrandbits(128), version=4))


def new_id(prefix, n):
    return prefix + "".join(IDR.choice(ALNUM) for _ in range(n))


# ---------------------------------------------------------------- models and prices (USD per 1M tokens)
MODELS = {
    "opus": dict(name="claude-opus-4-5", pin=5.0, pout=25.0, pcr=0.50, pcc=6.25, ttft=(1000, 2200), ms=24),
    "sonnet": dict(name="claude-sonnet-4-5", pin=3.0, pout=15.0, pcr=0.30, pcc=3.75, ttft=(500, 1400), ms=12),
    "haiku": dict(name="claude-haiku-4-5", pin=1.0, pout=5.0, pcr=0.10, pcc=1.25, ttft=(250, 700), ms=6),
}

# ---------------------------------------------------------------- accounts / PCs
USERS = [
    dict(key="alice", email="alice@example.com", host="alice-laptop", os="windows", osver="10.0.26100",
         term="vscode", plan="max", root="C:\\Users\\alice\\Documents\\Projects", sep="\\", home="C:\\Users\\alice",
         hours=(8, 17), qs="sdk", projects={"web-shop": 0.65, "data-pipeline": 0.35}, per_day=(2, 4),
         version=lambda d: "2.1.327" if d < 6 else "2.1.325"),
    dict(key="bob", email="bob@example.com", host="bob-workstation", os="linux", osver="6.8.0",
         term="tmux", plan="max", root="/home/bob/src", sep="/", home="/home/bob",
         hours=(11, 20), qs="repl_main_thread", projects={"mobile-app": 0.6, "data-pipeline": 0.4}, per_day=(2, 4),
         version=lambda d: "2.1.327" if d < 9 else "2.1.323"),
    dict(key="carol", email="carol@example.com", host="carol-macbook", os="darwin", osver="15.1",
         term="iTerm.app", plan="team", root="/Users/carol/Projects", sep="/", home="/Users/carol",
         hours=(6, 15), qs="repl_main_thread", projects={"web-shop": 0.5, "mobile-app": 0.5}, per_day=(1, 3),
         version=lambda d: "2.1.323"),
]
for _u in USERS:
    _u["uuid"] = new_uuid()
    _u["uid"] = "".join(IDR.choice("0123456789abcdef") for _ in range(64))
ORG_ID = new_uuid()

# ---------------------------------------------------------------- projects
# files: (relative path, weight, kind) kind: '' normal, 'big' = result > 200 KB
PROJECTS = {
    "web-shop": dict(
        opus=0.07, miss=0.04,
        files=[("src/cart/CartService.ts", 7, ""), ("src/cart/CartService.test.ts", 1.5, ""),
               ("src/checkout/PaymentForm.tsx", 2, ""), ("src/checkout/stripe.ts", 1.5, ""),
               ("src/catalog/ProductList.tsx", 1.5, ""), ("src/catalog/search.ts", 1.2, ""),
               ("src/api/orders.ts", 1.5, ""), ("src/api/client.ts", 1, ""), ("src/components/Button.tsx", 1, ""),
               ("src/hooks/useCart.ts", 1.5, ""), ("src/styles/theme.css", 0.8, ""),
               ("tests/e2e/checkout.spec.ts", 1.2, ""), ("package.json", 1.2, ""), ("README.md", 0.8, ""),
               ("docs/architecture.md", 0.8, ""), ("CLAUDE.md", 1.2, ""), (".claude/agents/code-reviewer.md", 0.5, ""),
               ("package-lock.json", 0.12, "big")],
        grep=["useCart", "applyDiscount", "TODO", "formatPrice", "CartItem", "stripe"],
        globs=["**/*.test.ts", "src/**/*.tsx", "**/*.css"],
        dirs=["src", "src/cart", "src/checkout", "tests"],
        bash=[("npm test", 8000, 40000, 2000, 12000, 0.12), ("npm run lint", 3000, 15000, 500, 5000, 0.08),
              ("npm run build", 10000, 45000, 800, 4000, 0.05), ("git status", 30, 120, 200, 900, 0),
              ("git diff", 40, 200, 1000, 30000, 0), ("git log --oneline -10", 30, 100, 400, 900, 0),
              ("npx playwright test", 20000, 90000, 2000, 9000, 0.15), ("ls src", 20, 60, 200, 700, 0)],
        mcp=[("github", "list_issues"), ("github", "create_pull_request"), ("playwright", "browser_snapshot")],
        reject={"Bash": 0.12, "Write": 0.05},
        agents={"Explore": 5, "general-purpose": 1.5, "code-reviewer": 2, "test-runner": 1.5},
        skills=[("commit-message", "user-slash", "user"), ("pdf", "claude-proactive", "plugin")],
        branches=["main", "feature/cart-discounts", "fix/checkout-rounding", "feature/product-search"],
        titles=["Add discount codes to the cart", "Fix rounding in checkout totals", "Speed up product search",
                "Refactor the cart hook", "Stripe webhook retries", "Write e2e tests for checkout",
                "Update the theme colours"],
        prompts=["Add a discount code field to the cart and validate it against the API",
                 "Why does the checkout total differ by one cent for some carts?",
                 "Write unit tests for CartService.applyDiscount",
                 "Refactor useCart so it does not refetch on every render",
                 "Find every place where we format prices and use one helper",
                 "Add an e2e test for paying with a saved card",
                 "Explain how the order API handles failed payments",
                 "Make the product list keyboard accessible",
                 "Update the README with the new environment variables",
                 "Review my changes in src/checkout before I open a pull request",
                 "Rename CartItem.qty to quantity everywhere",
                 "The build fails after the Stripe upgrade, please fix it"],
    ),
    "data-pipeline": dict(
        opus=0.10, miss=0.70,
        files=[("etl/transform/clean.py", 16, ""), ("etl/transform/aggregate.py", 2, ""),
               ("etl/extract/orders.py", 1.5, ""), ("etl/load/warehouse.py", 1.5, ""),
               ("dags/daily_sales.py", 1.5, ""), ("dags/hourly_events.py", 1.2, ""),
               ("sql/models/fact_orders.sql", 1.5, ""), ("sql/models/dim_customer.sql", 1, ""),
               ("tests/test_clean.py", 1.2, ""), ("tests/test_aggregate.py", 1, ""),
               ("config/pipeline.yaml", 1, ""), ("requirements.txt", 0.6, ""), ("README.md", 0.6, ""),
               ("logs/etl.log", 5.5, "big"), ("data/sample/orders_sample.csv", 4, "big")],
        grep=["null_rate", "dedupe", "warehouse", "TODO", "schedule_interval", "customer_id"],
        globs=["**/*.py", "sql/**/*.sql", "dags/*.py"],
        dirs=["etl", "dags", "sql", "tests"],
        bash=[("pytest -q", 3000, 20000, 500, 6000, 0.12), ("python -m etl.transform.clean", 2000, 30000, 300, 4000, 0.1),
              ("git status", 30, 120, 200, 900, 0), ("git diff", 40, 200, 1000, 30000, 0),
              ("ruff check .", 300, 1500, 200, 3000, 0.08), ("psql -c \"select count(*) from fact_orders\"", 200, 2500, 100, 400, 0),
              ("docker compose up -d", 2000, 9000, 300, 1200, 0.05), ("ls dags", 20, 60, 200, 600, 0)],
        mcp=[("postgres", "query"), ("postgres", "list_tables"), ("github", "list_issues")],
        reject={"Bash": 0.07},
        agents={"Explore": 4, "general-purpose": 2, "code-reviewer": 1, "docs-writer": 1.5},
        skills=[("sql-review", "claude-proactive", "user"), ("commit-message", "user-slash", "user")],
        branches=["main", "feature/dedupe-orders", "fix/null-handling", "feature/hourly-events"],
        titles=["Deduplicate orders before loading", "Handle nulls in the clean step", "Add the hourly events DAG",
                "Speed up the aggregate step", "Investigate the failed nightly run", "Document the pipeline config"],
        prompts=["The nightly run failed in the clean step, find out why",
                 "Deduplicate orders by order_id and keep the latest row",
                 "Add a data quality check for null customer_id",
                 "Why is the aggregate step so slow on the sample data?",
                 "Write a DAG that loads hourly events into the warehouse",
                 "Review the SQL in sql/models for anything that scans the full table",
                 "Explain what config/pipeline.yaml controls",
                 "Add tests for the dedupe function",
                 "Summarise the errors in the ETL log from yesterday",
                 "Move the warehouse credentials to environment variables"],
    ),
    "mobile-app": dict(
        opus=0.60, miss=0.08,
        files=[("src/screens/HomeScreen.tsx", 3, ""), ("src/screens/LoginScreen.tsx", 2.5, ""),
               ("src/navigation/AppNavigator.tsx", 2, ""), ("src/services/api.ts", 2, ""),
               ("src/store/userSlice.ts", 1.5, ""), ("src/components/ProductCard.tsx", 1.5, ""),
               ("ios/Podfile", 0.6, ""), ("android/app/build.gradle", 0.8, ""), ("package.json", 1, ""),
               ("app.json", 0.6, ""), ("__tests__/LoginScreen.test.tsx", 1.2, ""), ("README.md", 0.6, "")],
        grep=["useNavigation", "AsyncStorage", "TODO", "accessToken", "ProductCard", "push notification"],
        globs=["src/**/*.tsx", "__tests__/**", "**/*.json"],
        dirs=["src", "src/screens", "__tests__"],
        bash=[("npx jest", 4000, 25000, 800, 6000, 0.1), ("npx tsc --noEmit", 3000, 14000, 300, 4000, 0.1),
              ("git status", 30, 120, 200, 900, 0), ("git diff", 40, 200, 1000, 30000, 0),
              ("yarn ios", 15000, 60000, 500, 3000, 0.1), ("pod install", 8000, 40000, 600, 3000, 0.05),
              ("./gradlew assembleDebug", 20000, 90000, 800, 5000, 0.1), ("ls src", 20, 60, 200, 700, 0)],
        mcp=[("github", "list_issues"), ("github", "create_pull_request")],
        reject={"Bash": 0.10, "Edit": 0.05},
        agents={"Explore": 4, "general-purpose": 1.5, "test-runner": 2, "code-reviewer": 1},
        skills=[("commit-message", "user-slash", "user")],
        branches=["main", "feature/biometric-login", "fix/android-back-button", "feature/offline-cart"],
        titles=["Add biometric login", "Fix the Android back button", "Offline mode for the cart",
                "Push notification permissions", "Speed up the home screen", "Tests for the login screen"],
        prompts=["Add Face ID login on the login screen with a fallback to the password",
                 "The Android back button closes the app on the cart screen, fix it",
                 "Cache the product list so the home screen works offline",
                 "Why does the home screen re-render twice on start?",
                 "Write tests for LoginScreen",
                 "Ask for push notification permission after the first order, not at launch",
                 "Upgrade the navigation library and fix the type errors",
                 "Explain how the access token is refreshed",
                 "Add a pull-to-refresh to the product list",
                 "Review the changes in src/store before I merge"],
    ),
}


def add_filler(name, dirs, words):
    """Many rarely touched files, so only the deliberately hot ones are read over and over."""
    P = PROJECTS[name]
    core = sum(f[1] for f in P["files"] if f[2] == "")
    names = [("%s/%s%s%s" % (d, pre, w.capitalize() if cap else w, ext))
             for d, pre, ext, cap in dirs for w in words]
    for n in names:
        P["files"].append((n, core * 2.5 / len(names), ""))


SHOP_WORDS = ["order", "invoice", "address", "wishlist", "review", "shipping", "coupon", "inventory", "profile",
              "search", "banner", "footer", "header", "modal", "toast", "table", "form", "loader", "rating", "payment"]
ETL_WORDS = ["orders", "customers", "events", "products", "refunds", "sessions", "payments", "shipments", "inventory",
             "campaigns", "returns", "suppliers", "pricing", "ratings", "clicks", "carts", "invoices", "regions",
             "stores", "users"]
add_filler("web-shop", [("src/components", "", ".tsx", True), ("src/pages", "", ".tsx", True),
                        ("src/lib", "", ".ts", False), ("tests/unit", "", ".test.ts", False)], SHOP_WORDS)
add_filler("data-pipeline", [("etl/extract", "", ".py", False), ("etl/transform", "", ".py", False),
                             ("tests", "test_", ".py", False), ("sql/models", "", ".sql", False)], ETL_WORDS)
add_filler("mobile-app", [("src/components", "", ".tsx", True), ("src/screens", "", ".tsx", True),
                          ("src/services", "", ".ts", False), ("__tests__", "", ".test.tsx", True)], SHOP_WORDS)

TOOLW = {"Read": 30, "Edit": 20, "Bash": 20, "Grep": 12, "Glob": 6, "Write": 4, "mcp": 3, "Agent": 3, "SendMessage": 0.8}
AGENT_TOOLW = {"Read": 45, "Grep": 25, "Glob": 15, "Bash": 10, "Edit": 5}
AGENT_SPEC = {
    "Explore": dict(model="haiku", qs="agent:builtin:Explore", custom=False),
    "general-purpose": dict(model="sonnet", qs="agent:builtin:general-purpose", custom=False),
    "code-reviewer": dict(model="sonnet", qs="agent:custom", custom=True),
    "test-runner": dict(model="haiku", qs="agent:custom", custom=True),
    "docs-writer": dict(model="sonnet", qs="agent:custom", custom=True),
}
SUBTASKS = ["Find where the cart total is computed", "Check which tests cover the checkout flow",
            "List the callers of the API client", "Review the staged changes", "Run the unit tests and summarise failures",
            "Draft a section for the README", "Map the folder structure", "Find unused exports"]
ERRORS = [(529, "overloaded_error: Overloaded"), (429, "rate_limit_error: This request would exceed the rate limit"),
          (500, "api_error: Internal server error"), (0, "Connection error."), (529, "overloaded_error: Overloaded")]


class Ctx:
    def __init__(self, ctx):
        self.ctx = ctx
        self.last = None


class Session:
    pass


ROWS = []


def ts_str(t):
    us = int(round(t * 1e6))
    sec, us = divmod(us, 1_000_000)
    return datetime.fromtimestamp(sec, timezone.utc).strftime("%Y-%m-%d %H:%M:%S") + ".%06d000" % us


def emit(S, t, name, attrs, agent=None):
    if t > S.limit:
        return False
    S.seq += 1
    a = {"event.name": name, "event.sequence": str(S.seq), "session.id": S.sid, "user.id": S.u["uid"],
         "user.account_uuid": S.u["uuid"], "user.email": S.u["email"], "organization.id": ORG_ID,
         "anthropic.plan": S.u["plan"], "terminal.type": S.u["term"]}
    if S.pid:
        a["prompt.id"] = S.pid
    if agent:
        a["agent_id"] = agent
    a.update({k: str(v) for k, v in attrs.items()})
    ROWS.append({"Timestamp": ts_str(t), "SeverityText": "INFO", "SeverityNumber": 9, "ServiceName": "claude-code",
                 "Body": "claude_code." + name, "ResourceAttributes": S.res,
                 "ScopeName": "com.anthropic.claude_code.events", "ScopeVersion": S.res["service.version"],
                 "LogAttributes": a})
    return True


def wchoice(d):
    items = list(d.items())
    return R.choices([k for k, _ in items], [w for _, w in items])[0]


def abspath(S, rel):
    return S.base + S.u["sep"] + rel.replace("/", S.u["sep"])


def ms(lo, hi):
    return R.uniform(lo, hi)


# ---------------------------------------------------------------- model requests
def request(S, t, mkey, qs, cs, pending, final, agent=None, agent_name=None, skill=None, first=False):
    """One api_request (with retries on api_error). Returns (t_end, request_id, billed_tokens) or None past the limit."""
    m = MODELS[mkey]
    effort = "" if mkey == "haiku" else R.choice(["medium", "medium", "medium", "high", "low"])
    err_p = 0.04 if S.bad_day else 0.005
    attempt = 0
    while R.random() < err_p and attempt < 3:
        attempt += 1
        status, text = R.choice(ERRORS)
        dur = int(ms(300, 1800)) if status else int(ms(5000, 30000))
        t += dur / 1000
        emit(S, t, "api_error", {"model": m["name"], "error": text, "status_code": status or "", "duration_ms": dur,
                                 "attempt": attempt, "request_id": new_id("req_", 24), "speed": "normal",
                                 "query_source": qs, "effort": effort}, agent)
        t += min(2 ** attempt, 8) + R.uniform(0, 1)
    if t > S.limit:
        return None
    gap_miss = cs.last is not None and t - cs.last > 300
    miss = cs.last is None or gap_miss or R.random() < (S.proj["miss"] if agent is None else 0.05)
    new = max(pending, 50)
    if miss:
        creation, read = cs.ctx + new, 0
    else:
        creation, read = new, cs.ctx
    inp = R.randint(1, 14)
    out = R.randint(350, 1800) if final else R.randint(60, 480)
    if final and R.random() < 0.15:
        out = R.randint(80, 480)
    cost = (inp * m["pin"] + out * m["pout"] + read * m["pcr"] + creation * m["pcc"]) / 1e6
    f = S.ttft_factor
    if S.pname == "mobile-app":
        f *= 2.6 if mkey == "opus" else 1.4
    ttft = int(ms(*m["ttft"]) * f)
    dur = int(ttft + out * m["ms"] * R.uniform(0.8, 1.3))
    t_end = t + dur / 1000
    rid = new_id("req_", 24)
    a = {"model": m["name"], "input_tokens": inp, "output_tokens": out, "cache_read_tokens": read,
         "cache_creation_tokens": creation, "cost_usd": "%.6f" % cost, "duration_ms": dur, "ttft_ms": ttft,
         "effort": effort, "query_source": qs, "request_id": rid, "speed": "normal"}
    if agent_name and first:
        a["agent.name"] = agent_name
    if skill:
        a["skill.name"] = skill
    if not emit(S, t_end, "api_request", a, agent):
        return None
    cs.ctx += new + out
    cs.last = t_end
    return t_end, rid, inp + out + creation


def aux_request(S, t, qs, model="haiku"):
    m = MODELS[model]
    inp, out = R.randint(300, 900), R.randint(8, 40)
    dur = int(ms(300, 900))
    cost = (inp * m["pin"] + out * m["pout"]) / 1e6
    emit(S, t + dur / 1000, "api_request",
         {"model": m["name"], "input_tokens": inp, "output_tokens": out, "cache_read_tokens": 0,
          "cache_creation_tokens": 0, "cost_usd": "%.6f" % cost, "duration_ms": dur, "ttft_ms": int(dur * 0.6),
          "effort": "", "query_source": qs, "request_id": new_id("req_", 24), "speed": "normal"})


# ---------------------------------------------------------------- tools
def hook(S, t, name, event, dur_ms):
    emit(S, t, "hook_execution_start", {"hook_name": name, "hook_event": event, "num_hooks": 1})
    emit(S, t + dur_ms / 1000, "hook_execution_complete",
         {"hook_name": name, "hook_event": event, "total_duration_ms": dur_ms, "num_hooks": 1, "num_success": 1,
          "num_blocking": 0, "num_non_blocking_error": 0, "num_cancelled": 0})


def result_bytes_default(lo=None):
    return int(min(max(R.lognormvariate(8.4, 0.9), 200), 120000))


def tool_spec(S, name, big=False):
    """-> (tool_input dict, tool_parameters dict, duration_ms, result_bytes, success)"""
    P = S.proj
    ok = R.random() > 0.03
    if name == "Read":
        rel, _, kind = R.choices(P["files"], [f[1] for f in P["files"]])[0]
        if R.random() < 0.015:
            path = S.u["home"] + S.u["sep"] + ".gitconfig"
            return {"file_path": path}, {}, int(ms(4, 30)), 900, ok
        nbytes = int(R.uniform(210000, 900000)) if kind == "big" else result_bytes_default()
        return {"file_path": abspath(S, rel)}, {}, int(ms(5, 60)), nbytes if ok else 120, ok
    if name in ("Edit", "Write"):
        rel = R.choices(P["files"], [f[1] for f in P["files"]])[0][0]
        if name == "Write" and R.random() < 0.5:
            rel = rel.rsplit("/", 1)[0] + "/" + R.choice(["helpers", "types", "constants", "utils"]) + (
                ".py" if rel.endswith(".py") else ".ts") if "/" in rel else "notes.md"
        return {"file_path": abspath(S, rel)}, {}, int(ms(20, 120)), int(ms(150, 900)), ok
    if name == "Grep":
        d = abspath(S, R.choice(P["dirs"]))
        return {"pattern": R.choice(P["grep"]), "path": d}, {}, int(ms(30, 400)), int(R.lognormvariate(7.5, 1.0)) % 40000 + 100, True
    if name == "Glob":
        return {"pattern": R.choice(P["globs"]), "path": S.base}, {}, int(ms(20, 200)), int(ms(300, 4000)), True
    if name == "Bash":
        cmd, dlo, dhi, blo, bhi, fail = R.choice(P["bash"])
        first = cmd.split()[0]
        okb = R.random() > fail
        return ({"command": cmd}, {"bash_command": first}, int(ms(dlo, dhi)), int(ms(blo, bhi)), okb)
    if name.startswith("mcp__"):
        _, server, tool = name.split("__", 2)
        return ({"query": "select 1"} if tool == "query" else {}), {"mcp_server_name": server, "mcp_tool_name": tool}, \
            int(ms(200, 3000)), int(ms(500, 9000)), ok
    if name == "SendMessage":
        return {"to": R.choice(["code-reviewer", "test-runner"])}, {}, int(ms(15, 60)), 120, True
    if name == "Skill":
        return {}, {}, int(ms(30, 90)), int(ms(800, 4000)), True
    return {}, {}, 50, 200, True


def decide(S, name, in_agent):
    """-> ('accept'|'reject', source)"""
    P = S.proj
    rp = P["reject"].get(name, 0)
    if in_agent:
        rp *= 0.5
    if R.random() < rp:
        return "reject", R.choices(["user_reject", "config", "hook"], [75, 15, 10])[0]
    if name in ("Read", "Grep", "Glob", "Skill", "Agent", "Task", "SendMessage"):
        return "accept", "config"
    if name in ("Edit", "Write"):
        if S.mode == "acceptEdits":
            return "accept", "config"
        return "accept", R.choices(["user_temporary", "config", "hook"], [80, 12, 8])[0]
    return "accept", R.choices(["config", "user_temporary", "hook"], [55, 30, 15])[0]


def do_tool(S, t, name, rid, agent, big_agent=False):
    """One tool use. Returns (t_end, result_tokens, ran)."""
    ti, tp, dur, nbytes, ok = tool_spec(S, name)
    if big_agent:
        nbytes = int(R.uniform(40000, 80000))
    decision, source = decide(S, name, agent is not None)
    tuid = new_id("toolu_", 22)
    emit(S, t + 0.02, "tool_decision",
         {"decision": decision, "source": source, "tool_name": name, "permission_mode": S.mode, "request_id": rid,
          "tool_use_id": tuid, "tool_parameters": json.dumps(tp)}, agent)
    if decision == "reject":
        return t + R.uniform(0.5, 3.0), 60, False
    t0 = t + 0.05
    if name == "Bash":
        if R.random() < 0.15:
            aux_request(S, t0, "bash_prefix")
        h = int(ms(60, 220))
        hook(S, t0, "PreToolUse:Bash", "PreToolUse", h)
        t0 += h / 1000
    t_end = t0 + dur / 1000
    emit(S, t_end, "tool_result",
         {"tool_name": name, "success": "true" if ok else "false", "duration_ms": dur, "tool_input": json.dumps(ti),
          "tool_parameters": json.dumps(tp), "tool_result_size_bytes": nbytes, "request_id": rid,
          "tool_use_id": tuid}, agent)
    if name in ("Edit", "Write") and ok:
        h = int(ms(600, 1500)) if name == "Edit" else int(ms(60, 200))
        hook(S, t_end, "PostToolUse:" + name, "PostToolUse", h)
        t_end += h / 1000
    return t_end, min(nbytes // 4, 25000) + 40, True


def run_agent(S, t, parent_rid, atype, outlier=False):
    spec = AGENT_SPEC[atype]
    aid = new_id("a", 16)
    cs = Ctx(7000)
    steps = 12 if outlier else R.randint(3, 7)
    t_start = t
    total = tools = 0
    pending = 1200
    for i in range(steps):
        final = i == steps - 1
        r = request(S, t, spec["model"], spec["qs"], cs, pending, final, agent=aid,
                    agent_name=atype if spec["custom"] else None, first=(i == 0))
        if r is None:
            return t, False
        t, rid, billed = r
        total += billed
        pending = 0
        if not final:
            for _ in range(R.choice([1, 2]) if outlier else R.choice([1, 1, 2])):
                name = wchoice(AGENT_TOOLW)
                t, rt, ran = do_tool(S, t, name, rid, aid, big_agent=outlier)
                tools += ran
                pending += rt
    emit(S, t, "subagent_completed",
         {"agent_type": atype, "agent_id": aid, "total_tokens": total, "total_tool_uses": tools,
          "duration_ms": int((t - t_start) * 1000), "model": MODELS[spec["model"]]["name"]})
    return t, True


# ---------------------------------------------------------------- prompts and sessions
def run_prompt(S, t, idx, text, slash=None, force_outlier=False):
    S.pid = new_uuid()
    pending = len(text) // 4 + 60
    emit(S, t, "user_prompt", {"prompt": text, "prompt_text": text, "prompt_length": len(text),
                               "command_name": slash or ""})
    hook(S, t, "UserPromptSubmit", "UserPromptSubmit", int(ms(50, 180)))
    skill = None
    if slash:
        skill = next(s[0] for s in S.proj["skills"] if s[1] == "user-slash")
        emit(S, t + 0.3, "skill_activated", {"skill.name": skill, "skill.source": "user", "invocation_trigger": "user-slash"})
    elif R.random() < 0.08 and any(s[1] == "claude-proactive" for s in S.proj["skills"]):
        skill_pending = next(s for s in S.proj["skills"] if s[1] == "claude-proactive")
    else:
        skill_pending = None
    if slash:
        skill_pending = None
    steps = R.choice([2, 3, 3, 4, 4, 5, 6, 7, 9])
    if force_outlier:
        steps = max(steps, 3)
    t += R.uniform(0.2, 0.8)
    for i in range(steps):
        final = i == steps - 1
        r = request(S, t, S.mkey, S.u["qs"], S.cs, pending, final, skill=skill)
        if r is None:
            return t
        t, rid, _ = r
        pending = 0
        if S.cs.ctx > 160000:
            emit(S, t, "compaction", {"trigger": "auto", "pre_tokens": S.cs.ctx, "post_tokens": 14000,
                                      "duration_ms": 9000, "success": "true"})
            t += 9
            S.cs.ctx = 14000
            S.cs.last = None
        if final:
            break
        names = []
        if force_outlier and i == 1:
            names = ["Agent!"]
        else:
            if skill_pending and i == 0:
                names.append("Skill")
            for _ in range(R.choice([1, 1, 1, 2, 2, 3])):
                names.append(wchoice(TOOLW))
        for name in names:
            if name == "Skill":
                sname, trig, src = skill_pending
                t, rt, _ = do_tool(S, t, "Skill", rid, None)
                emit(S, t, "skill_activated", {"skill.name": sname, "skill.source": src, "invocation_trigger": trig})
                skill = sname
                pending += rt
            elif name in ("Agent", "Agent!"):
                outlier = name == "Agent!"
                atype = "Explore" if outlier else wchoice(S.proj["agents"])
                tool = "Task" if S.days_ago > 14 else "Agent"
                tuid = new_id("toolu_", 22)
                emit(S, t + 0.02, "tool_decision", {"decision": "accept", "source": "config", "tool_name": tool,
                                                    "permission_mode": S.mode, "request_id": rid, "tool_use_id": tuid,
                                                    "tool_parameters": json.dumps({"subagent_type": atype})})
                t_before = t
                t, done = run_agent(S, t + 0.1, rid, atype, outlier=outlier)
                emit(S, t, "tool_result", {"tool_name": tool, "success": "true", "duration_ms": int((t - t_before) * 1000),
                                           "tool_input": json.dumps({"subagent_type": atype,
                                                                     "description": R.choice(SUBTASKS)}),
                                           "tool_parameters": json.dumps({"subagent_type": atype}),
                                           "tool_result_size_bytes": int(ms(1500, 6000)), "request_id": rid,
                                           "tool_use_id": tuid})
                pending += 900
                S.agents_used = True
                if not done:
                    return t
            elif name == "mcp":
                server, tool = R.choice(S.proj["mcp"])
                t, rt, _ = do_tool(S, t, "mcp__%s__%s" % (server, tool), rid, None)
                pending += rt
            else:
                t, rt, _ = do_tool(S, t, name, rid, None)
                pending += rt
    if R.random() < 0.012:
        emit(S, t, "at_mention", {"mention_type": "file", "success": "true"})
    return t


def run_session(S, t0, n_prompts, live=False, force_outlier=False, slow_think=False):
    S.pid = ""
    t = t0
    emit(S, t, "mcp_server_connection", {"server_name": R.choice(["github", "postgres", "playwright"]),
                                         "status": "connected", "duration_ms": int(ms(300, 2500))})
    hook(S, t + 0.2, "SessionStart:startup", "SessionStart", int(ms(80, 300)))
    t += R.uniform(2, 8)
    texts = list(S.proj["prompts"])
    R.shuffle(texts)
    meta_sent = False
    p = 0
    while True:
        if live:
            if t >= S.limit - 5:
                break
        elif p >= n_prompts:
            break
        slash = None
        text = texts[p % len(texts)]
        if p > 0 and R.random() < 0.12 and any(s[1] == "user-slash" for s in S.proj["skills"]):
            slash = "commit-message"
            text = "/commit-message"
        t = run_prompt(S, t, p, text, slash=slash, force_outlier=(force_outlier and p == 1))
        if not meta_sent and t <= S.limit:
            aux_request(S, t, "generate_session_title")
            S.title = R.choice(S.proj["titles"])
            meta(S, t + 2, "ai")
            meta_sent = True
        elif p == 3 and R.random() < 0.3 and t <= S.limit:
            S.title = R.choice(S.proj["titles"])
            meta(S, t + 1, "custom")
        p += 1
        if t > S.limit:
            break
        think = R.uniform(25, 200)
        if slow_think:
            think = R.uniform(30, 70)
        elif R.random() < 0.08:
            think = R.uniform(600, 2400)
        t += think
    return t


def meta(S, t, source):
    if t > S.limit:
        return
    ROWS.append({"Timestamp": ts_str(t), "SeverityText": "INFO", "SeverityNumber": 9, "ServiceName": "cc-session-meta",
                 "Body": "session_meta",
                 "ResourceAttributes": {"service.name": "cc-session-meta", "host": S.u["host"]},
                 "ScopeName": "cc-session-meta",
                 "LogAttributes": {"event.name": "session_meta", "session.id": S.sid, "title": S.title,
                                   "title_source": source, "git_branch": S.branch, "cwd": S.base,
                                   "cc_version": S.res["service.version"]}})


def make_session(u, pname, t0, now, days_ago, bad_days, spike_days, **kw):
    S = Session()
    S.u, S.pname, S.proj = u, pname, PROJECTS[pname]
    S.sid = new_uuid()
    S.seq = 0
    S.pid = ""
    S.limit = now - 20
    S.days_ago = days_ago
    S.bad_day = days_ago in bad_days
    S.ttft_factor = 1.8 if days_ago in spike_days else 1.0
    S.base = u["root"] + u["sep"] + pname
    S.branch = R.choice(S.proj["branches"])
    S.mode = R.choices(["default", "acceptEdits", "plan"], [70, 20, 10])[0]
    S.mkey = "opus" if R.random() < S.proj["opus"] else "sonnet"
    S.cs = Ctx(R.randint(15000, 22000))
    S.title = ""
    labelled = not (u["key"] == "carol" and R.random() < 0.15)
    S.res = {"service.name": "claude-code", "service.version": u["version"](days_ago), "os.type": u["os"],
             "os.version": u["osver"], "host.arch": "arm64" if u["os"] == "darwin" else "amd64", "host": u["host"]}
    if labelled:
        S.res["project"] = pname
    n = R.choice([2, 3, 3, 4, 5, 6])
    run_session(S, t0, n, **kw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--now", help="UTC ISO time, default: the current time")
    ap.add_argument("--days", type=int, default=30)
    args = ap.parse_args()
    now = (datetime.fromisoformat(args.now).replace(tzinfo=timezone.utc).timestamp() if args.now else time.time())
    midnight = now - now % 86400
    bad_days, spike_days = {3, 17}, {5, 21}
    for d in range(args.days - 1, -1, -1):
        day0 = midnight - d * 86400
        wd = datetime.fromtimestamp(day0, timezone.utc).weekday()
        for u in USERS:
            n = R.randint(*u["per_day"]) if wd < 5 else (1 if R.random() < 0.25 else 0)
            hours = sorted(R.uniform(u["hours"][0], u["hours"][1]) for _ in range(n))
            for h in hours:
                t0 = day0 + h * 3600
                if t0 > now - 600:
                    continue
                make_session(u, wchoice(u["projects"]), t0, now, d, bad_days, spike_days)
    alice, bob = USERS[0], USERS[1]
    # the Explore outlier of the tips: a session two days ago
    make_session(alice, "web-shop", now - 2 * 86400 - 4 * 3600, now, 2, bad_days, spike_days, force_outlier=True)
    # a session still running now, and one that ended a while ago today
    make_session(alice, "web-shop", now - 3300, now, 0, bad_days, spike_days, live=True, slow_think=True)
    make_session(bob, "mobile-app", now - 3 * 3600, now, 0, bad_days, spike_days)
    ROWS.sort(key=lambda r: r["Timestamp"])
    out = sys.stdout
    for r in ROWS:
        out.write(json.dumps(r, separators=(",", ":")) + "\n")
    sys.stderr.write("rows: %d\n" % len(ROWS))


if __name__ == "__main__":
    main()
