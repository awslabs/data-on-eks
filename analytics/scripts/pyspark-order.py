import logging
import sys
from datetime import datetime

from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql import functions as f
from pyspark.sql.functions import year
from pyspark.sql.functions import col
from pyspark.sql.functions import month
from pyspark.sql.functions import dayofmonth

# Logging configuration
formatter = logging.Formatter('[%(asctime)s] %(levelname)s @ line %(lineno)d: %(message)s')
handler = logging.StreamHandler(sys.stdout)
handler.setLevel(logging.INFO)
handler.setFormatter(formatter)
logger = logging.getLogger()
logger.setLevel(logging.INFO)
logger.addHandler(handler)

dt_string = datetime.now().strftime("%Y_%m_%d_%H_%M_%S")
AppName = "OrderData"


def main(args):

    raw_input_folder = args[1]
    transform_output_folder = args[2]

    # Create Spark Session
    spark = SparkSession \
        .builder \
        .appName(AppName + "_" + str(dt_string)) \
        .getOrCreate()

    spark.sparkContext.setLogLevel("INFO")
    logger.info("Starting spark application")

    logger.info("Reading Parquet file from S3")
    order_df = spark.read.parquet(raw_input_folder)

    # Add additional columns to the DF
    #final_order_df = order_df.withColumn("current_date", f.lit(datetime.now()))

    # split order date into year month and date columns
    final_order_df = order_df.withColumn('year', year('order_date'))
    final_order_df = final_order_df.withColumn('month', month('order_date'))
    final_order_df = final_order_df.withColumn('day', dayofmonth('order_date'))

    # delete order date column
    final_order_df = final_order_df.drop('order_date')

    logger.info("Order data schema preview")
    final_order_df.printSchema()

    logger.info("Previewing order data sample")
    final_order_df.show(20, truncate=False)

    logger.info("Total number of records: " + str(final_order_df.count()))

    logger.info("Write order data to S3 transform table")
    final_order_df.repartition(2).write.mode("overwrite").parquet(transform_output_folder)

    logger.info("Ending spark application")
    # end spark code
    spark.stop()

    return None


if __name__ == "__main__":
    print(len(sys.argv))
    if len(sys.argv) != 3:
        print("Usage: spark-etl [input-folder] [output-folder]")
        sys.exit(0)

    main(sys.argv)
