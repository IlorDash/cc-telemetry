-- Views over the raw OTLP log table (otel.otel_logs, created by the collector).
-- Plain views, not materialized: editing this file and re-running views-init
-- re-parses all history.

CREATE DATABASE IF NOT EXISTS cc;

-- 1. One row per Claude Code event, attributes flattened into columns.
CREATE OR REPLACE VIEW cc.events AS
SELECT
    Timestamp                                                   AS ts,
    lower(if(ResourceAttributes['project'] != '', ResourceAttributes['project'], 'unknown')) AS project,
    if(ResourceAttributes['host'] != '', ResourceAttributes['host'], 'unknown')               AS host,
    ResourceAttributes['service.version']                       AS cc_version,
    LogAttributes['event.name']                                 AS event,
    LogAttributes['session.id']                                 AS session_id,
    LogAttributes['prompt.id']                                  AS prompt_id,
    LogAttributes['user.email']                                 AS account,
    LogAttributes['agent_id']                                   AS agent_id,
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
    toUInt64OrZero(LogAttributes['total_duration_ms'])          AS hook_duration_ms
FROM otel.otel_logs
WHERE ServiceName = 'claude-code';

-- 2. agent_id -> readable agent name (context-auditor, Explore, ...).
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
FROM cc.events
WHERE agent_id != ''
GROUP BY agent_id;

-- 3. API request -> skill that was active (Claude Code tags requests with skill.name).
CREATE OR REPLACE VIEW cc.requests AS
SELECT
    request_id,
    anyIf(skill_name, skill_name != '') AS skill
FROM cc.events
WHERE event = 'api_request' AND request_id != ''
GROUP BY request_id;

-- 4. Model requests with actor (main / agent name / aux:<source>) and skill.
CREATE OR REPLACE VIEW cc.api_requests AS
SELECT
    e.ts AS ts, e.project AS project, e.host AS host, e.account AS account,
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

-- 5. Tool calls with actor, skill (via request_id) and a project-relative path.
--    Worktrees <project>-<name>/ fold into the same relative path as the main folder.
CREATE OR REPLACE VIEW cc.tool_calls AS
SELECT
    ts, project, host, account, session_id, prompt_id, agent_id,
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
        e.ts AS ts, e.project AS project, e.host AS host, e.account AS account,
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

-- 6. One row per session.
CREATE OR REPLACE VIEW cc.sessions AS
SELECT
    session_id,
    any(project)                                   AS project,
    any(host)                                      AS host,
    any(account)                                   AS account,
    min(ts)                                        AS started,
    max(ts)                                        AS last_event,
    argMinIf(prompt, ts, event = 'user_prompt')    AS first_prompt,
    countIf(event = 'user_prompt')                 AS prompts,
    sumIf(cost_usd, event = 'api_request')         AS cost_usd,
    sumIf(input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens,
          event = 'api_request')                   AS tokens,
    countIf(event = 'tool_result')                 AS tool_calls,
    countIf(event = 'subagent_completed')          AS agents_run,
    countIf(event = 'skill_activated')             AS skills_run
FROM cc.events
WHERE session_id != ''
GROUP BY session_id;
