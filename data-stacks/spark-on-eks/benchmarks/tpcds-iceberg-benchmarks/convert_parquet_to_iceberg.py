"""
convert_parquet_to_iceberg.py
─────────────────────────────
PySpark job that converts existing TPC-DS Parquet tables in S3
to Apache Iceberg tables registered in AWS Glue Data Catalog.

Why Iceberg?
  Reading raw Parquet paths bypasses catalog-managed table metadata.
  Iceberg tables registered in Glue provide a stronger table abstraction,
  partition metadata, and better optimizer integration for pruning and planning.

Recommended S3 layout:
  Raw Parquet source:
    s3://<bucket>/<src-prefix>/<table>/

  Iceberg warehouse root:
    s3://<bucket>/<iceberg-prefix>/

  Iceberg table root:
    s3://<bucket>/<iceberg-prefix>/<glue-db>.db/<table>/

Example usecase:
  Raw source:
    s3://${S3_BUCKET}/TPCDS-TEST-3TB/store_sales/

  Iceberg warehouse root (shared across all scales):
    s3://${S3_BUCKET}/tpcds-iceberg/

  Iceberg table root:
    s3://${S3_BUCKET}/tpcds-iceberg/tpcds_3tb.db/store_sales/
        ├── metadata/  (Iceberg metadata JSON + manifests)
        └── data/      (Parquet data files)

  S3 hierarchy for multiple scales:
    s3://${S3_BUCKET}/tpcds-iceberg/
    ├── tpcds_1tb.db/
    ├── tpcds_3tb.db/
    └── tpcds_10tb.db/

Usage:
  spark-submit convert_parquet_to_iceberg.py \
      --src-bucket ${S3_BUCKET} \
      --src-prefix TPCDS-TEST-3TB \
      --glue-db tpcds_3tb \
      --iceberg-prefix tpcds-iceberg \
      --region us-west-2 \
      [--table store_sales] \
      [--overwrite] \
      [--verify-counts] \
      [--compute-stats] \
      [--stats-only]

Operational behavior:
  - By default, existing Glue tables are skipped
  - Use --overwrite to replace existing tables
  - Use --verify-counts only for spot checks because it is expensive
"""

import argparse
import sys
import time
from typing import List, Optional, Set, Tuple

from pyspark.sql import SparkSession
from pyspark.sql.functions import col

MAX_RETRIES = 1          # per-table retry attempts on transient failure
RETRY_SLEEP_SEC = 30     # seconds to wait before retry
TARGET_FILE_SIZE = 1 * 1024 ** 3   # 1 GiB — reduces small-file count at scale


# (table_name, partition_column_or_None)
TPCDS_TABLES: List[Tuple[str, Optional[str]]] = [
    # Fact tables
    ("store_sales", "ss_sold_date_sk"),
    ("store_returns", "sr_returned_date_sk"),
    ("catalog_sales", "cs_sold_date_sk"),
    ("catalog_returns", "cr_returned_date_sk"),
    ("web_sales", "ws_sold_date_sk"),
    ("web_returns", "wr_returned_date_sk"),
    ("inventory", "inv_date_sk"),
    # Dimension tables
    ("customer", None),
    ("customer_address", None),
    ("customer_demographics", None),
    ("date_dim", None),
    ("household_demographics", None),
    ("item", None),
    ("promotion", None),
    ("reason", None),
    ("ship_mode", None),
    ("store", None),
    ("time_dim", None),
    ("warehouse", None),
    ("web_page", None),
    ("web_site", None),
    ("call_center", None),
    ("catalog_page", None),
    ("income_band", None),
]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert TPC-DS Parquet tables in S3 to Iceberg tables in Glue"
    )
    parser.add_argument(
        "--src-bucket",
        required=True,
        help="Source S3 bucket name without s3:// or s3a://",
    )
    parser.add_argument(
        "--src-prefix",
        required=True,
        help="Source S3 prefix containing Parquet tables, e.g. TPCDS-TEST-3TB",
    )
    parser.add_argument(
        "--glue-db",
        required=True,
        help="Glue database name, e.g. tpcds_3tb",
    )
    parser.add_argument(
        "--iceberg-prefix",
        required=True,
        help="Iceberg warehouse root prefix, e.g. TPCDS-TEST-3TB-ICEBERG",
    )
    parser.add_argument(
        "--region",
        default="us-west-2",
        help="AWS region for Glue",
    )
    parser.add_argument(
        "--table",
        default=None,
        help="Convert only one table",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace existing Iceberg table if it already exists",
    )
    parser.add_argument(
        "--verify-counts",
        action="store_true",
        help="Run COUNT(*) on source and target after conversion (expensive)",
    )
    parser.add_argument(
        "--compute-stats",
        action="store_true",
        help="Compute NDV column statistics (Puffin files) for cost-based optimization",
    )
    parser.add_argument(
        "--stats-only",
        action="store_true",
        help="Only compute NDV stats on existing tables; skip conversion",
    )
    return parser.parse_args()


