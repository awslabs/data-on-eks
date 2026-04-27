-- Agentic Analytics schema for StarRocks (Shared-Data mode)
--
-- Run this against the StarRocks FE before starting the seed job:
--   mysql -h <FE_HOST> -P 9030 -u root < starrocks-schema.sql
--
-- Or interactively:
--   kubectl exec -n starrocks deploy/starrocks-shared-data-fe -- \
--     mysql -h 127.0.0.1 -P 9030 -u root

CREATE DATABASE IF NOT EXISTS ad_analytics;
USE ad_analytics;

-- Primary table: ad impression/click events
-- PK upsert semantics, hourly partitions for pruning, hash-distributed on event_id
CREATE TABLE IF NOT EXISTS ad_events (
    event_id        BIGINT        NOT NULL,
    event_ts        DATETIME      NOT NULL,
    advertiser_id   INT           NOT NULL,
    creative_id     INT           NOT NULL,
    placement_id    INT           NOT NULL,
    device_type     VARCHAR(32)   NOT NULL,
    country_code    VARCHAR(8)    NOT NULL,
    impressions     INT           NOT NULL,
    clicks          INT           NOT NULL
)
PRIMARY KEY (event_id, event_ts)
PARTITION BY date_trunc('hour', event_ts)
DISTRIBUTED BY HASH(event_id) BUCKETS 32
PROPERTIES (
    "replication_num"          = "1",
    "enable_persistent_index"  = "true"
);

-- 1-minute async MV — fast CTR rollup used by the MCP list_dims tool
CREATE MATERIALIZED VIEW IF NOT EXISTS ad_events_1min
REFRESH ASYNC EVERY (INTERVAL 1 MINUTE)
AS
SELECT
    date_trunc('minute', event_ts)                                   AS ts_minute,
    advertiser_id,
    creative_id,
    placement_id,
    device_type,
    country_code,
    SUM(impressions)                                                  AS impressions,
    SUM(clicks)                                                       AS clicks,
    ROUND(SUM(clicks) / NULLIF(SUM(impressions), 0) * 100, 4)        AS ctr_pct
FROM ad_events
GROUP BY 1, 2, 3, 4, 5, 6;
