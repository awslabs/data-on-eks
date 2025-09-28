---
title: S3 Tables
sidebar_position: 8
---

# S3 Tables

This blueprint demonstrates Apache Iceberg integration with S3 Tables for transactional data lakes, ACID compliance, and optimized analytics queries.

## Overview

Amazon S3 Tables provide the first cloud-native tables optimized for analytics workloads in AWS. Built on Apache Iceberg, S3 Tables deliver up to 3x faster query performance and up to 10x higher transactions per second compared to traditional table formats.

## Key Features

- **ACID Transactions**: Full transactional support with serializable isolation
- **Schema Evolution**: Add, drop, and modify columns without breaking existing queries
- **Time Travel**: Query historical data with snapshot isolation
- **Partition Evolution**: Change partitioning without rewriting data
- **Optimized Performance**: Built-in compaction and optimization
- **DuckDB Integration**: High-performance analytics with DuckDB engine

## Prerequisites

Before deploying this blueprint, ensure you have:

- ✅ [Infrastructure deployed](/data-on-eks/docs/datastacks/spark-on-eks/infra)
- ✅ `kubectl` configured for your EKS cluster
- ✅ S3 Tables namespace created
- ✅ IAM roles with S3 Tables permissions

## Quick Deploy & Test

### 1. Create S3 Tables Namespace

```bash
# Create S3 Tables namespace
export NAMESPACE_NAME="spark-analytics"
export REGION="us-west-2"

aws s3tables create-namespace \
  --region $REGION \
  --name $NAMESPACE_NAME
```

### 2. Deploy Spark Application

```bash
# Navigate to data-stacks directory
cd data-stacks/spark-on-eks

# Deploy S3 Tables Spark job
kubectl apply -f examples/s3-tables/s3table-spark-operator.yaml
```

### 3. Generate Test Data

```bash
# Run data generation script
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: s3tables-data-gen
  namespace: spark-team-a
spec:
  template:
    spec:
      containers:
      - name: data-generator
        image: public.ecr.aws/spark/spark-py:3.5.0
        command: ["/bin/bash", "/opt/spark/scripts/input-data-gen.sh"]
        env:
        - name: S3_NAMESPACE
          value: "$NAMESPACE_NAME"
      restartPolicy: Never
EOF
```

### 4. Verify S3 Tables Creation

```bash
# List created tables
aws s3tables list-tables --namespace $NAMESPACE_NAME

# Check table metadata
kubectl logs -n spark-team-a -l spark-role=driver | grep -i "iceberg"

# Query table via DuckDB notebook
kubectl port-forward -n spark-team-a svc/jupyter-notebook 8888:8888
```

## Configuration Details

### S3 Tables Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: s3tables-config
  namespace: spark-team-a
data:
  namespace: "spark-analytics"
  table-name: "customer-transactions"
  warehouse-path: "s3://spark-s3tables-warehouse/"
  catalog-impl: "org.apache.iceberg.aws.s3.S3FileIO"
```

### Spark Application with Iceberg

```yaml
spec:
  sparkConf:
    "spark.sql.extensions": "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
    "spark.sql.catalog.s3tables": "org.apache.iceberg.spark.SparkCatalog"
    "spark.sql.catalog.s3tables.catalog-impl": "org.apache.iceberg.aws.s3.S3TablesCatalog"
    "spark.sql.catalog.s3tables.warehouse": "s3://spark-s3tables-warehouse/"
    "spark.sql.catalog.s3tables.s3.region": "us-west-2"
    "spark.sql.defaultCatalog": "s3tables"
    "spark.serializer": "org.apache.spark.serializer.KryoSerializer"
  deps:
    jars:
      - "s3a://spark-on-eks-data/jars/iceberg-spark-runtime-3.5_2.12-1.4.0.jar"
      - "s3a://spark-on-eks-data/jars/iceberg-aws-1.4.0.jar"
```

### DuckDB Integration

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: duckdb-notebook
  namespace: spark-team-a
spec:
  containers:
  - name: jupyter
    image: public.ecr.aws/data-on-eks/jupyter-duckdb:latest
    ports:
    - containerPort: 8888
    env:
    - name: S3_TABLES_NAMESPACE
      value: "spark-analytics"
    - name: AWS_REGION
      value: "us-west-2"
    volumeMounts:
    - name: notebooks
      mountPath: /home/jovyan/work
```

## Performance Validation

### ACID Transaction Testing

```python
# Create table with ACID properties
spark.sql("""
  CREATE TABLE s3tables.transactions (
    id BIGINT,
    customer_id STRING,
    amount DECIMAL(10,2),
    transaction_date DATE,
    created_at TIMESTAMP
  ) USING ICEBERG
  PARTITIONED BY (transaction_date)
  TBLPROPERTIES (
    'write.format.default' = 'parquet',
    'write.parquet.compression-codec' = 'zstd'
  )
""")

# Insert data with transactions
spark.sql("""
  INSERT INTO s3tables.transactions
  VALUES
    (1, 'cust_001', 100.50, '2024-01-01', current_timestamp()),
    (2, 'cust_002', 250.75, '2024-01-01', current_timestamp())
""")

# Update with ACID guarantees
spark.sql("""
  MERGE INTO s3tables.transactions t
  USING (VALUES (1, 'cust_001', 150.50)) AS s(id, customer_id, new_amount)
  ON t.id = s.id
  WHEN MATCHED THEN UPDATE SET amount = s.new_amount
""")
```

### Time Travel Queries

