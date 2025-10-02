import os
from pyspark.sql import SparkSession

# --- Configuration ---
# These should be configured to match your environment
DB_URL = os.getenv('DB_URL', 'jdbc:postgresql://host.docker.internal:5432/workshop')
DB_USER = os.getenv('DB_USER', 'workshop')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'workshop')
S3_WAREHOUSE_PATH = os.getenv('S3_WAREHOUSE_PATH', 's3a://your-bucket/iceberg-warehouse/')
DB_DRIVER = "org.postgresql.Driver"

def main():
    """
    A Spark job to perform a full snapshot of tables from a PostgreSQL database
    and write them as Iceberg tables in the data lake.
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
        # Add the JDBC driver to the Spark session
        .config("spark.jars.packages", "org.postgresql:postgresql:42.6.0")
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
            .load()
        )
        
        print(f"Successfully read {cats_df.count()} rows from 'cats' table.")
        
        # Write the DataFrame to a new Iceberg table called 'cats_profiles_raw'
        print("Writing to Iceberg table 'workshop.cats_profiles_raw'...")
        (
            cats_df.writeTo("workshop.cats_profiles_raw")
            .createOrReplace()
        )
        print("Successfully created 'cats_profiles_raw' Iceberg table.")

    except Exception as e:
        print(f"An error occurred during 'cats' table ingestion: {e}")


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
            .load()
        )

        print(f"Successfully read {visitors_df.count()} rows from 'visitors' table.")

        # Write the DataFrame to a new Iceberg table called 'visitors_profiles_raw'
        print("Writing to Iceberg table 'workshop.visitors_profiles_raw'...")
        (
            visitors_df.writeTo("workshop.visitors_profiles_raw")
            .createOrReplace()
        )
        print("Successfully created 'visitors_profiles_raw' Iceberg table.")

    except Exception as e:
        print(f"An error occurred during 'visitors' table ingestion: {e}")

    print("\nBatch ingestion complete. Stopping Spark session.")
    spark.stop()


if __name__ == '__main__':
    main()
