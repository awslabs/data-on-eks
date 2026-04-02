"""
convert_parquet_to_iceberg.py
─────────────────────────────
PySpark job that converts existing TPC-DS v4 Parquet tables (1 TB scale)
to Apache Iceberg format stored in AWS Glue Data Catalog.

Why Iceberg?
  Raw-Parquet reads bypass Spark's catalog and have no partition statistics,
  so Dynamic Partition Pruning (DPP) degrades to full table scans on
  partition-sensitive queries (q14, q23, q24, q39, q47, q57).
  Iceberg tables registered in Glue expose column stats + partition metadata
  that allow the Spark optimizer to prune partitions correctly.

Usage (via SparkApplication YAML — all args come from SparkApplication.spec.arguments):
  spark-submit convert_parquet_to_iceberg.py \\
      --src-bucket      <S3_BUCKET>              \\
      --src-prefix      TPCDS-TEST-3TB           \\
      --glue-db         tpcds_3tb                \\
      --iceberg-prefix  TPCDS-TEST-3TB-ICEBERG   \\
      --region          us-west-2                \\
      [--table          <single_table>]          # optional: convert one table only

S3 layout (single Iceberg prefix with data/ and metadata/ subdirectories):
  Parquet-only data : s3://<bucket>/TPCDS-TEST-{N}TB/{table}/                  (--src-prefix)
  Iceberg data files: s3://<bucket>/TPCDS-TEST-{N}TB-ICEBERG/data/{table}/     (derived)
  Iceberg metadata  : s3://<bucket>/TPCDS-TEST-{N}TB-ICEBERG/metadata/         (derived)

  To run at a different scale (3TB, 10TB), change --src-prefix, --glue-db,
  and --iceberg-prefix in the SparkApplication YAML — no image rebuild needed.

The job is idempotent — it checks existing Glue tables and skips any already converted.

Partition columns match the standard TPC-DS partitioning used by the
databricks/spark-sql-perf data generation tooling:
  Fact tables  → partitioned on their sold-date foreign key
  Dim tables   → not partitioned (small, fits in broadcast)
"""

import argparse
import time
import sys

from pyspark.sql import SparkSession


# ── TPC-DS v4 table definitions ──────────────────────────────────────────────
# (table_name, partition_column_or_None)
# Fact tables are partitioned on their date dimension FK for DPP.
# Dimension tables are left unpartitioned (broadcast-eligible, typically <1 GB).

TPCDS_TABLES = [
    # ── Fact tables (partitioned) ────────────────────────────────────────────
    ("store_sales",          "ss_sold_date_sk"),
    ("store_returns",        "sr_returned_date_sk"),
    ("catalog_sales",        "cs_sold_date_sk"),
    ("catalog_returns",      "cr_returned_date_sk"),
    ("web_sales",            "ws_sold_date_sk"),
    ("web_returns",          "wr_returned_date_sk"),
    ("inventory",            "inv_date_sk"),
    # ── Dimension tables (unpartitioned) ─────────────────────────────────────
    ("customer",             None),
    ("customer_address",     None),
    ("customer_demographics", None),
    ("date_dim",             None),
    ("household_demographics", None),
    ("item",                 None),
    ("promotion",            None),
    ("reason",               None),
    ("ship_mode",            None),
    ("store",                None),
    ("time_dim",             None),
    ("warehouse",            None),
    ("web_page",             None),
    ("web_site",             None),
    ("call_center",          None),
    ("catalog_page",         None),
    ("income_band",          None),
]


def parse_args():
    parser = argparse.ArgumentParser(description="Convert TPC-DS Parquet → Iceberg (Glue catalog)")
    # ── Scale-specific args — only these change per benchmark scale in the YAML ─
    # Scale | --src-prefix         | --glue-db   | --iceberg-prefix
    # 1TB   | TPCDS-TEST-1TB       | tpcds_1tb   | TPCDS-TEST-1TB-ICEBERG
    # 3TB   | TPCDS-TEST-3TB       | tpcds_3tb   | TPCDS-TEST-3TB-ICEBERG
    # 10TB  | TPCDS-TEST-10TB      | tpcds_10tb  | TPCDS-TEST-10TB-ICEBERG
    parser.add_argument("--src-bucket",     required=True,  help="Source S3 bucket name (no s3a:// prefix)")
    parser.add_argument("--src-prefix",     required=True,  help="S3 prefix for source Parquet, e.g. TPCDS-TEST-3TB")
    parser.add_argument("--glue-db",        required=True,  help="Target Glue database name, e.g. tpcds_3tb")
    parser.add_argument("--iceberg-prefix", required=True,  help="S3 prefix for Iceberg output, e.g. TPCDS-TEST-3TB-ICEBERG")
    # ── Fixed args ───────────────────────────────────────────────────────────────
    parser.add_argument("--region",      default="us-west-2",  help="AWS region for Glue")
    parser.add_argument("--table",       default=None,         help="Convert a single table only (optional)")
    return parser.parse_args()


