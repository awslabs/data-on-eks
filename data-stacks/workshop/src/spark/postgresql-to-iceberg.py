import os
from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, TimestampType

DB_URL = os.getenv('DB_URL', 'jdbc:postgresql://postgresql-0.postgresql.workshop.svc.cluster.local:5432/workshop')
DB_USER = os.getenv('DB_USER', 'workshop')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'workshop')
S3_WAREHOUSE_PATH = os.getenv('S3_WAREHOUSE_PATH', 's3a://data-on-eks-spark-logs-20251001184655839600000005/iceberg-warehouse/')
DB_DRIVER = "org.postgresql.Driver"
GLUE_DATABASE_NAME = "data_on_eks"

# Spark's JDBC reader often infers all columns as nullable, so we match that behavior.
cats_schema = StructType([
    StructField("cat_id", StringType(), True),
    StructField("name", StringType(), True),
    StructField("coat_color", StringType(), True),
    StructField("coat_length", StringType(), True),
    StructField("age", IntegerType(), True),
    StructField("archetype", StringType(), True),
    StructField("status", StringType(), True),
    StructField("admitted_date", TimestampType(), True),
    StructField("adopted_date", TimestampType(), True),
    StructField("last_checkup_time", TimestampType(), True)
])

visitors_schema = StructType([
    StructField("visitor_id", StringType(), True), # Primary Key is not nullable
    StructField("name", StringType(), True),
    StructField("archetype", StringType(), True),
    StructField("first_visit_date", TimestampType(), True)
])


def main():
    """
    A Spark job to perform a full snapshot of tables from a PostgreSQL database
    and write them as Iceberg tables using an explicit schema.
    """
    print("Starting Spark session for batch ingestion...")
    spark = (
        SparkSession.builder
        .appName("PostgresToIcebergSnapshot")
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .config("spark.sql.catalog.workshop", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.workshop.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog")
        .config("spark.sql.catalog.workshop.warehouse", S3_WAREHOUSE_PATH)
        .config("spark.sql.catalog.workshop.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")
        .config("spark.jars.packages", "org.postgresql:postgresql:42.6.0")
        .config("spark.sql.optimizer.excludedRules", "org.apache.spark.sql.catalyst.optimizer.SimplifyCasts")
        .getOrCreate()
    )
    print("Spark session created.")

    # --- Ingest the 'cats' table ---
    print("Reading 'cats' table from PostgreSQL...")
    try:
        cats_df = (
            spark.read
            .format("jdbc")
            .option("url", DB_URL)
            .option("dbtable", "cats")
            .option("user", DB_USER)
            .option("password", DB_PASSWORD)
            .option("driver", DB_DRIVER)
            .schema(cats_schema)
            .load()
        )
        
        print(f"Successfully read {cats_df.count()} rows from 'cats' table.")
        
        target_table_cats = f"workshop.{GLUE_DATABASE_NAME}.cats_profiles_raw"
        print(f"Writing to Iceberg table '{target_table_cats}'...")
        
        (
            cats_df.writeTo(target_table_cats)
            .createOrReplace()
        )
        
        print(f"Successfully created '{target_table_cats}' Iceberg table.")

    except Exception as e:
        print(f"An error occurred during 'cats' table ingestion: {e}")
        raise


    # --- Ingest the 'visitors' table ---
    print("\nReading 'visitors' table from PostgreSQL...")
    try:
        visitors_df = (
            spark.read
            .format("jdbc")
            .option("url", DB_URL)
            .option("dbtable", "visitors")
            .option("user", DB_USER)
            .option("password", DB_PASSWORD)
            .option("driver", DB_DRIVER)
            .schema(visitors_schema)
            .load()
        )

        print(f"Successfully read {visitors_df.count()} rows from 'visitors' table.")

        target_table_visitors = f"workshop.{GLUE_DATABASE_NAME}.visitors_profiles_raw"
        print(f"Writing to Iceberg table '{target_table_visitors}'...")
        
        (
            visitors_df.writeTo(target_table_visitors)
            .createOrReplace()
        )
        
        print(f"Successfully created '{target_table_visitors}' Iceberg table.")

    except Exception as e:
        print(f"An error occurred during 'visitors' table ingestion: {e}")
        raise

    print("\nBatch ingestion complete. Stopping Spark session.")
    spark.stop()


if __name__ == '__main__':
    main()
