# Tips

Tips are the hints the stack finds on its own in your data: a file read again and again, a low
cache hit rate, a slow hook. This page lists every rule and what to do about it. The
dashboards are described on [the Dashboards page](dashboards.md).

## What a tip is

A tip is a heuristic hint, not an error: something exceeded a threshold over the last 7 days.
It is worth a look and may be fine for your work.

- The window is **fixed to the last 7 days**. Tips ignore the dashboard time range and the
  variables.
- The thresholds are first guesses. There is no way to dismiss a tip: it disappears when the
  pattern leaves the 7-day window.
- There is no rule for repeated Bash commands: the telemetry carries only the first word of a
  command (`git`, `cd`), so counting them would report noise.

---

## Where tips show

| Where | What you see |
| --- | --- |
| The Tips section on top of **Efficiency** | The number of tips (**Tips · 7d**), the tokens they affect (**Affected · 7d**), **Affected tokens by category**, and two tables: **Token tips** and **Time and friction tips** |
| The side rail on every dashboard | **Tips · 7 d** with the number of tips and, under it, the most frequent category. A click opens the Tips section of **Efficiency** |

Click a tip's title in either table to open one evidence panel full-screen, with the project (or
session) already chosen. The rules table is repeated at the bottom of **Efficiency**, in
**How tips are made**.

---

## The rules

| Category | Fires when (grouped by) | What to do | The link opens |
| --- | --- | --- | --- |
| `cache` | Cache hit rate below 40 % with at least 20 requests (project) | Keep the prompt prefix (`CLAUDE.md`, tools) stable; use fewer `/clear` commands and model switches | **Efficiency**, **Cache hit rate by project** |
| `repeated-read` | One file read more than 10 times (project, file) | Keep the key facts in `CLAUDE.md` or a note instead of rereading | **Tools & files**, **Files re-read within one session** |
| `big-results` | At least 5 tool results over 200 KB (project) | Narrow the search or limit the read range: big outputs fill the context | **Tools & files**, **Largest tool results** |
| `short-opus` | Opus model: at least 20 answers under 500 output tokens, and they are at least half of its requests (project) | A smaller model may handle such turns; the cost shown is an upper bound of the saving | **Prompts**, **Most expensive prompts** |
| `agent-outlier` | A subagent's biggest run is over 6 times its mean and over 50,000 tokens, with at least 3 runs (agent type) | Open the session of that run and check what it did | **Sessions**, **Timeline** of that session (session and agent type preset; the range is zoomed to the session) |
| `denials` | A tool rejected at least 5 times (project, tool) | Add an allow or deny rule if the rejections are not intended; the tip text names the main source (config, hook, user) | **Tools & files**, **Rejected tool calls** |
| `slow-hook` | A hook's mean duration over 500 ms, with at least 10 runs (hook) | Hooks run synchronously and delay every matching tool call: speed the hook up or make it async | **Health**, **Hook time** |
| `slow-ttft` | Mean time to first token over 3 s, with at least 10 requests (project, model) | Long contexts or a busy provider; compare the days in the panel | **Health**, **Time to first token by day** |

The rules are the `cc.tips` view in `clickhouse/views.sql`. To change a number, edit it there and
run `docker compose run --rm views-init`.

---

## Affected tokens and cost

The two numbers next to a token tip measure how big the pattern is. Neither is a promised
saving.

| Value | Meaning |
| --- | --- |
| Affected tokens | Roughly the tokens the tip refers to. `cache`: cache-creation tokens. `repeated-read` and `big-results`: result size / 4, because the telemetry carries the size in bytes and 4 bytes per token is a rule of thumb, so the figure is approximate. `short-opus`: input + output + cache-create tokens of the short answers (cache reads excluded). `agent-outlier`: the tokens of the biggest run |
| `cost_usd` | The `cost_usd` of the requests the tip is about; empty where it cannot be measured. `cache`: the cost of all the project's requests in 7 days, not only the wasted part. `short-opus`: the short answers. `agent-outlier`: the biggest run, empty if the run cannot be matched to its requests. Empty for `repeated-read`, `big-results` and the time tips |

Time tips (`denials`, `slow-hook`, `slow-ttft`) have no token value. They are listed in **Time
and friction tips** with the number behind them: a count or a mean in milliseconds. `cost_usd`
comes from Claude Code's own figure for each request; on a subscription it is not a bill.

---

## Where the links lead

A tip's link opens the evidence panel full-screen on the dashboard named in the last column of
the rules table, with the project preset (the hook tip has none, hooks belong to no project). It
keeps the time range of the dashboard you clicked from, so you can look at the same period.

The `agent-outlier` tip is the exception: it opens the session of the biggest run and zooms the
time range to that session (its activity span, padded by 3 %, at least 5 seconds each side). The
browser Back button returns you to the earlier range.

For the other panels and what their clicks do, see [Clicks](dashboards.md#clicks).
