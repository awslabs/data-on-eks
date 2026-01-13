import logging
from pyspark.sql import SparkSession
from pyspark import SparkConf
from pyspark.sql.functions import col, rand, expr
import time

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configure Spark with RAPIDS plugin to ensure GPU-only execution
logger.info("Configuring Spark session with RAPIDS (GPU-only mode)...")
conf = SparkConf() \
    .setAppName("Spark-RAPIDS-GPU-Only-Performance-Test") \
    .set("spark.plugins", "com.nvidia.spark.SQLPlugin") \
    .set("spark.rapids.sql.enabled", "true") \
    .set("spark.rapids.sql.concurrentGpuTasks", "2") \
    .set("spark.executor.resource.gpu.amount", "1") \
    .set("spark.task.resource.gpu.amount", "0.5") \
    .set("spark.executor.cores", "4") \
    .set("spark.executor.memory", "16g") \
    .set("spark.executor.memoryOverhead", "4g") \
    .set("spark.rapids.memory.pinnedPool.size", "2g") \
    .set("spark.dynamicAllocation.enabled", "false") \
    .set("spark.rapids.sql.explain", "ALL")  # Explain all stages of the query plan for debugging

# Initialize Spark session
spark = SparkSession.builder.config(conf=conf).getOrCreate()
logger.info("Spark session initialized successfully (GPU-only).")

# Generate large DataFrames for GPU-based processing
logger.info("Creating large DataFrames with multiple columns for join operation...")
df1 = spark.range(0, 100000000).toDF("id1")  # Increased data size
df1 = df1.withColumn("value1", rand()) \
    .withColumn("category1", expr("CASE WHEN rand() > 0.5 THEN 'A' ELSE 'B' END")) \
    .withColumn("amount1", expr("rand() * 1000")) \
    .withColumn("quantity1", expr("CAST(rand() * 100 AS INT)"))

df2 = spark.range(0, 100000000).toDF("id2")  # Increased data size
df2 = df2.withColumn("value2", rand()) \
    .withColumn("category2", expr("CASE WHEN rand() > 0.5 THEN 'X' ELSE 'Y' END")) \
    .withColumn("amount2", expr("rand() * 2000")) \
    .withColumn("quantity2", expr("CAST(rand() * 200 AS INT)"))

# Perform a join between the two large DataFrames (GPU-bound)
logger.info("Performing a GPU-accelerated join between two large DataFrames...")
joined_df = df1.join(df2, df1["id1"] == df2["id2"], "inner")

# Perform aggregation on the joined DataFrame
logger.info("Performing aggregation on the joined DataFrame using GPU...")
aggregated_df = joined_df.groupBy("category1", "category2").agg(
    expr("sum(amount1) as total_amount1"),
    expr("sum(amount2) as total_amount2"),
    expr("avg(quantity1) as avg_quantity1"),
    expr("avg(quantity2) as avg_quantity2")
)

# Additional iterative computation to increase execution time
logger.info("Performing additional computations to extend job duration...")
for i in range(10):
    logger.info(f"Iteration {i + 1} of additional transformations...")
    aggregated_df = aggregated_df.withColumn("total_amount_diff", col("total_amount1") - col("total_amount2"))
    aggregated_df = aggregated_df.withColumn("amount_ratio", col("total_amount1") / col("total_amount2"))

# Explain the GPU execution plan for debugging and validation
logger.info("Running SQL query with aggregation and filtering, explaining execution plan...")
aggregated_df.createOrReplaceTempView("aggregated")
spark.sql("""
    SELECT category1, category2, total_amount1, total_amount2
    FROM aggregated
    WHERE total_amount1 > 5000 AND total_amount2 > 10000
    ORDER BY total_amount1 DESC
""").explain()

# Execute the final query and display some results
logger.info("Executing the SQL query and displaying the results (GPU-only execution)...")
results = spark.sql("""
    SELECT category1, category2, total_amount1, total_amount2
    FROM aggregated
    WHERE total_amount1 > 5000 AND total_amount2 > 10000
    ORDER BY total_amount1 DESC
""")
results.show()

# Add a sleep step to ensure the job runs for at least 10 minutes
logger.info("Ensuring job runs for 5 minutes...")
time.sleep(300)  # Sleep for 5 mins

# Stop the Spark session
logger.info("Stopping the Spark session.")
spark.stop()
logger.info("Spark session stopped successfully.")