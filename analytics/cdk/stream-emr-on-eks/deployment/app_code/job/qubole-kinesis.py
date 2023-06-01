from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col
from pyspark.sql.types import StructField, StructType, StringType, IntegerType
import boto3,json,sys

# creating a Kinesis stream
stream_name='pyspark-kinesis'
client_region = sys.argv[1]
client = boto3.client('kinesis', client_region)

try:
    print("create a new stream")
    client.create_stream(
            StreamName=stream_name,
            ShardCount=1)
except:
    print("the stream exists")

# sending a couple of messages to kinesis
messages = [
    {'message_type': 'message1', 'count': 2},
    {'message_type': 'message2', 'count': 1},
    {'message_type': 'message1', 'count': 2},
    {'message_type': 'message3', 'count': 3},
    {'message_type': 'message1', 'count': 5}
]
for message in messages:
    client.put_record(
        StreamName=stream_name,
        Data=json.dumps(message),
        PartitionKey='part_key')

spark = SparkSession.builder \
    .appName('PySparkKinesis') \
    .getOrCreate()

# spark.sparkContext.setLogLevel("DEBUG")
kinesis = spark \
    .readStream \
    .format('kinesis') \
    .option('streamName', stream_name) \
    .option('endpointUrl', 'https://kinesis.'+client_region+'.amazonaws.com')\
    .option('region', client_region) \
    .option('startingposition', 'TRIM_HORIZON')\
    .option('awsUseInstanceProfile', 'false') \
    .load()


schema = StructType([
            StructField("message_type", StringType()),
            StructField("count", IntegerType())])

     
kinesis.selectExpr('CAST(data AS STRING)')\
    .select(from_json('data', schema).alias('data'))\
    .select('data.*')\
    .writeStream \
    .outputMode('append')\
    .format('console') \
    .trigger(once=True) \
    .start() \
    .awaitTermination()

# write to s3
# kinesis.selectExpr('CAST(data AS STRING)')\
#     .select(from_json('data',data_schema).alias('data'))\
#     .select('data.*')\
#     .writeStream \
#     .outputMode('append')\
#     .format('parquet') \
#     .option('truncate', True) \
#     .option('checkpointLocation', sys.argv[2]) \
#     .option('path',sys.argv[3]) \
#     .trigger(processingTime='5 seconds') \
#     .start() \
#     .awaitTermination()

# delete the kinesis stream
# client.delete_stream(StreamName=stream_name)
