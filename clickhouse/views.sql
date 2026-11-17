-- Views over the raw OTLP log table (otel.otel_logs, created by the collector).
-- Plain views, not materialized: editing this file and re-running views-init
-- re-parses all history.

CREATE DATABASE IF NOT EXISTS cc;

-- 1. One row per Claude Code event, attributes flattened into columns.
--    project_label = the explicit label from OTEL_RESOURCE_ATTRIBUTES ('unknown' when missing).
--    The effective project (label, else inferred from file paths) is cc.events, view 4.
CREATE OR REPLACE VIEW cc.events_raw AS
SELECT
    Timestamp                                                   AS ts,
    lower(if(ResourceAttributes['project'] != '', ResourceAttributes['project'], 'unknown')) AS project_label,
    if(ResourceAttributes['host'] != '', ResourceAttributes['host'], 'unknown')               AS host,
    ResourceAttributes['service.version']                       AS cc_version,
    LogAttributes['event.name']                                 AS event,
    LogAttributes['session.id']                                 AS session_id,
    LogAttributes['prompt.id']                                  AS prompt_id,
    LogAttributes['user.account_uuid']                          AS account_uuid,
    -- display label: email, else the first 8 characters of the account uuid, else ''
    if(LogAttributes['user.email'] != '', LogAttributes['user.email'],
       left(LogAttributes['user.account_uuid'], 8))             AS account,
    LogAttributes['agent_id']                                  AS agent_id,
    LogAttributes['request_id']                                 AS request_id,
    LogAttributes['query_source']                               AS query_source,
    LogAttributes['agent.name']                                 AS agent_name,
    LogAttributes['agent_type']                                 AS agent_type,
    LogAttributes['skill.name']                                 AS skill_name,
    LogAttributes['invocation_trigger']                         AS skill_trigger,
    LogAttributes['tool_name']                                  AS tool_name,
    LogAttributes['tool_use_id']                                AS tool_use_id,
    LogAttributes['tool_input']                                 AS tool_input,
    LogAttributes['tool_parameters']                            AS tool_parameters,
    LogAttributes['success'] = 'true'                           AS success,
    LogAttributes['decision']                                   AS decision,
    LogAttributes['source']                                     AS decision_source,
    toUInt64OrZero(LogAttributes['duration_ms'])                AS duration_ms,
    LogAttributes['model']                                      AS model,
    toUInt64OrZero(LogAttributes['input_tokens'])               AS input_tokens,
    toUInt64OrZero(LogAttributes['output_tokens'])              AS output_tokens,
    toUInt64OrZero(LogAttributes['cache_read_tokens'])          AS cache_read_tokens,
    toUInt64OrZero(LogAttributes['cache_creation_tokens'])      AS cache_creation_tokens,
    toFloat64OrZero(LogAttributes['cost_usd'])                  AS cost_usd,
    toUInt64OrZero(LogAttributes['total_tokens'])               AS agent_total_tokens,
    toUInt64OrZero(LogAttributes['total_tool_uses'])            AS agent_tool_uses,
    LogAttributes['prompt']                                     AS prompt,
    LogAttributes['hook_name']                                  AS hook_name,
    toUInt64OrZero(LogAttributes['total_duration_ms'])          AS hook_duration_ms,
    toUInt64OrZero(LogAttributes['tool_result_size_bytes'])     AS result_bytes,
    toUInt64OrZero(LogAttributes['ttft_ms'])                    AS ttft_ms
FROM otel.otel_logs
WHERE ServiceName = 'claude-code';

-- 1b. (view 12 in the card) Session titles and working directory sent by the client hook as separate
--     events: ServiceName 'cc-session-meta' (never read by the views above, which see only 'claude-code').
--     A client re-sends a session only when a value changed: the latest row per session wins.
--     Defined here because cc.path_roots reads it (a view must exist before another one reads it).
--     title_source: 'custom' (/rename) | 'ai' | ''. cwd = first working directory of the session.
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

