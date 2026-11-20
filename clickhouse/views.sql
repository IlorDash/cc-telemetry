-- The cc.* views the dashboards read. Applied by clickhouse/init-views.sh after schema.sql (tables and the
-- materialized view) and backfill.sql (history), so a view never reads a half-filled table.
--
-- Everything here is a plain view over cc.events_t (flattened Claude Code events), cc.session_project_t and
-- cc.tips_t (small tables rebuilt by clickhouse/refresh.sql) or over otel.otel_logs (cc.session_meta):
-- a view change applies to all history at once, editing a view needs no migration.
-- Re-runnable: views are CREATE OR REPLACE (order matters: a view must exist before one reading it).

-- 1. One row per Claude Code event, the original column list (the computed columns of cc.events_t stay inside).
--    Low-cardinality text columns are LowCardinality(String).
CREATE OR REPLACE VIEW cc.events_raw AS
SELECT
    ts, project_label, host, cc_version, event, session_id, prompt_id, account_uuid, account, agent_id, request_id,
    query_source, agent_name, agent_type, skill_name, skill_trigger, tool_name, tool_use_id, tool_input,
    tool_parameters, success, decision, decision_source, duration_ms, model, input_tokens, output_tokens,
    cache_read_tokens, cache_creation_tokens, cost_usd, agent_total_tokens, agent_tool_uses, prompt,
    hook_name, hook_duration_ms, result_bytes, ttft_ms, status_code, error
FROM cc.events_t;

-- 2. Session titles and working directory sent by the client hook as separate events:
--    ServiceName 'cc-session-meta' (never in cc.events_t, which holds only 'claude-code').
--    A client re-sends a session only when a value changed: the latest row per session wins.
--    Defined here because cc.path_roots reads it (a view must exist before another one reads it).
--    title_source: 'custom' (/rename) | 'ai' | ''. cwd = first working directory of the session.
--    A plain view over the (small) otel.otel_logs slice of the hook.
CREATE OR REPLACE VIEW cc.session_meta AS
SELECT
    LogAttributes['session.id']                                 AS session_id,
    argMax(LogAttributes['title'], Timestamp)                   AS title,
    argMax(LogAttributes['title_source'], Timestamp)            AS title_source,
    argMax(LogAttributes['git_branch'], Timestamp)              AS git_branch,
    argMax(LogAttributes['cwd'], Timestamp)                     AS cwd,
    argMax(ResourceAttributes['host'], Timestamp)               AS host,
    argMax(LogAttributes['cc_version'], Timestamp)              AS cc_version,
    max(Timestamp)                                              AS updated
FROM otel.otel_logs
WHERE ServiceName = 'cc-session-meta'
  AND LogAttributes['event.name'] = 'session_meta'
  AND LogAttributes['session.id'] != ''
GROUP BY session_id;