def normalize_s3a_path(bucket: str, prefix: str) -> str:
    clean_prefix = prefix.strip("/")
    if clean_prefix:
        return f"s3a://{bucket}/{clean_prefix}"
    return f"s3a://{bucket}"


def build_spark_session(region: str, warehouse_root: str) -> SparkSession:
    return (
        SparkSession.builder
        .appName("TPC-DS Parquet to Iceberg Conversion")
        .config(
            "spark.sql.extensions",
            "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
        )
        .config(
            "spark.sql.catalog.glue_catalog",
            "org.apache.iceberg.spark.SparkCatalog",
        )
        .config(
            "spark.sql.catalog.glue_catalog.catalog-impl",
            "org.apache.iceberg.aws.glue.GlueCatalog",
        )
        .config(
            "spark.sql.catalog.glue_catalog.io-impl",
            "org.apache.iceberg.aws.s3.S3FileIO",
        )
        .config(
            "spark.sql.catalog.glue_catalog.warehouse",
            warehouse_root,
        )
        .config(
            "spark.sql.catalog.glue_catalog.glue.region",
            region,
        )
        .config("spark.sql.statistics.fallBackToHdfs", "false")
        .getOrCreate()
    )


def ensure_glue_database(spark: SparkSession, glue_db: str) -> None:
    spark.sql(f"CREATE DATABASE IF NOT EXISTS glue_catalog.{glue_db}")
    print(f"[info] Glue database ready: {glue_db}")


def get_existing_tables(spark: SparkSession, glue_db: str) -> Set[str]:
    try:
        rows = spark.sql(f"SHOW TABLES IN glue_catalog.{glue_db}").collect()
        return {row.tableName for row in rows}
    except Exception as exc:
        raise RuntimeError(f"Failed to list existing tables in Glue database {glue_db}: {exc}") from exc


def get_tables_to_convert(single_table: Optional[str]) -> List[Tuple[str, Optional[str]]]:
    if single_table is None:
        return TPCDS_TABLES

    matches = [(t, p) for t, p in TPCDS_TABLES if t == single_table]
    if not matches:
        raise ValueError(f"Unknown TPC-DS table: {single_table}")
    return matches


def compute_ndv_statistics(spark: SparkSession, glue_db: str, table_name: str) -> None:
    """Compute NDV column statistics (Puffin files) for CBO."""
    start = time.time()
    spark.sql(f"CALL glue_catalog.system.compute_table_stats('{glue_db}.{table_name}')")
    elapsed = time.time() - start
    print(f"[stats] {glue_db}.{table_name:25s} NDV stats computed in {elapsed:7.1f}s")


