# Feature planning and stages

Every "implement X" / "fix Y" that is not a trivial change (CLAUDE.md) runs as:
**plan → user approval → stages**, each stage through the feature chain.

## 1. Plan first
- The main session writes the plan itself (not a subagent), after reading `context-claude.md`,
  the module files and the code it touches. No developer dispatch before the plan is approved.
- Where:
  - small plan (one area, a few files, nothing open) → in the chat reply;
  - otherwise a file `claude-context/plans/<name>.md` (main folder). In a parallel-task worktree
    `cc-telemetry-<name>` `claude-context/` is locked: write `<wt>/.wt-ledger/plan-<name>.md`
    instead; `parallel-task finish` moves it to `claude-context/plans/`.
- Contents: goal; current state (files, views, panels, ledger entries involved); approach and
  decisions with the reason; risks (data, idempotency, exposure, ClickHouse 22.3 compatibility);
  open questions; verification (which checks from `guides/verification.md`); **Stages** as the
  last section (§ 2).
- **Wait for the user's approval**; close the open questions with them first. A plan changed during
  the work is updated (file or a new chat version) and re-approved when a stage's scope or result
  changes.

## 2. Stages (decomposition) — last section of the plan
- **One stage = one commit.** Each stage has a **checkable result** — what proves it is done:
  `check-dashboard.js` all `ok`, a named SQL sample returns the expected rows, `views-init` prints
  `cc.* views are ready`, a script run exits 0 and keeps `.env`, a panel shows X on the live
  Grafana. "Code written" is not a result.
- Every stage leaves the stack working and the dashboards loading; no stage depends on a later one.
- Order: views (`clickhouse/views.sql`) before the panels that read them; site pages (EN + RU)
  and README last or with the stage that changes the behaviour they describe; new screenshots
  (`tools/docs-demo/`) after the panels they show.
- A small feature where splitting only adds overhead: the section reads
  `Small feature — decomposition not recommended.` It then runs as one stage.
- Execution, per stage: developer → reviewer (BLOCKED → back to developer; trivial-change rule as
  in CLAUDE.md). The developer prompt names the plan, the stage number and its checkable result;
  the developer implements only that stage. After the chain: report the stage result and how it
  was verified, then the **user commits**. The next stage starts only after the user says the stage
  is committed (check with `git log -1` / `git status --short`).

## 3. Plan files
- `claude-context/plans/<name>.md` is tracked; `<name>` = the feature's short name (the worktree
  name when there is one).
- A finished plan stays as the record of the decisions; mark it `Status: done (<date>)` at the top
  when the last stage is committed.