-- 2. Project folder of every tool call that touched an absolute path (candidate project names).
--    The working directory of a session (cc.session_meta.cwd) goes through the same rules as a directory
--    path (from_cwd = 1); cc.session_project prefers it.
--    Lower-cased, `\` -> `/`, `/c/` -> `c:/`, `/mnt/c/` accepted. The folder is the first path segment that is
--    not a home dir (users/<u>, home/<u>, root) or a generic container (documents, projects, src, dev, ...):
--    c:/users/u/documents/projects/<proj>/..., /home/u/src/<proj>/..., c:/<proj>/...
--    Dropped: hidden folders (.claude), temp/system/AppData folders, files directly in a container.
--    OneDrive-redirected folders (`onedrive`, `onedrive - <company>`) are containers too.
--    Keep the two lists below (regex and IN; `onedrive - *` is a regex alternative and a startsWith) in step.
CREATE OR REPLACE VIEW cc.path_roots AS
SELECT session_id, cand, from_cwd
FROM
(
    SELECT
        session_id, from_cwd, j_file, j_nb, j_dir,
        multiIf(j_file != '', j_file, j_nb != '', j_nb, j_dir) AS raw_path,
        replaceRegexpOne(lower(replaceAll(raw_path, '\\', '/')), '^/([a-z])/', '\\1:/') AS p,
        if(j_file = '' AND j_nb = '', replaceRegexpOne(p, '/*$', '/'), p) AS pp,
        extract(pp, '^(?:/mnt/[a-z]/|/|[a-z]:/)(?:(?:users|home)/[^/]+/|root/)?(?:(?:documents|projects|project|repos|repo|src|source|sources|dev|work|code|git|github|gitlab|workspace|workspaces|desktop|downloads|onedrive(?: - [^/]*)?)/)*([^/.][^/]*)/') AS c0,
        if(c0 IN ('users', 'home', 'root', 'mnt', 'documents', 'projects', 'project', 'repos', 'repo', 'src', 'source',
                  'sources', 'dev', 'work', 'code', 'git', 'github', 'gitlab', 'workspace', 'workspaces', 'desktop',
                  'downloads', 'onedrive', 'appdata', 'tmp', 'temp', 'var', 'etc', 'usr', 'proc', 'sys', 'windows', 'programdata',
                  'program files', 'program files (x86)', 'node_modules', '$recycle.bin')
              OR startsWith(c0, 'onedrive - '), '', c0) AS cand
    FROM
    (
        SELECT
            session_id, toUInt8(0) AS from_cwd,
            JSONExtractString(tool_input, 'file_path')     AS j_file,
            JSONExtractString(tool_input, 'notebook_path') AS j_nb,
            JSONExtractString(tool_input, 'path')          AS j_dir
        FROM cc.events_raw
        WHERE event = 'tool_result' AND session_id != ''
        UNION ALL
        SELECT session_id, toUInt8(1), '', '', cwd
        FROM cc.session_meta
        WHERE cwd != ''
    )
    WHERE raw_path != ''
)
WHERE cand != '';

-- 3. Inferred project per session: the folder of its working directory (cc.session_meta.cwd) when there is
--    one, else the most frequent folder among its tool-call paths (ties: name order).
--    A worktree folder <project>-<name> folds into <project> when that name is known, either as another
--    folder seen in paths or as an explicit label (the longest such prefix wins).
CREATE OR REPLACE VIEW cc.session_project AS
WITH
    (SELECT groupUniqArray(n) FROM
        (SELECT cand AS n FROM cc.path_roots
         UNION ALL
         SELECT project_label AS n FROM cc.events_raw WHERE project_label != 'unknown')) AS names
SELECT
    session_id,
    argMin(root, (-toInt64(cwd_n), -toInt64(cnt), root)) AS project
FROM
(
    SELECT
        session_id,
        if(base != '', base, cand) AS root,
        count() AS cnt,
        sum(from_cwd) AS cwd_n
    FROM
    (
        SELECT
            session_id,
            cand,
            from_cwd,
            arrayFirst(n -> startsWith(cand, concat(n, '-')), arrayReverseSort(n -> length(n), names)) AS base
        FROM cc.path_roots
    )
    GROUP BY session_id, root
)
GROUP BY session_id;

-- 4. Effective events: an explicit label wins; sessions without one get the inferred project, else 'unknown'.
--    Every other view reads this one (or cc.events_raw when it needs no project).
CREATE OR REPLACE VIEW cc.events AS
SELECT
    e.* EXCEPT (project_label),
    if(e.project_label != 'unknown', e.project_label,
       if(s.project != '', s.project, 'unknown')) AS project
FROM cc.events_raw AS e
LEFT JOIN cc.session_project AS s ON s.session_id = e.session_id;

-- 5. agent_id -> readable agent name (context-auditor, Explore, ...).
--    agent.name arrives with the subagent's first API request, agent_type at completion.
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
WHERE agent_id != ''
GROUP BY agent_id;

-- 6. API request -> skill that was active (Claude Code tags requests with skill.name).
CREATE OR REPLACE VIEW cc.requests AS
SELECT
    request_id,
    anyIf(skill_name, skill_name != '') AS skill
FROM cc.events_raw
WHERE event = 'api_request' AND request_id != ''
GROUP BY request_id;

-- 7. Model requests with actor (main / agent name / aux:<source>) and skill.
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
    e.duration_ms AS duration_ms
FROM cc.events AS e
LEFT JOIN cc.agents AS a ON a.agent_id = e.agent_id
WHERE e.event = 'api_request';

-- 8. Tool calls with actor, skill (via request_id) and a project-relative path.
--    Worktrees <project>-<name>/ fold into the same relative path as the main folder.
CREATE OR REPLACE VIEW cc.tool_calls AS
SELECT
    ts, project, host, account, account_uuid, session_id, prompt_id, agent_id,
    if(agent_id = '', 'main', if(agent_label = '', 'agent?', agent_label)) AS actor,
    skill_label AS skill,
    tool_name, tool_use_id, success, duration_ms,
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
    JSONExtractString(tool_parameters, 'bash_command') AS bash_cmd
FROM
(
    SELECT
        e.ts AS ts, e.project AS project, e.host AS host, e.account AS account, e.account_uuid AS account_uuid,
        e.session_id AS session_id, e.prompt_id AS prompt_id, e.agent_id AS agent_id,
        a.agent AS agent_label, r.skill AS skill_label,
        e.tool_name AS tool_name, e.tool_use_id AS tool_use_id,
        e.success AS success, e.duration_ms AS duration_ms,
        e.tool_parameters AS tool_parameters,
        JSONExtractString(e.tool_input, 'file_path')     AS j_file,
        JSONExtractString(e.tool_input, 'notebook_path') AS j_nb,
        JSONExtractString(e.tool_input, 'path')          AS j_dir,
        multiIf(j_file != '', j_file, j_nb != '', j_nb, j_dir) AS raw_path,
        replaceRegexpOne(lower(replaceAll(raw_path, '\\', '/')), '^/([a-z])/', '\\1:/') AS p
    FROM cc.events AS e
    LEFT JOIN cc.agents   AS a ON a.agent_id   = e.agent_id
    LEFT JOIN cc.requests AS r ON r.request_id = e.request_id
    WHERE e.event = 'tool_result'
);

-- 9. One row per session.
--    title, title_source, git_branch, cwd come from cc.session_meta ('' when the client sent none).
--    account / account_uuid: of the latest event that has an account (a session may span accounts).
--    last_prompt: time of the latest user_prompt; a session without a prompt gets `started`.
--    model: the model with the highest api_request cost in the session ('' when there is no request).
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

-- 10. Tips: one row per finding, a UNION ALL of rules over the last 7 days (thresholds are tunable).
--     Columns: category, title, body, scope (project / agent / hook), metric (the number behind the tip),
--     link (relative Grafana URL: one evidence panel full-screen via viewPanel=panel-<id>, variables preset;
--     it always has a query string, the dashboards append '&' + the time range).
--     Savings are estimated only from our own cost_usd (no price table).
CREATE OR REPLACE VIEW cc.tips AS
-- Low cache hit rate (< 40 %) per effective project, at least 20 requests.
SELECT
    'cache' AS category,
    concat('Low cache hit rate in ', project) AS title,
    concat('Cache reads are ', toString(round(hit * 100, 1)), ' % of input over ', toString(n),
           ' requests in 7 days (below 40 %). A stable prefix (CLAUDE.md, tools) and fewer /clear or model switches keep the cache warm.') AS body,
    project AS scope,
    toFloat64(round(hit * 100, 1)) AS metric,
    concat('/d/cc-usage?viewPanel=panel-57&var-project=', encodeURLComponent(project)) AS link
FROM
(
    SELECT project, count() AS n,
           sum(cache_read_tokens) / (sum(cache_read_tokens) + sum(input_tokens) + sum(cache_creation_tokens)) AS hit
    FROM cc.api_requests
    WHERE ts >= now() - INTERVAL 7 DAY
    GROUP BY project
    HAVING n >= 20 AND sum(cache_read_tokens) + sum(input_tokens) + sum(cache_creation_tokens) > 0 AND hit < 0.4
)
UNION ALL
-- File read more than 10 times.
SELECT
    'repeated-read',
    concat('File read ', toString(n), ' times: ', path),
    concat('Read ', toString(n), ' times in 7 days in ', project, '. Consider keeping the key facts in CLAUDE.md or a note instead of rereading.'),
    project,
    toFloat64(n),
    concat('/d/cc-tools?viewPanel=panel-24&var-project=', encodeURLComponent(project))
FROM
(
    SELECT project, path, count() AS n
    FROM cc.tool_calls
    WHERE ts >= now() - INTERVAL 7 DAY AND op = 'read' AND path != ''
    GROUP BY project, path
    HAVING n > 10
)
UNION ALL
-- No "Bash command run > 15 times" rule: bash_cmd holds only the first word of the command
-- (cd, git, ...), so counting it would report noise, not repeated commands.
-- At least 5 tool results larger than 200 KB.
SELECT
    'big-results',
    concat(toString(n), ' tool results over 200 KB in ', project),
    concat('Largest result: ', toString(round(biggest / 1048576, 2)), ' MB. Big outputs fill the context; narrow the search or limit the read range.'),
    project,
    toFloat64(n),
    concat('/d/cc-tools?viewPanel=panel-140&var-project=', encodeURLComponent(project))
FROM
(
    SELECT project, count() AS n, max(result_bytes) AS biggest
    FROM cc.events
    WHERE ts >= now() - INTERVAL 7 DAY AND event = 'tool_result' AND result_bytes > 200000
    GROUP BY project
    HAVING n >= 5
)
UNION ALL
-- Many short Opus answers (< 500 output tokens): the cost of these requests is the upper bound of the saving.
SELECT
    'short-opus',
    concat('Many short Opus answers in ', project),
    concat(toString(short), ' of ', toString(total), ' Opus requests in 7 days returned under 500 output tokens and cost $',
           toString(round(short_cost, 2)), ' together. A smaller model could handle such turns for less.'),
    project,
    toFloat64(round(short_cost, 4)),
    concat('/d/cc-prompts?viewPanel=panel-180&var-project=', encodeURLComponent(project))
FROM
(
    SELECT project, count() AS total, countIf(output_tokens < 500) AS short, sumIf(cost_usd, output_tokens < 500) AS short_cost
    FROM cc.api_requests
    WHERE ts >= now() - INTERVAL 7 DAY AND positionCaseInsensitive(model, 'opus') > 0
    GROUP BY project
    HAVING short >= 20 AND short * 2 >= total
)
UNION ALL
-- Subagent outlier: the biggest run is over 6 times the mean and over 50k tokens.
SELECT
    'agent-outlier',
    concat('Subagent ', agent_type, ' used ', toString(biggest), ' tokens in one run'),
    concat('Mean is ', toString(round(mean)), ' tokens over ', toString(n), ' runs in 7 days. Check what that run did (project ', project, ').'),
    agent_type,
    toFloat64(biggest),
    concat('/d/cc-sessions?viewPanel=panel-100&var-session=', encodeURLComponent(session),
           '&var-actor=', encodeURLComponent(agent_type))
FROM
(
    SELECT agent_type, count() AS n, avg(agent_total_tokens) AS mean, max(agent_total_tokens) AS biggest,
           argMax(session_id, agent_total_tokens) AS session, argMax(project, agent_total_tokens) AS project
    FROM cc.events
    WHERE ts >= now() - INTERVAL 7 DAY AND event = 'subagent_completed' AND agent_type != ''
    GROUP BY agent_type
    HAVING n >= 3 AND biggest > 6 * mean AND biggest > 50000
)
UNION ALL
-- Frequent permission denials for one tool: an allow-list or deny-list candidate.
SELECT
    'denials',
    concat(tool_name, ' rejected ', toString(n), ' times in ', project),
    concat('Tool ', tool_name, ' was rejected ', toString(n), ' times in 7 days (mostly by ', top_source,
           '). If the rule is intended, ignore this; otherwise review the permission rules for it.'),
    project,
    toFloat64(n),
    concat('/d/cc-tools?viewPanel=panel-19&var-project=', encodeURLComponent(project))
FROM
(
    SELECT project, tool_name, count() AS n, topK(1)(decision_source)[1] AS top_source
    FROM cc.events
    WHERE ts >= now() - INTERVAL 7 DAY AND event = 'tool_decision' AND decision = 'reject' AND tool_name != ''
    GROUP BY project, tool_name
    HAVING n >= 5
)
UNION ALL
-- Slow hook: mean over 500 ms in at least 10 runs.
SELECT
    'slow-hook',
    concat('Slow hook ', hook_name),
    concat('Mean ', toString(round(mean)), ' ms over ', toString(n), ' runs in 7 days. Hooks run synchronously and delay every matching tool call.'),
    hook_name,
    toFloat64(round(mean)),
    '/d/cc-health?viewPanel=panel-26'
FROM
(
    SELECT hook_name, count() AS n, avg(hook_duration_ms) AS mean
    FROM cc.events_raw
    WHERE ts >= now() - INTERVAL 7 DAY AND event = 'hook_execution_complete' AND hook_name != ''
    GROUP BY hook_name
    HAVING n >= 10 AND mean > 500
)
UNION ALL
-- High time to first token: mean over 3 s in at least 10 requests.
SELECT
    'slow-ttft',
    concat('High time to first token for ', model, ' in ', project),
    concat('Mean ', toString(round(mean)), ' ms over ', toString(n), ' requests in 7 days. Long contexts and a busy provider slow the first token.'),
    project,
    toFloat64(round(mean)),
    concat('/d/cc-health?viewPanel=panel-161&var-project=', encodeURLComponent(project))
FROM
(
    SELECT project, model, count() AS n, avg(ttft_ms) AS mean
    FROM cc.events
    WHERE ts >= now() - INTERVAL 7 DAY AND event = 'api_request' AND ttft_ms > 0
    GROUP BY project, model
    HAVING n >= 10 AND mean > 3000
);

-- 11. One row per prompt (session_id + prompt_id): the user prompt and everything it triggered
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
