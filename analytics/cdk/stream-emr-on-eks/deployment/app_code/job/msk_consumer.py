from pyspark.sql import SparkSession
from pyspark.sql.types import *
from pyspark.sql.functions import *
import pyspark
import sys

spark = SparkSession.builder \
  .appName("Spark Structured Streaming from Kafka") \
  .getOrCreate()

sdfRides = spark \
  .readStream \
  .format("kafka") \
  .option("kafka.bootstrap.servers", sys.argv[1]) \
  .option("subscribe", "taxirides") \
  .option("startingOffsets", "latest") \
  .option("auto.offset.reset", "latest") \
  .load() \
  .selectExpr("decode(CAST(value AS STRING),'utf-8') as value") 
    
taxiRidesSchema = StructType([ \
  StructField("rideId", LongType()), StructField("isStart", StringType()), \
  StructField("endTime", TimestampType()), StructField("startTime", TimestampType()), \
  StructField("startLon", FloatType()), StructField("startLat", FloatType()), \
  StructField("endLon", FloatType()), StructField("endLat", FloatType()), \
  StructField("passengerCnt", ShortType()), StructField("taxiId", LongType()), \
  StructField("driverId", LongType()),StructField("timestamp", TimestampType())])

def parse_data_from_kafka_message(sdf, schema):
  assert sdf.isStreaming == True, "DataFrame doesn't receive streaming data"
  col = split(sdf['value'], ',') 
  for idx, field in enumerate(schema): 
      sdf = sdf.withColumn(field.name, col.getItem(idx).cast(field.dataType)) 
      if field.name=="timestamp":
          sdf = sdf.withColumn(field.name, current_timestamp())
  return sdf.select([field.name for field in schema])

sdfRides = parse_data_from_kafka_message(sdfRides, taxiRidesSchema)
# sdfFares = parse_data_from_kafka_message(sdfFares, taxiFaresSchema)

query = sdfRides.withWatermark("timestamp", "10 seconds") \
                .groupBy("driverId", window("timestamp", "10 seconds", "5 seconds")).count()

# query.writeStream \
#     .outputMode("append") \
#     .format("console") \
#     .option("checkpointLocation", "s3://test/stream/checkpoint/consumer_taxi2") \
#     .option("truncate", False) \
#     .start() \
#     .awaitTermination()

output=query.select(to_json(struct("*")).alias("value")) \
  .selectExpr("CAST(value AS STRING)") \
  .writeStream \
  .outputMode("append") \
  .format("kafka") \
  .option("kafka.bootstrap.servers", sys.argv[1]) \
  .option("topic", sys.argv[3]) \
  .option("checkpointLocation", sys.argv[2]) \
  .start()

output.awaitTermination()
