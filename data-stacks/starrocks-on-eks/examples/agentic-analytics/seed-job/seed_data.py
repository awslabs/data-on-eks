"""
Seed job — generates ~1 M synthetic ad_events and writes them to StarRocks.

Injects a known anomaly so the agent has something to find:
  advertiser_id = 42, creative_id = 8821
  In the last 15 minutes their CTR drops from ~2 % to ~0.1 %.

Run once via the K8s Job (seed-job.yaml), then delete the job.
"""

import os
import random
from datetime import datetime, timedelta

import mysql.connector

SR_HOST = os.environ.get("STARROCKS_HOST", "starrocks-shared-data-fe-service.starrocks.svc.cluster.local")
SR_PORT = int(os.environ.get("STARROCKS_PORT", "9030"))
SR_USER = os.environ.get("STARROCKS_USER", "root")
SR_PASS = os.environ.get("STARROCKS_PASSWORD", "")
SR_DB   = os.environ.get("STARROCKS_DATABASE", "ad_analytics")

TOTAL_EVENTS         = 1_000_000
BATCH_SIZE           = 10_000

ANOMALY_ADVERTISER   = 42
ANOMALY_CREATIVE     = 8821
ANOMALY_WINDOW_MIN   = 15

ADVERTISERS = list(range(1, 11)) + [ANOMALY_ADVERTISER]   # include 42 so anomaly fires
CREATIVES   = list(range(1000, 1020)) + [ANOMALY_CREATIVE]
PLACEMENTS  = [101, 102, 103, 104, 105]
DEVICES     = ["mobile", "desktop", "tablet"]
COUNTRIES   = ["US", "GB", "DE", "FR", "JP", "CA", "AU"]


def generate_rows(now: datetime) -> list[tuple]:
    anomaly_cutoff = now - timedelta(minutes=ANOMALY_WINDOW_MIN)
    rows = []
    for i in range(TOTAL_EVENTS):
        ts = now - timedelta(minutes=random.uniform(0, 120))
        advertiser_id = random.choice(ADVERTISERS)
        creative_id   = random.choice(CREATIVES)

        is_anomaly = (
            advertiser_id == ANOMALY_ADVERTISER
            and creative_id == ANOMALY_CREATIVE
            and ts >= anomaly_cutoff
        )

        impressions = random.randint(50, 500)
        # Normal CTR 1.5–3 %; anomaly CTR 0.05–0.15 %
        ctr    = random.uniform(0.0005, 0.0015) if is_anomaly else random.uniform(0.015, 0.03)
        clicks = max(0, int(impressions * ctr))

        rows.append((
            i + 1,
            ts.strftime("%Y-%m-%d %H:%M:%S"),
            advertiser_id,
            creative_id,
            random.choice(PLACEMENTS),
            random.choice(DEVICES),
            random.choice(COUNTRIES),
            impressions,
            clicks,
        ))
    return rows


def main() -> None:
    print(f"Connecting to StarRocks at {SR_HOST}:{SR_PORT} ...")
    conn = mysql.connector.connect(
        host=SR_HOST, port=SR_PORT,
        user=SR_USER, password=SR_PASS,
        database=SR_DB,
        connection_timeout=30,
    )
    cursor = conn.cursor()

    print(f"Generating {TOTAL_EVENTS:,} synthetic events ...")
    now  = datetime.utcnow()
    rows = generate_rows(now)

    sql = """
        INSERT INTO ad_events
            (event_id, event_ts, advertiser_id, creative_id, placement_id,
             device_type, country_code, impressions, clicks)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    """

    total = 0
    for i in range(0, len(rows), BATCH_SIZE):
        batch = rows[i : i + BATCH_SIZE]
        cursor.executemany(sql, batch)
        conn.commit()
        total += len(batch)
        print(f"  {total:>9,} / {TOTAL_EVENTS:,} rows inserted")

    cursor.close()
    conn.close()
    print(
        f"\nDone. Anomaly injected: "
        f"advertiser_id={ANOMALY_ADVERTISER}, creative_id={ANOMALY_CREATIVE} "
        f"in the last {ANOMALY_WINDOW_MIN} minutes."
    )


if __name__ == "__main__":
    main()
