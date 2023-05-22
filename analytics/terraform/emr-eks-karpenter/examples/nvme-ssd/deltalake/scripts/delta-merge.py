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

# Define schema for file
emp_schema = StructType(
      [ StructField("id",IntegerType(),True),
       StructField("firstname",StringType(),True),
       StructField("lastname",StringType(),True),
       StructField("ssn", StringType(), True),
       StructField("salary", IntegerType(), True)])

# Performing Merge
#Load initial created delta table.
deltaTableEmp = DeltaTable.forPath(spark, TABLE_LOCATION)
#Load updated file in dataframe
df_update_csv= spark.read.schema(emp_schema)\
 .format("csv").options(header=False,delimiter=",")\
 .load(f"{S3_BUCKET_NAME}/data/update_emp.csv")\
 .withColumn("checksum",md5(concat(col("firstname"),col("lastname"),col("ssn")))) \

# perform merge(update and insert) on delta table comparing  checksum column
deltaTableEmp.alias("emp") \
  .merge(
    df_update_csv.alias("emp_updated"),
    "emp.checksum = emp_updated.checksum"
  ) \
  .whenMatchedUpdate(set =
    {
      "id": "emp_updated.id",
      "firstName": "emp_updated.firstName",
      "lastName": "emp_updated.lastName",
      "ssn": "emp_updated.ssn",
      "salary": "emp_updated.salary",
      "checksum":"emp_updated.checksum"
    }
  ) \
  .whenNotMatchedInsert(values =
    {
      "id": "emp_updated.id",
      "firstName": "emp_updated.firstName",
      "lastName": "emp_updated.lastName",
      "ssn": "emp_updated.ssn",
      "salary": "emp_updated.salary",
      "checksum":"emp_updated.checksum"
    }
  ) \
  .execute()