-- 3. Candidate project names: the project folder of every tool call that touched an absolute path
--    (cc.events_t.path_cand, computed at insert time) plus the working directory of every session
--    (cc.session_meta.cwd, treated as a directory path: from_cwd = 1; cc.session_project prefers it).
--    Lower-cased, `\` -> `/`, `/c/` -> `c:/`, `/mnt/c/` accepted. The folder is the first path segment that is
--    not a home dir (users/<u>, home/<u>, root) or a generic container (documents, projects, src, dev, ...):
--    c:/users/u/documents/projects/<proj>/..., /home/u/src/<proj>/..., c:/<proj>/...
--    Dropped: hidden folders (.claude), temp/system/AppData folders, files directly in a container.
--    OneDrive-redirected folders (`onedrive`, `onedrive - <company>`) are containers too.
--    The cwd part repeats the rules of the materialized view in schema.sql (regex, IN list, trailing slash):
--    keep in step.
CREATE OR REPLACE VIEW cc.path_roots AS
SELECT session_id, path_cand AS cand, toUInt8(0) AS from_cwd
FROM cc.events_t
WHERE event = 'tool_result' AND session_id != '' AND path_cand != ''
UNION ALL
SELECT session_id, cand, toUInt8(1) AS from_cwd
FROM
(
    SELECT
        session_id,
        replaceRegexpOne(lower(replaceAll(cwd, '\\', '/')), '^/([a-z])/', '\\1:/') AS p,
        replaceRegexpOne(p, '/*$', '/') AS pp,
        extract(pp, '^(?:/mnt/[a-z]/|/|[a-z]:/)(?:(?:users|home)/[^/]+/|root/)?(?:(?:documents|projects|project|repos|repo|src|source|sources|dev|work|code|git|github|gitlab|workspace|workspaces|desktop|downloads|onedrive(?: - [^/]*)?)/)*([^/.][^/]*)/') AS c0,
        if(c0 IN ('users', 'home', 'root', 'mnt', 'documents', 'projects', 'project', 'repos', 'repo', 'src', 'source',
                  'sources', 'dev', 'work', 'code', 'git', 'github', 'gitlab', 'workspace', 'workspaces', 'desktop',
                  'downloads', 'onedrive', 'appdata', 'tmp', 'temp', 'var', 'etc', 'usr', 'proc', 'sys', 'windows', 'programdata',
                  'program files', 'program files (x86)', 'node_modules', '$recycle.bin')
              OR startsWith(c0, 'onedrive - '), '', c0) AS cand
    FROM cc.session_meta
    WHERE cwd != ''
)
WHERE cand != '';

-- 4. Inferred project per session: the table cc.session_project_t, rebuilt by clickhouse/refresh.sql from
--    cc.path_roots: the folder of the session's working directory when there is one, else the most
--    frequent folder among its tool-call paths (ties: name order). A worktree folder <project>-<name>
--    folds into <project> when that name is known, as another folder seen in paths or as an explicit label.
CREATE OR REPLACE VIEW cc.session_project AS
SELECT session_id, project
FROM cc.session_project_t;

-- 5. Effective events: an explicit label wins; sessions without one get the inferred project, else 'unknown'.
--    Most views read this one (or cc.events_raw when they need no project).
--    The project of a session is as old as the last refresh (a few minutes), not computed per query.
CREATE OR REPLACE VIEW cc.events AS
SELECT
    e.* EXCEPT (project_label),
    if(e.project_label != 'unknown', e.project_label,
       if(s.project != '', s.project, 'unknown')) AS project
FROM cc.events_raw AS e
LEFT JOIN cc.session_project AS s ON s.session_id = e.session_id;

-- 6. agent_id -> readable agent name (context-auditor, Explore, ...).
--    agent.name arrives with the subagent's first API request, agent_type at completion; the events that
--    carry a name, an agent_type or a query_source are the four listed. Other events with an agent_id
--    (tool calls, hooks) give no name: their agent stays 'agent?' as before.
CREATE OR REPLACE VIEW cc.agents AS
SELECT
    agent_id,
    multiIf(
        anyIf(agent_type, agent_type != '') != '', anyIf(agent_type, agent_type != ''),
        anyIf(agent_name, agent_name != '') != '', anyIf(agent_name, agent_name != ''),
        anyIf(query_source, startsWith(query_source, 'agent:')) != '',
            replaceRegexpOne(anyIf(query_source, startsWith(query_source, 'agent:')), '^agent:[^:]*:', ''),
        'agent?') AS agent
FROM cc.events_raw
WHERE event IN ('api_request', 'assistant_response', 'api_error', 'subagent_completed') AND agent_id != ''
GROUP BY agent_id;

-- 7. API request -> skill that was active (Claude Code tags requests with skill.name).
CREATE OR REPLACE VIEW cc.requests AS
SELECT
    request_id,
    anyIf(skill_name, skill_name != '') AS skill
FROM cc.events_raw
WHERE event = 'api_request' AND request_id != ''
GROUP BY request_id;

-- 8. Model requests with actor (main / agent name / aux:<source>) and skill.
CREATE OR REPLACE VIEW cc.api_requests AS
SELECT
    e.ts AS ts, e.project AS project, e.host AS host, e.account AS account, e.account_uuid AS account_uuid,
    e.session_id AS session_id, e.prompt_id AS prompt_id, e.agent_id AS agent_id,
    multiIf(
        e.agent_id != '', if(a.agent = '', 'agent?', a.agent),
        e.query_source IN ('sdk', 'main') OR startsWith(e.query_source, 'repl_main'), 'main',
        concat('aux:', e.query_source)) AS actor,
    e.skill_name AS skill,
    e.model AS model,
    e.input_tokens AS input_tokens,
    e.output_tokens AS output_tokens,
    e.cache_read_tokens AS cache_read_tokens,
    e.cache_creation_tokens AS cache_creation_tokens,
    e.input_tokens + e.output_tokens + e.cache_read_tokens + e.cache_creation_tokens AS total_tokens,
    e.cost_usd AS cost_usd,
    e.duration_ms AS duration_ms,
    e.ttft_ms AS ttft_ms,        -- time to first token, 0 when not streamed
    e.request_id AS request_id   -- one response; tool_result events carry the same id (work phase, Efficiency dashboard)
FROM cc.events AS e
LEFT JOIN cc.agents AS a ON a.agent_id = e.agent_id
WHERE e.event = 'api_request';

-- 9. Tool calls with actor, skill (via request_id) and a project-relative path.
--    Reads cc.events_t directly (abs_path and bash_cmd are computed there); the project is chosen
--    exactly as in cc.events.
--    Worktrees <project>-<name>/ fold into the same relative path as the main folder.
CREATE OR REPLACE VIEW cc.tool_calls AS
SELECT
    ts, project, host, account, account_uuid, session_id, prompt_id, agent_id,
    if(agent_id = '', 'main', if(agent_label = '', 'agent?', agent_label)) AS actor,
    skill_label AS skill,
    tool_name, tool_use_id, success, duration_ms, result_bytes,
    multiIf(tool_name = 'Read', 'read',
            tool_name IN ('Edit', 'MultiEdit', 'Write', 'NotebookEdit'), 'write',
            tool_name IN ('Grep', 'Glob'), 'search',
            'other') AS op,
    p AS abs_path,
    position(p, concat('/', project)) AS pos,
    substring(p, pos + length(project) + 1) AS rest,
    multiIf(p = '', '',
            pos = 0, p,
            rest = '', '.',
            startsWith(rest, '/'), if(rest = '/', '.', substring(rest, 2)),
            startsWith(rest, '-'), if(position(rest, '/') > 0, substring(rest, position(rest, '/') + 1), '.'),
            p) AS path,
    multiIf(path = '', '',
            pos = 0, 'external',
            startsWith(path, 'claude-context/') OR startsWith(path, '.claude/'), 'claude-context',
            position(path, '/') = 0, '(root)',
            splitByChar('/', path)[1]) AS area,
    multiIf(path = '' OR pos = 0, '',
            position(path, '/') = 0, '.',
            substring(path, 1, length(path) - position(reverse(path), '/'))) AS dir,
    bash_cmd
FROM
(
    SELECT
        e.ts AS ts,
        if(e.project_label != 'unknown', e.project_label,
           if(sp.project != '', sp.project, 'unknown')) AS project,
        e.host AS host, e.account AS account, e.account_uuid AS account_uuid,
        e.session_id AS session_id, e.prompt_id AS prompt_id, e.agent_id AS agent_id,
        a.agent AS agent_label, r.skill AS skill_label,
        e.tool_name AS tool_name, e.tool_use_id AS tool_use_id,
        e.success AS success, e.duration_ms AS duration_ms, e.result_bytes AS result_bytes,
        e.abs_path AS p, e.bash_cmd AS bash_cmd
    FROM cc.events_t AS e
    LEFT JOIN cc.session_project AS sp ON sp.session_id = e.session_id
    LEFT JOIN cc.agents   AS a ON a.agent_id   = e.agent_id
    LEFT JOIN cc.requests AS r ON r.request_id = e.request_id
    WHERE e.event = 'tool_result'
);

-- 10. One row per session.
--     title, title_source, git_branch, cwd come from cc.session_meta ('' when the client sent none).
--     account / account_uuid: of the latest event that has an account (a session may span accounts).
--     last_prompt: time of the latest user_prompt; a session without a prompt gets `started`.
--     model: the model with the highest api_request cost in the session ('' when there is no request).
CREATE OR REPLACE VIEW cc.sessions AS
SELECT
    s.*,
    m.title                                        AS title,
    m.title_source                                 AS title_source,
    m.git_branch                                   AS git_branch,
    m.cwd                                          AS cwd
FROM
(
  -- one join per query level: ClickHouse 22.3 cannot expand `s.*` over two joins
  SELECT t.*, mm.model AS model
  FROM
  (
    SELECT
        session_id,
        any(project)                                   AS project,
        any(host)                                      AS host,
        argMaxIf(account, ts, ev.account != '')        AS account,
        argMaxIf(account_uuid, ts, ev.account != '')   AS account_uuid,
        min(ts)                                        AS started,
        max(ts)                                        AS last_event,
        if(countIf(event = 'user_prompt') > 0, maxIf(ts, event = 'user_prompt'), min(ts)) AS last_prompt,
        argMinIf(prompt, ts, event = 'user_prompt')    AS first_prompt,
        countIf(event = 'user_prompt')                 AS prompts,
        sumIf(cost_usd, event = 'api_request')         AS cost_usd,
        sumIf(input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens,
              event = 'api_request')                   AS tokens,
        countIf(event = 'tool_result')                 AS tool_calls,
        countIf(event = 'subagent_completed')          AS agents_run,
        countIf(event = 'skill_activated')             AS skills_run,
        countIf(event = 'api_request')                 AS requests
    FROM cc.events AS ev
    WHERE session_id != ''
    GROUP BY session_id
  ) AS t
  LEFT JOIN
  (
    SELECT session_id, argMax(mdl, mcost) AS model
    FROM
    (
        SELECT session_id, model AS mdl, sum(cost_usd) AS mcost
        FROM cc.events
        WHERE event = 'api_request' AND session_id != '' AND model != ''
        GROUP BY session_id, model
    )
    GROUP BY session_id
  ) AS mm ON mm.session_id = t.session_id
) AS s
LEFT JOIN cc.session_meta AS m ON m.session_id = s.session_id;

-- 11. Tips: one row per finding of the last 7 days. The table cc.tips_t is rebuilt by clickhouse/refresh.sql
--     (rules and thresholds are there). Columns: category, title, body, scope (project / agent / hook),
--     metric (the number behind the tip), link (relative Grafana URL), affected (tokens the tip is about,
--     NULL for time tips), cost_usd (cost of the requests it is about, NULL when not known); see refresh.sql.
--     Rows are ordered by affected, biggest first, NULLs last.
CREATE OR REPLACE VIEW cc.tips AS
SELECT category, title, body, scope, metric, link, affected, cost_usd
FROM cc.tips_t
ORDER BY affected DESC NULLS LAST, category, title;

-- 12. One row per prompt (session_id + prompt_id): the user prompt and everything it triggered
--     (main, subagent and auxiliary requests, tool calls). Sums add up to cc.sessions.
--     prompt is '' or '<REDACTED>' unless the client sets OTEL_LOG_USER_PROMPTS=1.
CREATE OR REPLACE VIEW cc.prompts AS
SELECT
    session_id,
    prompt_id,
    any(project)                                   AS project,
    any(host)                                      AS host,
    argMaxIf(account, ts, ev.account != '')        AS account,
    argMaxIf(account_uuid, ts, ev.account != '')   AS account_uuid,
    min(ts)                                        AS started,
    max(ts)                                        AS last_event,
    argMinIf(prompt, ts, event = 'user_prompt')    AS prompt,
    countIf(event = 'api_request')                 AS requests,
    sumIf(cost_usd, event = 'api_request')         AS cost_usd,
    -- aliases differ from the source columns: the `tokens` sum below would otherwise read the alias
    sumIf(input_tokens, event = 'api_request')          AS input,
    sumIf(output_tokens, event = 'api_request')         AS output,
    sumIf(cache_read_tokens, event = 'api_request')     AS cache_read,
    sumIf(cache_creation_tokens, event = 'api_request') AS cache_creation,
    sumIf(input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens,
          event = 'api_request')                   AS tokens,
    countIf(event = 'tool_result')                 AS tool_calls,
    maxIf(result_bytes, event = 'tool_result')     AS max_result_bytes,
    countIf(event = 'subagent_completed')          AS agents_run
FROM cc.events AS ev
WHERE session_id != '' AND prompt_id != ''
GROUP BY session_id, prompt_id
HAVING countIf(event IN ('user_prompt', 'api_request', 'tool_result')) > 0;
