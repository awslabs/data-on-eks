import logging
import sys
from datetime import datetime

from pyspark.sql import SparkSession

# Logging configuration
formatter = logging.Formatter('[%(asctime)s] %(levelname)s @ line %(lineno)d: %(message)s')
handler = logging.StreamHandler(sys.stdout)
handler.setLevel(logging.INFO)
handler.setFormatter(formatter)
logger = logging.getLogger()
logger.setLevel(logging.INFO)
logger.addHandler(handler)

# Application-specific variables
dt_string = datetime.now().strftime("%Y_%m_%d_%H_%M_%S")
AppName = "EmployeeDataS3TableJob"


def main(args):
    """
    Main function to execute the S3 table job.
    """
    if len(args) != 3:
        logger.error("Usage: spark-etl [input-csv-path] [s3table-arn]")
        sys.exit(1)

    # Input parameters
    input_csv_path = args[1]  # Path to the input CSV file
    s3table_arn = args[2]  # s3table arn

    # Initialize Spark session
    logger.info("Initializing Spark Session")
    spark = (SparkSession
             .builder
             .appName(f"{AppName}_{dt_string}")
             .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
             .config("spark.sql.catalog.s3tablesbucket", "org.apache.iceberg.spark.SparkCatalog")
             .config("spark.sql.catalog.s3tablesbucket.catalog-impl", "software.amazon.s3tables.iceberg.S3TablesCatalog")
             .config("spark.sql.catalog.s3tablesbucket.warehouse", s3table_arn)
             .config('spark.hadoop.fs.s3.impl', "org.apache.hadoop.fs.s3a.S3AFileSystem")
             .config("spark.sql.defaultCatalog", "s3tablesbucket")
             .getOrCreate())

    spark.sparkContext.setLogLevel("INFO")
    logger.info("Spark session initialized successfully")

    namespace = "doeks_namespace"
    table_name = "employee_s3_table"
    full_table_name = f"s3tablesbucket.{namespace}.{table_name}"

    # Step 1: Create namespace if not exists
    logger.info(f"Creating namespace: {namespace}")
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS s3tablesbucket.{namespace}")

    # Step 2: Read input CSV data
    logger.info(f"Reading employee data from input CSV: {input_csv_path}")
    employee_df = spark.read.csv(input_csv_path, header=True, inferSchema=True)

    logger.info("Previewing employee data schema")
    employee_df.printSchema()

    logger.info("Previewing first 10 records from the input data")
    employee_df.show(10, truncate=False)

    logger.info("Source data count:")
    employee_df.count()

    # Step 3: Create or replace table and write data in one operation
    logger.info(f"Creating/Replacing and writing data to table: {full_table_name}")
    (employee_df.writeTo(full_table_name)
                .using("iceberg")
                .createOrReplace())

    # Step 4: Read data back from the Iceberg table
    logger.info(f"Reading data back from Iceberg table: {full_table_name}")
    iceberg_data_df = spark.read.format("iceberg").load(full_table_name)

    logger.info("Previewing first 10 records from the Iceberg table")
    iceberg_data_df.show(10, truncate=False)

    # Count records using both DataFrame API and SQL
    logger.info("Total records in Iceberg table (DataFrame API):")
    print(f"DataFrame count: {iceberg_data_df.count()}")

    # List the table snapshots
    logger.info("List the s3table snapshot versions:")
    spark.sql(f"SELECT * FROM {full_table_name}.history LIMIT 10").show()

    # Stop Spark session
    logger.info("Stopping Spark Session")
    spark.stop()


if __name__ == "__main__":
    logger.info("Starting the Spark job")
    main(sys.argv)
