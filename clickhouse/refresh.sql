-- Rebuilds the small derived tables cc.session_project_t and cc.tips_t.
-- Run only by the cc-refresh service, every 5 minutes (views-init does not run it: two runs at once would
-- fill the same cc.<name>_new). Do not run it by hand while cc-refresh is running.
--
-- Each table is rebuilt in a new table (cc.<name>_new), which is swapped in with EXCHANGE TABLES and
-- dropped: readers see either the old or the new content, never a half-built table. If a step fails,
-- the client stops and the old content stays; the next run drops a leftover cc.<name>_new first.

-- 1. cc.session_project_t: the inferred project per session.
--    The folder of the session's working directory (cc.path_roots rows with from_cwd = 1) when there is one,
--    else the most frequent folder among its tool-call paths (ties: name order).
--    A worktree folder <project>-<name> folds into <project> when that name is known, either as another
--    folder seen in paths or as an explicit label (the longest such prefix wins).
DROP TABLE IF EXISTS cc.session_project_new;
CREATE TABLE cc.session_project_new AS cc.session_project_t;
INSERT INTO cc.session_project_new
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
-- Safety net: two overlapping runs would fill the same cc.session_project_new twice. The error stops the
-- script before the swap, so the old table stays (cc.events would double-count a session otherwise).
SELECT throwIf(count() != uniqExact(session_id), 'cc.session_project_new has duplicate session_id: another refresh is running?')
FROM cc.session_project_new;
EXCHANGE TABLES cc.session_project_t AND cc.session_project_new;
DROP TABLE cc.session_project_new;

-- 2. cc.tips_t: usage tips, one row per finding, a UNION ALL of rules over the last 7 days (fixed; ignores
--    the dashboard range and variables; thresholds are tunable).
--    Columns: category, title, body, scope (project / agent / hook), metric (the number behind the tip),
--    link (relative Grafana URL: one evidence panel full-screen via viewPanel=panel-<id>, variables preset;
--    it always has a query string, the dashboards append '&' + the time range).
--    affected (Nullable UInt64): tokens the tip refers to; NULL for time tips (denials, slow-hook, slow-ttft).
--      cache = cache_creation tokens; repeated-read / big-results = result bytes / 4, i.e. "~ tokens"
--      (an APPROXIMATION: the telemetry carries result size in bytes only, 4 bytes per token is a rule of thumb);
--      short-opus = input + output + cache_creation tokens of the short answers (cache reads excluded);
--      agent-outlier = tokens of the biggest run; cache-rewrite = cache-creation tokens of the rewrites.
--    cost_usd (Nullable Float64): sum of cost_usd of the requests the tip is about; only cache, short-opus,
--      agent-outlier, cache-rewrite, NULL otherwise. cache: the cost of ALL the project's requests in 7 days.
--      agent-outlier: NULL when the biggest run has no agent_id or no matching api_request.
--      Money comes only from api_request cost_usd (no price table).
--    The order of the rows is set by the view cc.tips (views.sql).
DROP TABLE IF EXISTS cc.tips_new;
CREATE TABLE cc.tips_new AS cc.tips_t;
INSERT INTO cc.tips_new
-- Low cache hit rate (< 40 %) per effective project, at least 20 requests.
SELECT
    'cache' AS category,
    concat('Low cache hit rate in ', project) AS title,
    concat('Cache reads are ', toString(round(hit * 100, 1)), ' % of input over ', toString(n),
           ' requests in 7 days (below 40 %). A stable prefix (CLAUDE.md, tools) and fewer /clear or model switches keep the cache warm.') AS body,
    project AS scope,
    toFloat64(round(hit * 100, 1)) AS metric,
    concat('/d/cc-efficiency?viewPanel=panel-226&var-project=', encodeURLComponent(project)) AS link,
    toNullable(created) AS affected,
    toNullable(proj_cost) AS cost_usd
