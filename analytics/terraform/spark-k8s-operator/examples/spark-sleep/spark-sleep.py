import logging
import sys
import time
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

dt_string = datetime.now().strftime("%Y_%m_%d_%H_%M_%S")
AppName = "sparkSleep"


def main(args):

    try: 
        parallel_range = args[2]
    except IndexError: 
        logger.info("parallel_range not provided, defaulting to 25")
        parallel_range = 25

    sleep_time = int(args[1])
    parallel_range = int(parallel_range)

    # Create Spark Session
    spark = SparkSession \
        .builder \
        .appName(AppName + "_" + str(dt_string)) \
        .getOrCreate()

    spark.sparkContext.setLogLevel("INFO")
    logger.info("Starting spark application")

    spark.sparkContext.parallelize(range(parallel_range), parallel_range).map(lambda x: time.sleep(sleep_time)).collect()
    
    logger.info("Stopping spark application")

    # end spark code
    spark.stop()

    return None


if __name__ == "__main__":
    print(len(sys.argv))
    if len(sys.argv) < 2:
        print("This script expects at least one parameter: sleep_time - the time each executor process should sleep")
        print("    you can optionally provide: parallel_range - number of processes to create, default: 25")
        sys.exit(0)

    main(sys.argv)