def get_existing_tables(spark, glue_db):
    """Return set of table names already in the Glue database."""
    try:
        rows = spark.sql(f"SHOW TABLES IN glue_catalog.{glue_db}").collect()
        return {r.tableName for r in rows}
    except Exception:
        return set()


def ensure_glue_database(spark, glue_db):
    spark.sql(f"CREATE DATABASE IF NOT EXISTS glue_catalog.{glue_db}")
    print(f"[info] Glue database ready: {glue_db}")


def convert_table(spark, table_name, partition_col, src_path, glue_db, data_path):
    """
    CTAS: read Parquet from src_path, write as partitioned Iceberg table in Glue.
    Uses CREATE OR REPLACE so re-running is safe (drops old Iceberg snapshot).

    S3 layout (derived from --iceberg-prefix):
      src_path  → --src-prefix           (raw Parquet, read-only source)
      data_path → <iceberg-prefix>/data  (Iceberg data files)
      warehouse → <iceberg-prefix>/metadata (Iceberg metadata/snapshots)
    """
    full_table = f"glue_catalog.{glue_db}.{table_name}"

    partition_clause = ""
    if partition_col:
        partition_clause = f"PARTITIONED BY ({partition_col})"

    table_data_path = f"{data_path.rstrip('/')}/{table_name}"

    sql = f"""
        CREATE OR REPLACE TABLE {full_table}
        USING iceberg
        {partition_clause}
        TBLPROPERTIES (
            'write.format.default' = 'parquet',
            'write.parquet.compression-codec' = 'snappy',
            'write.data.path' = '{table_data_path}'
        )
        AS SELECT * FROM parquet.`{src_path}`
    """

    t0 = time.time()
    spark.sql(sql)
    elapsed = time.time() - t0
    row_count = spark.sql(f"SELECT COUNT(1) FROM {full_table}").collect()[0][0]
    print(f"[ok]  {table_name:35s}  {row_count:>15,} rows  {elapsed:6.1f}s")
    return elapsed


def main():
    args = parse_args()

    src_base = f"s3a://{args.src_bucket}/{args.src_prefix}"
    warehouse = f"s3a://{args.src_bucket}/{args.iceberg_prefix}/metadata"
    data_path = f"s3a://{args.src_bucket}/{args.iceberg_prefix}/data"

    spark = (
        SparkSession.builder
        .appName("TPC-DS Parquet to Iceberg Conversion")
        # Iceberg Glue catalog
        .config("spark.sql.extensions",
                "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .config("spark.sql.catalog.glue_catalog",
                "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.glue_catalog.catalog-impl",
                "org.apache.iceberg.aws.glue.GlueCatalog")
        .config("spark.sql.catalog.glue_catalog.warehouse", warehouse)
        .config("spark.sql.catalog.glue_catalog.io-impl",
                "org.apache.iceberg.aws.s3.S3FileIO")
        .config("spark.sql.catalog.glue_catalog.glue.region", args.region)
        # v2 bridge so unqualified SQL also resolves via Iceberg
        .config("spark.sql.catalog.spark_catalog",
                "org.apache.iceberg.spark.SparkSessionCatalog")
        .config("spark.sql.catalog.spark_catalog.type", "glue")
        # Use Glue-provided column statistics for DPP
        .config("spark.sql.statistics.fallBackToHdfs", "false")
        .getOrCreate()
    )

    spark.sparkContext.setLogLevel("WARN")

    ensure_glue_database(spark, args.glue_db)
    existing = get_existing_tables(spark, args.glue_db)

    tables_to_convert = TPCDS_TABLES
    if args.table:
        tables_to_convert = [(t, p) for t, p in TPCDS_TABLES if t == args.table]
        if not tables_to_convert:
            print(f"[error] Unknown table: {args.table}")
            sys.exit(1)

    print(f"\n{'Table':35s}  {'Rows':>15}  {'Time':>6}")
    print("─" * 65)

    total_start = time.time()
    skipped = 0
    converted = 0
    failed = []

    for table_name, partition_col in tables_to_convert:
        if table_name in existing:
            print(f"[skip] {table_name:35s}  (already in Glue — use CREATE OR REPLACE to force)")
            skipped += 1
            continue

        src_path = f"{src_base}/{table_name}"
        try:
            convert_table(spark, table_name, partition_col, src_path, args.glue_db, data_path)
            converted += 1
        except Exception as exc:
            print(f"[fail] {table_name}: {exc}")
            failed.append(table_name)

    total_elapsed = time.time() - total_start
    print(f"\n{'─' * 65}")
    print(f"Converted : {converted}")
    print(f"Skipped   : {skipped}")
    print(f"Failed    : {len(failed)}  {failed if failed else ''}")
    print(f"Total time: {total_elapsed:.1f}s")

    spark.stop()

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