def convert_table(
    spark: SparkSession,
    glue_db: str,
    table_name: str,
    partition_col: Optional[str],
    src_path: str,
    table_location: str,
    overwrite: bool,
    verify_counts: bool,
    compute_stats: bool,
) -> None:
    """
    Convert one source Parquet table into one Iceberg table.

    Each Iceberg table gets its own table root:
      <warehouse-root>/<glue-db>.db/<table>/

    Iceberg manages metadata/ and data/ under that table root.
    """
    full_table_name = f"glue_catalog.{glue_db}.{table_name}"

    source_df = spark.read.parquet(src_path)
    if verify_counts:
        source_df = source_df.cache()

    writer = (
        source_df.writeTo(full_table_name)
        .using("iceberg")
        .tableProperty("location", table_location)
        .tableProperty("write.format.default", "parquet")
        .tableProperty("write.parquet.compression-codec", "snappy")
        .tableProperty("write.target-file-size-bytes", str(TARGET_FILE_SIZE))
        .tableProperty("write.object-storage.enabled", "true")
        .tableProperty("write.object-storage.partitioned-paths", "true")
    )

    if partition_col:
        writer = writer.partitionedBy(col(partition_col))

    start = time.time()

    if overwrite:
        writer.createOrReplace()
    else:
        writer.create()

    elapsed = time.time() - start

    if compute_stats:
        compute_ndv_statistics(spark, glue_db, table_name)

    if verify_counts:
        src_count = source_df.count()   # served from cache — no S3 re-scan
        tgt_count = spark.table(full_table_name).count()
        source_df.unpersist()
        if src_count != tgt_count:
            raise RuntimeError(
                f"Row count mismatch for {table_name}: source={src_count}, target={tgt_count}"
            )
        print(f"[ok]   {table_name:25s} created in {elapsed:7.1f}s rows={tgt_count:,}")
    else:
        print(f"[ok]   {table_name:25s} created in {elapsed:7.1f}s")


def main():
    args = parse_args()

    src_base = normalize_s3a_path(args.src_bucket, args.src_prefix)
    warehouse_root = normalize_s3a_path(args.src_bucket, args.iceberg_prefix)

    spark = build_spark_session(args.region, warehouse_root)
    spark.sparkContext.setLogLevel("WARN")

    try:
        ensure_glue_database(spark, args.glue_db)
        existing_tables = get_existing_tables(spark, args.glue_db)
        tables_to_convert = get_tables_to_convert(args.table)

        if args.stats_only:
            _run_stats_only(spark, args.glue_db, tables_to_convert, existing_tables)
            return

        converted = 0
        skipped = 0
        failed = []

        print(f"\n{'Table':25s} {'Status':10s} {'Time'}")
        print("-" * 70)

        total_start = time.time()

        for table_name, partition_col in tables_to_convert:
            src_path = f"{src_base}/{table_name}"
            table_location = f"{warehouse_root}/{args.glue_db}.db/{table_name}"

            if table_name in existing_tables and not args.overwrite:
                print(f"[skip] {table_name:25s} already exists")
                skipped += 1
                continue

            for attempt in range(MAX_RETRIES + 1):
                try:
                    convert_table(
                        spark=spark,
                        glue_db=args.glue_db,
                        table_name=table_name,
                        partition_col=partition_col,
                        src_path=src_path,
                        table_location=table_location,
                        overwrite=args.overwrite,
                        verify_counts=args.verify_counts,
                        compute_stats=args.compute_stats,
                    )
                    converted += 1
                    break
                except Exception as exc:
                    if attempt < MAX_RETRIES:
                        print(f"[retry] {table_name:25s} attempt {attempt + 1} failed: {exc} — retrying in {RETRY_SLEEP_SEC}s")
                        time.sleep(RETRY_SLEEP_SEC)
                    else:
                        print(f"[fail] {table_name:25s} {exc}")
                        failed.append(table_name)

        total_elapsed = time.time() - total_start

        print("\n" + "-" * 70)
        print(f"Converted : {converted}")
        print(f"Skipped   : {skipped}")
        print(f"Failed    : {len(failed)} {failed if failed else ''}")
        print(f"Total time: {total_elapsed:.1f}s")

        if failed:
            sys.exit(1)

    finally:
        spark.stop()


def _run_stats_only(
    spark: SparkSession,
    glue_db: str,
    tables: List[Tuple[str, Optional[str]]],
    existing_tables: Set[str],
) -> None:
    """Compute NDV statistics on existing Iceberg tables only."""
    failed = []
    total_start = time.time()

    for table_name, _ in tables:
        if table_name not in existing_tables:
            print(f"[skip] {table_name:25s} not found in catalog")
            continue
        try:
            compute_ndv_statistics(spark, glue_db, table_name)
        except Exception as exc:
            print(f"[fail] {table_name:25s} {exc}")
            failed.append(table_name)

    print(f"\nTotal time: {time.time() - total_start:.1f}s")
    if failed:
        print(f"Failed: {failed}")
        sys.exit(1)


if __name__ == "__main__":
    main()