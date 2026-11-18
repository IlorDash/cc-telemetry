-- Backfill of cc.events_t for one time range: claude-code rows of otel.otel_logs that cc.events_t does not
-- have yet (history from before the materialized view existed, rows a restart lost).
-- Run by clickhouse/init-views.sh once per month of data, with the query parameters
--   --param_lo='YYYY-MM-DD hh:mm:ss' --param_hi='YYYY-MM-DD hh:mm:ss' --param_guard=<seconds>
--   (lo inclusive, hi exclusive)
-- so a big history never needs the keys of all events in memory at once (per-query limit 1.5 GB).
-- Safe to repeat: inserts nothing when nothing is missing.
-- - Rows within {guard} seconds of now are left to the materialized view (a row that is just arriving would
--   otherwise be copied twice). init-views.sh passes 30 for the month passes and 5 for the second pass, which
--   runs more than 30 s after the view was created, so every row from before the view (even from a client
--   whose clock is up to 30 s ahead) is older than the guard by then.
-- - The months together have no lower or upper bound, and rows more than {guard} s ahead of now are copied
--   too: a client with a wrong clock still gets its rows.
-- - (session_id, seq, ts) is unique over all events; (session_id, seq) alone is not.
-- Same expressions as cc.events_mv in schema.sql (keep in step).
INSERT INTO cc.events_t
SELECT * EXCEPT (j_file, j_nb, j_dir, raw_path, pp, c0)
FROM
(
    SELECT
        Timestamp                                                   AS ts,
        lower(if(ResourceAttributes['project'] != '', ResourceAttributes['project'], 'unknown')) AS project_label,
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
        toUInt64OrZero(LogAttributes['total_duration_ms'])          AS hook_duration_ms,
        toUInt64OrZero(LogAttributes['tool_result_size_bytes'])     AS result_bytes,
        toUInt64OrZero(LogAttributes['ttft_ms'])                    AS ttft_ms,
        toUInt64OrZero(LogAttributes['event.sequence'])             AS seq,
        if(event = 'tool_result', JSONExtractString(tool_input, 'file_path'), '')     AS j_file,
        if(event = 'tool_result', JSONExtractString(tool_input, 'notebook_path'), '') AS j_nb,
        if(event = 'tool_result', JSONExtractString(tool_input, 'path'), '')          AS j_dir,
        multiIf(j_file != '', j_file, j_nb != '', j_nb, j_dir) AS raw_path,
        replaceRegexpOne(lower(replaceAll(raw_path, '\\', '/')), '^/([a-z])/', '\\1:/') AS abs_path,
        if(j_file = '' AND j_nb = '', replaceRegexpOne(abs_path, '/*$', '/'), abs_path) AS pp,
        extract(pp, '^(?:/mnt/[a-z]/|/|[a-z]:/)(?:(?:users|home)/[^/]+/|root/)?(?:(?:documents|projects|project|repos|repo|src|source|sources|dev|work|code|git|github|gitlab|workspace|workspaces|desktop|downloads|onedrive(?: - [^/]*)?)/)*([^/.][^/]*)/') AS c0,
        if(c0 IN ('users', 'home', 'root', 'mnt', 'documents', 'projects', 'project', 'repos', 'repo', 'src', 'source',
                  'sources', 'dev', 'work', 'code', 'git', 'github', 'gitlab', 'workspace', 'workspaces', 'desktop',
                  'downloads', 'onedrive', 'appdata', 'tmp', 'temp', 'var', 'etc', 'usr', 'proc', 'sys', 'windows', 'programdata',
                  'program files', 'program files (x86)', 'node_modules', '$recycle.bin')
              OR startsWith(c0, 'onedrive - '), '', c0) AS path_cand,
        JSONExtractString(tool_parameters, 'bash_command')          AS bash_cmd
    FROM otel.otel_logs
    WHERE ServiceName = 'claude-code'
      -- TimestampTime = toDateTime(Timestamp): the first two conditions let ClickHouse skip whole days
      AND TimestampTime >= toDateTime({lo:String}) AND TimestampTime <= toDateTime({hi:String})
      AND Timestamp >= toDateTime64({lo:String}, 9) AND Timestamp < toDateTime64({hi:String}, 9)
      AND (Timestamp < now() - toIntervalSecond({guard:UInt32}) OR Timestamp > now() + toIntervalSecond({guard:UInt32}))
      AND (LogAttributes['session.id'], toUInt64OrZero(LogAttributes['event.sequence']), Timestamp)
          NOT IN (SELECT session_id, seq, ts FROM cc.events_t
                  WHERE ts >= toDateTime64({lo:String}, 9) AND ts < toDateTime64({hi:String}, 9))
);