FROM
(
    SELECT project, count() AS n,
           sum(cache_read_tokens) / (sum(cache_read_tokens) + sum(input_tokens) + sum(cache_creation_tokens)) AS hit,
           sum(cache_creation_tokens) AS created,
           sum(cost_usd) AS proj_cost
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
    concat('/d/cc-tools?viewPanel=panel-24&var-project=', encodeURLComponent(project)),
    toNullable(toUInt64(round(avg_bytes / 4 * (n - 1)))),
    CAST(NULL AS Nullable(Float64))
FROM
(
    SELECT project, path, count() AS n, avg(result_bytes) AS avg_bytes
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
    concat('/d/cc-tools?viewPanel=panel-140&var-project=', encodeURLComponent(project)),
    toNullable(toUInt64(round(big_bytes / 4))),
    CAST(NULL AS Nullable(Float64))
FROM
(
    SELECT project, count() AS n, max(result_bytes) AS biggest, sum(result_bytes) AS big_bytes
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
    concat('/d/cc-prompts?viewPanel=panel-180&var-project=', encodeURLComponent(project)),
    toNullable(short_tokens),
    toNullable(short_cost)
FROM
(
    SELECT project, count() AS total, countIf(output_tokens < 500) AS short, sumIf(cost_usd, output_tokens < 500) AS short_cost,
           sumIf(input_tokens + output_tokens + cache_creation_tokens, output_tokens < 500) AS short_tokens
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
           '&var-actor=', encodeURLComponent(agent_type),
           -- zoom to the session: its activity span, padded by 3 % (at least 5 s), as the Sessions table does
           if(t1 = 0, '', concat('&from=', toString(t0 - greatest(intDiv(3 * (t1 - t0), 100), 5000)),
                                 '&to=', toString(t1 + greatest(intDiv(3 * (t1 - t0), 100), 5000))))),
    toNullable(biggest),
    if(matched_agent = '', CAST(NULL AS Nullable(Float64)), toNullable(run_cost))
FROM
(
    SELECT o.agent_type AS agent_type, o.n AS n, o.mean AS mean, o.biggest AS biggest,
           o.session AS session, o.project AS project, c.agent_id AS matched_agent, c.run_cost AS run_cost,
           w.t0 AS t0, w.t1 AS t1
    FROM
    (
        SELECT agent_type, count() AS n, avg(agent_total_tokens) AS mean, max(agent_total_tokens) AS biggest,
               argMax(session_id, agent_total_tokens) AS session, argMax(project, agent_total_tokens) AS project,
               argMax(agent_id, agent_total_tokens) AS run_agent
        FROM cc.events
        WHERE ts >= now() - INTERVAL 7 DAY AND event = 'subagent_completed' AND agent_type != ''
        GROUP BY agent_type
        HAVING n >= 3 AND biggest > 6 * mean AND biggest > 50000
    ) AS o
    LEFT JOIN
    (
        -- cost of the requests of the biggest run (its agent_id)
        SELECT agent_id, sum(cost_usd) AS run_cost
        FROM cc.api_requests
        WHERE agent_id != ''
        GROUP BY agent_id
    ) AS c ON c.agent_id = o.run_agent
    LEFT JOIN
    (
        -- activity span of the session in ms (0 when none): first start to last end of its prompts, requests and tool calls
        SELECT session_id, min(a_s) AS t0, max(a_e) AS t1
        FROM
        (
            SELECT session_id, toUnixTimestamp64Milli(ts) - if(event = 'user_prompt', toInt64(0), toInt64(duration_ms)) AS a_s,
                   toUnixTimestamp64Milli(ts) AS a_e
            FROM cc.events_raw
            WHERE event IN ('user_prompt', 'api_request', 'tool_result')
              AND session_id IN (SELECT session_id FROM cc.events_raw WHERE event = 'subagent_completed' AND ts >= now() - INTERVAL 7 DAY)
        )
        GROUP BY session_id
    ) AS w ON w.session_id = o.session
)
UNION ALL
-- Cache rewrites: a request after a pause of 5 min or more (the cache lifetime) that wrote 50k or more
-- cache-creation tokens. The pause is the gap to the previous request of the same (session_id, agent_id), found
-- over the whole history of the sessions active in the window (as Efficiency 225 and Sessions 445 do); only
-- the requests inside the 7 days are counted. Fires on 3 rewrites or more, or on $2 or more in total.
-- cost_usd is the upper bound of the waste: a fresh session writes a cache too, only a smaller one.
-- The link opens Sessions 445 for the session of the most expensive rewrite, zoomed to its activity span.
SELECT
    'cache-rewrite',
    concat(toString(n), ' cache rewrites after pauses in ', project),
    concat(toString(n), ' requests in 7 days came after a pause of 5 minutes or more and rewrote ',
           multiIf(created < 999500, concat(toString(round(created / 1000)), 'k'), concat(toString(round(created / 1000000, 2)), 'M')),
           ' tokens of cache, $', toString(round(rw_cost, 2)), ' together (the most you could save). ',
           'Run /compact before a long break, or start a new session instead of resuming a huge one.'),
    project,
    toFloat64(n),
    concat('/d/cc-sessions?viewPanel=panel-445&var-session=', encodeURLComponent(session),
           -- zoom to the session: its activity span, padded by 3 % (at least 5 s), as the Sessions table does
           if(t1 = 0, '', concat('&from=', toString(t0 - greatest(intDiv(3 * (t1 - t0), 100), 5000)),
                                 '&to=', toString(t1 + greatest(intDiv(3 * (t1 - t0), 100), 5000))))),
    toNullable(created),
    toNullable(rw_cost)
FROM
(
    SELECT r.project AS project, r.n AS n, r.created AS created, r.rw_cost AS rw_cost, r.session AS session,
           w.t0 AS t0, w.t1 AS t1
    FROM
    (
        SELECT project, count() AS n, sum(cache_creation_tokens) AS created, sum(cost_usd) AS rw_cost,
               argMax(session_id, cost_usd) AS session
        FROM
        (
            SELECT ts, project, session_id, cache_creation_tokens, cost_usd,
                   toUnixTimestamp(ts) AS cur,
                   lagInFrame(toUnixTimestamp(ts), 1, 0) OVER (PARTITION BY session_id, agent_id ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS prev
            FROM cc.api_requests
            WHERE session_id IN (SELECT session_id FROM cc.api_requests WHERE ts >= now() - INTERVAL 7 DAY)
        )
        WHERE ts >= now() - INTERVAL 7 DAY AND prev > 0 AND cur - prev >= 300 AND cache_creation_tokens >= 50000
        GROUP BY project
        HAVING n >= 3 OR rw_cost >= 2
    ) AS r
    LEFT JOIN
    (
        -- activity span of the session in ms (0 when none), as in agent-outlier
        SELECT session_id, min(a_s) AS t0, max(a_e) AS t1
        FROM
        (
            SELECT session_id, toUnixTimestamp64Milli(ts) - if(event = 'user_prompt', toInt64(0), toInt64(duration_ms)) AS a_s,
                   toUnixTimestamp64Milli(ts) AS a_e
            FROM cc.events_raw
            WHERE event IN ('user_prompt', 'api_request', 'tool_result')
              AND session_id IN (SELECT session_id FROM cc.api_requests WHERE ts >= now() - INTERVAL 7 DAY)
        )
        GROUP BY session_id
    ) AS w ON w.session_id = r.session
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
    concat('/d/cc-tools?viewPanel=panel-19&var-project=', encodeURLComponent(project)),
    CAST(NULL AS Nullable(UInt64)),
    CAST(NULL AS Nullable(Float64))
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
    '/d/cc-health?viewPanel=panel-26',
    CAST(NULL AS Nullable(UInt64)),
    CAST(NULL AS Nullable(Float64))
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
    concat('/d/cc-health?viewPanel=panel-161&var-project=', encodeURLComponent(project)),
    CAST(NULL AS Nullable(UInt64)),
    CAST(NULL AS Nullable(Float64))
FROM
(
    SELECT project, model, count() AS n, avg(ttft_ms) AS mean
    FROM cc.events
    WHERE ts >= now() - INTERVAL 7 DAY AND event = 'api_request' AND ttft_ms > 0
    GROUP BY project, model
    HAVING n >= 10 AND mean > 3000
);
EXCHANGE TABLES cc.tips_t AND cc.tips_new;
DROP TABLE cc.tips_new;
