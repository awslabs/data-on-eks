import os
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, to_date, avg, max, count, lit, sum, when

# ==============================================================================
#  1. Configuration
# ==============================================================================
# These should be configured to match your environment
S3_WAREHOUSE_PATH = os.getenv('S3_WAREHOUSE_PATH', 's3a://your-bucket/iceberg-warehouse/')
ICEBERG_CATALOG_NAME = 'workshop'
GLUE_DATABASE_NAME = 'data_on_eks'

def main():
    """
    A Spark batch job that reads from raw Iceberg tables, creates a daily
    summary for each cat, and writes the result to a new, clean Iceberg table.
    """
    print("Starting Spark session for Daily Cat Summary job...")
    spark = (
        SparkSession.builder
        .appName("DailyCatSummaryETL")
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .config(f"spark.sql.catalog.{ICEBERG_CATALOG_NAME}", "org.apache.iceberg.spark.SparkCatalog")
        .config(f"spark.sql.catalog.{ICEBERG_CATALOG_NAME}.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog")
        .config(f"spark.sql.catalog.{ICEBERG_CATALOG_NAME}.warehouse", S3_WAREHOUSE_PATH)
        .config(f"spark.sql.catalog.{ICEBERG_CATALOG_NAME}.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")
        .getOrCreate()
    )
    print("Spark session created.")

    # Define the full path to our source and destination tables
    wellness_table = f"{ICEBERG_CATALOG_NAME}.{GLUE_DATABASE_NAME}.cat_wellness_raw"
    interactions_table = f"{ICEBERG_CATALOG_NAME}.{GLUE_DATABASE_NAME}.cat_interactions_raw"
    profiles_table = f"{ICEBERG_CATALOG_NAME}.{GLUE_DATABASE_NAME}.cats_profiles_raw"
    summary_table = f"{ICEBERG_CATALOG_NAME}.{GLUE_DATABASE_NAME}.daily_cat_summary"

    try:
        # ==============================================================================
        #  2. EXTRACT: Read the raw source tables from Iceberg
        # ==============================================================================
        print(f"Reading from source tables: {wellness_table} and {interactions_table}")
        wellness_df = spark.table(wellness_table)
        interactions_df = spark.table(interactions_table)
        profiles_df = spark.table(profiles_table)

        # ==============================================================================
        #  3. TRANSFORM: Perform aggregations and joins
        # ==============================================================================
        print("Transforming data: Aggregating daily wellness and interaction metrics...")

        # --- Aggregate wellness data by day ---
        wellness_daily_df = (
            wellness_df
            .withColumn("day", to_date(col("event_time")))
            .groupBy("cat_id", "day")
            .agg(
                avg("activity_level").alias("avg_activity_level"),
                max("hours_since_last_drink").alias("max_hours_since_drink")
            )
        )

        # --- Aggregate interaction data by day ---
        interactions_daily_df = (
            interactions_df
            .withColumn("day", to_date(col("event_time")))
            .groupBy("cat_id", "day")
            .agg(
                count("*").alias("total_interaction_count"),
                sum(when(col("interaction_type") == "like", 1).otherwise(0)).alias("like_count")
            )
        )

        # --- Join the summaries together ---
        print("Joining daily summaries...")
        daily_summary_df = (
            wellness_daily_df
            .join(interactions_daily_df, ["cat_id", "day"], "full_outer")
            # Join with profiles to get the cat's name
            .join(profiles_df.select("cat_id", "name"), "cat_id", "left")
            .na.fill(0) # Fill nulls with 0 for counts/metrics where one side of the join had no data
            .select(
                "day",
                "cat_id",
                "name",
                "avg_activity_level",
                "max_hours_since_drink",
                "total_interaction_count",
                "like_count"
            )
        )

        # ==============================================================================
        #  4. LOAD: Write the final summary table to Iceberg
        # ==============================================================================
        print(f"Writing final summary to Iceberg table: {summary_table}")
        (
            daily_summary_df.writeTo(summary_table)
            .partitionedBy("day") # Partition the summary table by day for fast queries
            .createOrReplace()
        )

        print(f"Successfully created or replaced '{summary_table}' table.")

    except Exception as e:
        print(f"An error occurred during the ETL job: {e}")
        raise
    finally:
        print("\nBatch job complete. Stopping Spark session.")
        spark.stop()


if __name__ == '__main__':
    main()