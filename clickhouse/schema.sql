-- Storage for the cc.* views: the table of flattened Claude Code events, its materialized view and two
-- small derived tables. Applied by clickhouse/init-views.sh before clickhouse/backfill.sql and
-- clickhouse/views.sql.
--
-- Claude Code events are flattened once, at insert time, into cc.events_t by the materialized view
-- cc.events_mv from otel.otel_logs (written by the collector). The cc.* views read that table and the
-- tables cc.session_project_t and cc.tips_t, which clickhouse/refresh.sql rebuilds every few minutes.
--
-- Re-runnable: everything is CREATE ... IF NOT EXISTS. A materialized view cannot be replaced: changing the
-- expressions of cc.events_mv (or the columns of cc.events_t) needs an explicit migration, because
-- IF NOT EXISTS skips the change and old rows keep the old values.
-- Migrate by hand: back up (linux-server-tools/backup.sh dump), DROP VIEW cc.events_mv, rebuild cc.events_t
-- (a new table filled by INSERT ... SELECT with the new expressions from otel.otel_logs, one month at a time:
-- one INSERT over more than 100 daily partitions is refused; then EXCHANGE TABLES),
-- CREATE the new view; events that arrive in between must be covered (rerun the backfill).
-- The expressions are written twice, here and in backfill.sql: keep them in step (and the path rules also
-- in cc.path_roots, views.sql).
--
-- The layout of cc.events_t (PARTITION BY, TTL, SETTINGS) is different: setup-server.sh migrates it
-- (migrate_storage, on every run; Windows servers: README, manual migration). It takes the CREATE TABLE of
-- cc.events_t below as the target and reads the retention from its TTL line, which otel.* get too. So keep
-- the lines "CREATE TABLE IF NOT EXISTS cc.events_t", "PARTITION BY ..." and "TTL ... INTERVAL <n> DAY" as
-- they are written, and the exporter ttl in otel-collector.yaml at the same number of days.

CREATE DATABASE IF NOT EXISTS cc;

-- cc.events_t: one row per Claude Code event, attributes flattened into typed columns.
--    project_label = the explicit label from OTEL_RESOURCE_ATTRIBUTES ('unknown' when missing).
--    The effective project (label, else inferred from file paths) is cc.events (views.sql).
--    Columns after ttft_ms are computed at insert time and used by the views, not exposed by cc.events_raw:
--      seq        event.sequence; (session_id, seq, ts) identifies an event (the backfill skips known ones)
--      abs_path   tool_result: the normalised path of the call (file_path, notebook_path, path):
--                 lower case, `\` -> `/`, `/c/` -> `c:/`
--      path_cand  tool_result: candidate project folder of that path (rules in cc.path_roots, views.sql)
--      bash_cmd   tool_parameters.bash_command (first word of the command only)
CREATE TABLE IF NOT EXISTS cc.events_t
(
    ts                    DateTime64(9),
    project_label         LowCardinality(String),
    host                  LowCardinality(String),
    cc_version            LowCardinality(String),
    event                 LowCardinality(String),
    session_id            String,
    prompt_id             String,
    account               LowCardinality(String),
    agent_id              String,
    request_id            String,
    query_source          LowCardinality(String),
    agent_name            LowCardinality(String),
    agent_type            LowCardinality(String),
    skill_name            LowCardinality(String),
    skill_trigger         LowCardinality(String),
    tool_name             LowCardinality(String),
    tool_use_id           String,
    tool_input            String CODEC(ZSTD(1)),
    tool_parameters       String CODEC(ZSTD(1)),
    success               UInt8,
    decision              LowCardinality(String),
    decision_source       LowCardinality(String),
    duration_ms           UInt64,
    model                 LowCardinality(String),
    input_tokens          UInt64,
    output_tokens         UInt64,
    cache_read_tokens     UInt64,
    cache_creation_tokens UInt64,
    cost_usd              Float64,
    agent_total_tokens    UInt64,
    agent_tool_uses       UInt64,
    prompt                String CODEC(ZSTD(1)),
    hook_name             LowCardinality(String),
    hook_duration_ms      UInt64,
    result_bytes          UInt64,
    ttft_ms               UInt64,
    seq                   UInt64,
    abs_path              String,
    path_cand             String,
    bash_cmd              String
)
ENGINE = MergeTree
PARTITION BY toDate(ts)
ORDER BY (event, ts)
TTL toDateTime(ts) + INTERVAL 180 DAY
SETTINGS ttl_only_drop_parts = 1;

-- Inferred project per session and usage tips: small tables rebuilt by clickhouse/refresh.sql, run only by the
-- cc-refresh service (a new table is filled, then swapped in with EXCHANGE TABLES, so readers never see a
-- half-built one).
CREATE TABLE IF NOT EXISTS cc.session_project_t
(
    session_id String,
    project    String
)
ENGINE = MergeTree
ORDER BY session_id;

CREATE TABLE IF NOT EXISTS cc.tips_t
(
    category String,
    title    String,
    body     String,
    scope    String,
    metric   Float64,
    link     String
)
ENGINE = MergeTree
ORDER BY tuple();

-- Insert-time flattening of every new claude-code row of otel.otel_logs into cc.events_t.
-- Path rules (normalisation, the container-folder regex and the IN stop list) are written three times:
-- here, in backfill.sql, and for the session working directory in cc.path_roots (views.sql).
-- Keep the three in step: regex, stop list and trailing-slash rule.
CREATE MATERIALIZED VIEW IF NOT EXISTS cc.events_mv TO cc.events_t AS
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
);
