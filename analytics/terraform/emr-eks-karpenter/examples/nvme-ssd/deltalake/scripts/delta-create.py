import sys
from pyspark.sql.session import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
from delta.tables import *

spark = SparkSession.builder\
.appName("EMRonEKS-DeltaTable")\
.enableHiveSupport()\
.getOrCreate()
S3_BUCKET_NAME=sys.argv[1]
TABLE_LOCATION=f"{S3_BUCKET_NAME}/delta/delta_emp"


# Define schema for source file
emp_schema = StructType(
      [ StructField("id",IntegerType(),True),
       StructField("firstname",StringType(),True),
       StructField("lastname",StringType(),True),
       StructField("ssn", StringType(), True),
       StructField("salary", IntegerType(), True)])


#Create Delta Table with initial file
df_intial_csv = spark.read.schema(emp_schema)\
 .format("csv")\
 .options(header=False,delimiter=",")\
 .load(f"{S3_BUCKET_NAME}/data/initial_emp.csv")\
 .withColumn("checksum",md5(concat(col("firstname"),col("lastname"),col("ssn")))) \
 .write.format("delta")\
 .mode("overwrite")\
 .save(TABLE_LOCATION)

# Generate and register the symlink file in the Glue Data Catalog
spark.sql(f"""CREATE TABLE IF NOT EXISTS delta_table_emp USING DELTA LOCATION '{TABLE_LOCATION}'""")
spark.sql("GENERATE symlink_format_manifest FOR TABLE delta_table_emp")
spark.sql("ALTER TABLE delta_table_emp SET TBLPROPERTIES(delta.compatibility.symlinkFormatManifest.enabled=true)")

# Create table in Athena to query
spark.sql(f"""
    CREATE EXTERNAL TABLE IF NOT EXISTS default.delta_emp (
     `id` int
    ,`firstName` string
    ,`lastName` string
    ,`ssn` string
    ,`salary` int
    ,`checksum` string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT 'org.apache.hadoop.hive.ql.io.SymlinkTextInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION '{TABLE_LOCATION}/_symlink_format_manifest/'""")