```python
# Query historical snapshots
spark.sql("""
  SELECT * FROM s3tables.transactions
  VERSION AS OF 1
""").show()

# Query as of timestamp
spark.sql("""
  SELECT * FROM s3tables.transactions
  TIMESTAMP AS OF '2024-01-01 10:00:00'
""").show()

# Show table history
spark.sql("SELECT * FROM s3tables.transactions.history").show()
```

### Schema Evolution

```python
# Add new column
spark.sql("""
  ALTER TABLE s3tables.transactions
  ADD COLUMN payment_method STRING
""")

# Rename column
spark.sql("""
  ALTER TABLE s3tables.transactions
  RENAME COLUMN customer_id TO client_id
""")

# Change column type
spark.sql("""
  ALTER TABLE s3tables.transactions
  ALTER COLUMN amount TYPE DECIMAL(12,2)
""")
```

## Expected Results

✅ **ACID Compliance**: Full transactional support with consistency guarantees
✅ **Query Performance**: 3x faster analytics compared to traditional formats
✅ **Schema Flexibility**: Non-breaking schema evolution
✅ **Time Travel**: Historical data access and recovery
✅ **DuckDB Integration**: High-performance analytical queries

## Troubleshooting

### Common Issues

**Table creation failures:**
```bash
# Check S3 Tables permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:role/spark-team-a \
  --action-names s3tables:CreateTable \
  --resource-arns arn:aws:s3tables:us-west-2:ACCOUNT:namespace/$NAMESPACE_NAME

# Verify namespace exists
aws s3tables list-namespaces --region us-west-2
```

**Iceberg catalog connection issues:**
```bash
# Check Spark driver logs
kubectl logs -n spark-team-a -l spark-role=driver | grep -i iceberg

# Verify jar dependencies
kubectl exec -n spark-team-a <driver-pod> -- ls -la /opt/spark/jars/ | grep iceberg

# Test S3 connectivity
kubectl exec -n spark-team-a <driver-pod> -- aws s3 ls s3://spark-s3tables-warehouse/
```

**DuckDB integration problems:**
```bash
# Check DuckDB extension loading
kubectl exec -n spark-team-a duckdb-notebook -- duckdb -c "LOAD iceberg;"

# Verify S3 Tables access from DuckDB
kubectl exec -n spark-team-a duckdb-notebook -- duckdb -c "
  SELECT * FROM iceberg_scan('s3://spark-s3tables-warehouse/transactions/metadata/*.json');
"
```

## Advanced Configuration

### Performance Optimization

```yaml
# Optimized Iceberg configuration
spec:
  sparkConf:
    "spark.sql.iceberg.vectorization.enabled": "true"
    "spark.sql.iceberg.planning.preserve-data-grouping": "true"
    "spark.sql.adaptive.enabled": "true"
    "spark.sql.adaptive.coalescePartitions.enabled": "true"
    "spark.sql.adaptive.skewJoin.enabled": "true"
    "spark.sql.iceberg.split-size": "268435456"
```

### Compaction Strategies

```python
# Configure automatic compaction
spark.sql("""
  ALTER TABLE s3tables.transactions
  SET TBLPROPERTIES (
    'write.target-file-size-bytes' = '134217728',
    'write.metadata.compression-codec' = 'gzip',
    'write.metadata.metrics.max-inferred-column-defaults' = '100'
  )
""")

# Manual compaction
spark.sql("""
  CALL s3tables.system.rewrite_data_files(
    table => 's3tables.transactions',
    options => map('target-file-size-bytes', '268435456')
  )
""")
```

### Multi-Table Transactions

```python
# Cross-table ACID transactions
spark.sql("BEGIN")

try:
    spark.sql("""
      INSERT INTO s3tables.transactions
      SELECT * FROM staging.new_transactions
    """)

    spark.sql("""
      UPDATE s3tables.customer_balances
      SET balance = balance - transaction_amount
      FROM s3tables.transactions t
      WHERE customer_balances.id = t.customer_id
    """)

    spark.sql("COMMIT")
except Exception as e:
    spark.sql("ROLLBACK")
    raise e
```

## Cost Optimization

### Storage Optimization

```python
# Configure storage classes
spark.sql("""
  ALTER TABLE s3tables.transactions
  SET TBLPROPERTIES (
    's3.storage-class' = 'INTELLIGENT_TIERING',
    'write.data.path' = 's3://spark-s3tables-warehouse/data/',
    'write.metadata.path' = 's3://spark-s3tables-warehouse/metadata/'
  )
""")
```

### Partition Pruning

```python
# Optimize partition strategy
spark.sql("""
  CREATE TABLE s3tables.transactions_optimized (
    id BIGINT,
    customer_id STRING,
    amount DECIMAL(10,2),
    transaction_date DATE,
    created_at TIMESTAMP
  ) USING ICEBERG
  PARTITIONED BY (
    bucket(16, customer_id),
    days(transaction_date)
  )
""")
```

## Related Blueprints

- [Mountpoint S3 Express](/data-on-eks/docs/datastacks/spark-on-eks/mountpoint-s3express) - Ultra-fast storage for S3 Tables
- [Spark Operator Benchmarks](/data-on-eks/docs/datastacks/spark-on-eks/spark-operator-benchmarks) - Performance testing with Iceberg
- [S3 Tables Images](/data-on-eks/docs/datastacks/spark-on-eks/s3tables-images) - Custom Docker images

## Additional Resources

- [Amazon S3 Tables Documentation](https://docs.aws.amazon.com/s3/latest/userguide/s3-tables.html)
- [Apache Iceberg Documentation](https://iceberg.apache.org/docs/latest/)
- [DuckDB Iceberg Extension](https://duckdb.org/docs/extensions/iceberg.html)